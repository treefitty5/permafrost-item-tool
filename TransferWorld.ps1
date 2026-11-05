# TransferWorld.ps1 - copies what is YOURS (your base with its containers and benches, the items on you, your skills) from one world's save into another world's save,
# so you can start the story again in a new world without rebuilding and re-collecting everything. The source save is only read; the target gets a backup first.
# Needs SaveCore.ps1, PlayerCore.ps1 (blob entries, backups) and ContainerLabels.ps1 (CL-ParseParts for the preview).
#
# How the save holds these values (see PlayerCore.ps1): every player value exists in THREE synced copies - the plain text, the PlayerSaveData blob and the HostSaveData blob.
# A brand-new character does not have three of them yet: PlayerBuildParts (the whole base, with the contents of every container and station) and BedRespawnPointID /
# BedRespawnLocation. They are ADDED where the game itself puts them: PlayerBuildParts is the FIRST entry of both blobs and sits in the plain text just before ?QuestSystem>;
# the two bed entries are the LAST entries of both blobs and sit in the plain text right after ?PlayerCraftingQueue>. Everything else is replaced in place.
# Character look, effects and every other world object are never touched. Learned recipes are copied only when you tick them. The story is only touched by the optional "skip the tutorial" step,
# which marks the four opening quests done (their records come from the source), starts the next one, copies the tutorial pop-ups seen and brings the dog (a world record) along; it only runs on a world with no quest progress.

$script:TwSkillKeys = @('CharacterSkillsComponent_SkillCount') + @(0..15 | ForEach-Object { "CharacterSkillsComponent_Skill_$_" }) + @('PointsAmount')
$script:TwGroups = [ordered]@{
  Base    = @{ Label = 'Your base: every building part with the contents of your barrels, chests, bookshelves, benches and furnaces, and your bed'; Keys = @('PlayerBuildParts', 'BedRespawnPointID', 'BedRespawnLocation'); Default = $true }
  Items   = @{ Label = 'The items on you: hotbar, worn clothes and backpack with everything in it, special items'; Keys = @('BaseInvSlots', 'Equipment', 'SpecialItems'); Default = $true }
  Skills  = @{ Label = 'Your 16 skills (levels and experience) and unspent skill points'; Keys = $script:TwSkillKeys; Default = $true }
  Vitals  = @{ Label = 'Your vitals: health, stamina, energy, hunger and body warmth (a new character starts cold and hurt)'; Keys = @('health', 'MaxHealth', 'stamina', 'MaxStamina', 'energy', 'MaxEnergy', 'hunger', 'MaxHunger', 'BodyWarmth', 'MaxBodyWarmth'); Default = $true }
  Map     = @{ Label = 'The map you have uncovered (the fog of war: the squares you have explored)'; Keys = @('FogOfWarRevealer_Voxels'); Default = $true }
  Tutorial = @{ Label = 'SKIP THE TUTORIAL: mark the opening quests done (tools, campfire, bow, the cave, the dog), start Robyn''s next quest and bring your dog along'; Keys = @('QuestSystem'); Default = $true }
  Recipes = @{ Label = 'The recipes you have learned (OFF by default: a few story steps unlock recipes, so copying them can skip or confuse parts of the story)'; Keys = @('PlayerKnowledge_Knowledge'); Default = $false }
}
# the opening of the story, in the order the game runs it; each quest's last step starts the next one. The last entry is only STARTED (it is the first quest of the real story).
$script:TwTutorialChain = @('Main_01_NewBeginning', 'Main_02', 'Main_Robyn_Cooking', 'Village_Main_01_DogDays')
$script:TwFirstReal = 'Side_Robyn_03_NewHome_Final'
$script:TwFirstRealId = 'BP_Quest_EA_Side_Robyn_06_v2'   # the quest's own QuestID in the game files (what the save's active list names)

# the dog is a world record (State Idle in the cave in a new world; Follow with its pack in your world)
function TW-DogRange([string]$s) {
  $tag = 'PrimaryObjectName>BP_CompanionShepard_C_UAID_'; $m = $s.IndexOf($tag, [StringComparison]::Ordinal)
  if ($m -lt 0 -or $s.IndexOf($tag, $m + 1, [StringComparison]::Ordinal) -ge 0) { return $null }
  $a = $s.LastIndexOf('[BEGIN_OBJECT_SAVE', $m, [StringComparison]::Ordinal); $e = $s.IndexOf('?END_OBJECT_SAVE', $m, [StringComparison]::Ordinal); if ($a -lt 0 -or $e -lt 0) { return $null }
  $b = $e + '?END_OBJECT_SAVE'.Length; return @{ Start = $a; End = $b; Text = $s.Substring($a, $b - $a) }
}
function TW-QuestEntries([string]$qs) {
  $i = $qs.IndexOf('@AllQuests', [StringComparison]::Ordinal); $j = $qs.IndexOf('@ActiveQuests', [StringComparison]::Ordinal); if ($i -lt 0 -or $j -lt $i) { return $null }
  return , @($qs.Substring($i + 10, $j - $i - 10) -split '(?=&/Game/)' | Where-Object { $_ })   # the comma keeps an empty list from turning into $null
}
function TW-ReplaceOnce([string]$t, [string]$old, [string]$new) { $i = $t.IndexOf($old, [StringComparison]::Ordinal); if ($i -lt 0 -or $t.IndexOf($old, $i + 1, [StringComparison]::Ordinal) -ge 0) { throw "could not find '$old' exactly once in the quest data" }; return $t.Substring(0, $i) + $new + $t.Substring($i + $old.Length) }

