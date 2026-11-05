# ContainerLabels.ps1 - names for your storage containers (barrels, chests, bookshelves...), shown in the game as floating text above each one.
# Two halves: this file (reads the containers of your base from the save, keeps your labels in container-labels.json, writes the mod's labels.lua, installs the mod)
# and ContainerLabelsMod\main.lua (the UE4SS mod that draws the text; it only reads labels.lua, the save is never touched).
# Needs RecipeTweaks.ps1 (RT-ModsDir finds the UE4SS Mods folder next to the save) and PlayerTools.ps1 (Msg and the list / button helpers).
#
# The base is the save's player entry PlayerBuildParts: one "#Type&X=..,Y=..,Z=..&P=..,Y=..,R=..&a&b$<content>" segment per part, and a container's content is a slot list
# "@0=Coal&50@1=Coal&50&0.0@2=..." (item&count[&condition]). A part whose content starts with "@<number>=" is a container. Its position identifies it in the game (the actor sits at the
# same X, Y, Z to within a millimetre), so labels are kept by position.

$script:ClInv = [Globalization.CultureInfo]::InvariantCulture
function CL-ModDir { return (Join-Path (RT-ModsDir) 'ContainerLabels') }
function CL-LabelsPath { if ($script:ClLabelsPathOverride) { return $script:ClLabelsPathOverride }; return (Join-Path $PSScriptRoot 'container-labels.json') }

function CL-Pretty([string]$id, $names) {
  if ($names -and $names.ContainsKey($id) -and $names[$id]) { return [string]$names[$id] }
  $s = ($id -creplace '_Ammo$', ' ammo' -creplace '_', ' ' -creplace '([a-z0-9])([A-Z])', '$1 $2').Trim(); return $s   # -creplace: the split must be case-sensitive
}
function CL-ItemNames {
  $h = @{}; try { $p = Join-Path $PSScriptRoot 'items.json'; if (Test-Path -LiteralPath $p) { $j = Get-Content -LiteralPath $p -Raw | ConvertFrom-Json; $arr = if ($j -is [array]) { $j } else { $j.items }; foreach ($i in $arr) { if ($i.id -and $i.name) { $h[[string]$i.id] = [string]$i.name } } } } catch { }
  return $h
}

# the containers of the base: @{ N; Type; X; Y; Z; Items (id -> total count); Slots (used slots) }, in the order the save lists them
function CL-ParseParts([string]$parts) {
  $res = New-Object System.Collections.Generic.List[object]; if (-not $parts) { return @() }
  $n = 0
  foreach ($seg in ($parts -split '(?=#[A-Za-z])')) {
    if (-not $seg) { continue }
    $i = $seg.IndexOf([char]'$'); if ($i -lt 0) { continue }
    $m = [regex]::Match($seg.Substring(0, $i), '^#([A-Za-z0-9_]+)&X=([-\d\.]+),Y=([-\d\.]+),Z=([-\d\.]+)'); if (-not $m.Success) { continue }
    $c = $seg.Substring($i + 1); if ($c -notmatch '^@\d+=') { continue }
    $items = @{}; $slots = 0
    foreach ($t in [regex]::Matches($c, '@\d+=([A-Za-z0-9_\.\-]+)&(\d+)')) { $slots++; $k = $t.Groups[1].Value; $items[$k] = [int]$items[$k] + [int]$t.Groups[2].Value }
    $n++
    $res.Add([pscustomobject]@{ N = $n; Type = $m.Groups[1].Value
      X = [double]::Parse($m.Groups[2].Value, $script:ClInv); Y = [double]::Parse($m.Groups[3].Value, $script:ClInv); Z = [double]::Parse($m.Groups[4].Value, $script:ClInv); Items = $items; Slots = $slots })
  }
  return $res.ToArray()
}

# "Coal x953, Wood x400"  (the biggest piles first)
function CL-Summary($items, $names, [int]$top = 4) {
  if (-not $items -or $items.Count -eq 0) { return '(empty)' }
  $sorted = @($items.GetEnumerator() | Sort-Object { -$_.Value }, Name)
  $txt = @(); foreach ($e in ($sorted | Select-Object -First $top)) { $txt += ('{0} x{1}' -f (CL-Pretty $e.Key $names), $e.Value) }
  $more = $sorted.Count - $top; if ($more -gt 0) { $txt += "+$more more" }
  return ($txt -join ', ')
}

