param(
  [string]$ExportRoot = '',
  [string]$BuildRoot = '',
  [string]$ItemsJson = (Join-Path $PSScriptRoot 'items.json')
)
. (Join-Path $PSScriptRoot 'Paths.ps1')
if (-not $ExportRoot) { $ExportRoot = PF-ExportPath 'Permafrost\Content\Permafrost\Blueprints\Items\DataAsset_Items' }
if (-not $BuildRoot) { $BuildRoot = PF-ExportPath 'Permafrost\Content\Permafrost\Blueprints\BuildingParts\Data\Default' }
# Adds specs to items.json (run AFTER Build-Catalog.ps1 and Build-DataCatalog.ps1):
#   maxCondition / condSource  - the item's maximum condition. Read from the game data for clothing and the weapons that carry the marker
#                                (checked against your saves: every clothing match was exact; weapons 22 of 23 consistent), else the highest value seen in your saves.
#   sources                    - where the game files link the item: Loot, Pickup, Craft, Quest, Trader, Animal (which files mention it; chances are unknown).
#   defaultCondition           - becomes the real maximum when it came from the game data (new items are added at full condition).
$ErrorActionPreference = 'Stop'
$items = Get-Content $ItemsJson -Raw | ConvertFrom-Json
$files = @{}; foreach ($f in [IO.Directory]::EnumerateFiles($ExportRoot, '*.uasset', [IO.SearchOption]::AllDirectories)) { $files[[IO.Path]::GetFileNameWithoutExtension($f)] = $f }
$markers = @{ Clothing = [byte[]](0x02, 0x01, 0x09, 0x01); Weapons = [byte[]](0x04, 0x01, 0x03, 0x01) }
function Read-After([byte[]]$b, [byte[]]$m, [int]$from) {
  for ($p = $from; $p -le $b.Length - $m.Length - 4; $p++) { $ok = $true; for ($k = 0; $k -lt $m.Length; $k++) { if ($b[$p + $k] -ne $m[$k]) { $ok = $false; break } }; if ($ok) { return [BitConverter]::ToSingle($b, $p + $m.Length + 4) } }   # two floats follow the marker; they are equal in 153 of 154 files. MoonRockPickaxe has 160 then 250 and your save holds 250, so the SECOND one is the maximum.
  return $null
}
# Second layout: the max condition is stored twice in a row as equal whole-number floats (backpacks, bows, firearms, food/medkits, a few clothing pieces without the marker).
# Checked against the marker: same value in 153 of 154 files, 0 differ; also equals every value previously seen only in your saves (consumables 25/25, backpacks, guns).
# When a file holds several such pairs (Weapon_Buria also has an unrelated 8,8) the one right after the float 5.0 (00 00 A0 40) is the condition.
function Read-Pair([byte[]]$b) {
  $found = @(); $after5 = @(); $hs = [BitConverter]::ToUInt32($b, 4)
  for ($p = $hs + 4; $p -le $b.Length - 8; $p++) { $a = [BitConverter]::ToSingle($b, $p)
    if ($a -ge 2 -and $a -le 5000 -and $a -eq [math]::Floor($a) -and $a -eq [BitConverter]::ToSingle($b, $p + 4)) {
      $found += $a; if ([BitConverter]::ToSingle($b, $p - 4) -eq 5.0) { $after5 += $a } } }
  if ($found.Count -eq 1) { return $found[0] }
  if ($after5.Count -eq 1) { return $after5[0] }
  return $null
}
# Placeable items keep their max condition in their building-part file (DA_Build_*), as a whole number at a fixed spot. Each value equals what your saves show.
$buildCond = @{ 'DA_Accessory_Tent_' = @('DA_Build_Tent', 141); 'DA_Accessory_Candle' = @('DA_Build_Candle', 135); 'DA_Accessory_OilLamp_' = @('DA_Build_OilLamp', 131) }
function Norm([string]$s) { ($s.ToLower() -replace '[^a-z0-9]', '') }

# ---- where is each item mentioned (from the catalog CSVs)
$cat = Join-Path $PSScriptRoot 'catalog'
$tableLabel = [ordered]@{ 'loot-configs' = 'Loot'; 'containers' = 'Loot'; 'world-items' = 'Pickup'; 'reward-pools' = 'Quest'; 'npcs' = 'Trader'; 'animals' = 'Animal' }
$src = @{}
foreach ($t in $tableLabel.Keys) { $p = Join-Path $cat "$t.csv"; if (-not (Test-Path -LiteralPath $p)) { continue }
  foreach ($r in (Import-Csv $p)) { foreach ($id in ($r.Items -split ';' | Where-Object { $_ })) { if (-not $src.ContainsKey($id)) { $src[$id] = New-Object System.Collections.Generic.HashSet[string] }; [void]$src[$id].Add($tableLabel[$t]) } } }
