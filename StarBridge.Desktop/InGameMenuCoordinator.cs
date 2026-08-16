using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;

namespace StarBridge.Desktop;

internal enum InGameMenuExitMode
{
    RestorePreviousOverlay,
    SwitchToInformationOverlay,
    NavigateToDesktop,
    Deactivated,
    ApplicationClosing
}

internal sealed class InGameMenuClosedEventArgs(
    InGameMenuExitMode mode,
    bool informationOverlayWasVisible) : EventArgs
{
    internal InGameMenuExitMode Mode { get; } = mode;
    internal bool InformationOverlayWasVisible { get; } = informationOverlayWasVisible;
}

internal sealed class InGameMenuCoordinator : IDisposable
{
    private sealed class TransientInteractionLease(InGameMenuCoordinator owner) : IDisposable
    {
        private InGameMenuCoordinator? _owner = owner;

        public void Dispose() =>
            Interlocked.Exchange(ref _owner, null)?.EndTransientInteraction();
    }

    private enum ToolKind
    {
        Browser,
        Image,
        Fleet,
        Friends,
        Profile,
        Social,
        Rooms
    }

    private InGameMenuWindow? _window;
    private InGameBrowserWindow? _browserWindow;
    private InGameImageWindow? _imageWindow;
    private readonly HashSet<Window> _movingToolWindows = [];
    private readonly InGameToolSessionStore _toolSessionStore =
        InGameToolSessionStore.CreateDefault();
    private InGameFleetWindow? _fleetWindow;
    private InGameFriendsWindow? _friendsWindow;
    private readonly Dictionary<string, InGameProfileWindow> _profileWindows =
        new(StringComparer.OrdinalIgnoreCase);
    private readonly HashSet<string> _requestedProfileKeys =
        new(StringComparer.OrdinalIgnoreCase);
    private InGameProfileWindow? _activeProfileWindow;
    private InGameSocialWindow? _socialWindow;
    private InGameRoomWindow? _roomWindow;
    private readonly InGameWorkspaceRequestGate _requestGate = new();
    private InGameMenuExitMode _pendingExitMode = InGameMenuExitMode.RestorePreviousOverlay;
    private bool _informationOverlayWasVisible;
    private bool _captureInProgress;
    private bool _closingSession;
    private bool _menuSessionOpen;
    private bool _focusCheckPending;
    private int _transientInteractionDepth;
    private bool _browserRequestedVisible;
    private bool _imageRequestedVisible;
    private bool _fleetRequestedVisible;
    private bool _friendsRequestedVisible;
    private bool _socialRequestedVisible;
    private bool _roomsRequestedVisible;
    private InGameSocialSection _socialSection = InGameSocialSection.DirectMessages;
    private ToolKind? _lastActiveTool;
    private bool _disposed;
    private Uri _browserHomePage = InGameBrowserPreferences.ResolveHomePage(null);
    private InGameMenuSettings _settings = InGameMenuSettings.Default;
    private InGameToolSessionState _toolSessionState;
    private readonly bool _previousSessionEndedUnexpectedly;
    private bool _restoredCrossRestartSession;
    private string _informationOverlayHotkey = "";
    private string _imageLanguage = "zh";

    internal InGameMenuCoordinator()
    {
        _toolSessionState = _toolSessionStore.Load();
        _previousSessionEndedUnexpectedly =
            _toolSessionState.SessionWasOpen;
    }

    internal event EventHandler<InGameMenuActionRequestedEventArgs>? ActionRequested;
    internal event EventHandler<InGameMenuClosedEventArgs>? Closed;
    internal event EventHandler? FleetRefreshRequested;
    internal event EventHandler? FleetCommunicationRequested;
    internal event EventHandler<InGameFleetMemberActionRequestedEventArgs>? FleetMemberActionRequested;
    internal event EventHandler<InGameFleetShipImageReportRequestedEventArgs>? FleetShipImageReportRequested;
    internal event EventHandler? SocialRefreshRequested;
    internal event EventHandler<InGameSocialConversationRequestedEventArgs>? SocialConversationRequested;
    internal event EventHandler<InGameSocialChannelRequestedEventArgs>? SocialChannelRequested;
    internal event EventHandler<InGameSocialMessageRequestedEventArgs>? SocialMessageRequested;
    internal event EventHandler<InGameSocialAttachmentRequestedEventArgs>? SocialAttachmentRequested;
    internal event EventHandler<InGameChatAttachmentActionRequestedEventArgs>? ChatAttachmentActionRequested;
    internal event EventHandler<InGameSocialFriendSearchRequestedEventArgs>? FriendSearchRequested;
    internal event EventHandler<InGameSocialFriendActionRequestedEventArgs>? FriendActionRequested;
    internal event EventHandler<InGameFriendPresenceChangedEventArgs>? FriendPresenceChanged;
    internal event EventHandler<InGameProfileRequestedEventArgs>? ProfileRequested;
    internal event EventHandler? RoomRefreshRequested;
    internal event EventHandler<InGameRoomJoinRequestedEventArgs>? RoomJoinRequested;
    internal event EventHandler<InGameRoomCreateRequestedEventArgs>? RoomCreateRequested;
    internal event EventHandler? RoomLeaveRequested;
    internal event EventHandler<InGameRoomMessageRequestedEventArgs>? RoomMessageRequested;
    internal event EventHandler<InGameRoomAttachmentRequestedEventArgs>? RoomAttachmentRequested;
    internal event EventHandler<InGameRoomInvitationActionRequestedEventArgs>? RoomInvitationActionRequested;

    internal bool IsOpen =>
        _menuSessionOpen &&
        _window?.IsMenuOpen == true;
    internal bool IsFleetVisible => _fleetWindow?.IsVisible == true;

    internal IDisposable BeginTransientInteraction()
    {
        _transientInteractionDepth++;
        return new TransientInteractionLease(this);
    }

    private void EndTransientInteraction()
    {
        if (_transientInteractionDepth <= 0)
        {
            return;
        }

        _transientInteractionDepth--;
        if (_transientInteractionDepth == 0 && _menuSessionOpen && !_closingSession)
        {
            ScheduleFocusCheck();
        }
    }

    internal bool BeginAccountSession(
        AccountSessionLease accountSession,
        string statusText,
        bool isLoading)
    {
        if (!_requestGate.BeginAccountSession(accountSession))
        {
            return false;
        }

        CloseProfileWindowsForAccountChange();
        _fleetWindow?.ResetAccountState(statusText, isLoading);
        _friendsWindow?.ResetAccountState(statusText, isLoading);
        _socialWindow?.ResetAccountState(statusText, isLoading);
        _roomWindow?.ResetAccountState(statusText, isLoading);
        return true;
    }

    internal InGameWorkspaceRequest BeginDataRequest(
        AccountSessionLease accountSession,
        InGameWorkspaceRequestLane lane,
        string? targetKey = null,
        InGameWorkspaceRequestPolicy policy = InGameWorkspaceRequestPolicy.LatestWins)
    {
        if (_requestGate.BeginAccountSession(accountSession))
        {
            CloseProfileWindowsForAccountChange();
            const string status = "正在加载当前账号的数据";
            _fleetWindow?.ResetAccountState(status, isLoading: true);
            _friendsWindow?.ResetAccountState(status, isLoading: true);
            _socialWindow?.ResetAccountState(status, isLoading: true);
            _roomWindow?.ResetAccountState(status, isLoading: true);
        }

        return _requestGate.Begin(accountSession, lane, targetKey, policy);
    }

    internal void SetBrowserHomePage(Uri homePage)
    {
        ArgumentNullException.ThrowIfNull(homePage);
        _browserHomePage = homePage;
        _browserWindow?.SetHomePage(homePage);
    }

