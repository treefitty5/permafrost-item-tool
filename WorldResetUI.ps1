# WorldResetUI.ps1 - the "World reset" window: put felled trees, mined ores, picked-up items and looted containers back (engine: WorldReset.ps1).
# Needs SaveCore.ps1, WorldCore.ps1, WorldReset.ps1 and PlayerTools.ps1 (helpers) loaded. The save is only written by the Reset button; a backup is made first.
$script:WR = @{}

function WR-Options {
  $u = $script:WR
  return @{ Trees = $u.ChkTrees.Checked; Ores = $u.ChkOres.Checked; Breakables = $u.ChkBreak.Checked; Items = $u.ChkItems.Checked; Containers = $u.ChkCont.Checked
            KeepFilled = $u.ChkKeep.Checked; RadiusM = [double]$u.Radius.Value; Seed = [int]((Get-Date).Ticks % 100000) }
}
# the world to work on: the one chosen in this window's World box (it starts on the save selected in the main window)
function WR-SavePath {
  $u = $script:WR
  if ($u.World -and $u.World.SelectedItem -and $u.WorldPaths -and $u.WorldPaths.ContainsKey([string]$u.World.SelectedItem)) { return $u.WorldPaths[[string]$u.World.SelectedItem] }
  if ($script:WRSavePathOverride) { return $script:WRSavePathOverride }
  return $script:SavePath
}
function WR-WorldInfo {
  $u = $script:WR; if (-not $u.WorldInfo) { return }
  try {
    $path = WR-SavePath; $leaf = [IO.Path]::GetFileName($path); $s = $script:L1.GetString([IO.File]::ReadAllBytes($path))
    $hrs = [regex]::Match($s, 'TotalPlayTime>([\d\.]+)').Groups[1].Value; $when = [regex]::Match($s, 'LastUpdatedAt>([^\?]+)').Groups[1].Value
    $nb = @(Get-ChildItem (Get-BackupDir) -Filter "*_$leaf" -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '_NEW_' }).Count
    $h = ''; if ($hrs) { $h = ('{0:0.0} h played, ' -f ([double]::Parse($hrs, [Globalization.CultureInfo]::InvariantCulture) / 3600)) }
    $u.WorldInfo.Text = "$h" + "last saved $when, $nb backup(s) of this world" + $(if ($nb -eq 0) { ' (no history: destroyed ores and picked-up items cannot be restored)' } else { '' })
  } catch { $u.WorldInfo.Text = "Could not read this save: $($_.Exception.Message)" }
}

function WR-Preview {
  $u = $script:WR; $u.Msg.Text = ''
  try {
    if (-not ($u.ChkTrees.Checked -or $u.ChkOres.Checked -or $u.ChkBreak.Checked -or $u.ChkItems.Checked -or $u.ChkCont.Checked)) { $u.Out.Text = 'Tick at least one thing to put back.'; return }
    $form = $u.Form; $old = $form.Cursor; $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor; [System.Windows.Forms.Application]::DoEvents()
    $plan = Build-ResetPlan (WR-SavePath) (WR-Options)
    $u.Plan = $plan; $u.Out.Text = ((Get-ResetSummary $plan) -join "`r`n")
    $form.Cursor = $old
  } catch { $u.Out.Text = "Could not read the save: $($_.Exception.Message)"; try { $u.Form.Cursor = [System.Windows.Forms.Cursors]::Default } catch { } }
}

function WR-DoReset {
  $u = $script:WR
  try {
    if ((-not $script:TestMode) -and (Test-GameRunning)) { Msg 'The game is running. Save and close Permafrost first (a running game would overwrite the change).' 'World reset' 'OK' 'Warning' | Out-Null; return }
    WR-Preview; if (-not $u.Plan -or $u.Plan.Items.Count -eq 0) { if ($u.Plan) { Msg 'Nothing to put back with these settings - nothing was changed.' 'World reset' 'OK' 'Information' | Out-Null }; return }
    $a = Msg ("About to change this world:`n" + (WR-SavePath) + "`n`n" + ($u.Out.Text) + "`n`nA backup is made first and the result is checked before it replaces the save. Steam Cloud should be OFF for Permafrost.`n`nContinue?") 'World reset' 'OKCancel' 'Question' 'Button2'
    if ($a -ne 'OK') { return }
    $u.Form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor; [System.Windows.Forms.Application]::DoEvents()
    $res = Install-WorldReset (WR-SavePath) (WR-Options) -SkipGameCheck:$script:TestMode
    $u.Form.Cursor = [System.Windows.Forms.Cursors]::Default
    $u.Msg.Text = "Done. Backup: $([IO.Path]::GetFileName($res.Backup)). Start the game and load the world."
    $u.Out.Text = ((@('Reset done:') + $res.Summary) -join "`r`n"); $u.Plan = $null
    if ($script:OnSaveChanged) { & $script:OnSaveChanged "World reset applied (backup $([IO.Path]::GetFileName($res.Backup)))." }
  } catch { try { $u.Form.Cursor = [System.Windows.Forms.Cursors]::Default } catch { }; Msg "Nothing was changed: $($_.Exception.Message)" 'World reset' 'OK' 'Error' | Out-Null; $u.Msg.Text = "Failed: $($_.Exception.Message)" }
}

