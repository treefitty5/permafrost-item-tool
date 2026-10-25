# Make-Release.ps1 - builds the release ZIP from exactly the files git would commit (tracked + new files that are not ignored).
#   pwsh -NoProfile -File .\Make-Release.ps1 -Version 1.2.0          ->  Releases\PermafrostItemTool-v1.2.0.zip
# The ZIP unpacks to one folder, "PermafrostItemTool". Your private files (Backups, icons, config.json, theme.json, ... see .gitignore) can never end up in it.
# It also scans every text file for personal strings and stops if it finds one.
param([Parameter(Mandatory)][string]$Version, [string]$OutDir = (Join-Path $PSScriptRoot 'Releases'))
$ErrorActionPreference = 'Stop'
$git = @('C:\Program Files\Git\cmd\git.exe', 'git') | Where-Object { Get-Command $_ -ErrorAction SilentlyContinue } | Select-Object -First 1
if (-not $git) { throw 'git was not found.' }
# strings that must not appear in any shipped text file: this PC's user name, computer name and profile path (read at run time, so nothing personal is written into this script),
# plus anything you list in release-scan.txt (one string per line; git-ignored)
$words = @($env:USERNAME, $env:COMPUTERNAME, $env:USERPROFILE) | Where-Object { $_ -and $_.Length -ge 3 }
$extra = Join-Path $PSScriptRoot 'release-scan.txt'; if (Test-Path -LiteralPath $extra) { $words += @(Get-Content -LiteralPath $extra | Where-Object { $_.Trim() }) }
$Scan = ($words | ForEach-Object { [regex]::Escape($_) }) -join '|'
$files = @(& $git -C $PSScriptRoot ls-files -c -o --exclude-standard)
if (-not $files.Count) { throw 'git lists no files - is this folder a repository?' }
$bad = $files | Where-Object { $_ -match '^(icons|Backups|Archive|Releases)/|^(config|theme|spoiler|backpacks|backpack-tweaks|stack-tweaks|weapon-tweaks|recipe-tweaks|pictures)\.json$|^(ForumPost|release-scan)\.txt$|\.(pfs|pak|utoc|ucas|uasset|ubulk|uexp|umap|usmap|dll|exe)$|^assets/(?!app\.ico$|app-icon\.png$)|^catalog/(text|lore)\.csv$' }
if ($bad) { throw "private files would be shipped: $($bad -join ', ')" }
$stage = Join-Path ([IO.Path]::GetTempPath()) ('pf-release-' + [Guid]::NewGuid().ToString('N')); $root = Join-Path $stage 'PermafrostItemTool'; New-Item -ItemType Directory -Path $root | Out-Null
$hits = @()
foreach ($f in $files) {
  $src = Join-Path $PSScriptRoot $f; if (-not (Test-Path -LiteralPath $src)) { continue }
  $dst = Join-Path $root $f; New-Item -ItemType Directory -Path (Split-Path $dst -Parent) -Force | Out-Null; Copy-Item -LiteralPath $src -Destination $dst
  if ($f -notmatch '\.(png|ico|jpg|zip)$' -and ([IO.File]::ReadAllText($src) -match $Scan)) { $hits += $f }
}
if ($hits) { Remove-Item -LiteralPath $stage -Recurse -Force; throw "personal text found in: $($hits -join ', ')" }
if (-not (Test-Path -LiteralPath $OutDir)) { New-Item -ItemType Directory -Path $OutDir -Force | Out-Null }
$zip = Join-Path $OutDir "PermafrostItemTool-v$Version.zip"; if (Test-Path -LiteralPath $zip) { Remove-Item -LiteralPath $zip -Force }
Compress-Archive -Path $root -DestinationPath $zip -CompressionLevel Optimal
Remove-Item -LiteralPath $stage -Recurse -Force
"Built $zip : $($files.Count) files, $([math]::Round((Get-Item -LiteralPath $zip).Length / 1KB)) KB"