# where to put you after the copy: just outside the front door = the door closest to the bed (outwards = away from the middle of the foundations), a little above the ground
function TW-DoorSpot($parts, $bed) {
  $inv = [Globalization.CultureInfo]::InvariantCulture; $doors = @(); $fx = 0.0; $fy = 0.0; $fn = 0; $rx = '^#([A-Za-z0-9_]+)&X=([-\d\.]+),Y=([-\d\.]+),Z=([-\d\.]+)&P=[-\d\.]+,Y=([-\d\.]+),R='
  foreach ($seg in ($parts -split '(?=#[A-Za-z])')) { $m = [regex]::Match($seg, $rx); if (-not $m.Success) { continue }
    $x = [double]::Parse($m.Groups[2].Value, $inv); $y = [double]::Parse($m.Groups[3].Value, $inv); $z = [double]::Parse($m.Groups[4].Value, $inv); $yaw = [double]::Parse($m.Groups[5].Value, $inv); $ty = $m.Groups[1].Value
    if ($ty -match 'Foundation|Floor') { $fx += $x; $fy += $y; $fn++ }
    if ($ty -match 'Door$') { $doors += [pscustomobject]@{ X = $x; Y = $y; Z = $z; Yaw = $yaw } } }
  if (-not $doors.Count) { foreach ($seg in ($parts -split '(?=#[A-Za-z])')) { $m = [regex]::Match($seg, $rx); if ($m.Success -and $m.Groups[1].Value -match 'Doorway$') { $doors += [pscustomobject]@{ X = [double]::Parse($m.Groups[2].Value, $inv); Y = [double]::Parse($m.Groups[3].Value, $inv); Z = [double]::Parse($m.Groups[4].Value, $inv); Yaw = [double]::Parse($m.Groups[5].Value, $inv) } } } }
  if (-not $doors.Count -or $fn -eq 0) { return $null }
  $cx = $fx / $fn; $cy = $fy / $fn
  $d = $doors | Sort-Object { [math]::Pow($_.X - $bed.X, 2) + [math]::Pow($_.Y - $bed.Y, 2) } | Select-Object -First 1
  $a = $d.Yaw * [math]::PI / 180; $axes = @(@([math]::Cos($a), [math]::Sin($a)), @(-[math]::Sin($a), [math]::Cos($a)))   # the door's two horizontal axes
  $vx = $d.X - $cx; $vy = $d.Y - $cy; $len = [math]::Sqrt($vx * $vx + $vy * $vy); if ($len -lt 1) { return $null }
  $best = $null; $bd = 0.0; foreach ($u in $axes) { $dot = ($vx * $u[0] + $vy * $u[1]) / $len; if ([math]::Abs($dot) -gt [math]::Abs($bd)) { $bd = $dot; $best = $u } }
  $sg = if ($bd -ge 0) { 1 } else { -1 }
  return @{ X = $d.X + $sg * $best[0] * 100; Y = $d.Y + $sg * $best[1] * 100; Z = $d.Z; DoorX = $d.X; DoorY = $d.Y }
}

# the new QuestSystem value for the target and the dog record, or @{ Skip = 'why' }
function TW-Tutorial($S, $D, [string]$srcText, [string]$dstText) {
  $sq = $S.PV['QuestSystem']; $dq = $D.PV['QuestSystem']; if (-not $sq -or -not $dq) { return @{ Skip = 'a save has no quest data' } }
  $de = TW-QuestEntries $dq; if ($null -eq $de) { return @{ Skip = 'the target quest data is not in the expected layout' } }
  if ($de.Count -ne 0 -or $dq -notmatch '@ActiveQuests#QuestRewards#TimeEvents#OtherData@PinnedRecipe@UnlockedRegions@SkipAllTutorial' -or $dq -notmatch '@Recordings\|\d+@Tutorials\|\d+') { return @{ Skip = 'the target world already has quest progress: only a brand-new world can have its tutorial skipped' } }
  $se = TW-QuestEntries $sq; if ($null -eq $se) { return @{ Skip = 'the source quest data is not in the expected layout' } }
  $pick = @{}; foreach ($n in ($script:TwTutorialChain + $script:TwFirstReal)) { $e = @($se | Where-Object { $_ -match ('/BP_Quest_EA_' + [regex]::Escape($n) + '\.BP_Quest_EA_' + [regex]::Escape($n) + '_C\*') }); if ($e.Count -ne 1) { return @{ Skip = "the source world has no record of the quest $n (it has not got that far)" } }; $pick[$n] = $e[0] }
  foreach ($n in $script:TwTutorialChain) { $st = $pick[$n].Split('*')[1]; if ($st -notmatch 'Success|Final|End|^QuestState_(21|9|1)$') { return @{ Skip = "the source world has not finished the opening quest $n (it is at $st)" } } }
  # the first real quest, only STARTED: first state, every counter at 0
  $p = $pick[$script:TwFirstReal].Split('*'); if ($p.Count -ne 4 -or $p[2] -notmatch '^Branches' -or $p[3] -notmatch '^States\$') { return @{ Skip = 'the layout of the next quest record is not the expected one' } }
  $first = $p[3].Substring(7).Split('$')[0]
  $next = 'QuestState_6'; $exitBranch = 'QuestBranch_45'   # "Exit the Bone Cave" (State_1_Start -> QuestState_6) is done: you are not in the cave
  if ($p[3] -notmatch ('\$' + $next + '(\$|$)') -or $p[2] -notmatch ('\$' + $exitBranch + ',')) { return @{ Skip = 'the next quest record does not have the expected steps' } }
  $zeroed = $p[2] -replace ',\d+', ',0'; $zeroed = [regex]::Replace($zeroed, ('\$' + $exitBranch + ',0(?=\$|$)'), ('$' + $exitBranch + ',1'))
  $startRec = $p[0] + '*' + $next + '*' + $zeroed + '*States$' + $first + '$' + $next
  $body = ''; foreach ($n in $script:TwTutorialChain) { $body += $pick[$n] }; $body += $startRec
  $new = TW-ReplaceOnce $dq '@AllQuests@ActiveQuests' ('@AllQuests' + $body + '@ActiveQuests&' + $script:TwFirstRealId)
  # journal: the opening recording, all tutorial pop-ups seen, the village region, the hut reward
  $rec = @(); $m = [regex]::Match($sq, '@Recordings\|\d+((?:&[^&@#]*)*)@Tutorials'); if ($m.Success) { $rec = @($m.Groups[1].Value.Split('&') | Where-Object { $_ -in 'HorizonStart', 'HorizonStart2' }) }
  $tut = @(); $m = [regex]::Match($sq, '@Tutorials\|\d+((?:&[^&@#]*)*)@Animals'); if ($m.Success) { $tut = @($m.Groups[1].Value.Split('&') | Where-Object { $_ }) }
  $new = [regex]::Replace($new, '@Recordings\|\d+@Tutorials\|\d+', ('@Recordings|' + $rec.Count + (($rec | ForEach-Object { '&' + $_ }) -join '') + '@Tutorials|' + $tut.Count + (($tut | ForEach-Object { '&' + $_ }) -join '')))
  $reg = [regex]::Match($sq, '@UnlockedRegions((?:&[^&@#]*)*)@SkipAllTutorial'); if ($reg.Success -and $reg.Groups[1].Value) { $new = TW-ReplaceOnce $new '@UnlockedRegions@SkipAllTutorial' ('@UnlockedRegions' + $reg.Groups[1].Value + '@SkipAllTutorial') }
  if ($sq -match 'RewardPool_Village&[^>]*OnboardingHut=1') { $new = TW-ReplaceOnce $new '#QuestRewards#TimeEvents' '#QuestRewards$RewardPool_Village&OnboardingHut=1>#TimeEvents' }
  if ($new.Contains('?')) { return @{ Skip = 'the new quest data contains a field separator' } }
  $res = @{ Value = $new; Lines = ("Tutorial: the opening quests $(($script:TwTutorialChain | ForEach-Object { $_ -replace '^(Main|Village_Main)_(\d+_)?', '' }) -join ', ') are marked done, '$($script:TwFirstReal)' is started at its step 'establish a new home' (the cave exit counts as done), $($tut.Count) tutorial pop-ups count as seen."); Dog = $null }
  $sd = TW-DogRange $srcText; $dd = TW-DogRange $dstText
  if ($sd -and $dd) { $res.Dog = $sd.Text; $res.Lines += " Your dog comes along (it follows you, with its pack)." } else { $res.Warn = 'The dog could not be found in one of the saves, so it stays in its cave.' }
  return $res
}
# keys that a fresh character does not have yet and that may therefore have to be ADDED to the target
$script:TwAddable = @('PlayerBuildParts', 'BedRespawnPointID', 'BedRespawnLocation')