# a short label from the contents: one dominant item -> its name; several calibers of ammo -> "Ammo"; otherwise the top three names
function CL-Suggest($items, $names) {
  if (-not $items -or $items.Count -eq 0) { return '' }
  $total = 0; foreach ($v in $items.Values) { $total += $v }
  $sorted = @($items.GetEnumerator() | Sort-Object { -$_.Value }, Name)
  $ammo = 0; foreach ($e in $sorted) { if ($e.Key -match '_Ammo$|^FlareAmmo$') { $ammo += $e.Value } }
  if ($total -gt 0 -and ($ammo / $total) -ge 0.8) { if (@($sorted | Where-Object { $_.Key -match '_Ammo$|^FlareAmmo$' }).Count -eq 1) { return (CL-Pretty $sorted[0].Key $names).ToUpper() } else { return 'AMMO' } }
  $weap = 0; foreach ($e in $sorted) { if ($e.Key -match '^Weapon_') { $weap += $e.Value } }
  if ($total -gt 0 -and ($weap / $total) -ge 0.5) { return 'WEAPONS' }
  if ($total -gt 0 -and ($sorted[0].Value / $total) -ge 0.7) { return (CL-Short $sorted[0].Key $names) }
  $w = New-Object System.Collections.Generic.List[string]
  foreach ($e in ($sorted | Select-Object -First 6)) { $s = CL-Short $e.Key $names; if ($s -and -not $w.Contains($s) -and $w.Count -lt 3) { $w.Add($s) } }
  return ($w -join '/')   # in the game each word gets its own line: FOOD / FATS / WOOD
}
# one short word for an item: "Surgical Spirit" -> SPIRIT, "Iron Ingot" -> IRON, "Dish H" -> DISH, "Gun Powder Container" -> POWDER
function CL-Short([string]$id, $names) {
  $p = CL-Pretty $id $names; $w = @($p -split '\s+' | Where-Object { $_ }); if ($w.Count -le 1) { return $p.ToUpper() }
  $last = $w[$w.Count - 1]; if ($last.Length -le 2) { return $w[0].ToUpper() }
  if ($last -match '^(Ingot|Container|Ammo|Package)$') { return $w[$w.Count - 2].ToUpper() }
  return $last.ToUpper()
}

# --- the labels file: { "labels": [ { "x":..., "y":..., "z":..., "text":"..." } ] } ---
function CL-ReadLabels {
  $res = New-Object System.Collections.Generic.List[object]; $p = CL-LabelsPath
  try { if (Test-Path -LiteralPath $p) { $j = Get-Content -LiteralPath $p -Raw | ConvertFrom-Json; foreach ($l in @($j.labels)) { if ($null -ne $l.x) { $res.Add([pscustomobject]@{ X = [double]$l.x; Y = [double]$l.y; Z = [double]$l.z; Text = [string]$l.text }) } } } } catch { }
  return $res.ToArray()
}
function CL-FindLabel($labels, $c) { foreach ($l in $labels) { if ([math]::Abs($l.X - $c.X) -lt 30 -and [math]::Abs($l.Y - $c.Y) -lt 30 -and [math]::Abs($l.Z - $c.Z) -lt 30) { return $l.Text } }; return '' }
function CL-WriteLabelsFile($containers, $texts) {
  $out = New-Object System.Collections.Generic.List[object]
  for ($i = 0; $i -lt $containers.Count; $i++) { $t = [string]$texts[$i]; if ($t.Trim()) { $out.Add([ordered]@{ x = $containers[$i].X; y = $containers[$i].Y; z = $containers[$i].Z; text = $t.Trim() }) } }
  $o = [ordered]@{ version = 1; labels = $out.ToArray() }
  [IO.File]::WriteAllText((CL-LabelsPath), ($o | ConvertTo-Json -Depth 4), (New-Object Text.UTF8Encoding($false)))
  return $out.Count
}

