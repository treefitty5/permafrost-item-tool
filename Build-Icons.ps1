param(
  # where FModel put its exports (raw .uasset/.ubulk textures, or PNGs if you exported those)
  [string]$ExportRoot = '',
  [int]$MaxSize = 128
)
. (Join-Path $PSScriptRoot 'Paths.ps1')
if (-not $ExportRoot) { $ExportRoot = PF-ExportRoot }
# Builds  icons\<item id>.png  for every item in items.json, from FModel's texture export.
# Works with RAW exports (.uasset + .ubulk, decoded by TextureDecode.ps1) and with PNG exports.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
. (Join-Path $PSScriptRoot 'TextureDecode.ps1')
$items = Get-Content (Join-Path $PSScriptRoot 'items.json') -Raw | ConvertFrom-Json
$outDir = Join-Path $PSScriptRoot 'icons'; if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir | Out-Null }
$content = Join-Path $ExportRoot 'Permafrost\Content'
$cache = @{}          # icon path -> decoded bitmap (many items share one icon, e.g. all keys)
$written = 0; $missing = New-Object System.Collections.Generic.List[string]; $viaRaw = 0; $viaPng = 0

function Get-IconBitmap([string]$gamePath) {
  $rel = ($gamePath -replace '^/Game/', '').Replace('/', '\')
  $raw = Join-Path $content "$rel.uasset"
  if (Test-Path -LiteralPath $raw) { $b = Convert-TextureToBitmap $raw; if ($b) { $script:viaRaw++; return $b } }
  $png = Join-Path $content "$rel.png"
  if (Test-Path -LiteralPath $png) { $script:viaPng++; return [System.Drawing.Image]::FromFile($png) }
  return $null
}

foreach ($it in $items) {
  if (-not $it.icon) { continue }
  if (-not $cache.ContainsKey($it.icon)) { $cache[$it.icon] = Get-IconBitmap $it.icon }
  $src = $cache[$it.icon]
  if (-not $src) { [void]$missing.Add("$($it.id)  <-  $($it.icon)"); continue }
  $safe = ($it.id -replace '[\\/:*?"<>|]', '_')
  $sc = [math]::Min(1.0, [math]::Min($MaxSize / $src.Width, $MaxSize / $src.Height))
  $w = [math]::Max(1, [int]($src.Width * $sc)); $h = [math]::Max(1, [int]($src.Height * $sc))
  $bmp = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp); $g.InterpolationMode = 'HighQualityBicubic'; $g.SmoothingMode = 'HighQuality'; $g.PixelOffsetMode = 'HighQuality'; $g.DrawImage($src, 0, 0, $w, $h); $g.Dispose()
  $bmp.Save((Join-Path $outDir "$safe.png"), [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose(); $written++
}
foreach ($v in $cache.Values) { if ($v) { $v.Dispose() } }
$total = @($items | Where-Object { $_.icon }).Count
"pictures written: $written of $total items  ->  $outDir   (decoded from raw: $viaRaw textures, from PNG: $viaPng)"
$listFile = Join-Path $PSScriptRoot 'icons-missing.txt'
if ($missing.Count) { "still missing: $($missing.Count) items (their hover shows text only)"; $missing | Set-Content $listFile -Encoding utf8; "list written to $listFile" }
elseif (Test-Path -LiteralPath $listFile) { Remove-Item -LiteralPath $listFile -Force; "no missing icons" }
