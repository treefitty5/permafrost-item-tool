# TeleportMap.ps1 - the "Teleport map": the game's named places, the squares of the map you have uncovered and the objects the atlas flights found,
# drawn from the tool's own data (catalog\places.csv, catalog\map-points.csv, your save's fog of war). Click a point to see its coordinates and the heights found
# there, then use it in Player tools > Teleport. Needs PlayerCore.ps1 + Theme.ps1 + PlayerTools.ps1 (New-LV / New-Lbl / New-Btn / Msg) loaded.
# Orientation as on the game's own map: east (+X) is to the right, north is up (up = -Y, down = +Y).
$script:TM = @{ Loaded = $false }

function TM-Load {
  $m = $script:TM; if ($m.Loaded) { return }
  $m.Dots = @{ o = (New-Object System.Collections.Generic.List[int[]]); c = (New-Object System.Collections.Generic.List[int[]]); i = (New-Object System.Collections.Generic.List[int[]]); t = (New-Object System.Collections.Generic.List[int[]]); b = (New-Object System.Collections.Generic.List[int[]]); n = (New-Object System.Collections.Generic.List[int[]]) }
  $p = Join-Path $PSScriptRoot 'catalog\map-points.csv'
  if (Test-Path -LiteralPath $p) { foreach ($r in (Import-Csv -LiteralPath $p)) { if ($m.Dots.ContainsKey($r.K)) { $m.Dots[$r.K].Add([int[]]@([int]$r.X, [int]$r.Y)) } } }
  $m.Loaded = $true
}
function TM-Bounds {
  $m = $script:TM; $xs = New-Object System.Collections.Generic.List[double]; $ys = New-Object System.Collections.Generic.List[double]
  # the uncovered squares and the named places frame the map (a few stray dots far out must not shrink it); with neither, the dots do
  foreach ($pl in (Get-Places)) { $xs.Add($pl.X); $ys.Add($pl.Y) }
  foreach ($s in $m.Explored) { $xs.Add($s.X0); $xs.Add($s.X0 + 5000); $ys.Add($s.Y0); $ys.Add($s.Y0 + 5000) }
  if ($m.Explored.Count -eq 0) { foreach ($k in $m.Dots.Keys) { foreach ($d in $m.Dots[$k]) { $xs.Add($d[0]); $ys.Add($d[1]) } } }
  if ($xs.Count -eq 0) { return @(-90000.0, -140000.0, 80000.0, 30000.0) }
  return @((($xs | Measure-Object -Minimum).Minimum - 4000), (($ys | Measure-Object -Minimum).Minimum - 4000), (($xs | Measure-Object -Maximum).Maximum + 4000), (($ys | Measure-Object -Maximum).Maximum + 4000))
}
function TM-Fit {
  $m = $script:TM; $b = TM-Bounds; $w = [math]::Max(1, $m.Pic.ClientSize.Width); $h = [math]::Max(1, $m.Pic.ClientSize.Height)
  $m.Scale = [math]::Min($w / ($b[2] - $b[0]), $h / ($b[3] - $b[1])) * 0.96; $m.CX = ($b[0] + $b[2]) / 2; $m.CY = ($b[1] + $b[3]) / 2
}
function TM-ToScreen([double]$x, [double]$y) { $m = $script:TM; return @(([float](($x - $m.CX) * $m.Scale + $m.Pic.ClientSize.Width / 2)), ([float](($y - $m.CY) * $m.Scale + $m.Pic.ClientSize.Height / 2))) }
function TM-ToWorld([double]$sx, [double]$sy) { $m = $script:TM; return @((($sx - $m.Pic.ClientSize.Width / 2) / $m.Scale + $m.CX), (($sy - $m.Pic.ClientSize.Height / 2) / $m.Scale + $m.CY)) }

