# WeaponTweaks.ps1 - change a weapon's damage in the game (the Damage row beside the Selected item box in the main window).
# A weapon's damage is not stored per item in a save: it belongs to the weapon's game data (ItemConfig_Weapon / ItemConfig_RangeWeapon: Damage X = min, Y = max),
# so every copy of that weapon is affected. A small UE4SS mod (WeaponTweaksMod\main.lua) sets it while the game runs; your save is never touched.
# Ammo has no damage of its own (only a multiplier, 1.0 for all arrows and bullets), so the weapon is the only place to change.
# Settings file weapon-tweaks.json: { "version": 1, "weapons": { "<asset name>": { "min": 300, "max": 300 }, ... } } (private, git-ignored)
# Needs RecipeTweaks.ps1 (RT-ModsDir).
$script:WtTweakPathOverride = $null     # tests point this at a temporary file
$script:WtMax = 100000

function WT-TweakPath { if ($script:WtTweakPathOverride) { return $script:WtTweakPathOverride }; return (Join-Path $PSScriptRoot 'weapon-tweaks.json') }
function WT-ModsDir { return (RT-ModsDir) }
function WT-ModDir { return (Join-Path (WT-ModsDir) 'WeaponTweaks') }

# the game's own damage of an item from items.json ('150' or '27-22'): @{ Min; Max } or $null when the item has none
function WT-GameDamage($item) {
  if (-not $item -or -not $item.asset -or -not $item.damage) { return $null }
  $m = [regex]::Match([string]$item.damage, '^\s*(-?[\d.]+)(?:\s*-\s*(-?[\d.]+))?')
  if (-not $m.Success) { return $null }
  $a = [double]::Parse($m.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture)
  $b = if ($m.Groups[2].Success) { [double]::Parse($m.Groups[2].Value, [Globalization.CultureInfo]::InvariantCulture) } else { $a }
  return @{ Min = $a; Max = $b }
}
function WT-IsWeapon($item) { return [bool]($item -and $item.itemClass -in 'ItemConfig_Weapon', 'ItemConfig_RangeWeapon' -and (WT-GameDamage $item)) }

# ---------------- settings ----------------
function Get-WeaponConfig {   # @{ <asset> = @{ Min; Max } } for every weapon that is changed
  $cfg = @{}; $p = WT-TweakPath
  if (Test-Path -LiteralPath $p) {
    try { $o = Get-Content -LiteralPath $p -Raw | ConvertFrom-Json
      if ($null -ne $o.weapons) { foreach ($pr in $o.weapons.PSObject.Properties) { $mn = [double]$pr.Value.min; $mx = [double]$pr.Value.max; if ($mn -ge 0 -and $mx -ge 0 -and $mn -le $script:WtMax -and $mx -le $script:WtMax) { $cfg[$pr.Name] = @{ Min = $mn; Max = $mx } } } }
    } catch { }
  }
  return $cfg
}
function WT-SaveConfig($cfg) {
  $w = [ordered]@{}; foreach ($k in ($cfg.Keys | Sort-Object)) { $w[$k] = [ordered]@{ min = [double]$cfg[$k].Min; max = [double]$cfg[$k].Max } }
  ([ordered]@{ version = 1; weapons = $w } | ConvertTo-Json -Depth 5) | Set-Content -LiteralPath (WT-TweakPath) -Encoding utf8
  $script:WtStatusCache = $null
}
function WT-WriteLua($cfg = $null) {   # tweaks.lua in the mod folder (when the mod is installed)
  if (-not $cfg) { $cfg = Get-WeaponConfig }
  $inv = [Globalization.CultureInfo]::InvariantCulture
  $lua = New-Object System.Text.StringBuilder
  [void]$lua.AppendLine('-- Written by the Permafrost Item Tool (Damage box in the main window). Weapons not listed keep the game''s own damage.')
  [void]$lua.AppendLine('return {'); [void]$lua.AppendLine('  version = 1,'); [void]$lua.AppendLine('  damage = {')
  foreach ($k in ($cfg.Keys | Sort-Object)) { [void]$lua.AppendLine(("    {0} = {{ {1}, {2} }}," -f $k, ([double]$cfg[$k].Min).ToString('0.###', $inv), ([double]$cfg[$k].Max).ToString('0.###', $inv))) }
  [void]$lua.AppendLine('  },'); [void]$lua.AppendLine('}')
  $dir = WT-ModDir; if (-not (Test-Path -LiteralPath $dir)) { return $false }
  [IO.File]::WriteAllText((Join-Path $dir 'tweaks.lua'), $lua.ToString(), (New-Object Text.UTF8Encoding($false))); return $true
}

