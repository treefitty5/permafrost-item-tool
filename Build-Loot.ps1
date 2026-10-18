param(
  [string]$BlueprintsRoot = '',
  [string]$ItemsJson = (Join-Path $PSScriptRoot 'items.json')
)
. (Join-Path $PSScriptRoot 'Paths.ps1')
if (-not $BlueprintsRoot) { $BlueprintsRoot = PF-ExportPath 'Permafrost\Content\Permafrost\Blueprints' }
# Loot tables, read from FModel's JSON export (made with Mappings.usmap: every field has its real name).
# Writes catalog\loot-items.csv (one row per entry) and catalog\loot-links.csv (who uses which list).
#
# Classes under Items\LootConfigs and what they hold:
#   LootConfig_RandomList      RandomItemsList : Item, SpawnWeight, AmountRange, bRandomizeDurability, RandomDurabilityRange
#   LootConfig                 StaticLoot (always given: Item, AmountRange, bOverrideDurability, OverrideDurabilityValue)
#                              RandomLoot (references to RandomLists; a list named N times is rolled N times)
#   SingleResourceLootConfig   Loot : Item, AmountRange          (ores / destructibles)
#   LootFilterConfig           AllowedItems
#   CharacterEquipmentConfig   StartingEquipment (slot -> item), SpecialItems, StaticLoot, RandomLoot, RecipesToLearn
#   CharacterClassConfig       ClassName, ClassDescription, EquipmentConfig
# Amounts are shown as intervals: [a, b) = a included, b excluded (the bound types are stored in the file). Where a file stores no bound
# types (ore loot) the interval is shown as 'a .. b'.
# Other assets (containers, NPCs, world items) point at a loot config with a soft reference; those links come from each asset's name map / import table.
$ErrorActionPreference = 'Stop'
$src = Get-Content (Join-Path $PSScriptRoot 'Build-Catalog.ps1') -Raw
$m = [regex]::Match($src, 'function Get-NameMap.*?\r?\n\}\r?\n', 'Singleline'); Invoke-Expression $m.Value
$items = Get-Content $ItemsJson -Raw | ConvertFrom-Json
$idOf = @{}; foreach ($i in $items) { $idOf[$i.asset] = $i.id }
function AssetName($p) { if (-not $p) { return '' }; return ((([string]$p) -split '/')[-1] -replace '^.*\.', '') }
function ItemId([string]$a) { if ($idOf.ContainsKey($a)) { return $idOf[$a] }; return ($a -replace '^(DA|BP)_[A-Za-z]+?_', '' -replace '^(DA|BP)_', '') }
function Fmt($v) { if ($null -eq $v) { return '' }; return ('{0:0.##}' -f [double]$v) }
function Interval($r) {
  if (-not $r) { return '' }; $lo = $r.LowerBound; $up = $r.UpperBound
  if (($lo -and $lo.Type) -or ($up -and $up.Type)) {
    $a = if ($lo.Type -match 'Inclusive') { '[' } elseif ($lo.Type -match 'Exclusive') { '(' } else { '[' }
    $b = if ($up.Type -match 'Inclusive') { ']' } elseif ($up.Type -match 'Exclusive') { ')' } else { ']' }
    return "$a$($lo.Value), $($up.Value)$b" }
  return "$($lo.Value) .. $($up.Value)" }
function Read-NameBatch([byte[]]$b, [int]$off) {
  $cnt = [BitConverter]::ToUInt32($b, $off); $hdr = $off + 16 + $cnt * 8; $sp = $hdr + $cnt * 2; $names = New-Object System.Collections.Generic.List[string]
  for ($i = 0; $i -lt $cnt; $i++) { $h0 = $b[$hdr + $i * 2]; $h1 = $b[$hdr + $i * 2 + 1]; $len = (($h0 -band 0x7F) -shl 8) -bor $h1
    if (($h0 -band 0x80) -ne 0) { $names.Add([Text.Encoding]::Unicode.GetString($b, $sp, $len * 2)); $sp += $len * 2 } else { $names.Add([Text.Encoding]::ASCII.GetString($b, $sp, $len)); $sp += $len } }
  return , $names }
function Get-ZenImports([byte[]]$b) {
  $impMapOff = [BitConverter]::ToInt32($b, 28); $expMapOff = [BitConverter]::ToInt32($b, 32); $pkgNamesOff = [BitConverter]::ToInt32($b, 48)
  $pk = Read-NameBatch $b $pkgNamesOff; $n = [int](($expMapOff - $impMapOff) / 8); $res = @()
  for ($i = 0; $i -lt $n; $i++) { $v = [BitConverter]::ToUInt64($b, $impMapOff + $i * 8); $type = [int]($v -shr 62)
    if ($type -eq 2) { $pi = [int](($v -shr 32) -band 0x3FFFFFFF); $res += $(if ($pi -lt $pk.Count) { $pk[$pi] } else { '' }) } else { $res += '' } }
  return , $res }

