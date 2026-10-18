param(
  [string]$BlueprintsRoot = '',
  [string]$ItemsJson = (Join-Path $PSScriptRoot 'items.json')
)
. (Join-Path $PSScriptRoot 'Paths.ps1')
if (-not $BlueprintsRoot) { $BlueprintsRoot = PF-ExportPath 'Permafrost\Content\Permafrost\Blueprints' }
# Reads the quest reward pools (DA_RewardPool_*) and the learning-recipe assets (DA_Learn*) straight from the raw export and writes
#   catalog\reward-groups.csv   one row per reward group: items with amounts, recipes it teaches
#   catalog\learning-details.csv  one row per learning asset: what it teaches and how it can be learned
# Layout of a reward pool (decoded from the raw data; checked on all 18 pools / 68 groups):
#   per group:  <name-map index of the group name, int32> <name number, int32>  80 07 01 <N>  00 00 00
#               N items, 26 bytes each:  00 05 <slot> 7 zero bytes <name-map index of the item asset> 8 zero bytes <int32 amount>
#               <int32 M> then M learning-recipe references (each points at a DA_Learn* name-map entry or at 'None' = empty slot)
#   Checks: every group's items parse in place, and M equals (learning references found + empty 'None' slots) in all 68 groups.
# Layout of a learning asset: the name map holds the learnable thing's name and the learning methods it can be unlocked by.
$ErrorActionPreference = 'Stop'
$src = Get-Content (Join-Path $PSScriptRoot 'Build-Catalog.ps1') -Raw
$m = [regex]::Match($src, 'function Get-NameMap.*?\r?\n\}\r?\n', 'Singleline'); Invoke-Expression $m.Value
$items = Get-Content $ItemsJson -Raw | ConvertFrom-Json
$idOf = @{}; foreach ($i in $items) { $idOf[$i.asset] = $i.id }
function Short([string]$a) { if ($idOf.ContainsKey($a)) { return $idOf[$a] }; return ($a -replace '^(DA|BP)_[A-Za-z]+?_', '' -replace '^(DA|BP)_', '') }
function LearnShort([string]$a) { return ($a -replace '^DA_Learn(ing|Building)(Recipe)?_', '') }
function Test-Zeros([byte[]]$b, [int]$from, [int]$cnt) { for ($k = 0; $k -lt $cnt; $k++) { if ($b[$from + $k] -ne 0) { return $false } }; return $true }

$groupsOut = New-Object System.Collections.Generic.List[object]; $problems = @()
foreach ($f in [IO.Directory]::EnumerateFiles($BlueprintsRoot, 'DA_RewardPool_*.uasset', [IO.SearchOption]::AllDirectories)) {
  $pool = [IO.Path]::GetFileNameWithoutExtension($f); $b = [IO.File]::ReadAllBytes($f); $hs = [BitConverter]::ToUInt32($b, 4); $nm = Get-NameMap $f; $end = $b.Length - 4
  $marks = @()
  for ($p = $hs + 8; $p -le $end - 8; $p++) {
    if ($b[$p] -eq 0x80 -and $b[$p + 1] -eq 7 -and $b[$p + 2] -eq 1 -and $b[$p + 3] -le 40) {
      $kb = $p - 8; $key = [BitConverter]::ToUInt32($b, $kb); $num = [BitConverter]::ToUInt32($b, $kb + 4)
      if ($key -lt $nm.Count -and $nm[$key] -notmatch '^/' -and $nm[$key] -notmatch '^(DA|BP)_' -and $num -lt 100000) { $marks += [pscustomobject]@{ p = $p; kb = $kb; key = $key; num = $num; n = $b[$p + 3] } } } }
  for ($g = 0; $g -lt $marks.Count; $g++) {
    $mk = $marks[$g]; $limit = if ($g + 1 -lt $marks.Count) { $marks[$g + 1].kb } else { $end }
    $label = $nm[$mk.key]; if ($mk.num -gt 0) { $label += "_$($mk.num - 1)" }
    $q = $mk.p + 7; $its = @(); $ok = $true
    for ($i = 0; $i -lt $mk.n; $i++) {
      if (-not ($b[$q] -eq 0 -and $b[$q + 1] -eq 5 -and (Test-Zeros $b ($q + 3) 7) -and (Test-Zeros $b ($q + 14) 8))) { $ok = $false; break }
      $rr = [BitConverter]::ToUInt32($b, $q + 10); if ($rr -ge $nm.Count) { $ok = $false; break }
      $its += [pscustomobject]@{ asset = $nm[$rr]; amount = [BitConverter]::ToInt32($b, $q + 22) }; $q += 26 }
    if (-not $ok) { $problems += "$pool / ${label}: item layout not as expected"; continue }
    $M = [BitConverter]::ToInt32($b, $q); $refs = @()
    if ($M -ge 0 -and $M -le 60) { for ($r = $q + 4; $r -le $limit - 4; $r++) { $v = [BitConverter]::ToUInt32($b, $r); if ($v -lt $nm.Count -and $nm[$v] -match '^DA_Learn' -and $b[$r - 1] -eq 0) { $refs += $nm[$v]; $r += 3 } } }
    $empty = $M - $refs.Count; $noneInMap = ($nm -contains 'None')
    if ($empty -lt 0 -or ($empty -gt 0 -and -not $noneInMap)) { $problems += "$pool / ${label}: M=$M but $($refs.Count) recipe references" }
    $groupsOut.Add([pscustomobject]@{
        Pool = ($pool -replace '^DA_RewardPool_', ''); Group = $label
        Items = (($its | ForEach-Object { "$(Short $_.asset) x$($_.amount)" }) -join '; ')
        ItemIds = (($its | ForEach-Object { Short $_.asset }) -join ';')
        Amounts = (($its | ForEach-Object { $_.amount }) -join ';')
        Teaches = (($refs | ForEach-Object { LearnShort $_ }) -join '; ')
        TeachAssets = ($refs -join ';')
        EmptyRecipeSlots = [math]::Max(0, $empty) }) } }
