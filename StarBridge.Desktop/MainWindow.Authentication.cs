using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Auth;
using System.Diagnostics;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.Http.Json;
using System.Windows;
using System.Windows.Controls;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private readonly TestBuildNoticeStore _testBuildNoticeStore = new();

    private async Task RunStartupAndGameplayConsentFlowAsync()
    {
        if (!ShowTestBuildNoticeIfNeeded())
        {
            return;
        }

        var onboardingCompleted = await RunStartupFlowAsync();
        if (!onboardingCompleted || Dispatcher.HasShutdownStarted)
        {
            return;
        }

        BindGameplayStatisticsOwner();
        ShowGameplayDataConsentIfNeeded();
        ShowLocationDataContributionConsentIfNeeded();
    }

    private bool ShowTestBuildNoticeIfNeeded()
    {
        if (_testBuildNoticeStore.IsAcknowledged())
        {
            return true;
        }

        var accepted = StarBridgeMessageBox.ShowAction(
            this,
            "当前版本仍处于测试阶段。请只从星海舰桥官网或官方 GitHub Release 下载，并在安装前核对 Windows 数字签名和官方公布的 SHA-256。如果安装程序显示“未知发布者”、签名无效或文件哈希不一致，请不要继续安装。\n\n" +
            "功能、界面、本地设置和联网服务可能继续调整，也可能因游戏、日志、网络、Windows、驱动或安全软件变化而出现中断、延迟、误判或无法使用。\n\n" +
            "星海舰桥是玩家独立开发的非官方社区工具，未获得 Cloud Imperium Games 或 Roberts Space Industries 针对本应用的书面许可、合规认证或特别豁免。只读 Game.log、使用独立 Windows 浮层且不注入游戏，是当前实现方式，不代表官方认可，也不能完全排除反作弊误报或账号相关风险。\n\n" +
            "应用提供的舰船、地点、在线状态和事件信息仅供协作参考。请自行判断是否安装和使用，并遵守当时有效的游戏及平台规则；若官方要求与本应用发生冲突，请停止使用受影响功能。\n\n" +
            "当前测试版不会随包提供来源与再分发授权尚未完成核实的第三方图片，相关位置可能显示占位图。只有完成权利核验并通过发布审计的媒体，才会进入后续正式载荷。\n\n" +
            "在适用法律允许的最大范围内，作者、维护者和贡献者不对因安装、使用或无法使用本应用而产生的账号措施、游戏内损失、数据损失、软件冲突、协作失误或间接损失承担责任。本声明不排除适用法律不能排除的责任。\n\n" +
            "继续使用前，请阅读随应用提供的《完整客户端许可条款》。完整条款与上述说明可随时在“帮助与反馈 → 说明与声明”中查看。如果你不接受这些事项，请关闭应用。",
            $"星海舰桥 {GetAppUpdateVersion()} 测试版",
            "我已阅读并理解，继续",
            "退出应用",
            MessageBoxImage.Information);

        if (!accepted)
        {
            System.Windows.Application.Current.Shutdown();
            return false;
        }

        if (!_testBuildNoticeStore.TryAcknowledge(out var acknowledgementError))
        {
            StarBridgeMessageBox.Show(
                this,
                $"无法保存本次许可确认记录。为避免下次启动重复询问，请检查应用配置目录是否可写。\n\n{acknowledgementError}",
                "确认记录未保存",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
        }

        return true;
    }

    private async Task<bool> RunStartupFlowAsync()
    {
        var completionStatus = OnboardingState.GetCompletionStatus();
        var onboardingCompleted = completionStatus == OnboardingCompletionStatus.Current;
        if (onboardingCompleted)
        {
            await InitializeLoginAndNetworkAsync();
            return true;
        }

        await InitializeLoginAndNetworkAsync();
        if (!IsLoggedIn)
        {
            return false;
        }

        _onboardingDialogOpen = true;
        try
        {
            onboardingCompleted = await StartInitialGuidedTourAsync();
            return onboardingCompleted;
        }
        finally
        {
            _onboardingDialogOpen = false;
            if (onboardingCompleted && !Dispatcher.HasShutdownStarted && IsLoaded)
            {
                ReevaluateIdentityBinding(showPrompt: true);
            }
        }
    }

    private async Task HandleOnboardingActionAsync(OnboardingNextAction action)
    {
        switch (action)
        {
            case OnboardingNextAction.Login:
                await ShowLoginDialogAsync();
                if (IsLoggedIn)
                {
                    await AutoConnectNetworkAsync();
                }
                break;
            case OnboardingNextAction.OpenIdentitySettings:
                OpenPersonalIdentitySettings_Click(this, new RoutedEventArgs());
                break;
            case OnboardingNextAction.SelectLog:
                SelectLog_Click(this, new RoutedEventArgs());
                if (IsLoggedIn)
                {
                    await AutoConnectNetworkAsync();
                }
                break;
            case OnboardingNextAction.QuickScanLog:
                QuickScanLogAndStart();
                if (IsLoggedIn)
                {
                    await AutoConnectNetworkAsync();
                }
                break;
            case OnboardingNextAction.BindIdentity:
                if (!IsLoggedIn)
                {
                    await ShowLoginDialogAsync();
                }

                if (!IsLoggedIn)
                {
                    ExitApplicationForUnboundIdentity();
                    break;
                }

                if (string.IsNullOrWhiteSpace(_logPath) || !File.Exists(_logPath))
                {
                    SelectLog_Click(this, new RoutedEventArgs());
                }

                if (string.IsNullOrWhiteSpace(_localPlayer))
                {
                    StarBridgeMessageBox.Show(
                        this,
                        "尚未从 Game.log 识别到游戏 ID。请确认日志路径正确，并启动一次 Star Citizen；识别成功后会继续要求绑定。",
                        "等待识别游戏身份",
                        MessageBoxButton.OK,
                        MessageBoxImage.Information);
                    break;
                }

                await AutoConnectNetworkAsync();
                if (!_identityBindingSupported)
                {
                    StarBridgeMessageBox.Show(
                        this,
                        "暂时无法连接身份验证服务。请检查网络后重试；完成绑定前不会启用多人同步。",
                        "无法开始身份绑定",
                        MessageBoxButton.OK,
                        MessageBoxImage.Warning);
                    break;
                }

                if (!IsIdentityBindingVerified)
                {
                    await ShowIdentityBindingPromptAsync(force: true);
                }
                break;
            case OnboardingNextAction.FindFleet:
                if (!TryLeaveOverlayEditorTab())
                {
                    break;
                }

                MainTabs.SelectedItem = FindFleetTab;
                SetActiveNav(FindFleetNavButton);
                if (IsLoggedIn)
                {
                    await AutoConnectNetworkAsync();
                    await PullNetworkFleetsAsync(silent: true);
                }
                break;
            case OnboardingNextAction.MyFleet:
                NavigateToMyFleet();
                if (IsLoggedIn)
                {
                    await AutoConnectNetworkAsync();
                }
                break;
            case OnboardingNextAction.CreateFleet:
                if (!IsLoggedIn)
                {
                    await ShowLoginDialogAsync();
                }

                if (IsLoggedIn)
                {
                    await AutoConnectNetworkAsync();
                    FleetCreateButton_Click(this, new RoutedEventArgs());
                }
                break;
            case OnboardingNextAction.MySquad:
                if (TryLeaveOverlayEditorTab())
                {
                    var previousTab = MainTabs.SelectedItem;
                    MainTabs.SelectedItem = MySquadTab;
                    SetActiveNav(MySquadNavButton);
                    QueueMainPageReveal(previousTab);
                }
                if (IsLoggedIn)
                {
                    await AutoConnectNetworkAsync();
                }
                break;
            case OnboardingNextAction.Overlay:
                MainTabs.SelectedItem = OverlayEditTab;
                SetActiveNav(OverlayNavButton);
                RenderOverlayEditor();
                OnboardingState.MarkHintCompleted(OverlayInitialTourVisitedHintId);
                if (IsLoggedIn)
                {
                    await AutoConnectNetworkAsync();
                }
                break;
            case OnboardingNextAction.Profile:
                PersonalNav_Click(PersonalNavButton, new RoutedEventArgs());
                break;
            default:
                if (IsLoggedIn)
                {
                    await AutoConnectNetworkAsync();
                }
                break;
        }

        RefreshOnboardingSupportPanel();
    }

    private static bool IsFeatureTourAction(OnboardingNextAction action) =>
        action is OnboardingNextAction.FindFleet or
            OnboardingNextAction.MyFleet or
            OnboardingNextAction.MySquad or
            OnboardingNextAction.Overlay or
            OnboardingNextAction.Profile;

    private void ShowOneTimeGuideHint(string hintId, string title, string message)
    {
        if (_guideMode != GuideMode.None)
        {
            OnboardingState.MarkHintCompleted(hintId);
            return;
        }

        if (OnboardingState.IsHintCompleted(hintId))
        {
            return;
        }

        var dialog = new GuideHintWindow(title, message)
        {
            Owner = this
        };
        dialog.ShowDialog();
        OnboardingState.MarkHintCompleted(hintId);
        RefreshOnboardingSupportPanel();
    }

    private void GuideCompleteButton_Click(object sender, RoutedEventArgs e)
    {
        OnboardingState.MarkCompleted();
        RefreshOnboardingSupportPanel();
    }

    private async void GuideLoginButton_Click(object sender, RoutedEventArgs e)
    {
        await HandleOnboardingActionAsync(OnboardingNextAction.Login);
    }

    private async void HelpGuideOnboardingButton_Click(object sender, RoutedEventArgs e)
    {
        if (_guideMode != GuideMode.None)
        {
            return;
        }

        if (!IsLoggedIn)
        {
            await ShowLoginDialogAsync();
            return;
        }

        OnboardingState.ClearDeferred();
        OnboardingState.SetFeatureTourStep(0);
        _onboardingDialogOpen = true;
        var completed = false;
        try
        {
            completed = await StartInitialGuidedTourAsync();
        }
        finally
        {
            _onboardingDialogOpen = false;
        }

        if (!completed || Dispatcher.HasShutdownStarted || !IsLoaded)
        {
            return;
        }

        ReevaluateIdentityBinding(showPrompt: true);
        BindGameplayStatisticsOwner();
        ShowGameplayDataConsentIfNeeded();
        ShowLocationDataContributionConsentIfNeeded();
    }

    private async void GuideSelectLogButton_Click(object sender, RoutedEventArgs e)
    {
        await HandleOnboardingActionAsync(OnboardingNextAction.SelectLog);
    }

    private async void GuideQuickScanLogButton_Click(object sender, RoutedEventArgs e)
    {
        QuickScanLogAndStart();
        if (IsLoggedIn)
        {
            await AutoConnectNetworkAsync();
        }
    }

    private async void GuideFindFleetButton_Click(object sender, RoutedEventArgs e)
    {
        await HandleOnboardingActionAsync(OnboardingNextAction.FindFleet);
    }

    private async void GuideCreateFleetButton_Click(object sender, RoutedEventArgs e)
    {
        await HandleOnboardingActionAsync(OnboardingNextAction.CreateFleet);
    }

    private async void GuideSquadButton_Click(object sender, RoutedEventArgs e)
    {
        await HandleOnboardingActionAsync(OnboardingNextAction.MySquad);
    }

    private async void GuideOverlayButton_Click(object sender, RoutedEventArgs e)
    {
        await HandleOnboardingActionAsync(OnboardingNextAction.Overlay);
    }

    private async Task InitializeLoginAndNetworkAsync()
    {
        if (!IsScmLoggedIn)
        {
            _scmSessionRestoreOutcome = ScmSessionRestoreOutcome.NotAttempted;
            _scmSessionRestoreInProgress = true;
            LoginStatusText.Text = "正在恢复 SCM 登录状态...";
            RefreshAccountPanel();
            RefreshAuthenticationRequiredViews();
            RefreshHeaderStatusBar();
            try
            {
                await EnsureScmRegionResolvedAsync(CancellationToken.None);
                var scmSession = await _scmOAuthClient.TryRestoreSessionAsync(CancellationToken.None);
                if (scmSession is not null)
                {
                    ApplyScmOAuthSession(scmSession);
                    if (!await RefreshScmBootstrapAsync(scmSession, CancellationToken.None))
                    {
                        await RefreshLegacyIdentityLinkStateAsync(scmSession);
                    }
                }
            }
            catch (HttpRequestException)
            {
                LoginStatusText.Text = "SCM 暂时不可用，登录凭据已保留";
                NetworkStatusText.Text = "SCM 离线 · 可稍后重试";
            }
            catch (Exception) when (
                _scmOAuthClient.LastSessionRestoreOutcome == ScmSessionRestoreOutcome.ReauthorizationRequired)
            {
                LoginStatusText.Text = "SCM 登录已失效，请重新授权";
                NetworkStatusText.Text = "SCM 会话需要重新登录";
            }
            finally
            {
                _scmSessionRestoreOutcome = _scmOAuthClient.LastSessionRestoreOutcome;
                _scmSessionRestoreInProgress = false;
                RefreshAuthenticationRequiredViews();
            }

            if (_scmOAuthSession is { } restoredSession)
            {
                ScheduleScmRuntimeRecovery(restoredSession, "session-restore");
            }
        }

        if (IsLoggedIn)
        {
            await AutoConnectNetworkAsync();
            return;
        }

        if (IsScmLoggedIn)
        {
            RefreshAccountPanel();
            RefreshHeaderStatusBar();
            return;
        }

        _authenticationExpired =
            _scmSessionRestoreOutcome == ScmSessionRestoreOutcome.ReauthorizationRequired;
        RefreshAccountPanel();
        NetworkStatusText.Text = _scmSessionRestoreOutcome switch
        {
            ScmSessionRestoreOutcome.ReauthorizationRequired =>
                "SCM 登录已失效 · 未自动切换旧账号",
            ScmSessionRestoreOutcome.CredentialTemporarilyUnavailable =>
                "SCM 暂时不可用 · 登录凭据已保留",
            _ => "等待 SCM 登录"
        };
        RefreshHeaderStatusBar();
    }

    private string GetSignedOutScmLoginStatusText()
    {
        if (_scmSessionRestoreInProgress)
        {
            return "正在恢复 SCM 登录状态...";
        }

        return _scmSessionRestoreOutcome switch
        {
            ScmSessionRestoreOutcome.ReauthorizationRequired => "SCM 登录已失效，请重新授权",
            ScmSessionRestoreOutcome.CredentialTemporarilyUnavailable =>
                "SCM 暂时不可用，登录凭据已保留",
            _ => "未登录 SCM"
        };
    }

    private string GetSignedOutScmStatusText() => _scmSessionRestoreInProgress
        ? "正在安全恢复 SCM 登录状态..."
        : _scmSessionRestoreOutcome switch
        {
            ScmSessionRestoreOutcome.ReauthorizationRequired => "SCM 登录已失效 · 请重新授权",
            ScmSessionRestoreOutcome.CredentialTemporarilyUnavailable =>
                "SCM 暂时不可用 · 凭据已保留",
            _ => "浏览模式 · 可登录 SCM 或配置 Game.log"
        };

    private string GetSignedOutScmAccountModeText() => _scmSessionRestoreOutcome switch
    {
        ScmSessionRestoreOutcome.ReauthorizationRequired =>
            "SCM 登录已失效；旧账号不会被自动启用，重新授权后恢复同步",
        ScmSessionRestoreOutcome.CredentialTemporarilyUnavailable =>
            "SCM 暂时不可用；登录凭据已保留，旧账号不会被自动启用",
        _ => "登录 SCM 后可同步或管理舰队；Game.log 可在登录前配置"
    };

    private async Task AutoConnectNetworkAsync()
    {
        Task operation;
        lock (_startupDataSyncLock)
        {
            if (_startupDataSyncTask is { IsCompleted: false } active &&
                _startupDataSyncCts?.IsCancellationRequested != true)
            {
                operation = active;
            }
            else
            {
                operation = AutoConnectNetworkCoreAsync();
                _startupDataSyncTask = operation;
            }
        }

        try
        {
            await operation;
        }
        finally
        {
            lock (_startupDataSyncLock)
            {
                if (ReferenceEquals(_startupDataSyncTask, operation) && operation.IsCompleted)
                {
                    _startupDataSyncTask = null;
                }
            }
        }
    }

    private async Task AutoConnectNetworkCoreAsync()
    {
        if (!IsLoggedIn && string.IsNullOrWhiteSpace(NetworkServerKeyBox.Password))
        {
            ResetStartupDataGate();
            LoginStatusText.Text = "未登录";
            RefreshAccountPanel();
            RefreshHeaderStatusBar();
            return;
        }

        var attempt = BeginStartupDataGate(_accountSessionCoordinator.Capture());
        if (IsLoggedIn && !await EnsureSyncConsentAsync())
        {
            CompleteStartupDataGate(
                attempt,
                StartupSyncOutcome.Failed,
                Stopwatch.StartNew());
            NetworkStatusText.Text = "已登录 · 游戏状态同步未启用";
            RefreshHeaderStatusBar();
            return;
        }

        var startupIdentityDecision = ResolveStartupIdentityGateDecision();
        if (IsLoggedIn && startupIdentityDecision != StartupIdentityGateDecision.Allow)
        {
            // Either the legacy binding or the authoritative SCM game identity
            // is still unavailable (or SCM conflicts with Game.log). This is
            // an intentional privacy gate, not a relay failure.
            ReevaluateIdentityBinding(showPrompt: true);
            CompleteStartupDataGate(
                attempt,
                startupIdentityDecision == StartupIdentityGateDecision.IdentityMismatch
                    ? StartupSyncOutcome.IdentityMismatch
                    : StartupSyncOutcome.IdentityRequired,
                Stopwatch.StartNew());
            NetworkStatusText.Text = startupIdentityDecision == StartupIdentityGateDecision.IdentityMismatch
                ? "游戏身份不相同 · 用户数据同步已暂停"
                : "等待游戏身份 · 多人同步未启动";
            RefreshHeaderStatusBar();
            HideSyncStatusOverlay();
            return;
        }

        ShowSyncStatusOverlay(
            "正在同步服务器数据",
            "正在同步账号、组织、任务和玩家状态...",
            showRetry: false);
        var slowNotice = BeginSyncStatusSlowNotice();
        var elapsed = Stopwatch.StartNew();
        var completionAttempt = attempt;
        StartupSyncOutcome outcome;
        try
        {
            var cancellationToken = _startupDataSyncCts?.Token ?? CancellationToken.None;
            outcome = await StartupSyncTimeoutPolicy.WaitAsync(
                async timeoutToken =>
                {
                    var connected = await TestNetworkAsync(
                        silent: true,
                        pullFleetDirectory: false);
                    timeoutToken.ThrowIfCancellationRequested();
                    if (!connected || !IsStartupAttemptCurrent(completionAttempt))
                    {
                        return false;
                    }

                    if (IsLoggedIn && !await ValidateSavedSessionAsync())
                    {
                        return false;
                    }

                    timeoutToken.ThrowIfCancellationRequested();
                    var validatedSession = _accountSessionCoordinator.Capture();
                    if (!_accountSessionCoordinator.IsCurrent(completionAttempt.AccountSession))
                    {
                        // A legacy saved session can be upgraded from a name
                        // identity to a stable account id during validation.
                        // Start the data mutation lease from the validated
                        // identity instead of treating that legitimate upgrade
                        // as a stale response.
                        completionAttempt = RestartStartupDataGate(validatedSession);
                    }

                    if (!IsStartupAttemptCurrent(completionAttempt))
                    {
                        return false;
                    }

                    if (IsLoggedIn && !CanSynchronizeUserData)
                    {
                        StopNetworkDataSyncTimers();
                        ReevaluateIdentityBinding(showPrompt: true);
                        return false;
                    }

                    var sharing = GetPresenceSharingDecision();
                    var pulledFleets = await PullNetworkFleetsAsync(
                        silent: true,
                        startupAttempt: completionAttempt);
                    timeoutToken.ThrowIfCancellationRequested();
                    var pulledPlayers = !sharing.CanReceiveRealtime ||
                                        await PullNetworkSnapshotsAsync(
                                            silent: true,
                                            startupAttempt: completionAttempt);
                    timeoutToken.ThrowIfCancellationRequested();

                    if (sharing.CanPublishRealtime && IsStartupAttemptCurrent(completionAttempt))
                    {
                        _ = await PushLocalSnapshotAsync(
                            silent: true,
                            pushFleetDirectory: false);
                    }

                    return pulledFleets && pulledPlayers &&
                           IsStartupAttemptCurrent(completionAttempt);
                },
                _startupSyncTimingHistory.ResolveTimeout(_networkClient.Timeout),
                cancellationToken);
        }
        catch (OperationCanceledException)
        {
            CompleteSyncStatusSlowNotice(slowNotice);
            return;
        }

        if (outcome != StartupSyncOutcome.Succeeded)
        {
            // The directory cache is verified lazily only after the live pull
            // fails. Complete the gate from what was actually recovered, not
            // merely from the fact that a cache file existed at startup.
            completionAttempt = completionAttempt with
            {
                HasCachedState = _hasFleet || _allNetworkFleets.Count > 0,
                CacheWrittenAtUtc = ResolveStartupCacheWrittenAtUtc()
            };
        }

        CompleteSyncStatusSlowNotice(slowNotice);

        if (!CompleteStartupDataGate(completionAttempt, outcome, elapsed))
        {
            HideSyncStatusOverlay();
            return;
        }

        if (StartupRetryPolicy.ShouldArmPeriodicSynchronization(outcome))
        {
            ArmNetworkAutoSyncRecovery();
            LoginStatusText.Text = string.IsNullOrWhiteSpace(_accountName)
                ? "已连接服务器"
                : $"已登录：{_accountName}";
            NetworkStatusText.Text = _syncPrivacySettings.PresenceVisibilityMode switch
            {
                PlayerPresenceVisibilityMode.Invisible => "隐身模式：已连接，不上传即时状态",
                PlayerPresenceVisibilityMode.Offline => "离线模式：账号已验证，即时同步未启动",
                _ => "已完成启动同步"
            };
            RefreshAccountPanel();
            RefreshHeaderStatusBar();
            HideSyncStatusOverlay();
            HideNetworkSyncIssueDialog();
            AppendOutput($"STARTUP SYNC | {_startupSyncTimingHistory.Describe()}");
            return;
        }

        StopNetworkDataSyncTimers();
        var terminalState = _startupDataGate.Current.State;
        NetworkStatusText.Text = terminalState == StartupDataGateState.OfflineCache
            ? "启动同步未完成 · 当前显示本地缓存"
            : "启动同步未完成 · 当前没有可用缓存";
        RefreshHeaderStatusBar();
        var issue = outcome == StartupSyncOutcome.TimedOut
            ? terminalState == StartupDataGateState.OfflineCache
                ? "同步等待已超时，当前显示本地缓存。请在网络稳定后手动重试。"
                : "同步等待已超时，且没有可用缓存。请检查网络后重试。"
            : terminalState == StartupDataGateState.OfflineCache
                ? "服务器数据同步失败，当前显示本地缓存。请在网络恢复后手动重试。"
                : "服务器数据同步失败，且没有可用缓存。请检查网络后重试。";
        ShowSyncStatusOverlay(
            "同步暂未完成",
            issue,
            showRetry: true);
        HideNetworkSyncIssueDialog();
    }

    private void ArmNetworkAutoSyncRecovery()
    {
        ApplyNetworkSyncMasterState();
    }

    private async Task<bool> ValidateSavedSessionAsync()
    {
        if (!IsLoggedIn)
        {
            return true;
        }

        if (IsScmLoggedIn && _scmOAuthSession is { } scmSession)
        {
            // SCM owns the authenticated account/profile facts. Validate the
            // compatibility projection with the read-only session endpoint;
            // never turn startup validation into a legacy profile write.
            return await RefreshScmLegacyRelaySessionAsync(scmSession, CancellationToken.None);
        }

        var session = _accountSessionCoordinator.Capture();
        try
        {
            using var response = await _relayClient.GetAsync("api/auth/session");
            if (!_accountSessionCoordinator.IsCurrent(session))
            {
                return false;
            }
            if (HandleAuthorizationFailure(response.StatusCode, "登录校验", silent: true))
            {
                return false;
            }

            if (!response.IsSuccessStatusCode)
            {
                return true;
            }

            var auth = await response.Content.ReadFromJsonAsync<AuthResponse>();
            if (auth is not null && !string.IsNullOrWhiteSpace(auth.Token))
            {
                ApplyAuthResponse(auth);
                SaveCurrentConfig();
            }

            return true;
        }
        catch (Exception ex) when (HandleAuthorizationFailure(ex, "登录校验", silent: true))
        {
            return false;
        }
        catch
        {
            return true;
        }
    }

    private async Task ShowLoginDialogAsync()
    {
        if (_isLoginDialogOpen)
        {
            return;
        }

        _isLoginDialogOpen = true;
        var dialog = new LoginWindow(_accountName) { Owner = this };
        dialog.SendPasswordResetCodeAsync = RequestPasswordResetCodeAsync;
        dialog.ResetPasswordAsync = ResetPasswordAsync;
        dialog.AuthenticateWithScmAsync = async cancellationToken =>
        {
            try
            {
                var session = await _scmOAuthClient.SignInAsync(
                    cancellationToken,
                    dialog.ReportScmLoginProgress);
                return new LoginWindowScmAuthResult(true, "SCM 授权成功。", session);
            }
            catch (OperationCanceledException)
            {
                throw;
            }
            catch (Exception exception)
            {
                return new LoginWindowScmAuthResult(
                    false,
                    UserFacingError.Describe(exception, "SCM 登录未完成，请稍后重试。"));
            }
        };
        dialog.AuthenticateAsync = async request =>
        {
            var error = await AuthenticateAsync(
                request.Email,
                request.Password);
            return new LoginWindowAuthResult(error is null, error ?? "登录成功");
        };
        try
        {
            var result = dialog.ShowDialog();
            if (result != true)
            {
                RefreshAccountPanel();
                return;
            }

            if (dialog.IsSkipped)
            {
                LoginStatusText.Text = "已进入浏览模式";
                RefreshAccountPanel();
                return;
            }

            if (dialog.ScmSession is not null)
            {
                ApplyScmOAuthSession(dialog.ScmSession);
                if (!await RefreshScmBootstrapAsync(dialog.ScmSession, CancellationToken.None))
                {
                    await RefreshLegacyIdentityLinkStateAsync(dialog.ScmSession);
                }

                ScheduleScmRuntimeRecovery(dialog.ScmSession, "interactive-login");
            }
        }
        finally
        {
            _isLoginDialogOpen = false;
        }

        if (IsLoggedIn)
        {
            await EnsureSyncConsentAsync();
            if (_scmOAuthSession is not null)
            {
                if (_legacyIdentityLinked is null)
                {
                    await RefreshLegacyIdentityLinkStateAsync(_scmOAuthSession);
                }

                if (_legacyIdentityLinked == false)
                {
                    await ChooseLegacyIdentityPathAsync();
                }
            }
        }

        if (IsLoggedIn &&
            _guideMode == GuideMode.None &&
            OnboardingState.GetCompletionStatus() != OnboardingCompletionStatus.Current)
        {
            _onboardingDialogOpen = true;
            try
            {
                _ = await StartInitialGuidedTourAsync();
            }
            finally
            {
                _onboardingDialogOpen = false;
            }

            if (!IsScmLoggedIn && !IsIdentityBindingVerified)
            {
                ReevaluateIdentityBinding(showPrompt: true);
            }
        }

        UpdateFleetEntryPanels();
        SchedulePendingOverlayAppearanceUnlockNotice();
    }

    private async Task<string> RequestPasswordResetCodeAsync(string email)
    {
        if (string.IsNullOrWhiteSpace(email))
        {
            return "请输入邮箱地址。";
        }

        try
        {
            var request = new EmailVerificationRequest(email.Trim());
            var response = await _networkClient.PostAsJsonAsync(
                BuildAuthenticationUri("api/auth/password-reset/send-code"),
                request);
            if (!response.IsSuccessStatusCode)
            {
                var error = await ReadResponseErrorAsync(response);
                return FormatActionFailure("发送验证码", MapVerificationError(error));
            }

            return "如果该邮箱已注册，验证码将在几分钟内发送，10 分钟内有效。";
        }
        catch (TaskCanceledException)
        {
            return "发送失败：连接服务器超时，请稍后再试。";
        }
        catch (Exception ex)
        {
            return $"发送失败：{MapNetworkException(ex)}";
        }
    }

    private async Task<LoginWindowAuthResult> ResetPasswordAsync(LoginWindowPasswordResetRequest request)
    {
        try
        {
            var payload = new PasswordResetRequest(
                request.Email.Trim(),
                request.VerificationCode.Trim(),
                request.NewPassword);
            var response = await _networkClient.PostAsJsonAsync(
                BuildAuthenticationUri("api/auth/password-reset/confirm"),
                payload);
            if (!response.IsSuccessStatusCode)
            {
                var error = await ReadResponseErrorAsync(response);
                return new LoginWindowAuthResult(false, MapPasswordResetError(error));
            }

            return new LoginWindowAuthResult(true, "密码已重置。");
        }
        catch (TaskCanceledException)
        {
            return new LoginWindowAuthResult(false, "连接服务器超时，请稍后再试。");
        }
        catch (Exception ex)
        {
            return new LoginWindowAuthResult(false, $"重置失败：{MapNetworkException(ex)}");
        }
    }

    private async Task<string?> AuthenticateAsync(string email, string password)
    {
        if (string.IsNullOrWhiteSpace(email) || string.IsNullOrWhiteSpace(password))
        {
            return "请输入登录邮箱和密码。";
        }

        try
        {
            var request = new AuthRequest(email.Trim(), password, _localPlayer);
            var response = await _networkClient.PostAsJsonAsync(BuildAuthenticationUri("api/auth/login"), request);
            if (!response.IsSuccessStatusCode)
            {
                var serverError = await ReadResponseErrorAsync(response);
                return MapAuthenticationError(response.StatusCode, serverError);
            }

            var auth = await response.Content.ReadFromJsonAsync<AuthResponse>();
            if (auth is null || string.IsNullOrWhiteSpace(auth.Token))
            {
                return "暂时无法完成登录，请稍后重试。";
            }

            if (IsLoggedIn && AccountSessionCoordinator.HasChanged(
                    new AccountSessionIdentity(_accountId, _accountName),
                    new AccountSessionIdentity(auth.AccountId, auth.Email ?? auth.UserName)))
            {
                await PushOfflineSnapshotForAccountSwitchAsync();
            }

            ApplyAuthResponse(auth);
            CaptureLegacyMigrationCredential(auth.AccountId, auth.Email ?? auth.UserName, auth.Token);
            LoginStatusText.Text = $"登录成功：{_accountName}";
            NetworkStatusText.Text = "已登录并连接服务器";
            SaveCurrentConfig();
            RefreshAccountPanel();
            NetworkStatusText.Text = "已登录 · 等待同步设置";
            RefreshHeaderStatusBar();
            return null;
        }
        catch (TaskCanceledException)
        {
            return "连接服务器超时，请检查网络或稍后再试。";
        }
        catch (Exception ex)
        {
            var message = MapNetworkException(ex);
            LoginStatusText.Text = $"登录失败：{message}";
            NetworkStatusText.Text = "登录失败";
            return $"登录失败：{message}";
        }
    }

    private void CaptureLegacyMigrationCredential(string? accountId, string? accountName, string? authToken)
    {
        if (string.IsNullOrWhiteSpace(accountId) || string.IsNullOrWhiteSpace(authToken))
        {
            return;
        }

        _legacyMigrationCredentialStore.Save(new LegacyMigrationCredential(
            accountId.Trim(),
            string.IsNullOrWhiteSpace(accountName) ? null : accountName.Trim(),
            authToken,
            DateTimeOffset.UtcNow));
        _hasLegacyMigrationCredential = true;
    }

    private async void HeaderLegacyIdentityLinkMenuItem_Click(object sender, RoutedEventArgs e)
    {
        if (_identityLinkInProgress)
        {
            _accountOperationStatusText = "正在取消兼容身份设置";
            _identityLinkCancellation?.Cancel();
            RefreshAccountPanel();
            return;
        }

        await ChooseLegacyIdentityPathAsync();
    }

    private async Task ChooseLegacyIdentityPathAsync()
    {
        if (_identityLinkInProgress || _scmOAuthSession is null || _legacyIdentityLinked == true)
        {
            return;
        }

        var choice = IdentityLinkChoiceDialog.Show(this);
        if (choice == IdentityLinkChoice.LinkExisting)
        {
            await LinkLegacyIdentityAsync();
            return;
        }

        if (choice != IdentityLinkChoice.CreateCompatibilityAccount)
        {
            LoginStatusText.Text = "已暂缓设置 StarBridge 兼容身份";
            return;
        }

        var confirmed = StarBridgeMessageBox.ShowAction(
            this,
            "仅当你从未使用过旧版 StarBridge、没有旧舰队、好友、聊天、房间或历史数据时创建兼容档案。创建后当前 SCM 账号将绑定一个新的内部 AccountId，不能再自行关联其他旧账号。",
            "确认创建兼容档案",
            "确认没有旧账号，创建",
            "返回",
            MessageBoxImage.Warning);
        if (confirmed)
        {
            await ProvisionCompatibilityAccountAsync();
        }
    }

    private async Task LinkLegacyIdentityAsync()
    {
        if (_identityLinkInProgress || _scmOAuthSession is null)
        {
            return;
        }

        var operationCancellation = new CancellationTokenSource();
        using var operationTimeout = CancellationTokenSource.CreateLinkedTokenSource(
            operationCancellation.Token);
        operationTimeout.CancelAfter(TimeSpan.FromMinutes(3));
        _identityLinkCancellation = operationCancellation;
        _identityLinkInProgress = true;
        _accountOperationStatusText = "正在检查 SCM 账号关联状态";
        var resumeRuntimeSynchronization = false;
        string? finalStatus = null;
        var finalStatusImage = MessageBoxImage.Information;
        ScmOAuthSession? activeSession = null;
        RefreshAccountPanel();
        try
        {
            LoginStatusText.Text = "正在请求 SCM 旧账号关联授权...";
            activeSession = await _scmOAuthClient.RefreshIdentityAsync(
                _scmOAuthSession,
                operationTimeout.Token);
            ApplyScmOAuthSession(activeSession);
            var result = await _identityLinkCoordinator.EnsureLinkedAsync(
                activeSession,
                operationTimeout.Token,
                message => Dispatcher.Invoke(() => ReportAccountOperationProgress(message)),
                _ => Task.FromResult(LegacyIdentityLinkCredentialDialog.Show(
                    this,
                    _legacyMigrationCredentialStore.Load()?.AccountName)));
            switch (result.Outcome)
            {
                case IdentityLinkOutcome.Linked:
                case IdentityLinkOutcome.AlreadyLinked:
                    _hasLegacyMigrationCredential = false;
                    _legacyIdentityLinkProjection = string.IsNullOrWhiteSpace(result.LegacyAccountId)
                        ? null
                        : new ScmIdentityLinkProjection("ACTIVE", result.LegacyAccountId);
                    _legacyIdentityLinked = _legacyIdentityLinkProjection is not null;
                    AdvanceAccountRouteIdentity();
                    resumeRuntimeSynchronization = true;
                    await RefreshScmLegacyRelaySessionAsync(activeSession, operationTimeout.Token);
                    finalStatus = "旧 StarBridge 账号已关联到当前 SCM 账号";
                    break;
                case IdentityLinkOutcome.Conflict:
                    finalStatus = "旧账号关联存在冲突，已保留迁移凭据，请稍后重试或联系支持";
                    finalStatusImage = MessageBoxImage.Warning;
                    break;
                case IdentityLinkOutcome.ExistingLinkMismatch:
                    _legacyIdentityLinkProjection = string.IsNullOrWhiteSpace(result.LegacyAccountId)
                        ? null
                        : new ScmIdentityLinkProjection("ACTIVE", result.LegacyAccountId);
                    _legacyIdentityLinked = _legacyIdentityLinkProjection is not null;
                    AdvanceAccountRouteIdentity();
                    resumeRuntimeSynchronization = true;
                    await RefreshScmLegacyRelaySessionAsync(activeSession, operationTimeout.Token);
                    finalStatus = "当前 SCM 账号已关联其他旧账号，未修改现有关系";
                    finalStatusImage = MessageBoxImage.Warning;
                    break;
                default:
                    _hasLegacyMigrationCredential = false;
                    finalStatus = "未找到可迁移的旧账号凭据";
                    break;
            }
        }
        catch (OperationCanceledException) when (operationCancellation.IsCancellationRequested)
        {
            finalStatus = "已取消旧账号关联";
        }
        catch (OperationCanceledException)
        {
            if (activeSession is not null && await TryReconcileLegacyIdentityLinkAsync(activeSession))
            {
                resumeRuntimeSynchronization = true;
                finalStatus = "请求虽已超时，但已从 SCM 确认旧账号关联成功";
            }
            else
            {
                finalStatus = "旧账号关联等待超时，入口已解锁，请重试";
                finalStatusImage = MessageBoxImage.Warning;
            }
        }
        catch (LegacyIdentityLinkRateLimitException exception)
        {
            var retryAfterSeconds = Math.Max(1, (int)Math.Ceiling(exception.RetryAfter?.TotalSeconds ?? 30));
            finalStatus = $"旧账号验证尝试过于频繁，请在 {retryAfterSeconds} 秒后重试";
            finalStatusImage = MessageBoxImage.Warning;
        }
        catch (LegacyIdentityLinkAuthenticationException)
        {
            finalStatus = "旧账号名、邮箱或密码错误，请重新检查";
            finalStatusImage = MessageBoxImage.Warning;
        }
        catch (HttpRequestException exception)
        {
            if (activeSession is not null && await TryReconcileLegacyIdentityLinkAsync(activeSession))
            {
                resumeRuntimeSynchronization = true;
                finalStatus = "网络响应中断，但已从 SCM 确认旧账号关联成功";
            }
            else
            {
                finalStatus = UserFacingError.Describe(
                    exception,
                    "旧账号关联暂未完成，入口已解锁，请重试。");
                finalStatusImage = MessageBoxImage.Warning;
            }
        }
        catch (Exception exception)
        {
            finalStatus = UserFacingError.Describe(
                exception,
                "旧账号关联暂未完成，请稍后重试。");
            finalStatusImage = MessageBoxImage.Warning;
        }
        finally
        {
            var resumeSynchronization = resumeRuntimeSynchronization &&
                ReferenceEquals(_identityLinkCancellation, operationCancellation) &&
                !operationCancellation.IsCancellationRequested;
            if (ReferenceEquals(_identityLinkCancellation, operationCancellation))
            {
                _identityLinkCancellation = null;
            }
            operationCancellation.Dispose();
            _identityLinkInProgress = false;
            _accountOperationStatusText = null;
            RefreshAccountPanel();
            if (resumeSynchronization && activeSession is not null)
            {
                // Applying a Link changes the account namespace and resets the
                // startup gate. Relay authentication alone does not reload it.
                // Release the busy gate first, then use the existing leased,
                // retrying recovery lane (including consent and identity gates).
                ScheduleScmRuntimeRecovery(
                    activeSession,
                    "identity-link-completed",
                    forceDependencyReplay: true);
            }
            if (!string.IsNullOrWhiteSpace(finalStatus))
            {
                LoginStatusText.Text = finalStatus;
                StarBridgeMessageBox.Show(
                    this,
                    finalStatus,
                    "旧账号关联",
                    MessageBoxButton.OK,
                    finalStatusImage);
            }
        }
    }

    private async Task ProvisionCompatibilityAccountAsync()
    {
        if (_identityLinkInProgress || _scmOAuthSession is null)
        {
            return;
        }

        var operationCancellation = new CancellationTokenSource();
        using var operationTimeout = CancellationTokenSource.CreateLinkedTokenSource(
            operationCancellation.Token);
        operationTimeout.CancelAfter(TimeSpan.FromMinutes(3));
        _identityLinkCancellation = operationCancellation;
        _identityLinkInProgress = true;
        _accountOperationStatusText = "正在创建 StarBridge 兼容档案";
        var resumeRuntimeSynchronization = false;
        string? finalStatus = null;
        var finalStatusImage = MessageBoxImage.Information;
        ScmOAuthSession? activeSession = null;
        RefreshAccountPanel();
        try
        {
            activeSession = await _scmOAuthClient.RefreshIdentityAsync(
                _scmOAuthSession,
                operationTimeout.Token);
            ApplyScmOAuthSession(activeSession);
            var result = await _identityLinkCoordinator.ProvisionCompatibilityAccountAsync(
                activeSession,
                operationTimeout.Token,
                message => Dispatcher.Invoke(() => ReportAccountOperationProgress(message)));
            switch (result.Outcome)
            {
                case IdentityLinkOutcome.Linked:
                case IdentityLinkOutcome.AlreadyLinked:
                    _legacyIdentityLinkProjection = string.IsNullOrWhiteSpace(result.LegacyAccountId)
                        ? null
                        : new ScmIdentityLinkProjection("ACTIVE", result.LegacyAccountId);
                    _legacyIdentityLinked = _legacyIdentityLinkProjection is not null;
                    AdvanceAccountRouteIdentity();
                    resumeRuntimeSynchronization = true;
                    await RefreshScmLegacyRelaySessionAsync(activeSession, operationTimeout.Token);
                    finalStatus = "StarBridge 兼容档案已创建并绑定到当前 SCM 账号";
                    break;
                case IdentityLinkOutcome.Conflict:
                    finalStatus = "兼容档案创建存在身份冲突，未修改当前账号关系";
                    finalStatusImage = MessageBoxImage.Warning;
                    break;
                default:
                    finalStatus = "兼容档案创建未完成，请稍后重试";
                    finalStatusImage = MessageBoxImage.Warning;
                    break;
            }
        }
        catch (OperationCanceledException) when (operationCancellation.IsCancellationRequested)
        {
            finalStatus = "已取消创建兼容档案";
        }
        catch (OperationCanceledException)
        {
            if (activeSession is not null && await TryReconcileLegacyIdentityLinkAsync(activeSession))
            {
                resumeRuntimeSynchronization = true;
                finalStatus = "请求虽已超时，但已从 SCM 确认兼容档案创建成功";
            }
            else
            {
                finalStatus = "兼容档案创建等待超时，入口已解锁，请重试";
                finalStatusImage = MessageBoxImage.Warning;
            }
        }
        catch (HttpRequestException exception)
        {
            if (activeSession is not null && await TryReconcileLegacyIdentityLinkAsync(activeSession))
            {
                resumeRuntimeSynchronization = true;
                finalStatus = "网络响应中断，但已从 SCM 确认兼容档案创建成功";
            }
            else
            {
                finalStatus = UserFacingError.Describe(
                    exception,
                    "兼容档案创建暂未完成，入口已解锁，请重试。");
                finalStatusImage = MessageBoxImage.Warning;
            }
        }
        catch (Exception exception)
        {
            finalStatus = UserFacingError.Describe(
                exception,
                "兼容档案创建暂未完成，请稍后重试。");
            finalStatusImage = MessageBoxImage.Warning;
        }
        finally
        {
            var resumeSynchronization = resumeRuntimeSynchronization &&
                ReferenceEquals(_identityLinkCancellation, operationCancellation) &&
                !operationCancellation.IsCancellationRequested;
            if (ReferenceEquals(_identityLinkCancellation, operationCancellation))
            {
                _identityLinkCancellation = null;
            }
            operationCancellation.Dispose();
            _identityLinkInProgress = false;
            _accountOperationStatusText = null;
            RefreshAccountPanel();
            if (resumeSynchronization && activeSession is not null)
            {
                // Applying a Link changes the account namespace and resets the
                // startup gate. Relay authentication alone does not reload it.
                // Release the busy gate first, then use the existing leased,
                // retrying recovery lane (including consent and identity gates).
                ScheduleScmRuntimeRecovery(
                    activeSession,
                    "identity-link-completed",
                    forceDependencyReplay: true);
            }
            if (!string.IsNullOrWhiteSpace(finalStatus))
            {
                LoginStatusText.Text = finalStatus;
                StarBridgeMessageBox.Show(
                    this,
                    finalStatus,
                    "StarBridge 兼容身份",
                    MessageBoxButton.OK,
                    finalStatusImage);
            }
        }
    }

    private async Task RefreshLegacyIdentityLinkStateAsync(ScmOAuthSession session)
    {
        try
        {
            var projection = await _identityLinkCoordinator.ResolveAsync(session, CancellationToken.None);
            if (_scmOAuthSession is not null &&
                string.Equals(_scmOAuthSession.Subject, session.Subject, StringComparison.Ordinal) &&
                string.Equals(_scmOAuthSession.AuthorityId, session.AuthorityId, StringComparison.Ordinal))
            {
                _legacyIdentityLinkProjection = projection;
                _legacyIdentityLinked = projection is not null &&
                                        string.Equals(projection.Status, "ACTIVE", StringComparison.OrdinalIgnoreCase) &&
                                        !string.IsNullOrWhiteSpace(projection.LegacyAccountId);
                AdvanceAccountRouteIdentity();
                if (_legacyIdentityLinked == true)
                {
                    await RefreshScmLegacyRelaySessionAsync(session, CancellationToken.None);
                }
                else
                {
                    _scmLegacyRelayAuthenticated = false;
                }
            }
        }
        catch (HttpRequestException)
        {
            _legacyIdentityLinked = null;
            _legacyIdentityLinkProjection = null;
            _scmLegacyRelayAuthenticated = false;
            AdvanceAccountRouteIdentity();
        }
        finally
        {
            RefreshAccountPanel();
        }
    }

    private async Task<bool> TryReconcileLegacyIdentityLinkAsync(ScmOAuthSession session)
    {
        try
        {
            using var reconciliationTimeout = new CancellationTokenSource(TimeSpan.FromSeconds(10));
            var projection = await _identityLinkCoordinator.ResolveAsync(
                session,
                reconciliationTimeout.Token);
            if (projection is null ||
                !string.Equals(projection.Status, "ACTIVE", StringComparison.OrdinalIgnoreCase) ||
                string.IsNullOrWhiteSpace(projection.LegacyAccountId))
            {
                return false;
            }

            _legacyIdentityLinkProjection = projection;
            _legacyIdentityLinked = true;
            _hasLegacyMigrationCredential = false;
            AdvanceAccountRouteIdentity();
            try
            {
                await RefreshScmLegacyRelaySessionAsync(session, reconciliationTimeout.Token);
            }
            catch (Exception exception) when (exception is HttpRequestException or OperationCanceledException)
            {
                _scmLegacyRelayAuthenticated = false;
                UpdateAccountRuntimeState();
            }

            return true;
        }
        catch (Exception exception) when (exception is HttpRequestException or OperationCanceledException)
        {
            return false;
        }
    }

    private async Task<bool> RefreshScmLegacyRelaySessionAsync(
        ScmOAuthSession session,
        CancellationToken cancellationToken,
        ScmRuntimeRecoveryLease? recoveryLease = null)
    {
        if (!CanPublishScmRuntimeRecovery(session, recoveryLease))
        {
            return false;
        }

        var projection = _legacyIdentityLinkProjection;
        if (projection is null ||
            !string.Equals(projection.Status, "ACTIVE", StringComparison.OrdinalIgnoreCase) ||
            string.IsNullOrWhiteSpace(projection.LegacyAccountId))
        {
            ScmAuthDiagnostics.Write(
                session.CorrelationId ?? "relay-session",
                "legacy-relay-session",
                "skipped",
                "activeLinkProjection=false");
            _scmLegacyRelayAuthenticated = false;
            UpdateAccountRuntimeState();
            return false;
        }

        try
        {
            ScmAuthDiagnostics.Write(
                session.CorrelationId ?? "relay-session",
                "legacy-relay-session",
                "started",
                "activeLinkProjection=true");
            using var request = new HttpRequestMessage(
                HttpMethod.Get,
                BuildAuthenticationUri("api/auth/session"));
            request.Headers.Authorization = new System.Net.Http.Headers.AuthenticationHeaderValue(
                "Bearer",
                session.AccessToken);
            var relayKey = NetworkServerKeyBox.Password.Trim();
            if (!string.IsNullOrWhiteSpace(relayKey))
            {
                request.Headers.Add("X-StarBridge-Key", relayKey);
            }

            using var response = await _networkClient.SendAsync(request, cancellationToken);
            if (!CanPublishScmRuntimeRecovery(session, recoveryLease))
            {
                return false;
            }

            if (!response.IsSuccessStatusCode)
            {
                ScmAuthDiagnostics.Write(
                    session.CorrelationId ?? "relay-session",
                    "legacy-relay-session",
                    "rejected",
                    $"status={(int)response.StatusCode}");
                _scmLegacyRelayAuthenticated = false;
                UpdateAccountRuntimeState();
                return false;
            }

            var auth = await response.Content.ReadFromJsonAsync<AuthResponse>(cancellationToken);
            if (!CanPublishScmRuntimeRecovery(session, recoveryLease))
            {
                return false;
            }

            if (auth is null ||
                !string.Equals(auth.AccountId, projection.LegacyAccountId, StringComparison.OrdinalIgnoreCase))
            {
                ScmAuthDiagnostics.Write(
                    session.CorrelationId ?? "relay-session",
                    "legacy-relay-session",
                    "rejected",
                    "accountMatch=false");
                _scmLegacyRelayAuthenticated = false;
                UpdateAccountRuntimeState();
                return false;
            }

            _scmLegacyRelayAuthenticated = true;
            ApplyAuthResponse(auth with { Token = "" });
            SaveCurrentConfig();
            ScmAuthDiagnostics.Write(
                session.CorrelationId ?? "relay-session",
                "legacy-relay-session",
                "completed",
                "accountMatch=true");
            return true;
        }
        catch (Exception exception) when (
            exception is HttpRequestException or TaskCanceledException or System.Text.Json.JsonException or NotSupportedException)
        {
            if (!CanPublishScmRuntimeRecovery(session, recoveryLease))
            {
                return false;
            }

            ScmAuthDiagnostics.Write(
                session.CorrelationId ?? "relay-session",
                "legacy-relay-session",
                "degraded",
                $"exceptionType={exception.GetType().Name}");
            _scmLegacyRelayAuthenticated = false;
            UpdateAccountRuntimeState();
            return false;
        }
    }

    private ScmRuntimeRecoveryIdentity CreateScmRuntimeRecoveryIdentity(ScmOAuthSession session) => new(
        _scmOAuthOptions.ResourceServerBaseUri.AbsoluteUri,
        session.AuthorityId,
        session.Subject);

    private bool IsCurrentScmSessionIdentity(ScmOAuthSession session) =>
        _scmOAuthSession is { } current &&
        string.Equals(current.Subject, session.Subject, StringComparison.Ordinal) &&
        string.Equals(current.AuthorityId, session.AuthorityId, StringComparison.Ordinal);

    private bool CanPublishScmRuntimeRecovery(
        ScmOAuthSession session,
        ScmRuntimeRecoveryLease? recoveryLease) =>
        IsCurrentScmSessionIdentity(session) &&
        (recoveryLease is null || _scmRuntimeRecoveryCoordinator.IsCurrent(recoveryLease.Value));

    private bool NeedsScmRuntimeRecovery =>
        _scmBootstrapSnapshot is null ||
        _legacyIdentityLinked is null ||
        (_legacyIdentityLinked == true && !_scmLegacyRelayAuthenticated) ||
        (_scmLegacyRelayAuthenticated &&
         _startupDataGate.Current.State == StartupDataGateState.Initial &&
         _syncPrivacySettings.SyncConsentCompleted &&
         _syncPrivacySettings.SyncConsentVersion >= CurrentSyncConsentVersion);

    private void ScheduleScmRuntimeRecovery(
        ScmOAuthSession session,
        string trigger,
        bool forceDependencyReplay = false)
    {
        if (_scmSessionRestoreInProgress ||
            _identityLinkInProgress ||
            !IsCurrentScmSessionIdentity(session) ||
            (!forceDependencyReplay && !NeedsScmRuntimeRecovery))
        {
            return;
        }

        var identity = CreateScmRuntimeRecoveryIdentity(session);
        var recovery = _scmRuntimeRecoveryCoordinator.RequestAsync(
            identity,
            (lease, cancellationToken) => RecoverScmRuntimeStateAsync(
                session,
                lease,
                trigger,
                cancellationToken));
        _ = ObserveScmRuntimeRecoveryAsync(recovery, session, trigger);
    }

    private async Task<bool> RecoverScmRuntimeStateAsync(
        ScmOAuthSession session,
        ScmRuntimeRecoveryLease lease,
        string trigger,
        CancellationToken cancellationToken)
    {
        if (!CanPublishScmRuntimeRecovery(session, lease))
        {
            return true;
        }

        ScmAuthDiagnostics.Write(
            session.CorrelationId ?? "runtime-recovery",
            "runtime-recovery",
            "started",
            $"trigger={trigger} generation={lease.Generation}");

        var bootstrapRecovered = await RefreshScmBootstrapAsync(
            session,
            cancellationToken,
            lease);
        if (!CanPublishScmRuntimeRecovery(session, lease))
        {
            return true;
        }

        if (!bootstrapRecovered ||
            _legacyIdentityLinked is null ||
            (_legacyIdentityLinked == true && !_scmLegacyRelayAuthenticated))
        {
            ScmAuthDiagnostics.Write(
                session.CorrelationId ?? "runtime-recovery",
                "runtime-recovery",
                "retrying",
                $"trigger={trigger} generation={lease.Generation}");
            return false;
        }

        RefreshAccountPanel();
        RefreshAuthenticationRequiredViews();
        RefreshHeaderStatusBar();

        if (_scmLegacyRelayAuthenticated &&
            _syncPrivacySettings.SyncConsentCompleted &&
            _syncPrivacySettings.SyncConsentVersion >= CurrentSyncConsentVersion)
        {
            await AutoConnectNetworkAsync();
        }

        ScmAuthDiagnostics.Write(
            session.CorrelationId ?? "runtime-recovery",
            "runtime-recovery",
            "completed",
            $"trigger={trigger} generation={lease.Generation} relayAuthenticated={_scmLegacyRelayAuthenticated}");
        return true;
    }

    private static async Task ObserveScmRuntimeRecoveryAsync(
        Task recovery,
        ScmOAuthSession session,
        string trigger)
    {
        try
        {
            await recovery;
        }
        catch (Exception exception)
        {
            ScmAuthDiagnostics.Write(
                session.CorrelationId ?? "runtime-recovery",
                "runtime-recovery",
                "failed",
                $"trigger={trigger} exceptionType={exception.GetType().Name}");
        }
    }

    private void RestoreAndActivateMainWindow()
    {
        if (WindowState == WindowState.Minimized)
        {
            WindowState = WindowState.Normal;
        }
        Show();
        Activate();
        Topmost = true;
        Topmost = false;
        Focus();
    }

    private void ReportAccountOperationProgress(string message)
    {
        RestoreAndActivateMainWindow();
        _accountOperationStatusText = message.TrimEnd('.', '。');
        LoginStatusText.Text = message;
        RefreshAccountPanel();
    }

    private static string MapVerificationError(string serverError)
    {
        var normalized = serverError.ToLowerInvariant();
        if (normalized.Contains("rate") || normalized.Contains("60") || normalized.Contains("频繁"))
        {
            return "验证码发送过于频繁，请稍后再试。";
        }

        if (normalized.Contains("email service") || normalized.Contains("smtp") || normalized.Contains("not configured"))
        {
            return "服务器邮件服务未配置或暂时不可用。";
        }

        if (normalized.Contains("email is required"))
        {
            return "请输入邮箱地址。";
        }

        return NormalizeServerError(serverError, "发送验证码");
    }

    private static string MapPasswordResetError(string serverError)
    {
        var normalized = serverError.ToLowerInvariant();
        if (normalized.Contains("验证码") || normalized.Contains("verification"))
        {
            return "验证码无效或已过期，请重新获取。";
        }

        if (normalized.Contains("8") || normalized.Contains("128") || normalized.Contains("密码"))
        {
            return NormalizeServerError(serverError, "重置密码");
        }

        return NormalizeServerError(serverError, "重置密码");
    }

    private static string MapAuthenticationError(HttpStatusCode statusCode, string serverError)
    {
        var cleanedServerError = NormalizeServerError(serverError, "登录");
        if (!string.IsNullOrWhiteSpace(cleanedServerError) &&
            ContainsUserFacingError(cleanedServerError))
        {
            return FormatActionFailure("登录", cleanedServerError);
        }

        if (statusCode == HttpStatusCode.Unauthorized)
        {
            return "旧账号邮箱不存在或密码错误。";
        }

        if (statusCode == HttpStatusCode.NotFound)
        {
            return "当前服务器版本缺少登录接口，请联系管理员更新服务器。";
        }

        return FormatActionFailure("登录", cleanedServerError);
    }

    private static string FormatActionFailure(string actionName, string? reason)
    {
        var cleaned = NormalizeServerError(reason, actionName);
        if (string.IsNullOrWhiteSpace(cleaned))
        {
            cleaned = "服务器没有返回详细原因。";
        }

        return $"{actionName}失败：{cleaned}";
    }

    private static string NormalizeServerError(string? serverError, string actionName)
    {
        var cleaned = (serverError ?? "").Trim();
        if (string.IsNullOrWhiteSpace(cleaned))
        {
            return "";
        }

        var prefixes = new[]
        {
            $"{actionName}失败:",
            $"{actionName}失败:",
            "发送失败:",
            "发送失败:"
        };

        foreach (var prefix in prefixes)
        {
            if (cleaned.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
            {
                return cleaned[prefix.Length..].Trim();
            }
        }

        return cleaned;
    }

    private static bool ContainsUserFacingError(string message)
    {
        return message.Contains(':') ||
               message.Contains("验证码", StringComparison.OrdinalIgnoreCase) ||
               message.Contains("邮箱", StringComparison.OrdinalIgnoreCase) ||
               message.Contains("邮件", StringComparison.OrdinalIgnoreCase) ||
               message.Contains("密码", StringComparison.OrdinalIgnoreCase) ||
               message.Contains("呼号", StringComparison.OrdinalIgnoreCase) ||
               message.Contains("SMTP", StringComparison.OrdinalIgnoreCase) ||
               message.Contains("未配置", StringComparison.OrdinalIgnoreCase) ||
               message.Contains("过期", StringComparison.OrdinalIgnoreCase);
    }

    private static string MapNetworkException(Exception exception)
    {
        return exception switch
        {
            TaskCanceledException => "连接服务器超时，请检查网络或稍后再试。",
            HttpRequestException => "无法连接星海舰桥服务，请检查网络后重试。",
            _ => UserFacingError.Describe(exception, "暂时无法完成账号操作，请稍后重试。")
        };
    }

    private async Task UpdateProfileAsync(bool includeAvatarImage = false)
    {
        if (!IsLoggedIn ||
            IsScmLoggedIn ||
            string.IsNullOrWhiteSpace(_authToken))
        {
            // The legacy profile endpoint is not an SCM profile authority.
            // SCM-owned profile editing is introduced by the S2 migration.
            return;
        }

        try
        {
            var response = await PostNetworkJsonAsync(
                "api/auth/profile",
                new ProfileUpdateRequest(
                    _callsign,
                    _allowEmailNotifications,
                    includeAvatarImage ? BuildAvatarImageData() : null));
            if (HandleAuthorizationFailure(response.StatusCode, "个人资料同步", silent: true))
            {
                return;
            }

            response.EnsureSuccessStatusCode();
        }
        catch (Exception ex) when (HandleAuthorizationFailure(ex, "个人资料同步", silent: true))
        {
            // The handler clears stale authenticated state.
        }
        catch
        {
            // Ignore transient relay errors and keep local profile changes.
        }
    }

    private async Task<bool> TestNetworkAsync(
        bool silent = false,
        bool pullFleetDirectory = true)
    {
        try
        {
            var health = await ProbeRelayHealthAsync();
            ApplyRelayHealthProbeResult(health);
            if (!health.IsConnected)
            {
                throw health.Error ?? new HttpRequestException("服务器健康检查未通过。");
            }

            NetworkStatusText.Text = "连接成功";
            RefreshHeaderStatusBar();
            HideNetworkSyncIssueDialog();
            if (!silent)
            {
                AppendOutput($"NETWORK | connected={NetworkServerUrlBox.Text.Trim()}");
            }
            if (pullFleetDirectory)
            {
                await PullNetworkFleetsAsync(silent: true);
            }
            return true;
        }
        catch (TaskCanceledException)
        {
            _lastRelayLatencyMs = -1;
            var issue = "连接失败:服务器响应超时，请稍后重试。";
            NetworkStatusText.Text = issue;
            RefreshHeaderStatusBar();
            if (!silent)
            {
                AppendOutput("NETWORK | connect failed=timeout");
                ShowNetworkSyncIssueDialog(issue);
            }

            return false;
        }
        catch (Exception ex)
        {
            _lastRelayLatencyMs = -1;
            var issue = FormatNetworkSyncIssue("连接失败", ex);
            NetworkStatusText.Text = issue;
            RefreshHeaderStatusBar();
            if (!silent)
            {
                AppendOutput($"NETWORK | connect failed={ex.Message}");
                ShowNetworkSyncIssueDialog(issue);
            }

            return false;
        }
    }
}
