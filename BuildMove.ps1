# BuildMove.ps1 - installs the "BuildMove" in-game mod (BuildMoveMod\main.lua): pick up a placed building part and put it down somewhere else.
# Needs RecipeTweaks.ps1 (RT-ModsDir finds the UE4SS Mods folder next to the save) and PlayerTools.ps1 (Msg). The save is never touched.

function BM-ModDir { return (Join-Path (RT-ModsDir) 'BuildMove') }

function BM-Status {
  $dir = BM-ModDir; $main = Join-Path $dir 'Scripts\main.lua'; $src = Join-Path $PSScriptRoot 'BuildMoveMod\main.lua'
  if (-not (Test-Path -LiteralPath (RT-ModsDir))) { return @{ Ok = $false; Text = 'UE4SS Mods folder not found next to your save.' } }
  if (-not (Test-Path -LiteralPath $main)) { return @{ Ok = $false; Text = 'Not installed yet.' } }
  $mt = Join-Path (RT-ModsDir) 'mods.txt'
  if (-not ((Test-Path -LiteralPath $mt) -and ((Get-Content $mt -Raw) -match '(?m)^\s*BuildMove\s*:\s*1'))) { return @{ Ok = $false; Text = 'Installed but switched off in mods.txt.' } }
  if ((Test-Path -LiteralPath $src) -and ((Get-FileHash $main).Hash -ne (Get-FileHash $src).Hash)) { return @{ Ok = $false; Text = 'An older version is installed.' } }
  return @{ Ok = $true; Text = 'Installed and switched on.' }
}

function BM-Install {
  $mods = RT-ModsDir; if (-not (Test-Path -LiteralPath $mods)) { throw "UE4SS Mods folder not found: $mods" }
  $src = Join-Path $PSScriptRoot 'BuildMoveMod\main.lua'; if (-not (Test-Path -LiteralPath $src)) { throw 'BuildMoveMod\main.lua is missing next to the tool.' }
  $dir = BM-ModDir; New-Item -ItemType Directory -Force (Join-Path $dir 'Scripts') | Out-Null
  Copy-Item -LiteralPath $src -Destination (Join-Path $dir 'Scripts\main.lua') -Force
  $mt = Join-Path $mods 'mods.txt'; $lines = New-Object System.Collections.Generic.List[string]; if (Test-Path -LiteralPath $mt) { foreach ($l in (Get-Content $mt)) { $lines.Add($l) } }
  $bk = "$mt.bak-before-buildmove"; if ((Test-Path -LiteralPath $mt) -and -not (Test-Path -LiteralPath $bk)) { Copy-Item -LiteralPath $mt -Destination $bk }
  $ix = -1; for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*BuildMove\s*:') { $ix = $i; break } }
  if ($ix -ge 0) { $lines[$ix] = 'BuildMove : 1' }
  else { $cm = -1; for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*;.*[Bb]uilt-in keybinds') { $cm = $i; break } }
    $last = -1; $lim = $(if ($cm -ge 0) { $cm } else { $lines.Count }); for ($i = 0; $i -lt $lim; $i++) { if ($lines[$i] -match '^\S+\s*:\s*[01]\s*$') { $last = $i } }
    $lines.Insert($last + 1, 'BuildMove : 1') }
  [IO.File]::WriteAllText($mt, (($lines -join "`r`n") + "`r`n"), (New-Object Text.UTF8Encoding($false)))
}

function BM-Open {
  $st = BM-Status
  $how = "How it works in the game:`n`n" +
    "  Q wheel > Move   look at a placed furniture / workbench / storage / light / brazier / bed, open the Q wheel and choose Move (the slot after Deconstruction). The part follows your crosshair.`n" +
    "  Left click       put it down where it is. (Choosing Move again or pressing F7 also puts it down.)`n" +
    "  F7               the same as the wheel's Move, without opening the wheel.`n" +
    "  Page Up/Down     turn it 15 degrees while you hold it (not tested yet).`n" +
    "  F6               cancel: it jumps back to where it was (not tested yet).`n`n" +
    "There is no collision check, on purpose: parts can be placed on top of other parts, storage can be stacked (chests on chests, barrels on barrels) and put on walls. A part that ends up inside a wall can be picked up again.`n`n" +
    "The same object is moved: health, contents and variation stay, no materials are used or refunded. Walls, floors, foundations, roofs, doors, beams and stairs are meant to be refused because they are tied to the building grid (not tested yet).`n`n" +
    "The mod fills the wheel's empty padlock slot with Move. Everything it does is logged to ue4ss\Mods\BuildMove\BuildMove.log.`n`n" +
    "A mod only loads when the game starts, so restart the game after installing."
  $a = Msg ("Build move mod: $($st.Text)`n`nInstall / update it now? (Mods\mods.txt is backed up first; your save is not touched.)`n`n$how") 'Build move' 'YesNo' 'Question'
  if ($a -ne 'Yes') { return }
  try { BM-Install; Msg 'Installed. Start (or restart) the game to load it.' 'Build move' 'OK' 'Information' | Out-Null }
  catch { Msg "Could not install: $($_.Exception.Message)" 'Build move' 'OK' 'Error' | Out-Null }
}
