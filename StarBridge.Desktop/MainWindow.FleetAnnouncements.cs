using StarBridge.Core.FleetAnnouncements;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.IO;
using System.Net.Http.Json;
using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Media;
using Brush = System.Windows.Media.Brush;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private readonly ObservableCollection<FleetAnnouncementRow> _fleetAnnouncementHistory = [];
    private FleetAnnouncementContract? _fleetCurrentAnnouncement;
    private long _fleetAnnouncementTimelineRevision;
    private bool _fleetAnnouncementCanManage;
    private bool _isRefreshingFleetAnnouncements;
    private bool _isMutatingFleetAnnouncement;
    private bool _fleetAnnouncementEditorCreatesNew;
    private bool _returnToAnnouncementCenterAfterEdit;
    private DateTimeOffset _withdrawAnnouncementConfirmationExpiresAt;

    private void InitializeFleetAnnouncements()
    {
        FleetAnnouncementHistoryList.ItemsSource = _fleetAnnouncementHistory;
        RenderFleetAnnouncementSurfaces();
    }

    private async Task RefreshFleetAnnouncementsAsync(bool showErrors)
    {
        if (_isRefreshingFleetAnnouncements || !CanUseFleetChat)
        {
            return;
        }

        var session = _accountSessionCoordinator.Capture();
        _isRefreshingFleetAnnouncements = true;
        try
        {
            var timeline = await _relayClient.GetFromJsonAsync<FleetAnnouncementTimelineContract>(
                $"api/fleets/announcements?fleetCode={Uri.EscapeDataString(_fleetCode)}");
            if (timeline is null)
            {
                throw new InvalidDataException("公告时间线数据为空。");
            }

            if (!_accountSessionCoordinator.IsCurrent(session))
            {
                return;
            }

            ApplyFleetAnnouncementTimeline(timeline);
        }
        catch (Exception ex)
        {
            if (showErrors)
            {
                SetFleetAnnouncementStatus(UserFacingError.Describe(ex, "公告暂时无法同步，请稍后重试。"), StatusPalette.WarningBrush);
            }
        }
        finally
        {
            _isRefreshingFleetAnnouncements = false;
        }
    }

    private void ApplyFleetAnnouncementTimeline(FleetAnnouncementTimelineContract timeline)
    {
        if (!timeline.FleetCode.Equals(_fleetCode, StringComparison.OrdinalIgnoreCase) ||
            timeline.Revision < _fleetAnnouncementTimelineRevision)
        {
            return;
        }

        var previousSignature = BuildFleetAnnouncementSignature(_fleetCurrentAnnouncement);
        _fleetAnnouncementTimelineRevision = timeline.Revision;
        _fleetAnnouncementCanManage = timeline.CanManage;
        _fleetCurrentAnnouncement = timeline.Current;
        _fleetAnnouncementHistory.Clear();
        foreach (var announcement in timeline.History.OrderByDescending(item => item.UpdatedAt))
        {
            _fleetAnnouncementHistory.Add(new FleetAnnouncementRow(announcement));
        }

        if (timeline.Current is { } current)
        {
            _fleetNoticeTitle = current.Title;
            _fleetNoticeContent = current.Content;
            _fleetNoticePublishedAt = current.PublishedAt;
        }
        else
        {
            _fleetNoticeTitle = "";
            _fleetNoticeContent = "";
            _fleetNoticePublishedAt = null;
        }

        RenderFleetAnnouncementSurfaces();
        RefreshFleetInfoPanel();
        RefreshTaskManagementPanel();
        SetFleetAnnouncementStatus(
            _fleetAnnouncementCanManage
                ? "可发布新公告，或管理当前广播。"
                : "公告历史仅供舰队成员查看。",
            StatusPalette.DisabledBrush);
        if (!previousSignature.Equals(BuildFleetAnnouncementSignature(_fleetCurrentAnnouncement), StringComparison.Ordinal))
        {
            SaveCurrentConfig();
        }
    }

    private void RenderFleetAnnouncementSurfaces()
    {
        RefreshFleetHeaderAnnouncement();
        RenderFleetAnnouncementCenter();
    }

    private void RefreshFleetHeaderAnnouncement()
    {
        if (FleetHeaderAnnouncementButton is null || FleetHeaderAnnouncementTitleText is null)
        {
            return;
        }

        var title = _fleetCurrentAnnouncement?.Title ?? _fleetNoticeTitle;
        var content = _fleetCurrentAnnouncement?.Content ?? _fleetNoticeContent;
        var useChinese = _language.Equals("zh", StringComparison.OrdinalIgnoreCase);
        var presentation = FleetHeaderAnnouncementProjection.Project(title, content, useChinese);

        FleetHeaderAnnouncementTitleText.Inlines.Clear();
        FleetHeaderAnnouncementTitleText.Inlines.Add(
            new System.Windows.Documents.Run(presentation.TitleText));
        if (presentation.ContentSuffix.Length > 0)
        {
            FleetHeaderAnnouncementTitleText.Inlines.Add(
                new System.Windows.Documents.Run(presentation.ContentSuffix)
                {
                    Foreground = FleetCommandBrush(Theming.BridgeBrushToken.Ink3)
                });
        }

        FleetHeaderAnnouncementTitleText.ToolTip = presentation.AccessibleText;
        System.Windows.Automation.AutomationProperties.SetName(
            FleetHeaderAnnouncementButton,
            useChinese
                ? $"公告：{presentation.AccessibleText}"
                : $"Bulletin: {presentation.AccessibleText}");
        FleetHeaderAnnouncementButton.IsEnabled = _hasFleet;
    }

    private async void FleetHeaderAnnouncementButton_Click(object sender, RoutedEventArgs e)
    {
        if (_hasFleet)
        {
            await OpenFleetAnnouncementCenterAsync();
        }
    }

    private void RenderFleetAnnouncementCenter()
    {
        if (FleetAnnouncementCenterPanel is null)
        {
            return;
        }

        var current = _fleetCurrentAnnouncement;
        FleetAnnouncementCenterCurrentTitleText.Text = current?.Title ?? "暂无正在广播的公告";
        FleetAnnouncementCenterCurrentContentText.Text = current is null
            ? "有权限的成员可以发布新公告；已撤下和已归档内容仍会保留在历史中。"
            : string.IsNullOrWhiteSpace(current.Content) ? "本公告没有补充正文。" : current.Content;
        FleetAnnouncementCenterCurrentTimeText.Text = current is null
            ? "未发布"
            : CommunicationTimeFormatter.Format(current.PublishedAt);
        FleetAnnouncementCenterCurrentAuthorText.Text = current is null
            ? ""
            : FormatFleetAnnouncementAuthor(current.Author);
        FleetAnnouncementHistoryCountText.Text = $"{_fleetAnnouncementHistory.Count} 条记录";
        FleetAnnouncementHistoryEmptyText.Visibility = _fleetAnnouncementHistory.Count == 0
            ? Visibility.Visible
            : Visibility.Collapsed;
        WithdrawFleetAnnouncementButton.Visibility = _fleetAnnouncementCanManage && current is not null
            ? Visibility.Visible
            : Visibility.Collapsed;
        EditFleetAnnouncementButton.Visibility = _fleetAnnouncementCanManage && current is not null
            ? Visibility.Visible
            : Visibility.Collapsed;
        NewFleetAnnouncementButton.Visibility = _fleetAnnouncementCanManage
            ? Visibility.Visible
            : Visibility.Collapsed;
    }

    private void RefreshFleetAnnouncementTimeLabels(DateTimeOffset now)
    {
        foreach (var row in _fleetAnnouncementHistory)
        {
            row.RefreshTime(now);
        }

        if (_fleetCurrentAnnouncement is { } current)
        {
            FleetAnnouncementCenterCurrentTimeText.Text = CommunicationTimeFormatter.Format(current.PublishedAt, now);
        }
    }

    private async void FleetCommunicationAnnouncementHistoryButton_Click(object sender, RoutedEventArgs e)
    {
        await OpenFleetAnnouncementCenterAsync();
    }

    private async void OpenFleetAnnouncementCenterButton_Click(object sender, RoutedEventArgs e)
    {
        await OpenFleetAnnouncementCenterAsync();
    }

    private async void FleetCommunicationAnnouncementManageButton_Click(object sender, RoutedEventArgs e)
    {
        if (!_fleetAnnouncementCanManage && !CanCurrentUserManageAnnouncements())
        {
            return;
        }

        if (_fleetCurrentAnnouncement is null)
        {
            OpenFleetNoticeEditor(createNew: true, returnToCenter: false);
            return;
        }

        await OpenFleetAnnouncementCenterAsync();
    }

    private async Task OpenFleetAnnouncementCenterAsync()
    {
        FleetActivitySchedulePanel.Hide();
        await RefreshFleetAnnouncementsAsync(showErrors: true);
        RenderFleetAnnouncementCenter();
        FleetAnnouncementCenterPanel.Show();
    }

    private void CloseFleetAnnouncementCenterButton_Click(object sender, RoutedEventArgs e)
    {
        FleetAnnouncementCenterPanel.Hide();
        ResetWithdrawAnnouncementConfirmation();
    }

    private void NewFleetAnnouncementButton_Click(object sender, RoutedEventArgs e)
    {
        OpenFleetNoticeEditor(createNew: true, returnToCenter: true);
    }

    private void EditFleetAnnouncementButton_Click(object sender, RoutedEventArgs e)
    {
        if (_fleetCurrentAnnouncement is not null)
        {
            OpenFleetNoticeEditor(createNew: false, returnToCenter: true);
        }
    }

    private async void WithdrawFleetAnnouncementButton_Click(object sender, RoutedEventArgs e)
    {
        if (_isMutatingFleetAnnouncement || _fleetCurrentAnnouncement is not { } current)
        {
            return;
        }

        if (DateTimeOffset.UtcNow > _withdrawAnnouncementConfirmationExpiresAt)
        {
            _withdrawAnnouncementConfirmationExpiresAt = DateTimeOffset.UtcNow.AddSeconds(6);
            WithdrawFleetAnnouncementButton.Content = "再次点击确认撤下";
            SetFleetAnnouncementStatus("撤下后成员不再看到当前公告，但历史记录会保留。", StatusPalette.WarningBrush);
            return;
        }

        _isMutatingFleetAnnouncement = true;
        ApplyFleetAnnouncementMutationAvailability();
        try
        {
            var request = new FleetAnnouncementWithdrawRequestContract(
                _fleetCode,
                current.Id,
                current.Revision,
                Guid.NewGuid().ToString("N"));
            var result = await SendFleetAnnouncementMutationAsync(
                "api/fleets/announcements/withdraw",
                request);
            if (result?.Timeline is null)
            {
                SetFleetAnnouncementStatus(result?.Error ?? "撤下失败，请刷新后重试。", StatusPalette.WarningBrush);
                return;
            }

            ApplyFleetAnnouncementTimeline(result.Timeline);
            SetFleetAnnouncementStatus("当前公告已撤下，历史记录已保留。", StatusPalette.SuccessBrush);
        }
        finally
        {
            _isMutatingFleetAnnouncement = false;
            ResetWithdrawAnnouncementConfirmation();
            ApplyFleetAnnouncementMutationAvailability();
        }
    }

    private async Task PublishFleetAnnouncementDraftAsync()
    {
        if (_isMutatingFleetAnnouncement || !CanCurrentUserManageAnnouncements())
        {
            return;
        }

        var normalized = FleetAnnouncementPolicy.Normalize(
            FleetNoticeTitleBox.Text,
            FleetNoticeContentBox.Text);
        if (normalized.Error is not null)
        {
            FleetNoticeValidationText.Text = normalized.Error;
            return;
        }

        _isMutatingFleetAnnouncement = true;
        ApplyFleetAnnouncementMutationAvailability();
        FleetNoticeValidationText.Text = "正在同步公告…";
        FleetNoticeValidationText.Foreground = StatusPalette.InfoBrush;
        try
        {
            FleetAnnouncementMutationResponseContract? result;
            if (_fleetAnnouncementEditorCreatesNew || _fleetCurrentAnnouncement is null)
            {
                result = await SendFleetAnnouncementMutationAsync(
                    "api/fleets/announcements/publish",
                    new FleetAnnouncementPublishRequestContract(
                        _fleetCode,
                        normalized.Title,
                        normalized.Content,
                        Guid.NewGuid().ToString("N")));
            }
            else
            {
                var current = _fleetCurrentAnnouncement;
                result = await SendFleetAnnouncementMutationAsync(
                    "api/fleets/announcements/edit",
                    new FleetAnnouncementEditRequestContract(
                        _fleetCode,
                        current.Id,
                        current.Revision,
                        normalized.Title,
                        normalized.Content,
                        Guid.NewGuid().ToString("N")));
            }

            if (result?.Timeline is null)
            {
                FleetNoticeValidationText.Text = result?.Error ?? "公告同步失败，请刷新后重试。";
                FleetNoticeValidationText.Foreground = StatusPalette.WarningBrush;
                return;
            }

            ApplyFleetAnnouncementTimeline(result.Timeline);
            FleetNoticeEditorPanel.Hide();
            if (_returnToAnnouncementCenterAfterEdit)
            {
                FleetAnnouncementCenterPanel.Show();
                SetFleetAnnouncementStatus(
                    _fleetAnnouncementEditorCreatesNew ? "新公告已发布。" : "当前公告已更新。",
                    StatusPalette.SuccessBrush);
            }
        }
        finally
        {
            _isMutatingFleetAnnouncement = false;
            ApplyFleetAnnouncementMutationAvailability();
        }
    }

    private async Task<FleetAnnouncementMutationResponseContract?> SendFleetAnnouncementMutationAsync<T>(
        string route,
        T request)
    {
        try
        {
            using var response = await _relayClient.PostJsonAsync(route, request);
            var payload = await response.Content.ReadFromJsonAsync<FleetAnnouncementMutationResponseContract>();
            if (response.IsSuccessStatusCode)
            {
                return payload;
            }

            return payload ?? new FleetAnnouncementMutationResponseContract(
                null,
                "failed",
                DescribeResponseFailure(response.StatusCode));
        }
        catch (Exception ex)
        {
            return new FleetAnnouncementMutationResponseContract(null, "failed", UserFacingError.Describe(ex, "公告操作未完成，请稍后重试。"));
        }
    }

    private void OpenFleetNoticeEditor(bool createNew, bool returnToCenter)
    {
        if (!CanCurrentUserManageAnnouncements())
        {
            return;
        }

        _fleetAnnouncementEditorCreatesNew = createNew || _fleetCurrentAnnouncement is null;
        _returnToAnnouncementCenterAfterEdit = returnToCenter;
        FleetAnnouncementCenterPanel.Hide();
        FleetNoticeEditorPanel.Title = _fleetAnnouncementEditorCreatesNew ? "发布舰队公告" : "编辑当前公告";
        PublishFleetNoticeButton.Content = _fleetAnnouncementEditorCreatesNew ? "发布公告" : "保存修订";
        FleetNoticeTitleBox.Text = _fleetAnnouncementEditorCreatesNew ? "" : _fleetCurrentAnnouncement?.Title ?? _fleetNoticeTitle;
        FleetNoticeContentBox.Text = _fleetAnnouncementEditorCreatesNew ? "" : _fleetCurrentAnnouncement?.Content ?? _fleetNoticeContent;
        FleetNoticeValidationText.Text = "";
        FleetNoticeValidationText.Foreground = StatusPalette.WarningBrush;
        FleetNoticeEditorPanel.Show();
        FleetNoticeTitleBox.Focus();
    }

    private void ApplyFleetAnnouncementMutationAvailability()
    {
        PublishFleetNoticeButton.IsEnabled = !_isMutatingFleetAnnouncement;
        NewFleetAnnouncementButton.IsEnabled = !_isMutatingFleetAnnouncement;
        EditFleetAnnouncementButton.IsEnabled = !_isMutatingFleetAnnouncement;
        WithdrawFleetAnnouncementButton.IsEnabled = !_isMutatingFleetAnnouncement;
    }

    private void SetFleetAnnouncementStatus(string text, Brush brush)
    {
        if (FleetAnnouncementCenterStatusText is null)
        {
            return;
        }

        FleetAnnouncementCenterStatusText.Text = text;
        FleetAnnouncementCenterStatusText.Foreground = brush;
    }

    private void ResetWithdrawAnnouncementConfirmation()
    {
        _withdrawAnnouncementConfirmationExpiresAt = DateTimeOffset.MinValue;
        WithdrawFleetAnnouncementButton.Content = "撤下当前公告";
    }

    private void ResetFleetAnnouncements()
    {
        _fleetCurrentAnnouncement = null;
        _fleetAnnouncementHistory.Clear();
        _fleetAnnouncementTimelineRevision = 0;
        _fleetAnnouncementCanManage = false;
        _isRefreshingFleetAnnouncements = false;
        _isMutatingFleetAnnouncement = false;
        FleetAnnouncementCenterPanel.Hide();
        FleetNoticeEditorPanel.Hide();
        ResetWithdrawAnnouncementConfirmation();
        RenderFleetAnnouncementSurfaces();
    }

    private static string FormatFleetAnnouncementAuthor(FleetAnnouncementAuthorContract author) =>
        string.IsNullOrWhiteSpace(author.GameId)
            ? author.Callsign
            : $"{author.Callsign} · {author.GameId}";

    private static string BuildFleetAnnouncementSignature(FleetAnnouncementContract? announcement) =>
        announcement is null
            ? ""
            : $"{announcement.Id}|{announcement.Revision}|{announcement.State}|{announcement.Title}|{announcement.Content}";
}

