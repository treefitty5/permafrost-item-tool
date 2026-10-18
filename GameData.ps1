# GameData.ps1 - the "Game data" window: search everything in the game files, reward pools, quests, recipes, all tables, bundles.
# Needs PlayerTools.ps1 (helpers) loaded. $script:Cat = item catalog, $script:QueueAdder = scriptblock { param($id,$count) } that queues an item.
$script:GD = @{}
$script:TableCache = @{}
$script:AllRowsCache = $null
$script:DomainTables = @('quests', 'quest-bindings', 'quest-areas', 'quest-dialogues', 'quest-recordings', 'quest-events', 'reward-pools', 'loot-configs', 'crafting-recipes', 'learning-recipes', 'building-parts', 'containers', 'interactions', 'npcs', 'animals', 'companion', 'world-locations', 'weather-world', 'gameplay-effects', 'achievements', 'random-encounters', 'difficulty-status', 'skills', 'world-items', 'holdables')

function GD-AssetMap { if (-not $script:GD.AssetToId) { $m = @{}; foreach ($i in $script:Cat) { $m[$i.asset] = $i.id }; $script:GD.AssetToId = $m }; return $script:GD.AssetToId }
# ---------- spoiler guard: story text (quest descriptions, recordings, dialogue, NPC journals) is hidden until you untick the box ----------
function Get-HideSpoilers { if ($null -eq $script:HideSpoilers) { $script:HideSpoilers = $true; $p = Join-Path $PSScriptRoot 'spoiler.json'; if (Test-Path -LiteralPath $p) { try { $script:HideSpoilers = [bool]((Get-Content $p -Raw | ConvertFrom-Json).hide) } catch { } } }; return [bool]$script:HideSpoilers }
function Set-HideSpoilers([bool]$v) { $script:HideSpoilers = $v; try { (@{ hide = $v } | ConvertTo-Json) | Set-Content (Join-Path $PSScriptRoot 'spoiler.json') -Encoding utf8 } catch { } }
function GD-Spoil([string]$text) { if ($text -and (Get-HideSpoilers)) { return '[story text hidden - untick "Hide story text" to read]' }; return $text }
function GD-SpoilCols([string]$csv, $row) {
  if ($csv -eq 'text') { if ([string]$row.Table -match 'Narrative|Quest|Journal|Additional|Bunker|Flavour') { return @('Text') }; return @() }
  if ($csv -eq 'npcs') { return @('Journal') }; return @()
}
function GD-CatItem([string]$id) { if (-not $script:GD.ById) { $m = @{}; foreach ($i in $script:Cat) { $m[$i.id] = $i }; $script:GD.ById = $m }; return $script:GD.ById[$id] }

function GD-Rows([string]$name) {
  if ($script:TableCache.ContainsKey($name)) { return $script:TableCache[$name] }
  $dir = Join-Path $PSScriptRoot 'catalog'; $p = Join-Path $dir "$name.csv"
  if (-not (Test-Path -LiteralPath $p)) { throw "catalog\$name.csv not found - run Build-DataCatalog.ps1" }
  $rows = New-Object System.Collections.Generic.List[object]
  if ($name -eq 'blueprints-index') {
    $map = GD-AssetMap
    foreach ($r in (Import-Csv $p)) { $its = @(); $oth = @(); foreach ($x in ($r.Refs -split ';' | Where-Object { $_ })) { if ($map.ContainsKey($x)) { $its += $map[$x] } else { $oth += $x } }
      $rows.Add([pscustomobject]@{ Table = $name; Asset = $r.Asset; Group = $r.Group; Folder = $r.Folder; Items = ($its -join ';'); References = ($oth -join ';') }) }
  } else {
    foreach ($r in (Import-Csv $p)) { $rows.Add([pscustomobject]@{ Table = $name; Asset = $r.Asset; Group = $r.Group; Folder = $r.Folder; Items = $r.Items; References = $r.References }) }
  }
  $script:TableCache[$name] = $rows.ToArray(); return $script:TableCache[$name]
}
function GD-All {
  if ($script:AllRowsCache) { return $script:AllRowsCache }
  $seen = @{}; $all = New-Object System.Collections.Generic.List[object]
  foreach ($t in $script:DomainTables) { foreach ($r in (GD-Rows $t)) { $all.Add($r); $seen["$($r.Folder)/$($r.Asset)"] = 1 } }
  foreach ($r in (GD-Rows 'blueprints-index')) { if (-not $seen.ContainsKey("$($r.Folder)/$($r.Asset)")) { $all.Add([pscustomobject]@{ Table = 'other'; Asset = $r.Asset; Group = $r.Group; Folder = $r.Folder; Items = $r.Items; References = $r.References }) } }
  $script:AllRowsCache = $all.ToArray(); return $script:AllRowsCache
}

