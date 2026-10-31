# SolarPanelFix.ps1 - installs the "SolarPanelFix" in-game mod (SolarPanelFixMod\main.lua): gives the solar panels their "Press F" prompt back.
# Why it is needed: the loot box of a panel (the only part that answers the game's interaction ray) lies below the terrain surface, so the ray never reaches it.
# The mod makes the panel's cabinet answer the ray too. It only changes collision while the game runs; the save is never touched.
# Needs RecipeTweaks.ps1 (RT-ModsDir finds the UE4SS Mods folder next to the save) and PlayerTools.ps1 (Msg).

function SP-ModDir { return (Join-Path (RT-ModsDir) 'SolarPanelFix') }

function SP-Status {
  $dir = SP-ModDir; $main = Join-Path $dir 'Scripts\main.lua'; $src = Join-Path $PSScriptRoot 'SolarPanelFixMod\main.lua'
  if (-not (Test-Path -LiteralPath (RT-ModsDir))) { return @{ Ok = $false; Text = 'UE4SS Mods folder not found next to your save.' } }
  if (-not (Test-Path -LiteralPath $main)) { return @{ Ok = $false; Text = 'Not installed yet.' } }
  $mt = Join-Path (RT-ModsDir) 'mods.txt'
  if (-not ((Test-Path -LiteralPath $mt) -and ((Get-Content $mt -Raw) -match '(?m)^\s*SolarPanelFix\s*:\s*1'))) { return @{ Ok = $false; Text = 'Installed but switched off in mods.txt.' } }
  if ((Test-Path -LiteralPath $src) -and ((Get-FileHash $main).Hash -ne (Get-FileHash $src).Hash)) { return @{ Ok = $false; Text = 'An older version is installed.' } }
  return @{ Ok = $true; Text = 'Installed and switched on (it applies itself every time the game starts).' }
}

function SP-Install {
  $mods = RT-ModsDir; if (-not (Test-Path -LiteralPath $mods)) { throw "UE4SS Mods folder not found: $mods" }
  $src = Join-Path $PSScriptRoot 'SolarPanelFixMod\main.lua'; if (-not (Test-Path -LiteralPath $src)) { throw 'SolarPanelFixMod\main.lua is missing next to the tool.' }
  $dir = SP-ModDir; New-Item -ItemType Directory -Force (Join-Path $dir 'Scripts') | Out-Null
  Copy-Item -LiteralPath $src -Destination (Join-Path $dir 'Scripts\main.lua') -Force
  $mt = Join-Path $mods 'mods.txt'; $lines = New-Object System.Collections.Generic.List[string]; if (Test-Path -LiteralPath $mt) { foreach ($l in (Get-Content $mt)) { $lines.Add($l) } }
  $bk = "$mt.bak-before-solarpanelfix"; if ((Test-Path -LiteralPath $mt) -and -not (Test-Path -LiteralPath $bk)) { Copy-Item -LiteralPath $mt -Destination $bk }
  $ix = -1; for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*SolarPanelFix\s*:') { $ix = $i; break } }
  if ($ix -ge 0) { $lines[$ix] = 'SolarPanelFix : 1' }
  else { $cm = -1; for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*;.*[Bb]uilt-in keybinds') { $cm = $i; break } }
    $last = -1; $lim = $(if ($cm -ge 0) { $cm } else { $lines.Count }); for ($i = 0; $i -lt $lim; $i++) { if ($lines[$i] -match '^\S+\s*:\s*[01]\s*$') { $last = $i } }
    $lines.Insert($last + 1, 'SolarPanelFix : 1') }
  [IO.File]::WriteAllText($mt, (($lines -join "`r`n") + "`r`n"), (New-Object Text.UTF8Encoding($false)))
}

function SP-Open {
  $st = SP-Status
  $how = "What it does:`n`n" +
    "  In the game as it is, no solar panel shows 'Press F': the loot box of a panel lies below the terrain surface, so the game's interaction ray never reaches it. The same happens in a brand-new world with no mods, so it is the game, not your save.`n" +
    "  The mod makes the panel's cabinet (the part with the white dot) answer that ray too. Aim at the cabinet and F appears.`n`n" +
    "It changes collision only while the game runs. Your save and the game's files are not touched, and nothing has to be switched on in the game: once installed it applies itself every time the game starts and as panels load. If the game's developers fix the cause, the mod simply has nothing left to do.`n`n" +
    "Log: ue4ss\Mods\SolarPanelFix\SolarPanelFix.log. Switch it off with 'SolarPanelFix : 0' in Mods\mods.txt.`n`n" +
    "A mod only loads when the game starts, so restart the game after installing."
  $a = Msg ("Solar panel fix: $($st.Text)`n`nInstall / update it now? (Mods\mods.txt is backed up first; your save is not touched.)`n`n$how") 'Solar panel fix' 'YesNo' 'Question'
  if ($a -ne 'Yes') { return }
  try { SP-Install; Msg 'Installed. Start (or restart) the game to load it.' 'Solar panel fix' 'OK' 'Information' | Out-Null }
  catch { Msg "Could not install: $($_.Exception.Message)" 'Solar panel fix' 'OK' 'Error' | Out-Null }
}