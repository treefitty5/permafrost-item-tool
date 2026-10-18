param(
  [string]$ItemsRoot = '',
  [string]$ItemsJson = (Join-Path $PSScriptRoot 'items.json')
)
. (Join-Path $PSScriptRoot 'Paths.ps1')
if (-not $ItemsRoot) { $ItemsRoot = PF-ExportPath 'Permafrost\Content\Permafrost\Blueprints\Items' }
# Crafting recipes, read from FModel's JSON export (made with Mappings.usmap, so the fields have their real names):
#   Cost = ingredients with amounts, Result = what is made and how many, Time = crafting time (seconds), Type = the station that crafts it,
#   Category, plus the in-game name / description.
# Writes catalog\recipe-details.csv and adds a 'recipe' text and the exact 'Craft' source to items.json.
# Checked 2026-10-18: all 176 recipes gave exactly the same ingredients, amounts and results as the earlier byte-level decoder.
# Run AFTER Build-Catalog.ps1 and BEFORE Build-Specs.ps1.
$ErrorActionPreference = 'Stop'
$items = Get-Content $ItemsJson -Raw | ConvertFrom-Json
$idOf = @{}; foreach ($i in $items) { $idOf[$i.asset] = $i.id }
function AssetName($p) { if (-not $p) { return '' }; return ((([string]$p) -split '/')[-1] -replace '^.*\.', '') }
function ItemId([string]$a) { if ($idOf.ContainsKey($a)) { return $idOf[$a] }; return ($a -replace '^(DA|BP)_[A-Za-z]+?_', '' -replace '^(DA|BP)_', '') }
function Fmt($v) { if ($null -eq $v) { return '' }; return ('{0:0.##}' -f [double]$v) }
$station = @{ ECT_CraftingBench = 'Crafting bench'; ECT_WeaponsBench = 'Weapons bench'; ECT_TailoringBench = 'Tailoring bench'; ECT_TanningRack = 'Tanning rack'; ECT_StoneFurnace = 'Stone furnace'; ECT_MakeshiftSmelter = 'Makeshift smelter'; ECT_ProfessionalSmelter = 'Professional smelter'; ECT_Player = 'By hand' }

$rows = New-Object System.Collections.Generic.List[object]
foreach ($f in [IO.Directory]::EnumerateFiles($ItemsRoot, 'DA_CraftingRecipe_*.json', [IO.SearchOption]::AllDirectories)) {
  $name = [IO.Path]::GetFileNameWithoutExtension($f)
  $o = (Get-Content $f -Raw | ConvertFrom-Json) | Where-Object { $_.Properties } | Select-Object -First 1; if (-not $o) { continue }; $pr = $o.Properties
  $cost = @($pr.Cost); $res = @($pr.Result)
  $st = (@($pr.Type) | ForEach-Object { $k = ([string]$_ -replace '^.*::', ''); if ($station.ContainsKey($k)) { $station[$k] } else { $k } }) -join ' / '
  $cat = (@($pr.Category) | ForEach-Object { ([string]$_ -replace '^.*::ECT_', '') }) -join ' / '
  $rows.Add([pscustomobject]@{
      Recipe = $name; ResultAsset = (AssetName $res[0].Item.AssetPathName); Result = (ItemId (AssetName $res[0].Item.AssetPathName)); ResultAmount = $res[0].Amount
      AllResults = ((@($res) | ForEach-Object { "$(ItemId (AssetName $_.Item.AssetPathName)) x$($_.Amount)" }) -join '; ')
      Ingredients = ((@($cost) | ForEach-Object { "$(ItemId (AssetName $_.Item.AssetPathName)) x$($_.Amount)" }) -join '; ')
      IngredientAssets = ((@($cost) | ForEach-Object { "$(AssetName $_.Item.AssetPathName) x$($_.Amount)" }) -join '; ')
      Time = (Fmt $pr.Time); Station = $st; Category = $cat
      Name = $(if ($pr.Name) { [string]$pr.Name.SourceString } else { '' }); Description = $(if ($pr.Description) { [string]$pr.Description.SourceString } else { '' }) }) }
$rows | Sort-Object Recipe | Export-Csv -Path (Join-Path $PSScriptRoot 'catalog\recipe-details.csv') -NoTypeInformation -Encoding UTF8

$by = @{}; foreach ($r in $rows) { if (-not $by.ContainsKey($r.ResultAsset)) { $by[$r.ResultAsset] = @() }; $by[$r.ResultAsset] += $r }
foreach ($i in $items) {
  $txt = ''; if ($by.ContainsKey($i.asset)) { $txt = (($by[$i.asset] | ForEach-Object { "$($_.Ingredients) => makes $($_.ResultAmount)" + $(if ($_.Station -or $_.Time) { " ($($_.Station)$(if ($_.Time) { ', ' + $_.Time + 's' }))" } else { '' }) }) -join '  |  ') }
  $i | Add-Member -Force recipe $txt }
$items | ConvertTo-Json -Depth 6 | Set-Content $ItemsJson -Encoding utf8
"recipes: $($rows.Count) | items with a recipe: $(@($items | Where-Object { $_.recipe }).Count) | recipes with several results: $(@($rows | Where-Object { $_.AllResults -match ';' }).Count)"
