# PlayerTools.ps1 - the "Player tools" window: vitals, skills, recipes, teleport, quest progress, save info.
# Needs SaveCore.ps1 + PlayerCore.ps1 loaded and System.Windows.Forms available. State lives in $script:PT.
$script:PT = @{}
$script:TestMode = $false
$script:ActiveForm = $null

function Msg([string]$text, [string]$title, [string]$buttons = 'OK', [string]$icon = 'Information', [string]$def = 'Button1') {
  if ($script:TestMode) { return $(if ($buttons -eq 'YesNo') { 'Yes' } else { 'OK' }) }
  if ($script:ActiveForm) { return [System.Windows.Forms.MessageBox]::Show($script:ActiveForm, $text, $title, $buttons, $icon, $def) }
  return [System.Windows.Forms.MessageBox]::Show($text, $title, $buttons, $icon, $def)
}
function New-LV($parent, [string[]]$cols, [int[]]$widths) {
  $lv = New-Object System.Windows.Forms.ListView; $lv.View = 'Details'; $lv.FullRowSelect = $true; $lv.HideSelection = $false; $lv.MultiSelect = $false; $lv.GridLines = $true
  for ($i = 0; $i -lt $cols.Count; $i++) { [void]$lv.Columns.Add($cols[$i], $widths[$i]) }
  $parent.Controls.Add($lv); return $lv
}
function New-Lbl($parent, [string]$text, [int]$x, [int]$y, [int]$w = 160, [int]$h = 20) { $l = New-Object System.Windows.Forms.Label; $l.AutoSize = $false; $l.Text = $text; $l.Location = New-Object System.Drawing.Point($x, $y); $l.Size = New-Object System.Drawing.Size($w, $h); $parent.Controls.Add($l); return $l }
function New-Btn($parent, [string]$text, [int]$x, [int]$y, [int]$w, [int]$h = 28) { $b = New-Object System.Windows.Forms.Button; $b.Text = $text; $b.Location = New-Object System.Drawing.Point($x, $y); $b.Size = New-Object System.Drawing.Size($w, $h); $parent.Controls.Add($b); return $b }
function New-Num($parent, [int]$x, [int]$y, [int]$w, [decimal]$min, [decimal]$max, [int]$dec = 0) { $n = New-Object System.Windows.Forms.NumericUpDown; $n.Location = New-Object System.Drawing.Point($x, $y); $n.Size = New-Object System.Drawing.Size($w, 24); $n.Minimum = $min; $n.Maximum = $max; $n.DecimalPlaces = $dec; $parent.Controls.Add($n); return $n }
function Set-Num($n, [double]$v) { $n.Value = [math]::Min([math]::Max([decimal]$v, $n.Minimum), $n.Maximum) }
function Test-Match([string]$hay, [string]$filter) { if (-not $filter) { return $true }; foreach ($w in ($filter -split '\s+' | Where-Object { $_ })) { if ($hay.IndexOf($w, [StringComparison]::OrdinalIgnoreCase) -lt 0) { return $false } }; return $true }

function PT-Status([string]$t) { if ($script:PT.Status) { $script:PT.Status.Text = $t } }

# ---------- load / refresh ----------
function PT-Load {
  $ui = $script:PT
  try { $ui.Data = Get-PlayerData $script:SavePath } catch { PT-Status ('Could not read the save: ' + $_.Exception.Message); $ui.Data = $null; return }
  $d = $ui.Data
  foreach ($v in $d.Vitals) { Set-Num $ui.VCur[$v.Key] $v.Value; Set-Num $ui.VMax[$v.Key] $v.Max }
  Set-Num $ui.Points $d.Points
  $ui.Pend = @{}; PT-FillSkills
  PT-FillRecipes; PT-FillTele; PT-FillQuest; PT-FillInfo
  PT-Status ("Loaded {0}: {1:N1} h played, {2} recipes known, {3} skills." -f $d.World, ($d.Playtime / 3600), $d.Known.Count, $d.Skills.Count)
}

