using StarBridge.Core.Presence;
using StarBridge.Core.Profiles;
using System.Globalization;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;

namespace StarBridge.Desktop;

public partial class MainWindow
{
    private void CallsignBox_TextChanged(object sender, TextChangedEventArgs e)
    {
        if (_isLoadingSettings)
        {
            return;
        }

        if (!IsLoggedIn)
        {
            return;
        }

        var limited = LimitCallsign(CallsignBox.Text);
        if (!CallsignBox.Text.Equals(limited, StringComparison.Ordinal))
        {
            var caret = Math.Min(CallsignBox.CaretIndex, limited.Length);
            CallsignBox.Text = limited;
            CallsignBox.CaretIndex = caret;
            return;
        }

        _callsign = string.IsNullOrWhiteSpace(limited)
            ? null
            : limited.Trim();
        SaveCurrentConfig();
        RenderState();
        StartProfileSyncDebounce();
    }

    private void PersonalDisplayNameEditButton_Click(object sender, RoutedEventArgs e)
    {
        BeginPersonalDisplayNameEdit();
    }

    private void PersonalDisplayNameEditBox_KeyDown(object sender, System.Windows.Input.KeyEventArgs e)
    {
        if (e.Key == Key.Enter)
        {
            CommitPersonalDisplayNameEdit();
            e.Handled = true;
            return;
        }

        if (e.Key == Key.Escape)
        {
            CancelPersonalDisplayNameEdit();
            e.Handled = true;
        }
    }

    private void PersonalDisplayNameEditBox_LostFocus(object sender, RoutedEventArgs e)
    {
        if (_isClosingPersonalDisplayNameEditor ||
            PersonalDisplayNameEditBox.Visibility != Visibility.Visible)
        {
            return;
        }

        CommitPersonalDisplayNameEdit();
    }

    private void BeginPersonalDisplayNameEdit()
    {
        _isClosingPersonalDisplayNameEditor = false;
        PersonalDisplayNameEditBox.Text = _callsign ?? GetPersonalDisplayName();
        PersonalDisplayNameReadText.Visibility = Visibility.Collapsed;
        PersonalDisplayNameEditButton.Visibility = Visibility.Collapsed;
        PersonalDisplayNameEditBox.Visibility = Visibility.Visible;
        PersonalDisplayNameEditBox.Focus();
        PersonalDisplayNameEditBox.SelectAll();
    }

    private void CommitPersonalDisplayNameEdit()
    {
        var limited = LimitCallsign(PersonalDisplayNameEditBox.Text);
        var normalized = string.IsNullOrWhiteSpace(limited)
            ? null
            : limited.Trim();

        _callsign = normalized;
        var wasLoadingSettings = _isLoadingSettings;
        _isLoadingSettings = true;
        try
        {
            CallsignBox.Text = normalized ?? "";
        }
        finally
        {
            _isLoadingSettings = wasLoadingSettings;
        }

        EndPersonalDisplayNameEdit();
        SaveCurrentConfig();
        RefreshAccountPanel();
        RenderState();
        // Display-name changes use the existing profile synchronization path.
        StartProfileSyncDebounce();
    }

    private void CancelPersonalDisplayNameEdit()
    {
        EndPersonalDisplayNameEdit();
    }

    private void EndPersonalDisplayNameEdit()
    {
        _isClosingPersonalDisplayNameEditor = true;
        PersonalDisplayNameEditBox.Visibility = Visibility.Collapsed;
        PersonalDisplayNameReadText.Visibility = Visibility.Visible;
        PersonalDisplayNameEditButton.Visibility = Visibility.Visible;
        PersonalDisplayNameEditButton.Focus();
        Dispatcher.BeginInvoke(new Action(() => _isClosingPersonalDisplayNameEditor = false), DispatcherPriority.Background);
    }

    private void StartProfileSyncDebounce()
    {
        if (!IsLoggedIn)
        {
            return;
        }

        _profileSyncDebounceTimer.Stop();
        _profileSyncDebounceTimer.Start();
    }

    private async Task FlushProfileSyncDebouncedAsync()
    {
        if (!IsLoggedIn)
        {
            return;
        }

        await UpdateProfileAsync();
        if (_syncPrivacySettings.SyncConsentCompleted &&
            _syncPrivacySettings.SyncConsentVersion >= CurrentSyncConsentVersion &&
            HasAnyGameStateSyncEnabled())
        {
            await PushLocalSnapshotAsync(silent: true, pushFleetDirectory: false);
        }
    }

    private void EmailNotificationsCheck_Changed(object sender, RoutedEventArgs e)
    {
        if (_isLoadingSettings || _isRefreshingAccountPanel)
        {
            return;
        }

        if (FleetActionFeatureSettingsLocked)
        {
            _allowEmailNotifications = false;
            EmailNotificationsCheck.IsChecked = false;
            RefreshPersonalRightEmailReminderStatus();
            return;
        }

        _allowEmailNotifications = EmailNotificationsCheck.IsChecked == true;
        SaveCurrentConfig();
        if (IsLoggedIn)
        {
            _ = UpdateProfileAsync();
        }

        UpdateSyncPrivacySummary();
        RefreshPersonalRightEmailReminderStatus();
    }

    private static SyncPrivacySettings ApplyFleetActionSettingsLock(SyncPrivacySettings settings)
    {
        if (!FleetActionFeatureSettingsLocked)
        {
            return settings;
        }

        return settings with
        {
            TaskOnlineStatusVisible = false,
            TaskShipStatusVisible = false,
            TaskLocationStatusVisible = false,
            CommandReadinessSummaryVisible = false
        };
    }

    private static NotificationSettings ApplyFleetActionSettingsLock(NotificationSettings settings)
    {
        if (!FleetActionFeatureSettingsLocked)
        {
            return settings;
        }

        return settings with
        {
            EnableEmailNotifications = false,
            NotifyFleetOrders = false,
            NotifyMissionUpdates = false,
            NotifyRallyPointUpdates = false,
            ActionPlanReminderMinutes = 0,
            NotifyUrgentOrders = false,
            NotifySquadOrders = false,
            EmailHourlyLimit = 0,
            EmailOnlyCritical = false
        };
    }

