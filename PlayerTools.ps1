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

# ---------- recipe hover pictures (catalog\recipe-icons.csv from Build-RecipeIcons.ps1; text-only when a recipe has no picture) ----------
$script:RcTip = @{ Map = $null; Img = @{}; Data = $null; Key = $null; Tt = $null }
function PT-RcImage([string]$rel) {
  if (-not $rel) { return $null }
  if ($script:RcTip.Img.ContainsKey($rel)) { return $script:RcTip.Img[$rel] }
  $img = $null; $f = Join-Path $PSScriptRoot $rel
  if (Test-Path -LiteralPath $f) { try { $ms = New-Object IO.MemoryStream (, [IO.File]::ReadAllBytes($f)); $img = [System.Drawing.Image]::FromStream($ms) } catch { $img = $null } }
  $script:RcTip.Img[$rel] = $img; return $img
}
function PT-RcInfo($r) {
  if (-not $script:RcTip.Map) {
    $m = @{}; $f = Join-Path $PSScriptRoot 'catalog\recipe-icons.csv'
    if (Test-Path -LiteralPath $f) { foreach ($x in (Import-Csv $f)) { $m[$x.Asset] = $x } }
    $script:RcTip.Map = $m
  }
  return $script:RcTip.Map[$r.Asset]
}
function PT-RcWrap([string]$text, [int]$max) {
  $out = New-Object System.Collections.Generic.List[string]; $line = ''
  foreach ($w in ($text -split '\s+' | Where-Object { $_ })) { if ($line.Length + $w.Length + 1 -gt $max -and $line) { $out.Add($line); $line = $w } else { $line = $(if ($line) { "$line $w" } else { $w }) } }
  if ($line) { $out.Add($line) }; return , $out.ToArray()
}
function PT-RcTipData($r, [string]$status, [string]$group = "") {
  $info = PT-RcInfo $r; $lines = New-Object System.Collections.Generic.List[string]
  $lines.Add("$($r.Kind)  /  $(if ($group) { $group } elseif ($r.Group) { $r.Group } else { 'General' })  -  $status")
  if ($info -and $info.Detail) { foreach ($seg in ($info.Detail -split ' \| ')) { foreach ($w in (PT-RcWrap $seg 70)) { $lines.Add($w) } } }
  $img = $null; if ($info) { $img = PT-RcImage $info.IconFile }
  return @{ Id = $r.Name; Lines = $lines.ToArray(); Icon = $img }
}
function PT-RcMeasure($d) {
  $fb = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold); $f = New-Object System.Drawing.Font('Segoe UI', 9)
  $tw = [System.Windows.Forms.TextRenderer]::MeasureText([string]$d.Id, $fb).Width; $th = 24
  foreach ($ln in $d.Lines) { $s = [System.Windows.Forms.TextRenderer]::MeasureText([string]$ln, $f); $tw = [math]::Max($tw, $s.Width); $th += 18 }
  $iw = if ($d.Icon) { 112 } else { 0 }
  $w = [math]::Min([int]($iw + $tw + 28), 640); $h = [math]::Max([int]($th + 14), $(if ($d.Icon) { 120 } else { 44 })); $fb.Dispose(); $f.Dispose()
  return New-Object System.Drawing.Size($w, $h)
}
function PT-RcDraw($g, $r, $d) {
  $g.SmoothingMode = 'AntiAlias'; $g.InterpolationMode = 'HighQualityBicubic'
  $bg = New-Object System.Drawing.SolidBrush ($script:Th.Panel); $g.FillRectangle($bg, $r); $bg.Dispose()
  $pen = New-Object System.Drawing.Pen ($script:Th.Accent); $g.DrawRectangle($pen, $r.X, $r.Y, $r.Width - 1, $r.Height - 1); $pen.Dispose()
  $x = $r.X + 8
  if ($d.Icon) { $box = 96; $sc = [math]::Min($box / $d.Icon.Width, $box / $d.Icon.Height); $w = [int]($d.Icon.Width * $sc); $h = [int]($d.Icon.Height * $sc)
    $g.DrawImage($d.Icon, $x + [int](($box - $w) / 2), $r.Y + [int](($r.Height - $h) / 2), $w, $h); $x += 104 }
  $fb = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold); $f = New-Object System.Drawing.Font('Segoe UI', 9); $y = $r.Y + 8
  [System.Windows.Forms.TextRenderer]::DrawText($g, [string]$d.Id, $fb, (New-Object System.Drawing.Point($x, $y)), $script:Th.Text); $y += 24
  foreach ($ln in $d.Lines) { [System.Windows.Forms.TextRenderer]::DrawText($g, [string]$ln, $f, (New-Object System.Drawing.Point($x, $y)), $script:Th.Muted); $y += 18 }
  $fb.Dispose(); $f.Dispose()
}
function PT-RcHover($lv, $e) {
  $it = $lv.GetItemAt($e.X, $e.Y)
  if (-not $it -or -not $it.Tag) { $script:RcTip.Key = $null; $script:RcTip.Tt.Hide($lv); return }
  if ($script:RcTip.Key -eq $it.Tag.Asset) { return }
  $script:RcTip.Key = $it.Tag.Asset; $script:RcTip.Data = PT-RcTipData $it.Tag $it.SubItems[3].Text $it.SubItems[2].Text
  $script:RcTip.Tt.Show(' ', $lv, ($e.X + 18), ($e.Y + 22))
}
function PT-RcInitTip($lv) {
  $tt = New-Object System.Windows.Forms.ToolTip; $tt.OwnerDraw = $true; $tt.ShowAlways = $true; $tt.AutoPopDelay = 30000; $script:RcTip.Tt = $tt
  $tt.Add_Popup({ param($s, $e) if ($script:RcTip.Data) { $e.ToolTipSize = PT-RcMeasure $script:RcTip.Data } })
  $tt.Add_Draw({ param($s, $e) if ($script:RcTip.Data) { PT-RcDraw $e.Graphics $e.Bounds $script:RcTip.Data } else { $e.DrawBackground(); $e.DrawBorder(); $e.DrawText() } })
  $lv.Add_MouseMove({ param($s, $e) PT-RcHover $s $e })
  $lv.Add_MouseLeave({ $script:RcTip.Key = $null; $script:RcTip.Tt.Hide($script:PT.LvRecipes) })
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
# the list: your bed, the crash site, your builds, the game's named places and fast-travel points (catalog\places.csv) and your own spots
function PT-KindOrder([string]$k) { switch ($k) { 'My spot' { 0 } 'Bed' { 1 } 'Start' { 2 } 'Named place' { 3 } 'Fast travel' { 4 } default { 5 } } }
function PT-Dist2D($d, $t) { if (-not $d.Position) { return 0 }; [math]::Round([math]::Sqrt([math]::Pow($t.X - $d.Position.X, 2) + [math]::Pow($t.Y - $d.Position.Y, 2)) / 100.0) }
function PT-FillTele {
  $ui = $script:PT; $d = $ui.Data; if (-not $d) { return }
  if ($d.Position) { $ui.TeleNow.Text = ('You are at X {0:N0}  Y {1:N0}  Z {2:N0}  (game units; 100 = 1 metre)' -f $d.Position.X, $d.Position.Y, $d.Position.Z) } else { $ui.TeleNow.Text = 'Current position unknown' }
  $f = $ui.TeleFilter.Text.Trim(); $show = [string]$ui.TeleKind.SelectedItem
  $keep = { param($t) switch ($show) { 'Named places' { $t.Kind -eq 'Named place' } 'Fast travel' { $t.Kind -eq 'Fast travel' } 'My spots' { $t.Kind -eq 'My spot' } 'Bed, start and builds' { $t.Kind -in 'Bed', 'Start', 'Your build' } default { $true } } }
  $lv = $ui.LvTele; $lv.BeginUpdate(); $lv.Items.Clear()
  foreach ($t in (Get-TeleportTargets $d | Sort-Object { PT-KindOrder $_.Kind }, Name)) {
    if (-not (& $keep $t)) { continue }
    if (-not (Test-Match "$($t.Name) $($t.Kind)" $f)) { continue }
    $place = $t.Kind -in 'Named place', 'Fast travel'
    $hz = if ($place) { $th = Get-TargetHeight $t; if ($null -ne $th.Z) { [string][int]$th.Z } else { '?' } } else { [string][int]$t.Z }
    $li = New-Object System.Windows.Forms.ListViewItem($t.Name); $li.Tag = $t; [void]$li.SubItems.Add($t.Kind); [void]$li.SubItems.Add([string]$(if ($place) { PT-Dist2D $d $t } else { Get-DistanceM $d $t })); [void]$li.SubItems.Add($hz); [void]$lv.Items.Add($li)
  }
  $lv.EndUpdate()
  $gs = GS-ModStatus; $ui.TeleSnap.Enabled = (Test-Path -LiteralPath (RT-ModsDir))
  $gl = GS-LastResult; $ui.TeleSnapNote.Text = $(if (GS-HasRequest) { 'Waiting for the next time you load the world.' } elseif ($gl) { "Last time in the game: $gl" } elseif (-not $ui.TeleSnap.Enabled) { 'No UE4SS Mods folder found next to your save: not available.' } else { '' }); $ui.TeleSnapNote.Visible = [bool]$ui.TeleSnapNote.Text
  $u = Get-TeleportUndo $script:SavePath; $ui.BtnUndo.Enabled = [bool]$u
  $ui.BtnUndo.Text = 'Undo last teleport'
  $sel = $ui.LvTele.SelectedItems; $ui.BtnDelSpot.Enabled = ($sel.Count -gt 0 -and $sel[0].Tag.Kind -eq 'My spot')
}
# the heights found near a spot, with the one that will be used marked; $ui.TeleLevelZ is the height chosen (null = none known)
function PT-ShowLevels($t, [bool]$setBoxes = $true) {
  $ui = $script:PT; $th = Get-TargetHeight $t; $lv = $ui.LvLevels; $ui.TeleBusy = $true
  $lv.BeginUpdate(); $lv.Items.Clear(); $pick = $null
  foreach ($l in $th.Levels) { $li = New-Object System.Windows.Forms.ListViewItem([string]$l.Z); $li.Tag = $l; [void]$li.SubItems.Add([string]$l.N); [void]$li.SubItems.Add([string]$l.G); [void]$li.SubItems.Add([string]$l.D); [void]$lv.Items.Add($li); if ($null -ne $th.Z -and [math]::Abs($l.Z - $th.Z) -lt 1) { $pick = $li } }
  if ($pick) { $pick.Selected = $true; $pick.Font = New-Object System.Drawing.Font($lv.Font, [System.Drawing.FontStyle]::Bold); $pick.EnsureVisible() }
  $lv.EndUpdate(); $ui.TeleBusy = $false; $ui.TeleLevelZ = $th.Z
  if ($setBoxes) { Set-Num $ui.TeleX $t.X; Set-Num $ui.TeleY $t.Y; if ($null -ne $th.Z) { Set-Num $ui.TeleZ $th.Z } }
  $ui.TeleInfo.Text = if ($null -ne $th.Z) { "Height used: Z $([int]$th.Z) - $($th.Why).`r`nYou appear $([math]::Round([double]$ui.TeleDrop.Value / 100.0, 1)) m above it and drop. Click another height in the list to use that one instead (the bold one is the suggestion). Heights come from objects the atlas flights found within 100 m: hills and buildings have several floors, so if a landing is wrong, try the next height up or down, or use Undo." } else { "No height data near this spot (the flights found no objects within 100 m).`r`nType a Z yourself (the in-game map shows your own X / Y / Z at its lower left), or pick a height from the list when one is shown." }
  return $th
}
function PT-OnPlaceSelected {
  $ui = $script:PT; if ($ui.LvTele.SelectedItems.Count -eq 0) { $ui.BtnDelSpot.Enabled = $false; return }
  $t = $ui.LvTele.SelectedItems[0].Tag; $ui.BtnDelSpot.Enabled = ($t.Kind -eq 'My spot'); [void](PT-ShowLevels $t)
}
function PT-OnLevelPicked {
  $ui = $script:PT; if ($ui.TeleBusy -or $ui.LvLevels.SelectedItems.Count -eq 0) { return }
  $z = [double]$ui.LvLevels.SelectedItems[0].Tag.Z; $ui.TeleLevelZ = $z; Set-Num $ui.TeleZ $z
  $ui.TeleInfo.Text = "Height chosen: Z $([int]$z). You appear $([math]::Round([double]$ui.TeleDrop.Value / 100.0, 1)) m above it (Z $([int]($z + [double]$ui.TeleDrop.Value))) and drop onto the ground when the game loads."
}
# the one place that writes the move: confirm, back up (Set-SaveKeys), keep the undo information, reload
function PT-DoMove([double]$x, [double]$y, [double]$z, [string]$label, [string]$why, [bool]$estimated = $false) {
  $ui = $script:PT; $d = $ui.Data; $drop = [double]$ui.TeleDrop.Value; $fill = [bool]$ui.TeleVitals.Checked
  $snap = $estimated -and [bool]$ui.TeleSnap.Checked -and $ui.TeleSnap.Enabled
  if (Test-GameRunning) { Msg "The game is running, so nothing was changed.`n`nSave and close the game first, then try again." 'Game is running' 'OK' 'Warning' | Out-Null; return $false }
  $far = [math]::Round([math]::Sqrt([math]::Pow($x - $d.Position.X, 2) + [math]::Pow($y - $d.Position.Y, 2)) / 100.0)
  $txt = "About to edit this save:`n$($script:SavePath)`n`nMove you to: $label`nX=$([int]$x)  Y=$([int]$y)  Z=$([int]$z)  ($far m away)  - $why`nYou will appear $([math]::Round($drop / 100.0, 1)) m above that height and drop onto the ground when the game loads.`n"
  if ($fill) { $txt += "Your health, stamina, energy, hunger and warmth are filled to the maximum first.`n" }
  if ($snap) { $gs = GS-ModStatus; $txt += "The height is an estimate, so the GroundSnap game mod will also measure the real ground when you load and put you on it" + $(if ($gs.Active -and $gs.UpToDate) { '' } else { " (it will be installed into the game's UE4SS Mods folder now)" }) + ".`n" }
  elseif ($estimated -and -not [bool]$ui.TeleSnap.Checked) { $txt += "GroundSnap is switched off for this teleport: the estimated height is used as it is.`n" }
  $warn = @(Get-TeleportWarning $x $y $z $drop); if ($warn.Count) { $txt += "`nWARNING:`n" + (($warn | ForEach-Object { "- $_" }) -join "`n") + "`n" }
  $txt += "`nHeights are estimates: landing too low puts you UNDER the map, too high is a long fall. 'Undo last teleport' puts you back where you were before you started teleporting, and the backup made first is in the Backups folder ('Restore a backup...' in the main window) if anything goes wrong.`nSteam Cloud should be OFF for Permafrost.`n`nContinue?"
  if ((Msg $txt 'Teleport?' 'YesNo' 'Question' 'Button2') -ne 'Yes') { PT-Status 'Cancelled - nothing changed.'; return $false }
  try {
    $r = Move-Player $script:SavePath $d $x $y $z $drop $label -FillVitals:$fill
    $snapNote = ''
    if ($snap) { try { [void](GS-WriteRequest $x $y $z $label); $snapNote = "`n`nGroundSnap will measure the real ground when you load and put you on it (what it did is in the Teleport tab afterwards and in GroundSnap.log in its mod folder)." } catch { GS-ClearRequest; $snapNote = "`n`nGroundSnap could not be set up ($($_.Exception.Message)); the estimated height is used as it is." } }
    else { GS-ClearRequest }
    PT-Status ('Teleport written and verified. Backup: ' + $r.Backup)
    if ($script:OnSaveChanged) { & $script:OnSaveChanged "Player tools: teleport to $label  (backup: $($r.Backup))" }
    PT-Load
    Msg "Done. You will load at X=$([int]$x) Y=$([int]$y) Z=$([int]($z + $drop)).$snapNote`n`nBackup: $($r.Backup)`n`nStart the game and load the world. If Steam asks about a cloud conflict, keep the LOCAL (newer) files. Not happy with the landing? Come back here and press 'Undo last teleport' (game closed)." 'Success' 'OK' 'Information' | Out-Null
    return $true
  } catch {
    PT-Status ('FAILED: ' + $_.Exception.Message)
    Msg "The change did not go through.`n`nReason: $($_.Exception.Message)`n`nNo harm done - your save was not modified (or was put back)." 'Failed safely' 'OK' 'Error' | Out-Null
    return $false
  }
}
function PT-Teleport {
  $ui = $script:PT; if ($ui.LvTele.SelectedItems.Count -eq 0) { Msg 'Pick a place in the list first.' 'Teleport' 'OK' 'Information' | Out-Null; return }
  $t = $ui.LvTele.SelectedItems[0].Tag; $th = Get-TargetHeight $t
  $z = if ($null -ne $ui.TeleLevelZ) { [double]$ui.TeleLevelZ } else { $th.Z }
  if ($null -eq $z) { Msg "There is no height data for this spot. Type a Z in the coordinates box (the in-game map shows your own X / Y / Z at its lower left) and use 'Teleport to coordinates'." 'No height' 'OK' 'Information' | Out-Null; return }
  [void](PT-DoMove $t.X $t.Y $z $t.Name $(if ($null -ne $ui.TeleLevelZ -and [math]::Abs($ui.TeleLevelZ - $th.Z) -gt 1) { 'the height you picked' } else { $th.Why }) (Test-HeightIsEstimate $t $z))
}
# teleport to the coordinates in the boxes (typed, read off the in-game map, or filled in by the map window); Z 0 = use the suggested height
function PT-TeleportXYZ {
  $ui = $script:PT; $x = [double]$ui.TeleX.Value; $y = [double]$ui.TeleY.Value; $z = [double]$ui.TeleZ.Value; $why = 'the height you typed'
  if ($z -eq 0) { $th = Get-TargetHeight ([pscustomobject]@{ Name = 'coordinates'; Kind = 'Coordinates'; X = $x; Y = $y; Z = 0 }); if ($null -eq $th.Z) { Msg "Type a Z as well: there is no height data near these coordinates." 'No height' 'OK' 'Information' | Out-Null; return }; $z = [double]$th.Z; $why = $th.Why }
  [void](PT-DoMove $x $y $z 'the coordinates you typed' $why (Test-HeightIsEstimate ([pscustomobject]@{ Name = 'coordinates'; Kind = 'Coordinates'; X = $x; Y = $y; Z = 0 }) $z))
}
function PT-ShowHeightsHere {
  $ui = $script:PT; [void](PT-ShowLevels ([pscustomobject]@{ Name = 'coordinates'; Kind = 'Coordinates'; X = [double]$ui.TeleX.Value; Y = [double]$ui.TeleY.Value; Z = 0 }) $false)
  if ($null -ne $ui.TeleLevelZ) { Set-Num $ui.TeleZ $ui.TeleLevelZ }
}
function PT-UndoTeleport {
  $ui = $script:PT; $u = Get-TeleportUndo $script:SavePath; if (-not $u) { Msg 'There is no teleport to undo for this save.' 'Undo' 'OK' 'Information' | Out-Null; return }
  if (Test-GameRunning) { Msg "The game is running, so nothing was changed.`n`nSave and close the game first, then try again." 'Game is running' 'OK' 'Warning' | Out-Null; return }
  if ((Msg "Put your position back to where it was before the last teleport (to: $($u.to), made $($u.at))?`n`nA backup is made first." 'Undo teleport?' 'YesNo' 'Question' 'Button2') -ne 'Yes') { return }
  try { $r = Undo-Teleport $script:SavePath; GS-ClearRequest; PT-Status ('Teleport undone. Backup: ' + $r.Backup); if ($script:OnSaveChanged) { & $script:OnSaveChanged "Player tools: teleport undone  (backup: $($r.Backup))" }; PT-Load; Msg "Done. Your old position is back.`n`nBackup: $($r.Backup)" 'Undone' 'OK' 'Information' | Out-Null }
  catch { PT-Status ('FAILED: ' + $_.Exception.Message); Msg "Nothing was changed.`n`nReason: $($_.Exception.Message)" 'Failed safely' 'OK' 'Error' | Out-Null }
}
function PT-SaveSpot {
  $ui = $script:PT; $d = $ui.Data; if (-not $d.Position) { Msg 'Your position could not be read.' 'My spot' 'OK' 'Information' | Out-Null; return }
  Add-Type -AssemblyName Microsoft.VisualBasic
  $name = if ($script:TestMode) { 'Test spot' } else { [Microsoft.VisualBasic.Interaction]::InputBox("Name for the spot (your position in the save: X $([int]$d.Position.X)  Y $([int]$d.Position.Y)  Z $([int]$d.Position.Z)):", 'Save my position as a spot', '') }
  if (-not $name -or -not $name.Trim()) { return }
  try { Add-MySpot $name $d.Position.X $d.Position.Y ($d.Position.Z - 150); PT-Status "Saved the spot '$($name.Trim())'."; PT-FillTele } catch { Msg $_.Exception.Message 'My spot' 'OK' 'Warning' | Out-Null }
}
function PT-DeleteSpot {
  $ui = $script:PT; if ($ui.LvTele.SelectedItems.Count -eq 0 -or $ui.LvTele.SelectedItems[0].Tag.Kind -ne 'My spot') { return }
  $n = $ui.LvTele.SelectedItems[0].Tag.Name; if ((Msg "Remove the spot '$n' from your list?" 'Remove spot' 'YesNo' 'Question' 'Button2') -ne 'Yes') { return }
  Remove-MySpot $n; PT-FillTele
}
function PT-OpenMap {
  $ui = $script:PT; $p = Show-TeleportMap $script:ActiveForm $script:SavePath $ui.Data
  if ($p) { Set-Num $ui.TeleX $p.X; Set-Num $ui.TeleY $p.Y; PT-ShowHeightsHere; $ui.LvTele.SelectedItems.Clear() }
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
  $t1 = NewTab 'Vitals and skills'
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
  # the last column (Benefit) takes whatever width the table has left, so nothing is cut off on a wide window
  $ui.LvSkills.Add_Resize({ $lv = $script:PT.LvSkills; if ($lv.Columns.Count -ge 6) { $o = 0; for ($i = 0; $i -lt 5; $i++) { $o += $lv.Columns[$i].Width }; $lv.Columns[5].Width = [math]::Max(260, $lv.ClientSize.Width - $o - 4) } })
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
  PT-RcInitTip $ui.LvRecipes; $ui.RcMode.Add_SelectedIndexChanged({ PT-FillRecipes }); $ui.RcKind.Add_SelectedIndexChanged({ PT-FillRecipes }); $ui.RcFilter.Add_TextChanged({ PT-FillRecipes })
  $bAllRc.Add_Click({ foreach ($i in $script:PT.LvRecipes.Items) { $i.Checked = ($i.SubItems[3].Text -eq 'not learned') } }); $bNoRc.Add_Click({ foreach ($i in $script:PT.LvRecipes.Items) { $i.Checked = $false } }); $bUn.Add_Click({ PT-UnlockRecipes })

  # --- tab 3: teleport (docked panels and flow rows, so it fills any window size and display scaling: places on the left, the heights and the controls on the right)
  $t3 = NewTab 'Teleport'
  $bold = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
  $mkLbl = { param([string]$text) $l = New-Object System.Windows.Forms.Label; $l.Text = $text; $l.AutoSize = $true; $l.Margin = New-Object System.Windows.Forms.Padding(0, 8, 8, 0); return $l }
  $mkBtn = { param([string]$text, [bool]$primary) $b = New-Object System.Windows.Forms.Button; $b.Text = $text; $b.AutoSize = $true; $b.AutoSizeMode = 'GrowAndShrink'; $b.MinimumSize = New-Object System.Drawing.Size(0, 34); $b.Padding = New-Object System.Windows.Forms.Padding(12, 0, 12, 0); $b.Margin = New-Object System.Windows.Forms.Padding(0, 4, 10, 4); if ($primary) { $b.Font = $bold }; return $b }
  $mkNum = { param([int]$w, [decimal]$min, [decimal]$max) $n = New-Object System.Windows.Forms.NumericUpDown; $n.Width = $w; $n.Minimum = $min; $n.Maximum = $max; $n.DecimalPlaces = 0; $n.Margin = New-Object System.Windows.Forms.Padding(0, 4, 14, 4); return $n }
  $mkRow = { $r = New-Object System.Windows.Forms.FlowLayoutPanel; $r.Dock = 'Fill'; $r.AutoSize = $true; $r.AutoSizeMode = 'GrowAndShrink'; $r.WrapContents = $true; $r.Margin = New-Object System.Windows.Forms.Padding(0, 2, 0, 2); return $r }
  $mkGroup = { param([string]$title) $g = New-Object ThemedGroup; $g.Text = $title; $g.Dock = 'Fill'; $g.Padding = New-Object System.Windows.Forms.Padding(12, 8, 12, 10); return $g }
  $head = New-Object System.Windows.Forms.Panel; $head.Dock = 'Top'; $head.Height = 34; $t3.Controls.Add($head)
  $ui.TeleNow = New-Object System.Windows.Forms.Label; $ui.TeleNow.Dock = 'Fill'; $ui.TeleNow.TextAlign = 'MiddleLeft'; $ui.TeleNow.Font = $bold; $head.Controls.Add($ui.TeleNow)
  $tl = New-Object System.Windows.Forms.TableLayoutPanel; $tl.Dock = 'Fill'; $tl.ColumnCount = 2; $tl.RowCount = 1
  [void]$tl.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 54))); [void]$tl.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 46))); [void]$tl.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
  $t3.Controls.Add($tl); $tl.BringToFront()
  # left: the places
  $gP = & $mkGroup 'Places'; $gP.Margin = New-Object System.Windows.Forms.Padding(0, 0, 10, 0); $tl.Controls.Add($gP, 0, 0)
  $fr = New-Object System.Windows.Forms.FlowLayoutPanel; $fr.Dock = 'Top'; $fr.AutoSize = $true; $fr.AutoSizeMode = 'GrowAndShrink'; $fr.WrapContents = $false; $fr.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 6); $gP.Controls.Add($fr)
  $fr.Controls.Add((& $mkLbl 'Search'))
  $ui.TeleFilter = New-Object System.Windows.Forms.TextBox; $ui.TeleFilter.Width = 230; $ui.TeleFilter.Margin = New-Object System.Windows.Forms.Padding(0, 5, 18, 5); $fr.Controls.Add($ui.TeleFilter)
  $fr.Controls.Add((& $mkLbl 'Show'))
  $ui.TeleKind = New-Object System.Windows.Forms.ComboBox; $ui.TeleKind.DropDownStyle = 'DropDownList'; $ui.TeleKind.Width = 210; $ui.TeleKind.Margin = New-Object System.Windows.Forms.Padding(0, 5, 0, 5); foreach ($k in 'All', 'Named places', 'Fast travel', 'My spots', 'Bed, start and builds') { [void]$ui.TeleKind.Items.Add($k) }; $ui.TeleKind.SelectedIndex = 0; $fr.Controls.Add($ui.TeleKind)
  $ui.LvTele = New-LV $gP @('Place', 'Kind', 'Distance (m)', 'Height (Z)') @(240, 130, 120, 110); $ui.LvTele.Dock = 'Fill'; $ui.LvTele.BringToFront()
  # right: the controls on top, the heights below
  $rt = New-Object System.Windows.Forms.TableLayoutPanel; $rt.Dock = 'Fill'; $rt.ColumnCount = 1; $rt.RowCount = 2; [void]$rt.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
  [void]$rt.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 44))); [void]$rt.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 56))); $tl.Controls.Add($rt, 1, 0)
  $gG = & $mkGroup 'Go there'; $gG.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 10); $rt.Controls.Add($gG, 0, 0)
  $gt = New-Object System.Windows.Forms.TableLayoutPanel; $gt.Dock = 'Top'; $gt.AutoSize = $true; $gt.AutoSizeMode = 'GrowAndShrink'; $gt.ColumnCount = 1; [void]$gt.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100))); $pnl = New-Object System.Windows.Forms.Panel; $pnl.Dock = 'Fill'; $pnl.AutoScroll = $true; $gG.Controls.Add($pnl); $pnl.Controls.Add($gt)
  $r1 = & $mkRow; $r1.Controls.Add((& $mkLbl 'X')); $ui.TeleX = & $mkNum 96 -400000 400000; $r1.Controls.Add($ui.TeleX); $r1.Controls.Add((& $mkLbl 'Y')); $ui.TeleY = & $mkNum 96 -400000 400000; $r1.Controls.Add($ui.TeleY); $r1.Controls.Add((& $mkLbl 'Z')); $ui.TeleZ = & $mkNum 86 -20000 40000; $r1.Controls.Add($ui.TeleZ)
  $bHere = & $mkBtn 'Heights here' $false; $r1.Controls.Add($bHere)
  $r2 = & $mkRow; $r2.Controls.Add((& $mkLbl 'Drop height (cm)')); $ui.TeleDrop = & $mkNum 80 50 2000; $ui.TeleDrop.Value = 400; $r2.Controls.Add($ui.TeleDrop)
  $ui.TeleVitals = New-Object System.Windows.Forms.CheckBox; $ui.TeleVitals.Text = 'Refill my vitals first (recommended)'; $ui.TeleVitals.Checked = $true; $ui.TeleVitals.AutoSize = $true; $ui.TeleVitals.Margin = New-Object System.Windows.Forms.Padding(8, 7, 0, 0); $ui.TeleVitals.ForeColor = $script:Th.Text; $r2.Controls.Add($ui.TeleVitals)
  $r2b = & $mkRow
  $ui.TeleSnap = New-Object System.Windows.Forms.CheckBox; $ui.TeleSnap.Text = 'Let the game fix my height when I arrive (GroundSnap mod)'; $ui.TeleSnap.Checked = $true; $ui.TeleSnap.AutoSize = $true; $ui.TeleSnap.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 0); $ui.TeleSnap.ForeColor = $script:Th.Text; $r2b.Controls.Add($ui.TeleSnap)
  $ui.TeleSnapNote = New-Object System.Windows.Forms.Label; $ui.TeleSnapNote.AutoSize = $true; $ui.TeleSnapNote.MaximumSize = New-Object System.Drawing.Size(640, 0); $ui.TeleSnapNote.ForeColor = $script:Th.Muted; $ui.TeleSnapNote.Margin = New-Object System.Windows.Forms.Padding(22, 0, 0, 0); $r2b.Controls.Add($ui.TeleSnapNote); $r2b.SetFlowBreak($ui.TeleSnap, $true)
  $tipSnap = New-Object System.Windows.Forms.ToolTip; $tipSnap.AutoPopDelay = 30000; $tipSnap.SetToolTip($ui.TeleSnap, "The tool only has estimates of the ground height. With this on, a small in-game mod (GroundSnap, for UE4SS) holds you in the air when you load, asks the game where the real ground is under you,`nand puts you on it - so a wrong estimate cannot put you under the map or drop you from a great height. Your save is not touched by it.`nHeights that are real (your bed, the start, your builds, your saved spots, a Z you typed) are never corrected.")
  $r3 = & $mkRow; $r3.Margin = New-Object System.Windows.Forms.Padding(0, 2, 0, 8); $bTp = & $mkBtn 'Teleport to selected place' $true; $bXyz = & $mkBtn 'Teleport to coordinates' $true; $r3.Controls.Add($bTp); $r3.Controls.Add($bXyz)
  $r4 = & $mkRow; $bMap = & $mkBtn 'Open the map...' $false; $bSpot = & $mkBtn 'Save my position...' $false; $ui.BtnUndo = & $mkBtn 'Undo last teleport' $false; $ui.BtnDelSpot = & $mkBtn 'Remove my spot' $false; $ui.BtnDelSpot.Enabled = $false
  foreach ($b in $bMap, $bSpot, $ui.BtnUndo, $ui.BtnDelSpot) { $r4.Controls.Add($b) }
  foreach ($rw in $r3, $r1, $r2, $r2b, $r4) { $gt.Controls.Add($rw) }   # the two main buttons first: they stay in view in a small window
  $gH = & $mkGroup 'Heights found near the selected spot'; $rt.Controls.Add($gH, 0, 1)
  $hl = New-Object System.Windows.Forms.TableLayoutPanel; $hl.Dock = 'Fill'; $hl.ColumnCount = 1; $hl.RowCount = 2; [void]$hl.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100)))
  [void]$hl.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 56))); [void]$hl.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 44))); $gH.Controls.Add($hl)
  $ui.LvLevels = New-LV $hl @('Height (Z)', 'Objects', 'On ground', 'Nearest (m)') @(110, 100, 120, 120); $ui.LvLevels.Dock = 'Fill'; $ui.LvLevels.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
  $ui.TeleInfo = New-Object System.Windows.Forms.Label; $ui.TeleInfo.Dock = 'Fill'; $ui.TeleInfo.AutoSize = $false; $ui.TeleInfo.ForeColor = $script:Th.Muted
  $ui.TeleInfo.Text = "Pick a place in the list: its heights appear here, the suggested one in bold.`r`n`r`nHow it works: a new position is written into the save (game closed, backup first; Undo last teleport puts it back). You load above the spot and drop onto it; with 'Let the game fix my height' ticked, a small in-game mod then measures the real ground and puts you on it. Places: the game's named locations and fast-travel points, your bed, the crash site, your builds and your own spots. Open the map to click any point. Heights come from objects the atlas flights found: good, not perfect, on hills and in buildings."
  $hl.Controls.Add($ui.TeleInfo)
  $fitCols = { Fit-LastColumn $this; $lc = $this.Columns[$this.Columns.Count - 1]; $lc.Width = [math]::Max(40, $lc.Width - 24) }; $ui.LvTele.Add_Resize($fitCols); $ui.LvLevels.Add_Resize($fitCols)   # leave room for the scroll bar so no horizontal bar shows
  $ui.TeleLevelZ = $null; $ui.TeleBusy = $false
  $ui.TeleFilter.Add_TextChanged({ PT-FillTele }); $ui.TeleKind.Add_SelectedIndexChanged({ PT-FillTele })
  $bTp.Add_Click({ PT-Teleport }); $ui.LvTele.Add_DoubleClick({ PT-Teleport }); $ui.LvTele.Add_SelectedIndexChanged({ PT-OnPlaceSelected }); $ui.LvLevels.Add_SelectedIndexChanged({ PT-OnLevelPicked })
  $bXyz.Add_Click({ PT-TeleportXYZ }); $bHere.Add_Click({ PT-ShowHeightsHere }); $ui.BtnUndo.Add_Click({ PT-UndoTeleport }); $ui.BtnDelSpot.Add_Click({ PT-DeleteSpot }); $bMap.Add_Click({ PT-OpenMap }); $bSpot.Add_Click({ PT-SaveSpot })
  $ui.TeleDrop.Add_ValueChanged({ if ($script:PT.LvLevels.SelectedItems.Count) { PT-OnLevelPicked } })

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
function Show-PlayerTools($owner) { $f = New-PlayerForm; $f.WindowState = 'Maximized'; $script:ActiveForm = $f; try { [void]$f.ShowDialog($owner) } finally { $script:ActiveForm = $null } }