# the mod's labels.lua: every container of the base (so numbers mode can number them all), with its label text when it has one
function CL-LuaQuote([string]$s) { $t = $s -replace '\\', '\\' -replace '"', '\"' -replace "[\r\n\t]", ' '; return '"' + $t + '"' }
function CL-LuaText($containers, $texts) {
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine('-- written by the Permafrost Item Tool (Player tools > Container labels). Do not edit: the tool overwrites this file.')
  [void]$sb.AppendLine('return { version = 1, items = {')
  for ($i = 0; $i -lt $containers.Count; $i++) { $c = $containers[$i]
    [void]$sb.AppendLine(('  {{ type = {0}, x = {1}, y = {2}, z = {3}, text = {4} }},' -f (CL-LuaQuote $c.Type), $c.X.ToString('0.###', $script:ClInv), $c.Y.ToString('0.###', $script:ClInv), $c.Z.ToString('0.###', $script:ClInv), (CL-LuaQuote ([string]$texts[$i]).Trim()))) }
  [void]$sb.AppendLine('} }')
  return $sb.ToString()
}
function CL-WriteLua($containers, $texts) {
  $dir = CL-ModDir; New-Item -ItemType Directory -Force $dir | Out-Null
  [IO.File]::WriteAllText((Join-Path $dir 'labels.lua'), (CL-LuaText $containers $texts), (New-Object Text.UTF8Encoding($false)))
}

# --- the mod itself ---
function CL-Status {
  $dir = CL-ModDir; $main = Join-Path $dir 'Scripts\main.lua'; $src = Join-Path $PSScriptRoot 'ContainerLabelsMod\main.lua'
  if (-not (Test-Path -LiteralPath (RT-ModsDir))) { return @{ Ok = $false; Text = 'UE4SS Mods folder not found next to your save.' } }
  if (-not (Test-Path -LiteralPath $main)) { return @{ Ok = $false; Text = 'Not installed yet.' } }
  $mt = Join-Path (RT-ModsDir) 'mods.txt'
  if (-not ((Test-Path -LiteralPath $mt) -and ((Get-Content $mt -Raw) -match '(?m)^\s*ContainerLabels\s*:\s*1'))) { return @{ Ok = $false; Text = 'Installed but switched off in mods.txt.' } }
  if ((Test-Path -LiteralPath $src) -and ((Get-FileHash $main).Hash -ne (Get-FileHash $src).Hash)) { return @{ Ok = $false; Text = 'An older version is installed.' } }
  return @{ Ok = $true; Text = 'Installed and switched on.' }
}
function CL-Install {
  $mods = RT-ModsDir; if (-not (Test-Path -LiteralPath $mods)) { throw "UE4SS Mods folder not found: $mods" }
  $src = Join-Path $PSScriptRoot 'ContainerLabelsMod\main.lua'; if (-not (Test-Path -LiteralPath $src)) { throw 'ContainerLabelsMod\main.lua is missing next to the tool.' }
  $dir = CL-ModDir; New-Item -ItemType Directory -Force (Join-Path $dir 'Scripts') | Out-Null
  Copy-Item -LiteralPath $src -Destination (Join-Path $dir 'Scripts\main.lua') -Force
  $mt = Join-Path $mods 'mods.txt'; $lines = New-Object System.Collections.Generic.List[string]; if (Test-Path -LiteralPath $mt) { foreach ($l in (Get-Content $mt)) { $lines.Add($l) } }
  $bk = "$mt.bak-before-containerlabels"; if ((Test-Path -LiteralPath $mt) -and -not (Test-Path -LiteralPath $bk)) { Copy-Item -LiteralPath $mt -Destination $bk }
  $ix = -1; for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*ContainerLabels\s*:') { $ix = $i; break } }
  if ($ix -ge 0) { $lines[$ix] = 'ContainerLabels : 1' }
  else { $cm = -1; for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*;.*[Bb]uilt-in keybinds') { $cm = $i; break } }
    $last = -1; $lim = $(if ($cm -ge 0) { $cm } else { $lines.Count }); for ($i = 0; $i -lt $lim; $i++) { if ($lines[$i] -match '^\S+\s*:\s*[01]\s*$') { $last = $i } }
    $lines.Insert($last + 1, 'ContainerLabels : 1') }
  [IO.File]::WriteAllText($mt, (($lines -join "`r`n") + "`r`n"), (New-Object Text.UTF8Encoding($false)))
}

