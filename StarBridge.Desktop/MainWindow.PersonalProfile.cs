namespace StarBridge.Desktop;

using System.Globalization;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using StarBridge.Core.Profiles;

public partial class MainWindow
{
    private PersonalProfileSettings _personalProfileSettings = PersonalProfileSettings.CreateDefault();
    private PersonalProfileSettings _personalProfileSavedSettings = PersonalProfileSettings.CreateDefault();
    private bool _isPersonalProfileEditMode;
    private bool _isUpdatingPersonalProfileEditor;
    private bool _isPersonalProfileDirty;
    private bool _isPersonalProfilePublicPreviewMode;
    private bool _isPersonalProfileVisitorMode;
    private PersonalProfileVisitorLoadState _personalProfileVisitorLoadState;
    private PlayerRow? _personalProfileVisitorTarget;
    private PersonalProfileDocumentContract? _personalProfileVisitorDocument;
    private PersonalProfileSettings? _personalProfileOwnerSettingsBeforeVisitor;
    private PersonalProfileSettings? _personalProfileOwnerSavedSettingsBeforeVisitor;
    private IReadOnlyList<OwnedShipRecord> _personalProfileVisitorFallbackShips = [];
    private CancellationTokenSource? _personalProfileVisitorCts;
    private object? _personalProfileVisitorReturnTab;
    private string? _personalProfileSavedCallsign;
    private string? _personalProfileSavedAvatarPath;
    private string? _personalProfileDraftAvatarPath;
    private Point _personalProfileDragStart;
    private Border? _personalProfileDragSource;
    private Border? _personalProfileDragTarget;
    private PersonalProfileModuleSetting[]? _personalProfileDragBaseModules;
    private PersonalProfileModuleSetting[]? _personalProfileDragPreviewModules;
    private int? _personalProfileDragPreviewPosition;
    private string? _personalProfileSizeModuleId;
    private int? _personalProfilePendingInsertPosition;
    private readonly List<string> _personalProfileRoleDraftIds = [];
    private readonly List<string> _personalProfileParticipationInterestDraft = [];
    private readonly List<string> _personalProfileSupportCapabilityDraft = [];
    private readonly List<string> _personalProfileFavoriteShipDraftCodes = [];
    private readonly List<PersonalProfileAvailabilityWindowSetting> _personalProfileAvailabilityWindowDraft = [];
    private string _personalProfileRoleActiveCategoryId = PersonalProfileRoleCatalog.Categories[0].Id;
    private readonly PersonalProfileSyncCoordinator _personalProfileSyncCoordinator = new();
    private PersonalProfileRemoteRepository? _personalProfileRepository;
    private CancellationTokenSource? _personalProfileSyncCts;
    private CancellationTokenSource? _personalProfileAutoSaveCts;
    private string? _activePersonalProfileAccountIdentity;
    private bool _isApplyingPresenceVisibilityMode;

    private const string PersonalProfileModuleDragFormat = "StarBridge.PersonalProfileModule";
    private const double PersonalProfileModuleRowHeight = 140;

    private enum PersonalProfileVisitorLoadState
    {
        None,
        Loading,
        Loaded,
        NotFound,
        Unavailable
    }

    private static readonly string[] PersonalProfileTimeOptions = Enumerable
        .Range(0, 48)
        .Select(index => TimeOnly.MinValue.AddMinutes(index * 30).ToString("HH:mm", CultureInfo.InvariantCulture))
        .ToArray();

    private static readonly string[] PersonalProfileActivityRhythmOptions =
        ["休闲", "稳定活跃", "高频活跃", "周末为主", "不固定"];

    private void InitializePersonalProfileEditor()
    {
        _personalProfileSettings = PersonalProfileSettings.Load(GetPersonalProfileAccountIdentity());
        _personalProfileSavedSettings = _personalProfileSettings.Copy();

        PersonalProfileAvailabilityTimeZoneBox.ItemsSource = _fleetTimeZoneOptions;
        PersonalProfileActivityRhythmBox.ItemsSource = PersonalProfileActivityRhythmOptions;
        PersonalProfilePresenceIntentBox.ItemsSource = PersonalProfilePresenceIntentCatalog.Options;
        PersonalProfileVisibilityModeBox.ItemsSource = PlayerPresenceVisibilityCatalog.Options;
        ApplyPresenceVisibilityModeToProfileControl();
        ApplyPersonalProfileSettingsToEditor();
        SetPersonalProfileEditMode(false);
        RefreshPersonalProfileContent();
    }

    private string? GetPersonalProfileAccountIdentity() =>
        !string.IsNullOrWhiteSpace(_accountId) ? _accountId : _accountName;

    private void BeginPersonalProfileAccountSession(bool sameAccount)
    {
        var accountIdentity = GetPersonalProfileAccountIdentity();
        if (string.IsNullOrWhiteSpace(accountIdentity))
        {
            return;
        }

        var accountChanged = !sameAccount ||
                             !string.Equals(
                                 _activePersonalProfileAccountIdentity,
                                 accountIdentity,
                                 StringComparison.OrdinalIgnoreCase);
        if (accountChanged)
        {
            _personalProfileSyncCts?.Cancel();
            _personalProfileAutoSaveCts?.Cancel();
            _personalProfileSyncCoordinator.Reset();
            _activePersonalProfileAccountIdentity = accountIdentity;
            _personalProfileSettings = PersonalProfileSettings.Load(accountIdentity);
            _personalProfileSavedSettings = _personalProfileSettings.Copy();
            ApplyPersonalProfileSettingsToEditor();
            SetPersonalProfileEditMode(false);
            RefreshPersonalProfileContent();
        }

        if (accountChanged || _personalProfileSyncCoordinator.Snapshot is null)
        {
            _ = RefreshPersonalProfileFromServerAsync();
        }
    }

    private void EndPersonalProfileAccountSession()
    {
        if (_isPersonalProfileVisitorMode)
        {
            ExitPersonalProfileVisitorMode(restoreReturnTab: false);
        }

        _personalProfileSyncCts?.Cancel();
        _personalProfileAutoSaveCts?.Cancel();
        _personalProfileSyncCts = null;
        _personalProfileAutoSaveCts = null;
        _personalProfileSyncCoordinator.Reset();
        _activePersonalProfileAccountIdentity = null;
        _personalProfileSettings = PersonalProfileSettings.CreateDefault();
        _personalProfileSavedSettings = _personalProfileSettings.Copy();
        ApplyPersonalProfileSettingsToEditor();
        SetPersonalProfileEditMode(false);
        RefreshPersonalProfileContent();
    }

