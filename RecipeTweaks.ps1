# RecipeTweaks.ps1 - the "Recipe tweaks" window. Edit crafting recipes (ingredient amounts, how many a craft makes, crafting time); Save writes
# tweaks.lua into the game's UE4SS mod folder, where the RecipeTweaks mod (RecipeTweaksMod\main.lua) applies it inside the running game.
# Nothing in your save is touched. Needs PlayerTools.ps1 (helpers) and catalog\recipe-details.csv (Build-Recipes.ps1).
$script:RT = @{}
$script:RtModsDirOverride = $null     # tests point this at a temporary folder

function RT-ModsDir {
  if ($script:RtModsDirOverride) { return $script:RtModsDirOverride }
  # SavePath = ...\Permafrost\Permafrost\SaveGame\World#2.pfs  ->  ...\Permafrost\Permafrost\Binaries\Win64\ue4ss\Mods
  $root = Split-Path (Split-Path $script:SavePath -Parent) -Parent
  return (Join-Path $root 'Binaries\Win64\ue4ss\Mods')
}
function RT-ModDir { return (Join-Path (RT-ModsDir) 'RecipeTweaks') }
$script:RtStateOverride = $null
function RT-StatePath { if ($script:RtStateOverride) { return $script:RtStateOverride }; return (Join-Path $PSScriptRoot 'recipe-tweaks.json') }
$script:RtInv = [Globalization.CultureInfo]::InvariantCulture

function RT-ParseAmounts([string]$text) {   # 'Cloth x8; Wood x2' -> list of @{Name; Amount}
  $out = New-Object System.Collections.Generic.List[object]
  foreach ($part in ($text -split '; ')) { if ($part -match '^(.*) x(\d+)$') { $out.Add([pscustomobject]@{ Name = $Matches[1]; Amount = [int]$Matches[2] }) } }
  return $out.ToArray()
}
function RT-LoadRecipes {
  $p = Join-Path $PSScriptRoot 'catalog\recipe-details.csv'; $rows = New-Object System.Collections.Generic.List[object]
  if (-not (Test-Path -LiteralPath $p)) { return @() }
  foreach ($r in (Import-Csv $p)) {
    $ing = RT-ParseAmounts $r.Ingredients; $res = RT-ParseAmounts $(if ($r.AllResults) { $r.AllResults } else { "$($r.Result) x$($r.ResultAmount)" })
    $tm = 0.0; $null = [double]::TryParse([string]$r.Time, [Globalization.NumberStyles]::Float, $script:RtInv, [ref]$tm); if ($tm -eq 0 -and $r.Time) { $null = [double]::TryParse([string]$r.Time, [ref]$tm) }
    $rows.Add([pscustomobject]@{ Recipe = $r.Recipe; Name = $(if ($r.Name) { $r.Name } else { ($r.Recipe -replace '^DA_CraftingRecipe_', '') }); Station = $r.Station; Category = $r.Category
        Ing = $ing; Res = $res; Time = $tm
        Cur = @{ cost = [int[]]@($ing | ForEach-Object { $_.Amount }); result = [int[]]@($res | ForEach-Object { $_.Amount }); time = $tm } })
  }
  return $rows.ToArray()
}
function RT-IsChanged($row) {
  $c = $row.Cur
  for ($i = 0; $i -lt $row.Ing.Count; $i++) { if ($c.cost[$i] -ne $row.Ing[$i].Amount) { return $true } }
  for ($i = 0; $i -lt $row.Res.Count; $i++) { if ($c.result[$i] -ne $row.Res[$i].Amount) { return $true } }
  return ([math]::Abs($c.time - $row.Time) -gt 0.001)
}
function RT-Reset($row) { $row.Cur.cost = [int[]]@($row.Ing | ForEach-Object { $_.Amount }); $row.Cur.result = [int[]]@($row.Res | ForEach-Object { $_.Amount }); $row.Cur.time = $row.Time }
function RT-LoadState($rows) {   # remembered edits (recipe-tweaks.json)
  $p = RT-StatePath; if (-not (Test-Path -LiteralPath $p)) { return }
  try { $st = Get-Content $p -Raw | ConvertFrom-Json } catch { return }
  $by = @{}; foreach ($r in $rows) { $by[$r.Recipe] = $r }
  foreach ($prop in $st.recipes.PSObject.Properties) { $r = $by[$prop.Name]; if (-not $r) { continue }; $v = $prop.Value
    if ($v.cost -and @($v.cost).Count -eq $r.Ing.Count) { $r.Cur.cost = [int[]]@($v.cost) }
    if ($v.result -and @($v.result).Count -eq $r.Res.Count) { $r.Cur.result = [int[]]@($v.result) }
    if ($null -ne $v.time) { $r.Cur.time = [double]$v.time } }
}
function RT-Fmt([double]$v) { return $v.ToString('0.##', $script:RtInv) }
function RT-Scale([int]$orig, [double]$mult) { if ($orig -le 0) { return $orig }; return [int][math]::Max(1, [math]::Round($orig * $mult, [MidpointRounding]::AwayFromZero)) }

