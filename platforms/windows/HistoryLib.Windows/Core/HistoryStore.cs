using System.Text.Json;
using System.IO.Compression;

namespace HistoryLib.Windows.Core;

public sealed class HistoryStore
{
    private readonly string _file = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "HistoryLib", "history.json");
    private readonly object _gate = new();
    private List<HistoryRecord> _records = [];
    public IReadOnlyList<HistoryRecord> Records { get { lock (_gate) return _records.ToArray(); } }
    public HistoryStore() { Load(); }
    private void Load()
    {
        try { if (File.Exists(_file)) _records = JsonSerializer.Deserialize<List<HistoryRecord>>(File.ReadAllText(_file)) ?? []; }
        catch { _records = []; }
    }
    private void Save() { Directory.CreateDirectory(Path.GetDirectoryName(_file)!); File.WriteAllText(_file, JsonSerializer.Serialize(_records, new JsonSerializerOptions { WriteIndented = true })); }
    public Summary GetSummary()
    {
        var r = Records; if (r.Count == 0) return new(0, 0, 0, 0, []);
        var first = r.Min(x => x.VisitedAt.Date); var last = r.Max(x => x.VisitedAt.Date);
        var days = Math.Max(1, (last - first).Days + 1);
        var months = Math.Max(1, (last.Year - first.Year) * 12 + last.Month - first.Month + 1);
        var years = Math.Max(1, last.Year - first.Year + 1);
        var top = r.GroupBy(x => Uri.TryCreate(x.Url, UriKind.Absolute, out var u) && !string.IsNullOrWhiteSpace(u.Host) ? u.Host.Trim().ToLowerInvariant() : "(unknown)").Select(g => (Host: g.Key, Count: g.Count())).OrderByDescending(x => x.Count).ThenBy(x => x.Host).Take(10).ToArray();
        return new(r.Count, (double)r.Count / days, (double)r.Count / months, (double)r.Count / years, top);
    }
    public IReadOnlyList<HistoryRecord> Search(string query) => string.IsNullOrWhiteSpace(query) ? Records : Records.Where(x => x.Url.Contains(query, StringComparison.OrdinalIgnoreCase) || x.Title.Contains(query, StringComparison.OrdinalIgnoreCase)).ToArray();
    public void Delete(HistoryRecord record) { lock (_gate) { _records.RemoveAll(x => x.UniqueKey == record.UniqueKey); Save(); } }
    public void Clear() { lock (_gate) { _records.Clear(); Save(); } }
    public async Task<ImportReport> ImportAsync(string path, CancellationToken cancellationToken = default, string? password = null)
    {
        if (File.Exists(path) && Path.GetExtension(path).Equals(".hlz", StringComparison.OrdinalIgnoreCase))
        {
            await using var probe = File.OpenRead(path); var magic = new byte[6]; _ = await probe.ReadAsync(magic, cancellationToken);
            if (System.Text.Encoding.ASCII.GetString(magic) == "HLZENC") { if (string.IsNullOrEmpty(password)) throw new InvalidDataException("This archive is password protected."); var decrypted = HlzEncryption.Decrypt(await File.ReadAllBytesAsync(path, cancellationToken), password); var decryptedPath = Path.Combine(Path.GetTempPath(), "historylib-dec-" + Guid.NewGuid().ToString("N") + ".hlz"); try { await File.WriteAllBytesAsync(decryptedPath, decrypted, cancellationToken); return await ImportAsync(decryptedPath, cancellationToken); } finally { try { File.Delete(decryptedPath); } catch { } } }
        }
        var files = File.Exists(path) ? [path] : Directory.Exists(path) ? Directory.EnumerateFiles(path, "*.json", SearchOption.AllDirectories).Concat(Directory.EnumerateFiles(path, "*.jsonl", SearchOption.AllDirectories)).ToArray() : [];
        if (Path.GetExtension(path).Equals(".zip", StringComparison.OrdinalIgnoreCase) || Path.GetExtension(path).Equals(".hlz", StringComparison.OrdinalIgnoreCase))
        {
            var temp = Path.Combine(Path.GetTempPath(), "historylib-" + Guid.NewGuid().ToString("N")); Directory.CreateDirectory(temp);
            try { ZipFile.ExtractToDirectory(path, temp); ValidateHlzDirectory(temp); return await ImportAsync(temp, cancellationToken); } finally { try { Directory.Delete(temp, true); } catch { } }
        }
        var errors = new List<string>(); var imported = 0; var merged = 0; var skipped = 0; var validFiles = 0; var format = "Unknown";
        foreach (var file in files)
        {
            cancellationToken.ThrowIfCancellationRequested();
            try
            {
                if (file.EndsWith(".jsonl", StringComparison.OrdinalIgnoreCase))
                {
                    format = "HistoryLib"; validFiles++;
                    foreach (var line in await File.ReadAllLinesAsync(file, cancellationToken))
                    {
                        if (string.IsNullOrWhiteSpace(line)) continue;
                        using var lineDoc = JsonDocument.Parse(line); var e = lineDoc.RootElement;
                        if (!e.TryGetProperty("u", out var u) || !e.TryGetProperty("ts", out var ts) || !long.TryParse(ts.ToString(), out var t)) { skipped++; continue; }
                        var url = u.GetString()?.Trim(); if (string.IsNullOrWhiteSpace(url)) { skipped++; continue; }
                        var browser = GetString(e, "sb"); if (string.IsNullOrWhiteSpace(browser)) browser = "Safari";
                        AddRecord(url, t, GetString(e, "t"), GetInt(e, "vc", 1), browser, Path.GetFileName(file), ref imported, ref merged);
                    }
                    continue;
                }
                using var doc = JsonDocument.Parse(await File.ReadAllTextAsync(file, cancellationToken));
                var root = doc.RootElement; IEnumerable<JsonElement> entries;
                if (root.TryGetProperty("metadata", out var meta) && meta.TryGetProperty("browser_name", out var bn) && bn.GetString()?.Equals("Safari", StringComparison.OrdinalIgnoreCase) == true && root.TryGetProperty("history", out var safari)) { format = "Safari"; entries = safari.EnumerateArray(); }
                else if (root.TryGetProperty("Browser History", out var chrome)) { format = "Chrome Takeout"; entries = chrome.EnumerateArray(); }
                else if (root.TryGetProperty("records", out var own)) { format = "HistoryLib"; entries = own.EnumerateArray(); }
                else { continue; }
                validFiles++;
                foreach (var e in entries)
                {
                    if (!e.TryGetProperty("url", out var urlNode) || !e.TryGetProperty("time_usec", out var timeNode) || !long.TryParse(timeNode.ToString(), out var time)) { skipped++; continue; }
                    var url = urlNode.GetString()?.Trim(); if (string.IsNullOrWhiteSpace(url)) { skipped++; continue; }
                    var browser = format == "Safari" ? "Safari" : format.StartsWith("Chrome") ? "Chrome" : "HistoryLib";
                    AddRecord(url, time, GetString(e, "title"), GetInt(e, "visit_count", 1), browser, Path.GetFileName(file), ref imported, ref merged);
                }
            }
            catch (Exception ex) { errors.Add(Path.GetFileName(file) + ": " + ex.Message); }
        }
        lock (_gate) Save();
        return new(format, files.Length, validFiles, imported, merged, skipped, errors);
    }
    public async Task ExportSafariAsync(string path)
    {
        var payload = new { metadata = new { browser_name = "Safari", data_type = "history", schema_version = 1 }, history = Records.OrderBy(x => x.VisitedAtUsec).Select(x => new { url = x.Url, title = x.Title, time_usec = x.VisitedAtUsec, visit_count = x.VisitCount }).ToArray() };
        await File.WriteAllTextAsync(path, JsonSerializer.Serialize(payload, new JsonSerializerOptions { WriteIndented = true }));
    }
    public async Task ExportHistoryLibAsync(string path, string? password = null)
    {
        var temp = Path.Combine(Path.GetTempPath(), "historylib-export-" + Guid.NewGuid().ToString("N")); Directory.CreateDirectory(temp);
        try
        {
            var records = Records.OrderBy(x => x.VisitedAtUsec).ToArray(); var chunkPath = Path.Combine(temp, "chunks"); Directory.CreateDirectory(chunkPath);
            var lines = records.Select(x => JsonSerializer.Serialize(new { u = x.Url, ts = x.VisitedAtUsec, t = x.Title, vc = x.VisitCount, uk = x.UniqueKey, sb = x.SourceBrowser, ia = x.ImportedAtUsec, rt = x.RawTimeUsec, sf = x.SourceFileName })).ToArray();
            var bytes = System.Text.Encoding.UTF8.GetBytes(string.Join("\n", lines) + (lines.Length > 0 ? "\n" : "")); var chunkName = "chunks/00000001.jsonl";
            await File.WriteAllBytesAsync(Path.Combine(chunkPath, "00000001.jsonl"), bytes);
            var sha = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(bytes)).ToLowerInvariant();
            var manifest = new { format = "historylib", format_version = 1, created_at_usec = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() * 1000, app_name = "HistoryLib", app_version = "1.4", record_schema = "hl_record_v1", record_count = records.Length, chunk_count = records.Length == 0 ? 0 : 1, time_range_usec = records.Length == 0 ? null : new { min = records.Min(x => x.VisitedAtUsec), max = records.Max(x => x.VisitedAtUsec) }, chunk_encoding = "jsonl", chunk_target_records = 50000, feature_flags = Array.Empty<string>(), indexes = new { chunks = "indexes/chunks.json" } };
            Directory.CreateDirectory(Path.Combine(temp, "indexes")); await File.WriteAllTextAsync(Path.Combine(temp, "manifest.json"), JsonSerializer.Serialize(manifest));
            var index = records.Length == 0 ? Array.Empty<object>() : new object[] { new { id = 1, path = chunkName, record_count = records.Length, min_ts = records.Min(x => x.VisitedAtUsec), max_ts = records.Max(x => x.VisitedAtUsec), sha256 = sha } };
            await File.WriteAllTextAsync(Path.Combine(temp, "indexes", "chunks.json"), JsonSerializer.Serialize(index));
            var plainPath = Path.Combine(Path.GetTempPath(), "historylib-plain-" + Guid.NewGuid().ToString("N") + ".hlz"); ZipFile.CreateFromDirectory(temp, plainPath, CompressionLevel.Optimal, false); var plain = await File.ReadAllBytesAsync(plainPath); try { if (string.IsNullOrEmpty(password)) await File.WriteAllBytesAsync(path, plain); else await File.WriteAllBytesAsync(path, HlzEncryption.Encrypt(plain, password)); } finally { try { File.Delete(plainPath); } catch { } }
        }
        finally { try { Directory.Delete(temp, true); } catch { } }
    }
    private void AddRecord(string url, long time, string title, int count, string browser, string sourceFile, ref int imported, ref int merged)
    {
        var normalizedBrowser = browser.Trim().ToLowerInvariant(); var key = Normalize(url) + "|" + (time / 1_000_000) + "|" + normalizedBrowser;
        lock (_gate) { var existing = _records.FirstOrDefault(x => x.UniqueKey == key || (x.UniqueKey.StartsWith(Normalize(url) + "|") && Math.Abs(x.VisitedAtUsec - time) <= 1_000_000)); if (existing != null) { existing.VisitCount += Math.Max(1, count); if (string.IsNullOrEmpty(existing.Title)) existing.Title = title; merged++; } else { _records.Add(new HistoryRecord { UniqueKey = key, Url = url, Title = title, VisitedAtUsec = time, RawTimeUsec = time, VisitCount = Math.Max(1, count), SourceBrowser = browser, SourceFileName = sourceFile, ImportedAtUsec = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() * 1000 }); imported++; } }
    }
    private static void ValidateHlzDirectory(string root)
    {
        var manifestPath = Path.Combine(root, "manifest.json"); if (!File.Exists(manifestPath)) return;
        using var manifest = JsonDocument.Parse(File.ReadAllText(manifestPath)); var m = manifest.RootElement;
        if (!m.TryGetProperty("format", out var f) || !string.Equals(f.GetString(), "historylib", StringComparison.OrdinalIgnoreCase) || !m.TryGetProperty("format_version", out var v) || v.GetInt32() != 1) throw new InvalidDataException("Unsupported HistoryLib archive.");
        var indexPath = Path.Combine(root, "indexes", "chunks.json"); if (!File.Exists(indexPath)) throw new InvalidDataException("HistoryLib archive is missing its chunk index.");
        using var index = JsonDocument.Parse(File.ReadAllText(indexPath)); var chunks = index.RootElement.EnumerateArray().ToArray(); var expected = m.TryGetProperty("chunk_count", out var cc) ? cc.GetInt32() : -1; if (expected != chunks.Length) throw new InvalidDataException("HistoryLib chunk count is inconsistent.");
        long records = 0; var ids = new HashSet<int>(); var paths = new HashSet<string>(StringComparer.OrdinalIgnoreCase); foreach (var c in chunks) { var id = c.GetProperty("id").GetInt32(); if (id < 1 || !ids.Add(id) || !paths.Add(c.GetProperty("path").GetString() ?? "")) throw new InvalidDataException("HistoryLib chunk index is not contiguous."); var rel = c.GetProperty("path").GetString() ?? ""; var full = Path.GetFullPath(Path.Combine(root, rel.Replace('/', Path.DirectorySeparatorChar))); if (!full.StartsWith(Path.GetFullPath(root) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase) || !File.Exists(full)) throw new InvalidDataException("HistoryLib chunk path is invalid."); var bytes = File.ReadAllBytes(full); var sha = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(bytes)).ToLowerInvariant(); if (!string.Equals(sha, c.GetProperty("sha256").GetString(), StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("HistoryLib chunk checksum mismatch."); long chunkRecords = 0; foreach (var line in File.ReadLines(full)) { if (string.IsNullOrWhiteSpace(line)) throw new InvalidDataException("HistoryLib chunk contains a blank line."); using var record = JsonDocument.Parse(line); if (!record.RootElement.TryGetProperty("u", out var u) || string.IsNullOrWhiteSpace(u.GetString()) || !record.RootElement.TryGetProperty("ts", out var ts) || !long.TryParse(ts.ToString(), out _)) throw new InvalidDataException("HistoryLib chunk contains an invalid record."); chunkRecords++; } if (chunkRecords != c.GetProperty("record_count").GetInt64()) throw new InvalidDataException("HistoryLib chunk record count is inconsistent."); records += chunkRecords; }
        if (ids.Count > 0 && !ids.SetEquals(Enumerable.Range(1, ids.Count))) throw new InvalidDataException("HistoryLib chunk ids are not contiguous.");
        if (m.TryGetProperty("record_count", out var rc) && rc.GetInt64() != records) throw new InvalidDataException("HistoryLib record count is inconsistent.");
    }
    private static string Normalize(string url) { if (!Uri.TryCreate(url.Trim(), UriKind.Absolute, out var u)) return url.Trim().ToLowerInvariant(); var b = new UriBuilder(u) { Fragment = "" }; if ((u.Scheme == "http" && u.Port == 80) || (u.Scheme == "https" && u.Port == 443)) b.Port = -1; var s = b.Uri.ToString().TrimEnd('/'); return s.Length == b.Uri.GetLeftPart(UriPartial.Authority).Length ? s + "/" : s; }
    private static string GetString(JsonElement e, string name) => e.TryGetProperty(name, out var n) ? n.GetString() ?? "" : "";
    private static int GetInt(JsonElement e, string name, int d) => e.TryGetProperty(name, out var n) && int.TryParse(n.ToString(), out var v) ? v : d;
}
