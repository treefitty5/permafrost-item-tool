# WorldReset.ps1 - puts used-up world objects back in a save: felled trees, mined boulders/ores, picked-up world items, looted containers.
# Needs SaveCore.ps1 and WorldCore.ps1 loaded first. The game must be closed when a reset is installed.
#
# What the data showed (8 backups of the same world compared, 2026-10-18):
#   * Every actor of a visited map cell has a record in the save's world block. Destroyed / picked-up actors simply have no record any more
#     (e.g. 110 boulders of the 10/14 backup have none today, though their cell is still saved).
#   * Felled trees stay as a record with Scavengeable_CurrentHealth 0.0; partly mined boulders keep their reduced health forever.
#   * A container's loot is rolled when its cell is first saved and stored in the record (Inventory); opening it sets bEverOpened true,
#     state EIS_Reuse/EIS_Deactivated and writes a second copy of the state into the plain-text part (runtime data / object save).
# So a reset is: tree -> remove its record + plain copy; partly mined ore -> full health; destroyed ore / picked-up item -> put the record
# back from the newest backup that still has it; opened container -> back to unopened with its ORIGINAL loot (from a backup) or, when no
# backup saw it unopened, the loot of another unopened container of the same type (a real game roll), plain copy removed.

$script:ResetInv = [Globalization.CultureInfo]::InvariantCulture

function Get-NodeTable {
  $t = @{}; $p = Join-Path $PSScriptRoot 'catalog\resource-nodes.csv'
  if (Test-Path $p) { foreach ($r in (Import-Csv $p)) { $t[$r.Class] = [double]::Parse($r.MaxHealth, $script:ResetInv) } }
  return $t
}

function Get-ResetKind([string]$cls, [string]$path) {
  if ($cls -match '^BP_ScavengableTree_') { return 'tree' }
  if ($cls -match '^BP_D_.*Boulder') { return 'ore' }
  if ($cls -match '^BP_D_') { return 'breakable' }
  if ($cls -match '_WI_C$') { return 'item' }
  # rock shards and scavengable bushes are plain pick-up records: a destroyed one has no record, so it is restored like a world item
  if ($cls -match '^BP_(RockShard|BushScavengable)') { return 'item' }
  if (($cls -match '^BP_S_' -and $path -match '/Interactions/Containers/') -or ($cls -match '^BP_SolarPanel' -and $path -match '/Scavengable/')) { return 'container' }
  return ''
}

# real loot rolls of unopened containers per loot group (catalog\loot-pool.json, made by Build-Pristine.ps1): the LAST resort for a container whose loot group has no
# unopened example left in the world and no backup. Keys are the same pool keys the plan uses.
function Get-ShippedLootPool {
  $p = Join-Path $PSScriptRoot 'catalog\loot-pool.json'; $h = @{}
  if (-not (Test-Path $p)) { return $h }
  try { $o = Get-Content $p -Raw | ConvertFrom-Json; foreach ($pr in $o.PSObject.Properties) { $h[$pr.Name] = @($pr.Value) } } catch { }
  return $h
}

function Get-ProtectedIds {
  # items a container must never be re-rolled for: quest items and keys
  $ids = @{}; $p = Join-Path $PSScriptRoot 'items.json'
  if (Test-Path $p) { foreach ($i in (Get-Content $p -Raw | ConvertFrom-Json)) { if ($i.category -eq 'QuestItems' -or $i.id -match 'Key') { $ids[[string]$i.id] = 1 } } }
  return $ids
}
function Test-InvProtected([string]$inv, $prot) {
  if (-not $inv) { return $false }
  foreach ($m in [regex]::Matches($inv, '@\d+=([^&@]+)')) { if ($prot.ContainsKey($m.Groups[1].Value)) { return $true } }
  return $false
}

function Get-PlayerPos([string]$s) {
  $m = [regex]::Match($s, 'PawnLocation>(-?[\d\.]+),(-?[\d\.]+),(-?[\d\.]+)'); if (-not $m.Success) { return $null }
  return @([double]::Parse($m.Groups[1].Value, $script:ResetInv), [double]::Parse($m.Groups[2].Value, $script:ResetInv), [double]::Parse($m.Groups[3].Value, $script:ResetInv))
}
function Test-NearPos($pos, $center, [double]$radius) {
  if ($radius -le 0) { return $true }; if ($null -eq $pos -or $null -eq $center) { return $false }
  $dx = $pos[0] - $center[0]; $dy = $pos[1] - $center[1]; $dz = $pos[2] - $center[2]
  return (($dx * $dx + $dy * $dy + $dz * $dz) -le ($radius * $radius))
}
function Get-RecHealth($r) { $h = $r.Get('Scavengeable_CurrentHealth'); if ($null -eq $h -or $h -eq '') { return $null }; $v = 0.0; if ([double]::TryParse($h, [Globalization.NumberStyles]::Float, $script:ResetInv, [ref]$v)) { return $v }; return $null }
function Format-Health([double]$v) { $t = $v.ToString('0.0###', $script:ResetInv); return $t }

