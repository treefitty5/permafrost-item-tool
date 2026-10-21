# Build-Everything.ps1 - rebuilds the data pack (items.json and catalog\*.csv) from YOUR copy of the game, in one go.
# Normally NOT needed: the release already contains the data. Use it after a game update when there is no new release yet (README, section 9).
# Run it after the FModel export (README 9.2). It takes about a minute.
#   pwsh -NoProfile -File .\Build-Everything.ps1
# What it runs, in order:  Build-Catalog (item list)  ->  Rebuild-All (recipes, loot, quests, building parts, ...)  ->  Build-Finalize (makes it the shippable data pack)
# The pictures are not made here: the "Pictures..." button in the tool reads them straight from the installed game.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Paths.ps1')
$here = $PSScriptRoot
Write-Host "Game folder : $(if (PF-GameDir) { PF-GameDir } else { '(not found - only needed to find your save and install the recipe mod)' })"
Write-Host "Export root : $(PF-ExportRoot)"
$need = 'Permafrost\Content\Permafrost\Blueprints\Items\DataAsset_Items', 'Permafrost\Content\Permafrost\Blueprints'
foreach ($n in $need) { if (-not (Test-Path -LiteralPath (PF-ExportPath $n))) { throw "Missing in the export: $n  (README, section 9.2)" } }
Write-Host '== Build-Catalog'; & pwsh -NoProfile -File (Join-Path $here 'Build-Catalog.ps1') 2>&1 | Select-Object -Last 6
& pwsh -NoProfile -File (Join-Path $here 'Rebuild-All.ps1')
Write-Host '== Build-Finalize'; & pwsh -NoProfile -File (Join-Path $here 'Build-Finalize.ps1')
Write-Host ''
Write-Host 'Finished. Start the tool with "Run Permafrost Item Tool.cmd".'