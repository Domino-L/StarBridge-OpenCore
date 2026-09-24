namespace StarBridge.Desktop;

using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Net.Http;
using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Threading;
using StarBridge.Core.Identity;
using StarBridge.HostRuntime.Auth;

public partial class MainWindow
{
    private string? _boundGameName;
    private DateTimeOffset? _identityBindingConfirmedAt;
    private DateTimeOffset? _identityBindingUpdatedAt;
    private bool _identityBindingSupported;
    private IdentityBindingAssessment _identityBindingAssessment =
        IdentityBindingPolicy.Evaluate(null, null, null);
    private bool _identityBindingRequestInProgress;
    private bool _scmIdentityRefreshInProgress;
    private bool _onboardingDialogOpen;
    private string? _lastScmIdentityDiagnosticState;

    private StartupIdentityGateDecision ResolveStartupIdentityGateDecision() =>
        StartupIdentityGatePolicy.Evaluate(
            IsScmLoggedIn,
            IsScmGameIdentityVerified,
            CurrentScmGameIdentity.Handle,
            _identityBindingSupported,
            _identityBindingAssessment.CanSynchronize,
            _boundGameName,
            _localPlayer);

    private bool CanSynchronizeUserData =>
        IsLoggedIn &&
        !_isAccountTransition &&
        ResolveStartupIdentityGateDecision() == StartupIdentityGateDecision.Allow;

    private bool CanUseIdentitySensitiveNetworkWrites =>
        IsLoggedIn &&
        !_isAccountTransition &&
        (IsScmLoggedIn
            ? CurrentScmIdentityAssessment.CanUseIdentitySensitiveNetworkWrites
            : _identityBindingAssessment.CanUseIdentitySensitiveNetworkWrites);

    private bool IsIdentityBindingVerified =>
        IsLoggedIn &&
        _identityBindingSupported &&
        _identityBindingAssessment.State == IdentityVerificationState.Verified;

    private ScmGameIdentitySnapshot CurrentScmGameIdentity =>
        _scmOAuthSession?.AuthoritativeGameIdentity ??
        new ScmGameIdentitySnapshot(ScmGameIdentityStatus.Unknown, null, null);

    private IdentityBindingAssessment CurrentScmIdentityAssessment =>
        IdentityBindingPolicy.Evaluate(CurrentScmGameIdentity, _localPlayer);

    private bool IsScmGameIdentityVerified =>
        CurrentScmGameIdentity.Status == ScmGameIdentityStatus.Verified;

    private bool IsScmGameIdentityMismatch =>
        CurrentScmIdentityAssessment.State == IdentityVerificationState.Mismatch;

    private void UpdateIdentityBindingFromAuth(AuthResponse auth, bool showPrompt)
    {
        _boundGameName = string.IsNullOrWhiteSpace(auth.GameName) ? null : auth.GameName.Trim();
        _identityBindingConfirmedAt = auth.IdentityBindingConfirmedAt;
        _identityBindingUpdatedAt = auth.IdentityBindingUpdatedAt;
        _identityBindingSupported = auth.IdentityBindingRequired.HasValue;
        ReevaluateIdentityBinding(showPrompt);
    }

    private void ObserveDetectedGameIdentity(string? detectedGameName)
    {
        if (string.IsNullOrWhiteSpace(detectedGameName))
        {
            return;
        }

        _localPlayer = detectedGameName.Trim();
        ReevaluateIdentityBinding(showPrompt: true);
    }

    private void ResetIdentityBindingSession()
    {
        _boundGameName = null;
        _identityBindingConfirmedAt = null;
        _identityBindingUpdatedAt = null;
        _identityBindingSupported = false;
        _identityBindingAssessment = IdentityBindingPolicy.Evaluate(null, null, _localPlayer);
        RefreshIdentityVerificationPresentation();
        if (_guideMode == GuideMode.IdentityBinding)
        {
            if (_initialGuideCompletionSource is { Task.IsCompleted: false })
            {
                ShowJourneyStage(OnboardingJourney.Resume(isLoggedIn: false, savedChapterIndex: 0));
            }
            else
            {
                HideGuidedTour();
            }
        }
    }