# "Please wait" status line: the UI (Invoke-Busy in Theme.ps1) shows what the slow steps are doing; without a window this does nothing
function Report-Progress([string]$text) { if ($script:BusyStatus) { & $script:BusyStatus $text } }
# the level name sits in the save header; reading it with a plain text search is much faster than a regex over the whole file
function Get-LevelName([string]$t) {
  $i = $t.IndexOf('LevelName>', [StringComparison]::Ordinal); if ($i -lt 0) { return '' }
  $i += 10; $e = $t.IndexOf('?', $i, [StringComparison]::Ordinal); if ($e -lt 0) { $e = $t.Length }
  return $t.Substring($i, $e - $i)
}

# plain-text copies of an actor: "[BEGIN_OBJECT_SAVE?Guid>HEX?...?END_OBJECT_SAVE?" and "[BEGIN_RUNTIME_DATA_SAVE?RuntimeDataPayload###>HEX?...?[END_RUNTIME_DATA_SAVE?"
function Get-CopyGuids([string]$s) {
  $set = @{}
  # plain text searches (the regex version took 0.45 s per save); a guid is 32 upper-case hex digits followed by '?'
  foreach ($pair in @(@('[BEGIN_OBJECT_SAVE?Guid>', 'object'), @('[BEGIN_RUNTIME_DATA_SAVE?RuntimeDataPayload###>', 'runtime'))) {
    $tag = $pair[0]; $i = $s.IndexOf($tag, [StringComparison]::Ordinal)
    while ($i -ge 0) {
      $g = $i + $tag.Length
      if ($g + 33 -le $s.Length -and $s[$g + 32] -eq '?') { $h = $s.Substring($g, 32); if ($h -cmatch '^[0-9A-F]{32}$') { $set[$h] = $pair[1] } }
      $i = $s.IndexOf($tag, $g, [StringComparison]::Ordinal) } }
  return $set
}
# The save keeps ONE list of "[rGUID>HEX?" entries (HEX = the actor's text-form guid, 3756 entries in a 100 h world, one more for every thing
# you destroy / collect). The game treats a listed actor as used up and drops its world record again on load, so a restored actor has to
# be taken off this list too (checked 2026-10-19: all 40 ores restored by a reset and then lost were on the list).
function Remove-RGuids([string]$s, $guids) {
  $set = New-Object 'System.Collections.Generic.HashSet[string]'; foreach ($g in $guids) { [void]$set.Add([string]$g) }
  if ($set.Count -eq 0) { return $s }
  $ev = [Text.RegularExpressions.MatchEvaluator] { param($m) if ($set.Contains($m.Groups[1].Value)) { '' } else { $m.Value } }
  return [regex]::Replace($s, '\[rGUID>([0-9A-F]{32})\?', $ev)
}
# Harvested bushes and other generated plants / rocks are NOT world records: each one is an 80-byte entry (translation 3 doubles, rotation quat 4,
# scale 3) in a base64 list "PCGReActor_ExcludedInteractionTransforms>" stored on a PCG actor in the plain-text part (12 lists in World#2).
# Harvesting one bush added exactly one entry at its position; removing that entry brought the bush back in the game (verified 2026-10-19).
$script:ExclRx = '(PrimaryObjectName>([^?]*)\?PCGReActor_ExcludedInteractionTransforms>)([^?]*)(\?)'
function Get-ExclusionLists([string]$s) {
  $res = New-Object System.Collections.Generic.List[object]
  foreach ($m in [regex]::Matches($s, $script:ExclRx)) {
    try { $raw = [Convert]::FromBase64String($m.Groups[3].Value) } catch { continue }
    if ($raw.Length -eq 0 -or ($raw.Length % 80) -ne 0) { continue }
    $res.Add([pscustomobject]@{ Name = $m.Groups[2].Value; Raw = $raw; Count = [int]($raw.Length / 80) }) }
  return $res
}
function Get-ExclEntryPos($list, [int]$k) { return @([BitConverter]::ToDouble($list.Raw, $k * 80), [BitConverter]::ToDouble($list.Raw, $k * 80 + 8), [BitConverter]::ToDouble($list.Raw, $k * 80 + 16)) }
# $drop: hashtable list name -> HashSet[int] of entry indexes to remove
function Remove-ExclusionEntries([string]$s, $drop) {
  if ($drop.Count -eq 0) { return $s }
  $ev = [Text.RegularExpressions.MatchEvaluator] {
    param($m)
    $name = $m.Groups[2].Value
    if (-not $drop.ContainsKey($name)) { return $m.Value }
    $raw = [Convert]::FromBase64String($m.Groups[3].Value); $n = [int]($raw.Length / 80); $keep = New-Object System.Collections.Generic.List[byte]
    for ($k = 0; $k -lt $n; $k++) { if (-not $drop[$name].Contains($k)) { $keep.AddRange([byte[]]$raw[($k * 80)..($k * 80 + 79)]) } }
    return $m.Groups[1].Value + [Convert]::ToBase64String($keep.ToArray()) + $m.Groups[4].Value }
  return [regex]::Replace($s, $script:ExclRx, $ev)
}
function Remove-Copies([string]$s, $guids) {
  $set = New-Object 'System.Collections.Generic.HashSet[string]'; foreach ($g in $guids) { [void]$set.Add([string]$g) }
  if ($set.Count -eq 0) { return $s }
  $ev = [Text.RegularExpressions.MatchEvaluator] { param($m) if ($set.Contains($m.Groups[1].Value)) { '' } else { $m.Value } }
  $s = [regex]::Replace($s, '\[BEGIN_OBJECT_SAVE\?Guid>([0-9A-F]{32})\?.*?\?END_OBJECT_SAVE\?', $ev, 'Singleline')
  $s = [regex]::Replace($s, '\[BEGIN_RUNTIME_DATA_SAVE\?RuntimeDataPayload###>([0-9A-F]{32})\?.*?\?\[END_RUNTIME_DATA_SAVE\??', $ev, 'Singleline')
  # the very last runtime record has no trailing '?'; if it was removed, the record before it must not leave one behind
  if ($s.EndsWith('[END_RUNTIME_DATA_SAVE?')) { $s = $s.Substring(0, $s.Length - 1) }
  return $s
}