function TW-ReadPlayer([string]$path) {
  $s = Get-SaveText $path
  $ps = Read-BlobEntries (Get-BlobSection $s 'PlayerSaveData').Bytes; $hs = Read-BlobEntries (Get-BlobSection $s 'HostSaveData').Bytes
  $pv = @{}; foreach ($e in $ps.Entries) { $pv[$e.Key] = $e.Text }
  $hv = @{}; foreach ($e in $hs.Entries) { $hv[$e.Key] = $e.Text }
  $level = [regex]::Match($s, 'LevelName>([^?]*)').Groups[1].Value
  return @{ Text = $s; Player = $ps; Host = $hs; PV = $pv; HV = $hv; Level = $level }
}

# what would be copied: @{ Keys = ordered list of @{ Key; Value; Mode = 'replace'|'add'|'skip'; Why }; Lines; Warnings; Fatal }
function TW-Plan([string]$srcPath, [string]$dstPath, [string[]]$groups) {
  $plan = @{ Keys = New-Object System.Collections.Generic.List[object]; Lines = New-Object System.Collections.Generic.List[string]; Warnings = New-Object System.Collections.Generic.List[string]; Fatal = $null }
  if (-not (Test-Path -LiteralPath $srcPath)) { $plan.Fatal = "The source save is missing: $srcPath"; return $plan }
  if (-not (Test-Path -LiteralPath $dstPath)) { $plan.Fatal = "The target save is missing: $dstPath"; return $plan }
  if ([IO.Path]::GetFullPath($srcPath) -ieq [IO.Path]::GetFullPath($dstPath)) { $plan.Fatal = 'The source and the target are the same file. Pick another world as the target.'; return $plan }
  $S = TW-ReadPlayer $srcPath; $D = TW-ReadPlayer $dstPath
  if ($S.Level -ne $D.Level) { $plan.Fatal = "The two worlds are not on the same map ('$($S.Level)' and '$($D.Level)'): the base would not fit."; return $plan }
  $plan.Dog = $null; $plan.TutorialLines = $null
  foreach ($g in $groups) {
    if (-not $script:TwGroups.Contains($g)) { continue }
    if ($g -eq 'Map') {
      $sm = [regex]::Match($S.Text, 'FogOfWarRevealer_Voxels>([0-9,;]*)'); $dm = [regex]::Match($D.Text, 'FogOfWarRevealer_Voxels>([0-9,;]*)')
      if (-not $sm.Success -or -not $dm.Success) { $plan.Warnings.Add('The map was NOT copied: a save has no uncovered-map data.'); continue }
      $cells = New-Object System.Collections.Generic.List[string]; $seen = @{}; foreach ($v in (($sm.Groups[1].Value + ';' + $dm.Groups[1].Value) -split ';')) { if ($v -match '^-?\d+,-?\d+$' -and -not $seen.ContainsKey($v)) { $seen[$v] = 1; $cells.Add($v) } }
      $val = ($cells -join ';') + $(if ($sm.Groups[1].Value.EndsWith(';')) { ';' } else { '' }); $plan.MapCells = $cells.Count
      if ($val -ceq $dm.Groups[1].Value) { [void]$plan.Keys.Add(@{ Key = 'FogOfWarRevealer_Voxels'; Mode = 'skip'; Why = 'already identical'; Group = $g }) } else { [void]$plan.Keys.Add(@{ Key = 'FogOfWarRevealer_Voxels'; Value = $val; Mode = 'replace'; Group = $g; PlainOnly = $true }) }
      continue }
    if ($g -eq 'Tutorial') {
      $t = TW-Tutorial $S $D $S.Text $D.Text
      if ($t.Skip) { $plan.Warnings.Add("The tutorial was NOT skipped: $($t.Skip).") ; [void]$plan.Keys.Add(@{ Key = 'QuestSystem'; Mode = 'skip'; Why = $t.Skip; Group = $g }); continue }
      [void]$plan.Keys.Add(@{ Key = 'QuestSystem'; Value = $t.Value; Mode = 'replace'; Group = $g }); $plan.Dog = $t.Dog; $plan.TutorialLines = $t.Lines; if ($t.Warn) { $plan.Warnings.Add($t.Warn) }
      continue }
    foreach ($k in $script:TwGroups[$g].Keys) {
      if (-not $S.PV.ContainsKey($k)) { [void]$plan.Keys.Add(@{ Key = $k; Mode = 'skip'; Why = 'the source save has none'; Group = $g }); continue }
      if ($S.HV[$k] -cne $S.PV[$k]) { $plan.Fatal = "The source save is inconsistent for '$k' (its two blob copies differ). Nothing can be copied safely."; return $plan }
      $have = $D.PV.ContainsKey($k) -and $D.HV.ContainsKey($k)
      if ($D.PV.ContainsKey($k) -ne $D.HV.ContainsKey($k)) { $plan.Fatal = "The target save is inconsistent for '$k'. Nothing can be copied safely."; return $plan }
      if ($S.PV[$k].Contains('?')) { $plan.Fatal = "The value of '$k' contains a field separator; refusing."; return $plan }
      if ($have) { if ($D.PV[$k] -ceq $S.PV[$k]) { [void]$plan.Keys.Add(@{ Key = $k; Value = $S.PV[$k]; Mode = 'skip'; Why = 'already identical in the target'; Group = $g }) } else { [void]$plan.Keys.Add(@{ Key = $k; Value = $S.PV[$k]; Mode = 'replace'; Group = $g }) } }
      elseif ($script:TwAddable -contains $k) { [void]$plan.Keys.Add(@{ Key = $k; Value = $S.PV[$k]; Mode = 'add'; Group = $g }) }
      else { $plan.Fatal = "The target save has no '$k' and the tool does not know where the game puts it. Nothing was changed."; return $plan }
    }
  }
  # the summary
  $sp = Get-PlayerData $srcPath; $dp = Get-PlayerData $dstPath
  $plan.Lines.Add(("From: {0}  ({1:N1} h played)   Into: {2}  ({3:N1} h played)" -f [IO.Path]::GetFileName($srcPath), ($sp.Playtime / 3600), [IO.Path]::GetFileName($dstPath), ($dp.Playtime / 3600)))
  if ($groups -contains 'Base' -and $S.PV.ContainsKey('PlayerBuildParts')) {
    $segs = @($S.PV['PlayerBuildParts'] -split '(?=#[A-Za-z])' | Where-Object { $_ }); $cs = @(CL-ParseParts $S.PV['PlayerBuildParts']); $stacks = 0; $pieces = 0; foreach ($c in $cs) { $stacks += $c.Slots; foreach ($v in $c.Items.Values) { $pieces += $v } }
    $plan.Lines.Add(("Base: {0} building parts, among them {1} containers holding {2} item stacks ({3} items in all). Bed: {4}." -f $segs.Count, $cs.Count, $stacks, $pieces, $(if ($S.PV.ContainsKey('BedRespawnLocation')) { 'yes (respawn point copied)' } else { 'none' })))
    if ($D.PV.ContainsKey('PlayerBuildParts')) { $dsegs = @($D.PV['PlayerBuildParts'] -split '(?=#[A-Za-z])' | Where-Object { $_ }); $plan.Warnings.Add("The target already has a base ($($dsegs.Count) parts): it will be REPLACED by yours (the backup keeps it).") }
  }
  if ($groups -contains 'Items') {
    $hot = @($S.PV['BaseInvSlots'] -split '(?=@\d+=)' | Where-Object { $_ }).Count; $worn = [regex]::Matches($S.PV['Equipment'], '#\d+=').Count; $bp = [regex]::Matches($S.PV['Equipment'], '@\d+=').Count
    $plan.Lines.Add("Items on you: $hot hotbar stacks, $worn worn pieces, $bp stacks in the backpack, special items copied as they are.") }
  if ($groups -contains 'Skills') { $lv = @(foreach ($k in 0..15) { $j = $S.PV["CharacterSkillsComponent_Skill_$k"]; if ($j) { [regex]::Match($j, '"level":(\d+)').Groups[1].Value } }); $plan.Lines.Add(("Skills: 16 skills (levels {0}), {1} unspent skill points." -f ($lv -join ' '), $S.PV['PointsAmount'])) }
  if ($groups -contains 'Recipes') { $plan.Lines.Add(("Recipes: {0} learned recipes will replace the target's {1}." -f ([regex]::Matches($S.PV['PlayerKnowledge_Knowledge'], '/Game/')).Count, ([regex]::Matches($D.PV['PlayerKnowledge_Knowledge'], '/Game/')).Count)) }
  if ($groups -contains 'Map' -and $plan.MapCells) { $plan.Lines.Add("Map: $($plan.MapCells) explored squares (50 m x 50 m) are uncovered in the target.") }
  if ($groups -contains 'Vitals') { $plan.Lines.Add(("Vitals: health {0}/{1}, warmth {2}/{3} as in the source world." -f $S.PV['health'], $S.PV['MaxHealth'], $S.PV['BodyWarmth'], $S.PV['MaxBodyWarmth'])) }
  if ($plan.TutorialLines) { $plan.Lines.Add($plan.TutorialLines) }
  $plan.Lines.Add($(if ($plan.TutorialLines) { 'Never touched: the rest of the story (every later quest starts from the beginning), character look, status effects and every other object of the world.' } else { 'Never touched: the story and quests, character look, status effects and every object of the world.' }))
  if (($dp.Playtime / 3600) -gt 2) { $plan.Warnings.Add(("The target world has {0:N1} hours played: it does not look like a new world. The copy replaces what it lists above in that world." -f ($dp.Playtime / 3600))) }
  return $plan
}