    private void ReevaluateIdentityBinding(bool showPrompt)
    {
        var couldSynchronize = CanSynchronizeUserData;
        _identityBindingAssessment = IsLoggedIn && _identityBindingSupported
            ? IdentityBindingPolicy.Evaluate(
                _boundGameName,
                _identityBindingConfirmedAt,
                _localPlayer)
            : IdentityBindingPolicy.Evaluate(null, null, _localPlayer);

        if (!CanSynchronizeUserData)
        {
            StopNetworkDataSyncTimers();
            _profileSyncDebounceTimer.Stop();
            _friendOverlayNotificationTracker.Reset();
            ResetFleetOverlayChatProjection();

            if (_syncPrivacySettings.SyncEnabled)
            {
                StartNetworkSyncTimers();
            }
        }
        else if (!couldSynchronize && _syncPrivacySettings.SyncEnabled)
        {
            StartNetworkSyncTimers();
        }

        RefreshIdentityVerificationPresentation();
        RefreshHeaderStatusBar();

        if (IsLoggedIn &&
            !IsScmLoggedIn &&
            _identityBindingSupported &&
            !CanSynchronizeUserData &&
            IsLoaded &&
            !_isLoginDialogOpen)
        {
            Dispatcher.BeginInvoke(
                DispatcherPriority.Background,
                new Action(ShowMandatoryIdentityBindingGuide));
            return;
        }

        if (CanSynchronizeUserData && _guideMode == GuideMode.IdentityBinding)
        {
            CompleteMandatoryIdentityBindingGuide();
            return;
        }

        _ = showPrompt;
    }

