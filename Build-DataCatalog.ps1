param(
  [string]$ExportRoot = '',
  [string]$OutDir = (Join-Path $PSScriptRoot 'catalog')
)
. (Join-Path $PSScriptRoot 'Paths.ps1')
if (-not $ExportRoot) { $ExportRoot = PF-ExportPath 'Permafrost\Content' }
# Builds the big data catalog from FModel's RAW export. Everything is read from each asset's name table
# (the list of names/assets a file refers to), which is readable without property mappings.
$ErrorActionPreference = 'Stop'
if (-not (Test-Path $OutDir)) { New-Item -ItemType Directory -Path $OutDir | Out-Null }
$sw = [Diagnostics.Stopwatch]::StartNew()

function Get-NameMap([byte[]]$b) {
  for ($off = 0; $off -le [math]::Min(300, $b.Length - 16); $off += 4) {
    $cnt = [BitConverter]::ToUInt32($b, $off); $nsb = [BitConverter]::ToUInt32($b, $off + 4); $alg = [BitConverter]::ToUInt64($b, $off + 8)
    if ($alg -eq [uint64]3244556288 -and $cnt -gt 0 -and $cnt -lt 20000 -and $nsb -gt 0 -and $nsb -lt 2000000) {
      $hdr = $off + 16 + $cnt * 8; $sp = $hdr + $cnt * 2; $names = New-Object System.Collections.Generic.List[string]
      for ($i = 0; $i -lt $cnt; $i++) { $h0 = $b[$hdr + $i * 2]; $h1 = $b[$hdr + $i * 2 + 1]; $len = (($h0 -band 0x7F) -shl 8) -bor $h1
        if (($h0 -band 0x80) -ne 0) { $names.Add([Text.Encoding]::Unicode.GetString($b, $sp, $len * 2)); $sp += $len * 2 } else { $names.Add([Text.Encoding]::ASCII.GetString($b, $sp, $len)); $sp += $len } }
      return $names } }
  return $null
}

$bpRoot = Join-Path $ExportRoot 'Permafrost\Blueprints'
$files = [IO.Directory]::EnumerateFiles($bpRoot, '*.uasset', [IO.SearchOption]::AllDirectories)
$refRx = '^(DA|BP|AM|IA|IP|NPC|GE|GA|WL|PERMA|BT|BTT|ST|ABP|PALS|RALS|NE|AIC|S|EQS|Anim|TemperatureProfile)_'
$rows = New-Object System.Collections.Generic.List[object]
foreach ($f in $files) {
  $b = [IO.File]::ReadAllBytes($f); $n = Get-NameMap $b
  $rel = $f.Substring($bpRoot.Length + 1); $stem = [IO.Path]::GetFileNameWithoutExtension($f); $parts = $rel -split '\\'
  $refs = @(); $paths = @()
  if ($n) {
    $refs = @($n | Where-Object { $_ -match $refRx -and $_ -ne $stem -and $_ -ne "${stem}_C" -and $_ -notmatch '\.' -and $_ -notmatch '/' } | ForEach-Object { $_ -replace '_C$', '' } | Select-Object -Unique)
    $paths = @($n | Where-Object { $_ -like '/Game/*' -and $_ -notmatch '\.' } | Select-Object -Unique)
  }
  $prefix = if ($stem -match '^([A-Za-z]+)_') { $Matches[1] } else { '' }
  $rows.Add([pscustomobject]@{ Asset = $stem; Prefix = $prefix; Area = $parts[0]; Group = $(if ($parts.Count -gt 2) { $parts[1] } else { '' }); Folder = ($parts[0..($parts.Count - 2)] -join '/'); SizeKB = [math]::Round($b.Length / 1KB, 1); Refs = ($refs -join ';'); RefCount = $refs.Count; AssetPaths = ($paths -join ';') })
}
"indexed $($rows.Count) blueprint-area assets in $([math]::Round($sw.Elapsed.TotalSeconds,1)) s"
$rows | Export-Csv (Join-Path $OutDir 'blueprints-index.csv') -NoTypeInformation -Encoding utf8

