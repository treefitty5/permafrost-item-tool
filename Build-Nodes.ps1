param(
  [string]$BlueprintsRoot = ''
)
. (Join-Path $PSScriptRoot 'Paths.ps1')
if (-not $BlueprintsRoot) { $BlueprintsRoot = PF-ExportPath 'Permafrost\Content\Permafrost\Blueprints' }
# Harvestable world objects (boulders / ores, trees, bushes, pallets, rubble...), read from FModel's JSON export.
# Writes catalog\resource-nodes.csv: Class (as in the save: BP_xxx_C), Kind, Name, MaxHealth, RequiredTool, Tier, ProgressiveLoot, FinalLoot.
# The world reset uses MaxHealth to put a partly mined boulder back to full.
$ErrorActionPreference = 'Stop'
function AssetName($p) { if (-not $p) { return '' }; return ((([string]$p) -split '/')[-1] -replace '^.*\.', '') }
$rows = New-Object System.Collections.Generic.List[object]
foreach ($sub in 'Destructable\DestructableBlueprints', 'Interactions\Scavengable') {
  $root = Join-Path $BlueprintsRoot $sub
  foreach ($f in [IO.Directory]::EnumerateFiles($root, 'BP_*.json', [IO.SearchOption]::AllDirectories)) {
    $name = [IO.Path]::GetFileNameWithoutExtension($f)
    $objs = Get-Content $f -Raw | ConvertFrom-Json
    $d = $objs | Where-Object { $_.Name -eq "Default__$($name)_C" -and $_.Properties } | Select-Object -First 1
    if (-not $d) { continue }; $p = $d.Properties
    if ($null -eq $p.MaxHealth) { continue }
    $kind = if ($name -match 'ScavengableTree') { 'tree' } elseif ($name -match 'Bush') { 'bush' } elseif ($name -match 'Boulder') { 'boulder' } else { 'destructible' }
    $rows.Add([pscustomobject]@{ Class = "$($name)_C"; Kind = $kind; Name = $(if ($p.Name) { [string]$p.Name.SourceString } else { '' }); MaxHealth = [double]$p.MaxHealth
        RequiredTool = ([string]$p.'Required Tool' -replace '^.*::', ''); Tier = ([string]$p.'Required Tool Tier' -replace '^.*::', '')
        ProgressiveLoot = (AssetName $p.'Progressive Loot'.AssetPathName); FinalLoot = (AssetName $p.'Final Loot'.AssetPathName); Folder = ($f.Substring($root.Length + 1) -replace '\\[^\\]+$', '') }) } }
$rows | Sort-Object Kind, Class | Export-Csv (Join-Path $PSScriptRoot 'catalog\resource-nodes.csv') -NoTypeInformation -Encoding UTF8
Write-Host "resource-nodes.csv: $($rows.Count) classes ($((($rows | Group-Object Kind | ForEach-Object { "$($_.Name) $($_.Count)" }) -join ', ')))"
