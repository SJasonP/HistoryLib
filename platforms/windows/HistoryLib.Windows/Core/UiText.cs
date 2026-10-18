using Windows.ApplicationModel.Resources;

namespace HistoryLib.Windows.Core;

public static class UiText
{
    private static readonly ResourceLoader Loader = ResourceLoader.GetForViewIndependentUse();
    public static string Get(string key, params object[] args)
    {
        var value = Loader.GetString(key);
        if (string.IsNullOrEmpty(value)) return key;
        return args.Length == 0 ? value : string.Format(System.Globalization.CultureInfo.CurrentCulture, value.Replace("%1$s", "{0}").Replace("%2$s", "{1}"), args);
    }
}