    private void ApplySyncPrivacySettingsToControls()
    {
        if (SyncPrivacyOnlineStatusCheck is null)
        {
            return;
        }

        _isApplyingSyncPrivacyControls = true;
        try
        {
            _syncPrivacySettings = ApplyFleetActionSettingsLock(_syncPrivacySettings);
            SyncPrivacyMasterCheck.IsChecked = _syncPrivacySettings.SyncEnabled;
            SyncPrivacyOnlineStatusCheck.IsChecked = _syncPrivacySettings.SyncOnlineStatus;
            SyncPrivacyShipStatusCheck.IsChecked = _syncPrivacySettings.SyncShipStatus;
            SyncPrivacyLocationStatusCheck.IsChecked = _syncPrivacySettings.SyncLocationStatus;
            SyncPrivacyServerInfoCheck.IsChecked = _syncPrivacySettings.SyncServerInfo;
            ApplySyncPrivacyVisibilityScope(_syncPrivacySettings.EffectiveVisibilityScope);
            SyncPrivacyPersonalHangarVisibleCheck.IsChecked = _syncPrivacySettings.PersonalHangarVisible;
            SyncPrivacyTaskOnlineStatusCheck.IsChecked = _syncPrivacySettings.TaskOnlineStatusVisible;
            SyncPrivacyTaskShipStatusCheck.IsChecked = _syncPrivacySettings.TaskShipStatusVisible;
            SyncPrivacyTaskLocationStatusCheck.IsChecked = _syncPrivacySettings.TaskLocationStatusVisible;
            SyncPrivacyCommandReadinessCheck.IsChecked = _syncPrivacySettings.CommandReadinessSummaryVisible;
            SyncPrivacyHideLowConfidenceLocationCheck.IsChecked = _syncPrivacySettings.HideLowConfidenceLocation;
            SyncPrivacyFriendsPresenceCheck.IsChecked = _syncPrivacySettings.FriendsCanViewPresence;
            ApplyDualAxisPrivacySettingsToEditor();
            UpdateSyncPrivacyOptionsEnabledState();
        }
        finally
        {
            _isApplyingSyncPrivacyControls = false;
        }

        UpdateSyncPrivacySummary();
    }

    private async void SyncPrivacyMasterCheck_Changed(object sender, RoutedEventArgs e)
    {
        if (_isLoadingSettings || _isApplyingSyncPrivacyControls)
        {
            return;
        }

        var enabled = SyncPrivacyMasterCheck.IsChecked == true;
        if (DualAxisPrivacyEditor is not null)
        {
            _dualAxisPrivacySettings = (_dualAxisPrivacySettings with
            {
                PublicationEnabled = enabled
            }).Normalize();
            await CommitDualAxisPrivacyEditorAsync();
            return;
        }

        _syncPrivacySettings = _syncPrivacySettings with
        {
            SyncEnabled = enabled,
            SyncConsentCompleted = true,
            SyncConsentVersion = CurrentSyncConsentVersion
        };
        SaveSyncPrivacySettingsAndRefreshDualAxis();
        ApplyNetworkSyncMasterState();
        UpdateSyncPrivacyOptionsEnabledState();
        UpdateSyncPrivacySummary();
        UpdateShipDatabaseSummary();

        if (!enabled)
        {
            ReplaceRemoteFleetShipsForOwner(_localPlayer, _callsign, [], refresh: false);
            RefreshFleetShipInventory();
        }

        if (IsLoggedIn)
        {
            await PushLocalSnapshotAsync(
                silent: true,
                pushFleetDirectory: false,
                forcePrivacyClear: !enabled);
        }
    }

    private void UpdateSyncPrivacyOptionsEnabledState()
    {
        if (SyncPrivacyOptionsHost is null)
        {
            return;
        }

        var enabled = _syncPrivacySettings.SyncEnabled;
        SyncPrivacyOptionsHost.IsEnabled = enabled;
        SyncPrivacyOptionsHost.Opacity = enabled ? 1 : 0.48;
        DualAxisPrivacyEditor.IsEnabled = enabled;
        DualAxisPrivacyEditor.Opacity = enabled ? 1 : 0.48;
        SyncPrivacyTaskOnlineStatusCheck.IsEnabled = enabled && !FleetActionFeatureSettingsLocked;
        SyncPrivacyTaskShipStatusCheck.IsEnabled = enabled && !FleetActionFeatureSettingsLocked;
        SyncPrivacyTaskLocationStatusCheck.IsEnabled = enabled && !FleetActionFeatureSettingsLocked;
        SyncPrivacyCommandReadinessCheck.IsEnabled = enabled && !FleetActionFeatureSettingsLocked;
        RefreshPlayerEventSharingPresentation();
    }

    private void ApplyPlayerEventSharingSettingsToControls()
    {
        if (PlayerEventSharingMasterCheck is null)
        {
            return;
        }

        _isApplyingPlayerEventSharingControls = true;
        try
        {
            _playerEventSharingSettings = _playerEventSharingSettings.Normalize();
            PlayerEventSharingMasterCheck.IsChecked = _playerEventSharingSettings.Enabled;
            PlayerEventSharingPresenceCheck.IsChecked = _playerEventSharingSettings.EventTypes.HasFlag(PlayerSharedEventTypes.Presence);
            PlayerEventSharingServerCheck.IsChecked = _playerEventSharingSettings.EventTypes.HasFlag(PlayerSharedEventTypes.Server);
            PlayerEventSharingShipCheck.IsChecked = _playerEventSharingSettings.EventTypes.HasFlag(PlayerSharedEventTypes.Ship);
            PlayerEventSharingLocationCheck.IsChecked = _playerEventSharingSettings.EventTypes.HasFlag(PlayerSharedEventTypes.Location);
            PlayerEventSharingLifeCheck.IsChecked = _playerEventSharingSettings.EventTypes.HasFlag(PlayerSharedEventTypes.Life);
        }
        finally
        {
            _isApplyingPlayerEventSharingControls = false;
        }

        RefreshPlayerEventSharingPresentation();
    }

    private void PlayerEventSharingMasterCheck_Changed(object sender, RoutedEventArgs e) =>
        SavePlayerEventSharingSettingsFromControls();

    private void PlayerEventSharingSettingCheck_Changed(object sender, RoutedEventArgs e) =>
        SavePlayerEventSharingSettingsFromControls();