    private void RefreshIdentityVerificationPresentation()
    {
        RecordScmIdentityPolicyState();
        if (IdentityVerificationBanner is null || IdentityVerificationBannerActionButton is null)
        {
            return;
        }

        if (PersonalQuickScanLogButton is not null)
        {
            PersonalQuickScanLogButton.Content = HasConnectedGameLog()
                ? "重新扫描"
                : "扫描日志";
        }

        if (!IsLoggedIn && !IsScmLoggedIn)
        {
            if (HasConnectedGameLog())
            {
                IdentityVerificationBanner.Visibility = Visibility.Collapsed;
                return;
            }

            IdentityVerificationBanner.Visibility = Visibility.Visible;
            var informationBrush = FindBrush("StatusInfoBrush", Brushes.DeepSkyBlue);
            IdentityVerificationBannerTitleText.Text = "连接游戏日志";
            IdentityVerificationBannerDetailText.Text = "登录前也可以先扫描 Game.log，稍后将用它识别并绑定你的游戏 ID";
            IdentityVerificationBannerTitleText.Foreground = informationBrush;
            IdentityVerificationBanner.BorderBrush = informationBrush;
            IdentityVerificationBannerActionButton.Content = "扫描日志";
            IdentityVerificationBannerActionButton.Visibility = Visibility.Visible;
            return;
        }

        if (IsScmLoggedIn)
        {
            IdentityVerificationBanner.Visibility = Visibility.Visible;
            var identityDecision = ResolveStartupIdentityGateDecision();
            var isMismatch = identityDecision == StartupIdentityGateDecision.IdentityMismatch;
            var isVerified = IsScmGameIdentityVerified;
            var identityState = CurrentScmIdentityAssessment.State;
            var statusBrush = isMismatch
                ? FindBrush("StatusDangerBrush", Brushes.IndianRed)
                : isVerified
                    ? FindBrush("StatusSuccessBrush", Brushes.SpringGreen)
                    : FindBrush("StatusWarningBrush", Brushes.Goldenrod);
            IdentityVerificationBannerTitleText.Text = isMismatch
                ? "游戏身份不相同"
                : identityState switch
                {
                    IdentityVerificationState.ReverificationRequired => "SCM 游戏身份需要重新验证",
                    IdentityVerificationState.Revoked => "SCM 游戏身份已撤销",
                    IdentityVerificationState.Unavailable => "暂时无法确认 SCM 游戏身份",
                    _ => isVerified ? "SCM 游戏身份已验证" : "需要验证 SCM 游戏身份"
                };
            IdentityVerificationBannerDetailText.Text = isMismatch
                ? "SCM、兼容账号或 Game.log 中存在不一致的游戏 ID；身份敏感操作已暂停"
                : identityState switch
                {
                    IdentityVerificationState.ReverificationRequired =>
                        "SCM 记录显示原游戏身份已失效；重新验证前身份敏感操作不可用",
                    IdentityVerificationState.Revoked =>
                        "SCM 游戏身份绑定已撤销；重新验证前身份敏感操作不可用",
                    IdentityVerificationState.Unavailable =>
                        "身份服务暂不可用；为保护账号，身份敏感操作暂不可用",
                    _ => isVerified
                        ? "SCM 已确认你的 Star Citizen 游戏账户"
                        : "在应用内获取验证码，写入 RSI 个人资料后完成验证"
                };
            IdentityVerificationBannerTitleText.Foreground = statusBrush;
            IdentityVerificationBanner.BorderBrush = statusBrush;
            IdentityVerificationBannerActionButton.Content = _scmIdentityRefreshInProgress
                ? "刷新中..."
                : isVerified
                    ? "刷新状态"
                    : "立即验证";
            IdentityVerificationBannerActionButton.IsEnabled = !_scmIdentityRefreshInProgress;
            IdentityVerificationBannerActionButton.Visibility = Visibility.Visible;
            if (PersonalHeaderBindingText is not null)
            {
                PersonalHeaderBindingText.Text = isMismatch
                    ? "SCM 游戏身份 · 不一致"
                    : identityState switch
                    {
                        IdentityVerificationState.ReverificationRequired => "SCM 游戏身份 · 需重新验证",
                        IdentityVerificationState.Revoked => "SCM 游戏身份 · 已撤销",
                        IdentityVerificationState.Unavailable => "SCM 游戏身份 · 暂不可用",
                        _ => isVerified
                            ? "SCM 游戏身份 · 已验证"
                            : "SCM 游戏身份 · 待验证"
                    };
                PersonalHeaderBindingText.Foreground = statusBrush;
            }
            return;
        }

        if (!_identityBindingSupported || IsIdentityBindingVerified)
        {
            IdentityVerificationBanner.Visibility = Visibility.Collapsed;
            return;
        }

        IdentityVerificationBanner.Visibility = Visibility.Visible;
        var warningBrush = FindBrush("StatusWarningBrush", Brushes.Goldenrod);
        IdentityVerificationBannerTitleText.Foreground = warningBrush;
        IdentityVerificationBanner.BorderBrush = warningBrush;
        switch (_identityBindingAssessment.State)
        {
            case IdentityVerificationState.BindingRequired:
                IdentityVerificationBannerTitleText.Text = "需要绑定游戏身份";
                IdentityVerificationBannerDetailText.Text =
                    $"同步尚未启用 · Game.log 已识别 {_identityBindingAssessment.DetectedGameName}";
                IdentityVerificationBannerActionButton.Content = "立即绑定";
                IdentityVerificationBannerActionButton.Visibility = Visibility.Visible;
                break;
            case IdentityVerificationState.Mismatch:
                IdentityVerificationBannerTitleText.Text = "无法验证身份";
                IdentityVerificationBannerDetailText.Text =
                    $"所有同步已暂停 · 已绑定 {_identityBindingAssessment.BoundGameName} / 当前 {_identityBindingAssessment.DetectedGameName}";
                IdentityVerificationBannerActionButton.Content = "重新绑定";
                IdentityVerificationBannerActionButton.Visibility = Visibility.Visible;
                break;
            default:
                IdentityVerificationBannerTitleText.Text = "等待游戏身份";
                IdentityVerificationBannerDetailText.Text =
                    "进入游戏后将从 Game.log 识别游戏 ID；完成绑定前不会同步用户数据";
                IdentityVerificationBannerActionButton.Content = "开始绑定";
                IdentityVerificationBannerActionButton.Visibility = Visibility.Visible;
                break;
        }

        if (PersonalHeaderBindingText is not null)
        {
            PersonalHeaderBindingText.Text = GetIdentityBindingSummaryText();
            PersonalHeaderBindingText.Foreground = warningBrush;
        }
    }

