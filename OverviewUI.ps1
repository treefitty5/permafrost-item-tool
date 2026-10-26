# OverviewUI.ps1 - the "Overview" window: a read-only report of everything the tool can see in the selected save
# (world, character, skills, inventory, recipes, quests, buildings, explored area, companion, in-game mods and settings, backups). Never writes to the save.
# Needs SaveCore.ps1, PlayerCore.ps1, WorldCore.ps1, Theme.ps1 and PlayerTools.ps1 (helpers) loaded.
$script:OV = @{}

# Steam build id of the installed game (from steamapps\appmanifest_2254990.acf), or '' when not found
function Get-InstalledGameBuild([string]$savePath, [string]$gameDir = '') {
  $dirs = New-Object System.Collections.Generic.List[string]
  if ($gameDir) { $dirs.Add($gameDir) }
  try { $g = Split-Path (Split-Path (Split-Path $savePath -Parent) -Parent) -Parent; if ($g) { $dirs.Add($g) } } catch { }
  foreach ($g in $dirs) {
    try { $acf = Join-Path (Split-Path (Split-Path $g -Parent) -Parent) 'appmanifest_2254990.acf'
      if (Test-Path -LiteralPath $acf) { $m = [regex]::Match((Get-Content -LiteralPath $acf -Raw), '"buildid"\s+"(\d+)"'); if ($m.Success) { return $m.Groups[1].Value } } } catch { }
  }
  return ''
}

function OV-Hdr([string]$t) { return @('', $t.ToUpper(), ('-' * $t.Length)) }