    private void SavePlayerEventSharingSettingsFromControls()
    {
        if (_isLoadingSettings || _isApplyingPlayerEventSharingControls)
        {
            return;
        }

        var eventTypes = PlayerSharedEventTypes.None;
        if (PlayerEventSharingPresenceCheck.IsChecked == true)
        {
            eventTypes |= PlayerSharedEventTypes.Presence;
        }
        if (PlayerEventSharingServerCheck.IsChecked == true)
        {
            eventTypes |= PlayerSharedEventTypes.Server;
        }
        if (PlayerEventSharingShipCheck.IsChecked == true)
        {
            eventTypes |= PlayerSharedEventTypes.Ship;
        }
        if (PlayerEventSharingLocationCheck.IsChecked == true)
        {
            eventTypes |= PlayerSharedEventTypes.Location;
        }
        if (PlayerEventSharingLifeCheck.IsChecked == true)
        {
            eventTypes |= PlayerSharedEventTypes.Life;
        }

        _playerEventSharingSettings = new PlayerEventSharingSettings(
            PlayerEventSharingMasterCheck.IsChecked == true,
            eventTypes).Normalize();
        if (!_playerEventSharingSettings.Allows(PlayerSharedEventTypes.Life))
        {
            _sharedLifeEvents.Clear();
        }

        SavePlayerEventSharingSettingsAndRefreshDualAxis();
        RefreshPlayerEventSharingPresentation();
        UpdateSyncPrivacySummary();
        NetworkStatusText.Text = "事件共享设置已保存";
        QueueRealtimeNetworkSnapshotPush();
    }

    private void RefreshPlayerEventSharingPresentation()
    {
        if (PlayerEventSharingOptionsPanel is null || PlayerEventSharingStatusText is null)
        {
            return;
        }

        var enabled = _syncPrivacySettings.SyncEnabled && _playerEventSharingSettings.Enabled;
        PlayerEventSharingOptionsPanel.IsEnabled = enabled;
        PlayerEventSharingOptionsPanel.Opacity = enabled ? 1 : 0.48;
        var enabledCount = Enum.GetValues<PlayerSharedEventTypes>()
            .Count(value => value is not (PlayerSharedEventTypes.None or PlayerSharedEventTypes.All) &&
                            _playerEventSharingSettings.Allows(value));
        PlayerEventSharingStatusText.Text = !_syncPrivacySettings.SyncEnabled
            ? "同步信息已关闭，不会发送事件"
            : !_playerEventSharingSettings.Enabled
                ? "事件共享已暂停"
                : $"正在共享 {enabledCount} 类事件";
        PlayerEventSharingStatusText.Foreground = enabled
            ? (System.Windows.Media.Brush)FindResource("StatusSuccessBrush")
            : (System.Windows.Media.Brush)FindResource("MutedTextBrush");
    }

    private void SyncPrivacySettingCheck_Changed(object sender, RoutedEventArgs e)
    {
        if (_isLoadingSettings || _isApplyingSyncPrivacyControls)
        {
            return;
        }

        var previousPersonalHangarVisible = _syncPrivacySettings.PersonalHangarVisible;
        var previousFriendsCanViewPresence = _syncPrivacySettings.FriendsCanViewPresence;
        var visibilityScope = GetSelectedSyncPrivacyVisibilityScope();
        _syncPrivacySettings = ApplyFleetActionSettingsLock((_syncPrivacySettings with
        {
            SyncOnlineStatus = IsSwitchOn(SyncPrivacyOnlineStatusCheck),
            SyncShipStatus = IsSwitchOn(SyncPrivacyShipStatusCheck),
            SyncLocationStatus = IsSwitchOn(SyncPrivacyLocationStatusCheck),
            SyncServerInfo = IsSwitchOn(SyncPrivacyServerInfoCheck),
            SyncOnlyInGame = true,
            VisibilityScope = visibilityScope,
            PersonalHangarVisible = IsSwitchOn(SyncPrivacyPersonalHangarVisibleCheck),
            TaskOnlineStatusVisible = IsSwitchOn(SyncPrivacyTaskOnlineStatusCheck),
            TaskShipStatusVisible = IsSwitchOn(SyncPrivacyTaskShipStatusCheck),
            TaskLocationStatusVisible = IsSwitchOn(SyncPrivacyTaskLocationStatusCheck),
            CommandReadinessSummaryVisible = IsSwitchOn(SyncPrivacyCommandReadinessCheck),
            HideStatusBeforeGameStart = true,
            HideServerInfoBeforePu = true,
            StopSyncAfterGameExit = true,
            HideLowConfidenceLocation = IsSwitchOn(SyncPrivacyHideLowConfidenceLocationCheck),
            SyncConsentCompleted = true,
            SyncConsentVersion = CurrentSyncConsentVersion,
            FriendsCanViewPresence = IsSwitchOn(SyncPrivacyFriendsPresenceCheck)
        }).NormalizeVisibilityScope());

        SaveSyncPrivacySettingsAndRefreshDualAxis();
        NetworkStatusText.Text = "同步与隐私设置已保存";
        UpdateShipDatabaseSummary();
        UpdateSyncPrivacySummary();

        var personalHangarVisibilityChanged =
            previousPersonalHangarVisible != _syncPrivacySettings.PersonalHangarVisible;
        var friendPresenceVisibilityChanged =
            previousFriendsCanViewPresence != _syncPrivacySettings.FriendsCanViewPresence;
        if (personalHangarVisibilityChanged)
        {
            ReplaceRemoteFleetShipsForOwner(
                _localPlayer,
                _callsign,
                _syncPrivacySettings.PersonalHangarVisible ? BuildFleetShipSnapshots(includeOwnerAvatarImage: true) : [],
                refresh: false);
            RefreshFleetShipInventory();
        }

        if (IsLoggedIn &&
            (personalHangarVisibilityChanged || friendPresenceVisibilityChanged || _syncPrivacySettings.SyncEnabled))
        {
            _ = PushLocalSnapshotAsync(silent: true, pushFleetDirectory: false);
        }
    }

    private void UpdateSyncPrivacySummary()
    {
        if (SyncPrivacyEnabledSummaryText is null)
        {
            return;
        }

        var projection = BuildPrivacyAudienceProjection();
        var fleetFieldCount = CountStatusFields(projection.FleetStatusFields);
        var roomFieldCount = CountStatusFields(projection.RoomStatusFields);
        SyncPrivacyEnabledSummaryText.Text = $"舰队可见 {fleetFieldCount} 项";
        SyncPrivacyDisabledSummaryText.Text = roomFieldCount > 0
            ? $"同房间可见 {roomFieldCount} 项"
            : "同房间不共享";

        if (SyncPrivacyVisibilitySummaryText is not null)
        {
            SyncPrivacyVisibilitySummaryText.Text = !_dualAxisPrivacySettings.PublicationEnabled
                ? "同步信息已关闭"
                : DualAxisPrivacyPanel.FormatPolicySummary(projection);
            if (SyncPrivacyScopeDescriptionText is not null)
            {
                SyncPrivacyScopeDescriptionText.Text = GetSyncPrivacyVisibilityScopeDescription(
                    _syncPrivacySettings.EffectiveVisibilityScope);
            }
        }

        RefreshSpecifiedVisibilityMembersPresentation();
    }

