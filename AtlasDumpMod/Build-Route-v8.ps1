param([int]$Spacing = 7500, [int]$Dilate = 1, [string]$Out = '')
$TR = 'C:\Users\Fabiano\Documents\PermafrostItemTool'; Set-Location $TR; $script:ToolDir = $TR
Add-Type -AssemblyName System.Windows.Forms; Add-Type -AssemblyName System.Drawing
foreach ($f in 'Paths','SaveCore','Theme','PlayerCore','PlayerTools','WorldCore','WorldReset') { . "$TR\$f.ps1" }
$sp = PF-SavePath
$text = $script:L1.GetString([IO.File]::ReadAllBytes($sp))
$m = [regex]::Match($text, 'FogOfWarRevealer_Voxels>([0-9,;]+)')
$vox = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($t in ($m.Groups[1].Value -split ';')) { if ($t) { [void]$vox.Add($t) } }
"revealed voxels: $($vox.Count)"
$V = 5000; $A = 31; $B = 31
# every position the tool knows: the explored world's records (all classes) + the first flight's log
$pts = New-Object System.Collections.Generic.List[double[]]
$w = Parse-WorldFromText $text 2>$null
if (-not $w) { $plan = Build-ResetPlan $sp @{ Trees = $true; Ores = $true; Breakables = $true; Items = $true; Containers = $true; RadiusM = 0 }; $w = $plan.World }
foreach ($c in $w.Cells) { foreach ($r in $c.Recs) { if ($r.Pos -and $r.Pos.Count -ge 3) { $pts.Add([double[]]@($r.Pos[0], $r.Pos[1], $r.Pos[2])) } } }
"records: $($pts.Count)"
$log = Join-Path $TR 'Archive\atlas-flight\AtlasDump-after-route106.log'
$n0 = $pts.Count
foreach ($ln in [IO.File]::ReadLines($log)) { if ($ln.StartsWith('STOP')) { $q = $ln.Split('|'); if ($q.Count -ge 8 -and $q[2] -notmatch 'MasterClothing|Spawner|PCGReActor|QuestItemDispenser|RespawnPoint|WeatherManager|WorldMapManager|Companion|PhaseWeather' -and [double]::Parse($q[6], $script:ResetInv) -lt 15000) { $pts.Add([double[]]@([double]::Parse($q[4], $script:ResetInv), [double]::Parse($q[5], $script:ResetInv), [double]::Parse($q[6], $script:ResetInv))) } } }
"log positions added: $($pts.Count - $n0)"
# z lookup grid (1 km cells are too coarse; use 100 m buckets of max z)
$bk = @{}
foreach ($q in $pts) { $key = "$([math]::Floor($q[0] / 5000)),$([math]::Floor($q[1] / 5000))"; if (-not $bk.ContainsKey($key) -or $q[2] -gt $bk[$key]) { $bk[$key] = $q[2] } }
"z buckets (50 m): $($bk.Count)"
# dilated region (in voxels)
$reg = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($t in $vox) { $p = $t -split ','; $c = [int]$p[0]; $r = [int]$p[1]; foreach ($dc in (-$Dilate)..$Dilate) { foreach ($dr in (-$Dilate)..$Dilate) { [void]$reg.Add("$($c + $dc),$($r + $dr)") } } }
"region voxels after dilation: $($reg.Count)"
# lattice anchored at the spawn
$x0 = -64901; $y0 = -94509
$stops = New-Object System.Collections.Generic.List[object]
$minI = [int][math]::Floor((-($A + 5) * $V - $x0) / $Spacing); $maxI = [int][math]::Ceiling(((60 - $A) * $V - $x0) / $Spacing)
$minJ = [int][math]::Floor((-($B + 5) * $V - $y0) / $Spacing); $maxJ = [int][math]::Ceiling(((60 - $B) * $V - $y0) / $Spacing)
foreach ($i in $minI..$maxI) { foreach ($j in $minJ..$maxJ) { $x = $x0 + $i * $Spacing; $y = $y0 + $j * $Spacing
  $c = [int][math]::Floor($x / $V) + $A; $r = [int][math]::Floor($y / $V) + $B
  if ($reg.Contains("$c,$r")) { $stops.Add([pscustomobject]@{ X = $x; Y = $y; Z = $null; Src = '' }) } } }