public sealed class FleetAnnouncementRow : INotifyPropertyChanged
{
    private string _timeText;

    public FleetAnnouncementRow(FleetAnnouncementContract announcement)
    {
        Announcement = announcement;
        _timeText = CommunicationTimeFormatter.Format(announcement.UpdatedAt);
    }

    public FleetAnnouncementContract Announcement { get; }
    public string Title => Announcement.Title;
    public string Summary => string.IsNullOrWhiteSpace(Announcement.Content) ? "无补充正文" : Announcement.Content;
    public string AuthorText => string.IsNullOrWhiteSpace(Announcement.Author.GameId)
        ? Announcement.Author.Callsign
        : $"{Announcement.Author.Callsign} · {Announcement.Author.GameId}";
    public string StateText => Announcement.State.Equals(FleetAnnouncementStates.Withdrawn, StringComparison.OrdinalIgnoreCase)
        ? "已撤下"
        : "已归档";
    public bool IsWithdrawn => Announcement.State.Equals(
        FleetAnnouncementStates.Withdrawn,
        StringComparison.OrdinalIgnoreCase);
    public string TimeText
    {
        get => _timeText;
        private set
        {
            if (_timeText == value)
            {
                return;
            }

            _timeText = value;
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(TimeText)));
        }
    }

    public event PropertyChangedEventHandler? PropertyChanged;

    public void RefreshTime(DateTimeOffset now) =>
        TimeText = CommunicationTimeFormatter.Format(Announcement.UpdatedAt, now);

}
