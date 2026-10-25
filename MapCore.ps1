# MapCore.ps1 - reads the ORIGINAL actor layout of the world from FModel's raw export of the map cells
# (Maps\PF_Worldmap_v2\_Generated_\<cell id>.umap, zen packages; no mappings file needed for what we read).
# Each cell file lists its actors as exports of the PersistentLevel; an actor's transform is stored in its root component
# export as unversioned properties: 2-byte fragment header (skip count 5 = RelativeLocation first), then FVector/FRotator/FVector doubles.
# Verified: moon rock boulder transforms equal the save's ActorTransform to 6 decimals (Z can differ because the game settles objects).
if (-not ('MapCells' -as [type])) {
Add-Type -TypeDefinition @'
using System; using System.Collections.Generic; using System.IO; using System.Text;
public class MapActor { public string Cell, Name, Class; public double X, Y, Z, Pitch, Yaw, Roll, SX = 1, SY = 1, SZ = 1; public bool HasTransform; public int RootSize; }
public static class MapCells {
  static string[] ReadNames(byte[] b, out int off0) {
    off0 = -1;
    for (int off = 0; off <= 300 && off + 16 < b.Length; off += 4) {
      uint cnt = BitConverter.ToUInt32(b, off); ulong alg = BitConverter.ToUInt64(b, off + 8);
      if (alg == 3244556288UL && cnt > 0 && cnt < 200000) {
        int hdr = off + 16 + (int)cnt * 8; int sp = hdr + (int)cnt * 2; var n = new string[cnt];
        for (int i = 0; i < cnt; i++) { int h0 = b[hdr + i * 2], h1 = b[hdr + i * 2 + 1]; int len = ((h0 & 0x7F) << 8) | h1;
          if ((h0 & 0x80) != 0) { n[i] = Encoding.Unicode.GetString(b, sp, len * 2); sp += len * 2; } else { n[i] = Encoding.ASCII.GetString(b, sp, len); sp += len; } }
        off0 = off; return n; } }
    return null;
  }
  public static List<MapActor> Read(string file) {
    var res = new List<MapActor>(); var b = File.ReadAllBytes(file); int o0; var nm = ReadNames(b, out o0); if (nm == null) return res;
    int expOff = BitConverter.ToInt32(b, 32), bundleOff = BitConverter.ToInt32(b, 36); int n = (bundleOff - expOff) / 72; if (n <= 0 || n > 200000) return res;
    var off = new long[n]; var size = new long[n]; var name = new string[n]; var outer = new ulong[n];
    long last = 0;
    for (int i = 0; i < n; i++) { int o = expOff + i * 72; off[i] = (long)BitConverter.ToUInt64(b, o); size[i] = (long)BitConverter.ToUInt64(b, o + 8);
      uint ni = BitConverter.ToUInt32(b, o + 16); uint nn = BitConverter.ToUInt32(b, o + 20); name[i] = (ni < nm.Length ? nm[ni] : "?") + (nn > 0 ? "_" + (nn - 1).ToString() : ""); outer[i] = BitConverter.ToUInt64(b, o + 24); if (off[i] + size[i] > last) last = off[i] + size[i]; }
    long dataStart = b.Length - last;
    int level = -1; for (int i = 0; i < n; i++) if (name[i] == "PersistentLevel") { level = i; break; }
    if (level < 0) return res;
    string cell = Path.GetFileNameWithoutExtension(file);
    var rootOf = new Dictionary<int, int>();
    for (int i = 0; i < n; i++) { if (outer[i] < (ulong)n && (name[i] == "Root" || name[i] == "DefaultSceneRoot")) { int a = (int)outer[i]; if (!rootOf.ContainsKey(a)) rootOf[a] = i; } }
    for (int i = 0; i < n; i++) {
      if (outer[i] != (ulong)level) continue; if (i == level) continue;
      var a = new MapActor(); a.Cell = cell; a.Name = name[i]; a.Class = name[i];
      int r; if (rootOf.TryGetValue(i, out r)) {
        long p = dataStart + off[r]; long end = p + size[r]; a.RootSize = (int)size[r];
        // fragment header(s)
        int idx = 0; var values = new List<int>(); bool ok = true; int guard = 0;
        while (true) { if (p + 2 > end || guard++ > 8) { ok = false; break; } int v = b[p] | (b[p + 1] << 8); p += 2; int skip = v & 0x7F; bool zero = (v & 0x80) != 0; bool isLast = (v & 0x100) != 0; int num = v >> 9;
          if (zero) { ok = false; break; } idx += skip; for (int k = 0; k < num; k++) values.Add(idx + k); idx += num; if (isLast) break; }
        if (ok) { foreach (int pi in values) { if (pi < 5 || pi > 7) break; if (p + 24 > end) break; double x = BitConverter.ToDouble(b, (int)p), y = BitConverter.ToDouble(b, (int)p + 8), z = BitConverter.ToDouble(b, (int)p + 16); p += 24;
            if (pi == 5) { a.X = x; a.Y = y; a.Z = z; a.HasTransform = true; } else if (pi == 6) { a.Pitch = x; a.Yaw = y; a.Roll = z; } else { a.SX = x; a.SY = y; a.SZ = z; } } }
      }
      res.Add(a);
    }
    return res;
  }
}
'@
}
