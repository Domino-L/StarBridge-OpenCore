namespace StarBridge.Desktop;

using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Net.Http;
using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Threading;
using StarBridge.Core.Identity;

public partial class MainWindow
{
    private string? _boundGameName;
    private DateTimeOffset? _identityBindingConfirmedAt;
    private DateTimeOffset? _identityBindingUpdatedAt;
    private bool _identityBindingSupported;
    private IdentityBindingAssessment _identityBindingAssessment =
        IdentityBindingPolicy.Evaluate(null, null, null);
    private bool _identityBindingRequestInProgress;
    private bool _onboardingDialogOpen;

    private bool CanSynchronizeUserData =>
        IsLoggedIn &&
        !_isAccountTransition &&
        (!_identityBindingSupported ||
         _identityBindingAssessment.CanSynchronize);

    private bool IsIdentityBindingVerified =>
        IsLoggedIn &&
        _identityBindingSupported &&
        _identityBindingAssessment.State == IdentityVerificationState.Verified;

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

            if (_syncPrivacySettings.SyncEnabled && !_presenceHeartbeatTimer.IsEnabled)
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
            _identityBindingSupported &&
            !IsIdentityBindingVerified &&
            IsLoaded &&
            !_isLoginDialogOpen)
        {
            Dispatcher.BeginInvoke(
                DispatcherPriority.Background,
                new Action(ShowMandatoryIdentityBindingGuide));
            return;
        }

        if (IsIdentityBindingVerified && _guideMode == GuideMode.IdentityBinding)
        {
            CompleteMandatoryIdentityBindingGuide();
            return;
        }

        _ = showPrompt;
    }

    private void RefreshIdentityVerificationPresentation()
    {
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

        if (!IsLoggedIn)
        {
            if (HasConnectedGameLog())
            {
                IdentityVerificationBanner.Visibility = Visibility.Collapsed;
                if (TopBannerReserveRow is not null)
                {
                    TopBannerReserveRow.Height = new GridLength(0);
                }

                return;
            }

            IdentityVerificationBanner.Visibility = Visibility.Visible;
            if (TopBannerReserveRow is not null)
            {
                TopBannerReserveRow.Height = new GridLength(38);
            }

            var informationBrush = FindBrush("StatusInfoBrush", Brushes.DeepSkyBlue);
            IdentityVerificationBannerTitleText.Text = "连接游戏日志";
            IdentityVerificationBannerDetailText.Text = "登录前也可以先扫描 Game.log，稍后将用它识别并绑定你的游戏 ID";
            IdentityVerificationBannerTitleText.Foreground = informationBrush;
            IdentityVerificationBanner.BorderBrush = informationBrush;
            IdentityVerificationBannerActionButton.Content = "扫描日志";
            IdentityVerificationBannerActionButton.Visibility = Visibility.Visible;
            return;
        }

        if (!_identityBindingSupported || IsIdentityBindingVerified)
        {
            IdentityVerificationBanner.Visibility = Visibility.Collapsed;
            if (TopBannerReserveRow is not null)
            {
                TopBannerReserveRow.Height = new GridLength(0);
            }

            return;
        }

        IdentityVerificationBanner.Visibility = Visibility.Visible;
        if (TopBannerReserveRow is not null)
        {
            TopBannerReserveRow.Height = new GridLength(38);
        }

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

    private string GetIdentityBindingSummaryText()
    {
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

    private async void IdentityVerificationBannerActionButton_Click(object sender, RoutedEventArgs e)
    {
        if (!IsLoggedIn)
        {
            QuickScanLogAndStart();
            RefreshIdentityVerificationPresentation();
            return;
        }

        await ShowIdentityBindingPromptAsync(force: true);
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
        if (!IsLoggedIn || !_identityBindingSupported || IsIdentityBindingVerified)
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
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", _authToken);
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
