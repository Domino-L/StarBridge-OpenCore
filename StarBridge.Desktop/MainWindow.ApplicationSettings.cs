using Microsoft.Win32;
using StarBridge.Core.Presence;
using StarBridge.Core.Profiles;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using Brushes = System.Windows.Media.Brushes;
using SaveFileDialog = Microsoft.Win32.SaveFileDialog;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private void RefreshPersonalApplicationSettings()
    {
        if (PersonalAppVersionValueText is null)
        {
            return;
        }

        PersonalAppVersionValueText.Text = $"V{GetAppVersion()}";
        PersonalAppConfigPathValueText.Text = DesktopAppConfig.ConfigDirectory;
        LocalDataRootPathText.Text = DesktopAppConfig.ConfigDirectory;
        RefreshApplicationBehaviorPresentation();
        RefreshGameplayStatisticsPresentation();
        var canRedeem = IsLoggedIn;
        TemporaryEntitlementCodeBox.IsEnabled = canRedeem;
        TemporaryEntitlementCodeBox.Opacity = canRedeem ? 1 : 0.58;
        RedeemTemporaryEntitlementButton.IsEnabled = canRedeem;
        RedeemTemporaryEntitlementButton.Opacity = canRedeem ? 1 : 0.58;
    }

    private void MigrateLocalDataRootButton_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFolderDialog
        {
            Title = "选择星海舰桥的数据保存位置",
            InitialDirectory = Directory.Exists(DesktopAppConfig.ConfigDirectory)
                ? DesktopAppConfig.ConfigDirectory
                : null,
            Multiselect = false
        };
        if (dialog.ShowDialog(this) != true)
        {
            return;
        }

        string destinationRoot;
        try
        {
            destinationRoot = DesktopStorageRoot.ValidateMigrationDestination(dialog.FolderName);
        }
        catch (Exception ex)
        {
            StarBridgeMessageBox.Show(
                this,
                UserFacingError.Describe(ex, "无法使用所选文件夹，请选择一个空的专用文件夹。"),
                "无法更改数据位置",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
            return;
        }

        if (string.Equals(
                Path.TrimEndingDirectorySeparator(destinationRoot),
                Path.TrimEndingDirectorySeparator(DesktopAppConfig.ConfigDirectory),
                StringComparison.OrdinalIgnoreCase))
        {
            LocalDataManagementActionText.Text = "数据已经保存在所选位置。";
            return;
        }

        if (StarBridgeMessageBox.Show(
                this,
                $"星海舰桥将退出并重启，把配置、缓存、预设和个人数据迁移到：\n\n{destinationRoot}\n\n复制完成后会逐文件校验，确认无误才切换到新目录。是否继续？",
                "迁移数据并重启",
                MessageBoxButton.YesNo,
                MessageBoxImage.Question) != MessageBoxResult.Yes)
        {
            return;
        }

        try
        {
            DesktopStorageRoot.ScheduleMigration(destinationRoot);
            LocalDataManagementActionText.Text = "迁移请求已保存，正在退出并重启应用…";
            if (System.Windows.Application.Current is App app)
            {
                app.RequestExitForDataRootMigration();
            }
        }
        catch (Exception ex)
        {
            StarBridgeMessageBox.Show(
                this,
                UserFacingError.Describe(ex, "迁移请求没有保存，当前数据目录未改变。"),
                "无法开始迁移",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
        }
    }

    private void BindGameplayStatisticsOwner()
    {
        var ownerKey = !string.IsNullOrWhiteSpace(_accountId)
            ? _accountId
            : !string.IsNullOrWhiteSpace(_accountName)
                ? _accountName
                : _localPlayer;
        _gameplayStatisticsRecorder.BindOwner(ownerKey);
        RefreshGameplayStatisticsPresentation();
    }

    private void ShowGameplayDataConsentIfNeeded()
    {
        if (!CanShowPostOnboardingConsentPrompts() ||
            GameplayDataConsentOverlay.Visibility == Visibility.Visible ||
            LocationDataConsentOverlay.Visibility == Visibility.Visible)
        {
            return;
        }

        var consent = _gameplayStatisticsRecorder.Consent;
        if (!GameplayStatisticsConsentPromptPolicy.ShouldPrompt(
                consent,
                _gameplayStatisticsRecorder.HasOwner,
                IsLoggedIn,
                _accountId))
        {
            return;
        }

        ShowGameplayDataConsentDialog(isInitial: true);
    }

    private bool CanShowPostOnboardingConsentPrompts()
    {
        return !_onboardingDialogOpen &&
               _guideMode != GuideMode.IdentityBinding &&
               OnboardingState.GetCompletionStatus() == OnboardingCompletionStatus.Current;
    }

    private void ShowGameplayDataConsentDialog(bool isInitial)
    {
        _gameplayConsentDialogIsInitial = isInitial;
        var allowed = _gameplayStatisticsRecorder.IsRecordingAllowed;
        GameplayDataConsentDeclineButton.Content = allowed ? "停止记录" : "暂不允许";
        GameplayDataConsentAllowButton.Content = allowed ? "继续记录" : "允许并开始记录";
        GameplayDataConsentAllowButton.IsEnabled = _gameplayStatisticsRecorder.HasOwner;
        GameplayDataConsentAllowButton.Opacity = GameplayDataConsentAllowButton.IsEnabled ? 1 : 0.52;
        GameplayDataConsentFooterText.Text = _gameplayStatisticsRecorder.HasOwner
            ? "此选择不会影响日志读取、浮层或组织即时状态。"
            : "登录账号或等待游戏角色识别后，才可开始记录。";
        GameplayDataConsentOverlay.Visibility = Visibility.Visible;
        GameplayDataConsentAllowButton.Focus();
    }

    private void GameplayDataConsentAllowButton_Click(object sender, RoutedEventArgs e)
    {
        var continueStartupConsentFlow = _gameplayConsentDialogIsInitial;
        try
        {
            BindGameplayStatisticsOwner();
            _gameplayStatisticsRecorder.SetConsent(GameplayDataConsentState.Allowed, DateTimeOffset.UtcNow);
            GameplayDataConsentOverlay.Visibility = Visibility.Collapsed;
            RefreshGameplayStatisticsPresentation();
            if (continueStartupConsentFlow)
            {
                ShowLocationDataContributionConsentIfNeeded();
            }
        }
        catch (Exception ex)
        {
            GameplayStatisticsStatusText.Text = UserFacingError.Describe(ex, "记录许可未保存，请稍后重试。");
            GameplayStatisticsStatusText.Foreground = FindBrush("StatusDangerBrush", Brushes.IndianRed);
        }
    }

    private async void GameplayDataConsentDeclineButton_Click(object sender, RoutedEventArgs e)
    {
        var continueStartupConsentFlow = _gameplayConsentDialogIsInitial;
        if (_gameplayStatisticsRecorder.IsRecordingAllowed &&
            !await ConfirmStopGameplayRecordingAsync())
        {
            return;
        }

        try
        {
            _gameplayStatisticsRecorder.SetConsent(GameplayDataConsentState.Declined, DateTimeOffset.UtcNow);
            GameplayDataConsentOverlay.Visibility = Visibility.Collapsed;
            RefreshGameplayStatisticsPresentation();
            if (continueStartupConsentFlow)
            {
                ShowLocationDataContributionConsentIfNeeded();
            }
        }
        catch (Exception ex)
        {
            GameplayStatisticsStatusText.Text = UserFacingError.Describe(ex, "记录设置未保存，请稍后重试。");
            GameplayStatisticsStatusText.Foreground = FindBrush("StatusDangerBrush", Brushes.IndianRed);
        }
    }

    private void GameplayDataConsentCloseButton_Click(object sender, RoutedEventArgs e)
    {
        if (_gameplayConsentDialogIsInitial)
        {
            GameplayDataConsentDeclineButton_Click(sender, e);
            return;
        }

        GameplayDataConsentOverlay.Visibility = Visibility.Collapsed;
        RefreshGameplayStatisticsPresentation();
    }

    private void GameplayStatisticsExplainButton_Click(object sender, RoutedEventArgs e)
    {
        ShowGameplayDataConsentDialog(isInitial: false);
    }

    private async void GameplayStatisticsConsentCheck_Changed(object sender, RoutedEventArgs e)
    {
        if (_isLoadingSettings || _isApplyingGameplayStatisticsConsent)
        {
            return;
        }

        if (GameplayStatisticsConsentCheck.IsChecked == true)
        {
            if (!_gameplayStatisticsRecorder.IsRecordingAllowed)
            {
                _isApplyingGameplayStatisticsConsent = true;
                GameplayStatisticsConsentCheck.IsChecked = false;
                _isApplyingGameplayStatisticsConsent = false;
                ShowGameplayDataConsentDialog(isInitial: false);
            }

            return;
        }

        if (_gameplayStatisticsRecorder.IsRecordingAllowed)
        {
            _isApplyingGameplayStatisticsConsent = true;
            GameplayStatisticsConsentCheck.IsChecked = true;
            _isApplyingGameplayStatisticsConsent = false;
            if (!await ConfirmStopGameplayRecordingAsync())
            {
                RefreshGameplayStatisticsPresentation();
                return;
            }

            try
            {
                _gameplayStatisticsRecorder.SetConsent(GameplayDataConsentState.Declined, DateTimeOffset.UtcNow);
            }
            catch (Exception ex)
            {
                GameplayStatisticsStatusText.Text = UserFacingError.Describe(ex, "暂时无法停止记录，请稍后重试。");
                GameplayStatisticsStatusText.Foreground = FindBrush("StatusDangerBrush", Brushes.IndianRed);
            }
        }

        RefreshGameplayStatisticsPresentation();
    }

    private Task<bool> ConfirmStopGameplayRecordingAsync()
    {
        return ShowAppConfirmationAsync(
            "停止游玩时长记录？",
            "停止后，星海舰桥不会继续累计游玩时长。",
            "已有实时记录和历史补录会保留。再次开启后会继续累计；如需从零开始，请使用“重置游玩时长”。",
            "停止记录",
            "继续记录",
            danger: false,
            footerText: "此操作不会删除已有数据，也不会恢复历史导入次数。");
    }

    private async void GameplayStatisticsImportHistoryButton_Click(object sender, RoutedEventArgs e)
    {
        if (_gameplayStatisticsRecorder.Snapshot.HistoryImportedAt.HasValue)
        {
            await ShowAppNoticeAsync(
                "历史记录已经导入",
                "一次导入资格已经使用。",
                "重置游玩时长会同时清除历史补录，并恢复一次导入资格。");
            return;
        }

        var expectedGameName = ResolveGameplayHistoryIdentity();
        if (!_gameplayStatisticsRecorder.IsRecordingAllowed || string.IsNullOrWhiteSpace(expectedGameName))
        {
            await ShowAppNoticeAsync(
                "暂时无法导入",
                "请先允许游玩时长记录，并完成当前游戏 ID 识别。",
                "身份不匹配时不会导入，以免把其他游戏 ID 的记录计入当前资料。");
            return;
        }

        GameplayStatisticsImportHistoryButton.IsEnabled = false;
        GameplayStatisticsImportHistoryButton.Content = "正在扫描…";
        GameplayHistoryImportResult analysis;
        try
        {
            var gameLogPath = _logPath;
            var recordedBefore = _gameplayStatisticsRecorder.Snapshot.FirstRecordedAt;
            analysis = await Task.Run(() => GameplayHistoryImporter.Scan(
                gameLogPath,
                expectedGameName,
                recordedBefore));
        }
        finally
        {
            GameplayStatisticsImportHistoryButton.Content = "导入历史记录";
            RefreshGameplayStatisticsPresentation();
        }

        if (!analysis.HasData)
        {
            await ShowAppNoticeAsync(
                "没有可导入的历史记录",
                analysis.Error ?? "未找到有效的历史时长。",
                $"已跳过 {analysis.SkippedFileCount} 个无法确认归属、时间异常或与现有记录重叠的日志文件。");
            return;
        }

        var durationText = FormatGameplayStatisticsDuration(analysis.PlayTimeSeconds);
        var incompleteText = analysis.IncompleteSessionCount > 0
            ? $"其中 {analysis.IncompleteSessionCount} 次没有正常退出标记，将显示为非完整记录。"
            : "这些记录均包含完整的启动与正常退出时间范围。";
        var confirmed = await ShowAppConfirmationAsync(
            "导入历史游戏时长？",
            $"发现 {analysis.SessionCount} 次属于 {expectedGameName} 的历史记录，共 {durationText}。",
            $"只会补入可验证的游玩时长。{incompleteText}",
            "确认导入",
            "暂不导入",
            danger: false,
            footerText: "成功导入后不能重复执行；重置游玩时长后可再次导入一次。");
        if (!confirmed)
        {
            return;
        }

        try
        {
            _gameplayStatisticsRecorder.ImportHistory(analysis, DateTimeOffset.UtcNow);
            RefreshGameplayStatisticsPresentation();
            if (_gameplayStatisticsRecorder.Consent.ShareOnProfile)
            {
                await SyncGameplayStatisticsAsync();
            }

            await ShowAppNoticeAsync(
                "历史记录导入完成",
                $"已补入 {durationText}，共 {analysis.SessionCount} 次历史记录。",
                analysis.IncompleteSessionCount > 0
                    ? $"其中 {analysis.IncompleteSessionCount} 次已标记为非完整记录。"
                    : "记录来源与导入时间已保存，可在统计摘要中查看。");
        }
        catch (Exception ex)
        {
            await ShowAppNoticeAsync(
                "历史记录导入失败",
                UserFacingError.Describe(ex, "历史记录导入未完成，请检查日志文件后重试。"),
                "本次没有消耗导入资格，可以修正问题后重试。");
        }
    }

    private string? ResolveGameplayHistoryIdentity()
    {
        if (_identityBindingAssessment.State == StarBridge.Core.Identity.IdentityVerificationState.Mismatch)
        {
            return null;
        }

        return _identityBindingAssessment.BoundGameName ??
               _identityBindingAssessment.DetectedGameName ??
               _localPlayer;
    }

    private async void GameplayStatisticsShareCheck_Changed(object sender, RoutedEventArgs e)
    {
        if (_isLoadingSettings || _isApplyingGameplayStatisticsConsent)
        {
            return;
        }

        var shouldShare = GameplayStatisticsShareCheck.IsChecked == true;
        try
        {
            _gameplayStatisticsRecorder.SetProfileSharing(shouldShare, DateTimeOffset.UtcNow);
            _gameplayStatisticsPrivacySyncPending = true;
            _gameplayStatisticsSyncError = null;
            RefreshGameplayStatisticsPresentation();
            await SyncGameplayStatisticsAsync(allowPrivacyRevocationWhileOffline: !shouldShare);
        }
        catch (Exception ex)
        {
            GameplayStatisticsShareStatusText.Text = UserFacingError.Describe(ex, "展示设置未保存，请稍后重试。");
            GameplayStatisticsShareStatusText.Foreground = FindBrush("StatusDangerBrush", Brushes.IndianRed);
            RefreshGameplayStatisticsPresentation();
        }
    }

    private async void GameplayStatisticsClearButton_Click(object sender, RoutedEventArgs e)
    {
        var confirmed = await ShowAppConfirmationAsync(
            "重置本地游玩时长？",
            "已记录的游玩时长将从本机删除。",
            "这会清除实时与历史时长，并恢复一次历史导入资格。记录许可不会改变。",
            "重置游玩时长",
            "保留数据",
            danger: true,
            footerText: "如果统计已公开，将同步清空公开汇总。此操作无法撤销。");
        if (!confirmed)
        {
            return;
        }

        try
        {
            _gameplayStatisticsRecorder.Clear();
            RefreshGameplayStatisticsPresentation();
            if (_gameplayStatisticsRecorder.Consent.ShareOnProfile)
            {
                await SyncGameplayStatisticsAsync();
            }
        }
        catch (Exception ex)
        {
            GameplayStatisticsStatusText.Text = UserFacingError.Describe(ex, "统计数据未能清除，请稍后重试。");
            GameplayStatisticsStatusText.Foreground = FindBrush("StatusDangerBrush", Brushes.IndianRed);
        }
    }

    private void RefreshGameplayStatisticsPresentation()
    {
        if (GameplayStatisticsConsentCheck is null)
        {
            return;
        }

        var consent = _gameplayStatisticsRecorder.Consent;
        var snapshot = _gameplayStatisticsRecorder.Snapshot;
        _isApplyingGameplayStatisticsConsent = true;
        try
        {
            GameplayStatisticsConsentCheck.IsChecked = _gameplayStatisticsRecorder.IsRecordingAllowed;
            GameplayStatisticsShareCheck.IsChecked = consent.ShareOnProfile;
        }
        finally
        {
            _isApplyingGameplayStatisticsConsent = false;
        }

        GameplayStatisticsStatusText.Text = (_gameplayStatisticsRecorder.LastWriteError, consent.State) switch
        {
            (not null, GameplayDataConsentState.Allowed) => "已允许 · 本地保存暂时失败，将自动重试",
            (_, GameplayDataConsentState.Allowed) => "已允许 · 正在本机静默累计游玩时长",
            (_, GameplayDataConsentState.Declined) => "未允许 · 当前不会记录游玩时长",
            _ when !_gameplayStatisticsRecorder.HasOwner => "等待登录账号或游戏角色识别",
            _ => "尚未选择是否允许记录"
        };
        GameplayStatisticsStatusText.Foreground = (_gameplayStatisticsRecorder.LastWriteError, consent.State) switch
        {
            (not null, GameplayDataConsentState.Allowed) => FindBrush("StatusDangerBrush", Brushes.IndianRed),
            (_, GameplayDataConsentState.Allowed) => FindBrush("StatusSuccessBrush", Brushes.SpringGreen),
            (_, GameplayDataConsentState.Declined) => FindBrush("StatusDisabledBrush", Brushes.LightSlateGray),
            _ when !_gameplayStatisticsRecorder.HasOwner => FindBrush("StatusDisabledBrush", Brushes.LightSlateGray),
            _ => FindBrush("StatusWarningBrush", Brushes.Orange)
        };

        var durationText = FormatGameplayStatisticsDuration(snapshot.PlayTimeSeconds);
        var historicalText = snapshot.HistoryImportedAt.HasValue
            ? $" · 历史补录 {FormatGameplayStatisticsDuration(snapshot.HistoricalPlayTimeSeconds)} / {snapshot.HistoricalSessionCount} 次" +
              (snapshot.HistoricalIncompleteSessionCount > 0
                  ? $"（{snapshot.HistoricalIncompleteSessionCount} 次非完整）"
                  : "")
            : "";
        GameplayStatisticsSummaryText.Text = _gameplayStatisticsRecorder.IsRecordingAllowed || snapshot != GameplayStatisticsSnapshot.Empty
            ? $"已记录 {durationText}{historicalText}"
            : "允许后开始累计游玩时长，也可主动导入 logbackups 中的历史时长。";
        var canImportHistory = _gameplayStatisticsRecorder.IsRecordingAllowed &&
                               !snapshot.HistoryImportedAt.HasValue &&
                               !string.IsNullOrWhiteSpace(_logPath) &&
                               File.Exists(_logPath) &&
                               !string.IsNullOrWhiteSpace(ResolveGameplayHistoryIdentity());
        GameplayStatisticsImportHistoryButton.IsEnabled = canImportHistory;
        GameplayStatisticsImportHistoryButton.Opacity = canImportHistory ? 1 : 0.52;
        GameplayStatisticsImportHistoryButton.Content = snapshot.HistoryImportedAt.HasValue
            ? "历史记录已导入"
            : "导入历史记录";
        GameplayStatisticsImportHistoryButton.ToolTip = snapshot.HistoryImportedAt.HasValue
            ? "重置游玩时长后可再次导入一次"
            : !_gameplayStatisticsRecorder.IsRecordingAllowed
                ? "请先允许游玩时长记录"
                : "扫描 Game.log 同目录下的 logbackups 历史日志";
        GameplayStatisticsConsentCheck.IsEnabled = _gameplayStatisticsRecorder.HasOwner;
        GameplayStatisticsConsentCheck.Opacity = GameplayStatisticsConsentCheck.IsEnabled ? 1 : 0.52;
        GameplayStatisticsClearButton.IsEnabled = snapshot != GameplayStatisticsSnapshot.Empty;
        GameplayStatisticsClearButton.Opacity = GameplayStatisticsClearButton.IsEnabled ? 1 : 0.52;
        GameplayStatisticsShareCheck.IsEnabled = _gameplayStatisticsRecorder.HasOwner;
        GameplayStatisticsShareCheck.Opacity = GameplayStatisticsShareCheck.IsEnabled ? 1 : 0.52;
        GameplayStatisticsShareStatusText.Text = _gameplayStatisticsPrivacySyncPending
            ? consent.ShareOnProfile
                ? "访客展示设置等待同步；恢复在线同步后生效。"
                : "正在撤回访客权限；同步完成前旧公开数据可能仍可见。"
            : !string.IsNullOrWhiteSpace(_gameplayStatisticsSyncError)
                ? _gameplayStatisticsSyncError
                : consent.ShareOnProfile
                    ? _personalProfileSettings.IsProfilePublic
                        ? "已允许访客查看；只同步游玩时长汇总。"
                        : "已允许访客查看；你的个人主页公开后才会对外显示。"
                    : "默认仅自己可见，不会随公开主页自动公开。";
        GameplayStatisticsShareStatusText.Foreground = _gameplayStatisticsPrivacySyncPending ||
                                                       !string.IsNullOrWhiteSpace(_gameplayStatisticsSyncError)
            ? FindBrush("StatusWarningBrush", Brushes.Goldenrod)
            : consent.ShareOnProfile
                ? FindBrush("StatusSuccessBrush", Brushes.MediumSeaGreen)
                : FindBrush("MutedTextBrush", Brushes.SlateGray);
        RefreshPersonalProfileGameplayStatistics();
        if (PersonalProfileModuleGrid is not null)
        {
            ApplyPersonalProfileModuleLayout();
        }
        RefreshLocalDataManagementPresentation();
    }

    private static string FormatGameplayStatisticsDuration(long seconds)
    {
        var duration = TimeSpan.FromSeconds(Math.Max(0, seconds));
        return duration.TotalHours >= 1
            ? $"{(long)duration.TotalHours} 小时 {duration.Minutes} 分"
            : $"{Math.Max(0, (long)duration.TotalMinutes)} 分钟";
    }

    private void QueueGameplayStatisticsSync(DateTimeOffset now)
    {
        if ((!_gameplayStatisticsRecorder.Consent.ShareOnProfile && !_gameplayStatisticsPrivacySyncPending) ||
            _syncPrivacySettings.PresenceVisibilityMode != PlayerPresenceVisibilityMode.Online ||
            now - _lastGameplayStatisticsSyncAt < TimeSpan.FromMinutes(1))
        {
            return;
        }

        _ = SyncGameplayStatisticsAsync();
    }

    private async Task SyncGameplayStatisticsAsync(bool allowPrivacyRevocationWhileOffline = false)
    {
        if (_isGameplayStatisticsSyncing || !CanSynchronizeUserData || _personalProfileRepository is null)
        {
            return;
        }

        var shareOnProfile = _gameplayStatisticsRecorder.Consent.ShareOnProfile;
        if (!allowPrivacyRevocationWhileOffline &&
            _syncPrivacySettings.PresenceVisibilityMode != PlayerPresenceVisibilityMode.Online)
        {
            GameplayStatisticsShareStatusText.Text = shareOnProfile
                ? "展示设置已保存在本机；恢复在线同步后生效。"
                : "默认仅自己可见，不会随公开主页自动公开。";
            return;
        }

        _isGameplayStatisticsSyncing = true;
        try
        {
            var snapshot = _gameplayStatisticsRecorder.Snapshot;
            var result = await _personalProfileRepository.SaveGameplayStatisticsAsync(
                new PersonalProfileGameplayStatisticsUpdateRequestContract(
                    shareOnProfile,
                    snapshot.PlayTimeSeconds,
                    0,
                    0,
                    snapshot.HistoricalPlayTimeSeconds,
                    snapshot.HistoricalSessionCount,
                    snapshot.HistoricalIncompleteSessionCount,
                    snapshot.HistoryImportedAt));
            if (result.Saved)
            {
                _lastGameplayStatisticsSyncAt = DateTimeOffset.UtcNow;
                _gameplayStatisticsPrivacySyncPending = false;
                _gameplayStatisticsSyncError = null;
                if (result.Document is not null)
                {
                    _personalProfileSyncCoordinator.AcceptSaved(result.Document);
                }
            }
            else if (!string.IsNullOrWhiteSpace(result.Error))
            {
                _gameplayStatisticsPrivacySyncPending = true;
                _gameplayStatisticsSyncError = result.Error;
            }
        }
        finally
        {
            _isGameplayStatisticsSyncing = false;
            RefreshGameplayStatisticsPresentation();
        }
    }

    private void ApplyGameplayStatisticsOwnerDocument(PersonalProfileDocumentContract document)
    {
        if (!_gameplayStatisticsRecorder.HasOwner)
        {
            return;
        }

        if (_gameplayStatisticsRecorder.Consent.ShareOnProfile == document.IsGameplayStatisticsPublic)
        {
            _gameplayStatisticsPrivacySyncPending = false;
            _gameplayStatisticsSyncError = null;
            return;
        }

        try
        {
            _gameplayStatisticsRecorder.SetProfileSharing(
                document.IsGameplayStatisticsPublic,
                DateTimeOffset.UtcNow);
            _gameplayStatisticsPrivacySyncPending = false;
            _gameplayStatisticsSyncError = null;
        }
        catch
        {
            // The server remains the privacy source; local presentation will retry on refresh.
        }
    }

    private void ApplyApplicationBehaviorSettingsToControls()
    {
        if (LaunchAtStartupCheck is null ||
            WindowCloseBehaviorBox is null ||
            StartupWindowBehaviorBox is null)
        {
            return;
        }

        _isApplyingApplicationBehaviorSettings = true;
        try
        {
            _applicationBehaviorSettings = _applicationBehaviorSettings.Normalize();
            LaunchAtStartupCheck.IsChecked = _applicationBehaviorSettings.LaunchAtStartup;
            WindowCloseBehaviorBox.SelectedIndex = _applicationBehaviorSettings.KeepRunningInBackground ? 0 : 1;
            StartupWindowBehaviorBox.SelectedIndex = _applicationBehaviorSettings.StartMinimized ? 1 : 0;
            StartupWindowBehaviorBox.IsEnabled = _applicationBehaviorSettings.LaunchAtStartup;
        }
        finally
        {
            _isApplyingApplicationBehaviorSettings = false;
        }

        RefreshApplicationBehaviorPresentation();
    }

    private void ApplicationBehaviorSetting_Changed(object sender, RoutedEventArgs e)
    {
        if (_isLoadingSettings || _isApplyingApplicationBehaviorSettings)
        {
            return;
        }

        var requested = _applicationBehaviorSettings with
        {
            LaunchAtStartup = LaunchAtStartupCheck.IsChecked == true,
            KeepRunningInBackground = WindowCloseBehaviorBox.SelectedIndex == 0,
            StartMinimized = StartupWindowBehaviorBox.SelectedIndex == 1,
            CloseBehaviorChoiceMade = _applicationBehaviorSettings.CloseBehaviorChoiceMade ||
                                      ReferenceEquals(sender, WindowCloseBehaviorBox)
        };
        if (System.Windows.Application.Current is not App app)
        {
            ApplicationBehaviorStatusText.Text = "无法连接应用生命周期服务，设置未保存。";
            ApplicationBehaviorStatusText.Foreground = FindBrush("StatusDangerBrush", Brushes.IndianRed);
            ApplyApplicationBehaviorSettingsToControls();
            return;
        }

        var result = app.TryApplyBehaviorSettings(requested);
        _applicationBehaviorSettings = result.Settings;
        ApplyApplicationBehaviorSettingsToControls();
        if (!result.Succeeded)
        {
            ApplicationBehaviorStatusText.Text = $"设置未保存：{result.Error ?? "系统拒绝了本次更改。"}";
            ApplicationBehaviorStatusText.Foreground = FindBrush("StatusDangerBrush", Brushes.IndianRed);
            return;
        }

        ApplicationBehaviorStatusText.Text = "启动与后台设置已保存。";
        ApplicationBehaviorStatusText.Foreground = FindBrush("StatusSuccessBrush", Brushes.SpringGreen);
    }

    private void RefreshApplicationBehaviorPresentation()
    {
        if (ApplicationBehaviorCloseSummaryText is null)
        {
            return;
        }

        var settings = _applicationBehaviorSettings.Normalize();
        ApplicationBehaviorCloseSummaryText.Text = settings.KeepRunningInBackground
            ? "关闭窗口后：继续在系统托盘运行"
            : "关闭窗口后：完全退出应用";
        ApplicationBehaviorStartupSummaryText.Text = !settings.LaunchAtStartup
            ? "登录 Windows 后：不自动启动"
            : settings.StartMinimized
                ? "登录 Windows 后：直接进入后台"
                : "登录 Windows 后：打开主窗口";
        StartupWindowBehaviorBox.IsEnabled = settings.LaunchAtStartup;

        if (System.Windows.Application.Current is App app &&
            !string.IsNullOrWhiteSpace(app.ApplicationBehaviorError))
        {
            ApplicationBehaviorStatusText.Text = $"开机启动状态同步失败：{app.ApplicationBehaviorError}";
            ApplicationBehaviorStatusText.Foreground = FindBrush("StatusWarningBrush", Brushes.Orange);
        }
    }

    private void ApplyLocalPlayReminderSettingsToControls()
    {
        if (ContinuousPlayReminderCheck is null ||
            ContinuousPlayFirstIntervalBox is null ||
            ContinuousPlayRepeatIntervalBox is null)
        {
            return;
        }

        _localPlayReminderSettings = _localPlayReminderSettings.Normalize();
        _isApplyingLocalPlayReminderSettings = true;
        try
        {
            ContinuousPlayReminderCheck.IsChecked = _localPlayReminderSettings.Enabled;
            SelectComboBoxTag(
                ContinuousPlayFirstIntervalBox,
                _localPlayReminderSettings.FirstReminderMinutes.ToString(CultureInfo.InvariantCulture));
            SelectComboBoxTag(
                ContinuousPlayRepeatIntervalBox,
                _localPlayReminderSettings.RepeatReminderMinutes.ToString(CultureInfo.InvariantCulture));
            ContinuousPlayFirstIntervalBox.IsEnabled = _localPlayReminderSettings.Enabled;
            ContinuousPlayRepeatIntervalBox.IsEnabled = _localPlayReminderSettings.Enabled;
            if (EventNotifyLocalPlayReminderCheck is not null)
            {
                EventNotifyLocalPlayReminderCheck.IsChecked = _localPlayReminderSettings.Enabled;
            }
        }
        finally
        {
            _isApplyingLocalPlayReminderSettings = false;
        }

        _localPlaySessionReminder.ConfigureDelays(
            _localPlayReminderSettings.FirstReminderDelay,
            _localPlayReminderSettings.RepeatReminderDelay,
            DateTimeOffset.UtcNow);
        RefreshLocalPlayReminderPresentation();
    }

    private void LocalPlayReminderSetting_Changed(object sender, RoutedEventArgs e)
    {
        if (_isLoadingSettings || _isApplyingLocalPlayReminderSettings)
        {
            return;
        }

        var requested = new LocalPlayReminderSettings(
            ContinuousPlayReminderCheck.IsChecked == true,
            GetComboBoxTagAsInt(
                ContinuousPlayFirstIntervalBox,
                _localPlayReminderSettings.FirstReminderMinutes),
            GetComboBoxTagAsInt(
                ContinuousPlayRepeatIntervalBox,
                _localPlayReminderSettings.RepeatReminderMinutes)).Normalize();
        if (!LocalPlayReminderSettingsStore.TrySave(requested, out var error))
        {
            ContinuousPlayReminderStatusText.Text = $"设置未保存：{error}";
            ContinuousPlayReminderStatusText.Foreground = FindBrush("StatusDangerBrush", Brushes.IndianRed);
            ApplyLocalPlayReminderSettingsToControls();
            return;
        }

        _localPlayReminderSettings = requested;
        var types = requested.Enabled
            ? _overlaySettings.EventNotificationTypes | OverlayEventNotificationTypes.LocalPlayReminder
            : _overlaySettings.EventNotificationTypes & ~OverlayEventNotificationTypes.LocalPlayReminder;
        _overlaySettings = _overlaySettings with
        {
            EventNotificationTypes = OverlayDisplaySettings.NormalizeEventNotificationTypes(types)
        };
        ApplyLocalPlayReminderSettingsToControls();
        SaveCurrentConfig();
        RefreshOverlayEventNotificationControls();
        ContinuousPlayReminderStatusText.Text = "连续游玩提醒设置已保存。";
        ContinuousPlayReminderStatusText.Foreground = FindBrush("StatusSuccessBrush", Brushes.SpringGreen);
    }

    private void RefreshLocalPlayReminderPresentation()
    {
        if (ContinuousPlayReminderStatusText is null)
        {
            return;
        }

        ContinuousPlayReminderStatusText.Text = _localPlayReminderSettings.Enabled
            ? $"首次在 {FormatReminderMinutes(_localPlayReminderSettings.FirstReminderMinutes)}后提醒，之后每 {FormatReminderMinutes(_localPlayReminderSettings.RepeatReminderMinutes)}提醒一次。"
            : "已关闭，不会显示连续游玩提醒。";
        ContinuousPlayReminderStatusText.Foreground = _localPlayReminderSettings.Enabled
            ? FindBrush("StatusSuccessBrush", Brushes.SpringGreen)
            : FindBrush("StatusDisabledBrush", Brushes.LightSlateGray);
    }

    private static string FormatReminderMinutes(int minutes) => minutes switch
    {
        60 => "1 小时",
        90 => "1.5 小时",
        120 => "2 小时",
        180 => "3 小时",
        _ => $"{minutes} 分钟"
    };

    private void RefreshLocalDataManagementPresentation()
    {
        if (LocalDataManagementStatusText is null)
        {
            return;
        }

        var snapshot = _gameplayStatisticsRecorder.Snapshot;
        var duration = TimeSpan.FromSeconds(Math.Max(0, snapshot.PlayTimeSeconds));
        var durationText = duration.TotalHours >= 1
            ? $"{(long)duration.TotalHours} 小时 {duration.Minutes} 分"
            : $"{Math.Max(0, (long)duration.TotalMinutes)} 分钟";
        LocalDataManagementStatusText.Text =
            $"游玩时长：{durationText} · 地点待提交：{_locationDataContributionRecorder.PendingCount} · 已提交记录：{_locationDataContributionRecorder.SubmittedCount}";
        LocalDataClearStatisticsButton.IsEnabled = snapshot != GameplayStatisticsSnapshot.Empty;
        LocalDataClearStatisticsButton.Opacity = LocalDataClearStatisticsButton.IsEnabled ? 1 : 0.52;
        LocalDataClearLocationButton.IsEnabled = _locationDataContributionRecorder.PendingCount > 0 ||
                                                 _locationDataContributionRecorder.SubmittedCount > 0;
        LocalDataClearLocationButton.Opacity = LocalDataClearLocationButton.IsEnabled ? 1 : 0.52;
    }

    private void ExportLocalDataButton_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new SaveFileDialog
        {
            Title = "导出星海舰桥本地数据",
            Filter = "JSON 文件 (*.json)|*.json",
            FileName = $"StarBridge-local-data-{DateTime.Now:yyyyMMdd-HHmm}.json",
            AddExtension = true,
            DefaultExt = ".json"
        };
        if (dialog.ShowDialog(this) != true)
        {
            return;
        }

        try
        {
            var payload = new
            {
                ExportedAt = DateTimeOffset.Now,
                ApplicationVersion = GetAppUpdateVersion(),
                GameplayStatistics = _gameplayStatisticsRecorder.Snapshot,
                GameplayDataConsent = _gameplayStatisticsRecorder.Consent,
                LocationContribution = new
                {
                    _locationDataContributionRecorder.Consent,
                    _locationDataContributionRecorder.PendingCount,
                    _locationDataContributionRecorder.SubmittedCount
                }
            };
            File.WriteAllText(
                dialog.FileName,
                JsonSerializer.Serialize(payload, new JsonSerializerOptions { WriteIndented = true }));
            LocalDataManagementActionText.Text = $"已导出：{Path.GetFileName(dialog.FileName)}";
            LocalDataManagementActionText.Foreground = FindBrush("StatusSuccessBrush", Brushes.SpringGreen);
        }
        catch (Exception ex)
        {
            LocalDataManagementActionText.Text = UserFacingError.Describe(ex, "本地数据未能导出，请稍后重试。");
            LocalDataManagementActionText.Foreground = FindBrush("StatusDangerBrush", Brushes.IndianRed);
        }
    }

    private async void ClearLocationDataButton_Click(object sender, RoutedEventArgs e)
    {
        var confirmed = await ShowAppConfirmationAsync(
            "清除本地点数据记录？",
            "待提交地点代码和本机去重记录将被删除。",
            "参与许可不会改变；如果仍允许采集，之后遇到的地点代码会重新记录。",
            "清除地点记录",
            "保留数据",
            danger: true,
            footerText: "此操作只影响当前本机，无法撤销。");
        if (!confirmed)
        {
            return;
        }

        try
        {
            _locationDataContributionRecorder.ClearLocalObservations();
            RefreshLocationDataContributionPresentation();
            LocalDataManagementActionText.Text = "本地点数据记录已清除。";
            LocalDataManagementActionText.Foreground = FindBrush("StatusSuccessBrush", Brushes.SpringGreen);
        }
        catch (Exception ex)
        {
            LocalDataManagementActionText.Text = UserFacingError.Describe(ex, "本地数据未能清除，请稍后重试。");
            LocalDataManagementActionText.Foreground = FindBrush("StatusDangerBrush", Brushes.IndianRed);
        }
    }

    private async void RunApplicationDiagnosticsButton_Click(object sender, RoutedEventArgs e)
    {
        RunApplicationDiagnosticsButton.IsEnabled = false;
        ApplicationDiagnosticsSummaryText.Text = "正在检查本地环境与服务器连接…";
        ApplicationDiagnosticsDetailText.Text = "请稍候";
        try
        {
            var results = new List<ApplicationDiagnosticResult>
            {
                ApplicationDiagnosticProbe.CheckWritableDirectory(DesktopAppConfig.ConfigDirectory),
                ApplicationDiagnosticProbe.CheckGameLog(_logPath)
            };
            var networkConnected = await TestNetworkAsync(silent: true);
            results.Add(new ApplicationDiagnosticResult(
                "服务器连接",
                networkConnected,
                networkConnected
                    ? _lastRelayLatencyMs >= 0 ? $"可连接 · {_lastRelayLatencyMs} ms" : "可连接"
                    : "连接失败，请检查网络或服务器地址"));

            var startupRead = WindowsStartupRegistration.TryGetEnabled(out var startupEnabled, out var startupError);
            var startupMatches = startupRead && startupEnabled == _applicationBehaviorSettings.LaunchAtStartup;
            results.Add(new ApplicationDiagnosticResult(
                "开机启动",
                startupMatches,
                startupRead
                    ? startupMatches ? "注册状态与设置一致" : "注册状态与设置不一致，请重新切换开机自启动"
                    : $"无法读取：{startupError}"));

            var installationScan = ApplicationInstallationMaintenance.Scan();
            results.Add(new ApplicationDiagnosticResult(
                "安装状态",
                !installationScan.HasMaintenanceIssue,
                ApplicationInstallationMaintenance.Describe(installationScan)));

            var passed = results.Count(result => result.Passed);
            ApplicationDiagnosticsSummaryText.Text = passed == results.Count
                ? $"诊断完成 · {passed}/{results.Count} 项正常"
                : $"诊断完成 · {results.Count - passed} 项需要处理";
            ApplicationDiagnosticsSummaryText.Foreground = passed == results.Count
                ? FindBrush("StatusSuccessBrush", Brushes.SpringGreen)
                : FindBrush("StatusWarningBrush", Brushes.Orange);
            ApplicationDiagnosticsDetailText.Text = string.Join(
                "   ",
                results.Select(result => $"{(result.Passed ? "✓" : "!")} {result.Name}：{result.Detail}"));
        }
        catch (Exception ex)
        {
            ApplicationDiagnosticsSummaryText.Text = "诊断未完成";
            ApplicationDiagnosticsSummaryText.Foreground = FindBrush("StatusDangerBrush", Brushes.IndianRed);
            ApplicationDiagnosticsDetailText.Text = UserFacingError.Describe(ex, "一键诊断未完成，请稍后重试。");
        }
        finally
        {
            RunApplicationDiagnosticsButton.IsEnabled = true;
        }
    }

    private async void InstallationMaintenanceButton_Click(object sender, RoutedEventArgs e)
    {
        InstallationMaintenanceButton.IsEnabled = false;
        try
        {
            var scan = ApplicationInstallationMaintenance.Scan();
            var target = ApplicationInstallationMaintenance.SelectUninstallTarget(scan);
            var cleanupCount = scan.OrphanedRegistrations.Count +
                               (scan.StartupEntry?.NeedsCleanup == true ? 1 : 0);

            if (ApplicationInstallationMaintenance.IsReadOnlyPreviewBuild)
            {
                var previewTarget = target is null
                    ? "没有可调用的官方卸载器"
                    : $"拟调用：{target.DisplayName} {target.DisplayVersion}\n位置：{target.InstallDirectory}";
                await ShowAppNoticeAsync(
                    "Debug 安装清理检查",
                    ApplicationInstallationMaintenance.Describe(scan),
                    $"{previewTarget}\n拟清理的失效注册项：{cleanupCount}。\nDebug 版本仅显示检查结果，不会启动卸载器、删除注册项或改写开机启动项。",
                    "完成检查");
                return;
            }

            if (target is null && cleanupCount == 0)
            {
                await ShowAppNoticeAsync(
                    "没有可调用的官方卸载器",
                    "当前运行的可能是便携副本，或正式安装信息已经被手动删除。",
                    $"程序位置：{scan.CurrentExecutable}\n为避免丢失旧版本内的数据，本工具不会直接删除程序目录。请退出后确认该目录内容，再手动移除不需要的副本。");
                return;
            }

            var isCurrentTarget = target?.IsCurrentInstallation == true;
            var actionTitle = target is null
                ? "清理星海舰桥安装残留？"
                : isCurrentTarget
                    ? "卸载当前星海舰桥？"
                    : "卸载检测到的其他版本？";
            var actionMessage = target is null
                ? $"将移除 {cleanupCount} 个确认失效的本应用注册项。"
                : $"将启动 {target.DisplayName} {target.DisplayVersion} 的官方卸载器。";
            var targetDetail = target is null
                ? "不会扫描或删除其他软件的注册表，也不会删除星海舰桥用户数据。"
                : $"安装位置：{target.InstallDirectory}\n" +
                  (cleanupCount > 0 ? $"同时清理 {cleanupCount} 个失效注册项。" : "未发现额外失效注册项。") +
                  " 用户数据目录会保留。";

            var confirmed = await ShowAppConfirmationAsync(
                actionTitle,
                actionMessage,
                targetDetail,
                target is null ? "清理残留" : "启动卸载",
                "取消",
                danger: true,
                footerText: isCurrentTarget
                    ? "启动卸载器后，星海舰桥将退出。"
                    : "只处理已确认属于星海舰桥的安装信息。");
            if (!confirmed)
            {
                return;
            }

            var cleanup = ApplicationInstallationMaintenance.CleanupOrphansAndStaleStartup(scan);
            if (target is null)
            {
                var cleanupSummary = cleanup.Errors.Count == 0
                    ? $"已移除 {cleanup.RemovedUninstallRegistrations} 个失效卸载项" +
                      (cleanup.RemovedStartupEntry ? "，并清理失效开机启动项。" : "。")
                    : $"已完成部分清理，但有 {cleanup.Errors.Count} 项未能处理：{string.Join("；", cleanup.Errors)}";
                await ShowAppNoticeAsync(
                    cleanup.Errors.Count == 0 ? "安装残留已清理" : "安装残留部分清理",
                    cleanupSummary,
                    "用户数据和仍然有效的安装项没有被删除。",
                    "完成");
                return;
            }

            if (!ApplicationInstallationMaintenance.TryStartUninstaller(target, out var error))
            {
                await ShowAppNoticeAsync(
                    "无法启动卸载器",
                    error ?? "官方卸载器未能启动。",
                    "请打开 Windows“已安装的应用”，搜索“星海舰桥”后重试卸载。");
                return;
            }

            if (isCurrentTarget)
            {
                if (System.Windows.Application.Current is App app)
                {
                    app.RequestExit();
                }
                else
                {
                    System.Windows.Application.Current.Shutdown();
                }

                return;
            }

            if (_applicationBehaviorSettings.LaunchAtStartup)
            {
                WindowsStartupRegistration.TrySetEnabled(enabled: true, out _);
            }

            ApplicationDiagnosticsSummaryText.Text = "已启动其他版本的官方卸载器";
            ApplicationDiagnosticsDetailText.Text = "完成卸载后可再次运行一键诊断，确认重复安装与开机启动项均已清除。";
            ApplicationDiagnosticsSummaryText.Foreground = FindBrush("StatusSuccessBrush", Brushes.SpringGreen);
        }
        catch (Exception ex)
        {
            await ShowAppNoticeAsync(
                "安装清理未完成",
                UserFacingError.Describe(ex, "无法检查或处理安装信息，请稍后重试。"),
                "未执行目录删除，用户数据不受影响。");
        }
        finally
        {
            InstallationMaintenanceButton.IsEnabled = true;
        }
    }

    private void ExitApplicationButton_Click(object sender, RoutedEventArgs e)
    {
        if (System.Windows.Application.Current is App app)
        {
            app.RequestExit();
            return;
        }

        System.Windows.Application.Current.Shutdown();
    }

    private async void RedeemTemporaryEntitlementButton_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureLoggedIn("使用兑换码需要先登录服务器账号。"))
        {
            return;
        }

        var code = TemporaryEntitlementCodeBox.Text.Trim();
        if (string.IsNullOrWhiteSpace(code))
        {
            TemporaryEntitlementStatusText.Text = "请输入兑换码。";
            return;
        }

        RedeemTemporaryEntitlementButton.IsEnabled = false;
        TemporaryEntitlementStatusText.Text = "正在兑换…";
        try
        {
            var response = await PostNetworkJsonAsync(
                "api/auth/entitlements/redeem",
                new TemporaryEntitlementRedeemRequest(code));
            if (HandleAuthorizationFailure(response.StatusCode, "兑换"))
            {
                return;
            }

            if (!response.IsSuccessStatusCode)
            {
                TemporaryEntitlementStatusText.Text = await ReadResponseErrorAsync(response) ?? "兑换失败。";
                return;
            }

            var auth = await response.Content.ReadFromJsonAsync<AuthResponse>();
            if (auth is null)
            {
                TemporaryEntitlementStatusText.Text = "暂时无法兑换，请稍后重试。";
                return;
            }

            ApplyAuthResponse(auth);
            await RefreshNotificationCenterAsync(showErrors: false);
            SaveCurrentConfig();
            TemporaryEntitlementCodeBox.Clear();
            TemporaryEntitlementStatusText.Text = "兑换成功。";
        }
        catch (Exception ex)
        {
            TemporaryEntitlementStatusText.Text = UserFacingError.Describe(ex, "兑换未完成，请稍后重试。");
        }
        finally
        {
            RefreshPersonalApplicationSettings();
        }
    }

    private static OverlayVisualTheme GetOverlayThemeForShip(string? shipCode)
    {
        var code = ShipNameLocalizer.ResolveCode(shipCode);
        if (string.IsNullOrWhiteSpace(code) ||
            code.Equals("Unknown", StringComparison.OrdinalIgnoreCase))
        {
            return OverlayVisualTheme.Default;
        }

        var normalizedCode = code.ToUpperInvariant();
        var manufacturerCode = normalizedCode.Split('_', 2)[0];

        return manufacturerCode switch
        {
            "ANVL" => OverlayVisualTheme.Anvil,
            "DRAK" => OverlayVisualTheme.Drake,
            "ARGO" => OverlayVisualTheme.Argo,
            "MRAI" or "MIRAI" => OverlayVisualTheme.Mirai,
            "MISC" when normalizedCode.Contains("RAZOR", StringComparison.OrdinalIgnoreCase) => OverlayVisualTheme.Mirai,
            "MISC" => OverlayVisualTheme.Musashi,
            "CRUS" => OverlayVisualTheme.Crusader,
            "AEGS" => OverlayVisualTheme.Aegis,
            "RSI" => OverlayVisualTheme.Rsi,
            "ORIG" => OverlayVisualTheme.Origin,
            "GAMA" => OverlayVisualTheme.Gatac,
            "XIAN" when normalizedCode.Contains("RAILEN", StringComparison.OrdinalIgnoreCase) => OverlayVisualTheme.Gatac,
            "XIAN" or "AOPOA" or "AOPA" => OverlayVisualTheme.Aopoa,
            "ESPR" => OverlayVisualTheme.Esperia,
            _ => OverlayVisualTheme.Default
        };
    }
}
