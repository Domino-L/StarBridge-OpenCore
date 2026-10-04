namespace StarBridge.Desktop;

using System.Runtime.InteropServices;
using System.Threading;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Threading;
using StarBridge.Core.Overlay;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Overlay;
using StarBridge.HostRuntime.Presence;
using WinForms = System.Windows.Forms;

/// <summary>
/// Native Host adapter for the existing DirectComposition information overlay.
/// It owns one STA control thread and keeps every Windows implementation detail
/// behind <see cref="IInformationOverlayRuntime"/>.
/// </summary>
public sealed partial class NativeInformationOverlayRuntime :
    IInformationOverlayRuntime,
    IInformationOverlayLiveUpdateSink,
    IInformationOverlayAppearanceCatalog,
    IInformationOverlayReminderSink
{
    private const int WmHotkey = 0x0312;
    private const int WmGameCompatibleHotkey = 0x8053;
    private const int HotkeyId = 0x5B31;
    private const uint ModNoRepeat = 0x4000;
    private const int ErrorHotkeyAlreadyRegistered = 1409;
    private const int WsPopup = unchecked((int)0x80000000);
    private const int WsExToolWindow = 0x00000080;
    private const int WsExNoActivate = 0x08000000;

    private readonly Func<GameLogSessionSnapshot> _sessionProvider;
    private readonly Func<LocalGamePresenceSnapshot>? _localPresenceProvider;
    private PlayerPresenceKind? _confirmedLocalPresence;
    private PlayerPresenceKind? _lastRenderedLocalPresence;
    private readonly Func<IReadOnlyList<string>> _entitlementProvider;
    private readonly Func<InformationOverlayRoomContent?> _roomProvider;
    private readonly Func<InformationOverlayCommunityContent?> _communityProvider;
    private readonly Func<CancellationToken, Task>? _prepareCommunity;
    private CancellationTokenSource? _openingCancellation;
    internal Action<OverlaySceneSnapshot>? BeforeWindowCreation;
    // Regression harness only: exercise the real HWND/render lifecycle outside
    // every desktop surface, without replacing the maintainer's visible client.
    internal Rect? TestSurfaceBounds;
    internal IntPtr TestWindowHandle => _window?.NativeHandle ?? IntPtr.Zero;
    internal bool TestStartupTransitionEnabled => _window?.StartupTransitionEnabled ?? false;
    private readonly Func<string?> _sceneModeProvider;
    private readonly Func<string?>? _languageProvider;
    private readonly Func<InformationOverlayRosterPreferences> _rosterPreferences;
    private InformationOverlayRosterPreferences? _lastRosterPreferences;
    private string? _lastRenderedSourceMode;
    private InformationOverlayRoomContent? _lastRenderedRoom;
    private InformationOverlayCommunityContent? _lastRenderedCommunity;
    private int _contentRefreshQueued;
    private Guid? _lastRenderedSourceContinuity;
    private OverlaySceneKind? _lastRenderedSceneKind;
    private readonly ManualResetEventSlim _started = new(false);
    private readonly Thread _thread;
    private readonly object _lifetimeLock = new();
    private Dispatcher? _dispatcher;
    private Exception? _startupException;
    private bool _disposed;
    private bool _controlThreadCleanedUp;

    private HwndSource? _messageWindow;
    private DispatcherTimer? _gameWindowTimer;
    private DispatcherTimer? _appearanceFocusTimer;
    private readonly GameCompatibleHotkeyListener _gameCompatibleHotkey = new();
    private readonly OverlayHotkeyTriggerGate _hotkeyTriggerGate = new(TimeSpan.FromMilliseconds(180));
    private bool _windowsHotkeyRegistered;
    private long _nextHotkeyRegistrationAttempt;
    private string _hotkeyState = "disabled";
    private OverlayHotkeyBindingPlan? _hotkeyPlan;
    private long _hotkeyConfigurationRevision;
    internal long HotkeyConfigurationRevision => Interlocked.Read(ref _hotkeyConfigurationRevision);
    private string _followGameState = "manual";
    private bool? _previousGameRunning;
    private bool? _previousGameForeground;

    private InformationOverlayRuntimeWorkspace? _workspace;
    private InformationOverlayModuleDemand? _moduleDemand;
    private OverlayCompositionHudWindow? _window;
    private Rect _surfaceBounds;
    private Rect? _lastRenderedBounds;
    private double _lastRenderedDpiScale;
    private GameLogSessionSnapshot? _lastRenderedSession;
    private string[] _lastRenderedEntitlements = [];
    private InformationOverlayRuntimeSnapshot _snapshot =
        InformationOverlayRuntimeSnapshot.Unavailable;

    public NativeInformationOverlayRuntime(
        Func<GameLogSessionSnapshot>? sessionProvider = null,
        Func<IReadOnlyList<string>>? entitlementProvider = null,
        Func<InformationOverlayRoomContent?>? roomProvider = null,
        Func<InformationOverlayCommunityContent?>? communityProvider = null,
        Func<string?>? sceneModeProvider = null,
        Func<string?>? languageProvider = null,
        Func<InformationOverlayRosterPreferences>? rosterPreferences = null,
        Func<LocalGamePresenceSnapshot>? localPresenceProvider = null,
        Func<CancellationToken, Task>? prepareCommunity = null,
        Func<InformationOverlayRuntimeWorkspace, InformationOverlayModuleReadResult>? moduleProvider = null)
    {
        _sessionProvider = sessionProvider ?? (() => GameLogSessionSnapshot.Empty);
        _localPresenceProvider = localPresenceProvider;
        _entitlementProvider = entitlementProvider ?? (() => []);
        _roomProvider = roomProvider ?? (() => null);
        _communityProvider = communityProvider ?? (() => null);
        _prepareCommunity = prepareCommunity;
        _moduleProvider = moduleProvider;
        _sceneModeProvider = sceneModeProvider ?? (() => null);
        _languageProvider = languageProvider;
        _rosterPreferences = rosterPreferences ?? (() => InformationOverlayRosterPreferences.Empty);
        _thread = new Thread(RunControlThread)
        {
            IsBackground = true,
            Name = "StarBridge.InformationOverlayRuntime"
        };
        _thread.SetApartmentState(ApartmentState.STA);
        _thread.Start();
        if (!_started.Wait(TimeSpan.FromSeconds(5)))
        {
            throw new TimeoutException("Information overlay control thread did not start.");
        }
        if (_startupException is not null)
        {
            throw new InvalidOperationException(
                "Information overlay control thread failed to start.",
                _startupException);
        }
    }

    public async ValueTask<InformationOverlayRuntimeSnapshot> ExecuteAsync(
        InformationOverlayRuntimeCommand command,
        InformationOverlayRuntimeWorkspace workspace,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(workspace);
        Dispatcher? dispatcher;
        lock (_lifetimeLock)
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            dispatcher = _dispatcher;
        }

        if (dispatcher is null || dispatcher.HasShutdownStarted || dispatcher.HasShutdownFinished)
        {
            return FailedSnapshot(workspace, "overlay.runtime_unavailable", retryable: true);
        }

        var operation = dispatcher.InvokeAsync(
            () => ExecuteOnControlThread(command, workspace),
            DispatcherPriority.Send,
            cancellationToken);
        return await operation.Task.WaitAsync(cancellationToken).ConfigureAwait(false);
    }

    public IReadOnlyList<InformationOverlayAppearanceProfile> GetAppearances()
    {
        var entitlements = SafeReadEntitlements();
        return OverlaySkinCatalog.Listed
            .Select(profile => new InformationOverlayAppearanceProfile(
                profile.Id.ToString(),
                profile.DisplayNameZh,
                profile.DisplayNameEn,
                profile.Presentation.SummaryZh,
                profile.Presentation.SummaryEn,
                profile.Presentation.TraitsZh,
                profile.Presentation.TraitsEn,
                profile.Presentation.PreviewSurface,
                profile.Presentation.PreviewPrimary,
                profile.Presentation.PreviewSecondary,
                profile.LocksTheme,
                profile.SupportsBloom,
                profile.StartupTransition.ToString(),
                RequiresEntitlement: profile.Entitlement is not null,
                IsReleased: profile.IsReleased,
                IsAvailable: OverlaySkinCatalog.CanUse(profile.Id, entitlements),
                IsPreviewAvailable: profile.IsPreviewAvailable))
            .ToArray();
    }

    private InformationOverlayRuntimeSnapshot ExecuteOnControlThread(
        InformationOverlayRuntimeCommand command,
        InformationOverlayRuntimeWorkspace workspace)
    {
        try
        {
            ApplyWorkspace(workspace);
            return command switch
            {
                InformationOverlayRuntimeCommand.Open => OpenCore(retry: false),
                InformationOverlayRuntimeCommand.Close => CloseCore(),
                InformationOverlayRuntimeCommand.Retry => OpenCore(retry: true),
                _ => SynchronizeCore()
            };
        }
        catch (Exception exception)
        {
            DesktopRuntimeDiagnostics.WriteDiagnosticLog($"native-overlay-runtime-failed | {exception}");
            TryCloseWindow();
            _snapshot = FailedSnapshot(workspace, ResolveFailureCode(exception), retryable: true);
            return _snapshot;
        }
    }

    private void ApplyWorkspace(InformationOverlayRuntimeWorkspace workspace)
    {
        var session = SafeReadSession();
        _workspace = workspace with { Session = session };
        Volatile.Write(ref _moduleDemand, workspace.UsesModuleSources
            ? new InformationOverlayModuleDemand(workspace.Sources, OverlayModuleSourceResolver.VisibleModules(workspace.Settings), workspace.TemporarySource)
            : null);
        RefreshPresentationLanguage();
        if (workspace.HasInvalidSourceConfiguration)
        {
            // Close must work for a damaged preset, but must not first refresh
            // the old HWND or leave hotkey/game-follow able to read legacy data.
            TryCloseWindow();
            ConfigureHotkey(workspace.HotkeyBinding, false);
            _snapshot = FailedSnapshot(workspace, "overlay.workspace_invalid_preset", retryable: false);
            return;
        }
        ConfigureHotkey(workspace.HotkeyBinding, workspace.HotkeyEnabled);
        UpdateFollowGameState();
        if (_window is { IsVisible: true })
        {
            RefreshWindow(force: true);
        }

        var resolution = OverlaySkinCatalog.Resolve(
            workspace.Settings,
            SafeReadEntitlements());
        _snapshot = _snapshot with
        {
            AppliedRevision = workspace.Revision,
            HotkeyState = _hotkeyState,
            FollowGameState = _followGameState,
            RequestedSkin = resolution.RequestedSkin.ToString(),
            EffectiveSkin = resolution.EffectiveSkin.ToString(),
            UsedFallbackSkin = !resolution.IsAvailable,
            FailureCode = _snapshot.WindowState == "failed" ? _snapshot.FailureCode : null,
            Retryable = _snapshot.WindowState == "failed" && _snapshot.Retryable
        };
    }

    private InformationOverlayRuntimeSnapshot SynchronizeCore()
    {
        EvaluateGameWindowRules(initialSync: _previousGameRunning is null);
        if (_window is { IsVisible: true })
        {
            return SetHealthySnapshot("open", isVisible: true);
        }
        if (_openingCancellation is not null) return _snapshot;
        if (_snapshot.WindowState != "failed")
        {
            return SetHealthySnapshot("closed", isVisible: false);
        }
        return _snapshot;
    }

    private InformationOverlayRuntimeSnapshot OpenCore(bool retry, bool prepared = false)
    {
        RefreshPresentationLanguage();
        var workspace = _workspace ?? throw new InvalidOperationException("Overlay workspace is unavailable.");
        if (workspace.HasInvalidSourceConfiguration)
        {
            TryCloseWindow();
            return _snapshot = FailedSnapshot(workspace, "overlay.workspace_invalid_preset", retryable: false);
        }
        if (retry)
        {
            TryCloseWindow();
        }
        else if (_window is { IsVisible: true })
        {
            RefreshWindow(force: true);
            return SetHealthySnapshot("open", isVisible: true);
        }

        if (_openingCancellation is not null) return _snapshot;
        var entitlements = SafeReadEntitlements();
        var resolution = OverlaySkinCatalog.Resolve(workspace.Settings, entitlements);
        var settings = OverlayStartupTransitionPolicy.ResolveForOpen(
            resolution.Settings,
            StarCitizenProcessProbe.IsForeground());
        if (MenuActive) settings = settings with { EnableStartupTransition = false };
        _surfaceBounds = ResolveTargetSurfaceBounds(out var targetDpiScale);
        var room = !workspace.UsesModuleSources ? SafeReadRoom() : null;
        var sourceMode = SafeReadSourceMode();
        var preference = SourcePreference(sourceMode, settings.ScenePreference);
        var community = !workspace.UsesModuleSources && (sourceMode == "community" || preference == OverlayScenePreference.Auto && room is null) ? SafeReadCommunity() : null;
        if (!workspace.UsesModuleSources && !prepared && _prepareCommunity is not null && community is null &&
            (sourceMode == "community" || preference == OverlayScenePreference.Auto && room is null))
        {
            var pending = new CancellationTokenSource(TimeSpan.FromSeconds(20));
            _openingCancellation = pending;
            SetHealthySnapshot("opening", isVisible: false);
            _ = PrepareOpenAsync(pending);
            return _snapshot;
        }
        if (!workspace.UsesModuleSources && prepared && sourceMode == "community" && community is null)
            return _snapshot = FailedSnapshot(workspace, "overlay.runtime_unavailable", retryable: true);
        var localSession = SafeReadSession();
        var localPresence = ReadLocalDisplayPresence();
        var modules = ReadModules(workspace, localSession, localPresence);
        var content = modules is null
            ? ProjectSource(room, community, preference, workspace.Language, sourceMode == "community", localSession, localPresence)
            : (Scene: modules.Members.Scene, Command: modules.Notice.Command, Chat: modules.Chat.Chat.ToArray());
        _lastRenderedSourceMode = sourceMode;
        BeforeWindowCreation?.Invoke(content.Scene);
        var overlay = new OverlayCompositionHudWindow(
            new OverlayAuthorizedRoster(content.Scene.Players),
            content.Chat,
            ToDesktopLayout(workspace.Layout),
            settings,
            ReadRosterSettings(),
            workspace.Language,
            hasFleet: content.Scene.HasContent,
            content.Command,
            localPresence ?? PlayerPresenceKind.AppOnline,
            localSession.Server.Shard ?? string.Empty,
            _surfaceBounds,
            OverlayStartupTransitionContext.ForLanguage(workspace.Language),
            content.Scene.Context, targetDpiScale, modules);
        overlay.Closed += OverlayClosed;
        _window = overlay;
        overlay.SetMenuAbove(_menuWindow);
        Exception? failure = null;
        var opened = OverlayStartupBoundary.TryShow(
            overlay.Show,
            overlay.Close,
            exception => failure = exception);
        if (!opened)
        {
            overlay.Closed -= OverlayClosed;
            if (ReferenceEquals(_window, overlay))
            {
                _window = null;
            }
            throw failure ?? new InvalidOperationException("Information overlay did not open.");
        }

        _lastRenderedSession = localSession;
        _lastRenderedLocalPresence = localPresence;
        _lastRenderedRoom = room;
        _lastRenderedCommunity = community;
        _lastRenderedSceneKind = content.Scene.Context.Kind;
        _lastRenderedSourceContinuity = SourceContinuity(content.Scene.Context.Kind, room, community);
        _lastRenderedBounds = _surfaceBounds;
        _lastRenderedDpiScale = targetDpiScale;
        _lastRenderedEntitlements = entitlements;
        _lastRenderedModules = modules;
        ScheduleModuleValidation(modules);
        if (modules is not null) ModulesPresented?.Invoke(modules, overlay.ObserveModules());

        if (settings.AutoFocusGameWindowOnOpen && !MenuActive)
        {
            ScheduleAppearanceFocus(overlay, settings);
        }
        return SetHealthySnapshot("open", isVisible: true);
    }

    private InformationOverlayRuntimeSnapshot CloseCore()
    {
        TryCloseWindow();
        return SetHealthySnapshot("closed", isVisible: false);
    }

    private async Task PrepareOpenAsync(CancellationTokenSource pending)
    {
        try
        {
            var token = pending.Token;
            try { await Task.Run(() => _prepareCommunity!(token), token).WaitAsync(token).ConfigureAwait(false); }
            catch (Exception) { /* Re-read authority on the STA; failure never supplies display data. */ }
            var dispatcher = _dispatcher;
            if (dispatcher is null || dispatcher.HasShutdownStarted) return;
            await dispatcher.InvokeAsync(() =>
            {
                if (_disposed || !ReferenceEquals(_openingCancellation, pending)) return;
                _openingCancellation = null;
                try { _ = OpenCore(retry: false, prepared: true); }
                catch (Exception error)
                {
                    TryCloseWindow();
                    _snapshot = FailedSnapshot(_workspace!, ResolveFailureCode(error), retryable: true);
                }
            }).Task.ConfigureAwait(false);
        }
        catch (Exception error) when (error is OperationCanceledException or InvalidOperationException)
        { /* The dispatcher may shut down after the pending open was canceled. */ }
        finally { pending.Dispose(); }
    }

    private bool FinishPreparedOpenIfReady()
    {
        if (_openingCancellation is not { } pending) return false;
        var mode = SafeReadSourceMode();
        var room = SafeReadRoom();
        var ready = _workspace?.UsesModuleSources == true || (mode == "community" ? SafeReadCommunity() is not null :
            room is not null || SafeReadCommunity() is not null);
        if (!ready) return false;
        _openingCancellation = null;
        pending.Cancel();
        try { _ = OpenCore(retry: false, prepared: true); }
        catch (Exception error)
        {
            TryCloseWindow();
            _snapshot = FailedSnapshot(_workspace!, ResolveFailureCode(error), retryable: true);
        }
        return true;
    }

    private void ScheduleAppearanceFocus(OverlayCompositionHudWindow overlay, OverlayDisplaySettings settings)
    {
        _appearanceFocusTimer?.Stop();
        _appearanceFocusTimer = null;
        // WPF does not reactivate an already foreground game. Different skins
        // hand off while their shutter/progress cover is closed, not at the end.
        if (StarCitizenProcessProbe.IsForeground()) return;
        var delay = OverlayStartupFocusPolicy.DelayMs(settings, UiMotion.IsEnabled,
            overlay.AppearanceStartupFocusRemainingMs);
        var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(Math.Max(1, delay)) };
        var focusAttempts = 0;
        _appearanceFocusTimer = timer;
        timer.Tick += (_, _) =>
        {
            timer.Stop();
            if (!ReferenceEquals(_appearanceFocusTimer, timer)) return;
            if (_disposed || !ReferenceEquals(_window, overlay) || !overlay.IsVisible ||
                _workspace?.Settings.AutoFocusGameWindowOnOpen != true)
            { _appearanceFocusTimer = null; return; }
            TryFocusGameWindow();
            focusAttempts++;
            if (OverlayStartupFocusPolicy.RetryAtClosedShutter(settings, UiMotion.IsEnabled) &&
                !StarCitizenProcessProbe.IsForeground() && focusAttempts < 5)
            {
                timer.Interval = TimeSpan.FromMilliseconds(20);
                timer.Start();
                return;
            }
            _appearanceFocusTimer = null;
        };
        timer.Start();
    }

    private void RefreshWindow(bool force = false, bool allowHidden = false)
    {
        force |= RefreshPresentationLanguage();
        if (_window is not { } window || (!window.IsVisible && !allowHidden) || _workspace is null)
        {
            return;
        }

        var session = SafeReadSession();
        var localPresence = ReadLocalDisplayPresence();
        _workspace = _workspace with { Session = session };
        var entitlements = SafeReadEntitlements();
        var resolution = OverlaySkinCatalog.Resolve(_workspace.Settings, entitlements);
        var settings = resolution.Settings;
        var bounds = ResolveTargetSurfaceBounds(out var targetDpiScale);
        var rosterPreferences = SafeReadRosterPreferences();
        var rosterSettings = new OverlayRosterSelectionSettings(rosterPreferences.Pinned, rosterPreferences.Excluded);
        var rosterChanged = !Equals(_lastRosterPreferences, rosterPreferences);
        var room = !_workspace.UsesModuleSources ? SafeReadRoom() : null;
        var sourceMode = SafeReadSourceMode();
        var preference = SourcePreference(sourceMode, settings.ScenePreference);
        var community = !_workspace.UsesModuleSources && (sourceMode == "community" || preference == OverlayScenePreference.Auto && room is null) ? SafeReadCommunity() : null;
        var modules = ReadModules(_workspace, session, localPresence);
        ScheduleModuleValidation(modules);
        _snapshot = _snapshot with { FailureCode = _moduleFailure, Retryable = ModuleFailureRetryable };
        if (!force && !rosterChanged && _lastRenderedLocalPresence == localPresence && _lastRenderedDpiScale == targetDpiScale &&
            (modules is null ? _lastRenderedModules is null : modules.HasSameContent(_lastRenderedModules)) &&
            _lastRenderedSourceMode == sourceMode &&
            ReferenceEquals(_lastRenderedRoom, room) &&
            ReferenceEquals(_lastRenderedCommunity, community) &&
            Equals(_lastRenderedSession, session) &&
            _lastRenderedBounds is Rect lastBounds &&
            lastBounds == bounds &&
            _lastRenderedEntitlements.SequenceEqual(
                entitlements,
                StringComparer.OrdinalIgnoreCase))
        {
            return;
        }
        _surfaceBounds = bounds;
        var content = modules is null
            ? ProjectSource(room, community, preference, _workspace.Language, sourceMode == "community", session, localPresence)
            : (Scene: modules.Members.Scene, Command: modules.Notice.Command, Chat: modules.Chat.Chat.ToArray());
        _lastRenderedSourceMode = sourceMode;
        var continuity = SourceContinuity(content.Scene.Context.Kind, room, community);
        if (modules is null && (_lastRenderedSourceContinuity != continuity ||
            _lastRenderedSceneKind != content.Scene.Context.Kind))
            window.ClearAuthorizedContent(preserveDeviceLocalEvents: true, preserveAnnouncementReceipt: true);
        window.RefreshWithDpi(
            new OverlayAuthorizedRoster(content.Scene.Players),
            content.Chat,
            ToDesktopLayout(_workspace.Layout),
            settings,
            rosterSettings,
            _workspace.Language,
            hasFleet: content.Scene.HasContent,
            content.Command,
            localPresence ?? PlayerPresenceKind.AppOnline,
            session.Server.Shard ?? string.Empty,
            bounds,
            OverlayStartupTransitionContext.ForLanguage(_workspace.Language),
            content.Scene.Context, targetDpiScale, modules);
        _lastRenderedSession = session;
        _lastRenderedLocalPresence = localPresence;
        _lastRenderedRoom = room;
        _lastRenderedCommunity = community;
        _lastRenderedSceneKind = content.Scene.Context.Kind;
        _lastRenderedSourceContinuity = continuity;
        _lastRenderedBounds = bounds;
        _lastRenderedDpiScale = targetDpiScale;
        _lastRosterPreferences = rosterPreferences;
        _lastRenderedEntitlements = entitlements;
        _lastRenderedModules = modules;
        if (modules is not null) ModulesPresented?.Invoke(modules, window.ObserveModules());
    }

    private void EvaluateGameWindowRules(bool initialSync = false)
    {
        if (ValidateMenuInformationLayer()) return;
        if (_workspace is null)
        {
            return;
        }

        var settings = _workspace.Settings;
        var running = StarCitizenProcessProbe.IsRunning();
        var foreground = StarCitizenProcessProbe.IsForeground();
        ValidateReminder(foreground);
        var wasRunning = _previousGameRunning;
        var wasForeground = _previousGameForeground;
        _previousGameRunning = running;
        _previousGameForeground = foreground;
        UpdateFollowGameState(running, foreground);

        var openForStart = settings.AutoOpenOverlayOnGameStart && running &&
                           (initialSync || wasRunning == false);
        var openForForeground = settings.AutoOpenOverlayOnGameForeground && foreground &&
                                (initialSync || wasForeground == false);
        if (_window is not { IsVisible: true } && (openForStart || openForForeground))
        {
            _ = OpenCore(retry: false);
            return;
        }

        if ((_window is { IsVisible: true } || _openingCancellation is not null) &&
            settings.AutoCloseOverlayOnGameBackground &&
            wasForeground == true && !foreground)
        {
            _ = CloseCore();
            return;
        }

        if (_window is { IsVisible: true })
        {
            RefreshWindow();
        }
        else
        {
            if (FinishPreparedOpenIfReady()) return;
            _snapshot = _snapshot with
            {
                HotkeyState = _hotkeyState,
                FollowGameState = _followGameState
            };
        }
    }

    private void UpdateFollowGameState(bool? running = null, bool? foreground = null)
    {
        if (_workspace is null)
        {
            _followGameState = "unavailable";
            return;
        }

        var settings = _workspace.Settings;
        if (!settings.AutoOpenOverlayOnGameStart &&
            !settings.AutoOpenOverlayOnGameForeground &&
            !settings.AutoCloseOverlayOnGameBackground)
        {
            _followGameState = "manual";
            return;
        }

        var gameRunning = running ?? StarCitizenProcessProbe.IsRunning();
        var gameForeground = foreground ?? StarCitizenProcessProbe.IsForeground();
        _followGameState = gameForeground
            ? "followingGame"
            : gameRunning ? "gameInBackground" : "waitingForGame";
    }

    private void ConfigureHotkey(string binding, bool enabled)
    {
        var menu = _menuHotkey;
        var plan = OverlayHotkeyBindingPolicy.Build(binding, enabled,
            menu?.Binding, menu is { Enabled: true } && menu.IsCurrent());
        if (plan.InformationState != OverlayHotkeyBindingState.Ready)
            plan = plan with { InformationHotkey = null };
        if (plan.MenuState != OverlayHotkeyBindingState.Ready)
            plan = plan with { MenuHotkey = null };
        // Workspace/content refresh is not a hotkey configuration change.
        // Preserve the raw-input key-down filter and the duplicate-trigger gate,
        // and avoid stopping its message thread on every source refresh.
        if (plan == _hotkeyPlan &&
            ((plan.InformationHotkey is null && plan.MenuHotkey is null) || _gameCompatibleHotkey.IsRunning))
            return;

        var previousState = _hotkeyState;
        UnregisterHotkey();
        _hotkeyPlan = plan;
        Interlocked.Increment(ref _hotkeyConfigurationRevision);
        if (_messageWindow is null)
        {
            _hotkeyState = _menuHotkeyState = "unavailable";
            return;
        }

        var windowsError = 0;
        if (plan.InformationHotkey is { } chord)
        {
            _windowsHotkeyRegistered = RegisterHotKey(_messageWindow.Handle,
                HotkeyId, chord.Modifiers | ModNoRepeat, chord.VirtualKey);
            windowsError = _windowsHotkeyRegistered ? 0 : Marshal.GetLastWin32Error();
        }
        _nextHotkeyRegistrationAttempt = Environment.TickCount64 + 5000;
        var routes = plan.CreateGameCompatibleRoutes(0, MenuHotkeyCommand);
        var gameCompatible = routes.Count > 0 && _gameCompatibleHotkey.Start(
            _messageWindow.Handle, WmGameCompatibleHotkey, routes);
        _menuHotkeyState = plan.MenuState switch
        {
            OverlayHotkeyBindingState.Ready => gameCompatible ? "registered" : "failed",
            OverlayHotkeyBindingState.Disabled => "disabled",
            OverlayHotkeyBindingState.ConflictWithInformation => "conflictWithInformation",
            OverlayHotkeyBindingState.ModifierRequired => "modifierRequired",
            OverlayHotkeyBindingState.Reserved => "reserved",
            _ => "invalid"
        };
        _hotkeyState = plan.InformationState == OverlayHotkeyBindingState.Disabled ? "disabled" :
            plan.InformationState != OverlayHotkeyBindingState.Ready ? "invalid" :
            (_windowsHotkeyRegistered, gameCompatible) switch
        {
            (true, true) => "registered",
            (false, true) => "gameCompatibleOnly",
            (true, false) => "desktopOnly",
            (false, false) when windowsError == ErrorHotkeyAlreadyRegistered => "conflict",
            _ => "failed"
        };
        if (_hotkeyState != previousState)
            DesktopRuntimeDiagnostics.WriteDiagnosticLog($"native-overlay-hotkey-registration | state={_hotkeyState} windowsError={windowsError}");
    }

    private void RetryGlobalHotkeyRegistration()
    {
        // Startup overlap or another program can temporarily own the chord.
        // Retry on the HWND's STA without restarting the working game listener.
        if (_windowsHotkeyRegistered || _hotkeyPlan?.InformationHotkey is not { } chord ||
            _messageWindow is null || _hotkeyState is "disabled" or "invalid" ||
            Environment.TickCount64 < _nextHotkeyRegistrationAttempt)
            return;

        _nextHotkeyRegistrationAttempt = Environment.TickCount64 + 5000;
        if (!RegisterHotKey(_messageWindow.Handle, HotkeyId,
                chord.Modifiers | ModNoRepeat, chord.VirtualKey))
            return;

        _windowsHotkeyRegistered = true;
        _hotkeyState = _gameCompatibleHotkey.IsRunning ? "registered" : "desktopOnly";
        _snapshot = _snapshot with { HotkeyState = _hotkeyState };
        DesktopRuntimeDiagnostics.WriteDiagnosticLog("native-overlay-hotkey-registration-recovered");
    }

    public bool IsVisible => !_disposed && Volatile.Read(ref _snapshot).IsVisible;
    public bool HasDisplayDemand => !_disposed && Volatile.Read(ref _snapshot).WindowState is "open" or "suppressed";
    public InformationOverlayModuleDemand? ModuleDemand => Volatile.Read(ref _moduleDemand);

    public void RequestContentRefresh()
    {
        var dispatcher = _dispatcher;
        if ((!HasDisplayDemand && _snapshot.WindowState != "opening") || dispatcher is null || dispatcher.HasShutdownStarted || dispatcher.HasShutdownFinished ||
            Interlocked.CompareExchange(ref _contentRefreshQueued, 1, 0) != 0) return;
        try
        {
            dispatcher.BeginInvoke(() =>
            {
                Interlocked.Exchange(ref _contentRefreshQueued, 0);
                if (!_disposed && !FinishPreparedOpenIfReady() && HasDisplayDemand)
                {
                    if (!ValidateMenuInformationLayer()) RefreshWindow();
                }
            }, DispatcherPriority.DataBind);
        }
        catch (InvalidOperationException) { Interlocked.Exchange(ref _contentRefreshQueued, 0); }
    }

    private void UnregisterHotkey()
    {
        _hotkeyPlan = null;
        _gameCompatibleHotkey.Stop();
        _hotkeyTriggerGate.Reset();
        if (_windowsHotkeyRegistered && _messageWindow is not null)
        {
            _ = UnregisterHotKey(_messageWindow.Handle, HotkeyId);
        }
        _windowsHotkeyRegistered = false;
    }

    private IntPtr MessageWindowProc(
        IntPtr hwnd,
        int message,
        IntPtr wParam,
        IntPtr lParam,
        ref bool handled)
    {
        _ = hwnd;
        _ = lParam;
        if (message == WmHotkey && wParam.ToInt32() == HotkeyId)
        {
            handled = true;
            HandleHotkeyTrigger(requireGameForeground: false);
        }
        else if (message == WmGameCompatibleHotkey)
        {
            handled = true;
            if (wParam.ToInt32() == MenuHotkeyCommand)
            {
                try { HandleMenuHotkeyTrigger(); }
                catch { DesktopRuntimeDiagnostics.WriteDiagnosticLog("menu-hotkey-intent-unavailable"); }
            }
            else if (wParam.ToInt32() == 0) HandleHotkeyTrigger(requireGameForeground: true);
        }
        return IntPtr.Zero;
    }

    private void HandleHotkeyTrigger(bool requireGameForeground)
    {
        RefreshPresentationLanguage();
        if (_workspace?.HotkeyEnabled != true ||
            requireGameForeground && !StarCitizenProcessProbe.IsForeground() ||
            !_hotkeyTriggerGate.TryAccept(unchecked((uint)GetMessageTime())))
        {
            return;
        }

        try
        {
            _ = _window is { IsVisible: true } || _openingCancellation is not null ? CloseCore() : OpenCore(retry: false);
        }
        catch (Exception exception)
        {
            DesktopRuntimeDiagnostics.WriteDiagnosticLog($"native-overlay-hotkey-failed | {exception}");
            if (_workspace is not null)
            {
                _snapshot = FailedSnapshot(_workspace, ResolveFailureCode(exception), retryable: true);
            }
        }
    }

    private void RunControlThread()
    {
        try
        {
            _dispatcher = Dispatcher.CurrentDispatcher;
            var parameters = new HwndSourceParameters("StarBridge.NativeOverlayRuntime")
            {
                WindowStyle = WsPopup,
                ExtendedWindowStyle = WsExToolWindow | WsExNoActivate,
                PositionX = -32000,
                PositionY = -32000,
                Width = 1,
                Height = 1
            };
            _messageWindow = new HwndSource(parameters);
            _messageWindow.AddHook(MessageWindowProc);
            _gameWindowTimer = new DispatcherTimer(
                TimeSpan.FromMilliseconds(750),
                DispatcherPriority.Background,
                (_, _) =>
                {
                    try
                    {
                        RetryGlobalHotkeyRegistration();
                        EvaluateGameWindowRules();
                    }
                    catch (Exception exception)
                    {
                        DesktopRuntimeDiagnostics.WriteDiagnosticLog($"native-overlay-follow-game-failed | {exception}");
                    }
                },
                _dispatcher);
            _gameWindowTimer.Start();
            _started.Set();
            Dispatcher.Run();
        }
        catch (Exception exception)
        {
            _startupException = exception;
            _started.Set();
        }
        finally
        {
            CleanupOnControlThread();
        }
    }

    private void CleanupOnControlThread()
    {
        if (_controlThreadCleanedUp)
        {
            return;
        }
        _controlThreadCleanedUp = true;
        _gameWindowTimer?.Stop();
        _gameWindowTimer = null;
        UnregisterHotkey();
        _gameCompatibleHotkey.Dispose();
        TryCloseWindow();
        if (_messageWindow is not null)
        {
            _messageWindow.RemoveHook(MessageWindowProc);
            _messageWindow.Dispose();
            _messageWindow = null;
        }
    }

    private void OverlayClosed(object? sender, EventArgs e)
    {
        if (sender is OverlayCompositionHudWindow overlay)
        {
            overlay.Closed -= OverlayClosed;
        }
        if (ReferenceEquals(_window, sender))
        {
            _appearanceFocusTimer?.Stop();
            _appearanceFocusTimer = null;
            _window = null;
            _lastRenderedModules = null;
            _moduleFailure = null;
            ScheduleModuleValidation(null);
        }
        _snapshot = SetHealthySnapshot("closed", isVisible: false);
    }

    private void TryCloseWindow()
    {
        var pending = _openingCancellation;
        _openingCancellation = null;
        pending?.Cancel();
        _appearanceFocusTimer?.Stop();
        _appearanceFocusTimer = null;
        var window = _window;
        _window = null;
        _lastRenderedSession = null;
        _lastRenderedBounds = null;
        _lastRenderedEntitlements = [];
        _lastRenderedModules = null;
        _moduleFailure = null;
        ScheduleModuleValidation(null);
        if (window is null)
        {
            return;
        }
        window.Closed -= OverlayClosed;
        try
        {
            window.Close();
        }
        catch (Exception exception)
        {
            DesktopRuntimeDiagnostics.WriteDiagnosticLog($"native-overlay-close-failed | {exception}");
        }
    }

    private InformationOverlayRuntimeSnapshot SetHealthySnapshot(string state, bool isVisible)
    {
        var workspace = _workspace;
        var resolution = OverlaySkinCatalog.Resolve(
            workspace?.Settings ?? InformationOverlayDefaults.DefaultSettings,
            SafeReadEntitlements());
        _snapshot = new InformationOverlayRuntimeSnapshot(
            state,
            isVisible,
            workspace?.Revision ?? 0,
            _hotkeyState,
            _followGameState,
            resolution.RequestedSkin.ToString(),
            resolution.EffectiveSkin.ToString(),
            !resolution.IsAvailable,
            isVisible ? _moduleFailure : null,
            Retryable: isVisible && ModuleFailureRetryable);
        return _snapshot;
    }

    private static InformationOverlayRuntimeSnapshot FailedSnapshot(
        InformationOverlayRuntimeWorkspace workspace,
        string failureCode,
        bool retryable)
    {
        var requested = workspace.Settings.EffectiveRequestedSkin.ToString();
        return new InformationOverlayRuntimeSnapshot(
            "failed",
            IsVisible: false,
            workspace.Revision,
            HotkeyState: workspace.HotkeyEnabled ? "failed" : "disabled",
            FollowGameState: "unavailable",
            RequestedSkin: requested,
            EffectiveSkin: OverlaySkin.Default.ToString(),
            UsedFallbackSkin: workspace.Settings.EffectiveRequestedSkin != OverlaySkin.Default,
            failureCode,
            retryable);
    }

    private static string ResolveFailureCode(Exception exception) => exception switch
    {
        TimeoutException => "overlay.runtime_start_timeout",
        UnauthorizedAccessException => "overlay.runtime_permission_denied",
        _ => "overlay.runtime_open_failed"
    };

    private static IReadOnlyList<OverlayLayoutItem> ToDesktopLayout(
        IReadOnlyList<InformationOverlayLayoutItem> layout) =>
        OverlayLayoutItem.ParseMany(InformationOverlayLayoutItem.SerializeMany(layout)).ToArray();

    private static OverlayCommandState BuildCommandState(string language)
    {
        if (language.Equals("zh-Hant", StringComparison.OrdinalIgnoreCase))
        {
            return new OverlayCommandState(
                "資訊浮層",
                "已準備就緒，可用資訊會自動顯示。",
                null, null, null, null);
        }
        if (language.Equals("zh", StringComparison.OrdinalIgnoreCase))
        {
            return new OverlayCommandState(
                "信息浮层",
                "已准备就绪，可用信息会自动显示。",
                null, null, null, null);
        }
        return new OverlayCommandState(
            "INFORMATION OVERLAY",
            "Ready. Available information will appear automatically.",
            null, null, null, null);
    }

    private GameLogSessionSnapshot SafeReadSession()
    {
        try
        {
            return _sessionProvider() ?? GameLogSessionSnapshot.Empty;
        }
        catch
        {
            return GameLogSessionSnapshot.Empty;
        }
    }

    private OverlayRosterSelectionSettings ReadRosterSettings()
    {
        var prefs = SafeReadRosterPreferences();
        _lastRosterPreferences = prefs;
        return new(prefs.Pinned, prefs.Excluded);
    }

    private InformationOverlayRosterPreferences SafeReadRosterPreferences()
    {
        try { return _rosterPreferences() ?? InformationOverlayRosterPreferences.Empty; }
        catch { return InformationOverlayRosterPreferences.Empty; }
    }

    private string[] SafeReadEntitlements()
    {
        try
        {
            return (_entitlementProvider() ?? [])
                .Select(value => value?.Trim())
                .Where(value => !string.IsNullOrWhiteSpace(value) && value.Length <= 80)
                .Select(value => value!)
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .OrderBy(value => value, StringComparer.OrdinalIgnoreCase)
                .Take(64)
                .ToArray();
        }
        catch
        {
            return [];
        }
    }

    private Rect ResolveTargetSurfaceBounds(out double targetDpiScale)
    {
        targetDpiScale = 1;
        if (TestSurfaceBounds is { } testBounds) return testBounds;
        var gameWindow = StarCitizenProcessProbe.FindMainWindow();
        if (TryResolveScreenBounds(gameWindow, out var gameBounds, out targetDpiScale))
        {
            return gameBounds;
        }
        var primary = WinForms.Screen.PrimaryScreen;
        if (primary is not null && primary.Bounds.Width > 1 && primary.Bounds.Height > 1)
        {
            var dpi = GetDpiForSystem();
            var scale = dpi > 0 ? dpi / 96d : 1d;
            targetDpiScale = scale;
            return new Rect(
                primary.Bounds.Left / scale,
                primary.Bounds.Top / scale,
                primary.Bounds.Width / scale,
                primary.Bounds.Height / scale);
        }
        return new Rect(
            SystemParameters.VirtualScreenLeft,
            SystemParameters.VirtualScreenTop,
            Math.Max(1, SystemParameters.VirtualScreenWidth),
            Math.Max(1, SystemParameters.VirtualScreenHeight));
    }

    private static bool TryResolveScreenBounds(IntPtr handle, out Rect bounds, out double targetDpiScale)
    {
        bounds = default;
        targetDpiScale = 1;
        if (handle == IntPtr.Zero)
        {
            return false;
        }
        try
        {
            var screen = WinForms.Screen.FromHandle(handle);
            var dpi = GetDpiForWindow(handle);
            var scale = dpi > 0 ? dpi / 96d : 1d;
            targetDpiScale = scale;
            bounds = new Rect(
                screen.Bounds.Left / scale,
                screen.Bounds.Top / scale,
                screen.Bounds.Width / scale,
                screen.Bounds.Height / scale);
            return bounds.Width > 1 && bounds.Height > 1;
        }
        catch
        {
            return false;
        }
    }

    private static void TryFocusGameWindow()
    {
        var handle = StarCitizenProcessProbe.FindMainWindow();
        if (handle != IntPtr.Zero)
        {
            _ = SetForegroundWindow(handle);
        }
    }

    public void Dispose()
    {
        Dispatcher? dispatcher;
        lock (_lifetimeLock)
        {
            if (_disposed)
            {
                return;
            }
            _disposed = true;
            dispatcher = _dispatcher;
        }

        if (dispatcher is not null && !dispatcher.HasShutdownStarted && !dispatcher.HasShutdownFinished)
        {
            try
            {
                dispatcher.Invoke(CleanupOnControlThread, DispatcherPriority.Send);
                dispatcher.BeginInvokeShutdown(DispatcherPriority.Send);
            }
            catch
            {
            }
        }
        if (_thread.IsAlive && !ReferenceEquals(Thread.CurrentThread, _thread))
        {
            _ = _thread.Join(TimeSpan.FromSeconds(5));
        }
        _started.Dispose();
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool RegisterHotKey(IntPtr handle, int id, uint modifiers, uint virtualKey);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool UnregisterHotKey(IntPtr handle, int id);

    [DllImport("user32.dll")]
    private static extern int GetMessageTime();

    [DllImport("user32.dll")]
    private static extern uint GetDpiForWindow(IntPtr handle);

    [DllImport("user32.dll")]
    private static extern uint GetDpiForSystem();

    [DllImport("user32.dll")]
    private static extern bool SetForegroundWindow(IntPtr handle);
}
