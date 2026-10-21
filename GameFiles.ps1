# Reads files straight out of the game's own packed container (Paks\*.utoc + *.ucas), no FModel needed.
# Used by Build-IconsFromGame.ps1. Read-only: it never writes to the game folder.
# The container is Oodle-compressed, so it needs oodle-data-shared.dll (the same free decompressor FModel uses);
# Get-OodleDll finds one or downloads it (with the user's consent) into the tool's own folder.

if (-not ('IoStoreReader' -as [type])) {
Add-Type -TypeDefinition @'
using System; using System.Collections.Generic; using System.IO; using System.Runtime.InteropServices; using System.Text;

public static class OodleNative {
  [DllImport("kernel32", SetLastError = true, CharSet = CharSet.Unicode)] static extern IntPtr LoadLibraryW(string path);
  [DllImport("kernel32", SetLastError = true)] static extern IntPtr GetProcAddress(IntPtr h, string name);
  [UnmanagedFunctionPointer(CallingConvention.Cdecl)]
  delegate long DecompressFn(byte[] src, long srcSize, byte[] dst, long dstSize, int fuzzSafe, int checkCrc, int verbosity,
                             IntPtr decBufBase, long decBufSize, IntPtr cb, IntPtr cbUser, IntPtr decMem, long decMemSize, int threadPhase);
  static DecompressFn fn;
  public static void Load(string dllPath) {
    IntPtr h = LoadLibraryW(dllPath); if (h == IntPtr.Zero) throw new Exception("could not load " + dllPath + " (error " + Marshal.GetLastWin32Error() + ")");
    IntPtr p = GetProcAddress(h, "OodleLZ_Decompress"); if (p == IntPtr.Zero) throw new Exception("OodleLZ_Decompress not found in " + dllPath);
    fn = (DecompressFn)Marshal.GetDelegateForFunctionPointer(p, typeof(DecompressFn));
  }
  public static bool Ready { get { return fn != null; } }
  public static long Decompress(byte[] src, int srcLen, byte[] dst, int dstLen) {
    return fn(src, srcLen, dst, dstLen, 1, 0, 0, IntPtr.Zero, 0, IntPtr.Zero, IntPtr.Zero, IntPtr.Zero, 0, 3);
  }
}

public class IoStoreReader : IDisposable {
  public string UtocPath, UcasPath; FileStream ucas;
  public int EntryCount, BlockCount, BlockSize; public uint Version, Flags;
  byte[] chunkIds;            // EntryCount * 12
  long[] chunkOffset, chunkLength;
  long[] blkOffset; int[] blkComp, blkRaw; byte[] blkMethod;
  public Dictionary<string, int> Paths = new Dictionary<string, int>();   // lower-case path (no mount point) -> chunk index
  public string MountPoint = "";

  public IoStoreReader(string utoc) {
    UtocPath = utoc; UcasPath = Path.ChangeExtension(utoc, ".ucas");
    byte[] b = File.ReadAllBytes(utoc);
    if (Encoding.ASCII.GetString(b, 0, 16) != "-==--==--==--==-") throw new Exception("not an IoStore table of contents");
    Version = b[16]; if (Version < 5) throw new Exception("unsupported container version " + Version);
    uint headerSize = BitConverter.ToUInt32(b, 20); EntryCount = (int)BitConverter.ToUInt32(b, 24); BlockCount = (int)BitConverter.ToUInt32(b, 28);
    int mcount = (int)BitConverter.ToUInt32(b, 36), mlen = (int)BitConverter.ToUInt32(b, 40); BlockSize = (int)BitConverter.ToUInt32(b, 44);
    int dirSize = (int)BitConverter.ToUInt32(b, 48); Flags = b[80];
    if ((Flags & 2) != 0) throw new Exception("this container is encrypted (not supported)");
    int seeds = (int)BitConverter.ToUInt32(b, 84), noHash = (int)BitConverter.ToUInt32(b, 96);
    int p = (int)headerSize;
    chunkIds = new byte[EntryCount * 12]; Array.Copy(b, p, chunkIds, 0, chunkIds.Length); p += chunkIds.Length;
    chunkOffset = new long[EntryCount]; chunkLength = new long[EntryCount];
    for (int i = 0; i < EntryCount; i++) {
      long o = 0, l = 0; for (int k = 0; k < 5; k++) { o = (o << 8) | b[p + k]; l = (l << 8) | b[p + 5 + k]; }
      chunkOffset[i] = o; chunkLength[i] = l; p += 10; }
    p += seeds * 4 + noHash * 4;
    blkOffset = new long[BlockCount]; blkComp = new int[BlockCount]; blkRaw = new int[BlockCount]; blkMethod = new byte[BlockCount];
    for (int i = 0; i < BlockCount; i++) {
      blkOffset[i] = (long)(BitConverter.ToUInt64(b, p) & 0xFFFFFFFFFFUL);
      blkComp[i] = (int)(BitConverter.ToUInt32(b, p + 4) >> 8); uint t = BitConverter.ToUInt32(b, p + 8);
      blkRaw[i] = (int)(t & 0xFFFFFF); blkMethod[i] = (byte)(t >> 24); p += 12; }
    p += mcount * mlen;
    if ((Flags & 4) != 0) p += BlockCount * 20 + 0;        // signed containers carry hashes; not expected here
    if ((Flags & 8) != 0 && dirSize > 0) ReadDirectoryIndex(b, p, dirSize);
    ucas = new FileStream(UcasPath, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
  }

  static string ReadFString(byte[] b, ref int p) {
    int n = BitConverter.ToInt32(b, p); p += 4; if (n == 0) return "";
    if (n < 0) { n = -n; string s = Encoding.Unicode.GetString(b, p, (n - 1) * 2); p += n * 2; return s; }
    string a = Encoding.ASCII.GetString(b, p, n - 1); p += n; return a;
  }
  void ReadDirectoryIndex(byte[] b, int p, int size) {
    MountPoint = ReadFString(b, ref p);
    int nd = BitConverter.ToInt32(b, p); p += 4; int dp = p; p += nd * 16;
    int nf = BitConverter.ToInt32(b, p); p += 4; int fp = p; p += nf * 12;
    int ns = BitConverter.ToInt32(b, p); p += 4; string[] names = new string[ns]; for (int i = 0; i < ns; i++) names[i] = ReadFString(b, ref p);
    Walk(b, dp, fp, names, 0, "");
  }
  void Walk(byte[] b, int dp, int fp, string[] names, int dir, string prefix) {
    uint NONE = 0xFFFFFFFF;
    int o = dp + dir * 16; uint first = BitConverter.ToUInt32(b, o + 4), sib = BitConverter.ToUInt32(b, o + 8), file = BitConverter.ToUInt32(b, o + 12);
    for (uint f = file; f != NONE; ) { int q = fp + (int)f * 12; uint nm = BitConverter.ToUInt32(b, q), next = BitConverter.ToUInt32(b, q + 4), ud = BitConverter.ToUInt32(b, q + 8);
      Paths[(prefix + names[nm]).ToLowerInvariant()] = (int)ud; f = next; }
    for (uint c = first; c != NONE; ) { int q = dp + (int)c * 16; uint nm = BitConverter.ToUInt32(b, q), cs = BitConverter.ToUInt32(b, q + 8);
      Walk(b, dp, fp, names, (int)c, prefix + names[nm] + "/"); c = cs; }
  }

  // the chunk that carries the same package's bulk data (.ubulk): same 8-byte package id, same index, another chunk type
  public int FindSibling(int index, byte[] wantTypes) {
    int baseO = index * 12;
    foreach (byte ty in wantTypes) for (int i = 0; i < EntryCount; i++) { if (i == index) continue; int o = i * 12; bool same = true;
      for (int k = 0; k < 10 && same; k++) if (chunkIds[o + k] != chunkIds[baseO + k]) same = false;
      if (same && chunkIds[o + 11] == ty) return i; }
    return -1;
  }
  public byte[] ChunkId(int index) { byte[] r = new byte[12]; Array.Copy(chunkIds, index * 12, r, 0, 12); return r; }

  public byte[] ReadChunk(int index) {
    long off = chunkOffset[index], len = chunkLength[index]; byte[] result = new byte[len];
    int first = (int)(off / BlockSize), last = (int)((off + len - 1) / BlockSize); long written = 0; long skip = off - (long)first * BlockSize;
    for (int blk = first; blk <= last; blk++) {
      byte[] comp = new byte[blkComp[blk]]; ucas.Position = blkOffset[blk]; int got = 0; while (got < comp.Length) { int r = ucas.Read(comp, got, comp.Length - got); if (r <= 0) throw new Exception("unexpected end of .ucas"); got += r; }
      byte[] raw;
      if (blkMethod[blk] == 0) raw = comp;
      else { if (!OodleNative.Ready) throw new Exception("Oodle decompressor not loaded"); raw = new byte[blkRaw[blk]]; long n = OodleNative.Decompress(comp, comp.Length, raw, raw.Length); if (n != raw.Length) throw new Exception("Oodle returned " + n + " for a block of " + raw.Length); }
      long take = Math.Min(raw.Length - skip, len - written); Array.Copy(raw, skip, result, written, take); written += take; skip = 0;
    }
    return result;
  }
  public void Dispose() { if (ucas != null) ucas.Dispose(); }
}
'@
}

# finds oodle-data-shared.dll: the tool folder first, then a per-user folder, then a copy FModel left in Downloads; $null if none
function Find-OodleDll {
  foreach ($p in @((Join-Path $PSScriptRoot 'oodle-data-shared.dll'), (Join-Path $env:LOCALAPPDATA 'PermafrostItemTool\oodle-data-shared.dll'))) { if (Test-Path -LiteralPath $p) { return $p } }
  $dl = Join-Path $env:USERPROFILE 'Downloads'
  if (Test-Path -LiteralPath $dl) { $f = Get-ChildItem -Path $dl -Filter 'oodle-data-shared.dll' -Recurse -Depth 4 -ErrorAction SilentlyContinue | Select-Object -First 1; if ($f) { return $f.FullName } }
  return $null
}
function Open-GameContainer([string]$utocPath, [string]$oodleDll) {
  if (-not [OodleNative]::Ready) { if (-not $oodleDll) { throw 'No Oodle decompressor given.' }; [OodleNative]::Load($oodleDll) }
  return New-Object IoStoreReader($utocPath)
}

# the game's Paks table of contents under a Steam game folder (...\steamapps\common\Permafrost)
function Get-GameUtoc([string]$gameDir) {
  foreach ($rel in 'Permafrost\Content\Paks\Permafrost-Windows.utoc', 'Content\Paks\Permafrost-Windows.utoc') { $p = Join-Path $gameDir $rel; if (Test-Path -LiteralPath $p) { return $p } }
  return $null
}

# '/Game/Folder/T_Name' (or '/Game/Folder/T_Name.T_Name') -> decoded System.Drawing.Bitmap, or $null. Needs TextureDecode.ps1 loaded.
function Get-GameBitmap($reader, [string]$gamePath) {
  $rel = ($gamePath -replace '\.[^./]*$', '' -replace '^/Game/', 'permafrost/content/').ToLowerInvariant()
  if (-not $reader.Paths.ContainsKey("$rel.uasset")) { return $null }
  [byte[]]$ua = $reader.ReadChunk($reader.Paths["$rel.uasset"])
  [byte[]]$ub = $null; if ($reader.Paths.ContainsKey("$rel.ubulk")) { $ub = $reader.ReadChunk($reader.Paths["$rel.ubulk"]) }
  return Convert-TextureBytesToBitmap $ua $ub
}
