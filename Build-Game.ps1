param(
  [string]$BlueprintsRoot = '',
  [string]$ItemsJson = (Join-Path $PSScriptRoot 'items.json')
)
. (Join-Path $PSScriptRoot 'Paths.ps1')
if (-not $BlueprintsRoot) { $BlueprintsRoot = PF-ExportPath 'Permafrost\Content\Permafrost\Blueprints' }
# Game rules, read from FModel's JSON export (Mappings.usmap, real field names). Writes catalog\*.csv:
#   effects.csv      GAS\GameplayEffects   what each gameplay effect does (duration, period, stacking, attribute modifiers, tags, follow-up effects)
#   attributes.csv   GAS\Attributes        display names of the character attributes
#   statuses.csv     CharacterStatus       status effects (Bleeding, Weary, Caffeinated ...): label, description, remedy
#   difficulty.csv   Difficulty\Presets    each difficulty preset and its settings
#   animals.csv      Characters\Data\Animals   health, damage, threat score, loot, journal text
#   npcs.csv         Characters\Data       friendly NPCs (id, name, job, journal text)
#   skills.csv       Skills                level cap, experience per action, benefit per level
$ErrorActionPreference = 'Stop'
$items = Get-Content $ItemsJson -Raw | ConvertFrom-Json; $idOf = @{}; foreach ($i in $items) { $idOf[$i.asset] = $i.id }
function Txt($x) { if ($null -eq $x) { return '' }; if ($x -is [string]) { return $x }; if ($x.SourceString) { return [string]$x.SourceString }; if ($x.CultureInvariantString) { return [string]$x.CultureInvariantString }; return '' }
function Last($s) { return (([string]$s -split '/')[-1] -replace '^.*\.', '') }
function ClassName($r) { if (-not $r) { return '' }; $s = [string]$r.ObjectName; if ($s -match "'([^']*)'$") { $s = $Matches[1] }; return ($s -replace '_C$', '') }
function Simp($v, [int]$depth = 0) {
  if ($null -eq $v) { return '' }
  if ($v -is [string] -or $v -is [bool] -or $v -is [int] -or $v -is [long] -or $v -is [double]) { return ([string]$v -replace '^[A-Za-z]+::', '') }
  if ($v -is [array]) { return ((@($v) | ForEach-Object { Simp $_ ($depth + 1) }) -join '; ') }
  $p = $v.PSObject.Properties.Name
  if ($p -contains 'SourceString') { return [string]$v.SourceString }
  if ($p -contains 'AssetPathName') { $a = Last $v.AssetPathName; if ($idOf.ContainsKey($a)) { return $idOf[$a] }; return $a }
  if ($p -contains 'TagName') { return [string]$v.TagName }
  if ($p -contains 'ObjectName') { return (ClassName $v) }
  if ($depth -ge 3) { return '{...}' }
  return '{' + ((@($p) | ForEach-Object { "$_=$(Simp $v.$_ ($depth + 1))" }) -join ', ') + '}'
}
function Read-Json($f) { return (Get-Content $f -Raw | ConvertFrom-Json) }
function Main-Obj($j) { return @($j | Where-Object { $_.Properties -and $_.Type -notmatch 'BlueprintGeneratedClass' } | Select-Object -First 1)[0] }
function Files($sub, $filter) { $d = Join-Path $BlueprintsRoot $sub; if (-not (Test-Path -LiteralPath $d)) { return @() }; return @([IO.Directory]::EnumerateFiles($d, $filter, [IO.SearchOption]::AllDirectories)) }
$cat = Join-Path $PSScriptRoot 'catalog'

