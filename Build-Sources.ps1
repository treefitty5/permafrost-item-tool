param(
  [string]$ItemsJson = (Join-Path $PSScriptRoot 'items.json')
)
# "Where to find it": joins the decoded loot data into, per item, the places that can give it and the chance per opening.
#   loot-items.csv (entries, SpawnWeight)  +  loot-links.csv (config -> lists, rolls; asset -> config)  +  animals.csv  +  destructibles.csv  +  reward groups
# Chance model (from the game's own loot structure): a container's loot config names RandomLists; each time a list is named it is rolled once, and one
# entry is picked with probability weight / (sum of the list's weights). So  P(item at least once) = 1 - product over lists of (1 - p)^rolls.
# StaticLoot and single-resource loot are always given. Trader configs are shown as 'sold by', without a chance (their numbers are stock, not odds).
# This says how likely an item is WHEN a container of that type is opened - not how many such containers exist in the world.
# Writes catalog\item-sources.csv and, in items.json, 'sourcesText'. Run after Build-Loot.ps1 and Build-Rewards.ps1, Build-Game.ps1.
$ErrorActionPreference = 'Stop'
$cat = Join-Path $PSScriptRoot 'catalog'
$items = Get-Content $ItemsJson -Raw | ConvertFrom-Json
$li = @(Import-Csv "$cat\loot-items.csv"); $lk = @(Import-Csv "$cat\loot-links.csv")
$animals = @(Import-Csv "$cat\animals.csv"); $destr = @(Import-Csv "$cat\destructibles.csv")
function Clean([string]$n) { return ($n -replace '^(BP_S_|BP_D_|BP_|DA_Animal_|DA_LC_Containers_Survival_|DA_LC_Containers_|DA_LC_Trading_Survival_|DA_LC_Trading_|DA_LC_Scavengable_Survival_|DA_LC_Destructable_Survival_|DA_LC_)', '') }

# lists: name -> entries (RandomItemsList) with total weight
$listEntries = @{}; $listTotal = @{}; $configStatic = @{}
foreach ($r in $li) {
  if ($r.Section -eq 'RandomItemsList' -and $r.Item) { if (-not $listEntries.ContainsKey($r.List)) { $listEntries[$r.List] = New-Object System.Collections.Generic.List[object] }; $listEntries[$r.List].Add($r); $listTotal[$r.List] = [double]$listTotal[$r.List] + [double]$r.Weight }
  elseif ($r.Section -in 'StaticLoot', 'Loot' -and $r.Item) { if (-not $configStatic.ContainsKey($r.List)) { $configStatic[$r.List] = New-Object System.Collections.Generic.List[object] }; $configStatic[$r.List].Add($r) } }
# config -> (list, rolls)
$cfgLists = @{}; $lootFiles = @{}; foreach ($r in $li) { $lootFiles[$r.List] = 1 }
foreach ($l in $lk) { if ($lootFiles.ContainsKey($l.From) -and $l.Refs -and $listEntries.ContainsKey($l.To)) { if (-not $cfgLists.ContainsKey($l.From)) { $cfgLists[$l.From] = @() }; $cfgLists[$l.From] += [pscustomobject]@{ List = $l.To; Rolls = [int]$l.Refs } } }
$cfgFolder = @{}; foreach ($r in $li) { $cfgFolder[$r.List] = $r.Folder }
function Kind-Of($cfg, [string]$fromFolder) {
  if ($cfg -match '^DA_LC_Trading_') { return 'Trader' }; $fo = [string]$cfgFolder[$cfg]
  if ($fo -match 'Hostile' -or $cfg -match 'Hostile') { return 'Enemy drop' }; if ($cfg -match 'Scavengable|Destructable' -or $fo -match 'Resource') { return 'Scavenge / resource' }
  if ($fromFolder -eq 'Container') { return 'Container' }; if ($cfg -match 'Equipment$') { return $null }; return 'Other' }
# source asset -> configs, by kind
$srcCfg = New-Object System.Collections.Generic.List[object]
foreach ($l in $lk) { if ($l.FromFolder -in 'Container', 'Asset' -and ($lootFiles.ContainsKey($l.To))) { $kind = Kind-Of $l.To $l.FromFolder; if ($kind) { $srcCfg.Add([pscustomobject]@{ Kind = $kind; Source = (Clean $l.From); Config = $l.To }) } } }
foreach ($a in $animals) { if ($a.Loot) { $srcCfg.Add([pscustomobject]@{ Kind = 'Animal (carcass)'; Source = $a.Name; Config = $a.Loot }) } }
foreach ($d in $destr) { foreach ($t in ((@($d.FinalLoot, $d.ProgressiveLoot) -join ' ') -split '[\s;,{}=]+' | Where-Object { $_ -match '^DA_LC_' } | Select-Object -Unique)) { $srcCfg.Add([pscustomobject]@{ Kind = 'Destructible (breaking it)'; Source = $(if ($d.Name) { $d.Name } else { Clean $d.Asset }); Config = $t }) } }