function GD-RefGroup([string]$r) {
  if ($r -like 'DA_RewardPool_*') { return 'Reward pools' } elseif ($r -like 'DA_QuestDialogue_*' -or $r -like 'BP_Dialogue*' -or $r -like '*Dialogue*') { return 'Dialogues' } elseif ($r -like 'DA_QuestArea_*') { return 'Quest areas' }
  elseif ($r -like 'BP_Quest_*') { return 'Quests' } elseif ($r -like 'DA_CraftingRecipe_*' -or $r -like 'DA_Recipe*') { return 'Crafting recipes' } elseif ($r -like 'DA_Learn*') { return 'Learning recipes' }
  elseif ($r -like 'DA_Bunker*' -or $r -like 'DA_Radio*' -or $r -like '*Recording*') { return 'Recordings / radio' } elseif ($r -like 'BP_NPC*' -or $r -like 'NPC_*') { return 'NPCs' } else { return 'Other' }
}
function GD-CraftDetail($r) {
  $d = $r.Rec; $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine("Recipe:      $($d.Name)   [$($d.Recipe)]"); if ($d.Description) { [void]$sb.AppendLine("About:       $($d.Description)") }
  [void]$sb.AppendLine(); [void]$sb.AppendLine("Ingredients: $($d.Ingredients)"); [void]$sb.AppendLine("Makes:       $(if ($d.AllResults) { $d.AllResults } else { "$($d.Result) x$($d.ResultAmount)" })")
  [void]$sb.AppendLine("Station:     $($d.Station)     Time: $($d.Time)s     Category: $($d.Category)")
  $need = @(GD-IngredientList $d 1); $miss = @(([string]$d.Ingredients -split '; ') | Where-Object { $_ -match '^(.*) x\d+$' -and -not (GD-ItemKey $Matches[1]) })
  [void]$sb.AppendLine(); [void]$sb.AppendLine("The button below queues these ingredients for the number of crafts in the box ($(($need | ForEach-Object { "$($_.id) x$($_.amount)" }) -join ', ') per craft)."); if ($miss.Count) { [void]$sb.AppendLine("Not addable with this tool: $($miss -join ', ')") }
  return $sb.ToString().TrimEnd()
}
function GD-DetailText($r) {
  if (-not $r) { return '' }
  $sb = New-Object System.Text.StringBuilder
  if ($r.Table -eq 'quest-graph') { return (GD-QuestDetail $r) }
  if ($r.Table -eq 'craft') { return (GD-CraftDetail $r) }
  if ($r.Table -eq 'building') { return (GD-BuildDetail $r) }
  if ($r.Table -eq 'lore') { return (GD-LoreDetail $r) }
  if ($r.Table -eq 'rules') { return (GD-RulesDetail $r) }
  if ($r.Table -eq 'loot-lists') {
    [void]$sb.AppendLine("Loot list: $($r.Asset)"); [void]$sb.AppendLine("Folder:    $($r.Folder)"); [void]$sb.AppendLine()
    if (@($r.UsedBy).Count) { [void]$sb.AppendLine('Used by:'); foreach ($u in $r.UsedBy) { $via = if ($script:LootUsedBy.ContainsKey($u)) { '   <- ' + ((@($script:LootUsedBy[$u] | Select-Object -Unique) | Select-Object -First 6) -join ', ') } else { '' }; [void]$sb.AppendLine("   $u$via") } } else { [void]$sb.AppendLine('Used by: (no file links to it)') }
    if (@($r.Uses).Count) { [void]$sb.AppendLine(); [void]$sb.AppendLine('Refers to these lists:'); foreach ($x in $r.Uses) { [void]$sb.AppendLine("   $x") } }
    if (@($r.Entries).Count) {
      [void]$sb.AppendLine(); [void]$sb.AppendLine(("Entries ({0}):   section | weight | amount | durability | item" -f @($r.Entries).Count))
      foreach ($e in $r.Entries) { if (-not $e.Item) { [void]$sb.AppendLine("   $($e.Section): $($e.Note)"); continue }
        $c = GD-CatItem $e.Item; $extra = @($e.Note, $(if (-not $c) { 'not in this tool' })) | Where-Object { $_ }
        [void]$sb.AppendLine(("   {0,-16} | {1,6} | {2,-9} | {3,-12} | {4}{5}" -f $e.Section, $e.Weight, $e.Amount, $e.Durability, $e.Item, $(if ($extra) { "   [$($extra -join '; ')]" } else { '' }))) }
      [void]$sb.AppendLine(); [void]$sb.AppendLine('Field meanings, from the files: weight = SpawnWeight (relative chance within the list); amount = AmountRange, shown as an interval where [ ] includes and ( ) excludes the end; durability = random or fixed condition when the entry sets one. StaticLoot is always given; a RandomLoot list is rolled once per time it is named.')
    }    return $sb.ToString().TrimEnd()
  }
  if ($r.Table -eq 'reward-groups') {
    [void]$sb.AppendLine("Reward pool:  $($r.Asset)"); [void]$sb.AppendLine("Reward group: $($r.Group)"); [void]$sb.AppendLine()
    $ids = @($r.Items -split ';' | Where-Object { $_ }); $am = @($r.Amounts -split ';')
    if ($ids.Count) { [void]$sb.AppendLine('Gives:'); for ($k = 0; $k -lt $ids.Count; $k++) { $c = GD-CatItem $ids[$k]; [void]$sb.AppendLine(("   {0,-8} {1,-28} {2}" -f ('x' + $am[$k]), $ids[$k], $(if ($c) { "$($c.category), stack $($c.stackSize)  (can be added with this tool)" } else { '' }))) } } else { [void]$sb.AppendLine('Gives no items.') }
    $ta = @($r.TeachAssets -split ';' | Where-Object { $_ })
    if ($ta.Count) { [void]$sb.AppendLine(); [void]$sb.AppendLine('Teaches these recipes:'); foreach ($a in $ta) { $d = GD-LearnInfo $a; [void]$sb.AppendLine("   $($a -replace '^DA_Learn(ing|Building)(Recipe)?_', '')$(if ($d) { '   -  ' + $d.Kind + $(if ($d.DisplayName) { ' "' + $d.DisplayName + '"' }) + $(if ($d.Methods) { '; learned by: ' + ($d.Methods -replace ';', ', ') + $(if ($d.Cost) { ', cost ' + $d.Cost }) }) })") } }
    if ([int]$r.Empty -gt 0) { [void]$sb.AppendLine("   (+ $($r.Empty) empty recipe slot in the data)") }
    [void]$sb.AppendLine(); [void]$sb.AppendLine('(Whether a group is paid out, and when, is decided by the quest logic, which is not stored in these files.)')
    return $sb.ToString().TrimEnd()
  }
  [void]$sb.AppendLine("Asset:   $($r.Asset)"); [void]$sb.AppendLine("Table:   $($r.Table)        Folder: $($r.Folder)")
  $its = @($r.Items -split ';' | Where-Object { $_ })
  if ($its.Count) { [void]$sb.AppendLine(); [void]$sb.AppendLine('Items it refers to:'); foreach ($id in $its) { $c = GD-CatItem $id; if ($c) { [void]$sb.AppendLine(("   {0,-26} {1}, stack {2}  (can be added with this tool)" -f $id, $c.category, $c.stackSize)) } else { [void]$sb.AppendLine("   $id") } } }
  $refs = @($r.References -split ';' | Where-Object { $_ })
  if ($refs.Count) { [void]$sb.AppendLine(); foreach ($g in ($refs | Group-Object { GD-RefGroup $_ } | Sort-Object Name)) { [void]$sb.AppendLine("$($g.Name):"); foreach ($x in $g.Group) { [void]$sb.AppendLine("   $x") } } }
  [void]$sb.AppendLine(); [void]$sb.AppendLine('(Drop chances and quest branch logic are not stored in these files - only which things are linked. Recipe ingredients and reward amounts are shown in the Recipes and Reward pools tabs.)')
  return $sb.ToString().TrimEnd()
}
function GD-LearnInfo([string]$asset) {
  if (-not $script:LearnDet) { $script:LearnDet = @{}; $lp = Join-Path $PSScriptRoot 'catalog\learning-details.csv'; if (Test-Path -LiteralPath $lp) { foreach ($d in (Import-Csv $lp)) { $script:LearnDet[$d.Asset] = $d } } }
  return $script:LearnDet[$asset]
}
function GD-RewardsFor([string]$asset) {
  if (-not $script:LearnRewards) { $script:LearnRewards = @{}; foreach ($r in (GD-PoolList)) { foreach ($a in ($r.TeachAssets -split ';' | Where-Object { $_ })) { if (-not $script:LearnRewards.ContainsKey($a)) { $script:LearnRewards[$a] = @() }; $script:LearnRewards[$a] += "$($r.Asset -replace '^DA_RewardPool_', '')/$($r.Group)" } } }
  return @($script:LearnRewards[$asset])
}
function GD-RowItems($r) { if (-not $r) { return @() }; return @($r.Items -split ';' | Where-Object { $_ -and (GD-CatItem $_) }) }