# ---- attributes
$attr = New-Object System.Collections.Generic.List[object]; $attrName = @{}
foreach ($f in Files 'GAS\Attributes' '*.json') { $o = Main-Obj (Read-Json $f); if (-not $o -or $o.Type -ne 'Data_AttributeDisplayConfig') { continue }; $p = $o.Properties
  $attr.Add([pscustomobject]@{ Asset = [IO.Path]::GetFileNameWithoutExtension($f); AttributeID = (Simp $p.AssetID); DisplayName = (Txt $p.DisplayName); BenefitDirection = (Simp $p.BenefitDirection) }); $attrName[(Simp $p.AssetID)] = (Txt $p.DisplayName) }
$attr | Export-Csv "$cat\attributes.csv" -NoTypeInformation -Encoding UTF8

# ---- gameplay effects
function Mag($m) {
  if (-not $m) { return '' }; $t = if ($m.MagnitudeCalculationType) { ([string]$m.MagnitudeCalculationType -replace '^.*::', '') } else { 'ScalableFloat' }
  switch ($t) { 'ScalableFloat' { return [string]$m.ScalableFloatMagnitude.Value }
    'SetByCaller' { $tag = if ($m.SetByCallerMagnitude -and $m.SetByCallerMagnitude.DataTag) { ' ' + [string]$m.SetByCallerMagnitude.DataTag.TagName } else { '' }; return "value supplied by the item/ability$tag" }
    'AttributeBased' { return 'based on an attribute' } 'CustomCalculationClass' { return 'custom calculation' } default { return $t } } }
$eff = New-Object System.Collections.Generic.List[object]
foreach ($f in Files 'GAS\GameplayEffects' 'GE_*.json') {
  $name = [IO.Path]::GetFileNameWithoutExtension($f); $folder = ($f.Substring((Join-Path $BlueprintsRoot 'GAS\GameplayEffects').Length + 1) -replace '\\[^\\]+$', '')
  $j = Read-Json $f; $d = @($j | Where-Object { $_.Name -like 'Default__*' })[0]; $p = if ($d) { $d.Properties } else { $null }
  $pol = if ($p -and $p.DurationPolicy) { ([string]$p.DurationPolicy -replace '^.*::', '') } else { 'Instant' }
  $dur = if ($p -and $p.DurationMagnitude) { Mag $p.DurationMagnitude } else { '' }
  $per = if ($p -and $p.Period) { if ($p.Period.Value) { [string]$p.Period.Value } else { Simp $p.Period } } else { '' }
  $stack = if ($p -and $p.StackingType) { ([string]$p.StackingType -replace '^.*::', '') + $(if ($p.StackLimitCount) { " (limit $($p.StackLimitCount))" }) } else { '' }
  $mods = if ($p -and $p.Modifiers) { (@($p.Modifiers) | ForEach-Object { $an = [string]$_.Attribute.AttributeName; $nice = if ($attrName.ContainsKey($an)) { $attrName[$an] } else { $an }; "$nice $(([string]$_.ModifierOp -replace '^.*::', '')) $(Mag $_.ModifierMagnitude)" }) -join ' ; ' } else { '' }
  $tags = if ($p -and $p.InheritableGameplayEffectTags -and $p.InheritableGameplayEffectTags.Added) { (@($p.InheritableGameplayEffectTags.Added) | ForEach-Object { ($_ -split '\.')[-2..-1] -join '.' }) -join '; ' } else { '' }
  $follow = @(); if ($p -and $p.ConditionalGameplayEffects) { foreach ($c in @($p.ConditionalGameplayEffects)) { $follow += (ClassName $c.EffectClass) } }
  $other = @(); foreach ($o in $j) { if ($o.Type -match 'GameplayEffectComponent$|EffectComponent$' -and $o.Properties) { $pp = $o.Properties
      foreach ($k in 'OnApplicationGameplayEffects', 'OnCompleteNormal', 'OnCompletePrematurely', 'OnCompleteAlways') { if ($pp.$k) { $follow += (@($pp.$k) | ForEach-Object { "$k -> $(ClassName $_)" }) } }
      if ($o.Type -match 'StatusUI') { $other += ('status UI: ' + (Simp $pp 2)) } } }
  $eff.Add([pscustomobject]@{ Effect = $name; Folder = $folder; Policy = $pol; Duration = $dur; Period = $per; Stacking = $stack; Modifiers = $mods; Tags = $tags; FollowUp = (($follow | Select-Object -Unique) -join '; '); Notes = ($other -join ' | ') }) }
