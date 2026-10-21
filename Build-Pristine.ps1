# Build-Pristine.ps1 - builds catalog\pristine-world.bin: the "untouched map" the World reset uses when a world has no backup of an object.
#
# What goes in: every boulder / ore / breakable / world-item record of a save that was FLOWN over the whole playable area (AtlasDump mod) in a world
# nobody had played, plus records (not dropped by a player; damaged ores are fine, World reset heals them when it restores them) of the same kinds from other saves of the same map for objects
# that world did not spawn. Only class, position, state and health are stored - nothing about any player.
#
# It also writes catalog\loot-pool.json: real loot rolls of UNOPENED containers per loot group (same grouping as the World reset's own pools), quest items and keys left out.
# World reset only uses them when a world has no unopened container of that group left to copy from.
#
# Usage:  pwsh -Command "& .\Build-Pristine.ps1 -Base <flown save.pfs> -Extra <other save.pfs>,<other save.pfs> -ExtraDir <folder of saves / backups>"
param([Parameter(Mandatory)][string]$Base, [string[]]$Extra = @(), [string]$ExtraDir = '', [string]$OutDir = (Join-Path $PSScriptRoot 'catalog'))
$ErrorActionPreference = 'Stop'
foreach ($f in 'Paths.ps1', 'SaveCore.ps1', 'WorldCore.ps1', 'PlayerCore.ps1', 'WorldReset.ps1') { . (Join-Path $PSScriptRoot $f) | Out-Null }
$L1 = [Text.Encoding]::Latin1
$kinds = 'ore', 'breakable', 'item'
$prot = Get-ProtectedIds
$cfgOf = @{}; $llp = Join-Path $PSScriptRoot 'catalog\loot-links.csv'; if (Test-Path $llp) { foreach ($l in (Import-Csv $llp)) { if ($l.FromFolder -eq 'Container') { $cfgOf[$l.From + '_C'] = $l.To } } }
$loot = @{}
function Add-Loot($r) {
  $inv = $r.Get('Inventory'); if (-not $inv -or $r.Get('bEverOpened') -ne 'false' -or (Test-InvProtected $inv $prot)) { return }
  $k = if ($cfgOf.ContainsKey($r.Cls)) { 'cfg:' + $cfgOf[$r.Cls] } else { $r.Cls }
  if (-not $loot.ContainsKey($k)) { $loot[$k] = New-Object 'System.Collections.Generic.SortedSet[string]' }; [void]$loot[$k].Add($inv) }

function Read-Save([string]$p) { $t = $L1.GetString([IO.File]::ReadAllBytes($p)); [pscustomobject]@{ Text = $t; World = (Read-WorldCells $t); Level = [regex]::Match($t, 'LevelName>([^?]*)').Groups[1].Value; Copies = (Get-CopyGuids $t) } }

$b = Read-Save $Base
$cells = [ordered]@{}; $have = @{}; $added = @{ base = 0; extra = 0 }
function Get-OutCell($c) { if (-not $cells.Contains($c.Name)) { $nc = New-Object WCell; $nc.NameRaw = $c.NameRaw; $nc.Name = $c.Name; $cells[$c.Name] = $nc }; return $cells[$c.Name] }

foreach ($c in $b.World.Cells) { foreach ($r in $c.Recs) {
  $bk = Get-ResetKind $r.Cls $r.ClsPath; if ($bk -eq 'container') { Add-Loot $r; continue }
  if ($kinds -notcontains $bk) { continue }
  if ($b.Copies.ContainsKey($r.TextGuid)) { continue }
  (Get-OutCell $c).Recs.Add($r); $have[$r.GuidHex] = 1; $added.base++ } }

