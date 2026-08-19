using StarBridge.Core.FleetBroadcasts;
using System.Collections.ObjectModel;
using System.Globalization;
using System.IO;
using System.Net.Http.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using WpfBrush = System.Windows.Media.Brush;
using WpfBrushes = System.Windows.Media.Brushes;
using WpfColor = System.Windows.Media.Color;
using WpfColorConverter = System.Windows.Media.ColorConverter;
using WpfComboBox = System.Windows.Controls.ComboBox;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private readonly ObservableCollection<FleetBroadcastHistoryRow> _fleetBroadcastHistory = [];
    private readonly HashSet<string> _seenFleetBroadcastIds = new(StringComparer.OrdinalIgnoreCase);
    private readonly DateTimeOffset _fleetBroadcastSessionStartedAt = DateTimeOffset.UtcNow;
    private FleetBroadcastAlertWindow? _fleetBroadcastAlertWindow;
    private FleetBroadcastSenderSettings _fleetBroadcastSettings = FleetBroadcastSenderSettings.Default;
    private string _fleetBroadcastSettingsAccountKey = "";
    private string _fleetBroadcastFeedCode = "";
    private bool _fleetBroadcastCanPublish;
    private bool _isRefreshingFleetBroadcasts;
    private bool _isPublishingFleetBroadcast;
    private bool _isApplyingFleetBroadcastSettings;

    private void InitializeFleetBroadcasts()
    {
        FleetBroadcastHistoryList.ItemsSource = _fleetBroadcastHistory;
        _isApplyingFleetBroadcastSettings = true;
        try
        {
            FleetBroadcastPresetBox.SelectedIndex = 0;
            FleetBroadcastDurationBox.SelectedIndex = 1;
            FleetBroadcastRepeatBox.SelectedIndex = 1;
            FleetBroadcastFontScaleBox.SelectedIndex = 0;
        }
        finally
        {
            _isApplyingFleetBroadcastSettings = false;
        }

        RenderFleetBroadcastPage();
    }

    private async Task RefreshFleetBroadcastsAsync(bool showErrors, CancellationToken cancellationToken = default)
    {
        if (_isRefreshingFleetBroadcasts || !CanUseFleetChat || string.IsNullOrWhiteSpace(_fleetCode))
        {
            return;
        }

        EnsureFleetBroadcastSettingsForAccount();
        var session = _accountSessionCoordinator.Capture();
        _isRefreshingFleetBroadcasts = true;
        try
        {
            var feed = await _relayClient.GetFromJsonAsync<FleetBroadcastFeedContract>(
                $"api/fleets/broadcasts?fleetCode={Uri.EscapeDataString(_fleetCode)}");
            cancellationToken.ThrowIfCancellationRequested();
            if (feed is null)
            {
                throw new InvalidDataException("广播数据为空。");
            }

            if (!_accountSessionCoordinator.IsCurrent(session))
            {
                return;
            }

            ApplyFleetBroadcastFeed(feed);
        }
        catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
        {
        }
        catch (Exception ex)
        {
            if (showErrors)
            {
                SetFleetBroadcastStatus(UserFacingError.Describe(ex, "舰队广播暂时无法同步，请稍后重试。"), StatusPalette.WarningBrush);
            }
        }
        finally
        {
            _isRefreshingFleetBroadcasts = false;
        }
    }

    private void ApplyFleetBroadcastFeed(FleetBroadcastFeedContract feed)
    {
        if (!feed.FleetCode.Equals(_fleetCode, StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        if (!_fleetBroadcastFeedCode.Equals(feed.FleetCode, StringComparison.OrdinalIgnoreCase))
        {
            _fleetBroadcastFeedCode = feed.FleetCode;
            _seenFleetBroadcastIds.Clear();
            _fleetBroadcastHistory.Clear();
        }

        _fleetBroadcastCanPublish = feed.CanPublish;
        foreach (var broadcast in feed.Broadcasts.OrderBy(item => item.SentAt))
        {
            if (_fleetBroadcastHistory.All(row => !row.Broadcast.Id.Equals(broadcast.Id, StringComparison.OrdinalIgnoreCase)))
            {
                _fleetBroadcastHistory.Insert(0, new FleetBroadcastHistoryRow(broadcast));
            }

            if (!_seenFleetBroadcastIds.Add(broadcast.Id))
            {
                continue;
            }

            if (_isGameProcessRunning &&
                broadcast.SentAt >= _fleetBroadcastSessionStartedAt &&
                broadcast.ExpiresAt > feed.ServerTime)
            {
                ShowFleetBroadcastAlert(broadcast);
            }
        }

        while (_fleetBroadcastHistory.Count > FleetBroadcastPolicy.MaximumRetainedBroadcasts)
        {
            _fleetBroadcastHistory.RemoveAt(_fleetBroadcastHistory.Count - 1);
        }

        RenderFleetBroadcastPage();
    }

    private async void FleetBroadcastSendButton_Click(object sender, RoutedEventArgs e)
    {
        if (_isPublishingFleetBroadcast || !CanCurrentUserPublishFleetBroadcasts())
        {
            return;
        }

        var normalized = FleetBroadcastPolicy.NormalizeMessage(FleetBroadcastMessageBox.Text);
        if (normalized.Error is not null)
        {
            SetFleetBroadcastStatus(normalized.Error, StatusPalette.WarningBrush);
            return;
        }

        EnsureFleetBroadcastSettingsForAccount();
        _isPublishingFleetBroadcast = true;
        RenderFleetBroadcastPage();
        SetFleetBroadcastStatus("正在发送广播…", StatusPalette.InfoBrush);
        try
        {
            var request = new FleetBroadcastPublishRequestContract(
                _fleetCode,
                normalized.Message,
                _fleetBroadcastSettings.ToAppearance(),
                Guid.NewGuid().ToString("N"));
            using var response = await _relayClient.PostJsonAsync("api/fleets/broadcasts/publish", request);
            var payload = await response.Content.ReadFromJsonAsync<FleetBroadcastMutationResponseContract>();
            if (!response.IsSuccessStatusCode || payload?.Broadcast is null)
            {
                SetFleetBroadcastStatus(
                    payload?.Error ?? DescribeResponseFailure(response.StatusCode),
                    StatusPalette.WarningBrush);
                return;
            }

            FleetBroadcastMessageBox.Clear();
            SetFleetBroadcastStatus("广播已发出，正在游戏中的舰队成员将强制看到。", StatusPalette.SuccessBrush);
            await RefreshFleetBroadcastsAsync(showErrors: false);
        }
        catch (Exception ex)
        {
            SetFleetBroadcastStatus(UserFacingError.Describe(ex, "广播发送失败，请稍后重试。"), StatusPalette.WarningBrush);
        }
        finally
        {
            _isPublishingFleetBroadcast = false;
            RenderFleetBroadcastPage();
        }
    }

    private void FleetBroadcastAppearanceBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_isApplyingFleetBroadcastSettings || FleetBroadcastPresetBox is null)
        {
            return;
        }

        _fleetBroadcastSettings = ReadFleetBroadcastSettingsFromControls();
        FleetBroadcastSettingsStore.Save(ResolveFleetBroadcastAccountKey(), _fleetBroadcastSettings);
        ApplyFleetBroadcastPreview();
    }

    private void EnsureFleetBroadcastSettingsForAccount()
    {
        var accountKey = ResolveFleetBroadcastAccountKey();
        if (_fleetBroadcastSettingsAccountKey.Equals(accountKey, StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        _fleetBroadcastSettingsAccountKey = accountKey;
        _fleetBroadcastSettings = FleetBroadcastSettingsStore.Load(accountKey);
        ApplyFleetBroadcastSettingsToControls();
    }

    private string ResolveFleetBroadcastAccountKey() =>
        string.IsNullOrWhiteSpace(_accountId)
            ? string.IsNullOrWhiteSpace(_accountName) ? "local" : _accountName
            : _accountId;

    private FleetBroadcastSenderSettings ReadFleetBroadcastSettingsFromControls() =>
        new(
            ReadComboTag(FleetBroadcastPresetBox, "emergency"),
            ParseDoubleTag(FleetBroadcastDurationBox, 10),
            (int)ParseDoubleTag(FleetBroadcastRepeatBox, 2),
            ParseDoubleTag(FleetBroadcastFontScaleBox, 1));

    private void ApplyFleetBroadcastSettingsToControls()
    {
        _isApplyingFleetBroadcastSettings = true;
        try
        {
            SelectComboTag(FleetBroadcastPresetBox, _fleetBroadcastSettings.Preset);
            SelectComboTag(FleetBroadcastDurationBox, _fleetBroadcastSettings.DurationSeconds.ToString("0", CultureInfo.InvariantCulture));
            SelectComboTag(FleetBroadcastRepeatBox, _fleetBroadcastSettings.RepeatCount.ToString(CultureInfo.InvariantCulture));
            SelectComboTag(FleetBroadcastFontScaleBox, _fleetBroadcastSettings.FontScale.ToString("0.##", CultureInfo.InvariantCulture));
        }
        finally
        {
            _isApplyingFleetBroadcastSettings = false;
        }

        ApplyFleetBroadcastPreview();
    }

    private void ApplyFleetBroadcastPreview()
    {
        if (FleetBroadcastPreviewBorder is null)
        {
            return;
        }

        var appearance = _fleetBroadcastSettings.ToAppearance();
        FleetBroadcastPreviewBorder.BorderBrush = ParseFleetBroadcastBrush(appearance.AccentColor, WpfBrushes.OrangeRed);
        FleetBroadcastPreviewBorder.Background = ParseFleetBroadcastBrush(appearance.BackgroundColor, WpfBrushes.Black);
        FleetBroadcastPreviewText.Foreground = ParseFleetBroadcastBrush(appearance.TextColor, WpfBrushes.White);
        FleetBroadcastPreviewText.FontSize = 17 * appearance.FontScale;
    }

    private void RenderFleetBroadcastPage()
    {
        if (FleetBroadcastSendButton is null)
        {
            return;
        }

        var allowed = _fleetBroadcastCanPublish || CanCurrentUserPublishFleetBroadcasts();
        FleetBroadcastSendButton.IsEnabled = allowed && !_isPublishingFleetBroadcast;
        FleetBroadcastMessageBox.IsEnabled = allowed && !_isPublishingFleetBroadcast;
        FleetBroadcastPermissionText.Text = allowed
            ? "当前身份拥有发送广播权限"
            : "当前身份没有发送广播权限";
        FleetBroadcastPermissionText.Foreground = allowed ? StatusPalette.SuccessBrush : StatusPalette.DisabledBrush;
        ApplyFleetBroadcastPreview();
    }

    private void ShowFleetBroadcastAlert(FleetBroadcastContract broadcast)
    {
        _fleetBroadcastAlertWindow ??= new FleetBroadcastAlertWindow();
        _fleetBroadcastAlertWindow.Enqueue(broadcast);
    }

    private void ResetFleetBroadcasts()
    {
        _fleetBroadcastFeedCode = "";
        _fleetBroadcastCanPublish = false;
        _seenFleetBroadcastIds.Clear();
        _fleetBroadcastHistory.Clear();
        _fleetBroadcastAlertWindow?.Close();
        _fleetBroadcastAlertWindow = null;
        RenderFleetBroadcastPage();
    }

    private void SetFleetBroadcastStatus(string text, WpfBrush brush)
    {
        if (FleetBroadcastStatusText is null)
        {
            return;
        }

        FleetBroadcastStatusText.Text = text;
        FleetBroadcastStatusText.Foreground = brush;
    }

    private static string ReadComboTag(WpfComboBox box, string fallback) =>
        box.SelectedItem is ComboBoxItem item && item.Tag is string value && value.Length > 0
            ? value
            : fallback;

    private static double ParseDoubleTag(WpfComboBox box, double fallback) =>
        double.TryParse(ReadComboTag(box, ""), NumberStyles.Float, CultureInfo.InvariantCulture, out var value)
            ? value
            : fallback;

    private static void SelectComboTag(WpfComboBox box, string tag)
    {
        var match = box.Items.OfType<ComboBoxItem>().FirstOrDefault(item =>
            string.Equals(item.Tag?.ToString(), tag, StringComparison.OrdinalIgnoreCase));
        box.SelectedItem = match ?? box.Items.OfType<ComboBoxItem>().FirstOrDefault();
    }

    private static WpfBrush ParseFleetBroadcastBrush(string value, WpfBrush fallback)
    {
        try
        {
            var brush = new SolidColorBrush((WpfColor)WpfColorConverter.ConvertFromString(value));
            brush.Freeze();
            return brush;
        }
        catch
        {
            return fallback;
        }
    }
}

public sealed class FleetBroadcastHistoryRow
{
    public FleetBroadcastHistoryRow(FleetBroadcastContract broadcast)
    {
        Broadcast = broadcast;
        AccentBrush = ParseBrush(broadcast.Appearance.AccentColor);
    }

    public FleetBroadcastContract Broadcast { get; }
    public string Message => Broadcast.Message;
    public string MetaText => $"{Broadcast.Author.Callsign} · {Broadcast.Author.RoleTitle} · {CommunicationTimeFormatter.Format(Broadcast.SentAt)}";
    public WpfBrush AccentBrush { get; }

    private static WpfBrush ParseBrush(string value)
    {
        try
        {
            var brush = new SolidColorBrush((WpfColor)WpfColorConverter.ConvertFromString(value));
            brush.Freeze();
            return brush;
        }
        catch
        {
            return WpfBrushes.OrangeRed;
        }
    }
}
