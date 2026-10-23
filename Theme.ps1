# Theme.ps1 - colour palettes applied to every window of the tool. The header shows the title as plain text (add your own assets\logo.png / assets\art_*.jpg if you like).
# $script:Th holds the active palette (System.Drawing.Color values). Set-Theme picks one, Apply-Theme paints a control tree.
Add-Type -AssemblyName System.Windows.Forms; Add-Type -AssemblyName System.Drawing
$script:ThemeRefs = [AppDomain]::CurrentDomain.GetAssemblies() | Where-Object { -not $_.IsDynamic -and $_.Location } | ForEach-Object { $_.Location } | Select-Object -Unique
if (-not ('ThemedTabs' -as [type])) {
  Add-Type -ReferencedAssemblies $script:ThemeRefs -TypeDefinition @'
using System; using System.Drawing; using System.Windows.Forms;
public class ThemedTabs : TabControl {
  public Color BackC = Color.FromArgb(18,23,31), PageC = Color.FromArgb(34,40,50), TextC = Color.White, AccentC = Color.SteelBlue, MutedC = Color.Gray;
  public ThemedTabs() { SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw, true); }
  protected override void OnPaint(PaintEventArgs e) {
    var g = e.Graphics; using (var b = new SolidBrush(BackC)) g.FillRectangle(b, ClientRectangle);
    for (int i = 0; i < TabCount; i++) {
      var r = GetTabRect(i); bool sel = (i == SelectedIndex);
      using (var b = new SolidBrush(sel ? PageC : BackC)) g.FillRectangle(b, r);
      if (sel) using (var p = new Pen(AccentC, 3)) g.DrawLine(p, r.Left, r.Top + 1, r.Right - 1, r.Top + 1);
      TextRenderer.DrawText(g, TabPages[i].Text.Replace("&&", "&"), Font, r, sel ? TextC : MutedC, TextFormatFlags.HorizontalCenter | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine);
    }
  }
}
public class ThemedGroup : GroupBox {
  public Color BorderC = Color.FromArgb(61,72,94), TitleC = Color.White, OuterC = Color.FromArgb(18,23,31);
  public ThemedGroup() { SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer | ControlStyles.ResizeRedraw | ControlStyles.SupportsTransparentBackColor, true); }
  protected override void OnPaint(PaintEventArgs e) {
    var g = e.Graphics; using (var b = new SolidBrush(OuterC)) g.FillRectangle(b, ClientRectangle);
    var sz = TextRenderer.MeasureText(Text, Font); int top = sz.Height / 2;
    var rc = new Rectangle(0, top, Width - 1, Height - top - 1);
    using (var f = new SolidBrush(BackColor)) g.FillRectangle(f, rc);
    using (var p = new Pen(BorderC)) g.DrawRectangle(p, rc);
    if (Text.Length > 0) { using (var b = new SolidBrush(OuterC)) g.FillRectangle(b, 8, 0, sz.Width + 4, sz.Height);
      TextRenderer.DrawText(g, Text, Font, new Point(10, 0), TitleC, TextFormatFlags.NoPadding); }
  }
}
'@
}

