param(
  [string]$QuestRoot = ''
)
. (Join-Path $PSScriptRoot 'Paths.ps1')
if (-not $QuestRoot) { $QuestRoot = PF-ExportPath 'Permafrost\Content\Permafrost\Blueprints\QuestSystem' }
# Recordings, radio messages and notes (RecordingConfig / RadioMessageConfig / NoteConfig), read from FModel's JSON export.
# Each has an id, an in-game name, a short description and its text lines. Writes catalog\lore.csv.
$ErrorActionPreference = 'Stop'
function T($x) { if ($null -eq $x) { return '' }; if ($x.SourceString) { return [string]$x.SourceString }; if ($x.CultureInvariantString) { return [string]$x.CultureInvariantString }; return '' }
$rows = New-Object System.Collections.Generic.List[object]
foreach ($f in [IO.Directory]::EnumerateFiles($QuestRoot, '*.json', [IO.SearchOption]::AllDirectories)) {
  $h = [IO.File]::OpenRead($f); $buf = New-Object byte[] 300; $n = $h.Read($buf, 0, 300); $h.Close(); $head = [Text.Encoding]::UTF8.GetString($buf, 0, $n)
  if ($head -notmatch '"Type":\s*"(RecordingConfig|RadioMessageConfig|NoteConfig)"') { continue }; $type = $Matches[1] -replace 'Config$', ''
  $o = (Get-Content $f -Raw | ConvertFrom-Json) | Where-Object { $_.Properties } | Select-Object -First 1; $p = $o.Properties
  $id = if ($p.RecordingID) { [string]$p.RecordingID } elseif ($p.NoteID) { [string]$p.NoteID } else { '' }
  $nameObj = if ($p.RecordingInGameName) { $p.RecordingInGameName } else { $p.NoteInGameName }
  $lines = @(@($p.Lines) | Where-Object { $_ } | ForEach-Object { T $_.Text } | Where-Object { $_ })
  $rows.Add([pscustomobject]@{ Type = $type; Asset = [IO.Path]::GetFileNameWithoutExtension($f); ID = $id; Name = (T $nameObj); ShortDescription = (T $p.ShortDescription); Lines = $lines.Count; Text = ($lines -join ' / ')
      Audio = $(if ($p.AudioEvent -and $p.AudioEvent.AssetPathName) { (([string]$p.AudioEvent.AssetPathName -split '/')[-1] -replace '^.*\.', '') } else { '' })
      StartsQuest = $(if ($p.QuestToStart) { (([string]$p.QuestToStart.ObjectName -replace "^.*'(.*)'$", '$1') -replace '^.*[:.]', '') } else { '' }) }) }
$rows | Sort-Object Type, Name | Export-Csv (Join-Path $PSScriptRoot 'catalog\lore.csv') -NoTypeInformation -Encoding UTF8
"lore entries: $($rows.Count) | " + (($rows | Group-Object Type | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ', ') + " | with real text: $(@($rows | Where-Object { $_.Text -and $_.Text -notmatch '^Placeholder' }).Count)"
