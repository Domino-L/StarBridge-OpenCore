namespace StarBridge.Desktop;

using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Net.Http;
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
    private readonly IdentityBindingPromptTracker _identityBindingPromptTracker = new();
    private bool _identityBindingPromptOpen;
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
        _identityBindingPromptTracker.Reset();
        _identityBindingAssessment = IdentityBindingPolicy.Evaluate(null, null, _localPlayer);
        RefreshIdentityVerificationPresentation();
    }

    private void ReevaluateIdentityBinding(bool showPrompt)
    {
        _identityBindingAssessment = IsLoggedIn && _identityBindingSupported
            ? IdentityBindingPolicy.Evaluate(
                _boundGameName,
                _identityBindingConfirmedAt,
                _localPlayer)
            : IdentityBindingPolicy.Evaluate(null, null, _localPlayer);

        if (!CanSynchronizeUserData)
        {
            StopNetworkSyncTimers();
            _profileSyncDebounceTimer.Stop();
            _friendOverlayNotificationTracker.Reset();
            ResetFleetOverlayChatProjection();
        }

        RefreshIdentityVerificationPresentation();
        RefreshHeaderStatusBar();

        if (!_identityBindingPromptTracker.ShouldPrompt(
                _accountId,
                _identityBindingAssessment,
                promptAllowed: showPrompt && IsLoaded && IsLoggedIn &&
                               !_onboardingDialogOpen))
        {
            return;
        }

        Dispatcher.BeginInvoke(
            DispatcherPriority.Background,
            new Action(async () => await ShowIdentityBindingPromptAsync(force: false)));
    }

    private void RefreshIdentityVerificationPresentation()
    {
        if (IdentityVerificationBanner is null || IdentityVerificationBannerActionButton is null)
        {
            return;
        }

        if (!IsLoggedIn || !_identityBindingSupported || IsIdentityBindingVerified)
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
                IdentityVerificationBannerActionButton.Visibility = Visibility.Collapsed;
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
        await ShowIdentityBindingPromptAsync(force: true);
    }

    private async Task ShowIdentityBindingPromptAsync(bool force)
    {
        if (_identityBindingPromptOpen || _identityBindingRequestInProgress || !IsLoggedIn)
        {
            return;
        }

        var assessment = _identityBindingAssessment;
        if (assessment.State is not (IdentityVerificationState.BindingRequired or IdentityVerificationState.Mismatch) ||
            string.IsNullOrWhiteSpace(assessment.DetectedGameName))
        {
            return;
        }

        _identityBindingPromptOpen = true;
        try
        {
            var replacing = assessment.State == IdentityVerificationState.Mismatch;
            var title = replacing ? "无法验证身份" : "绑定游戏身份";
            var message = (replacing
                ? $"当前检测到的游戏 ID 与账号绑定信息不一致。\n\n已绑定：{assessment.BoundGameName}\n当前检测：{assessment.DetectedGameName}\n\n为保护账号数据，所有同步功能已暂停。本地游玩时长仍会继续记录。重新绑定后，舰队身份、权限和机库归属会迁移到新的游戏 ID。"
                : $"已从 Game.log 识别到游戏 ID：{assessment.DetectedGameName}\n\n星海舰桥需要绑定该游戏 ID，用于校验当前账号的游戏身份，避免同一账号切换到其他游戏 ID 后继续同步并造成资料错乱。不同星海舰桥账号可以绑定相同的游戏 ID。") +
                "\n\n如果暂不绑定，星海舰桥将退出。下次启动后仍可重新完成绑定。";
            var confirmed = StarBridgeMessageBox.ShowAction(
                this,
                message,
                title,
                replacing ? "重新绑定" : "绑定此游戏 ID",
                "退出应用",
                replacing ? MessageBoxImage.Warning : MessageBoxImage.Question);
            if (!confirmed)
            {
                ExitApplicationForUnboundIdentity();
                return;
            }

            await BindDetectedGameIdentityAsync(assessment.DetectedGameName, replacing);
        }
        finally
        {
            _identityBindingPromptOpen = false;
        }
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
        }
    }
}
