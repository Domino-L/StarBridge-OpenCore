using StarBridge.Core.Events;
using StarBridge.Core.Presence;
using System.Diagnostics;
using System.Net;
using System.Net.Http;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;
using Color = System.Windows.Media.Color;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private async void NetworkTestButton_Click(object sender, RoutedEventArgs e)
    {
        await TestNetworkAsync();
    }

    private async void LoginButton_Click(object sender, RoutedEventArgs e)
    {
        await ShowLoginDialogAsync();
        if (IsLoggedIn)
        {
            await AutoConnectNetworkAsync();
            NotifyGuidedTourAction(GuideStep.LoginFirst);
        }
    }

    private void HeaderAccountButton_Click(object sender, RoutedEventArgs e)
    {
        HeaderAccountMenu.PlacementTarget = PersonalNavButton;
        HeaderAccountMenu.IsOpen = true;
        NotifyGuidedTourAction(GuideStep.OpenAccountMenu);
        e.Handled = true;
    }

    private void HeaderIdentityMenuItem_Click(object sender, RoutedEventArgs e)
    {
        OpenPersonalIdentitySettings_Click(sender, e);
        NotifyGuidedTourAction(GuideStep.OpenIdentitySettings);
    }

    private void HeaderProfileMenuItem_Click(object sender, RoutedEventArgs e) =>
        PersonalNav_Click(sender, e);

    private void ClearAuthenticatedLocalState()
    {
        _isAccountTransition = true;
        _accountSessionCoordinator.End();
        BeginInGameWorkspaceAccountSession(
            _accountSessionCoordinator.Capture(),
            signedIn: false);
        try
        {
            ResetAccountScopedState("登录后即可查看组织通讯。");
            ResetAccountAvatarState();
            _authToken = null;
            _accountId = null;
            ReloadDualAxisPrivacySettings();
            _gameIdVisibilityPreference = GameIdVisibilityPolicy.Normalize(null, _localPlayer, null);
            ApplyGameIdVisibilityToEditor();
            _accountEntitlements.Clear();
            _temporaryEntitlements.Clear();
            _temporaryEntitlementTimer.Stop();
            _entitlementRefreshTimer.Stop();
            _pendingOverlayAppearanceUnlockNotices.Clear();
            _queuedOverlayAppearanceUnlockKeys.Clear();
            CompleteOverlayAppearanceUnlockNotice(useNow: false, scheduleNext: false);
            ResetIdentityBindingSession();
            RefreshDirectMessagePrivacyAuthenticationState();
            ApplyOverlayEntitlementState();
            RefreshPersonalApplicationSettings();
        }
        finally
        {
            _isAccountTransition = false;
        }
    }

    private void ResetAccountScopedState(string fleetChatStatus)
    {
        StopNetworkSyncTimers();
        ResetFleetActivityAccountSession();
        ResetStartupDataGate();
        _profileSyncDebounceTimer.Stop();
        EndPersonalProfileAccountSession();
        ResetOverlayRosterSelectionAccountSession();

        _pendingFleetApplicationCodes.Clear();
        _findFleetJoinInProgressCodes.Clear();
        _sharedLifeEvents.Clear();
        _lastNetworkPlayerSnapshotFingerprint = null;
        ClearPartyRoomState();
        ClearFleetState();
        ResetFleetChat(fleetChatStatus);
        ResetFriendCenterAccountState();
        ResetHangarManagementPage();
        _privateVisibilityGroups.Clear();
        DualAxisPrivacyEditor?.SetGroups(_privateVisibilityGroups);

        _allNetworkFleets.Clear();
        _networkFleets.Clear();
        _fleetDirectoryState.InvalidateLoads();
        ApplyFleetSearchFilter();
        RefreshFleetDirectoryViewState();
        ResetFleetOverlayChatProjection();
    }

    private void LogoutButton_Click(object sender, RoutedEventArgs e)
    {
        _authenticationExpired = false;
        StopNetworkSyncTimers();
        ClearAuthenticatedLocalState();
        SaveCurrentConfig(clearSavedSession: true);
        RefreshAccountPanel();
        UpdateFleetEntryPanels();
        RenderState();
        LoginStatusText.Text = "已退出登录，当前为浏览模式";
        NetworkStatusText.Text = "浏览模式：同步已关闭";
        RefreshHeaderStatusBar();
    }

    private async void NetworkPushButton_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureLoggedIn("上传本机状态需要先登录。"))
        {
            return;
        }

        if (!await EnsureSyncConsentAsync())
        {
            NetworkStatusText.Text = "本机状态同步未启用";
            return;
        }

        await PushLocalSnapshotAsync(pushFleetDirectory: false);
    }

    private async void NetworkPullButton_Click(object sender, RoutedEventArgs e)
    {
        if (_startupDataGate.Current.State != StartupDataGateState.Live)
        {
            await AutoConnectNetworkAsync();
            return;
        }

        await PullNetworkFleetsAsync();
        await PullNetworkSnapshotsAsync();
    }

    private async Task<bool> EnsureSyncConsentAsync()
    {
        if (_syncPrivacySettings.SyncConsentCompleted &&
            _syncPrivacySettings.SyncConsentVersion >= CurrentSyncConsentVersion)
        {
            return true;
        }

        var result = await ShowSyncChoiceAsync(
            "选择同步范围",
            "首次启用前，请决定哪些本地状态可以参与 StarBridge 组织协作。个人机库需要单独授权。",
            resetPersonalHangar: true,
            confirmText: "保存选择");
        return result is not null;
    }

    private bool HasAnyGameStateSyncEnabled()
    {
        return _syncPrivacySettings.SyncEnabled &&
              (_syncPrivacySettings.SyncOnlineStatus ||
               _syncPrivacySettings.SyncShipStatus ||
               _syncPrivacySettings.SyncLocationStatus ||
               _syncPrivacySettings.SyncServerInfo ||
               _syncPrivacySettings.PersonalHangarVisible);
    }

    private Task<SyncChoiceResult?> ShowSyncChoiceAsync(
        string title,
        string context,
        bool resetPersonalHangar,
        string confirmText)
    {
        _syncChoiceSource?.TrySetResult(null);
        _syncChoiceSource = new TaskCompletionSource<SyncChoiceResult?>(TaskCreationOptions.RunContinuationsAsynchronously);

        SyncChoiceTitleText.Text = title;
        SyncChoiceContextText.Text = context;
        SyncChoiceSaveButton.Content = confirmText;
        SyncChoiceMasterCheck.IsChecked = _syncPrivacySettings.SyncEnabled;
        SyncChoiceOnlineCheck.IsChecked = _syncPrivacySettings.SyncOnlineStatus;
        SyncChoiceShipCheck.IsChecked = _syncPrivacySettings.SyncShipStatus;
        SyncChoiceLocationCheck.IsChecked = _syncPrivacySettings.SyncLocationStatus;
        SyncChoiceServerCheck.IsChecked = _syncPrivacySettings.SyncServerInfo;
        SyncChoiceHangarCheck.IsChecked = resetPersonalHangar
            ? false
            : _syncPrivacySettings.PersonalHangarVisible;
        ApplySyncChoiceVisibilityScope(_syncPrivacySettings.EffectiveVisibilityScope);
        UpdateSyncChoiceEnabledState();
        SyncChoiceOverlay.Visibility = Visibility.Visible;
        SyncChoiceSaveButton.Focus();
        return _syncChoiceSource.Task;
    }

    private void ApplySyncChoiceVisibilityScope(SyncPrivacyVisibilityScope scope)
    {
        SyncChoiceScopePrivateRadio.IsChecked = scope == SyncPrivacyVisibilityScope.Private;
        SyncChoiceScopeAdminRadio.IsChecked = scope == SyncPrivacyVisibilityScope.AdminOnly;
        SyncChoiceScopeSpecifiedRadio.IsChecked = scope == SyncPrivacyVisibilityScope.SpecifiedMembers;
        SyncChoiceScopeFleetRadio.IsChecked = scope == SyncPrivacyVisibilityScope.Fleet;
    }

    private SyncPrivacyVisibilityScope GetSyncChoiceVisibilityScope()
    {
        if (SyncChoiceScopeFleetRadio.IsChecked == true)
        {
            return SyncPrivacyVisibilityScope.Fleet;
        }

        if (SyncChoiceScopeSpecifiedRadio.IsChecked == true)
        {
            return SyncPrivacyVisibilityScope.SpecifiedMembers;
        }

        if (SyncChoiceScopeAdminRadio.IsChecked == true)
        {
            return SyncPrivacyVisibilityScope.AdminOnly;
        }

        return SyncPrivacyVisibilityScope.Private;
    }

    private void SyncChoiceMasterCheck_Changed(object sender, RoutedEventArgs e)
    {
        UpdateSyncChoiceEnabledState();
    }

    private void UpdateSyncChoiceEnabledState()
    {
        if (SyncChoiceOptionsHost is null)
        {
            return;
        }

        var enabled = SyncChoiceMasterCheck.IsChecked == true;
        SyncChoiceOptionsHost.IsEnabled = enabled;
        SyncChoiceOptionsHost.Opacity = enabled ? 1 : 0.48;
        SyncChoiceScopeHost.IsEnabled = enabled;
        SyncChoiceScopeHost.Opacity = enabled ? 1 : 0.48;
    }

    private void SyncChoiceSaveButton_Click(object sender, RoutedEventArgs e)
    {
        var enabled = SyncChoiceMasterCheck.IsChecked == true;
        var result = new SyncChoiceResult(
            enabled,
            SyncChoiceOnlineCheck.IsChecked == true,
            SyncChoiceShipCheck.IsChecked == true,
            SyncChoiceLocationCheck.IsChecked == true,
            SyncChoiceServerCheck.IsChecked == true,
            SyncChoiceHangarCheck.IsChecked == true,
            GetSyncChoiceVisibilityScope());
        ApplySyncChoiceResult(result);
        CompleteSyncChoice(result);
    }

    private void SyncChoiceCancelButton_Click(object sender, RoutedEventArgs e)
    {
        CompleteSyncChoice(null);
    }

    private void CompleteSyncChoice(SyncChoiceResult? result)
    {
        var source = _syncChoiceSource;
        _syncChoiceSource = null;
        SyncChoiceOverlay.Visibility = Visibility.Collapsed;
        source?.TrySetResult(result);
    }

    private void ApplySyncChoiceResult(SyncChoiceResult result)
    {
        var wasEnabled = _syncPrivacySettings.SyncEnabled;
        var scope = result.VisibilityScope;
        _syncPrivacySettings = ApplyFleetActionSettingsLock(_syncPrivacySettings with
        {
            SyncEnabled = result.SyncEnabled,
            SyncOnlineStatus = result.SyncOnlineStatus,
            SyncShipStatus = result.SyncShipStatus,
            SyncLocationStatus = result.SyncLocationStatus,
            SyncServerInfo = result.SyncServerInfo,
            PersonalHangarVisible = result.PersonalHangarVisible,
            VisibilityScope = scope,
            SyncConsentCompleted = true,
            SyncConsentVersion = CurrentSyncConsentVersion
        }).NormalizeVisibilityScope();
        SaveSyncPrivacySettingsAndRefreshDualAxis();
        ApplySyncPrivacySettingsToControls();
        UpdateShipDatabaseSummary();
        if (wasEnabled && !result.SyncEnabled && IsLoggedIn)
        {
            _ = PushLocalSnapshotAsync(
                silent: true,
                pushFleetDirectory: false,
                forcePrivacyClear: true);
        }

        ApplyNetworkSyncMasterState();
    }

    private void ApplyNetworkSyncMasterState()
    {
        if (_syncPrivacySettings.SyncEnabled)
        {
            StartNetworkSyncTimers();
        }
        else
        {
            StopNetworkSyncTimers();
        }
    }

    private void StartNetworkSyncTimers()
    {
        if (CanSynchronizeUserData && GetPresenceSharingDecision().CanReceiveRealtime)
        {
            _networkSyncTimer.Start();
            _networkPlayerRealtimePullTimer.Start();
            StartFleetActivityLoop();
        }
        else
        {
            StopNetworkDataSyncTimers();
        }

        if (CanPublishPresenceHeartbeat())
        {
            _presenceHeartbeatTimer.Start();
            _ = SendPresenceHeartbeatAsync();
        }
        else
        {
            _presenceHeartbeatTimer.Stop();
        }

        RefreshBridgeSceneBandStatus();
    }

    private void StopNetworkDataSyncTimers()
    {
        _networkSyncTimer.Stop();
        _networkPlayerRealtimePullTimer.Stop();
        StopFleetActivityLoop();
        _networkRealtimePushTimer.Stop();
        _networkRealtimePushQueued = false;
    }

    private void StopNetworkSyncTimers()
    {
        StopNetworkDataSyncTimers();
        _presenceHeartbeatTimer.Stop();
        ClearPresenceHeartbeatFailure();
        RefreshBridgeSceneBandStatus();
    }

    private bool CanReceiveRealtimePlayerSync()
    {
        // Realtime member rows are account-scoped user data and intentionally remain behind
        // verified identity. The minimal presence heartbeat is weaker and does not inherit this gate.
        return IsLoggedIn &&
               CanSynchronizeUserData &&
               _syncPrivacySettings.SyncEnabled &&
               GetPresenceSharingDecision().CanReceiveRealtime &&
               DateTimeOffset.UtcNow >= _nextNetworkSyncAt;
    }

    private bool CanPublishRealtimePlayerSync() =>
        CanReceiveRealtimePlayerSync() && GetPresenceSharingDecision().CanPublishRealtime;

    private bool CanPublishPresenceHeartbeat()
    {
        return IsLoggedIn &&
               !_isAccountTransition &&
               _syncPrivacySettings.SyncEnabled &&
               GetPresenceSharingDecision().CanPublishRealtime;
    }

    private async Task SendPresenceHeartbeatAsync()
    {
        if (_isPresenceHeartbeatRunning)
        {
            return;
        }

        if (!CanPublishPresenceHeartbeat())
        {
            return;
        }

        _isPresenceHeartbeatRunning = true;
        try
        {
            var projection = GetLocalFleetPresencePrivacyProjection();
            using var response = await PostNetworkJsonAsync(
                "api/players/heartbeat",
                new PlayerPresenceHeartbeatRequest(projection.Online, projection.LiveStatus));

            if (HandleAuthorizationFailure(response.StatusCode, "在线状态同步", silent: true))
            {
                return;
            }

            if (response.StatusCode == HttpStatusCode.NotFound)
            {
                var restored = await PushLocalSnapshotAsync(silent: true, pushFleetDirectory: false);
                if (restored)
                {
                    ClearPresenceHeartbeatFailure();
                }
                else
                {
                    RegisterPresenceHeartbeatFailure();
                }

                return;
            }

            if (!response.IsSuccessStatusCode)
            {
                RegisterPresenceHeartbeatFailure();
                return;
            }

            ClearPresenceHeartbeatFailure();
        }
        catch (Exception ex)
        {
            if (!HandleAuthorizationFailure(ex, "在线状态同步", silent: true))
            {
                RegisterPresenceHeartbeatFailure();
            }
        }
        finally
        {
            _isPresenceHeartbeatRunning = false;
        }
    }

    private void RegisterPresenceHeartbeatFailure()
    {
        _presenceHeartbeatFailureCount = Math.Min(_presenceHeartbeatFailureCount + 1, 3);
        if (_presenceHeartbeatFailureCount < 2)
        {
            return;
        }

        _presenceHeartbeatTopNotice = new TopStatusNotice(
            "在线状态同步中断",
            "其他玩家可能暂时看到你处于离线状态；应用会自动重试，也可立即重试。",
            SyncStatusOverlayTone.Warning,
            ShowRetry: true);
        NetworkStatusText.Text = "在线状态同步中断，正在自动重试";
        RenderTopStatusNotice();
        RefreshHeaderStatusBar();
    }

    private void ClearPresenceHeartbeatFailure()
    {
        var wasInterrupted = _presenceHeartbeatTopNotice is not null;
        _presenceHeartbeatFailureCount = 0;
        _presenceHeartbeatTopNotice = null;
        if (!wasInterrupted)
        {
            return;
        }

        NetworkStatusText.Text = "在线状态同步已恢复";
        RenderTopStatusNotice();
        RefreshHeaderStatusBar();
    }

    private async Task NetworkPlayerRealtimePullAsync()
    {
        if (!CanReceiveRealtimePlayerSync() ||
            _isNetworkSyncRunning ||
            _isNetworkRealtimePullRunning ||
            _isNetworkRealtimePushRunning)
        {
            return;
        }

        _isNetworkRealtimePullRunning = true;
        try
        {
            var pulled = await PullNetworkSnapshotsAsync(silent: true);
            if (!pulled && _syncPrivacySettings.SyncEnabled && IsLoggedIn)
            {
                DeferNetworkSync();
                VerifyRelayHealthAfterSynchronizationFailure();
                RefreshHeaderStatusBar();
            }
        }
        finally
        {
            _isNetworkRealtimePullRunning = false;
        }
    }

    private void QueueRealtimeNetworkSnapshotPush()
    {
        if (!CanPublishRealtimePlayerSync() ||
            string.IsNullOrWhiteSpace(_localPlayer))
        {
            return;
        }

        _networkRealtimePushQueued = true;
        ArmRealtimeNetworkSnapshotPushTimer();
    }

    private void ArmRealtimeNetworkSnapshotPushTimer()
    {
        var interval = NetworkRealtimePushDebounce;
        if (_lastNetworkRealtimePushAt != DateTimeOffset.MinValue)
        {
            var throttleRemaining = NetworkRealtimePushMinimumInterval - (DateTimeOffset.UtcNow - _lastNetworkRealtimePushAt);
            if (throttleRemaining > interval)
            {
                interval = throttleRemaining;
            }
        }

        if (interval < TimeSpan.FromMilliseconds(50))
        {
            interval = TimeSpan.FromMilliseconds(50);
        }

        _networkRealtimePushTimer.Interval = interval;
        _networkRealtimePushTimer.Stop();
        _networkRealtimePushTimer.Start();
    }

    private async Task FlushRealtimeNetworkSnapshotPushAsync()
    {
        _networkRealtimePushTimer.Stop();
        if (!_networkRealtimePushQueued)
        {
            return;
        }

        if (!CanPublishRealtimePlayerSync() ||
            string.IsNullOrWhiteSpace(_localPlayer))
        {
            _networkRealtimePushQueued = false;
            return;
        }

        if (_isNetworkSyncRunning ||
            _isNetworkRealtimePullRunning ||
            _isNetworkRealtimePushRunning)
        {
            ArmRealtimeNetworkSnapshotPushTimer();
            return;
        }

        _networkRealtimePushQueued = false;
        _isNetworkRealtimePushRunning = true;
        try
        {
            var pushed = await PushLocalSnapshotAsync(silent: true, pushFleetDirectory: false);
            if (pushed)
            {
                _lastNetworkRealtimePushAt = DateTimeOffset.UtcNow;
            }
            else if (_syncPrivacySettings.SyncEnabled && IsLoggedIn)
            {
                DeferNetworkSync();
                VerifyRelayHealthAfterSynchronizationFailure();
                RefreshHeaderStatusBar();
            }
        }
        finally
        {
            _isNetworkRealtimePushRunning = false;
            if (_networkRealtimePushQueued)
            {
                ArmRealtimeNetworkSnapshotPushTimer();
            }
        }
    }

    private bool ShouldQueueRealtimeNetworkSnapshotPush(FleetEvent fleetEvent, bool gameServerChanged)
    {
        if (gameServerChanged)
        {
            return true;
        }

        if (!IsRealtimeNetworkSnapshotEvent(fleetEvent.Type))
        {
            return false;
        }

        return IsLocalPlayer(fleetEvent.Player);
    }

    private static bool IsRealtimeNetworkSnapshotEvent(FleetEventType eventType)
    {
        return eventType is FleetEventType.PlayerOnline
            or FleetEventType.PlayerOffline
            or FleetEventType.PlayerEnteredShip
            or FleetEventType.PlayerExitedShip
            or FleetEventType.PlayerControllingShip
            or FleetEventType.PlayerShipControlSignal
            or FleetEventType.PlayerStoppedDrivingShip
            or FleetEventType.PlayerLocationChanged
            or FleetEventType.PlayerNavigationTargetChanged;
    }

    private async Task NetworkAutoSyncAsync()
    {
        if (!_syncPrivacySettings.SyncEnabled || !CanSynchronizeUserData)
        {
            RefreshHeaderStatusBar();
            return;
        }

        var sharing = GetPresenceSharingDecision();
        if (!sharing.CanReceiveRealtime)
        {
            RefreshHeaderStatusBar();
            return;
        }

        if (_isNetworkSyncRunning ||
            _isNetworkRealtimePullRunning ||
            _isNetworkRealtimePushRunning)
        {
            return;
        }

        if (DateTimeOffset.UtcNow < _nextNetworkSyncAt)
        {
            return;
        }

        _isNetworkSyncRunning = true;
        try
        {
            if (_pendingPrivacyOfflineClear)
            {
                await PushOfflineSnapshotOnShutdownAsync();
            }

            var pulledFleets = await PullNetworkFleetsAsync(
                silent: true,
                refreshBehavior: FleetDirectoryRefreshBehavior.PreserveVisibleOrder);
            var pulledPlayers = await PullNetworkSnapshotsAsync(silent: true);
            var pushedLocal = sharing.CanPublishRealtime
                ? await PushLocalSnapshotAsync(silent: true, pushFleetDirectory: false)
                : !_pendingPrivacyOfflineClear;
            if (pushedLocal || pulledFleets || pulledPlayers)
            {
                _networkSyncFailureCount = 0;
                _nextNetworkSyncAt = DateTimeOffset.MinValue;
                HideSyncStatusOverlay();
                HideNetworkSyncIssueDialog();
                RefreshHeaderStatusBar();
            }
            else
            {
                DeferNetworkSync();
                VerifyRelayHealthAfterSynchronizationFailure();
                RefreshHeaderStatusBar();
            }
        }
        catch
        {
            DeferNetworkSync();
            VerifyRelayHealthAfterSynchronizationFailure();
            RefreshHeaderStatusBar();
        }
        finally
        {
            _isNetworkSyncRunning = false;
        }
    }

    private void DeferNetworkSync()
    {
        _networkSyncFailureCount = Math.Min(_networkSyncFailureCount + 1, 5);
        var delaySeconds = Math.Min(15 * _networkSyncFailureCount, 90);
        _nextNetworkSyncAt = DateTimeOffset.UtcNow.AddSeconds(delaySeconds);
    }

    private CancellationTokenSource BeginSyncStatusSlowNotice()
    {
        var previous = _syncStatusOverlayCts;
        _syncStatusOverlayCts = null;
        previous?.Cancel();
        previous?.Dispose();
        var cts = new CancellationTokenSource();
        _syncStatusOverlayCts = cts;
        _ = ShowSlowSyncNoticeAsync(cts.Token);
        return cts;
    }

    private void CompleteSyncStatusSlowNotice(CancellationTokenSource owner)
    {
        // A newer synchronization attempt owns the slot after replacing this
        // token source. BeginSyncStatusSlowNotice has already cancelled and
        // disposed the old owner in that case, so the old continuation must
        // not touch it again.
        if (!ReferenceEquals(_syncStatusOverlayCts, owner))
        {
            return;
        }

        _syncStatusOverlayCts = null;
        owner.Cancel();
        owner.Dispose();
    }

    private async Task ShowSlowSyncNoticeAsync(CancellationToken cancellationToken)
    {
        try
        {
            await Task.Delay(TimeSpan.FromSeconds(4), cancellationToken);
            await Dispatcher.InvokeAsync(() =>
            {
                if (cancellationToken.IsCancellationRequested || SyncStatusOverlay.Visibility != Visibility.Visible)
                {
                    return;
                }

                _syncTopNotice = new TopStatusNotice(
                    "同步仍在进行",
                    "正在等待服务器响应，当前界面会继续保留本地数据。",
                    SyncStatusOverlayTone.Warning,
                    ShowRetry: false);
                RenderTopStatusNotice();
            });
        }
        catch (TaskCanceledException)
        {
            // Expected when the sync finishes quickly.
        }
    }

    private enum SyncStatusOverlayTone
    {
        Info,
        Warning,
        Danger,
        Success
    }

    private sealed record TopStatusNotice(
        string Title,
        string Detail,
        SyncStatusOverlayTone Tone,
        bool ShowRetry);

    private TopStatusNotice? _syncTopNotice;
    private TopStatusNotice? _relayHealthTopNotice;
    private TopStatusNotice? _relayRecoveryTopNotice;
    private TopStatusNotice? _presenceHeartbeatTopNotice;

    private static SolidColorBrush CreateOverlayBrush(string hex)
    {
        return new SolidColorBrush((Color)System.Windows.Media.ColorConverter.ConvertFromString(hex));
    }

    private void ApplySyncStatusOverlayTone(SyncStatusOverlayTone tone)
    {
        if (SyncStatusOverlay is null ||
            SyncOverlayStatusDot is null ||
            SyncOverlayTitleText is null ||
            SyncOverlayDetailText is null)
        {
            return;
        }

        var (background, border, accent, detail) = tone switch
        {
            SyncStatusOverlayTone.Danger => ("#E0141117", "#D4FF6974", "#FFFF6974", "#FFE2ECF3"),
            SyncStatusOverlayTone.Warning => ("#DE171408", "#C4FFC95B", "#FFFFC95B", "#FFDFD2A8"),
            SyncStatusOverlayTone.Success => ("#DE06170F", "#B55DE9A0", "#FF62F6A4", "#FFB9DFC9"),
            _ => ("#C806101A", "#8A4CBFFF", "#FF69CCFF", "#FF9EBBD1")
        };

        var accentBrush = CreateOverlayBrush(accent);
        SyncStatusOverlay.Background = CreateOverlayBrush(background);
        SyncStatusOverlay.BorderBrush = CreateOverlayBrush(border);
        SyncOverlayStatusDot.Fill = accentBrush;
        SyncOverlayTitleText.Foreground = accentBrush;
        SyncOverlayDetailText.Foreground = CreateOverlayBrush(detail);
    }

    private void ShowSyncStatusOverlay(string title, string detail, bool showRetry)
    {
        _syncTopNotice = new TopStatusNotice(
            title,
            detail,
            showRetry || title.Contains("失败", StringComparison.OrdinalIgnoreCase)
                ? SyncStatusOverlayTone.Danger
                : title.Contains("仍在进行", StringComparison.OrdinalIgnoreCase)
                    ? SyncStatusOverlayTone.Warning
                    : SyncStatusOverlayTone.Info,
            showRetry);
        RenderTopStatusNotice();
    }

    private void HideSyncStatusOverlay()
    {
        var slowNotice = _syncStatusOverlayCts;
        _syncStatusOverlayCts = null;
        slowNotice?.Cancel();
        slowNotice?.Dispose();
        _syncTopNotice = null;
        RenderTopStatusNotice();
    }

    private void VerifyRelayHealthAfterSynchronizationFailure()
    {
        var decision = RelayHealthPresentationPolicy.ObserveDataSynchronizationFailure(
            _relayServiceHealthState,
            _relayHealthConsecutiveFailures);
        _relayHealthConsecutiveFailures = decision.ConsecutiveProbeFailures;
        if (decision.ShouldRequestProbe)
        {
            _ = MeasureRelayLatencyAsync();
        }
    }

    private void ApplyRelayHealthProbeResult(RelayHealthProbeResult result)
    {
        _lastRelayLatencyMs = result.IsConnected
            ? Math.Max(1, result.LatencyMilliseconds)
            : -1;

        var decision = RelayHealthPresentationPolicy.ObserveHealthProbe(
            _relayServiceHealthState,
            _relayHealthConsecutiveFailures,
            result.State);
        _relayHealthConsecutiveFailures = decision.ConsecutiveProbeFailures;
        if (result.State is RelayServiceHealthState.Healthy or RelayServiceHealthState.Degraded)
        {
            _lastSuccessfulRelayHealthAt = DateTimeOffset.UtcNow;
        }

        SetRelayServiceHealthState(decision.State);
    }

    private void SetRelayServiceHealthState(RelayServiceHealthState state)
    {
        var previous = _relayServiceHealthState;
        _relayServiceHealthState = state;
        _relayHealthTopNotice = state switch
        {
            RelayServiceHealthState.Degraded => new TopStatusNotice(
                "服务器繁忙",
                "部分同步功能可能延迟，应用会继续自动重试。",
                SyncStatusOverlayTone.Warning,
                ShowRetry: false),
            RelayServiceHealthState.Unhealthy => new TopStatusNotice(
                "服务器状态异常",
                "在线功能暂时不可用，本地功能仍可继续使用。",
                SyncStatusOverlayTone.Danger,
                ShowRetry: true),
            RelayServiceHealthState.Unreachable => new TopStatusNotice(
                "无法连接服务器",
                BuildRelayUnavailableDetail(),
                SyncStatusOverlayTone.Danger,
                ShowRetry: true),
            _ => null
        };

        if (state == RelayServiceHealthState.Healthy &&
            previous is RelayServiceHealthState.Degraded or
                RelayServiceHealthState.Unhealthy or
                RelayServiceHealthState.Unreachable)
        {
            ShowRelayRecoveryNotice();
        }

        RenderTopStatusNotice();
    }

    private string BuildRelayUnavailableDetail() =>
        _lastSuccessfulRelayHealthAt == DateTimeOffset.MinValue
            ? "本地功能仍可使用，应用正在自动重试。"
            : $"本地功能仍可使用；上次连接成功于 {_lastSuccessfulRelayHealthAt.ToLocalTime():HH:mm:ss}。";

    private void ShowRelayRecoveryNotice()
    {
        var previous = _relayRecoveryNoticeCts;
        _relayRecoveryNoticeCts = null;
        previous?.Cancel();
        previous?.Dispose();

        _relayRecoveryTopNotice = new TopStatusNotice(
            "服务器连接已恢复",
            "在线同步已经重新开始。",
            SyncStatusOverlayTone.Success,
            ShowRetry: false);
        var cts = new CancellationTokenSource();
        _relayRecoveryNoticeCts = cts;
        _ = HideRelayRecoveryNoticeAsync(cts);
    }

    private async Task HideRelayRecoveryNoticeAsync(CancellationTokenSource owner)
    {
        try
        {
            await Task.Delay(TimeSpan.FromSeconds(4), owner.Token);
            await Dispatcher.InvokeAsync(() =>
            {
                if (!ReferenceEquals(_relayRecoveryNoticeCts, owner))
                {
                    return;
                }

                _relayRecoveryNoticeCts = null;
                _relayRecoveryTopNotice = null;
                owner.Dispose();
                RenderTopStatusNotice();
            });
        }
        catch (TaskCanceledException)
        {
            // A newer recovery notice replaced this one.
        }
    }

    private void ClearRelayHealthTopNotice()
    {
        _relayServiceHealthState = RelayServiceHealthState.Unknown;
        _relayHealthConsecutiveFailures = 0;
        _relayHealthTopNotice = null;
        _relayRecoveryTopNotice = null;
        var recovery = _relayRecoveryNoticeCts;
        _relayRecoveryNoticeCts = null;
        recovery?.Cancel();
        recovery?.Dispose();
        RenderTopStatusNotice();
    }

    private void RenderTopStatusNotice()
    {
        if (SyncStatusOverlay is null)
        {
            return;
        }

        var notice = _relayHealthTopNotice ??
                     _presenceHeartbeatTopNotice ??
                     _syncTopNotice ??
                     _relayRecoveryTopNotice;
        if (notice is null)
        {
            SyncStatusOverlay.Visibility = Visibility.Collapsed;
            return;
        }

        SyncOverlayTitleText.Text = notice.Title;
        SyncOverlayDetailText.Text = notice.Detail;
        SyncOverlayRetryButton.Visibility = notice.ShowRetry ? Visibility.Visible : Visibility.Collapsed;
        ApplySyncStatusOverlayTone(notice.Tone);
        SyncStatusOverlay.Visibility = Visibility.Visible;
    }

    private void ShowNetworkSyncIssueDialog(string issue)
    {
        var problem = string.IsNullOrWhiteSpace(issue)
            ? "无法连接到服务器，请检查网络后重试。"
            : issue.Trim();

        NetworkSyncIssueText.Text = problem;
        NetworkSyncIssueOverlay.Visibility = Visibility.Visible;
    }

    private void HideNetworkSyncIssueDialog()
    {
        NetworkSyncIssueOverlay.Visibility = Visibility.Collapsed;
    }

    private static string FormatNetworkSyncIssue(string context, Exception exception)
    {
        return $"{context}:{MapNetworkException(exception)}";
    }

    private async void NetworkSyncIssueRetryButton_Click(object sender, RoutedEventArgs e)
    {
        if (_isNetworkSyncIssueRetrying)
        {
            return;
        }

        _isNetworkSyncIssueRetrying = true;
        NetworkSyncIssueRetryButton.IsEnabled = false;
        HideNetworkSyncIssueDialog();
        try
        {
            await AutoConnectNetworkAsync();
        }
        finally
        {
            _isNetworkSyncIssueRetrying = false;
            NetworkSyncIssueRetryButton.IsEnabled = true;
        }
    }

    private void NetworkSyncIssueExitButton_Click(object sender, RoutedEventArgs e)
    {
        StopNetworkSyncTimers();
        HideNetworkSyncIssueDialog();
        HideSyncStatusOverlay();
        _isClosingAfterOfflineUpload = true;
        Close();
    }

    private async void SyncOverlayRetryButton_Click(object sender, RoutedEventArgs e)
    {
        SyncOverlayRetryButton.IsEnabled = false;
        try
        {
            await AutoConnectNetworkAsync();
        }
        finally
        {
            SyncOverlayRetryButton.IsEnabled = true;
        }
    }
}