function C([string]$hex) { [System.Drawing.ColorTranslator]::FromHtml($hex) }
# Palettes: charcoal panels #12171F/#222832/#2E333F, steel #3D485E, frost #5A99D5/#85BEE3, sunset amber #F8AD41, off-white #DAE1E8
$script:PaletteDefs = [ordered]@{
  'Frostbite' = @{ Dark = $true; Art = 'art_frost.jpg'; Back = '#12171F'; Panel = '#1B222C'; Field = '#161B23'; Button = '#2E333F'; ButtonHot = '#3D485E'; Border = '#3D485E'; Text = '#DAE1E8'; Muted = '#8E9AAD'; Accent = '#5A99D5'; Accent2 = '#85BEE3'; AccentText = '#0B1118'; Good = '#6FD3A0'; Bad = '#FF7B7B'; Warn = '#F8AD41'; Select = '#2F4A66'; Header = '#2A3342' }
  'Dusk'      = @{ Dark = $true; Art = 'art_dusk.jpg'; Back = '#1A141E'; Panel = '#231C2A'; Field = '#1E1824'; Button = '#382A3A'; ButtonHot = '#4D3A50'; Border = '#4D3A50'; Text = '#EDE4EC'; Muted = '#A593A8'; Accent = '#F8AD41'; Accent2 = '#F8C77A'; AccentText = '#1A1006'; Good = '#8FD694'; Bad = '#FF7B7B'; Warn = '#FFB324'; Select = '#5A3F3A'; Header = '#33283A' }
  'Daylight'  = @{ Dark = $false; Art = 'art_day.jpg'; Back = '#DAE1E8'; Panel = '#EEF2F6'; Field = '#FFFFFF'; Button = '#C5CFDA'; ButtonHot = '#B3C1D1'; Border = '#9AABBD'; Text = '#1A212B'; Muted = '#5B6878'; Accent = '#2F6FA8'; Accent2 = '#2F6FA8'; AccentText = '#FFFFFF'; Good = '#1E8A55'; Bad = '#C23B3B'; Warn = '#B8741A'; Select = '#BBD3EA'; Header = '#C5CFDA' }
}
$script:Palettes = @{}
foreach ($k in $script:PaletteDefs.Keys) { $d = $script:PaletteDefs[$k]; $p = @{ Name = $k; Dark = $d.Dark; Art = $d.Art }; foreach ($r in 'Back', 'Panel', 'Field', 'Button', 'ButtonHot', 'Border', 'Text', 'Muted', 'Accent', 'Accent2', 'AccentText', 'Good', 'Bad', 'Warn', 'Select', 'Header') { $p[$r] = C $d[$r] }; $script:Palettes[$k] = $p }
$script:ThemeFile = Join-Path $PSScriptRoot 'theme.json'
$script:ThemeRoles = 'Text', 'Muted', 'Accent', 'Accent2', 'Good', 'Bad', 'Warn', 'Back', 'Panel', 'Field'

function Get-SavedThemeName { try { $n = (Get-Content $script:ThemeFile -Raw | ConvertFrom-Json).name; if ($script:Palettes.Contains($n)) { return $n } } catch { }; return 'Frostbite' }
function Save-ThemeName([string]$n) { try { (@{ name = $n } | ConvertTo-Json) | Set-Content $script:ThemeFile -Encoding utf8 } catch { } }
function Set-Theme([string]$name) { if (-not $script:Palettes.Contains($name)) { $name = 'Frostbite' }; $script:Th = $script:Palettes[$name]; $script:ThName = $name }
Set-Theme (Get-SavedThemeName)

# a colour used by an older theme (or the code's defaults) -> the same role in the active theme
function Map-Color([System.Drawing.Color]$c) {
  if ($c.IsSystemColor -or $c.IsEmpty) { return $null }
  foreach ($pal in $script:Palettes.Values) { foreach ($r in 'Muted', 'Accent', 'Accent2', 'Good', 'Bad', 'Warn', 'Text') { if ($pal[$r].ToArgb() -eq $c.ToArgb()) { return $script:Th[$r] } } }
  return $null
}