# returns the report as an array of text lines
function Get-SaveOverview([string]$savePath) {
  $L = New-Object System.Collections.Generic.List[string]
  function Sec([string]$title, [scriptblock]$body) {
    foreach ($x in (OV-Hdr $title)) { $L.Add($x) }
    try { foreach ($x in (& $body)) { $L.Add([string]$x) } } catch { $L.Add("  (could not read this part: $($_.Exception.Message))") }
  }
  $inv = [Globalization.CultureInfo]::InvariantCulture
  $names = @{}; try { foreach ($i in (Get-Content (Join-Path $PSScriptRoot 'items.json') -Raw | ConvertFrom-Json)) { $names[[string]$i.id] = $(if ($i.display) { [string]$i.display } else { [string]$i.id }) } } catch { }
  function Nm([string]$id) { if ($names.ContainsKey($id)) { return $names[$id] } else { return $id } }
  $pd = Get-PlayerData $savePath
  $text = Get-SaveText $savePath

  Sec 'World' {
    $h = '{0:0.0}' -f ($pd.Playtime / 3600)
    "  World:            $($pd.World)   ($([IO.Path]::GetFileName($savePath)), $([math]::Round((Get-Item -LiteralPath $savePath).Length / 1MB, 1)) MB)"
    "  Play time:        $h hours"
    "  Created:          $($pd.Created)"
    "  Last saved:       $($pd.Updated)"
    $gb = Get-InstalledGameBuild $savePath; $dp = $null; try { $dpp = Join-Path $PSScriptRoot 'datapack.json'; if (Test-Path -LiteralPath $dpp) { $dp = Get-Content -LiteralPath $dpp -Raw | ConvertFrom-Json } } catch { }
    if ($gb) { "  Installed game:   Steam build $gb" }
    if ($dp) { "  Data in this tool: made for Steam build $($dp.steamBuild) ($($dp.items) items)"; if ($gb -and [string]$dp.steamBuild -ne $gb) { "                     ^ the game was updated since; new items/recipes may be missing here" } }
  }
  Sec 'Character' {
    foreach ($v in $pd.Vitals) { '  {0,-16}  {1:0.#} / {2:0.#}' -f $v.Label, $v.Value, $v.Max }
    if ($pd.Position) { '  {0,-16}  X {1:N0}   Y {2:N0}   Z {3:N0}' -f 'Position', $pd.Position.X, $pd.Position.Y, $pd.Position.Z }
    if ($pd.Bed) { '  {0,-16}  X {1:N0}   Y {2:N0}   Z {3:N0}' -f 'Bed (respawn)', $pd.Bed.X, $pd.Bed.Y, $pd.Bed.Z }
    '  Skill points to spend: ' + $pd.Points
    $tu = Get-TeleportUndo $savePath; if ($tu) { "  Last teleport:    to $($tu.to), $($tu.at) - 'Undo last teleport' (Player tools) can put you back" }
  }
  Sec 'Skills' { foreach ($s in ($pd.Skills | Sort-Object Name)) { '  {0,-26} level {1}' -f $s.Name, $s.Level } }
  Sec 'Inventory' {
    $rows = @(Get-InventoryView $savePath)
    $hot = @($rows | Where-Object { $_.Where -eq 'Hotbar' }); $bp = @($rows | Where-Object { $_.Where -like 'Backpack*' })
    '  Hotbar:'
    foreach ($r in $hot) { '    slot {0}: {1}   {2}' -f $r.Slot, (Nm $r.Item), $r.Detail }
    if ($bp.Count) {
      $bpName = ($bp[0].Where -replace '^Backpack \(|\)$', ''); $cap = ''; $ovf = $null
      try { $eq = Parse-Equipment (Read-Save $savePath).Equip   # the size the tool counts: your Backpack slots setting (while its mod is on), else the game's own
        if ($eq) { $cap = " of $((Get-BackpackMaxSlot $eq) + 1) ($(Get-BackpackSource $eq))"; $ovf = BT-Overflow $eq } } catch { }
      ''; "  Backpack ($bpName): $($bp.Count) slot(s) used$cap"
      if ($ovf) { "  DANGER: an item sits in slot $($ovf.Highest + 1), beyond the $($ovf.Slots) slots the game will give this backpack - the game deletes such items when it saves."; "          Switch the in-game backpack mod on (Apply in game) or restore a backup before you play." }
      $tot = @{}; foreach ($r in $bp) { $n = 1; $m = [regex]::Match([string]$r.Detail, '^x(\d+)'); if ($m.Success) { $n = [int]$m.Groups[1].Value }; $tot[$r.Item] = [int]$tot[$r.Item] + $n }
      foreach ($k in ($tot.Keys | Sort-Object { -$tot[$_] }, { Nm $_ })) { '    {0,6} x  {1}' -f $tot[$k], (Nm $k) }
    }
  }
  Sec 'Recipes' {
    $total = $null; try { $total = @(Get-RecipeCatalog).Count } catch { }
    '  Recipes known: ' + @($pd.Known).Count + $(if ($total) { " of $total in the game" } else { '' })
  }
  Sec 'Quests' {
    $q = $pd.Quests
    '  Quests started: {0}    active now: {1}    unlocked regions: {2}' -f @($q.Quests).Count, @($q.Active).Count, @($q.Regions).Count
    $qn = @{}; try { $qp = Join-Path $PSScriptRoot 'catalog\quests-detail.csv'; if (Test-Path -LiteralPath $qp) { foreach ($r in (Import-Csv $qp)) { if ($r.Name) { $qn[$r.Quest] = $r.Name; if ($r.QuestID) { $qn[$r.QuestID] = $r.Name } } } } } catch { }
    foreach ($a in $q.Active) { $id = ([string]$a -replace '^.*/', '' -replace '\..*$', ''); $nm = $(if ($qn.ContainsKey($id)) { $qn[$id] } else { $id }); '    active: ' + $nm }
  }
  Sec 'Buildings you placed' {
    '  Parts placed: ' + @($pd.Parts).Count
    foreach ($g in ($pd.Parts | Group-Object Type | Sort-Object Count -Descending | Select-Object -First 25)) { '    {0,4} x  {1}' -f $g.Count, $g.Name }
  }
  Sec 'Explored world' {
    $w = Read-WorldCells $text; $cells = @($w.Cells); $recs = 0; $cont = 0; $opened = 0; $unopened = 0
    foreach ($c in $cells) { foreach ($r in $c.Recs) { $recs++; $be = $r.Get('bEverOpened'); if ($null -ne $be) { $cont++; if ($be -eq 'true') { $opened++ } else { $unopened++ } } } }
    $used = ([regex]::Matches($text, '\[rGUID>')).Count
    $disc = $null; try { $disc = @(Get-ExploredSquares $savePath).Count } catch { }
    if ($null -ne $disc) { "  Map squares discovered (50 m x 50 m, as on the Teleport map): $disc" }
    "  Map areas explored (loaded at least once): $($cells.Count)"
    "  Objects saved in those areas:              $recs"
    "  Containers found: $cont   (opened $opened, still unopened $unopened)"
    "  Objects used up (picked up / mined / destroyed): $used"
  }
  Sec 'Companion (dog)' {
    $m = [regex]::Match($text, '\[BEGIN_OBJECT_SAVE.{0,200}?PrimaryObjectName>BP_Companion[^\?]*\?.*?END_OBJECT_SAVE', 'Singleline')
    if ($m.Success) { $o = $m.Value; $st = [regex]::Match($o, 'State>([^\?]*)').Groups[1].Value; $bond = [regex]::Match($o, 'Bond>([^\?]*)').Groups[1].Value; $ci = [regex]::Match($o, 'CompanionInventory>([^\?]*)').Groups[1].Value
      '  State: {0}    bonded: {1}    items carried: {2}' -f $st, $bond, ([regex]::Matches($ci, '@\d+=')).Count } else { '  No companion found in this save.' }
  }
  Sec 'In-game mods and settings' {
    '  (these change the running game, never your save file)'
    $ms = $null; try { $ms = RT-ModStatus } catch { }
    if ($ms -and $ms.Text -notmatch 'Mods folder not found') {
      '  Recipe tweaks:    ' + $(if ($ms.Ok) { 'mod on.  ' } else { 'mod not on.  ' }) + ($ms.Text -replace '\s+(start-up|spawned in the world):.*$', '')
      $bm = $null; try { $bm = BM-Status } catch { }; if ($bm) { '  Build move:       ' + $bm.Text }
      $bt = $null; try { $bt = BT-ModStatus } catch { }
      if ($bt) { $set = @(); try { $h = Get-BackpackTweaks; foreach ($k in ($h.Keys | Sort-Object)) { $set += "$k = $($h[$k]) slots" } } catch { }
        '  Backpack size:    ' + $bt.Text + $(if ($set.Count) { '  Your sizes: ' + ($set -join ', ') + '.' } else { '  No size set (the game''s own sizes are used).' }) }
      $stt = $null; try { $stt = ST-ModStatus } catch { }
      if ($stt) { $sc = Get-StackConfig; $sm = ST-SummaryText $sc
        '  Stack sizes:      ' + $stt.Text + '  Setting: ' + $(if ($sm) { $sm + ' (per slot).' } else { 'off (every item keeps the game''s own stack size).' })
        try { $fs = ST-FindStacks $savePath
          if ($fs.Stacks -gt 0) { "                    Stacks bigger than the game allows in your save: $($fs.Stacks)  ($($fs.Extra) items too many; $($fs.Player) in your inventory, $($fs.Containers) in containers)"
            $dg = ST-DangerText $fs $sc; if ($dg) { '                    ' + $dg } } } catch { } }
      $wts = $null; try { $wts = WT-ModStatus } catch { }
      if ($wts) { $wsm = ''; try { $wsm = WT-SummaryText } catch { }
        '  Weapon damage:    ' + $wts.Text + '  Setting: ' + $(if ($wsm) { $wsm + '.' } else { 'none (every weapon keeps the game''s own damage).' }) }
      $gss = $null; try { $gss = GS-ModStatus } catch { }
      if ($gss) { $gsl = ''; try { $gsl = GS-LastResult } catch { }
        '  Teleport ground:  ' + $gss.Text + $(if ($gsl) { '  Last time in the game: ' + $gsl } else { '' }) }
    } else { '  UE4SS (the free script loader the mods need) was not found next to your save, so none of the in-game mods can be installed from here.' }
  }
  Sec 'Backups of this world' {
    $leaf = [IO.Path]::GetFileName($savePath); $bk = @(Get-ChildItem (Get-BackupDir) -Filter "*_$leaf" -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '_NEW_' })
    "  $($bk.Count) backup(s) in the Backups folder" + $(if ($bk.Count) { "   (newest: $(($bk | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime.ToString('g')))" } else { '' })
    $sn = @($bk | Where-Object { $_.Name -match '_BASELINE_' }); if ($sn.Count) { "  Starting snapshot: yes ($($sn[0].Name)) - World reset's best source for container loot" } else { '  Starting snapshot: none (the tool only makes one for a world that has no backup the first time it opens it)' }
  }
  return $L.ToArray()
}