# the blob with entries prepended / appended and values replaced (same layout as Write-BlobEntries)
function TW-WriteBlob([byte[]]$blob, $parsed, [hashtable]$changes, $prepend, $append) {
  # the 4 bytes just before the entries hold the entry count: it grows with every added entry
  $ms = New-Object IO.MemoryStream; $ms.Write($blob, 0, $parsed.Start - 4)
  $ms.Write([BitConverter]::GetBytes([int]($parsed.Entries.Count + @($prepend).Count + @($append).Count)), 0, 4)
  $emit = { param($key, $raw) $kb = $script:L1.GetBytes($key + "`0"); $ms.Write([BitConverter]::GetBytes([int]$kb.Length), 0, 4); $ms.Write($kb, 0, $kb.Length); $ms.Write([BitConverter]::GetBytes([int]$raw.Length), 0, 4); if ($raw.Length -gt 0) { $ms.Write($raw, 0, $raw.Length) } }
  foreach ($a in $prepend) { & $emit $a.Key ($script:L1.GetBytes([string]$a.Value + "`0")) }
  foreach ($e in $parsed.Entries) { if ($changes -and $changes.ContainsKey($e.Key)) { & $emit $e.Key ($script:L1.GetBytes([string]$changes[$e.Key] + "`0")) } else { & $emit $e.Key $e.Raw } }
  foreach ($a in $append) { & $emit $a.Key ($script:L1.GetBytes([string]$a.Value + "`0")) }
  return $ms.ToArray()
}

