# StackTweaks.ps1 - the "Stack sizes" window (banner button): choose, item by item, how many of an item fit in one slot.
# The limit belongs to the item's game data, so it works in every inventory (hotbar, backpack, containers); a small UE4SS mod (StackSizesMod\main.lua) sets it while the game runs.
# Nothing in your save is touched by the mod.
#   * First aid kits normally take one slot each because they carry a durability (the "condition"): a stack would share ONE condition and waste kits.
#     So a stacked kit is also made SINGLE USE (durability off): every use consumes one whole kit, like a bandage.
#   * Panacea (and both splints) have a stack limit in the game data but NO stackable flag, so they never stack; the mod sets the flag and a size.
#   * Surgical Spirit, Painkillers and the bandages already stack (10 / 5 / 5); the mod just raises the size.
# DANGER (tested): with the mod off the game trims every stack above the item's own limit the next time it saves, so the tool refuses to switch an item off
# (or lower it) while such stacks exist, backs up your save when you apply, and shows a red warning when stacks exist and the mod is not on.
# Settings file stack-tweaks.json: { "version": 2, "items": { "<save id>": { "enabled": true, "size": 10 }, ... } } (the older kits / meds format is read and converted).
# Needs RecipeTweaks.ps1 (RT-ModsDir), SaveCore.ps1 (Get-InventoryView, Get-BackupDir), WorldCore.ps1 (Read-WorldCells).
$script:StTweakPathOverride = $null     # tests point this at a temporary file
$script:StStatusCache = $null
$script:StMaxSize = 20                  # 20 is what food stacks to in the game; bigger sizes were never tried
$script:StConfirmAbove = 10             # a stacked kit above this was not tried in the game
# Group = heading in the window; Base = what ONE slot holds without the mod (1 = does not stack); Default = size offered the first time
$script:StItems = @(
  @{ Id = 'MedkitAFAK';       Asset = 'DA_Consumable_Medication_AFAK_Medkit';       Name = 'Medkit AFAK';       Group = 'First aid kits'; Base = 1;  Default = 10; SingleUse = $true }
  @{ Id = 'MedkitMFAK';       Asset = 'DA_Consumable_Medication_MFAK_Medkit';       Name = 'Medkit MFAK';       Group = 'First aid kits'; Base = 1;  Default = 10; SingleUse = $true }
  @{ Id = 'MedkitIFAK';       Asset = 'DA_Consumable_Medication_IFAK_Medkit';       Name = 'Medkit IFAK';       Group = 'First aid kits'; Base = 1;  Default = 10; SingleUse = $true }
  @{ Id = 'CarMedkit';        Asset = 'DA_Consumable_Medication_Car_Medkit';        Name = 'Car Medkit';        Group = 'First aid kits'; Base = 1;  Default = 10; SingleUse = $true }
  @{ Id = 'Panacea';          Asset = 'DA_Consumable_Medication_Panacea';           Name = 'Panacea';           Group = 'Medicine';       Base = 1;  Default = 20; SingleUse = $false }
  @{ Id = 'SurgicalSpirit';   Asset = 'DA_Consumable_Medication_SurgicalSpirit';    Name = 'Surgical Spirit';   Group = 'Medicine';       Base = 10; Default = 20; SingleUse = $false }
  @{ Id = 'Painkillers';      Asset = 'DA_Consumable_Medication_Painkillers';       Name = 'Painkillers';       Group = 'Medicine';       Base = 5;  Default = 20; SingleUse = $false }
  @{ Id = 'Bandage';          Asset = 'DA_Consumable_Medication_Bandage';           Name = 'Bandage';           Group = 'Bandages';       Base = 5;  Default = 10; SingleUse = $false }
  @{ Id = 'MakeshiftBandage'; Asset = 'DA_Consumable_Medication_MakeshiftBandage';  Name = 'Makeshift Bandage'; Group = 'Bandages';       Base = 5;  Default = 10; SingleUse = $false }
  @{ Id = 'MilitaryBandage';  Asset = 'DA_Consumable_Medication_MilitaryBandage';   Name = 'Military Bandage';  Group = 'Bandages';       Base = 5;  Default = 10; SingleUse = $false }
)
$script:StById = @{}; foreach ($it in $script:StItems) { $it.Min = [math]::Max(2, $it.Base); $script:StById[$it.Id] = $it }
$script:StGroupNames = @('First aid kits', 'Medicine', 'Bandages')

