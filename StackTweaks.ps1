# StackTweaks.ps1 - the "Stack sizes" window (banner button): first aid kits that STACK and are SINGLE USE.
# Kits normally take one slot each because they carry a durability (the "condition"): a stack would share ONE condition and waste kits. With this setting the
# StackSizes UE4SS mod (StackSizesMod\main.lua) marks the kits stackable AND turns their durability off, so every use consumes one whole kit, like a bandage.
# The limit belongs to the item, so it works in every inventory (hotbar, backpack, containers). Nothing in your save is touched by the mod.
# DANGER (tested): with the mod off the game trims a stack of kits to 1 the next time it saves, so the tool refuses to switch the setting off while stacks exist.
# Needs RecipeTweaks.ps1 (RT-ModsDir), SaveCore.ps1 (Get-InventoryView, Get-BackupDir), WorldCore.ps1 (Read-WorldCells).
$script:StTweakPathOverride = $null     # tests point this at a temporary file
$script:StStatusCache = $null
$script:StKitIds = @('MedkitAFAK', 'MedkitIFAK', 'MedkitMFAK', 'CarMedkit')
$script:StKitAssets = [ordered]@{ MedkitAFAK = 'DA_Consumable_Medication_AFAK_Medkit'; MedkitIFAK = 'DA_Consumable_Medication_IFAK_Medkit'; MedkitMFAK = 'DA_Consumable_Medication_MFAK_Medkit'; CarMedkit = 'DA_Consumable_Medication_Car_Medkit' }
$script:StDefaultSize = 10
$script:StMinSize = 2
$script:StMaxSize = 20
$script:StConfirmAbove = 10             # sizes above this were not tried in the game (raise it when a bigger size has been tested)

function ST-TweakPath { if ($script:StTweakPathOverride) { return $script:StTweakPathOverride }; return (Join-Path $PSScriptRoot 'stack-tweaks.json') }
function ST-ModsDir { return (RT-ModsDir) }
function ST-ModDir { return (Join-Path (ST-ModsDir) 'StackSizes') }

function Get-StackTweaks {   # @{ Enabled; Size }
  $r = @{ Enabled = $false; Size = $script:StDefaultSize }; $p = ST-TweakPath
  if (Test-Path -LiteralPath $p) { try { $o = Get-Content -LiteralPath $p -Raw | ConvertFrom-Json; if ($null -ne $o.kits) { $r.Enabled = [bool]$o.kits.enabled; if ([int]$o.kits.size -ge $script:StMinSize) { $r.Size = [int]$o.kits.size } } } catch { } }
  return $r
}
function ST-WriteLua([bool]$enabled, [int]$size) {   # tweaks.lua in the mod folder (when the mod is installed)
  $lua = New-Object System.Text.StringBuilder
  [void]$lua.AppendLine('-- Written by the Permafrost Item Tool ("Stack sizes" window). Items not listed keep the game''s own stack size and durability.')
  [void]$lua.AppendLine('return {'); [void]$lua.AppendLine('  version = 1,'); [void]$lua.AppendLine('  stacks = {')
  if ($enabled) { foreach ($k in $script:StKitAssets.Keys) { [void]$lua.AppendLine(("    {0} = {1}," -f $script:StKitAssets[$k], $size)) } }
  [void]$lua.AppendLine('  },'); [void]$lua.AppendLine('  singleuse = {')
  if ($enabled) { foreach ($k in $script:StKitAssets.Keys) { [void]$lua.AppendLine(("    {0} = true," -f $script:StKitAssets[$k])) } }
  [void]$lua.AppendLine('  },'); [void]$lua.AppendLine('}')
  $dir = ST-ModDir; if (-not (Test-Path -LiteralPath $dir)) { return $false }
  [IO.File]::WriteAllText((Join-Path $dir 'tweaks.lua'), $lua.ToString(), (New-Object Text.UTF8Encoding($false))); return $true
}

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
  $t = Get-StackTweaks; [void](ST-WriteLua $t.Enabled $t.Size)
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

