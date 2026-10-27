using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using HistoryLib.Windows.Views;
using HistoryLib.Windows.Core;

namespace HistoryLib.Windows;

public sealed partial class MainWindow : Window
{
    public HistoryStore Store { get; } = new();
    public FaviconStore Favicons { get; } = new();
    public MainWindow()
    {
        InitializeComponent();
        SummaryButton.Content = Core.UiText.Get("destination_summary"); LibraryButton.Content = Core.UiText.Get("destination_library"); ManageButton.Content = Core.UiText.Get("destination_manage"); ContentFrame.Navigate(typeof(SummaryPage), this);
        SetLocked(true);
        ContentFrame.Navigate(typeof(PrivacyLockPage), this);
    }
    private void Summary_Click(object sender, RoutedEventArgs e) => ContentFrame.Navigate(typeof(SummaryPage), this);
    private void Library_Click(object sender, RoutedEventArgs e) => ContentFrame.Navigate(typeof(LibraryPage), this);
    private void Manage_Click(object sender, RoutedEventArgs e) => ContentFrame.Navigate(typeof(ManagePage), this);
    public void Navigate<T>() where T : Page => ContentFrame.Navigate(typeof(T), this);
    public void Unlock()
    {
        SetLocked(false);
        ContentFrame.Navigate(typeof(SummaryPage), this);
    }
    private void SetLocked(bool locked)
    {
        NavigationPanel.IsEnabled = !locked;
    }
}