    private async Task RefreshPersonalProfileFromServerAsync()
    {
        var accountIdentity = _activePersonalProfileAccountIdentity;
        if (!CanSynchronizeUserData || string.IsNullOrWhiteSpace(accountIdentity) || _personalProfileRepository is null)
        {
            return;
        }

        _personalProfileSyncCts?.Cancel();
        var syncCts = new CancellationTokenSource();
        _personalProfileSyncCts = syncCts;
        var result = await _personalProfileRepository.LoadOwnerAsync(accountIdentity, syncCts.Token);
        if (syncCts.IsCancellationRequested ||
            !string.Equals(accountIdentity, _activePersonalProfileAccountIdentity, StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        if (result.HasPendingUpload)
        {
            if (result.Document is not null)
            {
                _personalProfileSyncCoordinator.AcceptSaved(result.Document);
            }

            RefreshPersonalProfileOnlineTimeEditorState(result.Error ?? "本地资料正在等待同步", isWarning: true);
            return;
        }

        if (result.Document is null)
        {
            if (!string.IsNullOrWhiteSpace(result.Error))
            {
                RefreshPersonalProfileOnlineTimeEditorState(result.Error, isWarning: true);
            }

            return;
        }

        ApplyGameplayStatisticsOwnerDocument(result.Document);
        RefreshGameplayStatisticsPresentation();

        if (result.Document.Revision == 0 && HasMeaningfulPersonalProfileContent(_personalProfileSettings))
        {
            var migration = await SavePersonalProfileRemoteAsync(
                _personalProfileSettings,
                result.Document.Revision,
                accountIdentity,
                syncCts.Token);
            if (migration.Status == PersonalProfileSaveStatus.Saved && migration.Document is not null)
            {
                AcceptSavedPersonalProfile(migration.Document, accountIdentity, applyToEditor: !_isPersonalProfileEditMode);
                RefreshPersonalProfileOnlineTimeEditorState("已同步");
            }
            else
            {
                RefreshPersonalProfileOnlineTimeEditorState(migration.Error ?? "本地资料正在等待同步", isWarning: true);
            }

            return;
        }

        if (!_personalProfileSyncCoordinator.TryAcceptRemote(
                result.Document,
                _isPersonalProfileEditMode,
                _isPersonalProfileDirty))
        {
            return;
        }

        _personalProfileSettings = PersonalProfileContractMapper.ToSettings(result.Document, _personalProfileSettings);
        _personalProfileSavedSettings = _personalProfileSettings.Copy();
        _personalProfileSettings.Save(accountIdentity);
        ApplyPersonalProfileSettingsToEditor();
        RefreshPersonalProfileContent();
        RefreshPersonalProfileOnlineTimeEditorState(
            result.Source == PersonalProfileLoadSource.Remote ? "已同步" : "已加载本地资料",
            isWarning: result.Source != PersonalProfileLoadSource.Remote);
    }

    private void ApplyPersonalProfileSettingsToEditor()
    {
        _isUpdatingPersonalProfileEditor = true;
        try
        {
            PersonalProfileOnlineTimeEnabledCheck.IsChecked = _personalProfileSettings.ShowOnlineTime;
            _personalProfileAvailabilityWindowDraft.Clear();
            _personalProfileAvailabilityWindowDraft.AddRange(
                (_personalProfileSettings.AvailabilityWindows ?? [])
                .Select(window => new PersonalProfileAvailabilityWindowSetting(
                    [.. window.Days],
                    window.StartTime,
                    window.EndTime)));

            var availabilityTimeZoneId = string.IsNullOrWhiteSpace(_personalProfileSettings.AvailabilityTimeZoneId)
                ? TimeZoneInfo.Local.Id
                : _personalProfileSettings.AvailabilityTimeZoneId;
            PersonalProfileAvailabilityTimeZoneBox.SelectedItem = _fleetTimeZoneOptions.FirstOrDefault(option =>
                    string.Equals(option.Id, availabilityTimeZoneId, StringComparison.OrdinalIgnoreCase)) ??
                FindFleetTimeZoneOptionBySameOffset(availabilityTimeZoneId) ??
                _fleetTimeZoneOptions.FirstOrDefault();
            RenderPersonalProfileAvailabilityWindows();
            PersonalProfileActivityRhythmBox.SelectedItem = _personalProfileSettings.ActivityRhythm;
            PersonalProfilePresenceIntentBox.SelectedItem = PersonalProfilePresenceIntentCatalog.Options.First(option =>
                string.Equals(option.Id, _personalProfileSettings.PresenceIntent, StringComparison.OrdinalIgnoreCase));
            PersonalProfilePublicCheck.IsChecked = _personalProfileSettings.IsProfilePublic;
            PersonalProfileIntroductionEditor.Text = _personalProfileSettings.Introduction;
            RefreshPersonalProfileOnlineTimeEditorState();
        }
        finally
        {
            _isUpdatingPersonalProfileEditor = false;
        }
    }

    private void SetPersonalProfileEditMode(bool isEditing)
    {
        if (_isPersonalProfilePublicPreviewMode || _isPersonalProfileVisitorMode)
        {
            isEditing = false;
        }

        if (isEditing)
        {
            _isPersonalProfilePublicPreviewMode = false;
        }

        _isPersonalProfileEditMode = isEditing;
        PersonalProfileAvatarDisplayImage.Visibility = isEditing ? Visibility.Collapsed : Visibility.Visible;
        PersonalProfileAvatarDraftImage.Visibility = isEditing ? Visibility.Visible : Visibility.Collapsed;
        PersonalProfileAvatarEditButton.Visibility = isEditing ? Visibility.Visible : Visibility.Collapsed;
        PersonalProfileCallsignText.Visibility = isEditing ? Visibility.Collapsed : Visibility.Visible;
        PersonalProfileCallsignEditor.Visibility = isEditing ? Visibility.Visible : Visibility.Collapsed;
        RenderPersonalProfileAvailabilityWindows();
        PersonalProfileAddModuleButton.Visibility = isEditing ? Visibility.Visible : Visibility.Collapsed;
        PersonalProfileCancelButton.Visibility = isEditing ? Visibility.Visible : Visibility.Collapsed;
        PersonalProfileSaveButton.Visibility = isEditing ? Visibility.Visible : Visibility.Collapsed;
        PersonalProfileEditHint.Visibility = isEditing ? Visibility.Visible : Visibility.Collapsed;
        PersonalProfileIntroductionText.Visibility = isEditing ? Visibility.Collapsed : Visibility.Visible;
        PersonalProfileIntroductionEditor.Visibility = isEditing ? Visibility.Visible : Visibility.Collapsed;
        PersonalProfilePresenceIntentEditorPanel.Visibility = isEditing ? Visibility.Visible : Visibility.Collapsed;
        PersonalProfileFixedInfoPanel.Padding = isEditing
            ? new Thickness(13, 11, 13, 11)
            : new Thickness(13, 9, 13, 9);
        PersonalProfileFixedInfoPanel.Background = isEditing
            ? new SolidColorBrush(Color.FromRgb(7, 24, 35))
            : Brushes.Transparent;
        PersonalProfileFixedInfoPanel.BorderThickness = isEditing
            ? new Thickness(1)
            : new Thickness(0, 1, 0, 1);
        PersonalProfileOnlineTimeDescriptionText.Visibility = isEditing ? Visibility.Visible : Visibility.Collapsed;
        PersonalProfileOnlineTimeEditorPanel.Visibility = isEditing ? Visibility.Visible : Visibility.Collapsed;

        PersonalProfileActivityRhythmDescriptionText.Visibility = isEditing ? Visibility.Visible : Visibility.Collapsed;
        PersonalProfileActivityRhythmDivider.Visibility = isEditing ? Visibility.Visible : Visibility.Collapsed;
        PersonalProfileActivityRhythmEditorPanel.Visibility = isEditing ? Visibility.Visible : Visibility.Collapsed;
        RefreshPersonalProfileFixedInformationLayout(GetPersonalProfilePresentationState());

        foreach (var controls in GetPersonalProfileModuleControls().Values)
        {
            controls.Visibility = isEditing ? Visibility.Visible : Visibility.Collapsed;
        }

        if (!isEditing)
        {
            _isPersonalProfileDirty = false;
            _personalProfilePendingInsertPosition = null;
            PersonalProfileModulePickerPopup.IsOpen = false;
            PersonalProfileModuleSizePopup.IsOpen = false;
        }

        RefreshPersonalProfileOnlineTimeEditorState();
        RefreshPersonalProfileEditorState();
        ApplyPersonalProfileModuleLayout();
        RefreshPersonalProfileAccessState();
        RefreshPersonalProfilePresenceIntent();
    }

    private void RefreshPersonalProfileEditorState(string? message = null, bool isWarning = false)
    {
        PersonalProfileSaveButton.IsEnabled = _isPersonalProfileDirty;
        PersonalProfileEditHintText.Text = message ?? (_isPersonalProfileDirty
            ? "你有未保存的主页更改。头像、呼号与主页内容会一起保存。"
            : "编辑公开资料、在线时间与主页模块，完成后统一保存。");
        PersonalProfileEditHintText.Foreground = isWarning
            ? FindBrush("StatusWarningBrush", Brushes.Goldenrod)
            : FindBrush("SecondaryTextBrush", Brushes.LightSlateGray);
    }

    private void PersonalProfileEditButton_Click(object sender, RoutedEventArgs e)
    {
        _personalProfileSavedSettings = _personalProfileSettings.Copy();
        _personalProfileSavedCallsign = _callsign;
        _personalProfileSavedAvatarPath = _avatarPath;
        _personalProfileDraftAvatarPath = _avatarPath;
        ApplyPersonalProfileSettingsToEditor();
        ApplyPersonalProfileIdentityDraftToEditor();
        SetPersonalProfileEditMode(true);
    }

    private void PersonalProfilePreviewButton_Click(object sender, RoutedEventArgs e)
    {
        if (_isPersonalProfileEditMode)
        {
            return;
        }

        _isPersonalProfilePublicPreviewMode = true;
        ApplyPersonalProfileModuleLayout();
        RefreshPersonalProfileAccessState();
    }

    private void PersonalProfilePreviewExitButton_Click(object sender, RoutedEventArgs e)
    {
        if (_isPersonalProfileVisitorMode)
        {
            ExitPersonalProfileVisitorMode(restoreReturnTab: true);
            return;
        }

        _isPersonalProfilePublicPreviewMode = false;
        ApplyPersonalProfileModuleLayout();
        RefreshPersonalProfileAccessState();
    }

    private void PersonalProfileVisitorBackButton_Click(object sender, RoutedEventArgs e)
    {
        ExitPersonalProfileVisitorMode(restoreReturnTab: true);
    }

    private async Task OpenPersonalProfileVisitorAsync(PlayerRow target)
    {
        if (_isPersonalProfileEditMode && _isPersonalProfileDirty)
        {
            StarBridgeMessageBox.Show(
                this,
                "你的个人主页仍有未保存更改。请先返回个人主页保存或取消，再查看其他成员资料。",
                "个人主页尚未保存",
                MessageBoxButton.OK,
                MessageBoxImage.Information);
            return;
        }

        var wasVisitorMode = _isPersonalProfileVisitorMode;
        _personalProfileVisitorCts?.Cancel();
        _personalProfileVisitorCts?.Dispose();
        var visitorCts = new CancellationTokenSource();
        _personalProfileVisitorCts = visitorCts;

        if (!wasVisitorMode)
        {
            _personalProfileOwnerSettingsBeforeVisitor = _personalProfileSettings.Copy();
            _personalProfileOwnerSavedSettingsBeforeVisitor = _personalProfileSavedSettings.Copy();
            _personalProfileVisitorReturnTab = ReferenceEquals(MainTabs.SelectedItem, PersonalTab)
                ? FleetTab
                : MainTabs.SelectedItem;
        }
        _personalProfileVisitorTarget = target;
        _personalProfileVisitorDocument = null;
        _personalProfileVisitorFallbackShips = ResolveVisitorFallbackShips(target);
        _personalProfileVisitorLoadState = PersonalProfileVisitorLoadState.Loading;
        _isPersonalProfilePublicPreviewMode = false;
        _isPersonalProfileVisitorMode = true;
        _personalProfileSettings = PersonalProfileSettings.CreateDefault();
        _personalProfileSavedSettings = _personalProfileSettings.Copy();
        SetPersonalProfileEditMode(false);
        ApplyPersonalProfileSettingsToEditor();
        RefreshPersonalProfileContent();

        var previousTab = MainTabs.SelectedItem;
        MainTabs.SelectedItem = PersonalTab;
        SetActiveNav(PersonalNavButton);
        QueueMainPageReveal(previousTab);

        if (_personalProfileRepository is null)
        {
            ApplyPersonalProfileVisitorFailure(PersonalProfileVisitorLoadState.Unavailable);
            return;
        }

        var result = await _personalProfileRepository.LoadPublicAsync(target.AccountId!, visitorCts.Token);
        if (visitorCts.IsCancellationRequested ||
            !_isPersonalProfileVisitorMode ||
            !string.Equals(
                target.AccountId,
                _personalProfileVisitorTarget?.AccountId,
                StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        switch (result.Status)
        {
            case PersonalProfilePublicLoadStatus.Loaded when result.Document is not null:
                _personalProfileVisitorDocument = result.Document;
                _personalProfileVisitorLoadState = PersonalProfileVisitorLoadState.Loaded;
                _personalProfileSettings = PersonalProfileContractMapper.ToSettings(
                    result.Document,
                    PersonalProfileSettings.CreateDefault());
                _personalProfileSavedSettings = _personalProfileSettings.Copy();
                ApplyPersonalProfileSettingsToEditor();
                RefreshPersonalProfileContent();
                break;
            case PersonalProfilePublicLoadStatus.NotFound:
                ApplyPersonalProfileVisitorFailure(PersonalProfileVisitorLoadState.NotFound);
                break;
            default:
                ApplyPersonalProfileVisitorFailure(PersonalProfileVisitorLoadState.Unavailable);
                break;
        }
    }

    private void ApplyPersonalProfileVisitorFailure(PersonalProfileVisitorLoadState state)
    {
        _personalProfileVisitorDocument = null;
        _personalProfileVisitorLoadState = state;
        _personalProfileSettings = PersonalProfileSettings.CreateDefault();
        _personalProfileSavedSettings = _personalProfileSettings.Copy();
        ApplyPersonalProfileSettingsToEditor();
        RefreshPersonalProfileContent();
    }

    private async void PersonalProfileVisitorRetryButton_Click(object sender, RoutedEventArgs e)
    {
        if (_personalProfileVisitorTarget is not null)
        {
            await OpenPersonalProfileVisitorAsync(_personalProfileVisitorTarget);
        }
    }

    private void ExitPersonalProfileVisitorMode(bool restoreReturnTab)
    {
        if (!_isPersonalProfileVisitorMode)
        {
            return;
        }

        var returnTab = _personalProfileVisitorReturnTab ?? FleetTab;
        _personalProfileVisitorCts?.Cancel();
        _personalProfileVisitorCts?.Dispose();
        _personalProfileVisitorCts = null;
        _isPersonalProfileVisitorMode = false;
        _personalProfileVisitorLoadState = PersonalProfileVisitorLoadState.None;
        _personalProfileVisitorTarget = null;
        _personalProfileVisitorDocument = null;
        _personalProfileVisitorFallbackShips = [];
        _personalProfileVisitorReturnTab = null;
        _personalProfileSettings = _personalProfileOwnerSettingsBeforeVisitor?.Copy() ??
                                   PersonalProfileSettings.Load(GetPersonalProfileAccountIdentity());
        _personalProfileSavedSettings = _personalProfileOwnerSavedSettingsBeforeVisitor?.Copy() ??
                                        _personalProfileSettings.Copy();
        _personalProfileOwnerSettingsBeforeVisitor = null;
        _personalProfileOwnerSavedSettingsBeforeVisitor = null;
        ApplyPersonalProfileSettingsToEditor();
        SetPersonalProfileEditMode(false);
        RefreshPersonalProfileContent();

        if (!restoreReturnTab)
        {
            return;
        }

        var previousTab = MainTabs.SelectedItem;
        MainTabs.SelectedItem = returnTab;
        RestoreMainNavigationForTab(returnTab);
        QueueMainPageReveal(previousTab);
    }

    private void MainTabs_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (ReferenceEquals(e.Source, MainTabs) && ReferenceEquals(MainTabs.SelectedItem, HomeTab))
        {
            RefreshHomeDashboard();
        }

        if (!ReferenceEquals(e.Source, MainTabs) ||
            !_isPersonalProfileVisitorMode ||
            ReferenceEquals(MainTabs.SelectedItem, PersonalTab))
        {
            return;
        }

        ExitPersonalProfileVisitorMode(restoreReturnTab: false);
    }

    private void RestoreMainNavigationForTab(object? tab)
    {
        if (ReferenceEquals(tab, FleetTab))
        {
            SetActiveNav(MyFleetNavButton);
        }
        else if (ReferenceEquals(tab, FindFleetTab))
        {
            SetActiveNav(FindFleetNavButton);
        }
        else if (ReferenceEquals(tab, MySquadTab))
        {
            SetActiveNav(MySquadNavButton);
        }
        else if (ReferenceEquals(tab, OverlayEditTab))
        {
            SetActiveNav(OverlayNavButton);
        }
        else if (ReferenceEquals(tab, SettingsTab))
        {
            SetActiveNav(HeaderSettingsButton);
        }
        else if (ReferenceEquals(tab, FriendCenterTab))
        {
            SetActiveNav(HeaderFriendCenterButton);
        }
        else if (ReferenceEquals(tab, PersonalTab))
        {
            SetActiveNav(PersonalNavButton);
        }
        else
        {
            SetActiveNav(null);
        }
    }

    private IReadOnlyList<OwnedShipRecord> ResolveVisitorFallbackShips(PlayerRow target)
    {
        if (!_networkSnapshots.TryGetValue(target.Name, out var snapshot))
        {
            return [];
        }

        return (snapshot.OwnedShips ?? [])
            .Where(ship => !string.IsNullOrWhiteSpace(ship.Code))
            .Select(ship => new OwnedShipRecord(
                ship.Code,
                string.IsNullOrWhiteSpace(ship.DisplayName) ? ship.Code : ship.DisplayName,
                "PublicProfile",
                ship.ImportedAt,
                ship.ImportedAt,
                ship.SyncedAt,
                ship.InstanceId))
            .ToArray();
    }

    private void PersonalProfileCancelButton_Click(object sender, RoutedEventArgs e)
    {
        _personalProfileSettings = _personalProfileSavedSettings.Copy();
        _personalProfileDraftAvatarPath = _personalProfileSavedAvatarPath;
        ApplyPersonalProfileSettingsToEditor();
        ApplyPersonalProfileIdentityDraftToEditor();
        SetPersonalProfileEditMode(false);
        RefreshPersonalProfileContent();
    }

    private void ApplyPersonalProfileIdentityDraftToEditor()
    {
        _isUpdatingPersonalProfileEditor = true;
        try
        {
            PersonalProfileCallsignEditor.Text =
                _personalProfileSavedCallsign ?? _callsign ?? GetPersonalDisplayName();
            ApplyPersonalProfileAvatarDraftPreview();
        }
        finally
        {
            _isUpdatingPersonalProfileEditor = false;
        }
    }

    private void ApplyPersonalProfileAvatarDraftPreview()
    {
        if (TryLoadBitmapImage(_personalProfileDraftAvatarPath, out var image) && image is not null)
        {
            PersonalProfileAvatarDraftImage.Source = image;
            return;
        }

        PersonalProfileAvatarDraftImage.Source = AvatarImage.Source;
    }

    private void PersonalProfileAvatarEditButton_Click(object sender, RoutedEventArgs e)
    {
        var croppedPath = ChooseAndCropImage(
            "选择个人头像",
            $"player-avatar-draft-{Guid.NewGuid():N}.png",
            LocalImageStorage.UserAsset);
        if (croppedPath is null)
        {
            return;
        }

        _personalProfileDraftAvatarPath = croppedPath;
        ApplyPersonalProfileAvatarDraftPreview();
        MarkPersonalProfileDirty();
    }

    private void PersonalProfileCallsignEditor_TextChanged(object sender, TextChangedEventArgs e)
    {
        if (_isUpdatingPersonalProfileEditor || !_isPersonalProfileEditMode)
        {
            return;
        }

        var limited = LimitCallsign(PersonalProfileCallsignEditor.Text ?? "");
        if (!string.Equals(PersonalProfileCallsignEditor.Text, limited, StringComparison.Ordinal))
        {
            _isUpdatingPersonalProfileEditor = true;
            try
            {
                var caret = Math.Min(PersonalProfileCallsignEditor.CaretIndex, limited.Length);
                PersonalProfileCallsignEditor.Text = limited;
                PersonalProfileCallsignEditor.CaretIndex = caret;
            }
            finally
            {
                _isUpdatingPersonalProfileEditor = false;
            }
        }

        MarkPersonalProfileDirty();
    }

    private void CommitPersonalProfileIdentityDraft()
    {
        var normalized = LimitCallsign(PersonalProfileCallsignEditor.Text ?? "").Trim();
        var nextCallsign = string.IsNullOrWhiteSpace(normalized) ? _callsign : normalized;
        var callsignChanged = !string.Equals(_callsign, nextCallsign, StringComparison.Ordinal);
        var avatarChanged = !string.Equals(
            _avatarPath,
            _personalProfileDraftAvatarPath,
            StringComparison.OrdinalIgnoreCase);

        _callsign = nextCallsign;
        if (avatarChanged)
        {
            _avatarPath = _personalProfileDraftAvatarPath;
            _cachedAvatarImagePath = null;
            _cachedAvatarImageData = null;
        }

        var wasLoadingSettings = _isLoadingSettings;
        _isLoadingSettings = true;
        try
        {
            CallsignBox.Text = _callsign ?? "";
        }
        finally
        {
            _isLoadingSettings = wasLoadingSettings;
        }

        SaveCurrentConfig();
        RefreshAccountPanel();
        RenderState();
        if (callsignChanged)
        {
            StartProfileSyncDebounce();
        }

        if (callsignChanged || avatarChanged)
        {
            _ = PushLocalSnapshotAsync(silent: true);
        }

        _personalProfileSavedCallsign = _callsign;
        _personalProfileSavedAvatarPath = _avatarPath;
        _personalProfileDraftAvatarPath = _avatarPath;
    }

    private async void PersonalProfileSaveButton_Click(object sender, RoutedEventArgs e)
    {
        if (!_isPersonalProfileDirty)
        {
            return;
        }

        var draftCallsign = LimitCallsign(PersonalProfileCallsignEditor.Text ?? "").Trim();
        if (string.IsNullOrWhiteSpace(draftCallsign))
        {
            RefreshPersonalProfileEditorState("呼号不能为空。", isWarning: true);
            PersonalProfileCallsignEditor.Focus();
            return;
        }

        var candidate = ReadPersonalProfileSettingsFromEditor();
        var accountIdentity = GetPersonalProfileAccountIdentity();
        try
        {
            if (!CanSynchronizeUserData || string.IsNullOrWhiteSpace(accountIdentity) || _personalProfileRepository is null)
            {
                candidate.Save(accountIdentity);
                _personalProfileSettings = candidate;
                _personalProfileSavedSettings = candidate.Copy();
                CommitPersonalProfileIdentityDraft();
                SetPersonalProfileEditMode(false);
                RefreshPersonalProfileContent();
                return;
            }

            RefreshPersonalProfileEditorState("正在保存个人主页…");
            PersonalProfileSaveButton.IsEnabled = false;
            var expectedRevision = _personalProfileSyncCoordinator.Snapshot?.Revision ?? 0;
            var result = await SavePersonalProfileRemoteAsync(
                candidate,
                expectedRevision,
                accountIdentity,
                CancellationToken.None);
            switch (result.Status)
            {
                case PersonalProfileSaveStatus.Saved when result.Document is not null:
                    AcceptSavedPersonalProfile(result.Document, accountIdentity, applyToEditor: true);
                    CommitPersonalProfileIdentityDraft();
                    SetPersonalProfileEditMode(false);
                    RefreshPersonalProfileContent();
                    RefreshPersonalProfileOnlineTimeEditorState("已同步");
                    break;
                case PersonalProfileSaveStatus.QueuedOffline:
                case PersonalProfileSaveStatus.Unauthorized:
                    candidate.Save(accountIdentity);
                    _personalProfileSettings = candidate;
                    _personalProfileSavedSettings = candidate.Copy();
                    CommitPersonalProfileIdentityDraft();
                    SetPersonalProfileEditMode(false);
                    RefreshPersonalProfileContent();
                    RefreshPersonalProfileOnlineTimeEditorState("已保存到本地，等待同步", isWarning: true);
                    break;
                case PersonalProfileSaveStatus.Conflict:
                    if (result.Document is not null)
                    {
                        _personalProfileSyncCoordinator.AcceptSaved(result.Document);
                    }

                    _personalProfileSettings = candidate;
                    _isPersonalProfileDirty = true;
                    RefreshPersonalProfileEditorState(
                        "资料已在其他设备更新。当前编辑内容仍保留，请检查后再次保存。",
                        isWarning: true);
                    break;
            }

            PersonalProfileSaveButton.IsEnabled = _isPersonalProfileDirty;
        }
        catch
        {
            PersonalProfileSaveButton.IsEnabled = _isPersonalProfileDirty;
            RefreshPersonalProfileEditorState("主页设置保存失败，请检查本地配置目录后重试。", isWarning: true);
        }
    }

    private void PersonalProfileEditorChanged(object sender, RoutedEventArgs e)
    {
        if (_isUpdatingPersonalProfileEditor)
        {
            return;
        }

        var previous = _personalProfileSettings;
        _personalProfileSettings = ReadPersonalProfileSettingsFromEditor();
        RefreshPersonalProfileOnlineTimeEditorState();
        if (_isPersonalProfileEditMode)
        {
            MarkPersonalProfileDirty();
        }
        else
        {
            try
            {
                var accountIdentity = GetPersonalProfileAccountIdentity();
                _personalProfileSettings.Save(accountIdentity);
                _personalProfileSavedSettings = _personalProfileSettings.Copy();
                SchedulePersonalProfileAutoSync();
                RefreshPersonalProfileOnlineTimeEditorState("已保存");
            }
            catch
            {
                _personalProfileSettings = previous;
                ApplyPersonalProfileSettingsToEditor();
                RefreshPersonalProfileOnlineTimeEditorState("保存失败，请重试", isWarning: true);
            }
        }

        RefreshPersonalProfileContent();
    }

    private void SchedulePersonalProfileAutoSync()
    {
        if (!CanSynchronizeUserData ||
            string.IsNullOrWhiteSpace(_activePersonalProfileAccountIdentity) ||
            _personalProfileRepository is null)
        {
            return;
        }

        _personalProfileAutoSaveCts?.Cancel();
        _personalProfileAutoSaveCts = new CancellationTokenSource();
        _ = AutoSyncPersonalProfileAsync(_personalProfileAutoSaveCts.Token);
    }

    private async Task AutoSyncPersonalProfileAsync(CancellationToken cancellationToken)
    {
        try
        {
            await Task.Delay(TimeSpan.FromMilliseconds(1200), cancellationToken);
            var accountIdentity = _activePersonalProfileAccountIdentity;
            if (cancellationToken.IsCancellationRequested ||
                _isPersonalProfileEditMode ||
                string.IsNullOrWhiteSpace(accountIdentity))
            {
                return;
            }

            var candidate = _personalProfileSettings.Copy();
            var expectedRevision = _personalProfileSyncCoordinator.Snapshot?.Revision ?? 0;
            var result = await SavePersonalProfileRemoteAsync(
                candidate,
                expectedRevision,
                accountIdentity,
                cancellationToken);
            if (cancellationToken.IsCancellationRequested ||
                !string.Equals(accountIdentity, _activePersonalProfileAccountIdentity, StringComparison.OrdinalIgnoreCase))
            {
                return;
            }

            switch (result.Status)
            {
                case PersonalProfileSaveStatus.Saved when result.Document is not null:
                    AcceptSavedPersonalProfile(result.Document, accountIdentity, applyToEditor: false);
                    RefreshPersonalProfileOnlineTimeEditorState("已同步");
                    break;
                case PersonalProfileSaveStatus.Conflict:
                    if (result.Document is not null)
                    {
                        _personalProfileSyncCoordinator.AcceptSaved(result.Document);
                    }

                    RefreshPersonalProfileOnlineTimeEditorState(
                        "其他设备已更新资料，本地内容已保留",
                        isWarning: true);
                    break;
                default:
                    RefreshPersonalProfileOnlineTimeEditorState(
                        result.Error ?? "已保存到本地，等待同步",
                        isWarning: true);
                    break;
            }
        }
        catch (OperationCanceledException)
        {
            // A newer edit superseded this save request.
        }
    }

    private Task<PersonalProfileSaveResult> SavePersonalProfileRemoteAsync(
        PersonalProfileSettings settings,
        long expectedRevision,
        string accountIdentity,
        CancellationToken cancellationToken)
    {
        if (_personalProfileRepository is null)
        {
            return Task.FromResult(new PersonalProfileSaveResult(
                PersonalProfileSaveStatus.QueuedOffline,
                null,
                "同步服务尚未就绪，资料已保存在本地。"));
        }

        var request = new PersonalProfileUpdateRequestContract(
            expectedRevision,
            settings.IsProfilePublic,
            PersonalProfileContractMapper.ToContract(settings));
        return _personalProfileRepository.SaveOwnerAsync(accountIdentity, request, cancellationToken);
    }

    private void AcceptSavedPersonalProfile(
        PersonalProfileDocumentContract document,
        string accountIdentity,
        bool applyToEditor)
    {
        _personalProfileSyncCoordinator.AcceptSaved(document);
        var saved = PersonalProfileContractMapper.ToSettings(document, _personalProfileSettings);
        saved.Save(accountIdentity);
        _personalProfileSettings = saved;
        _personalProfileSavedSettings = saved.Copy();
        _isPersonalProfileDirty = false;
        if (applyToEditor)
        {
            ApplyPersonalProfileSettingsToEditor();
        }
    }

    private static bool HasMeaningfulPersonalProfileContent(PersonalProfileSettings settings) =>
        settings.IsProfilePublic ||
        settings.ShowOnlineTime ||
        !string.IsNullOrWhiteSpace(settings.PresenceIntent) ||
        !string.IsNullOrWhiteSpace(settings.Introduction) ||
        (settings.SkilledRoles?.Length ?? 0) > 0 ||
        (settings.SupportCapabilities?.Length ?? 0) > 0 ||
        (settings.ParticipationInterests?.Length ?? 0) > 0 ||
        (settings.FavoriteShipCodes?.Length ?? 0) > 0 ||
        settings.Modules.Any(module => module.IsVisible);

    private void RefreshPersonalProfileOnlineTimeEditorState(string? status = null, bool isWarning = false)
    {
        if (PersonalProfileOnlineTimeEnabledCheck is null)
        {
            return;
        }

        var canEdit = _isPersonalProfileEditMode;
        PersonalProfileOnlineTimeEnabledCheck.IsEnabled = canEdit;
        PersonalProfileAvailabilityTimeZoneBox.IsEnabled = canEdit;
        PersonalProfileUseLocalTimeZoneButton.IsEnabled = canEdit;
        PersonalProfileAddAvailabilityWindowButton.IsEnabled = canEdit && _personalProfileAvailabilityWindowDraft.Count < 3;
        PersonalProfileAvailabilityWindowCountText.Text = $"{_personalProfileAvailabilityWindowDraft.Count}/3";
        PersonalProfileOnlineTimeSaveStateText.Text = status ?? (_isPersonalProfileEditMode ? "随主页设置一起保存" : "更改后自动保存");
        PersonalProfileOnlineTimeSaveStateText.Foreground = isWarning
            ? FindBrush("StatusErrorBrush", Brushes.IndianRed)
            : status == "已保存"
                ? FindBrush("StatusSuccessBrush", Brushes.MediumSeaGreen)
                : FindBrush("MutedTextBrush", Brushes.SlateGray);
    }

    private PersonalProfileSettings ReadPersonalProfileSettingsFromEditor()
    {
        var windows = _personalProfileAvailabilityWindowDraft
            .Select(window => new PersonalProfileAvailabilityWindowSetting(
                [.. window.Days],
                window.StartTime,
                window.EndTime))
            .ToArray();
        var firstWindow = windows.FirstOrDefault();
        var timeZoneId = (PersonalProfileAvailabilityTimeZoneBox.SelectedItem as FleetTimeZoneOptionRow)?.Id;

        return _personalProfileSettings with
        {
            ShowOnlineTime = PersonalProfileOnlineTimeEnabledCheck.IsChecked == true,
            OnlineTimeStart = firstWindow?.StartTime ?? "19:00",
            OnlineTimeEnd = firstWindow?.EndTime ?? "22:00",
            AvailabilityTimeZoneId = string.IsNullOrWhiteSpace(timeZoneId)
                ? TimeZoneInfo.Local.Id
                : timeZoneId,
            AvailabilityWindows = windows,
            Introduction = PersonalProfileIntroductionEditor.Text ?? "",
            PresenceIntent = (PersonalProfilePresenceIntentBox.SelectedItem as PersonalProfilePresenceIntentOption)?.Id,
            ActivityRhythm = PersonalProfileActivityRhythmBox.SelectedItem as string ?? "休闲",
            IsProfilePublic = PersonalProfilePublicCheck.IsChecked == true,
            SkilledRoles = PersonalProfileRoleCatalog.NormalizeRoleIds(_personalProfileSettings.SkilledRoles),
            SupportCapabilities = PersonalProfilePlayStyleCatalog.Normalize(_personalProfileSettings.SupportCapabilities),
            ParticipationInterests = PersonalProfilePlayStyleCatalog.Normalize(_personalProfileSettings.ParticipationInterests)
        };
    }

    private void PersonalProfileUseLocalTimeZoneButton_Click(object sender, RoutedEventArgs e)
    {
        var localTimeZoneId = TimeZoneInfo.Local.Id;
        var option = _fleetTimeZoneOptions.FirstOrDefault(item =>
                         item.Id.Equals(localTimeZoneId, StringComparison.OrdinalIgnoreCase)) ??
                     FindFleetTimeZoneOptionBySameOffset(localTimeZoneId) ??
                     _fleetTimeZoneOptions.FirstOrDefault();
        if (option is null)
        {
            return;
        }

        if (ReferenceEquals(PersonalProfileAvailabilityTimeZoneBox.SelectedItem, option))
        {
            PersonalProfileEditorChanged(sender, e);
            return;
        }

        PersonalProfileAvailabilityTimeZoneBox.SelectedItem = option;
    }

    private void PersonalProfilePresenceIntentBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_isUpdatingPersonalProfileEditor || !_isPersonalProfileEditMode)
        {
            return;
        }

        MarkPersonalProfileDirty();
    }

    private async void PersonalProfileVisibilityModeBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_isApplyingPresenceVisibilityMode ||
            _isPersonalProfileVisitorMode ||
            _isPersonalProfilePublicPreviewMode ||
            PersonalProfileVisibilityModeBox.SelectedItem is not PlayerPresenceVisibilityOption option ||
            option.Mode == _syncPrivacySettings.PresenceVisibilityMode)
        {
            return;
        }