$eff | Sort-Object Folder, Effect | Export-Csv "$cat\effects.csv" -NoTypeInformation -Encoding UTF8

# ---- status effects
$st = New-Object System.Collections.Generic.List[object]
foreach ($f in Files 'CharacterStatus' 'DA_CharStatus_*.json') { $o = Main-Obj (Read-Json $f); if (-not $o) { continue }; $p = $o.Properties
  $st.Add([pscustomobject]@{ Asset = [IO.Path]::GetFileNameWithoutExtension($f); Label = (Txt $p.Label); Description = (Txt $p.Description); Remedy = (Txt $p.Remedy); EffectAffinity = (Simp $p.EffectAffinity); ShowPopup = [string]$p.bShowPopup; Popup = (Simp $p.PopupData 2) }) }
$st | Sort-Object Label | Export-Csv "$cat\statuses.csv" -NoTypeInformation -Encoding UTF8

# ---- difficulty
$df = New-Object System.Collections.Generic.List[object]
foreach ($f in Files 'Difficulty\Presets' 'DA_*Preset*.json') { $o = Main-Obj (Read-Json $f); if (-not $o -or $o.Type -ne 'DifficultyPreset') { continue }; $p = $o.Properties
  $df.Add([pscustomobject]@{ Asset = [IO.Path]::GetFileNameWithoutExtension($f); Name = (Txt $p.PresetName); Type = (Simp $(if ($p.PresetType) { $p.PresetType } else { $p.Settings.PresetType })); Description = (Txt $p.Description); Settings = (Simp $p.Settings 1) }) }
$df | Export-Csv "$cat\difficulty.csv" -NoTypeInformation -Encoding UTF8

# ---- animals / npcs
$an = New-Object System.Collections.Generic.List[object]; $np = New-Object System.Collections.Generic.List[object]
foreach ($f in Files 'Characters\Data' '*.json') { $o = Main-Obj (Read-Json $f); if (-not $o) { continue }; $p = $o.Properties; $name = [IO.Path]::GetFileNameWithoutExtension($f)
  if ($o.Type -eq 'AnimalConfig') { $an.Add([pscustomobject]@{ Asset = $name; CharacterID = [string]$p.CharacterID; Name = (Txt $p.CharacterName); MaxHealth = [string]$p.MaxHealth; Damage = [string]$p.Damage; ThreatScore = [string]$p.AnimalThreatScore; Loot = (Last $p.RandomLoot.AssetPathName); Journal = ((@($p.JournalDescriptions) | ForEach-Object { Txt $_ }) -join ' ') }) }
  elseif ($o.Type -eq 'NPCConfig') { $np.Add([pscustomobject]@{ Asset = $name; CharacterID = [string]$p.CharacterID; Name = (Txt $p.CharacterName); Job = (Txt $p.JobName); Journal = ((@($p.JournalDescriptions) | ForEach-Object { Txt $_ }) -join ' ') }) } }
$an | Sort-Object Name | Export-Csv "$cat\animals.csv" -NoTypeInformation -Encoding UTF8; $np | Sort-Object Name | Export-Csv "$cat\npcs.csv" -NoTypeInformation -Encoding UTF8

# ---- skills
$sk = New-Object System.Collections.Generic.List[object]
foreach ($f in Files 'Skills' 'DA_Skill_*.json') { $o = Main-Obj (Read-Json $f); if (-not $o) { continue }; $p = $o.Properties
  $sk.Add([pscustomobject]@{ Asset = [IO.Path]::GetFileNameWithoutExtension($f); SkillID = [string]$p.SkillWorkingName; Name = (Txt $p.SkillName); LevelCap = [string]$p.SkillLevelCap; ExperiencePerAction = [string]$p.ExperienceByAction
      BenefitPerLevel = [string]$p.UniformValuePerLevel; Unit = (Txt $p.BenefitUnit); Benefit = (Txt $p.FrontBenefitText); Description = (Txt $p.Description) }) }