# per config: item -> chance
$cfgItem = @{}   # config -> item -> @{ chance; guaranteed; amount }
function Add-Item($cfg, $item, $chance, $guar, $amount) { if (-not $cfgItem.ContainsKey($cfg)) { $cfgItem[$cfg] = @{} }; $h = $cfgItem[$cfg]; if (-not $h.ContainsKey($item)) { $h[$item] = @{ miss = 1.0; guar = $false; amount = $amount } }
  if ($guar) { $h[$item].guar = $true } else { $h[$item].miss *= [math]::Pow(1 - $chance, 1) }; if (-not $h[$item].amount) { $h[$item].amount = $amount } }
$configs = @($srcCfg | Select-Object -ExpandProperty Config -Unique)
foreach ($c in $configs) {
  if ($configStatic.ContainsKey($c)) { foreach ($s in $configStatic[$c]) { Add-Item $c $s.Item 1 $true $s.Amount } }
  foreach ($cl in @($cfgLists[$c])) { if (-not $cl) { continue }; $tot = $listTotal[$cl.List]; if (-not $tot) { continue }
    $perItem = @{}; foreach ($e in $listEntries[$cl.List]) { $perItem[$e.Item] = [double]$perItem[$e.Item] + [double]$e.Weight; if (-not $perItem["amt:$($e.Item)"]) { $perItem["amt:$($e.Item)"] = $e.Amount } }
    foreach ($k in @($perItem.Keys | Where-Object { $_ -notlike 'amt:*' })) { $p = [double]$perItem[$k] / $tot
      for ($n = 0; $n -lt $cl.Rolls; $n++) { Add-Item $c $k $p $false $perItem["amt:$k"] } } } }

# rows grouped by (item, kind, config): list of sources
$rows = New-Object System.Collections.Generic.List[object]
$byCfg = @{}; foreach ($s in $srcCfg) { $k = "$($s.Kind)|$($s.Config)"; if (-not $byCfg.ContainsKey($k)) { $byCfg[$k] = New-Object System.Collections.Generic.List[string] }; if (-not $byCfg[$k].Contains($s.Source)) { $byCfg[$k].Add($s.Source) } }
foreach ($k in $byCfg.Keys) { $kind, $cfg = $k -split '\|', 2; if (-not $cfgItem.ContainsKey($cfg)) { continue }
  foreach ($item in $cfgItem[$cfg].Keys) { $h = $cfgItem[$cfg][$item]; $chance = if ($h.guar) { 100.0 } else { [math]::Round((1 - $h.miss) * 100, 1) }
    $rows.Add([pscustomobject]@{ Item = $item; Kind = $kind; Config = $cfg; ChancePerOpening = $(if ($kind -eq 'Trader') { '' } else { $chance }); Guaranteed = $(if ($h.guar) { 'yes' } else { '' }); Amount = $h.amount; SourceCount = $byCfg[$k].Count; Sources = (($byCfg[$k] | Sort-Object) -join ', ') }) } }
# quest rewards
foreach ($i in $items) { if ($i.rewards) { foreach ($rw in ($i.rewards -split '; ')) { $rows.Add([pscustomobject]@{ Item = $i.id; Kind = 'Quest reward'; Config = ($rw -replace ' x\d+$', ''); ChancePerOpening = ''; Guaranteed = 'yes'; Amount = ($rw -replace '^.* x', 'x'); SourceCount = 1; Sources = ($rw -replace ' x\d+$', '') }) } } }
$rows | Sort-Object Item, Kind, @{ Expression = { -[double]($_.ChancePerOpening -as [double]) } } | Export-Csv "$cat\item-sources.csv" -NoTypeInformation -Encoding UTF8

# items.json: short text for the item panel
$byItem = @{}; foreach ($r in $rows) { if (-not $byItem.ContainsKey($r.Item)) { $byItem[$r.Item] = New-Object System.Collections.Generic.List[object] }; $byItem[$r.Item].Add($r) }
$n = 0
foreach ($i in $items) { $txt = ''
  if ($byItem.ContainsKey($i.id)) { $g = @($byItem[$i.id] | Where-Object { $_.Kind -ne 'Quest reward' -and $_.Kind -ne 'Trader' } | Sort-Object { -[double]($_.ChancePerOpening -as [double]) }, { -[int]$_.SourceCount } | Select-Object -First 4)
    $parts = @($g | ForEach-Object { $names = @($_.Sources -split ', '); $nm = ($names | Select-Object -First 2) -join ', '; if ($names.Count -gt 2) { $nm += " +$($names.Count - 2)" }; "$($_.ChancePerOpening)% $nm [$($_.Kind)]" })
    $parts = @($parts | Select-Object -Unique)   # several configs can read the same; show each line once
    $tr = @($byItem[$i.id] | Where-Object Kind -eq 'Trader' | ForEach-Object { $_.Sources -split ', ' } | Select-Object -Unique); if ($tr.Count) { $parts += "sold by $((@($tr) | Select-Object -First 3) -join ', ')$(if ($tr.Count -gt 3) { ' +' + ($tr.Count - 3) })" }
    $txt = $parts -join '  |  '; if ($txt) { $n++ } }
  $i | Add-Member -Force sourcesText $txt }
$items | ConvertTo-Json -Depth 6 | Set-Content $ItemsJson -Encoding utf8
"source rows: $($rows.Count) | items with a place to find them: $n of $($items.Count) | configs used by a source: $($configs.Count)"