    internal void SetSettings(InGameMenuSettings settings)
    {
        _settings = settings.Normalize();
        RenderOptions.ProcessRenderMode =
            _settings.EffectiveCompatibilityMode ==
            InGameMenuCompatibilityMode.Software
                ? RenderMode.SoftwareOnly
                : RenderMode.Default;
        _window?.ApplySettings(_settings);
        _browserWindow?.ApplySettings(_settings);
        _imageWindow?.ApplySettings(_settings);

        _friendsWindow?.ApplySettings(_settings);
        _roomWindow?.ApplySettings(_settings);
    }

    internal void SetImageLanguage(string? language)
    {
        _imageLanguage = language?.Trim().StartsWith(
            "zh",
            StringComparison.OrdinalIgnoreCase) == true
            ? "zh"
            : "en";
        _imageWindow?.ApplyLanguage(_imageLanguage);
    }

    internal async Task<bool> ClearBrowserDataAsync()
    {
        if (_browserWindow is null)
        {
            return false;
        }

        await _browserWindow.ClearBrowsingDataAsync();
        return true;
    }

    internal int ResetToolWindowPlacements()
    {
        _toolSessionState = _toolSessionState with
        {
            Placements = new Dictionary<string, InGameToolWindowPlacement>(
                StringComparer.OrdinalIgnoreCase)
        };
        _ = _toolSessionStore.TrySave(_toolSessionState);
        var windows = SessionWindows()
            .Where(window => !ReferenceEquals(window, _window))
            .ToArray();
        foreach (var window in windows)
        {
            MainWindowPlacementService.FitInitialWindow(
                window,
                _window ?? window);
        }

        return windows.Length;
    }

    internal void SetInformationOverlayHotkey(string? displayText)
    {
        _informationOverlayHotkey = displayText?.Trim() ?? "";
        _window?.ApplyInformationOverlayHotkey(
            _informationOverlayHotkey);
    }

    internal void Prepare(
        InGameMenuSnapshot snapshot,
        Rect surfaceBounds,
        bool informationOverlayWasVisible)
    {
        if (_disposed || _window is not null)
        {
            return;
        }

        _informationOverlayWasVisible = informationOverlayWasVisible;
        var window = CreateMenuWindow();
        ApplyMenuState(window, snapshot, surfaceBounds);
        window.PrepareForFirstOpen();
    }

