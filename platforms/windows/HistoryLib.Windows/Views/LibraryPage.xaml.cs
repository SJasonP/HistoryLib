using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using HistoryLib.Windows.Core;
using Windows.System;
namespace HistoryLib.Windows.Views;
public sealed partial class LibraryPage : Page
{
    private HistoryStore Store => ((MainWindow)App.Window!).Store;
    public LibraryPage() { InitializeComponent(); SearchBox.PlaceholderText = UiText.Get("library_search_hint"); Loaded += (_, _) => Refresh(); }
    private async void Refresh() { var items = Store.Search(SearchBox.Text).ToArray(); if (((MainWindow)App.Window!).Favicons.IsEnabled) foreach (var item in items) item.FaviconPath = await ((MainWindow)App.Window!).Favicons.GetAsync(item.Url); List.ItemsSource = items; }
    private void Search_Changed(object sender, TextChangedEventArgs e) => Refresh();
    private void Delete_Click(object sender, RoutedEventArgs e) { if ((sender as Button)?.Tag is HistoryRecord r) Store.Delete(r); Refresh(); }
    private async void Open_Click(object sender, RoutedEventArgs e) { if ((sender as Button)?.Tag is HistoryRecord r) { _ = ((MainWindow)App.Window!).Favicons.GetAsync(r.Url); await Launcher.LaunchUriAsync(new Uri(r.Url)); } }
}
