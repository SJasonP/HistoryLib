using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using HistoryLib.Windows.Core;
namespace HistoryLib.Windows.Views;
public sealed partial class SettingsPage : Page
{
    private WindowsSettingsStore Settings { get; } = new();
    public SettingsPage() { InitializeComponent(); IconsToggle.IsOn = Settings.GetBool("show_icons", true); TimeToggle.IsOn = Settings.GetBool("show_time", true); DeleteToggle.IsOn = Settings.GetBool("enable_delete", false); OpenToggle.IsOn = Settings.GetBool("open_browser", true); ExpandCombo.SelectedIndex = Settings.GetInt("expand_level", 2); PrivacyLockToggle.IsOn = Settings.GetBool("privacy_lock_enabled", true); }
    private void Icons_Toggled(object s, RoutedEventArgs e) => Settings.Set("show_icons", IconsToggle.IsOn);
    private void Time_Toggled(object s, RoutedEventArgs e) => Settings.Set("show_time", TimeToggle.IsOn);
    private void Delete_Toggled(object s, RoutedEventArgs e) => Settings.Set("enable_delete", DeleteToggle.IsOn);
    private void Open_Toggled(object s, RoutedEventArgs e) => Settings.Set("open_browser", OpenToggle.IsOn);
    private void Expand_Changed(object s, SelectionChangedEventArgs e) { if (ExpandCombo != null && ExpandCombo.SelectedIndex >= 0) Settings.Set("expand_level", ExpandCombo.SelectedIndex); }
    private void PrivacyLock_Toggled(object s, RoutedEventArgs e) => Settings.Set("privacy_lock_enabled", PrivacyLockToggle.IsOn);
}
