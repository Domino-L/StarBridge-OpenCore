using System.Diagnostics;
using System.Windows;
using StarBridge.Desktop.Controls;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private readonly StartupSyncTimingHistory _startupSyncTimingHistory = new();

    private StartupDataGateAttempt BeginStartupDataGate(AccountSessionLease session)
    {
        _startupDataSyncCts?.Cancel();
        _startupDataSyncCts?.Dispose();
        _startupDataSyncCts = new CancellationTokenSource();

        var attempt = _startupDataGate.Begin(
            session,
            HasUsableStartupCache(),
            ResolveStartupCacheWrittenAtUtc());
        RefreshStartupDataGatePresentation();
        return attempt;
    }

    private StartupDataGateAttempt RestartStartupDataGate(AccountSessionLease session)
    {
        var attempt = _startupDataGate.Begin(
            session,
            HasUsableStartupCache(),
            ResolveStartupCacheWrittenAtUtc());
        RefreshStartupDataGatePresentation();
        return attempt;
    }

    private bool HasUsableStartupCache() =>
        _hasFleet || _fleetDirectoryCache.HasCachedFile;

    private DateTimeOffset? ResolveStartupCacheWrittenAtUtc()
    {
        var directoryWrittenAt = _fleetDirectoryCache.LastLoadedWrittenAtUtc;
        if (_fleetStateCachedAtUtc is null)
        {
            return directoryWrittenAt;
        }

        if (directoryWrittenAt is null)
        {
            return _fleetStateCachedAtUtc;
        }

        return _fleetStateCachedAtUtc > directoryWrittenAt
            ? _fleetStateCachedAtUtc
            : directoryWrittenAt;
    }

    private bool IsStartupAttemptCurrent(StartupDataGateAttempt? attempt)
    {
        // Once D66 owns startup, an unleased pull must not form a second path
        // around it. Ordinary refreshes resume only after the first live
        // synchronization has completed.
        return attempt is null
            ? _startupDataGate.Current.State == StartupDataGateState.Live
            : _startupDataGate.IsCurrent(attempt.Value) &&
              _accountSessionCoordinator.IsCurrent(attempt.Value.AccountSession);
    }

    private bool CompleteStartupDataGate(
        StartupDataGateAttempt attempt,
        StartupSyncOutcome outcome,
        Stopwatch elapsed)
    {
        var applied = _startupDataGate.TryComplete(
            attempt,
            _accountSessionCoordinator.IsCurrent(attempt.AccountSession),
            outcome);
        if (!applied)
        {
            return false;
        }

        if (outcome == StartupSyncOutcome.Succeeded)
        {
            _startupSyncTimingHistory.RecordSuccessful(elapsed.Elapsed);
        }

        RefreshStartupDataGatePresentation();
        return true;
    }

    private void ResetStartupDataGate()
    {
        _startupDataSyncCts?.Cancel();
        _startupDataSyncCts?.Dispose();
        _startupDataSyncCts = null;
        HideSyncStatusOverlay();
        _startupDataGate.Reset();
        RefreshStartupDataGatePresentation();
    }

    private void ConfirmAuthoritativeNoFleetState()
    {
        _fleetStateCachedAtUtc = null;
        var session = _accountSessionCoordinator.Capture();
        var attempt = _startupDataGate.Begin(
            session,
            hasCachedState: false,
            cacheWrittenAtUtc: null);
        _startupDataGate.TryComplete(
            attempt,
            _accountSessionCoordinator.IsCurrent(session),
            StartupSyncOutcome.Succeeded);
        RefreshStartupDataGatePresentation();
    }

    private void RefreshStartupDataGatePresentation()
    {
        if (FindFleetServerDataContent is null ||
            FleetServerDataContent is null ||
            FindFleetStartupBlockingState is null ||
            FleetStartupBlockingState is null ||
            FindFleetStartupOfflineState is null ||
            FleetStartupOfflineState is null ||
            OnlineMembersText is null ||
            PersonalHeaderFleetIdentityCard is null)
        {
            return;
        }

        var snapshot = _startupDataGate.Current;
        var visibility = snapshot.Visibility;
        var showSignedOutShell = snapshot.State == StartupDataGateState.Initial && !IsLoggedIn;
        var serverDataVisibility = visibility.ServerDataVisible || showSignedOutShell
            ? Visibility.Visible
            : Visibility.Collapsed;
        FindFleetServerDataContent.Visibility = serverDataVisibility;
        FleetServerDataContent.Visibility = serverDataVisibility;
        OnlineMembersText.Visibility = visibility.OnlineCountVisible
            ? Visibility.Visible
            : Visibility.Collapsed;
        PersonalHeaderFleetIdentityCard.Visibility =
            snapshot.State == StartupDataGateState.Live || showSignedOutShell
            ? Visibility.Visible
            : Visibility.Collapsed;

        ConfigureBlockingState(FindFleetStartupBlockingState, snapshot.State);
        ConfigureBlockingState(FleetStartupBlockingState, snapshot.State);

        var notice = StartupCacheNotice.Resolve(
            snapshot.CacheWrittenAtUtc,
            DateTimeOffset.UtcNow,
            _language == "zh");
        ConfigureOfflineState(FindFleetStartupOfflineState, notice);
        ConfigureOfflineState(FleetStartupOfflineState, notice);

        var blockingVisibility = visibility.BlockingStateVisible
            ? Visibility.Visible
            : Visibility.Collapsed;
        FindFleetStartupBlockingState.Visibility = blockingVisibility;
        FleetStartupBlockingState.Visibility = blockingVisibility;
        var offlineVisibility = visibility.OfflineCacheNoticeVisible
            ? Visibility.Visible
            : Visibility.Collapsed;
        FindFleetStartupOfflineState.Visibility = offlineVisibility;
        FleetStartupOfflineState.Visibility = offlineVisibility;

        // These secondary surfaces do not carry their own cache warning, so
        // they show fleet-derived data only after a live response. Local
        // settings, identity, avatar, hangar, and layout remain untouched.
        RefreshNavigationActivityBadges();
        RefreshHomeDashboard();
        RefreshPersonalProfileAccessState();
        RefreshBridgeShellForSelectedTab();
    }

    private void ConfigureBlockingState(
        BridgeStatePresenter presenter,
        StartupDataGateState state)
    {
        if (state == StartupDataGateState.IdentityRequired)
        {
            presenter.State = BridgeStateKind.AccessDenied;
            presenter.TitleOverride = _language == "zh"
                ? "等待游戏身份"
                : "Waiting for game identity";
            presenter.DescriptionOverride = _language == "zh"
                ? "进入游戏后将从 Game.log 识别游戏 ID；完成绑定前不会同步用户数据。"
                : "Start the game so Game.log can identify your player. User data sync stays paused until identity binding is complete.";
            presenter.ActionTextOverride = string.Empty;
            return;
        }

        if (state == StartupDataGateState.Error)
        {
            presenter.State = BridgeStateKind.Error;
            presenter.TitleOverride = _language == "zh"
                ? "无法同步服务器数据"
                : "Unable to synchronize server data";
            presenter.DescriptionOverride = _language == "zh"
                ? "当前没有可用缓存。检查网络后重试。"
                : "No usable cache is available. Check the connection and retry.";
            presenter.ActionTextOverride = _language == "zh" ? "重试" : "Retry";
            return;
        }

        presenter.State = BridgeStateKind.Loading;
        presenter.TitleOverride = _language == "zh"
            ? "正在同步服务器数据"
            : "Synchronizing server data";
        presenter.DescriptionOverride = _language == "zh"
            ? "正在确认舰队、权限、任务和成员状态。"
            : "Confirming fleet, permissions, tasks, and member status.";
        presenter.ActionTextOverride = string.Empty;
    }

    private void ConfigureOfflineState(
        BridgeStatePresenter presenter,
        StartupCacheNotice notice)
    {
        presenter.State = BridgeStateKind.OfflineCache;
        presenter.TitleOverride = notice.Title;
        presenter.DescriptionOverride = notice.Description;
        presenter.ActionTextOverride = _language == "zh" ? "重试" : "Retry";
    }

    private async void StartupDataRetry_Click(object sender, RoutedEventArgs e)
    {
        if (!IsLoggedIn)
        {
            return;
        }

        await AutoConnectNetworkAsync();
    }
}