function Fit-LastColumn($lv) {
  try { $n = $lv.Columns.Count; if ($n -lt 1 -or $lv.ClientSize.Width -lt 50) { return }; $sum = 0; for ($i = 0; $i -lt $n - 1; $i++) { $sum += $lv.Columns[$i].Width }
    $w = $lv.ClientSize.Width - $sum - 2; if ($w -gt 40) { $lv.Columns[$n - 1].Width = $w } } catch { }
}
if (-not ('PfWin' -as [type])) { Add-Type -Namespace '' -Name PfWin -MemberDefinition '[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool PrintWindow(System.IntPtr hwnd, System.IntPtr hdc, uint flags); [System.Runtime.InteropServices.DllImport("user32.dll")] public static extern System.IntPtr GetDC(System.IntPtr h); [System.Runtime.InteropServices.DllImport("user32.dll")] public static extern int ReleaseDC(System.IntPtr h, System.IntPtr dc); [System.Runtime.InteropServices.DllImport("gdi32.dll")] public static extern int GetDeviceCaps(System.IntPtr dc, int i);' }
function Save-WindowShot($f, [string]$path, [scriptblock]$pre = $null) {
  if ($env:PF_LIVE) {   # real on-screen pixels: show the window for a moment, copy the screen, hide it again
    $oldLoc = $f.Location; $f.Opacity = 1; $f.Location = New-Object System.Drawing.Point(0, 0); $f.TopMost = $true; $f.Activate(); for ($k = 0; $k -lt 12; $k++) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 40 }; if ($pre) { & $pre; for ($k = 0; $k -lt 10; $k++) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 50 } }
    $dc = [PfWin]::GetDC([IntPtr]::Zero); $sc = [PfWin]::GetDeviceCaps($dc, 118) / [double][PfWin]::GetDeviceCaps($dc, 8); [void][PfWin]::ReleaseDC([IntPtr]::Zero, $dc); if ($sc -lt 1) { $sc = 1 }
    $pw = [int]($f.Width * $sc); $ph = [int]($f.Height * $sc); $bmp = New-Object System.Drawing.Bitmap $pw, $ph; $g = [System.Drawing.Graphics]::FromImage($bmp); $g.CopyFromScreen(0, 0, 0, 0, (New-Object System.Drawing.Size($pw, $ph))); $g.Dispose(); $bmp.Save($path); $bmp.Dispose()
    $f.TopMost = $false; $f.Opacity = 0; $f.Location = $oldLoc; [System.Windows.Forms.Application]::DoEvents(); return
  }
  $bmp = New-Object System.Drawing.Bitmap $f.Width, $f.Height; $g = [System.Drawing.Graphics]::FromImage($bmp); $hdc = $g.GetHdc(); [void][PfWin]::PrintWindow($f.Handle, $hdc, 2); $g.ReleaseHdc($hdc); $g.Dispose(); $bmp.Save($path); $bmp.Dispose()
}

