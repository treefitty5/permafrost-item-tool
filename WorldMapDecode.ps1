# WorldMapDecode.ps1 - puts the game's world map picture back together (used by Build-WorldMap.ps1; tested by the self-test).
#
# The game stores the map as a UE5 "virtual texture": the picture cut into tiles of 128 x 128 pixels plus 4 pixels of border on every side (136 x 136), BC1 (DXT1) blocks,
# tile after tile in Morton (Z-order) inside the first data chunk, which starts with a 4-byte header. Convert-WorldMapChunk returns the 24-bit BGR pixels.
if (-not ('VtBc1' -as [type])) {
Add-Type -TypeDefinition @'
using System;
public static class VtBc1 {
  static int Part(int n) { int x = 0; for (int b = 0; b < 8; b++) x |= ((n >> (2 * b)) & 1) << b; return x; }
  static void Rgb565(int c, out int r, out int g, out int b) { r = ((c >> 11) & 31) * 255 / 31; g = ((c >> 5) & 63) * 255 / 63; b = (c & 31) * 255 / 31; }
  // returns BGR bytes (side * side * 3), side = tilesPerSide * inner
  public static byte[] Build(byte[] ub, int off, int tilesPerSide, int inner, int border) {
    int tile = inner + 2 * border, side = tilesPerSide * inner, tb = tile * tile / 2; var img = new byte[side * side * 3];
    var cr = new int[4]; var cg = new int[4]; var cb = new int[4];
    for (int n = 0; n < tilesPerSide * tilesPerSide; n++) {
      int tx = Part(n), ty = Part(n >> 1), t0 = off + n * tb;
      for (int by = 0; by < tile / 4; by++) for (int bx = 0; bx < tile / 4; bx++) {
        int p = t0 + (by * (tile / 4) + bx) * 8; int c0 = ub[p] | (ub[p + 1] << 8), c1 = ub[p + 2] | (ub[p + 3] << 8);
        Rgb565(c0, out cr[0], out cg[0], out cb[0]); Rgb565(c1, out cr[1], out cg[1], out cb[1]);
        if (c0 > c1) { for (int k = 0; k < 3; k++) { } cr[2] = (2 * cr[0] + cr[1]) / 3; cg[2] = (2 * cg[0] + cg[1]) / 3; cb[2] = (2 * cb[0] + cb[1]) / 3; cr[3] = (cr[0] + 2 * cr[1]) / 3; cg[3] = (cg[0] + 2 * cg[1]) / 3; cb[3] = (cb[0] + 2 * cb[1]) / 3; }
        else { cr[2] = (cr[0] + cr[1]) / 2; cg[2] = (cg[0] + cg[1]) / 2; cb[2] = (cb[0] + cb[1]) / 2; cr[3] = 0; cg[3] = 0; cb[3] = 0; }
        uint bits = (uint)(ub[p + 4] | (ub[p + 5] << 8) | (ub[p + 6] << 16) | (ub[p + 7] << 24));
        for (int y = 0; y < 4; y++) for (int x = 0; x < 4; x++) {
          int px = bx * 4 + x - border, py = by * 4 + y - border; if (px < 0 || py < 0 || px >= inner || py >= inner) continue;
          int idx = (int)((bits >> (2 * (y * 4 + x))) & 3); int o = ((ty * inner + py) * side + tx * inner + px) * 3;
          img[o] = (byte)cb[idx]; img[o + 1] = (byte)cg[idx]; img[o + 2] = (byte)cr[idx]; } } }
    return img; }
}
'@
}

function Convert-WorldMapChunk([byte[]]$ub, [int]$off = 4, [int]$tilesPerSide = 32, [int]$inner = 128, [int]$border = 4) { return , [VtBc1]::Build($ub, $off, $tilesPerSide, $inner, $border) }   # the comma keeps the 150 MB byte array from being unrolled into the pipeline