$sk | Sort-Object Name | Export-Csv "$cat\skills.csv" -NoTypeInformation -Encoding UTF8
# ---- plants (farming), destructibles, random encounters, fast travel, achievements, world locations
function Flat($p, [string[]]$names) { return (($names | ForEach-Object { if ($p.PSObject.Properties.Name -contains $_) { "$_=$(Simp $p.$_ 2)" } }) -join ' | ') }
$pl = New-Object System.Collections.Generic.List[object]
foreach ($f in Files 'Farming' 'DA_Plant_*.json') { $o = Main-Obj (Read-Json $f); if (-not $o -or $o.Type -ne 'PlantConfig') { continue }; $p = $o.Properties
  $pl.Add([pscustomobject]@{ Asset = [IO.Path]::GetFileNameWithoutExtension($f); PlantID = [string]$p.PlantID; Name = (Txt $p.PlantName); Description = (Txt $p.PlantDescription); YieldProducingTime = [string]$p.YieldProducingTime; WaterUsage = [string]$p.WaterUsageRate; LightUsage = [string]$p.LightUsageRate; SoilUsage = [string]$p.SoilQualityUsageRate; Yields = (Simp $p.HarvestedYields 2); GrowthStages = (Simp $p.GrowthStages 2); YieldStages = (Simp $p.YieldStages 2) }) }
$pl | Export-Csv "$cat\plants.csv" -NoTypeInformation -Encoding UTF8
$ds = New-Object System.Collections.Generic.List[object]
foreach ($f in Files 'Destructable\DestructableBlueprints' 'BP_D_*.json') { $j = Read-Json $f; $d = @($j | Where-Object { $_.Name -like 'Default__*' })[0]; if (-not $d -or -not $d.Properties) { continue }; $p = $d.Properties
  $ds.Add([pscustomobject]@{ Asset = [IO.Path]::GetFileNameWithoutExtension($f); Name = (Txt $p.Name); MaxHealth = [string]$p.MaxHealth; ToolType = (Simp $p.'Required Tool Type'); ToolTier = (Simp $p.'Required Tool Tier'); FinalLoot = (Simp $p.'Final Loot' 1); ProgressiveLoot = (Simp $p.'Progressive Loot' 1) }) }
$ds | Sort-Object Asset | Export-Csv "$cat\destructibles.csv" -NoTypeInformation -Encoding UTF8
$en = New-Object System.Collections.Generic.List[object]
foreach ($f in Files 'RandomEncounters' '*.json') { $o = Main-Obj (Read-Json $f); if (-not $o -or $o.Type -ne 'RandomEncounter_Config') { continue }; $p = $o.Properties
  $en.Add([pscustomobject]@{ Asset = [IO.Path]::GetFileNameWithoutExtension($f); EncounterID = [string]$p.RandomEncounterID; SpawnTime = (Simp $p.SpawnTime); Actors = (Simp $p.ActorsToSpawn 2); Query = (Simp $p.RandomEncounterQuery 1); Placement = (Simp $p.ActorPlacementQuery 1) }) }
