param(
  [string]$ItemsRoot = '',
  [string]$ItemsJson = (Join-Path $PSScriptRoot 'items.json')
)
. (Join-Path $PSScriptRoot 'Paths.ps1')
if (-not $ItemsRoot) { $ItemsRoot = PF-ExportPath 'Permafrost\Content\Permafrost\Blueprints\Items\DataAsset_Items' }
# Reads the item data straight from FModel's JSON export (made with Mappings.usmap, so every field has its real name) and adds to items.json:
#   display (the in-game name), description, jsonId (the game's own item id), stackAmount, durInitial / durMax / durPerUse, damage, ...
# and then makes the JSON the source of truth for: stack size, max condition, start condition, item id.
# Run AFTER Build-Catalog / Build-Recipes / Build-Specs / Build-Rewards (it overrides their guesses with the game's own numbers).
$ErrorActionPreference = 'Stop'
$items = Get-Content $ItemsJson -Raw | ConvertFrom-Json
$map = @{}; foreach ($f in [IO.Directory]::EnumerateFiles($ItemsRoot, '*.json', [IO.SearchOption]::AllDirectories)) { $map[[IO.Path]::GetFileNameWithoutExtension($f)] = $f }
$idOf = @{}; foreach ($i in $items) { $idOf[$i.asset] = $i.id }
function AssetName($p) { if (-not $p) { return '' }; $s = [string]$p; if ($s -match '^\{') { return '' }; return (($s -split '/')[-1] -replace '^.*\.', '') }
function ItemId([string]$a) { if ($idOf.ContainsKey($a)) { return $idOf[$a] }; return ($a -replace '^(DA|BP)_[A-Za-z]+?_', '' -replace '^(DA|BP)_', '') }
function Num($v) { if ($null -eq $v) { return $null }; return [double]$v }
function Fmt($v) { if ($null -eq $v) { return '' }; if ($v -is [array]) { return ((@($v) | ForEach-Object { Fmt $_ }) -join '/') }; return ('{0:0.##}' -f [double]$v) }

