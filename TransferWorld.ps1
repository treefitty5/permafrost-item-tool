# TransferWorld.ps1 - copies what is YOURS (your base with its containers and benches, the items on you, your skills) from one world's save into another world's save,
# so you can start the story again in a new world without rebuilding and re-collecting everything. The source save is only read; the target gets a backup first.
# Needs SaveCore.ps1, PlayerCore.ps1 (blob entries, backups) and ContainerLabels.ps1 (CL-ParseParts for the preview).
#
# How the save holds these values (see PlayerCore.ps1): every player value exists in THREE synced copies - the plain text, the PlayerSaveData blob and the HostSaveData blob.
# A brand-new character does not have three of them yet: PlayerBuildParts (the whole base, with the contents of every container and station) and BedRespawnPointID /
# BedRespawnLocation. They are ADDED where the game itself puts them: PlayerBuildParts is the FIRST entry of both blobs and sits in the plain text just before ?QuestSystem>;
# the two bed entries are the LAST entries of both blobs and sit in the plain text right after ?PlayerCraftingQueue>. Everything else is replaced in place.
# The story (QuestSystem), vitals, character look, effects and every world object are never touched. Learned recipes are copied only when you tick them.

$script:TwSkillKeys = @('CharacterSkillsComponent_SkillCount') + @(0..15 | ForEach-Object { "CharacterSkillsComponent_Skill_$_" }) + @('PointsAmount')
$script:TwGroups = [ordered]@{
  Base    = @{ Label = 'Your base: every building part with the contents of your barrels, chests, bookshelves, benches and furnaces, and your bed'; Keys = @('PlayerBuildParts', 'BedRespawnPointID', 'BedRespawnLocation'); Default = $true }
  Items   = @{ Label = 'The items on you: hotbar, worn clothes and backpack with everything in it, special items'; Keys = @('BaseInvSlots', 'Equipment', 'SpecialItems'); Default = $true }
  Skills  = @{ Label = 'Your 16 skills (levels and experience) and unspent skill points'; Keys = $script:TwSkillKeys; Default = $true }
  Recipes = @{ Label = 'The recipes you have learned (OFF by default: a few story steps unlock recipes, so copying them can skip or confuse parts of the story)'; Keys = @('PlayerKnowledge_Knowledge'); Default = $false }
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
  foreach ($g in $groups) {
    if (-not $script:TwGroups.Contains($g)) { continue }
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
  $plan.Lines.Add('Never touched: the story and quests, vitals, character look, status effects and every object of the world.')
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
  return @{ Bytes = $script:L1.GetBytes($s); Rep = $rep; Add = $add }
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
    return $t2 }
  $replKeys = @($built.Rep.Keys); $addKeys = @($built.Add.Keys)
  if ((& $strip $o $replKeys @()) -cne (& $strip $n $replKeys $addKeys)) { $problems += 'something outside the copied values changed' }
  return $problems
}

