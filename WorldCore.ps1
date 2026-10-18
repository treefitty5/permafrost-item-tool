# WorldCore.ps1 - reads and rewrites the WORLD part of a Permafrost .pfs save (LevelStreamingData).
#
# Layout (verified on 9 saves, round trip is byte-exact):
#   blob  = int32 cellCount, then per cell:  FString cellName (int32 len incl NUL, text, NUL), int32 recordCount, records
#   record = 16-byte GUID, int32 fieldCount, fields;  field = int32 keyLen(incl NUL) key NUL, int32 valLen(incl NUL, 0 = empty) val NUL
# The same actors may also appear in the plain-text part of the save as  [BEGIN_OBJECT_SAVE?Guid>HEX?...?END_OBJECT_SAVE?  and
# [BEGIN_RUNTIME_DATA_SAVE?RuntimeDataPayload###>HEX?...?[END_RUNTIME_DATA_SAVE  where HEX is the record GUID with every 4-byte group reversed.

Add-Type -TypeDefinition @'
using System; using System.Collections.Generic; using System.Text; using System.IO;
public class WField { public byte[] Key; public byte[] Val; public string KeyText { get { return WorldBlob.L1.GetString(Key, 0, Key.Length - 1); } } }
public class WRec {
  public byte[] Guid = new byte[16]; public List<WField> Fields = new List<WField>();
  public string GuidHex { get { var sb = new StringBuilder(); foreach (var x in Guid) sb.Append(x.ToString("X2")); return sb.ToString(); } }
  // the form used by the plain-text copies: each 4-byte group reversed
  public string TextGuid { get { var sb = new StringBuilder(); for (int g = 0; g < 4; g++) for (int k = 3; k >= 0; k--) sb.Append(Guid[g * 4 + k].ToString("X2")); return sb.ToString(); } }
  public WField Find(string key) { foreach (var f in Fields) if (f.KeyText == key) return f; return null; }
  public string Get(string key) { var f = Find(key); if (f == null) return null; return f.Val.Length == 0 ? "" : WorldBlob.L1.GetString(f.Val, 0, f.Val.Length - 1); }
  public void Set(string key, string val) {
    byte[] v = val == null ? new byte[0] : AppendNul(WorldBlob.L1.GetBytes(val));
    var f = Find(key); if (f == null) { f = new WField(); f.Key = AppendNul(WorldBlob.L1.GetBytes(key)); Fields.Add(f); } f.Val = v; }
  public bool Remove(string key) { for (int i = 0; i < Fields.Count; i++) if (Fields[i].KeyText == key) { Fields.RemoveAt(i); return true; } return false; }
  static byte[] AppendNul(byte[] b) { var r = new byte[b.Length + 1]; Array.Copy(b, r, b.Length); return r; }
  public string Cls { get { var p = Get("ClassPathNote"); if (p == null) return ""; int i = p.LastIndexOf('.'); return i >= 0 ? p.Substring(i + 1) : p; } }
  public string ClsPath { get { return Get("ClassPathNote") ?? ""; } }
  public string Transform { get { return Get("ActorTransform") ?? ""; } }
  public string State { get { return Get("InteractionBase_InteractionState") ?? ""; } }
  public double[] Pos { get { var t = Transform; if (t.Length == 0) return null; var p = t.Split('|')[0].Split(','); if (p.Length < 3) return null;
      return new double[] { double.Parse(p[0], System.Globalization.CultureInfo.InvariantCulture), double.Parse(p[1], System.Globalization.CultureInfo.InvariantCulture), double.Parse(p[2], System.Globalization.CultureInfo.InvariantCulture) }; } }
  public WRec Clone() { var r = new WRec(); Array.Copy(Guid, r.Guid, 16); foreach (var f in Fields) { var n = new WField(); n.Key = (byte[])f.Key.Clone(); n.Val = (byte[])f.Val.Clone(); r.Fields.Add(n); } return r; }
}
public class WCell { public byte[] NameRaw; public string Name; public List<WRec> Recs = new List<WRec>(); }
public static class WorldBlob {
  public static readonly Encoding L1 = Encoding.GetEncoding(28591);
  public static List<WCell> Parse(byte[] b) {
    var cells = new List<WCell>(); int pos = 0; int gc = BitConverter.ToInt32(b, 0); pos = 4;
    if (gc < 0 || gc > 100000) throw new Exception("world blob: bad cell count " + gc);
    for (int g = 0; g < gc; g++) {
      var c = new WCell(); int nl = BitConverter.ToInt32(b, pos); if (nl < 1 || nl > 400) throw new Exception("world blob: bad cell name length at " + pos);
      c.NameRaw = new byte[nl]; Array.Copy(b, pos + 4, c.NameRaw, 0, nl); c.Name = L1.GetString(b, pos + 4, nl - 1); pos += 4 + nl;
      int rc = BitConverter.ToInt32(b, pos); pos += 4; if (rc < 0 || rc > 200000) throw new Exception("world blob: bad record count at " + pos);
      for (int i = 0; i < rc; i++) {
        var r = new WRec(); Array.Copy(b, pos, r.Guid, 0, 16); pos += 16; int n = BitConverter.ToInt32(b, pos); pos += 4;
        if (n < 0 || n > 80) throw new Exception("world blob: bad field count " + n + " in cell " + g + " record " + i);
        for (int f = 0; f < n; f++) {
          var fld = new WField(); int kl = BitConverter.ToInt32(b, pos); if (kl < 2 || kl > 120) throw new Exception("world blob: bad key length at " + pos);
          fld.Key = new byte[kl]; Array.Copy(b, pos + 4, fld.Key, 0, kl); pos += 4 + kl;
          int vl = BitConverter.ToInt32(b, pos); if (vl < 0 || pos + 4 + vl > b.Length) throw new Exception("world blob: bad value length at " + pos);
          fld.Val = new byte[vl]; Array.Copy(b, pos + 4, fld.Val, 0, vl); pos += 4 + vl; r.Fields.Add(fld);
        }
        c.Recs.Add(r);
      }
      cells.Add(c);
    }
    if (pos != b.Length) throw new Exception("world blob: parsed " + pos + " of " + b.Length + " bytes");
    return cells;
  }
  public static byte[] RecBytes(WRec r) {
    var ms = new MemoryStream(); var w = new BinaryWriter(ms); w.Write(r.Guid); w.Write(r.Fields.Count);
    foreach (var f in r.Fields) { w.Write(f.Key.Length); w.Write(f.Key); w.Write(f.Val.Length); w.Write(f.Val); }
    w.Flush(); return ms.ToArray();
  }
  public static string RecHash(WRec r) { return Convert.ToBase64String(System.Security.Cryptography.MD5.Create().ComputeHash(RecBytes(r))); }
  public static byte[] Serialize(List<WCell> cells) {
    var ms = new MemoryStream(); var w = new BinaryWriter(ms); w.Write(cells.Count);
    foreach (var c in cells) {
      w.Write(c.NameRaw.Length); w.Write(c.NameRaw); w.Write(c.Recs.Count);
      foreach (var r in c.Recs) { w.Write(r.Guid); w.Write(r.Fields.Count); foreach (var f in r.Fields) { w.Write(f.Key.Length); w.Write(f.Key); w.Write(f.Val.Length); w.Write(f.Val); } }
    }
    w.Flush(); return ms.ToArray();
  }
}
'@

$script:WL1 = [Text.Encoding]::Latin1

# Reads the world blob out of a save's text (needs Get-BlobSection from SaveCore.ps1)
function Read-WorldCells([string]$saveText) {
  $sec = Get-BlobSection $saveText 'LevelStreamingData'
  return @{ Sec = $sec; Cells = [WorldBlob]::Parse($sec.Bytes) }
}
function Test-WorldRoundTrip([string]$saveText) {
  $w = Read-WorldCells $saveText; $back = [WorldBlob]::Serialize($w.Cells)
  if ($back.Length -ne $w.Sec.Bytes.Length) { return $false }
  for ($i = 0; $i -lt $back.Length; $i++) { if ($back[$i] -ne $w.Sec.Bytes[$i]) { return $false } }
  return $true
}