# ---------- vitals & skills ----------
# skill facts from the game data (catalog\skills.csv): level cap, experience per action, benefit per level
function PT-SkillInfo([string]$name) {
  if (-not $script:PT.SkillCsv) { $m = @{}; $sp = Join-Path $PSScriptRoot 'catalog\skills.csv'; if (Test-Path -LiteralPath $sp) { foreach ($r in (Import-Csv $sp)) { $m[$r.Name] = $r; $m[$r.SkillID] = $r } }; $script:PT.SkillCsv = $m }
  return $script:PT.SkillCsv[$name]
}
function PT-SkillCap([string]$name) { $i = PT-SkillInfo $name; if ($i -and $i.LevelCap) { return [int]$i.LevelCap }; return 0 }
function PT-SkillBenefit([string]$name) { $i = PT-SkillInfo $name; if (-not $i) { return '' }; $b = [string]$i.Benefit; if ($i.BenefitPerLevel) { $b = ("{0} {1}{2}/level" -f $b, $(if ([double]$i.BenefitPerLevel -gt 0) { '+' } else { '' }), ($i.BenefitPerLevel + $i.Unit)) }; return $b.Trim() }
function PT-FillSkills {
  $ui = $script:PT; $d = $ui.Data; if (-not $d) { return }
  $lv = $ui.LvSkills; $sel = if ($lv.SelectedIndices.Count) { $lv.SelectedIndices[0] } else { -1 }
  $lv.BeginUpdate(); $lv.Items.Clear()
  foreach ($s in $d.Skills) {
    $p = $ui.Pend[$s.Index]; $L = if ($p) { $p.L } else { $s.Level }; $X = if ($p) { $p.X } else { $s.XP }
    $li = New-Object System.Windows.Forms.ListViewItem($s.Name + $(if ($p) { '  *' } else { '' })); $li.Tag = $s
    [void]$li.SubItems.Add([string]$L); [void]$li.SubItems.Add(('{0:N1}' -f $X)); [void]$li.SubItems.Add(('{0:N1}' -f (Get-SkillNeed $L))); [void]$li.SubItems.Add($($cap = PT-SkillCap $s.Name; if ($cap) { [string]$cap } else { '' })); [void]$li.SubItems.Add((PT-SkillBenefit $s.Name))
    if ($p) { $li.Font = New-Object System.Drawing.Font($lv.Font, [System.Drawing.FontStyle]::Bold); $li.ForeColor = $script:Th.Accent }
    [void]$lv.Items.Add($li)
  }
  $lv.EndUpdate(); if ($sel -ge 0 -and $sel -lt $lv.Items.Count) { $lv.Items[$sel].Selected = $true }
  $ui.PendLbl.Text = if ($ui.Pend.Count) { "$($ui.Pend.Count) skill change(s) waiting - press 'Apply changes to save'." } else { '' }
}
function PT-SelectSkill {
  $ui = $script:PT; if ($ui.LvSkills.SelectedItems.Count -eq 0) { return }
  $s = $ui.LvSkills.SelectedItems[0].Tag; $p = $ui.Pend[$s.Index]
  Set-Num $ui.SkLevel $(if ($p) { $p.L } else { $s.Level }); Set-Num $ui.SkXp $(if ($p) { $p.X } else { $s.XP })
}
function PT-SetSkill {
  $ui = $script:PT; if ($ui.LvSkills.SelectedItems.Count -eq 0) { PT-Status 'Pick a skill in the list first.'; return }
  $s = $ui.LvSkills.SelectedItems[0].Tag; $L = [int]$ui.SkLevel.Value; $cap = PT-SkillCap $s.Name; if ($cap -and $L -gt $cap) { $L = $cap; Set-Num $ui.SkLevel $L; PT-Status "$($s.Name) tops out at level $cap in the game data - set to $cap." }; $need = Get-SkillNeed $L; $X = [math]::Min([double]$ui.SkXp.Value, [math]::Max(0, $need - 0.01))
  if ($L -eq $s.Level -and [math]::Abs($X - $s.XP) -lt 0.001) { $ui.Pend.Remove($s.Index) } else { $ui.Pend[$s.Index] = @{ L = $L; X = $X } }
  PT-FillSkills
}
function PT-SetAllSkills {
  $ui = $script:PT; $d = $ui.Data; if (-not $d) { return }; $L = [int]$ui.AllLevel.Value
  foreach ($s in $d.Skills) { $cap = PT-SkillCap $s.Name; $Ls = if ($cap -and $L -gt $cap) { $cap } else { $L }; if ($s.Level -ne $Ls) { $ui.Pend[$s.Index] = @{ L = $Ls; X = 0.0 } } else { $ui.Pend.Remove($s.Index) } }
  PT-FillSkills
}
function PT-FillVitalsMax {
  $ui = $script:PT; foreach ($v in $ui.Data.Vitals) { Set-Num $ui.VCur[$v.Key] ([double]$ui.VMax[$v.Key].Value) }
}
function PT-Apply {
  $ui = $script:PT; $d = $ui.Data; if (-not $d) { return }
  $ch = @{}; $lines = @(); $warn = @()
  foreach ($v in $d.Vitals) {
    $cur = [double]$ui.VCur[$v.Key].Value; $mx = [double]$ui.VMax[$v.Key].Value
    if ($cur -gt $mx + 0.0005) { Msg "$($v.Label): the current value ($cur) is above the maximum ($mx). Raise the maximum or lower the current value." 'Check the values' 'OK' 'Warning' | Out-Null; return }
    if ([math]::Abs($cur - $v.Value) -gt 0.0005) { $ch[$v.Key] = Format-Num $cur; $lines += ("{0}: {1} -> {2}" -f $v.Label, (Format-Num $v.Value), (Format-Num $cur)) }
    if ([math]::Abs($mx - $v.Max) -gt 0.0005) { $ch[$v.MaxKey] = Format-Num $mx; $lines += ("{0} maximum: {1} -> {2}" -f $v.Label, (Format-Num $v.Max), (Format-Num $mx)); if ($mx -gt $v.Max * 2) { $warn += "$($v.Label) maximum is more than double the normal value - untested in the game." } }
  }
  if ([int]$ui.Points.Value -ne $d.Points) { $ch['PointsAmount'] = [string][int]$ui.Points.Value; $lines += "Skill points: $($d.Points) -> $([int]$ui.Points.Value)" }
  $top = ($d.Skills | Measure-Object -Property Level -Maximum).Maximum
  foreach ($s in $d.Skills) { $p = $ui.Pend[$s.Index]; if ($p) { $ch[$s.Key] = Build-SkillJson $s.Json $p.L $p.X; $lines += ("{0}: level {1} -> {2}" -f $s.Name, $s.Level, $p.L); if ($p.L -gt [math]::Max(30, $top)) { $cp = PT-SkillCap $s.Name; if ($cp -and $p.L -gt $cp) { $warn += "$($s.Name) level $($p.L) is above the game's cap of $cp." } elseif (-not $cp) { $warn += "$($s.Name) level $($p.L) is above anything seen in your save (highest: $top) - the game's cap for this skill is not in the data." } } } }
  if ($ch.Count -eq 0) { Msg 'Nothing has been changed.' 'Apply' 'OK' 'Information' | Out-Null; return }
  PT-Commit $ch ($lines -join "`n") ($warn -join "`n")
}
function PT-Commit([hashtable]$changes, [string]$summary, [string]$warnText = '') {
  if (Test-GameRunning) { Msg "The game is running, so nothing was changed.`n`nSave and close the game first, then try again." 'Game is running' 'OK' 'Warning' | Out-Null; return $false }
  $txt = "About to edit this save:`n$($script:SavePath)`n`n$summary"
  if ($warnText) { $txt += "`n`nCAUTION:`n$warnText" }
  $txt += "`n`nA backup is made first and the result is checked afterwards.`nSteam Cloud should be OFF for Permafrost.`n`nContinue?"
  if ((Msg $txt 'Apply changes?' 'YesNo' 'Question' 'Button2') -ne 'Yes') { PT-Status 'Cancelled - nothing changed.'; return $false }
  try {
    $r = Set-SaveKeys $script:SavePath $changes
    PT-Status ('Applied and verified. Backup: ' + $r.Backup)
    if ($script:OnSaveChanged) { & $script:OnSaveChanged "Player tools changed: $($r.Changed -join ', ')  (backup: $($r.Backup))" }
    PT-Load
    Msg "Done. Your save was backed up, edited and re-checked.`n`nBackup: $($r.Backup)`n`nStart the game and load the world. If Steam asks about a cloud conflict, keep the LOCAL (newer) files." 'Success' 'OK' 'Information' | Out-Null
    return $true
  } catch {
    PT-Status ('FAILED: ' + $_.Exception.Message)
    Msg "The change did not go through.`n`nReason: $($_.Exception.Message)`n`nNo harm done - your save was not modified (or was put back)." 'Failed safely' 'OK' 'Error' | Out-Null
    return $false
  }
}

