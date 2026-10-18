using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using HistoryLib.Windows.Core;
using Windows.Storage.Pickers;
using WinRT.Interop;

namespace HistoryLib.Windows.Views;

public sealed partial class ManagePage : Page
{
    private HistoryStore Store => ((MainWindow)App.Window!).Store;
    private FaviconStore Favicons => ((MainWindow)App.Window!).Favicons;
    public ManagePage() { InitializeComponent(); Loaded += (_, _) => ApplyText(); }
    private void ApplyText()
    {
        Title.Text = UiText.Get("destination_manage"); Subtitle.Text = "导入、导出和管理你的浏览器历史记录";
        ImportHeading.Text = UiText.Get("manage_import"); ImportDescription.Text = "HistoryLib 会自动识别 Safari、Chrome Takeout、HistoryLib 归档以及 ZIP 文件。";
        ImportButton.Content = UiText.Get("manage_import_file"); ImportFolderButton.Content = UiText.Get("manage_import_folder");
        ExportHeading.Text = UiText.Get("manage_export"); ExportDescription.Text = "HistoryLib 归档始终使用一个优化的 .hlz 文件；Safari 导出用于与 Safari 兼容。"; ExportButton.Content = UiText.Get("manage_export");
        DataHeading.Text = "数据"; IconsToggle.Content = UiText.Get("manage_show_site_icons"); IconsToggle.IsChecked = Favicons.IsEnabled; ClearCacheButton.Content = UiText.Get("manage_clear_cache"); ClearButton.Content = "清空历史记录";
        SettingsButton.Content = "设置"; HelpButton.Content = "帮助";
    }
    private FileOpenPicker Picker() { var p = new FileOpenPicker(); p.FileTypeFilter.Add("*"); InitializeWithWindow.Initialize(p, WindowNative.GetWindowHandle(App.Window)); return p; }
    private FolderPicker FolderPicker() { var p = new FolderPicker(); p.FileTypeFilter.Add("*"); InitializeWithWindow.Initialize(p, WindowNative.GetWindowHandle(App.Window)); return p; }
    private async void Import_Click(object sender, RoutedEventArgs e) { var f = await Picker().PickSingleFileAsync(); if (f == null) return; await ImportPath(f.Path); }
    private async void ImportFolder_Click(object sender, RoutedEventArgs e) { var f = await FolderPicker().PickSingleFolderAsync(); if (f == null) return; await ImportPath(f.Path); }
    private async Task ImportPath(string path)
    {
        try { var r = await Store.ImportAsync(path); Status.Text = $"识别格式：{r.Format}\n导入 {r.Imported}，合并 {r.Merged}，跳过 {r.Skipped}，扫描文件 {r.ScannedFiles}"; }
        catch (InvalidDataException ex) when (ex.Message.Contains("password", StringComparison.OrdinalIgnoreCase)) { var password = await PasswordDialog("输入归档密码"); if (password == null) return; try { var r = await Store.ImportAsync(path, default, password); Status.Text = $"识别格式：{r.Format}\n导入 {r.Imported}，合并 {r.Merged}，跳过 {r.Skipped}"; } catch (Exception retry) { Status.Text = "导入失败：" + retry.Message; } }
        catch (Exception ex) { Status.Text = "导入失败：" + ex.Message; }
    }
    private void ExportFormat_Changed(object sender, SelectionChangedEventArgs e) { if (ExportPasswordConfirm == null) return; var hlz = ExportFormat.SelectedIndex == 0; ExportPassword.Visibility = hlz ? Visibility.Visible : Visibility.Collapsed; ExportPasswordConfirm.Visibility = Visibility.Collapsed; ExportDescription.Text = hlz ? "HistoryLib 归档始终使用一个优化的 .hlz 文件。" : "Safari JSON 使用 HistoryLib 的标准 Safari 历史记录格式。"; }
    private async void Export_Click(object sender, RoutedEventArgs e)
    {
        if (ExportFormat.SelectedIndex == 0)
        {
            if (!string.IsNullOrEmpty(ExportPassword.Password) && ExportPassword.Password != ExportPasswordConfirm.Password) { ExportPasswordConfirm.Visibility = Visibility.Visible; Status.Text = "两次输入的密码不一致。"; return; }
            var p = new FileSavePicker { SuggestedFileName = "HistoryLib.hlz" }; p.FileTypeChoices.Add("HistoryLib archive", new[] { ".hlz" }); InitializeWithWindow.Initialize(p, WindowNative.GetWindowHandle(App.Window)); var f = await p.PickSaveFileAsync(); if (f != null) { await Store.ExportHistoryLibAsync(f.Path, ExportPassword.Password); Status.Text = "HistoryLib .hlz 已导出。"; }
        }
        else { var p = new FileSavePicker { SuggestedFileName = "History.json" }; p.FileTypeChoices.Add("JSON", new[] { ".json" }); InitializeWithWindow.Initialize(p, WindowNative.GetWindowHandle(App.Window)); var f = await p.PickSaveFileAsync(); if (f != null) { await Store.ExportSafariAsync(f.Path); Status.Text = "Safari JSON 已导出。"; } }
    }
    private async Task<string?> PasswordDialog(string title) { var box = new PasswordBox { PlaceholderText = "密码" }; var dialog = new ContentDialog { Title = title, Content = box, PrimaryButtonText = "确定", CloseButtonText = "取消", XamlRoot = XamlRoot }; return await dialog.ShowAsync() == ContentDialogResult.Primary && box.Password.Length > 0 ? box.Password : null; }
    private async void Clear_Click(object sender, RoutedEventArgs e) { var dialog = new ContentDialog { Title = "清空历史记录？", Content = "这将永久删除本机保存的所有历史记录。", PrimaryButtonText = "清空", CloseButtonText = "取消", XamlRoot = XamlRoot }; if (await dialog.ShowAsync() == ContentDialogResult.Primary) { Store.Clear(); Status.Text = "历史记录已清空。"; } }
    private void IconsToggle_Click(object sender, RoutedEventArgs e) => Favicons.SetEnabled(IconsToggle.IsChecked == true);
    private async void ClearCache_Click(object sender, RoutedEventArgs e) { var dialog = new ContentDialog { Title = UiText.Get("manage_cache_clear_title"), Content = "只删除网站图标缓存，不会删除历史记录。", PrimaryButtonText = UiText.Get("manage_clear_cache"), CloseButtonText = UiText.Get("common_cancel"), XamlRoot = XamlRoot }; if (await dialog.ShowAsync() == ContentDialogResult.Primary) { Favicons.Clear(); Status.Text = "网站图标缓存已清除。"; } }
    private void Settings_Click(object sender, RoutedEventArgs e) => ((MainWindow)App.Window!).Navigate<SettingsPage>();
    private void Help_Click(object sender, RoutedEventArgs e) => ((MainWindow)App.Window!).Navigate<HelpPage>();
}