# ---------- a generic tab: filter box + list + detail + "queue items" row ----------
function GD-MakeTab($tabs, [string]$key, [string]$title, [string[]]$cols, [int[]]$widths, [string]$hint) {
  $tab = New-Object System.Windows.Forms.TabPage; $tab.Text = $title; $tab.Padding = New-Object System.Windows.Forms.Padding(8); $tabs.TabPages.Add($tab)
  $g = @{}; $script:GD[$key] = $g
  $top = New-Object System.Windows.Forms.Panel; $top.Dock = 'Top'; $top.Height = 40; $tab.Controls.Add($top)
  New-Lbl $top 'Search' 0 12 50 | Out-Null; $g.Filter = New-Object System.Windows.Forms.TextBox; $g.Filter.Location = '54,8'; $g.Filter.Size = '300,24'; $top.Controls.Add($g.Filter)
  $g.Top = $top; $g.Count = New-Lbl $top '' 370 12 220; $g.Hint = New-Lbl $top $hint 600 12 520; $g.Hint.ForeColor = $script:Th.Muted
  $bot = New-Object System.Windows.Forms.Panel; $bot.Dock = 'Bottom'; $bot.Height = 230; $tab.Controls.Add($bot)
  $q = New-Object System.Windows.Forms.Panel; $q.Dock = 'Bottom'; $q.Height = 38; $bot.Controls.Add($q)
  $g.Detail = New-Object System.Windows.Forms.TextBox; $g.Detail.Multiline = $true; $g.Detail.ReadOnly = $true; $g.Detail.ScrollBars = 'Vertical'; $g.Detail.Dock = 'Fill'; $g.Detail.Font = New-Object System.Drawing.Font('Consolas', 9.5); $g.Detail.BackColor = [System.Drawing.Color]::White; $bot.Controls.Add($g.Detail); $g.Detail.BringToFront()
  $g.QBtn = New-Btn $q 'Queue the item(s) of the selected row' 0 5 280 28; New-Lbl $q 'Quantity (x amount)' 292 10 140 | Out-Null; $g.Qty = New-Num $q 436 7 80 1 99999 0; $g.QMsg = New-Lbl $q '' 530 10 500; $g.QMsg.ForeColor = $script:Th.Accent
  $g.LV = New-LV $tab $cols $widths; $g.LV.Dock = 'Fill'; $g.LV.BringToFront()
  $g.Panel = $tab; return $g
}
# ---------- what a quest step / a recipe needs, as items the tool can queue ----------
function GD-ParseParams([string]$p) { $h = @{}; foreach ($m in [regex]::Matches($p, '(\w+)=([^|]*)')) { $h[$m.Groups[1].Value] = $m.Groups[2].Value.Trim() }; return $h }
function GD-ItemKey([string]$name) {
  if (-not $name) { return '' }; if (GD-CatItem $name) { return $name }
  if (-not $script:GD.ByAsset) { $m = @{}; foreach ($i in $script:Cat) { $m[$i.asset] = $i.id }; $script:GD.ByAsset = $m }
  if ($script:GD.ByAsset.ContainsKey($name)) { return $script:GD.ByAsset[$name] }; if ($script:GD.ByAsset.ContainsKey("DA_$name")) { return $script:GD.ByAsset["DA_$name"] }; return ''
}
function GD-RecipeFor([string]$itemId) {
  if (-not $script:GD.RecByResult) { $m = @{}; $p = Join-Path $PSScriptRoot 'catalog\recipe-details.csv'; if (Test-Path -LiteralPath $p) { foreach ($r in (Import-Csv $p)) { if (-not $m.ContainsKey($r.Result)) { $m[$r.Result] = $r } } }; $script:GD.RecByResult = $m }
  return $script:GD.RecByResult[$itemId]
}
function GD-IngredientList($recipe, [double]$crafts) {   # 'Cloth x8; Wood x2' -> items x amount x crafts
  $out = @(); foreach ($part in ([string]$recipe.Ingredients -split '; ')) { if ($part -match '^(.*) x(\d+)$') { $id = GD-ItemKey $Matches[1]; if ($id) { $out += [pscustomobject]@{ id = $id; amount = [int][math]::Ceiling([int]$Matches[2] * $crafts) } } } }
  return $out
}
function GD-QuestNeeds([string]$quest, [string]$state) {
  $d = GD-QuestData; $q = $d.Quests | Where-Object { $_.Quest -eq $quest } | Select-Object -First 1; $need = New-Object System.Collections.Generic.List[object]; if (-not $q) { return @() }
  if (-not $state) { $state = $q.StartState }; $branches = @($d.Branches[$quest] | Where-Object { ($_.From -split '; ') -contains $state })
  foreach ($b in $branches) { foreach ($o in @($d.Objs["$quest|$($b.BranchID)"])) { $p = GD-ParseParams $o.Parameters; $qty = if ($p['RequiredQuantity']) { [int]$p['RequiredQuantity'] } else { 1 }; $why = "$($o.Objective): $(if ($o.Description) { $o.Description } else { $p['Item'] })"
      switch ($o.Objective) {
        { $_ -in 'ItemFind', 'ItemGive', 'ItemRecycle', 'ItemUse', 'ItemCook' } { $id = GD-ItemKey $p['Item']; if ($id) { $need.Add([pscustomobject]@{ id = $id; amount = $qty; why = $why }) } }
        'ItemCraft' { $id = GD-ItemKey $p['Item']; $rec = if ($id) { GD-RecipeFor $id } else { $null }; if ($rec) { foreach ($ing in (GD-IngredientList $rec $qty)) { $need.Add([pscustomobject]@{ id = $ing.id; amount = $ing.amount; why = "$why (ingredient)" }) } } elseif ($id) { $need.Add([pscustomobject]@{ id = $id; amount = $qty; why = $why }) } }
        'ItemCollectReward' { $grp = GD-PoolList | Where-Object { $_.Asset -eq $p['RewardPool'] -and $_.Group -eq $p['RewardKey'] } | Select-Object -First 1
          if ($grp) { $ids = @($grp.Items -split ';'); $am = @($grp.Amounts -split ';'); for ($k = 0; $k -lt $ids.Count; $k++) { if (GD-CatItem $ids[$k]) { $need.Add([pscustomobject]@{ id = $ids[$k]; amount = [int]$am[$k]; why = "$why (reward group $($p['RewardKey']))" }) } } } } } } }
  return $need.ToArray()
}
function GD-QueueRow($g) {
  if ($g.LV.SelectedItems.Count -eq 0) { $g.QMsg.Text = 'Pick a row first.'; return }
  $row = $g.LV.SelectedItems[0].Tag
  if ($row.Table -eq 'quest-graph') { $nd = @(GD-QuestNeeds $row.Q.Quest (GD-QuestState)[$row.Q.Quest]); if (-not $nd.Count) { $g.QMsg.Text = 'This quest step needs no items the tool can add.'; return }
    foreach ($n in $nd) { [void](& $script:QueueAdder $n.id ($n.amount * [int]$g.Qty.Value)) }; $g.QMsg.Text = "Queued for this step: $((($nd | ForEach-Object { "$($_.id) x$($_.amount)" }) -join ', '))"; return }
  if ($row.Table -eq 'craft') { $nd = @(GD-IngredientList $row.Rec ([int]$g.Qty.Value)); if (-not $nd.Count) { $g.QMsg.Text = 'No ingredients this tool can add.'; return }
    foreach ($n in $nd) { [void](& $script:QueueAdder $n.id $n.amount) }; $g.QMsg.Text = "Queued ingredients for $([int]$g.Qty.Value) craft(s): $((($nd | ForEach-Object { "$($_.id) x$($_.amount)" }) -join ', '))"; return }
  $ids = @(GD-RowItems $g.LV.SelectedItems[0].Tag); if ($ids.Count -eq 0) { $g.QMsg.Text = 'That row refers to no item this tool can add.'; return }
  if ($row.Table -eq 'reward-groups') { $all = @($row.Items -split ';'); $am = @($row.Amounts -split ';'); for ($k = 0; $k -lt $all.Count; $k++) { if (GD-CatItem $all[$k]) { [void](& $script:QueueAdder $all[$k] ([int]$am[$k] * [int]$g.Qty.Value)) } } }
  else { foreach ($id in $ids) { [void](& $script:QueueAdder $id ([int]$g.Qty.Value)) } }
  $g.QMsg.Text = "Queued: $($ids -join ', ')  (see the Queue in the main window)"
}
function GD-WireTab($g, [scriptblock]$fill) {
  $g.Fill = $fill; $g.Filter.Add_TextChanged({ GD-RefreshAll }) ; $g.LV.Add_SelectedIndexChanged({ GD-OnSelect }); $g.QBtn.Add_Click({ GD-QueueFromCurrent })
}
function GD-Current { $tp = $script:GD.Tabs.SelectedTab; foreach ($k in 'Find', 'Pools', 'Quests', 'Recipes', 'Loot', 'Build', 'Lore', 'Rules', 'Tables') { if ($script:GD[$k] -and $script:GD[$k].Panel -eq $tp) { return $script:GD[$k] } }; return $null }
function GD-OnSelect { $g = GD-Current; if (-not $g) { return }; if ($g.LV.SelectedItems.Count) { $g.Detail.Text = GD-DetailText $g.LV.SelectedItems[0].Tag } else { $g.Detail.Text = '' } }
function GD-QueueFromCurrent { $g = GD-Current; if ($g) { GD-QueueRow $g } }
function GD-RefreshAll { $g = GD-Current; if ($g -and $g.Fill) { & $g.Fill } }