# paints the whole map into a new bitmap
function TM-Render {
  $m = $script:TM; $w = [math]::Max(50, $m.Pic.ClientSize.Width); $h = [math]::Max(50, $m.Pic.ClientSize.Height); $th = $script:Th
  $bmp = New-Object System.Drawing.Bitmap($w, $h); $g = [System.Drawing.Graphics]::FromImage($bmp); $g.SmoothingMode = 'AntiAlias'; $g.TextRenderingHint = 'ClearTypeGridFit'
  $g.Clear($th.Back)
  # the squares you have uncovered
  if ($m.ChkExplored.Checked) { $ec = [System.Drawing.Color]::FromArgb(70, $th.Accent); $eb = New-Object System.Drawing.SolidBrush($ec); $sz = [float](5000 * $m.Scale)
    foreach ($s in $m.Explored) { $p = TM-ToScreen $s.X0 $s.Y0; if ($p[0] + $sz -lt 0 -or $p[1] + $sz -lt 0 -or $p[0] -gt $w -or $p[1] -gt $h) { continue }; $g.FillRectangle($eb, $p[0], $p[1], $sz + 0.6, $sz + 0.6) }; $eb.Dispose() }
  # a light grid every 1,000 m
  $gp = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(28, $th.Text)); $step = 100000; if ($m.Scale * 100000 -gt 260) { $step = 50000 }; if ($m.Scale * 50000 -gt 260) { $step = 10000 }
  $wa = TM-ToWorld 0 0; $wb = TM-ToWorld $w $h
  for ($x = [math]::Floor($wa[0] / $step) * $step; $x -le $wb[0]; $x += $step) { $p = TM-ToScreen $x 0; $g.DrawLine($gp, $p[0], 0, $p[0], $h) }
  for ($y = [math]::Floor($wa[1] / $step) * $step; $y -le $wb[1]; $y += $step) { $p = TM-ToScreen 0 $y; $g.DrawLine($gp, 0, $p[1], $w, $p[1]) }
  $gp.Dispose()
  # objects the flights found
  $r = [float][math]::Max(1.2, [math]::Min(3.5, $m.Scale * 900))
  $layers = @(@('t', $m.ChkTrees, '#3C8F7B'), @('b', $m.ChkBreak, '#8E9AAD'), @('i', $m.ChkItems, '#6FD3A0'), @('c', $m.ChkCont, '#E3D26F'), @('o', $m.ChkOres, '#F8AD41'), @('n', $m.ChkNotes, '#FF70BB'))
  foreach ($ly in $layers) { if (-not $ly[1].Checked) { continue }; $br = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml($ly[2]))
    foreach ($d in $m.Dots[$ly[0]]) { $p = TM-ToScreen $d[0] $d[1]; if ($p[0] -lt -4 -or $p[1] -lt -4 -or $p[0] -gt $w + 4 -or $p[1] -gt $h + 4) { continue }; $g.FillEllipse($br, $p[0] - $r, $p[1] - $r, 2 * $r, 2 * $r) }; $br.Dispose() }
  # named places, fast travel and your own spots, with labels that do not overlap
  $font = New-Object System.Drawing.Font('Segoe UI', 8.5); $tb = New-Object System.Drawing.SolidBrush($th.Text); $sh = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(200, $th.Back))
  $used = New-Object System.Collections.Generic.List[System.Drawing.RectangleF]
  $targets = @(); if ($m.ChkPlaces.Checked) { $targets += @(Get-Places) }; $targets += @(Get-MySpots)
  foreach ($pl in ($targets | Sort-Object { if ($_.Kind -eq 'My spot') { 0 } elseif ($_.Kind -eq 'Fast travel') { 1 } else { 2 } })) {
    $p = TM-ToScreen $pl.X $pl.Y; if ($p[0] -lt -60 -or $p[1] -lt -20 -or $p[0] -gt $w + 60 -or $p[1] -gt $h + 20) { continue }
    $col = if ($pl.Kind -eq 'Fast travel') { $th.Accent2 } elseif ($pl.Kind -eq 'My spot') { $th.Good } else { $th.Warn }; $b2 = New-Object System.Drawing.SolidBrush($col); $pen = New-Object System.Drawing.Pen($th.Back, 1.5)
    $pts = [System.Drawing.PointF[]]@([System.Drawing.PointF]::new($p[0], $p[1] - 6), [System.Drawing.PointF]::new($p[0] + 6, $p[1]), [System.Drawing.PointF]::new($p[0], $p[1] + 6), [System.Drawing.PointF]::new($p[0] - 6, $p[1]))
    $g.FillPolygon($b2, $pts); $g.DrawPolygon($pen, $pts); $b2.Dispose(); $pen.Dispose()
    $sz = $g.MeasureString($pl.Name, $font); $rc = New-Object System.Drawing.RectangleF(($p[0] + 8), ($p[1] - $sz.Height / 2), $sz.Width, $sz.Height)
    $clash = $false; foreach ($u in $used) { if ($u.IntersectsWith($rc)) { $clash = $true; break } }
    if (-not $clash) { $g.FillRectangle($sh, $rc); $g.DrawString($pl.Name, $font, $tb, $rc.X, $rc.Y); $used.Add($rc) } }
  # you
  if ($m.Player) { $p = TM-ToScreen $m.Player.X $m.Player.Y; $wp = New-Object System.Drawing.Pen($th.Bad, 2.5); $g.DrawEllipse($wp, $p[0] - 7, $p[1] - 7, 14, 14); $fb = New-Object System.Drawing.SolidBrush($th.Bad); $g.FillEllipse($fb, $p[0] - 3, $p[1] - 3, 6, 6); $g.DrawString('you', $font, $tb, $p[0] + 9, $p[1] - 18); $wp.Dispose(); $fb.Dispose() }
  # the selected point
  if ($m.Sel) { $p = TM-ToScreen $m.Sel[0] $m.Sel[1]; $sp = New-Object System.Drawing.Pen($th.Good, 2); $g.DrawEllipse($sp, $p[0] - 9, $p[1] - 9, 18, 18); $g.DrawLine($sp, $p[0] - 15, $p[1], $p[0] + 15, $p[1]); $g.DrawLine($sp, $p[0], $p[1] - 15, $p[0], $p[1] + 15); $sp.Dispose() }
  # scale bar and compass
  $bar = 100000; foreach ($c in 50000, 20000, 10000, 5000, 2000, 1000) { if ($c * $m.Scale -ge 70) { $bar = $c } }; $bw = [float]($bar * $m.Scale); $bp = New-Object System.Drawing.Pen($th.Text, 2)
  $g.DrawLine($bp, 14, $h - 22, 14 + $bw, $h - 22); $g.DrawLine($bp, 14, $h - 27, 14, $h - 17); $g.DrawLine($bp, 14 + $bw, $h - 27, 14 + $bw, $h - 17); $g.DrawString("$($bar / 100) m", $font, $tb, 18, $h - 42); $bp.Dispose()
  $g.DrawString('N', (New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)), $tb, $w - 30, 8); $ap = New-Object System.Drawing.Pen($th.Text, 2); $g.DrawLine($ap, $w - 21, 40, $w - 21, 28); $g.DrawLine($ap, $w - 21, 28, $w - 26, 34); $g.DrawLine($ap, $w - 21, 28, $w - 16, 34); $ap.Dispose()
  $font.Dispose(); $tb.Dispose(); $sh.Dispose(); $g.Dispose()
  if ($m.Pic.Image) { $m.Pic.Image.Dispose() }; $m.Pic.Image = $bmp; $m.Cache = $bmp
}

