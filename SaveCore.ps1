# SaveCore.ps1 - safe inventory editing for Permafrost .pfs saves (single-player worlds)
# The player's inventory lives in THREE synchronized copies inside a save: a plain-text object, a PlayerSaveData blob
# and a HostSaveData blob. Every edit here is applied to all three, then the result is re-read and verified.

$script:L1 = [Text.Encoding]::Latin1
$script:HotbarMaxSlot = 7
$script:DefaultBackpackMaxSlot = 24     # slots 0..24 are known valid for the Utility backpack

# ---------- helpers ----------
function Test-GameRunning { [bool](Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.ProcessName -match '^Permafrost' }) }

function Decode-B64U([string]$s) { $t = $s.Replace('-','+').Replace('_','/'); while ($t.Length % 4) { $t += '=' }; [Convert]::FromBase64String($t) }
function Encode-B64U([byte[]]$b) { [Convert]::ToBase64String($b).Replace('+','-').Replace('/','_') }

function Find-Bytes([byte[]]$hay, [byte[]]$needle, [int]$from = 0) {
  for ($i = $from; $i -le $hay.Length - $needle.Length; $i++) {
    if ($hay[$i] -ne $needle[0]) { continue }
    $ok = $true; for ($j = 1; $j -lt $needle.Length; $j++) { if ($hay[$i+$j] -ne $needle[$j]) { $ok = $false; break } }
    if ($ok) { return $i }
  }
  return -1
}

# where the [int32 keylen][key\0][int32 vallen][val\0]... entries of a PlayerSaveData / HostSaveData blob start.
# HostSaveData: int32 entry count, then the entries (start 4). PlayerSaveData: int32 1, int32 len + UUID text, int32 entry count, then the entries.
# (Not found through the 'PlayerBuildParts' key: a brand-new character has not built anything, so that entry does not exist yet.)
function Test-EntryStart([byte[]]$b, [int]$p) {
  if ($p + 8 -gt $b.Length) { return $false }; $kl = [BitConverter]::ToInt32($b, $p); if ($kl -lt 2 -or $kl -gt 80 -or $p + 4 + $kl + 4 -gt $b.Length) { return $false }
  if ($b[$p + 4 + $kl - 1] -ne 0) { return $false }
  for ($k = 0; $k -lt $kl - 1; $k++) { $c = $b[$p + 4 + $k]; if (-not (($c -ge 48 -and $c -le 57) -or ($c -ge 65 -and $c -le 90) -or ($c -ge 97 -and $c -le 122) -or $c -eq 95)) { return $false } }
  return $true }
function Get-BlobEntryStart([byte[]]$blob) {
  if ($blob.Length -lt 16) { throw 'blob layout not recognised' }
  $hl = [BitConverter]::ToInt32($blob, 4)
  if ([BitConverter]::ToInt32($blob, 0) -eq 1 -and $hl -ge 1 -and $hl -le 64 -and (Test-EntryStart $blob (8 + $hl + 4))) { $start = 8 + $hl + 4 }
  elseif (Test-EntryStart $blob 4) { $start = 4 }
  else { throw 'blob layout not recognised' }
  $i = Find-Bytes $blob ($script:L1.GetBytes("PlayerBuildParts`0")); if ($i -ge 4 -and ($i - 4) -ne $start) { throw 'blob layout not recognised' }
  return $start }

# walk [int32 keylen][key\0][int32 vallen][val\0]... ; returns entry count or throws
function Walk-Blob([byte[]]$blob) {
  $pos = Get-BlobEntryStart $blob; $n = 0
  while ($pos -lt $blob.Length) {
    $kl = [BitConverter]::ToInt32($blob, $pos); if ($kl -lt 2 -or $kl -gt 80) { throw "bad key length $kl at $pos" }
    if ($blob[$pos + 4 + $kl - 1] -ne 0) { throw "key not NUL-terminated at $pos" }
    $vl = [BitConverter]::ToInt32($blob, $pos + 4 + $kl); $end = $pos + 4 + $kl + 4 + $vl
    if ($vl -lt 0 -or $end -gt $blob.Length) { throw "bad value length $vl at $pos" }
    if ($vl -gt 0 -and $blob[$end - 1] -ne 0) { throw "value not NUL-terminated at $pos" }
    $pos = $end; $n++
  }
  if ($pos -ne $blob.Length) { throw 'walk did not land on blob end' }
  return $n
}

