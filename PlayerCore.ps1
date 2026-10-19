# PlayerCore.ps1 - player stats, skills, recipes, teleport and quest reading. Needs SaveCore.ps1 loaded first.
# Every one of these values lives in THREE synced copies (plain text + PlayerSaveData blob + HostSaveData blob),
# so every edit goes through Set-SaveKeys, which patches all three, verifies, backs up and re-checks.
$script:Inv = [Globalization.CultureInfo]::InvariantCulture

function Get-SaveText([string]$path) { $script:L1.GetString([IO.File]::ReadAllBytes($path)) }
function Format-Num([double]$v) { $v.ToString('0.0#####', $script:Inv) }

# ---------- blob entries (robust: walks the real entry list, no substring matching) ----------
function Read-BlobEntries([byte[]]$blob) {
  # layout: int32 1, int32 len + UUID text (33 bytes), int32 (entry count), then the entries. A brand-new character has no PlayerBuildParts yet,
  # so the start is computed from the header (checked against the PlayerBuildParts position when that entry exists).
  $start = Get-BlobEntryStart $blob; $pos = $start; $list = New-Object System.Collections.Generic.List[object]
  while ($pos -lt $blob.Length) {
    $kl = [BitConverter]::ToInt32($blob, $pos); if ($kl -lt 2 -or $kl -gt 80) { throw "bad key length $kl at $pos" }
    $key = $script:L1.GetString($blob, $pos + 4, $kl - 1)
    $vl = [BitConverter]::ToInt32($blob, $pos + 4 + $kl); $vs = $pos + 8 + $kl
    if ($vl -lt 0 -or $vs + $vl -gt $blob.Length) { throw "bad value length at $pos" }
    $raw = New-Object byte[] $vl; if ($vl -gt 0) { [Array]::Copy($blob, $vs, $raw, 0, $vl) }
    $list.Add([pscustomobject]@{ Key = $key; Raw = $raw; Text = $(if ($vl -gt 0) { $script:L1.GetString($raw, 0, $vl - 1) } else { '' }) })
    $pos = $vs + $vl
  }
  return @{ Start = $start; Entries = $list }
}
function Write-BlobEntries([byte[]]$blob, $parsed, [hashtable]$changes) {
  $ms = New-Object IO.MemoryStream; $ms.Write($blob, 0, $parsed.Start)
  foreach ($e in $parsed.Entries) {
    $kb = $script:L1.GetBytes($e.Key + "`0"); $ms.Write([BitConverter]::GetBytes([int]$kb.Length), 0, 4); $ms.Write($kb, 0, $kb.Length)
    if ($changes -and $changes.ContainsKey($e.Key)) { $vb = $script:L1.GetBytes([string]$changes[$e.Key] + "`0") } else { $vb = $e.Raw }
    $ms.Write([BitConverter]::GetBytes([int]$vb.Length), 0, 4); if ($vb.Length -gt 0) { $ms.Write($vb, 0, $vb.Length) }
  }
  return $ms.ToArray()
}

# ---------- generic, verified edit of any player keys ----------
function Build-KeyEdit([string]$path, [hashtable]$changes) {
  $s = Get-SaveText $path
  foreach ($k in $changes.Keys) { if (([string]$changes[$k]).Contains('?')) { throw "refusing: new value for $k contains a field separator" } }
  $ranges = @{}; foreach ($k in $changes.Keys) { $ranges[$k] = Get-PlainRange $s $k }
  # all three copies must agree before we touch anything
  foreach ($name in 'PlayerSaveData', 'HostSaveData') {
    $p = Read-BlobEntries (Get-BlobSection $s $name).Bytes; $h = @{}; foreach ($e in $p.Entries) { $h[$e.Key] = $e.Text }
    foreach ($k in $changes.Keys) { if (-not $h.ContainsKey($k)) { throw "$name has no entry '$k'" }; if ($h[$k] -cne $ranges[$k].Text) { throw "$name '$k' differs from the plain-text copy - save is inconsistent, aborting" } }
  }
  $todo = @{}; foreach ($k in $changes.Keys) { if ([string]$changes[$k] -cne $ranges[$k].Text) { $todo[$k] = [string]$changes[$k] } }
  if ($todo.Count -eq 0) { throw 'nothing to change (those values are already in the save)' }
  foreach ($k in ($todo.Keys | Sort-Object { $ranges[$_].Start } -Descending)) { $r = $ranges[$k]; $s = $s.Substring(0, $r.Start) + $todo[$k] + $s.Substring($r.End) }
  foreach ($name in 'PlayerSaveData', 'HostSaveData') {
    $sec = Get-BlobSection $s $name; $before = Walk-Blob $sec.Bytes; $parsed = Read-BlobEntries $sec.Bytes
    $same = Write-BlobEntries $sec.Bytes $parsed $null
    if ((Encode-B64U $same) -cne (Encode-B64U $sec.Bytes)) { throw "$name could not be rebuilt byte-for-byte - aborting" }
    $blob = Write-BlobEntries $sec.Bytes $parsed $todo
    $after = Walk-Blob $blob; if ($before -ne $after) { throw "$name entry count changed ($before -> $after)" }
    $s = $s.Substring(0, $sec.Start) + (Encode-B64U $blob) + $s.Substring($sec.End)
  }
  return @{ Bytes = $script:L1.GetBytes($s); Todo = $todo }
}

