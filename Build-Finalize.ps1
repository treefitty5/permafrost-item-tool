# Build-Finalize.ps1 - turns freshly built data into the SHIPPABLE data pack. Run it last (Build-Everything.ps1 does); safe to run again.
#   pwsh -NoProfile -File .\Build-Finalize.ps1
# What it does:
#  * items.json: removes the fields that came from the saves on THIS computer (samples, maxSeenCount, maxSeenDur) so nothing personal is committed
#  * catalog\blueprints-index.csv: keeps only the learning-recipe rows (the only rows the tool reads at run time; the full index is ~2.7 MB)
#  * catalog\npcs.csv: blanks the NPC journal text (story text is not part of the data pack)
#  * datapack.json: which Steam build of the game the data was made for (the Overview compares it with the installed game)
# Never shipped (kept out of git by .gitignore, but still made locally): catalog\text.csv, catalog\lore.csv, catalog\export-index.csv, catalog\_*.json / _tops.txt.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Paths.ps1')
$utf8 = New-Object Text.UTF8Encoding($false)
$ip = Join-Path $PSScriptRoot 'items.json'; if (-not (Test-Path -LiteralPath $ip)) { throw 'items.json not found - run Build-Everything.ps1 first.' }
$items = Get-Content -LiteralPath $ip -Raw | ConvertFrom-Json
$stripped = 0; foreach ($i in $items) { foreach ($n in 'samples', 'maxSeenCount', 'maxSeenDur') { if ($i.PSObject.Properties[$n]) { $i.PSObject.Properties.Remove($n); $stripped++ } } }
[IO.File]::WriteAllText($ip, (ConvertTo-Json -InputObject $items -Depth 30 -Compress), $utf8)
$cat = Join-Path $PSScriptRoot 'catalog'
$bi = Join-Path $cat 'blueprints-index.csv'
if (Test-Path -LiteralPath $bi) { $rows = @(Import-Csv -LiteralPath $bi); $keep = @($rows | Where-Object { $_.Asset -like 'DA_Learn*' }); if ($keep.Count -lt $rows.Count) { $keep | Export-Csv -LiteralPath $bi -NoTypeInformation -Encoding UTF8 } ; $kept = $keep.Count } else { $kept = 0 }
$np = Join-Path $cat 'npcs.csv'
if (Test-Path -LiteralPath $np) { $nr = @(Import-Csv -LiteralPath $np); if ($nr.Count) { foreach ($r in $nr) { if ($r.PSObject.Properties['Journal']) { $r.Journal = '' } }; $nr | Export-Csv -LiteralPath $np -NoTypeInformation -Encoding UTF8 } }   # read everything BEFORE writing (a pipeline would truncate the file it is still reading)
$build = ''
try { $g = PF-GameDir; if ($g) { $acf = Join-Path (Split-Path (Split-Path $g -Parent) -Parent) 'appmanifest_2254990.acf'; if (Test-Path -LiteralPath $acf) { $m = [regex]::Match((Get-Content -LiteralPath $acf -Raw), '"buildid"\s+"(\d+)"'); if ($m.Success) { $build = $m.Groups[1].Value } } } } catch { }
if (-not $build) { $old = Join-Path $PSScriptRoot 'datapack.json'; if (Test-Path -LiteralPath $old) { try { $build = [string](Get-Content -LiteralPath $old -Raw | ConvertFrom-Json).steamBuild } catch { } } }
$dp = [ordered]@{ steamBuild = $build; items = @($items).Count; made = (Get-Date).ToString('yyyy-MM-dd'); note = 'Names, numbers and relationships read from the game files. No pictures, art or story text.' }
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'datapack.json'), ($dp | ConvertTo-Json), $utf8)
"Data pack finished: $(@($items).Count) items ($stripped save-derived fields removed), $kept learning-recipe rows kept, game build $(if ($build) { $build } else { '(unknown)' })."