function Get-BlobValue([byte[]]$blob, [string]$key) {
  $kb = $script:L1.GetBytes("$key`0"); $i = Find-Bytes $blob $kb
  if ($i -lt 4 -or [BitConverter]::ToInt32($blob, $i - 4) -ne $kb.Length) { throw "key '$key' not found as expected" }
  if ((Find-Bytes $blob $kb ($i + 1)) -ge 0) { throw "key '$key' appears more than once" }
  $lenPos = $i + $kb.Length; $vl = [BitConverter]::ToInt32($blob, $lenPos)
  return @{ LenPos = $lenPos; ValStart = $lenPos + 4; ValLen = $vl; Text = $script:L1.GetString($blob, $lenPos + 4, [math]::Max(0, $vl - 1)) }
}
function Set-BlobValue([byte[]]$blob, [string]$key, [string]$newText) {
  $v = Get-BlobValue $blob $key; $nb = $script:L1.GetBytes($newText + "`0")
  $ms = New-Object IO.MemoryStream
  $ms.Write($blob, 0, $v.LenPos); $ms.Write([BitConverter]::GetBytes([int]$nb.Length), 0, 4); $ms.Write($nb, 0, $nb.Length)
  $tail = $v.ValStart + $v.ValLen; $ms.Write($blob, $tail, $blob.Length - $tail)
  return $ms.ToArray()
}

function Get-BlobSection([string]$s, [string]$name) {
  $tag = "$name###>"; $ti = $s.IndexOf($tag, [StringComparison]::Ordinal)
  if ($ti -lt 0 -or $s.IndexOf($tag, $ti + 1, [StringComparison]::Ordinal) -ge 0) { throw "$tag not found exactly once" }
  $bs = $ti + $tag.Length; $be = $s.IndexOf('?', $bs, [StringComparison]::Ordinal)
  return @{ Start = $bs; End = $be; Bytes = (Decode-B64U $s.Substring($bs, $be - $bs)) }
}

function Get-PlainRange([string]$s, [string]$key) {
  # plain text searches (a regex over the whole 5 MB save cost about 0.2 s per call)
  $tag = '?' + $key + '>'; $first = $s.IndexOf($tag, [StringComparison]::Ordinal); $count = 0; $at = $first
  while ($at -ge 0) { $count++; $at = $s.IndexOf($tag, $at + 1, [StringComparison]::Ordinal) }
  if ($count -ne 1) { throw "plain-text key '$key' found $count times (expected 1)" }
  $a = $first + $key.Length + 2; $b = $s.IndexOf('?', $a)
  return @{ Start = $a; End = $b; Text = $s.Substring($a, $b - $a) }
}

# ---------- inventory model ----------
function Parse-Slots([string]$text) {
  $list = New-Object System.Collections.Generic.List[object]
  foreach ($it in ($text -split '(?=@\d+=)' | Where-Object { $_ })) {
    $m = [regex]::Match($it, '^@(\d+)=([^&@#>]+)(.*)$'); if (-not $m.Success) { throw "cannot parse inventory entry '$it'" }
    $list.Add([pscustomobject]@{ Slot = [int]$m.Groups[1].Value; Id = $m.Groups[2].Value; Rest = $m.Groups[3].Value })
  }
  return , $list
}
function Format-Slots($list) { (($list | Sort-Object Slot | ForEach-Object { "@$($_.Slot)=$($_.Id)$($_.Rest)" }) -join '') }

# Equipment value: worn items "#slot=Id&..>" ; the backpack entry is followed by its contents "@slot=Id&.." up to the next '#'
function Parse-Equipment([string]$e) {
  $m = [regex]::Matches($e, '(#\d+=([A-Za-z0-9_]*Backpack)&[^>]*>)((?:@\d+=[^@#>]*)*)')
  if ($m.Count -eq 0) { return $null }
  if ($m.Count -gt 1) { throw 'more than one backpack found in Equipment' }
  return @{ Match = $m[0]; Name = $m[0].Groups[2].Value; Contents = (Parse-Slots $m[0].Groups[3].Value); ContentsIndex = $m[0].Groups[3].Index; ContentsLength = $m[0].Groups[3].Length }
}