# ---------- recipes ----------
function PT-FillRecipes {
  $ui = $script:PT; $d = $ui.Data; if (-not $d) { return }
  if (-not $ui.Recipes) { try { $ui.Recipes = @(Get-RecipeCatalog) } catch { PT-Status $_.Exception.Message; $ui.Recipes = @() } }
  $have = @{}; foreach ($k in $d.Known) { $have[$k] = 1 }
  $mode = [string]$ui.RcMode.SelectedItem; $kind = [string]$ui.RcKind.SelectedItem; $f = $ui.RcFilter.Text.Trim()
  $lv = $ui.LvRecipes; $lv.BeginUpdate(); $lv.Items.Clear(); $nk = 0
  foreach ($r in ($ui.Recipes | Sort-Object Kind, Group, Name)) {
    $known = $have.ContainsKey($r.Path); if ($known) { $nk++ }
    if ($mode -eq 'Not learned yet' -and $known) { continue }; if ($mode -eq 'Already learned' -and -not $known) { continue }
    if ($kind -ne 'All kinds' -and $r.Kind -ne $kind) { continue }
    if (-not (Test-Match "$($r.Name) $($r.Group) $($r.Asset)" $f)) { continue }
    $li = New-Object System.Windows.Forms.ListViewItem($r.Name); $li.Tag = $r; [void]$li.SubItems.Add($r.Kind); [void]$li.SubItems.Add($(if ($r.Group) { $r.Group } elseif ($r.Kind -eq 'Building recipe') { 'Building parts' } else { 'General' })); [void]$li.SubItems.Add($(if ($known) { 'learned' } else { 'not learned' }))
    if ($known) { $li.ForeColor = $script:Th.Muted } ; [void]$lv.Items.Add($li)
  }
  $lv.EndUpdate(); $ui.RcCount.Text = "$($lv.Items.Count) shown   |   you know $nk of $($ui.Recipes.Count) recipes in the game files"
}
function PT-UnlockRecipes {
  $ui = $script:PT; $paths = @(); $names = @()
  foreach ($li in $ui.LvRecipes.CheckedItems) { if ($li.SubItems[3].Text -eq 'not learned') { $paths += $li.Tag.Path; $names += $li.Tag.Name } }
  if ($paths.Count -eq 0) { Msg "Tick the recipes you want first (only 'not learned' ones count)." 'Nothing ticked' 'OK' 'Information' | Out-Null; return }
  $show = ($names | Select-Object -First 25) -join ', '; if ($names.Count -gt 25) { $show += " ... and $($names.Count - 25) more" }
  [void](PT-Commit @{ PlayerKnowledge_Knowledge = ($ui.Data.Entries['PlayerKnowledge_Knowledge'].TrimEnd('|') + '|' + ($paths -join '|')) } "Learn $($paths.Count) recipe(s):`n$show")
}

