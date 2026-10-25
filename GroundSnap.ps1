# GroundSnap.ps1 - the tool's side of the GroundSnap in-game mod (Teleport tab: "Let the game correct my height when I arrive").
# The tool can only estimate the ground height of a place. When you teleport to an ESTIMATED height the tool writes request.lua into the mod folder;
# the mod (GroundSnapMod\main.lua, UE4SS) waits until the world has loaded you at that spot, asks the game where the real ground is, and puts you on it.
# Heights that are real (your bed, the start, your own builds, your saved spots, a height you typed) are never corrected: they may be inside a building or a bunker.
# Needs RecipeTweaks.ps1 (RT-ModsDir).
function GS-ModDir { return (Join-Path (RT-ModsDir) 'GroundSnap') }

function GS-ModStatus {   # Installed / Enabled / UpToDate / Active / Text
  $r = @{ Installed = $false; Enabled = $false; UpToDate = $false; Active = $false; Text = '' }
  $dir = GS-ModDir; $main = Join-Path $dir 'Scripts\main.lua'; $src = Join-Path $PSScriptRoot 'GroundSnapMod\main.lua'
  if (-not (Test-Path -LiteralPath (RT-ModsDir))) { $r.Text = 'UE4SS Mods folder not found next to your save - the game mod cannot be installed from here.'; return $r }
  $r.Installed = Test-Path -LiteralPath $main
  $mt = Join-Path (RT-ModsDir) 'mods.txt'; $r.Enabled = (Test-Path -LiteralPath $mt) -and ((Get-Content -LiteralPath $mt -Raw) -match '(?m)^\s*GroundSnap\s*:\s*1')
  $r.UpToDate = $r.Installed -and (-not (Test-Path -LiteralPath $src) -or ((Get-FileHash -LiteralPath $main).Hash -eq (Get-FileHash -LiteralPath $src).Hash))
  $r.Active = $r.Installed -and $r.Enabled
  $r.Text = if (-not $r.Installed) { 'The in-game mod (GroundSnap) is not installed yet.' } elseif (-not $r.Enabled) { 'The mod is installed but switched OFF in mods.txt.' } elseif (-not $r.UpToDate) { 'The in-game mod is an older version.' } else { 'The in-game mod is installed and on.' }
  return $r
}
function GS-InstallMod {
  $mods = RT-ModsDir; if (-not (Test-Path -LiteralPath $mods)) { throw "UE4SS Mods folder not found: $mods" }
  $src = Join-Path $PSScriptRoot 'GroundSnapMod\main.lua'; if (-not (Test-Path -LiteralPath $src)) { throw 'GroundSnapMod\main.lua is missing next to the tool.' }
  $dir = GS-ModDir; New-Item -ItemType Directory -Force (Join-Path $dir 'Scripts') | Out-Null
  Copy-Item -LiteralPath $src -Destination (Join-Path $dir 'Scripts\main.lua') -Force
  $mt = Join-Path $mods 'mods.txt'; $lines = New-Object System.Collections.Generic.List[string]; if (Test-Path -LiteralPath $mt) { foreach ($l in (Get-Content -LiteralPath $mt)) { $lines.Add($l) } }
  $bk = "$mt.bak-before-groundsnap"; if ((Test-Path -LiteralPath $mt) -and -not (Test-Path -LiteralPath $bk)) { Copy-Item -LiteralPath $mt -Destination $bk }
  $ix = -1; for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*GroundSnap\s*:') { $ix = $i; break } }
  if ($ix -ge 0) { $lines[$ix] = 'GroundSnap : 1' }
  else { $cm = -1; for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*;.*[Bb]uilt-in keybinds') { $cm = $i; break } }
    $last = -1; $lim = $(if ($cm -ge 0) { $cm } else { $lines.Count }); for ($i = 0; $i -lt $lim; $i++) { if ($lines[$i] -match '^\S+\s*:\s*[01]\s*$') { $last = $i } }
    $lines.Insert($last + 1, 'GroundSnap : 1') }
  [IO.File]::WriteAllText($mt, (($lines -join "`r`n") + "`r`n"), (New-Object Text.UTF8Encoding($false)))
}

# ask the mod to correct the height after this teleport (installs / updates the mod first). Returns the mod status.
function GS-WriteRequest([double]$x, [double]$y, [double]$z, [string]$label) {
  $st = GS-ModStatus; if (-not ($st.Installed -and $st.Enabled -and $st.UpToDate)) { GS-InstallMod }
  $inv = [Globalization.CultureInfo]::InvariantCulture
  $lua = "return {{ version = 1, x = {0}, y = {1}, z = {2}, created = {3}, label = `"{4}`" }}`r`n" -f $x.ToString('0.###', $inv), $y.ToString('0.###', $inv), $z.ToString('0.###', $inv), [DateTimeOffset]::UtcNow.ToUnixTimeSeconds(), (($label -replace '[^\w\s\.\-\(\)'']', '') -replace '"', '')
  [IO.File]::WriteAllText((Join-Path (GS-ModDir) 'request.lua'), $lua, (New-Object Text.UTF8Encoding($false)))
  return (GS-ModStatus)
}
function GS-ClearRequest { try { $p = Join-Path (GS-ModDir) 'request.lua'; if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force } } catch { } }
function GS-HasRequest { return (Test-Path -LiteralPath (Join-Path (GS-ModDir) 'request.lua')) }
# what the mod last did in the game ('' = nothing yet)
function GS-LastResult { $p = Join-Path (GS-ModDir) 'status.txt'; if (Test-Path -LiteralPath $p) { return (Get-Content -LiteralPath $p -Raw).Trim() }; return '' }
