using System.Text.Json;

namespace HistoryLib.Windows.Core;

public sealed class WindowsSettingsStore
{
    private readonly string _path = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "HistoryLib", "settings.json");
    private Dictionary<string, JsonElement> _values = new(StringComparer.Ordinal);
    public WindowsSettingsStore() { try { if (File.Exists(_path)) _values = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(File.ReadAllText(_path)) ?? _values; } catch { _values = new(StringComparer.Ordinal); } }
    public bool GetBool(string key, bool fallback) => _values.TryGetValue(key, out var value) && value.ValueKind is JsonValueKind.True or JsonValueKind.False ? value.GetBoolean() : fallback;
    public int GetInt(string key, int fallback) => _values.TryGetValue(key, out var value) && value.TryGetInt32(out var result) ? result : fallback;
    public void Set(string key, bool value) { _values[key] = JsonSerializer.SerializeToElement(value); Save(); }
    public void Set(string key, int value) { _values[key] = JsonSerializer.SerializeToElement(value); Save(); }
    private void Save() { Directory.CreateDirectory(Path.GetDirectoryName(_path)!); File.WriteAllText(_path, JsonSerializer.Serialize(_values, new JsonSerializerOptions { WriteIndented = true })); }
}
