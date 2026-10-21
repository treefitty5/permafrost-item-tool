# WorldPicker.ps1 - "Choose your world": lists every Permafrost save found (World#1.pfs, World#2.pfs ...) with hours played and last-saved time.
# Needs Theme.ps1 and PlayerTools.ps1 (helpers) loaded. Read-only: it only reads the saves to show their details.
$script:WP = @{}

# every .pfs in the given folders (the folder of the current save, plus the auto-detected Steam save folders when Paths.ps1 is loaded)
function Get-WorldFiles([string]$currentSave) {
  $dirs = New-Object System.Collections.Generic.List[string]
  if ($currentSave) { try { $d = Split-Path $currentSave -Parent; if ($d -and (Test-Path -LiteralPath $d)) { $dirs.Add($d) } } catch { } }
  if (Get-Command PF-SaveFolders -ErrorAction SilentlyContinue) { try { foreach ($d in (PF-SaveFolders)) { if ($d -and (Test-Path -LiteralPath $d) -and -not ($dirs -contains $d)) { $dirs.Add($d) } } } catch { } }
  $rows = New-Object System.Collections.Generic.List[object]
  foreach ($d in $dirs) {
    foreach ($f in (Get-ChildItem -LiteralPath $d -Filter '*.pfs' -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
      $hrs = $null; $when = ''
      try { $s = [Text.Encoding]::GetEncoding(28591).GetString([IO.File]::ReadAllBytes($f.FullName)); $m = [regex]::Match($s, 'TotalPlayTime>([\d\.]+)'); if ($m.Success) { $hrs = [double]::Parse($m.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture) / 3600 }; $when = [regex]::Match($s, 'LastUpdatedAt>([^\?]+)').Groups[1].Value } catch { }
      $rows.Add([pscustomobject]@{ Name = $f.BaseName; Path = $f.FullName; Hours = $hrs; Saved = $when; Written = $f.LastWriteTime; SizeMB = [math]::Round($f.Length / 1MB, 1) })
    }
  }
  return $rows.ToArray()
}

# returns the chosen save path, or $null if cancelled
function Show-WorldPicker($owner, [string]$currentSave) {
  Add-Type -AssemblyName System.Windows.Forms; Add-Type -AssemblyName System.Drawing
  $script:WP = @{ Result = $null; Rows = @(Get-WorldFiles $currentSave) }; $u = $script:WP
  $f = New-Object System.Windows.Forms.Form; $f.Text = 'Choose your world'; $f.Size = New-Object System.Drawing.Size(760, 400); $f.MinimumSize = New-Object System.Drawing.Size(640, 320)
  $f.StartPosition = 'CenterParent'; $f.Font = New-Object System.Drawing.Font('Segoe UI', 9); $u.Form = $f
  $h = New-Lbl $f 'These are the Permafrost saves found on this PC. Pick the one you want to work on (the game must be closed before anything is changed).' 14 10 716 38; $h.Anchor = 'Top,Left,Right'
  $lv = New-LV $f @('World', 'Hours played', 'Last saved', 'Size', 'File') @(110, 100, 190, 60, 240); $lv.Location = '14,52'; $lv.Size = '716,248'; $lv.Anchor = 'Top,Left,Right,Bottom'; $u.List = $lv
  foreach ($r in $u.Rows) {
    $it = New-Object System.Windows.Forms.ListViewItem($r.Name); [void]$it.SubItems.Add($(if ($null -ne $r.Hours) { ('{0:0.0} h' -f $r.Hours) } else { '?' })); [void]$it.SubItems.Add($(if ($r.Saved) { $r.Saved } else { $r.Written.ToString('g') }))
    [void]$it.SubItems.Add("$($r.SizeMB) MB"); [void]$it.SubItems.Add($r.Path); $it.Tag = $r.Path; if ($currentSave -and $r.Path -eq $currentSave) { $it.Selected = $true }; [void]$lv.Items.Add($it) }
  if ($u.Rows.Count -eq 0) { $e = New-Lbl $f 'No saves were found automatically. Use "Browse for a file..." to pick a .pfs file yourself.' 14 310 560 20; $e.Anchor = 'Left,Bottom'; $e.ForeColor = $script:Th.Warn }
  $bUse = New-Btn $f 'Use this world' 14 322 150 32; $bUse.Anchor = 'Left,Bottom'; $bUse.Font = New-Object System.Drawing.Font('Segoe UI', 9, [System.Drawing.FontStyle]::Bold)
  $bBr = New-Btn $f 'Browse for a file...' 174 322 160 32; $bBr.Anchor = 'Left,Bottom'; $bCa = New-Btn $f 'Cancel' 344 322 100 32; $bCa.Anchor = 'Left,Bottom'
  $use = { $s = $script:WP.List.SelectedItems; if ($s.Count -gt 0) { $script:WP.Result = [string]$s[0].Tag; $script:WP.Form.Close() } }
  $bUse.Add_Click($use); $lv.Add_DoubleClick($use); $bCa.Add_Click({ $script:WP.Form.Close() })
  $bBr.Add_Click({ $d = New-Object System.Windows.Forms.OpenFileDialog; $d.Filter = 'Permafrost saves (*.pfs)|*.pfs'; if ($d.ShowDialog($script:WP.Form) -eq 'OK') { $script:WP.Result = $d.FileName; $script:WP.Form.Close() } })
  Apply-Theme $f; Set-AppIcon $f
  if ($script:TestMode) { return $f }
  $script:ActiveForm = $f; try { [void]$f.ShowDialog($owner) } finally { $script:ActiveForm = $null }
  return $script:WP.Result
}