# ---------- teleport ----------
function PT-FillTele {
  $ui = $script:PT; $d = $ui.Data; if (-not $d) { return }
  if ($d.Position) { $ui.TeleNow.Text = ('You are at X {0:N0}  Y {1:N0}  Z {2:N0}  (game units; 100 = 1 metre)' -f $d.Position.X, $d.Position.Y, $d.Position.Z) } else { $ui.TeleNow.Text = 'Current position unknown' }
  $f = $ui.TeleFilter.Text.Trim(); $lv = $ui.LvTele; $lv.BeginUpdate(); $lv.Items.Clear()
  foreach ($t in (Get-TeleportTargets $d | Sort-Object { if ($_.Kind -eq 'Your build') { 1 } else { 0 } }, Name)) {
    if (-not (Test-Match "$($t.Name) $($t.Kind)" $f)) { continue }
    $li = New-Object System.Windows.Forms.ListViewItem($t.Name); $li.Tag = $t; [void]$li.SubItems.Add($t.Kind); [void]$li.SubItems.Add([string](Get-DistanceM $d $t)); [void]$lv.Items.Add($li)
  }
  $lv.EndUpdate()
}
function PT-Teleport {
  $ui = $script:PT; if ($ui.LvTele.SelectedItems.Count -eq 0) { Msg 'Pick a place in the list first.' 'Teleport' 'OK' 'Information' | Out-Null; return }
  $t = $ui.LvTele.SelectedItems[0].Tag; $d = $ui.Data
  $new = "{0},{1},{2}|{3}" -f (Format-Num $t.X), (Format-Num $t.Y), (Format-Num ($t.Z + 150)), $d.Position.Rest
  [void](PT-Commit @{ PawnLocation = $new } ("Move you to: $($t.Name)  ($(Get-DistanceM $d $t) m away)`nYou will appear 1.5 m above that spot and drop onto it when the game loads.`nIf you ever want to come back, your old position is in the backup.") '')
}