function OV-Fill {
  $u = $script:OV; $u.Status.Text = 'Reading the save...'; [System.Windows.Forms.Application]::DoEvents()
  try { $u.Out.Text = ((Get-SaveOverview $u.Path) -join "`r`n").TrimStart(); $u.Status.Text = "Read-only report of $([IO.Path]::GetFileName($u.Path)) - nothing here changes your save." }
  catch { $u.Out.Text = "Could not read this save: $($_.Exception.Message)"; $u.Status.Text = '' }
}

function New-OverviewForm([string]$savePath) {
  Add-Type -AssemblyName System.Windows.Forms; Add-Type -AssemblyName System.Drawing
  $script:OV = @{ Path = $savePath }; $u = $script:OV
  $f = New-Object System.Windows.Forms.Form; $f.Text = 'Overview  -  a read-only report of your save'; $f.Size = New-Object System.Drawing.Size(860, 760); $f.MinimumSize = New-Object System.Drawing.Size(640, 480)
  $f.StartPosition = 'CenterParent'; $f.Font = New-Object System.Drawing.Font('Segoe UI', 9); $u.Form = $f
  $u.Out = New-Object System.Windows.Forms.TextBox; $u.Out.Multiline = $true; $u.Out.ReadOnly = $true; $u.Out.ScrollBars = 'Vertical'; $u.Out.WordWrap = $false; $u.Out.Font = New-Object System.Drawing.Font('Consolas', 9.5)
  $u.Out.Location = '12,12'; $u.Out.Size = '820,640'; $u.Out.Anchor = 'Top,Left,Right,Bottom'; $f.Controls.Add($u.Out)
  $bR = New-Btn $f 'Refresh' 12 668 110 30; $bR.Anchor = 'Left,Bottom'; $bC = New-Btn $f 'Copy report' 130 668 120 30; $bC.Anchor = 'Left,Bottom'
  $u.Status = New-Lbl $f '' 262 674 570 20; $u.Status.Anchor = 'Left,Right,Bottom'; $u.Status.ForeColor = $script:Th.Muted
  $bR.Add_Click({ OV-Fill }); $bC.Add_Click({ try { [System.Windows.Forms.Clipboard]::SetText($script:OV.Out.Text); $script:OV.Status.Text = 'Report copied to the clipboard.' } catch { } })
  $f.Add_Shown({ OV-Fill })
  Apply-Theme $f; Set-AppIcon $f
  return $f
}
function Show-Overview($owner, [string]$savePath) { $f = New-OverviewForm $savePath; $script:ActiveForm = $f; try { [void]$f.ShowDialog($owner) } finally { $script:ActiveForm = $null } }