# Backpack capacity. The save does not store it, but the game's item data does (ItemConfig_Clothing.ContainerDimensions, exported to items.json
# as containerSlots; checked: Utility 25 and Scavenger 35 equal what you had set by hand). Order used:
#   0. a size set with "Apply in game" (backpack-tweaks.json; counts only while the BackpackSlots in-game mod is installed and on, see BackpackTweaks.ps1)
#   1. the game data (items.json containerSlots)
#   2. a size you set yourself in the window, remembered per backpack in backpacks.json (only for a backpack the data does not cover)
#   3. otherwise the highest slot already in use (at least 10 slots) - a safe floor, never an over-estimate
function Get-BackpackGameSlots([string]$name) {
  if (-not $script:BpData) { $script:BpData = @{}; $p = Join-Path $PSScriptRoot 'items.json'
    if (Test-Path -LiteralPath $p) { try { foreach ($i in (Get-Content $p -Raw | ConvertFrom-Json)) { if ($i.containerSlots) { $script:BpData[[string]$i.id] = [int]$i.containerSlots } } } catch { } } }
  if ($script:BpData.ContainsKey($name)) { return $script:BpData[$name] }; return 0
}
function Get-BackpackSettings {
  $p = Join-Path $PSScriptRoot 'backpacks.json'; $h = @{}
  if (Test-Path $p) { try { $o = Get-Content $p -Raw | ConvertFrom-Json; foreach ($pr in $o.PSObject.Properties) { $h[$pr.Name] = [int]$pr.Value } } catch { } }
  return $h
}
function Set-BackpackSlots([string]$name, [int]$slots) {
  if ($slots -lt 5 -or $slots -gt 200) { throw 'Backpack slots must be between 5 and 200.' }
  $h = Get-BackpackSettings; $h[$name] = $slots
  ($h | ConvertTo-Json) | Set-Content (Join-Path $PSScriptRoot 'backpacks.json') -Encoding utf8
}
function Get-BackpackTweakSlots([string]$name) {
  if (-not (Get-Command Get-BackpackTweaks -ErrorAction SilentlyContinue)) { return 0 }
  $h = Get-BackpackTweaks; if ($h.ContainsKey($name) -and (BT-ModActive)) { return [int]$h[$name] }; return 0
}
function Get-BackpackMaxSlot($bp) {
  $tw = Get-BackpackTweakSlots $bp.Name; if ($tw -gt 0) { return $tw - 1 }
  $g = Get-BackpackGameSlots $bp.Name; if ($g -gt 0) { return $g - 1 }
  $h = Get-BackpackSettings; if ($h.ContainsKey($bp.Name)) { return [int]$h[$bp.Name] - 1 }
  if ($bp.Name -eq 'UtilityBackpack') { return $script:DefaultBackpackMaxSlot }
  $used = ($bp.Contents | Measure-Object Slot -Maximum).Maximum; if ($null -eq $used) { $used = 0 }
  return [math]::Max(9, [int]$used)
}
function Get-BackpackSource($bp) {
  if ((Get-BackpackTweakSlots $bp.Name) -gt 0) { return "your size; the game's own is $(Get-BackpackGameSlots $bp.Name)" }
  if ((Get-BackpackGameSlots $bp.Name) -gt 0) { return 'game data' }
  $h = Get-BackpackSettings; if ($h.ContainsKey($bp.Name)) { return 'your setting' }
  if ($bp.Name -eq 'UtilityBackpack') { return 'known size' }
  return 'estimated from slots in use - set the real number if it is bigger'
}

function Format-Entry($item, [int]$slot, [int]$count) {
  $s = "@$slot=$($item.id)&$count"
  if ($item.fieldsUsed -ge 2) { $s += '&' + ([double]$item.condition).ToString('0.0###', [Globalization.CultureInfo]::InvariantCulture) }
  if ($item.fieldsUsed -ge 3) { $s += '&' + [int]$item.loaded }
  return $s
}