function GD-AddRow($lv, $r, [string[]]$cells, $color) {
  $li = New-Object System.Windows.Forms.ListViewItem($cells[0]); $li.Tag = $r; foreach ($c in ($cells | Select-Object -Skip 1)) { [void]$li.SubItems.Add($c) }
  if ($color) { $li.ForeColor = $color }; [void]$lv.Items.Add($li)
}
function GD-Trunc([string]$s, [int]$n = 90) { if ($s.Length -gt $n) { return $s.Substring(0, $n) + '...' }; return $s }

# ---------- tab fillers ----------
function GD-FillFind {
  $g = $script:GD.Find; $f = $g.Filter.Text.Trim(); $lv = $g.LV; $lv.BeginUpdate(); $lv.Items.Clear()
  if ($f.Length -lt 2) { $lv.EndUpdate(); $g.Count.Text = 'type at least 2 characters'; return }
  $n = 0; $by = @{}
  foreach ($r in (GD-All | Sort-Object { if (Test-Match $_.Asset $f) { 0 } elseif (Test-Match "$($_.Items)" $f) { 1 } else { 2 } })) {
    if (-not (Test-Match "$($r.Asset) $($r.Folder) $($r.Items) $($r.References)" $f)) { continue }
    $n++; $by[$r.Table] = 1 + [int]$by[$r.Table]
    if ($lv.Items.Count -lt 1500) { $cl = if (@(GD-RowItems $r).Count) { $script:Th.Text } else { $script:Th.Muted }; GD-AddRow $lv $r @($r.Table, $r.Asset, (GD-Trunc $r.Items 60), (GD-Trunc $r.References 100), $r.Folder) $cl }
  }
  $lv.EndUpdate(); $g.Count.Text = "$n match(es)" + $(if ($n -gt 1500) { ' (first 1500 shown)' } else { '' })
  $g.QMsg.Text = ($by.GetEnumerator() | Sort-Object Value -Descending | Select-Object -First 8 | ForEach-Object { "$($_.Key) $($_.Value)" }) -join '   |   '
}
function GD-PoolList {
  if ($script:RewardGroups) { return $script:RewardGroups }
  $rows = New-Object System.Collections.Generic.List[object]; $p = Join-Path $PSScriptRoot 'catalog\reward-groups.csv'
  if (Test-Path -LiteralPath $p) { foreach ($r in (Import-Csv $p)) { $rows.Add([pscustomobject]@{ Table = 'reward-groups'; Asset = "DA_RewardPool_$($r.Pool)"; Group = $r.Group; Folder = 'QuestSystem/Bindings/RewardPools'; Items = $r.ItemIds; Amounts = $r.Amounts; Gives = $r.Items; Teaches = $r.Teaches; TeachAssets = $r.TeachAssets; Empty = $r.EmptyRecipeSlots; References = '' }) } }
  $script:RewardGroups = $rows.ToArray(); return $script:RewardGroups
}
function GD-FillPools {
  $g = $script:GD.Pools; $f = $g.Filter.Text.Trim(); $lv = $g.LV; $lv.BeginUpdate(); $lv.Items.Clear()
  foreach ($r in (GD-PoolList)) { if (-not (Test-Match "$($r.Asset) $($r.Group) $($r.Gives) $($r.Teaches)" $f)) { continue }; GD-AddRow $lv $r @(($r.Asset -replace '^DA_RewardPool_', ''), $r.Group, $r.Gives, $r.Teaches) $null }
  $lv.EndUpdate(); $g.Count.Text = "$($lv.Items.Count) reward groups"
}
function GD-LootLists {
  if ($script:LootLists) { return $script:LootLists }
  $ip = Join-Path $PSScriptRoot 'catalog\loot-items.csv'; $lp = Join-Path $PSScriptRoot 'catalog\loot-links.csv'
  $its = if (Test-Path -LiteralPath $ip) { @(Import-Csv $ip) } else { @() }; $lks = if (Test-Path -LiteralPath $lp) { @(Import-Csv $lp) } else { @() }
  $usedBy = @{}; $uses = @{}; $kind = @{}
  foreach ($l in $lks) {
    if (-not $usedBy.ContainsKey($l.To)) { $usedBy[$l.To] = New-Object System.Collections.Generic.List[string] }; $usedBy[$l.To].Add($l.From)
    if (-not $uses.ContainsKey($l.From)) { $uses[$l.From] = New-Object System.Collections.Generic.List[string] }; $uses[$l.From].Add($(if ($l.Refs) { "$($l.To) x$($l.Refs)" } else { $l.To }))
    if ($l.FromFolder -notin 'Container', 'Asset') { $kind[$l.From] = $l.FromFolder } }
  $byList = @{}; foreach ($r in $its) { if (-not $byList.ContainsKey($r.List)) { $byList[$r.List] = New-Object System.Collections.Generic.List[object] }; $byList[$r.List].Add($r); $kind[$r.List] = $r.Folder }
  $names = @($byList.Keys) + @($uses.Keys | Where-Object { $kind.ContainsKey($_) }) | Sort-Object -Unique
  $rows = New-Object System.Collections.Generic.List[object]
  foreach ($n in $names) {
    $ent = if ($byList.ContainsKey($n)) { $byList[$n].ToArray() } else { @() }
    $ids = @($ent | ForEach-Object { $_.Item } | Where-Object { GD-CatItem $_ } | Select-Object -Unique)
    $ub = if ($usedBy.ContainsKey($n)) { @($usedBy[$n] | Select-Object -Unique) } else { @() }; $us = if ($uses.ContainsKey($n)) { @($uses[$n]) } else { @() }
    $rows.Add([pscustomobject]@{ Table = 'loot-lists'; Asset = $n; Folder = [string]$kind[$n]; Items = ($ids -join ';'); References = ''; Entries = $ent; UsedBy = $ub; Uses = $us })
  }
  $script:LootLists = $rows.ToArray(); $script:LootUsedBy = $usedBy; return $script:LootLists
}
function GD-FillLoot {
  $g = $script:GD.Loot; $f = $g.Filter.Text.Trim(); $lv = $g.LV; $lv.BeginUpdate(); $lv.Items.Clear()
  foreach ($r in (GD-LootLists)) {
    $itemNames = (@($r.Entries | ForEach-Object { $_.Item } | Where-Object { $_ } | Select-Object -Unique) -join ', ')
    if (-not (Test-Match "$($r.Asset) $($r.Folder) $itemNames $($r.UsedBy -join ' ')" $f)) { continue }
    $cnt = @($r.Entries | Where-Object { $_.Item }).Count; $ent = if ($cnt) { "${cnt}: " + (GD-Trunc $itemNames 90) } else { '(links to other lists)' }
    GD-AddRow $lv $r @(($r.Asset -replace '^DA_', ''), ($r.Folder -replace '^(Survival\\|RandomLists\\)', ''), $ent, (GD-Trunc ($r.UsedBy -join ', ') 70), (GD-Trunc ($r.Uses -join ', ') 70)) $null }
  $lv.EndUpdate(); $g.Count.Text = "$($lv.Items.Count) loot lists"
}
function GD-BuildRows {
  if ($script:BuildRows) { return $script:BuildRows }
  $p = Join-Path $PSScriptRoot 'catalog\building-details.csv'; $rows = New-Object System.Collections.Generic.List[object]
  if (Test-Path -LiteralPath $p) { foreach ($r in (Import-Csv $p)) { $rows.Add([pscustomobject]@{ Table = 'building'; Asset = $r.Asset; Folder = $r.Folder; Items = ''; References = ''; B = $r }) } }
  $script:BuildRows = $rows.ToArray(); return $script:BuildRows
}
function GD-FillBuild {
  $g = $script:GD.Build; $f = $g.Filter.Text.Trim(); $lv = $g.LV; $lv.BeginUpdate(); $lv.Items.Clear()
  foreach ($r in (GD-BuildRows)) { $b = $r.B
    if (-not (Test-Match "$($b.Asset) $($b.ID) $($b.Name) $($b.BuildCost) $($b.Description) $($b.Folder)" $f)) { continue }
    GD-AddRow $lv $r @($b.ID, $b.Name, $b.MaxHealth, (GD-Trunc $b.BuildCost 60), (GD-Trunc $b.Requires 40), ($b.Folder -replace '^Default\\?', '')) $null }
  $lv.EndUpdate(); $g.Count.Text = "$($lv.Items.Count) building parts"
}
function GD-BuildDetail($r) {
  $b = $r.B; $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine("Building part: $($b.Name)   [$($b.Asset)]"); [void]$sb.AppendLine("ID: $($b.ID)     Folder: $($b.Folder)     Category number: $($b.Category)")
  if ($b.Description) { [void]$sb.AppendLine("About: $($b.Description)") }
  [void]$sb.AppendLine(); [void]$sb.AppendLine("Max health:         $($b.MaxHealth)     (can decay: $($b.Decays))")
  [void]$sb.AppendLine("Build cost:         $(if ($b.BuildCost) { $b.BuildCost } else { '(none stored)' })"); [void]$sb.AppendLine("Construction time:  $($b.ConstructionTime)s")
  [void]$sb.AppendLine("Deconstruct refund: $(if ($b.Refund) { $b.Refund } else { '(none)' })"); [void]$sb.AppendLine("Repair cost:        $(if ($b.RepairCost) { $b.RepairCost } else { '(none)' })")
  [void]$sb.AppendLine("Requires:           $(if ($b.Requires) { $b.Requires } else { '(nothing special)' })"); if ($b.Surface) { [void]$sb.AppendLine("Surface:            $($b.Surface)") }
  if ($b.PickupItem) { [void]$sb.AppendLine("Picked up as item:  $($b.PickupItem)") }; [void]$sb.AppendLine("In the build menu:  $($b.InBuildMenu)")
  return $sb.ToString().TrimEnd()
}
function GD-LoreRows {
  if ($script:LoreRows) { return $script:LoreRows }
  $p = Join-Path $PSScriptRoot 'catalog\lore.csv'; $rows = New-Object System.Collections.Generic.List[object]
  if (Test-Path -LiteralPath $p) { foreach ($r in (Import-Csv $p)) { $rows.Add([pscustomobject]@{ Table = 'lore'; Asset = $r.Asset; Folder = $r.Type; Items = ''; References = ''; L = $r }) } }
  $script:LoreRows = $rows.ToArray(); return $script:LoreRows
}
function GD-FillLore {
  $g = $script:GD.Lore; $f = $g.Filter.Text.Trim(); $lv = $g.LV; $lv.BeginUpdate(); $lv.Items.Clear()
  foreach ($r in (GD-LoreRows)) { $l = $r.L; if (-not (Test-Match "$($l.Asset) $($l.ID) $($l.Name) $(if (-not (Get-HideSpoilers)) { "$($l.ShortDescription) $($l.Text)" })" $f)) { continue }
    GD-AddRow $lv $r @($l.Type, $l.Name, (GD-Trunc (GD-Spoil $l.ShortDescription) 50), $l.Lines, (GD-Trunc (GD-Spoil $l.Text) 120)) $null }
  $lv.EndUpdate(); $g.Count.Text = "$($lv.Items.Count) entries"
}
function GD-LoreDetail($r) {
  $l = $r.L; $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine("$($l.Type): $($l.Name)   [$($l.Asset)]"); if ($l.ID) { [void]$sb.AppendLine("ID: $($l.ID)") }; if ($l.ShortDescription) { [void]$sb.AppendLine("Summary: $(GD-Spoil $l.ShortDescription)") }
  if ($l.Audio) { [void]$sb.AppendLine("Audio: $($l.Audio)") }; if ($l.StartsQuest) { [void]$sb.AppendLine("Starts quest: $($l.StartsQuest)") }
  [void]$sb.AppendLine(); if (Get-HideSpoilers) { [void]$sb.AppendLine("  $(GD-Spoil $l.Text)") } else { foreach ($t in ($l.Text -split ' / ')) { [void]$sb.AppendLine("  $t") } }
  return $sb.ToString().TrimEnd()
}
$script:RulesTables = [ordered]@{ 'Gameplay effects' = 'effects'; 'Status effects' = 'statuses'; 'Difficulty compare' = 'difficulty-compare'; 'Difficulty presets' = 'difficulty'; 'Animals' = 'animals'; 'NPCs' = 'npcs'; 'Skills' = 'skills'; 'Attributes' = 'attributes'; 'Plants / farming' = 'plants'; 'Destructibles' = 'destructibles'; 'Random encounters' = 'encounters'; 'Fast travel points' = 'fasttravel'; 'Achievements / statistics' = 'achievements'; 'World locations' = 'locations'; 'Game text (all in-game text)' = 'text' }
function GD-RulesRows([string]$csv) {
  if (-not $script:RulesCache) { $script:RulesCache = @{} }; if ($script:RulesCache.ContainsKey($csv)) { return $script:RulesCache[$csv] }
  $p = Join-Path $PSScriptRoot "catalog\$csv.csv"; $rows = @(); if (Test-Path -LiteralPath $p) { $rows = @(Import-Csv $p) }; $script:RulesCache[$csv] = $rows; return $rows
}
function GD-FillRules {
  $g = $script:GD.Rules; $f = $g.Filter.Text.Trim(); $lv = $g.LV; $label = [string]$g.Combo.SelectedItem; if (-not $label) { return }; $csv = $script:RulesTables[$label]; $rows = GD-RulesRows $csv
  $lv.BeginUpdate(); $lv.Items.Clear()
  if ($g.ShownCsv -ne $csv) { $lv.Columns.Clear(); $cols = @(); if ($rows.Count) { $cols = @($rows[0].PSObject.Properties.Name | Where-Object { $_ -ne 'Asset' } | Select-Object -First 6) }
    foreach ($c in $cols) { $w = switch -Regex ($c) { 'Description|Journal|Modifiers|Settings|FollowUp|Benefit' { 380 } 'Name|Label|Effect|Skill' { 190 } default { 110 } }; [void]$lv.Columns.Add($c, $w) }; $g.ShownCsv = $csv; $g.Cols = $cols }
  $shown = 0; $capped = $false
  foreach ($r in $rows) { if ($shown -ge 1500) { $capped = $true; break }; $sc = @(GD-SpoilCols $csv $r); $hide = (Get-HideSpoilers) -and $sc.Count; $all = (($r.PSObject.Properties | Where-Object { -not ($hide -and $sc -contains $_.Name) }).Value -join ' '); if (-not (Test-Match $all $f)) { continue }; $shown++
    $row = [pscustomobject]@{ Table = 'rules'; Asset = [string]$r.PSObject.Properties.Value[0]; Folder = $label; Items = ''; References = ''; R = $r; Csv = $csv }
    GD-AddRow $lv $row @($g.Cols | ForEach-Object { $v = [string]$r.$_; if ($hide -and $sc -contains $_) { $v = GD-Spoil $v }; GD-Trunc $v 90 }) $null }
  $lv.EndUpdate(); $g.Count.Text = "$($lv.Items.Count) of $($rows.Count) rows$(if ($capped) { ' (first 1500 - type to narrow)' })"
}
function GD-RulesDetail($r) {
  $sb = New-Object System.Text.StringBuilder; [void]$sb.AppendLine("$($r.Folder): $($r.Asset)"); [void]$sb.AppendLine()
  $sc = @(GD-SpoilCols $r.Csv $r.R); foreach ($p in $r.R.PSObject.Properties) { if ($null -ne $p.Value -and "$($p.Value)" -ne '') { $v = $p.Value; if ($sc -contains $p.Name) { $v = GD-Spoil ([string]$v) }; [void]$sb.AppendLine(("{0,-20} {1}" -f ($p.Name + ':'), $v)) } }
  return $sb.ToString().TrimEnd()
}
function GD-QuestState { if ($script:GD.QState) { return $script:GD.QState }; $m = @{}; try { foreach ($q in (Get-PlayerData $script:SavePath).Quests.Quests) { $m[$q.Quest] = $q.State } } catch { }; $script:GD.QState = $m; return $m }
function GD-QuestData {
  if ($script:QData) { return $script:QData }
  $d = @{ Quests = @(); States = @{}; Branches = @{}; Objs = @{} }; $c = Join-Path $PSScriptRoot 'catalog'
  if (Test-Path -LiteralPath "$c\quests-detail.csv") {
    $d.Quests = @(Import-Csv "$c\quests-detail.csv")
    foreach ($s in (Import-Csv "$c\quest-states.csv")) { if (-not $d.States.ContainsKey($s.Quest)) { $d.States[$s.Quest] = New-Object System.Collections.Generic.List[object] }; $d.States[$s.Quest].Add($s) }
    foreach ($b in (Import-Csv "$c\quest-branches.csv")) { if (-not $d.Branches.ContainsKey($b.Quest)) { $d.Branches[$b.Quest] = New-Object System.Collections.Generic.List[object] }; $d.Branches[$b.Quest].Add($b) }
    foreach ($o in (Import-Csv "$c\quest-objectives.csv")) { $k = "$($o.Quest)|$($o.BranchID)"; if (-not $d.Objs.ContainsKey($k)) { $d.Objs[$k] = New-Object System.Collections.Generic.List[object] }; $d.Objs[$k].Add($o) } }
  foreach ($name in 'States', 'Branches', 'Objs') { foreach ($k in @($d[$name].Keys)) { $d[$name][$k] = $d[$name][$k].ToArray() } }   # List[object] cannot be wrapped in @() here
  $script:QData = $d; return $d
}
function GD-StateType([string]$quest, [string]$state) {
  if (-not $state) { return '' }; $d = GD-QuestData; $cs = @($d.States[$quest]) | Where-Object { $_.StateID -eq $state } | Select-Object -First 1; if ($cs) { return [string]$cs.Type }; return ''
}
function GD-ObjText($o) { $t = $o.Objective; if ($o.Description) { return "$t - $($o.Description)" }; $p = [string]$o.Parameters; if ($p.Length -gt 120) { $p = $p.Substring(0, 117) + '...' }; if ($p) { return "$t ($p)" }; return $t }
function GD-QuestDetail($r) {
  $d = GD-QuestData; $q = $r.Q; $st = GD-QuestState; $cur = $st[$q.Quest]; $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine("Quest:   $($q.Name)   [$($q.Quest)]"); [void]$sb.AppendLine("Kind:    $(if ($q.Main -eq 'True') { 'Main quest' } else { 'Side / other' })     Quest ID: $($q.QuestID)     Chain: $($q.Chain)")
  if ($q.GeneralObjective) { [void]$sb.AppendLine("Goal:    $(GD-Spoil $q.GeneralObjective)") }; if ($q.Description) { [void]$sb.AppendLine("About:   $(GD-Spoil $q.Description)") }
  $states = @($d.States[$q.Quest]); $branches = @($d.Branches[$q.Quest])
  if ($cur) { $cs = $states | Where-Object { $_.StateID -eq $cur } | Select-Object -First 1
    [void]$sb.AppendLine(); [void]$sb.AppendLine("YOUR STATE: $cur$(if ($cs) { "  ($($cs.Type))" })"); if ($cs -and $cs.Description) { [void]$sb.AppendLine("   $(GD-Spoil $cs.Description)") }
    $next = @($branches | Where-Object { ($_.From -split '; ') -contains $cur })
    if ($next.Count) { [void]$sb.AppendLine('   To move on, finish ALL tasks of one branch:'); foreach ($b in $next) { [void]$sb.AppendLine("   - branch $($b.BranchID)  ->  state $($b.To)"); foreach ($o in @($d.Objs["$($q.Quest)|$($b.BranchID)"])) { [void]$sb.AppendLine("       task: $(GD-ObjText $o)") } } }
    elseif ($cs -and $cs.Type -match 'Success|Fail') { [void]$sb.AppendLine('   (this is an end state)') } }
  else { [void]$sb.AppendLine(); [void]$sb.AppendLine('Your state: not started / not in your save') }
  $nd = @(GD-QuestNeeds $q.Quest $cur); if ($nd.Count) { [void]$sb.AppendLine(); [void]$sb.AppendLine('Items this step needs (the button below queues them):'); foreach ($n in $nd) { [void]$sb.AppendLine("   $($n.id) x$($n.amount)   - $($n.why)") } }
  [void]$sb.AppendLine(); [void]$sb.AppendLine("All states ($($states.Count)):")
  foreach ($s in $states) { $dsc = [string]$s.Description; if ($dsc.Length -gt 150) { $dsc = $dsc.Substring(0, 147) + '...' }; $dsc = GD-Spoil $dsc
    [void]$sb.AppendLine("   $(if ($s.StateID -eq $cur) { '>> ' } else { '   ' })$($s.StateID) [$($s.Type)$(if ($s.IsStart -eq 'True') { ', start' })] $dsc$(if ($s.Events) { '   events: ' + $s.Events })") }
  [void]$sb.AppendLine(); [void]$sb.AppendLine("Branches ($($branches.Count)):  from state  ->  to state   (tasks, all required)")
  foreach ($b in $branches) { [void]$sb.AppendLine("   $($b.BranchID):  $($b.From)  ->  $($b.To)$(if ($b.Events) { '   events: ' + $b.Events })"); foreach ($o in @($d.Objs["$($q.Quest)|$($b.BranchID)"])) { [void]$sb.AppendLine("        task: $(GD-ObjText $o)") } }
  return $sb.ToString().TrimEnd()
}
function GD-FillQuests {
  $g = $script:GD.Quests; $f = $g.Filter.Text.Trim(); $lv = $g.LV; $lv.BeginUpdate(); $lv.Items.Clear(); $st = GD-QuestState; $d = GD-QuestData
  foreach ($q in $d.Quests) {
    $state = $st[$q.Quest]; if (-not (Test-Match "$($q.Quest) $($q.Name) $($q.QuestID) $($q.Chain) $(if (-not (Get-HideSpoilers)) { $q.Description }) $state" $f)) { continue }
    $cl = $null; $stType = GD-StateType $q.Quest $state; if ($state) { $cl = if ($stType -match 'Success' -or $state -match 'End|Success|Final') { $script:Th.Good } elseif ($stType -match 'Fail') { $script:Th.Bad } else { $script:Th.Accent } }
    $row = [pscustomobject]@{ Table = 'quest-graph'; Asset = $q.Quest; Folder = $q.Chain; Items = ''; References = ''; Q = $q }
    GD-AddRow $lv $row @($q.Quest, $q.Name, $(if ($q.Main -eq 'True') { 'Main' } else { 'Side' }), $(if ($state) { $state + $(if ($stType) { " ($stType)" } else { '' }) } else { '' }), ($q.Chain -replace '^Quests\\', '')) $cl }
  $lv.EndUpdate(); $g.Count.Text = "$($lv.Items.Count) quests"
}
function GD-FillRecipes {
  $g = $script:GD.Recipes; $f = $g.Filter.Text.Trim(); $lv = $g.LV; $lv.BeginUpdate(); $lv.Items.Clear()
  $known = @{}; try { foreach ($k in (Get-PlayerData $script:SavePath).Known) { $known[$k] = 1 } } catch { }
  if (-not $script:RecipeDet) { $script:RecipeDet = @{}; $rp = Join-Path $PSScriptRoot 'catalog\recipe-details.csv'; if (Test-Path -LiteralPath $rp) { foreach ($d in (Import-Csv $rp)) { $script:RecipeDet[$d.Recipe] = $d } } }
  $det = $script:RecipeDet
  foreach ($t in 'crafting-recipes', 'learning-recipes') { foreach ($r in (GD-Rows $t)) {
    $isL = ($t -eq 'learning-recipes'); $path = "/Game/Permafrost/Blueprints/$($r.Folder)/$($r.Asset).$($r.Asset)"; $kn = if (-not $isL) { '' } elseif ($known.ContainsKey($path)) { 'learned' } else { 'not learned' }
    $dt = $det[$r.Asset]; $ing = if ($dt) { "$($dt.Ingredients)  =>  $($dt.Result) x$($dt.ResultAmount)   [$($dt.Station)$(if ($dt.Time) { ', ' + $dt.Time + 's' })]" } elseif ($isL) { $li = GD-LearnInfo $r.Asset; $rw = @(GD-RewardsFor $r.Asset); $rwTxt = if ($rw.Count) { "   reward: " + ($rw -join ", ") } else { "" }; if ($li -and $li.Members) { "Set of: " + ($li.Members -replace ";", ", ") + $rwTxt } elseif ($li) { $tn = if ($li.DisplayName) { $li.DisplayName + $(if ($li.Teaches -and $li.Teaches -ne $li.DisplayName) { " [$($li.Teaches)]" } else { "" }) } elseif ($li.Teaches) { $li.Teaches } else { $r.Asset -replace "^DA_Learn[A-Za-z]*?_", "" }; "Teaches $tn" + $(if ($li.Methods) { " (learned by: " + ($li.Methods -replace ";", " + ") + $(if ($li.Cost) { ", cost $($li.Cost)" } else { "" }) + ")" } else { "" }) + $rwTxt } else { $r.Items } } else { $r.Items }
    if (-not (Test-Match "$($r.Asset) $ing $($r.References) $kn" $f)) { continue }
    $nm = ($r.Asset -replace '^DA_[A-Za-z]*?_', ''); $cl = if ($kn -eq 'learned') { $script:Th.Muted } else { $null }
    $rowObj = if ($dt) { [pscustomobject]@{ Table = 'craft'; Asset = $r.Asset; Folder = $r.Folder; Items = ''; References = $r.References; Rec = $dt } } else { $r }; GD-AddRow $lv $rowObj @($nm, $(if ($isL) { 'Learning recipe' } else { 'Crafting recipe' }), $kn, (GD-Trunc $ing 90), (GD-Trunc $r.References 80)) $cl } }
  $lv.EndUpdate(); $g.Count.Text = "$($lv.Items.Count) recipes"
}
function GD-FillTables {
  $g = $script:GD.Tables; $f = $g.Filter.Text.Trim(); $lv = $g.LV; $name = [string]$g.Combo.SelectedItem; if (-not $name) { return }
  $lv.BeginUpdate(); $lv.Items.Clear(); $n = 0
  foreach ($r in (GD-Rows $name)) { if (-not (Test-Match "$($r.Asset) $($r.Folder) $($r.Items) $($r.References)" $f)) { continue }; $n++; if ($lv.Items.Count -lt 3000) { GD-AddRow $lv $r @($r.Asset, $r.Group, $r.Folder, (GD-Trunc $r.Items 60), (GD-Trunc $r.References 110)) $null } }
  $lv.EndUpdate(); $g.Count.Text = "$n rows" + $(if ($n -gt 3000) { ' (first 3000 shown)' } else { '' })
}

