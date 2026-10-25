# Build-Terrain.ps1 - builds the two data files the Teleport tab and its map use, from the atlas flights (see AtlasDumpMod\README.txt):
#
#   catalog\terrain-levels.csv  C,R,Z,N,G     for every 50 m square of the flown map the heights (Z, game centimetres) at which objects were found,
#                                             N = objects at that height, G = how many of them lie on the ground (boulders, trees, bushes, pallets, cars...)
#   catalog\map-points.csv      K,X,Y         one dot per 10 m square and kind (o ore, c container, i loose item, t tree / bush, b breakable, n note) for the map picture
#
# Sources: the flight logs (every actor with a save id: class, position, id) and the saves that were flown (every visited cell holds a record for every object).
# Objects are counted once per save id. Usage:
#   pwsh -File .\Build-Terrain.ps1 [-Logs <log>,<log>] [-Saves <flown save>,<flown save>]
param([string[]]$Logs = @(), [string[]]$Saves = @())
$ErrorActionPreference = 'Stop'
foreach ($f in 'Paths.ps1', 'SaveCore.ps1', 'WorldCore.ps1', 'PlayerCore.ps1', 'WorldReset.ps1') { . (Join-Path $PSScriptRoot $f) | Out-Null }
$arc = Join-Path $PSScriptRoot 'Archive\atlas-flight'
if ($Logs.Count -eq 0) { $Logs = @((Join-Path $arc 'AtlasDump-after-route106.log'), (Join-Path $arc 'AtlasDump-v8-route297.log')) | Where-Object { Test-Path $_ } }
if ($Saves.Count -eq 0) { $Saves = @((Join-Path $arc 'World3-AFTERATLAS.pfs'), (Join-Path $arc 'NEWFLIGHT-raw-20261024-1825.pfs')) | Where-Object { Test-Path $_ } }
$inv = [Globalization.CultureInfo]::InvariantCulture; $L1 = [Text.Encoding]::Latin1
$skip = 'MasterClothing|Spawner|PCGReActor|Weather|WorldMap|Companion|Renovation|QuestItemDispenser|RespawnPoint|Doors|Brazier|Torch'
$ground = 'Boulder|ScavengableTree|BushScavengable|RockShard|WoodenPallet|StackOfPlanks|PlasticPallets|PileOfTrash|DeadOnTheGround|TrashCan|CartOfTrash|Car_\d'
$seen = New-Object 'System.Collections.Generic.HashSet[string]'
$objs = New-Object System.Collections.Generic.List[object]
function Add-Obj([string]$id, [string]$cls, [double]$x, [double]$y, [double]$z) {
  if ($cls -match $skip -or $z -gt 15000 -or $z -lt -3000) { return }
  if ($id -and -not $seen.Add($id)) { return }
  $objs.Add([pscustomobject]@{ Cls = $cls; X = $x; Y = $y; Z = $z }) }
foreach ($lg in $Logs) { "log $lg"; foreach ($ln in [IO.File]::ReadLines($lg)) { if (-not $ln.StartsWith('STOP')) { continue }; $q = $ln.Split('|'); if ($q.Count -lt 8) { continue }
  Add-Obj $q[7].Trim().ToUpper() $q[2] ([double]::Parse($q[4], $inv)) ([double]::Parse($q[5], $inv)) ([double]::Parse($q[6], $inv)) } }
foreach ($sv in $Saves) { "save $sv"; $t = $L1.GetString([IO.File]::ReadAllBytes($sv)); $w = Read-WorldCells $t
  foreach ($c in $w.Cells) { foreach ($r in $c.Recs) { if ($r.Pos -and $r.Pos.Count -ge 3) { $id = if ($r.GuidHex -match '^[0-9A-Fa-f]{32}$') { $r.GuidHex.ToUpper() } else { [string]$r.TextGuid }; Add-Obj $id ($r.Cls -replace '_C$', '') ([double]$r.Pos[0]) ([double]$r.Pos[1]) ([double]$r.Pos[2]) } } } }
"objects (unique ids): $($objs.Count)"
# ---- terrain levels: per 50 m square, cluster the heights (within 250 cm of the cluster's first member)
$cells = @{}
foreach ($o in $objs) { $k = "$([math]::Floor($o.X / 5000)),$([math]::Floor($o.Y / 5000))"; if (-not $cells.ContainsKey($k)) { $cells[$k] = New-Object System.Collections.Generic.List[object] }; $cells[$k].Add($o) }
$rows = New-Object System.Collections.Generic.List[string]; $rows.Add('C,R,Z,N,G')
foreach ($k in ($cells.Keys | Sort-Object)) { $c, $r = $k -split ','; $sorted = @($cells[$k] | Sort-Object Z); $i = 0
  while ($i -lt $sorted.Count) { $z0 = $sorted[$i].Z; $grp = New-Object System.Collections.Generic.List[object]
    while ($i -lt $sorted.Count -and $sorted[$i].Z - $z0 -le 250) { $grp.Add($sorted[$i]); $i++ }
    $zs = @($grp | ForEach-Object { $_.Z } | Sort-Object); $med = $zs[[int]($zs.Count / 2)]; $g = @($grp | Where-Object { $_.Cls -match $ground }).Count
    $rows.Add("$c,$r,$([int][math]::Round($med)),$($grp.Count),$g") } }
[IO.File]::WriteAllLines((Join-Path $PSScriptRoot 'catalog\terrain-levels.csv'), $rows)
"terrain-levels.csv: $($rows.Count - 1) levels in $($cells.Count) squares"
# ---- map dots
$kind = { param($cl) if ($cl -match 'Boulder') { 'o' } elseif ($cl -match 'ScavengableTree|BushScavengable') { 't' } elseif ($cl -match '^BP_S_') { 'c' } elseif ($cl -match '_WI$') { 'i' } elseif ($cl -match 'Note|Recording|Recipe_Tube') { 'n' } elseif ($cl -match '^BP_D_|RockShard') { 'b' } else { '' } }
$dots = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($o in $objs) { $kd = & $kind $o.Cls; if (-not $kd) { continue }; [void]$dots.Add("$kd,$([int]([math]::Round($o.X / 1000) * 10)),$([int]([math]::Round($o.Y / 1000) * 10))") }
$lines = New-Object System.Collections.Generic.List[string]; $lines.Add('K,X,Y'); foreach ($d in ($dots | Sort-Object)) { $p = $d -split ','; $lines.Add("$($p[0]),$([int]$p[1] * 100),$([int]$p[2] * 100)") }
[IO.File]::WriteAllLines((Join-Path $PSScriptRoot 'catalog\map-points.csv'), $lines)
"map-points.csv: $($lines.Count - 1) dots"