# Plan the new slot strings. $requests: objects with item (catalog entry incl. condition/loaded), count, stack, target ('Backpack'|'Hotbar')
function Build-Plan([string]$equipText, [string]$hotText, $requests) {
  $eq = Parse-Equipment $equipText; $hot = Parse-Slots $hotText
  $bpList = $null; $bpMax = 0
  if ($eq) { $bpList = New-Object System.Collections.Generic.List[object]; $eq.Contents | ForEach-Object { $bpList.Add($_) }; $bpMax = Get-BackpackMaxSlot $eq }
  $hotList = New-Object System.Collections.Generic.List[object]; $hot | ForEach-Object { $hotList.Add($_) }
  $added = New-Object System.Collections.Generic.List[string]
  foreach ($r in $requests) {
    $list = $null; $max = 0
    if ($r.target -eq 'Hotbar') { $list = $hotList; $max = $script:HotbarMaxSlot } else { if (-not $eq) { throw 'No backpack is equipped - use the Hotbar target, or equip a backpack in the game first.' }; $list = $bpList; $max = $bpMax }
    $remaining = [int]$r.count; $stack = [math]::Max(1, [int]$r.stack)
    while ($remaining -gt 0) {
      $used = @{}; foreach ($x in $list) { $used[$x.Slot] = $true }
      $free = $null; for ($s = 0; $s -le $max; $s++) { if (-not $used.ContainsKey($s)) { $free = $s; break } }
      if ($null -eq $free) { throw "Not enough free $($r.target.ToLower()) slots for $($r.item.id) (needs $([math]::Ceiling($remaining / $stack)) more). Free some space in the game first$(if ($r.target -eq 'Backpack') { ', add less, use the Hotbar target, or make the backpack bigger with the Backpack slots box (top right, Apply in game)' } else { '' })." }
      $n = [math]::Min($stack, $remaining)
      $entry = Format-Entry $r.item $free $n
      $m = [regex]::Match($entry, '^@(\d+)=([^&]+)(.*)$')
      $list.Add([pscustomobject]@{ Slot = $free; Id = $m.Groups[2].Value; Rest = $m.Groups[3].Value })
      $added.Add("$($r.target) slot $free : $($r.item.id) x$n")
      $remaining -= $n
    }
  }
  $newEquip = $equipText
  if ($eq -and ($requests | Where-Object { $_.target -ne 'Hotbar' })) {
    $newEquip = $equipText.Substring(0, $eq.ContentsIndex) + (Format-Slots $bpList) + $equipText.Substring($eq.ContentsIndex + $eq.ContentsLength)
  }
  $newHot = $hotText
  if ($requests | Where-Object { $_.target -eq 'Hotbar' }) { $newHot = Format-Slots $hotList }
  return @{ Equip = $newEquip; Hot = $newHot; Added = $added }
}

# ---------- reading a save ----------
function Read-Save([string]$path) {
  $s = $script:L1.GetString([IO.File]::ReadAllBytes($path))
  $eq = Get-PlainRange $s 'Equipment'; $hot = Get-PlainRange $s 'BaseInvSlots'
  return @{ Text = $s; Equip = $eq.Text; Hot = $hot.Text
            Playtime = (Get-HeaderValue $s 'TotalPlayTime>' '[\d\.]+'); Slot = (Get-HeaderValue $s 'SlotName>' '[^\?]+'); Updated = (Get-HeaderValue $s 'LastUpdatedAt>' '[^\?]+') }
}
# the value after the first "tag" in the save: found with a plain text search, then matched in a short piece (a regex over the whole save cost about 0.2 s each); falls back to the full regex
function Get-HeaderValue([string]$s, [string]$tag, [string]$valueRx) {
  $i = $s.IndexOf($tag, [StringComparison]::Ordinal)
  if ($i -ge 0) { $piece = $s.Substring($i, [math]::Min(120, $s.Length - $i)); $m = [regex]::Match($piece, [regex]::Escape($tag) + '(' + $valueRx + ')'); if ($m.Success) { return $m.Groups[1].Value } }
  return [regex]::Match($s, [regex]::Escape($tag) + '(' + $valueRx + ')').Groups[1].Value
}

