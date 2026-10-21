# PicturesUI.ps1 - the "Pictures" window: builds the item / building pictures straight from the installed game (engine: GameFiles.ps1,
# Build-Icons.ps1, Build-RecipeIcons.ps1). Nothing is written to the game folder or to the save. Needs Theme.ps1, PlayerTools.ps1 (helpers) loaded.
$script:PIC = @{}
$script:OodleUrl = 'https://github.com/WorkingRobot/OodleUE/releases/download/2026-06-04-1357/clang-cl-x64-release.zip'

function PIC-GameDirFromSave([string]$savePath) {
  # <game>\Permafrost\SaveGame\World#N.pfs  ->  <game>
  try { $d = Split-Path (Split-Path (Split-Path $savePath -Parent) -Parent) -Parent; if ($d -and (Get-GameUtoc $d)) { return $d } } catch { }
  return ''
}

# downloads the free Oodle decompressor (the same file FModel fetches) into the tool folder; $zipOverride is for tests (a local zip)
function PIC-DownloadOodle([string]$zipOverride = '') {
  $dest = Join-Path $PSScriptRoot 'oodle-data-shared.dll'
  $zip = $zipOverride; $tmp = $null
  if (-not $zip) {
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('oodle-' + [Guid]::NewGuid().ToString('N') + '.zip')
    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $script:OodleUrl -OutFile $tmp -UseBasicParsing; $zip = $tmp
  }
  try {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $za = [IO.Compression.ZipFile]::OpenRead($zip)
    try {
      $e = $za.Entries | Where-Object { $_.FullName -eq 'bin/oodle-data-shared.dll' } | Select-Object -First 1
      if (-not $e) { throw 'The download did not contain bin/oodle-data-shared.dll.' }
      [IO.Compression.ZipFileExtensions]::ExtractToFile($e, $dest, $true)
    } finally { $za.Dispose() }
  } finally { if ($tmp -and (Test-Path -LiteralPath $tmp)) { Remove-Item -LiteralPath $tmp -Force } }
  return $dest
}

function PIC-Refresh {
  $u = $script:PIC
  $gd = $u.GameDir.Text.Trim(); $okGame = [bool]($gd -and (Get-GameUtoc $gd))
  $u.GameState.Text = $(if ($okGame) { 'Game files found.' } elseif ($gd) { 'No Permafrost-Windows.utoc found there (pick the folder that contains Permafrost\Content\Paks).' } else { 'Pick your Permafrost game folder.' })
  $u.GameState.ForeColor = $(if ($okGame) { $script:Th.Good } else { $script:Th.Warn })
  $od = Find-OodleDll
  $u.OodleState.Text = $(if ($od) { "Decompressor found: $od" } else { 'Decompressor (oodle-data-shared.dll) not found - needed once.' })
  $u.OodleState.ForeColor = $(if ($od) { $script:Th.Good } else { $script:Th.Warn })
  $u.BtnOodle.Enabled = (-not $od); $u.BtnBuild.Enabled = ($okGame -and $od -and -not $u.Proc)
}

function PIC-Download {
  $u = $script:PIC
  $a = Msg ("The game's files are packed with Oodle compression. To read the pictures this tool needs the free Oodle decompressor library (oodle-data-shared.dll, about 1 MB) - the same file the FModel program downloads.`n`nSource: $($script:OodleUrl)`nIt is saved next to this tool and is only used to read your own game files.`n`nDownload it now?") 'Pictures' 'YesNo' 'Question' 'Button2'
  if ($a -ne 'Yes') { return }
  try {
    $u.Form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor; [System.Windows.Forms.Application]::DoEvents()
    $p = PIC-DownloadOodle; $u.Out.Text = "Saved $p"
  } catch { $u.Out.Text = "Download failed: $($_.Exception.Message)`r`nYou can also copy oodle-data-shared.dll from FModel's data folder (Output\.data) next to this tool." }
  finally { $u.Form.Cursor = [System.Windows.Forms.Cursors]::Default }
  PIC-Refresh
}

