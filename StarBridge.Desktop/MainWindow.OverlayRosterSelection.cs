namespace StarBridge.Desktop;

public partial class MainWindow
{
    private readonly System.Collections.ObjectModel.ObservableCollection<OverlayRosterPreferenceRow>
        _overlayRosterPreferenceRows = [];
    private readonly HashSet<string> _overlayRosterAuthorizedIdentityKeys =
        new(StringComparer.OrdinalIgnoreCase);
    private readonly OverlayRosterSelectionSettingsCache _overlayRosterSelectionSettingsCache = new();
    private OverlayRosterSelectionEditLease? _overlayRosterSelectionEditLease;
    private OverlayRosterSelectionSettings _overlayRosterSelectionEditSettings =
        OverlayRosterSelectionSettings.Default;

    private static HashSet<string> BuildOverlayRosterAuthorizedIdentityKeys(
        IEnumerable<NetworkPlayerSnapshot> snapshots) =>
        snapshots
            .Select(GetNetworkSnapshotKey)
            .Where(key => !string.IsNullOrWhiteSpace(key))
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

    private void ReplaceOverlayRosterAuthorizedIdentityKeys(IEnumerable<string> identityKeys)
    {
        _overlayRosterAuthorizedIdentityKeys.Clear();
        _overlayRosterAuthorizedIdentityKeys.UnionWith(
            identityKeys.Where(key => !string.IsNullOrWhiteSpace(key)));
    }

    private void ClearOverlayRosterAuthorizedIdentityKeys() =>
        _overlayRosterAuthorizedIdentityKeys.Clear();

    private OverlayRosterSelectionSettings GetOverlayRosterSelectionSettings()
        => _overlayRosterSelectionSettingsCache.Load(
            _accountId,
            OverlayRosterSelectionSettingsStore.Load);

    private void SaveOverlayRosterSelectionSettings(OverlayRosterSelectionSettings settings)
    {
        _overlayRosterSelectionSettingsCache.Save(
            _accountId,
            settings,
            OverlayRosterSelectionSettingsStore.Save);
        RefreshOverlayWindow();
    }

    private void OverlayRosterSelectionOpenButton_Click(
        object sender,
        System.Windows.RoutedEventArgs e)
    {
        var settings = GetOverlayRosterSelectionSettings();
        _overlayRosterSelectionEditLease = OverlayRosterSelectionEditLease.Capture(
            _accountSessionCoordinator,
            _accountId);
        _overlayRosterSelectionEditSettings = settings;
        var authorizedRoster = ResolveOverlayAuthorizedRoster(ResolveCurrentOverlayScene());
        _overlayRosterPreferenceRows.Clear();
        foreach (var row in OverlayRosterPreferencePolicy.ProjectRows(authorizedRoster, settings))
        {
            _overlayRosterPreferenceRows.Add(row);
        }

        OverlayRosterSelectionList.ItemsSource = _overlayRosterPreferenceRows;
        OverlayRosterIncludeOfflineCheck.IsChecked = settings.IncludeOfflineMembers;
        SetComboBoxSelectedTag(OverlayRosterOverflowModeBox, settings.OverflowMode.ToString());
        SetComboBoxSelectedTag(
            OverlayRosterRowLimitBox,
            settings.UserRowLimit.ToString(System.Globalization.CultureInfo.InvariantCulture));
        SetComboBoxSelectedTag(
            OverlayRosterRotationIntervalBox,
            settings.RotationIntervalSeconds.ToString(System.Globalization.CultureInfo.InvariantCulture));
        RefreshOverlayRosterSelectionPresentation();
        OverlayRosterSelectionOverlay.Show();
    }

    private void OverlayRosterPreferenceCheck_Changed(
        object sender,
        System.Windows.RoutedEventArgs e) =>
        RefreshOverlayRosterSelectionPresentation();

    private void OverlayRosterOverflowModeBox_SelectionChanged(
        object sender,
        System.Windows.Controls.SelectionChangedEventArgs e) =>
        RefreshOverlayRosterSelectionPresentation();

