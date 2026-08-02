using StarBridge.Core.Presence;
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

        if (OnboardingState.IsDeferred())
        {
            await InitializeLoginAndNetworkAsync();
            return false;
        }

        _onboardingDialogOpen = true;
        try
        {
            await InitializeLoginAndNetworkAsync();
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

        OnboardingState.ClearDeferred();
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

    private Task InitializeLoginAndNetworkAsync()
    {
        if (IsLoggedIn)
        {
            return AutoConnectNetworkAsync();
        }

        LoginStatusText.Text = _authenticationExpired ? "登录已失效" : "未登录";
        RefreshAccountPanel();
        RefreshHeaderStatusBar();
        return Task.CompletedTask;
    }

    private async Task AutoConnectNetworkAsync()
    {
        if (!IsLoggedIn && string.IsNullOrWhiteSpace(NetworkServerKeyBox.Password))
        {
            LoginStatusText.Text = "未登录";
            RefreshAccountPanel();
            RefreshHeaderStatusBar();
            return;
        }

        var session = _accountSessionCoordinator.Capture();
        if (IsLoggedIn && !await EnsureSyncConsentAsync())
        {
            NetworkAutoSyncCheck.IsChecked = false;
            NetworkStatusText.Text = "已登录 · 游戏状态同步未启用";
            RefreshHeaderStatusBar();
            return;
        }

        ShowSyncStatusOverlay(
            "正在同步服务器数据",
            "正在同步账号、舰队、小队、任务和玩家状态...",
            showRetry: false);
        var slowNotice = BeginSyncStatusSlowNotice();

        var connected = await TestNetworkAsync(silent: true);
        if (!_accountSessionCoordinator.IsCurrent(session))
        {
            HideSyncStatusOverlay();
            return;
        }
        var sharing = GetPresenceSharingDecision();
        var pulledFleets = false;
        var pulledPlayers = false;
        var pushedLocal = false;
        if (connected)
        {
            if (IsLoggedIn && !await ValidateSavedSessionAsync())
            {
                HideSyncStatusOverlay();
                return;
            }

            if (!_accountSessionCoordinator.IsCurrent(session))
            {
                HideSyncStatusOverlay();
                return;
            }

            if (IsLoggedIn && !CanSynchronizeUserData)
            {
                StopNetworkSyncTimers();
                NetworkStatusText.Text = _identityBindingAssessment.State ==
                                         StarBridge.Core.Identity.IdentityVerificationState.Mismatch
                    ? "无法验证身份 · 所有同步已暂停"
                    : "等待绑定游戏身份 · 同步尚未启用";
                HideSyncStatusOverlay();
                ReevaluateIdentityBinding(showPrompt: true);
                RefreshAccountPanel();
                RefreshHeaderStatusBar();
                return;
            }

            pulledFleets = await PullNetworkFleetsAsync(silent: true);
            if (sharing.CanReceiveRealtime)
            {
                pulledPlayers = await PullNetworkSnapshotsAsync(silent: true);
            }

            if (sharing.CanPublishRealtime)
            {
                pushedLocal = await PushLocalSnapshotAsync(silent: true, pushFleetDirectory: false);
            }
        }

        var syncCompleted = pulledFleets || pulledPlayers || pushedLocal ||
                            (connected && !sharing.CanReceiveRealtime);
        if (connected && syncCompleted)
        {
            NetworkAutoSyncCheck.IsChecked = true;
            StartNetworkSyncTimers();
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
            return;
        }

        slowNotice.Cancel();
        slowNotice.Dispose();
        if (ReferenceEquals(_syncStatusOverlayCts, slowNotice))
        {
            _syncStatusOverlayCts = null;
        }

        NetworkStatusText.Text = _accountSessionRequiresFreshSync
            ? "新账号数据尚未完成同步"
            : "启动同步失败，当前显示本地缓存";
        RefreshHeaderStatusBar();
        var issue = _accountSessionRequiresFreshSync
            ? "新账号的数据暂时无法加载。为避免混用旧账号资料，舰队、房间、好友和通讯将保持空白，请稍后重试。"
            : connected
                ? "服务器暂时无法同步，当前会保留本账号的本地舰队资料，请稍后重试。"
                : "当前网络不可用，已保留本账号的本地缓存数据。";
        ShowSyncStatusOverlay(
            "同步失败",
            issue,
            showRetry: true);
        ShowNetworkSyncIssueDialog(issue);
    }

    private async Task<bool> ValidateSavedSessionAsync()
    {
        if (!IsLoggedIn)
        {
            return true;
        }

        var session = _accountSessionCoordinator.Capture();
        try
        {
            var response = await PostNetworkJsonAsync(
                "api/auth/profile",
                new ProfileUpdateRequest(_callsign, _allowEmailNotifications));
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
        dialog.SendVerificationCodeAsync = RequestVerificationCodeAsync;
        dialog.SendPasswordResetCodeAsync = RequestPasswordResetCodeAsync;
        dialog.ResetPasswordAsync = ResetPasswordAsync;
        dialog.AuthenticateAsync = async request =>
        {
            var path = request.IsRegister ? "api/auth/register" : "api/auth/login";
            var actionName = request.IsRegister ? "注册" : "登录";
            var error = await AuthenticateAsync(
                path,
                actionName,
                request.Email,
                request.Password,
                request.Email,
                request.VerificationCode,
                request.Callsign);
            return new LoginWindowAuthResult(error is null, error ?? $"{actionName}成功");
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
        }
        finally
        {
            _isLoginDialogOpen = false;
        }

        UpdateFleetEntryPanels();
        SchedulePendingOverlayAppearanceUnlockNotice();

        if (IsLoggedIn)
        {
            await EnsureSyncConsentAsync();
        }
    }

    private async Task<string> RequestVerificationCodeAsync(string email)
    {
        if (string.IsNullOrWhiteSpace(email))
        {
            return "请输入邮箱地址。";
        }

        try
        {
            var request = new EmailVerificationRequest(email.Trim());
            var response = await _networkClient.PostAsJsonAsync(BuildAuthenticationUri("api/auth/send-code"), request);
            if (!response.IsSuccessStatusCode)
            {
                var error = await ReadResponseErrorAsync(response);
                return FormatActionFailure("发送验证码", MapVerificationError(error));
            }

            return "验证码已发送，10 分钟内有效。";
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

    private async Task<string?> AuthenticateAsync(
        string path,
        string actionName,
        string email,
        string password,
        string? authEmail,
        string? verificationCode,
        string? callsign)
    {
        if (string.IsNullOrWhiteSpace(email) || string.IsNullOrWhiteSpace(password))
        {
            return "请输入登录邮箱和密码。";
        }

        if (path.EndsWith("register", StringComparison.OrdinalIgnoreCase) &&
            (string.IsNullOrWhiteSpace(authEmail) ||
             string.IsNullOrWhiteSpace(verificationCode) ||
             string.IsNullOrWhiteSpace(callsign)))
        {
            return "注册需要登录邮箱、呼号和验证码。";
        }

        try
        {
            var request = new AuthRequest(email.Trim(), password, _localPlayer, authEmail?.Trim(), verificationCode?.Trim(), callsign?.Trim());
            var response = await _networkClient.PostAsJsonAsync(BuildAuthenticationUri(path), request);
            if (!response.IsSuccessStatusCode)
            {
                var serverError = await ReadResponseErrorAsync(response);
                return MapAuthenticationError(response.StatusCode, serverError, path.EndsWith("register", StringComparison.OrdinalIgnoreCase));
            }

            var auth = await response.Content.ReadFromJsonAsync<AuthResponse>();
            if (auth is null || string.IsNullOrWhiteSpace(auth.Token))
            {
                return $"暂时无法完成{actionName}，请稍后重试。";
            }

            if (IsLoggedIn && AccountSessionCoordinator.HasChanged(
                    new AccountSessionIdentity(_accountId, _accountName),
                    new AccountSessionIdentity(auth.AccountId, auth.Email ?? auth.UserName)))
            {
                await PushOfflineSnapshotForAccountSwitchAsync();
            }

            ApplyAuthResponse(auth);
            LoginStatusText.Text = $"{actionName}成功：{_accountName}";
            NetworkStatusText.Text = "已登录并连接服务器";
            SaveCurrentConfig();
            RefreshAccountPanel();
            NetworkAutoSyncCheck.IsChecked = false;
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
            LoginStatusText.Text = $"{actionName}失败：{message}";
            NetworkStatusText.Text = $"{actionName}失败";
            return $"{actionName}失败：{message}";
        }
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

    private static string MapAuthenticationError(HttpStatusCode statusCode, string serverError, bool isRegister)
    {
        var actionName = isRegister ? "注册" : "登录";
        var cleanedServerError = NormalizeServerError(serverError, actionName);
        var normalized = serverError.ToLowerInvariant();
        if (!string.IsNullOrWhiteSpace(cleanedServerError) &&
            ContainsUserFacingError(cleanedServerError))
        {
            return FormatActionFailure(actionName, cleanedServerError);
        }

        if (statusCode == HttpStatusCode.Unauthorized)
        {
            return isRegister
                ? "注册信息未通过验证，请检查验证码后再试。"
                : "邮箱未注册或密码错误。";
        }

        if (statusCode == HttpStatusCode.NotFound)
        {
            return "当前服务器版本缺少登录接口，请联系管理员更新服务器。";
        }

        if (statusCode == HttpStatusCode.Conflict || normalized.Contains("already registered"))
        {
            return "该邮箱已注册，请直接登录。";
        }

        if (normalized.Contains("verification code"))
        {
            return "验证码无效或已过期。";
        }

        if (normalized.Contains("password must"))
        {
            return "密码至少需要 8 个字符。";
        }

        if (normalized.Contains("callsign"))
        {
            return "呼号过长，请缩短后再试。";
        }

        if (normalized.Contains("email") && normalized.Contains("required"))
        {
            return "请输入登录邮箱和密码。";
        }

        return FormatActionFailure(actionName, cleanedServerError);
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
        if (!IsLoggedIn)
        {
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

    private async Task<bool> TestNetworkAsync(bool silent = false)
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
            await PullNetworkFleetsAsync(silent: true);
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