function PIC-Build {
  $u = $script:PIC; $gd = $u.GameDir.Text.Trim()
  $od = Find-OodleDll; if (-not $od) { return }
  $u.Out.Text = 'Reading the game files...'; $u.BtnBuild.Enabled = $false
  $u.Log = Join-Path ([IO.Path]::GetTempPath()) ('pictures-' + [Guid]::NewGuid().ToString('N') + '.txt')
  $q = { param($s) "'" + ($s -replace "'", "''") + "'" }
  $cmd = "Set-Location -LiteralPath $(& $q $PSScriptRoot); & '.\Build-Icons.ps1' -GameDir $(& $q $gd) -OodleDll $(& $q $od); if (Test-Path -LiteralPath '.\catalog\recipe-details.csv') { & '.\Build-RecipeIcons.ps1' -GameDir $(& $q $gd) -OodleDll $(& $q $od) }; 'FINISHED'"
  $pw = (Get-Process -Id $PID).Path
  $u.Proc = Start-Process -FilePath $pw -ArgumentList @('-NoProfile', '-WindowStyle', 'Hidden', '-Command', $cmd) -WindowStyle Hidden -PassThru -RedirectStandardOutput $u.Log -RedirectStandardError ($u.Log + '.err')
  $u.Timer = New-Object System.Windows.Forms.Timer; $u.Timer.Interval = 700
  $u.Timer.Add_Tick({
    $u = $script:PIC
    if ($u.Proc -and $u.Proc.HasExited) {
      $u.Timer.Stop(); $txt = ''; if (Test-Path -LiteralPath $u.Log) { $txt = (Get-Content -LiteralPath $u.Log -Raw) }; $err = ''; if (Test-Path -LiteralPath ($u.Log + '.err')) { $err = (Get-Content -LiteralPath ($u.Log + '.err') -Raw) }
      $u.Out.Text = (($txt + $(if ($err) { "`r`n" + $err } else { '' })) -replace "`r?`n", "`r`n").Trim()
      if ($txt -cmatch 'FINISHED') { $u.Msg.Text = 'Done. Pictures are in the icons folder next to the tool. Close and reopen Player tools to see the recipe pictures.' } else { $u.Msg.Text = 'Something went wrong - see the text above.' }
      $script:IconCache = @{}; $u.Proc = $null; foreach ($f in @($u.Log, ($u.Log + '.err'))) { Remove-Item -LiteralPath $f -Force -ErrorAction SilentlyContinue }
      PIC-Refresh
    }
  })
  $u.Timer.Start()
}