    private static int CountStatusFields(PlayerSharedStateFields fields) =>
        Enum.GetValues<PlayerSharedStateFields>()
            .Count(field => field is not (
                                PlayerSharedStateFields.None or
                                PlayerSharedStateFields.All or
                                PlayerSharedStateFields.SharedEvents) &&
                            fields.HasFlag(field));

    private void SyncPrivacySpecifiedMembersSelectButton_Click(object sender, RoutedEventArgs e)
    {
        var selectedAccountIds = (_syncPrivacySettings.SpecifiedMemberAccountIds ?? [])
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        _isUpdatingSpecifiedMemberSelection = true;
        try
        {
            _specifiedVisibilityMembers.Clear();
            foreach (var player in _players
                         .Where(player => !player.IsSelf && !string.IsNullOrWhiteSpace(player.AccountId))
                         .GroupBy(player => player.AccountId!, StringComparer.OrdinalIgnoreCase)
                         .Select(group => group.First())
                         .OrderBy(player => DisplayCallsign(player.Callsign, player.Name), StringComparer.OrdinalIgnoreCase))
            {
                _specifiedVisibilityMembers.Add(new SpecifiedVisibilityMemberRow
                {
                    AccountId = player.AccountId!,
                    Callsign = DisplayCallsign(player.Callsign, player.Name),
                    GameId = player.Name,
                    AvatarPath = player.AvatarPath,
                    IsSelected = selectedAccountIds.Contains(player.AccountId!)
                });
            }
        }
        finally
        {
            _isUpdatingSpecifiedMemberSelection = false;
        }

        SpecifiedVisibilityMembersEmptyText.Visibility = _specifiedVisibilityMembers.Count == 0
            ? Visibility.Visible
            : Visibility.Collapsed;
        RefreshSpecifiedVisibilitySelectionText();
        SpecifiedVisibilityMembersOverlay.Show();
    }

    private void SpecifiedVisibilityMemberCheck_Changed(object sender, RoutedEventArgs e)
    {
        if (_isUpdatingSpecifiedMemberSelection)
        {
            return;
        }

        var selectedCount = _specifiedVisibilityMembers.Count(member => member.IsSelected);
        if (selectedCount > PlayerSharedStateVisibility.MaxSpecifiedMembers &&
            sender is System.Windows.Controls.CheckBox { DataContext: SpecifiedVisibilityMemberRow row })
        {
            _isUpdatingSpecifiedMemberSelection = true;
            row.IsSelected = false;
            _isUpdatingSpecifiedMemberSelection = false;
        }

        RefreshSpecifiedVisibilitySelectionText();
    }

    private void SpecifiedVisibilityMembersSaveButton_Click(object sender, RoutedEventArgs e)
    {
        var selected = PlayerSharedStateVisibility.NormalizeSpecifiedMemberAccountIds(
            _specifiedVisibilityMembers
                .Where(member => member.IsSelected)
                .Select(member => member.AccountId));
        _syncPrivacySettings = (_syncPrivacySettings with
        {
            SpecifiedMemberAccountIds = selected
        }).NormalizeVisibilityScope();
        SaveSyncPrivacySettingsAndRefreshDualAxis();
        SpecifiedVisibilityMembersOverlay.Hide();
        RefreshSpecifiedVisibilityMembersPresentation();
        UpdateSyncPrivacySummary();
        QueueRealtimeNetworkSnapshotPush();
    }

    private void SpecifiedVisibilityMembersCancelButton_Click(object sender, RoutedEventArgs e)
    {
        SpecifiedVisibilityMembersOverlay.Hide();
    }

    private void RefreshSpecifiedVisibilitySelectionText()
    {
        var selectedCount = _specifiedVisibilityMembers.Count(member => member.IsSelected);
        SpecifiedVisibilityMembersSelectionText.Text =
            $"已选择 {selectedCount.ToString(CultureInfo.InvariantCulture)} / {PlayerSharedStateVisibility.MaxSpecifiedMembers}";
    }

    private void RefreshSpecifiedVisibilityMembersPresentation()
    {
        if (SyncPrivacySpecifiedMembersRow is null || SyncPrivacySpecifiedMembersCountText is null)
        {
            return;
        }

        var selectedCount = (_syncPrivacySettings.SpecifiedMemberAccountIds ?? []).Length;
        SyncPrivacySpecifiedMembersRow.Visibility =
            _syncPrivacySettings.EffectiveVisibilityScope == SyncPrivacyVisibilityScope.SpecifiedMembers
                ? Visibility.Visible
                : Visibility.Collapsed;
        SyncPrivacySpecifiedMembersCountText.Text =
            $"{selectedCount.ToString(CultureInfo.InvariantCulture)} 名成员";
    }

    private void ManageFleetTabs_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (!ReferenceEquals(e.Source, ManageFleetTabs))
        {
            return;
        }