function TW-Build([string]$dstPath, $plan) {
  $todo = @($plan.Keys | Where-Object { $_.Mode -ne 'skip' }); if ($todo.Count -eq 0) { throw 'Nothing to copy: everything that was asked for is already identical in the target, or missing in the source.' }
  $s = Get-SaveText $dstPath
  $rep = @{}; $add = @{}; foreach ($t in $todo) { if ($t.Mode -eq 'replace') { $rep[$t.Key] = [string]$t.Value } else { $add[$t.Key] = [string]$t.Value } }
  # 1) plain text: replacements first (from the end), additions as insertions
  $ops = New-Object System.Collections.Generic.List[object]
  foreach ($k in $rep.Keys) { $r = Get-PlainRange $s $k; $ops.Add(@{ Pos = $r.Start; End = $r.End; Text = $rep[$k] }) }
  if ($add.ContainsKey('PlayerBuildParts')) {
    $q = Get-PlainRange $s 'QuestSystem'; $tagStart = $q.Start - ('QuestSystem'.Length + 2)       # position of the '?' of ?QuestSystem>
    if ($s.Substring($tagStart, 1) -ne '?') { throw 'could not find the place for PlayerBuildParts in the plain text' }
    $ops.Add(@{ Pos = $tagStart; End = $tagStart; Text = '?PlayerBuildParts>' + $add['PlayerBuildParts'] }) }
  $bed = ''; foreach ($k in 'BedRespawnPointID', 'BedRespawnLocation') { if ($add.ContainsKey($k)) { $bed += '?' + $k + '>' + $add[$k] } }
  if ($bed) { $c = Get-PlainRange $s 'PlayerCraftingQueue'; $ops.Add(@{ Pos = $c.End; End = $c.End; Text = $bed }) }
  foreach ($o in ($ops | Sort-Object { $_.Pos } -Descending)) { $s = $s.Substring(0, $o.Pos) + $o.Text + $s.Substring($o.End) }
  if ($plan.Dog) { $dr = TW-DogRange $s; if (-not $dr) { throw 'the dog record was not found in the target' }; $s = $s.Substring(0, $dr.Start) + $plan.Dog + $s.Substring($dr.End) }
  # 2) both blobs
  $prepend = @(); if ($add.ContainsKey('PlayerBuildParts')) { $prepend = @(@{ Key = 'PlayerBuildParts'; Value = $add['PlayerBuildParts'] }) }
  $append = @(); foreach ($k in 'BedRespawnPointID', 'BedRespawnLocation') { if ($add.ContainsKey($k)) { $append += @{ Key = $k; Value = $add[$k] } } }
  foreach ($name in 'PlayerSaveData', 'HostSaveData') {
    $sec = Get-BlobSection $s $name; $before = Walk-Blob $sec.Bytes; $parsed = Read-BlobEntries $sec.Bytes
    $same = TW-WriteBlob $sec.Bytes $parsed $null @() @()
    if ((Encode-B64U $same) -cne (Encode-B64U $sec.Bytes)) { throw "$name could not be rebuilt byte-for-byte - aborting" }
    $blob = TW-WriteBlob $sec.Bytes $parsed $rep $prepend $append
    $after = Walk-Blob $blob; if ($after -ne ($before + $prepend.Count + $append.Count)) { throw "$name entry count is wrong after the copy ($before -> $after)" }
    $s = $s.Substring(0, $sec.Start) + (Encode-B64U $blob) + $s.Substring($sec.End)
  }
  return @{ Bytes = $script:L1.GetBytes($s); Rep = $rep; Add = $add; Dog = $plan.Dog }
}