# turns the stored text "&5&0.0" / "&1&345.0&8" into something readable
function Format-Detail([string]$rest) {
  $p = @($rest.TrimStart('&') -split '&' | Where-Object { $_ -ne '' })
  if ($p.Count -eq 0) { return '' }
  $s = "x$($p[0])"; $inv = [Globalization.CultureInfo]::InvariantCulture
  if ($p.Count -ge 2) { $v = 0.0; if ([double]::TryParse($p[1], [Globalization.NumberStyles]::Float, $inv, [ref]$v) -and $v -gt 0) { $s += ', condition ' + $v.ToString('0.#', $inv) } }
  if ($p.Count -ge 3) { $s += ", $($p[2]) loaded" }
  return $s
}
function Get-InventoryView([string]$path) {
  $sv = Read-Save $path; $rows = @()
  foreach ($h in (Parse-Slots $sv.Hot)) { $rows += [pscustomobject]@{ Where = 'Hotbar'; Slot = $h.Slot; Item = $h.Id; Detail = (Format-Detail $h.Rest) } }
  $eq = Parse-Equipment $sv.Equip
  if ($eq) { foreach ($b in ($eq.Contents | Sort-Object Slot)) { $rows += [pscustomobject]@{ Where = "Backpack ($($eq.Name))"; Slot = $b.Slot; Item = $b.Id; Detail = (Format-Detail $b.Rest) } } }
  return $rows
}

# ---------- writing: apply to all three copies, verify, return the new file bytes ----------
function Build-EditedSave([string]$srcPath, $requests) {
  $s = $script:L1.GetString([IO.File]::ReadAllBytes($srcPath))
  $eqR = Get-PlainRange $s 'Equipment'; $hotR = Get-PlainRange $s 'BaseInvSlots'
  $plan = Build-Plan $eqR.Text $hotR.Text $requests
  $changeEquip = ($plan.Equip -cne $eqR.Text); $changeHot = ($plan.Hot -cne $hotR.Text)
  if (-not ($changeEquip -or $changeHot)) { throw 'nothing to change' }
  if (($plan.Equip + $plan.Hot).Contains('?')) { throw 'refusing: new value would contain a field separator' }

  # 1) plain-text object (edit later key first so earlier offsets stay valid)
  $edits = @(); if ($changeEquip) { $edits += @{ R = $eqR; T = $plan.Equip } }; if ($changeHot) { $edits += @{ R = $hotR; T = $plan.Hot } }
  foreach ($e in ($edits | Sort-Object { $_.R.Start } -Descending)) { $s = $s.Substring(0, $e.R.Start) + $e.T + $s.Substring($e.R.End) }

  # 2) both binary blobs
  foreach ($name in 'PlayerSaveData', 'HostSaveData') {
    $sec = Get-BlobSection $s $name; $before = Walk-Blob $sec.Bytes; $blob = $sec.Bytes
    if ($changeEquip) { $cur = (Get-BlobValue $blob 'Equipment').Text; if ($cur -cne $eqR.Text) { throw "$name Equipment differs from the plain-text copy - save is inconsistent, aborting" }; $blob = Set-BlobValue $blob 'Equipment' $plan.Equip }
    if ($changeHot)   { $cur = (Get-BlobValue $blob 'BaseInvSlots').Text; if ($cur -cne $hotR.Text) { throw "$name BaseInvSlots differs from the plain-text copy - save is inconsistent, aborting" }; $blob = Set-BlobValue $blob 'BaseInvSlots' $plan.Hot }
    $after = Walk-Blob $blob; if ($before -ne $after) { throw "$name entry count changed ($before -> $after)" }
    $s = $s.Substring(0, $sec.Start) + (Encode-B64U $blob) + $s.Substring($sec.End)
  }
  return @{ Bytes = $script:L1.GetBytes($s); Plan = $plan; ChangedEquip = $changeEquip; ChangedHot = $changeHot }
}