# ---------- bundles ----------
function GD-Bundles {
  $b = New-Object System.Collections.Generic.List[object]
  $q = @($script:Cat | Where-Object { $_.category -eq 'QuestItems' } | ForEach-Object { @{ id = $_.id; count = 1 } }); $b.Add(@{ Name = 'Quest items (all keys, packages, trophies)'; Info = 'One of each item in the QuestItems category.'; Items = $q })
  $am = @($script:Cat | Where-Object { $_.category -eq 'Projectiles' -and $_.id -notlike '*Enemy' -and $_.id -ne 'GlowingStick' } | ForEach-Object { @{ id = $_.id; count = [int]$_.stackSize } }); $b.Add(@{ Name = 'One full stack of every ammo type'; Info = 'Every ammo/arrow/flare type, one full stack each (stack sizes from the game data).'; Items = $am })
  $carry = @(); try { foreach ($r in (Get-InventoryView $script:SavePath)) { $c = GD-CatItem $r.Item; if ($c -and $c.usesAmmo) { foreach ($a in @($c.usesAmmo)) { $ac = GD-CatItem $a; if ($ac -and -not ($carry | Where-Object { $_.id -eq $a })) { $carry += @{ id = $a; count = [int]$ac.stackSize } } } } } } catch { }
  $b.Add(@{ Name = 'Ammo for the weapons you are carrying now'; Info = 'Reads your inventory, finds each weapon, adds one full stack of its ammo.'; Items = $carry })
  foreach ($p in (GD-PoolList)) { $its = @(GD-RowItems $p | ForEach-Object { @{ id = $_; count = 1 } }); if ($its.Count) { $b.Add(@{ Name = 'Reward pool: ' + ($p.Asset -replace '^DA_RewardPool_', ''); Info = 'One of each item that pool can give.'; Items = $its }) } }
  return $b.ToArray()
}
function GD-FillBundles {
  $g = $script:GD.Bundles; $lv = $g.LV; $lv.Items.Clear(); $g.Detail.Text = ''
  foreach ($bd in (GD-Bundles)) { GD-AddRow $lv $bd @($bd.Name, [string]@($bd.Items).Count, (($bd.Items | ForEach-Object { "$($_.id) x$($_.count)" }) -join ', ')) $null }
}
function GD-BundleSelect { $g = $script:GD.Bundles; if ($g.LV.SelectedItems.Count) { $bd = $g.LV.SelectedItems[0].Tag; $g.Detail.Text = "$($bd.Name)`r`n$($bd.Info)`r`n`r`n" + (($bd.Items | ForEach-Object { "   $($_.id)  x$($_.count)" }) -join "`r`n") } }
function GD-QueueBundle {
  $g = $script:GD.Bundles; if ($g.LV.SelectedItems.Count -eq 0) { $g.Msg.Text = 'Pick a bundle first.'; return }
  $bd = $g.LV.SelectedItems[0].Tag; if (@($bd.Items).Count -eq 0) { $g.Msg.Text = 'That bundle is empty.'; return }
  foreach ($it in $bd.Items) { [void](& $script:QueueAdder $it.id $it.count) }
  $g.Msg.Text = "Queued $(@($bd.Items).Count) item(s) from '$($bd.Name)'. Check them in the Queue (main window), then Preview / Apply."
}