function Get-WorldHistory([string]$savePath) {
  $leaf = [IO.Path]::GetFileName($savePath); $list = New-Object System.Collections.Generic.List[object]
  $dir = Get-BackupDir; Report-Progress 'Reading the shipped map of untouched objects...'
  # 0) the shipped map of untouched objects (catalog\pristine-world.bin, made by Build-Pristine.ps1 from a flight over the whole map): the OLDEST source, so any backup
  #    or other world wins over it. Only objects whose id is on this save's used-up list are ever restored from it (see Build-ResetPlan).
  try {
    $pb = Join-Path $PSScriptRoot 'catalog\pristine-world.bin'; $pj = Join-Path $PSScriptRoot 'catalog\pristine-world.json'
    if ((Test-Path $pb) -and (Test-Path $pj)) {
      $pm = Get-Content $pj -Raw | ConvertFrom-Json
      $myT = $script:L1.GetString([IO.File]::ReadAllBytes($savePath))
      if ((Get-LevelName $myT) -eq $pm.Level) {
        $ms = New-Object IO.MemoryStream (, [IO.File]::ReadAllBytes($pb)); $gz = New-Object IO.Compression.GZipStream($ms, [IO.Compression.CompressionMode]::Decompress)
        $out = New-Object IO.MemoryStream; $gz.CopyTo($out); $gz.Close()
        $list.Add([pscustomobject]@{ Name = 'shipped map of untouched objects'; Cells = [WorldBlob]::Parse($out.ToArray()); Copies = @{}; Other = $true; Pristine = $true }) } }
  } catch { }
  # 1) other worlds on the same map (their saves and the tool's backups of them): the same object has the same id in every world, so what one
  #    world still has untouched can be put back into another. They come FIRST (oldest), so this world's own backups win; containers ignore them
  #    (loot is rolled per world).
  $others = @(); $myLevel = ''
  try {
    $myText = $script:L1.GetString([IO.File]::ReadAllBytes($savePath)); $myLevel = Get-LevelName $myText
    $folder = Split-Path $savePath -Parent; $others = @()
    foreach ($o in (Get-ChildItem -LiteralPath $folder -Filter '*.pfs' -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne $leaf })) {
      $others += $o; foreach ($b in (Get-ChildItem $dir -Filter "*_$($o.Name)" -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '_NEW_' } | Sort-Object Name)) { $others += $b } }
  } catch { }
  $own = @(Get-ChildItem $dir -Filter "*_$leaf" | Where-Object { $_.Name -notmatch '_NEW_' } | Sort-Object Name)
  $total = @($others).Count + $own.Count; $done = 0
  try {
    foreach ($f in $others) {
      $done++; Report-Progress "Reading earlier copies of your worlds: $done of $total"
      try { $t = $script:L1.GetString([IO.File]::ReadAllBytes($f.FullName)); if ((Get-LevelName $t) -ne $myLevel) { continue }
        $w = Read-WorldCells $t; $list.Add([pscustomobject]@{ Name = $f.Name; Cells = $w.Cells; Copies = (Get-CopyGuids $t); Other = $true }) } catch { } }
  } catch { }
  # 2) this world's own backups
  foreach ($f in $own) {
    $done++; Report-Progress "Reading earlier copies of your worlds: $done of $total"
    try { $t = $script:L1.GetString([IO.File]::ReadAllBytes($f.FullName)); $w = Read-WorldCells $t
      $list.Add([pscustomobject]@{ Name = $f.Name; Cells = $w.Cells; Copies = (Get-CopyGuids $t); Other = $false }) } catch { }
  }
  return $list
}

function Get-RecKey($r) { return $r.ClsPath + '|' + $r.Transform }