function Apply-Theme($ctl) {
  $t = $script:Th
  if ($ctl -is [System.Windows.Forms.Form]) { $ctl.BackColor = $t.Back; $ctl.ForeColor = $t.Text }
  elseif ($ctl -is [ThemedTabs]) { $ctl.BackC = $t.Back; $ctl.PageC = $t.Panel; $ctl.TextC = $t.Text; $ctl.AccentC = $t.Accent; $ctl.MutedC = $t.Muted; $ctl.BackColor = $t.Back; $ctl.Invalidate() }
  elseif ($ctl -is [System.Windows.Forms.TabPage]) { $ctl.BackColor = $t.Panel; $ctl.ForeColor = $t.Text }
  elseif ($ctl -is [ThemedGroup]) { $ctl.BackColor = $t.Panel; $ctl.OuterC = $t.Back; $ctl.BorderC = $t.Border; $ctl.TitleC = $t.Accent2; $ctl.ForeColor = $t.Text; $ctl.Invalidate() }
  elseif ($ctl -is [System.Windows.Forms.Button]) {
    $ctl.FlatStyle = 'Flat'; $ctl.FlatAppearance.BorderSize = 1; $ctl.UseVisualStyleBackColor = $false
    $primary = ($ctl.Font.Bold)
    if ($primary) { $ctl.BackColor = $t.Accent; $ctl.ForeColor = $t.AccentText; $ctl.FlatAppearance.BorderColor = $t.Accent2; $ctl.FlatAppearance.MouseOverBackColor = $t.Accent2 }
    else { $ctl.BackColor = $t.Button; $ctl.ForeColor = $t.Text; $ctl.FlatAppearance.BorderColor = $t.Border; $ctl.FlatAppearance.MouseOverBackColor = $t.ButtonHot }
  }
  elseif ($ctl -is [System.Windows.Forms.CheckBox]) { $ctl.ForeColor = $t.Text; $ctl.BackColor = $t.Panel }
  elseif ($ctl -is [System.Windows.Forms.TextBox]) { $ctl.BackColor = $t.Field; $ctl.ForeColor = $t.Text; $ctl.BorderStyle = 'FixedSingle' }
  elseif ($ctl -is [System.Windows.Forms.NumericUpDown]) { $ctl.BackColor = $t.Field; $ctl.ForeColor = $t.Text; $ctl.BorderStyle = 'FixedSingle' }
  elseif ($ctl -is [System.Windows.Forms.ComboBox]) { $ctl.BackColor = $t.Field; $ctl.ForeColor = $t.Text; $ctl.FlatStyle = 'Flat' }
  elseif ($ctl -is [System.Windows.Forms.ListBox]) { $ctl.BackColor = $t.Field; $ctl.ForeColor = $t.Text; $ctl.BorderStyle = 'FixedSingle' }
  elseif ($ctl -is [System.Windows.Forms.ListView]) {
    $ctl.BackColor = $t.Field; $ctl.ForeColor = $t.Text; $ctl.BorderStyle = 'FixedSingle'; $ctl.GridLines = $false
    if (-not $ctl.Tag -or $ctl.Tag -ne 'themed') {
      $ctl.OwnerDraw = $true; $ctl.Tag = 'themed'
      $ctl.Add_DrawColumnHeader({ param($s, $e)
        $th = $script:Th; $b = New-Object System.Drawing.SolidBrush($th.Header); $e.Graphics.FillRectangle($b, $e.Bounds); $b.Dispose()
        $p = New-Object System.Drawing.Pen($th.Border); $e.Graphics.DrawLine($p, $e.Bounds.Left, $e.Bounds.Bottom - 1, $e.Bounds.Right, $e.Bounds.Bottom - 1); $e.Graphics.DrawLine($p, $e.Bounds.Right - 1, $e.Bounds.Top + 3, $e.Bounds.Right - 1, $e.Bounds.Bottom - 4); $p.Dispose()
        $r = New-Object System.Drawing.Rectangle(($e.Bounds.X + 6), $e.Bounds.Y, ($e.Bounds.Width - 8), $e.Bounds.Height)
        [System.Windows.Forms.TextRenderer]::DrawText($e.Graphics, $e.Header.Text, $s.Font, $r, $th.Accent2, [System.Windows.Forms.TextFormatFlags]::VerticalCenter -bor [System.Windows.Forms.TextFormatFlags]::EndEllipsis) })
      $ctl.Add_DrawItem({ param($s, $e) $e.DrawDefault = $true })
      $ctl.Add_Resize({ param($s, $e) Fit-LastColumn $s })
      $ctl.Add_DrawSubItem({ param($s, $e) $e.DrawDefault = $true })
    }
    foreach ($li in $ctl.Items) { $m = Map-Color $li.ForeColor; if ($m) { $li.ForeColor = $m } }
    Fit-LastColumn $ctl; $ctl.Invalidate()
  }
  elseif ($ctl -is [System.Windows.Forms.Label]) {
    $m = Map-Color $ctl.ForeColor; if ($m) { $ctl.ForeColor = $m } elseif ($ctl.ForeColor.IsSystemColor) { $ctl.ForeColor = $t.Text }
    if ($ctl.Tag -eq 'status') { $ctl.BackColor = $t.Header }
  }
  elseif ($ctl -is [System.Windows.Forms.Panel]) { if ($ctl.Tag -ne 'banner') { $ctl.BackColor = [System.Drawing.Color]::Transparent; if ($ctl.Parent -is [System.Windows.Forms.TabPage]) { $ctl.BackColor = $t.Panel } } }
  foreach ($c in $ctl.Controls) { Apply-Theme $c }
}