# the side panel for the selected point: coordinates, nearest place, heights found there
function TM-Select([double]$x, [double]$y) {
  $m = $script:TM; $m.Sel = @($x, $y); $near = $null; $nd = 1e18
  foreach ($pl in (Get-Places)) { $d = ($pl.X - $x) * ($pl.X - $x) + ($pl.Y - $y) * ($pl.Y - $y); if ($d -lt $nd) { $nd = $d; $near = $pl } }
  $m.LblSel.Text = ('Selected: X {0:N0}   Y {1:N0}' -f $x, $y)
  $m.LblNear.Text = if ($near) { "Nearest named place: $($near.Name), $([math]::Round([math]::Sqrt($nd) / 100)) m away" } else { '' }
  $th = Get-TargetHeight ([pscustomobject]@{ Name = 'point'; Kind = 'Coordinates'; X = $x; Y = $y; Z = 0 }); $m.SelZ = $th.Z
  $lv = $m.LvLevels; $lv.BeginUpdate(); $lv.Items.Clear()
  foreach ($l in $th.Levels) { $li = New-Object System.Windows.Forms.ListViewItem([string]$l.Z); [void]$li.SubItems.Add([string]$l.N); [void]$li.SubItems.Add([string]$l.G); [void]$li.SubItems.Add([string]$l.D); $li.Tag = $l; [void]$lv.Items.Add($li); if ($null -ne $th.Z -and [math]::Abs($l.Z - $th.Z) -lt 1) { $li.Selected = $true; $li.Font = New-Object System.Drawing.Font($lv.Font, [System.Drawing.FontStyle]::Bold) } }
  $lv.EndUpdate()
  $m.LblZ.Text = if ($null -ne $th.Z) { "Suggested height: Z $([int]$th.Z) ($($th.Why))" } else { 'No height data within 100 m of this point: you would have to type a Z.' }
  $m.BtnUse.Enabled = $true; $m.BtnSpot.Enabled = $true
  TM-Render
}
function TM-Use {
  $m = $script:TM; if (-not $m.Sel) { return }
  $z = $m.SelZ; if ($m.LvLevels.SelectedItems.Count) { $z = [double]$m.LvLevels.SelectedItems[0].Tag.Z }
  $m.Result = @{ X = $m.Sel[0]; Y = $m.Sel[1]; Z = $z }; $m.Form.Close()
}
function TM-SaveSpot {
  $m = $script:TM; if (-not $m.Sel) { return }
  Add-Type -AssemblyName Microsoft.VisualBasic
  $name = if ($script:TestMode) { 'Map test spot' } else { [Microsoft.VisualBasic.Interaction]::InputBox("Name for the spot at X $([int]$m.Sel[0])  Y $([int]$m.Sel[1]):", 'Save as my spot', '') }
  if (-not $name -or -not $name.Trim()) { return }
  $z = $m.SelZ; if ($m.LvLevels.SelectedItems.Count) { $z = [double]$m.LvLevels.SelectedItems[0].Tag.Z }; if ($null -eq $z) { Msg 'There is no height data here, so the spot cannot be saved from the map. Use the Teleport tab and type a Z.' 'My spot' 'OK' 'Information' | Out-Null; return }
  try { Add-MySpot $name $m.Sel[0] $m.Sel[1] $z; TM-Render } catch { Msg $_.Exception.Message 'My spot' 'OK' 'Warning' | Out-Null }
}
function TM-Find {
  $m = $script:TM; $q = $m.TxtFind.Text.Trim(); if (-not $q) { return }
  $hit = @(@(Get-Places) + @(Get-MySpots) | Where-Object { $_.Name.IndexOf($q, [StringComparison]::OrdinalIgnoreCase) -ge 0 } | Sort-Object Name)
  if (-not $hit.Count) { $m.LblNear.Text = "No place matches '$q'."; return }
  $t = $hit[0]; $m.CX = $t.X; $m.CY = $t.Y; if ($m.Scale -lt 0.0025) { $m.Scale = 0.0025 }; TM-Select $t.X $t.Y
}