function New-WorldResetForm {
  Add-Type -AssemblyName System.Windows.Forms; Add-Type -AssemblyName System.Drawing
  $script:WR = @{ Plan = $null }; $u = $script:WR
  $f = New-Object System.Windows.Forms.Form; $f.Text = 'World reset  -  put trees, ores, items and loot back'; $f.Size = New-Object System.Drawing.Size(820, 680); $f.MinimumSize = New-Object System.Drawing.Size(720, 600)
  $f.StartPosition = 'CenterParent'; $f.Font = New-Object System.Drawing.Font('Segoe UI', 9); $u.Form = $f
  New-Lbl $f 'World' 14 15 50 | Out-Null
  $u.World = New-Object System.Windows.Forms.ComboBox; $u.World.DropDownStyle = 'DropDownList'; $u.World.Location = New-Object System.Drawing.Point(66, 11); $u.World.Size = New-Object System.Drawing.Size(200, 24); $f.Controls.Add($u.World)
  $u.WorldInfo = New-Lbl $f '' 276 15 520 20; $u.WorldInfo.Anchor = 'Top,Left,Right'; $u.WorldInfo.ForeColor = $script:Th.Muted
  $u.WorldPaths = @{}
  $curPath = $(if ($script:WRSavePathOverride) { $script:WRSavePathOverride } else { $script:SavePath }); $dir = Split-Path $curPath -Parent
  if ($dir -and (Test-Path -LiteralPath $dir)) { foreach ($sf in (Get-ChildItem -LiteralPath $dir -Filter '*.pfs' | Sort-Object Name)) { $u.WorldPaths[$sf.Name] = $sf.FullName; [void]$u.World.Items.Add($sf.Name) } }
  $curName = [IO.Path]::GetFileName($curPath); if (-not $u.WorldPaths.ContainsKey($curName)) { $u.WorldPaths[$curName] = $curPath; [void]$u.World.Items.Add($curName) }
  $u.World.SelectedItem = $curName
  $g = New-Object ThemedGroup; $g.Text = 'What to put back'; $g.Location = '10,46'; $g.Size = '780,196'; $g.Anchor = 'Top,Left,Right'; $f.Controls.Add($g)
  function Chk($parent, $text, $x, $y, $w, $on) { $c = New-Object System.Windows.Forms.CheckBox; $c.Text = $text; $c.Location = New-Object System.Drawing.Point($x, $y); $c.Size = New-Object System.Drawing.Size($w, 22); $c.Checked = $on; $parent.Controls.Add($c); return $c }
  $u.ChkTrees = Chk $g 'Trees you have chopped down' 14 26 360 $true
  $u.ChkOres = Chk $g 'Boulders and ores (rock, coal, flint, iron, copper, sulfur, gold, moon rock)' 14 52 600 $true
  $u.ChkItems = Chk $g 'Items that lay in the world (scrap, oil, plastic, food... that you picked up)' 14 78 600 $true
  $u.ChkCont = Chk $g 'Loot in containers (cars, cabinets, crates, corpses, trash cans...)' 14 104 600 $true
  $u.ChkBreak = Chk $g 'Other breakables (pallets, rubble, trash piles, furniture)' 14 130 600 $false
  $u.ChkKeep = Chk $g 'Leave containers alone that still hold items' 14 156 600 $true
  $r = New-Lbl $f 'Only within' 14 254 80; $u.Radius = New-Num $f 96 251 80 0 100000 0; $u.Radius.Value = 0
  New-Lbl $f 'metres of where you stand in the save (0 = the whole world). Tip: try 150 first, load the game, check, then do the rest.' 182 254 620 | Out-Null
  $u.Preview = New-Btn $f 'Preview' 10 284 140 30; $u.Reset = New-Btn $f 'Reset the world now...' 160 284 200 30; $u.Reset.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
  $note = New-Lbl $f 'Bushes are not covered: no save shows a harvested bush yet, so how the game remembers one is unknown. The game must be closed.' 370 290 430 36; $note.ForeColor = $script:Th.Muted
  $u.Out = New-Object System.Windows.Forms.TextBox; $u.Out.Multiline = $true; $u.Out.ReadOnly = $true; $u.Out.ScrollBars = 'Vertical'; $u.Out.Location = New-Object System.Drawing.Point(10, 328); $u.Out.Size = New-Object System.Drawing.Size(780, 254); $u.Out.Anchor = 'Top,Left,Right,Bottom'; $u.Out.Font = New-Object System.Drawing.Font('Consolas', 9.5)
  $u.Out.Text = 'Press Preview to see what would be put back. Nothing is changed until you press Reset.'; $f.Controls.Add($u.Out)
  $u.Msg = New-Lbl $f '' 10 590 780 40; $u.Msg.Anchor = 'Left,Right,Bottom'; $u.Msg.ForeColor = $script:Th.Accent
  $u.Preview.Add_Click({ WR-Preview }); $u.Reset.Add_Click({ WR-DoReset })
  foreach ($c in @($u.ChkTrees, $u.ChkOres, $u.ChkItems, $u.ChkCont, $u.ChkBreak, $u.ChkKeep)) { $c.Add_CheckedChanged({ $script:WR.Plan = $null }) }
  $u.Radius.Add_ValueChanged({ $script:WR.Plan = $null })
  $u.World.Add_SelectedIndexChanged({ $script:WR.Plan = $null; $script:WR.Msg.Text = ''; $script:WR.Out.Text = 'World changed. Press Preview to see what would be put back in it.'; WR-WorldInfo })
  WR-WorldInfo
  Apply-Theme $f; Set-AppIcon $f
  return $f
}
function Show-WorldReset($owner) { $f = New-WorldResetForm; $script:ActiveForm = $f; try { [void]$f.ShowDialog($owner) } finally { $script:ActiveForm = $null } }
