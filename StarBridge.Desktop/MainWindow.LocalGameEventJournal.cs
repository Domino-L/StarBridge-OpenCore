using Microsoft.Win32;
using StarBridge.Core.Events;
using System.Collections.ObjectModel;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using WpfBrushes = System.Windows.Media.Brushes;
using WpfColor = System.Windows.Media.Color;
using WpfColorConverter = System.Windows.Media.ColorConverter;
using WpfComboBox = System.Windows.Controls.ComboBox;
using DesktopSaveFileDialog = Microsoft.Win32.SaveFileDialog;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private readonly ObservableCollection<LocalGameEventRow> _localGameEventRows = [];
    private readonly LocalGameEventJournal _localGameEventJournal = new(
        Path.Combine(DesktopAppConfig.ConfigDirectory, "local-event-log.json"));
    private string _localGameEventFilter = "all";
    private bool _localGameEventJournalRenderDirty;
    private bool _localGameEventJournalRenderQueued;

    private void InitializeLocalGameEventJournal()
    {
        LocalGameEventList.ItemsSource = _localGameEventRows;
        LocalGameEventList.IsVisibleChanged += (_, _) => QueueLocalGameEventJournalRender();
        _localGameEventJournal.Changed += LocalGameEventJournal_Changed;
        _localGameEventJournal.Load();
        RenderLocalGameEventJournal();
    }

    private void LocalGameEventJournal_Changed(object? sender, EventArgs e)
    {
        _localGameEventJournalRenderDirty = true;
        if (Dispatcher.CheckAccess())
        {
            QueueLocalGameEventJournalRender();
        }
        else
        {
            Dispatcher.BeginInvoke(QueueLocalGameEventJournalRender, System.Windows.Threading.DispatcherPriority.Background);
        }
    }

    private void QueueLocalGameEventJournalRender()
    {
        if (!_localGameEventJournalRenderDirty ||
            _localGameEventJournalRenderQueued ||
            LocalGameEventList?.IsVisible != true)
        {
            return;
        }

        _localGameEventJournalRenderQueued = true;
        Dispatcher.BeginInvoke(() =>
        {
            _localGameEventJournalRenderQueued = false;
            if (_localGameEventJournalRenderDirty && LocalGameEventList?.IsVisible == true)
            {
                RenderLocalGameEventJournal();
            }
        }, System.Windows.Threading.DispatcherPriority.Background);
    }

    private void RenderLocalGameEventJournal()
    {
        _localGameEventJournalRenderDirty = false;
        if (LocalGameEventList is null || LocalGameEventSummaryText is null)
        {
            return;
        }

        var allEntries = _localGameEventJournal.Entries;
        var visibleEntries = _localGameEventFilter == "all"
            ? allEntries
            : allEntries.Where(entry => entry.Category.Equals(_localGameEventFilter, StringComparison.Ordinal)).ToArray();
        _localGameEventRows.Clear();
        foreach (var entry in visibleEntries)
        {
            _localGameEventRows.Add(new LocalGameEventRow(entry));
        }

        LocalGameEventSummaryText.Text = _localGameEventJournal.LastWriteError is { Length: > 0 } error
            ? $"保存异常 · {error}"
            : allEntries.Length == 0
                ? "等待新的已识别事件"
                : $"本机保留 {allEntries.Length} 条 · 最近记录 {allEntries[0].OccurredAt.ToLocalTime():MM-dd HH:mm:ss}";
        LocalGameEventSummaryText.Foreground = _localGameEventJournal.LastWriteError is null
            ? FindBrush("MutedTextBrush", WpfBrushes.SlateGray)
            : FindBrush("StatusDangerBrush", WpfBrushes.IndianRed);
        LocalGameEventEmptyState.Visibility = visibleEntries.Length == 0 ? Visibility.Visible : Visibility.Collapsed;
        LocalGameEventList.Visibility = visibleEntries.Length == 0 ? Visibility.Collapsed : Visibility.Visible;
        ClearLocalGameEventsButton.IsEnabled = allEntries.Length > 0;
        ExportLocalGameEventsButton.IsEnabled = allEntries.Length > 0;
    }

    private void RecordLocalGameLogEvent(FleetEvent fleetEvent)
    {
        var title = FormatLogEventForUser(fleetEvent);
        if (string.IsNullOrWhiteSpace(title))
        {
            return;
        }

        var detail = fleetEvent.Type switch
        {
            FleetEventType.PlayerEnteredShip or FleetEventType.PlayerExitedShip or
                FleetEventType.PlayerControllingShip or FleetEventType.PlayerStoppedDrivingShip =>
                string.IsNullOrWhiteSpace(fleetEvent.Ship) ? "" : $"原始舰船标识：{fleetEvent.Ship}",
            FleetEventType.PlayerLocationChanged or FleetEventType.PlayerNavigationTargetChanged =>
                string.IsNullOrWhiteSpace(fleetEvent.Location) ? "" : $"原始地点标识：{fleetEvent.Location}",
            _ => string.IsNullOrWhiteSpace(fleetEvent.Player) ? "" : $"玩家：{fleetEvent.Player}"
        };
        _localGameEventJournal.Append(
            LocalGameEventJournal.Classify(fleetEvent.Type),
            fleetEvent.Type.ToString(),
            title,
            detail);
    }

    private void RecordLocalGameServerEvent()
    {
        var connected = IsGameServerRegionCurrent();
        _localGameEventJournal.Append(
            LocalGameEventCategories.Server,
            connected ? "ServerJoined" : "ServerLeft",
            connected ? "已连接游戏服务器" : "已离开游戏服务器",
            connected ? $"{_gameServerRegion} / {_gameServerShard}" : "服务器标识已清空");
    }

    private void RecordLocalGameProcessEvent(bool isRunning, DateTimeOffset now)
    {
        _localGameEventJournal.Append(
            LocalGameEventCategories.Session,
            isRunning ? "GameStarted" : "GameStopped",
            isRunning ? "检测到 Star Citizen 启动" : "检测到 Star Citizen 退出",
            "来源：本机进程监控",
            now);
    }

    private void LocalGameEventFilterBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (sender is WpfComboBox { SelectedItem: ComboBoxItem { Tag: string category } })
        {
            _localGameEventFilter = category;
            RenderLocalGameEventJournal();
        }
    }

    private async void ClearLocalGameEventsButton_Click(object sender, RoutedEventArgs e)
    {
        if (!await ShowAppConfirmationAsync(
                "清空本地事件日志",
                "清空全部本地事件记录？",
                "此操作只删除星海舰桥生成的标准化事件日志，不会修改 Star Citizen 的 Game.log。",
                "清空记录",
                "取消",
                footerText: "清空后无法恢复。"))
        {
            return;
        }

        _localGameEventJournal.Clear();
    }

    private async void ExportLocalGameEventsButton_Click(object sender, RoutedEventArgs e)
    {
        var entries = _localGameEventJournal.Entries;
        if (entries.Length == 0)
        {
            return;
        }

        var dialog = new DesktopSaveFileDialog
        {
            Title = "导出本地事件日志",
            Filter = "文本文件 (*.txt)|*.txt",
            FileName = $"StarBridge-Local-Events-{DateTime.Now:yyyyMMdd-HHmmss}.txt",
            AddExtension = true,
            DefaultExt = ".txt"
        };
        if (dialog.ShowDialog(this) != true)
        {
            return;
        }

        try
        {
            await File.WriteAllTextAsync(
                dialog.FileName,
                LocalGameEventJournal.FormatExport(entries),
                new System.Text.UTF8Encoding(encoderShouldEmitUTF8Identifier: true));
            LocalGameEventSummaryText.Text = $"已导出 {entries.Length} 条记录 · {Path.GetFileName(dialog.FileName)}";
            LocalGameEventSummaryText.Foreground = FindBrush("StatusSuccessBrush", WpfBrushes.SpringGreen);
        }
        catch (Exception ex)
        {
            LocalGameEventSummaryText.Text = UserFacingError.Describe(ex, "本地事件日志未能导出，请稍后重试。");
            LocalGameEventSummaryText.Foreground = FindBrush("StatusDangerBrush", WpfBrushes.IndianRed);
        }
    }
}

