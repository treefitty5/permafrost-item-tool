# Build-WorldMap.ps1 - builds  assets\worldmap.png  (4096 x 4096): the picture of the game's world map, for the Teleport map window.
# It is made on YOUR computer from YOUR installed game and stays in your assets folder (git-ignored): the picture is the game developers' artwork and is never part of the tool's download.
#
# The game stores the map as a UE5 "virtual texture": the picture cut into 136 x 136 pixel tiles (128 + 4 pixels of border on every side) of BC1 (DXT1) blocks,
# tile after tile in Morton (Z-order) inside the first data chunk, which starts with a 4-byte header. This script puts the tiles back together.
#
# Usage:  pwsh -File .\Build-WorldMap.ps1 -GameDir <...\steamapps\common\Permafrost> [-OodleDll <oodle-data-shared.dll>]
#         pwsh -File .\Build-WorldMap.ps1 -ExportRoot <FModel Exports folder>        (a raw FModel export of T_WorldMap_HighRes_D works too)
param([string]$GameDir = '', [string]$OodleDll = '', [string]$ExportRoot = '')
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
. (Join-Path $PSScriptRoot 'Paths.ps1'); . (Join-Path $PSScriptRoot 'WorldMapDecode.ps1')
[byte[]]$ub = $null
if ($GameDir) {
  . (Join-Path $PSScriptRoot 'GameFiles.ps1')
  $utoc = Get-GameUtoc $GameDir; if (-not $utoc) { throw "No Permafrost-Windows.utoc found under $GameDir" }
  if (-not $OodleDll) { $OodleDll = Find-OodleDll }; if (-not $OodleDll) { throw 'The Oodle decompressor (oodle-data-shared.dll) was not found.' }
  $reader = Open-GameContainer $utoc $OodleDll
  $key = 'permafrost/content/permafrost/ui/journal/map/textures/t_worldmap_highres_d.ubulk'
  if (-not $reader.Paths.ContainsKey($key)) { throw 'The world map texture was not found in the game files (a game update may have moved it).' }
  $ub = $reader.ReadChunk($reader.Paths[$key])
} else {
  if (-not $ExportRoot) { $ExportRoot = PF-ExportRoot }
  $f = Join-Path $ExportRoot 'Permafrost\Content\Permafrost\UI\Journal\Map\Textures\T_WorldMap_HighRes_D.ubulk'
  if (-not (Test-Path -LiteralPath $f)) { throw "Not found: $f" }
  $ub = [IO.File]::ReadAllBytes($f)
}
# the first chunk is 32 x 32 tiles of 136 x 136 BC1 pixels after a 4-byte header: anything else means the game changed the map texture
$need = 4 + 32 * 32 * (136 * 136 / 2)
if ($ub.Length -lt $need) { throw "The map texture has a different layout than expected ($($ub.Length) bytes, expected at least $need). A game update may have changed it." }
$bgr = Convert-WorldMapChunk $ub; $side = 4096
$bmp = New-Object System.Drawing.Bitmap($side, $side, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
$bd = $bmp.LockBits((New-Object System.Drawing.Rectangle(0, 0, $side, $side)), [System.Drawing.Imaging.ImageLockMode]::WriteOnly, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
for ($y = 0; $y -lt $side; $y++) { [System.Runtime.InteropServices.Marshal]::Copy($bgr, $y * $side * 3, [IntPtr]($bd.Scan0.ToInt64() + $y * $bd.Stride), $side * 3) }
$bmp.UnlockBits($bd)
$dir = Join-Path $PSScriptRoot 'assets'; if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
$out = Join-Path $dir 'worldmap.png'; $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
"worldmap.png written: $out ($([math]::Round((Get-Item $out).Length / 1MB, 1)) MB)"