# kit stacks inside one inventory string: '@0=MedkitAFAK&4&200.0@1=Bandage&3' -> @(4)
function ST-KitCounts([string]$inv) {
  $out = @(); if (-not $inv) { return $out }
  foreach ($m in [regex]::Matches($inv, '@\d+=(MedkitAFAK|MedkitIFAK|MedkitMFAK|CarMedkit)&(\d+)')) { $out += [int]$m.Groups[2].Value }
  return $out
}
# stacks (more than one kit in a slot) in the save: your hotbar + backpack, and every container record. Stacks = how many slots, Extra = kits beyond the first, Max = the biggest stack
function ST-FindKitStacks([string]$savePath, [switch]$SkipContainers) {
  $res = @{ Stacks = 0; Extra = 0; Max = 1; Player = 0; Containers = 0 }
  try { foreach ($r in (Get-InventoryView $savePath)) { if ($script:StKitIds -contains $r.Item -and ([string]$r.Detail) -match '^x(\d+)') { $n = [int]$Matches[1]
      if ($n -gt 1) { $res.Stacks++; $res.Player++; $res.Extra += ($n - 1); if ($n -gt $res.Max) { $res.Max = $n } } } } } catch { }
  if (-not $SkipContainers) {
    try { $t = [Text.Encoding]::Latin1.GetString([IO.File]::ReadAllBytes($savePath)); $w = Read-WorldCells $t
      foreach ($c in $w.Cells) { foreach ($r in $c.Recs) { $inv = $r.Get('Inventory'); if ($inv -and $inv -match 'Medkit') { foreach ($n in (ST-KitCounts $inv)) { if ($n -gt 1) { $res.Stacks++; $res.Containers++; $res.Extra += ($n - 1); if ($n -gt $res.Max) { $res.Max = $n } } } } } }
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

# DANGER = kit stacks exist in the save but the setting is not in force (off, or the mod is not installed / not switched on): the game would trim them at its next save
function ST-DangerText($found) {
  if (-not $found -or $found.Stacks -lt 1) { return $null }
  $t = Get-StackTweaks
  if ($t.Enabled -and (ST-ModActive)) { return $null }
  return "DANGER: your save holds $($found.Stacks) stack(s) of first aid kits ($($found.Extra) kits beyond one per slot) but the Stack sizes mod is not on: the game deletes them at its next save."
}

# $found = ST-FindKitStacks result. Refuses to switch OFF while stacks exist, and to lower the size below the biggest existing stack
function ST-Check([bool]$enabled, [int]$size, $found) {
  if ($size -lt $script:StMinSize -or $size -gt $script:StMaxSize) { throw "Stack size must be between $($script:StMinSize) and $($script:StMaxSize)." }
  if ($found -and $found.Stacks -gt 0) {
    if (-not $enabled) { throw "NOT APPLIED - nothing was changed.`n`nYour save holds $($found.Stacks) stack(s) of first aid kits ($($found.Extra) kits beyond one per slot; $($found.Player) in your inventory, $($found.Containers) in containers). With the setting off the game deletes every kit beyond the first in a slot the next time it saves.`n`nFirst use those kits up (or take them out one at a time), then switch the setting off." }
    if ($size -lt $found.Max) { throw "NOT APPLIED - nothing was changed.`n`nYour biggest stack of kits holds $($found.Max). A size of $size would make the game trim it on the next save and delete the extra kits. Pick at least $($found.Max), or use those kits first." }
  }
}
function Set-StackTweak([bool]$enabled, [int]$size, $found) {
  ST-Check $enabled $size $found
  $o = [ordered]@{ kits = [ordered]@{ enabled = $enabled; size = $size } }
  ($o | ConvertTo-Json -Depth 4) | Set-Content -LiteralPath (ST-TweakPath) -Encoding utf8
  $script:StStatusCache = $null
  return @{ Wrote = (ST-WriteLua $enabled $size) }
}

# ---------------- the window ----------------
function ST-WinRefresh {
  $u = $script:STW; $st = ST-ModStatus; $tw = Get-StackTweaks; $found = ST-FindKitStacks $u.Save; $u.Found = $found
  $u.ModState.Text = $st.Text; $u.ModState.ForeColor = $(if ($st.Active -and $st.UpToDate) { [System.Drawing.Color]::LightGreen } else { [System.Drawing.Color]::Orange })
  $u.StackState.Text = $(if ($found.Stacks -gt 0) { "Your save holds $($found.Stacks) stack(s) of kits ($($found.Extra) kits beyond one per slot): $($found.Player) in your inventory, $($found.Containers) in containers. Biggest stack: $($found.Max)." } else { 'Your save holds no stacks of kits (every kit is alone in its slot).' })
  $d = ST-DangerText $found; $u.Warn.Text = $(if ($d) { $d } else { '' })
}
function ST-WinApply {
  $u = $script:STW; $en = [bool]$u.Chk.Checked; $sz = [int]$u.Num.Value
  try {
    $found = ST-FindKitStacks $u.Save
    ST-Check $en $sz $found     # refuses first: nothing is installed, backed up or written
    if ($en -and $sz -gt $script:StConfirmAbove -and -not $script:TestMode) {
      if ((Msg "Stacks of $sz kits were not tried in the game (stacks of 5 and 10 were). It should work the same, but please try it on a spare save first if you are unsure.`n`nUse $sz kits per slot?" 'Stack sizes' 'YesNo' 'Question' 'Button2') -ne 'Yes') { return } }
    $st = ST-ModStatus
    if ($en -and -not ($st.Active -and $st.UpToDate)) {
      if (-not $script:TestMode) {
        if ((Msg "Stacking first aid kits needs a small in-game mod (StackSizes, for UE4SS). It only changes numbers inside the running game and never touches your save. IMPORTANT: if the mod is ever not running, the game deletes every kit beyond the first in a slot when it saves.`n`nInstall it now?" 'Stack sizes' 'YesNo' 'Question') -ne 'Yes') { return } }
      ST-InstallMod }
    $bk = ST-BackupSave $u.Save
    [void](Set-StackTweak $en $sz $found)
    $u.Msg.Text = $(if ($en) { "Saved: first aid kits stack to $sz and are single use. It applies every time the game starts, before your save loads." } else { 'Saved: first aid kits are back to the game''s own behaviour (one per slot, with durability).' }) + $(if ($bk) { " A backup of your save was made first ($(Split-Path $bk -Leaf))." } else { ' No backup was made (the game is running or the copy failed).' }) + $(if (Test-GameRunning) { ' The game is running: restart it (or wait about 10 seconds and re-open your inventory) for the change.' } else { '' })
  } catch { $u.Msg.Text = ''; [void](Msg $_.Exception.Message 'Stack sizes - not applied' 'OK' 'Warning') }
  ST-WinRefresh
}
function New-StackSizesForm([string]$savePath) {
  Add-Type -AssemblyName System.Windows.Forms; Add-Type -AssemblyName System.Drawing
  $script:STW = @{ Save = $savePath }; $u = $script:STW; $tw = Get-StackTweaks
  $f = New-Object System.Windows.Forms.Form; $f.Text = 'Stack sizes  -  stackable, single-use first aid kits'; $f.Size = New-Object System.Drawing.Size(740, 600); $f.MinimumSize = New-Object System.Drawing.Size(680, 560)
  $f.StartPosition = 'CenterParent'; $f.Font = New-Object System.Drawing.Font('Segoe UI', 9); $u.Form = $f
  $intro = New-Lbl $f "First aid kits normally take one slot each, because they carry a durability (the 'condition'): a stack would share ONE condition and waste kits. This setting makes them stack AND turns their durability off, so every use consumes one whole kit, like a bandage. It works everywhere (backpack, hotbar, containers) through a small in-game mod and never touches your save. Partial use goes away: a small wound costs a whole kit." 14 10 700 78; $intro.Anchor = 'Top,Left,Right'
  $u.Chk = New-Object System.Windows.Forms.CheckBox; $u.Chk.Text = 'Make first aid kits stackable and single use'; $u.Chk.Location = '14,96'; $u.Chk.Size = '420,24'; $u.Chk.Checked = [bool]$tw.Enabled; $f.Controls.Add($u.Chk)
  New-Lbl $f 'Kits per slot:' 14 130 110 | Out-Null
  $u.Num = New-Object System.Windows.Forms.NumericUpDown; $u.Num.Location = '130,127'; $u.Num.Size = '70,24'; $u.Num.Minimum = $script:StMinSize; $u.Num.Maximum = $script:StMaxSize; $u.Num.Value = [math]::Min([math]::Max([decimal]$tw.Size, $u.Num.Minimum), $u.Num.Maximum); $f.Controls.Add($u.Num)
  $hint = New-Lbl $f "(bandages stack to 5; stacks of 5 and 10 were tried in the game)" 210 130 480; $hint.ForeColor = $script:Th.Muted
  New-Lbl $f 'The in-game mod' 14 170 110 | Out-Null
  $u.ModState = New-Lbl $f '' 130 170 580 22; $u.ModState.Anchor = 'Top,Left,Right'
  New-Lbl $f 'Kits in your save' 14 200 110 | Out-Null
  $u.StackState = New-Lbl $f '' 130 200 580 44; $u.StackState.Anchor = 'Top,Left,Right'
  $u.Warn = New-Lbl $f '' 14 252 700 44; $u.Warn.ForeColor = [System.Drawing.Color]::Tomato; $u.Warn.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold); $u.Warn.Anchor = 'Top,Left,Right'
  $u.Apply = New-Btn $f 'Apply' 14 304 150 34; $u.Apply.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
  $close = New-Btn $f 'Close' 174 304 100 34
  $u.Msg = New-Lbl $f '' 14 348 700 60; $u.Msg.ForeColor = $script:Th.Accent; $u.Msg.Anchor = 'Top,Left,Right'
  $note = New-Lbl $f "IMPORTANT (tested): if the mod is not running, the game trims every stack of kits to ONE the next time it saves and the extra kits are gone for good. So the tool refuses to switch this off while stacks exist (use the kits up first), makes a backup each time you apply, and shows a red warning in the main window if stacks exist and the mod is not on. If you remove the mod, UE4SS stops loading, or the game updates, check this window before you play." 14 416 700 100; $note.ForeColor = $script:Th.Muted; $note.Anchor = 'Top,Left,Right'
  $u.Apply.Add_Click({ ST-WinApply }); $close.Add_Click({ $script:STW.Form.Close() })
  ST-WinRefresh
  Apply-Theme $f; Set-AppIcon $f
  $u.ModState.ForeColor = $(if ((ST-ModStatus).Active) { [System.Drawing.Color]::LightGreen } else { [System.Drawing.Color]::Orange }); $u.Warn.ForeColor = [System.Drawing.Color]::Tomato
  return $f
}
function Show-StackSizes($owner, [string]$savePath) { $f = New-StackSizesForm $savePath; $script:ActiveForm = $f; try { [void]$f.ShowDialog($owner) } finally { $script:ActiveForm = $null } }