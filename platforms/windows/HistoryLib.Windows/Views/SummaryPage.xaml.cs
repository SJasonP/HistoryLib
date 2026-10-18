using Microsoft.UI.Xaml.Controls;
using HistoryLib.Windows.Core;
namespace HistoryLib.Windows.Views;
public sealed partial class SummaryPage : Page
{
    private HistoryStore Store => ((MainWindow)App.Window!).Store;
    public SummaryPage() { InitializeComponent(); Title.Text = UiText.Get("destination_summary"); TotalLabel.Text = UiText.Get("summary_total_records"); DayLabel.Text = UiText.Get("summary_avg_day"); MonthLabel.Text = UiText.Get("summary_avg_month"); YearLabel.Text = UiText.Get("summary_avg_year"); SitesTitle.Text = UiText.Get("summary_top_sites"); Loaded += (_, _) => Refresh(); }
    private void Refresh() { var s = Store.GetSummary(); Total.Text = s.TotalRecords.ToString(); Day.Text = s.AverageDay.ToString("F2"); Month.Text = s.AverageMonth.ToString("F2"); Year.Text = s.AverageYear.ToString("F2"); Sites.ItemsSource = s.TopSites; }
}