$stat = @{ matched = 0; stackSet = 0; condSet = 0; idFixed = 0; named = 0 }; $notes = @()
foreach ($it in $items) {
  $p = $map[$it.asset]; if (-not $p) { continue }
  $t = Get-Content $p -Raw | ConvertFrom-Json
  $o = $t | Where-Object { $_.Properties -and ($_.Type -match 'Config|Data_ProjectileProperties') } | Select-Object -First 1; if (-not $o) { continue }
  $pr = $o.Properties; $stat.matched++
  $add = @{}
  $add.display = if ($pr.Name -and $pr.Name.SourceString) { [string]$pr.Name.SourceString } else { '' }
  $add.description = if ($pr.Description -and $pr.Description.SourceString) { [string]$pr.Description.SourceString } else { '' }
  $add.jsonId = [string]$pr.AssetRegistrySearchableTag; $add.itemClass = [string]$o.Type
  if ($pr.StackableConfig) { $add.stackAmount = $(if ($null -ne $pr.StackableConfig.StackAmount) { [int]$pr.StackableConfig.StackAmount } else { 1 }) }
  $d = $pr.DurabilityConfig
  if ($d -and $null -ne $d.MaximumValue) { $add.durInitial = Num $d.InitialValue; $add.durMax = Num $d.MaximumValue; $add.durPerUse = Num $d.DurabilityCostPerUse
    $add.repair = (@($d.RepairCost | ForEach-Object { "$(ItemId (AssetName $_.Key)) x$($_.Value.X)-$($_.Value.Y)" }) -join '; ')
    if ($d.DurabilityOverTime) { $add.decay = "$(Fmt $d.DurabilityOverTime.Damage) per $(Fmt $d.DurabilityOverTime.Frequency)s" } }
  if ($pr.Damage) { $add.damage = $(if ($pr.Damage.X -eq $pr.Damage.Y) { Fmt $pr.Damage.X } else { "$(Fmt $pr.Damage.X)-$(Fmt $pr.Damage.Y)" }) }
  if ($pr.DamageType) { $add.damageType = ([string]$pr.DamageType -replace '^.*::', '') }
  if ($null -ne $pr.PowerAttackDamageMultiplier) { $add.powerAttack = Num $pr.PowerAttackDamageMultiplier }
  if ($null -ne $pr.StaminaCost) { $add.stamina = Num $pr.StaminaCost }
  if ($pr.ToolType) { $add.tool = (([string]$pr.ToolType -replace '^.*::ETT_', '') + $(if ($pr.ToolTier) { ' / ' + ([string]$pr.ToolTier -replace '^.*::ETT_', '') } else { '' })) }
  if ($null -ne $pr.MagazineSize) { $add.magazine = [int]$pr.MagazineSize }
  if ($null -ne $pr.FireRate) { $add.fireRate = Num $pr.FireRate }
  if ($pr.AllowedAmmoTypes) { $add.ammoTypes = (@($pr.AllowedAmmoTypes) | ForEach-Object { $a = $_; if ($a.AssetPathName) { ItemId (AssetName $a.AssetPathName) } else { ItemId (AssetName $a) } }) -join '; ' }
  if ($pr.TradingConfig -and $null -ne $pr.TradingConfig.BaseValue) { $add.tradeValue = [int]$pr.TradingConfig.BaseValue }
  if ($pr.RecyclingConfig -and $pr.RecyclingConfig.OutputItems) { $add.recycle = ((@($pr.RecyclingConfig.OutputItems) | ForEach-Object { "$(ItemId (AssetName $_.Item.AssetPathName)) x$($_.Amount)" }) -join '; ') }
  if ($pr.DetailsEquipmentArmor) { $add.armor = ((@($pr.DetailsEquipmentArmor) | ForEach-Object { "$($_.Key) $($_.Value)" }) -join ', ') }
  if ($null -ne $pr.DamageReductionPercentage) { $add.damageReduction = Num $pr.DamageReductionPercentage }
  if ($pr.ItemEffectData) { $ef = @(@($pr.ItemEffectData) | Where-Object { $_.Tag -and $_.Tag.TagName } | ForEach-Object { (($_.Tag.TagName -split '\.')[-1]) + ' ' + (Fmt $_.Value) }); if ($ef.Count) { $add.effect = $ef -join ', ' } }
  if ($pr.AttributeRestorationMap) { $add.restores = ((@($pr.AttributeRestorationMap) | ForEach-Object { "$((($_.Key.TagName) -split '\.')[-1]) +$(Fmt $_.Value)" }) -join ', ') }
  if ($it.category -eq 'Clothing' -and $pr.bCanContainsItems -and $pr.ContainerDimensions) { $add.containerSlots = [int]$pr.ContainerDimensions.X * [math]::Max(1, [int]$pr.ContainerDimensions.Y) }   # backpack / pocket capacity (checked: Utility 25, Scavenger 35 = what you set)
  if ($pr.ContainerDimensions) { $add.slotSize = "$($pr.ContainerDimensions.X)x$($pr.ContainerDimensions.Y)" }
  foreach ($k in $add.Keys) { $it | Add-Member -Force $k $add[$k] }
  if ($add.display) { $stat.named++ }
  # --- the game's own numbers replace the earlier decoded / guessed ones
  if ($null -ne $add.stackAmount) { if ([int]$it.stackSize -ne $add.stackAmount) { $notes += "stack $($it.id): was $($it.stackSize) ($($it.stackSource)) now $($add.stackAmount)" }; $it.stackSize = $add.stackAmount; $it.stackSource = 'game data'; $stat.stackSet++ }
  if ($null -ne $add.durMax) { $it.maxCondition = $add.durMax; $it.condSource = 'game data'; if ($it.category -ne 'Traps') { $it.defaultCondition = $add.durInitial }; $stat.condSet++ }   # traps: the data says 100 but every trap in your saves holds 1, so their add-default stays what the saves show
  if ($add.jsonId -and $add.jsonId -ne $it.id) { $notes += "id $($it.id) -> $($add.jsonId)"; $it.id = $add.jsonId; $it.confidence = 'exact'; $it.candidates = @($add.jsonId); $stat.idFixed++ }
}
$items | ConvertTo-Json -Depth 6 | Set-Content $ItemsJson -Encoding utf8
"items matched to JSON: $($stat.matched) of $($items.Count) | with in-game name: $($stat.named) | stack set from JSON: $($stat.stackSet) | condition set from JSON: $($stat.condSet) | ids corrected: $($stat.idFixed)"
$notes