# ---- item id lookup (asset name -> inventory id) so references to items read as item ids ----
$itemsPath = Join-Path $PSScriptRoot 'items.json'; $assetToId = @{}
if (Test-Path $itemsPath) { foreach ($i in (Get-Content $itemsPath -Raw | ConvertFrom-Json)) { $assetToId[$i.asset] = $i.id } }
function Resolve-Refs([string]$refs) {
  if (-not $refs) { return @{ Items = ''; Other = '' } }
  $it = @(); $ot = @()
  foreach ($r in ($refs -split ';')) { if ($assetToId.ContainsKey($r)) { $it += $assetToId[$r] } else { $ot += $r } }
  return @{ Items = ($it -join ';'); Other = ($ot -join ';') }
}
function Save-Domain([string]$name, $subset, [switch]$WithItems) {
  $out = foreach ($r in $subset) { $res = Resolve-Refs $r.Refs; [pscustomobject]@{ Asset = $r.Asset; Group = $r.Group; Folder = $r.Folder; SizeKB = $r.SizeKB; Items = $res.Items; References = $res.Other } }
  $out | Export-Csv (Join-Path $OutDir "$name.csv") -NoTypeInformation -Encoding utf8
  "{0,-24} {1,5} rows" -f $name, @($out).Count
}
"--- domain catalogs:"
Save-Domain 'quests'            ($rows | Where-Object { $_.Folder -like 'QuestSystem/Quests*' })
Save-Domain 'quest-bindings'    ($rows | Where-Object { $_.Folder -like 'QuestSystem/Bindings*' })
Save-Domain 'quest-areas'       ($rows | Where-Object { $_.Folder -like 'QuestSystem/Area_Markers*' })
Save-Domain 'quest-dialogues'   ($rows | Where-Object { $_.Folder -like 'QuestSystem/Dialogues*' -or $_.Asset -like 'DA_QuestDialogue_*' })
Save-Domain 'quest-recordings'  ($rows | Where-Object { $_.Folder -like 'QuestSystem/Recordings*' })
Save-Domain 'quest-events'      ($rows | Where-Object { $_.Folder -like 'QuestSystem/Events*' })
Save-Domain 'reward-pools'      ($rows | Where-Object { $_.Asset -like 'DA_RewardPool_*' })
Save-Domain 'loot-configs'      ($rows | Where-Object { $_.Folder -like 'Items/LootConfigs*' })
Save-Domain 'crafting-recipes'  ($rows | Where-Object { $_.Asset -like 'DA_CraftingRecipe_*' })
Save-Domain 'learning-recipes'  ($rows | Where-Object { $_.Asset -like 'DA_Learn*' -or $_.Folder -like 'BuildingParts/LearningRecipes*' })
Save-Domain 'building-parts'    ($rows | Where-Object { $_.Folder -like 'BuildingParts/*' -and $_.Folder -notlike 'BuildingParts/LearningRecipes*' })
Save-Domain 'containers'        ($rows | Where-Object { $_.Folder -like 'Interactions/Containers*' })
Save-Domain 'interactions'      ($rows | Where-Object { $_.Folder -like 'Interactions/*' -and $_.Folder -notlike 'Interactions/Containers*' })
Save-Domain 'npcs'              ($rows | Where-Object { $_.Folder -like 'Characters/NPCs*' })
Save-Domain 'animals'           ($rows | Where-Object { $_.Folder -like 'Characters/Animals*' })
Save-Domain 'companion'         ($rows | Where-Object { $_.Folder -like 'Characters/Companion*' })
Save-Domain 'world-locations'   ($rows | Where-Object { $_.Folder -like 'World/WorldLocations*' })
Save-Domain 'weather-world'     ($rows | Where-Object { $_.Folder -like 'World/*' -and $_.Folder -notlike 'World/WorldLocations*' })
Save-Domain 'gameplay-effects'  ($rows | Where-Object { $_.Folder -like 'GAS/*' })
Save-Domain 'achievements'      ($rows | Where-Object { $_.Folder -like 'AchievementsAndStatistics*' })
Save-Domain 'random-encounters' ($rows | Where-Object { $_.Folder -like 'RandomEncounters*' })
Save-Domain 'difficulty-status' ($rows | Where-Object { $_.Folder -like 'Difficulty*' -or $_.Folder -like 'CharacterStatus*' })
Save-Domain 'skills'            ($rows | Where-Object { $_.Asset -like 'DA_Skill_*' -or $_.Folder -like '*Skill*' })
Save-Domain 'world-items'       ($rows | Where-Object { $_.Folder -like 'Items/WorldItems*' })
Save-Domain 'holdables'         ($rows | Where-Object { $_.Folder -like 'Items/HoldableItems*' })
"total time $([math]::Round($sw.Elapsed.TotalSeconds,1)) s ; output: $OutDir"
