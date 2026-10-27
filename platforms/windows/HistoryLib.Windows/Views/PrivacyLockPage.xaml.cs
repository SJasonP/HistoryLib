using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;
using HistoryLib.Windows.Core;

namespace HistoryLib.Windows.Views;

public sealed partial class PrivacyLockPage : Page
{
    private MainWindow? Host { get; set; }
    private readonly PrivacyLockService _lock = new();

    public PrivacyLockPage() { InitializeComponent(); Loaded += (_, _) => _ = AuthenticateAsync(); }

    protected override void OnNavigatedTo(NavigationEventArgs e)
    {
        Host = e.Parameter as MainWindow;
        base.OnNavigatedTo(e);
    }

    private async void Retry_Click(object sender, RoutedEventArgs e) => await AuthenticateAsync();

    private async Task AuthenticateAsync()
    {
        RetryButton.IsEnabled = false;
        Status.Text = "正在请求系统验证…";
        var verified = await _lock.AuthenticateAsync();
        if (verified)
        {
            Host?.Unlock();
            return;
        }
        Status.Text = "验证失败或设备未配置 Windows Hello。HistoryLib 在验证成功前不会显示历史记录。";
        RetryButton.IsEnabled = true;
    }
}