    private void RecordScmIdentityPolicyState()
    {
        if (!IsScmLoggedIn)
        {
            _lastScmIdentityDiagnosticState = null;
            return;
        }

        var assessment = CurrentScmIdentityAssessment;
        var sensitiveWritesAllowed = assessment.CanUseIdentitySensitiveNetworkWrites;
        var diagnosticState =
            $"{assessment.AuthoritativeStatus}|{assessment.State}|{sensitiveWritesAllowed}";
        if (string.Equals(
                _lastScmIdentityDiagnosticState,
                diagnosticState,
                StringComparison.Ordinal))
        {
            return;
        }

        _lastScmIdentityDiagnosticState = diagnosticState;
        ScmAuthDiagnostics.Write(
            ScmAuthDiagnostics.NewCorrelationId(),
            "game-identity-policy",
            "evaluated",
            $"authoritativeStatus={assessment.AuthoritativeStatus} " +
            $"localState={assessment.State} " +
            $"sensitiveWritesAllowed={sensitiveWritesAllowed.ToString().ToLowerInvariant()}");
    }

    private string GetIdentityBindingSummaryText()
    {
        if (IsScmLoggedIn)
        {
            var assessment = CurrentScmIdentityAssessment;
            return assessment.State switch
            {
                IdentityVerificationState.Mismatch => "SCM 游戏身份 · 不一致",
                IdentityVerificationState.Verified => "SCM 游戏身份 · 已验证",
                IdentityVerificationState.AwaitingGameIdentity => "SCM 游戏身份 · 等待 Game.log",
                IdentityVerificationState.ReverificationRequired => "SCM 游戏身份 · 需重新验证",
                IdentityVerificationState.Revoked => "SCM 游戏身份 · 已撤销",
                IdentityVerificationState.Unavailable => "SCM 游戏身份 · 暂不可用",
                _ => "SCM 游戏身份 · 待验证"
            };
        }

        if (IsLoggedIn && !_identityBindingSupported)
        {
            return string.IsNullOrWhiteSpace(_localPlayer)
                ? "等待 Game.log 识别身份"
                : $"身份标识：{_localPlayer} · 已缓存";
        }

        return _identityBindingAssessment.State switch
        {
            IdentityVerificationState.Verified => $"身份标识：{_boundGameName} · 已验证",
            IdentityVerificationState.Mismatch => "无法验证身份 · 同步已暂停",
            IdentityVerificationState.BindingRequired => "等待确认绑定 · 同步未启用",
            _ => "等待 Game.log 识别身份"
        };
    }

    private string GetLegacyIdentityLinkSummaryText()
    {
        if (!IsScmLoggedIn)
        {
            return "需要 SCM 登录";
        }

        if (_legacyIdentityLinkProjection is null)
        {
            return _legacyIdentityLinked is null
                ? "正在检查关联状态"
                : "未关联旧 StarBridge 账号";
        }

        if (!string.Equals(_legacyIdentityLinkProjection.Status, "ACTIVE", StringComparison.OrdinalIgnoreCase))
        {
            return $"关联状态：{_legacyIdentityLinkProjection.Status}";
        }

        var accountId = _legacyIdentityLinkProjection.LegacyAccountId.Trim();
        var suffix = accountId.Length <= 8 ? accountId : accountId[^8..];
        return $"已关联旧账号 · ID 尾号 {suffix}";
    }

