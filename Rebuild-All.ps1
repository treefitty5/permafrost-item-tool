# Rebuilds every data file the tool uses from FModel's exports, in the right order. Needs: the raw export (.uasset) AND the JSON export
# (made with Mappings.usmap). Build-Catalog / Build-Icons are run separately (they need the save files and the full export).
$here = $PSScriptRoot; $ErrorActionPreference = 'Stop'
foreach ($s in 'Build-DataCatalog', 'Build-Recipes', 'Build-Specs', 'Build-Rewards', 'Build-Loot', 'Build-JsonSpecs', 'Build-BuildParts', 'Build-Nodes', 'Build-Quests', 'Build-Lore', 'Build-Game', 'Build-Text', 'Build-Sources') {
  Write-Host "== $s"; & pwsh -NoProfile -File (Join-Path $here "$s.ps1") 2>&1 | Select-Object -Last 4 }
Write-Host 'Done. Restart the tool to see the new data.'
