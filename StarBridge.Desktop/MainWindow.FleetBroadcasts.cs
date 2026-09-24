using StarBridge.Core.FleetBroadcasts;
using StarBridge.HostRuntime.Auth;
using System.Collections.ObjectModel;
using System.Globalization;
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
    private ScmFleetBroadcastScope? _fleetBroadcastScope;
    private long _fleetBroadcastResourceVersion;
    private bool _fleetBroadcastCanPublish;
    private bool _isRefreshingFleetBroadcasts;
    private bool _isPublishingFleetBroadcast;
    private bool _isApplyingFleetBroadcastSettings;
    private CancellationTokenSource _fleetBroadcastRouteCts = new();

    private AccountRouteIdentity CurrentAccountRouteIdentity =>
        AccountRouteIdentity.Create(
            _scmEnvironmentSettings.EnvironmentName,
            _scmOAuthSession?.AuthorityId,
            _scmOAuthSession?.Subject,
            _legacyIdentityLinked == true
                ? _legacyIdentityLinkProjection?.LegacyAccountId
                : null);

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
        if (_isRefreshingFleetBroadcasts || !CanUseFleetBroadcasts || _scmOAuthSession is not { } scmSession)
        {
            return;
        }

        EnsureFleetBroadcastSettingsForAccount();
        var session = _accountSessionCoordinator.Capture();
        var fleetCode = _fleetCode.Trim();
        using var requestCts = CancellationTokenSource.CreateLinkedTokenSource(
            cancellationToken,
            _fleetBroadcastRouteCts.Token);
        var requestToken = requestCts.Token;
        _isRefreshingFleetBroadcasts = true;
        try
        {
            if (!_fleetBroadcastFeedCode.Equals(fleetCode, StringComparison.OrdinalIgnoreCase) ||
                _fleetBroadcastScope is null)
            {
                var resolution = await _scmFleetBroadcastClient.ResolveOrganizationScopeAsync(
                    scmSession,
                    fleetCode,
                    requestToken);
                scmSession = resolution.ActiveSession;
                if (!_accountSessionCoordinator.IsCurrent(session) ||
                    !_fleetCode.Trim().Equals(fleetCode, StringComparison.OrdinalIgnoreCase))
                {
                    return;
                }

                ApplyScmOAuthSession(scmSession);
                _fleetBroadcastFeedCode = fleetCode;
                _fleetBroadcastScope = resolution.Result;
                _scmRealtimeClient?.SetFleetBroadcastScope(_fleetBroadcastScope);
                _fleetBroadcastResourceVersion = 0;
                _fleetBroadcastCanPublish = false;
                _seenFleetBroadcastIds.Clear();
                _fleetBroadcastHistory.Clear();
            }

            var result = await _scmFleetBroadcastClient.LoadFeedAsync(
                scmSession,
                _fleetBroadcastScope,
                _fleetBroadcastResourceVersion,
                requestToken);
            requestToken.ThrowIfCancellationRequested();

            if (!_accountSessionCoordinator.IsCurrent(session) ||
                !_fleetCode.Trim().Equals(fleetCode, StringComparison.OrdinalIgnoreCase))
            {
                return;
            }

            ApplyScmOAuthSession(result.ActiveSession);
            ApplyFleetBroadcastFeed(result.Result);
        }
        catch (OperationCanceledException) when (requestToken.IsCancellationRequested)
        {
        }
        catch (Exception ex)
        {
            if (showErrors && _accountSessionCoordinator.IsCurrent(session))
            {
                SetFleetBroadcastStatus(UserFacingError.Describe(ex, "舰队广播暂时无法同步，请稍后重试。"), StatusPalette.WarningBrush);
            }
        }
        finally
        {
            if (_accountSessionCoordinator.IsCurrent(session))
            {
                _isRefreshingFleetBroadcasts = false;
            }
        }
    }

    private void ApplyFleetBroadcastFeed(ScmFleetBroadcastFeed feed)
    {
        if (_fleetBroadcastScope is not { } scope ||
            !feed.ScopeType.Equals(scope.ScopeType, StringComparison.OrdinalIgnoreCase) ||
            feed.ScopeId != scope.ScopeId)
        {
            return;
        }

        _fleetBroadcastCanPublish = feed.CanPublish;
        foreach (var item in feed.Broadcasts.OrderBy(item => item.ResourceVersion))
        {
            var broadcast = ToFleetBroadcastContract(item);
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
        _fleetBroadcastResourceVersion = Math.Max(_fleetBroadcastResourceVersion, feed.ResourceVersion);

        while (_fleetBroadcastHistory.Count > FleetBroadcastPolicy.MaximumRetainedBroadcasts)
        {
            _fleetBroadcastHistory.RemoveAt(_fleetBroadcastHistory.Count - 1);
        }

        RenderFleetBroadcastPage();
    }

    private async void FleetBroadcastSendButton_Click(object sender, RoutedEventArgs e)
    {
        if (_isPublishingFleetBroadcast || !_fleetBroadcastCanPublish ||
            _fleetBroadcastScope is not { } scope || _scmOAuthSession is not { } scmSession)
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
        var session = _accountSessionCoordinator.Capture();
        using var requestCts = CancellationTokenSource.CreateLinkedTokenSource(
            _fleetBroadcastRouteCts.Token);
        _isPublishingFleetBroadcast = true;
        RenderFleetBroadcastPage();
        SetFleetBroadcastStatus("正在发送广播…", StatusPalette.InfoBrush);
        try
        {
            var appearance = _fleetBroadcastSettings.ToAppearance();
            var request = new ScmFleetBroadcastPublishRequest(
                scope.ScopeType,
                scope.ScopeId,
                normalized.Message,
                new ScmFleetBroadcastAppearance(
                    appearance.AccentColor,
                    appearance.BackgroundColor,
                    appearance.TextColor,
                    appearance.DurationSeconds,
                    appearance.RepeatCount,
                    appearance.FontScale),
                Guid.NewGuid().ToString("N"));
            var result = await _scmFleetBroadcastClient.PublishAsync(
                scmSession,
                request,
                requestCts.Token);
            if (!_accountSessionCoordinator.IsCurrent(session))
            {
                return;
            }

            ApplyScmOAuthSession(result.ActiveSession);
            if (result.Result.Broadcast is null)
            {
                SetFleetBroadcastStatus(
                    DescribeFleetBroadcastMutationFailure(result.Result),
                    StatusPalette.WarningBrush);
                return;
            }

            FleetBroadcastMessageBox.Clear();
            SetFleetBroadcastStatus("广播已发出，正在游戏中的舰队成员将强制看到。", StatusPalette.SuccessBrush);
            await RefreshFleetBroadcastsAsync(showErrors: false);
        }
        catch (OperationCanceledException) when (requestCts.IsCancellationRequested)
        {
        }
        catch (Exception ex)
        {
            if (_accountSessionCoordinator.IsCurrent(session))
            {
                SetFleetBroadcastStatus(UserFacingError.Describe(ex, "广播发送失败，请稍后重试。"), StatusPalette.WarningBrush);
            }
        }
        finally
        {
            if (_accountSessionCoordinator.IsCurrent(session))
            {
                _isPublishingFleetBroadcast = false;
                RenderFleetBroadcastPage();
            }
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
        CurrentAccountRouteIdentity.CacheNamespace;

    private void AdvanceAccountRouteIdentity()
    {
        var changed = _accountSessionCoordinator.UpdateRouteNamespace(
            CurrentAccountRouteIdentity.CacheNamespace);
        InvalidateFleetBroadcastRouteIdentity();
        if (changed)
        {
            ResetAccountScopedState("正在加载当前账号的组织通讯…");
            LoadFleetStateCacheForCurrentAccount();
            BindGameplayStatisticsOwner();
            ReloadDualAxisPrivacySettings();
            BeginPersonalProfileAccountSession(sameAccount: false);
            LoadOwnedShips();
        }
    }

    private void InvalidateFleetBroadcastRouteIdentity()
    {
        var accountKey = ResolveFleetBroadcastAccountKey();
        if (_fleetBroadcastSettingsAccountKey.Equals(accountKey, StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        _fleetBroadcastSettingsAccountKey = "";
        _fleetBroadcastSettings = FleetBroadcastSenderSettings.Default;
        ResetFleetBroadcasts();
    }

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

        var allowed = _fleetBroadcastCanPublish;
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
        _fleetBroadcastRouteCts.Cancel();
        _fleetBroadcastRouteCts.Dispose();
        _fleetBroadcastRouteCts = new CancellationTokenSource();
        _isRefreshingFleetBroadcasts = false;
        _isPublishingFleetBroadcast = false;
        _scmRealtimeClient?.SetFleetBroadcastScope(null);
        _fleetBroadcastFeedCode = "";
        _fleetBroadcastScope = null;
        _fleetBroadcastResourceVersion = 0;
        _fleetBroadcastCanPublish = false;
        _seenFleetBroadcastIds.Clear();
        _fleetBroadcastHistory.Clear();
        _fleetBroadcastAlertWindow?.Close();
        _fleetBroadcastAlertWindow = null;
        RenderFleetBroadcastPage();
    }

    private async Task HandleFleetBroadcastInvalidationAsync(
        string scopeType,
        long scopeId,
        long resourceVersion)
    {
        if (_fleetBroadcastScope is not { } scope ||
            !scope.ScopeType.Equals(scopeType, StringComparison.OrdinalIgnoreCase) ||
            scope.ScopeId != scopeId ||
            resourceVersion <= _fleetBroadcastResourceVersion)
        {
            return;
        }

        await RefreshFleetBroadcastsAsync(showErrors: false);
    }

    private bool CanUseFleetBroadcasts =>
        _scmOAuthSession is not null &&
        _legacyIdentityLinked == true &&
        _hasFleet &&
        !string.IsNullOrWhiteSpace(_fleetCode);

    private static FleetBroadcastContract ToFleetBroadcastContract(ScmFleetBroadcast item) =>
        new(
            item.Id,
            item.Scope.ScopeId.ToString(CultureInfo.InvariantCulture),
            item.Message,
            new FleetBroadcastAuthorContract(
                item.Author.LegacyAccountId,
                item.Author.Callsign ?? item.Author.GameName ?? "未知成员",
                item.Author.GameName ?? item.Author.Callsign ?? "未知成员",
                item.Author.RoleTitle ?? "成员"),
            new FleetBroadcastAppearanceContract(
                item.Appearance.AccentColor,
                item.Appearance.BackgroundColor,
                item.Appearance.TextColor,
                item.Appearance.DurationSeconds,
                item.Appearance.RepeatCount,
                item.Appearance.FontScale),
            item.CreatedAt,
            item.ExpiresAt);

    private static string DescribeFleetBroadcastMutationFailure(ScmFleetBroadcastMutation mutation) =>
        mutation.ErrorCode switch
        {
            "rate_limited" => $"发送过于频繁，请在 {Math.Max(1, mutation.RetryAfterSeconds)} 秒后重试。",
            "idempotency_conflict" => "这次广播请求与先前请求冲突，请重新发送。",
            "forbidden" => "当前身份没有发送广播权限。",
            _ => "广播发送失败，请稍后重试。"
        };

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