# ---------------- the in-game mod ----------------
function WT-ModStatus {   # Installed / Enabled / UpToDate / Active / Text
  $r = @{ Installed = $false; Enabled = $false; UpToDate = $false; Active = $false; Text = '' }
  $dir = WT-ModDir; $main = Join-Path $dir 'Scripts\main.lua'; $src = Join-Path $PSScriptRoot 'WeaponTweaksMod\main.lua'
  if (-not (Test-Path -LiteralPath (WT-ModsDir))) { $r.Text = 'UE4SS Mods folder not found next to your save - the game mod cannot be installed from here.'; return $r }
  $r.Installed = Test-Path -LiteralPath $main
  $mt = Join-Path (WT-ModsDir) 'mods.txt'; $r.Enabled = (Test-Path -LiteralPath $mt) -and ((Get-Content -LiteralPath $mt -Raw) -match '(?m)^\s*WeaponTweaks\s*:\s*1')
  $r.UpToDate = $r.Installed -and (-not (Test-Path -LiteralPath $src) -or ((Get-FileHash -LiteralPath $main).Hash -eq (Get-FileHash -LiteralPath $src).Hash))
  $r.Active = $r.Installed -and $r.Enabled
  $r.Text = if (-not $r.Installed) { 'The in-game mod (WeaponTweaks) is not installed yet.' } elseif (-not $r.Enabled) { 'The mod is installed but switched OFF in mods.txt.' } elseif (-not $r.UpToDate) { 'The in-game mod is an older version.' } else { 'The in-game mod is installed and on.' }
  return $r
}
function WT-InstallMod {
  $mods = WT-ModsDir; if (-not (Test-Path -LiteralPath $mods)) { throw "UE4SS Mods folder not found: $mods" }
  $src = Join-Path $PSScriptRoot 'WeaponTweaksMod\main.lua'; if (-not (Test-Path -LiteralPath $src)) { throw 'WeaponTweaksMod\main.lua is missing next to the tool.' }
  $dir = WT-ModDir; New-Item -ItemType Directory -Force (Join-Path $dir 'Scripts') | Out-Null
  Copy-Item -LiteralPath $src -Destination (Join-Path $dir 'Scripts\main.lua') -Force
  [void](WT-WriteLua (Get-WeaponConfig))
  $mt = Join-Path $mods 'mods.txt'; $lines = New-Object System.Collections.Generic.List[string]; if (Test-Path -LiteralPath $mt) { foreach ($l in (Get-Content -LiteralPath $mt)) { $lines.Add($l) } }
  $bk = "$mt.bak-before-weapontweaks"; if ((Test-Path -LiteralPath $mt) -and -not (Test-Path -LiteralPath $bk)) { Copy-Item -LiteralPath $mt -Destination $bk }
  $ix = -1; for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*WeaponTweaks\s*:') { $ix = $i; break } }
  if ($ix -ge 0) { $lines[$ix] = 'WeaponTweaks : 1' }
  else { $cm = -1; for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^\s*;.*[Bb]uilt-in keybinds') { $cm = $i; break } }
    $last = -1; $lim = $(if ($cm -ge 0) { $cm } else { $lines.Count }); for ($i = 0; $i -lt $lim; $i++) { if ($lines[$i] -match '^\S+\s*:\s*[01]\s*$') { $last = $i } }
    $lines.Insert($last + 1, 'WeaponTweaks : 1') }
  [IO.File]::WriteAllText($mt, (($lines -join "`r`n") + "`r`n"), (New-Object Text.UTF8Encoding($false)))
}

# ---------------- set / reset one weapon ----------------
# Min / Max equal to the game's own values means "not changed": the entry is removed. Installs / updates the mod and writes tweaks.lua. Returns the mod status.
function Set-WeaponDamage($item, [double]$min, [double]$max) {
  $g = WT-GameDamage $item; if (-not $g) { throw 'This item has no damage in the game data.' }
  if ($min -lt 0 -or $max -lt 0 -or $min -gt $script:WtMax -or $max -gt $script:WtMax) { throw "Damage must be between 0 and $($script:WtMax)." }
  if ($min -gt $max) { throw 'The minimum damage cannot be higher than the maximum.' }
  $cfg = Get-WeaponConfig
  if ([math]::Abs($min - $g.Min) -lt 0.001 -and [math]::Abs($max - $g.Max) -lt 0.001) { [void]$cfg.Remove([string]$item.asset) } else { $cfg[[string]$item.asset] = @{ Min = $min; Max = $max } }
  WT-SaveConfig $cfg
  if ($cfg.Count -gt 0) { WT-InstallMod } else { [void](WT-WriteLua $cfg) }
  return (WT-ModStatus)
}
function Reset-WeaponDamage($item) { $g = WT-GameDamage $item; if (-not $g) { return }; [void](Set-WeaponDamage $item $g.Min $g.Max) }
# what the box shows for an item: @{ Min; Max; Changed; Game }
function Get-WeaponDamageView($item) {
  $g = WT-GameDamage $item; if (-not $g) { return $null }
  $cfg = Get-WeaponConfig; $c = $cfg[[string]$item.asset]
  if ($c) { return @{ Min = $c.Min; Max = $c.Max; Changed = $true; Game = $g } }
  return @{ Min = $g.Min; Max = $g.Max; Changed = $false; Game = $g }
}
function WT-SummaryText($cfg = $null) { if (-not $cfg) { $cfg = Get-WeaponConfig }; return (($cfg.Keys | Sort-Object | ForEach-Object { ($_ -replace '^DA_Weapon_(Firearms_)?', '') + ' ' + ([double]$cfg[$_].Min).ToString('0.###', [Globalization.CultureInfo]::InvariantCulture) }) -join ', ') }
