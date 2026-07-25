using StarBridge.Core.Events;
using StarBridge.Core.Locations;
using StarBridge.Core.Parsing;
using System.IO;
using System.Net.Http.Json;
using System.Windows;
using System.Windows.Media;
using System.Windows.Threading;
using Brushes = System.Windows.Media.Brushes;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private readonly LocationDataContributionRecorder _locationDataContributionRecorder = new();
    private readonly DispatcherTimer _locationDataContributionSyncTimer = new()
    {
        Interval = TimeSpan.FromMinutes(1)
    };
    private bool _isApplyingLocationDataContributionConsent;
    private bool _locationDataConsentDialogIsInitial;
    private bool _isLocationDataContributionSyncing;
    private bool _isLocationHistoryScanRunning;
    private string? _locationHistoryScannedPath;
    private string? _locationDataContributionSyncError;

    private void InitializeLocationDataContribution()
    {
        _locationDataContributionSyncTimer.Tick += async (_, _) =>
            await SyncLocationDataContributionsAsync();
        _locationDataContributionSyncTimer.Start();
        RefreshLocationDataContributionPresentation();
    }

    private void ObserveLocationDataContribution(FleetEvent fleetEvent)
    {
        if (!_locationDataContributionRecorder.Observe(fleetEvent, DateTimeOffset.UtcNow))
        {
            return;
        }

        RefreshLocationDataContributionPresentation();
        _ = SyncLocationDataContributionsAsync();
    }

    private void ShowLocationDataContributionConsentIfNeeded()
    {
        if (!CanShowPostOnboardingConsentPrompts() ||
            LocationDataConsentOverlay.Visibility == Visibility.Visible ||
            GameplayDataConsentOverlay.Visibility == Visibility.Visible)
        {
            return;
        }

        var consent = _locationDataContributionRecorder.Consent;
        if (consent.Version >= LocationDataContributionRecorder.CurrentConsentVersion &&
            consent.State != LocationDataContributionConsentState.Unknown)
        {
            if (_locationDataContributionRecorder.IsAllowed)
            {
                StartLocationHistoryScanIfAllowed();
            }

            return;
        }

        ShowLocationDataContributionConsentDialog(isInitial: true);
    }

    private void ShowLocationDataContributionConsentDialog(bool isInitial)
    {
        _locationDataConsentDialogIsInitial = isInitial;
        var allowed = _locationDataContributionRecorder.IsAllowed;
        LocationDataConsentDeclineButton.Content = allowed ? "停止贡献" : "暂不参与";
        LocationDataConsentAllowButton.Content = allowed ? "继续贡献" : "同意并开始采集";
        LocationDataConsentOverlay.Visibility = Visibility.Visible;
        LocationDataConsentAllowButton.Focus();
    }

    private void LocationDataConsentAllowButton_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            _locationDataContributionRecorder.SetConsent(
                LocationDataContributionConsentState.Allowed,
                DateTimeOffset.UtcNow);
            LocationDataConsentOverlay.Visibility = Visibility.Collapsed;
            _locationDataContributionSyncError = null;
            RefreshLocationDataContributionPresentation();
            StartLocationHistoryScanIfAllowed();
            _ = SyncLocationDataContributionsAsync();
        }
        catch (Exception ex)
        {
            LocationDataContributionStatusText.Text = UserFacingError.Describe(ex, "地点数据许可未保存，请稍后重试。");
            LocationDataContributionStatusText.Foreground = FindBrush("StatusDangerBrush", Brushes.IndianRed);
        }
    }

    private void LocationDataConsentDeclineButton_Click(object sender, RoutedEventArgs e)
    {
        try
        {
            _locationDataContributionRecorder.SetConsent(
                LocationDataContributionConsentState.Declined,
                DateTimeOffset.UtcNow);
            LocationDataConsentOverlay.Visibility = Visibility.Collapsed;
            _locationDataContributionSyncError = null;
            RefreshLocationDataContributionPresentation();
        }
        catch (Exception ex)
        {
            LocationDataContributionStatusText.Text = UserFacingError.Describe(ex, "地点数据设置未保存，请稍后重试。");
            LocationDataContributionStatusText.Foreground = FindBrush("StatusDangerBrush", Brushes.IndianRed);
        }
    }

    private void LocationDataConsentCloseButton_Click(object sender, RoutedEventArgs e)
    {
        if (_locationDataConsentDialogIsInitial)
        {
            LocationDataConsentDeclineButton_Click(sender, e);
            return;
        }

        LocationDataConsentOverlay.Visibility = Visibility.Collapsed;
        RefreshLocationDataContributionPresentation();
    }

    private void LocationDataContributionExplainButton_Click(object sender, RoutedEventArgs e)
    {
        ShowLocationDataContributionConsentDialog(isInitial: false);
    }

    private void LocationDataContributionConsentCheck_Changed(object sender, RoutedEventArgs e)
    {
        if (_isLoadingSettings || _isApplyingLocationDataContributionConsent)
        {
            return;
        }

        if (LocationDataContributionConsentCheck.IsChecked == true)
        {
            if (!_locationDataContributionRecorder.IsAllowed)
            {
                _isApplyingLocationDataContributionConsent = true;
                LocationDataContributionConsentCheck.IsChecked = false;
                _isApplyingLocationDataContributionConsent = false;
                ShowLocationDataContributionConsentDialog(isInitial: false);
            }

            return;
        }

        if (_locationDataContributionRecorder.IsAllowed)
        {
            try
            {
                _locationDataContributionRecorder.SetConsent(
                    LocationDataContributionConsentState.Declined,
                    DateTimeOffset.UtcNow);
                _locationDataContributionSyncError = null;
            }
            catch (Exception ex)
            {
                _locationDataContributionSyncError = UserFacingError.Describe(ex, "地点数据暂时无法同步，应用稍后会自动重试。");
            }
        }

        RefreshLocationDataContributionPresentation();
    }

    private void RefreshLocationDataContributionPresentation()
    {
        if (LocationDataContributionConsentCheck is null)
        {
            return;
        }

        _isApplyingLocationDataContributionConsent = true;
        try
        {
            LocationDataContributionConsentCheck.IsChecked = _locationDataContributionRecorder.IsAllowed;
        }
        finally
        {
            _isApplyingLocationDataContributionConsent = false;
        }

        var consent = _locationDataContributionRecorder.Consent;
        var pending = _locationDataContributionRecorder.PendingCount;
        LocationDataContributionStatusText.Text = (_locationDataContributionRecorder.LastWriteError, _locationDataContributionSyncError, consent.State) switch
        {
            (not null, _, _) => "本地保存失败，请检查配置目录权限",
            (_, not null, LocationDataContributionConsentState.Allowed) when pending > 0 => $"已参与 · {pending} 项将在联网后自动提交",
            (_, _, LocationDataContributionConsentState.Allowed) when pending > 0 => $"已参与 · {pending} 项等待匿名提交",
            (_, _, LocationDataContributionConsentState.Allowed) => "已参与 · 等待新的地点代码",
            (_, _, LocationDataContributionConsentState.Declined) => "未参与 · 不会采集或提交地点代码",
            _ => "尚未选择是否参与"
        };
        LocationDataContributionStatusText.Foreground = (_locationDataContributionRecorder.LastWriteError, consent.State) switch
        {
            (not null, _) => FindBrush("StatusDangerBrush", Brushes.IndianRed),
            (_, LocationDataContributionConsentState.Allowed) => FindBrush("StatusSuccessBrush", Brushes.SpringGreen),
            (_, LocationDataContributionConsentState.Declined) => FindBrush("StatusDisabledBrush", Brushes.LightSlateGray),
            _ => FindBrush("StatusWarningBrush", Brushes.Orange)
        };
        LocationDataContributionSummaryText.Text = consent.State == LocationDataContributionConsentState.Allowed
            ? "只处理地点代码与匿名候选关系；正式名称仍需重复证据和人工审核。"
            : "参与后会扫描现有 Game.log，并继续处理新出现的地点事件。";
        RefreshLocalDataManagementPresentation();
    }

    private void StartLocationHistoryScanIfAllowed()
    {
        if (!_locationDataContributionRecorder.IsAllowed ||
            _isLocationHistoryScanRunning ||
            string.IsNullOrWhiteSpace(_logPath) ||
            !File.Exists(_logPath))
        {
            return;
        }

        var path = Path.GetFullPath(_logPath);
        if (string.Equals(path, _locationHistoryScannedPath, StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        _isLocationHistoryScanRunning = true;
        _ = ScanLocationHistoryAsync(path);
    }

    private async Task ScanLocationHistoryAsync(string path)
    {
        try
        {
            var events = await Task.Run(() => ReadLocationEvents(path));
            if (!_locationDataContributionRecorder.IsAllowed)
            {
                return;
            }

            foreach (var fleetEvent in events)
            {
                _locationDataContributionRecorder.Observe(fleetEvent, DateTimeOffset.UtcNow);
            }

            _locationHistoryScannedPath = path;
            _locationDataContributionSyncError = null;
            RefreshLocationDataContributionPresentation();
            await SyncLocationDataContributionsAsync();
        }
        catch (Exception ex)
        {
            _locationDataContributionSyncError = UserFacingError.Describe(ex, "历史日志扫描未完成，请检查日志文件后重试。");
            RefreshLocationDataContributionPresentation();
        }
        finally
        {
            _isLocationHistoryScanRunning = false;
        }
    }

    private static FleetEvent[] ReadLocationEvents(string path)
    {
        var parser = new RegexLogEventParser();
        var events = new List<FleetEvent>();
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        using var reader = new StreamReader(stream);
        while (reader.ReadLine() is { } line)
        {
            var fleetEvent = parser.TryParse(line);
            if (fleetEvent?.Type is FleetEventType.PlayerLocationChanged or FleetEventType.PlayerNavigationTargetChanged)
            {
                events.Add(fleetEvent);
            }
        }

        return events.ToArray();
    }

    private async Task SyncLocationDataContributionsAsync()
    {
        if (_isLocationDataContributionSyncing ||
            !_locationDataContributionRecorder.IsAllowed ||
            !CanSynchronizeUserData ||
            _syncPrivacySettings.PresenceVisibilityMode != StarBridge.Core.Presence.PlayerPresenceVisibilityMode.Online)
        {
            return;
        }

        var batch = _locationDataContributionRecorder.CreateBatch(_appStatsClientId);
        if (batch is null)
        {
            return;
        }

        _isLocationDataContributionSyncing = true;
        try
        {
            using var response = await _relayClient.PostJsonAsync("api/location-data/contributions", batch);
            if (!response.IsSuccessStatusCode)
            {
                _locationDataContributionSyncError = "地点数据尚未提交，应用稍后会自动重试。";
                return;
            }

            _ = await response.Content.ReadFromJsonAsync<LocationDataContributionResponseContract>();
            _locationDataContributionRecorder.Acknowledge(batch);
            _locationDataContributionSyncError = null;
        }
        catch (Exception ex)
        {
            _locationDataContributionSyncError = UserFacingError.Describe(ex, "地点数据暂时无法同步，应用稍后会自动重试。");
        }
        finally
        {
            _isLocationDataContributionSyncing = false;
            RefreshLocationDataContributionPresentation();
        }
    }
}
