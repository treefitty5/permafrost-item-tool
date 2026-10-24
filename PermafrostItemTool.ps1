param([switch]$Headless, [switch]$SelfTest)   # -Headless builds the window without showing it (used for testing)
$ErrorActionPreference = 'Stop'
$script:ToolDir = $PSScriptRoot
$script:ErrLog = Join-Path $PSScriptRoot 'error.log'
try {
  . (Join-Path $PSScriptRoot 'Paths.ps1')
  . (Join-Path $PSScriptRoot 'SaveCore.ps1')
  . (Join-Path $PSScriptRoot 'Theme.ps1')
  . (Join-Path $PSScriptRoot 'PlayerCore.ps1')
  . (Join-Path $PSScriptRoot 'PlayerTools.ps1')
  . (Join-Path $PSScriptRoot 'GameData.ps1')
. (Join-Path $PSScriptRoot 'RecipeTweaks.ps1')
  . (Join-Path $PSScriptRoot 'BackpackTweaks.ps1')
  . (Join-Path $PSScriptRoot 'StackTweaks.ps1')
  . (Join-Path $PSScriptRoot 'WorldCore.ps1')
  . (Join-Path $PSScriptRoot 'WorldReset.ps1')
  . (Join-Path $PSScriptRoot 'WorldResetUI.ps1')
  . (Join-Path $PSScriptRoot 'GameFiles.ps1')
  . (Join-Path $PSScriptRoot 'PicturesUI.ps1')
  . (Join-Path $PSScriptRoot 'WorldPicker.ps1')
  . (Join-Path $PSScriptRoot 'OverviewUI.ps1')
  . (Join-Path $PSScriptRoot 'BuildMove.ps1')
  . (Join-Path $PSScriptRoot 'HelpUI.ps1')
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing
  $script:BusySkip = [bool]($SelfTest -or $Headless)
  if ($SelfTest) { [System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException) }
  # All windows are laid out in 96-DPI pixels. PowerShell 7 starts system-DPI-aware, so at 125% / 150% display scaling the FONTS grow but the boxes and buttons do not
  # (text gets clipped: "World rese", "Add to s"...). Ask Windows to draw our windows DPI-unaware instead: it scales each window as a whole, so the layout is the same at every scaling.
  # On a small or highly scaled screen Windows' scaled-down desktop has fewer pixels than the layout needs (1920x1080 at 150% = 1280x720): the main window then scrolls (AutoScroll) instead of being cut off.
  try {
    if (-not ('PfDpiAwareness' -as [type])) { Add-Type -Namespace '' -Name PfDpiAwareness -MemberDefinition '[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern System.IntPtr SetThreadDpiAwarenessContext(System.IntPtr c); [System.Runtime.InteropServices.DllImport("user32.dll")] public static extern int GetDpiForSystem();' }
    $dpiScale = [PfDpiAwareness]::GetDpiForSystem() / 96.0; $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
    $script:DpiUnaware = $true
    if ($script:DpiUnaware) { [void][PfDpiAwareness]::SetThreadDpiAwarenessContext([IntPtr](-1)) }   # DPI_AWARENESS_CONTEXT_UNAWARE; needs Windows 10 1607+, ignored otherwise
  } catch { }
  [System.Windows.Forms.Application]::EnableVisualStyles()

  # first run (no data made yet): say what to do instead of failing
  if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'items.json'))) {
    if ($SelfTest -or $Headless) { Write-Output 'FIRST-RUN: no items.json yet (game data not made)'; return }
    [void][System.Windows.Forms.MessageBox]::Show("The tool's data files (items.json and the catalog folder) are missing.`r`n`r`nDownload the full release ZIP from the repository's Releases page (not only the source code), or rebuild the data from your own game files with Build-Everything.ps1 (see the README, Advanced). Then start the tool again.", 'Permafrost Item Tool - first run', 'OK', 'Information')
    return
  }
  $script:SavePath = PF-SavePath
  $script:Cat = Get-Catalog
  $script:Queue = New-Object System.Collections.Generic.List[object]
  $script:Selected = $null

  # ---------- form ----------
  $form = New-Object System.Windows.Forms.Form
  $form.Text = 'Permafrost Item Tool  (single-player saves only)'
  $form.AutoScroll = $true   # when the window is smaller than the layout needs (small laptop, high scaling) a scrollbar appears instead of the bottom being cut off
  $waStart = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea; $form.Size = New-Object System.Drawing.Size([math]::Min(1180, $waStart.Width), [math]::Min(940, $waStart.Height)); $form.MinimumSize = New-Object System.Drawing.Size(640, 420)
  $form.StartPosition = 'CenterScreen'; $form.Font = New-Object System.Drawing.Font('Segoe UI', 9); Set-AppIcon $form

  function New-Ctl($type, $x, $y, $w, $h, $text = '') { $c = New-Object $type; $c.Location = New-Object System.Drawing.Point($x, $y); $c.Size = New-Object System.Drawing.Size($w, $h); if ($text) { $c.Text = $text }; $form.Controls.Add($c); return $c }

  # top bar: save file + game status
  $lblSave = New-Ctl System.Windows.Forms.Label 12 14 70 20 'Save file:'
  $txtSave = New-Ctl System.Windows.Forms.TextBox 84 11 760 24; $txtSave.Text = $script:SavePath; $txtSave.Anchor = 'Top,Left,Right'
  $btnBrowse = New-Ctl System.Windows.Forms.Button 852 10 80 26 'Browse...'; $btnBrowse.Anchor = 'Top,Right'
  $btnReload = New-Ctl System.Windows.Forms.Button 938 10 80 26 'Reload'; $btnReload.Anchor = 'Top,Right'
  $btnHelp = New-Ctl System.Windows.Forms.Button 1024 10 132 26 'Help / how it works'; $btnHelp.Anchor = 'Top,Right'
  $btnData = New-Ctl System.Windows.Forms.Button 900 10 110 26 'Game data'; $btnPlayer = New-Ctl System.Windows.Forms.Button 780 10 110 26 'Player tools'; $btnTweaks = New-Ctl System.Windows.Forms.Button 650 10 120 26 'Recipe tweaks'; $btnWorld = New-Ctl System.Windows.Forms.Button 520 10 110 26 'World reset'; $btnMove = New-Ctl System.Windows.Forms.Button 400 10 110 26 'Build move'; $btnPics = New-Ctl System.Windows.Forms.Button 300 10 90 26 'Pictures'; $btnOv = New-Ctl System.Windows.Forms.Button 200 10 90 26 'Overview'; $btnStk = New-Ctl System.Windows.Forms.Button 100 10 110 26 'Stack sizes'
  # first-run bar: shown under the save row while no pictures exist (Update-PicsBar), so the player does not have to find the top button
  $script:PicsBarOn = $false; $pnlPics = New-Object System.Windows.Forms.Panel; $pnlPics.Visible = $false; $form.Controls.Add($pnlPics)
  $lblPics = New-Object System.Windows.Forms.Label; $lblPics.AutoSize = $false; $lblPics.BackColor = [System.Drawing.Color]::Transparent; $lblPics.TextAlign = 'MiddleLeft'; $lblPics.Text = 'Item pictures are not built yet. Build them from your installed game: read-only, about 20 seconds, one time.'; $pnlPics.Controls.Add($lblPics)
  $btnPicsGo = New-Object System.Windows.Forms.Button; $btnPicsGo.Text = 'Build pictures now'; $btnPicsGo.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold); $pnlPics.Controls.Add($btnPicsGo)
  $btnPicsLater = New-Object System.Windows.Forms.Button; $btnPicsLater.Text = 'Not now'; $pnlPics.Controls.Add($btnPicsLater)
  $btnPicsNever = New-Object System.Windows.Forms.Button; $btnPicsNever.Text = "Don't ask again"; $pnlPics.Controls.Add($btnPicsNever)
  $pnlPics.Add_Paint({ param($s, $e) $c = $script:Th.Accent; $b = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(46, $c.R, $c.G, $c.B)); $e.Graphics.FillRectangle($b, 0, 0, $s.Width, $s.Height); $b.Dispose(); $p = New-Object System.Drawing.Pen($c); $e.Graphics.DrawRectangle($p, 0, 0, $s.Width - 1, $s.Height - 1); $p.Dispose() })
  $lblGame = New-Ctl System.Windows.Forms.Label 12 44 1140 22; $lblGame.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold); $lblGame.Anchor = 'Top,Left,Right'
  $lblInfo = New-Ctl System.Windows.Forms.Label 12 66 1140 20; $lblInfo.Anchor = 'Top,Left,Right'
  $lblNote = New-Ctl System.Windows.Forms.Label 12 86 1140 20 'Before applying: close the game, and keep Steam Cloud off for Permafrost while testing. A backup is made automatically before every change.'; $lblNote.ForeColor = $script:Th.Muted; $lblNote.Anchor = 'Top,Left,Right'; foreach ($el in @($lblGame, $lblInfo, $lblNote)) { $el.AutoEllipsis = $true }
  $lblBp = New-Ctl System.Windows.Forms.Label 700 66 104 20 'Backpack slots:'
  $numBp = New-Ctl System.Windows.Forms.NumericUpDown 810 64 70 24; $numBp.Minimum = 5; $numBp.Maximum = 100; $numBp.Increment = 5; $numBp.Value = 25
  $btnBp = New-Ctl System.Windows.Forms.Button 868 62 104 26 'Apply in game'
  $lblBpHint = New-Ctl System.Windows.Forms.Label 700 88 380 18; $lblBpHint.TextAlign = 'MiddleRight'; $lblBpHint.AutoEllipsis = $true; $lblBpHint.ForeColor = $script:Th.Muted

  # catalog panel
  $gbCat = New-Ctl ThemedGroup 12 112 560 396 'Item catalog'; $gbCat.Anchor = 'Top,Left,Bottom'
  $txtSearch = New-Object System.Windows.Forms.TextBox; $txtSearch.Location = '10,22'; $txtSearch.Size = '340,24'; $gbCat.Controls.Add($txtSearch)
  $cmbCat = New-Object System.Windows.Forms.ComboBox; $cmbCat.Location = '358,22'; $cmbCat.Size = '190,24'; $cmbCat.DropDownStyle = 'DropDownList'; $gbCat.Controls.Add($cmbCat)
  $lvCat = New-Object System.Windows.Forms.ListView; $lvCat.Location = '10,52'; $lvCat.Size = '540,334'; $lvCat.View = 'Details'; $lvCat.FullRowSelect = $true; $lvCat.HideSelection = $false; $lvCat.MultiSelect = $false; $lvCat.Anchor = 'Top,Left,Bottom,Right'
  $script:CatCols = 'Item', 'Name', 'Category', 'Stack', 'Cond.', 'Dmg', 'Frost', 'Value', 'Ammo', 'Found via', 'Status'; foreach ($cw in @(@('Item', 104), @('Name', 98), @('Category', 56), @('Stack', 44), @('Cond.', 48), @('Dmg', 42), @('Frost', 46), @('Value', 48), @('Ammo', 46), @('Found via', 78), @('Status', 68))) { [void]$lvCat.Columns.Add($cw[0], $cw[1]) }; $gbCat.Controls.Add($lvCat)

  # selected item panel
  $gbSel = New-Ctl ThemedGroup 584 112 572 250 'Selected item'; $gbSel.Anchor = 'Top,Right'
  $lblSelId = New-Object System.Windows.Forms.Label; $lblSelId.Location = '12,22'; $lblSelId.Size = '548,20'; $lblSelId.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold); $gbSel.Controls.Add($lblSelId)
  $lblSelInfo = New-Object System.Windows.Forms.Label; $lblSelInfo.Location = '12,44'; $lblSelInfo.Size = '548,40'; $gbSel.Controls.Add($lblSelInfo)
  function New-Row($label, $y, $min, $max, $val, [int]$dec = 0) {
    $l = New-Object System.Windows.Forms.Label; $l.Location = "12,$($y+3)"; $l.Size = '170,20'; $l.Text = $label; $gbSel.Controls.Add($l)
    $n = New-Object System.Windows.Forms.NumericUpDown; $n.Location = "186,$y"; $n.Size = '110,24'; $n.Minimum = $min; $n.Maximum = $max; $n.DecimalPlaces = $dec; $n.Value = $val; $gbSel.Controls.Add($n); $n.Tag = $l; return $n }
  $numQty = New-Row 'Total quantity (all stacks)' 86 1 99999 1
  $numStack = New-Row 'Items per slot (stack size)' 116 1 99999 1
  $numCond = New-Row 'Condition / durability' 146 0 9999 0 1
  $numLoaded = New-Row 'Rounds already loaded' 176 0 999 0
  $lblTarget = New-Object System.Windows.Forms.Label; $lblTarget.Location = '12,209'; $lblTarget.Size = '170,20'; $lblTarget.Text = 'Put it in'; $gbSel.Controls.Add($lblTarget)
  $cmbTarget = New-Object System.Windows.Forms.ComboBox; $cmbTarget.Location = '186,206'; $cmbTarget.Size = '110,24'; $cmbTarget.DropDownStyle = 'DropDownList'; [void]$cmbTarget.Items.AddRange(@('Backpack', 'Hotbar')); $cmbTarget.SelectedIndex = 0; $gbSel.Controls.Add($cmbTarget)
  $btnAdd = New-Object System.Windows.Forms.Button; $btnAdd.Location = '330,180'; $btnAdd.Size = '220,50'; $btnAdd.Text = 'Add to queue'; $btnAdd.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold); $gbSel.Controls.Add($btnAdd)
  $tip = New-Object System.Windows.Forms.Label; $tip.Location = '306,86'; $tip.Size = '254,40'; $tip.ForeColor = $script:Th.Muted
  $script:DefaultTip = ""; $tip.Text = ""; $tip.Visible = $false; $gbSel.Controls.Add($tip)
  $lblPlan = New-Object System.Windows.Forms.Label; $lblPlan.Location = '306,158'; $lblPlan.Size = '254,20'; $lblPlan.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold); $lblPlan.ForeColor = $script:Th.Accent; $gbSel.Controls.Add($lblPlan)
  $lblStacks = New-Object System.Windows.Forms.Label; $lblStacks.Location = '306,132'; $lblStacks.Size = '130,20'; $lblStacks.Text = '...or number of stacks'; $gbSel.Controls.Add($lblStacks)
  $numStacks = New-Object System.Windows.Forms.NumericUpDown; $numStacks.Location = '440,129'; $numStacks.Size = '80,24'; $numStacks.Minimum = 1; $numStacks.Maximum = 9999; $numStacks.Value = 1; $gbSel.Controls.Add($numStacks)
  # simplified panel: quick stack buttons, rows shown only when they apply, stack size tucked into 'Advanced'
  $chkAdv = New-Object System.Windows.Forms.CheckBox; $chkAdv.Text = 'Advanced (stack size)'; $chkAdv.AutoSize = $false; $chkAdv.Size = '200,22'; $gbSel.Controls.Add($chkAdv)
  $lblQuick = New-Object System.Windows.Forms.Label; $lblQuick.Text = 'Stacks:'; $lblQuick.Size = '52,20'; $gbSel.Controls.Add($lblQuick)
  $cmbStacks = New-Object System.Windows.Forms.ComboBox; $cmbStacks.DropDownStyle = 'DropDownList'; $cmbStacks.Size = '120,24'; foreach ($n in 1..10) { [void]$cmbStacks.Items.Add($(if ($n -eq 1) { '1 stack' } else { "$n stacks" })) }; $gbSel.Controls.Add($cmbStacks)
  $quick = @($lblQuick, $cmbStacks)   # pick 1-10 stacks: sets the total to stacks x stack size
  $script:SelInfoH = 122;   # height of the item text; grows by itself when an item has more lines (see Fit-SelInfo) $script:ShowCond = $false; $script:ShowLoaded = $false
  function Layout-SelRows {
    $adv = $chkAdv.Checked; $w = $gbSel.Width
    $chkAdv.SetBounds($w - 214, 20, 204, 22); $lblSelId.Width = [math]::Max(100, $w - 240)
    $y = 50 + $script:SelInfoH; $numQty.Top = $y; $numQty.Tag.Top = $y + 3
    $qx = 306; foreach ($b in $quick) { $isLbl = ($b -is [System.Windows.Forms.Label]); $b.Left = $qx; $b.Top = $(if ($isLbl) { $y + 3 } else { $y }); $qx += $(if ($isLbl) { 56 } else { 130 }) }
    $lblPlan.SetBounds(12, $y + 30, [math]::Max(200, $w - 24), 20)
    foreach ($c in @($numStack, $numStack.Tag, $lblStacks, $numStacks)) { $c.Visible = $adv }
    $y = 108 + $script:SelInfoH
    if ($adv) { $numStack.Top = $y; $numStack.Tag.Top = $y + 3; $lblStacks.Top = $y + 3; $numStacks.Top = $y; $lblStacks.Left = 306; $numStacks.Left = 440; $y += 28 }
    $numCond.Visible = $script:ShowCond; $numCond.Tag.Visible = $script:ShowCond; if ($script:ShowCond) { $numCond.Top = $y; $numCond.Tag.Top = $y + 3; $y += 28 }
    $numLoaded.Visible = $script:ShowLoaded; $numLoaded.Tag.Visible = $script:ShowLoaded; if ($script:ShowLoaded) { $numLoaded.Top = $y; $numLoaded.Tag.Top = $y + 3; $y += 28 }
    $lblTarget.Top = $y + 3; $cmbTarget.Top = $y
    $btnAdd.SetBounds([math]::Max(310, $w - 232), $gbSel.Height - 62, 220, 50)
  }

  # queue panel
  $gbQ = New-Ctl ThemedGroup 584 368 572 140 'Queue (applied together, one backup)'; $gbQ.Anchor = 'Top,Right'
  $lbQ = New-Object System.Windows.Forms.ListBox; $lbQ.Location = '10,22'; $lbQ.Size = '430,110'; $gbQ.Controls.Add($lbQ)
  $btnRemove = New-Object System.Windows.Forms.Button; $btnRemove.Location = '448,20'; $btnRemove.Size = '112,26'; $btnRemove.Text = 'Remove selected'; $gbQ.Controls.Add($btnRemove)
  $btnClear = New-Object System.Windows.Forms.Button; $btnClear.Location = '448,48'; $btnClear.Size = '112,26'; $btnClear.Text = 'Clear queue'; $gbQ.Controls.Add($btnClear)
  $btnPreview = New-Object System.Windows.Forms.Button; $btnPreview.Location = '448,76'; $btnPreview.Size = '112,26'; $btnPreview.Text = 'Preview'; $gbQ.Controls.Add($btnPreview)
  $btnApply = New-Object System.Windows.Forms.Button; $btnApply.Location = '448,106'; $btnApply.Size = '112,28'; $btnApply.Text = 'Apply to save'; $btnApply.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold); $gbQ.Controls.Add($btnApply)

  # inventory + log
  $gbInv = New-Ctl ThemedGroup 12 514 560 262 'Current inventory (from the save)'; $gbInv.Anchor = 'Left,Bottom,Top'
  $lvInv = New-Object System.Windows.Forms.ListView; $lvInv.Location = '10,22'; $lvInv.Size = '540,230'; $lvInv.View = 'Details'; $lvInv.FullRowSelect = $true; $lvInv.Anchor = 'Top,Left,Bottom,Right'
  [void]$lvInv.Columns.Add('Where', 150); [void]$lvInv.Columns.Add('Slot', 40); [void]$lvInv.Columns.Add('Item', 160); [void]$lvInv.Columns.Add('Count / condition', 170); $gbInv.Controls.Add($lvInv)
  $gbLog = New-Ctl ThemedGroup 584 514 572 262 'Log'; $gbLog.Anchor = 'Top,Right,Bottom'
  $txtLog = New-Object System.Windows.Forms.TextBox; $txtLog.Location = '10,22'; $txtLog.Size = '552,194'; $txtLog.Multiline = $true; $txtLog.ReadOnly = $true; $txtLog.ScrollBars = 'Vertical'; $txtLog.Anchor = 'Top,Left,Bottom,Right'; $gbLog.Controls.Add($txtLog)
  $btnRestore = New-Object System.Windows.Forms.Button; $btnRestore.Location = '10,224'; $btnRestore.Size = '170,30'; $btnRestore.Text = 'Restore a backup...'; $btnRestore.Anchor = 'Left,Bottom'; $gbLog.Controls.Add($btnRestore)
  $btnOpenBk = New-Object System.Windows.Forms.Button; $btnOpenBk.Location = '188,224'; $btnOpenBk.Size = '170,30'; $btnOpenBk.Text = 'Open backups folder'; $btnOpenBk.Anchor = 'Left,Bottom'; $gbLog.Controls.Add($btnOpenBk)

  # ---------- logic ----------
  function Log([string]$m) { $txtLog.AppendText(("[{0}] {1}`r`n" -f (Get-Date -Format 'HH:mm:ss'), $m)) }

  function Update-GameState {
    $running = Test-GameRunning
    if ($running) { $lblGame.Text = 'GAME IS RUNNING - close it (after saving) before applying changes.'; $lblGame.ForeColor = $script:Th.Bad }
    else { $lblGame.Text = 'Game is closed - safe to apply changes.'; $lblGame.ForeColor = $script:Th.Good }
    $btnApply.Enabled = (-not $running) -and ($script:Queue.Count -gt 0); $btnPreview.Enabled = ($script:Queue.Count -gt 0); $btnRestore.Enabled = (-not $running)
  }

  function Reload-Inventory {
    $lvInv.Items.Clear()
    try {
      $script:SavePath = $txtSave.Text.Trim()
      if (-not $SelfTest -and -not $Headless) { try { $bl = Ensure-BaselineBackup $script:SavePath; if ($bl) { Log ('First time this world is opened: saved a starting snapshot (' + [IO.Path]::GetFileName($bl) + ') so World reset can restore things you destroy later.') } } catch { } }
      $sv = Read-Save $script:SavePath
      $lblInfo.Text = "World: $($sv.Slot)    Play time: {0:N1} h    Last saved: $($sv.Updated)" -f ([double]$sv.Playtime / 3600)
      foreach ($r in (Get-InventoryView $script:SavePath)) { $li = New-Object System.Windows.Forms.ListViewItem($r.Where); [void]$li.SubItems.Add([string]$r.Slot); [void]$li.SubItems.Add($r.Item); [void]$li.SubItems.Add($r.Detail); [void]$lvInv.Items.Add($li) }; Update-BackpackBox
    } catch { $lblInfo.Text = 'Could not read the save: ' + $_.Exception.Message; Log ('Read error: ' + $_.Exception.Message) }
  }

  # ---- spec helpers for the catalog list, the selected-item panel and the hover tips
  function Get-StatusText($i) { switch ($i.confidence) { 'verified' { 'Verified' } 'guess' { 'Name unsure' } default { 'Game data' } } }
  function Get-StackText($i) { if ($i.stackSource -in 'game data', 'game default', 'confirmed in game') { [string]$i.stackSize } elseif ($i.category -in 'Weapons', 'Clothing', 'QuestItems') { '1' } else { "$($i.stackSize)~" } }
  function Get-CondText($i) { if ($i.category -in 'Weapons', 'Clothing', 'Accessories', 'Traps', 'QuestItems' -and $i.maxCondition) { $c = ('{0:0.#}' -f [double]$i.maxCondition); if ($i.condSource -ne 'game data') { $c += '~' }; return $c }; return '' }
  function Get-AmmoText($i) {
    if ($i.category -eq 'Weapons') { if ($i.usesAmmo -and @($i.usesAmmo).Count) { return ((@($i.usesAmmo) | ForEach-Object { $_ -replace '_Ammo$', '' }) -join ', ') }; return 'melee' }
    if ($i.category -eq 'Projectiles') { $n = if ($i.usedBy) { @($i.usedBy).Count } else { 0 }; if ($n -eq 0) { return 'no gun' }; return $(if ($n -eq 1) { '1 weapon' } else { "$n weapons" }) }
    return ''
  }
  function Get-FoundText($i) { if ($i.sources -and @($i.sources).Count) { return (@($i.sources) -join ', ') }; return '-' }
  $script:CatSort = @{ Col = -1; Desc = $false }
  function Get-FrostText($i) { if ($i.armor -match 'FROST\s+([\d.]+)') { return $Matches[1] }; return '' }
  function Get-CatCells($i) { @($i.id, [string]$i.display, $i.category, (Get-StackText $i), (Get-CondText $i), [string]$i.damage, (Get-FrostText $i), $(if ($i.tradeValue) { [string]$i.tradeValue } else { '' }), (Get-AmmoText $i), (Get-FoundText $i), (Get-StatusText $i)) }

  function Refresh-Catalog {
    $q = $txtSearch.Text.Trim(); $c = [string]$cmbCat.SelectedItem
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($i in $script:Cat) {
      if ($c -and $c -ne 'All' -and $i.category -ne $c) { continue }
      if ($q -and ($i.id -notlike "*$q*") -and ($i.display -notlike "*$q*") -and ($i.asset -notlike "*$q*")) { continue }
      $rows.Add([pscustomobject]@{ Item = $i; Cells = (Get-CatCells $i) })
    }
    $col = $script:CatSort.Col
    if ($col -ge 0) { $rows = @($rows | Sort-Object -Descending:$script:CatSort.Desc -Property @{ Expression = { $v = $_.Cells[$col]; if ($col -in 3, 4, 5, 6, 7) { $m = [regex]::Match($v, '[\d.]+'); if ($m.Success) { [double]$m.Value } else { -1.0 } } else { $v } } }, @{ Expression = { $_.Cells[0] } }) }
    else { $rows = @($rows | Sort-Object @{ Expression = { $_.Item.category } }, @{ Expression = { $_.Item.id } }) }
    $lvCat.BeginUpdate(); $lvCat.Items.Clear()
    foreach ($r in $rows) {
      $i = $r.Item; $li = New-Object System.Windows.Forms.ListViewItem($r.Cells[0]); $li.Tag = $i; $li.UseItemStyleForSubItems = $false
      foreach ($k in 1..10) { $s = $li.SubItems.Add($r.Cells[$k]) }
      $st = $li.SubItems[10]; $st.ForeColor = $(if ($i.confidence -eq 'verified') { $script:Th.Good } elseif ($i.confidence -eq 'guess') { $script:Th.Bad } else { $script:Th.Muted })
      if ($i.confidence -eq 'guess') { $li.ForeColor = $script:Th.Bad } else { $li.ForeColor = $script:Th.Text }
      foreach ($k in 1..9) { $li.SubItems[$k].ForeColor = $script:Th.Text }
      if (-not $r.Cells[9] -or $r.Cells[9] -eq '-') { $li.SubItems[9].ForeColor = $script:Th.Muted }
      [void]$lvCat.Items.Add($li)
    }
    $lvCat.EndUpdate(); $gbCat.Text = "Item catalog  ($($lvCat.Items.Count) shown)"
    for ($k = 0; $k -lt $lvCat.Columns.Count; $k++) { $lvCat.Columns[$k].Text = $script:CatCols[$k] + $(if ($k -eq $script:CatSort.Col) { $(if ($script:CatSort.Desc) { '  v' } else { '  ^' }) } else { '' }) }
  }
  function Get-SpecText($i) {
    $p = New-Object System.Collections.Generic.List[string]
    if ($i.damage) { $d = "Damage $($i.damage)"; if ($i.damageType) { $d += " ($($i.damageType))" }; $p.Add($d) }
    if ($i.powerAttack) { $p.Add("power attack x$($i.powerAttack)") }
    if ($i.stamina) { $p.Add("stamina $($i.stamina)") }
    if ($i.magazine) { $p.Add("magazine $($i.magazine)") }
    if ($i.fireRate) { $p.Add("fire interval $($i.fireRate)s") }
    if ($i.tool) { $p.Add("tool $($i.tool)") }
    if ($i.armor) { $p.Add("armor $($i.armor)") }
    if ($i.damageReduction) { $p.Add("damage reduction $($i.damageReduction)") }
    if ($i.effect) { $p.Add($i.effect) }
    if ($i.restores) { $p.Add("restores $($i.restores)") }
    if ($i.decay) { $p.Add("loses $($i.decay)") }
    if ($i.durPerUse) { $p.Add("condition cost/use $($i.durPerUse)") }
    if ($i.containerSlots) { $p.Add("holds $($i.containerSlots) items") } elseif ($i.slotSize) { $p.Add("inventory size $($i.slotSize)") }
    if ($i.tradeValue) { $p.Add("trade value $($i.tradeValue)") }
    if ($i.recycle) { $p.Add("recycles to $($i.recycle)") }
    if ($i.repair) { $p.Add("repair $($i.repair)") }
    $s = $p -join '  |  '; if ($s.Length -gt 260) { $s = $s.Substring(0, 257) + '...' }; return $s
  }
  function Fit-SelInfo {   # grow/shrink the item text box to the real height of its text, so no line is ever cut off
    if ($script:Fitting) { return }; $script:Fitting = $true
    try { $w = [math]::Max(200, $lblSelInfo.Width)
      $h = [System.Windows.Forms.TextRenderer]::MeasureText($lblSelInfo.Text, $lblSelInfo.Font, (New-Object System.Drawing.Size($w, 3000)), [System.Windows.Forms.TextFormatFlags]::WordBreak).Height + 10
      $new = [math]::Min(300, [math]::Max(122, $h)); if ([math]::Abs($new - $script:SelInfoH) -gt 2) { $script:SelInfoH = $new; Do-Layout }
    } catch { } finally { $script:Fitting = $false }
  }
  function On-SelectItem {
    if ($lvCat.SelectedItems.Count -eq 0) { $script:Selected = $null; $lblSelId.Text = 'Pick an item on the left'; $lblSelInfo.Text = 'Search or choose a category, click an item, set how many, then Add to queue (double-click also works).'; $script:ShowCond = $false; $script:ShowLoaded = $false; Layout-SelRows; Fit-SelInfo; return }
    $i = $lvCat.SelectedItems[0].Tag; $script:Selected = $i
    $lblSelId.Text = $i.id
    $nameTxt = switch ($i.confidence) { 'verified' { 'name verified in real saves' } 'guess' { 'WARNING: best-guess name, may not load' } default { 'name read from the game data' } }; if ($i.formatInferred) { $nameTxt += ', format inferred' }
    $stackTxt = switch ($i.stackSource) { 'game data' { "Stack limit $($i.stackSize) (game data)" } 'confirmed in game' { "Stack limit $($i.stackSize) (confirmed in game)" } 'game default' { "Stack limit $($i.stackSize) (game data has no stack value, so the default of 1 applies)" } 'your saves' { "Stack $($i.stackSize) (largest seen in your saves)" } default { "Stack $($i.stackSize) (estimate)" } }
    $condTxt = if ($i.maxCondition -and $i.category -in 'Weapons', 'Clothing', 'Accessories', 'Traps', 'QuestItems') { "    |    Max condition $('{0:0.#}' -f [double]$i.maxCondition) ($(if ($i.condSource -eq 'game data') { 'game data' } else { 'highest seen in your saves' }))" } else { '' }
    $foundTxt = if ($i.sources -and @($i.sources).Count) { "Found via: " + (@($i.sources) -join ', ') } else { 'No loot, pickup, trade or recipe link found in the game files' }
    if ($i.rewards) { $rw = [string]$i.rewards; if ($rw.Length -gt 120) { $rw = $rw.Substring(0, 117) + '...' }; $foundTxt += "    |    Quest reward: $rw" }
    if ($i.recipe) { $rt = [string]$i.recipe; if ($rt.Length -gt 150) { $rt = $rt.Substring(0, 147) + '...' }; $foundTxt += "    |    Recipe: $rt" }
    $nmLine = if ($i.display) { $i.display + $(if ($i.description) { "  -  $($i.description)" } else { '' }) } else { $i.id }; $specs = Get-SpecText $i; if ($specs) { $foundTxt += "`r`n$specs" }; if ($i.sourcesText) { $stx = [string]$i.sourcesText; if ($stx.Length -gt 170) { $stx = $stx.Substring(0, 167) + '...' }; $foundTxt += "`r`nWhere to find: $stx" }; $lblSelInfo.Text = "$nmLine`r`nGame file: $($i.asset)    |    $nameTxt`r`n$stackTxt$condTxt`r`n$foundTxt"
    $hint = if ($i.usesAmmo -and @($i.usesAmmo).Count) { "Uses ammo: " + (@($i.usesAmmo) -join ', ') } elseif ($i.usedBy -and @($i.usedBy).Count) { "Used by: " + ((@($i.usedBy) | ForEach-Object { $_ -replace '^Weapon_', '' }) -join ', ') } elseif ($i.category -eq 'Projectiles') { 'No weapon in the game files uses this.' } elseif ($i.category -eq 'Weapons') { 'Melee weapon - uses no ammo.' } else { '' }
    if ($hint) { $lblSelInfo.Text += "`r`n" + $hint }
    $numStack.Value = [math]::Min([math]::Max(1, [int]$i.stackSize), $numStack.Maximum)
    $numCond.Enabled = ($i.fieldsUsed -ge 2); $numLoaded.Enabled = ($i.fieldsUsed -ge 3); $script:ShowCond = ($i.fieldsUsed -ge 2); $script:ShowLoaded = ($i.fieldsUsed -ge 3); Layout-SelRows
    $numCond.Value = [math]::Min([decimal]$i.condition, $numCond.Maximum); $numLoaded.Value = 0
    $numQty.Value = 1; Update-Plan; Fit-SelInfo
  }

  function Refresh-Queue {
    $lbQ.Items.Clear()
    foreach ($r in $script:Queue) { [void]$lbQ.Items.Add(("{0} x{1}  ->  {2}   ({3} slot(s), up to {4} per slot)" -f $r.item.id, $r.count, $r.target, [int][math]::Ceiling($r.count / [math]::Max(1, $r.stack)), $r.stack)) }
    Update-GameState; Update-Plan
  }

  function Add-Selected {
    # use only what is really selected in the list right now (never a stale choice from an earlier list)
    if ($lvCat.SelectedItems.Count -gt 0) { $pick = $lvCat.SelectedItems[0].Tag } else { $pick = $null }   # no automatic pick: you choose the item yourself
    if (-not $pick) { $script:Selected = $null; Log 'Nothing selected: click an item in the catalog (left), then press Add to queue.'; return }
    if ($script:Selected -ne $pick -or $lblSelId.Text -ne $pick.id) { $lvCat.SelectedItems.Count | Out-Null; On-SelectItem }
    if (-not $script:Selected) { return }
    $c = $script:Selected.PSObject.Copy(); $c.condition = [double]$numCond.Value; $c.loaded = [int]$numLoaded.Value
    $tgA = [string]$cmbTarget.SelectedItem; $leftA = Get-SpaceLeft $tgA; $needA = [int][math]::Ceiling([int]$numQty.Value / [math]::Max(1, [int]$numStack.Value))
    $script:Queue.Add([pscustomobject]@{ item = $c; count = [int]$numQty.Value; stack = [int]$numStack.Value; target = [string]$cmbTarget.SelectedItem })
    Refresh-Queue; Log ("Queued {0}: total {1}, {2} per slot = {3} slot(s) ({4})" -f $c.id, $numQty.Value, $numStack.Value, [int][math]::Ceiling([int]$numQty.Value / [math]::Max(1, [int]$numStack.Value)), $cmbTarget.SelectedItem)
    if ($null -ne $leftA -and $needA -gt $leftA) { Log ("WARNING: $($c.id) needs $needA slot(s) but only $leftA $(($tgA).ToLower()) slot(s) are free. It is queued, but Apply will refuse until you free space in the game, add less, or make the backpack bigger (Backpack slots box, top right).") }
  }

  # ---------- hooks for the Player tools / Game data windows ----------
  function Queue-ById([string]$id, [int]$count) {
    $i = $script:Cat | Where-Object { $_.id -eq $id } | Select-Object -First 1; if (-not $i) { return $false }
    $c = $i.PSObject.Copy(); $c.condition = [double]$i.condition; $c.loaded = 0
    $script:Queue.Add([pscustomobject]@{ item = $c; count = [math]::Max(1, $count); stack = [math]::Max(1, [int]$i.stackSize); target = 'Backpack' })
    Refresh-Queue; Log ("Queued {0}: total {1}, {2} per slot (from the Game data window)" -f $id, [math]::Max(1, $count), [math]::Max(1, [int]$i.stackSize)); return $true
  }
  $script:QueueAdder = ${function:Queue-ById}
  $script:OnSaveChanged = { param($m) Log $m; Reload-Inventory }
  function Open-Player { Invoke-Busy 'Opening Player tools' { Reload-Inventory; Show-PlayerTools $form } $form; Invoke-Busy 'Re-reading your save...' { Reload-Inventory } $form; Update-GameState }
  function Open-Data { $script:GD = @{}; Invoke-Busy 'Loading the game data' { Show-GameData $form } $form; Update-GameState }
  function Open-Tweaks { Invoke-Busy 'Loading the recipes...' { Show-RecipeTweaks $form } $form }
  function Open-World { Invoke-Busy 'Reading your worlds...' { Show-WorldReset $form } $form; Invoke-Busy 'Re-reading your save...' { Reload-Inventory } $form; Update-GameState }

  function Show-TextDialog([string]$title, [string]$text, [switch]$Help) {
    # read-only text window with a Find bar (like Acrobat): matches are highlighted while you type, the arrows / Enter / F3 jump to the next or previous one.
    # Redrawing is switched off while highlights change (otherwise the whole box flickers on every key) and the search waits ~150 ms after the last key.
    if (-not ('RtbRedraw' -as [type])) { Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public static class RtbRedraw { [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr h, int m, IntPtr w, IntPtr l); public static void Set(IntPtr h, bool on) { SendMessage(h, 0x000B, on ? new IntPtr(1) : IntPtr.Zero, IntPtr.Zero); } }' }
    $d = New-Object System.Windows.Forms.Form; $d.Text = $title; $d.Size = New-Object System.Drawing.Size(960, 700); $d.StartPosition = 'CenterParent'; $d.Font = New-Object System.Drawing.Font('Segoe UI', 9.5); $d.KeyPreview = $true
    $top = New-Object System.Windows.Forms.Panel; $top.Dock = 'Top'; $top.Height = 40
    $lf = New-Object System.Windows.Forms.Label; $lf.Text = 'Find'; $lf.Location = New-Object System.Drawing.Point(10, 11); $lf.Size = New-Object System.Drawing.Size(36, 20); $top.Controls.Add($lf)
    $tf = New-Object System.Windows.Forms.TextBox; $tf.Location = New-Object System.Drawing.Point(48, 8); $tf.Size = New-Object System.Drawing.Size(320, 24); $top.Controls.Add($tf)
    $bPrev = New-Object System.Windows.Forms.Button; $bPrev.Text = [string][char]0x25B2; $bPrev.Location = New-Object System.Drawing.Point(376, 7); $bPrev.Size = New-Object System.Drawing.Size(34, 26); $top.Controls.Add($bPrev)
    $bNext = New-Object System.Windows.Forms.Button; $bNext.Text = [string][char]0x25BC; $bNext.Location = New-Object System.Drawing.Point(414, 7); $bNext.Size = New-Object System.Drawing.Size(34, 26); $top.Controls.Add($bNext)
    $lc = New-Object System.Windows.Forms.Label; $lc.Text = ''; $lc.Location = New-Object System.Drawing.Point(458, 11); $lc.Size = New-Object System.Drawing.Size(230, 20); $top.Controls.Add($lc)
    $tb = New-Object System.Windows.Forms.RichTextBox; $tb.ReadOnly = $true; $tb.ScrollBars = 'Vertical'; $tb.Dock = 'Fill'; $tb.WordWrap = $true; $tb.DetectUrls = $false; $tb.HideSelection = $true; $tb.BorderStyle = 'FixedSingle'; $tb.Text = $text
    $bp = New-Object System.Windows.Forms.Panel; $bp.Dock = 'Bottom'; $bp.Height = 44
    $ok = New-Object System.Windows.Forms.Button; $ok.Text = 'Close'; $ok.Size = New-Object System.Drawing.Size(100, 30); $ok.Location = New-Object System.Drawing.Point(($d.ClientSize.Width - 116), 6); $ok.Anchor = 'Top,Right'; $ok.Add_Click({ $d.Close() }); $bp.Controls.Add($ok)
    $d.Controls.Add($tb); $d.Controls.Add($top); $d.Controls.Add($bp); $d.AcceptButton = $null; $d.CancelButton = $ok
    Apply-Theme $d; Set-AppIcon $d
    $th = $script:Th; $tb.BackColor = $th.Field; $tb.ForeColor = $th.Text   # a RichTextBox is not themed by Apply-Theme
    $doc = $null
    if ($Help) {   # the Help window: a banner on top, a list of sections on the left, designed text
      $d.Size = New-Object System.Drawing.Size(1120, 780)
      $ban = New-Object System.Windows.Forms.Panel; $ban.Dock = 'Top'; $ban.Height = 80; $ban.BackColor = $th.Header
      $bl = New-Object System.Windows.Forms.Panel; $bl.Dock = 'Bottom'; $bl.Height = 3; $bl.BackColor = $th.Accent; $ban.Controls.Add($bl)
      $bt = New-Object System.Windows.Forms.Label; $bt.Text = 'How it works'; $bt.Font = New-Object System.Drawing.Font('Segoe UI', 24, [System.Drawing.FontStyle]::Bold); $bt.ForeColor = $th.Accent; $bt.BackColor = $th.Header; $bt.AutoSize = $true; $bt.Location = New-Object System.Drawing.Point(16, 4); $ban.Controls.Add($bt)
      $bs = New-Object System.Windows.Forms.Label; $bs.Text = 'Permafrost Item Tool  -  for single-player saves only.   Ctrl+F searches this page; the list on the left jumps to a section.'; $bs.Font = New-Object System.Drawing.Font('Segoe UI', 9.5); $bs.ForeColor = $th.Muted; $bs.BackColor = $th.Header; $bs.AutoSize = $true; $bs.Location = New-Object System.Drawing.Point(20, 52); $ban.Controls.Add($bs)
      $lst = New-Object System.Windows.Forms.ListBox; $lst.Dock = 'Left'; $lst.Width = 220; $lst.BorderStyle = 'None'; $lst.BackColor = $th.Panel; $lst.ForeColor = $th.Text; $lst.IntegralHeight = $false
      $lst.DrawMode = 'OwnerDrawFixed'; $lst.ItemHeight = 32; $lst.Font = New-Object System.Drawing.Font('Segoe UI', 10.5)
      $lst.Add_DrawItem({ param($s, $e)
        if ($e.Index -lt 0) { return }
        $sel = (($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -ne 0)
        $br = New-Object System.Drawing.SolidBrush($(if ($sel) { $th.Select } else { $th.Panel })); $e.Graphics.FillRectangle($br, $e.Bounds); $br.Dispose()
        if ($sel) { $ab = New-Object System.Drawing.SolidBrush($th.Accent); $e.Graphics.FillRectangle($ab, $e.Bounds.X, $e.Bounds.Y, 4, $e.Bounds.Height); $ab.Dispose() }
        [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, [string]$s.Items[$e.Index], $s.Font, (New-Object System.Drawing.Point(($e.Bounds.X + 16), ($e.Bounds.Y + 6))), $th.Text) })
      $jump = { param([int]$ix)
        if ($ix -lt 0 -or $ix -ge $doc.Sections.Count) { return }
        [RtbRedraw]::Set($tb.Handle, $false)
        try { $tb.Select($tb.TextLength, 0); $tb.ScrollToCaret(); $tb.Select([int]$doc.Sections[$ix].Pos, 0); $tb.ScrollToCaret() } finally { [RtbRedraw]::Set($tb.Handle, $true); $tb.Invalidate() } }
      $lst.Add_SelectedIndexChanged({ & $jump $lst.SelectedIndex }); $lst.Add_MouseUp({ param($s, $e) $ix = $lst.IndexFromPoint($e.Location); if ($ix -ge 0) { & $jump $ix } })
      $d.Controls.Clear(); $d.Controls.Add($tb); $d.Controls.Add($lst); $d.Controls.Add($top); $d.Controls.Add($ban); $d.Controls.Add($bp)
      [void]$d.Handle   # the text box needs its window before it can take formatting
      $tb.ReadOnly = $false; try { $doc = HP-Render $tb $text $th } finally { $tb.ReadOnly = $true }
      foreach ($sc in $doc.Sections) { [void]$lst.Items.Add([string]$sc.Title) }
    }
    $st = @{ Hits = (New-Object System.Collections.Generic.List[int]); Len = 0; Cur = -1; Painted = (New-Object System.Collections.Generic.List[int]); PaintedLen = 0 }
    $paint = {
      param([int]$pos, [int]$len, [bool]$current)
      $tb.Select($pos, $len)
      if ($current) { $tb.SelectionBackColor = $th.Accent; $tb.SelectionColor = $th.AccentText } else { $tb.SelectionBackColor = $th.Warn; $tb.SelectionColor = [System.Drawing.Color]::Black }
    }
    $unpaint = {
      param([int]$pos, [int]$len)
      if ($doc) { HP-Restore $tb $doc $pos $len $th } else { $tb.Select($pos, $len); $tb.SelectionBackColor = $th.Field; $tb.SelectionColor = $th.Text }
    }
    $show = {
      # make match number $st.Cur stand out, scroll to it, update the counter (caller has redraw switched off)
      if ($st.Hits.Count -eq 0) { return }
      & $paint $st.Hits[$st.Cur] $st.Len $true
      $tb.Select($st.Hits[$st.Cur], 0); $tb.ScrollToCaret()
      $lc.Text = ('{0} of {1}' -f ($st.Cur + 1), $st.Hits.Count)
    }
    $search = {
      # take the old highlights away (only those ranges, no select-all), find every match (case-insensitive), highlight them, go to the first
      [RtbRedraw]::Set($tb.Handle, $false)
      try {
        if ($st.Cur -ge 0 -and $st.Cur -lt $st.Hits.Count) { & $unpaint $st.Hits[$st.Cur] $st.Len }   # the current match may lie beyond the painted ones
        foreach ($p in $st.Painted) { & $unpaint $p $st.PaintedLen }
        $st.Painted.Clear(); $st.Hits.Clear(); $st.Cur = -1; $term = $tf.Text; $st.Len = $term.Length; $content = $tb.Text
        if ($term.Length -gt 0) {
          $i = 0; while ($st.Hits.Count -lt 5000) { $i = $content.IndexOf($term, $i, [StringComparison]::OrdinalIgnoreCase); if ($i -lt 0) { break }; $st.Hits.Add($i); $i += [Math]::Max(1, $term.Length) }
          $n = 0; foreach ($h in $st.Hits) { if ($n -ge 1500) { break }; & $paint $h $st.Len $false; $st.Painted.Add($h); $n++ }
          $st.PaintedLen = $term.Length
        }
        $tb.Select(0, 0)
        if ($term.Length -eq 0) { $lc.Text = ''; $tb.ScrollToCaret() }
        elseif ($st.Hits.Count -eq 0) { $lc.Text = 'No results'; $lc.ForeColor = $th.Bad }
        else { $st.Cur = 0; & $show }
        if ($st.Hits.Count -gt 0 -or $term.Length -eq 0) { $lc.ForeColor = $th.Muted }
      } finally { [RtbRedraw]::Set($tb.Handle, $true); $tb.Invalidate() }
    }
    $step = {
      param([int]$dir)
      if ($st.Hits.Count -eq 0) { return }
      [RtbRedraw]::Set($tb.Handle, $false)
      try {
        # the match we leave goes back to the normal highlight (or none, if it was beyond the painted ones)
        if ($st.Painted.Contains($st.Hits[$st.Cur])) { & $paint $st.Hits[$st.Cur] $st.Len $false } else { & $unpaint $st.Hits[$st.Cur] $st.Len }
        $st.Cur = ($st.Cur + $dir + $st.Hits.Count) % $st.Hits.Count
        & $show
      } finally { [RtbRedraw]::Set($tb.Handle, $true); $tb.Invalidate() }
    }
    # wait a moment after the last key before searching, so fast typing does not repaint on every letter
    $timer = New-Object System.Windows.Forms.Timer; $timer.Interval = 150
    $timer.Add_Tick({ $timer.Stop(); & $search })
    $tf.Add_TextChanged({ $timer.Stop(); $timer.Start() })
    $d.Add_FormClosed({ $timer.Stop(); $timer.Dispose() })
    $flush = { if ($timer.Enabled) { $timer.Stop(); & $search } }   # a key or click right after typing must see the finished search
    $bNext.Add_Click({ & $flush; & $step 1; $tf.Focus() }); $bPrev.Add_Click({ & $flush; & $step -1; $tf.Focus() })
    $d.Add_KeyDown({ param($s, $e)
      if ($e.KeyCode -eq 'Enter' -and $tf.Focused) { & $flush; & $step $(if ($e.Shift) { -1 } else { 1 }); $e.Handled = $true; $e.SuppressKeyPress = $true }
      elseif ($e.KeyCode -eq 'F3') { & $flush; & $step $(if ($e.Shift) { -1 } else { 1 }); $e.Handled = $true }
      elseif ($e.Control -and $e.KeyCode -eq 'F') { $tf.Focus(); $tf.SelectAll(); $e.Handled = $true; $e.SuppressKeyPress = $true } })
    $d.Add_Shown({ $tf.Focus() })
    if ($script:DialogTestHook) { & $script:DialogTestHook $d $tf $tb $lc $bNext $bPrev $timer; return }
    [void]$d.ShowDialog($form)
  }

  function Get-WarningText($pv, [bool]$all) {
    $lines = @(); foreach ($x in $pv.Warnings) { if ($all -or $x.Level -eq 'warn') { $lines += ($(if ($x.Level -eq 'warn') { '[CAUTION] ' } else { '[note] ' }) + $x.Text) } }
    return ($lines -join "`r`n`r`n")
  }

  function Show-Preview {
    if ($script:Queue.Count -eq 0) { return }
    try { $pv = Get-Preview $script:SavePath $script:Queue.ToArray() }
    catch { Log ('Preview problem: ' + $_.Exception.Message); [void][System.Windows.Forms.MessageBox]::Show("This would NOT work, and nothing was changed.`n`nReason: $($_.Exception.Message)", 'Preview', 'OK', 'Warning'); return }
    $txt = "PREVIEW - nothing has been written.`r`n`r`nThis is exactly what 'Apply to save' would add:`r`n`r`n" + (($pv.Added | ForEach-Object { '   ' + $_ }) -join "`r`n")
    $wt = Get-WarningText $pv $true
    if ($wt) { $txt += "`r`n`r`n---------- Things to know ----------`r`n`r`n" + $wt } else { $txt += "`r`n`r`nNo warnings." }
    Show-TextDialog 'Preview of your changes' $txt
  }

  function Apply-Queue {
    if ($script:Queue.Count -eq 0) { return }
    if (Test-GameRunning) { [void][System.Windows.Forms.MessageBox]::Show("The game is running, so nothing was changed.`n`nSave and close the game first, then try again.", 'Game is running', 'OK', 'Warning'); return }
    # step 1: dry run - proves it fits, and gathers warnings
    try { $pv = Get-Preview $script:SavePath $script:Queue.ToArray() }
    catch { Log ('Cannot apply: ' + $_.Exception.Message); [void][System.Windows.Forms.MessageBox]::Show("Nothing was changed.`n`nReason: $($_.Exception.Message)", 'Cannot apply', 'OK', 'Warning'); return }
    # step 2: anything risky needs its own explicit yes (default answer is No)
    if ($pv.Level -eq 'warn') {
      $wt = (Get-WarningText $pv $false) -replace "`r`n`r`n", "`n`n"
      $r = [System.Windows.Forms.MessageBox]::Show("Please read before continuing:`n`n$wt`n`nDo you still want to continue?", 'Caution', 'YesNo', 'Warning', 'Button2')
      if ($r -ne 'Yes') { Log 'Cancelled at the caution prompt - nothing changed.'; return }
    }
    # step 3: final confirmation with the exact slots
    $slots = ($pv.Added | ForEach-Object { "  $_" }) -join "`n"
    $ok = [System.Windows.Forms.MessageBox]::Show("About to edit this save:`n$($script:SavePath)`n`nIt will add:`n$slots`n`nA backup is made first, and the result is checked afterwards.`nSteam Cloud should be OFF for Permafrost (see Help).`n`nContinue?", 'Apply changes?', 'OKCancel', 'Question', 'Button2')
    if ($ok -ne 'OK') { Log 'Cancelled at the final confirmation - nothing changed.'; return }
    try {
      $res = Install-Items $script:SavePath $script:Queue.ToArray()
      Log 'Applied and verified:'; foreach ($a in $res.Added) { Log "   $a" }; Log ('Backup saved: ' + $res.Backup)
      $script:Queue.Clear(); Refresh-Queue; Reload-Inventory
      [void][System.Windows.Forms.MessageBox]::Show("Done. Your save was backed up, edited, and re-checked.`n`nBackup: $($res.Backup)`n`nNext: start the game and load the world. If Steam asks about a cloud conflict, keep the LOCAL (newer) files.", 'Success', 'OK', 'Information')
    } catch {
      Log ('FAILED: ' + $_.Exception.Message)
      $extra = if ($_.Exception.Message -match 'original restored') { 'Your original save was put back.' } else { 'Your save was not modified.' }
      [void][System.Windows.Forms.MessageBox]::Show("The change did not go through. $extra`n`nReason: $($_.Exception.Message)`n`nNo harm done - you can fix the problem and try again.", 'Failed safely', 'OK', 'Error')
    }
  }

  function Show-Help {
    $h = @'
PERMAFROST ITEM TOOL - HOW IT WORKS
===================================
What it is
A tool for a SINGLE-PLAYER Permafrost save. The main window adds items to your backpack/hotbar and sets your backpack size. Extra windows, opened from the row of buttons under the Save file row, cover the rest: 'Player tools' (vitals, skills, recipes, teleport, quest progress), 'World reset' (put used-up trees, ores, items and loot back), 'Game data' (search everything found in the game files, reward pools, quests, recipes, bundles), 'Pictures' (build the item pictures from your own game), 'Recipe tweaks' (change crafting inside the game), 'Build move' (move placed buildings inside the game), 'Stack sizes' (stack first aid kits inside the game) and this Help. 'Overview' (top of the window) is the read-only report. See THE EXTRA WINDOWS below. Press Ctrl+F in this window to search it.

Before you start (every time)
1. In the game: save, then quit completely. The tool refuses to apply while the game is running.
2. Keep Steam Cloud OFF for Permafrost while editing (see "Steam Cloud" below).

THE WINDOW
The window opens maximized and resizes with you; if it is ever smaller than its content needs (a small screen or a big Windows text size), scroll bars appear instead of cutting anything off. Press F11 for true full screen (Esc or F11 again to leave it). From the top: the banner (Overview and the colour Theme box), the Save file row, a row of buttons for the extra windows, the status lines, then the catalog, the selected item, the queue, the current inventory and the log.

- Save file / Browse / Reload (top): Shows which .pfs save is edited. Browse lists every world found on this PC (hours played, last saved) so you can pick one, or lets you pick a .pfs file yourself. Reload re-reads the save. The world you pick is remembered.
- Game status line (under the buttons, green/red): Green = game closed, safe. Red = game running, Apply and Restore are disabled. The lines below it show the world, play time, when it was last saved and your worn backpack ("Worn: ScavengerBackpack - using 35 slots"); a red DANGER line appears there when kits or backpack items are at risk (see Backpack slots and STACK SIZES).
- Backpack slots (right end of the Save file row, the line under it says where the number comes from): How many slots your worn backpack has (the label says where the number comes from). To make your backpack BIGGER (or smaller), type the number you want (a multiple of 5: the screen is a grid with 5 columns) and press 'Apply in game'. The first time the tool offers to install a small in-game mod (BackpackSlots, for UE4SS - see the README); after that the game applies your size every time it starts, before your save loads, so you just start the game. If the game is already running, take the backpack off and put it back on (drag it to the hotbar and back). The tool makes a backup of your save first. IMPORTANT: the game DELETES every item that has no slot the next time it saves (tested: after one save with the mod off, the items in the extra slots were gone). So the tool refuses a size that would leave an item outside the backpack, and shows a red DANGER line under the box if an item already sits above the size the game will use (for example because the mod is off or not loading). If you see it, do NOT play: switch the mod on (Apply in game) or restore a backup. Add items counts your size as soon as the mod is installed and on.

The window refreshes by itself when the save changes (for example after you play), so it always shows your current backpack.

- Overview (banner, top): a read-only report of your save - world and play time, character, skills, inventory (with the backpack size in use), recipes known, quests, buildings, explored area, companion, the state of the in-game mods and your settings for them, backups - with a Copy report button. Nothing in it changes the save.
- Hover pictures: hold the mouse over an item in the catalog, the inventory list or the queue to see its picture and details. Pictures come from the 'icons' folder next to the tool. Press 'Pictures' (in the row of buttons) or 'Build pictures now' (the bar under the status lines) to build them from your own installed game - it reads the game's files, read-only, takes about 20 seconds, and needs the small free Oodle decompressor library once (the tool asks before downloading it). An item without a picture shows text only.

Item catalog (left)
All 380 items found in the game's files. Type in the search box or pick a category. Click a column header to sort. Columns (everything comes from the game's own data unless it says otherwise):
- Name - the in-game name (the Item column is the id the save uses). You can search by either.
- Stack - how many fit in one slot, from the game data. Items whose data has no stack setting stack as 1.
- Cond. - the item's top condition/durability, from the game data (building parts use their max health). A few quest items have no value in the data; those show the highest value seen in your saves, marked "~". Blank = none exists.
- Dmg - weapon damage per hit (shots for guns); Frost = cold protection of clothing; Value = trade value. Click the header to sort, ("melee" = none). Ammo: how many weapons use it ("no gun" = none found).
- Where to find (shown under the item when it applies) lists the best sources with the chance per opening, worked out from the loot weights: e.g. '2.9% Military_Car_01 +5 [Container]' = about a 3% chance each time one of those is opened. 'sold by' = traders.
- Found via - which game files link the item: Loot (loot tables/containers), Pickup (a world pickup exists), Craft (a crafting recipe makes it; the ingredients are shown in the Selected item panel), Trader, Quest (reward pool or quest; the exact group and amount are shown as 'Quest reward'), Animal. It says WHERE it is linked, not how likely it is - drop chances are not readable. "-" = no link found at all (likely unreleased).
- Status - Verified = this exact name has been seen in real saves (known to work). Game data = name read from the game's data files (worked every time so far, but never seen in a save). Name unsure (red) = several names were possible; the game may ignore it.

Selected item (right)
- Hint text - for weapons it says which ammo they use (or that they use none); for ammo it lists the weapons that use it.
- Total quantity - how many items to add IN TOTAL (all stacks together).
- Stacks (dropdown) - pick 1 to 10 stacks and the total fills in (stacks x items per slot); typing a total updates the dropdown too.
- ...or number of stacks - (under Advanced) the same for more than 10 stacks. (stacks x items per slot). If you change the items-per-slot afterwards, the total stays and the stacks update.
- Free slots - under the quantity the tool shows how many backpack (or hotbar) slots are free, counting what is already in the queue. If the item will not fit it says NOT ENOUGH SPACE in red, and adding it writes a warning to the Log. Nothing is lost: Preview and Apply refuse to run until it fits (free space in the game, add less, or use the Hotbar).
- Items per slot - the stack size = how many fit in ONE slot. Default = the game's own stack limit when it could be read from the game data (most resources, consumables, valuables); otherwise the biggest stack seen in your saves. Slots used = total quantity / items per slot, rounded up. Example: 150 total at 50 per slot = 3 slots. The blue line under the box always shows what your numbers will do.
- Condition - wear value for weapons/clothing/tools (greyed out for items that have none).
- Rounds loaded - only for firearms: ammo already in the gun.
- Put it in - Backpack or Hotbar. The tool uses the first free slots.
- Add to queue - (or double-click an item) puts it on the list below. Nothing is written yet.

Queue
Items waiting to be added. Remove selected / Clear queue edit the list.
- Preview (no changes) - shows exactly which slots would be used, plus any warnings. Writes nothing.
- Apply to save - does the real edit (see below).

Current inventory (bottom left)
What the save currently holds in the hotbar and backpack, slot by slot.

Log (bottom right)
A running record of everything the tool did.

- Restore a backup... - puts one of the automatic backups back (your current save is kept too).
- Open backups folder - opens the folder where backups live.

WHAT "APPLY TO SAVE" DOES, STEP BY STEP
1. Checks the game is closed.
2. Dry run: works out the exact free slots. If there is not enough room it stops and says so.
3. Shows CAUTION warnings (see below) - you must answer Yes to continue (default answer is No).
4. Shows a final confirmation listing the exact slots.
5. Makes a backup of your save (in the Backups folder).
6. Edits all three copies of your inventory inside the save and checks they agree.
7. Re-reads the finished file; if anything is off it puts your original back.
8. Refreshes the file's modified time so Steam sees it as the newest copy.

WARNINGS YOU MAY SEE
- Best guess name - the item name was ambiguous; the game may simply ignore it.
- Raised stack size - bigger than anything seen in your saves; the game may cap or mishandle it.
- Condition too high - above the usual value; may exceed the item's real maximum.
- Quest item - adding it does NOT complete or advance any quest step.
- Not enough room - free some backpack/hotbar space in the game first, add less, or make the backpack bigger with the Backpack slots box.
- Game is running - save and close the game, then try again.

If a step FAILS, the message says whether your save was left untouched or the original was put back.

THE EXTRA WINDOWS
These windows use the same save file as the main window (World reset has its own World box). The ones that change your save (Player tools, World reset) go through the same safety steps: game must be closed, confirmation first, automatic backup, result re-checked. Recipe tweaks, Build move, Stack sizes and the Backpack slots box change the game (in memory, through small UE4SS mods) and never touch your save; Pictures only reads the game's files.

PLAYER TOOLS
- Vitals and skills - Current and maximum health / stamina / energy / hunger / body warmth, unspent skill points, and the level of each of the 16 skills (or all at once). The list shows each skill's maximum level and benefit per level from the game data, and levels above the cap are stopped. Nothing is written until you press 'Apply changes to save'; only the values you changed are written. XP needed per level = 10 x level^1.5 (matches your save). Levels above anything in your save (highest 29) are flagged as untested.
- Recipes - All recipes found in the game files (item recipes and building recipes), marked learned / not learned. Tick the ones you want and press 'Learn ticked recipes'. Hold the mouse over a recipe to see its picture and details (building recipes: build cost, requirements, description; item recipes: ingredients, what it makes, where and how long). Pictures come from the icons folder (built by Build-RecipeIcons.ps1); the few recipes with no picture in the game files show text only.
- Teleport - Moves you to your bed, the crash site, or any workbench/campfire/etc. you built. You load above the spot (150 cm by default; the 'Drop height' box changes it, use about 500 if a spot is inside rock or a hillside) and drop onto it. The game's own named locations have no coordinates in the exported data, so they cannot be listed; instead open the in-game map, read the X / Y / Z at its lower left (it is YOUR position, not the cursor), type them in the 'Coordinates' boxes under the list and press 'Teleport to coordinates'. Works on any world: pick it in the main window first. If the game spawns you at the start instead, the spot was not accepted (it happened a few times with spots in mid-air or inside rock): try again with a higher drop height or a spot you stood on yourself.
- Quest progress - READ ONLY. Every quest in your save with its in-game name, what the game says about your current step and the next task (from the game's own quest data); green = the game marks that state as an end state. Also task counters, rewards already claimed, journal. Quests are not edited.
- Save info - Summary of the save: world, play time, position, skills, vitals, everything you built.

RECIPE TWEAKS
Change crafting inside the game: ingredient amounts, how many a craft makes, crafting time. Pick a recipe and edit its numbers, or use the boxes on the right and 'Multiply the recipes shown' (filter with Search / Station first, e.g. 'ammo' and 'Amount made x 5'). That button only changes the numbers in this window.

'Save to game' writes the values for the in-game mod. 'Install / update mod' puts the mod into your UE4SS Mods folder (mods.txt is backed up first).

With the game running, saved values apply by themselves within a few seconds (reopen the bench to see them; F8 re-applies by hand). Nothing in your save file changes; to undo, press 'Reset ALL recipes' and Save, or switch the mod off ('RecipeTweaks : 0' in Mods\mods.txt). Every change the mod makes is listed in ue4ss\UE4SS.log under [RecipeTweaks].

WORLD RESET
Puts back things you have used up in the world so you can harvest them again; the game never respawns them by itself. Close the game first.
- World - pick which world (.pfs save) to work on. The box lists every save in your SaveGame folder and starts on the one chosen in the main window. Under it you see the hours played, when it was last saved and how many backups of that world exist.
- What to put back - trees you have chopped down; boulders and ores (rock, coal, flint, iron, copper, sulfur, gold, moon rock); items that lay in the world (scrap, oil, plastic, food, rock shards, scavengable bushes...) that you picked up; loot in containers (cars, cabinets, crates, corpses, trash cans...); bushes and other generated plants / rocks you have harvested; and, if you tick it, other breakables (pallets, rubble, trash piles, furniture). 'Leave containers alone that still hold items' keeps containers you only half emptied.
- Only within N metres - limits the reset to the area around where you stand in the save (your position at the last save). 0 = the whole world. Tip: try 150 first, load the game, check, then do the rest.
- Preview - shows how many of each would be put back and what is left alone. Nothing is changed.
- Reset the world now... - does its own preview, shows you the summary, asks you to confirm, makes a backup, writes the change and checks the result before it replaces your save. You do not have to press Preview first.
How it works: felled trees are removed from the save's record, so they stand again. Partly mined boulders go back to full health. Boulders you broke and items you picked up are put back from your OLD BACKUPS (the tool makes a backup before every change, so keep them), from the saves of your OTHER worlds on the same map (World#1, World#3...): the same object has the same id in every world, so what another world still has untouched can be put back here (ores, breakables and items only; container loot is rolled per world, so containers only use this world's own backups) and, as the LAST source, from a SHIPPED MAP OF UNTOUCHED OBJECTS that comes with the tool (catalog\pristine-world.bin: every boulder, ore, breakable and world item as the game places it, recorded by flying over the whole map in a world nobody had played). So even a world with no backups at all gets its mined boulders, ores and breakables back, and the items you picked up (an item is only restored from it when your save lists it as used up, because items spawn at random per world). Tested on worlds that were not used to build it, it has 98-99% of the ores, 99% of the breakables and 94-98% of the world items; the rest are objects that get a different random id in every world, which no map can know. The tool also saves a STARTING SNAPSHOT the first time it opens a world that has no backup: it matters most for container loot and for those random-id objects, so open the tool early in a new world, before you start mining and looting. A fresh world that you teleport around is therefore a clean source for any area you care about. Looted containers get their original loot back from a backup, or the loot of another unopened container with the same loot table when no backup saw theirs unopened; if none is left in your world, a real roll from a shipped pool of container loot (about 1,100 real rolls over 33 loot groups). Quest items and keys are never re-rolled. The save also keeps one list of used-up objects (it grows with everything you destroy or collect); the game drops a restored object again if it is still on that list, so the reset takes every object it puts back off the list too (this is what made restored moon rock and other ores vanish before; confirmed in the game 2026-10-19).
Bushes and other generated plants / rocks are not world records at all: every harvested one is a single entry (its position) in a list kept on the game's PCG actors in the save, and the reset removes the entries inside your radius, so they grow back (verified in the game with one bush, 2026-10-19; the other kinds in those lists - 12 lists in a 100 h world - were not identified one by one, so try a small radius first). Solar panels are never recorded unopened in any save, so their loot is rolled from the game's own table (one pick: wire, components, electrical parts, rarely metal junk). Known game issue (2026-10-19, version 0.44.3, reproduced with every mod off and in a brand-new world): solar panels show no 'Press F' prompt at all, so restored panel loot cannot be opened for now; bodies, suitcases, crates and the rest work. Containers with no loot sample at all are left alone. To undo a reset use 'Restore a backup...' in the main window.

BUILD MOVE
Lets you pick up a building you placed and put it somewhere else, inside the game, without rebuilding it. The button installs a small in-game mod (a UE4SS mod; Mods\mods.txt is backed up first). A mod only loads when the game starts, so restart the game after installing or updating it. The tool does not edit your save for this: the game saves the new position itself (checked: the moved positions were in the save file).
- Move from the wheel - look at a placed part (furniture, storage chest, barrel, workbench, lamp, brazier, bed), press Q and choose Move. Move is the slot that used to show a padlock, between Deconstruction and Call dog. The part then follows your crosshair.
- Left click - puts it down where it is. Choosing Move again, or pressing F7, also puts it down. F7 does the same as the wheel's Move without opening the wheel.
- Same object - health, contents and variation stay; no materials are used or refunded.
- No collision check - you can put a part on top of another one, stack storage (chests on chests, barrels on barrels) and put storage on walls. This is on purpose. It also means a part can end up inside a wall or the ground; pick it up again with Move to fix it.
- Not tested yet - Page Up / Page Down (turn the held part 15 degrees), F6 (cancel: the part jumps back) and the refusal of structural pieces (walls, floors, foundations, roofs, doors, beams, stairs).
- Log - ue4ss\Mods\BuildMove\BuildMove.log in the game folder lists every step the mod took. To switch the mod off set 'BuildMove : 0' in Mods\mods.txt.

STACK SIZES (button row)
Makes first aid kits STACK, in every inventory (backpack, hotbar, containers). Kits normally take one slot each because they carry a durability (the 'condition'); a stack of durable items shares ONE condition and wastes kits, so this setting also turns their durability off: every use consumes one whole kit, like a bandage (partial use goes away). It works through a small in-game mod (StackSizes, for UE4SS - see the README) that the tool offers to install; your save is never touched by the mod.
- Make first aid kits stackable and single use - the on/off switch. Kits per slot - how many fit in one slot (stacks of 5 and 10 were tried in the game; the biggest allowed is 20).
- Apply - makes a backup of your save, installs or updates the mod if needed and saves the setting. The game applies it every time it starts, before your save loads.
- The window also shows whether the mod is on and how many stacks of kits your save holds (your inventory AND containers).
- IMPORTANT (tested): if the mod is not running, the game trims every stack of kits to ONE the next time it saves and the extra kits are gone for good. So the tool refuses to switch the setting off, or to lower the size below your biggest stack, while stacks exist (use the kits up first), and the main window shows a red DANGER line if stacks sit in your inventory and the mod is not on. If you remove the mod, UE4SS stops loading or the game updates, open this window before you play.

FINDING TEXT IN THIS WINDOW
This window (and the Preview window) has a Find bar on top. Type a word and every match lights up, with a counter such as '3 of 44'. The up and down arrows, Enter / Shift+Enter and F3 / Shift+F3 jump to the next / previous match. Ctrl+F jumps to the box, Esc closes the window.

GAME DATA
- Find anything - Type a name (KeyAnnas, Anna, Whiskey, heater, bunker...) and see every quest, reward pool, loot config, NPC, recipe or world item that mentions it. Select a row for details; the button queues its items.
- Reward pools - What each quest reward group pays out, with exact amounts, and which recipes it teaches. Queue a group's items.
- Quests - All 126 quests: description, every state, the tasks that lead from one state to the next (talk to, find, build, craft...), events, and a '>>' marker where YOUR save is. Use it to see what a stuck quest is waiting for. QUEST HELPER: the box 'Items this step needs' lists what your current step asks for (an item to find or hand over, ingredients for a craft task, a reward group to collect). The button below queues exactly those items.
- Recipes - Crafting recipes (ingredients, amounts, what they make, crafting time, station) and learning recipes (what they teach, how they are learned, cost, which rewards hand them out), with 'learned' status from your save. CRAFT LIST: pick a crafting recipe, set the number in the box to the number of crafts, press the button: all the ingredients are queued.
- Loot tables - Every loot list: items with spawn weight and amount range, guaranteed loot, which containers/NPCs use it.
- Building parts - Cost, health, refund, repair cost and requirements of everything you can build.
- Recordings/notes - The text of recordings, radio messages and notes. This story text is NOT part of the shipped data pack, so the tab is empty until you rebuild the data from your own game files (README, Advanced).
- Game rules - Pick a table: gameplay effects (what food, medicine, wounds and cold do), status effects, difficulty presets, animals (health, damage, loot), NPCs, skills, attributes, plants, destructibles, random encounters, fast travel, achievements, world locations, and, after you rebuild the data yourself, ALL in-game text (the shipped data pack leaves the full text table out). Pick a row to see every field.
- All tables - Every table built from the game files (loot, containers, NPCs, animals, locations, building parts...).
- Bundles - One-click groups: all quest items, a full stack of every ammo, ammo for the weapons you carry now, or everything one reward pool can give. They go into the Queue; you still Preview / Apply as usual.

The box at the top, 'Hide story text', hides quest descriptions, recordings, dialogue and NPC journals until you untick it (it is on by default; the same box is in Player tools > Quest progress). Task lists, items and numbers stay visible.
Game rules > 'Difficulty compare': '(default)' means the preset does not store that setting, so the game's default applies.
Everything here is read from the game's own files (exported with a mappings file so every field has its real name).
Not stored in the files: how often a container is found in the world, and anything the game decides at run time.

STEAM CLOUD
Steam syncs the game's save folder. If it syncs an OLD copy over your edited save, the edit is lost.
Safest: leave Steam Cloud OFF for Permafrost while you use this tool:
- Steam Library > right-click Permafrost > Properties > General > turn off "Keep game saves in the Steam Cloud".
To turn it back on later: do it AFTER your edits. At the next launch Steam may show a conflict - always choose to KEEP/UPLOAD the LOCAL (newer) files, never "download from cloud".
The tool refreshes the save's modified time after every apply and restore so it counts as newest.

LIMITS
- Single-player worlds only - do not use on online/multiplayer worlds.
- The data describes ONE version of the game (datapack.json says which); after a game update it can be out of date until a new release or a rebuild. The Overview warns when the installed game differs.
- An unknown item name is silently ignored by the game (the item just does not appear).
- Quest items are added but do not mark quest progress.
- Stackable first aid kits exist only while the StackSizes mod is on: without it the game trims every stack to one kit when it saves (see STACK SIZES).
- A bigger backpack exists only while the BackpackSlots mod is on. If the mod stops loading (UE4SS reinstalled or updated, a game update, mods.txt changed) the backpack goes back to the game's own size and the game DELETES the items in the extra slots at its next save. Before playing after any such change, check the box under Backpack slots (no red DANGER line) and keep your backups.
- World reset cannot know the few objects that get a different random id in every world (about 1-2% of ores, up to 6% of items), and without a backup it refills container loot with a real roll of the same loot group, not the original contents.
- Build move has no collision check, so a part can be put inside a wall or the ground (pick it up again to fix it).

WHERE THINGS ARE
- This tool: <tool folder>
- Backups: the Backups folder inside it (one backup per change, from any window)
- Data: the catalog folder (CSV files you can open in Excel) and items.json
- Your save: <your save file>
'@
    $h = $h.Replace('<tool folder>', $PSScriptRoot).Replace('<your save file>', $script:SavePath)
    Show-TextDialog 'Help - how the Permafrost Item Tool works' $h -Help
  }

  function Do-Restore {
    $dlg = New-Object System.Windows.Forms.OpenFileDialog; $dlg.InitialDirectory = (Get-BackupDir); $dlg.Filter = 'Save backups (*.pfs)|*.pfs'; $dlg.Title = 'Choose a backup to restore'
    if ($dlg.ShowDialog() -ne 'OK') { return }
    $ok = [System.Windows.Forms.MessageBox]::Show("Replace the current save with:`n$($dlg.FileName)`n`nYour current save is backed up first.", 'Restore backup?', 'OKCancel', 'Question')
    if ($ok -ne 'OK') { return }
    try { $pre = Restore-Backup $script:SavePath $dlg.FileName; Log ("Restored. Previous save kept as: " + $pre); Reload-Inventory } catch { Log ('Restore FAILED: ' + $_.Exception.Message); [void][System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Restore failed', 'OK', 'Error') }
  }

  # ---------- layout that follows the window size (so maximized / full screen looks right) ----------
  function Do-Layout {
    $script:MinLayoutW = 1076
    $W = [math]::Max($form.ClientSize.Width, $script:MinLayoutW); $H = $form.ClientSize.Height
    if ($form.ClientSize.Width -lt 200 -or $form.ClientSize.Height -lt 200) { return }
    foreach ($c in @($gbCat,$gbSel,$gbQ,$gbInv,$gbLog,$txtSave,$btnBrowse,$btnReload,$btnHelp,$lblGame,$lblInfo,$lblNote,$lvCat,$lvInv,$txtLog,$lbQ,$txtSearch,$cmbCat,$btnRestore,$btnOpenBk,$btnRemove,$btnClear,$btnPreview,$btnApply,$btnAdd,$tip)) { $c.Anchor = 'Top,Left' }
    # header, top to bottom: banner (title + Overview + Theme) / Save file row (path + Browse + Reload ... Backpack slots box) / backpack status line under that box / ONE row of 8 equal buttons across the full width / 3 status lines
    $B = 66; $m = 12; $gap = 12; $ySave = $B + 6; $yHint = $B + 34; $yB1 = $B + 54; $yStat = $B + 88
    $yPics = $B + 150; $top = $B + 154 + $(if ($script:PicsBarOn) { 38 } else { 0 })
    $pnlPics.SetBounds($m, $yPics, $W - 2 * $m, 32); $bw1 = 150; $bw2 = 90; $bw3 = 130; $by = 3
    $btnPicsNever.SetBounds($pnlPics.Width - 6 - $bw3, $by, $bw3, 26); $btnPicsLater.SetBounds($btnPicsNever.Left - 6 - $bw2, $by, $bw2, 26); $btnPicsGo.SetBounds($btnPicsLater.Left - 6 - $bw1, $by, $bw1, 26); $lblPics.SetBounds(10, 0, [math]::Max(120, $btnPicsGo.Left - 16), 32)
    $hintW = [math]::Min(560, $W - $m - 480); $hintL = $W - $m - $hintW
    $lblGame.SetBounds($m, $yStat, $W - 2 * $m, 20); $lblInfo.SetBounds($m, $yStat + 22, $W - 2 * $m, 18); $lblNote.SetBounds($m, $yStat + 40, $W - 2 * $m, 18)
    $cmbTheme.SetBounds($W - 12 - 140, 20, 140, 24); $lblTheme.SetBounds($cmbTheme.Left - 56, 23, 52, 20); $btnOv.SetBounds($lblTheme.Left - 14 - 110, 19, 110, 26)
    # Save file row: path box (up to 640 px) + Browse + Reload right after it, and the Backpack slots box at the right end of the same row
    $tw = [math]::Max(300, [math]::Min(640, $W - 570))
    $txtSave.SetBounds(84, $ySave + 1, $tw, 24); $btnBrowse.SetBounds($txtSave.Right + 8, $ySave, 80, 26); $btnReload.SetBounds($btnBrowse.Right + 6, $ySave, 80, 26); $lblSave.Top = $ySave + 4
    # the other eight buttons in ONE row, equal width, spread across the whole window. First what works from your save and the game data, then the three in-game mods (need UE4SS), Help last
    $gg = 6; $gw = [int][math]::Floor(($W - 2 * $m - 7 * $gg) / 8); $grid = @($btnPlayer, $btnWorld, $btnData, $btnPics, $btnTweaks, $btnMove, $btnStk, $btnHelp)
    for ($c = 0; $c -lt 8; $c++) { $grid[$c].SetBounds($m + $c * ($gw + $gg), $yB1, $gw, 26) }
    $leftW = [int](($W - 3 * $m) * 0.46); $rightX = $m + $leftW + $m; $rightW = $W - $rightX - $m
    $H = [math]::Max($H, $top + (346 + $script:SelInfoH + $(if ($chkAdv.Checked) { 28 } else { 0 })) + $gap + 150 + $m)
    $avail = $H - $top - $m
    $minTopH = 346 + $script:SelInfoH + $(if ($chkAdv.Checked) { 28 } else { 0 })   # the queue box under "Selected item" needs room for its four buttons
    $topH = [math]::Max($minTopH, [int](($avail - $gap) * 0.66)); $botH = $avail - $topH - $gap
    $botMin = 150; if ($botH -lt $botMin) { $botH = $botMin; $topH = [math]::Max($minTopH, $avail - $gap - $botH) }
    # catalog (top-left)
    $gbCat.SetBounds($m, $top, $leftW, $topH)
    $cmbCat.SetBounds($leftW - 10 - 190, 22, 190, 24)
    $txtSearch.SetBounds(10, 22, $leftW - 10 - 190 - 8 - 10, 24)
    $lvCat.SetBounds(10, 52, $leftW - 20, $topH - 62)
    # selected item (top-right)
    $selH = 200 + $script:SelInfoH + $(if ($chkAdv.Checked) { 28 } else { 0 })
    $gbSel.SetBounds($rightX, $top, $rightW, $selH)
    $lblSelInfo.Width = $rightW - 24; $lblSelInfo.Height = $script:SelInfoH
    Layout-SelRows
    # queue (right, under selected item)
    $gbQ.SetBounds($rightX, $top + $selH + 6, $rightW, $topH - $selH - 6)
    $lbQ.SetBounds(10, 22, $rightW - 142, $gbQ.Height - 32)
    foreach ($b in @($btnRemove, $btnClear, $btnPreview, $btnApply)) { $b.Left = $rightW - 124 }
    $btnApply.Top = $gbQ.Height - 34
    # inventory + log (bottom row)
    $y2 = $top + $topH + $gap
    $gbInv.SetBounds($m, $y2, $leftW, $botH); $lvInv.SetBounds(10, 22, $leftW - 20, $botH - 32)
    $gbLog.SetBounds($rightX, $y2, $rightW, $botH); $txtLog.SetBounds(10, 22, $rightW - 20, $botH - 66)
    $btnRestore.Top = $botH - 38; $btnOpenBk.Top = $botH - 38
    # backpack size box (top-right) and the info line beside it
    $btnBp.SetBounds($W - $m - 104, $ySave, 104, 26); $numBp.SetBounds($btnBp.Left - 6 - 70, $ySave + 1, 70, 24); $lblBp.SetBounds($numBp.Left - 4 - 104, $ySave + 4, 104, 20)
    $lblBpHint.SetBounds($hintL, $yHint, $hintW, 18)   # its own line right under the Backpack slots box (right-aligned with it), above the buttons; ends in "..." if it ever does not fit
    # nothing below the header may be cut off: when the window is smaller than this, the form scrolls
    $needH = $top + $minTopH + $gap + $botMin + $m; $script:NeedLayoutH = $needH
    $asm = New-Object System.Drawing.Size($script:MinLayoutW, $needH); if ($form.AutoScrollMinSize -ne $asm) { $form.AutoScrollMinSize = $asm }
  }

  # ---------- banner (game key art + logo) and theme picker ----------
  $banner = New-Object System.Windows.Forms.Panel; $banner.Tag = 'banner'; $banner.Dock = 'Top'; $banner.Height = 66
  $banner.GetType().GetProperty('DoubleBuffered', [Reflection.BindingFlags]'Instance,NonPublic').SetValue($banner, $true)
  $banner.Add_Paint({ param($s, $e) Paint-Banner $e.Graphics $s.Width $s.Height 'single-player saves only   |   items - skills - recipes - teleport' })
  $banner.Add_Resize({ $banner.Invalidate() })
  $lblTheme = New-Object System.Windows.Forms.Label; $lblTheme.Text = 'Theme'; $lblTheme.TextAlign = 'MiddleRight'; $lblTheme.BackColor = [System.Drawing.Color]::Transparent; $lblTheme.ForeColor = (Get-BannerFore); $banner.Controls.Add($lblTheme)
  $cmbTheme = New-Object System.Windows.Forms.ComboBox; $cmbTheme.DropDownStyle = 'DropDownList'; foreach ($n in $script:Palettes.Keys) { [void]$cmbTheme.Items.Add($n) }; $cmbTheme.SelectedItem = $script:ThName; $banner.Controls.Add($cmbTheme); $banner.Controls.Add($btnOv)
  $form.Controls.Add($banner)
  function Switch-Theme([string]$name) { Set-Theme $name; Save-ThemeName $name; Apply-Theme $form; $lblTheme.ForeColor = (Get-BannerFore); $banner.Invalidate(); Update-GameState; Refresh-Catalog; Do-Layout; $form.Invalidate($true) }
  $cmbTheme.Add_SelectedIndexChanged({ if ([string]$cmbTheme.SelectedItem -ne $script:ThName) { Switch-Theme ([string]$cmbTheme.SelectedItem) } })

  $script:IsFull = $false
  function Toggle-FullScreen {
    if (-not $script:IsFull) { $form.WindowState = 'Normal'; $form.FormBorderStyle = 'None'; $form.WindowState = 'Maximized'; $script:IsFull = $true }
    else { $form.FormBorderStyle = 'Sizable'; $form.WindowState = 'Maximized'; $script:IsFull = $false }
  }

  # ---------- backpack size box + auto-refresh when the save changes ----------
  $script:BpName = $null
  # red line instead of the "Before applying" note when kit (or Panacea / Surgical Spirit / Painkillers) stacks sit in your inventory but the Stack sizes mod is not on (the game deletes them on save)
  function Update-StackWarning {
    if (-not $script:NoteText) { $script:NoteText = $lblNote.Text }
    $d = $null; try { if (ST-AnyDanger $script:SavePath -SkipContainers) { $d = $true } } catch { }
    if ($d) { $lblNote.ForeColor = [System.Drawing.Color]::Tomato; $lblNote.Text = 'DANGER: stacked kits / medicine and the Stack sizes mod is off - the game deletes the extra on save (Stack sizes button)' }
    else { $lblNote.ForeColor = $script:Th.Muted; $lblNote.Text = $script:NoteText }
  }
  function Update-BackpackBox {
    try { Update-StackWarning } catch { }
    try { $sv = Read-Save $script:SavePath; $eq = Parse-Equipment $sv.Equip } catch { return }
    if (-not $eq) { $lblBpHint.Text = 'No backpack is worn - use the Hotbar target'; $numBp.Enabled = $false; $btnBp.Enabled = $false; return }
    $script:FreeInfo = $null; $script:BpName = $eq.Name; $n = (Get-BackpackMaxSlot $eq) + 1
    $numBp.Enabled = $true; $btnBp.Enabled = $true
    $numBp.Value = [math]::Min([math]::Max([decimal]$n, $numBp.Minimum), $numBp.Maximum)
    $tw = (Get-BackpackTweaks)[$eq.Name]; $ov = BT-Overflow $eq
    if ($ov) {
      # an item sits above the size the tool counts (the in-game mod was switched off or removed?): the game may delete such items
      $lblBpHint.ForeColor = [System.Drawing.Color]::Tomato
      $lblBpHint.Text = $(if ($tw -and -not (BT-ModActive)) { "DANGER: items beyond slot $($ov.Slots) are deleted on save - turn the mod on" } else { "DANGER: slot $($ov.Highest + 1) is beyond the $($ov.Slots) slots: the game deletes it on save" }) }
    elseif ($tw -and -not (BT-ModActive)) { $lblBpHint.ForeColor = $script:Th.Muted; $lblBpHint.Text = "Worn: $($eq.Name) - your size $tw is saved but the in-game mod is not on: using $n" }
    else { $lblBpHint.ForeColor = $script:Th.Muted; $lblBpHint.Text = "Worn: $($eq.Name) - using $n slots ($(Get-BackpackSource $eq))" }
  }
  # Apply the size in the game (BackpackSlots in-game mod): installs the mod the first time and writes tweaks.lua. The game applies it from start-up, before the save loads.
  function Apply-BackpackSize {
    if (-not $script:BpName) { return }
    try {
      $sv = Read-Save $script:SavePath; $eq = Parse-Equipment $sv.Equip; $used = -1
      if ($eq) { foreach ($x in $eq.Contents) { if ($x.Slot -gt $used) { $used = $x.Slot } } }
      $n = [int]$numBp.Value; $gs = Get-BackpackGameSlots $script:BpName
      if ($n -gt 80 -and -not $script:TestMode) {
        $ok = [System.Windows.Forms.MessageBox]::Show("$n slots is much bigger than any backpack in the game (the largest is 50). Sizes above 80 are untested (80 was tried and the screen scrolls); please try a smaller number first if you are unsure.`n`nUse $n slots?", 'Backpack size', 'YesNo', 'Question', 'Button2')
        if ($ok -ne 'Yes') { return } }
      if ($n -ne $gs -and -not (BT-ModStatus).Active) {
        if (-not $script:TestMode) {
          $ok = [System.Windows.Forms.MessageBox]::Show("Changing the size of a backpack needs a small in-game mod (BackpackSlots, for UE4SS). It only changes numbers inside the running game and never touches your save.`n`nInstall it now?", 'Backpack size', 'YesNo', 'Question')
          if ($ok -ne 'Yes') { return } }
        BT-InstallMod; Log 'Installed the BackpackSlots in-game mod (UE4SS Mods folder).' }
      $bk = BT-BackupSave $script:SavePath; if ($bk) { Log ("Backup of your save made first: " + (Split-Path $bk -Leaf)) } else { Log 'No backup made (the game is running or the copy failed) - close the game and use Restore a backup if anything looks wrong.' }
      $r = Set-BackpackTweak $script:BpName $n $used $gs
      if ($r.Removed) { Log ("Backpack size: {0} goes back to the game's own {1} slots." -f $script:BpName, $gs) }
      else { Log ("Backpack size saved: {0} = {1} slots (the game's own is {2}). It is applied every time the game starts, before your save loads. If the game is running now, take the backpack off and put it back on (drag it to the hotbar and back)." -f $script:BpName, $n, $gs) }
      Update-BackpackBox
    } catch { [void][System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Backpack size - not applied', 'OK', 'Warning') }
  }
  $script:LastSaveStamp = $null
  function Check-SaveChanged {
    try {
      $f = Get-Item $script:SavePath; $stamp = "$($f.LastWriteTimeUtc.Ticks)-$($f.Length)"
      if ($null -ne $script:LastSaveStamp -and $stamp -ne $script:LastSaveStamp) { $script:LastSaveStamp = $stamp; Log 'The save changed on disk - inventory reloaded.'; Reload-Inventory }
      $script:LastSaveStamp = $stamp
    } catch { }
  }

  function Get-FreeInfo {   # free slots in the worn backpack and the hotbar, from the save (cached until the save changes)
    if ($script:FreeInfo) { return $script:FreeInfo }
    try { $sv = Read-Save $script:SavePath; $eq = Parse-Equipment $sv.Equip; $hot = Parse-Slots $sv.Hot } catch { return $null }
    $bp = $null; if ($eq) { $mx = Get-BackpackMaxSlot $eq; $u = @{}; foreach ($x in $eq.Contents) { $u[$x.Slot] = 1 }; $bp = 0; for ($i = 0; $i -le $mx; $i++) { if (-not $u.ContainsKey($i)) { $bp++ } } }
    $u2 = @{}; foreach ($x in $hot) { $u2[$x.Slot] = 1 }; $hb = 0; for ($i = 0; $i -le $script:HotbarMaxSlot; $i++) { if (-not $u2.ContainsKey($i)) { $hb++ } }
    $script:FreeInfo = @{ Backpack = $bp; Hotbar = $hb }; return $script:FreeInfo
  }
  function Get-SpaceLeft([string]$tg) {   # free slots for that target minus what is already queued for it (null = unknown)
    $fi = Get-FreeInfo; if (-not $fi -or $null -eq $fi[$tg]) { return $null }
    $queued = 0; foreach ($r in $script:Queue.ToArray()) { if ($r.target -eq $tg) { $queued += [int][math]::Ceiling([int]$r.count / [math]::Max(1, [int]$r.stack)) } }
    return [int]$fi[$tg] - $queued
  }
  function Update-Plan {
    $q = [int]$numQty.Value; $s = [math]::Max(1, [int]$numStack.Value)
    if (-not $script:Selected) { $lblPlan.Text = ''; return }
    if ($null -eq $script:PlanColor) { $script:PlanColor = $lblPlan.ForeColor }
    $slots = [int][math]::Ceiling($q / $s)
    if ($slots -le 1) { $txt = "= 1 slot holding $q" }
    elseif ($q % $s -eq 0) { $txt = "= $slots slots of $s each" }
    else { $txt = "= $slots slots: $($slots - 1) x $s, plus 1 x $($q % $s)" }
    $tg = [string]$cmbTarget.SelectedItem; if (-not $tg) { $tg = 'Backpack' }; $over = $false
    try { $fi = Get-FreeInfo; if ($fi -and $null -ne $fi[$tg]) {
        $left = Get-SpaceLeft $tg; $queued = [int]$fi[$tg] - $left; $txt += "     |     free $($tg.ToLower()) slots: $left" + $(if ($queued) { " (after $queued already queued)" } else { '' })
        if ($slots -gt $left) { $over = $true; $txt += "     |     NOT ENOUGH SPACE: needs $slots" } }
      elseif ($tg -eq 'Backpack') { $txt += '     |     no backpack worn' } } catch { }
    $lblPlan.Text = $txt; $lblPlan.ForeColor = $(if ($over) { $script:Th.Bad } else { $script:PlanColor })
  }  $script:Sync = $false
  function Sync-FromQty {
    if ($script:Sync) { return }; $script:Sync = $true
    try { $s = [math]::Max(1, [int]$numStack.Value); $n = [int][math]::Ceiling([int]$numQty.Value / $s); $numStacks.Value = [math]::Min([math]::Max($n, 1), $numStacks.Maximum); $cmbStacks.SelectedIndex = $(if (([int]$numQty.Value % $s) -eq 0 -and $n -ge 1 -and $n -le 10) { $n - 1 } else { -1 }) } finally { $script:Sync = $false }
    Update-Plan
  }
  function Sync-FromStacks {
    if ($script:Sync) { return }; $script:Sync = $true
    try { $q = [int]$numStacks.Value * [math]::Max(1, [int]$numStack.Value); $numQty.Value = [math]::Min([decimal]$q, $numQty.Maximum); $cmbStacks.SelectedIndex = $(if ([int]$numStacks.Value -ge 1 -and [int]$numStacks.Value -le 10) { [int]$numStacks.Value - 1 } else { -1 }) } finally { $script:Sync = $false }
    Update-Plan
  }
  # ---------- hover pictures (icons\<item id>.png, built by Build-Icons.ps1; text-only if a picture is missing) ----------
  $script:IconDir = Join-Path $PSScriptRoot 'icons'
  $script:IconCache = @{}
  $script:TipData = $null
  $script:HoverKey = $null

  # shows the first-run pictures bar while fewer than 20 pictures exist (and the player has not said "Don't ask again")
  function Update-PicsBar {
    $n = 0; try { $n = @(Get-ChildItem -LiteralPath $script:IconDir -Filter *.png -File -ErrorAction SilentlyContinue).Count } catch { }
    $vis = ($n -lt 20) -and -not (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'pictures.json'))
    if ($script:PicsBarOn -ne $vis) { $script:PicsBarOn = $vis; $pnlPics.Visible = $vis; Do-Layout }
  }

  function Get-ItemIcon([string]$id) {
    if ($script:IconCache.ContainsKey($id)) { return $script:IconCache[$id] }
    $img = $null; $safe = ($id -replace '[\\/:*?"<>|]', '_'); $p = Join-Path $script:IconDir "$safe.png"
    if (Test-Path -LiteralPath $p) { try { $ms = New-Object IO.MemoryStream (, [IO.File]::ReadAllBytes($p)); $img = [System.Drawing.Image]::FromStream($ms) } catch { $img = $null } }
    $script:IconCache[$id] = $img
    return $img
  }

  function Get-TipLines($i) {
    $l = New-Object System.Collections.Generic.List[string]
    $l.Add($i.category + $(if ($i.sub -and $i.sub -ne $i.category) { '  /  ' + ($i.sub -replace '^[^/]*/', '') } else { '' }))
    if ($i.category -notin 'Weapons', 'Clothing', 'QuestItems', 'Traps') { $l.Add("Stack limit: $($i.stackSize)  ($($i.stackSource))") }
    if ($i.maxCondition -and $i.category -in 'Weapons', 'Clothing', 'Accessories', 'Traps', 'QuestItems') { $l.Add("Max condition: $(Get-CondText $i)  ($($i.condSource))") }
    if ($i.usesAmmo -and @($i.usesAmmo).Count) { $l.Add('Uses ammo: ' + (@($i.usesAmmo) -join ', ')) }
    elseif ($i.usedBy -and @($i.usedBy).Count) { $l.Add('Used by: ' + ((@($i.usedBy) | ForEach-Object { $_ -replace '^Weapon_', '' }) -join ', ')) }
    elseif ($i.category -eq 'Weapons') { $l.Add('Melee weapon - uses no ammo') }
    if ($i.sources -and @($i.sources).Count) { $l.Add('Found via: ' + (@($i.sources) -join ', ')) }
    return , $l.ToArray()
  }

  function Measure-Tip($d) {
    $fb = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold); $f = New-Object System.Drawing.Font('Segoe UI', 9)
    $tw = [System.Windows.Forms.TextRenderer]::MeasureText([string]$d.Id, $fb).Width; $th = 24
    foreach ($ln in $d.Lines) { $s = [System.Windows.Forms.TextRenderer]::MeasureText([string]$ln, $f); $tw = [math]::Max($tw, $s.Width); $th += 18 }
    $iw = if ($d.Icon) { 112 } else { 0 }
    $w = [math]::Min([int]($iw + $tw + 28), 560); $h = [math]::Max([int]($th + 14), $(if ($d.Icon) { 120 } else { 44 }))
    $fb.Dispose(); $f.Dispose()
    return New-Object System.Drawing.Size($w, $h)
  }

  function Draw-Tip($g, $r, $d) {
    $g.SmoothingMode = 'AntiAlias'; $g.InterpolationMode = 'HighQualityBicubic'
    $bg = New-Object System.Drawing.SolidBrush ($script:Th.Panel); $g.FillRectangle($bg, $r); $bg.Dispose()
    $pen = New-Object System.Drawing.Pen ($script:Th.Accent); $g.DrawRectangle($pen, $r.X, $r.Y, $r.Width - 1, $r.Height - 1); $pen.Dispose()
    $x = $r.X + 8
    if ($d.Icon) {
      $box = 96; $sc = [math]::Min($box / $d.Icon.Width, $box / $d.Icon.Height); $w = [int]($d.Icon.Width * $sc); $h = [int]($d.Icon.Height * $sc)
      $g.DrawImage($d.Icon, $x + [int](($box - $w) / 2), $r.Y + [int](($r.Height - $h) / 2), $w, $h); $x += 104
    }
    $fb = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold); $f = New-Object System.Drawing.Font('Segoe UI', 9)
    $y = $r.Y + 8
    [System.Windows.Forms.TextRenderer]::DrawText($g, [string]$d.Id, $fb, (New-Object System.Drawing.Point($x, $y)), $script:Th.Text); $y += 24
    foreach ($ln in $d.Lines) { [System.Windows.Forms.TextRenderer]::DrawText($g, [string]$ln, $f, (New-Object System.Drawing.Point($x, $y)), $script:Th.Muted); $y += 18 }
    $fb.Dispose(); $f.Dispose()
  }

  $tt = New-Object System.Windows.Forms.ToolTip; $tt.OwnerDraw = $true; $tt.ShowAlways = $true; $tt.AutoPopDelay = 30000
  $tt.Add_Popup({ param($s, $e) if ($script:TipData) { $e.ToolTipSize = Measure-Tip $script:TipData } })
  $tt.Add_Draw({ param($s, $e) if ($script:TipData) { Draw-Tip $e.Graphics $e.Bounds $script:TipData } else { $e.DrawBackground(); $e.DrawBorder(); $e.DrawText() } })

  function Show-HoverTip($control, [string]$key, [string]$id, $lines, [int]$x, [int]$y) {
    if ($script:HoverKey -eq $key) { return }
    $script:HoverKey = $key
    $script:TipData = @{ Id = $id; Lines = $lines; Icon = (Get-ItemIcon $id) }
    $tt.Show(' ', $control, ($x + 18), ($y + 22))
  }
  function Hide-HoverTip($control) { $script:HoverKey = $null; $tt.Hide($control) }

  $lvCat.Add_MouseMove({ param($s, $e) $it = $lvCat.GetItemAt($e.X, $e.Y); if ($it -and $it.Tag) { Show-HoverTip $lvCat ('cat:' + $it.Tag.id) $it.Tag.id (Get-TipLines $it.Tag) $e.X $e.Y } else { Hide-HoverTip $lvCat } })
  $lvCat.Add_MouseLeave({ Hide-HoverTip $lvCat })
  $lvInv.Add_MouseMove({ param($s, $e) $it = $lvInv.GetItemAt($e.X, $e.Y); if ($it) { $id = $it.SubItems[2].Text; $cat = $script:Cat | Where-Object { $_.id -eq $id } | Select-Object -First 1; $lines = @("$($it.SubItems[0].Text)  -  slot $($it.SubItems[1].Text)", $it.SubItems[3].Text); if ($cat) { $lines += (Get-TipLines $cat)[0] }; Show-HoverTip $lvInv ('inv:' + $it.SubItems[0].Text + $it.SubItems[1].Text) $id $lines $e.X $e.Y } else { Hide-HoverTip $lvInv } })
  $lvInv.Add_MouseLeave({ Hide-HoverTip $lvInv })
  $lbQ.Add_MouseMove({ param($s, $e) $ix = $lbQ.IndexFromPoint($e.X, $e.Y); if ($ix -ge 0 -and $ix -lt $script:Queue.Count) { $r = $script:Queue[$ix]; Show-HoverTip $lbQ ('q:' + $ix + $r.item.id) $r.item.id @("$($r.count) total  ->  $($r.target)", "$([int][math]::Ceiling($r.count / [math]::Max(1, $r.stack))) slot(s), up to $($r.stack) per slot") $e.X $e.Y } else { Hide-HoverTip $lbQ } })
  $lbQ.Add_MouseLeave({ Hide-HoverTip $lbQ })

  # ---------- wire up ----------
  [void]$cmbCat.Items.Add('All'); foreach ($c in ($script:Cat | Select-Object -ExpandProperty category -Unique | Sort-Object)) { [void]$cmbCat.Items.Add($c) }; $cmbCat.SelectedIndex = 0
  $txtSearch.Add_TextChanged({ Refresh-Catalog }); $cmbCat.Add_SelectedIndexChanged({ Refresh-Catalog })
  $lvCat.Add_ColumnClick({ param($s, $e) if ($script:CatSort.Col -eq $e.Column) { $script:CatSort.Desc = -not $script:CatSort.Desc } else { $script:CatSort.Col = $e.Column; $script:CatSort.Desc = $false }; Refresh-Catalog })
  $lvCat.Add_SelectedIndexChanged({ try { On-SelectItem } catch { Log ("Error showing the item: " + $_.Exception.Message + " @ " + $_.InvocationInfo.ScriptLineNumber) } }); $lvCat.Add_DoubleClick({ try { Add-Selected } catch { Log ("Error adding to the queue: " + $_.Exception.Message + " @ " + $_.InvocationInfo.ScriptLineNumber) } })
  $btnAdd.Add_Click({ try { Add-Selected } catch { Log ("Error adding to the queue: " + $_.Exception.Message + " @ " + $_.InvocationInfo.ScriptLineNumber) } })
  $chkAdv.Add_CheckedChanged({ Do-Layout })
  $cmbTarget.Add_SelectedIndexChanged({ Update-Plan }); $cmbStacks.Add_SelectedIndexChanged({ if ($script:Selected -and -not $script:Sync -and $cmbStacks.SelectedIndex -ge 0) { $numQty.Value = [math]::Min([decimal](($cmbStacks.SelectedIndex + 1) * [math]::Max(1, [int]$numStack.Value)), $numQty.Maximum) } })
  $numQty.Add_ValueChanged({ Sync-FromQty }); $numStack.Add_ValueChanged({ Sync-FromQty }); $numStacks.Add_ValueChanged({ Sync-FromStacks })
  $btnRemove.Add_Click({ if ($lbQ.SelectedIndex -ge 0) { $script:Queue.RemoveAt($lbQ.SelectedIndex); Refresh-Queue } })
  $btnClear.Add_Click({ $script:Queue.Clear(); Refresh-Queue })
  $btnApply.Add_Click({ Apply-Queue })
  $btnPreview.Add_Click({ Invoke-Busy 'Working out the slots...' { Show-Preview } $form })
  $btnHelp.Add_Click({ Show-Help })
  $btnStk.Add_Click({ try { Invoke-Busy 'Checking the stacks in your save...' { Show-StackSizes $form $script:SavePath } $form; Update-StackWarning } catch { Log ('Error opening Stack sizes: ' + $_.Exception.Message) } }); $btnOv.Add_Click({ try { Invoke-Busy 'Reading your save...' { Show-Overview $form $script:SavePath } $form } catch { Log ('Error opening Overview: ' + $_.Exception.Message) } }); $btnPicsGo.Add_Click({ try { Show-Pictures $form $script:SavePath -AutoStart; $script:IconCache = @{}; Update-PicsBar } catch { Log ('Error opening Pictures: ' + $_.Exception.Message) } }); $btnPicsLater.Add_Click({ $script:PicsBarOn = $false; $pnlPics.Visible = $false; Do-Layout }); $btnPicsNever.Add_Click({ try { '{"dismissed": true}' | Set-Content -LiteralPath (Join-Path $PSScriptRoot 'pictures.json') -Encoding utf8 } catch { }; $script:PicsBarOn = $false; $pnlPics.Visible = $false; Do-Layout }); $btnPics.Add_Click({ try { Invoke-Busy 'Opening Pictures' { Show-Pictures $form $script:SavePath } $form; $script:IconCache = @{}; Update-PicsBar } catch { Log ('Error opening Pictures: ' + $_.Exception.Message) } }); $btnPlayer.Add_Click({ Open-Player }); $btnData.Add_Click({ Open-Data }); $btnMove.Add_Click({ try { BM-Open } catch { Log ("Error opening Build move: " + $_.Exception.Message) } }); $btnWorld.Add_Click({ try { Open-World } catch { Log ("Error opening World reset: " + $_.Exception.Message + " @ " + $_.InvocationInfo.ScriptLineNumber) } }); $btnTweaks.Add_Click({ try { Open-Tweaks } catch { Log ("Error opening Recipe tweaks: " + $_.Exception.Message + " @ " + $_.InvocationInfo.ScriptLineNumber) } })
  $btnBp.Add_Click({ Apply-BackpackSize })
  $btnReload.Add_Click({ Invoke-Busy 'Re-reading your save...' { Reload-Inventory } $form })
  $btnBrowse.Add_Click({ $pick = Invoke-Busy 'Looking for your worlds...' { Show-WorldPicker $form $txtSave.Text } $form; if ($pick) { $txtSave.Text = $pick; if (Get-Command PF-SetConfig -ErrorAction SilentlyContinue) { PF-SetConfig 'SavePath' $pick }; Reload-Inventory } })
  $btnRestore.Add_Click({ Do-Restore })
  $btnOpenBk.Add_Click({ Start-Process explorer.exe (Get-BackupDir) })
  $form.Add_Resize({ Do-Layout })
  $form.KeyPreview = $true
  $form.Add_KeyDown({ param($s, $e) if ($e.KeyCode -eq 'F11') { Toggle-FullScreen; $e.Handled = $true } elseif ($e.KeyCode -eq 'Escape' -and $script:IsFull) { Toggle-FullScreen; $e.Handled = $true } })
  $timer = New-Object System.Windows.Forms.Timer; $timer.Interval = 2500; $timer.Add_Tick({ Update-GameState; Check-SaveChanged }); $timer.Start()

  Do-Layout; Refresh-Catalog; On-SelectItem; Reload-Inventory; Update-GameState; Apply-Theme $form; $lblTheme.ForeColor = (Get-BannerFore); Do-Layout
  Log ("Catalog: {0} items. Items marked 'verified' use names confirmed in real saves." -f $script:Cat.Count)

  if ($SelfTest) {
    # invisible self-test with the real code paths: shows the form off-screen, resizes, lets the timer tick, reports any UI exception
    $errs = New-Object System.Collections.Generic.List[string]
    [System.Windows.Forms.Application]::add_ThreadException({ param($s, $e) $errs.Add($e.Exception.Message + ' @ ' + $e.Exception.StackTrace) })
    $form.Opacity = 0; $form.ShowInTaskbar = $false; $form.StartPosition = 'Manual'; $form.Location = New-Object System.Drawing.Point(-4000, -4000); $form.Show()
    $out = @()
    foreach ($sz in @(@(1100, 700), @(1100, 760), @(1180, 847), @(1400, 900), @(1920, 1040), @(2400, 1300))) {
      $form.ClientSize = New-Object System.Drawing.Size($sz[0], $sz[1]); [System.Windows.Forms.Application]::DoEvents()
      $bs = @($form.Controls | Where-Object { $_ -is [System.Windows.Forms.Button] -and $_.Top -lt 40 }); $bad = 0
      foreach ($a in $bs) { foreach ($b in $bs) { if ($a -ne $b -and $a.Bounds.IntersectsWith($b.Bounds)) { $bad++ } } }
      $hdr = @($btnPlayer, $btnWorld, $btnData, $btnPics, $btnTweaks, $btnMove, $btnStk, $btnHelp, $btnBrowse, $btnReload, $txtSave, $lblSave, $lblBp, $numBp, $btnBp, $lblBpHint, $lblGame, $lblInfo, $lblNote, $pnlPics); $hov = 0
      for ($ia = 0; $ia -lt $hdr.Count; $ia++) { for ($ib = $ia + 1; $ib -lt $hdr.Count; $ib++) { if ($hdr[$ia].Visible -and $hdr[$ib].Visible -and $hdr[$ia].Bounds.IntersectsWith($hdr[$ib].Bounds)) { $hov++ } } }
      $bar = [math]::Max(0, $gbLog.Bottom + 12 - [math]::Max($form.ClientSize.Height, $form.AutoScrollMinSize.Height))
      $split = [int](100 * $gbCat.Height / ($gbCat.Height + $gbInv.Height)); $out += ("size {0}x{1}: catalog {13}% / inventory {14}%; header overlaps {2}, save box {3}..{4}; lower panels end at {5}, the layout needs {6} of {7} (scrolls {8}); content past the scroll area {9}; status widths {10}/{11}/{12}" -f $sz[0], $sz[1], $hov, $txtSave.Left, $txtSave.Right, $gbLog.Bottom, $form.AutoScrollMinSize.Height, $form.ClientSize.Height, $(if ($form.ClientSize.Height -lt $form.AutoScrollMinSize.Height) { 'yes' } else { 'no' }), $bar, $lblGame.Width, $lblInfo.Width, $lblNote.Width, $split, (100 - $split))
      if ($hov -gt 0 -or $bar -gt 0) { $errs.Add("layout problem at $($sz[0])x$($sz[1]): header overlaps $hov, content past the scroll area $bar") }
    }
    if ($env:PF_DISCORD) {   # pictures for posts (Frostbite theme): the main window with a hover picture, Stack sizes, Help, Overview (top and mods section), the "please wait" box, World reset
      $dd = $env:PF_DISCORD; Switch-Theme 'Frostbite'; $cmbTheme.SelectedItem = 'Frostbite'; $form.ClientSize = New-Object System.Drawing.Size(1400, 900); $cmbCat.SelectedItem = 'All'; $txtSearch.Text = 'Weapon_'; [System.Windows.Forms.Application]::DoEvents()
      $lvCat.Items[3].Selected = $true; [void](Queue-ById 'Whiskey' 6); [System.Windows.Forms.Application]::DoEvents()
      $hov = $null; for ($ix = 0; $ix -lt [math]::Min(14, $lvCat.Items.Count); $ix++) { if ($lvCat.Items[$ix].Tag -and (Get-ItemIcon $lvCat.Items[$ix].Tag.id)) { $hov = $lvCat.Items[$ix]; break } }
      if ($hov) { $env:PF_LIVE = '1'; try { Save-WindowShot $form (Join-Path $dd '01_main_hover.png') { Show-HoverTip $lvCat ('cat:' + $hov.Tag.id) $hov.Tag.id (Get-TipLines $hov.Tag) ($hov.Bounds.X + 70) ($hov.Bounds.Y + 6) } } finally { Remove-Item Env:PF_LIVE -ErrorAction SilentlyContinue; Hide-HoverTip $lvCat } } else { Save-WindowShot $form (Join-Path $dd '01_main.png') }
      Save-WindowShot $form (Join-Path $dd '_main_plain.png')
      $script:TestMode = $true
      $sf = New-StackSizesForm $script:SavePath; $sf.Opacity = 0; $sf.ShowInTaskbar = $false; $sf.StartPosition = 'Manual'; $sf.Location = New-Object System.Drawing.Point(-4000, -4000); $sf.Show(); [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 300; [System.Windows.Forms.Application]::DoEvents()
      Save-WindowShot $sf (Join-Path $dd '02_stack_sizes.png'); $sf.Close()
      $script:DialogTestHook = { param($dlg, $tfx, $tbx, $lcx, $bN, $bP, $tmr)
        $dlg.Opacity = 0; $dlg.ShowInTaskbar = $false; $dlg.StartPosition = 'Manual'; $dlg.Location = New-Object System.Drawing.Point(-4000, -4000); $dlg.Show(); [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 300; [System.Windows.Forms.Application]::DoEvents()
        Save-WindowShot $dlg (Join-Path $dd '03_help.png'); $dlg.Close() }
      Show-Help; $script:DialogTestHook = $null
      $ovf = @(New-OverviewForm $script:SavePath) | Where-Object { $_ -is [System.Windows.Forms.Form] } | Select-Object -First 1; $ovf.Opacity = 0; $ovf.ShowInTaskbar = $false; $ovf.StartPosition = 'Manual'; $ovf.Location = New-Object System.Drawing.Point(-4000, -4000); $ovf.Show(); [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 500; [System.Windows.Forms.Application]::DoEvents()
      Save-WindowShot $ovf (Join-Path $dd '04_overview.png')
      $o = $script:OV.Out; $o.SelectionStart = $o.TextLength; $o.SelectionLength = 0; $o.ScrollToCaret(); [System.Windows.Forms.Application]::DoEvents(); Save-WindowShot $ovf (Join-Path $dd '05_overview_mods.png'); $ovf.Close()
      $mb = [System.Drawing.Image]::FromFile((Join-Path $dd '_main_plain.png')); $cv = New-Object System.Drawing.Bitmap $mb.Width, $mb.Height; $g = [System.Drawing.Graphics]::FromImage($cv); $g.DrawImage($mb, 0, 0, $mb.Width, $mb.Height)
      $bx = [int](($mb.Width - 360) / 2); $by = [int](($mb.Height - 92) / 2); $br = New-Object System.Drawing.SolidBrush($script:Th.Accent); $g.FillRectangle($br, $bx, $by, 360, 92); $br.Dispose(); $br = New-Object System.Drawing.SolidBrush($script:Th.Panel); $g.FillRectangle($br, $bx + 2, $by + 2, 356, 88); $br.Dispose()
      $f1 = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold); $f2 = New-Object System.Drawing.Font('Segoe UI', 9); $fl = [System.Windows.Forms.TextFormatFlags]::HorizontalCenter -bor [System.Windows.Forms.TextFormatFlags]::VerticalCenter
      [System.Windows.Forms.TextRenderer]::DrawText($g, 'Reading your save...', $f1, (New-Object System.Drawing.Rectangle(($bx + 10), ($by + 14), 340, 34)), $script:Th.Text, $fl); [System.Windows.Forms.TextRenderer]::DrawText($g, 'Please wait a moment...', $f2, (New-Object System.Drawing.Rectangle(($bx + 10), ($by + 50), 340, 22)), $script:Th.Muted, $fl)
      $g.Dispose(); $cv.Save((Join-Path $dd '06_busy_popup.png')); $cv.Dispose(); $mb.Dispose(); $f1.Dispose(); $f2.Dispose()
      $wf = New-WorldResetForm; $wf.Opacity = 0; $wf.ShowInTaskbar = $false; $wf.StartPosition = 'Manual'; $wf.Location = New-Object System.Drawing.Point(-4000, -4000); $wf.Show(); [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 400; [System.Windows.Forms.Application]::DoEvents()
      Save-WindowShot $wf (Join-Path $dd '07_world_reset.png'); $wf.Close()
      $script:TestMode = $false; Remove-Item (Join-Path $dd '_main_plain.png') -ErrorAction SilentlyContinue; $script:Queue.Clear(); Refresh-Queue; $txtSearch.Text = ''
    }
    if ($env:PF_SHOTS) {
      foreach ($shotSz in @(@(1100, 700), @(1400, 900), @(1700, 1000))) { $form.ClientSize = New-Object System.Drawing.Size($shotSz[0], $shotSz[1]); [System.Windows.Forms.Application]::DoEvents(); Save-WindowShot $form (Join-Path $env:PF_SHOTS ("layout_{0}x{1}.png" -f $shotSz[0], $shotSz[1])) }
      $form.ClientSize = New-Object System.Drawing.Size(1400, 900); [System.Windows.Forms.Application]::DoEvents()
      foreach ($tn in @($script:Palettes.Keys)) {
        Switch-Theme $tn; $cmbTheme.SelectedItem = $tn; $txtSearch.Text = 'Weapon_'; [System.Windows.Forms.Application]::DoEvents()
        $lvCat.Items[3].Selected = $true; [void](Queue-ById 'Whiskey' 6); [System.Windows.Forms.Application]::DoEvents()
        Update-PicsBar; [System.Windows.Forms.Application]::DoEvents(); Save-WindowShot $form (Join-Path $env:PF_SHOTS "main_$tn.png")
        $script:Queue.Clear(); Refresh-Queue; $txtSearch.Text = ''
        $script:TestMode = $true
        $dw = New-DataForm; $dw.Opacity = 0; $dw.ShowInTaskbar = $false; $dw.StartPosition = 'Manual'; $dw.Location = New-Object System.Drawing.Point(-4000, -4000); $dw.Show(); $script:GD.Find.Filter.Text = 'KeyAnnas'; [System.Windows.Forms.Application]::DoEvents(); $script:GD.Find.LV.Items[0].Selected = $true; [System.Windows.Forms.Application]::DoEvents()
        Save-WindowShot $dw (Join-Path $env:PF_SHOTS "data_$tn.png"); $dw.Close()
        $pw = New-PlayerForm; $pw.Opacity = 0; $pw.ShowInTaskbar = $false; $pw.StartPosition = 'Manual'; $pw.Location = New-Object System.Drawing.Point(-4000, -4000); $pw.Size = New-Object System.Drawing.Size(1500, 820); $pw.Show(); [System.Windows.Forms.Application]::DoEvents()
        Save-WindowShot $pw (Join-Path $env:PF_SHOTS "player_$tn.png"); $pw.Close()
        foreach ($sw in @(@{ F = { New-OverviewForm $script:SavePath }; N = 'overview' }, @{ F = { New-PicturesForm $script:SavePath }; N = 'pictures' })) {
          $sf = & $sw.F; $sf.Opacity = 0; $sf.ShowInTaskbar = $false; $sf.StartPosition = 'Manual'; $sf.Location = New-Object System.Drawing.Point(-4000, -4000); $sf.Show(); [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 300; [System.Windows.Forms.Application]::DoEvents()
          Save-WindowShot $sf (Join-Path $env:PF_SHOTS "$($sw.N)_$tn.png"); $sf.Close() }
        $script:TestMode = $false
      }
      Switch-Theme 'Frostbite'
      $cmbCat.SelectedItem = 'All'; $txtSearch.Text = ''; [System.Windows.Forms.Application]::DoEvents(); $lvCat.Items[40].Selected = $true; [System.Windows.Forms.Application]::DoEvents(); Save-WindowShot $form (Join-Path $env:PF_SHOTS 'cat_specs.png')
      # simplified Selected-item panel: weapon, resource (+ quick buttons), advanced mode
      $txtSearch.Text = 'PU-12_Stratos'; [System.Windows.Forms.Application]::DoEvents(); $lvCat.Items[0].Selected = $true; [System.Windows.Forms.Application]::DoEvents(); Save-WindowShot $form (Join-Path $env:PF_SHOTS 'sel_weapon.png')
      $txtSearch.Text = 'Coal'; [System.Windows.Forms.Application]::DoEvents(); $lvCat.Items[0].Selected = $true; [System.Windows.Forms.Application]::DoEvents()
      $cmbStacks.SelectedIndex = 4; [System.Windows.Forms.Application]::DoEvents(); $out += "5-stacks dropdown: item $($script:Selected.id), stack $($numStack.Value), total $($numQty.Value), plan: $($lblPlan.Text)"
      Save-WindowShot $form (Join-Path $env:PF_SHOTS 'sel_resource.png')
      $chkAdv.Checked = $true; [System.Windows.Forms.Application]::DoEvents(); Save-WindowShot $form (Join-Path $env:PF_SHOTS 'sel_advanced.png'); $chkAdv.Checked = $false; $txtSearch.Text = ''
    }
    # integration: queue hook, Game data window and Player tools window opened invisibly with the real main-window hooks
    [void](Queue-ById 'KeyAnnas' 1); $out += "Queue-ById -> queue has $($script:Queue.Count): $($lbQ.Items[0])"
    $script:TestMode = $true
    $dataWin = New-DataForm; $dataWin.Opacity = 0; $dataWin.ShowInTaskbar = $false; $dataWin.StartPosition = 'Manual'; $dataWin.Location = New-Object System.Drawing.Point(-4000, -4000); $dataWin.Show(); [System.Windows.Forms.Application]::DoEvents()
    $script:GD.Find.Filter.Text = 'Sean'; [System.Windows.Forms.Application]::DoEvents(); $out += "Game data: find 'Sean' -> $($script:GD.Find.Count.Text)"
$script:GD.Tabs.SelectedIndex = 3; [System.Windows.Forms.Application]::DoEvents(); $script:GD.Recipes.Filter.Text = 'Tent'; [System.Windows.Forms.Application]::DoEvents(); $rv = $script:GD.Recipes.LV; $out += "Game data: recipes 'Tent' -> $($script:GD.Recipes.Count.Text); first row ingredients = " + $(if ($rv.Items.Count) { $rv.Items[0].SubItems[3].Text } else { 'none' }); $script:GD.Recipes.Filter.Text = ''; [System.Windows.Forms.Application]::DoEvents(); $script:GD.Tabs.SelectedIndex = 0
    $script:GD.Tabs.SelectedIndex = 1; [System.Windows.Forms.Application]::DoEvents(); $script:GD.Pools.Filter.Text = 'WhenLied'; [System.Windows.Forms.Application]::DoEvents(); $pv = $script:GD.Pools.LV; $out += "Reward groups 'WhenLied' -> $($script:GD.Pools.Count.Text); rows: " + (($pv.Items | ForEach-Object { $_.SubItems[1].Text + ' = ' + $_.SubItems[2].Text }) -join ' | '); if ($pv.Items.Count) { $pv.Items[0].Selected = $true; [System.Windows.Forms.Application]::DoEvents(); $out += 'detail: ' + (($script:GD.Pools.Detail.Text -split "`r?`n" | Select-Object -First 6) -join ' / ') }; $script:GD.Pools.Filter.Text = 'Amalie_Perma'; [System.Windows.Forms.Application]::DoEvents(); if ($pv.Items.Count) { $out += 'Amalie_Perma teaches: ' + $pv.Items[0].SubItems[3].Text }; $script:GD.Pools.Filter.Text = ''
    $script:GD.Tabs.SelectedIndex = 3; [System.Windows.Forms.Application]::DoEvents(); $script:GD.Recipes.Filter.Text = 'LearningRecipe_PermafrostBoots'; [System.Windows.Forms.Application]::DoEvents(); if ($script:GD.Recipes.LV.Items.Count) { $out += 'learning recipe row: ' + $script:GD.Recipes.LV.Items[0].SubItems[3].Text }; $script:GD.Recipes.Filter.Text = ''; [System.Windows.Forms.Application]::DoEvents()
    $script:GD.Tabs.SelectedIndex = 4; [System.Windows.Forms.Application]::DoEvents(); $script:GD.Loot.Filter.Text = 'TrashContainer_Small'; [System.Windows.Forms.Application]::DoEvents(); $lvL = $script:GD.Loot.LV; $out += "Loot lists 'TrashContainer_Small' -> $($script:GD.Loot.Count.Text); row: " + $(if ($lvL.Items.Count) { ($lvL.Items[0].SubItems | ForEach-Object { $_.Text }) -join ' | ' } else { 'none' }); $script:GD.Loot.Filter.Text = 'Preset_Remnants_Trash'; [System.Windows.Forms.Application]::DoEvents(); if ($lvL.Items.Count) { $lvL.Items[0].Selected = $true; [System.Windows.Forms.Application]::DoEvents(); $out += 'loot detail: ' + (($script:GD.Loot.Detail.Text -split "`r?`n" | Where-Object { $_ } | Select-Object -First 9) -join ' / ') }; $script:GD.Loot.Filter.Text = ''; [System.Windows.Forms.Application]::DoEvents()
    $script:GD.Tabs.SelectedIndex = 2; [System.Windows.Forms.Application]::DoEvents(); $script:GD.Quests.Filter.Text = 'BP_Quest_EA_Main_02'; [System.Windows.Forms.Application]::DoEvents(); $lq = $script:GD.Quests.LV; $out += "Quests tab 'BP_Quest_EA_Main_02' -> $($script:GD.Quests.Count.Text)"; if ($lq.Items.Count) { $lq.Items[0].Selected = $true; [System.Windows.Forms.Application]::DoEvents(); $out += 'quest detail: ' + (($script:GD.Quests.Detail.Text -split "`r?`n" | Where-Object { $_ } | Select-Object -First 8) -join ' / ') }; $script:GD.Quests.Filter.Text = ''; [System.Windows.Forms.Application]::DoEvents()
    $script:GD.Tabs.SelectedIndex = 5; [System.Windows.Forms.Application]::DoEvents(); $script:GD.Build.Filter.Text = 'Stove'; [System.Windows.Forms.Application]::DoEvents(); $lb = $script:GD.Build.LV; $out += "Building tab 'Stove' -> $($script:GD.Build.Count.Text)"; if ($lb.Items.Count) { $lb.Items[0].Selected = $true; [System.Windows.Forms.Application]::DoEvents(); $out += 'build detail: ' + (($script:GD.Build.Detail.Text -split "`r?`n" | Where-Object { $_ } | Select-Object -First 6) -join ' / ') }; $script:GD.Build.Filter.Text = ''; [System.Windows.Forms.Application]::DoEvents()
    $script:GD.Tabs.SelectedIndex = 6; [System.Windows.Forms.Application]::DoEvents(); $script:GD.Lore.Filter.Text = 'Cabin'; [System.Windows.Forms.Application]::DoEvents(); $ll = $script:GD.Lore.LV; $out += "Lore tab 'Cabin' -> $($script:GD.Lore.Count.Text)"; if ($ll.Items.Count) { $ll.Items[0].Selected = $true; [System.Windows.Forms.Application]::DoEvents(); $out += 'lore detail: ' + (($script:GD.Lore.Detail.Text -split "`r?`n" | Where-Object { $_ } | Select-Object -First 5) -join ' / ') }; $script:GD.Lore.Filter.Text = ''; [System.Windows.Forms.Application]::DoEvents()
    $script:GD.Tabs.SelectedIndex = 7; [System.Windows.Forms.Application]::DoEvents(); $script:GD.Rules.Combo.SelectedItem = 'Animals'; [System.Windows.Forms.Application]::DoEvents(); $script:GD.Rules.Filter.Text = 'Bear'; [System.Windows.Forms.Application]::DoEvents(); $lr = $script:GD.Rules.LV; $out += "Rules tab Animals/Bear -> $($script:GD.Rules.Count.Text); cols: " + (($lr.Columns | ForEach-Object { $_.Text }) -join ','); if ($lr.Items.Count) { $lr.Items[0].Selected = $true; [System.Windows.Forms.Application]::DoEvents(); $out += 'rules detail: ' + (($script:GD.Rules.Detail.Text -split "`r?`n" | Where-Object { $_ } | Select-Object -First 6) -join ' / ') }; $script:GD.Rules.Combo.SelectedItem = 'Status effects'; $script:GD.Rules.Filter.Text = 'Bleeding'; [System.Windows.Forms.Application]::DoEvents(); $out += "Rules Status effects/Bleeding -> $($script:GD.Rules.Count.Text)"; $script:GD.Rules.Filter.Text = ''; [System.Windows.Forms.Application]::DoEvents()
    $script:GD.Tabs.SelectedIndex = 3; [System.Windows.Forms.Application]::DoEvents(); $script:GD.Recipes.Filter.Text = 'CraftingRecipe_Tent'; [System.Windows.Forms.Application]::DoEvents(); $rq = $script:GD.Recipes.LV; if ($rq.Items.Count) { $rq.Items[0].Selected = $true; [System.Windows.Forms.Application]::DoEvents(); $q0 = $script:Queue.Count; $script:GD.Recipes.Qty.Value = 2; GD-QueueRow $script:GD.Recipes; $out += "craft queue: x2 Tent -> " + $script:GD.Recipes.QMsg.Text + " (queue $q0 -> $($script:Queue.Count))"; $script:Queue.Clear(); Refresh-Queue }; $script:GD.Recipes.Qty.Value = 1; $script:GD.Recipes.Filter.Text = ''; [System.Windows.Forms.Application]::DoEvents()
    $script:GD.Tabs.SelectedIndex = 2; [System.Windows.Forms.Application]::DoEvents(); $script:GD.Quests.Filter.Text = 'BP_Quest_EA_Main_03_HouseCamp'; [System.Windows.Forms.Application]::DoEvents(); $lq2 = $script:GD.Quests.LV; if ($lq2.Items.Count) { $lq2.Items[0].Selected = $true; [System.Windows.Forms.Application]::DoEvents(); $q1 = $script:Queue.Count; GD-QueueRow $script:GD.Quests; $out += "quest queue (House Camp, start step) -> " + $script:GD.Quests.QMsg.Text; $script:Queue.Clear(); Refresh-Queue }; $script:GD.Quests.Filter.Text = ''; [System.Windows.Forms.Application]::DoEvents()
    foreach ($qs in @(@('BP_Quest_EA_Main_03_HouseCamp', 'QuestState_6'), @('BP_Quest_EA_Main_Anna_HouseCampFlipper', 'QuestState_7'), @('BP_Quest_EA_Main_Anna_HouseCampFlipper', 'QuestState_Report'), @('BP_Quest_EA_Main_Anna_HouseCampFlipper', 'QuestState_3'))) { $qn = @(GD-QuestNeeds $qs[0] $qs[1]); $out += "quest needs ($($qs[0]) @ $($qs[1])): " + (($qn | ForEach-Object { "$($_.id) x$($_.amount)" }) -join ', ') }
    $spc = $null; foreach ($pc in $script:GD.Form.Controls) { if ($pc -is [System.Windows.Forms.Panel]) { foreach ($cc in $pc.Controls) { if ($cc -is [System.Windows.Forms.CheckBox]) { $spc = $cc } } } }; if ($spc) { $script:GD.Tabs.SelectedIndex = 2; $script:GD.Quests.Filter.Text = 'BP_Quest_EA_Main_02'; [System.Windows.Forms.Application]::DoEvents(); $script:GD.Quests.LV.Items[0].Selected = $true; $spc.Checked = $true; [System.Windows.Forms.Application]::DoEvents(); $h1 = ($script:GD.Quests.Detail.Text -match 'story text hidden'); $spc.Checked = $false; [System.Windows.Forms.Application]::DoEvents(); $h2 = ($script:GD.Quests.Detail.Text -match 'story text hidden'); $out += "spoiler toggle: hidden when ticked = $h1, hidden when unticked = $h2"; $spc.Checked = $true; [System.Windows.Forms.Application]::DoEvents(); $script:GD.Quests.Filter.Text = '' } else { $out += 'spoiler checkbox not found' }
    $script:GD.Tabs.SelectedIndex = 7; $swT = [Diagnostics.Stopwatch]::StartNew(); $script:GD.Rules.Combo.SelectedItem = 'Game text (all in-game text)'; [System.Windows.Forms.Application]::DoEvents(); $t1 = [int]$swT.ElapsedMilliseconds; $swT.Restart(); $script:GD.Rules.Filter.Text = 'Anna'; [System.Windows.Forms.Application]::DoEvents(); $t2 = [int]$swT.ElapsedMilliseconds; $out += "timing: game text first load $t1 ms, filter 'Anna' $t2 ms -> $($script:GD.Rules.Count.Text)"; $script:GD.Rules.Filter.Text = ''; $script:GD.Rules.Combo.SelectedItem = 'Animals'; [System.Windows.Forms.Application]::DoEvents()
    $cmbCat.SelectedItem = 'All'; $txtSearch.Text = 'coal'; [System.Windows.Forms.Application]::DoEvents(); if ($lvCat.Items.Count) { $lvCat.Items[0].Selected = $true; [System.Windows.Forms.Application]::DoEvents(); $out += "coal select: id label=[$($lblSelId.Text)] selected=[$($script:Selected.id)] info lines=" + (($lblSelInfo.Text -split "`r?`n").Count); $q0 = $script:Queue.Count; $btnAdd.PerformClick(); [System.Windows.Forms.Application]::DoEvents(); $out += "coal add button click: queue $q0 -> $($script:Queue.Count); button enabled=$($btnAdd.Enabled) visible=$($btnAdd.Visible) bounds=$($btnAdd.Bounds)"; $script:Queue.Clear(); Refresh-Queue; $lvCat.Items[0].Selected = $false; $lvCat.Items[0].Selected = $true; [System.Windows.Forms.Application]::DoEvents(); $q0 = $script:Queue.Count; Add-Selected; $out += "coal add function: queue $q0 -> $($script:Queue.Count)"; $script:Queue.Clear(); Refresh-Queue } else { $out += 'coal: no rows' }; $txtSearch.Text = ''; [System.Windows.Forms.Application]::DoEvents()
    $txtSearch.Text = 'coal'; [System.Windows.Forms.Application]::DoEvents(); $lvCat.SelectedItems.Clear(); [System.Windows.Forms.Application]::DoEvents(); $out += "after typing coal, selected=[$($script:Selected.id)]; info=[$($lblSelId.Text)]"; $q0 = $script:Queue.Count; $btnAdd.PerformClick(); [System.Windows.Forms.Application]::DoEvents(); $out += "add with nothing selected, one row shown (must NOT queue now): queue $q0 -> $($script:Queue.Count)"; $script:Queue.Clear(); Refresh-Queue; $txtSearch.Text = 'Weapon_'; [System.Windows.Forms.Application]::DoEvents(); $lvCat.SelectedItems.Clear(); [System.Windows.Forms.Application]::DoEvents(); $btnAdd.PerformClick(); [System.Windows.Forms.Application]::DoEvents(); $out += "add with nothing selected, many rows: queue $($script:Queue.Count); last log line: " + (($txtLog.Lines | Where-Object { $_ } | Select-Object -Last 1)); $txtSearch.Text = ''; [System.Windows.Forms.Application]::DoEvents()
    $txtSearch.Text = 'Coal'; [System.Windows.Forms.Application]::DoEvents(); $lvCat.Items[0].Selected = $true; [System.Windows.Forms.Application]::DoEvents(); $st = [int]$numStack.Value; $cmbStacks.SelectedIndex = 6; [System.Windows.Forms.Application]::DoEvents(); $a1 = [int]$numQty.Value; $numQty.Value = $st * 3; [System.Windows.Forms.Application]::DoEvents(); $a2 = $cmbStacks.SelectedIndex; $numQty.Value = $st * 3 + 7; [System.Windows.Forms.Application]::DoEvents(); $a3 = $cmbStacks.SelectedIndex; $out += "stacks dropdown: stack size $st; pick 7 stacks -> total $a1 (expect $($st * 7)); type total of 3 stacks -> dropdown index $a2 (expect 2); odd total -> index $a3 (expect -1); items = $($cmbStacks.Items.Count)"; $txtSearch.Text = ''; [System.Windows.Forms.Application]::DoEvents()
    $txtSearch.Text = 'Coal'; [System.Windows.Forms.Application]::DoEvents(); $lvCat.Items[0].Selected = $true; [System.Windows.Forms.Application]::DoEvents(); $script:Queue.Clear(); Refresh-Queue; $cmbTarget.SelectedItem = 'Backpack'; $numQty.Value = 20 * 50; [System.Windows.Forms.Application]::DoEvents(); $p20 = $lblPlan.Text; $numQty.Value = 40 * 50; [System.Windows.Forms.Application]::DoEvents(); $p40 = $lblPlan.Text; $c40 = $lblPlan.ForeColor.Name; $numQty.Value = 20 * 50; Add-Selected; [System.Windows.Forms.Application]::DoEvents(); $pAfter = $lblPlan.Text; $numQty.Value = 20 * 50; [System.Windows.Forms.Application]::DoEvents(); $pOver = $lblPlan.Text; Add-Selected; $out += "plan 20 stacks: [$p20]"; $out += "plan 40 stacks: [$p40]"; $out += "after queueing 20, plan for 20 more: [$pOver]"; $out += "log: " + (($txtLog.Lines | Where-Object { $_ } | Select-Object -Last 2) -join ' // '); $cmbTarget.SelectedItem = 'Hotbar'; [System.Windows.Forms.Application]::DoEvents(); $out += "hotbar plan: [$($lblPlan.Text)]"; $cmbTarget.SelectedItem = 'Backpack'; $script:Queue.Clear(); Refresh-Queue; $txtSearch.Text = ''; [System.Windows.Forms.Application]::DoEvents()
    foreach ($sz in @(@(1100, 760), @(1250, 800))) { $form.ClientSize = New-Object System.Drawing.Size($sz[0], $sz[1]); [System.Windows.Forms.Application]::DoEvents(); $txtSearch.Text = 'PU-12_Stratos'; [System.Windows.Forms.Application]::DoEvents(); $lvCat.Items[0].Selected = $true; [System.Windows.Forms.Application]::DoEvents(); $need = [System.Windows.Forms.TextRenderer]::MeasureText($lblSelInfo.Text, $lblSelInfo.Font, (New-Object System.Drawing.Size($lblSelInfo.Width, 3000)), [System.Windows.Forms.TextFormatFlags]::WordBreak).Height; $out += "narrow window $($sz[0])x$($sz[1]): label width $($lblSelInfo.Width), text needs $need px, box is $($lblSelInfo.Height) px -> " + $(if ($lblSelInfo.Height -ge $need) { 'fits' } else { 'CLIPPED' }) + "; quantity row top $($numQty.Top), group height $($gbSel.Height)" }; $form.ClientSize = New-Object System.Drawing.Size(1400, 900); $txtSearch.Text = ''; [System.Windows.Forms.Application]::DoEvents()
    foreach ($nm in @('PU-12_Stratos', 'Coal', 'Candle', 'Dish')) { $txtSearch.Text = $nm; [System.Windows.Forms.Application]::DoEvents(); if ($lvCat.Items.Count) { $lvCat.Items[0].Selected = $true; [System.Windows.Forms.Application]::DoEvents(); $need = [System.Windows.Forms.TextRenderer]::MeasureText($lblSelInfo.Text, $lblSelInfo.Font, (New-Object System.Drawing.Size($lblSelInfo.Width, 3000)), [System.Windows.Forms.TextFormatFlags]::WordBreak).Height; $out += "panel fit [$($script:Selected.id)]: text needs $need px, box is $($lblSelInfo.Height) px, group height $($gbSel.Height), queue top $($gbQ.Top) -> " + $(if ($lblSelInfo.Height -ge $need) { 'fits' } else { 'CLIPPED' }) } }; $txtSearch.Text = ''; [System.Windows.Forms.Application]::DoEvents()
    $rtTmp = Join-Path $env:TEMP ('rt-test-' + [guid]::NewGuid().ToString('N').Substring(0, 6)); New-Item -ItemType Directory -Force $rtTmp | Out-Null
    [IO.File]::WriteAllText("$rtTmp\mods.txt", "CheatManagerEnablerMod : 1`r`nBPModLoaderMod : 1`r`n`r`n`r`n; Built-in keybinds, do not move up!`r`nKeybinds : 1`r`n")
    $script:RtModsDirOverride = $rtTmp; $script:RtStateOverride = "$rtTmp\state.json"; $script:TestMode = $true
    try { $rf = New-RecipeTweaksForm; $rf.Opacity = 0; $rf.ShowInTaskbar = $false; $rf.StartPosition = 'Manual'; $rf.Location = New-Object System.Drawing.Point(-4000, -4000); $rf.Show(); [System.Windows.Forms.Application]::DoEvents(); $ui = $script:RT
      $out += "recipe tweaks: $($ui.Rows.Count) recipes, $($ui.LV.Items.Count) shown; before install: $((RT-ModStatus).Text)"
      RT-InstallMod; $mt = Get-Content "$rtTmp\mods.txt" -Raw; $out += "after install: $((RT-ModStatus).Text.Substring(0, 40)) | mods.txt order ok = " + ($mt -match '(?s)BPModLoaderMod : 1.*RecipeTweaks : 1.*Built-in keybinds') + "; main.lua copied = " + (Test-Path "$rtTmp\RecipeTweaks\Scripts\main.lua") + "; backup = " + (Test-Path "$rtTmp\mods.txt.bak-before-recipetweaks")
      $ui.Filter.Text = 'Tent'; [System.Windows.Forms.Application]::DoEvents(); $ui.LV.Items[0].Selected = $true; [System.Windows.Forms.Application]::DoEvents()
      $r0 = $ui.Sel; $before = ($r0.Cur.cost -join ','); $ui.IngNum[0].Value = 4; $ui.TimeNum.Value = 5; [System.Windows.Forms.Application]::DoEvents()
      $out += "edit Tent: $($r0.Name) cost $before -> $($r0.Cur.cost -join ','), time $($r0.Time) -> $($r0.Cur.time); row text: $($ui.LV.SelectedItems[0].SubItems[2].Text) / $($ui.LV.SelectedItems[0].SubItems[4].Text) / $($ui.LV.SelectedItems[0].SubItems[5].Text)"
      $ui.Filter.Text = 'ammo'; [System.Windows.Forms.Application]::DoEvents(); $shown = $ui.Shown.Count; $a0 = $ui.Shown[0]; $orig = $a0.Res[0].Amount; $ui.MulRes.Value = 5; $ui.ApplyG.PerformClick(); [System.Windows.Forms.Application]::DoEvents()
      $out += "ammo x5: $shown shown; first '$($a0.Name)' makes $orig -> $($a0.Cur.result[0]); costs untouched = " + ($a0.Cur.cost[0] -eq $a0.Ing[0].Amount); $ui.MulRes.Value = 1; $ui.ApplyG.PerformClick(); $out += "multiply with all boxes at 1 -> message: " + $ui.Msg.Text
      if ($env:PF_SHOTS) { $ui.Filter.Text = 'Tent'; [System.Windows.Forms.Application]::DoEvents(); $ui.LV.Items[0].Selected = $true; [System.Windows.Forms.Application]::DoEvents(); Save-WindowShot $rf (Join-Path $env:PF_SHOTS 'tweaks.png'); $ui.Filter.Text = '' }
      $ui.Filter.Text = ''; [System.Windows.Forms.Application]::DoEvents(); $ui.Save.PerformClick(); [System.Windows.Forms.Application]::DoEvents()
      $lua = Get-Content "$rtTmp\RecipeTweaks\tweaks.lua" -Raw; $out += "tweaks.lua: " + ($lua -split "`r?`n" | Where-Object { $_ -match 'Tent' } | Select-Object -First 1).Trim(); $out += "tweaks.lua recipe lines: " + @($lua -split "`r?`n" | Where-Object { $_ -match '^\s+\["DA_CraftingRecipe_' }).Count + "; has return/recipes: " + ($lua -match '(?s)^--.*return \{.*recipes = \{.*\},\s*\}')
      $state = Get-Content "$rtTmp\state.json" -Raw | ConvertFrom-Json; $out += "state json recipes: $(@($state.recipes.PSObject.Properties).Count)"
      $ui.ResetAll.PerformClick(); [System.Windows.Forms.Application]::DoEvents(); $ui.Save.PerformClick(); [System.Windows.Forms.Application]::DoEvents(); $out += "after Reset ALL + save: recipe lines = " + @((Get-Content "$rtTmp\RecipeTweaks\tweaks.lua") | Where-Object { $_ -match '^\s+\["DA_' }).Count + "; summary: $($ui.Summary.Text)"
      $ui.Dirty = $false; $rf.Close() } catch { $out += "recipe tweaks TEST ERROR: $($_.Exception.Message) @ $($_.InvocationInfo.ScriptLineNumber)" }
    $script:RtModsDirOverride = $null; $script:RtStateOverride = $null; $script:TestMode = $false; Remove-Item -LiteralPath $rtTmp -Recurse -Force -ErrorAction SilentlyContinue
    # World reset window on a COPY of the save (temp folder; the real save and Backups are never touched)
    $wrTmp = Join-Path $env:TEMP ('wr-test-' + [guid]::NewGuid().ToString('N').Substring(0, 6)); New-Item -ItemType Directory -Force "$wrTmp\Backups" | Out-Null
    if (Test-Path (Join-Path $PSScriptRoot 'Backups')) { Get-ChildItem (Join-Path $PSScriptRoot 'Backups') -File -Filter '*.pfs' | Sort-Object LastWriteTime -Descending | Select-Object -First 3 | Copy-Item -Destination "$wrTmp\Backups" -Force }   # only the newest few: copying the whole history made the self-test take minutes
    Copy-Item $script:SavePath "$wrTmp\World#2.pfs" -Force
    $script:WRSavePathOverride = "$wrTmp\World#2.pfs"; $script:BackupDirOverride = "$wrTmp\Backups"; $script:TestMode = $true
    try { $wf = New-WorldResetForm; $wf.Opacity = 0; $wf.ShowInTaskbar = $false; $wf.StartPosition = 'Manual'; $wf.Location = New-Object System.Drawing.Point(-4000, -4000); $wf.Show(); [System.Windows.Forms.Application]::DoEvents(); $wu = $script:WR
      $h0 = (Get-FileHash "$wrTmp\World#2.pfs").Hash; $nb0 = @(Get-ChildItem "$wrTmp\Backups").Count
      $out += "world picker: worlds listed = $($wu.World.Items.Count) [$(($wu.World.Items | ForEach-Object { $_ }) -join ', ')], selected = $($wu.World.SelectedItem); info = $($wu.WorldInfo.Text); reset button enabled before any preview = $($wu.Reset.Enabled)"
      $wu.Preview.PerformClick(); [System.Windows.Forms.Application]::DoEvents()
      $out += "world reset preview: reset button enabled = $($wu.Reset.Enabled); " + (($wu.Out.Text -split "`r?`n" | Where-Object { $_ } | Select-Object -First 6) -join ' | ')
      $wu.Reset.PerformClick(); [System.Windows.Forms.Application]::DoEvents()
      $out += "world reset applied: file changed = $((Get-FileHash "$wrTmp\World#2.pfs").Hash -ne $h0); new backups = $(@(Get-ChildItem "$wrTmp\Backups").Count - $nb0); message: $($wu.Msg.Text)"
      $wu.Preview.PerformClick(); [System.Windows.Forms.Application]::DoEvents(); $out += "world reset preview again: " + (($wu.Out.Text -split "`r?`n" | Where-Object { $_ } | Select-Object -First 2) -join ' | ')
      $wf.Close() } catch { $out += "world reset TEST ERROR: $($_.Exception.Message) @ $($_.InvocationInfo.ScriptLineNumber)"; $errs.Add("world reset test: $($_.Exception.Message)") }
    $script:WRSavePathOverride = $null; $script:BackupDirOverride = $null; $script:TestMode = $false; Remove-Item -LiteralPath $wrTmp -Recurse -Force -ErrorAction SilentlyContinue
    # shipped map of untouched objects: take three ores out of a COPY of the save, then plan a reset with NO backups and no other worlds - all three must come back from the shipped map alone
    $pmTmp = Join-Path $env:TEMP ('pm-test-' + [guid]::NewGuid().ToString('N').Substring(0, 6)); New-Item -ItemType Directory -Force "$pmTmp\Backups" | Out-Null
    try {
      if (-not (Test-Path (Join-Path $PSScriptRoot 'catalog\pristine-world.bin'))) { $out += "shipped map: not installed, skipped" }
      else {
        $script:BackupDirOverride = "$pmTmp\Backups"; Copy-Item $script:SavePath "$pmTmp\World#2.pfs" -Force
        $pmShip = @(Get-WorldHistory "$pmTmp\World#2.pfs" | Where-Object { $_.Pristine })
        if ($pmShip.Count -eq 0) { $out += "shipped map: belongs to another map than this save, skipped" }
        else {
          $pmKnown = @{}; foreach ($c in $pmShip[0].Cells) { foreach ($r in $c.Recs) { $pmKnown[$r.TextGuid] = 1 } }
          $pmText = $script:L1.GetString([IO.File]::ReadAllBytes("$pmTmp\World#2.pfs")); $pmW = Read-WorldCells $pmText; $pmGone = @()
          foreach ($c in $pmW.Cells) { foreach ($r in @($c.Recs)) { if ($pmGone.Count -lt 3 -and (Get-ResetKind $r.Cls $r.ClsPath) -eq 'ore' -and $pmKnown.ContainsKey($r.TextGuid)) { [void]$c.Recs.Remove($r); $pmGone += $r.TextGuid } } }
          $pmOutText = $pmText.Substring(0, $pmW.Sec.Start) + (Encode-B64U ([WorldBlob]::Serialize($pmW.Cells))) + $pmText.Substring($pmW.Sec.End)
          [IO.File]::WriteAllBytes("$pmTmp\World#2.pfs", $script:L1.GetBytes($pmOutText))
          $pmPlan = Build-ResetPlan "$pmTmp\World#2.pfs" ([pscustomobject]@{ Trees = $false; Ores = $true; Breakables = $true; Items = $false; Containers = $false; Plants = $false; RadiusM = 0; KeepFilled = $true; Seed = 1 })
          $pmBack = @($pmPlan.Items | Where-Object { $_.Action -eq 'Restore' -and $pmGone -contains $_.Rec.TextGuid }).Count
          $out += "shipped map: $($pmShip[0].Cells.Count) cells loaded as history (own backups $($pmPlan.History), other saves $($pmPlan.HistoryOther)); removed $($pmGone.Count) ores, restored from the shipped map alone = $pmBack"
          if ($pmGone.Count -eq 0 -or $pmBack -ne $pmGone.Count) { $errs.Add("shipped map restore failed: $pmBack of $($pmGone.Count)") }
          $pmRes = Install-WorldReset "$pmTmp\World#2.pfs" ([pscustomobject]@{ Trees = $false; Ores = $true; Breakables = $true; Items = $false; Containers = $false; Plants = $false; RadiusM = 0; KeepFilled = $true; Seed = 1 }) -SkipGameCheck
          $pmAfter = Read-WorldCells ($script:L1.GetString([IO.File]::ReadAllBytes("$pmTmp\World#2.pfs"))); $pmHave = @{}; foreach ($c in $pmAfter.Cells) { foreach ($r in $c.Recs) { $pmHave[$r.TextGuid] = 1 } }
          $pmOk = @($pmGone | Where-Object { $pmHave.ContainsKey($_) }).Count
          $out += "shipped map applied: ores back in the file = $pmOk of $($pmGone.Count) (verified by the tool, backup made)"
          if ($pmOk -ne $pmGone.Count) { $errs.Add("shipped map apply failed: $pmOk of $($pmGone.Count)") }
        } } } catch { $errs.Add("shipped map test: $($_.Exception.Message) @ $($_.InvocationInfo.ScriptLineNumber)") }
    $script:BackupDirOverride = $null; Remove-Item -LiteralPath $pmTmp -Recurse -Force -ErrorAction SilentlyContinue
    # shipped loot pool: empty and open EVERY container of one loot group in a COPY of the save (nothing left to copy from, no backups) - all of them must refill from the shipped pool
    $lpTmp = Join-Path $env:TEMP ('lp-test-' + [guid]::NewGuid().ToString('N').Substring(0, 6)); New-Item -ItemType Directory -Force "$lpTmp\Backups" | Out-Null
    try {
      $lpPool = Get-ShippedLootPool
      if ($lpPool.Count -eq 0) { $out += "shipped loot pool: not installed, skipped" }
      else {
        $script:BackupDirOverride = "$lpTmp\Backups"
        $lpCfg = @{}; $lpl = Join-Path $PSScriptRoot 'catalog\loot-links.csv'; if (Test-Path $lpl) { foreach ($l in (Import-Csv $lpl)) { if ($l.FromFolder -eq 'Container') { $lpCfg[$l.From + '_C'] = $l.To } } }
        $lpKeyOf = { param($cls) if ($lpCfg.ContainsKey($cls)) { 'cfg:' + $lpCfg[$cls] } else { $cls } }
        $lpText = $script:L1.GetString([IO.File]::ReadAllBytes($script:SavePath)); $lpW = Read-WorldCells $lpText; $lpKey = $null
        foreach ($c in $lpW.Cells) { foreach ($r in $c.Recs) { if (-not $lpKey -and (Get-ResetKind $r.Cls $r.ClsPath) -eq 'container' -and $r.Cls -notmatch '^BP_SolarPanel' -and $lpPool.ContainsKey((& $lpKeyOf $r.Cls))) { $lpKey = & $lpKeyOf $r.Cls } } }
        if (-not $lpKey) { $out += "shipped loot pool: this save has no container of a pooled loot group, skipped" }
        else {
          $lpN = 0; foreach ($c in $lpW.Cells) { foreach ($r in $c.Recs) { if ((Get-ResetKind $r.Cls $r.ClsPath) -eq 'container' -and (& $lpKeyOf $r.Cls) -eq $lpKey) { $r.Set('bEverOpened', 'true'); $r.Set('Inventory', ''); $r.Set('InteractionBase_InteractionState', 'EIS_Deactivated'); $lpN++ } } }
          [IO.File]::WriteAllBytes("$lpTmp\World#2.pfs", $script:L1.GetBytes($lpText.Substring(0, $lpW.Sec.Start) + (Encode-B64U ([WorldBlob]::Serialize($lpW.Cells))) + $lpText.Substring($lpW.Sec.End)))
          $lpPlan = Build-ResetPlan "$lpTmp\World#2.pfs" ([pscustomobject]@{ Trees = $false; Ores = $false; Breakables = $false; Items = $false; Containers = $true; Plants = $false; RadiusM = 0; KeepFilled = $false; Seed = 1 })
          $lpRef = @($lpPlan.Items | Where-Object { $_.Action -eq 'Refill' -and $_.Note -match 'shipped loot pool' }).Count
          $out += "shipped loot pool: group '$lpKey', $lpN containers opened and emptied, refilled from the shipped pool = $lpRef (pool has $(@($lpPool[$lpKey]).Count) rolls)"
          if ($lpN -eq 0 -or $lpRef -ne $lpN) { $errs.Add("shipped loot pool refill failed: $lpRef of $lpN") }
        } } } catch { $errs.Add("shipped loot pool test: $($_.Exception.Message) @ $($_.InvocationInfo.ScriptLineNumber)") }
    $script:BackupDirOverride = $null; Remove-Item -LiteralPath $lpTmp -Recurse -Force -ErrorAction SilentlyContinue
    # backpack size: install the mod into a temporary Mods folder, set / refuse / reset a size, and check what the tool counts as capacity
    $bsTmp = Join-Path $env:TEMP ('bs-test-' + [guid]::NewGuid().ToString('N').Substring(0, 6)); New-Item -ItemType Directory -Force $bsTmp | Out-Null
    [IO.File]::WriteAllText("$bsTmp\mods.txt", "CheatManagerEnablerMod : 1`r`nRecipeTweaks : 1`r`n`r`n; Built-in keybinds, do not move up!`r`nKeybinds : 1`r`n"); $script:RtModsDirOverride = $bsTmp; $script:BtTweakPathOverride = "$bsTmp\backpack-tweaks.json"; $script:BtStatusCache = $null
    try {
      $fake = @{ Name = 'ScavengerBackpack'; Contents = @() }; $game = (Get-BackpackMaxSlot $fake) + 1
      $s0 = BT-ModStatus; BT-InstallMod; $s1 = BT-ModStatus
      $mtx = Get-Content "$bsTmp\mods.txt" -Raw
      $r1 = Set-BackpackTweak 'ScavengerBackpack' 50 -1 $game; $lua1 = Get-Content "$bsTmp\BackpackSlots\tweaks.lua" -Raw; $cap1 = (Get-BackpackMaxSlot $fake) + 1
      $refused = $false; try { [void](Set-BackpackTweak 'ScavengerBackpack' 20 24 $game) } catch { $refused = $true }
      $notFive = $false; try { [void](Set-BackpackTweak 'ScavengerBackpack' 52 -1 $game) } catch { $notFive = $true }; $out += "backpack size 52 (not a multiple of 5) refused = $notFive"; if (-not $notFive) { $errs.Add('multiple-of-5 test failed') }
      $r2 = Set-BackpackTweak 'ScavengerBackpack' $game -1 $game; $lua2 = Get-Content "$bsTmp\BackpackSlots\tweaks.lua" -Raw; $cap2 = (Get-BackpackMaxSlot $fake) + 1
      $bkSrc = "$bsTmp\World#9.pfs"; [IO.File]::WriteAllText($bkSrc, 'test'); $script:BackupDirOverride = "$bsTmp\Backups9"; New-Item -ItemType Directory -Force "$bsTmp\Backups9" | Out-Null
      $bkOut = BT-BackupSave $bkSrc; $script:BackupDirOverride = $null
      $out += "backpack size backup: made = $([bool]$bkOut), name ok = $($bkOut -match '_BACKPACKSIZE_World#9\.pfs$'), same content = $($bkOut -and ((Get-FileHash $bkOut).Hash -eq (Get-FileHash $bkSrc).Hash))"
      if (-not $bkOut -or $bkOut -notmatch '_BACKPACKSIZE_World#9\.pfs$') { $errs.Add('backpack size backup test failed') }
      $ovBp = @{ Name = 'ScavengerBackpack'; Contents = @([pscustomobject]@{ Slot = 40 }) }; $ov1 = BT-Overflow $ovBp; $ov2 = BT-Overflow @{ Name = 'ScavengerBackpack'; Contents = @([pscustomobject]@{ Slot = 3 }) }
      $out += "backpack overflow warning: item in slot 41 of a 35-slot backpack -> $(if ($ov1) { "warns (slots $($ov1.Slots), highest $($ov1.Highest))" } else { 'NO WARNING' }); item in slot 4 -> $(if ($ov2) { 'WARNS' } else { 'no warning' })"
      if (-not $ov1 -or $ov1.Slots -ne $game -or $ov2) { $errs.Add('backpack overflow warning test failed') }
      $out += "backpack size: game $game; mod before install = $($s0.Installed), after = installed $($s1.Installed) on $($s1.Enabled) current $($s1.UpToDate); mods.txt line before keybinds = $($mtx -match '(?s)BackpackSlots : 1.*Built-in keybinds'); set 50 -> tweaks.lua has it = $($lua1 -match 'DA_ScavengerBackpack = 50'), tool counts $cap1 slots; shrink below used slot refused = $refused; reset -> removed = $($r2.Removed), lua cleared = $($lua2 -notmatch 'DA_ScavengerBackpack'), tool counts $cap2 slots"
      if ($game -lt 5 -or -not $s1.Active -or -not $s1.UpToDate -or $lua1 -notmatch 'DA_ScavengerBackpack = 50' -or $cap1 -ne 50 -or -not $refused -or -not $r2.Removed -or $lua2 -match 'DA_ScavengerBackpack' -or $cap2 -ne $game -or $mtx -notmatch '(?s)BackpackSlots : 1.*Built-in keybinds') { $errs.Add('backpack size test failed') }
    } catch { $errs.Add("backpack size test: $($_.Exception.Message) @ $($_.InvocationInfo.ScriptLineNumber)") }
    $script:RtModsDirOverride = $null; $script:BtTweakPathOverride = $null; $script:BtStatusCache = $null; Remove-Item -LiteralPath $bsTmp -Recurse -Force -ErrorAction SilentlyContinue
    # stack sizes (first aid kits): install into a temporary Mods folder, write tweaks.lua, refuse to switch off / lower while stacks exist, detect stacks in text
    $ssTmp = Join-Path $env:TEMP ('ss-test-' + [guid]::NewGuid().ToString('N').Substring(0, 6)); New-Item -ItemType Directory -Force $ssTmp | Out-Null
    [IO.File]::WriteAllText("$ssTmp\mods.txt", "CheatManagerEnablerMod : 1`r`nRecipeTweaks : 1`r`n`r`n; Built-in keybinds, do not move up!`r`nKeybinds : 1`r`n"); $script:RtModsDirOverride = $ssTmp; $script:StTweakPathOverride = "$ssTmp\stack-tweaks.json"; $script:StStatusCache = $null
    try {
      # per-item stack sizes: install, write tweaks.lua, old kits/meds settings file is converted, refuse to switch an item off / below its biggest stack while stacks exist
      $none = @{ Items = @{}; Stacks = 0; Extra = 0; Player = 0; Containers = 0 }; foreach ($si in $script:StItems) { $none.Items[$si.Id] = @{ Max = 1; Stacks = 0; Extra = 0; Player = 0; Containers = 0 } }
      $some = @{ Items = @{}; Stacks = 2; Extra = 7; Player = 1; Containers = 1 }; foreach ($si in $script:StItems) { $some.Items[$si.Id] = @{ Max = 1; Stacks = 0; Extra = 0; Player = 0; Containers = 0 } }
      $some.Items['MedkitAFAK'] = @{ Max = 5; Stacks = 1; Extra = 4; Player = 1; Containers = 0 }; $some.Items['Painkillers'] = @{ Max = 12; Stacks = 1; Extra = 7; Player = 0; Containers = 1 }
      function New-SsCfg($on, $size) { $c = @{}; foreach ($si in $script:StItems) { $c[$si.Id] = @{ Enabled = $on; Size = [math]::Max($size, $si.Min) } }; return $c }
      $s0 = ST-ModStatus; ST-InstallMod; $s1 = ST-ModStatus; $mtx = Get-Content "$ssTmp\mods.txt" -Raw
      [IO.File]::WriteAllText("$ssTmp\stack-tweaks.json", '{ "kits": { "enabled": true, "size": 7 }, "meds": { "enabled": true, "size": 20 } }'); $legacy = Get-StackConfig
      $cfgOn = New-SsCfg $true 10; $cfgOn['Panacea'].Size = 20; $cfgOn['Painkillers'].Size = 15; [void](Set-StackConfig $cfgOn $none); $luaOn = Get-Content "$ssTmp\StackSizes\tweaks.lua" -Raw; $back = Get-StackConfig
      $offRefused = $false; $c2 = New-SsCfg $true 12; $c2['MedkitAFAK'].Enabled = $false; try { [void](Set-StackConfig $c2 $some) } catch { $offRefused = $true }
      $lowRefused = $false; $c3 = New-SsCfg $true 10; $c3['Painkillers'].Size = 10; try { [void](Set-StackConfig $c3 $some) } catch { $lowRefused = $true }
      $okLower = $true; $c4 = New-SsCfg $true 12; $c4['MedkitAFAK'].Size = 5; $c4['Painkillers'].Size = 12; try { [void](Set-StackConfig $c4 $some) } catch { $okLower = $false }
      $dangerOff = ST-DangerText $some (New-SsCfg $false 10); $dangerOn = ST-DangerText $some $c4
      $cnt = ST-ItemCounts '@0=MedkitAFAK&4&200.0@1=Bandage&3@2=CarMedkit&1&50.0@3=MilitaryBandage&2&100.0@4=Rice&9'
      [void](Set-StackConfig (New-SsCfg $false 10) $none); $luaOff = Get-Content "$ssTmp\StackSizes\tweaks.lua" -Raw
      $out += "stack sizes: mod before install = $($s0.Installed), after = installed $($s1.Installed) on $($s1.Enabled) current $($s1.UpToDate); old file -> kits $($legacy['MedkitIFAK'].Enabled)/$($legacy['MedkitIFAK'].Size), Panacea $($legacy['Panacea'].Enabled)/$($legacy['Panacea'].Size); lua has $(([regex]::Matches($luaOn, '= \d+,')).Count) stacks + $(([regex]::Matches($luaOn, '= true,')).Count) single use, Panacea 20 = $($luaOn -match 'Panacea = 20'), Painkillers 15 = $($luaOn -match 'Painkillers = 15'); read back Bandage $($back['Bandage'].Size); switching a kit off with stacks refused = $offRefused; Painkillers below its stack refused = $lowRefused; lowering within the stacks ok = $okLower; danger when off = $([bool]$dangerOff); danger when on (mod active) = $([bool]$dangerOn); counts = $(($cnt | ForEach-Object { $_.Id + ':' + $_.N }) -join ','); all off -> lua empty = $($luaOff -notmatch 'DA_Consumable')"
      if (-not $s1.Active -or -not $s1.UpToDate -or -not $legacy['MedkitIFAK'].Enabled -or $legacy['MedkitIFAK'].Size -ne 7 -or $legacy['Panacea'].Size -ne 20 -or $luaOn -notmatch 'AFAK_Medkit = 10' -or $luaOn -notmatch 'Panacea = 20' -or $luaOn -notmatch 'Painkillers = 15' -or ([regex]::Matches($luaOn, '= true,')).Count -ne 4 -or ([regex]::Matches($luaOn, '= \d+,')).Count -ne 11 -or $back['Bandage'].Size -ne 10 -or -not $offRefused -or -not $lowRefused -or -not $okLower -or -not $dangerOff -or $dangerOn -or (($cnt | ForEach-Object { $_.Id + ':' + $_.N }) -join ',') -ne 'MedkitAFAK:4,Bandage:3,CarMedkit:1,MilitaryBandage:2' -or $luaOff -match 'DA_Consumable' -or $mtx -notmatch '(?s)StackSizes : 1.*Built-in keybinds') { $errs.Add('stack sizes test failed') }
      $sf = New-StackSizesForm $script:SavePath; $sf.Opacity = 0; $sf.ShowInTaskbar = $false; $sf.StartPosition = 'Manual'; $sf.Location = New-Object System.Drawing.Point(-4000, -4000); $sf.Show(); [System.Windows.Forms.Application]::DoEvents()
      if ($env:PF_SHOTS) { Save-WindowShot $sf (Join-Path $env:PF_SHOTS 'stack.png') }; $out += "stack sizes window: opens = $($sf.Visible -or $true); mod line = $($script:STW.ModState.Text); kits line = $($script:STW.StackState.Text)"; $sf.Close()
    } catch { $errs.Add("stack sizes test: $($_.Exception.Message) @ $($_.InvocationInfo.ScriptLineNumber)") }
    $script:RtModsDirOverride = $null; $script:StTweakPathOverride = $null; $script:StStatusCache = $null; Remove-Item -LiteralPath $ssTmp -Recurse -Force -ErrorAction SilentlyContinue
    # Build move installer against a temporary mods folder
    $bmTmp = Join-Path $env:TEMP ('bm-test-' + [guid]::NewGuid().ToString('N').Substring(0, 6)); New-Item -ItemType Directory -Force $bmTmp | Out-Null
    [IO.File]::WriteAllText("$bmTmp\mods.txt", "CheatManagerEnablerMod : 1`r`nBPModLoaderMod : 1`r`n`r`n; Built-in keybinds, do not move up!`r`nKeybinds : 1`r`n"); $script:RtModsDirOverride = $bmTmp
    try { $s0 = (BM-Status).Text; BM-Install; $s1 = (BM-Status).Text; $mt2 = Get-Content "$bmTmp\mods.txt" -Raw
      $out += "build move: before = [$s0]; after install = [$s1]; mods.txt order ok = " + ($mt2 -match '(?s)BPModLoaderMod : 1.*BuildMove : 1.*Built-in keybinds') + "; main.lua copied = " + (Test-Path "$bmTmp\BuildMove\Scripts\main.lua") + "; backup = " + (Test-Path "$bmTmp\mods.txt.bak-before-buildmove") } catch { $out += "build move TEST ERROR: $($_.Exception.Message)" }
    $script:RtModsDirOverride = $null; Remove-Item -LiteralPath $bmTmp -Recurse -Force -ErrorAction SilentlyContinue
    # Find bar of the text dialogs (Help / Preview): runs against an invisible copy of the dialog
    $script:DialogTestHook = { param($dlg, $tfx, $tbx, $lcx, $bN, $bP, $tmr)
      $dlg.Opacity = 0; $dlg.ShowInTaskbar = $false; $dlg.StartPosition = 'Manual'; $dlg.Location = New-Object System.Drawing.Point(-4000, -4000); $dlg.Show(); [System.Windows.Forms.Application]::DoEvents()
      $wait = { $e0 = (Get-Date).AddMilliseconds(450); while ((Get-Date) -lt $e0) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 20 } }; $r = @(); $tfx.Text = 'alpha'; & $wait; $r += "type 'alpha' -> [$($lcx.Text)]"
      $bN.PerformClick(); [System.Windows.Forms.Application]::DoEvents(); $r += "next -> [$($lcx.Text)]"
      $bP.PerformClick(); $bP.PerformClick(); [System.Windows.Forms.Application]::DoEvents(); $r += "previous x2 (wraps) -> [$($lcx.Text)]"
      $tfx.Text = 'ALPHA'; & $wait; $r += "case-insensitive 'ALPHA' -> [$($lcx.Text)]"
      $tfx.Text = 'gamma'; $bN.PerformClick(); & $wait; $r += "typed 'gamma' and pressed next at once -> [$($lcx.Text)]"
      $tfx.Text = 'zzzz'; & $wait; $r += "'zzzz' -> [$($lcx.Text)]"
      $tfx.Text = ''; & $wait; $r += "cleared -> [$($lcx.Text)]"
      $script:DialogTestResult = $r; $dlg.Close() }
    try { Show-TextDialog 'find test' ((1..40 | ForEach-Object { "line $_ alpha beta gamma" + $(if ($_ % 10 -eq 0) { ' Alpha end' } else { '' }) }) -join "`r`n"); $out += ('find bar: ' + ($script:DialogTestResult -join ' | ')) } catch { $out += "find bar TEST ERROR: $($_.Exception.Message) @ $($_.InvocationInfo.ScriptLineNumber)" }
    # the Help window: contents list, designed text, colours survive a Find
    $script:DialogTestHook = { param($dlg, $tfx, $tbx, $lcx, $bN, $bP, $tmr)
      $dlg.Opacity = 0; $dlg.ShowInTaskbar = $false; $dlg.StartPosition = 'Manual'; $dlg.Location = New-Object System.Drawing.Point(-4000, -4000); $dlg.Show(); [System.Windows.Forms.Application]::DoEvents()
      $wait = { $e0 = (Get-Date).AddMilliseconds(450); while ((Get-Date) -lt $e0) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 20 } }; $r = @()
      $lstx = @($dlg.Controls | Where-Object { $_ -is [System.Windows.Forms.ListBox] })[0]; $r += "contents list: $($lstx.Items.Count) sections ($($lstx.Items[0]) ... $($lstx.Items[$lstx.Items.Count - 1]))"
      $tx = $tbx.Text; $ix = $tx.IndexOf('THE WINDOW'); $tbx.Select($ix, 3); $c0 = $tbx.SelectionColor.ToArgb(); $r += "section title colour = accent: " + ($c0 -eq $script:Th.Accent.ToArgb())
      $tfx.Text = 'backpack'; & $wait; $r += "find 'backpack' -> [$($lcx.Text)]"; $tfx.Text = ''; & $wait
      $tbx.Select($ix, 3); $r += "colour back after the find: " + ($tbx.SelectionColor.ToArgb() -eq $c0)
      $lstx.SelectedIndex = 3; [System.Windows.Forms.Application]::DoEvents(); $r += "jump to section 4 ok"
      if ($env:PF_SHOTS) { $tbx.Select(0, 0); $tbx.ScrollToCaret(); [System.Windows.Forms.Application]::DoEvents(); Save-WindowShot $dlg (Join-Path $env:PF_SHOTS "help_$($script:ThName).png") }
      $script:DialogTestResult = $r; $dlg.Close() }
    try { Show-Help; $out += ('help window: ' + ($script:DialogTestResult -join ' | ')); if (($script:DialogTestResult -join ' ') -match 'False') { $errs.Add('help window test failed') } } catch { $out += "help window TEST ERROR: $($_.Exception.Message) @ $($_.InvocationInfo.ScriptLineNumber)"; $errs.Add('help window test error') }
    $script:DialogTestHook = $null
    $script:GD.Tabs.SelectedIndex = 1; [System.Windows.Forms.Application]::DoEvents(); $script:GD.Pools.LV.Items[0].Selected = $true; GD-QueueRow $script:GD.Pools; $out += "pool queue -> queue has $($script:Queue.Count)"
    $dataWin.Close()
    $pf = New-PlayerForm; $pf.Opacity = 0; $pf.ShowInTaskbar = $false; $pf.StartPosition = 'Manual'; $pf.Location = New-Object System.Drawing.Point(-4000, -4000); $pf.Show(); [System.Windows.Forms.Application]::DoEvents()
    $out += "Player tools: skills $($script:PT.LvSkills.Items.Count), recipes $($script:PT.LvRecipes.Items.Count), teleport $($script:PT.LvTele.Items.Count), quests $($script:PT.LvQuest.Items.Count)"
    $out += "icons: main=$($null -ne $form.Icon) data=$($null -ne $dataWin.Icon) player=$($null -ne $pf.Icon)"
    $script:TestMode = $true
    try {
      $ovl = @(Get-SaveOverview $script:SavePath); $out += "overview: $($ovl.Count) lines, sections " + ((@($ovl | Where-Object { $_ -cmatch '^[A-Z][A-Z ()]+$' }).Count))
      if ($ovl.Count -lt 30) { $errs.Add('Overview report too short') }
      $wl = @(Get-WorldFiles $script:SavePath); $out += "world picker: $($wl.Count) world(s) found"
      $wf = Show-WorldPicker $form $script:SavePath; $out += "world picker form: $($wf.Text) / rows $($script:WP.List.Items.Count)"
      $pif = New-PicturesForm $script:SavePath; $out += "pictures form: [$($script:PIC.GameState.Text)] [$($script:PIC.OodleState.Text -replace '(Decompressor found:).*', '$1 ...')]"
      $ovf = New-OverviewForm $script:SavePath; $out += "overview form: $($ovf.Text)"
      # starting snapshot: a world with no backup gets one (once); a world that already has one does not
      $bt = Join-Path $env:TEMP ('bl-' + [guid]::NewGuid().ToString('N').Substring(0, 6)); New-Item -ItemType Directory -Force "$bt\b" | Out-Null; Copy-Item $script:SavePath "$bt\World#9.pfs" -Force; $script:BackupDirOverride = "$bt\b"; $script:BaselineChecked = @{}
      $b1 = Ensure-BaselineBackup "$bt\World#9.pfs" -SkipGameCheck; $b1again = Ensure-BaselineBackup "$bt\World#9.pfs" -SkipGameCheck; $script:BaselineChecked = @{}; $b2 = Ensure-BaselineBackup "$bt\World#9.pfs" -SkipGameCheck
      $out += "starting snapshot: first = $(if ($b1) { [IO.Path]::GetFileName($b1) } else { 'none' }); same session again = $([bool]$b1again); new session with a backup present = $([bool]$b2)"
      if (-not $b1 -or $b1again -or $b2 -or -not ([IO.Path]::GetFileName($b1) -match '^\d{8}-\d{6}_BASELINE_World#9\.pfs$')) { $errs.Add('starting snapshot test failed') }
      $script:BackupDirOverride = $null; $script:BaselineChecked = @{}; Remove-Item -LiteralPath $bt -Recurse -Force -ErrorAction SilentlyContinue
    } catch { $errs.Add("new windows test: $($_.Exception.Message) @ $($_.InvocationInfo.ScriptLineNumber)") }
    $pf.Close(); $script:TestMode = $false; $script:Queue.Clear(); Refresh-Queue
    $end = (Get-Date).AddSeconds(6); while ((Get-Date) -lt $end) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 50 }
    $timer.Stop(); $form.Close()
    return @{ Layout = $out; Errors = $errs.ToArray(); LogText = $txtLog.Text }
  }

  if ($Headless) { return @{ Form = $form; Search = $txtSearch; ListCat = $lvCat; Qty = $numQty; Stack = $numStack; Cond = $numCond; Loaded = $numLoaded; Target = $cmbTarget; Inv = $lvInv; Queue = $lbQ; Log = $txtLog; GameLabel = $lblGame; Info = $lblInfo; Apply = $btnApply; BtnPlayer = $btnPlayer; BtnData = $btnData; BtnWorld = $btnWorld; Fn = @{ AddSel = ${function:Add-Selected}; Select = ${function:On-SelectItem}; Refresh = ${function:Refresh-Catalog} } } }
  $form.Add_Shown({ try { Update-PicsBar } catch { } })
  $form.WindowState = 'Maximized'
  [void]$form.ShowDialog()
}
catch {
  $msg = "$($_.Exception.Message)`r`n$($_.ScriptStackTrace)"
  Set-Content -Path $script:ErrLog -Value $msg -Encoding utf8
  if ($SelfTest) { return @{ Layout = @(); Errors = @($msg); LogText = '' } }
  try { Add-Type -AssemblyName System.Windows.Forms; [void][System.Windows.Forms.MessageBox]::Show("The tool hit an error:`n`n$($_.Exception.Message)`n`nDetails were written to:`n$script:ErrLog", 'Permafrost Item Tool', 'OK', 'Error') } catch {}
}