function Remove-EditableSpans([string]$t, [string[]]$keys) {
  $rs = @(); foreach ($k in $keys) { $rs += Get-PlainRange $t $k }
  foreach ($r in ($rs | Sort-Object Start -Descending)) { $t = $t.Substring(0, $r.Start) + $t.Substring($r.End) }
  foreach ($name in 'PlayerSaveData', 'HostSaveData') { $sec = Get-BlobSection $t $name; $t = $t.Substring(0, $sec.Start) + $t.Substring($sec.End) }
  return $t
}
function Test-KeyEdit([string]$origPath, [byte[]]$newBytes, [hashtable]$todo) {
  $o = Get-SaveText $origPath; $n = $script:L1.GetString($newBytes); $problems = @()
  foreach ($k in $todo.Keys) { if ((Get-PlainRange $n $k).Text -cne $todo[$k]) { $problems += "plain-text $k is not what was planned" } }
  foreach ($name in 'PlayerSaveData', 'HostSaveData') {
    $po = Read-BlobEntries (Get-BlobSection $o $name).Bytes; $pn = Read-BlobEntries (Get-BlobSection $n $name).Bytes
    if ($po.Entries.Count -ne $pn.Entries.Count) { $problems += "$name entry count differs"; continue }
    for ($i = 0; $i -lt $po.Entries.Count; $i++) {
      $a = $po.Entries[$i]; $b = $pn.Entries[$i]
      if ($a.Key -cne $b.Key) { $problems += "$name entry order changed"; break }
      if ($todo.ContainsKey($a.Key)) { if ($b.Text -cne $todo[$a.Key]) { $problems += "$name $($a.Key) mismatch" } }
      elseif ($a.Text -cne $b.Text) { $problems += "$name $($a.Key) changed unexpectedly" }
    }
  }
  $keys = @($todo.Keys)
  if ((Remove-EditableSpans $o $keys) -cne (Remove-EditableSpans $n $keys)) { $problems += 'something outside the edited values changed' }
  return $problems
}

function Set-SaveKeys([string]$savePath, [hashtable]$changes, [switch]$SkipGameCheck) {
  if ((-not $SkipGameCheck) -and (Test-GameRunning)) { throw 'The game is running. Save and close it first.' }
  if (-not (Test-Path -LiteralPath $savePath)) { throw "Save not found: $savePath" }
  $r = Build-KeyEdit $savePath $changes
  $problems = Test-KeyEdit $savePath $r.Bytes $r.Todo
  if ($problems.Count) { throw ('Verification failed, nothing was written: ' + ($problems -join '; ')) }
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'; $name = [IO.Path]::GetFileName($savePath)
  $backup = Join-Path (Get-BackupDir) "$stamp`_$name"
  Copy-Item -LiteralPath $savePath -Destination $backup -Force
  if ((Get-FileHash -LiteralPath $backup).Hash -ne (Get-FileHash -LiteralPath $savePath).Hash) { throw 'Backup did not match the original - nothing was written.' }
  $tmp = Join-Path (Get-BackupDir) "$stamp`_NEW_$name"; [IO.File]::WriteAllBytes($tmp, $r.Bytes)
  if ((Get-FileHash -LiteralPath $tmp).Hash -ne ([BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($r.Bytes)).Replace('-', ''))) { throw 'Temp file write mismatch - nothing was installed.' }
  Copy-Item -LiteralPath $tmp -Destination $savePath -Force; [IO.File]::Delete($tmp)
  $final = Test-KeyEdit $backup ([IO.File]::ReadAllBytes($savePath)) $r.Todo
  if ($final.Count) { Copy-Item -LiteralPath $backup -Destination $savePath -Force; throw ('Post-install check failed, original restored: ' + ($final -join '; ')) }
  [IO.File]::SetLastWriteTime($savePath, (Get-Date))
  return @{ Backup = $backup; Changed = @($r.Todo.Keys) }
}