# independent check of a candidate file against the original
function Test-EditedSave([string]$origPath, [byte[]]$newBytes, $plan, [bool]$chEq, [bool]$chHot) {
  $o = $script:L1.GetString([IO.File]::ReadAllBytes($origPath)); $n = $script:L1.GetString($newBytes); $problems = @()
  $oe = (Get-PlainRange $o 'Equipment').Text; $oh = (Get-PlainRange $o 'BaseInvSlots').Text
  $ne = (Get-PlainRange $n 'Equipment').Text; $nh = (Get-PlainRange $n 'BaseInvSlots').Text
  if ($ne -cne $plan.Equip) { $problems += 'plain-text Equipment is not what was planned' }
  if ($nh -cne $plan.Hot) { $problems += 'plain-text hotbar is not what was planned' }
  foreach ($name in 'PlayerSaveData', 'HostSaveData') {
    $b = (Get-BlobSection $n $name).Bytes; [void](Walk-Blob $b)
    if ((Get-BlobValue $b 'Equipment').Text -cne $plan.Equip) { $problems += "$name Equipment mismatch" }
    if ((Get-BlobValue $b 'BaseInvSlots').Text -cne $plan.Hot) { $problems += "$name hotbar mismatch" }
  }
  # everything else must be untouched: remove the three edited spans and compare the remainders
  foreach ($k in 'LevelStreamingData###>') { $a = $o.IndexOf($k); $b2 = $n.IndexOf($k); $ae = $o.IndexOf('PlayerSaveData###>'); $be = $n.IndexOf('PlayerSaveData###>'); if ($o.Substring($a, $ae - $a) -cne $n.Substring($b2, $be - $b2)) { $problems += 'world data changed' } }
  if ($o.Substring(0, $o.IndexOf('?[LevelStreamingData###>')) -cne $n.Substring(0, $n.IndexOf('?[LevelStreamingData###>'))) { $problems += 'save header changed' }
  $oq = $o.Substring($o.IndexOf('?QuestSystem>'), $o.IndexOf('?PawnLocation>') - $o.IndexOf('?QuestSystem>')); $nq = $n.Substring($n.IndexOf('?QuestSystem>'), $n.IndexOf('?PawnLocation>') - $n.IndexOf('?QuestSystem>'))
  if ($oq -cne $nq) { $problems += 'quest data changed' }
  return $problems
}

# ---------- backup / install / restore ----------
function Get-BackupDir { if ($script:BackupDirOverride) { return $script:BackupDirOverride }; $d = Join-Path $PSScriptRoot 'Backups'; if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d | Out-Null }; return $d }

# The first time the tool sees a world that has NO backup yet, copy it into Backups as a "starting snapshot" (<stamp>_BASELINE_<world>.pfs).
# World reset restores destroyed ores and picked-up items from earlier copies of the world, so a snapshot taken before the player starts
# destroying things is what makes that possible for a brand-new single world. Read-only on the save; skipped while the game runs (the file may be
# half-written) and tried again at the next reload. Returns the snapshot path, or $null when nothing was made.
function Ensure-BaselineBackup([string]$savePath, [switch]$SkipGameCheck) {
  if (-not $script:BaselineChecked) { $script:BaselineChecked = @{} }
  if (-not $savePath -or $script:BaselineChecked.ContainsKey($savePath) -or -not (Test-Path -LiteralPath $savePath)) { return $null }
  if (-not $SkipGameCheck -and (Test-GameRunning)) { return $null }          # not cached: try again later
  $script:BaselineChecked[$savePath] = $true
  $leaf = [IO.Path]::GetFileName($savePath); $dir = Get-BackupDir
  if (@(Get-ChildItem -LiteralPath $dir -Filter "*_$leaf" -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch '_NEW_' }).Count -gt 0) { return $null }
  $dest = Join-Path $dir ((Get-Date -Format 'yyyyMMdd-HHmmss') + "_BASELINE_$leaf")
  Copy-Item -LiteralPath $savePath -Destination $dest -Force
  if ((Get-Item -LiteralPath $dest).Length -ne (Get-Item -LiteralPath $savePath).Length -or (Get-FileHash -LiteralPath $dest).Hash -ne (Get-FileHash -LiteralPath $savePath).Hash) { Remove-Item -LiteralPath $dest -Force -ErrorAction SilentlyContinue; $script:BaselineChecked.Remove($savePath); return $null }
  return $dest
}