function New-TeleportMapForm([string]$savePath, $pd) {
  Add-Type -AssemblyName System.Windows.Forms; Add-Type -AssemblyName System.Drawing
  TM-Load; $m = $script:TM; $m.Result = $null; $m.Sel = $null; $m.SelZ = $null; $m.Cache = $null; $m.Drag = $null
  $m.Explored = @(Get-ExploredSquares $savePath); $m.Player = if ($pd -and $pd.Position) { @{ X = $pd.Position.X; Y = $pd.Position.Y } } else { $null }
  $f = New-Object System.Windows.Forms.Form; $f.Text = 'Teleport map  -  click a point to see its coordinates and heights'; $f.Size = New-Object System.Drawing.Size(1280, [math]::Min(860, [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea.Height - 30)); $f.MinimumSize = New-Object System.Drawing.Size(980, 620)
  $f.StartPosition = 'CenterParent'; $f.Font = New-Object System.Drawing.Font('Segoe UI', 9); $m.Form = $f
  # the side panel is one stack of rows that touch each other (find, selected point, heights, buttons) with the legend in the lower right corner
  $side = New-Object System.Windows.Forms.Panel; $side.Dock = 'Right'; $side.Width = 480; $side.Padding = New-Object System.Windows.Forms.Padding(12, 10, 12, 8); $side.AutoScroll = $true; $f.Controls.Add($side)
  $pic = New-Object System.Windows.Forms.PictureBox; $pic.Dock = 'Fill'; $pic.SizeMode = 'Normal'; $f.Controls.Add($pic); $pic.BringToFront(); $m.Pic = $pic
  $sl = New-Object System.Windows.Forms.TableLayoutPanel; $sl.Dock = 'Fill'; $sl.MinimumSize = New-Object System.Drawing.Size(0, [int](650 * $f.DeviceDpi / 96)); $sl.ColumnCount = 1; [void]$sl.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 100))); $side.Controls.Add($sl)
  $rowAuto = { [void]$sl.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::AutoSize))) }
  $lbl = { param([string]$text) $l = New-Object System.Windows.Forms.Label; $l.Text = $text; $l.AutoSize = $true; $l.MaximumSize = New-Object System.Drawing.Size(446, 0); $l.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 4); return $l }
  # row: find a place
  $fr = New-Object System.Windows.Forms.FlowLayoutPanel; $fr.Dock = 'Fill'; $fr.AutoSize = $true; $fr.WrapContents = $false; $fr.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 6)
  $l1 = & $lbl 'Find a place'; $l1.Margin = New-Object System.Windows.Forms.Padding(0, 8, 8, 0); $fr.Controls.Add($l1)
  $m.TxtFind = New-Object System.Windows.Forms.TextBox; $m.TxtFind.Width = 230; $m.TxtFind.Margin = New-Object System.Windows.Forms.Padding(0, 5, 8, 0); $fr.Controls.Add($m.TxtFind)
  $bFind = New-Object System.Windows.Forms.Button; $bFind.Text = 'Go'; $bFind.Width = 90; $bFind.Height = 30; $bFind.Margin = New-Object System.Windows.Forms.Padding(0, 2, 0, 0); $fr.Controls.Add($bFind)
  & $rowAuto; $sl.Controls.Add($fr)
  $m.LblSel = & $lbl 'Click the map to pick a point.'; $m.LblSel.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold); & $rowAuto; $sl.Controls.Add($m.LblSel)
  $m.LblNear = & $lbl ''; & $rowAuto; $sl.Controls.Add($m.LblNear)
  $lh = & $lbl 'Heights found near the point (Z):'; & $rowAuto; $sl.Controls.Add($lh)
  [void]$sl.RowStyles.Add((New-Object System.Windows.Forms.RowStyle([System.Windows.Forms.SizeType]::Percent, 100)))
  $m.LvLevels = New-LV $sl @('Height (Z)', 'Objects', 'On ground', 'Nearest (m)') @(110, 100, 120, 100); $m.LvLevels.Dock = 'Fill'; $m.LvLevels.MinimumSize = New-Object System.Drawing.Size(0, 110); $m.LvLevels.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 6)
  $m.LblZ = & $lbl ''; $m.LblZ.ForeColor = $script:Th.Accent; & $rowAuto; $sl.Controls.Add($m.LblZ)
  $m.BtnUse = New-Object System.Windows.Forms.Button; $m.BtnUse.Text = 'Use this spot in Teleport'; $m.BtnUse.Dock = 'Fill'; $m.BtnUse.Height = 38; $m.BtnUse.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 4); $m.BtnUse.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold); $m.BtnUse.Enabled = $false; & $rowAuto; $sl.Controls.Add($m.BtnUse)
  $m.BtnSpot = New-Object System.Windows.Forms.Button; $m.BtnSpot.Text = 'Save as my spot...'; $m.BtnSpot.Dock = 'Fill'; $m.BtnSpot.Height = 32; $m.BtnSpot.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 4); $m.BtnSpot.Enabled = $false; & $rowAuto; $sl.Controls.Add($m.BtnSpot)
  $vr = New-Object System.Windows.Forms.TableLayoutPanel; $vr.Dock = 'Fill'; $vr.ColumnCount = 3; $vr.RowCount = 1; $vr.AutoSize = $true; $vr.Margin = New-Object System.Windows.Forms.Padding(0, 0, 0, 8)
  [void]$vr.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 44))); [void]$vr.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 28))); [void]$vr.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 28)))
  $mkb = { param([string]$t) $b = New-Object System.Windows.Forms.Button; $b.Text = $t; $b.Dock = 'Fill'; $b.Height = 32; $b.Margin = New-Object System.Windows.Forms.Padding(0, 0, 4, 0); return $b }
  $bFit = & $mkb 'Show everything'; $bZoomIn = & $mkb 'Zoom +'; $bZoomOut = & $mkb 'Zoom -'; $vr.Controls.Add($bFit, 0, 0); $vr.Controls.Add($bZoomIn, 1, 0); $vr.Controls.Add($bZoomOut, 2, 0); & $rowAuto; $sl.Controls.Add($vr)
  # the legend, lower right: a coloured mark for everything on the map; the tick boxes switch layers on and off
  $th = $script:Th; $a = 70.0 / 255; $lightSq = [System.Drawing.Color]::FromArgb([int]($th.Back.R * (1 - $a) + $th.Accent.R * $a), [int]($th.Back.G * (1 - $a) + $th.Accent.G * $a), [int]($th.Back.B * (1 - $a) + $th.Accent.B * $a))
  $swPaint = { param($s, $e) $d = $s.Tag; $g = $e.Graphics; $g.SmoothingMode = 'AntiAlias'; $g.TranslateTransform(0, 3); $br = New-Object System.Drawing.SolidBrush($d.Color); $pn = New-Object System.Drawing.Pen($d.Edge, 1.2)
    switch ($d.Shape) { 'square' { $g.FillRectangle($br, 2, 5, 15, 15); $g.DrawRectangle($pn, 2, 5, 15, 15) } 'dot' { $g.FillEllipse($br, 4, 7, 11, 11) } 'ring' { $rp = New-Object System.Drawing.Pen($d.Color, 2.2); $g.DrawEllipse($rp, 3, 6, 12, 12); $rp.Dispose() }
      'diamond' { $pts = [System.Drawing.PointF[]]@([System.Drawing.PointF]::new(9.5, 3), [System.Drawing.PointF]::new(17, 12), [System.Drawing.PointF]::new(9.5, 21), [System.Drawing.PointF]::new(2, 12)); $g.FillPolygon($br, $pts); $g.DrawPolygon($pn, $pts) } }
    $br.Dispose(); $pn.Dispose() }
  $mkItem = { param([string]$text, [string]$shape, $color, [bool]$check, [bool]$on)
    $r = New-Object System.Windows.Forms.FlowLayoutPanel; $r.AutoSize = $true; $r.WrapContents = $false; $r.Margin = New-Object System.Windows.Forms.Padding(0, 1, 6, 1)
    $sw = New-Object System.Windows.Forms.Panel; $sw.Size = New-Object System.Drawing.Size(21, 31); $sw.Margin = New-Object System.Windows.Forms.Padding(0, 0, 3, 0); $sw.Tag = @{ Shape = $shape; Color = $color; Edge = $th.Muted }; $sw.Add_Paint($swPaint); $r.Controls.Add($sw)
    if ($check) { $c = New-Object System.Windows.Forms.CheckBox; $c.Text = $text; $c.Checked = $on; $c.AutoSize = $true; $c.Margin = New-Object System.Windows.Forms.Padding(0, 1, 0, 0); $c.ForeColor = $th.Text; $c.Add_CheckedChanged({ if ($script:TM.Pic.Image) { TM-Render } }); $r.Controls.Add($c) }
    else { $c = New-Object System.Windows.Forms.Label; $c.Text = $text; $c.AutoSize = $true; $c.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 0); $r.Controls.Add($c) }
    return @{ Row = $r; Ctl = $c } }
  $gL = New-Object ThemedGroup; $gL.Text = 'Legend'; $gL.Dock = 'Fill'; $gL.AutoSize = $true; $gL.AutoSizeMode = 'GrowAndShrink'; $gL.Padding = New-Object System.Windows.Forms.Padding(10, 6, 10, 8); $gL.Margin = New-Object System.Windows.Forms.Padding(0, 4, 0, 0)
  $lt = New-Object System.Windows.Forms.TableLayoutPanel; $lt.Dock = 'Top'; $lt.AutoSize = $true; $lt.AutoSizeMode = 'GrowAndShrink'; $lt.ColumnCount = 2; [void]$lt.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50))); [void]$lt.ColumnStyles.Add((New-Object System.Windows.Forms.ColumnStyle([System.Windows.Forms.SizeType]::Percent, 50)))
  $items = @(
    @('Uncovered area', 'square', $lightSq, $true, $true, 'ChkExplored'), @('Not uncovered yet', 'square', $th.Back, $false, $false, ''),
    @('Named places', 'diamond', $th.Warn, $true, $true, 'ChkPlaces'), @('Fast travel', 'diamond', $th.Accent2, $false, $false, ''),
    @('Your spots', 'diamond', $th.Good, $false, $false, ''), @('You (as saved)', 'ring', $th.Bad, $false, $false, ''),
    @('Ores', 'dot', [System.Drawing.ColorTranslator]::FromHtml('#F8AD41'), $true, $true, 'ChkOres'), @('Containers', 'dot', [System.Drawing.ColorTranslator]::FromHtml('#E3D26F'), $true, $true, 'ChkCont'),
    @('Loose items', 'dot', [System.Drawing.ColorTranslator]::FromHtml('#6FD3A0'), $true, $true, 'ChkItems'), @('Notes', 'dot', [System.Drawing.ColorTranslator]::FromHtml('#FF70BB'), $true, $true, 'ChkNotes'),
    @('Trees and bushes', 'dot', [System.Drawing.ColorTranslator]::FromHtml('#3C8F7B'), $true, $false, 'ChkTrees'), @('Breakables', 'dot', [System.Drawing.ColorTranslator]::FromHtml('#8E9AAD'), $true, $false, 'ChkBreak'))
  foreach ($it in $items) { $x = & $mkItem $it[0] $it[1] $it[2] $it[3] $it[4]; if ($it[5]) { $m[$it[5]] = $x.Ctl }; $lt.Controls.Add($x.Row) }
  $gL.Controls.Add($lt)
  $nt = New-Object System.Windows.Forms.Label; $nt.Dock = 'Bottom'; $nt.AutoSize = $true; $nt.MaximumSize = New-Object System.Drawing.Size(430, 0); $nt.ForeColor = $th.Muted; $nt.Padding = New-Object System.Windows.Forms.Padding(0, 6, 0, 0)
  $nt.Text = "Light squares: uncovered in this save (the game's 50 m fog-of-war squares; an edge can be off by one). Dark squares: not uncovered yet - sea, unvisited ground or gaps. Dots show what the atlas flights found, even on dark squares: where nothing is drawn nothing was found, so there are no heights. East (+X) is right, north is up. Drag to move, wheel to zoom."
  $gL.Controls.Add($nt); & $rowAuto; $sl.Controls.Add($gL)
  $m.LblPos = New-Object System.Windows.Forms.Label; $m.LblPos.Dock = 'Bottom'; $m.LblPos.Height = 22; $m.LblPos.Padding = New-Object System.Windows.Forms.Padding(8, 3, 0, 0); $f.Controls.Add($m.LblPos); $m.LblPos.BringToFront()
  Apply-Theme $f; Set-AppIcon $f
  $m.ZoomAt = { param([double]$factor, [double]$sx, [double]$sy) $mm = $script:TM; $wb = TM-ToWorld $sx $sy; $mm.Scale = [math]::Min(0.4, [math]::Max(0.0009, $mm.Scale * $factor)); $mm.CX = $wb[0] - ($sx - $mm.Pic.ClientSize.Width / 2) / $mm.Scale; $mm.CY = $wb[1] - ($sy - $mm.Pic.ClientSize.Height / 2) / $mm.Scale; TM-Render }
  $pic.Add_MouseWheel({ param($s, $e) & $script:TM.ZoomAt $(if ($e.Delta -gt 0) { 1.25 } else { 0.8 }) $e.X $e.Y })
  $pic.Add_MouseDown({ param($s, $e) if ($e.Button -eq 'Left') { $script:TM.Drag = @{ X = $e.X; Y = $e.Y; CX = $script:TM.CX; CY = $script:TM.CY; Moved = $false } } })
  $pic.Add_MouseMove({ param($s, $e) $mm = $script:TM; $w = TM-ToWorld $e.X $e.Y; $mm.LblPos.Text = ('Cursor: X {0:N0}   Y {1:N0}' -f $w[0], $w[1])
    if ($mm.Drag) { $dx = $e.X - $mm.Drag.X; $dy = $e.Y - $mm.Drag.Y; if ([math]::Abs($dx) + [math]::Abs($dy) -gt 4) { $mm.Drag.Moved = $true }
      if ($mm.Drag.Moved -and $mm.Cache) { $mm.CX = $mm.Drag.CX - $dx / $mm.Scale; $mm.CY = $mm.Drag.CY - $dy / $mm.Scale; $tmp = New-Object System.Drawing.Bitmap($mm.Pic.ClientSize.Width, $mm.Pic.ClientSize.Height); $gg = [System.Drawing.Graphics]::FromImage($tmp); $gg.Clear($script:Th.Back); $gg.DrawImage($mm.Cache, $dx, $dy); $gg.Dispose(); $old = $mm.Pic.Image; $mm.Pic.Image = $tmp; if ($old -and $old -ne $mm.Cache) { $old.Dispose() } } } })
  $pic.Add_MouseUp({ param($s, $e) $mm = $script:TM; $d = $mm.Drag; $mm.Drag = $null; if (-not $d) { return }
    if ($d.Moved) { TM-Render } elseif ($e.Button -eq 'Left') { $w = TM-ToWorld $e.X $e.Y; TM-Select $w[0] $w[1] } })
  # re-draw after every size change (a short timer waits for the layout to settle: maximizing the window left a stale picture before)
  $m.RTimer = New-Object System.Windows.Forms.Timer; $m.RTimer.Interval = 60; $m.RTimer.Add_Tick({ $script:TM.RTimer.Stop(); try { if ($script:TM.Scale) { TM-Render } } catch { $script:TM.LblPos.Text = 'render problem: ' + $_.Exception.Message } })
  $pic.Add_Resize({ $script:TM.RTimer.Stop(); $script:TM.RTimer.Start() }); $f.Add_Resize({ $script:TM.RTimer.Stop(); $script:TM.RTimer.Start() }); $f.Add_FormClosed({ $script:TM.RTimer.Stop(); $script:TM.RTimer.Dispose() })
  $bFit.Add_Click({ TM-Fit; TM-Render }); $bZoomIn.Add_Click({ $p = $script:TM.Pic; & $script:TM.ZoomAt 1.5 ($p.ClientSize.Width / 2) ($p.ClientSize.Height / 2) }); $bZoomOut.Add_Click({ $p = $script:TM.Pic; & $script:TM.ZoomAt 0.66 ($p.ClientSize.Width / 2) ($p.ClientSize.Height / 2) })
  $m.BtnUse.Add_Click({ TM-Use }); $m.BtnSpot.Add_Click({ TM-SaveSpot }); $bFind.Add_Click({ TM-Find }); $m.TxtFind.Add_KeyDown({ param($s, $e) if ($e.KeyCode -eq 'Return') { $e.SuppressKeyPress = $true; TM-Find } })
  $f.Add_Shown({ [System.Windows.Forms.Application]::DoEvents(); TM-Fit; TM-Render })
  return $f
}
# returns @{ X; Y; Z } for the point the user picked with 'Use this spot', or $null
function Show-TeleportMap($owner, [string]$savePath, $pd) {
  $f = New-TeleportMapForm $savePath $pd; $f.WindowState = 'Maximized'; $prev = $script:ActiveForm; $script:ActiveForm = $f
  try { [void]$f.ShowDialog($owner) } finally { $script:ActiveForm = $prev }
  return $script:TM.Result
}