# ---------- reading the player ----------
$script:VitalDefs = @(
  @{ Key = 'health';     Max = 'MaxHealth';     Label = 'Health' },
  @{ Key = 'stamina';    Max = 'MaxStamina';    Label = 'Stamina' },
  @{ Key = 'energy';     Max = 'MaxEnergy';     Label = 'Energy (sleep)' },
  @{ Key = 'hunger';     Max = 'MaxHunger';     Label = 'Hunger (food)' },
  @{ Key = 'BodyWarmth'; Max = 'MaxBodyWarmth'; Label = 'Body warmth' })

function Convert-ToD([string]$t) { $v = 0.0; [void][double]::TryParse($t, [Globalization.NumberStyles]::Float, $script:Inv, [ref]$v); return $v }

function Get-QuestInfo([string]$q) {
  $res = @{ Quests = @(); Tasks = @(); Rewards = @(); Journal = @(); Active = @(); Regions = @() }
  if (-not $q) { return $res }
  function Seg([string]$tag) { $i = $q.IndexOf($tag); if ($i -lt 0) { return $null }; $a = $i + $tag.Length; $b = $q.IndexOf('@', $a); $h = $q.IndexOf('#', $a); if ($b -lt 0 -or ($h -ge 0 -and $h -lt $b)) { $b = $h }; if ($b -lt 0) { $b = $q.Length }; return $q.Substring($a, $b - $a) }
  $all = Seg '@AllQuests&'; if ($all) {
    $res.Quests = @($all -split '&' | Where-Object { $_ } | ForEach-Object {
      $p = $_ -split '\*'; $asset = ($p[0] -replace '^.*/', '' -replace '\..*$', ''); $chain = if ($p[0] -match '/Quests/(?:EA_Release/)?([^/]+)/') { $Matches[1] } else { '' }
      $br = if ($p.Count -gt 2) { @($p[2] -split '\$' | Where-Object { $_ -and $_ -ne 'Branches' }).Count } else { 0 }
      $st = if ($p.Count -gt 3) { @($p[3] -split '\$' | Where-Object { $_ -and $_ -ne 'States' }).Count } else { 0 }
      [pscustomobject]@{ Quest = $asset; Chain = $chain; State = $(if ($p.Count -gt 1) { $p[1] } else { '' }); Branches = $br; StatesSeen = $st; Raw = $_ } })
  }
  $act = Seg '@ActiveQuests&'; if ($act) { $res.Active = @($act -split '&' | Where-Object { $_ }) }
  $tl = Seg '@TaskList&'; if ($tl) { $res.Tasks = @($tl -split '&' | Where-Object { $_ } | ForEach-Object { $kv = $_ -split '=', 2; [pscustomobject]@{ Task = $kv[0]; Count = $(if ($kv.Count -gt 1) { $kv[1] } else { '' }) } }) }
  $rg = Seg '@UnlockedRegions&'; if ($rg) { $res.Regions = @($rg -split '&' | Where-Object { $_ }) }
  $ri = $q.IndexOf('#QuestRewards'); if ($ri -ge 0) {
    $re = $q.IndexOf('#', $ri + 5); if ($re -lt 0) { $re = $q.Length }
    foreach ($pool in ($q.Substring($ri + 13, $re - $ri - 13) -split '>' | Where-Object { $_ })) {
      $pp = $pool.TrimStart('$') -split '&'; $res.Rewards += [pscustomobject]@{ Pool = $pp[0]; Claimed = (@($pp | Select-Object -Skip 1) -join ', ') } }
  }
  $ji = $q.IndexOf('#Journal'); if ($ji -ge 0) {
    $je = $q.IndexOf('#Quests', $ji); if ($je -lt 0) { $je = $q.Length }
    foreach ($sec in ($q.Substring($ji + 8, $je - $ji - 8) -split '@' | Where-Object { $_ })) {
      $pp = $sec -split '&'; $nm = ($pp[0] -split '\|')[0]; $res.Journal += [pscustomobject]@{ Section = $nm; Count = (@($pp | Select-Object -Skip 1).Count); Entries = (@($pp | Select-Object -Skip 1) -join ', ') } }
  }
  return $res
}