internal sealed record LocalGameEventRow(LocalGameEventEntry Entry)
{
    public string TimeText => Entry.OccurredAt.ToLocalTime().ToString("MM-dd\nHH:mm:ss");
    public string CategoryText => Entry.Category switch
    {
        LocalGameEventCategories.Session => "会话",
        LocalGameEventCategories.Identity => "身份",
        LocalGameEventCategories.Server => "服务器",
        LocalGameEventCategories.Ship => "舰船",
        LocalGameEventCategories.Location => "地点",
        LocalGameEventCategories.Life => "生命状态",
        _ => "其他"
    };
    public string Title => Entry.Title;
    public string Detail => Entry.Detail;
    public Visibility DetailVisibility => string.IsNullOrWhiteSpace(Entry.Detail)
        ? Visibility.Collapsed
        : Visibility.Visible;
    public System.Windows.Media.Brush AccentBrush => Entry.Category switch
    {
        LocalGameEventCategories.Session => CreateBrush("#42CF7C"),
        LocalGameEventCategories.Identity => CreateBrush("#69CCFF"),
        LocalGameEventCategories.Server => CreateBrush("#29AFFF"),
        LocalGameEventCategories.Ship => CreateBrush("#7BB6D8"),
        LocalGameEventCategories.Location => CreateBrush("#D9A23B"),
        LocalGameEventCategories.Life => CreateBrush("#F15B65"),
        _ => CreateBrush("#5E7283")
    };

    private static System.Windows.Media.Brush CreateBrush(string value)
    {
        var brush = new SolidColorBrush((WpfColor)WpfColorConverter.ConvertFromString(value));
        brush.Freeze();
        return brush;
    }
}