# ---------- planning ----------
# opt: Trees, Ores, Breakables, Items, Containers (bool), RadiusM (0 = whole world), KeepFilled (containers that still hold items stay as they are), Seed
function Build-ResetPlan([string]$savePath, $opt) {
  Report-Progress 'Reading your world...'
  $s = $script:L1.GetString([IO.File]::ReadAllBytes($savePath)); $w = Read-WorldCells $s; $cells = $w.Cells
  $nodes = Get-NodeTable; $prot = Get-ProtectedIds; $center = Get-PlayerPos $s; $radius = [double]$opt.RadiusM * 100
  $hist = Get-WorldHistory $savePath
  Report-Progress 'Comparing with the earlier copies...'
  # classes whose own file has no MaxHealth inherit the engine default: use the health every untouched (EIS_Active) actor of that class has in the saves
  $seen = @{}
  $setNo = 0
  foreach ($set in (@(, $cells) + @($hist | ForEach-Object { , $_.Cells }))) { $setNo++; Report-Progress "Comparing with the earlier copies: $setNo of $($hist.Count + 1)"; foreach ($c in $set) { foreach ($r in $c.Recs) {
    if ($r.Cls -notmatch '^BP_D_' -or $nodes.ContainsKey($r.Cls) -or $r.State -ne 'EIS_Active') { continue }
    $h = $r.Get('Scavengeable_CurrentHealth'); if (-not $h) { continue }
    if (-not $seen.ContainsKey($r.Cls)) { $seen[$r.Cls] = @{} }; $seen[$r.Cls][$h] = 1 + [int]$seen[$r.Cls][$h] } } }
  foreach ($k in $seen.Keys) { if ($seen[$k].Count -eq 1) { $nodes[$k] = [double]::Parse(@($seen[$k].Keys)[0], $script:ResetInv) } }
  $plan = [ordered]@{ Items = (New-Object System.Collections.Generic.List[object]); Plants = (New-Object System.Collections.Generic.List[object]); Skipped = [ordered]@{}; History = @($hist | Where-Object { -not $_.Other }).Count; HistoryOther = @($hist | Where-Object { $_.Other -and -not $_.Pristine }).Count; Pristine = [bool](@($hist | Where-Object { $_.Pristine }).Count); Radius = $opt.RadiusM }
  function Skip($why) { if ($plan.Skipped.Contains($why)) { $plan.Skipped[$why]++ } else { $plan.Skipped[$why] = 1 } }

  $cellByName = @{}; $byGuid = @{}; $byKey = @{}; $itemsByCls = @{}
  foreach ($c in $cells) { $cellByName[$c.Name] = $c
    foreach ($r in $c.Recs) { $byGuid[$r.GuidHex] = $r; $byKey[(Get-RecKey $r)] = $r
      if ($r.Cls -match '_WI_C$') { if (-not $itemsByCls.ContainsKey($r.Cls)) { $itemsByCls[$r.Cls] = New-Object System.Collections.Generic.List[object] }; $itemsByCls[$r.Cls].Add($r) } } }
  $queued = @{}

  # 1) trees and partly used ores
  foreach ($c in $cells) { foreach ($r in $c.Recs) {
    $kind = Get-ResetKind $r.Cls $r.ClsPath; if (-not $kind) { continue }
    if ($kind -eq 'tree' -and $opt.Trees) {
      $h = Get-RecHealth $r; if ($null -ne $h -and $h -le 0) { if (Test-NearPos $r.Pos $center $radius) { $plan.Items.Add([pscustomobject]@{ Kind = 'tree'; Action = 'Remove'; Cls = $r.Cls; Cell = $c.Name; Rec = $r; Pos = $r.Pos; Note = 'felled tree' }) } else { Skip 'outside the chosen radius' } }
    }
    elseif (($kind -eq 'ore' -and $opt.Ores) -or ($kind -eq 'breakable' -and $opt.Breakables)) {
      if (-not $nodes.ContainsKey($r.Cls)) { Skip "unknown max health: $($r.Cls)"; continue }
      $h = Get-RecHealth $r; $max = $nodes[$r.Cls]
      if ($null -ne $h -and ($h -lt $max -or $r.State -ne 'EIS_Active')) { if (Test-NearPos $r.Pos $center $radius) { $plan.Items.Add([pscustomobject]@{ Kind = $kind; Action = 'Heal'; Cls = $r.Cls; Cell = $c.Name; Rec = $r; Pos = $r.Pos; Note = "health $h -> $max" }) } else { Skip 'outside the chosen radius' } }
    }
  } }

  # 1b) records that exist but are also on the save's used-up list (left behind by an earlier reset): the game drops them on load, so take them off the list
  if ($opt.Ores -or $opt.Breakables -or $opt.Items) {
    $rl = New-Object 'System.Collections.Generic.HashSet[string]'; foreach ($m in [regex]::Matches($s, '\[rGUID>([0-9A-F]{32})\?')) { [void]$rl.Add($m.Groups[1].Value) }
    $planned = @{}; foreach ($it in $plan.Items) { $planned[$it.Rec.GuidHex] = 1 }
    foreach ($c in $cells) { foreach ($r in $c.Recs) {
      $kind = Get-ResetKind $r.Cls $r.ClsPath; if (-not $kind) { continue }
      if (-not (($kind -eq 'ore' -and $opt.Ores) -or ($kind -eq 'breakable' -and $opt.Breakables) -or ($kind -eq 'item' -and $opt.Items))) { continue }
      if ($planned.ContainsKey($r.GuidHex) -or -not $rl.Contains($r.TextGuid)) { continue }
      if (-not (Test-NearPos $r.Pos $center $radius)) { Skip 'outside the chosen radius'; continue }
      $plan.Items.Add([pscustomobject]@{ Kind = $kind; Action = 'Unlist'; Cls = $r.Cls; Cell = $c.Name; Rec = $r; Pos = $r.Pos; Note = 'record exists but was on the used-up list' }) } }
  }

  # 1c) harvested bushes and other generated plants / rocks: entries of the PCG exclusion lists (position known, so the radius works)
  if ($opt.Plants) {
    foreach ($L in (Get-ExclusionLists $s)) { for ($k = 0; $k -lt $L.Count; $k++) { $p = Get-ExclEntryPos $L $k
      if (Test-NearPos $p $center $radius) { $plan.Plants.Add([pscustomobject]@{ List = $L.Name; Index = $k; Pos = $p }) } else { Skip 'outside the chosen radius' } } }
  }

  # 2) destroyed ores / breakables and picked-up items: newest backup that still has the record
  $wantRestore = $opt.Ores -or $opt.Breakables -or $opt.Items
  $usedUp = New-Object 'System.Collections.Generic.HashSet[string]'; foreach ($m in [regex]::Matches($s, '\[rGUID>([0-9A-F]{32})\?')) { [void]$usedUp.Add($m.Groups[1].Value) }
  if ($wantRestore) {
    for ($hi = $hist.Count - 1; $hi -ge 0; $hi--) { $hs = $hist[$hi]; Report-Progress "Looking for destroyed objects: copy $($hist.Count - $hi) of $($hist.Count)"
      foreach ($hc in $hs.Cells) { if (-not $cellByName.ContainsKey($hc.Name)) { continue }
        foreach ($r in $hc.Recs) {
          $kind = Get-ResetKind $r.Cls $r.ClsPath
          if (-not (($kind -eq 'ore' -and $opt.Ores) -or ($kind -eq 'breakable' -and $opt.Breakables) -or ($kind -eq 'item' -and $opt.Items))) { continue }
          # ores and breakables are placed at fixed spots, so a missing record in a cell this save has means destroyed; items spawn at random per world, so the shipped map is only trusted for item ids this save lists as used up
          if ($hs.Pristine -and $kind -eq 'item' -and -not $usedUp.Contains($r.TextGuid)) { continue }
          $key = Get-RecKey $r; if ($byGuid.ContainsKey($r.GuidHex) -or $byKey.ContainsKey($key) -or $queued.ContainsKey($r.GuidHex) -or $queued.ContainsKey($key)) { continue }
          if ($hs.Copies.ContainsKey($r.TextGuid)) { Skip 'dropped/dynamic object (has a plain-text copy)'; continue }
          if ($kind -ne 'item' -and -not $nodes.ContainsKey($r.Cls)) { Skip "unknown max health: $($r.Cls)"; continue }
          if (-not (Test-NearPos $r.Pos $center $radius)) { Skip 'outside the chosen radius'; continue }
          if ($kind -eq 'item' -and -not $hs.Pristine -and $itemsByCls.ContainsKey($r.Cls)) { $near = $false; foreach ($o in $itemsByCls[$r.Cls]) { if (Test-NearPos $o.Pos $r.Pos 100) { $near = $true; break } }; if ($near) { Skip 'same item already lying within 1 m (it only moved)'; continue } }
          $queued[$r.GuidHex] = 1; $queued[$key] = 1
          $plan.Items.Add([pscustomobject]@{ Kind = $kind; Action = 'Restore'; Cls = $r.Cls; Cell = $hc.Name; Rec = $r; Pos = $r.Pos; Note = $(if ($hs.Pristine) { "from the shipped map of untouched objects" } else { "from backup $($hs.Name)" }) })
        } } }
  }

  # 3) containers
  if ($opt.Containers) {
    Report-Progress 'Working out the container loot...'
    # original loot per container (oldest backup that saw it unopened) and pools of real rolls per container type
    $orig = @{}; $pool = @{}; $cfgOf = @{}
    # containers that use the same loot table (catalog\loot-links.csv) share one pool of real rolls
    $lp = Join-Path $PSScriptRoot 'catalog\loot-links.csv'; if (Test-Path $lp) { foreach ($l in (Import-Csv $lp)) { if ($l.FromFolder -eq 'Container') { $cfgOf[$l.From + '_C'] = $l.To } } }
    $poolKey = { param($cls) if ($cfgOf.ContainsKey($cls)) { 'cfg:' + $cfgOf[$cls] } else { $cls } }
    $addPool = {
      param($r)
      $inv = $r.Get('Inventory'); if (-not $inv -or $r.Get('bEverOpened') -ne 'false' -or (Test-InvProtected $inv $prot)) { return }
      $pk = & $poolKey $r.Cls
      if (-not $pool.ContainsKey($pk)) { $pool[$pk] = New-Object System.Collections.Generic.List[string] }
      if (-not $pool[$pk].Contains($inv)) { $pool[$pk].Add($inv) } }
    foreach ($hs in $hist) { if ($hs.Other) { continue }; foreach ($hc in $hs.Cells) { foreach ($r in $hc.Recs) {
      if ((Get-ResetKind $r.Cls $r.ClsPath) -ne 'container') { continue }
      $inv = $r.Get('Inventory'); if ($inv -and $r.Get('bEverOpened') -eq 'false') { if (-not $orig.ContainsKey($r.GuidHex)) { $orig[$r.GuidHex] = $inv }; $k = Get-RecKey $r; if (-not $orig.ContainsKey($k)) { $orig[$k] = $inv }; & $addPool $r } } } }
    foreach ($c in $cells) { foreach ($r in $c.Recs) { if ((Get-ResetKind $r.Cls $r.ClsPath) -eq 'container') { & $addPool $r } } }
    $shipPool = Get-ShippedLootPool
    $rng = New-Object System.Random ([int]$opt.Seed); $usedPool = @{}
    foreach ($c in $cells) { foreach ($r in $c.Recs) {
      if ((Get-ResetKind $r.Cls $r.ClsPath) -ne 'container') { continue }
      if ($r.Get('bEverOpened') -ne 'true') { continue }
      if (-not (Test-NearPos $r.Pos $center $radius)) { Skip 'outside the chosen radius'; continue }
      $cur = $r.Get('Inventory')
      if ($opt.KeepFilled -and $cur) { Skip 'container still holds items (kept)'; continue }
      if (Test-InvProtected $cur $prot) { Skip 'holds a quest item or key (kept)'; continue }
      $key = Get-RecKey $r; $inv = $null; $src = ''
      if ($orig.ContainsKey($r.GuidHex)) { $inv = $orig[$r.GuidHex]; $src = 'its original loot' } elseif ($orig.ContainsKey($key)) { $inv = $orig[$key]; $src = 'its original loot' }
      if ($inv -and (Test-InvProtected $inv $prot)) { Skip 'holds a quest item or key (kept)'; continue }
      if (-not $inv) {
        $pk = & $poolKey $r.Cls
        if ($pool.ContainsKey($pk) -and $pool[$pk].Count -gt 0) {
          $cand = $pool[$pk]; $free = @($cand | Where-Object { -not $usedPool.ContainsKey($pk + '|' + $_) })
          if ($free.Count -eq 0) { $free = $cand.ToArray() }
          $inv = $free[$rng.Next($free.Count)]; $usedPool[$pk + '|' + $inv] = 1; $src = 'a real roll from the same loot table' }
        elseif ($r.Cls -match '^BP_SolarPanel_\d+_C$') {
          # solar panels are never recorded unopened in any save, so roll their loot from the game's own table
          # (DA_RandomList_Preset_Remnants_SolarPanel: one pick, weights Wire 7 / Components 5 / ElectricalJunk 2 / MetalJunk 0.1, amount 1)
          $tbl = @(@('Wire', 7.0), @('Components', 5.0), @('ElectricalParts', 2.0), @('MetalJunk', 0.1)); $tot = 0.0; foreach ($t in $tbl) { $tot += $t[1] }
          $pick = $rng.NextDouble() * $tot; $item = $tbl[0][0]; foreach ($t in $tbl) { if ($pick -lt $t[1]) { $item = $t[0]; break }; $pick -= $t[1] }
          $inv = "@0=$item&1"; $src = 'a roll from the game''s solar panel loot table' }
        elseif ($shipPool.ContainsKey($pk) -and @($shipPool[$pk] | Where-Object { -not (Test-InvProtected $_ $prot) }).Count -gt 0) {
          # nothing of this loot group is left unopened in the world and no backup has it: a real roll from the shipped pool
          $cand = @($shipPool[$pk] | Where-Object { -not (Test-InvProtected $_ $prot) }); $free = @($cand | Where-Object { -not $usedPool.ContainsKey($pk + '|' + $_) })
          if ($free.Count -eq 0) { $free = $cand }
          $inv = $free[$rng.Next($free.Count)]; $usedPool[$pk + '|' + $inv] = 1; $src = 'a real roll from the shipped loot pool' }
        else { Skip "no loot sample for $($r.Cls)"; continue } }
      $plan.Items.Add([pscustomobject]@{ Kind = 'container'; Action = 'Refill'; Cls = $r.Cls; Cell = $c.Name; Rec = $r; Pos = $r.Pos; Inv = $inv; Note = $src })
    } }
  }
  # fingerprints of every record before anything is edited (the verification uses them)
  $fp = @{}; $cnt = 0; foreach ($c in $cells) { foreach ($r in $c.Recs) { $fp[$r.GuidHex] = [WorldBlob]::RecHash($r); $cnt++ } }
  $plan.Text = $s; $plan.World = $w; $plan.Nodes = $nodes; $plan.OrigHash = $fp; $plan.OrigCount = $cnt
  return $plan
}