        await ApplyPresenceVisibilityModeAsync(option.Mode);
    }

    private void ApplyPresenceVisibilityModeToProfileControl()
    {
        if (PersonalProfileVisibilityModeBox is null)
        {
            return;
        }

        _isApplyingPresenceVisibilityMode = true;
        try
        {
            var option = PlayerPresenceVisibilityCatalog.Find(_syncPrivacySettings.PresenceVisibilityMode);
            PersonalProfileVisibilityModeBox.SelectedItem = option;
            PersonalProfileVisibilityModeBox.ToolTip = option.Description;
            PersonalProfileVisibilityModePanel.Visibility = _isPersonalProfileVisitorMode || _isPersonalProfilePublicPreviewMode
                ? Visibility.Collapsed
                : Visibility.Visible;
        }
        finally
        {
            _isApplyingPresenceVisibilityMode = false;
        }
    }

    private void PersonalProfileAddAvailabilityWindowButton_Click(object sender, RoutedEventArgs e)
    {
        if (!_isPersonalProfileEditMode || _personalProfileAvailabilityWindowDraft.Count >= 3)
        {
            return;
        }

        _personalProfileAvailabilityWindowDraft.Add(new PersonalProfileAvailabilityWindowSetting(
            [0, 1, 2, 3, 4, 5, 6],
            "19:00",
            "22:00"));
        RenderPersonalProfileAvailabilityWindows();
        PersonalProfileEditorChanged(sender, e);
    }

    private void RenderPersonalProfileAvailabilityWindows()
    {
        if (PersonalProfileAvailabilityWindowsPanel is null)
        {
            return;
        }

        PersonalProfileAvailabilityWindowsPanel.Children.Clear();
        if (_personalProfileAvailabilityWindowDraft.Count == 0)
        {
            PersonalProfileAvailabilityWindowsPanel.Children.Add(new TextBlock
            {
                Text = "尚未添加时间段；留空时不会对外展示可游玩时间。",
                Foreground = FindBrush("MutedTextBrush", Brushes.SlateGray),
                FontSize = 10,
                Margin = new Thickness(0, 2, 0, 2)
            });
            RefreshPersonalProfileOnlineTimeEditorState();
            return;
        }

        var orderedDays = GetPersonalProfileDayOrder();
        for (var index = 0; index < _personalProfileAvailabilityWindowDraft.Count; index++)
        {
            var windowIndex = index;
            var window = _personalProfileAvailabilityWindowDraft[windowIndex];
            var content = new StackPanel();

            var header = new Grid();
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            header.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            header.Children.Add(new TextBlock
            {
                Text = $"时间段 {windowIndex + 1}",
                Foreground = FindBrush("PrimaryTextBrush", Brushes.White),
                FontSize = 11,
                FontWeight = FontWeights.SemiBold,
                VerticalAlignment = VerticalAlignment.Center
            });
            var removeButton = new Button
            {
                Content = "移除",
                Height = 24,
                MinWidth = 52,
                IsEnabled = _isPersonalProfileEditMode,
                Style = TryFindResource("SecondaryButton") as Style
            };
            removeButton.Click += (_, _) =>
            {
                if (windowIndex >= _personalProfileAvailabilityWindowDraft.Count)
                {
                    return;
                }

                _personalProfileAvailabilityWindowDraft.RemoveAt(windowIndex);
                RenderPersonalProfileAvailabilityWindows();
                PersonalProfileEditorChanged(removeButton, new RoutedEventArgs());
            };
            Grid.SetColumn(removeButton, 1);
            header.Children.Add(removeButton);
            content.Children.Add(header);

            var daysPanel = new WrapPanel { Margin = new Thickness(0, 6, 0, 6) };
            foreach (var day in orderedDays)
            {
                var dayValue = day.Value;
                var dayCheck = new CheckBox
                {
                    Content = day.Label,
                    IsChecked = window.Days.Contains(dayValue),
                    IsEnabled = _isPersonalProfileEditMode,
                    Margin = new Thickness(0, 0, 9, 3),
                    VerticalAlignment = VerticalAlignment.Center
                };
                dayCheck.Checked += (_, _) => UpdatePersonalProfileAvailabilityDays(windowIndex, dayValue, true, dayCheck);
                dayCheck.Unchecked += (_, _) => UpdatePersonalProfileAvailabilityDays(windowIndex, dayValue, false, dayCheck);
                daysPanel.Children.Add(dayCheck);
            }
            content.Children.Add(daysPanel);

            var timeRow = new Grid();
            timeRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            timeRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(116) });
            timeRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            timeRow.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(116) });
            timeRow.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            var startLabel = new TextBlock
            {
                Text = "开始",
                Foreground = FindBrush("SecondaryTextBrush", Brushes.LightSlateGray),
                FontSize = 10,
                VerticalAlignment = VerticalAlignment.Center
            };
            timeRow.Children.Add(startLabel);
            var startBox = CreatePersonalProfileAvailabilityTimeBox(window.StartTime);
            Grid.SetColumn(startBox, 1);
            timeRow.Children.Add(startBox);
            var endLabel = new TextBlock
            {
                Text = "结束",
                Foreground = FindBrush("SecondaryTextBrush", Brushes.LightSlateGray),
                FontSize = 10,
                Margin = new Thickness(9, 0, 7, 0),
                VerticalAlignment = VerticalAlignment.Center
            };
            Grid.SetColumn(endLabel, 2);
            timeRow.Children.Add(endLabel);
            var endBox = CreatePersonalProfileAvailabilityTimeBox(window.EndTime);
            Grid.SetColumn(endBox, 3);
            timeRow.Children.Add(endBox);
            var nextDayText = new TextBlock
            {
                Text = "次日结束",
                Foreground = FindBrush("StatusWarningBrush", Brushes.Goldenrod),
                FontSize = 9,
                FontWeight = FontWeights.SemiBold,
                Margin = new Thickness(9, 0, 0, 0),
                VerticalAlignment = VerticalAlignment.Center,
                Visibility = IsPersonalProfileAvailabilityNextDay(window.StartTime, window.EndTime)
                    ? Visibility.Visible
                    : Visibility.Collapsed
            };
            Grid.SetColumn(nextDayText, 4);
            timeRow.Children.Add(nextDayText);
            startBox.SelectionChanged += (_, _) => UpdatePersonalProfileAvailabilityTime(
                windowIndex,
                startBox.SelectedItem as string,
                null,
                startBox);
            endBox.SelectionChanged += (_, _) => UpdatePersonalProfileAvailabilityTime(
                windowIndex,
                null,
                endBox.SelectedItem as string,
                endBox);
            content.Children.Add(timeRow);

            PersonalProfileAvailabilityWindowsPanel.Children.Add(new Border
            {
                Background = new SolidColorBrush(Color.FromRgb(11, 34, 48)),
                BorderBrush = new SolidColorBrush(Color.FromRgb(23, 52, 71)),
                BorderThickness = new Thickness(1),
                Padding = new Thickness(8, 7, 8, 7),
                Margin = new Thickness(0, 0, 0, 6),
                Child = content
            });
        }

        RefreshPersonalProfileOnlineTimeEditorState();
    }

    private ComboBox CreatePersonalProfileAvailabilityTimeBox(string selectedTime) => new()
    {
        ItemsSource = PersonalProfileTimeOptions,
        SelectedItem = PersonalProfileTimeOptions.Contains(selectedTime) ? selectedTime : "19:00",
        Height = 28,
        IsEnabled = _isPersonalProfileEditMode
    };

    private void UpdatePersonalProfileAvailabilityDays(int index, int day, bool isSelected, object sender)
    {
        if (_isUpdatingPersonalProfileEditor || index >= _personalProfileAvailabilityWindowDraft.Count)
        {
            return;
        }

        var current = _personalProfileAvailabilityWindowDraft[index];
        var days = current.Days.ToHashSet();
        if (isSelected)
        {
            days.Add(day);
        }
        else
        {
            days.Remove(day);
        }

        _personalProfileAvailabilityWindowDraft[index] = current with { Days = [.. days.Order()] };
        PersonalProfileEditorChanged(sender, new RoutedEventArgs());
    }

    private void UpdatePersonalProfileAvailabilityTime(
        int index,
        string? startTime,
        string? endTime,
        object sender)
    {
        if (_isUpdatingPersonalProfileEditor || index >= _personalProfileAvailabilityWindowDraft.Count)
        {
            return;
        }

        var current = _personalProfileAvailabilityWindowDraft[index];
        _personalProfileAvailabilityWindowDraft[index] = current with
        {
            StartTime = startTime ?? current.StartTime,
            EndTime = endTime ?? current.EndTime
        };
        RenderPersonalProfileAvailabilityWindows();
        PersonalProfileEditorChanged(sender, new RoutedEventArgs());
    }

    private static (int Value, string Label)[] GetPersonalProfileDayOrder()
    {
        (int Value, string Label)[] days =
        [
            (0, "周日"),
            (1, "周一"),
            (2, "周二"),
            (3, "周三"),
            (4, "周四"),
            (5, "周五"),
            (6, "周六")
        ];
        return CultureInfo.CurrentCulture.DateTimeFormat.FirstDayOfWeek == DayOfWeek.Sunday
            ? days
            : [.. days.Skip(1), days[0]];
    }

    private static bool IsPersonalProfileAvailabilityNextDay(string startTime, string endTime) =>
        TimeOnly.TryParseExact(startTime, "HH:mm", CultureInfo.InvariantCulture, DateTimeStyles.None, out var start) &&
        TimeOnly.TryParseExact(endTime, "HH:mm", CultureInfo.InvariantCulture, DateTimeStyles.None, out var end) &&
        end <= start;

    private void PersonalProfileAddModuleButton_Click(object sender, RoutedEventArgs e)
    {
        if (!_isPersonalProfileEditMode)
        {
            return;
        }

        _personalProfilePendingInsertPosition = null;
        PersonalProfileModulePickerPopup.PlacementTarget = PersonalProfileAddModuleButton;
        PersonalProfileModulePickerPopup.Placement = PlacementMode.Bottom;
        PersonalProfileModulePickerPopup.HorizontalOffset = -420;
        PersonalProfileModulePickerPopup.VerticalOffset = 8;
        RefreshPersonalProfileModulePicker();
        PersonalProfileModulePickerPopup.IsOpen = true;
    }

    private void PersonalProfileEmptySlot_Click(object sender, RoutedEventArgs e)
    {
        if (!_isPersonalProfileEditMode || sender is not Button { Tag: int position } button)
        {
            return;
        }

        _personalProfilePendingInsertPosition = position;
        PersonalProfileModulePickerPopup.PlacementTarget = button;
        PersonalProfileModulePickerPopup.Placement = PlacementMode.MousePoint;
        PersonalProfileModulePickerPopup.HorizontalOffset = 8;
        PersonalProfileModulePickerPopup.VerticalOffset = 8;
        RefreshPersonalProfileModulePicker();
        PersonalProfileModulePickerPopup.IsOpen = true;
    }

    private void PersonalProfileModulePickerItem_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string id } || !_isPersonalProfileEditMode)
        {
            return;
        }

        var modules = _personalProfileSettings.Modules.OrderBy(module => module.Order).ToArray();
        var index = Array.FindIndex(modules, module => string.Equals(module.Id, id, StringComparison.Ordinal));
        if (index < 0 || modules[index].IsVisible)
        {
            return;
        }

        var occupied = GetPersonalProfileOccupiedCells(modules);
        if (occupied.All(value => value))
        {
            RefreshPersonalProfileEditorState("九宫格空间已用满，请先缩小或移除其他模块。", isWarning: true);
            return;
        }

        var position = _personalProfilePendingInsertPosition is int requestedPosition &&
                       requestedPosition >= 0 && requestedPosition < occupied.Length &&
                       !occupied[requestedPosition]
            ? requestedPosition
            : FindFirstPersonalProfileModulePosition(occupied, modules[index].Span);
        var span = _personalProfilePendingInsertPosition.HasValue
            ? 1
            : GetPersonalProfileFittingSpan(occupied, position, modules[index].Span);
        if (position < 0 || span <= 0)
        {
            position = Array.FindIndex(occupied, value => !value);
            span = 1;
        }

        var visibleModules = modules
            .Where(module => module.IsVisible && !IsFixedPersonalProfileModule(module.Id))
            .OrderBy(module => module.Order)
            .ToList();
        var insertIndex = _personalProfilePendingInsertPosition.HasValue
            ? visibleModules.Count(module => module.Position < position)
            : visibleModules.Count;
        visibleModules.Insert(Math.Clamp(insertIndex, 0, visibleModules.Count), modules[index] with
        {
            IsVisible = true,
            Span = span,
            Position = position
        });
        var hiddenModules = modules
            .Where(module => !module.IsVisible && !string.Equals(module.Id, id, StringComparison.Ordinal))
            .ToArray();
        _personalProfileSettings = _personalProfileSettings with
        {
            Modules = visibleModules
                .Concat(hiddenModules)
                .Select((module, order) => module with { Order = order })
                .ToArray()
        };
        _personalProfilePendingInsertPosition = null;
        PersonalProfileModulePickerPopup.IsOpen = false;
        MarkPersonalProfileDirty();
        ApplyPersonalProfileModuleLayout();
    }

    private void PersonalProfileModuleSize_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string tag } button || !_isPersonalProfileEditMode)
        {
            return;
        }

        var id = ParsePersonalProfileModuleActionTag(tag, "size");
        if (!_personalProfileSettings.Modules.Any(module => string.Equals(module.Id, id, StringComparison.Ordinal) && module.IsVisible))
        {
            return;
        }

        _personalProfileSizeModuleId = id;
        PersonalProfileModuleSizePopup.PlacementTarget = button;
        RefreshPersonalProfileModuleSizePicker();
        PersonalProfileModuleSizePopup.IsOpen = true;
    }

    private void PersonalProfileModuleSizeOption_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string spanText } ||
            !int.TryParse(spanText, NumberStyles.None, CultureInfo.InvariantCulture, out var requestedSpan) ||
            string.IsNullOrWhiteSpace(_personalProfileSizeModuleId))
        {
            return;
        }

        var modules = _personalProfileSettings.Modules.OrderBy(module => module.Order).ToArray();
        var index = Array.FindIndex(modules, module => string.Equals(module.Id, _personalProfileSizeModuleId, StringComparison.Ordinal));
        if (index < 0)
        {
            return;
        }

        requestedSpan = PersonalProfileModuleConstraints.NormalizeSpan(modules[index].Id, requestedSpan);
        var occupied = GetPersonalProfileOccupiedCells(modules, modules[index].Id);
        var position = CanPlacePersonalProfileModule(occupied, modules[index].Position, requestedSpan)
            ? modules[index].Position
            : FindFirstPersonalProfileModulePosition(occupied, requestedSpan);
        if (position < 0)
        {
            RefreshPersonalProfileEditorState("九宫格剩余空间不足，请先缩小或移除其他模块。", isWarning: true);
            return;
        }

        modules[index] = modules[index] with { Span = requestedSpan, Position = position };
        _personalProfileSettings = _personalProfileSettings with { Modules = modules };
        PersonalProfileModuleSizePopup.IsOpen = false;
        MarkPersonalProfileDirty();
        ApplyPersonalProfileModuleLayout();
    }

    private void RefreshPersonalProfileModuleSizePicker()
    {
        var module = _personalProfileSettings.Modules
            .FirstOrDefault(module => string.Equals(module.Id, _personalProfileSizeModuleId, StringComparison.Ordinal));
        var currentSpan = PersonalProfileModuleConstraints.NormalizeSpan(module?.Id, module?.Span ?? 1);
        var maximumSpan = PersonalProfileModuleConstraints.GetMaximumSpan(module?.Id);
        foreach (var button in new[] { PersonalProfileModuleSizeOneButton, PersonalProfileModuleSizeTwoButton, PersonalProfileModuleSizeThreeButton })
        {
            var span = int.TryParse(button.Tag as string, out var value) ? value : 1;
            button.Visibility = span <= maximumSpan ? Visibility.Visible : Visibility.Collapsed;
            button.IsEnabled = span != currentSpan;
            button.Opacity = span == currentSpan ? 0.55 : 1;
        }
    }

    private void PersonalProfileModuleVisibility_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string tag })
        {
            return;
        }

        var id = ParsePersonalProfileModuleActionTag(tag, "visibility");
        var modules = _personalProfileSettings.Modules.ToArray();
        var index = Array.FindIndex(modules, module => string.Equals(module.Id, id, StringComparison.Ordinal));
        if (index < 0)
        {
            return;
        }

        modules[index] = modules[index] with { IsVisible = false, Position = -1 };
        _personalProfileSettings = _personalProfileSettings with { Modules = modules };
        MarkPersonalProfileDirty();
        ApplyPersonalProfileModuleLayout();
    }

    private void PersonalProfileModule_PreviewMouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (!_isPersonalProfileEditMode || sender is not Border card || IsPersonalProfileInteractiveSource(e.OriginalSource as DependencyObject))
        {
            _personalProfileDragSource = null;
            return;
        }

        _personalProfileDragSource = card;
        _personalProfileDragStart = e.GetPosition(PersonalProfileModuleGrid);
    }

    private void PersonalProfileModule_PreviewMouseMove(object sender, MouseEventArgs e)
    {
        if (!_isPersonalProfileEditMode || e.LeftButton != MouseButtonState.Pressed ||
            _personalProfileDragSource is not { Tag: string id } source)
        {
            return;
        }

        var current = e.GetPosition(PersonalProfileModuleGrid);
        if (Math.Abs(current.X - _personalProfileDragStart.X) < SystemParameters.MinimumHorizontalDragDistance &&
            Math.Abs(current.Y - _personalProfileDragStart.Y) < SystemParameters.MinimumVerticalDragDistance)
        {
            return;
        }

        source.Opacity = 0.58;
        try
        {
            _personalProfileDragBaseModules = _personalProfileSettings.Modules.ToArray();
            _personalProfileDragPreviewModules = _personalProfileDragBaseModules;
            _personalProfileDragPreviewPosition = _personalProfileDragBaseModules
                .FirstOrDefault(module => string.Equals(module.Id, id, StringComparison.Ordinal))?.Position;
            var data = new DataObject(PersonalProfileModuleDragFormat, id);
            DragDrop.DoDragDrop(source, data, DragDropEffects.Move);
        }
        finally
        {
            ClearPersonalProfileDragTarget();
            _personalProfileDragBaseModules = null;
            _personalProfileDragPreviewModules = null;
            _personalProfileDragPreviewPosition = null;
            _personalProfileDragSource = null;
            ApplyPersonalProfileModuleLayout();
        }
    }

    private void PersonalProfileModuleGrid_DragOver(object sender, DragEventArgs e)
    {
        if (!_isPersonalProfileEditMode ||
            e.Data.GetData(PersonalProfileModuleDragFormat) is not string sourceId ||
            _personalProfileDragBaseModules is null)
        {
            e.Effects = DragDropEffects.None;
            e.Handled = true;
            return;
        }

        var targetPosition = GetPersonalProfileDropPosition(e.GetPosition(PersonalProfileModuleGrid));
        PreviewPersonalProfileModuleMove(sourceId, targetPosition);
        e.Effects = DragDropEffects.Move;
        e.Handled = true;
    }

    private void PersonalProfileModule_DragEnter(object sender, DragEventArgs e)
    {
        if (!_isPersonalProfileEditMode || sender is not Border target || target == _personalProfileDragSource ||
            !e.Data.GetDataPresent(PersonalProfileModuleDragFormat))
        {
            e.Effects = DragDropEffects.None;
            return;
        }

        ClearPersonalProfileDragTarget();
        _personalProfileDragTarget = target;
        target.BorderBrush = FindBrush("AccentBrush", new SolidColorBrush(Color.FromRgb(41, 175, 255)));
        target.BorderThickness = new Thickness(2);
        e.Effects = DragDropEffects.Move;
        e.Handled = true;
    }

    private void PersonalProfileModule_DragLeave(object sender, DragEventArgs e)
    {
        if (sender == _personalProfileDragTarget)
        {
            ClearPersonalProfileDragTarget();
        }
    }

    private void PersonalProfileModule_Drop(object sender, DragEventArgs e)
    {
        if (!_isPersonalProfileEditMode || sender is not Border { Tag: string targetId } ||
            e.Data.GetData(PersonalProfileModuleDragFormat) is not string sourceId ||
            string.Equals(sourceId, targetId, StringComparison.Ordinal))
        {
            ClearPersonalProfileDragTarget();
            return;
        }

        var target = (_personalProfileDragPreviewModules ?? _personalProfileSettings.Modules).FirstOrDefault(module =>
            module.IsVisible && string.Equals(module.Id, targetId, StringComparison.Ordinal));
        CommitPersonalProfileModuleMove(sourceId, target?.Position ??
                                                  GetPersonalProfileDropPosition(e.GetPosition(PersonalProfileModuleGrid)));

        e.Handled = true;
    }

    private void PersonalProfileModuleGrid_Drop(object sender, DragEventArgs e)
    {
        if (!_isPersonalProfileEditMode || e.Handled ||
            e.Data.GetData(PersonalProfileModuleDragFormat) is not string sourceId)
        {
            return;
        }

        CommitPersonalProfileModuleMove(
            sourceId,
            GetPersonalProfileDropPosition(e.GetPosition(PersonalProfileModuleGrid)));
        e.Handled = true;
    }

    private void PersonalProfileEmptySlot_DragOver(object sender, DragEventArgs e)
    {
        if (!_isPersonalProfileEditMode || !e.Data.GetDataPresent(PersonalProfileModuleDragFormat))
        {
            e.Effects = DragDropEffects.None;
            return;
        }

        e.Effects = DragDropEffects.Move;
        e.Handled = true;
    }

    private void PersonalProfileEmptySlot_Drop(object sender, DragEventArgs e)
    {
        if (!_isPersonalProfileEditMode || sender is not Button { Tag: int position } ||
            e.Data.GetData(PersonalProfileModuleDragFormat) is not string sourceId)
        {
            return;
        }

        CommitPersonalProfileModuleMove(sourceId, position);
        e.Handled = true;
    }

    private void PreviewPersonalProfileModuleMove(string sourceId, int targetPosition)
    {
        if (_personalProfileDragBaseModules is null || _personalProfileDragPreviewPosition == targetPosition)
        {
            return;
        }

        _personalProfileDragPreviewPosition = targetPosition;
        _personalProfileDragPreviewModules = PersonalProfileModuleLayout.Move(
            _personalProfileDragBaseModules,
            sourceId,
            targetPosition);
        ApplyPersonalProfileModuleLayout();
        PersonalProfileModuleGrid.UpdateLayout();
    }

    private void CommitPersonalProfileModuleMove(string sourceId, int targetPosition)
    {
        var baseModules = _personalProfileDragBaseModules ?? _personalProfileSettings.Modules;
        var modules = _personalProfileDragPreviewModules is not null &&
                      _personalProfileDragPreviewPosition == targetPosition
            ? _personalProfileDragPreviewModules
            : PersonalProfileModuleLayout.Move(baseModules, sourceId, targetPosition);
        if (!PersonalProfileModuleLayout.HasSameLayout(baseModules, modules))
        {
            _personalProfileSettings = _personalProfileSettings with { Modules = modules };
            MarkPersonalProfileDirty();
        }

        _personalProfileDragBaseModules = _personalProfileSettings.Modules.ToArray();
        _personalProfileDragPreviewModules = _personalProfileDragBaseModules;
        ApplyPersonalProfileModuleLayout();
    }

    private int GetPersonalProfileDropPosition(Point point)
    {
        var column = GetPersonalProfileGridAxisIndex(
            point.X,
            PersonalProfileModuleGrid.ColumnDefinitions.Select(definition => definition.ActualWidth));
        var row = GetPersonalProfileGridAxisIndex(
            point.Y,
            PersonalProfileModuleGrid.RowDefinitions.Select(definition => definition.ActualHeight));
        return (row * 3) + column;
    }

    private static int GetPersonalProfileGridAxisIndex(double coordinate, IEnumerable<double> lengths)
    {
        var offset = 0d;
        var index = 0;
        foreach (var length in lengths)
        {
            if (coordinate < offset + length)
            {
                return index;
            }

            offset += length;
            index++;
        }

        return Math.Max(0, index - 1);
    }

    private void ClearPersonalProfileDragTarget()
    {
        if (_personalProfileDragTarget is null)
        {
            return;
        }

        _personalProfileDragTarget.BorderBrush = FindBrush("PanelBorderBrush", new SolidColorBrush(Color.FromRgb(23, 52, 71)));
        _personalProfileDragTarget.BorderThickness = new Thickness(1);
        _personalProfileDragTarget = null;
    }

    private static bool IsPersonalProfileInteractiveSource(DependencyObject? source)
    {
        for (var current = source; current is not null; current = VisualTreeHelper.GetParent(current))
        {
            if (current is ButtonBase or TextBox or ComboBox)
            {
                return true;
            }

            if (current is Border { Tag: string })
            {
                break;
            }
        }

        return false;
    }

    private void MarkPersonalProfileDirty()
    {
        _isPersonalProfileDirty = true;
        RefreshPersonalProfileEditorState();
    }

    private void RefreshPersonalProfileContent()
    {
        if (PersonalProfileOnlineTimeText is null)
        {
            return;
        }

        PersonalProfileOnlineTimeText.Text = PersonalProfileAvailabilityPresentation.FormatSummary(
            _personalProfileSettings,
            GetPersonalProfilePresentationState().ViewerMode);
        PersonalProfileAvailabilityTimeZoneText.Text =
            $"所在时区：{FormatPersonalProfileAvailabilityTimeZone(_personalProfileSettings.AvailabilityTimeZoneId)}";
        PersonalProfileActivityRhythmText.Text = _personalProfileSettings.ActivityRhythm;
        PersonalProfileIntroductionText.Text = string.IsNullOrWhiteSpace(_personalProfileSettings.Introduction)
            ? "添加个人介绍"
            : _personalProfileSettings.Introduction.Trim();
        RefreshPersonalProfileHeaderIdentity();
        RefreshPersonalProfileSkilledRolesDisplay();
        RefreshPersonalProfilePlayStyleTagDisplay(
            PersonalProfileSupportCapabilitiesPanel,
            _personalProfileSettings.SupportCapabilities,
            "尚未选择支援能力",
            "#29AFFF");
        RefreshPersonalProfilePlayStyleTagDisplay(
            PersonalProfileParticipationInterestsPanel,
            _personalProfileSettings.ParticipationInterests,
            "尚未选择参与偏好",
            "#29AFFF");
        RefreshPersonalProfileFavoriteShips();
        RefreshPersonalProfileHangarSummary();
        RefreshPersonalProfileGameplayStatistics();
        ApplyPersonalProfileModuleLayout();
        RefreshPersonalProfileAccessState();
    }

    private void RefreshPersonalProfilePlayStyleTagDisplay(
        WrapPanel panel,
        IEnumerable<string>? values,
        string emptyCopy,
        string accentHex)
    {
        panel.Children.Clear();
        var normalized = PersonalProfilePlayStyleCatalog.NormalizeSelection(values);
        panel.ToolTip = normalized.Length > 0 ? string.Join("、", normalized) : null;
        if (normalized.Length == 0)
        {
            panel.Children.Add(new TextBlock
            {
                Text = emptyCopy,
                Foreground = FindBrush("MutedTextBrush", Brushes.LightSlateGray),
                FontSize = 10,
                VerticalAlignment = VerticalAlignment.Center
            });
            return;
        }

        foreach (var value in normalized)
        {
            panel.Children.Add(CreatePersonalProfilePlayStyleDisplayChip(value, accentHex));
        }
    }

    private Border CreatePersonalProfilePlayStyleDisplayChip(string value, string accentHex) =>
        new()
        {
            MinHeight = 22,
            Margin = new Thickness(0, 0, 5, 1),
            Padding = new Thickness(7, 2, 7, 2),
            Background = BrushFromHex(accentHex, 0.10),
            BorderBrush = BrushFromHex(accentHex, 0.58),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(2),
            Child = new TextBlock
            {
                Text = value,
                Foreground = BrushFromHex(accentHex),
                FontSize = 9,
                VerticalAlignment = VerticalAlignment.Center
            }
        };

    private void RefreshPersonalProfileAccessState()
    {
        if (PersonalProfileVisibilityBadge is null)
        {
            return;
        }

        var presentation = GetPersonalProfilePresentationState();

        if (PersonalProfileOnlineTimeText is not null)
        {
            PersonalProfileOnlineTimeText.Text = PersonalProfileAvailabilityPresentation.FormatSummary(
                _personalProfileSettings,
                presentation.ViewerMode);
        }

        PersonalProfileVisibilityText.Text = _personalProfileSettings.IsProfilePublic
            ? "公开主页"
            : "仅自己可见";
        PersonalProfileVisibilityText.Foreground = _personalProfileSettings.IsProfilePublic
            ? FindBrush("StatusSuccessBrush", Brushes.MediumSeaGreen)
            : FindBrush("MutedTextBrush", Brushes.SlateGray);
        PersonalProfileVisibilityDot.Fill = _personalProfileSettings.IsProfilePublic
            ? FindBrush("StatusSuccessBrush", Brushes.MediumSeaGreen)
            : FindBrush("MutedTextBrush", Brushes.SlateGray);

        PersonalProfileVisibilityBadge.Visibility = presentation.ShowOwnerControls
            ? Visibility.Visible
            : Visibility.Collapsed;
        PersonalProfileVisibilityEditorPanel.Visibility = presentation.ShowVisibilityEditor
            ? Visibility.Visible
            : Visibility.Collapsed;
        PersonalProfileScanHangarButton.Visibility = presentation.ShowOwnerControls && !_isPersonalProfileEditMode
            ? Visibility.Visible
            : Visibility.Collapsed;
        RefreshPersonalProfileFriendAction();
        PersonalProfileEditButton.Visibility = presentation.ShowOwnerControls
            ? Visibility.Visible
            : Visibility.Collapsed;
        PersonalProfilePreviewButton.Visibility = presentation.ShowOwnerControls
            ? Visibility.Visible
            : Visibility.Collapsed;
        PersonalProfilePreviewBanner.Visibility = presentation.ShowVisitorPreviewBanner
            ? Visibility.Visible
            : Visibility.Collapsed;
        RefreshPersonalProfileVisitorChrome();

        PersonalProfileFixedInfoPanel.Visibility = presentation.ShowFixedInformation
            ? Visibility.Visible
            : Visibility.Collapsed;
        PersonalProfileModuleGrid.Visibility = presentation.ShowModules
            ? Visibility.Visible
            : Visibility.Collapsed;
        PersonalProfilePrivatePreviewPanel.Visibility = presentation.ShowPrivateVisitorState
            ? Visibility.Visible
            : Visibility.Collapsed;
        PersonalProfileOwnerIdentityBadgesPanel.Visibility = presentation.ShowIdentityDetails
            ? Visibility.Visible
            : Visibility.Collapsed;
        PersonalProfileIntroductionSummaryPanel.Visibility = presentation.ShowIdentityDetails &&
                                                               (!presentation.IsVisitor ||
                                                                !string.IsNullOrWhiteSpace(_personalProfileSettings.Introduction))
            ? Visibility.Visible
            : Visibility.Collapsed;
        PersonalProfileOwnerSummaryPanel.Visibility = presentation.ShowIdentityDetails
            ? Visibility.Visible
            : Visibility.Collapsed;
    }

    private PersonalProfilePresentationState GetPersonalProfilePresentationState() =>
        PersonalProfilePresentationPolicy.Build(
            _isPersonalProfilePublicPreviewMode || _isPersonalProfileVisitorMode
                ? PersonalProfileViewerMode.Visitor
                : PersonalProfileViewerMode.Owner,
            _isPersonalProfileEditMode,
            _personalProfileSettings.IsProfilePublic,
            showVisitorPreviewBanner: _isPersonalProfilePublicPreviewMode || _isPersonalProfileVisitorMode);

    private IReadOnlyList<OwnedShipRecord> GetPersonalProfileDisplayOwnedShips()
    {
        if (!_isPersonalProfileVisitorMode)
        {
            return _ownedShips.ToArray();
        }

        if (_personalProfileVisitorDocument?.Hangar is { } hangar)
        {
            return (hangar.Ships ?? [])
                .Where(ship => !string.IsNullOrWhiteSpace(ship.Code))
                .Select(ship => new OwnedShipRecord(
                    ship.Code,
                    string.IsNullOrWhiteSpace(ship.DisplayName) ? ship.Code : ship.DisplayName,
                    "PublicProfile",
                    ship.ImportedAt,
                    ship.ImportedAt,
                    ship.SyncedAt))
                .ToArray();
        }

        return _personalProfileVisitorFallbackShips;
    }

    private string FormatPersonalProfileHangarTotalValue(IEnumerable<OwnedShipRecord> ships)
    {
        var pricedShips = ships
            .Select(ship => ShipCatalog.Find(ship.Code, ship.DisplayName))
            .Where(catalog => catalog is not null && TryReadCatalogPrice(catalog.PriceUsd, out _))
            .Select(catalog =>
            {
                TryReadCatalogPrice(catalog!.PriceUsd, out var price);
                return price;
            })
            .ToArray();

        return pricedShips.Length == 0
            ? "未公布"
            : FormatFleetShipValue(pricedShips.Sum());
    }

    private void RefreshPersonalProfileVisitorChrome()
    {
        PersonalProfileVisitorBackButton.Visibility = _isPersonalProfileVisitorMode
            ? Visibility.Visible
            : Visibility.Collapsed;

        if (_isPersonalProfileVisitorMode)
        {
            var callsign = _personalProfileVisitorDocument?.Identity.Callsign ??
                           _personalProfileVisitorTarget?.Callsign ??
                           _personalProfileVisitorTarget?.Name ??
                           "舰队成员";
            PersonalProfilePageTitleText.Text = "公开资料";
            PersonalProfilePageDescriptionText.Text = $"查看 {callsign} 愿意公开的身份、活动节奏与个人模块。";
            PersonalProfilePreviewTitleText.Text = $"正在查看 {callsign}";
            PersonalProfilePreviewDescriptionText.Text = _personalProfileVisitorLoadState switch
            {
                PersonalProfileVisitorLoadState.Loading => "正在从服务器读取公开资料。",
                PersonalProfileVisitorLoadState.Loaded => "公开资料来自该成员最近一次保存的个人主页。",
                PersonalProfileVisitorLoadState.Unavailable => "连接暂时不可用，当前没有展示缓存资料。",
                _ => "该成员尚未公开个人主页，或资料已不存在。"
            };
            PersonalProfilePreviewExitButton.Content = "返回上一页";

            PersonalProfileVisitorRetryButton.Visibility = _personalProfileVisitorLoadState ==
                                                             PersonalProfileVisitorLoadState.Unavailable
                ? Visibility.Visible
                : Visibility.Collapsed;
            switch (_personalProfileVisitorLoadState)
            {
                case PersonalProfileVisitorLoadState.Loading:
                    PersonalProfilePrivateStateIconText.Text = "读";
                    PersonalProfilePrivateStateTitleText.Text = "正在读取公开资料";
                    PersonalProfilePrivateStateDescriptionText.Text = "资料加载完成后会在这里显示。";
                    break;
                case PersonalProfileVisitorLoadState.Unavailable:
                    PersonalProfilePrivateStateIconText.Text = "断";
                    PersonalProfilePrivateStateTitleText.Text = "暂时无法读取公开资料";
                    PersonalProfilePrivateStateDescriptionText.Text = "检查网络连接后重试，或稍后再打开该成员资料。";
                    break;
                default:
                    PersonalProfilePrivateStateIconText.Text = "私";
                    PersonalProfilePrivateStateTitleText.Text = "该用户未公开个人主页";
                    PersonalProfilePrivateStateDescriptionText.Text = "当前仅展示成员名册中已有的头像、呼号与游戏 ID。";
                    break;
            }

            return;
        }

        PersonalProfilePageTitleText.Text = "个人主页";
        PersonalProfilePageDescriptionText.Text = "展示你愿意公开的游戏资料。在线时间段可留空。";
        PersonalProfilePreviewTitleText.Text = "访客视角预览";
        PersonalProfilePreviewDescriptionText.Text = _personalProfileSettings.IsProfilePublic
            ? "这是其他用户查看你的个人主页时看到的内容。"
            : "你的主页当前未公开，其他用户只能看到基础身份信息。";
        PersonalProfilePreviewExitButton.Content = "返回我的主页";
        PersonalProfileVisitorRetryButton.Visibility = Visibility.Collapsed;
        PersonalProfilePrivateStateIconText.Text = "私";
        PersonalProfilePrivateStateTitleText.Text = "该用户未公开个人主页";
        PersonalProfilePrivateStateDescriptionText.Text = "当前仅展示头像、呼号与游戏 ID。";
    }

    private void RefreshPersonalProfileHeaderIdentity()
    {
        if (PersonalProfileCallsignText is null)
        {
            return;
        }

        if (!_isPersonalProfileVisitorMode)
        {
            ApplyPresenceVisibilityModeToProfileControl();
            PersonalProfileCallsignText.Text = !string.IsNullOrWhiteSpace(_callsign)
                ? _callsign!
                : GetPersonalDisplayName();
            PersonalProfileGameIdText.Text = string.IsNullOrWhiteSpace(_localPlayer) ? "未绑定游戏 ID" : _localPlayer;
            PersonalProfileAvatarDisplayImage.Source = AvatarImage.Source;
            PersonalProfileStatusText.Text = ProfileStatusText?.Text ?? "离线";
            RefreshPersonalProfilePresenceIntent();
            return;
        }

        ApplyPresenceVisibilityModeToProfileControl();
        var identity = _personalProfileVisitorDocument?.Identity;
        var target = _personalProfileVisitorTarget;
        PersonalProfileCallsignText.Text = !string.IsNullOrWhiteSpace(identity?.Callsign)
            ? identity!.Callsign
            : target?.Callsign ?? target?.Name ?? "未知成员";
        PersonalProfileGameIdText.Text = !string.IsNullOrWhiteSpace(identity?.GameId)
            ? identity!.GameId
            : target?.Name ?? "未知游戏 ID";
        PersonalProfileAvatarDisplayImage.Source = TryCreateImageSource(target?.AvatarPath);
        PersonalProfileStatusText.Text = PlayerPresencePresentation.Format(
            PlayerPresencePresentation.ResolveShared(target?.LiveStatus, target?.Status),
            _language);
        RefreshPersonalProfilePresenceIntent();

        var affiliation = _personalProfileVisitorDocument?.FleetAffiliation;
        if (affiliation is null)
        {
            PersonalHeaderFleetNameText.Text = "未公开舰队身份";
            PersonalHeaderFleetCodeText.Text = "";
            PersonalHeaderFleetRoleText.Text = "";
            PersonalHeaderFleetLogoImage.Source = null;
            return;
        }

        PersonalHeaderFleetNameText.Text = affiliation.FleetName;
        PersonalHeaderFleetCodeText.Text = affiliation.FleetCode;
        PersonalHeaderFleetRoleText.Text = affiliation.PositionTitle;
        PersonalHeaderFleetRoleText.Foreground = BrushFromHex(affiliation.PositionColor);
        if (!affiliation.FleetCode.Equals(_fleetCode, StringComparison.OrdinalIgnoreCase))
        {
            PersonalHeaderFleetLogoImage.Source = null;
        }
    }

    private void RefreshPersonalProfilePresenceIntent()
    {
        if (PersonalProfilePresenceIntentBadge is null || PersonalProfilePresenceIntentText is null)
        {
            return;
        }

        var display = _isPersonalProfileVisitorMode && _personalProfileVisitorDocument is null
            ? null
            : PersonalProfilePresenceIntentCatalog.Format(_personalProfileSettings.PresenceIntent);
        PersonalProfilePresenceIntentText.Text = display ?? "";
        PersonalProfilePresenceIntentBadge.Visibility = !_isPersonalProfileEditMode && !string.IsNullOrWhiteSpace(display)
            ? Visibility.Visible
            : Visibility.Collapsed;
    }

    private void RefreshPersonalProfileFavoriteShips()
    {
        if (PersonalProfileFavoriteShipsContentPanel is null)
        {
            return;
        }

        PersonalProfileFavoriteShipsContentPanel.Children.Clear();
        PersonalProfileFavoriteShipsContentPanel.ColumnDefinitions.Clear();

        var span = PersonalProfileModuleConstraints.NormalizeSpan(
            "favorite-ships",
            _personalProfileSettings.Modules.FirstOrDefault(module => module.Id == "favorite-ships")?.Span ?? 1);
        var displayShips = GetPersonalProfileDisplayOwnedShips();
        var selectedShips = ResolvePersonalProfileFavoriteShips(
                _personalProfileSettings.FavoriteShipCodes,
                displayShips)
            .Take(span)
            .ToArray();
        if (selectedShips.Length == 0)
        {
            PersonalProfileFavoriteShipsContentPanel.Children.Add(new StackPanel
            {
                VerticalAlignment = VerticalAlignment.Center,
                Children =
                {
                    new TextBlock
                    {
                        Text = "尚未选择最爱舰船",
                        Foreground = FindBrush("PrimaryTextBrush", Brushes.AliceBlue),
                        FontWeight = FontWeights.SemiBold
                    },
                    new TextBlock
                    {
                        Text = _isPersonalProfileVisitorMode
                            ? "该用户尚未公开最爱舰船"
                            : displayShips.Count == 0 ? "读取个人机库后即可选择" : "编辑主页并选择你想展示的舰船",
                        Margin = new Thickness(0, 5, 0, 0),
                        Foreground = FindBrush("MutedTextBrush", Brushes.LightSlateGray),
                        FontSize = 10
                    }
                }
            });
            return;
        }

        for (var index = 0; index < selectedShips.Length; index++)
        {
            PersonalProfileFavoriteShipsContentPanel.ColumnDefinitions.Add(
                new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            var card = CreatePersonalProfileFavoriteShipDisplayCard(selectedShips[index]);
            card.Margin = new Thickness(index == 0 ? 0 : 4, 0, index == selectedShips.Length - 1 ? 0 : 4, 0);
            Grid.SetColumn(card, index);
            PersonalProfileFavoriteShipsContentPanel.Children.Add(card);
        }
    }

    private IReadOnlyList<(OwnedShipRecord Ship, ShipCatalogEntry? Catalog)> ResolvePersonalProfileFavoriteShips(
        IEnumerable<string>? codes,
        IReadOnlyCollection<OwnedShipRecord> ships)
    {
        var ownedByCode = ships
            .Where(ship => !string.IsNullOrWhiteSpace(ship.Code))
            .GroupBy(ship => ship.Code.Trim(), StringComparer.OrdinalIgnoreCase)
            .ToDictionary(group => group.Key, group => group.First(), StringComparer.OrdinalIgnoreCase);
        var result = new List<(OwnedShipRecord Ship, ShipCatalogEntry? Catalog)>();
        foreach (var code in (codes ?? []).Where(code => !string.IsNullOrWhiteSpace(code)).Take(3))
        {
            if (!ownedByCode.TryGetValue(code.Trim(), out var ship))
            {
                if (!_isPersonalProfileVisitorMode)
                {
                    continue;
                }

                var catalog = ShipCatalog.Find(code.Trim(), code.Trim());
                ship = new OwnedShipRecord(
                    code.Trim(),
                    catalog?.EnglishName ?? code.Trim(),
                    "PublicProfile",
                    DateTimeOffset.MinValue);
            }

            result.Add((ship, ShipCatalog.Find(ship.Code, ship.DisplayName)));
        }

        return result;
    }

    private Border CreatePersonalProfileFavoriteShipDisplayCard(
        (OwnedShipRecord Ship, ShipCatalogEntry? Catalog) favorite)
    {
        var card = new Border
        {
            Background = CreateSolidBrush("#0D2130"),
            BorderBrush = CreateSolidBrush("#24506A"),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(2),
            Padding = new Thickness(7),
            ClipToBounds = true
        };
        var content = new Grid();
        content.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(70) });
        content.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        content.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(82) });

        var imageFrame = new Border
        {
            Width = 64,
            Height = 64,
            HorizontalAlignment = HorizontalAlignment.Left,
            VerticalAlignment = VerticalAlignment.Center,
            Background = CreateSolidBrush("#07131D"),
            BorderBrush = CreateSolidBrush("#2B5F79"),
            BorderThickness = new Thickness(1),
            ClipToBounds = true
        };
        var imageSource = TryCreateImageSource(favorite.Catalog?.ImagePath);
        imageFrame.Child = imageSource is null
            ? new TextBlock
            {
                Text = "SHIP",
                HorizontalAlignment = HorizontalAlignment.Center,
                VerticalAlignment = VerticalAlignment.Center,
                Foreground = FindBrush("MutedTextBrush", Brushes.LightSlateGray),
                FontSize = 9,
                FontWeight = FontWeights.SemiBold
            }
            : new Image { Source = imageSource, Stretch = Stretch.UniformToFill };
        content.Children.Add(imageFrame);

        var displayName = favorite.Catalog?.DisplayName(_language);
        if (string.IsNullOrWhiteSpace(displayName))
        {
            displayName = string.IsNullOrWhiteSpace(favorite.Ship.DisplayName)
                ? favorite.Ship.Code
                : favorite.Ship.DisplayName;
        }

        var details = new StackPanel
        {
            Margin = new Thickness(8, 0, 0, 0),
            VerticalAlignment = VerticalAlignment.Center
        };
        details.Children.Add(new TextBlock
        {
            Text = displayName,
            Foreground = FindBrush("PrimaryTextBrush", Brushes.AliceBlue),
            FontWeight = FontWeights.SemiBold,
            TextTrimming = TextTrimming.CharacterEllipsis,
            ToolTip = displayName
        });
        var englishName = favorite.Catalog?.EnglishName;
        if (!string.IsNullOrWhiteSpace(englishName) &&
            !englishName.Equals(displayName, StringComparison.OrdinalIgnoreCase))
        {
            details.Children.Add(new TextBlock
            {
                Text = englishName,
                Margin = new Thickness(0, 3, 0, 0),
                Foreground = FindBrush("MutedTextBrush", Brushes.LightSlateGray),
                FontSize = 9,
                TextTrimming = TextTrimming.CharacterEllipsis,
                ToolTip = englishName
            });
        }

        var role = favorite.Catalog?.RoleDisplay(_language);
        if (!string.IsNullOrWhiteSpace(role))
        {
            details.Children.Add(new TextBlock
            {
                Text = role,
                Margin = new Thickness(0, 4, 0, 0),
                Foreground = FindBrush("AccentBrush", Brushes.DeepSkyBlue),
                FontSize = 9,
                TextTrimming = TextTrimming.CharacterEllipsis
            });
        }

        Grid.SetColumn(details, 1);
        content.Children.Add(details);

        var valueText = string.IsNullOrWhiteSpace(favorite.Catalog?.PriceUsd)
            ? "价值未知"
            : favorite.Catalog!.PriceDisplay;
        var sizeText = string.IsNullOrWhiteSpace(favorite.Catalog?.Spec)
            ? "尺寸未知"
            : favorite.Catalog!.Spec;
        var facts = new StackPanel
        {
            Margin = new Thickness(8, 0, 0, 0),
            VerticalAlignment = VerticalAlignment.Center,
            HorizontalAlignment = HorizontalAlignment.Right
        };
        facts.Children.Add(new TextBlock
        {
            Text = "舰船价值",
            HorizontalAlignment = HorizontalAlignment.Right,
            Foreground = FindBrush("MutedTextBrush", Brushes.LightSlateGray),
            FontSize = 9
        });
        facts.Children.Add(new TextBlock
        {
            Text = valueText,
            Margin = new Thickness(0, 2, 0, 0),
            HorizontalAlignment = HorizontalAlignment.Right,
            Foreground = FindBrush("AccentBrush", Brushes.DeepSkyBlue),
            FontSize = 11,
            FontWeight = FontWeights.SemiBold
        });
        facts.Children.Add(new TextBlock
        {
            Text = sizeText,
            Margin = new Thickness(0, 5, 0, 0),
            HorizontalAlignment = HorizontalAlignment.Right,
            Foreground = FindBrush("SecondaryTextBrush", Brushes.LightSteelBlue),
            FontSize = 9,
            TextTrimming = TextTrimming.CharacterEllipsis,
            ToolTip = sizeText
        });
        Grid.SetColumn(facts, 2);
        content.Children.Add(facts);
        card.Child = content;
        return card;
    }

    private void RefreshPersonalProfileHangarSummary()
    {
        if (PersonalProfileHangarShipCountText is null ||
            PersonalProfileHangarSummaryMetricsGrid is null)
        {
            return;
        }

        var displayShips = GetPersonalProfileDisplayOwnedShips();
        var totalCount = displayShips.Count;
        var latestSync = displayShips
            .Select(ship => ship.SyncedAt)
            .Where(value => value != default && value != DateTimeOffset.MinValue)
            .DefaultIfEmpty(DateTimeOffset.MinValue)
            .Max();
        var latestImportedAt = displayShips
            .Select(ship => ship.ImportedAt)
            .Where(value => value != default && value != DateTimeOffset.MinValue)
            .DefaultIfEmpty(DateTimeOffset.MinValue)
            .Max();

        PersonalProfileHangarShipCountText.Text = $"{totalCount} 艘";

        var categoryCounts = new[]
        {
            (Name: "战斗", Category: FleetShipRoleCategory.Combat),
            (Name: "运输", Category: FleetShipRoleCategory.Transport),
            (Name: "工业", Category: FleetShipRoleCategory.Industrial),
            (Name: "探索", Category: FleetShipRoleCategory.Exploration),
            (Name: "支援", Category: FleetShipRoleCategory.Support),
            (Name: "其他", Category: FleetShipRoleCategory.Utility)
        }
            .Select((item, index) => new
            {
                item.Name,
                Order = index,
                Count = displayShips.Count(ship => GetOwnedShipRoleCategory(ship) == item.Category)
            })
            .OrderByDescending(item => item.Count)
            .ThenBy(item => item.Order)
            .ToArray();
        var primaryCategory = categoryCounts.FirstOrDefault(item => item.Count > 0);
        var categoryCount = categoryCounts.Count(item => item.Count > 0);
        PersonalProfileHangarCategoryCountText.Text = $"{categoryCount} 类";
        PersonalProfileHangarPrimaryTypeText.Text = primaryCategory is null
            ? "暂无"
            : $"{primaryCategory.Name} {primaryCategory.Count}";

        PersonalProfileHangarTotalValueText.Text = FormatPersonalProfileHangarTotalValue(displayShips);
        BuildPersonalProfileShipTypeBar(
            PersonalProfileHangarTypePreviewBar,
            PersonalProfileHangarTypePreviewText,
            3,
            displayShips);

        var recentShip = displayShips
            .OrderByDescending(ship => ship.ImportedAt == default || ship.ImportedAt == DateTimeOffset.MinValue
                ? ship.AddedToDatabaseAt
                : ship.ImportedAt)
            .ThenBy(ship => ship.DisplayName, StringComparer.OrdinalIgnoreCase)
            .FirstOrDefault();
        if (recentShip is null)
        {
            PersonalProfileHangarRecentShipImage.Source = null;
            PersonalProfileHangarRecentShipImagePlaceholder.Visibility = Visibility.Visible;
            PersonalProfileHangarRecentShipNameText.Text = "暂无舰船";
            PersonalProfileHangarRecentShipEnglishNameText.Text = "读取机库后显示";
            PersonalProfileHangarRecentShipDateText.Text = "入库时间 -";
        }
        else
        {
            var recentCatalog = ShipCatalog.Find(recentShip.Code, recentShip.DisplayName);
            var recentImage = TryCreateImageSource(recentCatalog?.ImagePath);
            var recentImportedAt = recentShip.ImportedAt == default ||
                                   recentShip.ImportedAt == DateTimeOffset.MinValue
                ? recentShip.AddedToDatabaseAt
                : recentShip.ImportedAt;
            PersonalProfileHangarRecentShipImage.Source = recentImage;
            PersonalProfileHangarRecentShipImagePlaceholder.Visibility = recentImage is null
                ? Visibility.Visible
                : Visibility.Collapsed;
            PersonalProfileHangarRecentShipNameText.Text = recentCatalog?.DisplayName(_language) ?? recentShip.DisplayName;
            PersonalProfileHangarRecentShipEnglishNameText.Text = FormatFleetShipEnglishName(
                recentShip.Code,
                recentCatalog?.EnglishName);
            PersonalProfileHangarRecentShipDateText.Text = recentImportedAt == default ||
                                                             recentImportedAt == DateTimeOffset.MinValue
                ? "入库时间待同步"
                : $"入库 {recentImportedAt.ToLocalTime():yyyy-MM-dd}";
        }

        var span = PersonalProfileModuleConstraints.NormalizeSpan(
            "hangar-summary",
            _personalProfileSettings.Modules
                .FirstOrDefault(module => module.Id.Equals("hangar-summary", StringComparison.Ordinal))?.Span ?? 2);
        PersonalProfileHangarTypePreviewPanel.Visibility = span >= 2 ? Visibility.Visible : Visibility.Collapsed;
        PersonalProfileHangarTotalValuePanel.Visibility = Visibility.Visible;
        PersonalProfileHangarRecentShipPanel.Visibility = span >= 3
            ? Visibility.Visible
            : Visibility.Collapsed;
        PersonalProfileHangarSummaryMetricsGrid.ColumnDefinitions[0].Width = span == 1
            ? new GridLength(1.35, GridUnitType.Star)
            : new GridLength(1, GridUnitType.Star);
        PersonalProfileHangarSummaryMetricsGrid.ColumnDefinitions[1].Width = span >= 2
            ? new GridLength(1.6, GridUnitType.Star)
            : new GridLength(0);
        PersonalProfileHangarSummaryMetricsGrid.ColumnDefinitions[2].Width = span == 1
            ? new GridLength(0.65, GridUnitType.Star)
            : span == 2
                ? new GridLength(0.8, GridUnitType.Star)
                : new GridLength(0.9, GridUnitType.Star);
        PersonalProfileHangarSummaryMetricsGrid.ColumnDefinitions[3].Width = span >= 3
            ? new GridLength(1.25, GridUnitType.Star)
            : new GridLength(0);

        PersonalProfileHangarSummaryStatusText.Text = totalCount == 0
            ? "读取官网机库后，这里会显示你的舰船概况"
            : latestSync != DateTimeOffset.MinValue
                ? $"RSI 官网机库 · 最近同步 {latestSync.ToLocalTime():yyyy-MM-dd HH:mm}"
                : latestImportedAt != DateTimeOffset.MinValue
                    ? $"RSI 官网机库 · 最后入库 {latestImportedAt.ToLocalTime():yyyy-MM-dd}"
                    : "RSI 官网机库 · 等待同步";
    }

    private void RefreshPersonalProfileSkilledRolesDisplay()
    {
        if (PersonalProfileSkilledRolesContentPanel is null)
        {
            return;
        }

        PersonalProfileSkilledRolesContentPanel.Children.Clear();
        var roles = PersonalProfileRoleCatalog.NormalizeRoleIds(_personalProfileSettings.SkilledRoles)
            .Select(PersonalProfileRoleCatalog.FindRole)
            .Where(role => role is not null)
            .Cast<PersonalProfileRoleDefinition>()
            .ToArray();
        var span = PersonalProfileModuleConstraints.NormalizeSpan(
            "skilled-roles",
            _personalProfileSettings.Modules
                .FirstOrDefault(module => module.Id.Equals("skilled-roles", StringComparison.Ordinal))?.Span ?? 1);

        if (roles.Length == 0)
        {
            PersonalProfileSkilledRolesContentPanel.Children.Add(new TextBlock
            {
                Text = _isPersonalProfileEditMode ? "尚未设置，点击“编辑”选择岗位" : "尚未设置擅长岗位",
                Foreground = FindBrush("MutedTextBrush", Brushes.LightSlateGray),
                FontSize = 11,
                TextWrapping = TextWrapping.Wrap,
                VerticalAlignment = VerticalAlignment.Center
            });
            return;
        }

        var primaryRole = roles[0];
        var rolePanel = new WrapPanel
        {
            HorizontalAlignment = HorizontalAlignment.Left,
            VerticalAlignment = VerticalAlignment.Center
        };
        rolePanel.Children.Add(CreatePersonalProfilePrimaryRoleCard(primaryRole, span));
        foreach (var role in roles.Skip(1))
        {
            rolePanel.Children.Add(CreatePersonalProfileRoleChip(role));
        }

        PersonalProfileSkilledRolesContentPanel.Children.Add(rolePanel);
    }

    private Border CreatePersonalProfilePrimaryRoleCard(PersonalProfileRoleDefinition role, int span)
    {
        var category = PersonalProfileRoleCatalog.FindCategory(role.CategoryId);
        var accentHex = category?.AccentHex ?? "#29AFFF";
        var grid = new Grid();
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(4) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        grid.Children.Add(new Border
        {
            Background = BrushFromHex(accentHex),
            CornerRadius = new CornerRadius(2, 0, 0, 2)
        });

        var title = new TextBlock
        {
            Text = role.Name,
            Margin = new Thickness(9, 0, 8, 0),
            VerticalAlignment = VerticalAlignment.Center,
            Foreground = FindBrush("PrimaryTextBrush", Brushes.AliceBlue),
            FontSize = span == 1 ? 12 : 13,
            FontWeight = FontWeights.SemiBold,
            TextTrimming = TextTrimming.CharacterEllipsis,
            ToolTip = role.Description
        };
        Grid.SetColumn(title, 1);
        grid.Children.Add(title);

        var badge = new Border
        {
            Margin = new Thickness(0, 0, 8, 0),
            Padding = new Thickness(6, 2, 6, 2),
            VerticalAlignment = VerticalAlignment.Center,
            Background = BrushFromHex(accentHex, 0.16),
            BorderBrush = BrushFromHex(accentHex, 0.72),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(2),
            Child = new TextBlock
            {
                Text = "主岗位",
                Foreground = BrushFromHex(accentHex),
                FontSize = 9,
                FontWeight = FontWeights.SemiBold
            }
        };
        Grid.SetColumn(badge, 2);
        grid.Children.Add(badge);

        return new Border
        {
            MinHeight = span == 1 ? 34 : 36,
            Margin = new Thickness(0, 0, 6, 5),
            HorizontalAlignment = HorizontalAlignment.Left,
            Background = BrushFromHex(accentHex, 0.10),
            BorderBrush = BrushFromHex(accentHex, 0.64),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(2),
            Child = grid,
            ToolTip = $"{category?.Name ?? "岗位"} · {role.Description}"
        };
    }

    private Border CreatePersonalProfileRoleChip(PersonalProfileRoleDefinition role)
    {
        var category = PersonalProfileRoleCatalog.FindCategory(role.CategoryId);
        var accentHex = category?.AccentHex ?? "#29AFFF";
        return new Border
        {
            MinHeight = 25,
            Margin = new Thickness(0, 0, 6, 5),
            Padding = new Thickness(8, 3, 8, 3),
            Background = BrushFromHex(accentHex, 0.11),
            BorderBrush = BrushFromHex(accentHex, 0.58),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(2),
            ToolTip = $"{category?.Name ?? "岗位"} · {role.Description}",
            Child = new TextBlock
            {
                Text = role.Name,
                Foreground = FindBrush("PrimaryTextBrush", Brushes.AliceBlue),
                FontSize = 10,
                VerticalAlignment = VerticalAlignment.Center
            }
        };
    }

    private void PersonalProfileSkilledRolesEditButton_Click(object sender, RoutedEventArgs e)
    {
        if (!_isPersonalProfileEditMode)
        {
            return;
        }

        OpenPersonalProfileRoleSelector();
    }

    private void OpenPersonalProfileRoleSelector()
    {
        _personalProfileRoleDraftIds.Clear();
        _personalProfileRoleDraftIds.AddRange(PersonalProfileRoleCatalog.NormalizeRoleIds(_personalProfileSettings.SkilledRoles));
        ResetPersonalProfileRoleDetailEditors();
        if (PersonalProfileRoleCatalog.FindCategory(_personalProfileRoleActiveCategoryId) is null)
        {
            _personalProfileRoleActiveCategoryId = PersonalProfileRoleCatalog.Categories[0].Id;
        }

        UiMotion.HideStatus(PersonalProfileRoleUnsavedPrompt);
        UiMotion.ShowModal(PersonalProfileRoleSelectorOverlay, PersonalProfileRoleSelectorCard);
        SetPersonalProfileRoleSelectorStatus("选择岗位并补充参与偏好与支援能力。", isWarning: false);
        RenderPersonalProfileRoleSelector();
    }

    private void RenderPersonalProfileRoleSelector()
    {
        RenderPersonalProfileRoleCategories();
        RenderPersonalProfileRoleOptions();
        RenderPersonalProfileSelectedRoles();
        RenderPersonalProfilePlayStyleOptions();
        PersonalProfileRoleDraftCountText.Text = $"{_personalProfileRoleDraftIds.Count} / {PersonalProfileRoleCatalog.MaxSelected}";
    }

    private void RenderPersonalProfilePlayStyleOptions()
    {
        RenderPersonalProfilePlayStyleOptionGroup(
            PersonalProfileParticipationInterestOptionsPanel,
            PersonalProfilePlayStyleCatalog.ParticipationInterests,
            _personalProfileParticipationInterestDraft,
            PersonalProfileParticipationInterestOption_Click);
        RenderPersonalProfilePlayStyleOptionGroup(
            PersonalProfileSupportCapabilityOptionsPanel,
            PersonalProfilePlayStyleCatalog.SupportCapabilities,
            _personalProfileSupportCapabilityDraft,
            PersonalProfileSupportCapabilityOption_Click);
        PersonalProfileParticipationInterestCountText.Text =
            $"{_personalProfileParticipationInterestDraft.Count} / {PersonalProfilePlayStyleCatalog.MaximumSelectedPerGroup}";
        PersonalProfileSupportCapabilityCountText.Text =
            $"{_personalProfileSupportCapabilityDraft.Count} / {PersonalProfilePlayStyleCatalog.MaximumSelectedPerGroup}";
    }

    private void RenderPersonalProfilePlayStyleOptionGroup(
        WrapPanel panel,
        IReadOnlyCollection<string> catalog,
        IReadOnlyCollection<string> selectedValues,
        RoutedEventHandler clickHandler)
    {
        panel.Children.Clear();
        var options = catalog
            .Concat(selectedValues.Where(value => !catalog.Contains(value, StringComparer.OrdinalIgnoreCase)))
            .Distinct(StringComparer.OrdinalIgnoreCase);
        foreach (var value in options)
        {
            var isSelected = selectedValues.Contains(value, StringComparer.OrdinalIgnoreCase);
            var button = new Button
            {
                MinHeight = 27,
                Margin = new Thickness(0, 0, 6, 6),
                Padding = new Thickness(8, 2, 8, 2),
                Background = isSelected ? CreateSolidBrush("#123A52") : CreateSolidBrush("#0D1D29"),
                BorderBrush = isSelected ? CreateSolidBrush("#29AFFF") : CreateSolidBrush("#173447"),
                BorderThickness = new Thickness(1),
                Foreground = isSelected
                    ? CreateSolidBrush("#EEF8FF")
                    : FindBrush("MutedTextBrush", Brushes.LightSlateGray),
                FontSize = 10,
                Content = isSelected ? $"{value}  ×" : value,
                Tag = value,
                Cursor = Cursors.Hand,
                ToolTip = isSelected
                    ? $"取消选择{value}"
                    : $"选择{value}"
            };
            button.Click += clickHandler;
            panel.Children.Add(button);
        }
    }

    private void PersonalProfileParticipationInterestOption_Click(object sender, RoutedEventArgs e) =>
        TogglePersonalProfilePlayStyleOption(sender, _personalProfileParticipationInterestDraft, "参与偏好");

    private void PersonalProfileSupportCapabilityOption_Click(object sender, RoutedEventArgs e) =>
        TogglePersonalProfilePlayStyleOption(sender, _personalProfileSupportCapabilityDraft, "支援能力");

    private void TogglePersonalProfilePlayStyleOption(object sender, List<string> draft, string groupName)
    {
        if (sender is not Button { Tag: string value })
        {
            return;
        }

        var existingIndex = draft.FindIndex(item => item.Equals(value, StringComparison.OrdinalIgnoreCase));
        if (existingIndex >= 0)
        {
            draft.RemoveAt(existingIndex);
            SetPersonalProfileRoleSelectorStatus($"已取消{groupName}：{value}", isWarning: false);
        }
        else if (draft.Count >= PersonalProfilePlayStyleCatalog.MaximumSelectedPerGroup)
        {
            SetPersonalProfileRoleSelectorStatus(
                $"{groupName}最多选择 {PersonalProfilePlayStyleCatalog.MaximumSelectedPerGroup} 项。",
                isWarning: true);
            return;
        }
        else
        {
            draft.Add(value);
            SetPersonalProfileRoleSelectorStatus($"已选择{groupName}：{value}", isWarning: false);
        }

        UiMotion.HideStatus(PersonalProfileRoleUnsavedPrompt);
        RenderPersonalProfilePlayStyleOptions();
    }

    private void RenderPersonalProfileRoleCategories()
    {
        PersonalProfileRoleCategoryList.Children.Clear();
        foreach (var category in PersonalProfileRoleCatalog.Categories)
        {
            var isActive = category.Id.Equals(_personalProfileRoleActiveCategoryId, StringComparison.OrdinalIgnoreCase);
            var selectedCount = _personalProfileRoleDraftIds.Count(id =>
                PersonalProfileRoleCatalog.FindRole(id)?.CategoryId.Equals(category.Id, StringComparison.OrdinalIgnoreCase) == true);
            var button = new Button
            {
                Height = 40,
                Margin = new Thickness(0, 0, 0, 7),
                Padding = new Thickness(0),
                HorizontalContentAlignment = HorizontalAlignment.Stretch,
                Cursor = Cursors.Hand,
                Tag = category.Id,
                Background = isActive ? BrushFromHex(category.AccentHex, 0.23) : CreateSolidBrush("#0B1B28"),
                BorderBrush = isActive ? BrushFromHex(category.AccentHex, 0.90) : CreateSolidBrush("#19384B"),
                BorderThickness = new Thickness(1),
                ToolTip = category.Description
            };
            button.Click += PersonalProfileRoleCategoryButton_Click;

            var content = new Grid();
            content.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(4) });
            content.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            content.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
            content.Children.Add(new Border
            {
                Background = BrushFromHex(category.AccentHex),
                Opacity = isActive ? 1 : 0.62,
                CornerRadius = new CornerRadius(2, 0, 0, 2)
            });

            var name = new TextBlock
            {
                Text = category.Name,
                Margin = new Thickness(10, 0, 6, 0),
                VerticalAlignment = VerticalAlignment.Center,
                Foreground = isActive
                    ? FindBrush("PrimaryTextBrush", Brushes.AliceBlue)
                    : FindBrush("MutedTextBrush", Brushes.LightSlateGray),
                FontWeight = isActive ? FontWeights.SemiBold : FontWeights.Normal
            };
            Grid.SetColumn(name, 1);
            content.Children.Add(name);

            var count = new TextBlock
            {
                Text = selectedCount > 0 ? selectedCount.ToString(CultureInfo.InvariantCulture) : "",
                Margin = new Thickness(0, 0, 10, 0),
                VerticalAlignment = VerticalAlignment.Center,
                Foreground = BrushFromHex(category.AccentHex),
                FontWeight = FontWeights.SemiBold
            };
            Grid.SetColumn(count, 2);
            content.Children.Add(count);
            button.Content = content;
            PersonalProfileRoleCategoryList.Children.Add(button);
        }
    }

    private void PersonalProfileRoleCategoryButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not Button { Tag: string categoryId })
        {
            return;
        }

        _personalProfileRoleActiveCategoryId = categoryId;
        UiMotion.HideStatus(PersonalProfileRoleUnsavedPrompt);
        RenderPersonalProfileRoleSelector();
    }

    private void RenderPersonalProfileRoleOptions()
    {
        var category = PersonalProfileRoleCatalog.FindCategory(_personalProfileRoleActiveCategoryId) ??
                       PersonalProfileRoleCatalog.Categories[0];
        PersonalProfileRoleActiveCategoryText.Text = category.Name;
        PersonalProfileRoleActiveCategoryText.Foreground = BrushFromHex(category.AccentHex);
        PersonalProfileRoleActiveCategoryDescriptionText.Text = category.Description;
        PersonalProfileRoleOptionsPanel.Children.Clear();

        foreach (var role in PersonalProfileRoleCatalog.Roles.Where(role =>
                     role.CategoryId.Equals(category.Id, StringComparison.OrdinalIgnoreCase)))
        {
            var isSelected = _personalProfileRoleDraftIds.Contains(role.Id, StringComparer.OrdinalIgnoreCase);
            var border = new Border
            {
                MinWidth = 154,
                MinHeight = 36,
                Margin = new Thickness(0, 0, 8, 8),
                Padding = new Thickness(10, 6, 10, 6),
                Background = isSelected ? BrushFromHex(category.AccentHex, 0.20) : CreateSolidBrush("#0D1D29"),
                BorderBrush = isSelected ? BrushFromHex(category.AccentHex, 0.92) : CreateSolidBrush("#24506A"),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(2),
                Cursor = Cursors.Hand,
                Tag = role,
                ToolTip = role.Description
            };
            border.MouseLeftButtonUp += PersonalProfileRoleOption_MouseLeftButtonUp;

            var content = new StackPanel { Orientation = Orientation.Horizontal };
            content.Children.Add(new Border
            {
                Width = 5,
                Height = 17,
                Margin = new Thickness(0, 0, 7, 0),
                VerticalAlignment = VerticalAlignment.Center,
                Background = BrushFromHex(category.AccentHex),
                CornerRadius = new CornerRadius(2),
                Opacity = isSelected ? 1 : 0.62
            });
            content.Children.Add(new TextBlock
            {
                Text = role.Name,
                Foreground = isSelected
                    ? FindBrush("PrimaryTextBrush", Brushes.AliceBlue)
                    : FindBrush("MutedTextBrush", Brushes.LightSlateGray),
                FontSize = 12,
                FontWeight = FontWeights.SemiBold,
                VerticalAlignment = VerticalAlignment.Center
            });
            if (isSelected)
            {
                content.Children.Add(new TextBlock
                {
                    Text = "  ✓",
                    Foreground = BrushFromHex(category.AccentHex),
                    FontWeight = FontWeights.Bold,
                    VerticalAlignment = VerticalAlignment.Center
                });
            }

            border.Child = content;
            PersonalProfileRoleOptionsPanel.Children.Add(border);
        }
    }

    private void PersonalProfileRoleOption_MouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        if (sender is not Border { Tag: PersonalProfileRoleDefinition role })
        {
            return;
        }

        var existingIndex = _personalProfileRoleDraftIds.FindIndex(id =>
            id.Equals(role.Id, StringComparison.OrdinalIgnoreCase));
        if (existingIndex >= 0)
        {
            _personalProfileRoleDraftIds.RemoveAt(existingIndex);
            SetPersonalProfileRoleSelectorStatus($"已移除：{role.Name}", isWarning: false);
        }
        else
        {
            if (_personalProfileRoleDraftIds.Count >= PersonalProfileRoleCatalog.MaxSelected)
            {
                SetPersonalProfileRoleSelectorStatus($"最多选择 {PersonalProfileRoleCatalog.MaxSelected} 个岗位。", isWarning: true);
                return;
            }

            _personalProfileRoleDraftIds.Add(role.Id);
            SetPersonalProfileRoleSelectorStatus(
                _personalProfileRoleDraftIds.Count == 1 ? $"已设为主岗位：{role.Name}" : $"已选择：{role.Name}",
                isWarning: false);
        }

        UiMotion.HideStatus(PersonalProfileRoleUnsavedPrompt);
        RenderPersonalProfileRoleSelector();
    }

    private void RenderPersonalProfileSelectedRoles()
    {
        PersonalProfileRoleSelectedList.Children.Clear();
        if (_personalProfileRoleDraftIds.Count == 0)
        {
            PersonalProfileRoleSelectedList.Children.Add(new TextBlock
            {
                Text = "尚未选择岗位。第一个选择的岗位将成为主岗位。",
                Margin = new Thickness(2, 8, 0, 0),
                Foreground = FindBrush("MutedTextBrush", Brushes.LightSlateGray),
                FontSize = 11
            });
            return;
        }

        for (var index = 0; index < _personalProfileRoleDraftIds.Count; index++)
        {
            var role = PersonalProfileRoleCatalog.FindRole(_personalProfileRoleDraftIds[index]);
            if (role is null)
            {
                continue;
            }

            var category = PersonalProfileRoleCatalog.FindCategory(role.CategoryId);
            var accentHex = category?.AccentHex ?? "#29AFFF";
            var row = new Grid { Height = 31, Margin = new Thickness(0, 0, 0, 5) };
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(32) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(76) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(30) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(30) });
            row.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(30) });

            var orderBadge = new Border
            {
                Background = BrushFromHex(accentHex, 0.15),
                BorderBrush = BrushFromHex(accentHex, 0.65),
                BorderThickness = new Thickness(1),
                CornerRadius = new CornerRadius(2),
                Child = new TextBlock
                {
                    Text = index == 0 ? "主" : (index + 1).ToString(CultureInfo.InvariantCulture),
                    HorizontalAlignment = HorizontalAlignment.Center,
                    VerticalAlignment = VerticalAlignment.Center,
                    Foreground = BrushFromHex(accentHex),
                    FontSize = 10,
                    FontWeight = FontWeights.Bold
                }
            };
            row.Children.Add(orderBadge);

            var roleName = new TextBlock
            {
                Text = role.Name,
                Margin = new Thickness(10, 0, 6, 0),
                VerticalAlignment = VerticalAlignment.Center,
                Foreground = FindBrush("PrimaryTextBrush", Brushes.AliceBlue),
                FontWeight = index == 0 ? FontWeights.SemiBold : FontWeights.Normal,
                ToolTip = role.Description
            };
            Grid.SetColumn(roleName, 1);
            row.Children.Add(roleName);

            var categoryText = new TextBlock
            {
                Text = category?.Name ?? "岗位",
                VerticalAlignment = VerticalAlignment.Center,
                Foreground = BrushFromHex(accentHex),
                FontSize = 10
            };
            Grid.SetColumn(categoryText, 2);
            row.Children.Add(categoryText);

            var capturedIndex = index;
            var upButton = CreatePersonalProfileRoleOrderButton("↑", "上移");
            upButton.IsEnabled = index > 0;
            upButton.Click += (_, _) => MovePersonalProfileRole(capturedIndex, -1);
            Grid.SetColumn(upButton, 3);
            row.Children.Add(upButton);

            var downButton = CreatePersonalProfileRoleOrderButton("↓", "下移");
            downButton.IsEnabled = index < _personalProfileRoleDraftIds.Count - 1;
            downButton.Click += (_, _) => MovePersonalProfileRole(capturedIndex, 1);
            Grid.SetColumn(downButton, 4);
            row.Children.Add(downButton);

            var removeButton = CreatePersonalProfileRoleOrderButton("×", "移除");
            removeButton.Foreground = FindBrush("StatusDangerBrush", Brushes.IndianRed);
            removeButton.Click += (_, _) => RemovePersonalProfileRole(capturedIndex);
            Grid.SetColumn(removeButton, 5);
            row.Children.Add(removeButton);
            PersonalProfileRoleSelectedList.Children.Add(row);
        }
    }

    private Button CreatePersonalProfileRoleOrderButton(string content, string toolTip)
    {
        return new Button
        {
            Width = 26,
            Height = 26,
            Margin = new Thickness(3, 2, 0, 2),
            Padding = new Thickness(0),
            Content = content,
            ToolTip = toolTip,
            FontSize = 13,
            VerticalContentAlignment = VerticalAlignment.Center,
            HorizontalContentAlignment = HorizontalAlignment.Center,
            Style = System.Windows.Application.Current.TryFindResource("SecondaryButton") as Style
        };
    }

    private void MovePersonalProfileRole(int index, int offset)
    {
        var targetIndex = index + offset;
        if (index < 0 || index >= _personalProfileRoleDraftIds.Count ||
            targetIndex < 0 || targetIndex >= _personalProfileRoleDraftIds.Count)
        {
            return;
        }

        var roleId = _personalProfileRoleDraftIds[index];
        _personalProfileRoleDraftIds.RemoveAt(index);
        _personalProfileRoleDraftIds.Insert(targetIndex, roleId);
        var role = PersonalProfileRoleCatalog.FindRole(roleId);
        SetPersonalProfileRoleSelectorStatus(
            targetIndex == 0 ? $"主岗位已改为：{role?.Name ?? "未命名岗位"}" : "已调整岗位展示顺序。",
            isWarning: false);
        RenderPersonalProfileRoleSelector();
    }

    private void RemovePersonalProfileRole(int index)
    {
        if (index < 0 || index >= _personalProfileRoleDraftIds.Count)
        {
            return;
        }

        var role = PersonalProfileRoleCatalog.FindRole(_personalProfileRoleDraftIds[index]);
        _personalProfileRoleDraftIds.RemoveAt(index);
        SetPersonalProfileRoleSelectorStatus($"已移除：{role?.Name ?? "未命名岗位"}", isWarning: false);
        RenderPersonalProfileRoleSelector();
    }

    private void PersonalProfileRoleSelectorSaveButton_Click(object sender, RoutedEventArgs e) =>
        ApplyPersonalProfileRoleDraftAndClose();

    private void PersonalProfileRoleSelectorCancelButton_Click(object sender, RoutedEventArgs e) =>
        TryClosePersonalProfileRoleSelector();

    private void PersonalProfileRoleSelectorCloseButton_Click(object sender, RoutedEventArgs e) =>
        TryClosePersonalProfileRoleSelector();

    private void PersonalProfileRoleSelectorOverlay_MouseLeftButtonDown(object sender, MouseButtonEventArgs e) =>
        TryClosePersonalProfileRoleSelector();

    private void PersonalProfileRoleSelectorCard_MouseLeftButtonDown(object sender, MouseButtonEventArgs e) =>
        e.Handled = true;

    private void TryClosePersonalProfileRoleSelector()
    {
        if (IsPersonalProfileRoleDraftDirty())
        {
            UiMotion.ShowStatus(PersonalProfileRoleUnsavedPrompt);
            SetPersonalProfileRoleSelectorStatus("游戏定位尚未保存。", isWarning: true);
            return;
        }

        ClosePersonalProfileRoleSelector();
    }

    private void PersonalProfileRoleUnsavedContinueButton_Click(object sender, RoutedEventArgs e)
    {
        UiMotion.HideStatus(PersonalProfileRoleUnsavedPrompt);
        SetPersonalProfileRoleSelectorStatus("继续编辑游戏定位。", isWarning: false);
    }

    private void PersonalProfileRoleUnsavedDiscardButton_Click(object sender, RoutedEventArgs e) =>
        ClosePersonalProfileRoleSelector();

    private void PersonalProfileRoleUnsavedSaveButton_Click(object sender, RoutedEventArgs e) =>
        ApplyPersonalProfileRoleDraftAndClose();

    private void ApplyPersonalProfileRoleDraftAndClose()
    {
        var skilledRoles = PersonalProfileRoleCatalog.NormalizeRoleIds(_personalProfileRoleDraftIds);
        var participationInterests = PersonalProfilePlayStyleCatalog.NormalizeSelection(_personalProfileParticipationInterestDraft);
        var supportCapabilities = PersonalProfilePlayStyleCatalog.NormalizeSelection(_personalProfileSupportCapabilityDraft);
        if (IsPersonalProfileRoleDraftDirty())
        {
            _personalProfileSettings = _personalProfileSettings with
            {
                SkilledRoles = skilledRoles,
                ParticipationInterests = participationInterests,
                SupportCapabilities = supportCapabilities
            };
            MarkPersonalProfileDirty();
            RefreshPersonalProfileContent();
        }

        ClosePersonalProfileRoleSelector();
    }

    private void ClosePersonalProfileRoleSelector()
    {
        ResetPersonalProfileRoleDetailEditors();
        UiMotion.HideStatus(PersonalProfileRoleUnsavedPrompt);
        UiMotion.HideModal(PersonalProfileRoleSelectorOverlay, PersonalProfileRoleSelectorCard);
        SetPersonalProfileRoleSelectorStatus("选择岗位并补充参与偏好与支援能力。", isWarning: false);
    }

    private bool IsPersonalProfileRoleDraftDirty()
    {
        var skilledRolesChanged = !PersonalProfileRoleCatalog.NormalizeRoleIds(_personalProfileSettings.SkilledRoles)
            .SequenceEqual(_personalProfileRoleDraftIds, StringComparer.OrdinalIgnoreCase);
        var participationInterestsChanged = !PersonalProfilePlayStyleCatalog
            .NormalizeSelection(_personalProfileSettings.ParticipationInterests)
            .SequenceEqual(_personalProfileParticipationInterestDraft, StringComparer.OrdinalIgnoreCase);
        var supportCapabilitiesChanged = !PersonalProfilePlayStyleCatalog
            .NormalizeSelection(_personalProfileSettings.SupportCapabilities)
            .SequenceEqual(_personalProfileSupportCapabilityDraft, StringComparer.OrdinalIgnoreCase);
        return skilledRolesChanged || participationInterestsChanged || supportCapabilitiesChanged;
    }

    private void ResetPersonalProfileRoleDetailEditors()
    {
        _personalProfileParticipationInterestDraft.Clear();
        _personalProfileParticipationInterestDraft.AddRange(
            PersonalProfilePlayStyleCatalog.NormalizeSelection(_personalProfileSettings.ParticipationInterests));
        _personalProfileSupportCapabilityDraft.Clear();
        _personalProfileSupportCapabilityDraft.AddRange(
            PersonalProfilePlayStyleCatalog.NormalizeSelection(_personalProfileSettings.SupportCapabilities));
    }

    private void SetPersonalProfileRoleSelectorStatus(string message, bool isWarning)
    {
        PersonalProfileRoleSelectorStatusText.Text = message;
        PersonalProfileRoleSelectorStatusText.Foreground = isWarning
            ? FindBrush("StatusWarningBrush", Brushes.Goldenrod)
            : FindBrush("MutedTextBrush", Brushes.LightSlateGray);
    }

    private void PersonalProfileFavoriteShipsEditButton_Click(object sender, RoutedEventArgs e)
    {
        if (!_isPersonalProfileEditMode)
        {
            return;
        }

        OpenPersonalProfileFavoriteShipSelector();
    }

    private void OpenPersonalProfileFavoriteShipSelector()
    {
        _personalProfileFavoriteShipDraftCodes.Clear();
        _personalProfileFavoriteShipDraftCodes.AddRange(
            (_personalProfileSettings.FavoriteShipCodes ?? [])
            .Where(code => !string.IsNullOrWhiteSpace(code))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Take(3));
        UiMotion.HideStatus(PersonalProfileFavoriteShipUnsavedPrompt);
        UiMotion.ShowModal(PersonalProfileFavoriteShipSelectorOverlay, PersonalProfileFavoriteShipSelectorCard);
        SetPersonalProfileFavoriteShipSelectorStatus(
            "点击舰船选择或取消选择。选择顺序决定主页展示顺序。",
            isWarning: false);
        RenderPersonalProfileFavoriteShipSelector();
    }

    private void RenderPersonalProfileFavoriteShipSelector()
    {
        PersonalProfileFavoriteShipOptionsPanel.Children.Clear();
        var options = _ownedShips
            .Where(ship => !string.IsNullOrWhiteSpace(ship.Code))
            .GroupBy(ship => ship.Code.Trim(), StringComparer.OrdinalIgnoreCase)
            .Select(group => group.First())
            .Select(ship => (Ship: ship, Catalog: ShipCatalog.Find(ship.Code, ship.DisplayName)))
            .OrderBy(item => item.Catalog?.DisplayName(_language) ?? item.Ship.DisplayName, StringComparer.CurrentCultureIgnoreCase)
            .ToArray();
        PersonalProfileFavoriteShipSelectorEmptyText.Visibility = options.Length == 0
            ? Visibility.Visible
            : Visibility.Collapsed;
        PersonalProfileFavoriteShipDraftCountText.Text = $"{_personalProfileFavoriteShipDraftCodes.Count} / 3";

        foreach (var option in options)
        {
            var isSelected = _personalProfileFavoriteShipDraftCodes.Contains(
                option.Ship.Code,
                StringComparer.OrdinalIgnoreCase);
            var selectionIndex = _personalProfileFavoriteShipDraftCodes.FindIndex(code =>
                code.Equals(option.Ship.Code, StringComparison.OrdinalIgnoreCase));
            var card = new Border
            {
                Width = 270,
                Height = 112,
                Margin = new Thickness(0, 0, 10, 10),
                Padding = new Thickness(8),
                Background = isSelected ? CreateSolidBrush("#12344A") : CreateSolidBrush("#0D1D29"),
                BorderBrush = isSelected ? FindBrush("AccentBrush", Brushes.DeepSkyBlue) : CreateSolidBrush("#24506A"),
                BorderThickness = new Thickness(isSelected ? 2 : 1),
                CornerRadius = new CornerRadius(2),
                Cursor = Cursors.Hand,
                Tag = option.Ship
            };
            card.MouseLeftButtonUp += PersonalProfileFavoriteShipOption_MouseLeftButtonUp;

            var content = new Grid();
            content.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(92) });
            content.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
            var imageFrame = new Border
            {
                Width = 84,
                Height = 84,
                VerticalAlignment = VerticalAlignment.Center,
                Background = CreateSolidBrush("#07131D"),
                BorderBrush = isSelected ? FindBrush("AccentBrush", Brushes.DeepSkyBlue) : CreateSolidBrush("#2B5F79"),
                BorderThickness = new Thickness(1),
                ClipToBounds = true
            };
            var imageSource = TryCreateImageSource(option.Catalog?.ImagePath);
            imageFrame.Child = imageSource is null
                ? new TextBlock
                {
                    Text = "SHIP",
                    HorizontalAlignment = HorizontalAlignment.Center,
                    VerticalAlignment = VerticalAlignment.Center,
                    Foreground = FindBrush("MutedTextBrush", Brushes.LightSlateGray),
                    FontSize = 9
                }
                : new Image { Source = imageSource, Stretch = Stretch.UniformToFill };
            content.Children.Add(imageFrame);

            var displayName = option.Catalog?.DisplayName(_language);
            if (string.IsNullOrWhiteSpace(displayName))
            {
                displayName = string.IsNullOrWhiteSpace(option.Ship.DisplayName)
                    ? option.Ship.Code
                    : option.Ship.DisplayName;
            }

            var details = new StackPanel
            {
                Margin = new Thickness(9, 1, 0, 0),
                VerticalAlignment = VerticalAlignment.Center
            };
            details.Children.Add(new TextBlock
            {
                Text = displayName,
                Foreground = FindBrush("PrimaryTextBrush", Brushes.AliceBlue),
                FontWeight = FontWeights.SemiBold,
                TextTrimming = TextTrimming.CharacterEllipsis,
                ToolTip = displayName
            });
            details.Children.Add(new TextBlock
            {
                Text = option.Catalog?.EnglishName ?? option.Ship.Code,
                Margin = new Thickness(0, 4, 0, 0),
                Foreground = FindBrush("MutedTextBrush", Brushes.LightSlateGray),
                FontSize = 10,
                TextTrimming = TextTrimming.CharacterEllipsis
            });
            var role = option.Catalog?.RoleDisplay(_language);
            if (!string.IsNullOrWhiteSpace(role))
            {
                details.Children.Add(new TextBlock
                {
                    Text = role,
                    Margin = new Thickness(0, 5, 0, 0),
                    Foreground = FindBrush("AccentBrush", Brushes.DeepSkyBlue),
                    FontSize = 10,
                    TextTrimming = TextTrimming.CharacterEllipsis
                });
            }

            if (isSelected)
            {
                details.Children.Add(new TextBlock
                {
                    Text = $"展示顺序 {selectionIndex + 1}",
                    Margin = new Thickness(0, 5, 0, 0),
                    Foreground = FindBrush("StatusSuccessBrush", Brushes.MediumSeaGreen),
                    FontSize = 10,
                    FontWeight = FontWeights.SemiBold
                });
            }

            Grid.SetColumn(details, 1);
            content.Children.Add(details);
            card.Child = content;
            PersonalProfileFavoriteShipOptionsPanel.Children.Add(card);
        }
    }

    private void PersonalProfileFavoriteShipOption_MouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        if (sender is not Border { Tag: OwnedShipRecord ship })
        {
            return;
        }

        var existingIndex = _personalProfileFavoriteShipDraftCodes.FindIndex(code =>
            code.Equals(ship.Code, StringComparison.OrdinalIgnoreCase));
        if (existingIndex >= 0)
        {
            _personalProfileFavoriteShipDraftCodes.RemoveAt(existingIndex);
            SetPersonalProfileFavoriteShipSelectorStatus("已从最爱舰船中移除。", isWarning: false);
        }
        else
        {
            if (_personalProfileFavoriteShipDraftCodes.Count >= 3)
            {
                SetPersonalProfileFavoriteShipSelectorStatus("最多选择 3 艘最爱舰船。", isWarning: true);
                return;
            }

            _personalProfileFavoriteShipDraftCodes.Add(ship.Code);
            SetPersonalProfileFavoriteShipSelectorStatus(
                $"已选择为第 {_personalProfileFavoriteShipDraftCodes.Count} 艘展示舰船。",
                isWarning: false);
        }

        UiMotion.HideStatus(PersonalProfileFavoriteShipUnsavedPrompt);
        RenderPersonalProfileFavoriteShipSelector();
    }

    private void PersonalProfileFavoriteShipSelectorSaveButton_Click(object sender, RoutedEventArgs e) =>
        ApplyPersonalProfileFavoriteShipDraftAndClose();

    private void PersonalProfileFavoriteShipSelectorCancelButton_Click(object sender, RoutedEventArgs e) =>
        TryClosePersonalProfileFavoriteShipSelector();

    private void PersonalProfileFavoriteShipSelectorCloseButton_Click(object sender, RoutedEventArgs e) =>
        TryClosePersonalProfileFavoriteShipSelector();

    private void PersonalProfileFavoriteShipSelectorOverlay_MouseLeftButtonDown(object sender, MouseButtonEventArgs e) =>
        TryClosePersonalProfileFavoriteShipSelector();

    private void PersonalProfileFavoriteShipSelectorCard_MouseLeftButtonDown(object sender, MouseButtonEventArgs e) =>
        e.Handled = true;

    private void TryClosePersonalProfileFavoriteShipSelector()
    {
        if (!NormalizePersonalProfileFavoriteShipCodes(_personalProfileSettings.FavoriteShipCodes)
                .SequenceEqual(_personalProfileFavoriteShipDraftCodes, StringComparer.OrdinalIgnoreCase))
        {
            UiMotion.ShowStatus(PersonalProfileFavoriteShipUnsavedPrompt);
            SetPersonalProfileFavoriteShipSelectorStatus("最爱舰船选择尚未保存。", isWarning: true);
            return;
        }

        ClosePersonalProfileFavoriteShipSelector();
    }

    private void PersonalProfileFavoriteShipUnsavedContinueButton_Click(object sender, RoutedEventArgs e)
    {
        UiMotion.HideStatus(PersonalProfileFavoriteShipUnsavedPrompt);
        SetPersonalProfileFavoriteShipSelectorStatus("继续选择最爱舰船。", isWarning: false);
    }

    private void PersonalProfileFavoriteShipUnsavedDiscardButton_Click(object sender, RoutedEventArgs e) =>
        ClosePersonalProfileFavoriteShipSelector();

    private void PersonalProfileFavoriteShipUnsavedSaveButton_Click(object sender, RoutedEventArgs e) =>
        ApplyPersonalProfileFavoriteShipDraftAndClose();

    private void ApplyPersonalProfileFavoriteShipDraftAndClose()
    {
        var normalized = NormalizePersonalProfileFavoriteShipCodes(_personalProfileFavoriteShipDraftCodes);
        if (!NormalizePersonalProfileFavoriteShipCodes(_personalProfileSettings.FavoriteShipCodes)
                .SequenceEqual(normalized, StringComparer.OrdinalIgnoreCase))
        {
            _personalProfileSettings = _personalProfileSettings with { FavoriteShipCodes = normalized };
            MarkPersonalProfileDirty();
            RefreshPersonalProfileContent();
        }

        ClosePersonalProfileFavoriteShipSelector();
    }

    private void ClosePersonalProfileFavoriteShipSelector()
    {
        UiMotion.HideStatus(PersonalProfileFavoriteShipUnsavedPrompt);
        UiMotion.HideModal(PersonalProfileFavoriteShipSelectorOverlay, PersonalProfileFavoriteShipSelectorCard);
        SetPersonalProfileFavoriteShipSelectorStatus(
            "点击舰船选择或取消选择。选择顺序决定主页展示顺序。",
            isWarning: false);
    }

    private void SetPersonalProfileFavoriteShipSelectorStatus(string message, bool isWarning)
    {
        PersonalProfileFavoriteShipSelectorStatusText.Text = message;
        PersonalProfileFavoriteShipSelectorStatusText.Foreground = isWarning
            ? FindBrush("StatusWarningBrush", Brushes.Goldenrod)
            : FindBrush("MutedTextBrush", Brushes.LightSlateGray);
    }

    private static string[] NormalizePersonalProfileFavoriteShipCodes(IEnumerable<string>? codes) =>
        (codes ?? [])
        .Select(code => (code ?? "").Trim())
        .Where(code => code.Length > 0)
        .Distinct(StringComparer.OrdinalIgnoreCase)
        .Take(3)
        .ToArray();

    private static string FormatPersonalProfileItems(IEnumerable<string>? values, string emptyText)
    {
        var items = (values ?? []).Where(value => !string.IsNullOrWhiteSpace(value)).ToArray();
        return items.Length == 0 ? emptyText : string.Join(" · ", items);
    }

    private void BuildPersonalProfileShipTypeBar(
        Grid bar,
        TextBlock summaryText,
        int summaryLimit,
        IReadOnlyCollection<OwnedShipRecord> ships)
    {
        bar.Children.Clear();
        bar.ColumnDefinitions.Clear();

        var counts = FleetShipRoleVisuals
            .Select(item => new
            {
                Name = item.DisplayName,
                Color = item.ColorHex,
                Count = ships.Count(ship => GetOwnedShipRoleCategory(ship) == item.Category)
            })
            .ToArray();
        var visible = counts.Where(item => item.Count > 0).ToArray();

        summaryText.Text = visible.Length == 0
            ? "读取个人机库后显示舰船构成"
            : string.Join(" · ", visible.Take(Math.Max(1, summaryLimit)).Select(item => $"{item.Name} {item.Count}")) +
              (visible.Length > summaryLimit ? $" · +{visible.Length - summaryLimit} 类" : "");

        if (visible.Length == 0)
        {
            bar.ColumnDefinitions.Add(new ColumnDefinition());
            bar.Children.Add(new Border
            {
                Background = CreateSolidBrush("#111920"),
                BorderBrush = CreateSolidBrush("#173447"),
                BorderThickness = new Thickness(1)
            });
            return;
        }

        for (var index = 0; index < visible.Length; index++)
        {
            var segment = visible[index];
            bar.ColumnDefinitions.Add(new ColumnDefinition
            {
                Width = new GridLength(segment.Count, GridUnitType.Star)
            });
            var border = new Border
            {
                Background = CreateSolidBrush(segment.Color),
                Opacity = 0.76,
                Margin = index == 0 ? new Thickness(0) : new Thickness(3, 0, 0, 0)
            };
            Grid.SetColumn(border, index);
            bar.Children.Add(border);
        }
    }

    private string FormatPersonalProfileAvailabilityTimeZone(string? timeZoneId)
    {
        var normalizedId = string.IsNullOrWhiteSpace(timeZoneId)
            ? TimeZoneInfo.Local.Id
            : timeZoneId;
        var option = _fleetTimeZoneOptions.FirstOrDefault(item =>
                         item.Id.Equals(normalizedId, StringComparison.OrdinalIgnoreCase)) ??
                     FindFleetTimeZoneOptionBySameOffset(normalizedId);
        if (option is not null)
        {
            return option.DisplayName;
        }

        try
        {
            return TimeZoneInfo.FindSystemTimeZoneById(normalizedId).DisplayName;
        }
        catch (TimeZoneNotFoundException)
        {
            return normalizedId;
        }
        catch (InvalidTimeZoneException)
        {
            return normalizedId;
        }
    }

    private void ApplyPersonalProfileModuleLayout()
    {
        if (PersonalProfileModuleGrid is null)
        {
            return;
        }

        var presentation = GetPersonalProfilePresentationState();
        var isEditing = presentation.IsEditing;
        var cards = GetPersonalProfileModuleCards();
        foreach (var card in cards.Values)
        {
            card.Visibility = Visibility.Collapsed;
        }

        var layoutModules = _personalProfileDragPreviewModules ?? _personalProfileSettings.Modules;
        var visibleModules = layoutModules
            .Where(module => module.IsVisible && !IsFixedPersonalProfileModule(module.Id))
            .OrderBy(module => module.Order)
            .ToArray();
        PersonalProfileEmptyStateTitle.Text = isEditing
            ? "添加你的第一个主页模块"
            : presentation.IsVisitor
                ? "该用户暂未展示主页模块"
                : "主页暂时没有模块";
        PersonalProfileEmptyStateDescription.Text = isEditing
            ? "点击上方“添加模块”，选择你愿意展示的内容。"
            : presentation.IsVisitor
                ? "个人主页中暂无公开模块。"
                : "点击“编辑主页”，选择你愿意展示的内容。";

        foreach (var emptySlot in PersonalProfileModuleGrid.Children
                     .OfType<Button>()
                     .Where(button => button.Tag is int)
                     .ToArray())
        {
            PersonalProfileModuleGrid.Children.Remove(emptySlot);
        }

        if (!presentation.ShowModules)
        {
            foreach (var row in PersonalProfileModuleGrid.RowDefinitions)
            {
                row.Height = new GridLength(0);
            }

            PersonalProfileEmptyState.Visibility = Visibility.Collapsed;
            return;
        }

        var occupied = new bool[9];
        foreach (var module in visibleModules)
        {
            if (!cards.TryGetValue(module.Id, out var card))
            {
                continue;
            }

            var span = PersonalProfileModuleConstraints.NormalizeSpan(module.Id, module.Span);
            var position = CanPlacePersonalProfileModule(occupied, module.Position, span)
                ? module.Position
                : FindFirstPersonalProfileModulePosition(occupied, span);
            if (position < 0)
            {
                continue;
            }

            var row = position / 3;
            var column = position % 3;
            MarkPersonalProfileModuleCells(occupied, position, span);

            Grid.SetRow(card, row);
            Grid.SetColumn(card, column);
            Grid.SetColumnSpan(card, span);
            card.Margin = new Thickness(column == 0 ? 0 : 5, 0, column + span == 3 ? 0 : 5, 10);
            card.VerticalAlignment = VerticalAlignment.Stretch;
            var isDraggingCard = _personalProfileDragPreviewModules is not null &&
                                 card == _personalProfileDragSource;
            card.Opacity = isDraggingCard ? 0.72 : 1;
            card.Cursor = isEditing ? Cursors.SizeAll : Cursors.Arrow;
            card.Background = isEditing
                ? new SolidColorBrush(Color.FromRgb(12, 29, 41))
                : new SolidColorBrush(Color.FromRgb(9, 24, 35));
            card.BorderBrush = isDraggingCard
                ? FindBrush("AccentBrush", new SolidColorBrush(Color.FromRgb(41, 175, 255)))
                : isEditing
                    ? new SolidColorBrush(Color.FromRgb(46, 106, 137))
                    : FindBrush("PanelBorderBrush", new SolidColorBrush(Color.FromRgb(23, 52, 71)));
            card.BorderThickness = new Thickness(isDraggingCard ? 2 : 1);
            Panel.SetZIndex(card, 1);
            card.Visibility = Visibility.Visible;
        }

        var hasVisibleModules = visibleModules.Length > 0;
        for (var row = 0; row < PersonalProfileModuleGrid.RowDefinitions.Count; row++)
        {
            var rowHasModule = occupied.Skip(row * 3).Take(3).Any(cell => cell);
            PersonalProfileModuleGrid.RowDefinitions[row].Height = isEditing || rowHasModule
                ? new GridLength(PersonalProfileModuleRowHeight)
                : row == 0 && !hasVisibleModules
                    ? new GridLength(144)
                    : new GridLength(0);
        }

        PersonalProfileEmptyState.Visibility = !isEditing && visibleModules.Length == 0
            ? Visibility.Visible
            : Visibility.Collapsed;
        if (presentation.ShowModuleEmptySlots)
        {
            AddPersonalProfileEmptySlots(occupied);
        }

        RefreshPersonalProfileModuleButtons();
        RefreshPersonalProfileModulePicker();
        RefreshPersonalProfileSkilledRolesDisplay();
        RefreshPersonalProfileFavoriteShips();
        RefreshPersonalProfileHangarSummary();
        RefreshPersonalProfileGameplayStatistics();
    }

    private void RefreshPersonalProfileFixedInformationLayout(
        PersonalProfilePresentationState presentation)
    {
        if (PersonalProfileGameplayStatisticsSection is null)
        {
            return;
        }

        var isEditing = presentation.IsEditing;
        var showGameplayStatistics = !isEditing && (!presentation.IsVisitor ||
            (_isPersonalProfileVisitorMode
                ? _personalProfileVisitorDocument?.GameplayStatistics is not null
                : _gameplayStatisticsRecorder.Consent.ShareOnProfile &&
                  !_gameplayStatisticsPrivacySyncPending));

        PersonalProfileOnlineTimeSummaryColumn.Width = new GridLength(1, GridUnitType.Star);
        PersonalProfileOnlineTimeDividerColumn.Width = GridLength.Auto;
        PersonalProfileOnlineTimeDivider.Visibility = Visibility.Visible;
        PersonalProfileGameplayStatisticsColumn.Width = isEditing || showGameplayStatistics
            ? new GridLength(1, GridUnitType.Star)
            : new GridLength(0);
        PersonalProfileGameplayStatisticsDividerColumn.Width = showGameplayStatistics
            ? GridLength.Auto
            : new GridLength(0);
        PersonalProfileOnlineTimeEditorColumn.Width = new GridLength(1, GridUnitType.Star);
        PersonalProfileGameplayStatisticsSection.Visibility = showGameplayStatistics
            ? Visibility.Visible
            : Visibility.Collapsed;
        PersonalProfileGameplayStatisticsDivider.Visibility = showGameplayStatistics
            ? Visibility.Visible
            : Visibility.Collapsed;

        Grid.SetColumn(PersonalProfileOnlineTimeEditorPanel, isEditing ? 2 : 4);
        Grid.SetColumnSpan(PersonalProfileOnlineTimeEditorPanel, isEditing ? 3 : 1);
        PersonalProfileFixedInfoRowDivider.Visibility = isEditing ? Visibility.Visible : Visibility.Collapsed;
        Grid.SetRow(PersonalProfileActivityRhythmSection, isEditing ? 2 : 0);
        Grid.SetColumn(PersonalProfileActivityRhythmSection, isEditing ? 0 : 4);
        Grid.SetColumnSpan(PersonalProfileActivityRhythmSection, isEditing ? 5 : 1);

        PersonalProfileActivityRhythmSummaryColumn.Width = new GridLength(1, GridUnitType.Star);
        PersonalProfileActivityRhythmDividerColumn.Width = isEditing ? GridLength.Auto : new GridLength(0);
        PersonalProfileActivityRhythmEditorColumn.Width = isEditing
            ? new GridLength(240)
            : new GridLength(0);
    }

    private void RefreshPersonalProfileGameplayStatistics()
    {
        if (PersonalProfileGameplayDurationText is null)
        {
            return;
        }

        var presentation = GetPersonalProfilePresentationState();
        RefreshPersonalProfileFixedInformationLayout(presentation);
        var visitorStatistics = _isPersonalProfileVisitorMode
            ? _personalProfileVisitorDocument?.GameplayStatistics
            : null;
        var playTimeSeconds = visitorStatistics?.PlayTimeSeconds ?? _gameplayStatisticsRecorder.Snapshot.PlayTimeSeconds;
        var duration = TimeSpan.FromSeconds(Math.Max(0, playTimeSeconds));
        PersonalProfileGameplayDurationText.Text = duration.TotalHours >= 1
            ? $"{(long)duration.TotalHours}小时 {duration.Minutes}分"
            : $"{Math.Max(0, (long)duration.TotalMinutes)}分钟";

        if (_isPersonalProfileVisitorMode || _isPersonalProfilePublicPreviewMode)
        {
            PersonalProfileGameplayPrivacyText.Text = "访客可见";
            PersonalProfileGameplayPrivacyText.Foreground = FindBrush("StatusSuccessBrush", Brushes.MediumSeaGreen);
            PersonalProfileGameplayPrivacyBadge.Background = BrushFromHex("#0D211B");
            PersonalProfileGameplayPrivacyBadge.BorderBrush = BrushFromHex("#276244");
            PersonalProfileGameplayPrivacyBadge.ToolTip = "该用户已允许访客查看游玩时长";
        }
        else if (!_gameplayStatisticsRecorder.IsRecordingAllowed &&
                 _gameplayStatisticsRecorder.Snapshot == GameplayStatisticsSnapshot.Empty)
        {
            PersonalProfileGameplayPrivacyText.Text = "尚未记录";
            PersonalProfileGameplayPrivacyText.Foreground = FindBrush("MutedTextBrush", Brushes.SlateGray);
            PersonalProfileGameplayPrivacyBadge.Background = BrushFromHex("#141A26");
            PersonalProfileGameplayPrivacyBadge.BorderBrush = BrushFromHex("#40566B");
            PersonalProfileGameplayPrivacyBadge.ToolTip = "允许记录后将在此显示游玩时长";
        }
        else if (_gameplayStatisticsRecorder.Consent.ShareOnProfile)
        {
            PersonalProfileGameplayPrivacyText.Text = _personalProfileSettings.IsProfilePublic
                ? "访客可见"
                : "主页未公开";
            PersonalProfileGameplayPrivacyText.Foreground = _personalProfileSettings.IsProfilePublic
                ? FindBrush("StatusSuccessBrush", Brushes.MediumSeaGreen)
                : FindBrush("StatusWarningBrush", Brushes.Goldenrod);
            PersonalProfileGameplayPrivacyBadge.Background = BrushFromHex(
                _personalProfileSettings.IsProfilePublic ? "#0D211B" : "#211C0F");
            PersonalProfileGameplayPrivacyBadge.BorderBrush = BrushFromHex(
                _personalProfileSettings.IsProfilePublic ? "#276244" : "#5B4A24");
            PersonalProfileGameplayPrivacyBadge.ToolTip = "可在应用设置中更改访客权限";
        }
        else
        {
            PersonalProfileGameplayPrivacyText.Text = "仅自己可见";
            PersonalProfileGameplayPrivacyText.Foreground = FindBrush("MutedTextBrush", Brushes.SlateGray);
            PersonalProfileGameplayPrivacyBadge.Background = BrushFromHex("#141A26");
            PersonalProfileGameplayPrivacyBadge.BorderBrush = BrushFromHex("#40566B");
            PersonalProfileGameplayPrivacyBadge.ToolTip = "可在应用设置中更改访客权限";
        }
    }

    private void RefreshPersonalProfileModuleButtons()
    {
        var settings = _personalProfileSettings.Modules.ToDictionary(module => module.Id, StringComparer.Ordinal);
        foreach (var (id, panel) in GetPersonalProfileModuleControls())
        {
            if (!settings.TryGetValue(id, out var module))
            {
                continue;
            }

            foreach (var button in panel.Children.OfType<Button>())
            {
                if (button.Tag is not string tag)
                {
                    continue;
                }

                if (string.Equals(tag, $"{id}:size", StringComparison.Ordinal))
                {
                    button.Content = $"{module.Span} 格";
                }
                else if (string.Equals(tag, $"{id}:visibility", StringComparison.Ordinal))
                {
                    button.Content = "移除";
                }
            }
        }
    }

    private void AddPersonalProfileEmptySlots(bool[] occupied)
    {
        var style = PersonalProfileModuleGrid.Resources["PersonalProfileEmptySlotButton"] as Style;
        for (var position = 0; position < occupied.Length; position++)
        {
            if (occupied[position])
            {
                continue;
            }

            var row = position / 3;
            var column = position % 3;
            var button = new Button
            {
                Tag = position,
                Style = style,
                Margin = new Thickness(column == 0 ? 0 : 5, 0, column == 2 ? 0 : 5, 10),
                ToolTip = "在此处添加模块",
                AllowDrop = true
            };
            AutomationProperties.SetName(button, $"在第 {row + 1} 行第 {column + 1} 列添加模块");
            button.Click += PersonalProfileEmptySlot_Click;
            button.DragOver += PersonalProfileEmptySlot_DragOver;
            button.Drop += PersonalProfileEmptySlot_Drop;
            Grid.SetRow(button, row);
            Grid.SetColumn(button, column);
            Panel.SetZIndex(button, 0);
            PersonalProfileModuleGrid.Children.Add(button);
        }
    }

    private static bool[] GetPersonalProfileOccupiedCells(
        IEnumerable<PersonalProfileModuleSetting> modules,
        string? excludedModuleId = null)
    {
        var occupied = new bool[9];
        foreach (var module in modules.Where(module =>
                     module.IsVisible &&
                     !IsFixedPersonalProfileModule(module.Id) &&
                     !string.Equals(module.Id, excludedModuleId, StringComparison.Ordinal)))
        {
            if (CanPlacePersonalProfileModule(occupied, module.Position, module.Span))
            {
                MarkPersonalProfileModuleCells(occupied, module.Position, module.Span);
            }
        }

        return occupied;
    }

    private static int GetPersonalProfileFittingSpan(bool[] occupied, int position, int preferredSpan)
    {
        for (var span = Math.Clamp(preferredSpan, 1, 3); span >= 1; span--)
        {
            if (CanPlacePersonalProfileModule(occupied, position, span))
            {
                return span;
            }
        }

        return 0;
    }

    private static int FindFirstPersonalProfileModulePosition(bool[] occupied, int span)
    {
        for (var position = 0; position < occupied.Length; position++)
        {
            if (CanPlacePersonalProfileModule(occupied, position, span))
            {
                return position;
            }
        }

        return -1;
    }

    private static bool CanPlacePersonalProfileModule(bool[] occupied, int position, int span)
    {
        if (position < 0 || position >= occupied.Length || span is < 1 or > 3)
        {
            return false;
        }

        var column = position % 3;
        if (column + span > 3 || position + span > occupied.Length)
        {
            return false;
        }

        for (var offset = 0; offset < span; offset++)
        {
            if (occupied[position + offset])
            {
                return false;
            }
        }

        return true;
    }

    private static void MarkPersonalProfileModuleCells(bool[] occupied, int position, int span)
    {
        for (var offset = 0; offset < span; offset++)
        {
            occupied[position + offset] = true;
        }
    }

    private static bool IsFixedPersonalProfileModule(string id) =>
        string.Equals(id, "introduction", StringComparison.Ordinal) ||
        string.Equals(id, "fleet-identity", StringComparison.Ordinal);

    private void RefreshPersonalProfileModulePicker()
    {
        if (PersonalProfilePickerFavoriteShipsButton is null)
        {
            return;
        }

        var settings = _personalProfileSettings.Modules.ToDictionary(module => module.Id, StringComparer.Ordinal);
        var hasRoom = GetPersonalProfileOccupiedCells(settings.Values).Any(value => !value);
        foreach (var (id, button) in GetPersonalProfileModulePickerButtons())
        {
            var isAdded = settings.TryGetValue(id, out var module) && module.IsVisible;
            button.IsEnabled = !isAdded && hasRoom;
            button.Opacity = isAdded ? 0.5 : 1;
            button.ToolTip = isAdded ? "已添加到主页" : "添加到主页";
        }
    }

    private Dictionary<string, Border> GetPersonalProfileModuleCards() => new(StringComparer.Ordinal)
    {
        ["favorite-ships"] = PersonalProfileFavoriteShipsModule,
        ["hangar-summary"] = PersonalProfileHangarSummaryModule,
        ["skilled-roles"] = PersonalProfileSkilledRolesModule
    };

    private Dictionary<string, StackPanel> GetPersonalProfileModuleControls() => new(StringComparer.Ordinal)
    {
        ["favorite-ships"] = PersonalProfileFavoriteShipsControls,
        ["hangar-summary"] = PersonalProfileHangarSummaryControls,
        ["skilled-roles"] = PersonalProfileSkilledRolesControls
    };

    private Dictionary<string, Button> GetPersonalProfileModulePickerButtons() => new(StringComparer.Ordinal)
    {
        ["favorite-ships"] = PersonalProfilePickerFavoriteShipsButton,
        ["hangar-summary"] = PersonalProfilePickerHangarSummaryButton,
        ["skilled-roles"] = PersonalProfilePickerSkilledRolesButton
    };

    private static string ParsePersonalProfileModuleActionTag(string tag, string action)
    {
        var suffix = $":{action}";
        return tag.EndsWith(suffix, StringComparison.Ordinal)
            ? tag[..^suffix.Length]
            : tag;
    }
}
