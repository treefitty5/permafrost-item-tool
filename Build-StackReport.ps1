# Build-StackReport.ps1 - report of how every consumable (food, drink, medication, dishes) stacks in the game's own data.
#   pwsh -NoProfile -File .\Build-StackReport.ps1        ->  docs\consumables-stack-report.md  and  docs\consumables-stack-report.csv
# Reads FModel's JSON export (the same one Build-Everything.ps1 uses) plus items.json for names and save ids. Run it again after a game update.
# Per item: the stack limit, whether the data marks it stackable (bCanBeStackable - when the flag is missing the game does NOT stack it, whatever the stack limit says),
# and whether it uses a durability (a stack shares ONE condition, so such items need 'single use' to be stackable without waste).
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Paths.ps1')
$dir = PF-ExportPath 'Permafrost\Content\Permafrost\Blueprints\Items\DataAsset_Items\Consumables'
if (-not (Test-Path -LiteralPath $dir)) { throw "Consumables export not found: $dir  (README, section 9.2)" }
$byAsset = @{}; $ip = Join-Path $PSScriptRoot 'items.json'
if (Test-Path $ip) { foreach ($i in (Get-Content $ip -Raw | ConvertFrom-Json)) { if ($i.asset) { $byAsset[[string]$i.asset] = $i } } }
function Has($o, $n) { return ($null -ne $o -and $o.PSObject.Properties.Name -contains $n) }

$rows = New-Object System.Collections.Generic.List[object]
foreach ($f in (Get-ChildItem -LiteralPath $dir -Recurse -Filter '*.json')) {
  $o = (Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json)[0]; $p = $o.Properties; $sc = $p.StackableConfig; $du = $p.DurabilityConfig
  $it = $byAsset[[string]$o.Name]
  $amount = $(if (Has $sc 'StackAmount') { [int]$sc.StackAmount } else { 1 })
  $flag = $(if (Has $sc 'bCanBeStackable') { [bool]$sc.bCanBeStackable } else { $null })
  $usesDur = $(if (Has $du 'bUsesDurability') { [bool]$du.bUsesDurability } else { $false })
  $folder = Split-Path (Split-Path $f.FullName -Parent) -Leaf
  # what the data says the game does today
  $stacksNow = ($flag -eq $true -and $amount -gt 1 -and -not $usesDur)
  $kind = if ($usesDur) { 'durability' } elseif ($flag -ne $true) { 'flag missing' } elseif (-not $it) { 'not in item list' } else { 'stackable' }
  $note = switch ($kind) {
    'stackable'    { "Stacks to $amount in the game. The limit can be raised with the StackSizes mod; no durability, so a stack wastes nothing." }
    'flag missing' { if ($folder -eq 'PredefinedRecipeOutput') { "Dish variants (loot and recipe outputs): same missing flag, limit 20. Not checked in the game whether they stack; the mod could mark them stackable." } else { "Not stackable in the game (the data has a stack limit of $amount but no stackable flag, so every piece takes its own slot). The mod can mark it stackable. No durability." } }
    'durability'   { "Has a durability (condition): a stack would share one condition. Needs the mod's 'single use' to stack without wasting items (that is how the first aid kits work)." }
    'not in item list' { "Not in the tool's item list (a recipe-output placeholder, not something found as a world item). Leave alone." }
  }
  $rows.Add([pscustomobject]@{
    Item = $(if ($it) { [string]$it.display } else { ($o.Name -replace '^DA_Consumable_', '') })
    SaveId = $(if ($it) { [string]$it.id } else { '' })
    Asset = [string]$o.Name; Folder = $folder
    GameStack = $amount; StackableFlag = $(if ($null -eq $flag) { 'missing' } else { "$flag" }); UsesDurability = $usesDur
    StacksToday = $stacksNow; Kind = $kind
    ItemCondition = $(if ($it -and $it.maxCondition) { [string]$it.maxCondition } else { '' })
    Note = $note })
}
$rows = @($rows | Sort-Object Kind, Folder, Item)
$docs = Join-Path $PSScriptRoot 'docs'; if (-not (Test-Path $docs)) { New-Item -ItemType Directory $docs | Out-Null }
$rows | Export-Csv -LiteralPath (Join-Path $docs 'consumables-stack-report.csv') -NoTypeInformation -Encoding utf8

$md = New-Object System.Collections.Generic.List[string]
$md.Add('# Consumables: how they stack (from the game data)'); $md.Add('')
$md.Add("Made by Build-StackReport.ps1 from the game's own data files ($($rows.Count) consumable assets). Re-run it after a game update.")
$md.Add(''); $md.Add('## How to read this'); $md.Add('')
$md.Add('- **Game stack** is the limit in the item data. **Stackable flag**: the game only stacks an item when its data says so; where the flag is *missing* the item takes one slot per piece although a limit is listed (Panacea and both splints).')
$md.Add('- **Uses durability**: the item carries a condition. A stack shares ONE condition, so the first aid kits only stack with the mod''s "single use" setting.')
$md.Add('- The condition shown in the item list for foods (10) is the item''s own condition field, not a durability; the game already stacks those to 20.')
$md.Add('- **Safety rule (tested with kits):** the stack limit belongs to the item data. With the StackSizes mod off, the game trims every stack above its own limit down on the next save and the extra items are gone. Anything raised with the mod needs the same DANGER warning and backup as the kits.')
$md.Add('- Sizes above 20 were never tried in the game (stacks of 5, 10 and the game''s own 20 were).')
$md.Add('')
$sum = $rows | Group-Object Kind | Sort-Object Name | ForEach-Object { "$($_.Count) $($_.Name)" }
$md.Add('**Summary:** ' + ($sum -join ', ') + '.'); $md.Add('')
foreach ($k in 'flag missing', 'durability', 'stackable', 'not in item list') {
  $g = @($rows | Where-Object { $_.Kind -eq $k }); if (-not $g.Count) { continue }
  $title = @{ 'flag missing' = 'Not stackable today (stack limit listed, flag missing)'; 'durability' = 'Items with a durability'; 'stackable' = 'Already stackable'; 'not in item list' = 'Recipe-output placeholders' }[$k]
  $md.Add("## $title ($($g.Count))"); $md.Add('')
  $md.Add('| Item | Save id | Game stack | Folder |'); $md.Add('|---|---|---|---|')
  foreach ($r in $g) { $md.Add("| $($r.Item) | $($r.SaveId) | $($r.GameStack) | $($r.Folder) |") }
  $md.Add(''); foreach ($n in ($g | ForEach-Object { $_.Note } | Select-Object -Unique)) { $md.Add("- $n") }; $md.Add('')
}
$smaller = @($rows | Where-Object { $_.Kind -eq 'stackable' -and $_.GameStack -lt 20 })
if ($smaller.Count) { $md.Add('## Stackable items with a limit below 20 (the most useful to raise)'); $md.Add('')
  foreach ($r in $smaller) { $md.Add("- $($r.Item) ($($r.SaveId)): $($r.GameStack)") }; $md.Add('') }
[IO.File]::WriteAllText((Join-Path $docs 'consumables-stack-report.md'), (($md -join "`n") + "`n"), (New-Object Text.UTF8Encoding($false)))
"Wrote docs\consumables-stack-report.md and .csv ($($rows.Count) rows)"
$rows | Group-Object Kind | ForEach-Object { "  $($_.Name): $($_.Count)" }
