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
  if ($cls -match '^BP_BushScavengable') { return 'bush' }
  if (($cls -match '^BP_S_' -and $path -match '/Interactions/Containers/') -or ($cls -match '^BP_SolarPanel' -and $path -match '/Scavengable/')) { return 'container' }
  return ''
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

# plain-text copies of an actor: "[BEGIN_OBJECT_SAVE?Guid>HEX?...?END_OBJECT_SAVE?" and "[BEGIN_RUNTIME_DATA_SAVE?RuntimeDataPayload###>HEX?...?[END_RUNTIME_DATA_SAVE?"
function Get-CopyGuids([string]$s) {
  $set = @{}
  foreach ($m in [regex]::Matches($s, '\[BEGIN_OBJECT_SAVE\?Guid>([0-9A-F]{32})\?')) { $set[$m.Groups[1].Value] = 'object' }
  foreach ($m in [regex]::Matches($s, '\[BEGIN_RUNTIME_DATA_SAVE\?RuntimeDataPayload###>([0-9A-F]{32})\?')) { $set[$m.Groups[1].Value] = 'runtime' }
  return $set
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
  $dir = Get-BackupDir
  foreach ($f in (Get-ChildItem $dir -Filter "*_$leaf" | Where-Object { $_.Name -notmatch '_NEW_' } | Sort-Object Name)) {
    try { $t = $script:L1.GetString([IO.File]::ReadAllBytes($f.FullName)); $w = Read-WorldCells $t
      $list.Add([pscustomobject]@{ Name = $f.Name; Cells = $w.Cells; Copies = (Get-CopyGuids $t) }) } catch { }
  }
  return $list
}

function Get-RecKey($r) { return $r.ClsPath + '|' + $r.Transform }