# --- the tab in Player tools ---
$script:CL = @{ Rows = @(); Texts = @(); Names = @{}; Dirty = $false }
function CL-Where($c, $bed) {
  if (-not $bed) { return '' }
  $d = [math]::Sqrt([math]::Pow($c.X - $bed.X, 2) + [math]::Pow($c.Y - $bed.Y, 2)) / 100.0; $dz = ($c.Z - $bed.Z) / 100.0
  $v = if ([math]::Abs($dz) -lt 1.5) { 'same level' } elseif ($dz -gt 0) { ('{0:N0} m higher' -f $dz) } else { ('{0:N0} m lower' -f (-$dz)) }
  return ('{0:N0} m from your bed, {1}' -f $d, $v)
}
function CL-Fill {
  $ui = $script:PT; $lv = $ui.LvLabels; if (-not $lv) { return }
  $lv.BeginUpdate(); $lv.Items.Clear()
  for ($i = 0; $i -lt $script:CL.Rows.Count; $i++) { $c = $script:CL.Rows[$i]
    $it = New-Object System.Windows.Forms.ListViewItem([string]$c.N); [void]$it.SubItems.Add($c.Type); [void]$it.SubItems.Add((CL-Where $c $script:CL.Bed)); [void]$it.SubItems.Add((CL-Summary $c.Items $script:CL.Names)); [void]$it.SubItems.Add([string]$script:CL.Texts[$i])
    $it.Tag = $i; if (-not [string]$script:CL.Texts[$i]) { $it.ForeColor = $script:Th.Muted }; [void]$lv.Items.Add($it) }
  $lv.EndUpdate()
  $lab = @($script:CL.Texts | Where-Object { $_ }).Count
  $ui.ClCount.Text = ('{0} containers in your base, {1} with a label{2}' -f $script:CL.Rows.Count, $lab, $(if ($script:CL.Dirty) { '  -  UNSAVED changes' } else { '' }))
}
function CL-Load {
  $ui = $script:PT; if (-not $ui.LvLabels) { return }
  $d = $ui.Data; if (-not $d) { return }
  $script:CL.Names = CL-ItemNames; $script:CL.Bed = $d.Bed
  $rows = @(CL-ParseParts ([string]$d.Entries['PlayerBuildParts'])); $labels = @(CL-ReadLabels)
  $script:CL.Rows = $rows; $script:CL.Texts = @($rows | ForEach-Object { CL-FindLabel $labels $_ }); $script:CL.Dirty = $false
  CL-Fill
}
function CL-OnSelect {
  $ui = $script:PT; $sel = $ui.LvLabels.SelectedItems
  if ($sel.Count -eq 1) { $ui.ClText.Text = [string]$script:CL.Texts[[int]$sel[0].Tag] } elseif ($sel.Count -eq 0) { $ui.ClText.Text = '' }
}
function CL-SetSelected([string]$text) {
  $ui = $script:PT; $sel = @($ui.LvLabels.SelectedItems); if (-not $sel.Count) { PT-Status 'Select one or more containers in the list first.'; return }
  foreach ($it in $sel) { $script:CL.Texts[[int]$it.Tag] = $text.Trim() }
  $script:CL.Dirty = $true; $keep = @($sel | ForEach-Object { [int]$_.Tag }); CL-Fill
  foreach ($it in $ui.LvLabels.Items) { if ($keep -contains [int]$it.Tag) { $it.Selected = $true } }
}
function CL-SuggestSelected {
  $ui = $script:PT; $sel = @($ui.LvLabels.SelectedItems); if (-not $sel.Count) { PT-Status 'Select one or more containers in the list first.'; return }
  foreach ($it in $sel) { $i = [int]$it.Tag; $script:CL.Texts[$i] = CL-Suggest $script:CL.Rows[$i].Items $script:CL.Names }
  $script:CL.Dirty = $true; $keep = @($sel | ForEach-Object { [int]$_.Tag }); CL-Fill
  foreach ($it in $ui.LvLabels.Items) { if ($keep -contains [int]$it.Tag) { $it.Selected = $true } }
}
function CL-SuggestEmpty {
  $n = 0; for ($i = 0; $i -lt $script:CL.Rows.Count; $i++) { if (-not [string]$script:CL.Texts[$i]) { $s = CL-Suggest $script:CL.Rows[$i].Items $script:CL.Names; if ($s) { $script:CL.Texts[$i] = $s; $n++ } } }
  if ($n) { $script:CL.Dirty = $true }; CL-Fill; PT-Status ("Suggested a label for $n containers that had none (from what they hold). Edit any of them, then save.")
}
function CL-ClearAll {
  if (-not $script:CL.Rows.Count) { return }
  $a = Msg 'Remove every label? (Nothing is saved until you press Save labels.)' 'Container labels' 'YesNo' 'Question'; if ($a -ne 'Yes') { return }
  $script:CL.Texts = @($script:CL.Rows | ForEach-Object { '' }); $script:CL.Dirty = $true; CL-Fill
}
function CL-Save {
  if (-not $script:CL.Rows.Count) { PT-Status 'This save has no containers in your base.'; return }
  try {
    $n = CL-WriteLabelsFile $script:CL.Rows $script:CL.Texts
    $st = $null; try { $st = CL-Status } catch { }
    if (-not $st -or -not $st.Ok) { CL-Install }
    CL-WriteLua $script:CL.Rows $script:CL.Texts
    $script:CL.Dirty = $false; CL-Fill
    PT-Status ("Saved $n labels and updated the game mod. In the game they show within 10 m of each container; the mod re-reads the file every 15 seconds, so a running game picks changes up by itself. (If the mod was just installed, start the game once.)")
  } catch { PT-Status ('Could not save the labels: ' + $_.Exception.Message) }
}
function CL-BuildTab($tab) {
  $ui = $script:PT
  $top = New-Object System.Windows.Forms.Panel; $top.Dock = 'Top'; $top.Height = 40; $tab.Controls.Add($top)
  $bR = New-Btn $top 'Reload from the save' 0 5 160; $bS = New-Btn $top 'Suggest labels for the empty ones' 168 5 240; $bC = New-Btn $top 'Remove all labels' 416 5 150
  $bSave = New-Btn $top 'Save labels and update the game mod' 574 5 300; $bSave.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
  $ui.ClCount = New-Object System.Windows.Forms.Label; $ui.ClCount.Dock = 'Bottom'; $ui.ClCount.Height = 24; $ui.ClCount.TextAlign = 'MiddleLeft'; $tab.Controls.Add($ui.ClCount)
  $bot = New-Object System.Windows.Forms.Panel; $bot.Dock = 'Bottom'; $bot.Height = 112; $tab.Controls.Add($bot)
  New-Lbl $bot 'Label for the selected container(s)' 0 10 250 | Out-Null
  $ui.ClText = New-Object System.Windows.Forms.TextBox; $ui.ClText.Location = '258,7'; $ui.ClText.Size = '360,24'; $ui.ClText.MaxLength = 40; $bot.Controls.Add($ui.ClText)
  $bSet = New-Btn $bot 'Set label' 628 4 110; $bSug = New-Btn $bot 'Suggest from contents' 746 4 190; $bNo = New-Btn $bot 'Clear label' 944 4 110
  $nt = New-Lbl $bot "In the game a label hangs in front of its container while you are within 10 m, in white capitals with one word per line (type FOOD/FATS/WOOD, or separate the words with spaces), and turns to face you; nothing is saved in your world. Press Ctrl+F5 in the game to show every container's NUMBER (the # column) for 25 m around you, so you can tell which row is which barrel; press it again to hide them. The labels file (container-labels.json) stays on your computer. The game does not have to be closed." 0 40 1050 64
  $nt.ForeColor = $script:Th.Muted
  $ui.LvLabels = New-LV $tab @('#', 'Type', 'Where', 'Contents', 'Label') @(46, 150, 230, 520, 260); $ui.LvLabels.Dock = 'Fill'; $ui.LvLabels.FullRowSelect = $true; $ui.LvLabels.MultiSelect = $true; $ui.LvLabels.BringToFront()
  $ui.LvLabels.Add_Resize({ $lv = $script:PT.LvLabels; if ($lv.Columns.Count -ge 5) { $o = 0; for ($i = 0; $i -lt 4; $i++) { $o += $lv.Columns[$i].Width }; $lv.Columns[4].Width = [math]::Max(200, $lv.ClientSize.Width - $o - 4) } })
  $ui.LvLabels.Add_SelectedIndexChanged({ CL-OnSelect })
  $bR.Add_Click({ CL-Load; PT-Status 'Reloaded the containers from the save and the saved labels.' }); $bS.Add_Click({ CL-SuggestEmpty }); $bC.Add_Click({ CL-ClearAll }); $bSave.Add_Click({ CL-Save })
  $bSet.Add_Click({ CL-SetSelected $script:PT.ClText.Text }); $bSug.Add_Click({ CL-SuggestSelected }); $bNo.Add_Click({ CL-SetSelected '' })
  $ui.ClText.Add_KeyDown({ param($s, $e) if ($e.KeyCode -eq 'Return') { $e.SuppressKeyPress = $true; CL-SetSelected $script:PT.ClText.Text } })
}