$groupsOut | Export-Csv -Path (Join-Path $PSScriptRoot 'catalog\reward-groups.csv') -NoTypeInformation -Encoding UTF8

# ---- learning assets.  Names/methods/cost come from FModel's JSON (LearningRecipeConfig: Name, LearnMethods, RecipeCost, RecipeType, AssetRegistrySearchableTag);
#      the 31 LearningRecipeSet bundles have no JSON, their members come from the names in their .uasset.
$jsonL = @{}; foreach ($jf in [IO.Directory]::EnumerateFiles($BlueprintsRoot, 'DA_Learn*.json', [IO.SearchOption]::AllDirectories)) {
  $o = (Get-Content $jf -Raw | ConvertFrom-Json) | Where-Object { $_.Properties } | Select-Object -First 1; if ($o) { $jsonL[[IO.Path]::GetFileNameWithoutExtension($jf)] = $o.Properties } }
$learn = New-Object System.Collections.Generic.List[object]
foreach ($f in [IO.Directory]::EnumerateFiles($BlueprintsRoot, 'DA_Learn*.uasset', [IO.SearchOption]::AllDirectories)) {
  $nm = Get-NameMap $f; $name = [IO.Path]::GetFileNameWithoutExtension($f)
  $members = @($nm | Where-Object { $_ -match '^DA_Learn' -and $_ -ne $name -and $_ -ne ($name -replace '_\d+$', '') })
  $jp = $jsonL[$name]
  if ($jp) { $methods = @(@($jp.LearnMethods) | Where-Object { $_ } | ForEach-Object { ([string]$_ -replace '^.*ELM_', '') }); $teach = [string]$jp.AssetRegistrySearchableTag; $disp = if ($jp.Name) { [string]$jp.Name.SourceString } else { '' }
    $cost = if ($null -ne $jp.RecipeCost) { [string]$jp.RecipeCost } else { '' }; $kind = if ($jp.RecipeType -match 'Building' -or $name -like 'DA_LearnBuilding_*') { 'Building' } else { 'Item recipe' } }
  else { $methods = @(); $teach = ''; $disp = ''; $cost = ''; $kind = $(if ($name -like 'DA_LearnBuilding_*') { 'Building' } else { 'Item recipe' }) }
  $learn.Add([pscustomobject]@{ Asset = $name; Teaches = $teach; DisplayName = $disp; Methods = ($methods -join ';'); Cost = $cost; Members = (($members | ForEach-Object { LearnShort $_ }) -join ';'); MemberAssets = ($members -join ';'); Kind = $kind }) }
$learn | Sort-Object Asset | Export-Csv -Path (Join-Path $PSScriptRoot 'catalog\learning-details.csv') -NoTypeInformation -Encoding UTF8
# ---- items.json: where each item is handed out as a quest reward (exact: group item lists)
$by = @{}
foreach ($r in $groupsOut) { $ids = $r.ItemIds -split ';'; $am = $r.Amounts -split ';'; for ($k = 0; $k -lt $ids.Count; $k++) { if (-not $by.ContainsKey($ids[$k])) { $by[$ids[$k]] = @() }; $by[$ids[$k]] += "$($r.Pool)/$($r.Group) x$($am[$k])" } }
foreach ($i in $items) { $i | Add-Member -Force rewards $(if ($by.ContainsKey($i.id)) { ($by[$i.id] -join '; ') } else { '' }) }
$items | ConvertTo-Json -Depth 6 | Set-Content $ItemsJson -Encoding utf8
"reward groups: $($groupsOut.Count) | learning assets: $($learn.Count) | items handed out by a pool: $($by.Count) | problems: $($problems.Count)"
$problems
