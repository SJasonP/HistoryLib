using Microsoft.UI.Xaml;

namespace HistoryLib.Windows;

public partial class App : Application
{
    public static MainWindow? Window { get; private set; }
    public App() => InitializeComponent();
    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        Window = new MainWindow();
        Window.Activate();
    }
}