# ---------- planning ----------
# opt: Trees, Ores, Breakables, Items, Containers (bool), RadiusM (0 = whole world), KeepFilled (containers that still hold items stay as they are), Seed
function Build-ResetPlan([string]$savePath, $opt) {
  $s = $script:L1.GetString([IO.File]::ReadAllBytes($savePath)); $w = Read-WorldCells $s; $cells = $w.Cells
  $nodes = Get-NodeTable; $prot = Get-ProtectedIds; $center = Get-PlayerPos $s; $radius = [double]$opt.RadiusM * 100
  $hist = Get-WorldHistory $savePath
  # classes whose own file has no MaxHealth inherit the engine default: use the health every untouched (EIS_Active) actor of that class has in the saves
  $seen = @{}
  foreach ($set in (@(, $cells) + @($hist | ForEach-Object { , $_.Cells }))) { foreach ($c in $set) { foreach ($r in $c.Recs) {
    if ($r.Cls -notmatch '^BP_D_' -or $nodes.ContainsKey($r.Cls) -or $r.State -ne 'EIS_Active') { continue }
    $h = $r.Get('Scavengeable_CurrentHealth'); if (-not $h) { continue }
    if (-not $seen.ContainsKey($r.Cls)) { $seen[$r.Cls] = @{} }; $seen[$r.Cls][$h] = 1 + [int]$seen[$r.Cls][$h] } } }
  foreach ($k in $seen.Keys) { if ($seen[$k].Count -eq 1) { $nodes[$k] = [double]::Parse(@($seen[$k].Keys)[0], $script:ResetInv) } }
  $plan = [ordered]@{ Items = (New-Object System.Collections.Generic.List[object]); Skipped = [ordered]@{}; History = $hist.Count; Radius = $opt.RadiusM }
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

  # 2) destroyed ores / breakables and picked-up items: newest backup that still has the record
  $wantRestore = $opt.Ores -or $opt.Breakables -or $opt.Items
  if ($wantRestore) {
    for ($hi = $hist.Count - 1; $hi -ge 0; $hi--) { $hs = $hist[$hi]
      foreach ($hc in $hs.Cells) { if (-not $cellByName.ContainsKey($hc.Name)) { continue }
        foreach ($r in $hc.Recs) {
          $kind = Get-ResetKind $r.Cls $r.ClsPath
          if (-not (($kind -eq 'ore' -and $opt.Ores) -or ($kind -eq 'breakable' -and $opt.Breakables) -or ($kind -eq 'item' -and $opt.Items))) { continue }
          $key = Get-RecKey $r; if ($byGuid.ContainsKey($r.GuidHex) -or $byKey.ContainsKey($key) -or $queued.ContainsKey($r.GuidHex) -or $queued.ContainsKey($key)) { continue }
          if ($hs.Copies.ContainsKey($r.TextGuid)) { Skip 'dropped/dynamic object (has a plain-text copy)'; continue }
          if ($kind -ne 'item' -and -not $nodes.ContainsKey($r.Cls)) { Skip "unknown max health: $($r.Cls)"; continue }
          if (-not (Test-NearPos $r.Pos $center $radius)) { Skip 'outside the chosen radius'; continue }
          if ($kind -eq 'item' -and $itemsByCls.ContainsKey($r.Cls)) { $near = $false; foreach ($o in $itemsByCls[$r.Cls]) { if (Test-NearPos $o.Pos $r.Pos 100) { $near = $true; break } }; if ($near) { Skip 'same item already lying within 1 m (it only moved)'; continue } }
          $queued[$r.GuidHex] = 1; $queued[$key] = 1
          $plan.Items.Add([pscustomobject]@{ Kind = $kind; Action = 'Restore'; Cls = $r.Cls; Cell = $hc.Name; Rec = $r; Pos = $r.Pos; Note = "from backup $($hs.Name)" })
        } } }
  }

  # 3) containers
  if ($opt.Containers) {
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
    foreach ($hs in $hist) { foreach ($hc in $hs.Cells) { foreach ($r in $hc.Recs) {
      if ((Get-ResetKind $r.Cls $r.ClsPath) -ne 'container') { continue }
      $inv = $r.Get('Inventory'); if ($inv -and $r.Get('bEverOpened') -eq 'false') { if (-not $orig.ContainsKey($r.GuidHex)) { $orig[$r.GuidHex] = $inv }; $k = Get-RecKey $r; if (-not $orig.ContainsKey($k)) { $orig[$k] = $inv }; & $addPool $r } } } }
    foreach ($c in $cells) { foreach ($r in $c.Recs) { if ((Get-ResetKind $r.Cls $r.ClsPath) -eq 'container') { & $addPool $r } } }
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
  $verb = @{ 'Remove' = 'felled trees put back'; 'Heal' = 'partly mined, back to full'; 'Restore' = 'destroyed / picked up, put back'; 'Refill' = 'looted, refilled' }
  foreach ($k in 'tree', 'ore', 'breakable', 'item', 'container') { foreach ($a in 'Remove', 'Heal', 'Restore', 'Refill') {
    $n = @($plan.Items | Where-Object { $_.Kind -eq $k -and $_.Action -eq $a }).Count
    if ($n) { $lines.Add(("{0,5}  {1}: {2}" -f $n, $label[$k], $verb[$a])) } } }
  if ($lines.Count -eq 0) { $lines.Add('Nothing to reset with these settings.') }
  if ($plan.Skipped.Count) { $lines.Add(''); $lines.Add('Left alone:'); foreach ($k in $plan.Skipped.Keys) { $lines.Add(("{0,5}  {1}" -f $plan.Skipped[$k], $k)) } }
  $lines.Add(''); $lines.Add("Backups used as history: $($plan.History)")
  return $lines
}

# ---------- applying ----------
function Build-ResetSave($plan, $opt) {
  $s = $plan.Text; $w = $plan.World; $cells = $w.Cells; $nodes = $plan.Nodes
  $cellByName = @{}; foreach ($c in $cells) { $cellByName[$c.Name] = $c }
  $removeGuids = New-Object System.Collections.Generic.List[string]; $removeRecs = New-Object System.Collections.Generic.HashSet[object]
  $inserts = New-Object System.Collections.Generic.List[object]
  foreach ($it in $plan.Items) {
    switch ($it.Action) {
      'Remove' { [void]$removeRecs.Add($it.Rec); $removeGuids.Add($it.Rec.TextGuid) }
      'Heal' { $it.Rec.Set('Scavengeable_CurrentHealth', (Format-Health $nodes[$it.Cls])); $it.Rec.Set('InteractionBase_InteractionState', 'EIS_Active') }
      'Restore' { $n = $it.Rec.Clone()
        if ($it.Kind -ne 'item') { $n.Set('Scavengeable_CurrentHealth', (Format-Health $nodes[$it.Cls])); $n.Set('InteractionBase_InteractionState', 'EIS_Active') }
        $inserts.Add(@{ Cell = $it.Cell; Rec = $n }) }
      'Refill' { $it.Rec.Set('InteractionBase_InteractionState', 'EIS_Active'); $it.Rec.Set('bEverOpened', 'false'); $it.Rec.Set('Inventory', $it.Inv); $removeGuids.Add($it.Rec.TextGuid) }
    } }
  foreach ($c in $cells) { if ($removeRecs.Count) { [void]$c.Recs.RemoveAll([Predicate[WRec]] { param($x) $removeRecs.Contains($x) }) } }
  foreach ($i in $inserts) { $cellByName[$i.Cell].Recs.Add($i.Rec) }
  $blob = [WorldBlob]::Serialize($cells)
  $sec = $w.Sec
  $out = $s.Substring(0, $sec.Start) + (Encode-B64U $blob) + $s.Substring($sec.End)
  $out = Remove-Copies $out ($removeGuids.ToArray() | Select-Object -Unique)
  return @{ Text = $out; Bytes = $script:L1.GetBytes($out); RemovedGuids = ($removeGuids.ToArray() | Select-Object -Unique) }
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
  if ($expect -cne $n) { $problems.Add('file differs from the expected result outside the planned edits') }
  foreach ($name in 'PlayerSaveData', 'HostSaveData') { $a = (Get-BlobSection $origText $name).Bytes; $b = (Get-BlobSection $n $name).Bytes; if ([Convert]::ToBase64String($a) -cne [Convert]::ToBase64String($b)) { $problems.Add("$name changed") } }
  if ($origText.Substring(0, $origText.IndexOf('[LevelStreamingData###>')) -cne $n.Substring(0, $n.IndexOf('[LevelStreamingData###>'))) { $problems.Add('save header changed') }
  return $problems
}

function Install-WorldReset([string]$savePath, $opt, [switch]$SkipGameCheck) {
  if ((-not $SkipGameCheck) -and (Test-GameRunning)) { throw 'The game is running. Save and close it first.' }
  if (-not (Test-Path $savePath)) { throw "Save not found: $savePath" }
  $orig = $script:L1.GetString([IO.File]::ReadAllBytes($savePath))
  $plan = Build-ResetPlan $savePath $opt
  if ($plan.Items.Count -eq 0) { throw 'nothing to reset with these settings' }
  $built = Build-ResetSave $plan $opt
  $problems = Test-ResetSave $orig $plan $built
  if ($problems.Count) { throw ('Verification failed, nothing was written: ' + (($problems | Select-Object -First 5) -join '; ')) }
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
