param(
  [string]$ExportRoot = '',
  [string[]]$SaveFiles = @(),
  [string]$Out = (Join-Path $PSScriptRoot 'items.json')
)
. (Join-Path $PSScriptRoot 'Paths.ps1')
if (-not $ExportRoot) { $ExportRoot = PF-ExportPath 'Permafrost\Content\Permafrost\Blueprints\Items\DataAsset_Items' }
if (-not $SaveFiles.Count) { $SaveFiles = PF-SaveFiles }
$ErrorActionPreference = 'Stop'
$L1 = [Text.Encoding]::Latin1

# ---- read the name table of a raw-exported (zen) package ----
function Get-NameMap([string]$path){
  $b=[IO.File]::ReadAllBytes($path)
  for($off=0;$off -le [math]::Min(300,$b.Length-16);$off+=4){
    $cnt=[BitConverter]::ToUInt32($b,$off); $nsb=[BitConverter]::ToUInt32($b,$off+4); $alg=[BitConverter]::ToUInt64($b,$off+8)
    if($alg -eq [uint64]3244556288 -and $cnt -gt 0 -and $cnt -lt 5000 -and $nsb -gt 0 -and $nsb -lt 200000){
      $hdr=$off+16+$cnt*8; $sp=$hdr+$cnt*2; $names=New-Object System.Collections.Generic.List[string]
      for($i=0;$i -lt $cnt;$i++){ $h0=$b[$hdr+$i*2]; $h1=$b[$hdr+$i*2+1]; $len=(($h0 -band 0x7F) -shl 8) -bor $h1
        if(($h0 -band 0x80) -ne 0){ $names.Add([Text.Encoding]::Unicode.GetString($b,$sp,$len*2)); $sp+=$len*2 } else { $names.Add([Text.Encoding]::ASCII.GetString($b,$sp,$len)); $sp+=$len } }
      return $names } }
  return $null
}

# Stack limit stored in an item's data: the pattern  00 00 00 00 00 00  05 01 <int32 stack>.  It sits near the start of the data
# for resources/consumables and further in (after the item's floats) for ammo, so the whole block is searched.
# Only trusted for categories where it was checked against the real stacks seen in your saves:
#   108 items compared: 37 exact matches, 71 larger than anything seen, 0 contradictions.
# (In weapons the same byte pattern belongs to a different field, so those categories are NOT read.)
function Get-GameStack([string]$path){
  $b=[IO.File]::ReadAllBytes($path); $hs=[BitConverter]::ToUInt32($b,4); if($hs -ge $b.Length){ return $null }
  [byte[]]$d=$b[$hs..($b.Length-1)]
  for($p=6;$p -le $d.Length-10;$p++){
    if($d[$p] -eq 5 -and $d[$p+1] -eq 1 -and $d[$p-1] -eq 0 -and $d[$p-2] -eq 0 -and $d[$p-3] -eq 0 -and $d[$p-4] -eq 0 -and $d[$p-5] -eq 0 -and $d[$p-6] -eq 0){
      $v=[BitConverter]::ToInt32($d,$p+2); if($v -ge 1 -and $v -le 100000){ return [int]$v } } }
  # Second header form of the same field:  01 03 <int32 stack> 82 03 01 00 03  (e.g. Dish_E2 = 20, Panacea = 5, splints = 5).
  for($p=2;$p -le $d.Length-9;$p++){
    if($d[$p-2] -eq 1 -and $d[$p-1] -eq 3 -and $d[$p+4] -eq 0x82 -and $d[$p+5] -eq 3 -and $d[$p+6] -eq 1 -and $d[$p+7] -eq 0 -and $d[$p+8] -eq 3){
      $v=[BitConverter]::ToInt32($d,$p); if($v -ge 1 -and $v -le 100000){ return [int]$v } } }
  return 0   # no stack field in the data = the class default, which is 1 (every such item seen in your saves stacks at 1)
}
# ---- item formats observed in real saves: id -> pattern + samples ----
$observed=@{}
foreach($f in $SaveFiles){ if(-not (Test-Path $f)){ continue }
  $t=$L1.GetString([IO.File]::ReadAllBytes($f))
  # decode the player/level blobs too (inventory formats appear in them)
  $texts=@($t)
  foreach($tag in 'PlayerSaveData','HostSaveData','LevelStreamingData'){ $i=$t.IndexOf("$tag###>"); if($i -ge 0){ $s=$i+"$tag###>".Length; $e=$t.IndexOf('?',$s); $x=$t.Substring($s,$e-$s).Replace('-','+').Replace('_','/'); while($x.Length%4){$x+='='}; try{ $texts+=$L1.GetString([Convert]::FromBase64String($x)) }catch{} } }
  foreach($tx in $texts){
    foreach($m in [regex]::Matches($tx,'[@#>]\d+=([A-Za-z0-9_\.\-]+)((?:&[0-9\.\-]+)*)(?![A-Za-z0-9_])')){ $id=$m.Groups[1].Value; $rest=$m.Groups[2].Value; if(-not $observed.ContainsKey($id)){ $observed[$id]=New-Object System.Collections.Generic.List[string] }; $observed[$id].Add($rest) }
    foreach($m in [regex]::Matches($tx,'SpecialItems>@([A-Za-z0-9_]+)((?:&[0-9\.\-]+)*)')){ $id=$m.Groups[1].Value; if(-not $observed.ContainsKey($id)){ $observed[$id]=New-Object System.Collections.Generic.List[string] }; $observed[$id].Add($m.Groups[2].Value) } } }