$en | Sort-Object Asset | Export-Csv "$cat\encounters.csv" -NoTypeInformation -Encoding UTF8
$ft = New-Object System.Collections.Generic.List[object]
foreach ($f in Files 'FastTravel' 'PDA_FT_*.json') { $o = Main-Obj (Read-Json $f); if (-not $o) { continue }; $p = $o.Properties; $ft.Add([pscustomobject]@{ Asset = [IO.Path]::GetFileNameWithoutExtension($f); WorkingName = [string]$p.WorkingName; Name = (Txt $p.FastTravelPointName) }) }
$ft | Export-Csv "$cat\fasttravel.csv" -NoTypeInformation -Encoding UTF8
$ac = New-Object System.Collections.Generic.List[object]
foreach ($f in Files 'AchievementsAndStatistics' '*.json') { $o = Main-Obj (Read-Json $f); if (-not $o) { continue }; $p = $o.Properties
  if ($o.Type -eq 'AchievementConfig') { $ac.Add([pscustomobject]@{ Asset = [IO.Path]::GetFileNameWithoutExtension($f); Kind = 'Achievement'; ID = [string]$p.AchievementId; Disabled = '' }) }
  elseif ($o.Type -eq 'StatisticConfig') { $ac.Add([pscustomobject]@{ Asset = [IO.Path]::GetFileNameWithoutExtension($f); Kind = 'Statistic'; ID = [string]$p.StatisticID; Disabled = [string]$p.bDisabled }) } }
$ac | Sort-Object Kind, ID | Export-Csv "$cat\achievements.csv" -NoTypeInformation -Encoding UTF8
$wl = New-Object System.Collections.Generic.List[object]
foreach ($f in Files 'World' 'WL_*.json') { $o = Main-Obj (Read-Json $f); if (-not $o -or $o.Type -ne 'Data_WorldLocationInstance') { continue }; $p = $o.Properties; $wl.Add([pscustomobject]@{ Asset = [IO.Path]::GetFileNameWithoutExtension($f); LocationID = [string]$p.LocationID; Category = (Simp $p.Category); Discoverable = [string]$p.bDiscoverable }) }
$wl | Sort-Object Category, LocationID | Export-Csv "$cat\locations.csv" -NoTypeInformation -Encoding UTF8
"plants: $($pl.Count) | destructibles: $($ds.Count) | encounters: $($en.Count) | fast travel: $($ft.Count) | achievements+stats: $($ac.Count) | world locations: $($wl.Count)"
# ---- difficulty: side-by-side comparison (rows = settings, columns = presets; a setting a preset does not store keeps the game's default)
$presetObjs = @(); foreach ($pf in Files 'Difficulty\Presets' 'DA_*Preset*.json') { $po = Main-Obj (Read-Json $pf); if ($po -and $po.Type -eq 'DifficultyPreset') { $presetObjs += [pscustomobject]@{ Name = ((Txt $po.Properties.PresetName).Trim()); Settings = $po.Properties.Settings } } }
$keys = New-Object System.Collections.Generic.List[string]; foreach ($po in $presetObjs) { foreach ($k in $po.Settings.PSObject.Properties.Name) { if ($k -ne 'PresetType' -and -not $keys.Contains($k)) { $keys.Add($k) } } }
function Setting-Text($v) { if ($null -eq $v) { return '(default)' }; if ($v -is [array]) { return ((@($v) | ForEach-Object { if ($_.WeatherConditionType) { "$(([string]$_.WeatherConditionType -replace '^.*::', '')) x$($_.TemperatureModifier)" } else { Simp $_ 2 } }) -join '; ') }; return (Simp $v 2) }
$cmp = New-Object System.Collections.Generic.List[object]
foreach ($k in $keys) { $row = [ordered]@{ Setting = $k }; foreach ($po in $presetObjs) { $row[$po.Name] = Setting-Text $po.Settings.$k }; $cmp.Add([pscustomobject]$row) }
$cmp | Export-Csv "$cat\difficulty-compare.csv" -NoTypeInformation -Encoding UTF8
"difficulty compare: $($keys.Count) settings x $($presetObjs.Count) presets"
"effects: $($eff.Count) (with modifiers: $(@($eff | Where-Object Modifiers).Count)) | attributes: $($attr.Count) | statuses: $($st.Count) | difficulty presets: $($df.Count) | animals: $($an.Count) | npcs: $($np.Count) | skills: $($sk.Count)"