"lattice stops inside the region: $($stops.Count)"
# ground reference: highest known object within R of the stop, widening the search if there is none
$have = 0; $near = 0; $none = 0
foreach ($s in $stops) { $best = $null
  foreach ($rad in 1, 2, 4) { $cx = [math]::Floor($s.X / 5000); $cy = [math]::Floor($s.Y / 5000)
    foreach ($dx in (-$rad)..$rad) { foreach ($dy in (-$rad)..$rad) { $k = "$($cx + $dx),$($cy + $dy)"; if ($bk.ContainsKey($k) -and ($null -eq $best -or $bk[$k] -gt $best)) { $best = $bk[$k] } } }
    if ($null -ne $best) { $s.Src = "r$rad"; break } }
  if ($null -ne $best) { $s.Z = [int][math]::Round($best) } else { $none++ } }
"z source: r1 (within ~75 m) $(@($stops | Where-Object { $_.Src -eq 'r1' }).Count), r2 $(@($stops | Where-Object { $_.Src -eq 'r2' }).Count), r4 $(@($stops | Where-Object { $_.Src -eq 'r4' }).Count), none $none"
# extra stops: known objects that lie farther than 80 m from every lattice stop (edges of the fog map, far outposts)
$sg = @{}; foreach ($st in $stops) { $k = "$([math]::Floor($st.X / 10000)),$([math]::Floor($st.Y / 10000))"; if (-not $sg[$k]) { $sg[$k] = New-Object System.Collections.Generic.List[object] }; $sg[$k].Add($st) }
$unc = @{}
foreach ($q in $pts) { $cx = [math]::Floor($q[0] / 10000); $cy = [math]::Floor($q[1] / 10000); $ok = $false
  :scan foreach ($dx in -1..1) { foreach ($dy in -1..1) { $l = $sg["$($cx + $dx),$($cy + $dy)"]; if ($l) { foreach ($st in $l) { $ddx = $st.X - $q[0]; $ddy = $st.Y - $q[1]; if ($ddx * $ddx + $ddy * $ddy -le 64000000) { $ok = $true; break scan } } } } }
  if (-not $ok) { $k = "$([math]::Floor(($q[0] - $x0) / $Spacing)),$([math]::Floor(($q[1] - $y0) / $Spacing))"; if (-not $unc[$k]) { $unc[$k] = @{ N = 0; SX = 0.0; SY = 0.0; Z = -1e9 } }; $e = $unc[$k]; $e.N++; $e.SX += $q[0]; $e.SY += $q[1]; if ($q[2] -gt $e.Z) { $e.Z = $q[2] } } }
$extra = 0; $uncObjs = 0; foreach ($e in $unc.Values) { $uncObjs += $e.N; if ($e.N -ge 2) { $stops.Add([pscustomobject]@{ X = [int]($e.SX / $e.N); Y = [int]($e.SY / $e.N); Z = [int]$e.Z; Src = 'extra' }); $extra++ } }
"objects outside 80 m of the lattice: $uncObjs in $($unc.Count) clusters; extra stops added (2+ objects): $extra"
# order: nearest neighbour from the spawn
$left = New-Object System.Collections.Generic.List[object]; $left.AddRange($stops); $ord = New-Object System.Collections.Generic.List[object]; $cx = $x0; $cy = $y0
while ($left.Count) { $bi = 0; $bd = [double]::MaxValue; for ($k = 0; $k -lt $left.Count; $k++) { $d = ($left[$k].X - $cx) * ($left[$k].X - $cx) + ($left[$k].Y - $cy) * ($left[$k].Y - $cy); if ($d -lt $bd) { $bd = $d; $bi = $k } }
  $s = $left[$bi]; $ord.Add($s); $cx = $s.X; $cy = $s.Y; $left.RemoveAt($bi) }
if ($Out) {
  $sb = New-Object System.Text.StringBuilder
  [void]$sb.AppendLine("-- route v8: stops every $($Spacing / 100) m over the revealed map of World#2 (fog-of-war squares + $Dilate square border), ordered outward from the spawn (nearest next). z = highest known object near the stop (cm; the mod hovers 25 m above it, or above what the trace finds). A stop with no z gets the mod's own ground trace.")
  [void]$sb.AppendLine('return {')
  $n = 0; foreach ($s in $ord) { $n++; $zt = if ($null -ne $s.Z) { ", z = $($s.Z)" } else { '' }; [void]$sb.AppendLine("  { name = `"S$n`", x = $($s.X), y = $($s.Y)$zt, wait = 18000 },") }
  [void]$sb.AppendLine('}'); [IO.File]::WriteAllText($Out, $sb.ToString()); "written $Out ($n stops)"
}
$ord | Export-Csv (Join-Path (Split-Path $Out) 'route8.csv') -NoTypeInformation 2>$null