function RT-WriteFiles($rows) {   # state json (always) + tweaks.lua (when the mod folder exists)
  $changed = @($rows | Where-Object { RT-IsChanged $_ } | Sort-Object Recipe)
  $state = [ordered]@{}; $lua = New-Object System.Text.StringBuilder
  [void]$lua.AppendLine('-- Written by the Permafrost Item Tool ("Recipe tweaks"). These values replace the game''s; recipes not listed keep the game''s own values.')
  [void]$lua.AppendLine('return {'); [void]$lua.AppendLine('  version = 1,'); [void]$lua.AppendLine('  recipes = {')
  foreach ($r in $changed) {
    $state[$r.Recipe] = [ordered]@{ cost = $r.Cur.cost; result = $r.Cur.result; time = $r.Cur.time }
    [void]$lua.AppendLine(("    [`"{0}`"] = {{ cost = {{{1}}}, result = {{{2}}}, time = {3} }}, -- {4}" -f $r.Recipe, ($r.Cur.cost -join ', '), ($r.Cur.result -join ', '), (RT-Fmt $r.Cur.time), ($r.Name -replace '[\r\n]', ' ')))
  }
  [void]$lua.AppendLine('  },'); [void]$lua.AppendLine('}')
  ([ordered]@{ recipes = $state } | ConvertTo-Json -Depth 5) | Set-Content (RT-StatePath) -Encoding utf8
  $dir = RT-ModDir; $wrote = $false
  if (Test-Path -LiteralPath $dir) { [IO.File]::WriteAllText((Join-Path $dir 'tweaks.lua'), $lua.ToString(), (New-Object Text.UTF8Encoding($false))); $wrote = $true }
  return @{ Changed = $changed.Count; WroteLua = $wrote; LuaPath = (Join-Path $dir 'tweaks.lua') }
}

function RT-ModStatus {   # text + whether it is installed/enabled
  $dir = RT-ModDir; $main = Join-Path $dir 'Scripts\main.lua'; $src = Join-Path $PSScriptRoot 'RecipeTweaksMod\main.lua'
  if (-not (Test-Path -LiteralPath (RT-ModsDir))) { return @{ Ok = $false; Text = 'UE4SS Mods folder not found next to your save - the game mod cannot be installed from here.' } }
  if (-not (Test-Path -LiteralPath $main)) { return @{ Ok = $false; Text = 'The in-game mod is NOT installed yet - press "Install / update mod".' } }
  $mt = Join-Path (RT-ModsDir) 'mods.txt'; $enabled = (Test-Path -LiteralPath $mt) -and ((Get-Content $mt -Raw) -match '(?m)^\s*RecipeTweaks\s*:\s*1')
  if (-not $enabled) { return @{ Ok = $false; Text = 'The mod is installed but switched off in mods.txt - press "Install / update mod" to switch it on.' } }
  if ((Test-Path -LiteralPath $src) -and ((Get-FileHash $main).Hash -ne (Get-FileHash $src).Hash)) { return @{ Ok = $false; Text = 'The in-game mod is an older version - press "Install / update mod".' } }
  $st = Join-Path $dir 'status.txt'; $last = if (Test-Path -LiteralPath $st) { 'Last applied in the game: ' + (Get-Content $st -Raw).Trim() } else { 'Installed. It has not applied anything yet (start the game).' }
  return @{ Ok = $true; Text = $last }
}
function RT-InstallMod {
  $mods = RT-ModsDir; if (-not (Test-Path -LiteralPath $mods)) { throw "UE4SS Mods folder not found: $mods" }
  $src = Join-Path $PSScriptRoot 'RecipeTweaksMod\main.lua'; if (-not (Test-Path -LiteralPath $src)) { throw 'RecipeTweaksMod\main.lua is missing next to the tool.' }
  $dir = RT-ModDir; New-Item -ItemType Directory -Force (Join-Path $dir 'Scripts') | Out-Null
  Copy-Item -LiteralPath $src -Destination (Join-Path $dir 'Scripts\main.lua') -Force
  if (-not (Test-Path -LiteralPath (Join-Path $dir 'tweaks.lua'))) { [IO.File]::WriteAllText((Join-Path $dir 'tweaks.lua'), "return {`r`n  version = 1,`r`n  recipes = {},`r`n}`r`n", (New-Object Text.UTF8Encoding($false))) }
  $mt = Join-Path $mods 'mods.txt'; $lines = New-Object System.Collections.Generic.List[string]; if (Test-Path -LiteralPath $mt) { foreach ($l in (Get-Content $mt)) { $lines.Add($l) } }
  $bk = "$mt.bak-before-recipetweaks"; if ((Test-Path -LiteralPath $mt) -and -not (Test-Path -LiteralPath $bk)) { Copy-Item -LiteralPath $mt -Destination $bk }
  $ix = -1; for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*RecipeTweaks\s*:') { $ix = $i; break } }
  if ($ix -ge 0) { $lines[$ix] = 'RecipeTweaks : 1' }
  else { $cm = -1; for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*;.*[Bb]uilt-in keybinds') { $cm = $i; break } }
    $last = -1; $lim = $(if ($cm -ge 0) { $cm } else { $lines.Count }); for ($i = 0; $i -lt $lim; $i++) { if ($lines[$i] -match '^\S+\s*:\s*[01]\s*$') { $last = $i } }
    $lines.Insert($last + 1, 'RecipeTweaks : 1') }
  [IO.File]::WriteAllText($mt, (($lines -join "`r`n") + "`r`n"), (New-Object Text.UTF8Encoding($false)))
}

# ---------------- the window ----------------
function RT-RefreshList {
  $ui = $script:RT; $f = $ui.Filter.Text.Trim(); $st = [string]$ui.Station.SelectedItem; $lv = $ui.LV
  $lv.BeginUpdate(); $lv.Items.Clear(); $ui.Shown = New-Object System.Collections.Generic.List[object]
  foreach ($r in $ui.Rows) {
    if ($st -and $st -ne 'All stations' -and $r.Station -ne $st) { continue }
    if (-not (Test-Match "$($r.Name) $($r.Recipe) $($r.Station) $(($r.Ing | ForEach-Object { $_.Name }) -join ' ') $(($r.Res | ForEach-Object { $_.Name }) -join ' ')" $f)) { continue }
    $li = New-Object System.Windows.Forms.ListViewItem($r.Name); $li.Tag = $r; for ($k = 0; $k -lt 5; $k++) { [void]$li.SubItems.Add('') }
    RT-FillItem $li $r; [void]$lv.Items.Add($li); $ui.Shown.Add($r) }
  $lv.EndUpdate(); $ui.Count.Text = "$($lv.Items.Count) of $($ui.Rows.Count) recipes shown"; RT-UpdateStatus
}
function RT-FillItem($li, $r) {
  $c = $r.Cur; $ch = RT-IsChanged $r
  $ing = for ($i = 0; $i -lt $r.Ing.Count; $i++) { "$($r.Ing[$i].Name) x$($c.cost[$i])" + $(if ($c.cost[$i] -ne $r.Ing[$i].Amount) { '*' } else { '' }) }
  $res = for ($i = 0; $i -lt $r.Res.Count; $i++) { "$($r.Res[$i].Name) x$($c.result[$i])" + $(if ($c.result[$i] -ne $r.Res[$i].Amount) { '*' } else { '' }) }
  $li.SubItems[1].Text = $r.Station; $li.SubItems[2].Text = ($ing -join '; '); $li.SubItems[3].Text = ($res -join '; ')
  $li.SubItems[4].Text = (RT-Fmt $c.time) + 's' + $(if ([math]::Abs($c.time - $r.Time) -gt 0.001) { '*' } else { '' }); $li.SubItems[5].Text = $(if ($ch) { 'CHANGED' } else { '' })
  $li.ForeColor = $(if ($ch) { $script:Th.Accent } else { $script:Th.Text })
}
function RT-UpdateStatus {
  $ui = $script:RT; $n = @($ui.Rows | Where-Object { RT-IsChanged $_ }).Count
  $ui.Summary.Text = "$n recipe(s) changed from the game's values.   " + $(if ($ui.Dirty) { 'Unsaved changes - press Save.' } else { 'Saved.' })
  $ms = RT-ModStatus; $ui.ModLbl.Text = $ms.Text; $ui.ModLbl.ForeColor = $(if ($ms.Ok) { $script:Th.Good } else { $script:Th.Warn })
}
function RT-LoadEditor {
  $ui = $script:RT; $ui.Loading = $true
  try { $r = $null; if ($ui.LV.SelectedItems.Count) { $r = $ui.LV.SelectedItems[0].Tag }; $ui.Sel = $r
    for ($i = 0; $i -lt 8; $i++) { $show = ($r -and $i -lt $r.Ing.Count); $ui.IngLbl[$i].Visible = $show; $ui.IngNum[$i].Visible = $show; if ($show) { $ui.IngLbl[$i].Text = "$($r.Ing[$i].Name)  (game: $($r.Ing[$i].Amount))"; Set-Num $ui.IngNum[$i] $r.Cur.cost[$i] } }
    for ($i = 0; $i -lt 2; $i++) { $show = ($r -and $i -lt $r.Res.Count); $ui.ResLbl[$i].Visible = $show; $ui.ResNum[$i].Visible = $show; if ($show) { $ui.ResLbl[$i].Text = "Makes $($r.Res[$i].Name)  (game: $($r.Res[$i].Amount))"; Set-Num $ui.ResNum[$i] $r.Cur.result[$i] } }
    $ui.TimeLbl.Visible = [bool]$r; $ui.TimeNum.Visible = [bool]$r; $ui.ResetOne.Enabled = [bool]$r
    if ($r) { $ui.Title.Text = "$($r.Name)   -   $($r.Station)"; $ui.TimeLbl.Text = "Crafting time, seconds  (game: $(RT-Fmt $r.Time))"; Set-Num $ui.TimeNum $r.Cur.time } else { $ui.Title.Text = 'Pick a recipe in the list to edit it.' }
  } finally { $ui.Loading = $false }
}
function RT-EditorChanged {
  $ui = $script:RT; if ($ui.Loading -or -not $ui.Sel) { return }; $r = $ui.Sel
  for ($i = 0; $i -lt $r.Ing.Count -and $i -lt 8; $i++) { $r.Cur.cost[$i] = [int]$ui.IngNum[$i].Value }
  for ($i = 0; $i -lt $r.Res.Count -and $i -lt 2; $i++) { $r.Cur.result[$i] = [int]$ui.ResNum[$i].Value }
  $r.Cur.time = [double]$ui.TimeNum.Value; $ui.Dirty = $true
  if ($ui.LV.SelectedItems.Count) { RT-FillItem $ui.LV.SelectedItems[0] $r }; RT-UpdateStatus
}
function RT-ApplyGlobal {
  $ui = $script:RT; $mr = [double]$ui.MulRes.Value; $mc = [double]$ui.MulCost.Value; $mt = [double]$ui.MulTime.Value
  if ($mr -eq 1 -and $mc -eq 1 -and $mt -eq 1) { $ui.Msg.Text = 'Nothing to multiply: all three boxes are 1. Set "Amount made", "Ingredient costs" or "Crafting time" to something other than 1 first.'; return }
  $n = 0; $shown = $ui.Shown.ToArray()
  foreach ($r in $shown) {
    $before = (($r.Cur.cost -join ',') + '|' + ($r.Cur.result -join ',') + '|' + $r.Cur.time)
    if ($mc -ne 1) { for ($i = 0; $i -lt $r.Ing.Count; $i++) { $r.Cur.cost[$i] = RT-Scale $r.Ing[$i].Amount $mc } }
    if ($mr -ne 1) { for ($i = 0; $i -lt $r.Res.Count; $i++) { $r.Cur.result[$i] = RT-Scale $r.Res[$i].Amount $mr } }
    if ($mt -ne 1) { $r.Cur.time = [math]::Round($r.Time * $mt, 1) }
    if ($before -ne (($r.Cur.cost -join ',') + '|' + ($r.Cur.result -join ',') + '|' + $r.Cur.time)) { $n++ } }
  if ($n -gt 0) { $ui.Dirty = $true }
  RT-RefreshList; RT-LoadEditor
  $ui.Msg.Text = "Multiplied inside this window: $n of the $($shown.Count) recipe(s) shown changed (the multipliers work from the game's own values, not on top of earlier edits). Nothing is in the game yet - press Save to game."
}function RT-SaveClicked {
  $ui = $script:RT
  try { $res = RT-WriteFiles @($ui.Rows) } catch { Msg "Could not save: $($_.Exception.Message)" 'Recipe tweaks' 'OK' 'Error' | Out-Null; return }
  $ui.Dirty = $false; RT-UpdateStatus
  if ($res.WroteLua) { $ui.Msg.Text = "Saved: $($res.Changed) changed recipe(s) written to the game mod. The game applies it by itself within a few seconds; close and reopen the bench to see it." }
  else { $ui.Msg.Text = "Saved here ($($res.Changed) changed recipe(s)), but the game mod is not installed, so the game cannot see them yet - press 'Install / update mod'." }
}
function New-RecipeTweaksForm {
  Add-Type -AssemblyName System.Windows.Forms; Add-Type -AssemblyName System.Drawing
  $script:RT = @{ Loading = $false; Dirty = $false; Sel = $null; IngLbl = @(); IngNum = @(); ResLbl = @(); ResNum = @() }; $ui = $script:RT
  $ui.Rows = RT-LoadRecipes; RT-LoadState $ui.Rows; $ui.Shown = New-Object System.Collections.Generic.List[object]
  $f = New-Object System.Windows.Forms.Form; $f.Text = 'Recipe tweaks  -  change crafting amounts and times'; $f.Size = New-Object System.Drawing.Size(1200, 800); $f.MinimumSize = New-Object System.Drawing.Size(1000, 700)
  $f.StartPosition = 'CenterParent'; $f.Font = New-Object System.Drawing.Font('Segoe UI', 9); $ui.Form = $f
  $top = New-Object System.Windows.Forms.Panel; $top.Dock = 'Top'; $top.Height = 74; $f.Controls.Add($top)
  New-Lbl $top 'Search' 10 12 50 | Out-Null; $ui.Filter = New-Object System.Windows.Forms.TextBox; $ui.Filter.Location = '64,8'; $ui.Filter.Size = '260,24'; $top.Controls.Add($ui.Filter)
  New-Lbl $top 'Station' 340 12 50 | Out-Null; $ui.Station = New-Object System.Windows.Forms.ComboBox; $ui.Station.DropDownStyle = 'DropDownList'; $ui.Station.Location = '394,8'; $ui.Station.Size = '200,24'
  [void]$ui.Station.Items.Add('All stations'); foreach ($s in ($ui.Rows | ForEach-Object { $_.Station } | Where-Object { $_ } | Sort-Object -Unique)) { [void]$ui.Station.Items.Add($s) }; $ui.Station.SelectedIndex = 0; $top.Controls.Add($ui.Station)
  $ui.Count = New-Lbl $top '' 610 12 260; $ui.Install = New-Btn $top 'Install / update mod' 900 6 170 28
  $ui.ModLbl = New-Lbl $top '' 10 44 1150 20
  $bot = New-Object System.Windows.Forms.Panel; $bot.Dock = 'Bottom'; $bot.Height = 330; $f.Controls.Add($bot)
  $ed = New-Object ThemedGroup; $ed.Text = 'Edit the selected recipe'; $ed.Location = '8,4'; $ed.Size = '760,232'; $ed.Anchor = 'Top,Left'; $bot.Controls.Add($ed)
  $ui.Title = New-Lbl $ed 'Pick a recipe in the list to edit it.' 12 22 730 20; $ui.Title.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
  for ($i = 0; $i -lt 8; $i++) { $cx = 12 + 370 * [math]::Floor($i / 4); $cy = 48 + 30 * ($i % 4); $ui.IngLbl += (New-Lbl $ed '' $cx ($cy + 3) 260 20); $ui.IngNum += (New-Num $ed ($cx + 266) $cy 80 0 9999 0) }
  for ($i = 0; $i -lt 2; $i++) { $cx = 12 + 370 * $i; $ui.ResLbl += (New-Lbl $ed '' $cx 173 260 20); $ui.ResNum += (New-Num $ed ($cx + 266) 170 80 0 9999 0) }
  $ui.TimeLbl = New-Lbl $ed '' 12 203 262 20; $ui.TimeNum = New-Num $ed 278 200 80 0 9999 1
  $ui.ResetOne = New-Btn $ed 'Reset this recipe' 560 198 170 26
  $gl = New-Object ThemedGroup; $gl.Text = 'Change every recipe shown in the list'; $gl.Location = '776,4'; $gl.Size = '400,232'; $gl.Anchor = 'Top,Left'; $bot.Controls.Add($gl)
  New-Lbl $gl 'Amount made  x' 14 36 150 | Out-Null; $ui.MulRes = New-Num $gl 170 33 90 0.1 100 2; $ui.MulRes.Value = 1; $ui.MulRes.Increment = 0.25
  New-Lbl $gl 'Ingredient costs  x' 14 70 150 | Out-Null; $ui.MulCost = New-Num $gl 170 67 90 0.1 100 2; $ui.MulCost.Value = 1; $ui.MulCost.Increment = 0.25
  New-Lbl $gl 'Crafting time  x' 14 104 150 | Out-Null; $ui.MulTime = New-Num $gl 170 101 90 0 100 2; $ui.MulTime.Value = 1; $ui.MulTime.Increment = 0.25
  $ui.ApplyG = New-Btn $gl 'Multiply the recipes shown' 14 138 220 28; $ui.ResetG = New-Btn $gl 'Reset the recipes shown' 14 170 220 28
  $hint = New-Lbl $gl 'Use Search / Station to pick which. A value of 1 = no change.' 14 208 372 20; $hint.ForeColor = $script:Th.Muted
  $ui.Summary = New-Lbl $bot '' 10 244 740 20; $ui.Msg = New-Lbl $bot '' 10 268 1160 20; $ui.Msg.ForeColor = $script:Th.Accent
  $ui.Save = New-Btn $bot 'Save to game' 10 292 160 30; $ui.Save.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold); $ui.ResetAll = New-Btn $bot 'Reset ALL recipes' 180 292 160 30
  $hk = New-Lbl $bot 'After saving, the game applies it by itself in a few seconds - reopen the bench. Your save file is never changed.' 360 299 800 20; $hk.ForeColor = $script:Th.Muted
  $ui.LV = New-LV $f @('Recipe', 'Station', 'Ingredients', 'Makes', 'Time', '') @(260, 150, 380, 220, 70, 80); $ui.LV.Dock = 'Fill'; $ui.LV.BringToFront(); $ui.LV.MultiSelect = $false
  $ui.LV.Add_SelectedIndexChanged({ RT-LoadEditor }); $ui.Filter.Add_TextChanged({ RT-RefreshList }); $ui.Station.Add_SelectedIndexChanged({ RT-RefreshList })
  foreach ($n in $ui.IngNum + $ui.ResNum + @($ui.TimeNum)) { $n.Add_ValueChanged({ RT-EditorChanged }) }
  $ui.ResetOne.Add_Click({ $u = $script:RT; if ($u.Sel) { RT-Reset $u.Sel; $u.Dirty = $true; RT-LoadEditor; if ($u.LV.SelectedItems.Count) { RT-FillItem $u.LV.SelectedItems[0] $u.Sel }; RT-UpdateStatus } })
  $ui.ApplyG.Add_Click({ RT-ApplyGlobal })
  $ui.ResetG.Add_Click({ $u = $script:RT; foreach ($r in $u.Shown.ToArray()) { RT-Reset $r }; $u.Dirty = $true; RT-RefreshList; RT-LoadEditor; $u.Msg.Text = 'The recipes shown are back to the game''s values.' })
  $ui.ResetAll.Add_Click({ $u = $script:RT; foreach ($r in $u.Rows) { RT-Reset $r }; $u.Dirty = $true; RT-RefreshList; RT-LoadEditor; $u.Msg.Text = 'Every recipe is back to the game''s values (press Save to write that).' })
  $ui.Save.Add_Click({ RT-SaveClicked })
  $ui.Install.Add_Click({ $u = $script:RT; try { RT-InstallMod; $u.Msg.Text = 'The in-game mod is installed and switched on (mods.txt was backed up first). Restart the game once to load it.'; RT-UpdateStatus } catch { Msg "Could not install: $($_.Exception.Message)" 'Recipe tweaks' 'OK' 'Error' | Out-Null } })
  $f.Add_FormClosing({ param($s, $e) $u = $script:RT; if ($u.Dirty) { $a = Msg 'You have unsaved recipe changes. Close without saving?' 'Recipe tweaks' 'YesNo' 'Question' 'Button2'; if ($a -ne 'Yes') { $e.Cancel = $true } } })
  RT-RefreshList; RT-LoadEditor; Apply-Theme $f; Set-AppIcon $f
  return $f
}
function Show-RecipeTweaks($owner) { $f = New-RecipeTweaksForm; $script:ActiveForm = $f; try { [void]$f.ShowDialog($owner) } finally { $script:ActiveForm = $null } }