function Get-PlayerData([string]$path) {
  $s = Get-SaveText $path; $p = Read-BlobEntries (Get-BlobSection $s 'PlayerSaveData').Bytes; $h = @{}; foreach ($e in $p.Entries) { $h[$e.Key] = $e.Text }
  $vit = foreach ($d in $script:VitalDefs) { [pscustomobject]@{ Key = $d.Key; MaxKey = $d.Max; Label = $d.Label; Value = (Convert-ToD $h[$d.Key]); Max = (Convert-ToD $h[$d.Max]) } }
  $cnt = [int]$h['CharacterSkillsComponent_SkillCount']; $skills = @()
  for ($i = 0; $i -lt $cnt; $i++) { $k = "CharacterSkillsComponent_Skill_$i"; if ($h.ContainsKey($k)) { $j = $h[$k] | ConvertFrom-Json; $skills += [pscustomobject]@{ Index = $i; Key = $k; Name = $j.skillName; Level = [int]$j.level; XP = [double]$j.currentExperience; Need = [double]$j.experienceNeededForNextLevel; Json = $h[$k] } }
  }
  $pos = $null; if ($h['PawnLocation'] -match '^(-?[\d.]+),(-?[\d.]+),(-?[\d.]+)\|(.*)$') { $pos = @{ X = (Convert-ToD $Matches[1]); Y = (Convert-ToD $Matches[2]); Z = (Convert-ToD $Matches[3]); Rest = $Matches[4] } }
  $bed = $null; if ($h['BedRespawnLocation'] -match 'X=(-?[\d.]+)\s+Y=(-?[\d.]+)\s+Z=(-?[\d.]+)') { $bed = @{ X = (Convert-ToD $Matches[1]); Y = (Convert-ToD $Matches[2]); Z = (Convert-ToD $Matches[3]) } }
  $fall = $null; if ($h['FallStartLocation'] -match 'X=(-?[\d.]+),Y=(-?[\d.]+),Z=(-?[\d.]+)') { $fall = @{ X = (Convert-ToD $Matches[1]); Y = (Convert-ToD $Matches[2]); Z = (Convert-ToD $Matches[3]) } }
  $parts = @(); foreach ($m in [regex]::Matches($h['PlayerBuildParts'], '#([A-Za-z0-9_]+)&X=(-?[\d.]+),Y=(-?[\d.]+),Z=(-?[\d.]+)')) { $parts += [pscustomobject]@{ Type = $m.Groups[1].Value; X = (Convert-ToD $m.Groups[2].Value); Y = (Convert-ToD $m.Groups[3].Value); Z = (Convert-ToD $m.Groups[4].Value) } }
  $known = @($h['PlayerKnowledge_Knowledge'] -split '\|' | Where-Object { $_ })
  [pscustomobject]@{
    Entries = $h; Vitals = @($vit); Skills = $skills; Points = [int]$h['PointsAmount']; Position = $pos; Bed = $bed; Fall = $fall; Parts = $parts; Known = $known
    Quests = (Get-QuestInfo $h['QuestSystem'])
    World = [regex]::Match($s, 'SlotName>([^\?]+)').Groups[1].Value; Created = [regex]::Match($s, 'CreatedAt>([^\?]+)').Groups[1].Value; Updated = [regex]::Match($s, 'LastUpdatedAt>([^\?]+)').Groups[1].Value
    Playtime = (Convert-ToD ([regex]::Match($s, 'TotalPlayTime>([\d\.]+)').Groups[1].Value)) }
}

# ---------- skills ----------
function Get-SkillNeed([int]$level) { 10.0 * [math]::Pow([math]::Max(1, $level), 1.5) }     # matches all 16 skills in the save
function Build-SkillJson([string]$json, [int]$level, [double]$xp) {
  $need = Get-SkillNeed $level
  $j = $json -replace '"level":\s*[-\d.eE+]+', ('"level":' + $level)
  $j = $j -replace '"currentExperience":\s*[-\d.eE+]+', ('"currentExperience":' + $xp.ToString('R', $script:Inv))
  $j = $j -replace '"experienceNeededForNextLevel":\s*[-\d.eE+]+', ('"experienceNeededForNextLevel":' + $need.ToString('R', $script:Inv))
  $o = $j | ConvertFrom-Json; if ([int]$o.level -ne $level) { throw 'skill text rebuild failed' }
  return $j
}