function Get-ResetSummary($plan) {
  $lines = New-Object System.Collections.Generic.List[string]
  $groups = $plan.Items | Group-Object Kind, Action
  $label = @{ 'tree' = 'Trees'; 'ore' = 'Boulders and ores'; 'breakable' = 'Other breakables (pallets, rubble...)'; 'item' = 'World items'; 'container' = 'Containers' }
  $verb = @{ 'Remove' = 'felled trees put back'; 'Heal' = 'partly mined, back to full'; 'Restore' = 'destroyed / picked up, put back'; 'Refill' = 'looted, refilled'; 'Unlist' = 'in the save but marked used up, cleared' }
  foreach ($k in 'tree', 'ore', 'breakable', 'item', 'container') { foreach ($a in 'Remove', 'Heal', 'Restore', 'Refill', 'Unlist') {
    $n = @($plan.Items | Where-Object { $_.Kind -eq $k -and $_.Action -eq $a }).Count
    if ($n) { $lines.Add(("{0,5}  {1}: {2}" -f $n, $label[$k], $verb[$a])) } } }
  if ($plan.Plants -and $plan.Plants.Count) { $lines.Add(("{0,5}  Bushes and other generated plants / rocks: harvested, put back" -f $plan.Plants.Count)) }
  if ($lines.Count -eq 0) { $lines.Add('Nothing to reset with these settings.') }
  if ($plan.Skipped.Count) { $lines.Add(''); $lines.Add('Left alone:'); foreach ($k in $plan.Skipped.Keys) { $lines.Add(("{0,5}  {1}" -f $plan.Skipped[$k], $k)) } }
  $lines.Add(''); $lines.Add("Backups used as history: $($plan.History)" + $(if ($plan.HistoryOther) { "  (+ $($plan.HistoryOther) save(s) of your other worlds on the same map)" } else { '' }) + $(if ($plan.Pristine) { "  + the shipped map of untouched objects" } else { '' }))
  return $lines
}

