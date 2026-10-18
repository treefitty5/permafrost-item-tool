# Build-Everything.ps1 - makes every data file the tool needs from YOUR copy of the game, in one go.
# Run it after step 4 of the README (the FModel export). It takes a few minutes (most of it is the item pictures).
#   pwsh -NoProfile -File .\Build-Everything.ps1
# What it runs, in order:  Build-Catalog (item list)  ->  Build-Icons (item pictures)  ->  Rebuild-All (recipes, loot, quests, text, ...)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Paths.ps1')
$here = $PSScriptRoot
Write-Host "Game folder : $(if (PF-GameDir) { PF-GameDir } else { '(not found - only needed to find your save and install the recipe mod)' })"
Write-Host "Export root : $(PF-ExportRoot)"
$need = 'Permafrost\Content\Permafrost\Blueprints\Items\DataAsset_Items', 'Permafrost\Content\Permafrost\Blueprints'
foreach ($n in $need) { if (-not (Test-Path -LiteralPath (PF-ExportPath $n))) { throw "Missing in the export: $n  (README step 4)" } }
foreach ($s in 'Build-Catalog', 'Build-Icons') { Write-Host "== $s"; & pwsh -NoProfile -File (Join-Path $here "$s.ps1") 2>&1 | Select-Object -Last 6 }
& pwsh -NoProfile -File (Join-Path $here 'Rebuild-All.ps1')
Write-Host ''
Write-Host 'Finished. Start the tool with "Run Permafrost Item Tool.cmd".'
