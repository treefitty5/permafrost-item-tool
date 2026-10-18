param(
  [string]$QuestRoot = '',
  [string]$ItemsJson = (Join-Path $PSScriptRoot 'items.json')
)
. (Join-Path $PSScriptRoot 'Paths.ps1')
if (-not $QuestRoot) { $QuestRoot = PF-ExportPath 'Permafrost\Content\Permafrost\Blueprints\QuestSystem' }
# Quests, read from FModel's JSON export (Mappings.usmap, real field names). Each BP_Quest_*.json holds one quest as a graph:
#   Quest        QuestStartState, States[], Branches[]       (+ default object: QuestID, bMainQuest, QuestName, QuestDescription, GeneralObjective)
#   QuestState   ID, StateNodeType (Success / Fail / ...), Description, Branches[] (the ways forward from this state), Events[]
#   QuestBranch  ID, QuestTasks[] (objectives that must ALL be done), DestinationState, Events[]
#   QuestObjective_*  the tasks: ItemFind, Build, NPC_Talk, ... each with its own parameters
# Writes catalog\quests-detail.csv, quest-states.csv, quest-branches.csv, quest-objectives.csv.
$ErrorActionPreference = 'Stop'
$items = Get-Content $ItemsJson -Raw | ConvertFrom-Json; $idOf = @{}; foreach ($i in $items) { $idOf[$i.asset] = $i.id }
function Short([string]$a) { if ($idOf.ContainsKey($a)) { return $idOf[$a] }; return $a }
function RefKey($r) { if (-not $r -or -not $r.ObjectName) { return '' }; $s = [string]$r.ObjectName; if ($s -match ":([^']*)'?$") { return $Matches[1] }; return '' }
function Simp($v, [int]$depth = 0) {
  if ($null -eq $v) { return '' }
  if ($v -is [string] -or $v -is [bool] -or $v -is [int] -or $v -is [long] -or $v -is [double]) { return [string]$v }
  if ($v -is [array]) { return ((@($v) | ForEach-Object { Simp $_ ($depth + 1) }) -join ' ; ') }
  $p = $v.PSObject.Properties.Name
  if ($p -contains 'SourceString') { return [string]$v.SourceString }
  if ($p -contains 'AssetPathName') { $a = ((([string]$v.AssetPathName) -split '/')[-1] -replace '^.*\.', ''); return (Short $a) }
  if ($p -contains 'TagName') { return [string]$v.TagName }
  if ($p -contains 'ObjectName') { $s = [string]$v.ObjectName; if ($s -match "'([^']*)'$") { $s = $Matches[1] }; return ($s -replace '^.*[:.]', '') }
  if ($depth -ge 3) { return '{...}' }
  return '{' + ((@($p) | ForEach-Object { "$_=$(Simp $v.$_ ($depth + 1))" }) -join ', ') + '}'
}
function EnumName([string]$e) { return ($e -replace '^.*::', '') }