# Items confirmed to work by testing in the real game (they have since been used up, so they no longer appear in the saves):
#   KeyAnnas - added to the backpack on 2026-10-13 and used to open the House Camp blueprint door.
$observed['KeyAnnas']=New-Object System.Collections.Generic.List[string]; $observed['KeyAnnas'].Add('&1&0.0')

$noise='^(BP_|DA_|GE_|SM_|SK_|ST_|T_|M_|MI_|NS_|ABP_|sfx_|Sfx_|AttributeSet_|ECharacter|ESurvivor|AbilitySystem\.|StatusEffect\.|HUDInput\.|SurfaceType|object_|icon_|PrimarySocket|SecondarySocket|spine_)'
$allcapsOk='^[A-Z][A-Z0-9_]+$'
$skipDirs='CraftingRecipes','LearningRecipes','PoseOffsets'
$items=New-Object System.Collections.Generic.List[object]
Get-ChildItem $ExportRoot -Recurse -File -Filter *.uasset | ?{ $rel=$_.FullName.Substring($ExportRoot.Length+1); -not ($skipDirs | ?{ $rel -match "(^|\\)$_(\\|$)" }) } | %{
  $rel=$_.FullName.Substring($ExportRoot.Length+1); $cat=($rel -split '\\')[0]; $stem=$_.BaseName
  $suffix=$stem -replace '^DA_[A-Za-z]+?_',''; $full=$stem -replace '^DA_',''
  $n=Get-NameMap $_.FullName; if(-not $n){ return }
  $pathLast=@($n | ?{ $_ -match '/' } | %{ ($_ -split '/')[-1] })   # object names of meshes/textures (e.g. MoonRock_Standing_Lamp_001) are not item ids; checked: only changes the 3 standing lamps, 0 verified ids affected
  $cands=@($n | ?{ ($_ -cnotin $pathLast) -and ($_ -notmatch '[/:]') -and ($_ -notmatch '\.' -or $_ -match '^\.?\d') -and ($_ -notmatch $noise) -and ($_ -cnotmatch $allcapsOk) -and ($_ -ne $stem) } | select -Unique)
  $id=''; $conf=''
  if($cands -contains $suffix){ $id=$suffix; $conf='exact' }
  elseif($cands -contains $full){ $id=$full; $conf='exact' }
  elseif($cands.Count -eq 1){ $id=$cands[0]; $conf='single' }
  elseif($cands.Count -gt 1){ $id=($cands | sort @{e={ if($suffix -like "*$_*" -or $_ -like "*$suffix*"){0}else{1} }},@{e={ [math]::Abs($_.Length-$suffix.Length) }} | select -First 1); $conf='guess' }
  else { return }
  $obs=$null; $verified=$observed.ContainsKey($id)
  $items.Add([pscustomobject]@{ id=$id; category=$cat; asset=$stem; confidence=$(if($verified){'verified'}else{$conf}); candidates=@($cands); gameStack=$(if($cat -in 'Weapons','Clothing'){ 0 } elseif($cat -in 'Resources','Consumables','Valuables','Projectiles','Accessories','Holdables','Traps','QuestItems'){ Get-GameStack $_.FullName } else { $null }); ammoRefs=@($n | ?{ $_ -match '^DA_Projectile_' } | select -Unique); icon=(@($n | ?{ $_ -match '^/Game/' -and $_ -notmatch '\.' -and (($_ -split '/')[-1] -match '(?i)icon') } | select -First 1) -join '') })
}
# ---- attach observed formats / sizes ----
foreach($it in $items){
  if($observed.ContainsKey($it.id)){ $s=$observed[$it.id]; $fields=@($s | %{ ([regex]::Matches($_,'&')).Count }); $maxFields=($fields | measure -Maximum).Maximum
    $counts=@($s | %{ $p=$_ -split '&'; if($p.Count -ge 2 -and $p[1]){ [double]$p[1] } } | ?{ $_ -ne $null })
    $durs=@($s | %{ $p=$_ -split '&'; if($p.Count -ge 3 -and $p[2]){ [double]$p[2] } } | ?{ $_ -ne $null })
    $it | Add-Member fields $maxFields; $it | Add-Member maxSeenCount $(if($counts){ ($counts | measure -Maximum).Maximum } else { 1 }); $it | Add-Member maxSeenDur $(if($durs){ ($durs | measure -Maximum).Maximum } else { $null }); $it | Add-Member samples @($s | select -Unique | select -First 3)
  } else { $it | Add-Member fields $null; $it | Add-Member maxSeenCount $null; $it | Add-Member maxSeenDur $null; $it | Add-Member samples @() }
}
# ---- sub-category (second folder level for weapons / clothing sets) + defaults for items never seen in a save ----
foreach($it in $items){ $it | Add-Member sub '' -Force }
$weaponSub=@{}
Get-ChildItem $ExportRoot -Recurse -File -Filter *.uasset | %{ $rel=$_.FullName.Substring($ExportRoot.Length+1); $weaponSub[$_.BaseName]=($rel -split '\\')[0..([math]::Min(1,($rel -split '\\').Count-2))] -join '/' }
foreach($it in $items){ $it.sub=$weaponSub[$it.asset] }
$catDefault=@{}   # category/sub -> most common field count among items seen in saves
foreach($g in ($items | ?{ $null -ne $_.fields } | group sub)){ $catDefault[$g.Name]=@{ fields=($g.Group | group fields | sort Count -desc | select -First 1).Name -as [int]; dur=(($g.Group | ?{ $null -ne $_.maxSeenDur } | measure maxSeenDur -Maximum).Maximum) } }
$catDefaultTop=@{}
foreach($g in ($items | ?{ $null -ne $_.fields } | group category)){ $catDefaultTop[$g.Name]=@{ fields=($g.Group | group fields | sort Count -desc | select -First 1).Name -as [int]; dur=(($g.Group | ?{ $null -ne $_.maxSeenDur } | measure maxSeenDur -Maximum).Maximum) } }
$fallbackFields=@{ Resources=1; Projectiles=1; Consumables=2; Weapons=2; Clothing=2; Accessories=2; QuestItems=2; Valuables=2; Traps=2; Holdables=2 }
foreach($it in $items){
  $inferred=($null -eq $it.fields)
  $d=$catDefault[$it.sub]; if(-not $d){ $d=$catDefaultTop[$it.category] }
  $f=$it.fields; if($null -eq $f){ $f=$(if($d -and $d.fields -ne $null){ $d.fields } else { $fallbackFields[$it.category] }) }
  if($it.sub -match 'Firearms' -and $inferred){ $f=3 }
  $dur=$it.maxSeenDur
  if($null -eq $dur){ if($it.category -in 'Weapons','Clothing'){ $dur=$(if($d -and $d.dur){ $d.dur } else { 300.0 }) } else { $dur=0.0 } }
  $stack=$it.maxSeenCount; if($null -eq $stack -or $stack -lt 1){ $stack=1 }
  if($inferred){ $stack=$(if($f -eq 1){ if($it.category -eq 'Projectiles'){ 30 } else { 20 } } elseif($it.category -eq 'Consumables'){ 5 } else { 1 }) }
  $src=$(if(-not $inferred){ 'your saves' } else { 'estimate' })
  if($null -ne $it.gameStack){
    $gs=[int]$it.gameStack; $isDefault=($gs -eq 0); if($isDefault){ $gs=1 }
    if($null -ne $it.maxSeenCount -and $gs -lt $it.maxSeenCount){ $src='your saves' } else { $stack=$gs; $src=$(if($isDefault){ 'game default' } else { 'game data' }) } }
  if($it.id -eq '9x19_Ammo'){ $stack=100; $src='confirmed in game' }   # you saw 9mm stacks of 100 in the game
  $it | Add-Member -Force fieldsUsed ([int]$f); $it | Add-Member -Force defaultCondition $dur; $it | Add-Member -Force stackSize ([int]$stack); $it | Add-Member -Force stackSource $src; $it | Add-Member -Force formatInferred $inferred
}
# ---- weapon <-> ammo links (read from each weapon's data: the ammo assets it refers to) ----
$assetId=@{}; foreach($it in $items){ $assetId[$it.asset]=$it.id }
foreach($it in $items){ $ids=@($it.ammoRefs | %{ $assetId[$_] } | ?{ $_ } | select -Unique); if($it.category -ne 'Weapons'){ $ids=@() }; $it | Add-Member -Force usesAmmo $ids }
foreach($it in $items){ $by=@(); if($it.category -eq 'Projectiles'){ $by=@($items | ?{ $_.category -eq 'Weapons' -and ($_.usesAmmo -contains $it.id) -and ($_.id -notmatch 'NODamage|Enemy') } | %{ $_.id } | sort) }; $it | Add-Member -Force usedBy $by }
foreach($it in $items){ $it.PSObject.Properties.Remove('ammoRefs') }
$items | sort category,id | ConvertTo-Json -Depth 5 | Set-Content $Out -Encoding utf8
"catalog: $($items.Count) items written to $Out"
$items | group confidence | sort Count -desc | %{ "  {0,-9} {1}" -f $_.Name,$_.Count }
$ids=@{}; $items | %{ $ids[$_.id]=1 }
$seen=@($observed.Keys); $miss=@($seen | ?{ -not $ids.ContainsKey($_) } | sort)
"item IDs seen in saves: $($seen.Count) ; covered by catalog: $($seen.Count-$miss.Count) ; not covered: $($miss.Count)"
if($miss.Count){ "  not covered: " + ($miss -join ', ') }