function Install-Items([string]$savePath, $requests, [switch]$SkipGameCheck) {
  if ((-not $SkipGameCheck) -and (Test-GameRunning)) { throw 'The game is running. Save and close it first.' }
  if (-not (Test-Path $savePath)) { throw "Save not found: $savePath" }
  $r = Build-EditedSave $savePath $requests
  $problems = Test-EditedSave $savePath $r.Bytes $r.Plan $r.ChangedEquip $r.ChangedHot
  if ($problems.Count) { throw ('Verification failed, nothing was written: ' + ($problems -join '; ')) }
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'; $name = [IO.Path]::GetFileName($savePath)
  $backup = Join-Path (Get-BackupDir) "$stamp`_$name"
  Copy-Item $savePath $backup -Force
  if ((Get-FileHash $backup).Hash -ne (Get-FileHash $savePath).Hash) { throw 'Backup did not match the original - nothing was written.' }
  $tmp = Join-Path (Get-BackupDir) "$stamp`_NEW_$name"; [IO.File]::WriteAllBytes($tmp, $r.Bytes)
  if ((Get-FileHash $tmp).Hash -ne ([BitConverter]::ToString([Security.Cryptography.SHA256]::Create().ComputeHash($r.Bytes)).Replace('-',''))) { throw 'Temp file write mismatch - nothing was installed.' }
  Copy-Item $tmp $savePath -Force; Remove-Item $tmp -Force
  # re-read the installed file as a final check
  $final = Test-EditedSave $backup ([IO.File]::ReadAllBytes($savePath)) $r.Plan $r.ChangedEquip $r.ChangedHot
  if ($final.Count) { Copy-Item $backup $savePath -Force; throw ('Post-install check failed, original restored: ' + ($final -join '; ')) }
  [IO.File]::SetLastWriteTime($savePath, (Get-Date))    # fresh timestamp so Steam Cloud sees this file as the newest
  return @{ Backup = $backup; Added = $r.Plan.Added }
}

function Restore-Backup([string]$savePath, [string]$backupFile, [switch]$SkipGameCheck) {
  if ((-not $SkipGameCheck) -and (Test-GameRunning)) { throw 'The game is running. Close it first.' }
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'; $pre = Join-Path (Get-BackupDir) "$stamp`_BEFORE-RESTORE_$([IO.Path]::GetFileName($savePath))"
  Copy-Item $savePath $pre -Force; Copy-Item $backupFile $savePath -Force
  if ((Get-FileHash $savePath).Hash -ne (Get-FileHash $backupFile).Hash) { throw 'Restore verification failed.' }
  [IO.File]::SetLastWriteTime($savePath, (Get-Date))    # an old backup keeps its old timestamp otherwise, and Steam could treat it as outdated
  return $pre
}

# ---------- catalog ----------
function Get-Catalog {
  $p = Join-Path $PSScriptRoot 'items.json'; if (-not (Test-Path $p)) { throw "items.json not found next to the tool. Run Build-Catalog.ps1." }
  $raw = Get-Content $p -Raw | ConvertFrom-Json
  foreach ($i in $raw) {
    $cond = if ($null -ne $i.defaultCondition) { [double]$i.defaultCondition } else { 0.0 }
    $i | Add-Member -Force condition $cond; $i | Add-Member -Force loaded 0
    if (-not $i.display) { $i | Add-Member -Force display ((($i.id -creplace '([a-z0-9])([A-Z])', '$1 $2') -replace '_', ' ').Trim()) }   # the in-game name from the game data (Build-JsonSpecs) wins; a name made from the id is only the fallback
  }
  return $raw
}