# quests: only count items a quest names directly and no pool covers
$qp = Join-Path $cat 'quests.csv'; if (Test-Path -LiteralPath $qp) { foreach ($r in (Import-Csv $qp)) { foreach ($id in ($r.Items -split ';' | Where-Object { $_ })) { if (-not $src.ContainsKey($id)) { $src[$id] = New-Object System.Collections.Generic.HashSet[string] }; [void]$src[$id].Add('Quest') } } }
# crafting: a recipe counts when its name matches the item (recipes also name ingredients, so mere mentions are ignored)
$recipes = @(); $rp = Join-Path $cat 'crafting-recipes.csv'; if (Test-Path -LiteralPath $rp) { $recipes = @(Import-Csv $rp | ForEach-Object { Norm ($_.Asset -replace '^DA_CraftingRecipe_', '') }) }
function Test-Craftable($it) {
  $names = @((Norm $it.id), (Norm ($it.asset -replace '^DA_[A-Za-z]+_', '')), (Norm ($it.asset -replace '^DA_[A-Za-z]+_[A-Za-z]+_', '')))
  foreach ($r in $recipes) { foreach ($n in $names) { if (-not $n -or -not $r) { continue }; if ($r -eq $n) { return $true }
      $short = if ($r.Length -le $n.Length) { $r } else { $n }; $long = if ($r.Length -le $n.Length) { $n } else { $r }
      if ($short.Length -ge 6 -and $long.StartsWith($short) -and ($short.Length / $long.Length) -ge 0.6) { return $true } } }
  return $false
}

$stat = @{ game = 0; saves = 0; none = 0; withSrc = 0; craft = 0 }
foreach ($it in $items) {
  $mc = $null; $cs = ''
  if ($it.category -in 'Clothing', 'Weapons', 'Consumables' -and $files.ContainsKey($it.asset)) {
    $b = [IO.File]::ReadAllBytes($files[$it.asset]); $v = $null
    if ($markers.ContainsKey($it.category)) { $v = Read-After $b $markers[$it.category] ([BitConverter]::ToUInt32($b, 4)) }
    if ($null -eq $v) { $v = Read-Pair $b }
    if ($null -ne $v -and $v -gt 1 -and $v -lt 5000) { $mc = [math]::Round([double]$v, 1); $cs = 'game data' } }
  elseif ($buildCond.ContainsKey($it.asset) -and (Test-Path -LiteralPath (Join-Path $BuildRoot ($buildCond[$it.asset][0] + '.uasset')))) {
    $b = [IO.File]::ReadAllBytes((Join-Path $BuildRoot ($buildCond[$it.asset][0] + '.uasset'))); $v = [BitConverter]::ToInt32($b, [int][BitConverter]::ToUInt32($b, 4) + $buildCond[$it.asset][1])
    if ($v -gt 1 -and $v -lt 5000) { $mc = [double]$v; $cs = 'game data' } }
  if ($null -eq $mc -and $it.maxSeenDur -and [double]$it.maxSeenDur -gt 1) { $mc = [math]::Round([double]$it.maxSeenDur, 1); $cs = 'your saves' }
  if ($cs -eq 'game data') { $stat.game++ } elseif ($cs -eq 'your saves') { $stat.saves++ } else { $stat.none++ }
  if ($cs -eq 'game data') { $it | Add-Member -Force defaultCondition $mc }
  $it | Add-Member -Force maxCondition $mc; $it | Add-Member -Force condSource $cs
  $s = @(); if ($src.ContainsKey($it.id)) { $s += @($src[$it.id]) }
  if ($it.recipe) { $s += 'Craft'; $stat.craft++ }   # exact: a decoded recipe (Build-Recipes.ps1) makes this item
  $order = 'Loot', 'Pickup', 'Craft', 'Trader', 'Quest', 'Animal'; $s = @($order | Where-Object { $s -contains $_ })
  if ($s.Count) { $stat.withSrc++ }
  $it | Add-Member -Force sources $s
}
$items | ConvertTo-Json -Depth 6 | Set-Content $ItemsJson -Encoding utf8
"items: $($items.Count) | max condition from game data: $($stat.game), from your saves: $($stat.saves), none: $($stat.none) | with a 'found via' source: $($stat.withSrc) (craftable by recipe name: $($stat.craft))"
