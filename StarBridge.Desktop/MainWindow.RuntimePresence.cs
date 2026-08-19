using StarBridge.Core.Events;
using StarBridge.Core.Presence;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Net.Http.Json;
using System.Windows;
using System.Windows.Input;
using Brushes = System.Windows.Media.Brushes;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private void RefreshOnboardingSupportPanel()
    {
        // 身份初始化与首次引导已移至专用引导和个人身份页面。
    }

    private async void HomeStatsRefreshButton_Click(object sender, RoutedEventArgs e)
    {
        await RefreshHomeStatsAsync(userInitiated: true);
    }

    private async Task RegisterAppInstallStatsAsync()
    {
        if (_appStatsInstallRegistered || string.IsNullOrWhiteSpace(_appStatsClientId))
        {
            return;
        }

        try
        {
            var request = new AppStatsInstallRequest(_appStatsClientId, GetAppVersion(), "desktop");
            using var response = await _networkClient.PostAsJsonAsync(BuildNetworkUri("api/app-stats/install"), request);
            if (!response.IsSuccessStatusCode)
            {
                return;
            }

            _homeAppStats = await response.Content.ReadFromJsonAsync<AppStatsSnapshot>();
            _appStatsInstallRegistered = true;
            RefreshHomeStatsPanel();
        }
        catch
        {
            // 首页统计不应阻塞启动或登录流程，失败后由定时心跳继续重试。
        }
    }

    private async Task RefreshHomeStatsAsync(bool userInitiated = false)
    {
        try
        {
            if (HomeStatsRefreshButton is not null)
            {
                HomeStatsRefreshButton.IsEnabled = false;
            }

            _homeAppStats = await _networkClient.GetFromJsonAsync<AppStatsSnapshot>(BuildNetworkUri("api/app-stats"));
            RefreshHomeStatsPanel();
        }
        catch (Exception ex)
        {
            if (userInitiated && HomeStatsUpdatedText is not null)
            {
                HomeStatsUpdatedText.Text = UserFacingError.Describe(ex, "统计数据暂时无法刷新，请稍后重试。");
                HomeStatsUpdatedText.Foreground = FindBrush("StatusDangerBrush", Brushes.IndianRed);
            }
        }
        finally
        {
            if (HomeStatsRefreshButton is not null)
            {
                HomeStatsRefreshButton.IsEnabled = true;
            }
        }
    }

    private async Task SendAppStatsHeartbeatAsync()
    {
        if (_isAppStatsHeartbeatRunning ||
            string.IsNullOrWhiteSpace(_appStatsClientId) ||
            _syncPrivacySettings.PresenceVisibilityMode != PlayerPresenceVisibilityMode.Online)
        {
            return;
        }

        UpdateOverlayUsageStatsAccumulator();
        var now = DateTimeOffset.UtcNow;
        if (now - _lastAppStatsHeartbeatAtUtc < TimeSpan.FromSeconds(25) &&
            _pendingOverlayUsageSeconds <= 0)
        {
            return;
        }

        _isAppStatsHeartbeatRunning = true;
        var overlayDelta = Math.Min(_pendingOverlayUsageSeconds, 3600);
        try
        {
            var request = new AppStatsHeartbeatRequest(
                _appStatsClientId,
                GetAppVersion(),
                _overlayWindow?.IsVisible == true,
                overlayDelta);
            using var response = await _networkClient.PostAsJsonAsync(BuildNetworkUri("api/app-stats/heartbeat"), request);
            if (!response.IsSuccessStatusCode)
            {
                return;
            }

            _homeAppStats = await response.Content.ReadFromJsonAsync<AppStatsSnapshot>();
            _pendingOverlayUsageSeconds = Math.Max(0, _pendingOverlayUsageSeconds - overlayDelta);
            _lastAppStatsHeartbeatAtUtc = now;
            _appStatsInstallRegistered = true;
            RefreshHomeStatsPanel();
        }
        catch
        {
            // 统计心跳失败不影响主功能，下次 tick 会继续补传 Overlay 增量。
        }
        finally
        {
            _isAppStatsHeartbeatRunning = false;
        }
    }

    private void UpdateOverlayUsageStatsAccumulator()
    {
        var now = DateTimeOffset.UtcNow;
        if (_lastOverlayStatsSampleAtUtc == DateTimeOffset.MinValue)
        {
            _lastOverlayStatsSampleAtUtc = now;
            return;
        }

        var elapsedSeconds = (long)Math.Floor((now - _lastOverlayStatsSampleAtUtc).TotalSeconds);
        if (elapsedSeconds <= 0)
        {
            return;
        }

        if (_overlayWindow?.IsVisible == true)
        {
            _pendingOverlayUsageSeconds = Math.Min(_pendingOverlayUsageSeconds + elapsedSeconds, 86400);
        }

        _lastOverlayStatsSampleAtUtc = now;
    }

    private void RefreshHomeStatsPanel()
    {
        if (HomeStatsDownloadText is null ||
            HomeStatsOnlineText is null ||
            HomeStatsFleetText is null ||
            HomeStatsOverlayText is null ||
            HomeStatsUpdatedText is null)
        {
            return;
        }

        if (_homeAppStats is null)
        {
            HomeStatsDownloadText.Text = "—";
            HomeStatsOnlineText.Text = "—";
            HomeStatsFleetText.Text = "—";
            HomeStatsOverlayText.Text = "—";
            HomeStatsUpdatedText.Text = "等待服务器统计";
            HomeStatsUpdatedText.Foreground = FindBrush("MutedTextBrush", Brushes.LightSlateGray);
            return;
        }

        HomeStatsDownloadText.Text = FormatCount(_homeAppStats.DownloadCount);
        HomeStatsOnlineText.Text = FormatCount(_homeAppStats.OnlineUserCount);
        HomeStatsFleetText.Text = FormatCount(_homeAppStats.FleetCount);
        HomeStatsOverlayText.Text = FormatOverlayUsageDuration(_homeAppStats.OverlayUsageSeconds);
        HomeStatsUpdatedText.Text = $"最后更新：{_homeAppStats.UpdatedAt.ToLocalTime():yyyy-MM-dd HH:mm}";
        HomeStatsUpdatedText.Foreground = FindBrush("MutedTextBrush", Brushes.LightSlateGray);
    }

    private static string FormatCount(long value)
    {
        return Math.Max(0, value).ToString("N0", CultureInfo.CurrentCulture);
    }

    private static string FormatOverlayUsageDuration(long seconds)
    {
        seconds = Math.Max(0, seconds);
        var duration = TimeSpan.FromSeconds(seconds);
        if (duration.TotalHours >= 1)
        {
            return $"{(long)duration.TotalHours:N0} 小时 {duration.Minutes} 分";
        }

        if (duration.TotalMinutes >= 1)
        {
            return $"{(long)duration.TotalMinutes:N0} 分钟";
        }

        return "0 分钟";
    }

    private static string LoadOrCreateAppStatsClientId()
    {
        var directory = DesktopAppConfig.ConfigDirectory;
        Directory.CreateDirectory(directory);
        var path = Path.Combine(directory, "app-client-id.txt");
        if (File.Exists(path))
        {
            var existing = File.ReadAllText(path).Trim();
            if (!string.IsNullOrWhiteSpace(existing))
            {
                return existing;
            }
        }

        var clientId = Guid.NewGuid().ToString("N");
        File.WriteAllText(path, clientId);
        return clientId;
    }

    private string GetHeaderConnectionStatus()
    {
        if (!IsLoggedIn)
        {
            return "浏览模式";
        }

        if (_syncPrivacySettings.PresenceVisibilityMode == PlayerPresenceVisibilityMode.Offline)
        {
            return "离线模式";
        }

        if (_syncPrivacySettings.PresenceVisibilityMode == PlayerPresenceVisibilityMode.Invisible)
        {
            return "隐身";
        }

        if (_isNetworkSyncRunning)
        {
            return "同步中";
        }

        var status = NetworkStatusText?.Text ?? "";
        if (status.Contains("失败", StringComparison.OrdinalIgnoreCase) ||
            status.Contains("超时", StringComparison.OrdinalIgnoreCase) ||
            status.Contains("异常", StringComparison.OrdinalIgnoreCase))
        {
            return "连接异常";
        }

        if (status.Contains("成功", StringComparison.OrdinalIgnoreCase) ||
            status.Contains("已登录", StringComparison.OrdinalIgnoreCase) ||
            status.Contains("已完成", StringComparison.OrdinalIgnoreCase) ||
            status.Contains("已上传", StringComparison.OrdinalIgnoreCase) ||
            status.Contains("已拉取", StringComparison.OrdinalIgnoreCase) ||
            _syncPrivacySettings.SyncEnabled)
        {
            return "连接正常";
        }

        return "待同步";
    }

    private static string CompactHeaderText(string value, int maxLength)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return "";
        }

        var trimmed = value.Trim().Replace(Environment.NewLine, " / ");
        return trimmed.Length <= maxLength
            ? trimmed
            : $"{trimmed[..Math.Max(0, maxLength - 1)]}…";
    }

    private void TrackAppInteraction(object? sender, PreProcessInputEventArgs args)
    {
        if (args.StagingItem.Input is not (System.Windows.Input.KeyEventArgs or System.Windows.Input.MouseEventArgs or TouchEventArgs or StylusEventArgs))
        {
            return;
        }

        var now = DateTimeOffset.UtcNow;
        if (now - _lastAppInteractionSampleAtUtc < TimeSpan.FromSeconds(1))
        {
            return;
        }

        _lastAppInteractionSampleAtUtc = now;
        _lastAppInteractionAtUtc = now;
        if (_localPresence == PlayerPresenceKind.Away && !_isGameProcessRunning)
        {
            RefreshLocalPresence(now, refreshUi: true, queueNetworkPush: true);
        }
    }

    private bool RefreshLocalPresence(
        DateTimeOffset now,
        bool refreshUi,
        bool queueNetworkPush)
    {
        var next = PlayerPresence.Resolve(
            IsLoggedIn,
            _isGameProcessRunning,
            _lastAppInteractionAtUtc,
            now);
        if (next == _localPresence)
        {
            return false;
        }

        _localPresence = next;
        RefreshHeaderAvatarPresenceDot();
        LocalGameSessionStatePolicy.MarkActiveIfRunning(
            _fleetState,
            _localPlayer,
            _isGameProcessRunning,
            _localPresence,
            now.ToLocalTime());

        if (refreshUi)
        {
            RenderState();
            RefreshLocalPresenceDisplays();
            RefreshHeaderStatusBar();
        }

        if (queueNetworkPush)
        {
            QueueRealtimeNetworkSnapshotPush();
        }

        return true;
    }

    private void RefreshLocalPresenceDisplays()
    {
        if (ProfileStatusText is not null && IsLoggedIn)
        {
            ProfileStatusText.Text = PlayerPresencePresentation.FormatLocal(
                _localPresence,
                _syncPrivacySettings.PresenceVisibilityMode,
                _language);
            ProfileStatusText.Foreground = PlayerPresencePresentation.LocalBrush(
                _localPresence,
                _syncPrivacySettings.PresenceVisibilityMode);
        }

        RefreshHeaderAvatarPresenceDot();
        RefreshPersonalProfileHeaderIdentity();
        RefreshBridgeSceneBandStatus();
    }

    private async Task ApplyPresenceVisibilityModeAsync(PlayerPresenceVisibilityMode mode)
    {
        if (!Enum.IsDefined(mode) || mode == _syncPrivacySettings.PresenceVisibilityMode)
        {
            return;
        }

        _networkRealtimePushTimer.Stop();
        _networkRealtimePushQueued = false;
        _syncPrivacySettings = _syncPrivacySettings with { PresenceVisibilityMode = mode };
        SaveSyncPrivacySettingsAndRefreshDualAxis();
        ApplySyncPrivacySettingsToControls();

        if (mode != PlayerPresenceVisibilityMode.Online)
        {
            await PushOfflineSnapshotOnShutdownAsync();
        }
        else
        {
            _pendingPrivacyOfflineClear = false;
        }

        if (mode == PlayerPresenceVisibilityMode.Offline)
        {
            StopNetworkSyncTimers();
            _partyRoomRefreshTimer?.Stop();
            _relayLatencyTimer.Stop();
            _appStatsTimer.Stop();
            ClearRelayHealthTopNotice();
            NetworkStatusText.Text = "离线模式：即时同步已暂停";
        }
        else
        {
            _partyRoomRefreshTimer?.Start();
            _relayLatencyTimer.Start();
            _ = MeasureRelayLatencyAsync();
            if (mode == PlayerPresenceVisibilityMode.Online)
            {
                _appStatsTimer.Start();
            }
            else
            {
                _appStatsTimer.Stop();
            }
            if (_syncPrivacySettings.SyncEnabled)
            {
                StartNetworkSyncTimers();
            }

            if (mode == PlayerPresenceVisibilityMode.Online)
            {
                QueueRealtimeNetworkSnapshotPush();
                NetworkStatusText.Text = "在线：即时状态同步已恢复";
            }
            else
            {
                NetworkStatusText.Text = "隐身模式：对外显示离线，不上传即时状态";
            }
        }

        RenderState();
        RefreshLocalPresenceDisplays();
        RefreshAccountPanel();
        RefreshHeaderStatusBar();
    }

    private void UpdateLocalOnlineStateFromGameProcess()
    {
        var stopwatch = Stopwatch.StartNew();
        try
        {
            var now = DateTimeOffset.UtcNow;
            var wasRunning = _isGameProcessRunning;
            var processObserved = StarCitizenProcessProbe.TryGetStart(out var gameProcessStartedAtUtc);
            var processObservation = GameProcessSessionBoundaryPolicy.Observe(
                wasRunning,
                processObserved,
                now,
                _gameProcessMissingSinceUtc);
            _isGameProcessRunning = processObservation.IsRunning;
            _gameProcessMissingSinceUtc = processObservation.MissingSinceUtc;
            _bridgeGameProcessStartedAtUtc = _isGameProcessRunning
                ? gameProcessStartedAtUtc ?? _bridgeGameProcessStartedAtUtc ?? now
                : null;
            if (wasRunning != _isGameProcessRunning)
            {
                RecordLocalGameProcessEvent(_isGameProcessRunning, now);
            }
            BindGameplayStatisticsOwner();
            _gameplayStatisticsRecorder.ObserveGameProcess(_isGameProcessRunning, now);
            QueueGameplayStatisticsSync(now);
            var isGameForeground = _isGameProcessRunning && StarCitizenProcessProbe.IsForeground();
            var serverStateChanged = ExpireGameServerRegionIfNeeded();
            UpdateOverlayGameAutomation(wasRunning, _isGameProcessRunning, isGameForeground);
            QueueLocalPlaySessionReminderIfDue(now, gameProcessStartedAtUtc);

            if (processObservation.SessionEnded && !string.IsNullOrWhiteSpace(_localPlayer))
            {
                _fleetState.Apply(new FleetEvent(FleetEventType.PlayerOffline, _localPlayer));
            }

            var presenceChanged = RefreshLocalPresence(
                now,
                refreshUi: false,
                queueNetworkPush: false);
            var shouldRefresh = wasRunning != _isGameProcessRunning || serverStateChanged || presenceChanged;
            if (shouldRefresh)
            {
                RenderState();
                RefreshLocalPresenceDisplays();
                RefreshHeaderStatusBar();
                RefreshGameplayStatisticsPresentation();
            }

            RefreshBridgeSceneBandStatus();

            if (presenceChanged)
            {
                QueueRealtimeNetworkSnapshotPush();
            }
        }
        finally
        {
            LogOverlayPerformance("game-process-refresh", stopwatch);
        }
    }

    private void UpdateOverlayGameAutomation(bool wasRunning, bool isRunning, bool isGameForeground)
    {
        var settings = GetEffectiveOverlaySettings();
        var overlayVisible = _overlayWindow is { IsVisible: true };
        if (settings.AutoCloseOverlayOnGameBackground &&
            isRunning &&
            !isGameForeground)
        {
            if (overlayVisible)
            {
                AppendOutput("OVERLAY | automation close: game window background.");
                CloseOverlayWindow();
                RefreshPersonalIdentityConsole();
                RefreshOverlayOverviewSummary();
            }

            return;
        }

        if (overlayVisible || !isRunning)
        {
            return;
        }

        if (settings.AutoOpenOverlayOnGameStart && !wasRunning)
        {
            AppendOutput("OVERLAY | automation open: game started.");
            OpenOverlayWindowFromAutomation(settings, isGameForeground);
            return;
        }

        if (settings.AutoOpenOverlayOnGameForeground && isGameForeground)
        {
            AppendOutput("OVERLAY | automation open: game window foreground.");
            OpenOverlayWindowFromAutomation(settings, isGameForeground);
        }
    }

    private void OpenOverlayWindowFromAutomation(OverlayDisplaySettings settings, bool isGameForeground)
    {
        var opened = OpenOverlayWindow(settings);
        if (opened && settings.AutoFocusGameWindowOnOpen && !isGameForeground)
        {
            ScheduleGameFocusAfterOverlayStartup(settings);
        }

        RefreshPersonalIdentityConsole();
        RefreshOverlayOverviewSummary();
    }

    private bool TryFocusStarCitizenWindow()
    {
        var stopwatch = Stopwatch.StartNew();
        try
        {
            OverlayHwndDiagnostics.LogForegroundWindow("game-focus-before");
            if (StarCitizenProcessProbe.IsForeground())
            {
                AppendOutput("OVERLAY | game window already active; focus request skipped.");
                OverlayHwndDiagnostics.LogForegroundWindow("game-focus-already-active");
                return false;
            }

            var handle = StarCitizenProcessProbe.FindMainWindow();
            if (handle == IntPtr.Zero)
            {
                AppendOutput("OVERLAY | game window focus skipped: Star Citizen window not found.");
                OverlayHwndDiagnostics.LogForegroundWindow("game-focus-window-missing");
                return false;
            }

            try
            {
                // OS-level focus request only: no input simulation, hooks, injection, or game-memory access.
                ShowWindow(handle, ShowWindowRestore);
                if (!SetForegroundWindow(handle))
                {
                    AppendOutput("OVERLAY | game window focus requested but Windows denied foreground activation.");
                    OverlayHwndDiagnostics.LogForegroundWindow("game-focus-denied");
                    return false;
                }

                AppendOutput("OVERLAY | switched to Star Citizen window.");
                OverlayHwndDiagnostics.LogForegroundWindow("game-focus-after");
                return true;
            }
            catch (Exception exception)
            {
                App.WriteCrashLog(exception);
                AppendOutput($"OVERLAY | game window focus failed: {exception.Message}");
                OverlayHwndDiagnostics.LogForegroundWindow("game-focus-exception");
                return false;
            }
        }
        finally
        {
            LogOverlayPerformance("focus-game-window", stopwatch, force: true);
        }
    }

}