    private void OverlayRosterSelectionSaveButton_Click(
        object sender,
        System.Windows.RoutedEventArgs e)
    {
        if (_overlayRosterSelectionEditLease is not { } editLease ||
            !editLease.IsCurrent(_accountSessionCoordinator, _accountId))
        {
            ResetOverlayRosterSelectionAccountSession();
            StarBridgeMessageBox.Show(
                this,
                "账号已切换，旧账号的浮层成员选择未保存。请重新打开后再设置。",
                "设置已关闭",
                System.Windows.MessageBoxButton.OK,
                System.Windows.MessageBoxImage.Information);
            return;
        }

        var overflowMode = Enum.TryParse<OverlayRosterOverflowMode>(
            GetSelectedComboBoxTag(OverlayRosterOverflowModeBox),
            ignoreCase: true,
            out var parsedMode)
            ? parsedMode
            : OverlayRosterOverflowMode.Summary;
        var rowLimit = int.TryParse(
            GetSelectedComboBoxTag(OverlayRosterRowLimitBox),
            System.Globalization.NumberStyles.Integer,
            System.Globalization.CultureInfo.InvariantCulture,
            out var parsedRowLimit)
            ? parsedRowLimit
            : 0;
        var rotationSeconds = int.TryParse(
            GetSelectedComboBoxTag(OverlayRosterRotationIntervalBox),
            System.Globalization.NumberStyles.Integer,
            System.Globalization.CultureInfo.InvariantCulture,
            out var parsedRotationSeconds)
            ? parsedRotationSeconds
            : 10;
        var mergedPreferences = OverlayRosterPreferencePolicy.MergeVisibleRows(
            _overlayRosterSelectionEditSettings,
            _overlayRosterPreferenceRows);
        var settings = mergedPreferences with
        {
            IncludeOfflineMembers = OverlayRosterIncludeOfflineCheck.IsChecked == true,
            OverflowMode = overflowMode,
            UserRowLimit = rowLimit,
            RotationIntervalSeconds = rotationSeconds
        };
        try
        {
            SaveOverlayRosterSelectionSettings(settings);
            ResetOverlayRosterSelectionAccountSession();
        }
        catch (Exception ex)
        {
            StarBridgeMessageBox.Show(
                this,
                UserFacingError.Describe(ex, "浮层选人设置未保存，请稍后重试。"),
                "保存失败",
                System.Windows.MessageBoxButton.OK,
                System.Windows.MessageBoxImage.Error);
        }
    }

    private void OverlayRosterSelectionCancelButton_Click(
        object sender,
        System.Windows.RoutedEventArgs e) =>
        ResetOverlayRosterSelectionAccountSession();

    private void ResetOverlayRosterSelectionAccountSession()
    {
        _overlayRosterSelectionEditLease = null;
        _overlayRosterSelectionEditSettings = OverlayRosterSelectionSettings.Default;
        _overlayRosterPreferenceRows.Clear();
        OverlayRosterSelectionOverlay?.Hide();
    }

    private void RefreshOverlayRosterSelectionPresentation()
    {
        if (OverlayRosterSelectionCountText is null ||
            OverlayRosterRotationIntervalRow is null ||
            OverlayRosterOverflowModeBox is null)
        {
            return;
        }

        var summary = OverlayRosterPreferencePolicy.Summarize(
            _overlayRosterSelectionEditSettings,
            _overlayRosterPreferenceRows);
        OverlayRosterSelectionCountText.Text = summary.UnrepresentedCount == 0
            ? $"钉住 {summary.TotalPinned} · 排除 {summary.TotalExcluded}"
            : $"钉住 {summary.TotalPinned} · 排除 {summary.TotalExcluded} · " +
              $"当前列表外 {summary.UnrepresentedPinned} 钉住 / {summary.UnrepresentedExcluded} 排除";
        OverlayRosterRotationIntervalRow.Visibility =
            GetSelectedComboBoxTag(OverlayRosterOverflowModeBox)
                ?.Equals(nameof(OverlayRosterOverflowMode.Rotate), StringComparison.OrdinalIgnoreCase) == true
                ? System.Windows.Visibility.Visible
                : System.Windows.Visibility.Collapsed;
    }

    private OverlayAuthorizedRoster ResolveOverlayAuthorizedRoster(OverlaySceneSnapshot scene) =>
        ResolveOverlayAuthorizedRoster(scene, _overlayRosterAuthorizedIdentityKeys);

    internal static OverlayAuthorizedRoster ResolveOverlayAuthorizedRoster(
        OverlaySceneSnapshot scene,
        IReadOnlySet<string> fleetAuthorizedIdentityKeys)
    {
        ArgumentNullException.ThrowIfNull(scene);
        ArgumentNullException.ThrowIfNull(fleetAuthorizedIdentityKeys);

        if (scene.Context.Kind == OverlaySceneKind.PartyRoom)
        {
            // The room scene was constructed from the room response itself, so its
            // returned member collection is already the authorized closed set.
            return new OverlayAuthorizedRoster(scene.Players);
        }

        var members = scene.Players
            .Where(player =>
                // Self is locally owned state. Retaining it before the first relay
                // pull cannot reveal another account's data and keeps local status
                // tools useful while every remote member still fails closed.
                player.IsSelf ||
                fleetAuthorizedIdentityKeys.Contains(
                    GetNetworkSnapshotKey(player.AccountId, player.Name)))
            .ToArray();
        return new OverlayAuthorizedRoster(members);
    }
}