$quests = New-Object System.Collections.Generic.List[object]; $states = New-Object System.Collections.Generic.List[object]
$branches = New-Object System.Collections.Generic.List[object]; $objs = New-Object System.Collections.Generic.List[object]
foreach ($f in [IO.Directory]::EnumerateFiles($QuestRoot, 'BP_Quest_*.json', [IO.SearchOption]::AllDirectories)) {
  $qn = [IO.Path]::GetFileNameWithoutExtension($f); $chain = ($f.Substring($QuestRoot.Length + 1) -replace '\\[^\\]+$', '')
  $j = Get-Content $f -Raw | ConvertFrom-Json
  $def = $j | Where-Object { $_.Type -like 'BP_Quest_*_C' -and $_.Name -like 'Default__*' } | Select-Object -First 1
  $qobj = $j | Where-Object { $_.Type -eq 'Quest' } | Select-Object -First 1
  # index every object by its key (outer path after ':' + name)
  $byKey = @{}; foreach ($o in $j) { if ($o.Outer -and $o.Outer.ObjectName) { $ok = RefKey $o.Outer; $byKey["$ok.$($o.Name)"] = $o } }
  $stateObjs = @(); $branchObjs = @()
  if ($qobj) { $stateObjs = @(@($qobj.Properties.States) | ForEach-Object { $byKey[(RefKey $_)] } | Where-Object { $_ }); $branchObjs = @(@($qobj.Properties.Branches) | ForEach-Object { $byKey[(RefKey $_)] } | Where-Object { $_ }) }
  $stateId = @{}; foreach ($s in $stateObjs) { $stateId[("QuestTemplate." + $s.Name)] = [string]$s.Properties.ID }
  $startKey = if ($qobj -and $qobj.Properties.QuestStartState) { RefKey $qobj.Properties.QuestStartState } else { '' }
  $branchOwner = @{}   # branch key -> states that lead into it
  foreach ($s in $stateObjs) { foreach ($b in @($s.Properties.Branches)) { $bk = RefKey $b; if (-not $branchOwner.ContainsKey($bk)) { $branchOwner[$bk] = @() }; $branchOwner[$bk] += [string]$s.Properties.ID } }
  $pd = if ($def) { $def.Properties } else { $null }
  $quests.Add([pscustomobject]@{ Quest = $qn; QuestID = [string]$pd.QuestID; Name = [string]$pd.QuestName.SourceString; Main = [bool]$pd.bMainQuest; GeneralObjective = [string]$pd.GeneralObjective.SourceString
      Description = [string]$pd.QuestDescription.SourceString; Chain = $chain; StartState = [string]$stateId[$startKey]; States = $stateObjs.Count; Branches = $branchObjs.Count })
  foreach ($s in $stateObjs) { $sp = $s.Properties
    $states.Add([pscustomobject]@{ Quest = $qn; StateID = [string]$sp.ID; IsStart = ((("QuestTemplate." + $s.Name) -eq $startKey)); Type = $(if ($sp.StateNodeType) { EnumName $sp.StateNodeType } else { 'Normal' })
        Description = [string]$sp.Description.SourceString
        Branches = ((@($sp.Branches) | ForEach-Object { $bo = $byKey[(RefKey $_)]; if ($bo) { [string]$bo.Properties.ID } }) -join '; ')
        Events = ((@($sp.Events) | ForEach-Object { $eo = $byKey[(RefKey $_)]; if ($eo) { "$($eo.Type -replace '_C$', '')" + $(if ($eo.Properties) { ' (' + (Simp $eo.Properties 2) + ')' }) } }) -join ' ; ') }) }
  foreach ($b in $branchObjs) { $bp = $b.Properties; $bk = "QuestTemplate.$($b.Name)"
    $dest = if ($bp.DestinationState) { [string]$stateId[(RefKey $bp.DestinationState)] } else { '' }
    $tasks = @(@($bp.QuestTasks) | ForEach-Object { $byKey[(RefKey $_)] } | Where-Object { $_ })
    $branches.Add([pscustomobject]@{ Quest = $qn; BranchID = [string]$bp.ID; From = (@($branchOwner[$bk] | Select-Object -Unique) -join '; '); To = $dest
        Tasks = (($tasks | ForEach-Object { ($_.Type -replace '^QuestObjective_', '') }) -join '; ')
        Events = ((@($bp.Events) | ForEach-Object { $eo = $byKey[(RefKey $_)]; if ($eo) { "$($eo.Type -replace '_C$', '')" + $(if ($eo.Properties) { ' (' + (Simp $eo.Properties 2) + ')' }) } }) -join ' ; ') })
    foreach ($t in $tasks) { $tp = $t.Properties; $kv = @(); if ($tp) { foreach ($n in $tp.PSObject.Properties.Name) { $kv += "$n=$(Simp $tp.$n)" } }
      $desc = if ($tp.DescriptionOverride) { [string]$tp.DescriptionOverride.SourceString } else { '' }
      $objs.Add([pscustomobject]@{ Quest = $qn; BranchID = [string]$bp.ID; Objective = ($t.Type -replace '^QuestObjective_', ''); Description = $desc; Parameters = ($kv -join ' | ') }) } } }
$cat = Join-Path $PSScriptRoot 'catalog'
$quests | Export-Csv "$cat\quests-detail.csv" -NoTypeInformation -Encoding UTF8; $states | Export-Csv "$cat\quest-states.csv" -NoTypeInformation -Encoding UTF8
$branches | Export-Csv "$cat\quest-branches.csv" -NoTypeInformation -Encoding UTF8; $objs | Export-Csv "$cat\quest-objectives.csv" -NoTypeInformation -Encoding UTF8
"quests: $($quests.Count) (main: $(@($quests | Where-Object Main).Count)) | states: $($states.Count) | branches: $($branches.Count) | objectives: $($objs.Count)"
"objective types: " + (($objs | Group-Object Objective | Sort-Object Count -Descending | ForEach-Object { "$($_.Name)=$($_.Count)" }) -join ', ')
