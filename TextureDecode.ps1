# TextureDecode.ps1 - turns FModel's RAW texture exports (.uasset + .ubulk) into pictures, without any extra tools.
# Supports the formats used by the item icons: PF_DXT5 (BC3) and PF_B8G8R8A8. (PF_DXT1 is included for completeness.)
Add-Type -AssemblyName System.Drawing
if (-not ('Bcn' -as [type])) {
Add-Type -TypeDefinition @'
using System;
public static class Bcn {
  static void Rgb565(int c, out int r, out int g, out int b) { r = ((c >> 11) & 31) * 255 / 31; g = ((c >> 5) & 63) * 255 / 63; b = (c & 31) * 255 / 31; }
  // returns BGRA bytes (w*h*4). mode: 5 = BC3/DXT5 (16-byte blocks), 1 = BC1/DXT1 (8-byte blocks)
  public static byte[] Decode(byte[] src, int off, int w, int h, int mode) {
    byte[] dst = new byte[w * h * 4];
    int bw = (w + 3) / 4, bh = (h + 3) / 4, p = off;
    int[] al = new int[8];
    int[] cr = new int[4], cg = new int[4], cb = new int[4], ca = new int[4];
    for (int by = 0; by < bh; by++) for (int bx = 0; bx < bw; bx++) {
      ulong abits = 0;
      if (mode == 5) {
        int a0 = src[p], a1 = src[p + 1];
        for (int i = 0; i < 6; i++) abits |= (ulong)src[p + 2 + i] << (8 * i);
        al[0] = a0; al[1] = a1;
        if (a0 > a1) { for (int i = 2; i < 8; i++) al[i] = ((8 - i) * a0 + (i - 1) * a1) / 7; }
        else { for (int i = 2; i < 6; i++) al[i] = ((6 - i) * a0 + (i - 1) * a1) / 5; al[6] = 0; al[7] = 255; }
        p += 8;
      }
      int c0 = src[p] | (src[p + 1] << 8), c1 = src[p + 2] | (src[p + 3] << 8);
      uint idx = (uint)(src[p + 4] | (src[p + 5] << 8) | (src[p + 6] << 16) | (src[p + 7] << 24)); p += 8;
      Rgb565(c0, out cr[0], out cg[0], out cb[0]); Rgb565(c1, out cr[1], out cg[1], out cb[1]);
      ca[0] = ca[1] = ca[2] = ca[3] = 255;
      if (mode == 5 || c0 > c1) {
        cr[2] = (2 * cr[0] + cr[1]) / 3; cg[2] = (2 * cg[0] + cg[1]) / 3; cb[2] = (2 * cb[0] + cb[1]) / 3;
        cr[3] = (cr[0] + 2 * cr[1]) / 3; cg[3] = (cg[0] + 2 * cg[1]) / 3; cb[3] = (cb[0] + 2 * cb[1]) / 3;
      } else {
        cr[2] = (cr[0] + cr[1]) / 2; cg[2] = (cg[0] + cg[1]) / 2; cb[2] = (cb[0] + cb[1]) / 2;
        cr[3] = 0; cg[3] = 0; cb[3] = 0; ca[3] = 0;
      }
      for (int py = 0; py < 4; py++) for (int px = 0; px < 4; px++) {
        int x = bx * 4 + px, y = by * 4 + py; int n = 4 * py + px;
        if (x >= w || y >= h) continue;
        int ci = (int)((idx >> (2 * n)) & 3); int o = (y * w + x) * 4;
        dst[o] = (byte)cb[ci]; dst[o + 1] = (byte)cg[ci]; dst[o + 2] = (byte)cr[ci];
        dst[o + 3] = mode == 5 ? (byte)al[(int)((abits >> (3 * n)) & 7)] : (byte)ca[ci];
      }
    }
    return dst;
  }
}
'@
}

function Get-TextureInfo([string]$uassetPath) {
  $b = [IO.File]::ReadAllBytes($uassetPath); $hs = [BitConverter]::ToUInt32($b, 4)
  if ($hs -ge $b.Length) { return $null }
  [byte[]]$d = $b[$hs..($b.Length - 1)]; $s = [Text.Encoding]::Latin1.GetString($d)
  $m = [regex]::Match($s, '[\x08\x0C]\x00\x00\x00(PF_DXT5|PF_DXT1|PF_B8G8R8A8)\x00')
  if (-not $m.Success) { return $null }
  $i = $m.Index
  $w = [BitConverter]::ToInt32($d, $i - 12); $h = [BitConverter]::ToInt32($d, $i - 8)
  if ($w -lt 1 -or $h -lt 1 -or $w -gt 8192 -or $h -gt 8192) { return $null }
  return @{ Format = $m.Groups[1].Value; Width = $w; Height = $h; Data = $d }
}

# returns a System.Drawing.Bitmap (top picture of the texture) or $null
function Convert-TextureToBitmap([string]$uassetPath) {
  $t = Get-TextureInfo $uassetPath; if (-not $t) { return $null }
  $w = $t.Width; $h = $t.Height
  $size = switch ($t.Format) { 'PF_DXT5' { [int]([math]::Ceiling($w / 4) * [math]::Ceiling($h / 4) * 16) } 'PF_DXT1' { [int]([math]::Ceiling($w / 4) * [math]::Ceiling($h / 4) * 8) } 'PF_B8G8R8A8' { $w * $h * 4 } default { 0 } }
  if ($size -le 0) { return $null }
  [byte[]]$px = $null
  $ubulk = $uassetPath -replace '\.uasset$', '.ubulk'
  if (Test-Path -LiteralPath $ubulk) {
    $ub = [IO.File]::ReadAllBytes($ubulk); if ($ub.Length -lt $size) { return $null }
    $px = New-Object byte[] $size; [Array]::Copy($ub, 0, $px, 0, $size)       # the biggest picture is stored first
  } else {
    # small textures keep the picture inside the .uasset, right before the (width, height, 1) triple that closes the mip entry
    $d = $t.Data; $tri = [byte[]]([BitConverter]::GetBytes([int]$w) + [BitConverter]::GetBytes([int]$h) + [BitConverter]::GetBytes([int]1))
    $at = -1
    for ($k = $d.Length - 12; $k -ge $size; $k--) { if ($d[$k] -eq $tri[0] -and $d[$k+1] -eq $tri[1] -and $d[$k+2] -eq $tri[2] -and $d[$k+3] -eq $tri[3] -and $d[$k+4] -eq $tri[4] -and $d[$k+5] -eq $tri[5] -and $d[$k+6] -eq $tri[6] -and $d[$k+7] -eq $tri[7] -and $d[$k+8] -eq 1 -and $d[$k+9] -eq 0 -and $d[$k+10] -eq 0 -and $d[$k+11] -eq 0) { $at = $k; break } }
    if ($at -lt 0) { return $null }
    $px = New-Object byte[] $size; [Array]::Copy($d, $at - $size, $px, 0, $size)
  }
  [byte[]]$bgra = switch ($t.Format) { 'PF_DXT5' { [Bcn]::Decode($px, 0, $w, $h, 5) } 'PF_DXT1' { [Bcn]::Decode($px, 0, $w, $h, 1) } default { $px } }
  $bmp = New-Object System.Drawing.Bitmap($w, $h, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $rect = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
  $bd = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::WriteOnly, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  [System.Runtime.InteropServices.Marshal]::Copy($bgra, 0, $bd.Scan0, $bgra.Length); $bmp.UnlockBits($bd)
  return $bmp
}