    private async void IdentityVerificationBannerActionButton_Click(object sender, RoutedEventArgs e)
    {
        if (!IsScmLoggedIn && IsLoggedIn)
        {
            StarBridgeMessageBox.Show(
                this,
                "验证旧 StarBridge 账号前，请先完成 SCM 统一账号授权。没有 SCM 账号可在授权页面完成注册，返回应用后再从个人档案继续。",
                "需要 SCM 授权",
                MessageBoxButton.OK,
                MessageBoxImage.Information);
            await ShowLoginDialogAsync();
            RefreshIdentityVerificationPresentation();
            return;
        }

        if (IsScmLoggedIn)
        {
            if (!_scmOAuthSession!.GameIdentityVerified)
            {
                var verificationWindow = new GameIdentityVerificationWindow(
                    _scmOAuthClient,
                    _scmOAuthSession)
                {
                    Owner = this
                };
                if (verificationWindow.ShowDialog() == true)
                {
                    if (verificationWindow.VerifiedSession is not null)
                    {
                        ApplyScmOAuthSession(verificationWindow.VerifiedSession);
                    }
                    await RefreshScmGameIdentityAsync(silent: false);
                }
                return;
            }

            await RefreshScmGameIdentityAsync(silent: false);
            return;
        }

        if (!IsLoggedIn)
        {
            QuickScanLogAndStart();
            RefreshIdentityVerificationPresentation();
            return;
        }

        await ShowIdentityBindingPromptAsync(force: true);
    }

    private async Task RefreshScmGameIdentityAsync(bool silent)
    {
        if (_scmIdentityRefreshInProgress || _scmOAuthSession is null)
        {
            return;
        }

        _scmIdentityRefreshInProgress = true;
        RefreshIdentityVerificationPresentation();
        try
        {
            var refreshedSession = await _scmOAuthClient.RefreshIdentityAsync(
                _scmOAuthSession,
                CancellationToken.None);
            ApplyScmOAuthSession(refreshedSession);
            await RefreshScmBootstrapAsync(refreshedSession, CancellationToken.None);
            if (refreshedSession.GameIdentityVerified)
            {
                NetworkStatusText.Text = "SCM 游戏身份已验证";
            }
            else if (!silent)
            {
                StarBridgeMessageBox.Show(
                    this,
                    "SCM 尚未返回已验证状态。请重新打开应用内验证窗口，确认已将验证码写入 RSI 个人资料并成功提交。",
                    "尚未完成验证",
                    MessageBoxButton.OK,
                    MessageBoxImage.Information);
            }
        }
        catch (Exception exception)
        {
            if (!silent)
            {
                StarBridgeMessageBox.Show(
                    this,
                    UserFacingError.Describe(exception, "无法刷新 SCM 游戏身份状态，请稍后重试。"),
                    "刷新失败",
                    MessageBoxButton.OK,
                    MessageBoxImage.Warning);
            }
        }
        finally
        {
            _scmIdentityRefreshInProgress = false;
            RefreshIdentityVerificationPresentation();
        }
    }

    private bool HasConnectedGameLog() =>
        !string.IsNullOrWhiteSpace(_logPath) &&
        File.Exists(_logPath) &&
        LogFileSelectionGuard.ValidateGameLogPath(_logPath).IsValid;

    private Task ShowIdentityBindingPromptAsync(bool force)
    {
        _ = force;
        ShowMandatoryIdentityBindingGuide();
        return Task.CompletedTask;
    }