# ---------- applying ----------
function Build-ResetSave($plan, $opt) {
  $s = $plan.Text; $w = $plan.World; $cells = $w.Cells; $nodes = $plan.Nodes
  $cellByName = @{}; foreach ($c in $cells) { $cellByName[$c.Name] = $c }
  $removeGuids = New-Object System.Collections.Generic.List[string]; $removeRecs = New-Object System.Collections.Generic.HashSet[object]
  $inserts = New-Object System.Collections.Generic.List[object]; $clearR = New-Object System.Collections.Generic.List[string]
  foreach ($it in $plan.Items) {
    switch ($it.Action) {
      'Remove' { [void]$removeRecs.Add($it.Rec); $removeGuids.Add($it.Rec.TextGuid) }
      'Heal' { $it.Rec.Set('Scavengeable_CurrentHealth', (Format-Health $nodes[$it.Cls])); $it.Rec.Set('InteractionBase_InteractionState', 'EIS_Active'); $clearR.Add($it.Rec.TextGuid) }
      'Restore' { $n = $it.Rec.Clone()
        if ($it.Kind -ne 'item') { $n.Set('Scavengeable_CurrentHealth', (Format-Health $nodes[$it.Cls])); $n.Set('InteractionBase_InteractionState', 'EIS_Active') }
        $inserts.Add(@{ Cell = $it.Cell; Rec = $n }); $clearR.Add($it.Rec.TextGuid) }
      'Refill' { $it.Rec.Set('InteractionBase_InteractionState', 'EIS_Active'); $it.Rec.Set('bEverOpened', 'false'); $it.Rec.Set('Inventory', $it.Inv); $removeGuids.Add($it.Rec.TextGuid); $clearR.Add($it.Rec.TextGuid) }
      'Unlist' { $clearR.Add($it.Rec.TextGuid) }
    } }
  foreach ($c in $cells) { if ($removeRecs.Count) { [void]$c.Recs.RemoveAll([Predicate[WRec]] { param($x) $removeRecs.Contains($x) }) } }
  foreach ($i in $inserts) { $cellByName[$i.Cell].Recs.Add($i.Rec) }
  $blob = [WorldBlob]::Serialize($cells)
  $sec = $w.Sec
  $out = $s.Substring(0, $sec.Start) + (Encode-B64U $blob) + $s.Substring($sec.End)
  $out = Remove-Copies $out ($removeGuids.ToArray() | Select-Object -Unique)
  $out = Remove-RGuids $out ($clearR.ToArray() | Select-Object -Unique)
  $drop = @{}; foreach ($pl in $plan.Plants) { if (-not $drop.ContainsKey($pl.List)) { $drop[$pl.List] = New-Object 'System.Collections.Generic.HashSet[int]' }; [void]$drop[$pl.List].Add([int]$pl.Index) }
  $out = Remove-ExclusionEntries $out $drop
  return @{ Text = $out; Bytes = $script:L1.GetBytes($out); RemovedGuids = ($removeGuids.ToArray() | Select-Object -Unique); ClearedGuids = ($clearR.ToArray() | Select-Object -Unique); PlantDrop = $drop }
}