# ---------- window icon (assets\app.ico) ----------
$script:AppIconCache = $null
function Set-AppIcon($form) {
  try { if (-not $script:AppIconCache) { $p = Join-Path $PSScriptRoot 'assets\app.ico'; if (Test-Path -LiteralPath $p) { $script:AppIconCache = New-Object System.Drawing.Icon($p, 32, 32) } }
    if ($script:AppIconCache) { $form.Icon = $script:AppIconCache; $form.ShowIcon = $true } } catch { }
}

# ---------- banner (game key art + logo) ----------
$script:BannerImgs = @{}
function Get-ThemeImage([string]$file) {
  if (-not $script:BannerImgs.ContainsKey($file)) { $p = Join-Path $PSScriptRoot "assets\$file"; $img = $null; if (Test-Path -LiteralPath $p) { try { $ms = New-Object IO.MemoryStream (, [IO.File]::ReadAllBytes($p)); $img = [System.Drawing.Image]::FromStream($ms) } catch { } }; $script:BannerImgs[$file] = $img }
  return $script:BannerImgs[$file]
}
# colour of the plain labels that sit on the banner (the Theme label): white over the key art or on dark themes, the theme text colour on a light plain header
function Get-BannerFore { if ($script:Th.Dark -or (Get-ThemeImage $script:PaletteDefs[$script:ThName].Art)) { return [System.Drawing.Color]::White }; return $script:Th.Text }
function Paint-Banner($g, [int]$W, [int]$H, [string]$subtitle) {
  $t = $script:Th; $g.SmoothingMode = 'AntiAlias'; $g.InterpolationMode = 'HighQualityBicubic'
  $b = New-Object System.Drawing.SolidBrush($t.Back); $g.FillRectangle($b, 0, 0, $W, $H); $b.Dispose()
  $art = Get-ThemeImage $script:PaletteDefs[$script:ThName].Art
  if ($art) {   # cover-fit the scene, take a band around the horizon
    $sc = $W / $art.Width; $dh = $art.Height * $sc; $y = -[int](($dh - $H) * 0.62)
    $g.DrawImage($art, 0, $y, $W, [int]$dh)
  }
  # darken from the left (for the logo) to a lighter right, then a bottom accent line
  $rect = New-Object System.Drawing.Rectangle(0, 0, $W, $H)
  $a1 = if ($t.Dark) { 215 } else { 120 }; $a2 = if ($t.Dark) { 120 } else { 20 }
  $lg = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, [System.Drawing.Color]::FromArgb($a1, $t.Back), [System.Drawing.Color]::FromArgb($a2, $t.Back), 0.0)
  $g.FillRectangle($lg, $rect); $lg.Dispose()
  $logo = Get-ThemeImage 'logo.png'
  $lx = 14
  if ($logo) { $lh = $H - 22; $lw = [int]($logo.Width * $lh / $logo.Height); $ly = 8
    if (-not $t.Dark) { $sh = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(70, 20, 30, 45)); $g.FillRectangle($sh, $lx - 4, $ly - 2, $lw + 8, $lh + 4); $sh.Dispose() }
    $g.DrawImage($logo, $lx, $ly, $lw, $lh); $lx += $lw + 18 }
  $f1 = New-Object System.Drawing.Font('Segoe UI Semibold', 15); $f2 = New-Object System.Drawing.Font('Segoe UI', 9)
  $tc = if ($t.Dark) { $t.Text } elseif ($art) { [System.Drawing.Color]::White } else { $t.Text }   # light theme: white text only over the key art, dark text on the plain header
  [System.Windows.Forms.TextRenderer]::DrawText($g, $(if ($logo) { 'ITEM TOOL' } else { 'PERMAFROST ITEM TOOL' }), $f1, (New-Object System.Drawing.Point($lx, 8)), $tc)
  [System.Windows.Forms.TextRenderer]::DrawText($g, $subtitle, $f2, (New-Object System.Drawing.Point(($lx + 2), 38)), $(if ($t.Dark) { $t.Accent2 } elseif ($art) { [System.Drawing.Color]::FromArgb(230, 238, 245) } else { $t.Accent }))
  $f1.Dispose(); $f2.Dispose()
  $p = New-Object System.Drawing.Pen($t.Accent, 2); $g.DrawLine($p, 0, $H - 1, $W, $H - 1); $p.Dispose()
}
# A small "please wait" window for things that take a moment before they show anything (opening a window that reads the save, searching for worlds...).
# The window is shown first, then $action runs (the program is busy meanwhile, so the box just stays up); it goes away by itself as soon as another window
# appears on screen, or when $action ends. The result of $action is returned. Not shown during the self-test.
$script:BusySkip = $false
function Invoke-Busy([string]$message, [scriptblock]$action, $owner = $null) {
  if ($script:BusySkip) { return (& $action) }
  $b = $null; $tm = $null; $old = [System.Windows.Forms.Cursor]::Current
  try {
    try {
      $b = New-Object System.Windows.Forms.Form; $b.FormBorderStyle = 'None'; $b.StartPosition = 'Manual'; $b.ShowInTaskbar = $false; $b.Size = New-Object System.Drawing.Size(360, 92)
      $b.BackColor = $script:Th.Accent; $b.Padding = New-Object System.Windows.Forms.Padding(2)
      $pn = New-Object System.Windows.Forms.Panel; $pn.Dock = 'Fill'; $pn.BackColor = $script:Th.Panel; $b.Controls.Add($pn)
      $l1 = New-Object System.Windows.Forms.Label; $l1.Text = $message; $l1.Font = New-Object System.Drawing.Font('Segoe UI', 12, [System.Drawing.FontStyle]::Bold); $l1.ForeColor = $script:Th.Text; $l1.BackColor = $script:Th.Panel
      $l1.AutoSize = $false; $l1.AutoEllipsis = $true; $l1.TextAlign = 'MiddleCenter'; $l1.SetBounds(10, 14, 336, 34); $pn.Controls.Add($l1)
      $l2 = New-Object System.Windows.Forms.Label; $l2.Text = 'Please wait a moment...'; $l2.Font = New-Object System.Drawing.Font('Segoe UI', 9); $l2.ForeColor = $script:Th.Muted; $l2.BackColor = $script:Th.Panel
      $l2.AutoSize = $false; $l2.TextAlign = 'MiddleCenter'; $l2.SetBounds(10, 50, 336, 22); $pn.Controls.Add($l2)
      $r = $(if ($owner -and $owner.Visible) { $owner.Bounds } else { [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea })
      $b.Location = New-Object System.Drawing.Point([int]($r.Left + ($r.Width - $b.Width) / 2), [int]($r.Top + ($r.Height - $b.Height) / 2))
      $b.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
      if ($owner) { $b.Show($owner) } else { $b.Show() }
      $b.Refresh(); [System.Windows.Forms.Application]::DoEvents()
      $tm = New-Object System.Windows.Forms.Timer; $tm.Interval = 120
      $tm.Add_Tick({ try { foreach ($f in @([System.Windows.Forms.Application]::OpenForms)) { if ($f -ne $b -and $f -ne $owner -and $f.Visible) { $b.Hide(); $tm.Stop(); break } } } catch { } }.GetNewClosure())
      $tm.Start()
    } catch { }
    return (& $action)
  } finally {
    try { if ($tm) { $tm.Stop(); $tm.Dispose() } } catch { }
    try { if ($b) { $b.Close(); $b.Dispose() } } catch { }
    try { [System.Windows.Forms.Cursor]::Current = $old } catch { }
  }
}