    internal void Open(
        InGameMenuSnapshot snapshot,
        Rect surfaceBounds,
        bool informationOverlayWasVisible)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        _informationOverlayWasVisible = informationOverlayWasVisible;
        _pendingExitMode = InGameMenuExitMode.RestorePreviousOverlay;
        _closingSession = false;
        var window = _window ?? CreateMenuWindow();
        ApplyMenuState(window, snapshot, surfaceBounds);
        _menuSessionOpen = true;
        window.ShowForMenu();
        MarkToolSessionOpen();
        ScheduleToolsRestoreOrMenuActivation(window);
    }

    private void ScheduleToolsRestoreOrMenuActivation(InGameMenuWindow window)
    {
        window.Dispatcher.BeginInvoke(
            DispatcherPriority.Input,
            new Action(() =>
            {
                if (_menuSessionOpen &&
                    !_closingSession &&
                    ReferenceEquals(_window, window))
                {
                    RestoreToolsOrActivateMenu();
                }
            }));
    }

    private InGameMenuWindow CreateMenuWindow()
    {
        var window = new InGameMenuWindow();
        _window = window;
        window.ActionRequested += Window_ActionRequested;
        window.MenuCloseRequested += Window_MenuCloseRequested;
        window.MenuDeactivated += Window_MenuDeactivated;
        window.Closing += Window_Closing;
        window.Closed += Window_Closed;
        return window;
    }

    private void ApplyMenuState(
        InGameMenuWindow window,
        InGameMenuSnapshot snapshot,
        Rect surfaceBounds)
    {
        window.ApplySurfaceBounds(surfaceBounds);
        window.ApplySnapshot(snapshot);
        window.ApplySettings(_settings);
        window.ApplyInformationOverlayHotkey(_informationOverlayHotkey);
        window.ApplyInformationOverlayState(_informationOverlayWasVisible);
    }

    internal void Refresh(InGameMenuSnapshot snapshot, Rect surfaceBounds)
    {
        if (_window is null)
        {
            return;
        }

        _window.ApplySurfaceBounds(surfaceBounds);
        _window.ApplySnapshot(snapshot);
    }

    internal void ShowNotice(
        string text,
        string? detail = null,
        bool isLoading = false) =>
        _window?.ShowNotice(text, detail, isLoading);

    internal void OpenBrowser()
    {
        if (_window is null)
        {
            return;
        }

        _browserRequestedVisible = true;
        _lastActiveTool = ToolKind.Browser;
        if (_browserWindow is not null)
        {
            AttachToolToMenu(_browserWindow);
            _browserWindow.ShowForMenu();
            return;
        }

        var browser = new InGameBrowserWindow(_browserHomePage);
        _browserWindow = browser;
        browser.ApplySettings(_settings);
        browser.Activated += Tool_Activated;
        browser.MenuCloseRequested += Tool_MenuCloseRequested;
        browser.ToolDeactivated += Tool_Deactivated;
        browser.ToolHidden += BrowserWindow_Hidden;
        browser.Closed += BrowserWindow_Closed;
        AttachToolToMenu(browser);
        browser.ShowForMenu();
    }

    internal void OpenImage()
    {
        if (_window is null)
        {
            return;
        }

        _lastActiveTool = ToolKind.Image;
        var image = _imageWindow;
        if (image is not null)
        {
            _imageRequestedVisible = true;
            AttachToolToMenu(image);
            image.ShowForMenu();
            return;
        }

        CreateImageWindow();
    }

    private void OpenImagePath(string path)
    {
        if (_window is null || string.IsNullOrWhiteSpace(path))
        {
            return;
        }

        _lastActiveTool = ToolKind.Image;
        var image = _imageWindow ?? CreateImageWindow(showImmediately: false);

        if (image is null)
        {
            return;
        }

        _imageRequestedVisible = true;
        AttachToolToMenu(image);
        image.LoadImage(path);
        image.ShowForMenu();
    }

    private InGameImageWindow? CreateImageWindow(bool showImmediately = true)
    {
        if (_imageWindow is not null)
        {
            if (showImmediately)
            {
                _imageRequestedVisible = true;
                AttachToolToMenu(_imageWindow);
                _imageWindow.ShowForMenu();
            }

            return _imageWindow;
        }

        var image = new InGameImageWindow();
        image.ApplyLanguage(_imageLanguage);
        image.ApplySettings(_settings);
        _imageWindow = image;
        _imageRequestedVisible = true;
        image.Activated += Tool_Activated;
        image.MenuCloseRequested += Tool_MenuCloseRequested;
        image.ToolDeactivated += Tool_Deactivated;
        image.ToolHidden += ImageWindow_Hidden;
        image.Closed += ImageWindow_Closed;
        AttachToolToMenu(image);
        if (showImmediately)
        {
            image.ShowForMenu();
        }

        return image;
    }

    internal void OpenFleet()
    {
        if (_window is null)
        {
            return;
        }

        _fleetRequestedVisible = true;
        _lastActiveTool = ToolKind.Fleet;
        if (_fleetWindow is not null)
        {
            AttachToolToMenu(_fleetWindow);
            _fleetWindow.ShowForMenu();
            FleetRefreshRequested?.Invoke(this, EventArgs.Empty);
            return;
        }

        var fleet = new InGameFleetWindow();
        _fleetWindow = fleet;
        fleet.ResetAccountState("正在读取组织详情与当前信息", isLoading: true);
        fleet.Activated += Tool_Activated;
        fleet.MenuCloseRequested += Tool_MenuCloseRequested;
        fleet.ToolDeactivated += Tool_Deactivated;
        fleet.ToolHidden += FleetWindow_Hidden;
        fleet.RefreshRequested += FleetWindow_RefreshRequested;
        fleet.CommunicationRequested += FleetWindow_CommunicationRequested;
        fleet.MemberActionRequested += FleetWindow_MemberActionRequested;
        fleet.ShipImageReportRequested += FleetWindow_ShipImageReportRequested;
        fleet.ShipImagePreviewRequested += FleetWindow_ShipImagePreviewRequested;
        fleet.Closed += FleetWindow_Closed;
        AttachToolToMenu(fleet);
        fleet.ShowForMenu();
        FleetRefreshRequested?.Invoke(this, EventArgs.Empty);
    }

    internal void OpenFriends()
    {
        if (_window is null)
        {
            return;
        }

        _friendsRequestedVisible = true;
        _lastActiveTool = ToolKind.Friends;
        if (_friendsWindow is not null)
        {
            AttachToolToMenu(_friendsWindow);
            _friendsWindow.ShowForMenu();
            SocialRefreshRequested?.Invoke(this, EventArgs.Empty);
            return;
        }

        var friends = new InGameFriendsWindow();
        _friendsWindow = friends;
        friends.ApplySettings(_settings);
        friends.Activated += Tool_Activated;
        friends.MenuCloseRequested += Tool_MenuCloseRequested;
        friends.ToolDeactivated += Tool_Deactivated;
        friends.ToolHidden += FriendsWindow_Hidden;
        friends.RefreshRequested += SocialWindow_RefreshRequested;
        friends.ConversationRequested += SocialWindow_ConversationRequested;
        friends.ProfileRequested += FriendsWindow_ProfileRequested;
        friends.FriendSearchRequested += SocialWindow_FriendSearchRequested;
        friends.FriendActionRequested += SocialWindow_FriendActionRequested;
        friends.PresenceChanged += FriendsWindow_PresenceChanged;
        friends.Closed += FriendsWindow_Closed;
        AttachToolToMenu(friends);
        friends.ShowForMenu();
        SocialRefreshRequested?.Invoke(this, EventArgs.Empty);
    }

    internal void OpenProfileWindow(InGameProfileTarget target)
    {
        if (_window is null || string.IsNullOrWhiteSpace(target.Key))
        {
            return;
        }

        _requestedProfileKeys.Add(target.Key);
        _lastActiveTool = ToolKind.Profile;
        if (_profileWindows.TryGetValue(target.Key, out var existing))
        {
            _activeProfileWindow = existing;
            AttachToolToMenu(existing);
            existing.ShowForMenu();
            return;
        }

        var profile = new InGameProfileWindow(target);
        _profileWindows[target.Key] = profile;
        _activeProfileWindow = profile;
        profile.Activated += Tool_Activated;
        profile.MenuCloseRequested += Tool_MenuCloseRequested;
        profile.ToolDeactivated += Tool_Deactivated;
        profile.ToolHidden += ProfileWindow_Hidden;
        profile.Closed += ProfileWindow_Closed;
        AttachToolToMenu(profile);
        profile.ShowForMenu();
    }

    internal bool AttachProfileSurface(
        string profileKey,
        TabItem sourceTab,
        IEnumerable<FrameworkElement> overlays,
        Action? released)
    {
        if (!_profileWindows.TryGetValue(profileKey, out var profile))
        {
            return false;
        }

        foreach (var other in _profileWindows.Values)
        {
            if (!ReferenceEquals(other, profile))
            {
                other.HideForMenu();
                _requestedProfileKeys.Remove(other.ProfileKey);
            }
        }

        _activeProfileWindow = profile;
        profile.AttachProfileSurface(sourceTab, overlays, released);
        return true;
    }

    internal void OpenChat() =>
        OpenSocial(_settings.CommunicationLanding switch
        {
            InGameMenuCommunicationLanding.Channels =>
                InGameSocialSection.Channels,
            InGameMenuCommunicationLanding.LastUsed =>
                _socialSection,
            _ => InGameSocialSection.DirectMessages
        });

    internal void OpenChannels() =>
        OpenSocial(InGameSocialSection.Channels);

    internal void OpenRooms()
    {
        if (_window is null)
        {
            return;
        }

        _roomsRequestedVisible = true;
        _lastActiveTool = ToolKind.Rooms;
        if (_roomWindow is not null)
        {
            AttachToolToMenu(_roomWindow);
            _roomWindow.ShowForMenu();
            RoomRefreshRequested?.Invoke(this, EventArgs.Empty);
            return;
        }

        var rooms = new InGameRoomWindow();
        _roomWindow = rooms;
        rooms.ApplySettings(_settings);
        rooms.Activated += Tool_Activated;
        rooms.MenuCloseRequested += Tool_MenuCloseRequested;
        rooms.ToolDeactivated += Tool_Deactivated;
        rooms.ToolHidden += RoomWindow_Hidden;
        rooms.RefreshRequested += RoomWindow_RefreshRequested;
        rooms.JoinRequested += RoomWindow_JoinRequested;
        rooms.CreateRequested += RoomWindow_CreateRequested;
        rooms.LeaveRequested += RoomWindow_LeaveRequested;
        rooms.MessageRequested += RoomWindow_MessageRequested;
        rooms.AttachmentRequested += RoomWindow_AttachmentRequested;
        rooms.AttachmentActionRequested += ChatWindow_AttachmentActionRequested;
        rooms.InvitationActionRequested += RoomWindow_InvitationActionRequested;
        rooms.Closed += RoomWindow_Closed;
        AttachToolToMenu(rooms);
        rooms.ShowForMenu();
        RoomRefreshRequested?.Invoke(this, EventArgs.Empty);
    }

    internal void ApplyFleetSnapshot(
        InGameFleetSnapshot snapshot,
        AccountSessionLease accountSession)
    {
        if (_requestGate.Accepts(accountSession))
        {
            _fleetWindow?.ApplySnapshot(snapshot);
        }
    }

    internal void ApplySocialSnapshot(
        InGameSocialSnapshot snapshot,
        AccountSessionLease accountSession)
    {
        if (_requestGate.Accepts(accountSession))
        {
            _friendsWindow?.ApplySnapshot(snapshot);
            _socialWindow?.ApplySnapshot(snapshot);
        }
    }

    internal void ApplySocialSnapshot(
        InGameSocialSnapshot snapshot,
        InGameWorkspaceRequest request)
    {
        if (request.IsCurrent)
        {
            _friendsWindow?.ApplySnapshot(snapshot);
            _socialWindow?.ApplySnapshot(snapshot);
        }
    }

    internal void ApplyRoomSnapshot(
        InGameRoomSnapshot snapshot,
        AccountSessionLease accountSession)
    {
        if (_requestGate.Accepts(accountSession))
        {
            _roomWindow?.ApplySnapshot(snapshot);
        }
    }

    internal void ApplyRoomSnapshot(
        InGameRoomSnapshot snapshot,
        InGameWorkspaceRequest request)
    {
        if (request.IsCurrent)
        {
            _roomWindow?.ApplySnapshot(snapshot);
        }
    }

    internal void ShowRoomStatus(string text, bool isLoading = false) =>
        _roomWindow?.SetStatus(text, isLoading);

    internal void ShowSocialStatus(string text) =>
        _socialWindow?.SetStatus(text);

    internal void ShowRoomInvitationStatus(string text, bool isLoading = false) =>
        _roomWindow?.SetInvitationStatus(text, isLoading);

    // Compatibility shims for profile requests created before the profile
    // surface was unified. The live application page now owns these updates.
    internal void ApplyProfileSnapshot(
        InGameProfileSnapshot snapshot,
        AccountSessionLease accountSession)
    {
    }

    internal void SetProfileSaveState(
        string profileKey,
        string statusText,
        bool isBusy,
        bool closeEditor)
    {
    }

    internal void UpdateProfileAvatar(
        string profileKey,
        string? avatarSource,
        string fallback)
    {
    }

    internal bool IsSocialConversationVisible(string? accountId) =>
        _socialWindow is
        {
            IsShowingConversation: true,
            ActiveConversationAccountId: { } activeId
        } &&
        !string.IsNullOrWhiteSpace(accountId) &&
        activeId.Equals(accountId, StringComparison.OrdinalIgnoreCase);

    private void OpenSocial(InGameSocialSection section)
    {
        if (_window is null)
        {
            return;
        }

        _socialRequestedVisible = true;
        _socialSection = section;
        _lastActiveTool = ToolKind.Social;
        if (_socialWindow is not null)
        {
            AttachToolToMenu(_socialWindow);
            _socialWindow.ShowForMenu(section);
            SocialRefreshRequested?.Invoke(this, EventArgs.Empty);
            return;
        }

        var social = new InGameSocialWindow();
        _socialWindow = social;
        social.Activated += Tool_Activated;
        social.MenuCloseRequested += Tool_MenuCloseRequested;
        social.ToolDeactivated += Tool_Deactivated;
        social.ToolHidden += SocialWindow_Hidden;
        social.RefreshRequested += SocialWindow_RefreshRequested;
        social.ConversationRequested += SocialWindow_ConversationRequested;
        social.ChannelRequested += SocialWindow_ChannelRequested;
        social.MessageRequested += SocialWindow_MessageRequested;
        social.AttachmentRequested += SocialWindow_AttachmentRequested;
        social.AttachmentActionRequested += ChatWindow_AttachmentActionRequested;
        social.FriendSearchRequested += SocialWindow_FriendSearchRequested;
        social.FriendActionRequested += SocialWindow_FriendActionRequested;
        social.Closed += SocialWindow_Closed;
        AttachToolToMenu(social);
        social.ShowForMenu(section);
        SocialRefreshRequested?.Invoke(this, EventArgs.Empty);
    }

    internal async Task<T> RunWithSessionHiddenAsync<T>(Func<Task<T>> action)
    {
        ArgumentNullException.ThrowIfNull(action);
        if (_window is null)
        {
            throw new InvalidOperationException("游戏时菜单尚未打开。");
        }

        if (_captureInProgress)
        {
            throw new InvalidOperationException("截屏正在处理中。");
        }

        _captureInProgress = true;
        try
        {
            return await InGameScreenshotCaptureSession.RunAsync(
                SessionWindows(),
                _window.Dispatcher,
                action);
        }
        finally
        {
            _captureInProgress = false;
            ActivateSessionWindow();
        }
    }

    internal void Close(InGameMenuExitMode mode)
    {
        var window = _window;
        if (window is null ||
            _closingSession ||
            mode != InGameMenuExitMode.ApplicationClosing &&
            !_menuSessionOpen)
        {
            return;
        }

        _closingSession = true;
        _pendingExitMode = mode;
        CaptureToolSessionState(sessionWasOpen: false);
        if (mode == InGameMenuExitMode.ApplicationClosing)
        {
            ClosePersistentToolsForApplication();
        }
        else
        {
            HidePersistentTools();
        }

        TryCloseWindow(window);
        if (_window is not null)
        {
            _closingSession = false;
        }
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        _closingSession = true;
        _pendingExitMode = InGameMenuExitMode.ApplicationClosing;
        CaptureToolSessionState(sessionWasOpen: false);
        _requestGate.Dispose();
        ClosePersistentToolsForApplication();
        TryCloseWindow(_window);
        _window = null;
    }

    private IEnumerable<Window> SessionWindows()
    {
        if (_window is not null)
        {
            yield return _window;
        }

        if (_browserWindow is not null)
        {
            yield return _browserWindow;
        }

        if (_imageWindow is not null)
        {
            yield return _imageWindow;
        }

        if (_fleetWindow is not null)
        {
            yield return _fleetWindow;
        }

        if (_friendsWindow is not null)
        {
            yield return _friendsWindow;
        }

        foreach (var profile in _profileWindows.Values)
        {
            yield return profile;
        }

        if (_socialWindow is not null)
        {
            yield return _socialWindow;
        }

        if (_roomWindow is not null)
        {
            yield return _roomWindow;
        }
    }

    private void ActivateSessionWindow()
    {
        if (_closingSession)
        {
            return;
        }

        if (_settings.RestoreLastFocusedTool &&
            _lastActiveTool == ToolKind.Browser &&
            _browserWindow is { IsVisible: true })
        {
            RestoreAndActivate(_browserWindow);
            return;
        }

        if (_settings.RestoreLastFocusedTool &&
            _lastActiveTool == ToolKind.Image &&
            _imageWindow is { IsVisible: true })
        {
            RestoreAndActivate(_imageWindow);
            return;
        }

        if (_settings.RestoreLastFocusedTool &&
            _lastActiveTool == ToolKind.Fleet &&
            _fleetWindow is { IsVisible: true })
        {
            RestoreAndActivate(_fleetWindow);
            return;
        }

        if (_settings.RestoreLastFocusedTool &&
            _lastActiveTool == ToolKind.Friends &&
            _friendsWindow is { IsVisible: true })
        {
            RestoreAndActivate(_friendsWindow);
            return;
        }

        if (_settings.RestoreLastFocusedTool &&
            _lastActiveTool == ToolKind.Profile &&
            _activeProfileWindow is { IsVisible: true })
        {
            RestoreAndActivate(_activeProfileWindow);
            return;
        }

        if (_settings.RestoreLastFocusedTool &&
            _lastActiveTool == ToolKind.Social &&
            _socialWindow is { IsVisible: true })
        {
            RestoreAndActivate(_socialWindow);
            return;
        }

        if (_settings.RestoreLastFocusedTool &&
            _lastActiveTool == ToolKind.Rooms &&
            _roomWindow is { IsVisible: true })
        {
            RestoreAndActivate(_roomWindow);
            return;
        }

        if (_browserWindow is { IsVisible: true })
        {
            RestoreAndActivate(_browserWindow);
            return;
        }

        if (_imageWindow is { IsVisible: true } visibleImage)
        {
            RestoreAndActivate(visibleImage);
            return;
        }

        if (_fleetWindow is { IsVisible: true })
        {
            RestoreAndActivate(_fleetWindow);
            return;
        }

        if (_friendsWindow is { IsVisible: true })
        {
            RestoreAndActivate(_friendsWindow);
            return;
        }

        var visibleProfile = _profileWindows.Values.LastOrDefault(profile => profile.IsVisible);
        if (visibleProfile is not null)
        {
            _activeProfileWindow = visibleProfile;
            RestoreAndActivate(visibleProfile);
            return;
        }

        if (_socialWindow is { IsVisible: true })
        {
            RestoreAndActivate(_socialWindow);
            return;
        }

        if (_roomWindow is { IsVisible: true })
        {
            RestoreAndActivate(_roomWindow);
            return;
        }

        if (_window is { IsVisible: true } window)
        {
            RestoreAndActivate(window);
        }
    }

    private static void RestoreAndActivate(Window window)
    {
        if (window.WindowState == WindowState.Minimized)
        {
            window.WindowState = WindowState.Normal;
        }

        window.Activate();
        if (window is InGameMenuWindow menu)
        {
            menu.TakeInputOwnership();
        }
    }

    private void ScheduleFocusCheck()
    {
        if (_focusCheckPending || _window is null)
        {
            return;
        }

        _focusCheckPending = true;
        _window.Dispatcher.BeginInvoke(() =>
        {
            _focusCheckPending = false;
            if (_closingSession ||
                _captureInProgress ||
                _transientInteractionDepth > 0 ||
                _imageWindow is { IsChoosingImage: true } ||
                SessionWindows().Any(window => window.IsActive) ||
                 ForegroundWindowBelongsToSession())
            {
                return;
            }

            Close(InGameMenuExitMode.Deactivated);
        }, DispatcherPriority.ContextIdle);
    }

    private void Window_ActionRequested(object? sender, InGameMenuActionRequestedEventArgs e)
    {
        if (e.Action != InGameMenuAction.ToggleInformationOverlay)
        {
            ActionRequested?.Invoke(this, e);
            return;
        }

        if (_informationOverlayWasVisible)
        {
            _informationOverlayWasVisible = false;
            _window?.ApplyInformationOverlayState(false);
            var detail = string.IsNullOrWhiteSpace(
                _informationOverlayHotkey)
                ? "可从菜单再次打开信息浮层"
                : $"快捷键 {_informationOverlayHotkey} 可随时切换信息浮层";
            ShowNotice("信息浮层已关闭", detail);
            return;
        }

        Close(InGameMenuExitMode.SwitchToInformationOverlay);
    }

    private void Window_MenuCloseRequested(object? sender, EventArgs e) =>
        Close(InGameMenuExitMode.RestorePreviousOverlay);

    private void Window_MenuDeactivated(object? sender, EventArgs e) =>
        ScheduleFocusCheck();

    private void Window_Closing(object? sender, System.ComponentModel.CancelEventArgs e)
    {
        if (!_closingSession)
        {
            CaptureToolSessionState(sessionWasOpen: false);
        }

        DetachPersistentToolOwners();
    }

    private void Tool_MenuCloseRequested(object? sender, EventArgs e) =>
        Close(InGameMenuExitMode.RestorePreviousOverlay);

    private void Tool_Deactivated(object? sender, EventArgs e) =>
        ScheduleFocusCheck();

    private void Tool_Activated(object? sender, EventArgs e)
    {
        switch (sender)
        {
            case InGameBrowserWindow:
                _lastActiveTool = ToolKind.Browser;
                break;
            case InGameImageWindow:
                _lastActiveTool = ToolKind.Image;
                break;
            case InGameFleetWindow:
                _lastActiveTool = ToolKind.Fleet;
                break;
            case InGameFriendsWindow:
                _lastActiveTool = ToolKind.Friends;
                break;
            case InGameProfileWindow profile:
                _activeProfileWindow = profile;
                _lastActiveTool = ToolKind.Profile;
                break;
            case InGameSocialWindow:
                _lastActiveTool = ToolKind.Social;
                break;
            case InGameRoomWindow:
                _lastActiveTool = ToolKind.Rooms;
                break;
        }
    }

    private void BrowserWindow_Hidden(object? sender, EventArgs e)
    {
        _browserRequestedVisible = false;
        ActivateSessionWindow();
    }

    private void ImageWindow_Hidden(object? sender, EventArgs e)
    {
        if (ReferenceEquals(_imageWindow, sender))
        {
            _imageRequestedVisible = false;
        }

        ActivateSessionWindow();
    }

    private void FleetWindow_Hidden(object? sender, EventArgs e)
    {
        _fleetRequestedVisible = false;
        ActivateSessionWindow();
    }

    private void FleetWindow_RefreshRequested(object? sender, EventArgs e) =>
        FleetRefreshRequested?.Invoke(this, EventArgs.Empty);

    private void FleetWindow_CommunicationRequested(object? sender, EventArgs e)
    {
        OpenChannels();
        FleetCommunicationRequested?.Invoke(this, EventArgs.Empty);
    }

    private void FleetWindow_MemberActionRequested(
        object? sender,
        InGameFleetMemberActionRequestedEventArgs e)
    {
        if (e.Action == InGameFleetMemberAction.SendMessage)
        {
            FleetMemberActionRequested?.Invoke(this, e);
            return;
        }

        var member = e.Member;
        var profileKey = member.IsSelf ? "self" : member.AccountId ?? "";
        if (!member.CanOpenProfile || string.IsNullOrWhiteSpace(profileKey))
        {
            return;
        }

        var target = new InGameProfileTarget(
            profileKey,
            member.IsSelf,
            member.Callsign,
            member.GameId,
            member.AvatarSource,
            member.Initials,
            member.PresenceText,
            member.PresenceBrush);
        OpenProfileWindow(target);
        ProfileRequested?.Invoke(this, new InGameProfileRequestedEventArgs(target));
    }

    private void FleetWindow_ShipImageReportRequested(
        object? sender,
        InGameFleetShipImageReportRequestedEventArgs e) =>
        FleetShipImageReportRequested?.Invoke(this, e);

    private void FleetWindow_ShipImagePreviewRequested(
        object? sender,
        InGameFleetShipImagePreviewRequestedEventArgs e)
    {
        if (!string.IsNullOrWhiteSpace(e.Ship.ImageSource))
        {
            OpenImagePath(e.Ship.ImageSource);
        }
    }

    private void FriendsWindow_Hidden(object? sender, EventArgs e)
    {
        _friendsRequestedVisible = false;
        ActivateSessionWindow();
    }

    private void ProfileWindow_Hidden(object? sender, EventArgs e)
    {
        if (sender is InGameProfileWindow profile)
        {
            _requestedProfileKeys.Remove(profile.ProfileKey);
        }

        if (ReferenceEquals(_activeProfileWindow, sender))
        {
            _activeProfileWindow = _profileWindows.Values
                .LastOrDefault(candidate => candidate.IsVisible);
        }

        ActivateSessionWindow();
    }

    private void FriendsWindow_PresenceChanged(
        object? sender,
        InGameFriendPresenceChangedEventArgs e) =>
        FriendPresenceChanged?.Invoke(this, e);

    private void SocialWindow_Hidden(object? sender, EventArgs e)
    {
        _socialRequestedVisible = false;
        ActivateSessionWindow();
    }

    private void SocialWindow_RefreshRequested(object? sender, EventArgs e) =>
        SocialRefreshRequested?.Invoke(this, EventArgs.Empty);

    private void SocialWindow_ConversationRequested(
        object? sender,
        InGameSocialConversationRequestedEventArgs e) =>
        SocialConversationRequested?.Invoke(this, e);

    private void FriendsWindow_ProfileRequested(
        object? sender,
        InGameProfileRequestedEventArgs e)
    {
        OpenProfileWindow(e.Target);
        ProfileRequested?.Invoke(this, e);
    }

    private void SocialWindow_ChannelRequested(
        object? sender,
        InGameSocialChannelRequestedEventArgs e) =>
        SocialChannelRequested?.Invoke(this, e);

    private void SocialWindow_MessageRequested(
        object? sender,
        InGameSocialMessageRequestedEventArgs e) =>
        SocialMessageRequested?.Invoke(this, e);

    private void SocialWindow_AttachmentRequested(
        object? sender,
        InGameSocialAttachmentRequestedEventArgs e) =>
        SocialAttachmentRequested?.Invoke(this, e);

    private void ChatWindow_AttachmentActionRequested(
        object? sender,
        InGameChatAttachmentActionRequestedEventArgs e) =>
        ChatAttachmentActionRequested?.Invoke(this, e);

    private void SocialWindow_FriendSearchRequested(
        object? sender,
        InGameSocialFriendSearchRequestedEventArgs e) =>
        FriendSearchRequested?.Invoke(this, e);

    private void SocialWindow_FriendActionRequested(
        object? sender,
        InGameSocialFriendActionRequestedEventArgs e) =>
        FriendActionRequested?.Invoke(this, e);

    private void RoomWindow_Hidden(object? sender, EventArgs e)
    {
        _roomsRequestedVisible = false;
        ActivateSessionWindow();
    }

    private void RoomWindow_RefreshRequested(object? sender, EventArgs e) =>
        RoomRefreshRequested?.Invoke(this, EventArgs.Empty);

    private void RoomWindow_JoinRequested(
        object? sender,
        InGameRoomJoinRequestedEventArgs e) =>
        RoomJoinRequested?.Invoke(this, e);

    private void RoomWindow_CreateRequested(
        object? sender,
        InGameRoomCreateRequestedEventArgs e) =>
        RoomCreateRequested?.Invoke(this, e);

    private void RoomWindow_LeaveRequested(object? sender, EventArgs e) =>
        RoomLeaveRequested?.Invoke(this, EventArgs.Empty);

    private void RoomWindow_MessageRequested(
        object? sender,
        InGameRoomMessageRequestedEventArgs e) =>
        RoomMessageRequested?.Invoke(this, e);

    private void RoomWindow_AttachmentRequested(
        object? sender,
        InGameRoomAttachmentRequestedEventArgs e) =>
        RoomAttachmentRequested?.Invoke(this, e);

    private void RoomWindow_InvitationActionRequested(
        object? sender,
        InGameRoomInvitationActionRequestedEventArgs e) =>
        RoomInvitationActionRequested?.Invoke(this, e);

    private void ToolWindow_MoveLoopChanged(Window window, bool isMoving)
    {
        if (isMoving)
        {
            _movingToolWindows.Add(window);
        }
        else
        {
            _movingToolWindows.Remove(window);
        }

        _window?.SetToolMoveMode(
            _settings.PauseUpdatesWhileDragging &&
            _movingToolWindows.Count > 0);
        if (!isMoving && _settings.SnapToolWindows)
        {
            MainWindowPlacementService.SnapToWorkingArea(
                window,
                _window ?? window,
                _settings.SnapDistance);
        }

        if (!isMoving && _settings.RememberWindowPlacement)
        {
            SaveWindowPlacement(window);
        }
    }

    private void BrowserWindow_Closed(object? sender, EventArgs e)
    {
        if (sender is InGameBrowserWindow browser)
        {
            browser.Activated -= Tool_Activated;
            browser.MenuCloseRequested -= Tool_MenuCloseRequested;
            browser.ToolDeactivated -= Tool_Deactivated;
            browser.ToolHidden -= BrowserWindow_Hidden;
            browser.Closed -= BrowserWindow_Closed;
        }

        if (ReferenceEquals(_browserWindow, sender))
        {
            _browserWindow = null;
        }

        ActivateSessionWindow();
    }

    private void ImageWindow_Closed(object? sender, EventArgs e)
    {
        if (sender is InGameImageWindow image)
        {
            image.Activated -= Tool_Activated;
            image.MenuCloseRequested -= Tool_MenuCloseRequested;
            image.ToolDeactivated -= Tool_Deactivated;
            image.ToolHidden -= ImageWindow_Hidden;
            image.Closed -= ImageWindow_Closed;
        }

        if (ReferenceEquals(_imageWindow, sender))
        {
            _imageWindow = null;
            _imageRequestedVisible = false;
        }

        ActivateSessionWindow();
    }

    private void FleetWindow_Closed(object? sender, EventArgs e)
    {
        if (sender is InGameFleetWindow fleet)
        {
            fleet.Activated -= Tool_Activated;
            fleet.MenuCloseRequested -= Tool_MenuCloseRequested;
            fleet.ToolDeactivated -= Tool_Deactivated;
            fleet.ToolHidden -= FleetWindow_Hidden;
            fleet.RefreshRequested -= FleetWindow_RefreshRequested;
            fleet.CommunicationRequested -= FleetWindow_CommunicationRequested;
            fleet.MemberActionRequested -= FleetWindow_MemberActionRequested;
            fleet.ShipImageReportRequested -= FleetWindow_ShipImageReportRequested;
            fleet.ShipImagePreviewRequested -= FleetWindow_ShipImagePreviewRequested;
            fleet.Closed -= FleetWindow_Closed;
        }

        if (ReferenceEquals(_fleetWindow, sender))
        {
            _fleetWindow = null;
        }

        ActivateSessionWindow();
    }

    private void SocialWindow_Closed(object? sender, EventArgs e)
    {
        if (sender is InGameSocialWindow social)
        {
            social.Activated -= Tool_Activated;
            social.MenuCloseRequested -= Tool_MenuCloseRequested;
            social.ToolDeactivated -= Tool_Deactivated;
            social.ToolHidden -= SocialWindow_Hidden;
            social.RefreshRequested -= SocialWindow_RefreshRequested;
            social.ConversationRequested -= SocialWindow_ConversationRequested;
            social.ChannelRequested -= SocialWindow_ChannelRequested;
            social.MessageRequested -= SocialWindow_MessageRequested;
            social.AttachmentRequested -= SocialWindow_AttachmentRequested;
            social.AttachmentActionRequested -= ChatWindow_AttachmentActionRequested;
            social.FriendSearchRequested -= SocialWindow_FriendSearchRequested;
            social.FriendActionRequested -= SocialWindow_FriendActionRequested;
            social.Closed -= SocialWindow_Closed;
        }

        if (ReferenceEquals(_socialWindow, sender))
        {
            _socialWindow = null;
        }

        ActivateSessionWindow();
    }

    private void FriendsWindow_Closed(object? sender, EventArgs e)
    {
        if (sender is InGameFriendsWindow friends)
        {
            friends.Activated -= Tool_Activated;
            friends.MenuCloseRequested -= Tool_MenuCloseRequested;
            friends.ToolDeactivated -= Tool_Deactivated;
            friends.ToolHidden -= FriendsWindow_Hidden;
            friends.RefreshRequested -= SocialWindow_RefreshRequested;
            friends.ConversationRequested -= SocialWindow_ConversationRequested;
            friends.ProfileRequested -= FriendsWindow_ProfileRequested;
            friends.FriendSearchRequested -= SocialWindow_FriendSearchRequested;
            friends.FriendActionRequested -= SocialWindow_FriendActionRequested;
            friends.PresenceChanged -= FriendsWindow_PresenceChanged;
            friends.Closed -= FriendsWindow_Closed;
        }

        if (ReferenceEquals(_friendsWindow, sender))
        {
            _friendsWindow = null;
        }

        ActivateSessionWindow();
    }

    private void ProfileWindow_Closed(object? sender, EventArgs e)
    {
        if (sender is not InGameProfileWindow profile)
        {
            return;
        }

        profile.Activated -= Tool_Activated;
        profile.MenuCloseRequested -= Tool_MenuCloseRequested;
        profile.ToolDeactivated -= Tool_Deactivated;
        profile.ToolHidden -= ProfileWindow_Hidden;
        profile.Closed -= ProfileWindow_Closed;
        _profileWindows.Remove(profile.ProfileKey);
        _requestedProfileKeys.Remove(profile.ProfileKey);
        if (ReferenceEquals(_activeProfileWindow, profile))
        {
            _activeProfileWindow = _profileWindows.Values.LastOrDefault();
        }

        ActivateSessionWindow();
    }

    private void RoomWindow_Closed(object? sender, EventArgs e)
    {
        if (sender is InGameRoomWindow rooms)
        {
            rooms.Activated -= Tool_Activated;
            rooms.MenuCloseRequested -= Tool_MenuCloseRequested;
            rooms.ToolDeactivated -= Tool_Deactivated;
            rooms.ToolHidden -= RoomWindow_Hidden;
            rooms.RefreshRequested -= RoomWindow_RefreshRequested;
            rooms.JoinRequested -= RoomWindow_JoinRequested;
            rooms.CreateRequested -= RoomWindow_CreateRequested;
            rooms.LeaveRequested -= RoomWindow_LeaveRequested;
            rooms.MessageRequested -= RoomWindow_MessageRequested;
            rooms.AttachmentRequested -= RoomWindow_AttachmentRequested;
            rooms.AttachmentActionRequested -= ChatWindow_AttachmentActionRequested;
            rooms.InvitationActionRequested -= RoomWindow_InvitationActionRequested;
            rooms.Closed -= RoomWindow_Closed;
        }

        if (ReferenceEquals(_roomWindow, sender))
        {
            _roomWindow = null;
        }

        ActivateSessionWindow();
    }

    private void Window_Closed(object? sender, EventArgs e)
    {
        var closedOpenSession = _menuSessionOpen;
        _menuSessionOpen = false;
        _closingSession = true;
        if (sender is InGameMenuWindow window)
        {
            window.ActionRequested -= Window_ActionRequested;
            window.MenuCloseRequested -= Window_MenuCloseRequested;
            window.MenuDeactivated -= Window_MenuDeactivated;
            window.Closing -= Window_Closing;
            window.Closed -= Window_Closed;
        }

        if (closedOpenSession)
        {
            HidePersistentTools();
        }

        _window = null;
        try
        {
            if (closedOpenSession)
            {
                Closed?.Invoke(
                    this,
                    new InGameMenuClosedEventArgs(
                        _pendingExitMode,
                        _informationOverlayWasVisible));
            }
        }
        finally
        {
            _informationOverlayWasVisible = false;
            _pendingExitMode = InGameMenuExitMode.RestorePreviousOverlay;
            _closingSession = false;
            _focusCheckPending = false;
            _movingToolWindows.Clear();
        }
    }

    private static void TryCloseWindow(Window? window)
    {
        if (window is null)
        {
            return;
        }

        try
        {
            window.Close();
        }
        catch (Exception exception)
        {
            App.WriteCrashLog(exception);
        }
    }

    private void RestorePersistentTools()
    {
        if (_browserRequestedVisible && _browserWindow is not null)
        {
            AttachToolToMenu(_browserWindow);
            _browserWindow.ShowForMenu();
        }

        if (_imageRequestedVisible &&
            _imageWindow is { HasImage: true } image)
        {
            AttachToolToMenu(image);
            image.ShowForMenu();
        }

        if (_fleetRequestedVisible && _fleetWindow is not null)
        {
            AttachToolToMenu(_fleetWindow);
            _fleetWindow.ShowForMenu();
            FleetRefreshRequested?.Invoke(this, EventArgs.Empty);
        }

        if (_friendsRequestedVisible && _friendsWindow is not null)
        {
            AttachToolToMenu(_friendsWindow);
            _friendsWindow.ShowForMenu();
        }

        foreach (var profileKey in _requestedProfileKeys.ToArray())
        {
            if (_profileWindows.TryGetValue(profileKey, out var profile))
            {
                AttachToolToMenu(profile);
                profile.ShowForMenu();
            }
        }

        if (_socialRequestedVisible && _socialWindow is not null)
        {
            AttachToolToMenu(_socialWindow);
            _socialWindow.ShowForMenu(_socialSection);
        }

        if (_roomsRequestedVisible && _roomWindow is not null)
        {
            AttachToolToMenu(_roomWindow);
            _roomWindow.ShowForMenu();
        }

        ActivateSessionWindow();
    }

    private void RestoreToolsOrActivateMenu()
    {
        RestoreCrossRestartToolsOnce();
        if (_settings.RestoreOpenTools)
        {
            RestorePersistentTools();
            return;
        }

        ActivateSessionWindow();
    }

    private void RestoreCrossRestartToolsOnce()
    {
        if (_restoredCrossRestartSession)
        {
            return;
        }

        _restoredCrossRestartSession = true;
        if (!_settings.RestoreToolsAcrossRestarts ||
            _settings.IsSafeModeSession)
        {
            return;
        }

        if (_previousSessionEndedUnexpectedly)
        {
            var restoreAfterCrash = _settings.CrashRecoveryMode switch
            {
                InGameMenuCrashRecoveryMode.Restore => true,
                InGameMenuCrashRecoveryMode.StartClean => false,
                _ => System.Windows.MessageBox.Show(
                         _window,
                         "上次菜单浮层没有正常结束。是否恢复当时打开的工具窗口？",
                         "恢复菜单浮层",
                         MessageBoxButton.YesNo,
                         MessageBoxImage.Question,
                         MessageBoxResult.No) ==
                     MessageBoxResult.Yes
            };
            if (!restoreAfterCrash)
            {
                _toolSessionState = _toolSessionState with
                {
                    OpenTools = [],
                    LastFocusedTool = ""
                };
                _ = _toolSessionStore.TrySave(_toolSessionState);
                return;
            }
        }

        ToolKind? restoredLastFocused = null;
        if (_settings.RestoreLastFocusedTool &&
            Enum.TryParse<ToolKind>(
                _toolSessionState.LastFocusedTool,
                ignoreCase: true,
                out var lastFocused))
        {
            restoredLastFocused = lastFocused;
        }

        var openTools = _toolSessionState.OpenTools.ToHashSet(
            StringComparer.OrdinalIgnoreCase);
        if (openTools.Contains(nameof(ToolKind.Browser)) &&
            _settings.ShowBrowserTool)
        {
            OpenBrowser();
        }

        if (openTools.Contains(nameof(ToolKind.Fleet)) &&
            _settings.ShowFleetTool)
        {
            OpenFleet();
        }

        if (openTools.Contains(nameof(ToolKind.Friends)) &&
            _settings.ShowFriendsTool)
        {
            OpenFriends();
        }

        if (openTools.Contains(nameof(ToolKind.Social)) &&
            _settings.ShowChatTool)
        {
            if (Enum.TryParse<InGameSocialSection>(
                    _toolSessionState.SocialSection,
                    ignoreCase: true,
                    out var section) &&
                section == InGameSocialSection.Channels)
            {
                OpenChannels();
            }
            else
            {
                OpenChat();
            }
        }

        if (openTools.Contains(nameof(ToolKind.Rooms)) &&
            _settings.ShowRoomsTool)
        {
            OpenRooms();
        }

        if (restoredLastFocused is not null)
        {
            _lastActiveTool = restoredLastFocused;
        }
    }

    private void MarkToolSessionOpen()
    {
        _toolSessionState = _toolSessionState with
        {
            SessionWasOpen = true
        };
        _ = _toolSessionStore.TrySave(_toolSessionState);
    }

    private void CaptureToolSessionState(bool sessionWasOpen)
    {
        var openTools = new List<string>();
        if (_browserRequestedVisible)
        {
            openTools.Add(nameof(ToolKind.Browser));
        }

        if (_fleetRequestedVisible)
        {
            openTools.Add(nameof(ToolKind.Fleet));
        }

        if (_friendsRequestedVisible)
        {
            openTools.Add(nameof(ToolKind.Friends));
        }

        if (_socialRequestedVisible)
        {
            openTools.Add(nameof(ToolKind.Social));
        }

        if (_roomsRequestedVisible)
        {
            openTools.Add(nameof(ToolKind.Rooms));
        }

        var placements = new Dictionary<string, InGameToolWindowPlacement>(
            _toolSessionState.Placements,
            StringComparer.OrdinalIgnoreCase);
        if (_settings.RememberWindowPlacement)
        {
            foreach (var window in SessionWindows())
            {
                if (window.WindowState == WindowState.Normal &&
                    TryResolveWindowKey(window, out var key))
                {
                    placements[key] = InGameToolWindowPlacement.FromBounds(
                        MainWindowPlacementService.ReadBounds(window));
                }
            }
        }

        _toolSessionState = _toolSessionState with
        {
            Placements = placements,
            OpenTools = openTools.ToArray(),
            LastFocusedTool = _lastActiveTool?.ToString() ?? "",
            SocialSection = _socialSection.ToString(),
            SessionWasOpen = sessionWasOpen
        };
        _ = _toolSessionStore.TrySave(_toolSessionState);
    }

    private void SaveWindowPlacement(Window window)
    {
        if (window.WindowState != WindowState.Normal ||
            !TryResolveWindowKey(window, out var key))
        {
            return;
        }

        var placements = new Dictionary<string, InGameToolWindowPlacement>(
            _toolSessionState.Placements,
            StringComparer.OrdinalIgnoreCase)
        {
            [key] = InGameToolWindowPlacement.FromBounds(
                MainWindowPlacementService.ReadBounds(window))
        };
        _toolSessionState = _toolSessionState with
        {
            Placements = placements
        };
        _ = _toolSessionStore.TrySave(_toolSessionState);
    }

    private bool TryResolveWindowKey(Window window, out string key)
    {
        switch (window)
        {
            case InGameBrowserWindow:
                key = "browser";
                return true;
            case InGameFleetWindow:
                key = "fleet";
                return true;
            case InGameFriendsWindow:
                key = "friends";
                return true;
            case InGameSocialWindow:
                key = "social";
                return true;
            case InGameRoomWindow:
                key = "rooms";
                return true;
            case InGameProfileWindow profile:
                key = $"profile:{profile.ProfileKey}";
                return true;
            case InGameImageWindow:
                key = "image";
                return true;
            default:
                key = "";
                return false;
        }
    }

    private void HidePersistentTools()
    {
        DetachPersistentToolOwners();
        _browserWindow?.HideForMenu();
        _imageWindow?.HideForMenu();

        _fleetWindow?.HideForMenu();
        _friendsWindow?.HideForMenu();
        foreach (var profile in _profileWindows.Values)
        {
            profile.HideForMenu();
        }
        _socialWindow?.HideForMenu();
        _roomWindow?.HideForMenu();
    }

    private void ClosePersistentToolsForApplication()
    {
        DetachPersistentToolOwners();
        var browser = _browserWindow;
        var image = _imageWindow;
        var fleet = _fleetWindow;
        var friends = _friendsWindow;
        var profiles = _profileWindows.Values.ToArray();
        var social = _socialWindow;
        var rooms = _roomWindow;
        _browserWindow = null;
        _imageWindow = null;
        _imageRequestedVisible = false;
        _fleetWindow = null;
        _friendsWindow = null;
        _profileWindows.Clear();
        _requestedProfileKeys.Clear();
        _activeProfileWindow = null;
        _socialWindow = null;
        _roomWindow = null;
        _browserRequestedVisible = false;
        _fleetRequestedVisible = false;
        _friendsRequestedVisible = false;
        _socialRequestedVisible = false;
        _roomsRequestedVisible = false;
        TryCloseForApplication(browser);
        TryCloseForApplication(image);

        TryCloseForApplication(fleet);
        TryCloseForApplication(friends);
        foreach (var profile in profiles)
        {
            TryCloseForApplication(profile);
        }
        TryCloseForApplication(social);
        TryCloseForApplication(rooms);
    }

    private void AttachToolToMenu(Window toolWindow)
    {
        if (_window is not null)
        {
            var fitInitial = !toolWindow.IsLoaded;
            InGameToolWindowBehavior.SetTransientOwner(toolWindow, _window);
            InGameToolWindowBehavior.TrackMoveLoop(toolWindow, ToolWindow_MoveLoopChanged);
            if (fitInitial &&
                _settings.RememberWindowPlacement &&
                TryResolveWindowKey(toolWindow, out var windowKey) &&
                _toolSessionState.Placements.TryGetValue(
                    windowKey,
                    out var placement))
            {
                MainWindowPlacementService.Restore(
                    toolWindow,
                    placement.ToBounds(),
                    _window);
            }
            else if (fitInitial)
            {
                MainWindowPlacementService.FitInitialWindow(toolWindow, _window);
            }
            else if (_settings.FitToolsToGameDisplay)
            {
                MainWindowPlacementService.EnsureVisible(toolWindow, _window);
            }
        }
    }

    private void DetachPersistentToolOwners()
    {
        if (_browserWindow is not null)
        {
            InGameToolWindowBehavior.SetTransientOwner(_browserWindow, null);
        }

        if (_imageWindow is not null)
        {
            InGameToolWindowBehavior.SetTransientOwner(_imageWindow, null);
        }

        if (_fleetWindow is not null)
        {
            InGameToolWindowBehavior.SetTransientOwner(_fleetWindow, null);
        }

        if (_friendsWindow is not null)
        {
            InGameToolWindowBehavior.SetTransientOwner(_friendsWindow, null);
        }

        foreach (var profile in _profileWindows.Values)
        {
            InGameToolWindowBehavior.SetTransientOwner(profile, null);
        }

        if (_socialWindow is not null)
        {
            InGameToolWindowBehavior.SetTransientOwner(_socialWindow, null);
        }

        if (_roomWindow is not null)
        {
            InGameToolWindowBehavior.SetTransientOwner(_roomWindow, null);
        }
    }

    private static void TryCloseForApplication(InGameBrowserWindow? window)
    {
        if (window is null)
        {
            return;
        }

        try
        {
            window.CloseForApplication();
        }
        catch (Exception exception)
        {
            App.WriteCrashLog(exception);
        }
    }

    private static void TryCloseForApplication(InGameImageWindow? window)
    {
        if (window is null)
        {
            return;
        }

        try
        {
            window.CloseForApplication();
        }
        catch (Exception exception)
        {
            App.WriteCrashLog(exception);
        }
    }

    private static void TryCloseForApplication(InGameFleetWindow? window)
    {
        if (window is null)
        {
            return;
        }

        try
        {
            window.CloseForApplication();
        }
        catch (Exception exception)
        {
            App.WriteCrashLog(exception);
        }
    }

    private static void TryCloseForApplication(InGameSocialWindow? window)
    {
        if (window is null)
        {
            return;
        }

        try
        {
            window.CloseForApplication();
        }
        catch (Exception exception)
        {
            App.WriteCrashLog(exception);
        }
    }

    private static void TryCloseForApplication(InGameFriendsWindow? window)
    {
        if (window is null)
        {
            return;
        }

        try
        {
            window.CloseForApplication();
        }
        catch (Exception exception)
        {
            App.WriteCrashLog(exception);
        }
    }

    private static void TryCloseForApplication(InGameProfileWindow? window)
    {
        if (window is null)
        {
            return;
        }

        try
        {
            window.CloseForApplication();
        }
        catch (Exception exception)
        {
            App.WriteCrashLog(exception);
        }
    }

    private void CloseProfileWindowsForAccountChange()
    {
        var profiles = _profileWindows.Values.ToArray();
        _requestedProfileKeys.Clear();
        _activeProfileWindow = null;
        foreach (var profile in profiles)
        {
            TryCloseForApplication(profile);
        }
    }

    private static void TryCloseForApplication(InGameRoomWindow? window)
    {
        if (window is null)
        {
            return;
        }

        try
        {
            window.CloseForApplication();
        }
        catch (Exception exception)
        {
            App.WriteCrashLog(exception);
        }
    }

    private bool ForegroundWindowBelongsToSession()
    {
        var handle = GetForegroundWindow();
        if (handle == IntPtr.Zero)
        {
            return false;
        }

        var sessionHandles = SessionWindows()
            .Select(window => new System.Windows.Interop.WindowInteropHelper(window).Handle)
            .Where(windowHandle => windowHandle != IntPtr.Zero)
            .ToHashSet();
        while (handle != IntPtr.Zero)
        {
            if (sessionHandles.Contains(handle))
            {
                return true;
            }

            handle = GetWindow(handle, GwOwner);
        }

        return false;
    }

    private const uint GwOwner = 4;

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern IntPtr GetWindow(IntPtr windowHandle, uint command);
}