# checks the finished bytes against the original: only the planned values changed, every copy agrees, the order is the game's, the save still parses
function TW-Verify([string]$origPath, [byte[]]$newBytes, $built) {
  $o = Get-SaveText $origPath; $n = $script:L1.GetString($newBytes); $problems = @(); $want = @{}; foreach ($k in $built.Rep.Keys) { $want[$k] = $built.Rep[$k] }; foreach ($k in $built.Add.Keys) { $want[$k] = $built.Add[$k] }
  foreach ($k in $want.Keys) { try { if ((Get-PlainRange $n $k).Text -cne $want[$k]) { $problems += "plain-text $k is not what was planned" } } catch { $problems += "plain-text $k : $($_.Exception.Message)" } }
  foreach ($name in 'PlayerSaveData', 'HostSaveData') {
    $po = Read-BlobEntries (Get-BlobSection $o $name).Bytes; $pn = Read-BlobEntries (Get-BlobSection $n $name).Bytes
    $okeys = @($po.Entries | ForEach-Object { $_.Key }); $nkeys = @($pn.Entries | ForEach-Object { $_.Key })
    $expect = @(); if ($built.Add.ContainsKey('PlayerBuildParts')) { $expect += 'PlayerBuildParts' }; $expect += $okeys; foreach ($k in 'BedRespawnPointID', 'BedRespawnLocation') { if ($built.Add.ContainsKey($k)) { $expect += $k } }
    if (($expect -join '|') -cne ($nkeys -join '|')) { $problems += "$name entry order is not the game's"; continue }
    $oh = @{}; foreach ($e in $po.Entries) { $oh[$e.Key] = $e.Text }
    foreach ($e in $pn.Entries) { if ($want.ContainsKey($e.Key)) { if ($e.Text -cne $want[$e.Key]) { $problems += "$name $($e.Key) mismatch" } } elseif ($e.Text -cne $oh[$e.Key]) { $problems += "$name $($e.Key) changed unexpectedly" } }
    try { $nb = (Get-BlobSection $n $name).Bytes; $cnt = Walk-Blob $nb; if ([BitConverter]::ToInt32($nb, $pn.Start - 4) -ne $cnt) { $problems += "$name entry count field does not match the $cnt entries" } } catch { $problems += "$name does not parse: $($_.Exception.Message)" }
  }
  # everything outside the edited values and the two blobs must be byte-identical
  $strip = { param($t, $reps, $adds)
    $t2 = $t
    foreach ($k in $adds) { $tag = '?' + $k + '>'; $i = $t2.IndexOf($tag, [StringComparison]::Ordinal); if ($i -ge 0) { $e = $t2.IndexOf('?', $i + $tag.Length); $t2 = $t2.Substring(0, $i) + $t2.Substring($e) } }
    foreach ($k in $reps) { $r = Get-PlainRange $t2 $k; $t2 = $t2.Substring(0, $r.Start) + $t2.Substring($r.End) }
    foreach ($name in 'PlayerSaveData', 'HostSaveData') { $sec = Get-BlobSection $t2 $name; $t2 = $t2.Substring(0, $sec.Start) + $t2.Substring($sec.End) }
    $dr = TW-DogRange $t2; if ($dr) { $t2 = $t2.Substring(0, $dr.Start) + $t2.Substring($dr.End) }
    return $t2 }
  if ($built.Dog) { $dn = TW-DogRange $n; if (-not $dn -or $dn.Text -cne $built.Dog) { $problems += 'the dog record is not what was planned' } }
  elseif ((TW-DogRange $o) -and (TW-DogRange $o).Text -cne (TW-DogRange $n).Text) { $problems += 'the dog record changed unexpectedly' }
  $replKeys = @($built.Rep.Keys); $addKeys = @($built.Add.Keys)
  if ((& $strip $o $replKeys @()) -cne (& $strip $n $replKeys $addKeys)) { $problems += 'something outside the copied values changed' }
  return $problems
}