# ---------- quest progress (read only) ----------
# what the game's own quest data says about a quest and the state the save is in (uses GameData.ps1's decoded quest graph)
function PT-QuestInfo([string]$quest, [string]$state) {
  $res = @{ Name = ''; Where = ''; Next = '' }
  try { $d = GD-QuestData; $q = $d.Quests | Where-Object { $_.Quest -eq $quest } | Select-Object -First 1; if (-not $q) { return $res }
    $res.Name = [string]$q.Name; $states = $d.States[$quest]; $cs = $states | Where-Object { $_.StateID -eq $state } | Select-Object -First 1
    if ($cs) { $res.Where = GD-Spoil ([string]$cs.Description); if ($cs.Type -match 'Success|Fail') { $res.Next = "(end: $($cs.Type))" } }
    if (-not $res.Next) { $nb = @($d.Branches[$quest] | Where-Object { ($_.From -split '; ') -contains $state } | Select-Object -First 1)
      if ($nb.Count -and $nb[0]) { $tasks = @($d.Objs["$quest|$($nb[0].BranchID)"] | ForEach-Object { GD-ObjText $_ }); $res.Next = ($tasks -join '  +  ') } } } catch { }
  return $res
}
function PT-FillQuest {
  $ui = $script:PT; $d = $ui.Data; if (-not $d) { return }
  $q = $d.Quests; $view = [string]$ui.QView.SelectedItem; $f = $ui.QFilter.Text.Trim(); $lv = $ui.LvQuest
  $lv.BeginUpdate(); $lv.Items.Clear(); $lv.Columns.Clear()
  function AddCols([string[]]$c, [int[]]$w) { for ($i = 0; $i -lt $c.Count; $i++) { [void]$lv.Columns.Add($c[$i], $w[$i]) } }
  switch ($view) {
    'Quests (state of each)' {
      AddCols @('Quest', 'In-game name', 'State now', 'What the game says now', 'Next task(s)', 'Active?') @(250, 170, 120, 330, 330, 70)
      foreach ($r in ($q.Quests | Sort-Object Chain, Quest)) {
        $qi = PT-QuestInfo $r.Quest $r.State; if (-not (Test-Match "$($r.Quest) $($r.Chain) $($r.State) $($qi.Name) $(if (-not (Get-HideSpoilers)) { $qi.Where }) $($qi.Next)" $f)) { continue }
        $act = $q.Active -contains $r.Quest
        $li = New-Object System.Windows.Forms.ListViewItem($r.Quest); foreach ($x in @($qi.Name, $r.State, $qi.Where, $qi.Next, $(if ($act) { 'ACTIVE' } else { '' }))) { [void]$li.SubItems.Add($x) }
        if ($qi.Next -match 'end: Success' -or $r.State -match 'End|Success|Final') { $li.ForeColor = $script:Th.Good } elseif ($qi.Next -match 'end: Fail') { $li.ForeColor = $script:Th.Bad } elseif ($act) { $li.ForeColor = $script:Th.Accent }
        [void]$lv.Items.Add($li) } }
    'Task counters' {
      AddCols @('Task', 'Count') @(560, 100)
      foreach ($r in $q.Tasks) { if (-not (Test-Match $r.Task $f)) { continue }; $li = New-Object System.Windows.Forms.ListViewItem($r.Task); [void]$li.SubItems.Add([string]$r.Count); [void]$lv.Items.Add($li) } }
    'Rewards already claimed' {
      AddCols @('Reward pool', 'Entries claimed') @(300, 600)
      foreach ($r in $q.Rewards) { if (-not (Test-Match "$($r.Pool) $($r.Claimed)" $f)) { continue }; $li = New-Object System.Windows.Forms.ListViewItem($r.Pool); [void]$li.SubItems.Add($r.Claimed); [void]$lv.Items.Add($li) } }
    'Journal (letters, recordings, places)' {
      AddCols @('Section', 'Count', 'Entries') @(140, 60, 800)
      foreach ($r in $q.Journal) { if (-not (Test-Match "$($r.Section) $($r.Entries)" $f)) { continue }; $li = New-Object System.Windows.Forms.ListViewItem($r.Section); [void]$li.SubItems.Add([string]$r.Count); [void]$li.SubItems.Add($r.Entries); [void]$lv.Items.Add($li) } }
  }
  Fit-LastColumn $lv; $lv.EndUpdate(); $ui.QCount.Text = "$($lv.Items.Count) rows"
}

# ---------- save info ----------
function PT-FillInfo {
  $ui = $script:PT; $d = $ui.Data; if (-not $d) { return }
  $sb = New-Object System.Text.StringBuilder; $fi = Get-Item -LiteralPath $script:SavePath
  [void]$sb.AppendLine("World:            $($d.World)"); [void]$sb.AppendLine("Created:          $($d.Created)"); [void]$sb.AppendLine("Last saved:       $($d.Updated)")
  [void]$sb.AppendLine(("Play time:        {0:N1} hours" -f ($d.Playtime / 3600))); [void]$sb.AppendLine(("File size:        {0:N0} KB   ({1})" -f ($fi.Length / 1KB), $fi.FullName))
  if ($d.Position) { [void]$sb.AppendLine(("Position:         X {0:N0}  Y {1:N0}  Z {2:N0}" -f $d.Position.X, $d.Position.Y, $d.Position.Z)) }
  [void]$sb.AppendLine("Things you built: $($d.Parts.Count)"); [void]$sb.AppendLine("Recipes known:    $($d.Known.Count)"); [void]$sb.AppendLine("Skill points:     $($d.Points)")
  [void]$sb.AppendLine(); [void]$sb.AppendLine('Vitals:'); foreach ($v in $d.Vitals) { [void]$sb.AppendLine(("   {0,-16} {1} / {2}" -f $v.Label, (Format-Num $v.Value), (Format-Num $v.Max))) }
  [void]$sb.AppendLine(); [void]$sb.AppendLine('Skills:'); foreach ($s in $d.Skills) { [void]$sb.AppendLine(("   {0,-14} level {1,-3} ({2:N1} / {3:N1} xp)" -f $s.Name, $s.Level, $s.XP, $s.Need)) }
  [void]$sb.AppendLine(); [void]$sb.AppendLine('Built things by type:'); foreach ($g in ($d.Parts | Group-Object Type | Sort-Object Count -Descending)) { [void]$sb.AppendLine(("   {0,-28} x{1}" -f $g.Name, $g.Count)) }
  $ui.InfoBox.Text = $sb.ToString()
}