    private void ShowMandatoryIdentityBindingGuide()
    {
        if (!IsLoggedIn || IsScmLoggedIn || !_identityBindingSupported || IsIdentityBindingVerified)
        {
            return;
        }

        _guideMode = GuideMode.IdentityBinding;
        _guideStep = GuideStep.BindIdentity;
        _guidedTourTarget = null;
        GuidedTourOverlay.Visibility = Visibility.Visible;
        GuidedTourInteractionBlocker.Visibility = Visibility.Visible;
        GuidedTourIntroductionScrollViewer.Visibility = Visibility.Collapsed;
        GuidedTourBodyText.Visibility = Visibility.Visible;
        GuidedTourBackButton.Visibility = Visibility.Collapsed;
        GuidedTourEyebrowText.Text = "必需设置 · 只需一次";
        GuidedTourProgressText.Text = "完成后自动启用好友、组织、房间与同步";

        switch (_identityBindingAssessment.State)
        {
            case IdentityVerificationState.BindingRequired:
                GuidedTourTitleText.Text = "确认你的游戏 ID";
                GuidedTourBodyText.Text =
                    $"已从 Game.log 识别到：{_identityBindingAssessment.DetectedGameName}\n\n确认后即可继续使用全部联网功能。";
                GuidedTourPrimaryButton.Content = "确认绑定";
                GuidedTourPrimaryButton.Visibility = Visibility.Visible;
                GuidedTourSecondaryButton.Visibility = Visibility.Collapsed;
                break;
            case IdentityVerificationState.Mismatch:
                GuidedTourTitleText.Text = "游戏 ID 已发生变化";
                GuidedTourBodyText.Text =
                    $"账号原绑定：{_identityBindingAssessment.BoundGameName}\n当前识别：{_identityBindingAssessment.DetectedGameName}\n\n确认重新绑定后即可恢复同步。";
                GuidedTourPrimaryButton.Content = "确认重新绑定";
                GuidedTourPrimaryButton.Visibility = Visibility.Visible;
                GuidedTourSecondaryButton.Visibility = Visibility.Collapsed;
                break;
            default:
                GuidedTourTitleText.Text = "连接 Game.log";
                GuidedTourBodyText.Text = File.Exists(_logPath)
                    ? "Game.log 已连接。请启动并进入一次 Star Citizen；识别到游戏 ID 后，本页会自动进入确认。"
                    : "点击“自动查找”连接 StarCitizen\\LIVE\\Game.log；如果游戏装在特殊目录，可以手动选择。连接后进入一次游戏即可。";
                GuidedTourPrimaryButton.Content = "自动查找";
                GuidedTourPrimaryButton.Visibility = Visibility.Visible;
                GuidedTourSecondaryButton.Content = "手动选择";
                GuidedTourSecondaryButton.Visibility = Visibility.Visible;
                break;
        }

        GuidedTourPrimaryButton.IsEnabled = !_identityBindingRequestInProgress;
        ScheduleGuidedTourLayout();
        GuidedTourPrimaryButton.Focus();
    }

    private async Task ContinueMandatoryIdentityBindingGuideAsync()
    {
        if (_identityBindingRequestInProgress || !IsLoggedIn)
        {
            return;
        }

        var assessment = _identityBindingAssessment;
        if (assessment.State == IdentityVerificationState.AwaitingGameIdentity ||
            string.IsNullOrWhiteSpace(assessment.DetectedGameName))
        {
            QuickScanLogAndStart();
            ShowMandatoryIdentityBindingGuide();
            return;
        }

        await BindDetectedGameIdentityAsync(
            assessment.DetectedGameName,
            assessment.State == IdentityVerificationState.Mismatch);
        if (!IsIdentityBindingVerified)
        {
            ShowMandatoryIdentityBindingGuide();
        }
    }

    private void CompleteMandatoryIdentityBindingGuide()
    {
        GuidedTourInteractionBlocker.Visibility = Visibility.Collapsed;
        if (_initialGuideCompletionSource is { Task.IsCompleted: false })
        {
            if (_onboardingJourneyStage.Chapter == OnboardingJourneyChapter.Login)
            {
                OnboardingState.MarkIntroductionRead();
                OnboardingState.MarkPreparationCompleted();
                OnboardingState.SetFeatureTourStep(0);
                ShowJourneyStage(OnboardingJourney.Next(_onboardingJourneyStage, isLoggedIn: true));
            }
            else
            {
                ShowJourneyStage(_onboardingJourneyStage);
            }

            return;
        }

        HideGuidedTour();
    }