        UpdateManageSettingsNavSelection();
        RefreshManageSettingsPreview();
    }

    private void ManageSettingsNavButton_Click(object sender, RoutedEventArgs e)
    {
        var targetTab = sender switch
        {
            _ when ReferenceEquals(sender, ManageNavOverviewButton) => ManageFleetOverviewTab,
            _ when ReferenceEquals(sender, ManageNavProfileButton) => ManageFleetProfileTab,
            _ when ReferenceEquals(sender, ManageNavAnnouncementButton) => ManageFleetNoticeTab,
            _ when ReferenceEquals(sender, ManageNavApplicationsButton) => FleetApplicationsTab,
            _ when ReferenceEquals(sender, ManageNavMembersButton) => ManageFleetMembersTab,
            _ when ReferenceEquals(sender, ManageNavNotificationsButton) => ManageFleetNotificationsTab,
            _ when ReferenceEquals(sender, ManageNavShipsButton) => ManageFleetShipsTab,
            _ when ReferenceEquals(sender, ManageNavLogButton) => ManageFleetLogTab,
            _ when ReferenceEquals(sender, ManageNavDangerButton) => ManageFleetDisbandTab,
            _ => null
        };

        OpenManageFleetSection(targetTab);
    }

    private void RefreshManageSettingsNavigation()
    {
        SetManageSettingsNavButtonVisibility(ManageNavOverviewButton, ManageFleetOverviewTab);
        SetManageSettingsNavButtonVisibility(ManageNavProfileButton, ManageFleetProfileTab);
        SetManageSettingsNavButtonVisibility(ManageNavAnnouncementButton, ManageFleetNoticeTab);
        SetManageSettingsNavButtonVisibility(ManageNavApplicationsButton, FleetApplicationsTab);
        SetManageSettingsNavButtonVisibility(ManageNavMembersButton, ManageFleetMembersTab);
        SetManageSettingsNavButtonVisibility(ManageNavNotificationsButton, ManageFleetNotificationsTab);
        SetManageSettingsNavButtonVisibility(ManageNavShipsButton, ManageFleetShipsTab);
        SetManageSettingsNavButtonVisibility(ManageNavLogButton, ManageFleetLogTab);
        SetManageSettingsNavButtonVisibility(ManageNavDangerButton, ManageFleetDisbandTab);
        SetManageSettingsNavButtonVisibility(ManageOverviewProfileButton, ManageFleetProfileTab);
        SetManageSettingsNavButtonVisibility(ManageOverviewNoticeButton, ManageFleetNoticeTab);
        SetManageSettingsNavButtonVisibility(ManageOverviewApplicationsButton, FleetApplicationsTab);
        SetManageSettingsNavButtonVisibility(ManageOverviewMembersButton, ManageFleetMembersTab);
        SetManageSettingsNavButtonVisibility(ManageOverviewVisibilityButton, ManageFleetShipsTab);
        SetManageSettingsNavButtonVisibility(ManageOverviewLogButton, ManageFleetLogTab);
        UpdateManageSettingsNavSelection();
    }

    private static void SetManageSettingsNavButtonVisibility(System.Windows.Controls.Button? button, TabItem? tab)
    {
        if (button is null)
        {
            return;
        }

        button.Visibility = tab?.Visibility == Visibility.Visible
            ? Visibility.Visible
            : Visibility.Collapsed;
    }

    private void UpdateManageSettingsNavSelection()
    {
        if (ManageFleetTabs is null)
        {
            return;
        }

        var activeButton = ManageFleetTabs.SelectedItem switch
        {
            _ when ReferenceEquals(ManageFleetTabs.SelectedItem, ManageFleetOverviewTab) => ManageNavOverviewButton,
            _ when ReferenceEquals(ManageFleetTabs.SelectedItem, ManageFleetProfileTab) => ManageNavProfileButton,
            _ when ReferenceEquals(ManageFleetTabs.SelectedItem, ManageFleetNoticeTab) => ManageNavAnnouncementButton,
            _ when ReferenceEquals(ManageFleetTabs.SelectedItem, FleetApplicationsTab) => ManageNavApplicationsButton,
            _ when ReferenceEquals(ManageFleetTabs.SelectedItem, ManageFleetMembersTab) => ManageNavMembersButton,
            _ when ReferenceEquals(ManageFleetTabs.SelectedItem, ManageFleetNotificationsTab) => ManageNavNotificationsButton,
            _ when ReferenceEquals(ManageFleetTabs.SelectedItem, ManageFleetShipsTab) => ManageNavShipsButton,
            _ when ReferenceEquals(ManageFleetTabs.SelectedItem, ManageFleetLogTab) => ManageNavLogButton,
            _ when ReferenceEquals(ManageFleetTabs.SelectedItem, ManageFleetDisbandTab) => ManageNavDangerButton,
            _ => null
        };

        UiMotion.ApplyNavigationSelection(EnumerateManageSettingsNavButtons(), activeButton);
    }

    private IEnumerable<System.Windows.Controls.Button> EnumerateManageSettingsNavButtons()
    {
        foreach (var button in new[]
                 {
                     ManageNavOverviewButton,
                     ManageNavProfileButton,
                     ManageNavAnnouncementButton,
                     ManageNavApplicationsButton,
                     ManageNavMembersButton,
                     ManageNavNotificationsButton,
                     ManageNavShipsButton,
                     ManageNavLogButton,
                     ManageNavDangerButton
                 })
        {
            if (button is not null)
            {
                yield return button;
            }
        }
    }

    private void ApplySyncPrivacyVisibilityScope(SyncPrivacyVisibilityScope scope)
    {
        if (SyncPrivacyScopePrivateRadio is null)
        {
            return;
        }

        SyncPrivacyScopePrivateRadio.IsChecked = scope == SyncPrivacyVisibilityScope.Private;
        SyncPrivacyScopeAdminRadio.IsChecked = scope == SyncPrivacyVisibilityScope.AdminOnly;
        SyncPrivacyScopeSpecifiedRadio.IsChecked = scope == SyncPrivacyVisibilityScope.SpecifiedMembers;
        SyncPrivacyScopeFleetRadio.IsChecked = scope == SyncPrivacyVisibilityScope.Fleet;
    }

    private SyncPrivacyVisibilityScope GetSelectedSyncPrivacyVisibilityScope()
    {
        if (SyncPrivacyScopePrivateRadio?.IsChecked == true)
        {
            return SyncPrivacyVisibilityScope.Private;
        }

        if (SyncPrivacyScopeAdminRadio?.IsChecked == true)
        {
            return SyncPrivacyVisibilityScope.AdminOnly;
        }

        if (SyncPrivacyScopeSpecifiedRadio?.IsChecked == true)
        {
            return SyncPrivacyVisibilityScope.SpecifiedMembers;
        }

        return SyncPrivacyVisibilityScope.Fleet;
    }

    private static string FormatSyncPrivacyVisibilityScope(SyncPrivacyVisibilityScope scope) =>
        scope switch
        {
            SyncPrivacyVisibilityScope.Private => "仅自己",
            SyncPrivacyVisibilityScope.AdminOnly => "管理员",
            SyncPrivacyVisibilityScope.SpecifiedMembers => "指定成员",
            SyncPrivacyVisibilityScope.Fleet => "全舰队",
            _ => "全舰队"
        };

    private static string FormatNetworkVisibilityScope(SyncPrivacyVisibilityScope scope) =>
        scope switch
        {
            SyncPrivacyVisibilityScope.Private => "Private",
            SyncPrivacyVisibilityScope.AdminOnly => "AdminOnly",
            SyncPrivacyVisibilityScope.SpecifiedMembers => "SpecifiedMembers",
            _ => "Fleet"
        };

    private FleetPresencePrivacyProjection GetLocalFleetPresencePrivacyProjection()
    {
        var hideLiveStatus = (_syncPrivacySettings.SyncOnlyInGame ||
                              _syncPrivacySettings.HideStatusBeforeGameStart ||
                              _syncPrivacySettings.StopSyncAfterGameExit) &&
                             !_isGameProcessRunning;
        var dualAxisWire = DualAxisPrivacyTakeover.ToWire(_dualAxisPrivacySettings);
        if (dualAxisWire.UsesDualAxisWire)
        {
            var hasAudience = dualAxisWire.FleetAdministratorsCanView ||
                              dualAxisWire.FleetMembersCanView ||
                              dualAxisWire.FleetVisibilityGroupIds.Length > 0 ||
                              dualAxisWire.RoomMembersCanView ||
                              dualAxisWire.RoomVisibilityGroupIds.Length > 0;
            var fields = dualAxisWire.FleetFields | dualAxisWire.RoomFields;
            return FleetPresencePrivacyPolicy.Resolve(
                _localPresence,
                _syncPrivacySettings.PresenceVisibilityMode,
                _dualAxisPrivacySettings.PublicationEnabled,
                hasAudience,
                !hideLiveStatus,
                fields.HasFlag(PlayerSharedStateFields.Presence));
        }

        return FleetPresencePrivacyPolicy.Resolve(
            _localPresence,
            _syncPrivacySettings.PresenceVisibilityMode,
            _syncPrivacySettings.SyncEnabled,
            _syncPrivacySettings.EffectiveVisibilityScope != SyncPrivacyVisibilityScope.Private,
            !hideLiveStatus,
            _syncPrivacySettings.SyncOnlineStatus);
    }

    private static string ResolveLocalNetworkLiveStatus(
        bool canPublishSharedState,
        bool publishOnline,
        PlayerPresenceKind presence)
    {
        if (!canPublishSharedState)
        {
            return "Paused";
        }

        return publishOnline
            ? PlayerPresence.ToWireValue(presence)
            : "Offline";
    }

    private static string NormalizeNetworkLiveStatus(string? liveStatus, bool online)
    {
        return PlayerPresence.ToWireValue(PlayerPresence.Normalize(liveStatus, online));
    }

    private static bool IsNetworkLiveStatusPaused(string? liveStatus)
    {
        return NormalizeNetworkLiveStatus(liveStatus, online: false)
            .Equals("Paused", StringComparison.OrdinalIgnoreCase);
    }

    private static string GetSyncPrivacyVisibilityScopeDescription(SyncPrivacyVisibilityScope scope) =>
        scope switch
        {
            SyncPrivacyVisibilityScope.Private => "仅在本机显示，不向舰队共享状态。",
            SyncPrivacyVisibilityScope.AdminOnly => "仅舰队管理者可查看允许共享的状态。",
            SyncPrivacyVisibilityScope.SpecifiedMembers => "仅你选择的舰队成员和管理者可查看允许共享的状态。",
            SyncPrivacyVisibilityScope.Fleet => "全舰队成员可以查看允许共享的状态。",
            _ => "全舰队成员可以查看允许共享的状态。"
        };

    private void ApplyNotificationSettingsToControls()
    {
        if (NotificationInAppCheck is null)
        {
            return;
        }

        _notificationSettings = ApplyFleetActionSettingsLock(_notificationSettings);
        NotificationInAppCheck.IsChecked = _notificationSettings.EnableInAppNotifications;
        NotificationOverlayCheck.IsChecked = _notificationSettings.EnableOverlayNotifications;
        NotificationEmailCheck.IsChecked = _notificationSettings.EnableEmailNotifications;
        NotificationSoundCheck.IsChecked = _notificationSettings.EnableSoundAlerts;
        NotificationDesktopCheck.IsChecked = _notificationSettings.EnableDesktopNotifications;
        NotificationFleetOrdersCheck.IsChecked = _notificationSettings.NotifyFleetOrders;
        NotificationMissionUpdatesCheck.IsChecked = _notificationSettings.NotifyMissionUpdates;
        NotificationRallyPointUpdatesCheck.IsChecked = _notificationSettings.NotifyRallyPointUpdates;
        NotificationUrgentOrdersCheck.IsChecked = _notificationSettings.NotifyUrgentOrders;
        NotificationSquadOrdersCheck.IsChecked = _notificationSettings.NotifySquadOrders;
        NotificationFleetOrdersCheck.IsEnabled = !FleetActionFeatureSettingsLocked;
        NotificationMissionUpdatesCheck.IsEnabled = !FleetActionFeatureSettingsLocked;
        NotificationRallyPointUpdatesCheck.IsEnabled = !FleetActionFeatureSettingsLocked;
        NotificationActionPlanReminderBox.IsEnabled = !FleetActionFeatureSettingsLocked;
        NotificationUrgentOrdersCheck.IsEnabled = !FleetActionFeatureSettingsLocked;
        NotificationSquadOrdersCheck.IsEnabled = !FleetActionFeatureSettingsLocked;
        NotificationEmailCheck.IsEnabled = !FleetActionFeatureSettingsLocked;
        NotificationEmailHourlyLimitBox.IsEnabled = !FleetActionFeatureSettingsLocked;
        NotificationEmailCriticalOnlyCheck.IsEnabled = !FleetActionFeatureSettingsLocked;
        NotificationSquadOnlineCheck.IsChecked = _notificationSettings.NotifySquadMemberOnline;
        NotificationSquadOfflineCheck.IsChecked = _notificationSettings.NotifySquadMemberOffline;
        NotificationMemberAnomalyCheck.IsChecked = _notificationSettings.NotifyMemberAnomalies;
        NotificationApplicationInviteCheck.IsChecked = _notificationSettings.NotifyApplicationsAndInvites;
        NotificationDoNotDisturbCheck.IsChecked = _notificationSettings.DoNotDisturb;
        NotificationReduceInGameCheck.IsChecked = _notificationSettings.ReduceAlertsInGame;
        NotificationEmailCriticalOnlyCheck.IsChecked = _notificationSettings.EmailOnlyCritical;

        SelectComboBoxTag(NotificationActionPlanReminderBox, _notificationSettings.ActionPlanReminderMinutes.ToString(CultureInfo.InvariantCulture));
        SelectComboBoxTag(NotificationCooldownBox, _notificationSettings.NotificationCooldownSeconds.ToString(CultureInfo.InvariantCulture));
        SelectComboBoxTag(NotificationEmailHourlyLimitBox, _notificationSettings.EmailHourlyLimit.ToString(CultureInfo.InvariantCulture));
        UpdateNotificationSettingsSummary();
        ApplyPlayerActivityNotificationSettingsToControls();
    }

    private void ApplyPlayerActivityNotificationSettingsToControls()
    {
        if (PlayerActivityNotificationCheck is null)
        {
            return;
        }

        PlayerActivityNotificationCheck.IsChecked = _notificationSettings.EnablePlayerActivityNotifications;
        PlayerActivityFleetScopeCheck.IsChecked =
            _notificationSettings.PlayerActivityScope.HasFlag(PlayerActivityNotificationScope.Fleet);
        PlayerActivityFriendScopeCheck.IsChecked =
            _notificationSettings.PlayerActivityScope.HasFlag(PlayerActivityNotificationScope.Friends);
        PlayerActivityRoomScopeCheck.IsChecked =
            _notificationSettings.PlayerActivityScope.HasFlag(PlayerActivityNotificationScope.PartyRoom);
        SelectComboBoxTag(PlayerActivityNotificationPositionBox, _notificationSettings.PlayerActivityPosition.ToString());
        PlayerActivityOnlineCheck.IsChecked = _notificationSettings.NotifyPlayerOnline;
        PlayerActivityOfflineCheck.IsChecked = _notificationSettings.NotifyPlayerOffline;
        PlayerActivityGameStartCheck.IsChecked = _notificationSettings.NotifyPlayerStartedGame;
        PlayerActivityGameStopCheck.IsChecked = _notificationSettings.NotifyPlayerStoppedGame;
        PlayerActivityBackgroundOnlyCheck.IsChecked = _notificationSettings.PlayerActivityBackgroundOnly;
        PlayerActivityReduceInGameCheck.IsChecked = _notificationSettings.ReducePlayerActivityNotificationsInGame;
        UpdatePlayerActivityNotificationSettingsState();
    }

    private void PlayerActivityNotificationSetting_Changed(object sender, RoutedEventArgs e)
    {
        SavePlayerActivityNotificationSettingsFromControls();
    }

    private void PlayerActivityNotificationOption_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        SavePlayerActivityNotificationSettingsFromControls();
    }

    private void SavePlayerActivityNotificationSettingsFromControls()
    {
        if (_isLoadingSettings || PlayerActivityNotificationCheck is null)
        {
            return;
        }

        _notificationSettings = (_notificationSettings with
        {
            EnablePlayerActivityNotifications = IsSwitchOn(PlayerActivityNotificationCheck),
            PlayerActivityScope = GetSelectedPlayerActivityNotificationScope(),
            PlayerActivityPosition = GetSelectedPlayerActivityNotificationPosition(),
            NotifyPlayerOnline = IsSwitchOn(PlayerActivityOnlineCheck),
            NotifyPlayerOffline = IsSwitchOn(PlayerActivityOfflineCheck),
            NotifyPlayerStartedGame = IsSwitchOn(PlayerActivityGameStartCheck),
            NotifyPlayerStoppedGame = IsSwitchOn(PlayerActivityGameStopCheck),
            PlayerActivityBackgroundOnly = IsSwitchOn(PlayerActivityBackgroundOnlyCheck),
            ReducePlayerActivityNotificationsInGame = IsSwitchOn(PlayerActivityReduceInGameCheck)
        }).Normalize();

        NotificationSettings.Save(_notificationSettings);
        NetworkStatusText.Text = "玩家动态通知设置已保存";
        UpdatePlayerActivityNotificationSettingsState();
    }

    private PlayerActivityNotificationScope GetSelectedPlayerActivityNotificationScope()
    {
        var scope = PlayerActivityNotificationScope.None;
        if (IsSwitchOn(PlayerActivityFleetScopeCheck))
        {
            scope |= PlayerActivityNotificationScope.Fleet;
        }

        if (IsSwitchOn(PlayerActivityFriendScopeCheck))
        {
            scope |= PlayerActivityNotificationScope.Friends;
        }

        if (IsSwitchOn(PlayerActivityRoomScopeCheck))
        {
            scope |= PlayerActivityNotificationScope.PartyRoom;
        }

        return scope;
    }

    private DesktopNotificationPosition GetSelectedPlayerActivityNotificationPosition()
    {
        return PlayerActivityNotificationPositionBox?.SelectedItem is ComboBoxItem item &&
               Enum.TryParse<DesktopNotificationPosition>(item.Tag?.ToString(), true, out var position) &&
               Enum.IsDefined(position)
            ? position
            : DesktopNotificationPosition.BottomRight;
    }

    private void UpdatePlayerActivityNotificationSettingsState()
    {
        if (PlayerActivityNotificationOptionsPanel is null || PlayerActivityNotificationStatusText is null)
        {
            return;
        }

        var enabled = _notificationSettings.EnablePlayerActivityNotifications;
        PlayerActivityNotificationOptionsPanel.IsEnabled = enabled;
        if (!enabled)
        {
            PlayerActivityNotificationStatusText.Text = "已关闭，不会弹出玩家动态通知。";
            PlayerActivityNotificationStatusText.Foreground = StatusPalette.DisabledBrush;
            return;
        }

        var eventCount = new[]
        {
            _notificationSettings.NotifyPlayerOnline,
            _notificationSettings.NotifyPlayerOffline,
            _notificationSettings.NotifyPlayerStartedGame,
            _notificationSettings.NotifyPlayerStoppedGame
        }.Count(value => value);
        var audiences = new List<string>(3);
        if (_notificationSettings.PlayerActivityScope.HasFlag(PlayerActivityNotificationScope.Fleet))
        {
            audiences.Add("舰队成员");
        }

        if (_notificationSettings.PlayerActivityScope.HasFlag(PlayerActivityNotificationScope.Friends))
        {
            audiences.Add("好友");
        }

        if (_notificationSettings.PlayerActivityScope.HasFlag(PlayerActivityNotificationScope.PartyRoom))
        {
            audiences.Add("同房间成员");
        }

        var scope = audiences.Count == 0 ? "未选择通知对象" : string.Join(" + ", audiences);
        var position = _notificationSettings.PlayerActivityPosition switch
        {
            DesktopNotificationPosition.TopLeft => "左上角",
            DesktopNotificationPosition.BottomLeft => "左下角",
            DesktopNotificationPosition.TopRight => "右上角",
            _ => "右下角"
        };
        PlayerActivityNotificationStatusText.Text = eventCount == 0
            ? "已开启，但尚未选择需要提醒的事件。"
            : audiences.Count == 0
                ? "已开启，但尚未选择需要提醒的成员范围。"
                : $"配置已保存 · {scope} · {position} · {eventCount} 类事件";
        PlayerActivityNotificationStatusText.Foreground = eventCount == 0 || audiences.Count == 0
            ? StatusPalette.WarningBrush
            : StatusPalette.SuccessBrush;
    }

    private void NotificationSetting_Changed(object sender, RoutedEventArgs e)
    {
        SaveNotificationSettingsFromControls();
    }

    private void NotificationOption_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        SaveNotificationSettingsFromControls();
    }

    private void SaveNotificationSettingsFromControls()
    {
        if (_isLoadingSettings || NotificationInAppCheck is null)
        {
            return;
        }

        _notificationSettings = ApplyFleetActionSettingsLock(new NotificationSettings(
            IsSwitchOn(NotificationInAppCheck),
            IsSwitchOn(NotificationOverlayCheck),
            IsSwitchOn(NotificationEmailCheck),
            IsSwitchOn(NotificationSoundCheck),
            IsSwitchOn(NotificationDesktopCheck),
            IsSwitchOn(NotificationFleetOrdersCheck),
            IsSwitchOn(NotificationMissionUpdatesCheck),
            IsSwitchOn(NotificationRallyPointUpdatesCheck),
            GetComboBoxTagAsInt(NotificationActionPlanReminderBox, _notificationSettings.ActionPlanReminderMinutes),
            IsSwitchOn(NotificationUrgentOrdersCheck),
            IsSwitchOn(NotificationSquadOrdersCheck),
            IsSwitchOn(NotificationSquadOnlineCheck),
            IsSwitchOn(NotificationSquadOfflineCheck),
            IsSwitchOn(NotificationMemberAnomalyCheck),
            IsSwitchOn(NotificationApplicationInviteCheck),
            IsSwitchOn(NotificationDoNotDisturbCheck),
            IsSwitchOn(NotificationReduceInGameCheck),
            GetComboBoxTagAsInt(NotificationCooldownBox, _notificationSettings.NotificationCooldownSeconds),
            GetComboBoxTagAsInt(NotificationEmailHourlyLimitBox, _notificationSettings.EmailHourlyLimit),
            IsSwitchOn(NotificationEmailCriticalOnlyCheck),
            _notificationSettings.EnablePlayerActivityNotifications,
            _notificationSettings.PlayerActivityScope,
            _notificationSettings.NotifyPlayerOnline,
            _notificationSettings.NotifyPlayerOffline,
            _notificationSettings.NotifyPlayerStartedGame,
            _notificationSettings.NotifyPlayerStoppedGame,
            _notificationSettings.PlayerActivityBackgroundOnly,
            _notificationSettings.ReducePlayerActivityNotificationsInGame,
            _notificationSettings.PlayerActivityPosition));

        _allowEmailNotifications = _notificationSettings.EnableEmailNotifications;
        NotificationSettings.Save(_notificationSettings);
        SaveCurrentConfig();
        NetworkStatusText.Text = "通知与邮件设置已保存";
        UpdateNotificationSettingsSummary();
    }

    private void UpdateNotificationSettingsSummary()
    {
        if (NotificationEnabledSummaryText is null)
        {
            return;
        }

        var switches = new[]
        {
            _notificationSettings.EnableInAppNotifications,
            _notificationSettings.EnableOverlayNotifications,
            _notificationSettings.EnableEmailNotifications,
            _notificationSettings.EnableSoundAlerts,
            _notificationSettings.EnableDesktopNotifications,
            _notificationSettings.NotifyFleetOrders,
            _notificationSettings.NotifyMissionUpdates,
            _notificationSettings.NotifyRallyPointUpdates,
            _notificationSettings.NotifyUrgentOrders,
            _notificationSettings.NotifySquadOrders,
            _notificationSettings.NotifySquadMemberOnline,
            _notificationSettings.NotifySquadMemberOffline,
            _notificationSettings.NotifyMemberAnomalies,
            _notificationSettings.NotifyApplicationsAndInvites,
            _notificationSettings.DoNotDisturb,
            _notificationSettings.ReduceAlertsInGame,
            _notificationSettings.EmailOnlyCritical
        };

        var enabled = switches.Count(value => value);
        NotificationEnabledSummaryText.Text = $"已开启 {enabled} 项";
        NotificationDisabledSummaryText.Text = $"已关闭 {switches.Length - enabled} 项";
        NotificationModeSummaryText.Text = _notificationSettings.DoNotDisturb
            ? "当前模式：免打扰"
            : _notificationSettings.ReduceAlertsInGame
                ? "当前模式：游戏中降噪"
                : "当前模式：标准提醒";

        var emailState = FleetActionFeatureSettingsLocked
            ? "不可用"
            : !_allowEmailNotifications ||
                         !_notificationSettings.EnableEmailNotifications ||
                         _notificationSettings.EmailHourlyLimit == 0
            ? "已关闭"
            : _notificationSettings.EmailOnlyCritical
                ? "仅紧急事件"
                : "已启用";
        NotificationMailStateText.Text = emailState;
        NotificationMailEmailText.Text = string.IsNullOrWhiteSpace(_accountName)
            ? "未绑定邮箱"
            : MaskAccountForDisplay(_accountName);
        NotificationMailLastText.Text = "无";
        NotificationMailCooldownText.Text = FleetActionFeatureSettingsLocked
            ? "行动邮件暂不可用"
            : _notificationSettings.NotificationCooldownSeconds == 0
            ? "无"
            : FormatNotificationCooldown(_notificationSettings.NotificationCooldownSeconds);
        NotificationSaveStateText.Text = "已自动保存到本地配置";
        RefreshPersonalRightEmailReminderStatus();
    }

    private static string FormatNotificationCooldown(int seconds)
    {
        return seconds switch
        {
            30 => "30 秒",
            60 => "1 分钟",
            300 => "5 分钟",
            _ when seconds <= 0 => "无",
            _ => $"{seconds} 秒"
        };
    }

    private static int GetComboBoxTagAsInt(System.Windows.Controls.ComboBox? comboBox, int fallback)
    {
        if (comboBox?.SelectedItem is ComboBoxItem item &&
            item.Tag is not null &&
            int.TryParse(item.Tag.ToString(), NumberStyles.Integer, CultureInfo.InvariantCulture, out var value))
        {
            return value;
        }

        return fallback;
    }

    private static void SelectComboBoxTag(System.Windows.Controls.ComboBox? comboBox, string tag)
    {
        if (comboBox is null)
        {
            return;
        }

        foreach (var candidate in comboBox.Items.OfType<ComboBoxItem>())
        {
            if (string.Equals(candidate.Tag?.ToString(), tag, StringComparison.OrdinalIgnoreCase))
            {
                comboBox.SelectedItem = candidate;
                return;
            }
        }
    }

    private static bool IsSwitchOn(System.Windows.Controls.CheckBox? checkBox)
    {
        return checkBox?.IsChecked == true;
    }
}