# independent re-read of the candidate: world block must parse, every planned change must be visible, everything else must be unchanged
function Test-ResetSave([string]$origText, $plan, $built) {
  $problems = New-Object System.Collections.Generic.List[string]
  $n = $built.Text; $nw = Read-WorldCells $n; $ow = $plan.World
  if (-not (Test-WorldRoundTrip $n)) { $problems.Add('new world block does not survive a rewrite round trip') }
  if ($nw.Cells.Count -ne $ow.Cells.Count) { $problems.Add('cell count changed') }
  $nm = @($plan.Items | Where-Object { $_.Action -eq 'Remove' }).Count; $nr = @($plan.Items | Where-Object { $_.Action -eq 'Restore' }).Count
  $newCount = 0; foreach ($c in $nw.Cells) { $newCount += $c.Recs.Count }
  if ($newCount -ne ($plan.OrigCount - $nm + $nr)) { $problems.Add("record count mismatch ($newCount, expected $($plan.OrigCount - $nm + $nr))") }
  $byGuid = @{}; foreach ($c in $nw.Cells) { foreach ($r in $c.Recs) { $byGuid[$r.GuidHex] = $r } }
  # every record that is not part of the plan must be byte-identical to before
  $touched = @{}; foreach ($it in $plan.Items) { $touched[$it.Rec.GuidHex] = 1 }
  foreach ($g in $plan.OrigHash.Keys) { if ($touched.ContainsKey($g)) { continue }
    if (-not $byGuid.ContainsKey($g)) { $problems.Add("untouched record vanished: $g"); continue }
    if ([WorldBlob]::RecHash($byGuid[$g]) -ne $plan.OrigHash[$g]) { $problems.Add("untouched record changed: $g") } }
  foreach ($it in $plan.Items) {
    switch ($it.Action) {
      'Remove' { if ($byGuid.ContainsKey($it.Rec.GuidHex)) { $problems.Add("tree still present: $($it.Rec.GuidHex)") } }
      'Heal' { $r = $byGuid[$it.Rec.GuidHex]; if (-not $r -or $r.State -ne 'EIS_Active') { $problems.Add("ore not healed: $($it.Rec.GuidHex)") } }
      'Restore' { if (-not $byGuid.ContainsKey($it.Rec.GuidHex)) { $problems.Add("record not restored: $($it.Cls)") } }
      'Refill' { $r = $byGuid[$it.Rec.GuidHex]; if (-not $r -or $r.State -ne 'EIS_Active' -or $r.Get('bEverOpened') -ne 'false' -or $r.Get('Inventory') -cne $it.Inv) { $problems.Add("container not refilled: $($it.Rec.GuidHex)") } }
    } }
  foreach ($g in $built.RemovedGuids) { if ($n.Contains($g)) { $problems.Add("plain-text copy still present: $g") } }
  # nothing outside the world block and the removed plain-text copies may differ from the original
  $expect = $origText.Substring(0, $ow.Sec.Start) + (Encode-B64U ([WorldBlob]::Serialize($nw.Cells))) + $origText.Substring($ow.Sec.End)
  $expect = Remove-Copies $expect $built.RemovedGuids
  $expect = Remove-RGuids $expect $built.ClearedGuids
  $expect = Remove-ExclusionEntries $expect $built.PlantDrop
  # every planned plant entry must be gone and every other entry of those lists must still be there
  $lo = @{}; foreach ($L in (Get-ExclusionLists $origText)) { $lo[$L.Name] = $L.Count }; $ln = @{}; foreach ($L in (Get-ExclusionLists $n)) { $ln[$L.Name] = $L.Count }
  foreach ($name in $lo.Keys) { $d = 0; if ($built.PlantDrop.ContainsKey($name)) { $d = $built.PlantDrop[$name].Count }
    if (-not $ln.ContainsKey($name) -and $d -lt $lo[$name]) { $problems.Add("exclusion list vanished: $name") } elseif ($ln.ContainsKey($name) -and $ln[$name] -ne ($lo[$name] - $d)) { $problems.Add("exclusion list size wrong: $name") } }
  foreach ($g in $built.ClearedGuids) { if ($n.Contains("[rGUID>${g}?")) { $problems.Add("still on the used-up list: $g") } }
  if ($expect -cne $n) { $problems.Add('file differs from the expected result outside the planned edits') }
  foreach ($name in 'PlayerSaveData', 'HostSaveData') { $a = (Get-BlobSection $origText $name).Bytes; $b = (Get-BlobSection $n $name).Bytes; if ([Convert]::ToBase64String($a) -cne [Convert]::ToBase64String($b)) { $problems.Add("$name changed") } }
  if ($origText.Substring(0, $origText.IndexOf('[LevelStreamingData###>')) -cne $n.Substring(0, $n.IndexOf('[LevelStreamingData###>'))) { $problems.Add('save header changed') }
  return $problems
}

