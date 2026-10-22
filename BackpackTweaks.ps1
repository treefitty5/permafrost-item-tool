# BackpackTweaks.ps1 - the backpack SIZE setting (main window, top right: "Backpack slots" + "Apply in game").
# The size of a worn backpack is not stored in the save: the game builds it from its item data when the world loads. The BackpackSlots UE4SS mod
# (BackpackSlotsMod\main.lua) changes that data inside the running game from the moment the game starts, using tweaks.lua in its folder, so the save already
# loads with the bigger backpack. This file installs the mod and writes tweaks.lua. Nothing in your save is touched. Needs RecipeTweaks.ps1 (RT-ModsDir).
$script:BtTweakPathOverride = $null     # tests point this at a temporary file
$script:BtStatusCache = $null

function BT-TweakPath { if ($script:BtTweakPathOverride) { return $script:BtTweakPathOverride }; return (Join-Path $PSScriptRoot 'backpack-tweaks.json') }
function BT-ModsDir { return (RT-ModsDir) }
function BT-ModDir { return (Join-Path (BT-ModsDir) 'BackpackSlots') }

function Get-BackpackTweaks {   # remembered sizes: backpack item id -> slots
  $h = @{}; $p = BT-TweakPath
  if (Test-Path -LiteralPath $p) { try { $o = Get-Content -LiteralPath $p -Raw | ConvertFrom-Json; foreach ($pr in $o.PSObject.Properties) { $h[$pr.Name] = [int]$pr.Value } } catch { } }
  return $h
}
function BT-WriteLua($h) {   # tweaks.lua in the mod folder (when the mod is installed)
  $lua = New-Object System.Text.StringBuilder
  [void]$lua.AppendLine('-- Written by the Permafrost Item Tool ("Backpack slots" box). Backpacks not listed keep the game''s own size.')
  [void]$lua.AppendLine('return {'); [void]$lua.AppendLine('  version = 1,'); [void]$lua.AppendLine('  slots = {')
  foreach ($k in ($h.Keys | Sort-Object)) { [void]$lua.AppendLine(("    DA_{0} = {1}," -f $k, [int]$h[$k])) }
  [void]$lua.AppendLine('  },'); [void]$lua.AppendLine('}')
  $dir = BT-ModDir; if (-not (Test-Path -LiteralPath $dir)) { return $false }
  [IO.File]::WriteAllText((Join-Path $dir 'tweaks.lua'), $lua.ToString(), (New-Object Text.UTF8Encoding($false))); return $true
}

function BT-ModStatus {   # Installed / Enabled / UpToDate / Active / Text
  $r = @{ Installed = $false; Enabled = $false; UpToDate = $false; Active = $false; Text = '' }
  $dir = BT-ModDir; $main = Join-Path $dir 'Scripts\main.lua'; $src = Join-Path $PSScriptRoot 'BackpackSlotsMod\main.lua'
  if (-not (Test-Path -LiteralPath (BT-ModsDir))) { $r.Text = 'UE4SS Mods folder not found next to your save - the game mod cannot be installed from here.'; return $r }
  $r.Installed = Test-Path -LiteralPath $main
  $mt = Join-Path (BT-ModsDir) 'mods.txt'; $r.Enabled = (Test-Path -LiteralPath $mt) -and ((Get-Content -LiteralPath $mt -Raw) -match '(?m)^\s*BackpackSlots\s*:\s*1')
  $r.UpToDate = $r.Installed -and (-not (Test-Path -LiteralPath $src) -or ((Get-FileHash -LiteralPath $main).Hash -eq (Get-FileHash -LiteralPath $src).Hash))
  $r.Active = $r.Installed -and $r.Enabled
  $r.Text = if (-not $r.Installed) { 'The in-game mod is not installed yet.' } elseif (-not $r.Enabled) { 'The mod is installed but switched off in mods.txt.' } elseif (-not $r.UpToDate) { 'The in-game mod is an older version.' } else { 'The in-game mod is installed and on.' }
  return $r
}
function BT-ModActive {   # cached for a couple of seconds: the capacity functions ask often
  try { if ($script:BtStatusCache -and ((Get-Date) - $script:BtStatusCache.At).TotalSeconds -lt 2) { return $script:BtStatusCache.Active }
    $a = [bool](BT-ModStatus).Active; $script:BtStatusCache = @{ At = (Get-Date); Active = $a }; return $a } catch { return $false }
}