$lootRoot = Join-Path $BlueprintsRoot 'Items\LootConfigs'
$rows = New-Object System.Collections.Generic.List[object]; $links = New-Object System.Collections.Generic.List[object]; $classes = @{}
foreach ($f in [IO.Directory]::EnumerateFiles($lootRoot, '*.json', [IO.SearchOption]::AllDirectories)) {
  $name = [IO.Path]::GetFileNameWithoutExtension($f); $folder = ($f.Substring($lootRoot.Length + 1) -replace '\\[^\\]+$', '')
  $o = (Get-Content $f -Raw | ConvertFrom-Json) | Where-Object { $_.Properties } | Select-Object -First 1; if (-not $o) { continue }
  $pr = $o.Properties; $cls = [string]$o.Type; $classes[$name] = $cls
  function AddRow($section, $asset, $weight, $amount, $dur, $note) { $script:rows.Add([pscustomobject]@{ List = $name; Folder = $folder; Class = $cls; Section = $section; Item = (ItemId $asset); Asset = $asset; Weight = $weight; Amount = $amount; Durability = $dur; Note = $note }) }
  foreach ($e in @($pr.RandomItemsList)) { if (-not $e) { continue }
    $dur = if ($e.bRandomizeDurability) { 'random ' + (Interval $e.RandomDurabilityRange) } else { '' }
    AddRow 'RandomItemsList' (AssetName $e.Item.AssetPathName) (Fmt $e.SpawnWeight) (Interval $e.AmountRange) $dur '' }
  foreach ($e in @($pr.StaticLoot)) { if (-not $e) { continue }
    $dur = if ($e.bOverrideDurability) { "fixed $($e.OverrideDurabilityValue)" } else { '' }
    AddRow 'StaticLoot' (AssetName $e.Item.AssetPathName) '' (Interval $e.AmountRange) $dur '' }
  if ($pr.Loot) { AddRow 'Loot' (AssetName $pr.Loot.Item.AssetPathName) '' (Interval $pr.Loot.AmountRange) '' '' }
  foreach ($e in @($pr.AllowedItems)) { if ($e) { AddRow 'AllowedItems' (AssetName $e.AssetPathName) '' '' '' '' } }
  foreach ($e in @($pr.StartingEquipment)) { if ($e) { AddRow 'StartingEquipment' (AssetName $e.Value.AssetPathName) '' '' '' "slot $($e.Key)" } }
  foreach ($e in @($pr.SpecialItems)) { if ($e -and $e.AssetPathName) { AddRow 'SpecialItems' (AssetName $e.AssetPathName) '' '' '' '' } }
  foreach ($e in @($pr.RecipesToLearn)) { if ($e) { AddRow 'RecipesToLearn' (AssetName $e.AssetPathName) '' '' '' 'learns this recipe' } }
  # list -> list references (RandomLoot): count = how many times it is rolled
  $cnt = @{}; foreach ($e in @($pr.RandomLoot)) { if ($e -and $e.ObjectName) { $t = ([string]$e.ObjectName -replace "^.*'(.*)'$", '$1'); $cnt[$t] = 1 + [int]$cnt[$t] } }
  foreach ($t in $cnt.Keys) { $links.Add([pscustomobject]@{ From = $name; FromFolder = $folder; To = $t; ToPath = ''; Refs = $cnt[$t] }) }
  if ($pr.EquipmentConfig -and $pr.EquipmentConfig.AssetPathName) { $links.Add([pscustomobject]@{ From = $name; FromFolder = $folder; To = (AssetName $pr.EquipmentConfig.AssetPathName); ToPath = ''; Refs = 1 }) }
  if ($cls -eq 'CharacterClassConfig' -and $pr.ClassName) { AddRow 'ClassDefinition' '' '' '' '' ("$($pr.ClassName.SourceString): $($pr.ClassDescription.SourceString)".Trim()) } }

# ---- every other game asset that points at a loot config (containers, NPCs, world items, quests ...)
$sw = [Diagnostics.Stopwatch]::StartNew(); $scanned = 0
foreach ($f in [IO.Directory]::EnumerateFiles($BlueprintsRoot, '*.uasset', [IO.SearchOption]::AllDirectories)) {
  if ($f.StartsWith($lootRoot, [StringComparison]::OrdinalIgnoreCase)) { continue }
  $scanned++; $b = [IO.File]::ReadAllBytes($f)
  if ([Text.Encoding]::Latin1.GetString($b).IndexOf('/LootConfigs/', [StringComparison]::Ordinal) -lt 0) { continue }
  $name = [IO.Path]::GetFileNameWithoutExtension($f); $nm = Get-NameMap $f; $targets = @{}
  if ($nm) { foreach ($x in $nm) { if ($x -match '/LootConfigs/') { $targets[$x] = 1 } } }
  try { foreach ($x in (Get-ZenImports $b)) { if ($x -match '/LootConfigs/') { $targets[$x] = 1 } } } catch { }
  $kind = if ($f -match '\\Interactions\\Containers\\') { 'Container' } else { 'Asset' }
  foreach ($p in ($targets.Keys | Sort-Object)) { $links.Add([pscustomobject]@{ From = $name; FromFolder = $kind; To = (($p -split '/')[-1] -replace '^.*\.', ''); ToPath = $p; Refs = '' }) } }

$rows | Export-Csv -Path (Join-Path $PSScriptRoot 'catalog\loot-items.csv') -NoTypeInformation -Encoding UTF8
$links | Export-Csv -Path (Join-Path $PSScriptRoot 'catalog\loot-links.csv') -NoTypeInformation -Encoding UTF8
"scanned $scanned other assets in $([int]$sw.Elapsed.TotalSeconds)s | loot files: $($classes.Count) | entries: $($rows.Count) in $(@($rows | Select-Object -ExpandProperty List -Unique).Count) lists | links: $($links.Count)"
