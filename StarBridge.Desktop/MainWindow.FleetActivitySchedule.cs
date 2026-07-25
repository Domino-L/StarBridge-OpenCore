using System.Windows;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private void RefreshFleetActivityHeaderPresentation()
    {
        if (FleetActivityScheduleButton is null || FleetTypeSummaryText is null)
        {
            return;
        }

        var windows = BuildFleetActivityHeaderWindows();
        var summary = FleetActivityHeaderPresentation.Resolve(
            windows,
            GetCurrentFleetTime(),
            _language.Equals("zh", StringComparison.OrdinalIgnoreCase));
        FleetTypeSummaryText.Text = _hasFleet ? summary.CompactText : "未设置";
        FleetActivityScheduleButton.ToolTip = _hasFleet
            ? $"{summary.FullText}\n\n点击查看完整排期"
            : "尚未加入舰队";
        FleetActivityScheduleButton.IsEnabled = _hasFleet;
    }

    private IReadOnlyList<FleetActivityHeaderWindow> BuildFleetActivityHeaderWindows() =>
        _fleetActivityWindows
            .Take(MaxFleetActivityWindowCount)
            .Select(window => new FleetActivityHeaderWindow(
                window.Days,
                FormatFleetActivityDays(window.Days),
                window.StartTime,
                window.EndTime,
                window.EndsNextDay))
            .ToArray();

    private void FleetActivityScheduleButton_Click(object sender, RoutedEventArgs e)
    {
        if (!_hasFleet)
        {
            return;
        }

        FleetAnnouncementCenterPanel.Visibility = Visibility.Collapsed;
        FleetActivityScheduleList.ItemsSource = BuildFleetActivityHeaderWindows()
            .Select((window, index) => new FleetActivityScheduleRow(
                $"时段 {index + 1}",
                window.DaysText,
                window.EndsNextDay
                    ? $"{window.StartTime} – 次日 {window.EndTime}"
                    : $"{window.StartTime} – {window.EndTime}"))
            .ToArray();
        var fleetNow = GetCurrentFleetTime();
        FleetActivityScheduleTimeZoneText.Text =
            $"舰队时区 {FormatUtcOffset(fleetNow.Offset)} · 当前 {fleetNow:MM-dd HH:mm}";
        EditFleetActivityScheduleButton.Visibility = CanCurrentUserManageFleetInfo()
            ? Visibility.Visible
            : Visibility.Collapsed;
        FleetActivitySchedulePanel.Visibility = Visibility.Visible;
    }

    private void CloseFleetActivityScheduleButton_Click(object sender, RoutedEventArgs e)
    {
        FleetActivitySchedulePanel.Visibility = Visibility.Collapsed;
    }

    private void EditFleetActivityScheduleButton_Click(object sender, RoutedEventArgs e)
    {
        FleetActivitySchedulePanel.Visibility = Visibility.Collapsed;
        OpenManageFleetSection(ManageFleetProfileTab);
    }
}

public sealed record FleetActivityScheduleRow(
    string SequenceText,
    string DaysText,
    string TimeText);