# ---------- the window ----------
function New-DataForm {
  Add-Type -AssemblyName System.Windows.Forms; Add-Type -AssemblyName System.Drawing
  $script:GD = @{}; $script:TableCache = @{}; $script:AllRowsCache = $null
  $f = New-Object System.Windows.Forms.Form; $f.Text = 'Game data  -  everything found in the game files'; $f.Size = New-Object System.Drawing.Size(1250, 800); $f.MinimumSize = New-Object System.Drawing.Size(1000, 640)
  $f.StartPosition = 'CenterParent'; $f.Font = New-Object System.Drawing.Font('Segoe UI', 9); $script:GD.Form = $f
  $spPanel = New-Object System.Windows.Forms.Panel; $spPanel.Dock = 'Top'; $spPanel.Height = 28; $f.Controls.Add($spPanel)
  $spChk = New-Object System.Windows.Forms.CheckBox; $spChk.Text = 'Hide story text (spoilers) - quest descriptions, recordings, dialogue and NPC journals'; $spChk.AutoSize = $true; $spChk.Location = '10,5'; $spChk.Checked = (Get-HideSpoilers); $spChk.ForeColor = $script:Th.Text; $spPanel.Controls.Add($spChk)
  $spChk.Add_CheckedChanged({ Set-HideSpoilers $this.Checked; GD-RefreshAll; GD-OnSelect })
  $tabs = New-Object ThemedTabs; $tabs.Dock = 'Fill'; $f.Controls.Add($tabs); $tabs.BringToFront(); $script:GD.Tabs = $tabs

  $g = GD-MakeTab $tabs 'Find' 'Find anything' @('Table', 'Asset', 'Items', 'Linked to', 'Folder') @(120, 330, 200, 420, 260) 'Try: KeyAnnas   Anna   Whiskey   Sean   heater   bear   bunker   radio'
  GD-WireTab $g ${function:GD-FillFind}
  $g = GD-MakeTab $tabs 'Pools' 'Reward pools' @('Reward pool', 'Reward group', 'Gives (amount)', 'Teaches recipes') @(200, 260, 480, 330) 'Each quest reward group with its exact items and amounts, read from the game files.'
  GD-WireTab $g ${function:GD-FillPools}
  $g = GD-MakeTab $tabs 'Quests' 'Quests' @('Quest', 'In-game name', 'Kind', 'Your state', 'Chain') @(330, 260, 60, 150, 380) 'Green = finished in your save, blue = started. Pick a quest to see every state, the tasks to leave each one, and where you are.'
  GD-WireTab $g ${function:GD-FillQuests}
  $g = GD-MakeTab $tabs 'Recipes' 'Recipes' @('Recipe', 'Kind', 'In your save', 'Ingredients  =>  result', 'Linked to') @(300, 130, 110, 420, 280) 'Crafting recipes show ingredient amounts and what they make, read from the game files. Use Player tools > Recipes to learn them.'
  GD-WireTab $g ${function:GD-FillRecipes}
  $g = GD-MakeTab $tabs 'Loot' 'Loot tables' @('Loot list', 'Type', 'Items (count: names)', 'Used by', 'Refers to') @(300, 160, 430, 260, 220) 'Loot lists and which containers use them. Pick a row for the exact items and the numbers stored with each.'
  GD-WireTab $g ${function:GD-FillLoot}
  $g = GD-MakeTab $tabs 'Build' 'Building parts' @('Part', 'In-game name', 'Max health', 'Build cost', 'Requires', 'Group') @(220, 220, 80, 330, 220, 150) 'Everything you can build: cost, health, refund, repair cost and requirements, read from the game files.'
  GD-WireTab $g ${function:GD-FillBuild}
  $g = GD-MakeTab $tabs 'Lore' 'Recordings and notes' @('Kind', 'Name', 'Summary', 'Lines', 'Text') @(110, 240, 330, 50, 520) 'Recordings, radio messages and notes with their text. Search the text, e.g. Anna, bunker, flare.'
  GD-WireTab $g ${function:GD-FillLore}
  $g = GD-MakeTab $tabs 'Rules' 'Game rules' @('Name') @(300) 'Effects, status effects, difficulty presets, animals, NPCs, skills and attributes - pick one from the box. Pick a row for every field.'
  $g.Combo = New-Object System.Windows.Forms.ComboBox; $g.Combo.DropDownStyle = 'DropDownList'; $g.Combo.Location = '600,8'; $g.Combo.Size = '230,24'; $g.Hint.Visible = $false; $g.Top.Controls.Add($g.Combo)
  foreach ($n in $script:RulesTables.Keys) { [void]$g.Combo.Items.Add($n) }; $g.Combo.SelectedIndex = 0; $g.Combo.Add_SelectedIndexChanged({ GD-FillRules }); $g.Count.Left = 840
  GD-WireTab $g ${function:GD-FillRules}
  $g = GD-MakeTab $tabs 'Tables' 'All tables' @('Asset', 'Group', 'Folder', 'Items', 'Linked to') @(330, 130, 280, 200, 400) 'Pick any table from the box: loot, containers, NPCs, animals, locations, building parts, ...'
  $g.Combo = New-Object System.Windows.Forms.ComboBox; $g.Combo.DropDownStyle = 'DropDownList'; $g.Combo.Location = '600,8'; $g.Combo.Size = '230,24'; $g.Hint.Visible = $false; $g.Top.Controls.Add($g.Combo)
  foreach ($n in (@('blueprints-index') + $script:DomainTables)) { [void]$g.Combo.Items.Add($n) }; $g.Combo.SelectedIndex = 0; $g.Combo.Add_SelectedIndexChanged({ GD-FillTables })
  $g.Count.Left = 840; GD-WireTab $g ${function:GD-FillTables}

  # bundles tab (different bottom row)
  $tab = New-Object System.Windows.Forms.TabPage; $tab.Text = 'Bundles'; $tab.Padding = New-Object System.Windows.Forms.Padding(8); $tabs.TabPages.Add($tab)
  $bg = @{}; $script:GD.Bundles = $bg; $bg.Panel = $tab
  $bot = New-Object System.Windows.Forms.Panel; $bot.Dock = 'Bottom'; $bot.Height = 250; $tab.Controls.Add($bot)
  $qp = New-Object System.Windows.Forms.Panel; $qp.Dock = 'Bottom'; $qp.Height = 40; $bot.Controls.Add($qp)
  $bg.Detail = New-Object System.Windows.Forms.TextBox; $bg.Detail.Multiline = $true; $bg.Detail.ReadOnly = $true; $bg.Detail.ScrollBars = 'Vertical'; $bg.Detail.Dock = 'Fill'; $bg.Detail.Font = New-Object System.Drawing.Font('Consolas', 9.5); $bg.Detail.BackColor = [System.Drawing.Color]::White; $bot.Controls.Add($bg.Detail); $bg.Detail.BringToFront()
  $bq = New-Btn $qp 'Queue this bundle' 0 6 200 28; $bq.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold); $bg.Msg = New-Lbl $qp '' 214 12 900; $bg.Msg.ForeColor = $script:Th.Accent
  $bg.LV = New-LV $tab @('Bundle', 'Items', 'Contents') @(380, 60, 760); $bg.LV.Dock = 'Fill'; $bg.LV.BringToFront()
  $bg.LV.Add_SelectedIndexChanged({ GD-BundleSelect }); $bq.Add_Click({ GD-QueueBundle })

  $tabs.Add_SelectedIndexChanged({ if ($script:GD.Tabs.SelectedTab -eq $script:GD.Bundles.Panel) { if ($script:GD.Bundles.LV.Items.Count -eq 0) { GD-FillBundles } } else { GD-RefreshAll } })
  GD-FillFind; Apply-Theme $f; Set-AppIcon $f; return $f
}
function Show-GameData($owner) { $f = New-DataForm; $script:ActiveForm = $f; try { [void]$f.ShowDialog($owner) } finally { $script:ActiveForm = $null } }
