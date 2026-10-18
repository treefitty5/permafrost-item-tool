# Paths.ps1 - finds the places the tool needs on THIS computer (game folder, save file, FModel export folder).
# Nothing is hard-coded: every value is auto-detected, and can be overridden in config.json next to this file, e.g.
#   { "GameDir": "E:\\Games\\Permafrost", "SavePath": "E:\\Games\\Permafrost\\Permafrost\\SaveGame\\World#1.pfs", "ExportRoot": "E:\\FModel\\Output\\Exports" }
# GameDir  = the folder that contains "Permafrost\Content" (Steam: ...\steamapps\common\Permafrost)
# ExportRoot = FModel's "Exports" folder, the one that contains the "Permafrost" folder

function PF-ConfigPath { return (Join-Path $PSScriptRoot 'config.json') }

function PF-GetConfig {
  $h = @{}
  try { $p = PF-ConfigPath; if (Test-Path -LiteralPath $p) { $o = Get-Content -LiteralPath $p -Raw | ConvertFrom-Json; foreach ($n in $o.PSObject.Properties.Name) { $h[$n] = [string]$o.$n } } } catch { }
  return $h
}

function PF-SetConfig([string]$name, [string]$value) {
  try { $h = PF-GetConfig; $h[$name] = $value; ($h | ConvertTo-Json) | Set-Content -LiteralPath (PF-ConfigPath) -Encoding utf8 } catch { }
}

# every Steam library folder (the one Steam is installed in, plus the extra ones listed in libraryfolders.vdf)
function PF-SteamLibraries {
  $roots = New-Object System.Collections.Generic.List[string]
  foreach ($k in 'HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam') {
    try { $v = (Get-ItemProperty -Path $k -ErrorAction Stop); foreach ($n in 'SteamPath', 'InstallPath') { if ($v.$n) { $roots.Add(([string]$v.$n).Replace('/', '\')) } } } catch { }
  }
  $libs = New-Object System.Collections.Generic.List[string]
  foreach ($r in $roots) {
    if (-not $libs.Contains($r)) { $libs.Add($r) }
    $vdf = Join-Path $r 'steamapps\libraryfolders.vdf'
    if (Test-Path -LiteralPath $vdf) { foreach ($m in [regex]::Matches((Get-Content -LiteralPath $vdf -Raw), '"path"\s+"([^"]+)"')) { $p = $m.Groups[1].Value.Replace('\\', '\'); if (-not $libs.Contains($p)) { $libs.Add($p) } } }
  }
  return $libs.ToArray()
}

# the game folder: config.json, else the Steam library that has steamapps\common\Permafrost
function PF-GameDir {
  $c = PF-GetConfig; if ($c.GameDir -and (Test-Path -LiteralPath $c.GameDir)) { return $c.GameDir }
  foreach ($l in (PF-SteamLibraries)) { $g = Join-Path $l 'steamapps\common\Permafrost'; if (Test-Path -LiteralPath (Join-Path $g 'Permafrost')) { return $g } }
  return ''
}

# folders that can hold .pfs saves
function PF-SaveFolders {
  $f = New-Object System.Collections.Generic.List[string]
  $g = PF-GameDir; if ($g) { $f.Add((Join-Path $g 'Permafrost\SaveGame')) }
  return $f.ToArray()
}

# the save file the window starts with: config.json, else the most recently written .pfs found
function PF-SavePath {
  $c = PF-GetConfig; if ($c.SavePath) { return $c.SavePath }
  $best = $null
  foreach ($d in (PF-SaveFolders)) { if (Test-Path -LiteralPath $d) { foreach ($s in (Get-ChildItem -LiteralPath $d -Filter '*.pfs' -File)) { if (-not $best -or $s.LastWriteTime -gt $best.LastWriteTime) { $best = $s } } } }
  if ($best) { return $best.FullName }
  $g = PF-GameDir; if ($g) { return (Join-Path $g 'Permafrost\SaveGame\World#1.pfs') }
  return (Join-Path $env:LOCALAPPDATA 'Permafrost\SaveGame\World#1.pfs')   # not found: the window shows it as missing, use Browse...
}

# every save file found (used as samples by Build-Catalog; optional)
function PF-SaveFiles {
  $r = New-Object System.Collections.Generic.List[string]
  foreach ($d in (PF-SaveFolders)) { if (Test-Path -LiteralPath $d) { foreach ($s in (Get-ChildItem -LiteralPath $d -Filter '*.pfs' -File)) { $r.Add($s.FullName) } } }
  return $r.ToArray()
}

# FModel's Exports folder: config.json, else FModel's own OutputDirectory setting, else the usual places
function PF-ExportRoot {
  $c = PF-GetConfig; if ($c.ExportRoot -and (Test-Path -LiteralPath $c.ExportRoot)) { return $c.ExportRoot }
  $cand = New-Object System.Collections.Generic.List[string]
  try { $as = Join-Path $env:APPDATA 'FModel\AppSettings.json'; if (Test-Path -LiteralPath $as) { $o = Get-Content -LiteralPath $as -Raw | ConvertFrom-Json; if ($o.OutputDirectory) { $cand.Add((Join-Path $o.OutputDirectory 'Exports')) } } } catch { }
  foreach ($p in @((Join-Path $env:USERPROFILE 'Downloads\FModel\Output\Exports'), (Join-Path $env:USERPROFILE 'Documents\FModel\Output\Exports'), (Join-Path $env:APPDATA 'FModel\Output\Exports'), (Join-Path $PSScriptRoot 'Output\Exports'))) { $cand.Add($p) }
  foreach ($p in $cand) { if (Test-Path -LiteralPath (Join-Path $p 'Permafrost')) { return $p } }
  throw "FModel's export folder was not found. Export the game files first (see README, step 4), or put its path in config.json as ""ExportRoot"" (the folder that contains the ""Permafrost"" folder)."
}

function PF-ExportPath([string]$relative) { return (Join-Path (PF-ExportRoot) $relative) }