# ---------- preview + warnings (no writing) ----------
# Returns slot assignments (or throws the same "not enough space" error the real apply would) and a list of warnings.
# Warning levels: 'warn' = needs an explicit extra confirmation; 'info' = just worth knowing.
function Get-Preview([string]$savePath, $requests) {
  $s = Read-Save $savePath
  $plan = Build-Plan $s.Equip $s.Hot $requests
  $w = New-Object System.Collections.Generic.List[object]
  $seen = @{}
  foreach ($r in $requests) {
    $i = $r.item; $id = $i.id
    if ($i.category -eq 'Weapons' -and $i.usesAmmo -and @($i.usesAmmo).Count) { foreach ($am in @($i.usesAmmo)) { $have = Get-CarriedCount $s $am; $queued = 0; foreach ($q in $requests) { if ($q.item.id -eq $am) { $queued += [int]$q.count } }; $w.Add(@{ Level = 'info'; Text = "$id uses $am. You carry $have now" + $(if ($queued) { " and are adding $queued in this batch." } else { " and are not adding any in this batch." }) }) } }
    if ($seen.ContainsKey($id)) { $w.Add(@{ Level = 'info'; Text = "$id is queued more than once; each entry uses its own slots." }) }; $seen[$id] = 1
    if ($i.confidence -eq 'guess') { $w.Add(@{ Level = 'warn'; Text = "$id : the game files listed several possible names and this is a BEST GUESS. If it is wrong the game will silently ignore it (nothing breaks, the item just will not appear)." }) }
    elseif ($i.confidence -ne 'verified') { $w.Add(@{ Level = 'info'; Text = "$id : the name was read from the game's files but has not been confirmed in a real save, so it is untested. If the game does not recognise it, it just will not appear." }) }
    if ($r.stack -gt $i.stackSize) {
      if ($i.stackSource -in 'game data', 'confirmed in game') { $w.Add(@{ Level = 'warn'; Text = "$id : $($r.stack) per slot is ABOVE this item's stack limit of $($i.stackSize) (read from the game's own data). The game may cap it, split it, or misbehave." }) }
      else { $w.Add(@{ Level = 'warn'; Text = "$id : you raised the stack size to $($r.stack); the largest stack seen in your saves is $($i.stackSize) (the game's real limit for this item could not be read, so it may be higher or lower). The game may cap it, split it, or misbehave." }) }
    }
    if ($i.fieldsUsed -ge 2 -and $i.category -in 'Weapons','Clothing' -and [double]$i.condition -gt ([double]$(if ($i.maxCondition) { $i.maxCondition } else { $i.defaultCondition }) + 0.5)) { $w.Add(@{ Level = 'warn'; Text = "$id : condition $($i.condition) is above the item's maximum ($(if ($i.maxCondition) { $i.maxCondition } else { $i.defaultCondition })). A value above the real maximum may behave oddly." }) }
    if ($i.category -eq 'QuestItems') { $w.Add(@{ Level = 'warn'; Text = "$id is a quest item. Adding it does not mark any quest step as done; the quest may still need its own dialogue or event." }) }
    if ($i.formatInferred) { $w.Add(@{ Level = 'info'; Text = "$id : its storage format was inferred from similar items (never seen in a real save)." }) }
    if ($r.target -eq 'Hotbar' -and $i.category -in 'Resources','Projectiles') { $w.Add(@{ Level = 'info'; Text = "$id is a stackable material; hotbar slots are normally used for tools and weapons." }) }
  }
  $eq = Parse-Equipment $s.Equip
  if ($eq -and (Get-BackpackSource $eq) -like 'estimated*') { $w.Add(@{ Level = 'info'; Text = "Your $($eq.Name)'s real size is not known to the tool; it is only using slots up to $(Get-BackpackMaxSlot $eq) (an estimate). If the backpack is bigger, set the real number in the 'Backpack slots' box." }) }
  $level = if ($w | Where-Object { $_.Level -eq 'warn' }) { 'warn' } else { 'ok' }
  return @{ Added = $plan.Added; Warnings = $w; Level = $level; Save = $s }
}

# how many of an item the player currently carries (hotbar + backpack)
function Get-CarriedCount($s, [string]$id) {
  $sum = 0
  foreach ($h in (Parse-Slots $s.Hot)) { if ($h.Id -eq $id) { $sum += [int](($h.Rest.TrimStart('&') -split '&')[0]) } }
  $eq = Parse-Equipment $s.Equip
  if ($eq) { foreach ($b in $eq.Contents) { if ($b.Id -eq $id) { $sum += [int](($b.Rest.TrimStart('&') -split '&')[0]) } } }
  return $sum
}