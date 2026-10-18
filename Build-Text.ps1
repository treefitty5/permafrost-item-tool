param(
  [string]$LocRoot = ''
)
. (Join-Path $PSScriptRoot 'Paths.ps1')
if (-not $LocRoot) { $LocRoot = PF-ExportPath 'Permafrost\Content\Permafrost\Blueprints\Utils\Localization' }
# All in-game text (string tables ST_*), read from FModel's JSON export: table, key, text. Writes catalog\text.csv.
# The keys are the ones other files refer to (item names/descriptions, quest text, dialogue lines, journal, tutorials ...).
$ErrorActionPreference = 'Stop'
$rows = New-Object System.Collections.Generic.List[object]
foreach ($f in [IO.Directory]::EnumerateFiles($LocRoot, 'ST_*.json', [IO.SearchOption]::AllDirectories)) {
  # -AsHashtable: keys that differ only by upper/lower case are kept apart (the default parser rejects them)
  $o = (Get-Content $f -Raw | ConvertFrom-Json -AsHashtable) | Where-Object { $_.StringTable } | Select-Object -First 1; if (-not $o) { continue }
  $tn = [IO.Path]::GetFileNameWithoutExtension($f)
  foreach ($k in $o.StringTable.KeysToEntries.Keys) { $rows.Add([pscustomobject]@{ Table = $tn; Key = [string]$k; Text = ([string]$o.StringTable.KeysToEntries[$k] -replace "[\r\n]+", ' / ') }) } }
$rows | Export-Csv (Join-Path $PSScriptRoot 'catalog\text.csv') -NoTypeInformation -Encoding UTF8
"text entries: $($rows.Count) in $(@($rows | Select-Object -ExpandProperty Table -Unique).Count) tables"
