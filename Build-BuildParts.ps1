param(
  [string]$DataRoot = '',
  [string]$ItemsJson = (Join-Path $PSScriptRoot 'items.json')
)
. (Join-Path $PSScriptRoot 'Paths.ps1')
if (-not $DataRoot) { $DataRoot = PF-ExportPath 'Permafrost\Content\Permafrost\Blueprints\BuildingParts\Data' }
# Building parts (BuildPartConfig, DA_Build_*), read from FModel's JSON export (Mappings.usmap):
#   ID, Name, Description, Categories, MaxHealth, BuildCost_, ConstructionTime, DeconstructionRefund_, RepairCost_,
#   requirements (foundations / grid / roof / enclosed building / temperature), surface restriction, PickupItemName.
# Writes catalog\building-details.csv and, in items.json, 'buildPart' + the condition of placeable items:
# a placeable item's maximum condition is its build part's MaxHealth (checked: Tent 250, Candle 50, Oil Lamp 50 = what your saves showed).
# Run after Build-JsonSpecs.ps1.
$ErrorActionPreference = 'Stop'
$items = Get-Content $ItemsJson -Raw | ConvertFrom-Json; $idOf = @{}; foreach ($i in $items) { $idOf[$i.asset] = $i.id }
function AssetName($p) { if (-not $p) { return '' }; return ((([string]$p) -split '/')[-1] -replace '^.*\.', '') }
function ItemId([string]$a) { if ($idOf.ContainsKey($a)) { return $idOf[$a] }; return ($a -replace '^(DA|BP)_[A-Za-z]+?_', '' -replace '^(DA|BP)_', '') }
function Fmt($v) { if ($null -eq $v) { return '' }; if ($v -is [array]) { return ((@($v) | ForEach-Object { Fmt $_ }) -join '/') }; return ('{0:0.##}' -f [double]$v) }
function Cost($list) { return ((@($list) | Where-Object { $_ } | ForEach-Object { "$(ItemId (AssetName $_.Item.AssetPathName)) x$($_.Amount)" }) -join '; ') }

$rows = New-Object System.Collections.Generic.List[object]
foreach ($f in [IO.Directory]::EnumerateFiles($DataRoot, 'DA_Build_*.json', [IO.SearchOption]::AllDirectories)) {
  $name = [IO.Path]::GetFileNameWithoutExtension($f); $folder = ($f.Substring($DataRoot.Length + 1) -replace '\\[^\\]+$', '')
  $o = (Get-Content $f -Raw | ConvertFrom-Json) | Where-Object { $_.Properties } | Select-Object -First 1; if (-not $o) { continue }; $p = $o.Properties
  $req = @(); if ($p.bRequireFoundations) { $req += 'foundation' }; if ($p.bRequireGrid) { $req += "grid ($(([string]$p.GridType) -replace '^.*::', ''))" }; if ($p.bRequireRoof) { $req += 'roof' }
  if ($p.bRequireEnclosedBuilding) { $req += 'enclosed building' }; if ($p.bRequireProperTemperature) { $req += "temperature >= $($p.MinTemperatureRequired)" }
  $rows.Add([pscustomobject]@{ Asset = $name; Folder = $folder; ID = [string]$p.ID; Name = $(if ($p.Name) { [string]$p.Name.SourceString } else { '' }); Description = $(if ($p.Description) { [string]$p.Description.SourceString } else { '' })
      Category = [string]$p.Categories; MaxHealth = (Fmt $p.MaxHealth); BuildCost = (Cost $p.BuildCost_); ConstructionTime = (Fmt $p.ConstructionTime); Refund = (Cost $p.DeconstructionRefund_); RepairCost = (Cost $p.RepairCost_)
      Requires = ($req -join ', '); Surface = ([string]$p.SurfaceRestriction -replace '^.*::', ''); PickupItem = [string]$p.PickupItemName; Decays = [string]$p.bCanDecay; InBuildMenu = $(if ($null -eq $p.bShowInBuildMenu) { 'True' } else { [string]$p.bShowInBuildMenu }) }) }
$rows | Sort-Object Asset | Export-Csv (Join-Path $PSScriptRoot 'catalog\building-details.csv') -NoTypeInformation -Encoding UTF8

# join to items: build part ID or PickupItemName equal to the item's own game id
$byId = @{}; foreach ($r in $rows) { foreach ($k in @($r.ID, $r.PickupItem)) { if ($k -and -not $byId.ContainsKey($k)) { $byId[$k] = $r } } }
$set = 0; $notes = @()
foreach ($it in $items) { $k = if ($it.jsonId) { $it.jsonId } else { $it.id }; $bp = $byId[$k]
  if ($bp) { $it | Add-Member -Force buildPart $bp.Asset
    if ($bp.MaxHealth -and -not $it.durMax) { $v = [double]$bp.MaxHealth
      if ($it.maxCondition -and [math]::Abs([double]$it.maxCondition - $v) -gt 0.5) { $notes += "$($it.id): was $($it.maxCondition) ($($it.condSource)), build part says $v" }
      $it.maxCondition = $v; $it.condSource = 'game data'; if ($it.category -ne 'Traps') { $it.defaultCondition = $v }; $set++ } } }
$items | ConvertTo-Json -Depth 6 | Set-Content $ItemsJson -Encoding utf8
"build parts: $($rows.Count) | items joined to a build part: $(@($items | Where-Object { $_.buildPart }).Count) | condition set from MaxHealth: $set"
$notes
