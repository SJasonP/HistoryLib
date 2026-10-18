using System.Text.Json.Serialization;

namespace HistoryLib.Windows.Core;

public sealed class HistoryRecord
{
    public string UniqueKey { get; set; } = "";
    public string Url { get; set; } = "";
    public string Title { get; set; } = "";
    public long VisitedAtUsec { get; set; }
    public int VisitCount { get; set; } = 1;
    public string SourceBrowser { get; set; } = "";
    public string SourceFileName { get; set; } = "";
    public long RawTimeUsec { get; set; }
    public string? SourceUrl { get; set; }
    public long? SourceTimeUsec { get; set; }
    public string? DestinationUrl { get; set; }
    public long? DestinationTimeUsec { get; set; }
    public bool? LatestVisitWasHttpGet { get; set; }
    public long ImportedAtUsec { get; set; }
    [JsonIgnore] public DateTime VisitedAt => DateTimeOffset.FromUnixTimeMilliseconds(VisitedAtUsec / 1000).LocalDateTime;
    [JsonIgnore] public string? FaviconPath { get; set; }
}

public sealed record ImportReport(string Format, int ScannedFiles, int ValidFiles, int Imported, int Merged, int Skipped, IReadOnlyList<string> Errors);
public sealed record Summary(int TotalRecords, double AverageDay, double AverageMonth, double AverageYear, IReadOnlyList<(string Host, int Count)> TopSites);