# ---------- recipes (what the character has learned) ----------
function Get-RecipeCatalog {
  $f = Join-Path $PSScriptRoot 'catalog\blueprints-index.csv'; if (-not (Test-Path -LiteralPath $f)) { throw 'catalog\blueprints-index.csv missing - run Build-DataCatalog.ps1' }
  $rows = Import-Csv $f | Where-Object { $_.Asset -like 'DA_LearningRecipe_*' -or ($_.Asset -like 'DA_Learn*' -and $_.Folder -like '*LearningRecipes*') }
  foreach ($r in $rows) {
    $isItem = $r.Asset -like 'DA_LearningRecipe_*'; $nm = ($r.Asset -replace '^DA_Learn[A-Za-z]*?_', '' -replace '^Learning_?', '')
    $grp = ($r.Folder -replace '^.*LearningRecipes/?', '')
    [pscustomobject]@{ Asset = $r.Asset; Name = (($nm -creplace '([a-z0-9])([A-Z])', '$1 $2') -replace '_', ' ').Trim(); Kind = $(if ($isItem) { 'Item recipe' } else { 'Building recipe' }); Group = $grp
      Path = "/Game/Permafrost/Blueprints/$($r.Folder)/$($r.Asset).$($r.Asset)"; Refs = $r.Refs }
  }
}
function Add-Recipes([string]$savePath, [string[]]$paths, [switch]$SkipGameCheck) {
  $cur = (Get-PlayerData $savePath).Entries['PlayerKnowledge_Knowledge']; $have = @{}; foreach ($k in ($cur -split '\|' | Where-Object { $_ })) { $have[$k] = 1 }
  $add = @($paths | Where-Object { $_ -and -not $have.ContainsKey($_) } | Select-Object -Unique); if ($add.Count -eq 0) { throw 'You already know all of those recipes.' }
  $new = if ($cur) { $cur.TrimEnd('|') + '|' + ($add -join '|') } else { $add -join '|' }
  return Set-SaveKeys $savePath @{ PlayerKnowledge_Knowledge = $new } -SkipGameCheck:$SkipGameCheck
}

# ---------- teleport ----------
function Get-TeleportTargets($pd) {
  $t = New-Object System.Collections.Generic.List[object]
  if ($pd.Bed) { $t.Add([pscustomobject]@{ Name = 'Your bed (respawn point)'; Kind = 'Bed'; X = $pd.Bed.X; Y = $pd.Bed.Y; Z = $pd.Bed.Z }) }
  if ($pd.Fall) { $t.Add([pscustomobject]@{ Name = 'Crash / start location'; Kind = 'Start'; X = $pd.Fall.X; Y = $pd.Fall.Y; Z = $pd.Fall.Z }) }
  $n = @{}
  foreach ($b in $pd.Parts) { if ($b.Type -match '^(Wooden|Stone|Metal|Brick|Concrete)?(Foundation|Wall|Floor|Roof|Door|Window|Ramp|Stairs|Pillar|Fence|Gate|Ceiling|Beam|Half|Corner|Platform|Frame)') { continue }; $n[$b.Type] = 1 + [int]$n[$b.Type]; $t.Add([pscustomobject]@{ Name = "$($b.Type) #$($n[$b.Type])"; Kind = 'Your build'; X = $b.X; Y = $b.Y; Z = $b.Z }) }
  return $t.ToArray()
}
function Get-DistanceM($pd, $t) { if (-not $pd.Position) { return 0 }; [math]::Round([math]::Sqrt([math]::Pow($t.X - $pd.Position.X, 2) + [math]::Pow($t.Y - $pd.Position.Y, 2) + [math]::Pow($t.Z - $pd.Position.Z, 2)) / 100.0) }
function Set-Teleport([string]$savePath, $pd, $target, [switch]$SkipGameCheck) {
  if (-not $pd.Position) { throw 'could not read your current position' }
  $new = "{0},{1},{2}|{3}" -f (Format-Num $target.X), (Format-Num $target.Y), (Format-Num ($target.Z + 150)), $pd.Position.Rest
  return Set-SaveKeys $savePath @{ PawnLocation = $new } -SkipGameCheck:$SkipGameCheck
}