# the whole job: build, verify, back up the target, install, verify the installed file, restore the original if anything is off
function TW-Run([string]$srcPath, [string]$dstPath, [string[]]$groups, [switch]$SkipGameCheck) {
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
  return @{ Backup = $backup; Plan = $plan; Replaced = @($b.Rep.Keys); Added = @($b.Add.Keys) }
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
  $ans = Msg ("Copy what is ticked from`n  " + [IO.Path]::GetFileName($script:SavePath) + "`ninto`n  " + [IO.Path]::GetFileName($t) + "`n`nThe source is not changed. The target gets a backup first and the result is checked afterwards." + $w + "`n`nContinue?") 'Transfer to a new world' 'OKCancel' 'Question' 'Button2'
  if ($ans -ne 'OK') { return }
  try {
    $res = TW-Run $script:SavePath $t (TW-Groups)
    $ui.TwBox.Text = $ui.TwBox.Text + "`r`n`r`nDONE.  Added: " + (($res.Added | Sort-Object) -join ', ') + "`r`nReplaced: " + ($res.Replaced.Count) + " value(s).`r`nBackup of the target before the copy: " + $res.Backup
    PT-Status ('Copied into ' + [IO.Path]::GetFileName($t) + '. Backup: ' + [IO.Path]::GetFileName($res.Backup))
  } catch { $ui.TwBox.Text = $ui.TwBox.Text + "`r`n`r`nFAILED - the target was not changed (or was restored): " + $_.Exception.Message; PT-Status ('Transfer failed: ' + $_.Exception.Message) }
}
function TW-BuildTab($tab) {
  $ui = $script:PT
  $tw_note = "WHAT THIS DOES:`r`n  Copies what is YOURS from the world you have open in the tool (the source) into another world (the target), so you can start the story again without rebuilding and re-collecting: your whole base with every container, bench, furnace and bed, the items on you, and your skills.`r`nHOW TO USE IT:`r`n  1.  Create the new world in the game, let it load, save and QUIT.  2.  Close the game.  3.  Pick that new world as the target, press Preview, read it, then press 'Copy into the target world'.`r`nGOOD TO KNOW:`r`n  -  The source world is only read, never changed.  The target gets a backup first (Backups folder) and the result is checked.  The story and quests of the target are never touched.`r`n  -  Recipes are OFF by default: some story steps hand out recipes, so copying them can skip parts of the story.  -  This was built from how the save is laid out; the game itself has to accept the copied base, so make sure the source world is safely backed up and try the new world once before you rely on it."
  [void](New-NoteBox $tab $tw_note 'PLEASE READ FIRST - HOW THE TRANSFER WORKS' -Dock Bottom)
  $top = New-Object System.Windows.Forms.Panel; $top.Dock = 'Top'; $top.Height = 232; $tab.Controls.Add($top)
  New-Lbl $top 'Source (copy FROM)' 0 8 150 | Out-Null; $ui.TwSrc = New-Lbl $top '' 160 8 880; 
  New-Lbl $top 'Target (copy INTO)' 0 38 150 | Out-Null
  $ui.TwTarget = New-Object System.Windows.Forms.ComboBox; $ui.TwTarget.DropDownStyle = 'DropDown'; $ui.TwTarget.Location = '160,34'; $ui.TwTarget.Size = '640,24'; $top.Controls.Add($ui.TwTarget)
  $bBr = New-Btn $top 'Browse...' 810 32 100; $bRe = New-Btn $top 'Refresh list' 918 32 120
  $ui.TwChk = @{}; $y = 70
  foreach ($g in $script:TwGroups.Keys) { $c = New-Object System.Windows.Forms.CheckBox; $c.Text = $script:TwGroups[$g].Label; $c.AutoSize = $true; $c.Location = New-Object System.Drawing.Point(0, $y); $c.Checked = $script:TwGroups[$g].Default; $c.ForeColor = $script:Th.Text; $top.Controls.Add($c); $ui.TwChk[$g] = $c; $y += 26 }
  $bPre = New-Btn $top 'Preview' 0 ($y + 8) 150 34; $bGo = New-Btn $top 'Copy into the target world' 160 ($y + 8) 270 34; $bGo.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
  $ui.TwBox = New-Object System.Windows.Forms.TextBox; $ui.TwBox.Multiline = $true; $ui.TwBox.ReadOnly = $true; $ui.TwBox.ScrollBars = 'Vertical'; $ui.TwBox.Dock = 'Fill'; $ui.TwBox.Font = New-Object System.Drawing.Font('Consolas', 10); $tab.Controls.Add($ui.TwBox); $ui.TwBox.BringToFront()
  $fill = { $u = $script:PT; $u.TwSrc.Text = $script:SavePath; $u.TwTarget.Items.Clear(); $list = @(TW-Targets); foreach ($p in $list) { [void]$u.TwTarget.Items.Add($p) }; if (-not $u.TwTarget.Text -and $list.Count -gt 0) { $u.TwTarget.Text = $list[$list.Count - 1] } }
  & $fill
  $ui.TwFill = $fill
  $bRe.Add_Click({ & $script:PT.TwFill }); $bPre.Add_Click({ [void](TW-Preview) }); $bGo.Add_Click({ TW-Go })
  $bBr.Add_Click({ $d = New-Object System.Windows.Forms.OpenFileDialog; $d.Filter = 'Permafrost saves (*.pfs)|*.pfs'; $d.InitialDirectory = Split-Path $script:SavePath -Parent; if ($d.ShowDialog() -eq 'OK') { $script:PT.TwTarget.Text = $d.FileName } })
}