# $Plan: the plan the Preview already made (reading all the earlier copies takes about a minute); it is only used when the save file is still exactly the one it was made from
function Install-WorldReset([string]$savePath, $opt, [switch]$SkipGameCheck, $Plan = $null) {
  if ((-not $SkipGameCheck) -and (Test-GameRunning)) { throw 'The game is running. Save and close it first.' }
  if (-not (Test-Path $savePath)) { throw "Save not found: $savePath" }
  $orig = $script:L1.GetString([IO.File]::ReadAllBytes($savePath))
  if ($Plan -and $Plan.Text -ceq $orig) { $plan = $Plan } else { $plan = Build-ResetPlan $savePath $opt }
  if ($plan.Items.Count -eq 0 -and $plan.Plants.Count -eq 0) { throw 'nothing to reset with these settings' }
  Report-Progress 'Putting the objects back...'
  $built = Build-ResetSave $plan $opt
  Report-Progress 'Checking the result before anything is written...'
  $problems = Test-ResetSave $orig $plan $built
  if ($problems.Count) { throw ('Verification failed, nothing was written: ' + (($problems | Select-Object -First 5) -join '; ')) }
  Report-Progress 'Making a backup and writing the save...'
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'; $name = [IO.Path]::GetFileName($savePath)
  $backup = Join-Path (Get-BackupDir) "$stamp`_$name"
  Copy-Item $savePath $backup -Force
  if ((Get-FileHash $backup).Hash -ne (Get-FileHash $savePath).Hash) { throw 'Backup did not match the original - nothing was written.' }
  $tmp = Join-Path (Get-BackupDir) "$stamp`_NEW_$name"; [IO.File]::WriteAllBytes($tmp, $built.Bytes)
  if ((Get-FileHash $tmp).Hash -ne ([BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($built.Bytes)).Replace('-', ''))) { throw 'Temp file write mismatch - nothing was installed.' }
  Copy-Item $tmp $savePath -Force; Remove-Item $tmp -Force
  $final = $script:L1.GetString([IO.File]::ReadAllBytes($savePath))
  if ($final -cne $built.Text) { Copy-Item $backup $savePath -Force; throw 'Post-install check failed, original restored.' }
  [IO.File]::SetLastWriteTime($savePath, (Get-Date))
  return @{ Backup = $backup; Summary = (Get-ResetSummary $plan) }
}