function BT-InstallMod {
  $mods = BT-ModsDir; if (-not (Test-Path -LiteralPath $mods)) { throw "UE4SS Mods folder not found: $mods" }
  $src = Join-Path $PSScriptRoot 'BackpackSlotsMod\main.lua'; if (-not (Test-Path -LiteralPath $src)) { throw 'BackpackSlotsMod\main.lua is missing next to the tool.' }
  $dir = BT-ModDir; New-Item -ItemType Directory -Force (Join-Path $dir 'Scripts') | Out-Null
  Copy-Item -LiteralPath $src -Destination (Join-Path $dir 'Scripts\main.lua') -Force
  [void](BT-WriteLua (Get-BackpackTweaks))
  $mt = Join-Path $mods 'mods.txt'; $lines = New-Object System.Collections.Generic.List[string]; if (Test-Path -LiteralPath $mt) { foreach ($l in (Get-Content -LiteralPath $mt)) { $lines.Add($l) } }
  $bk = "$mt.bak-before-backpackslots"; if ((Test-Path -LiteralPath $mt) -and -not (Test-Path -LiteralPath $bk)) { Copy-Item -LiteralPath $mt -Destination $bk }
  $ix = -1; for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*BackpackSlots\s*:') { $ix = $i; break } }
  if ($ix -ge 0) { $lines[$ix] = 'BackpackSlots : 1' }
  else { $cm = -1; for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*;.*[Bb]uilt-in keybinds') { $cm = $i; break } }
    $last = -1; $lim = $(if ($cm -ge 0) { $cm } else { $lines.Count }); for ($i = 0; $i -lt $lim; $i++) { if ($lines[$i] -match '^\S+\s*:\s*[01]\s*$') { $last = $i } }
    $lines.Insert($last + 1, 'BackpackSlots : 1') }
  [IO.File]::WriteAllText($mt, (($lines -join "`r`n") + "`r`n"), (New-Object Text.UTF8Encoding($false)))
  $script:BtStatusCache = $null
}

# $usedHighest = the highest slot number that holds an item in the worn backpack (-1 = empty); a size that would leave an item outside the backpack is refused
function Set-BackpackTweak([string]$name, [int]$slots, [int]$usedHighest = -1, [int]$gameSlots = 0) {
  if ($name -notmatch '^[A-Za-z0-9_]+Backpack$') { throw "Not a backpack: $name" }
  if ($slots -lt 5 -or $slots -gt 200) { throw 'Backpack slots must be between 5 and 200.' }
  if ($usedHighest -ge $slots) { throw "NOT APPLIED - nothing was changed.

Your backpack holds an item in slot $($usedHighest + 1). A size of $slots slots would leave that item OUTSIDE the backpack, and the game DELETES such items the next time it saves (tested).

First move or use the items in the higher slots (inside the game, or take them out), or choose at least $($usedHighest + 1) slots." }
  $h = Get-BackpackTweaks
  if ($gameSlots -gt 0 -and $slots -eq $gameSlots) { [void]$h.Remove($name) } else { $h[$name] = $slots }   # the game's own size = no tweak
  $o = [ordered]@{}; foreach ($k in ($h.Keys | Sort-Object)) { $o[$k] = [int]$h[$k] }
  ($o | ConvertTo-Json) | Set-Content -LiteralPath (BT-TweakPath) -Encoding utf8
  $script:BtStatusCache = $null
  return @{ Wrote = (BT-WriteLua $h); Removed = (-not $h.ContainsKey($name)) }
}

# the worn backpack holds an item in a slot above what the tool counts as its size (for example the in-game mod was switched off or removed): the game may drop such items
function BT-Overflow($bp) {
  $cap = (Get-BackpackMaxSlot $bp) + 1; $used = -1
  foreach ($x in $bp.Contents) { if ($x.Slot -gt $used) { $used = $x.Slot } }
  if ($used -ge $cap) { return @{ Highest = $used; Slots = $cap } }
  return $null
}

# A copy of the save before a backpack size is applied (the game deletes items that have no slot when it saves, so a mistake here must be undoable).
# Not made while the game runs (the file may be half-written). Returns the path, or $null.
function BT-BackupSave([string]$savePath) {
  if (-not $savePath -or -not (Test-Path -LiteralPath $savePath)) { return $null }
  if (Test-GameRunning) { return $null }
  $dest = Join-Path (Get-BackupDir) ((Get-Date -Format 'yyyyMMdd-HHmmss') + '_BACKPACKSIZE_' + [IO.Path]::GetFileName($savePath))
  Copy-Item -LiteralPath $savePath -Destination $dest -Force
  if ((Get-FileHash -LiteralPath $dest).Hash -ne (Get-FileHash -LiteralPath $savePath).Hash) { Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue; return $null }
  return $dest
}