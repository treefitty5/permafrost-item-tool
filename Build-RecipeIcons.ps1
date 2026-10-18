param(
  [string]$ExportRoot = '',
  [int]$MaxSize = 128
)
. (Join-Path $PSScriptRoot 'Paths.ps1')
if (-not $ExportRoot) { $ExportRoot = PF-ExportRoot }
# Pictures for the Player tools > Recipes hover tip.
#  - Building recipes: the build part's own Icon texture (DA_Build_* / DA_Outpost_* JSON) -> icons\build\<build id>.png
#  - Item recipes: the picture of the item the recipe makes (icons\<item id>.png from Build-Icons.ps1)
# Writes catalog\recipe-icons.csv: Asset (learning asset), Kind, IconFile (relative to the tool folder, may be empty), Makes, Detail.
# Run after Build-Icons.ps1, Build-Recipes.ps1 and Build-BuildParts.ps1.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
. (Join-Path $PSScriptRoot 'TextureDecode.ps1')
$content = Join-Path $ExportRoot 'Permafrost\Content'
$dataRoot = Join-Path $content 'Permafrost\Blueprints\BuildingParts\Data'
$bdir = Join-Path $PSScriptRoot 'icons\build'; if (-not (Test-Path $bdir)) { New-Item -ItemType Directory -Path $bdir | Out-Null }
function Safe([string]$s) { $s -replace '[\/:*?"<>|]', '_' }

# ---- 1. build part icons
$cache = @{}; $made = 0; $noIcon = @(); $buildIcon = @{}
foreach ($f in [IO.Directory]::EnumerateFiles($dataRoot, 'DA_*.json', [IO.SearchOption]::AllDirectories)) {
  $o = (Get-Content $f -Raw | ConvertFrom-Json) | Where-Object { $_.Properties -and $_.Properties.ID } | Select-Object -First 1; if (-not $o) { continue }
  $id = [string]$o.Properties.ID; $ip = [string]$o.Properties.Icon.AssetPathName; if (-not $ip) { $noIcon += $id; continue }
  if (-not $cache.ContainsKey($ip)) {
    $rel = (($ip -replace '^/Game/', '' -replace '\.[^./]*$', '')).Replace('/', '\'); $raw = Join-Path $content "$rel.uasset"; $b = $null
    if (Test-Path -LiteralPath $raw) { $b = Convert-TextureToBitmap $raw }
    $cache[$ip] = $b
  }
  $src = $cache[$ip]; if (-not $src) { $noIcon += $id; continue }
  $sc = [math]::Min(1.0, [math]::Min($MaxSize / $src.Width, $MaxSize / $src.Height)); $w = [math]::Max(1, [int]($src.Width * $sc)); $h = [math]::Max(1, [int]($src.Height * $sc))
  $bmp = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp); $g.InterpolationMode = 'HighQualityBicubic'; $g.SmoothingMode = 'HighQuality'; $g.PixelOffsetMode = 'HighQuality'; $g.DrawImage($src, 0, 0, $w, $h); $g.Dispose()
  $bmp.Save((Join-Path $bdir ((Safe $id) + '.png')), [System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose(); $buildIcon[$id] = "icons\build\$(Safe $id).png"; $made++
}
foreach ($v in $cache.Values) { if ($v) { $v.Dispose() } }

# ---- 2. recipe -> picture + detail line
$items = Get-Content (Join-Path $PSScriptRoot 'items.json') -Raw | ConvertFrom-Json
$byId = @{}; $byAsset = @{}; foreach ($i in $items) { $byId[$i.id] = $i; $byAsset[$i.asset] = $i }
$craft = @{}; foreach ($r in (Import-Csv (Join-Path $PSScriptRoot 'catalog\recipe-details.csv'))) { $craft[($r.Recipe -replace '^DA_CraftingRecipe_', '')] = $r }
$build = @{}; foreach ($b in (Import-Csv (Join-Path $PSScriptRoot 'catalog\building-details.csv'))) { $build[$b.ID] = $b }
function Has-Icon($id) { $p = Join-Path $PSScriptRoot ('icons\' + (Safe $id) + '.png'); return (Test-Path -LiteralPath $p) }
$out = New-Object System.Collections.Generic.List[object]; $unres = @()
foreach ($l in (Import-Csv (Join-Path $PSScriptRoot 'catalog\learning-details.csv'))) {
  $icon = ''; $makes = ''; $detail = ''
  if ($l.Kind -like 'Building*') {
    $key = $l.Teaches; if (-not $buildIcon.ContainsKey($key) -and $buildIcon.ContainsKey($l.DisplayName)) { $key = $l.DisplayName }
    if ($buildIcon.ContainsKey($key)) { $icon = $buildIcon[$key] }
    $b = $build[$key]; if ($b) { $makes = $b.Name; $detail = @(); if ($b.BuildCost) { $detail += "Cost: $($b.BuildCost)" }; if ($b.Requires) { $detail += "Needs: $($b.Requires)" }; if ($b.Description) { $detail += $b.Description }; $detail = $detail -join ' | ' }
  } else {
    $suffix = $l.Asset -replace '^DA_Learning(Recipe)?_', ''; $cr = $craft[$suffix]
    $it = $byId[$l.Teaches]
    if (-not $it -and $cr) { $it = $byAsset[$cr.ResultAsset]; if (-not $it) { $it = $byId[$cr.Result] } }
    if ($it -and (Has-Icon $it.id)) { $icon = 'icons\' + (Safe $it.id) + '.png'; $makes = $it.id }
    if ($cr) { $d = @(); if ($cr.Ingredients) { $d += "Needs: $($cr.Ingredients)" }; if ($cr.AllResults) { $d += "Makes: $($cr.AllResults)" }; if ($cr.Station) { $d += "At: $($cr.Station)" }; if ($cr.Time) { $d += "Time: $($cr.Time) s" }; $detail = $d -join ' | ' }
  }
  if (-not $icon) { $unres += "$($l.Asset) ($($l.Teaches))" }
  $out.Add([pscustomobject]@{ Asset = $l.Asset; Kind = $l.Kind; IconFile = $icon; Makes = $makes; Detail = $detail })
}
$out | Export-Csv (Join-Path $PSScriptRoot 'catalog\recipe-icons.csv') -NoTypeInformation -Encoding UTF8
"build icons written: $made | recipes: $($out.Count), with picture: $(@($out | Where-Object IconFile).Count), without: $($unres.Count)"
$unres -join '; '