$skipped = @{}
# ores / breakables sit at fixed spots, but a few have a slightly different position AND id from world to world (and older backups carry several ids for one spot):
# an extra record is only taken when no ore / breakable of the same class is already within 3 m, so a spot never gets two objects
$spots = @{}
function Test-Spot($r) { $p = $r.Pos; if (-not $p) { return $false }; if (-not $spots.ContainsKey($r.Cls)) { return $false }; foreach ($q in $spots[$r.Cls]) { if ([math]::Abs($q[0] - $p[0]) -lt 300 -and [math]::Abs($q[1] - $p[1]) -lt 300 -and [math]::Abs($q[2] - $p[2]) -lt 300) { return $true } }; return $false }
function Add-Spot($r) { $p = $r.Pos; if (-not $p) { return }; if (-not $spots.ContainsKey($r.Cls)) { $spots[$r.Cls] = New-Object 'System.Collections.Generic.List[double[]]' }; $spots[$r.Cls].Add([double[]]@($p[0], $p[1], $p[2])) }
foreach ($c in $cells.Values) { foreach ($r in $c.Recs) { if ((Get-ResetKind $r.Cls $r.ClsPath) -ne 'item') { Add-Spot $r } } }
if ($ExtraDir) { $Extra = @($Extra) + @(Get-ChildItem -LiteralPath $ExtraDir -Filter '*.pfs' | Sort-Object Name -Descending | ForEach-Object { $_.FullName }) }
foreach ($e in $Extra) {
  try { $s = Read-Save $e } catch { continue }; if ($s.Level -ne $b.Level) { continue }
  $n = 0
  foreach ($c in $s.World.Cells) { foreach ($r in $c.Recs) {
    $k = Get-ResetKind $r.Cls $r.ClsPath; if ($k -eq 'container') { Add-Loot $r; continue }; if ($kinds -notcontains $k) { continue }
    if ($have.ContainsKey($r.GuidHex)) { continue }
    if ($s.Copies.ContainsKey($r.TextGuid)) { $skipped['dropped by a player (plain-text copy)']++; continue }
    if ($r.Get('PlacedOnLevel') -ne '1') { $skipped['not placed on the level']++; continue }
    # a record that exists is an object that was NOT destroyed: a damaged one is fine, World reset puts restored ores back at full health and active
    if ($k -ne 'item') { if (Test-Spot $r) { $skipped['same spot already has that ore (other id)']++; continue }; Add-Spot $r }
    (Get-OutCell $c).Recs.Add($r); $have[$r.GuidHex] = 1; $added.extra++; $n++ } }
  if ($n) { Write-Host ("  +{0} records from {1}" -f $n, (Split-Path $e -Leaf)) }
}
$list = New-Object 'System.Collections.Generic.List[WCell]'; foreach ($c in $cells.Values) { $list.Add($c) }
$bytes = [WorldBlob]::Serialize($list)
$ms = New-Object IO.MemoryStream; $gz = New-Object IO.Compression.GZipStream($ms, [IO.Compression.CompressionLevel]::Optimal); $gz.Write($bytes, 0, $bytes.Length); $gz.Close(); $gzBytes = $ms.ToArray()
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory $OutDir | Out-Null }
[IO.File]::WriteAllBytes((Join-Path $OutDir 'pristine-world.bin'), $gzBytes)
$meta = [ordered]@{ Level = $b.Level; Records = ($added.base + $added.extra); FromFlight = $added.base; FromOtherSaves = $added.extra; Cells = $list.Count; Note = 'untouched ore / breakable / world-item records of the playable map; used by World reset when a world has no backup of an object' }
($meta | ConvertTo-Json) | Set-Content (Join-Path $OutDir 'pristine-world.json') -Encoding UTF8
Write-Host ("pristine-world.bin: {0} records in {1} cells ({2} from the flown world, {3} from other saves), {4} KB gzip; skipped: {5}" -f $meta.Records, $meta.Cells, $added.base, $added.extra, [int]($gzBytes.Length / 1KB), (($skipped.GetEnumerator() | % { "$($_.Value) $($_.Key)" }) -join '; '))
$pool = [ordered]@{}; foreach ($k in ($loot.Keys | Sort-Object)) { $pool[$k] = @($loot[$k]) }
($pool | ConvertTo-Json -Depth 3 -Compress) | Set-Content (Join-Path $OutDir 'loot-pool.json') -Encoding UTF8
Write-Host ("loot-pool.json: {0} loot groups, {1} distinct rolls, {2} KB" -f $pool.Count, (($pool.Values | ForEach-Object { $_.Count } | Measure-Object -Sum).Sum), [int]((Get-Item (Join-Path $OutDir 'loot-pool.json')).Length / 1KB))