function ST-TweakPath { if ($script:StTweakPathOverride) { return $script:StTweakPathOverride }; return (Join-Path $PSScriptRoot 'stack-tweaks.json') }
function ST-ModsDir { return (RT-ModsDir) }
function ST-ModDir { return (Join-Path (ST-ModsDir) 'StackSizes') }

# ---------------- settings ----------------
# @{ <save id> = @{ Enabled; Size } } for every item in the list (items not in the file are off, at their default size)
function Get-StackConfig {
  $cfg = @{}; foreach ($it in $script:StItems) { $cfg[$it.Id] = @{ Enabled = $false; Size = $it.Default } }
  $p = ST-TweakPath
  if (Test-Path -LiteralPath $p) {
    try {
      $o = Get-Content -LiteralPath $p -Raw | ConvertFrom-Json
      if ($null -ne $o.items) {
        foreach ($pr in $o.items.PSObject.Properties) { if ($script:StById.ContainsKey($pr.Name)) { $it = $script:StById[$pr.Name]
          $sz = [int]$pr.Value.size; if ($sz -lt $it.Min -or $sz -gt $script:StMaxSize) { $sz = $it.Default }
          $cfg[$pr.Name] = @{ Enabled = [bool]$pr.Value.enabled; Size = $sz } } }
      } else {   # the first format: one size for all kits ('kits') and one for the medicine group ('meds')
        if ($null -ne $o.kits) { foreach ($id in 'MedkitAFAK', 'MedkitMFAK', 'MedkitIFAK', 'CarMedkit') { $cfg[$id] = @{ Enabled = [bool]$o.kits.enabled; Size = [math]::Min([math]::Max([int]$o.kits.size, 2), $script:StMaxSize) } } }
        if ($null -ne $o.meds) { foreach ($id in 'Panacea', 'SurgicalSpirit', 'Painkillers', 'MilitaryBandage') { $it = $script:StById[$id]; $cfg[$id] = @{ Enabled = [bool]$o.meds.enabled; Size = [math]::Min([math]::Max([int]$o.meds.size, $it.Min), $script:StMaxSize) } } }
      }
    } catch { }
  }
  return $cfg
}
function ST-SaveConfig($cfg) {
  $items = [ordered]@{}; foreach ($it in $script:StItems) { $c = $cfg[$it.Id]; $items[$it.Id] = [ordered]@{ enabled = [bool]$c.Enabled; size = [int]$c.Size } }
  ([ordered]@{ version = 2; items = $items } | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath (ST-TweakPath) -Encoding utf8
  $script:StStatusCache = $null
}
# tweaks.lua in the mod folder (when the mod is installed): only items that are switched on are listed
function ST-WriteLua($cfg = $null) {
  if (-not $cfg) { $cfg = Get-StackConfig }
  $lua = New-Object System.Text.StringBuilder
  [void]$lua.AppendLine('-- Written by the Permafrost Item Tool ("Stack sizes" window). Items not listed keep the game''s own stack size and durability.')
  [void]$lua.AppendLine('return {'); [void]$lua.AppendLine('  version = 1,'); [void]$lua.AppendLine('  stacks = {')
  foreach ($it in $script:StItems) { if ($cfg[$it.Id].Enabled) { [void]$lua.AppendLine(("    {0} = {1}," -f $it.Asset, $cfg[$it.Id].Size)) } }
  [void]$lua.AppendLine('  },'); [void]$lua.AppendLine('  singleuse = {')
  foreach ($it in $script:StItems) { if ($cfg[$it.Id].Enabled -and $it.SingleUse) { [void]$lua.AppendLine(("    {0} = true," -f $it.Asset)) } }
  [void]$lua.AppendLine('  },'); [void]$lua.AppendLine('}')
  $dir = ST-ModDir; if (-not (Test-Path -LiteralPath $dir)) { return $false }
  [IO.File]::WriteAllText((Join-Path $dir 'tweaks.lua'), $lua.ToString(), (New-Object Text.UTF8Encoding($false))); return $true
}
function ST-SummaryText($cfg = $null) {   # "Medkit AFAK 10, Panacea 20" or ''
  if (-not $cfg) { $cfg = Get-StackConfig }
  return ((@($script:StItems | Where-Object { $cfg[$_.Id].Enabled } | ForEach-Object { "$($_.Name) $($cfg[$_.Id].Size)" })) -join ', ')
}

# ---------------- the in-game mod ----------------
function ST-ModStatus {   # Installed / Enabled / UpToDate / Active / Text
  $r = @{ Installed = $false; Enabled = $false; UpToDate = $false; Active = $false; Text = '' }
  $dir = ST-ModDir; $main = Join-Path $dir 'Scripts\main.lua'; $src = Join-Path $PSScriptRoot 'StackSizesMod\main.lua'
  if (-not (Test-Path -LiteralPath (ST-ModsDir))) { $r.Text = 'UE4SS Mods folder not found next to your save - the game mod cannot be installed from here.'; return $r }
  $r.Installed = Test-Path -LiteralPath $main
  $mt = Join-Path (ST-ModsDir) 'mods.txt'; $r.Enabled = (Test-Path -LiteralPath $mt) -and ((Get-Content -LiteralPath $mt -Raw) -match '(?m)^\s*StackSizes\s*:\s*1')
  $r.UpToDate = $r.Installed -and (-not (Test-Path -LiteralPath $src) -or ((Get-FileHash -LiteralPath $main).Hash -eq (Get-FileHash -LiteralPath $src).Hash))
  $r.Active = $r.Installed -and $r.Enabled
  $r.Text = if (-not $r.Installed) { 'The in-game mod (StackSizes) is not installed yet.' } elseif (-not $r.Enabled) { 'The mod is installed but switched OFF in mods.txt.' } elseif (-not $r.UpToDate) { 'The in-game mod is an older version - press Apply to update it.' } else { 'The in-game mod is installed and on.' }
  return $r
}
function ST-ModActive {   # cached for a couple of seconds
  try { if ($script:StStatusCache -and ((Get-Date) - $script:StStatusCache.At).TotalSeconds -lt 2) { return $script:StStatusCache.Active }
    $a = [bool](ST-ModStatus).Active; $script:StStatusCache = @{ At = (Get-Date); Active = $a }; return $a } catch { return $false }
}
function ST-InstallMod {
  $mods = ST-ModsDir; if (-not (Test-Path -LiteralPath $mods)) { throw "UE4SS Mods folder not found: $mods" }
  $src = Join-Path $PSScriptRoot 'StackSizesMod\main.lua'; if (-not (Test-Path -LiteralPath $src)) { throw 'StackSizesMod\main.lua is missing next to the tool.' }
  $dir = ST-ModDir; New-Item -ItemType Directory -Force (Join-Path $dir 'Scripts') | Out-Null
  Copy-Item -LiteralPath $src -Destination (Join-Path $dir 'Scripts\main.lua') -Force
  [void](ST-WriteLua (Get-StackConfig))
  $mt = Join-Path $mods 'mods.txt'; $lines = New-Object System.Collections.Generic.List[string]; if (Test-Path -LiteralPath $mt) { foreach ($l in (Get-Content -LiteralPath $mt)) { $lines.Add($l) } }
  $bk = "$mt.bak-before-stacksizes"; if ((Test-Path -LiteralPath $mt) -and -not (Test-Path -LiteralPath $bk)) { Copy-Item -LiteralPath $mt -Destination $bk }
  $ix = -1; for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*StackSizes\s*:') { $ix = $i; break } }
  if ($ix -ge 0) { $lines[$ix] = 'StackSizes : 1' }
  else { $cm = -1; for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*;.*[Bb]uilt-in keybinds') { $cm = $i; break } }
    $last = -1; $lim = $(if ($cm -ge 0) { $cm } else { $lines.Count }); for ($i = 0; $i -lt $lim; $i++) { if ($lines[$i] -match '^\S+\s*:\s*[01]\s*$') { $last = $i } }
    $lines.Insert($last + 1, 'StackSizes : 1') }
  [IO.File]::WriteAllText($mt, (($lines -join "`r`n") + "`r`n"), (New-Object Text.UTF8Encoding($false)))
  $script:StStatusCache = $null
}

# ---------------- stacks in your save ----------------
$script:StIdRx = '@\d+=(' + (($script:StItems | ForEach-Object { $_.Id }) -join '|') + ')&(\d+)'
$script:StQuickRx = (($script:StItems | ForEach-Object { $_.Id }) -join '|')
# '@0=MedkitAFAK&4&200.0@1=Bandage&3' -> @(@{Id='MedkitAFAK'; N=4}, @{Id='Bandage'; N=3})
function ST-ItemCounts([string]$inv) {
  $out = @(); if (-not $inv) { return $out }
  foreach ($m in [regex]::Matches($inv, $script:StIdRx)) { $out += @{ Id = $m.Groups[1].Value; N = [int]$m.Groups[2].Value } }
  return $out
}
# Items = per item @{ Max (biggest stack); Stacks / Extra (stacks above what the game allows on its own, and how many items too many); Player; Containers }; Stacks / Extra / Player / Containers also as totals
function ST-FindStacks([string]$savePath, [switch]$SkipContainers) {
  $res = @{ Items = @{}; Stacks = 0; Extra = 0; Player = 0; Containers = 0 }
  foreach ($it in $script:StItems) { $res.Items[$it.Id] = @{ Max = 1; Stacks = 0; Extra = 0; Player = 0; Containers = 0 } }
  $add = { param($id, $n, $where)
    $r = $res.Items[$id]; if ($n -gt $r.Max) { $r.Max = $n }; $b = $script:StById[$id].Base
    if ($n -gt $b) { $r.Stacks++; $r.Extra += ($n - $b); $res.Stacks++; $res.Extra += ($n - $b); if ($where -eq 'p') { $r.Player++; $res.Player++ } else { $r.Containers++; $res.Containers++ } } }
  try { foreach ($r in (Get-InventoryView $savePath)) { if ($script:StById.ContainsKey([string]$r.Item) -and ([string]$r.Detail) -match '^x(\d+)') { & $add ([string]$r.Item) ([int]$Matches[1]) 'p' } } } catch { }
  if (-not $SkipContainers) {
    try { $t = [Text.Encoding]::Latin1.GetString([IO.File]::ReadAllBytes($savePath)); $w = Read-WorldCells $t
      foreach ($c in $w.Cells) { foreach ($r in $c.Recs) { $inv = $r.Get('Inventory'); if ($inv -and $inv -match $script:StQuickRx) { foreach ($m in (ST-ItemCounts $inv)) { & $add $m.Id $m.N 'c' } } } }
    } catch { }
  }
  return $res
}

# a copy of the save before the setting changes (not made while the game runs); returns the path or $null
function ST-BackupSave([string]$savePath) {
  if (-not $savePath -or -not (Test-Path -LiteralPath $savePath)) { return $null }
  if (Test-GameRunning) { return $null }
  $dest = Join-Path (Get-BackupDir) ((Get-Date -Format 'yyyyMMdd-HHmmss') + '_STACKSIZES_' + [IO.Path]::GetFileName($savePath))
  Copy-Item -LiteralPath $savePath -Destination $dest -Force
  if ((Get-FileHash -LiteralPath $dest).Hash -ne (Get-FileHash -LiteralPath $savePath).Hash) { Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue; return $null }
  return $dest
}

# DANGER = stacks above the game's own limit exist in the save but the setting is not in force for that item (off, or the mod is not installed / not switched on): the game would trim them at its next save
function ST-DangerText($found, $cfg = $null) {
  if (-not $found -or $found.Stacks -lt 1) { return $null }
  if (-not $cfg) { $cfg = Get-StackConfig }
  $modOn = ST-ModActive; $bad = @(); $extra = 0
  foreach ($it in $script:StItems) { $r = $found.Items[$it.Id]; if ($r.Stacks -gt 0 -and -not ($cfg[$it.Id].Enabled -and $modOn)) { $bad += $it.Name; $extra += $r.Extra } }
  if ($bad.Count -eq 0) { return $null }
  return "DANGER: your save holds stacks of $($bad -join ', ') bigger than the game allows ($extra items too many) but the Stack sizes mod is not on for them: the game deletes the extra items at its next save."
}
# true when something in the save is at risk - for the red line in the main window
function ST-AnyDanger([string]$savePath, [switch]$SkipContainers) { return [bool](ST-DangerText (ST-FindStacks $savePath -SkipContainers:$SkipContainers)) }

# $cfg = the settings about to be applied, $found = ST-FindStacks result. Refuses to switch an item OFF while its stacks exist, and to go below its biggest existing stack
function ST-CheckConfig($cfg, $found) {
  foreach ($it in $script:StItems) {
    $c = $cfg[$it.Id]; $r = $null; if ($found) { $r = $found.Items[$it.Id] }
    if ($c.Enabled -and ($c.Size -lt $it.Min -or $c.Size -gt $script:StMaxSize)) { throw "$($it.Name): the stack size must be between $($it.Min) and $($script:StMaxSize)." }
    if (-not $r) { continue }
    if (-not $c.Enabled -and $r.Stacks -gt 0) { throw "NOT APPLIED - nothing was changed.`n`nYour save holds $($r.Stacks) stack(s) of $($it.Name) bigger than the game allows ($($r.Extra) items too many; $($r.Player) in your inventory, $($r.Containers) in containers). With this item switched off the game deletes the extra items the next time it saves.`n`nFirst use them up (or take them out one at a time), then switch $($it.Name) off." }
    if ($c.Enabled -and $r.Max -gt 1 -and $c.Size -lt $r.Max) { throw "NOT APPLIED - nothing was changed.`n`nYour biggest stack of $($it.Name) holds $($r.Max). A size of $($c.Size) would make the game trim it on the next save and delete the extra items. Pick at least $($r.Max), or use them first." }
  }
}
function Set-StackConfig($cfg, $found) {
  ST-CheckConfig $cfg $found
  ST-SaveConfig $cfg
  return @{ Wrote = (ST-WriteLua $cfg) }
}

# ---------------- the window ----------------
function ST-WinRefresh {
  $u = $script:STW; $st = ST-ModStatus; $found = ST-FindStacks $u.Save; $u.Found = $found; $cfg = Get-StackConfig
  $u.ModState.Text = $st.Text; $u.ModState.ForeColor = $(if ($st.Active -and $st.UpToDate) { [System.Drawing.Color]::LightGreen } else { [System.Drawing.Color]::Orange })
  foreach ($it in $script:StItems) { $r = $found.Items[$it.Id]; $lb = $u.Rows[$it.Id].Info
    $lb.Text = $(if ($r.Max -gt 1) { "biggest stack in your save: $($r.Max)" + $(if ($r.Stacks -gt 0) { '  (needs the mod)' } else { '' }) } else { 'none stacked in your save' })
    $lb.ForeColor = $(if ($r.Stacks -gt 0) { [System.Drawing.Color]::Orange } else { $script:Th.Muted }) }
  $u.StackState.Text = $(if ($found.Stacks -gt 0) { "Your save holds $($found.Stacks) stack(s) bigger than the game allows ($($found.Extra) items too many): $($found.Player) in your inventory, $($found.Containers) in containers." } else { 'Your save holds no stacks bigger than the game allows on its own.' })
  $d = ST-DangerText $found $cfg; $u.Warn.Text = $(if ($d) { $d } else { '' })
}
function ST-WinConfig {   # the settings as they stand in the window
  $u = $script:STW; $cfg = @{}
  foreach ($it in $script:StItems) { $row = $u.Rows[$it.Id]; $cfg[$it.Id] = @{ Enabled = [bool]$row.Chk.Checked; Size = [int]$row.Num.Value } }
  return $cfg
}
function ST-WinApply {
  $u = $script:STW
  try {
    $cfg = ST-WinConfig; $found = ST-FindStacks $u.Save
    ST-CheckConfig $cfg $found     # refuses first: nothing is installed, backed up or written
    $bigKits = @($script:StItems | Where-Object { $_.SingleUse -and $cfg[$_.Id].Enabled -and $cfg[$_.Id].Size -gt $script:StConfirmAbove })
    if ($bigKits.Count -gt 0 -and -not $script:TestMode) {
      if ((Msg "Stacks of more than $($script:StConfirmAbove) first aid kits were not tried in the game (stacks of 5 and 10 were). It should work the same, but please try it on a spare save first if you are unsure.`n`nGo ahead?" 'Stack sizes' 'YesNo' 'Question' 'Button2') -ne 'Yes') { return } }
    $any = @($script:StItems | Where-Object { $cfg[$_.Id].Enabled }).Count -gt 0
    $st = ST-ModStatus
    if ($any -and -not ($st.Active -and $st.UpToDate)) {
      if (-not $script:TestMode) {
        if ((Msg "Stacking items needs a small in-game mod (StackSizes, for UE4SS). It only changes numbers inside the running game and never touches your save. IMPORTANT: if the mod is ever not running, the game deletes every item beyond its own limit in a slot when it saves.`n`nInstall it now?" 'Stack sizes' 'YesNo' 'Question') -ne 'Yes') { return } }
      ST-InstallMod }
    $bk = ST-BackupSave $u.Save
    [void](Set-StackConfig $cfg $found)
    $sum = ST-SummaryText $cfg
    $u.Msg.Text = $(if ($sum) { "Saved: $sum. Items that are not ticked keep the game's own stack size." } else { 'Saved: nothing is stacked beyond the game''s own limits.' }) + " It applies every time the game starts, before your save loads." + $(if ($bk) { " A backup of your save was made first ($(Split-Path $bk -Leaf))." } else { ' No backup was made (the game is running or the copy failed).' }) + $(if (Test-GameRunning) { ' The game is running: restart it for the change.' } else { '' })
  } catch { $u.Msg.Text = ''; [void](Msg $_.Exception.Message 'Stack sizes - not applied' 'OK' 'Warning') }
  ST-WinRefresh
}
function New-StackSizesForm([string]$savePath) {
  Add-Type -AssemblyName System.Windows.Forms; Add-Type -AssemblyName System.Drawing
  $script:STW = @{ Save = $savePath; Rows = @{} }; $u = $script:STW; $cfg = Get-StackConfig
  $f = New-Object System.Windows.Forms.Form; $f.Text = 'Stack sizes  -  how many of each item fit in one slot'; $f.Size = New-Object System.Drawing.Size(800, [math]::Min(860, [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea.Height - 30)); $f.MinimumSize = New-Object System.Drawing.Size(740, 640)
  $f.StartPosition = 'CenterParent'; $f.Font = New-Object System.Drawing.Font('Segoe UI', 9); $u.Form = $f
  $by = $f.ClientSize.Height - 304     # top of the block of buttons and notes at the bottom; the list of items gets the rest
  $intro = New-Lbl $f "Tick an item and pick how many fit in one slot. It works everywhere (backpack, hotbar, containers) through a small in-game mod and never touches your save. First aid kits normally take one slot each because they carry a durability: a stack would share ONE condition and waste kits, so stacked kits are made single use (every use consumes one whole kit; a small wound costs a whole kit)." 14 10 760 62; $intro.Anchor = 'Top,Left,Right'
  # the list of items sits in a scrolling panel, so a small screen never cuts it off
  $pn = New-Object System.Windows.Forms.Panel; $pn.Location = '10,78'; $pn.Size = New-Object System.Drawing.Size(772, ($by - 86)); $pn.AutoScroll = $true; $pn.Anchor = 'Top,Left,Right,Bottom'; $f.Controls.Add($pn); $u.Panel = $pn
  $y = 4
  foreach ($gn in $script:StGroupNames) {
    $items = @($script:StItems | Where-Object { $_.Group -eq $gn })
    $g = New-Object ThemedGroup; $g.Text = $gn; $g.Location = New-Object System.Drawing.Point(2, $y); $g.Size = New-Object System.Drawing.Size(740, (30 + 30 * $items.Count)); $g.Anchor = 'Top,Left,Right'; $pn.Controls.Add($g)
    $ry = 26
    foreach ($it in $items) {
      $c = $cfg[$it.Id]
      $chk = New-Object System.Windows.Forms.CheckBox; $chk.Text = $it.Name; $chk.Location = New-Object System.Drawing.Point(14, $ry); $chk.Size = New-Object System.Drawing.Size(190, 24); $chk.Checked = [bool]$c.Enabled; $g.Controls.Add($chk)
      $lim = $(if ($it.Base -le 1) { "game: does not stack" } else { "game: $($it.Base) per slot" })
      $lbl = New-Object System.Windows.Forms.Label; $lbl.AutoSize = $false; $lbl.Text = $lim; $lbl.Location = New-Object System.Drawing.Point(208, ($ry + 3)); $lbl.Size = New-Object System.Drawing.Size(132, 20); $lbl.ForeColor = $script:Th.Muted; $g.Controls.Add($lbl)
      $num = New-Object System.Windows.Forms.NumericUpDown; $num.Location = New-Object System.Drawing.Point(346, ($ry + 1)); $num.Size = New-Object System.Drawing.Size(62, 24); $num.Minimum = $it.Min; $num.Maximum = $script:StMaxSize; $num.Value = [math]::Min([math]::Max([decimal]$c.Size, $num.Minimum), $num.Maximum); $g.Controls.Add($num)
      $inf = New-Object System.Windows.Forms.Label; $inf.AutoSize = $false; $inf.Text = ''; $inf.Location = New-Object System.Drawing.Point(420, ($ry + 3)); $inf.Size = New-Object System.Drawing.Size(310, 20); $inf.Anchor = 'Top,Left,Right'; $g.Controls.Add($inf)
      $u.Rows[$it.Id] = @{ Chk = $chk; Num = $num; Info = $inf }
      $ry += 30 }
    $y += $g.Height + 8 }
  # quick buttons
  $bTick = New-Btn $f 'Tick all' 14 $by 90 28; $bUntick = New-Btn $f 'Untick all' 110 $by 90 28
  $bSet = New-Btn $f 'Set ticked to' 214 $by 110 28; $u.NumAll = New-Num $f 330 ($by + 2) 62 2 $script:StMaxSize 0; $u.NumAll.Value = 10
  $bTick.Anchor = 'Left,Bottom'; $bUntick.Anchor = 'Left,Bottom'; $bSet.Anchor = 'Left,Bottom'; $u.NumAll.Anchor = 'Left,Bottom'
  $bTick.Add_Click({ foreach ($it in $script:StItems) { $script:STW.Rows[$it.Id].Chk.Checked = $true } })
  $bUntick.Add_Click({ foreach ($it in $script:StItems) { $script:STW.Rows[$it.Id].Chk.Checked = $false } })
  $bSet.Add_Click({ $v = [decimal]$script:STW.NumAll.Value; foreach ($it in $script:StItems) { $row = $script:STW.Rows[$it.Id]; if ($row.Chk.Checked) { $row.Num.Value = [math]::Min([math]::Max($v, $row.Num.Minimum), $row.Num.Maximum) } } })
  $lm = New-Lbl $f 'The in-game mod' 14 ($by + 36) 110; $lm.Anchor = 'Left,Bottom'
  $u.ModState = New-Lbl $f '' 130 ($by + 36) 640 22; $u.ModState.Anchor = 'Left,Right,Bottom'
  $ls = New-Lbl $f 'In your save' 14 ($by + 60) 110; $ls.Anchor = 'Left,Bottom'
  $u.StackState = New-Lbl $f '' 130 ($by + 60) 640 22; $u.StackState.Anchor = 'Left,Right,Bottom'
  $u.Warn = New-Lbl $f '' 14 ($by + 86) 760 36; $u.Warn.ForeColor = [System.Drawing.Color]::Tomato; $u.Warn.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold); $u.Warn.Anchor = 'Left,Right,Bottom'
  $u.Apply = New-Btn $f 'Apply' 14 ($by + 126) 150 34; $u.Apply.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold); $u.Apply.Anchor = 'Left,Bottom'
  $close = New-Btn $f 'Close' 174 ($by + 126) 100 34; $close.Anchor = 'Left,Bottom'
  $u.Msg = New-Lbl $f '' 14 ($by + 166) 760 60; $u.Msg.ForeColor = $script:Th.Accent; $u.Msg.Anchor = 'Left,Right,Bottom'
  $note = New-Lbl $f "IMPORTANT (tested): if the mod is not running, the game trims every stack above the item's own limit the next time it saves and the extra items are gone for good. So the tool refuses to switch an item off (or lower it) while such stacks exist, makes a backup each time you apply, and shows a red warning in the main window if they exist and the mod is not on. If you remove the mod, UE4SS stops loading, or the game updates, check this window before you play." 14 ($by + 230) 760 70; $note.ForeColor = $script:Th.Muted; $note.Anchor = 'Left,Right,Bottom'
  $u.Apply.Add_Click({ ST-WinApply }); $close.Add_Click({ $script:STW.Form.Close() })
  ST-WinRefresh
  Apply-Theme $f; Set-AppIcon $f
  $u.ModState.ForeColor = $(if ((ST-ModStatus).Active) { [System.Drawing.Color]::LightGreen } else { [System.Drawing.Color]::Orange }); $u.Warn.ForeColor = [System.Drawing.Color]::Tomato
  foreach ($it in $script:StItems) { $u.Rows[$it.Id].Info.ForeColor = $script:Th.Muted }
  ST-WinRefresh
  return $f
}
function Show-StackSizes($owner, [string]$savePath) { $f = New-StackSizesForm $savePath; $script:ActiveForm = $f; try { [void]$f.ShowDialog($owner) } finally { $script:ActiveForm = $null } }
