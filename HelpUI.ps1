# HelpUI.ps1 - draws the Help text with some design: big coloured section titles, bold names in the bullet lists, button names in the accent colour,
# warnings in red. The help itself stays plain text in PermafrostItemTool.ps1 (Show-Help); HP-Render turns it into formatted text in a RichTextBox and
# returns the list of sections (for the contents list on the left) and the colour of every piece of text (so the Find bar can put the colours back
# after it has highlighted a match). Needs Theme.ps1 ($script:Th).

function HP-Render($tb, [string]$text, $th) {
  $fonts = @{}
  $font = { param([double]$size, [bool]$bold) $k = "$size|$bold"; if (-not $fonts.ContainsKey($k)) { $fonts[$k] = New-Object System.Drawing.Font('Segoe UI', [single]$size, $(if ($bold) { [System.Drawing.FontStyle]::Bold } else { [System.Drawing.FontStyle]::Regular })) }; return $fonts[$k] }
  $starts = New-Object System.Collections.Generic.List[int]; $ends = New-Object System.Collections.Generic.List[int]; $fores = New-Object System.Collections.Generic.List[object]
  $sections = New-Object System.Collections.Generic.List[object]
  $add = {   # append formatted text and remember its colour
    param([string]$s, $fore, [double]$size, [bool]$bold)
    if ($s.Length -eq 0) { return }
    $p = $tb.TextLength; $tb.Select($p, 0); $tb.SelectionFont = (& $font $size $bold); $tb.SelectionColor = $fore; $tb.SelectionBackColor = $th.Field; $tb.SelectedText = $s
    if ($s.Trim("`n").Length -gt 0) { $starts.Add($p); $ends.Add($p + $s.Length); $fores.Add($fore) }
  }
  $para = { param([int]$indent, [int]$hang) $tb.Select($tb.TextLength, 0); $tb.SelectionIndent = $indent; $tb.SelectionHangingIndent = $hang; $tb.SelectionRightIndent = 12 }
  $inlineRe = [regex]"(?<q>(?<![A-Za-z0-9])'[^'\r\n]{2,45}'(?![A-Za-z0-9]))|(?<k>\b(?:IMPORTANT|DANGER|WARNING|CAUTION|NOT ENOUGH SPACE|NOT APPLIED|DELETES|DELETE)\b)"
  $inline = {   # one line of body text: 'button names' in the accent colour, warning words in red
    param([string]$s, $fore, [double]$size, [bool]$bold)
    $pos = 0
    foreach ($m in $inlineRe.Matches($s)) {
      if ($m.Index -gt $pos) { & $add $s.Substring($pos, $m.Index - $pos) $fore $size $bold }
      if ($m.Groups['q'].Success) { & $add $m.Value.Trim("'") $th.Accent2 $size $true } else { & $add $m.Value $th.Bad $size $true }
      $pos = $m.Index + $m.Length
    }
    if ($pos -lt $s.Length) { & $add $s.Substring($pos) $fore $size $bold }
  }
  $secRe = [regex]'^[A-Z][A-Z0-9 "''/\.&,\-]{3,}( \([^)]*\))?$'
  $ls = @($text -split "\r?\n"); $n = $ls.Count; $tb.Clear()
  for ($i = 0; $i -lt $n; $i++) {
    $l = $ls[$i].TrimEnd()
    if ($i -lt 2 -and ($i -eq 0 -or $l -match '^=+$')) { continue }   # the title lines: the banner shows them
    if ($l -match '^[=\-]{3,}$') { continue }
    if ($l.Length -eq 0) { & $para 8 0; & $add "`n" $th.Text 5 $false; continue }
    $prevBlank = ($i -eq 0 -or $ls[$i - 1].Trim().Length -eq 0 -or $ls[$i - 1] -match '^=+$'); $nextOk = ($i + 1 -lt $n -and $ls[$i + 1].Trim().Length -gt 0)
    if ($secRe.IsMatch($l)) {   # SECTION TITLE
      $pretty = (Get-Culture).TextInfo.ToTitleCase((($l -replace '"', '') -replace ' \(.*\)$', '' -replace ',.*$', '').ToLower())
      & $para 8 0; & $add "`n" $th.Text 9 $false
      $sections.Add(@{ Title = $pretty; Pos = $tb.TextLength })
      & $para 8 0; & $add ($l + "`n") $th.Accent 17 $true
      & $para 8 0; & $add (([string][char]0x2500) * 70 + "`n") $th.Border 7 $false
      & $para 8 0; & $add "`n" $th.Text 4 $false
      continue
    }
    if ($prevBlank -and $nextOk -and $l.Length -le 50 -and $l -notmatch '[\.:]$' -and $l -notmatch '^(- |\d+\. )') {   # sub title
      & $para 8 0; & $add ($l + "`n") $th.Accent2 12.5 $true; continue
    }
    if ($l -match '^(\d+)\. (.*)$') {   # numbered step
      & $para 16 22; & $add ($Matches[1] + '.' + "`t") $th.Accent 10.5 $true; & $inline $Matches[2] $th.Text 10.5 $false; & $add "`n" $th.Text 10.5 $false; continue
    }
    if ($l -match '^- (.*)$') {   # bullet: bold name, then the description
      $body = $Matches[1]; $name = ''; $rest = $body
      $m = [regex]::Match($body, '^((?:[^():]|\([^)]*\))+?)( - |: )(.*)$')
      if ($m.Success -and $m.Groups[1].Value.Length -le 100 -and $m.Groups[1].Value -notmatch '[\.!?]$') { $name = $m.Groups[1].Value; $rest = $m.Groups[3].Value; $sep = $m.Groups[2].Value.Trim() }
      & $para 18 20; & $add ([string][char]0x25CF + "`t") $th.Accent 8 $false
      if ($name) { & $inline $name $th.Accent2 10.5 $true; & $add ($sep + ' ') $th.Muted 10.5 $false }
      & $inline $rest $th.Text 10.5 $false; & $add "`n" $th.Text 10.5 $false; continue
    }
    & $para 8 0; & $inline $l $th.Text 10.5 $false; & $add "`n" $th.Text 10.5 $false
  }
  $tb.Select(0, 0)
  return @{ Starts = $starts.ToArray(); Ends = $ends.ToArray(); Fores = $fores.ToArray(); Sections = $sections.ToArray() }
}

# put the colours back on [pos, pos+len) after a Find highlight was removed
function HP-Restore($tb, $doc, [int]$pos, [int]$len, $th) {
  $e = $pos + $len; $i = [Array]::BinarySearch($doc.Ends, $pos); if ($i -lt 0) { $i = -$i - 1 } else { $i++ }   # first run that ends after pos
  for (; $i -lt $doc.Starts.Length -and $doc.Starts[$i] -lt $e; $i++) {
    $a = [Math]::Max($doc.Starts[$i], $pos); $b = [Math]::Min($doc.Ends[$i], $e)
    if ($b -gt $a) { $tb.Select($a, $b - $a); $tb.SelectionBackColor = $th.Field; $tb.SelectionColor = $doc.Fores[$i] }
  }
}