# the whole job: build, verify, back up the target, install, verify the installed file, restore the original if anything is off
function TW-Run([string]$srcPath, [string]$dstPath, [string[]]$groups, [switch]$SkipGameCheck, [switch]$Teleport) {
  if ((-not $SkipGameCheck) -and (Test-GameRunning)) { throw 'The game is running. Save and close it first.' }
  $plan = TW-Plan $srcPath $dstPath $groups; if ($plan.Fatal) { throw $plan.Fatal }
  $b = TW-Build $dstPath $plan
  $problems = TW-Verify $dstPath $b.Bytes $b; if ($problems.Count) { throw ('Verification failed, nothing was written: ' + ($problems -join '; ')) }
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'; $name = [IO.Path]::GetFileName($dstPath)
  $backup = Join-Path (Get-BackupDir) "$stamp`_BEFORE-TRANSFER_$name"
  Copy-Item -LiteralPath $dstPath -Destination $backup -Force
  if ((Get-FileHash -LiteralPath $backup).Hash -ne (Get-FileHash -LiteralPath $dstPath).Hash) { throw 'Backup did not match the original - nothing was written.' }
  $tmp = Join-Path (Get-BackupDir) "$stamp`_NEW_$name"; [IO.File]::WriteAllBytes($tmp, $b.Bytes)
  if ((Get-FileHash -LiteralPath $tmp).Hash -ne ([BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($b.Bytes)).Replace('-', ''))) { throw 'Temp file write mismatch - nothing was installed.' }
  Copy-Item -LiteralPath $tmp -Destination $dstPath -Force; [IO.File]::Delete($tmp)
  $final = TW-Verify $backup ([IO.File]::ReadAllBytes($dstPath)) $b
  if ($final.Count) { Copy-Item -LiteralPath $backup -Destination $dstPath -Force; throw ('Post-install check failed, the original was restored: ' + ($final -join '; ')) }
  [IO.File]::SetLastWriteTime($dstPath, (Get-Date))
  # a new world starts you at the crash site, far from the copied base: put you at your bed (4 m above it, you drop onto it). Its own verified, backed-up and undoable teleport.
  $moved = $null
  if ($Teleport) {
    try { $pd = Get-PlayerData $dstPath; $ds = $null; if ($pd.Bed -and $pd.Entries.ContainsKey('PlayerBuildParts')) { $ds = TW-DoorSpot $pd.Entries['PlayerBuildParts'] $pd.Bed }
      if ($ds) { [void](Move-Player $dstPath $pd $ds.X $ds.Y $ds.Z 150 'just outside your front door (after the transfer)' -SkipGameCheck:$SkipGameCheck); $moved = "you will load just outside your front door (X $([int]$ds.X), Y $([int]$ds.Y))" }
      elseif ($pd.Bed) { [void](Move-Player $dstPath $pd $pd.Bed.X $pd.Bed.Y $pd.Bed.Z 400 'your bed (after the transfer)' -SkipGameCheck:$SkipGameCheck); $moved = "no front door found: you will load above your bed (X $([int]$pd.Bed.X), Y $([int]$pd.Bed.Y))" } else { $moved = 'NOT moved: the target has no bed' } }
    catch { $moved = 'NOT moved (' + $_.Exception.Message + '); use Teleport > Your bed' }
  }
  return @{ Backup = $backup; Plan = $plan; Replaced = @($b.Rep.Keys); Added = @($b.Add.Keys); Moved = $moved }
}