# ---------- the window ----------
function New-PlayerForm {
  Add-Type -AssemblyName System.Windows.Forms; Add-Type -AssemblyName System.Drawing
  $ui = @{}; $script:PT = $ui
  $f = New-Object System.Windows.Forms.Form; $f.Text = 'Player tools  -  vitals, skills, recipes, teleport, quest progress'; $f.Size = New-Object System.Drawing.Size(1100, 760); $f.MinimumSize = New-Object System.Drawing.Size(980, 640)
  $f.StartPosition = 'CenterParent'; $f.Font = New-Object System.Drawing.Font('Segoe UI', 9); $ui.Form = $f
  $st = New-Object System.Windows.Forms.Label; $st.Dock = 'Bottom'; $st.Height = 26; $st.TextAlign = 'MiddleLeft'; $st.Padding = New-Object System.Windows.Forms.Padding(8, 0, 0, 0); $st.Tag = 'status'; $f.Controls.Add($st); $ui.Status = $st
  $tabs = New-Object ThemedTabs; $tabs.Dock = 'Fill'; $f.Controls.Add($tabs); $tabs.BringToFront()
  function NewTab([string]$title) { $p = New-Object System.Windows.Forms.TabPage; $p.Text = $title; $p.Padding = New-Object System.Windows.Forms.Padding(8); $tabs.TabPages.Add($p); return $p }

  # --- tab 1: vitals & skills
  $t1 = NewTab 'Vitals && skills'
  $gv = New-Object ThemedGroup; $gv.Text = 'Vitals (current value and maximum)'; $gv.Location = '10,10'; $gv.Size = '470,262'; $t1.Controls.Add($gv)
  New-Lbl $gv 'Current' 170 24 80 | Out-Null; New-Lbl $gv 'Maximum' 290 24 80 | Out-Null
  $ui.VCur = @{}; $ui.VMax = @{}; $y = 48
  foreach ($d in $script:VitalDefs) { New-Lbl $gv $d.Label 14 ($y + 3) 150 | Out-Null; $ui.VCur[$d.Key] = New-Num $gv 168 $y 100 0 99999 1; $ui.VMax[$d.Key] = New-Num $gv 288 $y 100 1 99999 1; $y += 34 }
  $bFill = New-Btn $gv 'Fill all current values to the maximum' 14 222 260; $bFill.Add_Click({ PT-FillVitalsMax })
  $gp = New-Object ThemedGroup; $gp.Text = 'Skill points'; $gp.Location = '10,282'; $gp.Size = '470,64'; $t1.Controls.Add($gp)
  New-Lbl $gp 'Unspent skill points' 14 27 150 | Out-Null; $ui.Points = New-Num $gp 168 24 100 0 9999 0
  $ui.PendLbl = New-Lbl $t1 '' 14 360 460 40; $ui.PendLbl.ForeColor = $script:Th.Accent
  $bApply = New-Btn $t1 'Apply changes to save' 14 410 230 40; $bApply.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold); $bApply.Add_Click({ PT-Apply })
  $bDisc = New-Btn $t1 'Discard / reload from save' 252 410 200 40; $bDisc.Add_Click({ PT-Load })
  $nt = New-Lbl $t1 "Nothing is written until you press 'Apply changes to save'. The game must be closed. A backup is made first.`r`nOnly values you changed are written." 14 462 460 50; $nt.ForeColor = $script:Th.Muted
  $gs = New-Object ThemedGroup; $gs.Text = 'Skills'; $gs.Location = '496,10'; $gs.Size = '560,500'; $gs.Anchor = 'Top,Left,Right,Bottom'; $t1.Controls.Add($gs)
  $pe = New-Object System.Windows.Forms.Panel; $pe.Dock = 'Bottom'; $pe.Height = 150; $gs.Controls.Add($pe)
  $ui.LvSkills = New-LV $gs @('Skill', 'Level', 'XP', 'XP needed for next', 'Max level', 'Benefit (from the game data)') @(170, 60, 80, 120, 80, 330); $ui.LvSkills.Dock = 'Fill'; $ui.LvSkills.BringToFront()
  $ui.LvSkills.Add_SelectedIndexChanged({ PT-SelectSkill })
  New-Lbl $pe 'Selected skill - level' 8 10 140 | Out-Null; $ui.SkLevel = New-Num $pe 154 7 70 1 100 0
  New-Lbl $pe 'XP' 240 10 30 | Out-Null; $ui.SkXp = New-Num $pe 274 7 90 0 99999 1
  $bSet = New-Btn $pe 'Set this skill' 378 4 150; $bSet.Add_Click({ PT-SetSkill })
  New-Lbl $pe 'All skills - set to level' 8 56 150 | Out-Null; $ui.AllLevel = New-Num $pe 154 53 70 1 100 0; $ui.AllLevel.Value = 10
  $bAll = New-Btn $pe 'Queue for all skills' 240 50 160; $bAll.Add_Click({ PT-SetAllSkills })
  New-Lbl $pe "XP needed for the next level = 10 x level^1.5 (matches all 16 of your skills). Changes wait in blue until you press Apply." 8 96 530 40 | Out-Null
  # --- tab 2: recipes
  $t2 = NewTab 'Recipes'
  $top = New-Object System.Windows.Forms.Panel; $top.Dock = 'Top'; $top.Height = 38; $t2.Controls.Add($top)
  New-Lbl $top 'Show' 0 11 40 | Out-Null; $ui.RcMode = New-Object System.Windows.Forms.ComboBox; $ui.RcMode.DropDownStyle = 'DropDownList'; $ui.RcMode.Location = '44,7'; $ui.RcMode.Size = '140,24'; [void]$ui.RcMode.Items.AddRange(@('Not learned yet', 'Already learned', 'All')); $ui.RcMode.SelectedIndex = 0; $top.Controls.Add($ui.RcMode)
  $ui.RcKind = New-Object System.Windows.Forms.ComboBox; $ui.RcKind.DropDownStyle = 'DropDownList'; $ui.RcKind.Location = '194,7'; $ui.RcKind.Size = '150,24'; [void]$ui.RcKind.Items.AddRange(@('All kinds', 'Item recipe', 'Building recipe')); $ui.RcKind.SelectedIndex = 0; $top.Controls.Add($ui.RcKind)
  New-Lbl $top 'Search' 360 11 50 | Out-Null; $ui.RcFilter = New-Object System.Windows.Forms.TextBox; $ui.RcFilter.Location = '412,7'; $ui.RcFilter.Size = '220,24'; $top.Controls.Add($ui.RcFilter)
  $bAllRc = New-Btn $top 'Tick all shown' 650 5 120; $bNoRc = New-Btn $top 'Untick all' 776 5 100; $bUn = New-Btn $top 'Learn ticked recipes' 884 5 160; $bUn.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
  $ui.RcCount = New-Object System.Windows.Forms.Label; $ui.RcCount.Dock = 'Bottom'; $ui.RcCount.Height = 24; $ui.RcCount.TextAlign = 'MiddleLeft'; $t2.Controls.Add($ui.RcCount)
  $ui.LvRecipes = New-LV $t2 @('Recipe', 'Kind', 'Group', 'Status') @(300, 120, 360, 110); $ui.LvRecipes.Dock = 'Fill'; $ui.LvRecipes.CheckBoxes = $true; $ui.LvRecipes.BringToFront()
  $ui.RcMode.Add_SelectedIndexChanged({ PT-FillRecipes }); $ui.RcKind.Add_SelectedIndexChanged({ PT-FillRecipes }); $ui.RcFilter.Add_TextChanged({ PT-FillRecipes })
  $bAllRc.Add_Click({ foreach ($i in $script:PT.LvRecipes.Items) { $i.Checked = ($i.SubItems[3].Text -eq 'not learned') } }); $bNoRc.Add_Click({ foreach ($i in $script:PT.LvRecipes.Items) { $i.Checked = $false } }); $bUn.Add_Click({ PT-UnlockRecipes })

  # --- tab 3: teleport
  $t3 = NewTab 'Teleport'
  $ui.TeleNow = New-Lbl $t3 '' 8 8 900 22; $ui.TeleNow.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
  New-Lbl $t3 'Search' 8 40 50 | Out-Null; $ui.TeleFilter = New-Object System.Windows.Forms.TextBox; $ui.TeleFilter.Location = '60,37'; $ui.TeleFilter.Size = '240,24'; $t3.Controls.Add($ui.TeleFilter)
  $bTp = New-Btn $t3 'Teleport to selected place' 320 33 220 32; $bTp.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
  $ui.LvTele = New-LV $t3 @('Place', 'Kind', 'Distance (m)') @(380, 140, 110); $ui.LvTele.Location = '8,76'; $ui.LvTele.Size = '640,520'; $ui.LvTele.Anchor = 'Top,Left,Bottom'
  $nt3 = New-Lbl $t3 "How it works: it writes a new position into the save (game closed, backup first). You load in 1.5 m above that spot and drop onto it.`r`n`r`nPlaces come from your own save: your bed, the crash site, and everything you built that isn't a plain wall/floor. Distances are straight-line.`r`n`r`nThe game's own named locations (Hunters Glade, Solar Fields, ...) have no coordinates in the exported data, so they can't be listed here. If you need one, stand there once and build/place something (e.g. a campfire) - it will show up in this list." 666 76 380 300; $nt3.ForeColor = $script:Th.Muted; $nt3.Anchor = 'Top,Left,Right'
  $ui.TeleFilter.Add_TextChanged({ PT-FillTele }); $bTp.Add_Click({ PT-Teleport }); $ui.LvTele.Add_DoubleClick({ PT-Teleport })

  # --- tab 4: quest progress
  $t4 = NewTab 'Quest progress'
  $tq = New-Object System.Windows.Forms.Panel; $tq.Dock = 'Top'; $tq.Height = 38; $t4.Controls.Add($tq)
  New-Lbl $tq 'View' 0 11 40 | Out-Null; $ui.QView = New-Object System.Windows.Forms.ComboBox; $ui.QView.DropDownStyle = 'DropDownList'; $ui.QView.Location = '44,7'; $ui.QView.Size = '260,24'; [void]$ui.QView.Items.AddRange(@('Quests (state of each)', 'Task counters', 'Rewards already claimed', 'Journal (letters, recordings, places)')); $ui.QView.SelectedIndex = 0; $tq.Controls.Add($ui.QView)
  New-Lbl $tq 'Search' 322 11 50 | Out-Null; $ui.QFilter = New-Object System.Windows.Forms.TextBox; $ui.QFilter.Location = '374,7'; $ui.QFilter.Size = '260,24'; $tq.Controls.Add($ui.QFilter)
  $ui.QCount = New-Lbl $tq '' 650 11 200; $ui.QSpoil = New-Object System.Windows.Forms.CheckBox; $ui.QSpoil.Text = 'Hide story text'; $ui.QSpoil.AutoSize = $true; $ui.QSpoil.Location = '860,9'; $ui.QSpoil.Checked = (Get-HideSpoilers); $ui.QSpoil.ForeColor = $script:Th.Text; $tq.Controls.Add($ui.QSpoil)
  $qn = New-Object System.Windows.Forms.Label; $qn.Dock = 'Bottom'; $qn.Height = 44; $qn.ForeColor = $script:Th.Muted; $qn.Text = "Read-only. Green = state name says finished (End / Success / Final). Blue = in the active list. Numbered states such as QuestState_6 are internal; the game files do not say what each one means, so this tool does not edit quests."; $t4.Controls.Add($qn)
  $ui.LvQuest = New-LV $t4 @('x') @(100); $ui.LvQuest.Dock = 'Fill'; $ui.LvQuest.BringToFront()
  $ui.QSpoil.Add_CheckedChanged({ Set-HideSpoilers $script:PT.QSpoil.Checked; PT-FillQuest }); $ui.QView.Add_SelectedIndexChanged({ PT-FillQuest }); $ui.QFilter.Add_TextChanged({ PT-FillQuest })

  # --- tab 5: save info
  $t5 = NewTab 'Save info'
  $ui.InfoBox = New-Object System.Windows.Forms.TextBox; $ui.InfoBox.Multiline = $true; $ui.InfoBox.ReadOnly = $true; $ui.InfoBox.ScrollBars = 'Vertical'; $ui.InfoBox.Dock = 'Fill'; $ui.InfoBox.Font = New-Object System.Drawing.Font('Consolas', 10); $ui.InfoBox.BackColor = [System.Drawing.Color]::White; $t5.Controls.Add($ui.InfoBox)

  PT-Load
  Apply-Theme $f; Set-AppIcon $f
  return $f
}
function Show-PlayerTools($owner) { $f = New-PlayerForm; $script:ActiveForm = $f; try { [void]$f.ShowDialog($owner) } finally { $script:ActiveForm = $null } }

