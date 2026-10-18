using System.Net.Http;

namespace HistoryLib.Windows.Core;

public sealed class FaviconStore
{
    private readonly string _root = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "HistoryLib", "favicons");
    private readonly HttpClient _http = new() { Timeout = TimeSpan.FromSeconds(5) };
    private readonly string _enabledFile = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "HistoryLib", "favicons.enabled");
    public bool IsEnabled => !File.Exists(_enabledFile) || File.ReadAllText(_enabledFile) != "0";
    public void SetEnabled(bool enabled) { Directory.CreateDirectory(Path.GetDirectoryName(_enabledFile)!); File.WriteAllText(_enabledFile, enabled ? "1" : "0"); }
    public async Task<string?> GetAsync(string url, CancellationToken cancellationToken = default)
    {
        if (!IsEnabled || !Uri.TryCreate(url, UriKind.Absolute, out var uri) || string.IsNullOrWhiteSpace(uri.Host)) return null;
        Directory.CreateDirectory(_root); var path = Path.Combine(_root, Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(uri.Host))).ToLowerInvariant() + ".ico");
        if (File.Exists(path)) return path;
        try { using var response = await _http.GetAsync($"{uri.Scheme}://{uri.Host}/favicon.ico", cancellationToken); if (!response.IsSuccessStatusCode) return null; var bytes = await response.Content.ReadAsByteArrayAsync(cancellationToken); if (bytes.Length == 0 || bytes.Length > 512 * 1024) return null; await File.WriteAllBytesAsync(path, bytes, cancellationToken); return path; } catch { return null; }
    }
    public void Clear() { if (Directory.Exists(_root)) Directory.Delete(_root, true); }
}