# ---------- the tab in Player tools ----------
function TW-Targets { $dir = Split-Path $script:SavePath -Parent; $cur = [IO.Path]::GetFullPath($script:SavePath); @(Get-ChildItem -LiteralPath $dir -Filter '*.pfs' -File -ErrorAction SilentlyContinue | Where-Object { [IO.Path]::GetFullPath($_.FullName) -ine $cur } | Sort-Object Name | ForEach-Object { $_.FullName }) }
function TW-Groups { $ui = $script:PT; @($script:TwGroups.Keys | Where-Object { $ui.TwChk[$_].Checked }) }
function TW-Preview {
  $ui = $script:PT; $ui.TwBox.Text = ''; $t = $ui.TwTarget.Text.Trim()
  if (-not $t) { $ui.TwBox.Text = 'Pick the target world first (the NEW world you want to copy into).'; return $null }
  $g = TW-Groups; if ($g.Count -eq 0) { $ui.TwBox.Text = 'Tick at least one thing to copy.'; return $null }
  try { $plan = TW-Plan $script:SavePath $t $g } catch { $ui.TwBox.Text = 'Could not read the saves: ' + $_.Exception.Message; return $null }
  if ($plan.Fatal) { $ui.TwBox.Text = 'NOT POSSIBLE: ' + $plan.Fatal; return $null }
  $sb = New-Object Text.StringBuilder; foreach ($l in $plan.Lines) { [void]$sb.AppendLine($l); [void]$sb.AppendLine() }
  $add = @($plan.Keys | Where-Object { $_.Mode -eq 'add' }).Count; $rep = @($plan.Keys | Where-Object { $_.Mode -eq 'replace' }).Count; $skip = @($plan.Keys | Where-Object { $_.Mode -eq 'skip' }).Count
  [void]$sb.AppendLine("Technically: $add value(s) will be added, $rep replaced, $skip left alone (identical or not in the source).")
  foreach ($w in $plan.Warnings) { [void]$sb.AppendLine(); [void]$sb.AppendLine('WARNING: ' + $w) }
  $ui.TwBox.Text = $sb.ToString(); return $plan
}
function TW-Go {
  $ui = $script:PT; $plan = TW-Preview; if (-not $plan) { return }
  if (Test-GameRunning) { Msg 'The game is running. Save and close it first, then press the button again.' 'Game is running' 'OK' 'Warning' | Out-Null; return }
  if (@($plan.Keys | Where-Object { $_.Mode -ne 'skip' }).Count -eq 0) { Msg 'There is nothing to copy: everything you ticked is already identical in the target.' 'Transfer' 'OK' 'Information' | Out-Null; return }
  $t = $ui.TwTarget.Text.Trim(); $w = if ($plan.Warnings.Count) { "`n`n" + ($plan.Warnings -join "`n") } else { '' }
  $ans = Msg ("Copy what is ticked from`n  " + [IO.Path]::GetFileName($script:SavePath) + "`ninto`n  " + [IO.Path]::GetFileName($t) + "`n`nThe source is not changed. The target gets a backup first and the result is checked afterwards." + $(if ($ui.TwTele.Checked) { "`n`nAFTER THE COPY YOU ARE MOVED TO YOUR FRONT DOOR: the next time you load the target world you appear just outside your base, not at the new-world start." } else { "" }) + $(if ((TW-Groups) -contains "Tutorial") { "`n`nTHE TUTORIAL IS SKIPPED: the opening quests count as done (tools, campfire, bow, the cave, the dog) and your dog comes along. Only do this in a brand-new world." } else { "" }) + $w + "`n`nContinue?") 'Transfer to a new world' 'OKCancel' 'Question' 'Button2'
  if ($ans -ne 'OK') { return }
  try {
    $res = TW-Run $script:SavePath $t (TW-Groups) -Teleport:([bool]$ui.TwTele.Checked)
    $ui.TwBox.Text = $ui.TwBox.Text + "`r`n`r`nDONE.  Added: " + (($res.Added | Sort-Object) -join ', ') + "`r`nReplaced: " + ($res.Replaced.Count) + " value(s)." + $(if ($res.Moved) { "`r`nPosition: " + $res.Moved + "." } else { "" }) + "`r`nBackup of the target before the copy: " + $res.Backup
    PT-Status ('Copied into ' + [IO.Path]::GetFileName($t) + '. Backup: ' + [IO.Path]::GetFileName($res.Backup))
  } catch { $ui.TwBox.Text = $ui.TwBox.Text + "`r`n`r`nFAILED - the target was not changed (or was restored): " + $_.Exception.Message; PT-Status ('Transfer failed: ' + $_.Exception.Message) }
}
function TW-BuildTab($tab) {
  $ui = $script:PT
  $tw_note = "WHAT THIS DOES:`r`n  Copies what is YOURS from the world open in the tool (the source) into another, NEW world (the target) so you can start the story again without rebuilding: your base with every container, bench, furnace and the bed, the items on you, your skills and your dog.`r`nIMPORTANT - READ BEFORE YOU PRESS THE BUTTON:`r`n  -  AFTER THE COPY YOU ARE MOVED TO YOUR FRONT DOOR.  The next time you load the target world you appear just outside your base, not at the new-world start.`r`n  -  THE TUTORIAL IS SKIPPED.  The opening quests (tools, campfire, bow, the cave, getting the dog) count as done and the first village quest is started; everything after that begins from the start. Only use this on a brand-new world: it refuses a world that already has quest progress.`r`nHOW TO USE IT:`r`n  1.  Create the new world in the game, let it load, save and QUIT.  2.  Close the game.  3.  Pick that world as the target, press Preview, read it, then press 'Copy into the target world'.`r`nGOOD TO KNOW:`r`n  -  The source world is only read. The target gets a backup first (Backups folder) and the result is checked. Recipes are OFF by default (some story steps hand them out).  -  This is new and only tried on a throwaway world so far: keep the source world's backup."
  [void](New-NoteBox $tab $tw_note 'PLEASE READ FIRST - HOW THE TRANSFER WORKS' -Dock Bottom)
  $top = New-Object System.Windows.Forms.Panel; $top.Dock = 'Top'; $top.Height = 316; $tab.Controls.Add($top)
  New-Lbl $top 'Source (copy FROM)' 0 8 150 | Out-Null; $ui.TwSrc = New-Lbl $top '' 160 8 880; 
  New-Lbl $top 'Target (copy INTO)' 0 38 150 | Out-Null
  $ui.TwTarget = New-Object System.Windows.Forms.ComboBox; $ui.TwTarget.DropDownStyle = 'DropDown'; $ui.TwTarget.Location = '160,34'; $ui.TwTarget.Size = '640,24'; $top.Controls.Add($ui.TwTarget)
  $bBr = New-Btn $top 'Browse...' 810 32 100; $bRe = New-Btn $top 'Refresh list' 918 32 120
  $ui.TwChk = @{}; $y = 70
  foreach ($g in $script:TwGroups.Keys) { $c = New-Object System.Windows.Forms.CheckBox; $c.Text = $script:TwGroups[$g].Label; $c.AutoSize = $true; $c.Location = New-Object System.Drawing.Point(0, $y); $c.Checked = $script:TwGroups[$g].Default; $c.ForeColor = $script:Th.Text; $top.Controls.Add($c); $ui.TwChk[$g] = $c; $y += 26 }
  $ui.TwTele = New-Object System.Windows.Forms.CheckBox; $ui.TwTele.Text = 'After the copy, put me just outside my front door in the target world (a new world starts you at the crash site, far from your base)'; $ui.TwTele.AutoSize = $true; $ui.TwTele.Location = New-Object System.Drawing.Point(0, $y); $ui.TwTele.Checked = $true; $ui.TwTele.ForeColor = $script:Th.Text; $top.Controls.Add($ui.TwTele); $y += 30
  $bPre = New-Btn $top 'Preview' 0 ($y + 8) 150 34; $bGo = New-Btn $top 'Copy into the target world' 160 ($y + 8) 270 34; $bGo.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
  $ui.TwBox = New-Object System.Windows.Forms.TextBox; $ui.TwBox.Multiline = $true; $ui.TwBox.ReadOnly = $true; $ui.TwBox.ScrollBars = 'Vertical'; $ui.TwBox.Dock = 'Fill'; $ui.TwBox.Font = New-Object System.Drawing.Font('Consolas', 10); $tab.Controls.Add($ui.TwBox); $ui.TwBox.BringToFront()
  $fill = { $u = $script:PT; $u.TwSrc.Text = $script:SavePath; $u.TwTarget.Items.Clear(); $list = @(TW-Targets); foreach ($p in $list) { [void]$u.TwTarget.Items.Add($p) }; if (-not $u.TwTarget.Text -and $list.Count -gt 0) { $u.TwTarget.Text = $list[$list.Count - 1] } }
  & $fill
  $ui.TwFill = $fill
  $bRe.Add_Click({ & $script:PT.TwFill }); $bPre.Add_Click({ [void](TW-Preview) }); $bGo.Add_Click({ TW-Go })
  $bBr.Add_Click({ $d = New-Object System.Windows.Forms.OpenFileDialog; $d.Filter = 'Permafrost saves (*.pfs)|*.pfs'; $d.InitialDirectory = Split-Path $script:SavePath -Parent; if ($d.ShowDialog() -eq 'OK') { $script:PT.TwTarget.Text = $d.FileName } })
}