function New-PicturesForm([string]$savePath, [switch]$AutoStart) {
  Add-Type -AssemblyName System.Windows.Forms; Add-Type -AssemblyName System.Drawing
  $script:PIC = @{ Proc = $null }; $u = $script:PIC
  $f = New-Object System.Windows.Forms.Form; $f.Text = 'Pictures  -  build item and building pictures from your game files'; $f.Size = New-Object System.Drawing.Size(760, 540); $f.MinimumSize = New-Object System.Drawing.Size(680, 480)
  $f.StartPosition = 'CenterParent'; $f.Font = New-Object System.Drawing.Font('Segoe UI', 9); $u.Form = $f
  $intro = New-Lbl $f "The hover pictures (items, recipes, buildings) are optional. They are read straight from your installed game - read-only, nothing in the game folder or your save is touched - and take about 20 seconds." 14 10 712 44; $intro.Anchor = 'Top,Left,Right'
  New-Lbl $f 'Game folder' 14 62 90 | Out-Null
  $u.GameDir = New-Object System.Windows.Forms.TextBox; $u.GameDir.Location = '106,59'; $u.GameDir.Size = '520,24'; $u.GameDir.Anchor = 'Top,Left,Right'; $f.Controls.Add($u.GameDir)
  $u.GameDir.Text = (PIC-GameDirFromSave $savePath)
  if (-not $u.GameDir.Text -and (Get-Command PF-GameDir -ErrorAction SilentlyContinue)) { try { $g = PF-GameDir; if ($g -and (Get-GameUtoc $g)) { $u.GameDir.Text = $g } } catch { } }
  $bb = New-Btn $f 'Browse...' 636 57 90 28; $bb.Anchor = 'Top,Right'
  $u.GameState = New-Lbl $f '' 106 88 620 24; $u.GameState.Anchor = 'Top,Left,Right'
  New-Lbl $f 'Decompressor' 14 120 90 | Out-Null
  $u.OodleState = New-Lbl $f '' 106 116 520 40; $u.OodleState.Anchor = 'Top,Left,Right'
  $u.BtnOodle = New-Btn $f 'Download it...' 636 114 90 28; $u.BtnOodle.Anchor = 'Top,Right'
  $u.BtnBuild = New-Btn $f 'Build pictures' 14 166 180 34; $u.BtnBuild.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
  $note = New-Lbl $f "The game's files are packed with Oodle compression, so a small free library (oodle-data-shared.dll, the same one the FModel program uses) is needed once to read them. The tool only downloads it when you say so." 14 208 712 48; $note.ForeColor = $script:Th.Muted; $note.Anchor = 'Top,Left,Right'
  $u.Out = New-Object System.Windows.Forms.TextBox; $u.Out.Multiline = $true; $u.Out.ReadOnly = $true; $u.Out.ScrollBars = 'Vertical'; $u.Out.Location = '14,262'; $u.Out.Size = '712,190'; $u.Out.Anchor = 'Top,Left,Right,Bottom'; $u.Out.Font = New-Object System.Drawing.Font('Consolas', 9)
  $u.Out.Text = 'Press "Build pictures" when the game folder and the decompressor both show green.'; $f.Controls.Add($u.Out)
  $u.Msg = New-Lbl $f '' 14 462 712 36; $u.Msg.Anchor = 'Left,Right,Bottom'; $u.Msg.ForeColor = $script:Th.Accent
  $bb.Add_Click({ $d = New-Object System.Windows.Forms.FolderBrowserDialog; $d.Description = 'Pick the Permafrost game folder (the one that contains Permafrost\Content\Paks)'; if ($d.ShowDialog() -eq 'OK') { $script:PIC.GameDir.Text = $d.SelectedPath } })
  $u.GameDir.Add_TextChanged({ PIC-Refresh }); $u.BtnOodle.Add_Click({ PIC-Download }); $u.BtnBuild.Add_Click({ try { PIC-Build } catch { $script:PIC.Out.Text = "Could not start: $($_.Exception.Message)"; PIC-Refresh } })
  if ($AutoStart) { $f.Add_Shown({ $u = $script:PIC; if ($u.BtnBuild.Enabled) { try { PIC-Build } catch { $u.Out.Text = "Could not start: $($_.Exception.Message)" } } else { $u.Out.Text = 'Almost there: ' + $(if (-not (Get-GameUtoc $u.GameDir.Text.Trim())) { 'pick your game folder (Browse...), ' } else { '' }) + $(if (-not (Find-OodleDll)) { 'press Download it... to get the small decompressor, ' } else { '' }) + 'then press Build pictures.' } }) }
  $f.Add_FormClosing({ param($s, $e) if ($script:PIC.Proc) { $e.Cancel = $true; [void](Msg 'Pictures are still being built - wait a few seconds.' 'Pictures' 'OK' 'Information') } })
  PIC-Refresh
  Apply-Theme $f; Set-AppIcon $f
  return $f
}
function Show-Pictures($owner, [string]$savePath, [switch]$AutoStart) { $f = New-PicturesForm $savePath -AutoStart:$AutoStart; $script:ActiveForm = $f; try { [void]$f.ShowDialog($owner) } finally { $script:ActiveForm = $null } }