    private void ExitApplicationForUnboundIdentity()
    {
        StopNetworkSyncTimers();
        _profileSyncDebounceTimer.Stop();
        if (Application.Current is App app)
        {
            app.RequestExit();
            return;
        }

        Application.Current?.Shutdown();
    }

    private async Task BindDetectedGameIdentityAsync(string detectedGameName, bool replaceExisting)
    {
        var session = _accountSessionCoordinator.Capture();
        _identityBindingRequestInProgress = true;
        IdentityVerificationBannerActionButton.IsEnabled = false;
        IdentityVerificationBannerActionButton.Content = replaceExisting ? "重新绑定中..." : "绑定中...";
        if (_guideMode == GuideMode.IdentityBinding)
        {
            GuidedTourPrimaryButton.IsEnabled = false;
            GuidedTourPrimaryButton.Content = replaceExisting ? "重新绑定中..." : "绑定中...";
        }
        try
        {
            using var request = new HttpRequestMessage(
                HttpMethod.Put,
                BuildAuthenticationUri("api/auth/identity-binding"))
            {
                Content = JsonContent.Create(new IdentityBindingUpdateRequest(detectedGameName, replaceExisting))
            };
            request.Headers.Authorization = new AuthenticationHeaderValue(
                "Bearer",
                GetRelayAuthorizationToken());
            var relayKey = NetworkServerKeyBox.Password.Trim();
            if (!string.IsNullOrWhiteSpace(relayKey))
            {
                request.Headers.Add("X-StarBridge-Key", relayKey);
            }

            using var response = await _networkClient.SendAsync(request);
            if (!_accountSessionCoordinator.IsCurrent(session))
            {
                return;
            }
            if (HandleAuthorizationFailure(response.StatusCode, "身份绑定", silent: true))
            {
                return;
            }

            if (!response.IsSuccessStatusCode)
            {
                var error = await ReadResponseErrorAsync(response);
                StarBridgeMessageBox.Show(
                    this,
                    string.IsNullOrWhiteSpace(error)
                        ? "身份绑定失败。请检查网络后重试。"
                        : error,
                    "身份绑定失败",
                    MessageBoxButton.OK,
                    MessageBoxImage.Warning);
                NetworkStatusText.Text = "无法验证身份 · 所有同步保持暂停";
                return;
            }

            var auth = await response.Content.ReadFromJsonAsync<AuthResponse>();
            if (auth is null || string.IsNullOrWhiteSpace(auth.Token))
            {
                throw new InvalidOperationException("服务器没有返回有效的身份绑定结果。");
            }

            ApplyAuthResponse(auth, refreshDependentData: false);
            SaveCurrentConfig();
            NetworkStatusText.Text = $"身份已验证：{detectedGameName}";
            RefreshAccountPanel();
            RefreshHeaderStatusBar();
            await AutoConnectNetworkAsync();
        }
        catch (TaskCanceledException)
        {
            StarBridgeMessageBox.Show(
                this,
                "身份绑定请求超时。所有同步仍保持暂停，请稍后重试。",
                "身份绑定超时",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
        }
        catch (Exception ex)
        {
            StarBridgeMessageBox.Show(
                this,
                $"身份绑定失败：{MapNetworkException(ex)}\n\n所有同步仍保持暂停。",
                "身份绑定失败",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
        }
        finally
        {
            _identityBindingRequestInProgress = false;
            IdentityVerificationBannerActionButton.IsEnabled = true;
            RefreshIdentityVerificationPresentation();
            if (IsLoggedIn && _identityBindingSupported && !IsIdentityBindingVerified)
            {
                ShowMandatoryIdentityBindingGuide();
            }
        }
    }
}
