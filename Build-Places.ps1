# Build-Places.ps1 - builds catalog\places.csv: the game's named places and fast-travel points with their world coordinates, for the Teleport tab.
#
# Positions come from the game's own level data (FModel export of Maps\PF_Worldmap_v2.umap): every named place is a 'BP_WorldLocationArea_Spline_C' actor,
# every fast-travel point a 'FastTravelDestination' actor; their transform is read with MapCore.ps1.
# The in-game NAMES are not stored next to those actors in a form we can read, so the first build matched each actor by position against the
# community N0M4D / MetaBot map (-NamesFrom <...\N0M4DLiveMap\dist\data\map.json>); later builds keep the names already in places.csv (an actor within 2 m).
# New actors with no known name are written as 'Unnamed place'.
#
# Usage:  pwsh -File .\Build-Places.ps1 [-NamesFrom <map.json>]
param([string]$NamesFrom = '', [string]$Umap = '')
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Paths.ps1'); . (Join-Path $PSScriptRoot 'MapCore.ps1')
if (-not $Umap) { $Umap = Join-Path (PF-ExportRoot) 'Permafrost\Content\Permafrost\Maps\PF_Worldmap_v2.umap' }
$out = Join-Path $PSScriptRoot 'catalog\places.csv'
$inv = [Globalization.CultureInfo]::InvariantCulture
$known = @(); if (Test-Path $out) { $known = @(Import-Csv $out) }
# N0M4D map: map pixel -> game centimetres (the app's own alignment: px = 0.013433912758 * cm + 1962.694653985, both axes)
$ref = @(); if ($NamesFrom) {
  $j = Get-Content $NamesFrom -Raw | ConvertFrom-Json; $cat = @{}; foreach ($c in $j.categories) { $cat[$c.id] = $c }
  $ref = @(foreach ($m in $j.markers) { $g = $cat[$m.category].group; if ($g -in 'Places', 'Travel') { [pscustomobject]@{ Name = [string]$m.name; Group = $g; X = ($m.x - 1962.694653985) / 0.013433912758; Y = ($m.y - 1962.694653985) / 0.013433912758 } } }) }
function Find-Name($x, $y, $group, [double]$rad) {
  foreach ($k in $known) { if ($k.Kind -eq $group -and [math]::Sqrt(([double]$k.X - $x) * ([double]$k.X - $x) + ([double]$k.Y - $y) * ([double]$k.Y - $y)) -le 200) { return $k.Name -replace ' \(\d+\)$', '' } }
  $best = $null; $bd = 1e18; foreach ($r in $ref) { if ($r.Group -ne $(if ($group -eq 'Fast travel') { 'Travel' } else { 'Places' })) { continue }; $d = ($r.X - $x) * ($r.X - $x) + ($r.Y - $y) * ($r.Y - $y); if ($d -lt $bd) { $bd = $d; $best = $r } }
  if ($best -and [math]::Sqrt($bd) -le $rad) { return $best.Name }; return $null }
$rows = New-Object System.Collections.Generic.List[object]
foreach ($a in [MapCells]::Read($Umap)) {
  $k = $a.Name -replace '_UAID_[0-9A-F]+(_\d+)?(_[0-9a-f]{16})?$', '' -replace '_\d+$', ''
  if (-not $a.HasTransform) { continue }
  if ($k -eq 'BP_WorldLocationArea_Spline_C') { $n = Find-Name $a.X $a.Y 'Named place' 500; $rows.Add([pscustomobject]@{ Name = $(if ($n) { $n } else { 'Unnamed place' }); Kind = 'Named place'; X = [int][math]::Round($a.X); Y = [int][math]::Round($a.Y); Z = [int][math]::Round($a.Z) }) }
  elseif ($k -eq 'FastTravelDestination') { $n = Find-Name $a.X $a.Y 'Fast travel' 2000; if ($n -and $n -in 'Church', "Crow's Nest", 'Horizon', 'Solar Fields', 'The Last Stand') { $rows.Add([pscustomobject]@{ Name = $n; Kind = 'Fast travel'; X = [int][math]::Round($a.X); Y = [int][math]::Round($a.Y); Z = [int][math]::Round($a.Z) }) } }
}
# readable names, and a number for places that share a name (west to east)
$fix = @{ 'HotSpringsCave' = 'Hot Springs Cave'; 'Named place' = 'Unnamed place' }
foreach ($r in $rows) { if ($fix.ContainsKey($r.Name)) { $r.Name = $fix[$r.Name] }; $r.Name = $r.Name.Replace([string][char]0x2019, "'") }
$final = New-Object System.Collections.Generic.List[object]
foreach ($g in ($rows | Group-Object Kind, Name)) { $items = @($g.Group | Sort-Object X, Y); $i = 0; foreach ($it in $items) { $i++; $nm = if ($items.Count -gt 1) { "$($it.Name) ($i)" } else { $it.Name }; $final.Add([pscustomobject]@{ Name = $nm; Kind = $it.Kind; X = $it.X; Y = $it.Y; Z = $it.Z }) } }
$final | Sort-Object Kind, Name | Export-Csv $out -NoTypeInformation -Encoding UTF8
"places.csv: $($final.Count) rows ($(@($final | Where-Object { $_.Kind -eq 'Named place' }).Count) named places, $(@($final | Where-Object { $_.Kind -eq 'Fast travel' }).Count) fast travel)"
