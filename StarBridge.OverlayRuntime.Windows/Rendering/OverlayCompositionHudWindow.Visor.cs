using StarBridge.Core.Overlay;
using StarBridge.Core.Presence;
using System.Windows.Threading;
using Vortice.Direct2D1;
using Vortice.DirectWrite;
using Vortice.DXGI;
using Vortice.Mathematics;
using DWriteFactoryType = Vortice.DirectWrite.FactoryType;

namespace StarBridge.Desktop;

/// <summary>
/// The visor appearance on the existing overlay pipeline: same window, render thread, frame scheduler,
/// calm timing and data; only "what is drawn" changes. The scene is taken from the frame state the
/// standard appearance already uses.
/// </summary>
internal sealed partial class OverlayCompositionHudWindow
{
    private OverlayVisorRenderer? _visorRenderer;
    private IDWriteFactory5? _visorWriteFactory;
    private static readonly System.Diagnostics.Stopwatch VisorClock = System.Diagnostics.Stopwatch.StartNew();
    private static double VisorNow => VisorClock.Elapsed.TotalSeconds;

    /// <summary>
    /// The member panel height the roster paging reads (its header 52 + 35 per row) for as many rows as the visor's
    /// members height holds (11-07: the maximum when adaptive, else the fixed height); more members turn pages.
    /// </summary>
    internal double VisorMemberViewport =>
        52 + OverlayVisorDraw.RowsFor((float)OverlayDisplaySettings.NormalizeVisorMembersHeight(_settings.VisorMembersHeight)) * 35;

    private bool VisorSelected => OverlaySkinCatalog.Get(_settings.Skin).RenderKind == OverlaySkinRenderKind.Visor;

    // The positions read from the saved layout; recomputed only when the layout, the event side, height or place across,
    // or the width changes. Keyed by the saved text, since the editor may move items in place.
    private (string Layout, OverlayEventNotificationSide Side, double EventY, double EventX, float Width, IReadOnlyDictionary<string, OverlayVisorSpot> Spots)? _visorSpots;

    private IReadOnlyDictionary<string, OverlayVisorSpot> VisorSpots(float layoutWidth)
    {
        var side = _settings.EventNotificationSide;
        var eventY = _settings.EventNotificationY;
        var eventX = _settings.VisorEventsX;
        var items = _layout.ToArray();
        var saved = InformationOverlayLayoutItem.SerializeMany(items);
        if (_visorSpots is { } cached && cached.Layout == saved && cached.Side == side && cached.EventY == eventY && cached.EventX == eventX && cached.Width == layoutWidth)
            return cached.Spots;
        var spots = OverlayVisorPlacement.Spots(items, side, eventY, layoutWidth, eventX);
        _visorSpots = (saved, side, eventY, eventX, layoutWidth, spots);
        return spots;
    }

    private bool TryDrawVisorFrame(ID2D1DeviceContext target, IDXGISurface dxgiSurface)
    {
        if (_state is not { VisorStyle: true } state)
        {
            // not the visor (any more): nothing keeps the last events' rows alive (review CX-VISOR-B86-R3)
            ForgetVisorEvents();
            return false;
        }
        _visorWriteFactory ??= DWrite.DWriteCreateFactory<IDWriteFactory5>(DWriteFactoryType.Shared);
        _visorRenderer ??= new OverlayVisorRenderer(target, _visorWriteFactory);
        target.SetDpi(96, 96);
        var properties = new BitmapProperties1(
            new Vortice.DCommon.PixelFormat(Format.B8G8R8A8_UNorm, Vortice.DCommon.AlphaMode.Premultiplied),
            96, 96, BitmapOptions.Target | BitmapOptions.CannotDraw);
        using var surfaceBitmap = target.CreateBitmapFromDxgiSurface(dxgiSurface, properties);
        if (_visorOpenPending)
        {
            // the opening starts with the first visor frame (its first moment is all but empty), and the frames keep coming
            // while it runs (review CX-VISOR-1110-R1). A frame drawn before the window is up (a cached state, CX-VISOR-INTRO-R2)
            // has no frame scheduler yet: StartVisorOpeningFrames starts the opening again once it has one.
            _visorOpenPending = false;
            _visorOpenAt = VisorNow;
            if (_frameScheduler is null) _visorOpenAwaitsScheduler = true;
            _frameScheduler?.Start(_adaptiveFramePacer.Resolve(
                ResolveStartupTransitionFramesPerSecond(_settings.StartupTransitionFrameRate), Environment.TickCount64));
        }
        // one reading of the own health for the drawing and the count alike (review CX-HUD-RINGFLICKER-073-R1 P2)
        var local = LocalVitals;
        var visorScene = BuildVisorScene(state, local) with { OpenAt = _visorOpenAt, CloseAt = _visorCloseAt };
        _visorRenderer.Render(surfaceBitmap, System.Numerics.Vector2.Zero, visorScene, _pixelWidth, _pixelHeight, VisorNow);
        // 11-15 (只有圆环在闪): counts only, why the own health ring goes away and how often it flashes
        _selfRingWatch.Observe(VisorNow, visorScene.ShowTeam, visorScene.Members, state.MemberRows.Count(row => row.Key is not null && row.IsSelf),
            local.Vitals, new OverlayVisorRenderCounts(_visorRenderer.RingFlashes, _visorRenderer.IntroFrames, _visorRenderer.LiveClears,
                OverlayHwndDiagnostics.TopmostChecks, OverlayHwndDiagnostics.TopmostRaised, !_visorRenderer.LastFrameRingComposed,
                OverlayVisorRefreshCounts.Read()));
        // motion that began in this frame (a health ring's flash or growth) asks for the next frames itself: the scheduler
        // is otherwise started before the frame is drawn (review CX-VISOR-INTRO-R3)
        if (!OverlayVisorRenderer.IntroBusy(_visorOpenAt, _visorCloseAt, VisorNow) && _visorRenderer.Animating(VisorNow))
            _frameScheduler?.Start(_adaptiveFramePacer.Resolve(ResolveMotionFramesPerSecond(state.AnimationFrameRate), Environment.TickCount64));
        if (VisorBarrage(state)) DrawVisorBarrage(target, dxgiSurface, state);
        if (state.ShowCrosshair) DrawVisorCrosshair(target, dxgiSurface, state);
        return true;
    }

    /// <summary>
    /// The chat shown as barrage (user, 11-07: "弹幕也要留着"): the visor leaves out its chat group and the overlay's own
    /// barrage runs across the screen on top, with every barrage setting (region, avoid the centre, density, size,
    /// duration, text edge). With nothing to show it draws nothing, as on the other appearances.
    /// </summary>
    private static bool VisorBarrage(OverlayCompositionFrameState state) =>
        state.ShowChat && state.ChatDisplayMode == OverlayChatDisplayMode.FullScreenBarrage && state.EmptyStates.Chat is null;

    /// <summary>Draws the barrage over the visor's frame, at the window's own DPI like the other appearances.</summary>
    /// <summary>
    /// The crosshair over the visor (user, 11-10: "给面罩补上准星", then "甲 原样叠加"): the overlay's own crosshair, as on
    /// the other appearances, with every crosshair setting. Fixed in the screen centre; it does not join the visor's opening.
    /// </summary>
    private void DrawVisorCrosshair(ID2D1DeviceContext target, IDXGISurface dxgiSurface, OverlayCompositionFrameState state)
    {
        var dpiX = (float)(96.0 * _renderDpiScaleX);
        var dpiY = (float)(96.0 * _renderDpiScaleY);
        target.SetDpi(dpiX, dpiY);
        var properties = new BitmapProperties1(
            new Vortice.DCommon.PixelFormat(Format.B8G8R8A8_UNorm, Vortice.DCommon.AlphaMode.Premultiplied),
            dpiX, dpiY, BitmapOptions.Target | BitmapOptions.CannotDraw);
        using var surfaceBitmap = target.CreateBitmapFromDxgiSurface(dxgiSurface, properties);
        target.Target = surfaceBitmap;
        try
        {
            target.BeginDraw();
            // one brush cache for the visor frame's extra passes (barrage, crosshair), freed once at the frame's end
            // (review CX-VISOR-SETTINGS-B87-R1)
            _frameBrushes ??= [];
            DrawCrosshair(target, state);
            target.EndDraw(out _, out _).CheckError();
        }
        catch
        {
            DisposeFrameBrushes();
            throw;
        }
        finally
        {
            target.Target = null;
        }
    }

    private void DrawVisorBarrage(ID2D1DeviceContext target, IDXGISurface dxgiSurface, OverlayCompositionFrameState state)
    {
        var dpiX = (float)(96.0 * _renderDpiScaleX);
        var dpiY = (float)(96.0 * _renderDpiScaleY);
        target.SetDpi(dpiX, dpiY);
        var properties = new BitmapProperties1(
            new Vortice.DCommon.PixelFormat(Format.B8G8R8A8_UNorm, Vortice.DCommon.AlphaMode.Premultiplied),
            dpiX, dpiY, BitmapOptions.Target | BitmapOptions.CannotDraw);
        using var surfaceBitmap = target.CreateBitmapFromDxgiSurface(dxgiSurface, properties);
        target.Target = surfaceBitmap;
        try
        {
            target.BeginDraw();
            target.TextAntialiasMode = Vortice.Direct2D1.TextAntialiasMode.Grayscale;
            // one brush cache for the visor frame's extra passes (barrage, crosshair), freed once at the frame's end
            // (review CX-VISOR-SETTINGS-B87-R1)
            _frameBrushes ??= [];
            // calm display dims the barrage like the chat module on the other appearances
            DrawChatPanel(target, state with { Opacity = state.Opacity * CalmFactor(state.ChatRect) });
            target.EndDraw(out _, out _).CheckError();
        }
        catch
        {
            // the caller falls back to the plain path, which starts a new brush cache: release this frame's first
            DisposeFrameBrushes();
            throw;
        }
        finally
        {
            target.Target = null;
        }
    }

    private void ReadVisorAnimationState(ref AppearanceAnimationState state)
    {
        if (_state is not { VisorStyle: true } || _visorRenderer is not { } renderer) return;
        // opening and closing run at the startup frame rate; other visor motion as ambient motion
        if (OverlayVisorRenderer.IntroBusy(_visorOpenAt, _visorCloseAt, VisorNow)) state = state with { StartupActive = true };
        else if (renderer.Animating(VisorNow)) state = state with { AmbientFlowActive = true };
    }

    // The visor's own open and close (user, 11-10: "转场动画应该做专属的"; "头盔上线", closing "反着收回"). It replaces the
    // shared startup cover for the visor, and follows the existing startup transition switch and reduced motion.
    private bool _visorOpenPending, _visorClosing, _visorOpenAwaitsScheduler;
    private double _visorOpenAt = double.NegativeInfinity, _visorCloseAt = double.PositiveInfinity;
    private EventHandler? _visorCloseOnShutdown;
    private DispatcherTimer? _visorCloseTimer, _visorCloseFallback;
    private bool VisorMotion => VisorSelected && _settings.EnableStartupTransition && UiMotion.IsEnabled;

    /// <summary>Show: the opening starts with the first visor frame; event cards wait until it is done.</summary>
    private bool TryBeginVisorIntro(ref bool started, ref double durationMs)
    {
        if (!VisorMotion) return false;
        _visorOpenPending = true;
        started = true;
        durationMs = OverlayVisorRenderer.Durations.Open * 1000;
        return true;
    }

    /// <summary>
    /// Close: a shown visor plays the closing, then disposes. A window never shown, or with motion off, closes at once (the
    /// caller then disposes). Returns true when the closing took over (or the window is already closing or closed).
    /// </summary>
    private bool TryBeginVisorClose()
    {
        var dispatcher = _renderDispatcher;
        lock (_disposeLock)
        {
            if (_disposed || _visorClosing) return true;
            if (!VisorMotion || !_isVisible || !FirstFrameCommitted || dispatcher is null || dispatcher.HasShutdownStarted ||
                dispatcher.HasShutdownFinished || _ownerDispatcher.HasShutdownStarted || _ownerDispatcher.HasShutdownFinished)
                return false;
            _visorClosing = true;
        }
        // the owner thread is going away: clean up here (a Dispose from another thread may have queued its cleanup too late)
        _visorCloseOnShutdown = (_, _) => { StopVisorCloseTimers(); Dispose(); };
        _ownerDispatcher.ShutdownStarted += _visorCloseOnShutdown;
        // a backstop in case the render thread never starts the closing
        _visorCloseFallback = StartOwnerTimer(OverlayVisorRenderer.Durations.Close + 1.0);
        dispatcher.BeginInvoke(() =>
        {
            if (_disposed || _renderThreadDisposed) return;
            _visorCloseAt = VisorNow;
            _frameScheduler?.Start(_adaptiveFramePacer.Resolve(
                ResolveStartupTransitionFramesPerSecond(_settings.StartupTransitionFrameRate), Environment.TickCount64));
            DrawFrame();
            // the closing has started: dispose once it has played (counted from here, not from Close)
            _ownerDispatcher.BeginInvoke(() =>
            {
                if (_disposed) return;
                _visorCloseTimer = StartOwnerTimer(OverlayVisorRenderer.Durations.Close + 0.12);
            });
        }, DispatcherPriority.Send);
        return true;
    }

    /// <summary>
    /// Render thread, once the frame scheduler exists: an opening that began on a frame drawn before the window was shown
    /// starts again from here (that frame was its all but empty first moment) and gets its frames.
    /// </summary>
    private void StartVisorOpeningFrames()
    {
        if (!_visorOpenAwaitsScheduler || _frameScheduler is null) return;
        _visorOpenAwaitsScheduler = false;
        if (_visorClosing || _disposed || _renderThreadDisposed) return;
        _visorOpenAt = VisorNow;
        _frameScheduler.Start(_adaptiveFramePacer.Resolve(
            ResolveStartupTransitionFramesPerSecond(_settings.StartupTransitionFrameRate), Environment.TickCount64));
    }

    /// <summary>An owner-thread timer that disposes the window once (whichever of the closing timers fires first).</summary>
    private DispatcherTimer StartOwnerTimer(double seconds)
    {
        var timer = new DispatcherTimer(DispatcherPriority.Normal, _ownerDispatcher) { Interval = TimeSpan.FromSeconds(seconds) };
        timer.Tick += (_, _) => Dispose();
        timer.Start();
        return timer;
    }

    /// <summary>Stops the closing timers and the shutdown hook (owner thread); called from Dispose.</summary>
    private void StopVisorCloseTimers()
    {
        _visorCloseTimer?.Stop(); _visorCloseTimer = null;
        _visorCloseFallback?.Stop(); _visorCloseFallback = null;
        if (_visorCloseOnShutdown is { } handler) _ownerDispatcher.ShutdownStarted -= handler;
        _visorCloseOnShutdown = null;
    }

    private void DisposeVisorResources()
    {
        _visorRenderer?.Dispose();
        _visorRenderer = null;
        _visorWriteFactory?.Dispose();
        _visorWriteFactory = null;
    }

    private static Color4 VisorColor(HudColor color) => new(color.R / 255f, color.G / 255f, color.B / 255f, 1);

    /// <summary>
    /// The local player's own health (user, 11-10: "连自己的血量一起做"), shown on their own row only and never shared.
    /// Unknown until a reader reports it.
    /// </summary>
    private (OverlayVisorVitals Vitals, float Health) _localVitals = (OverlayVisorVitals.Unknown, 0);
    private readonly object _localVitalsLock = new();
    private readonly OverlayVisorSelfRingWatch _selfRingWatch = new(DesktopRuntimeDiagnostics.WriteDiagnosticLog);

    /// <summary>Reports the local player's health (0..1 while alive); redraws only when it changed.</summary>
    internal void SetLocalVitals(OverlayVisorVitals vitals, float health)
    {
        var next = (vitals, vitals == OverlayVisorVitals.Alive ? Math.Clamp(float.IsFinite(health) ? health : 0, 0, 1) : 0f);
        lock (_localVitalsLock)
        {
            if (_localVitals == next || _disposed) return;
            _localVitals = next;
        }
        PublishStateToRenderer(forceEventPulse: false);
    }

    private (OverlayVisorVitals Vitals, float Health) LocalVitals
    {
        get { lock (_localVitalsLock) return _localVitals; }
    }

    // how far each shown event had opened, so one that leaves part way through opening closes from there
    private readonly Dictionary<object, float> _visorEventReveal = [];
    private readonly Dictionary<object, float> _visorEventLeaveFrom = [];

    /// <summary>
    /// An event title colour by its kind (user, 11-12: "根据事件不同定不一样的状态色"): arrivals, moves and the online summary
    /// pale cyan, ship changes cyan, server changes violet, joining your server green, a loss red and a gain green.
    /// Anything else (system lines) keeps the status cyan.
    /// </summary>
    internal static OverlayVisorEventTone EventTone(OverlayEventNotificationTypes type, bool negative) => type switch
    {
        OverlayEventNotificationTypes.LocationChange or OverlayEventNotificationTypes.OnlineSummary or
            OverlayEventNotificationTypes.MemberPresence => OverlayVisorEventTone.Place,
        OverlayEventNotificationTypes.ShipChange => OverlayVisorEventTone.Ship,
        OverlayEventNotificationTypes.MemberServer or OverlayEventNotificationTypes.PrimaryServer => OverlayVisorEventTone.Server,
        OverlayEventNotificationTypes.SameServer => OverlayVisorEventTone.SameServer,
        OverlayEventNotificationTypes.DeathAndRespawn => negative ? OverlayVisorEventTone.Bad : OverlayVisorEventTone.Good,
        _ => OverlayVisorEventTone.None,
    };

    /// <summary>A visor label in the overlay's language (Simplified, Traditional or English).</summary>
    private string VisorText(string simplified, string traditional, string english) =>
        !_language.StartsWith("zh", StringComparison.OrdinalIgnoreCase) ? english
        : _language.Contains("TW", StringComparison.OrdinalIgnoreCase) || _language.Contains("Hant", StringComparison.OrdinalIgnoreCase) ? traditional
        : simplified;

    private static OverlayVisorModuleOpacity VisorOpacity(OverlayCompositionModuleStyle style) =>
        new((float)Math.Clamp(style.TextOpacity, 0, 1), (float)Math.Clamp(style.BackgroundOpacity, 0, 1), (float)Math.Clamp(style.DecorationOpacity, 0, 1));

    private void ForgetVisorEvents()
    {
        _visorEventReveal.Clear();
        _visorEventLeaveFrom.Clear();
    }

    private OverlayVisorScene BuildVisorScene(OverlayCompositionFrameState state) => BuildVisorScene(state, LocalVitals);

    private OverlayVisorScene BuildVisorScene(OverlayCompositionFrameState state, (OverlayVisorVitals Vitals, float Health) local)
    {
        var facts = state.OverviewFacts;
        // only members: the classic list's own lines ("另有 N 人", "暂无可显示成员") carry no member key and stay out of the
        // visor, which has its count and page lines (11-14)
        var rows = state.MemberRows.Where(row => row.Key is not null).ToArray();
        var members = rows.Select(row =>
        {
            // a member row without a state is one whose state is not known (the read went stale, or the room does not
            // know it): 未知, never in game (11-14 user, "甲 按推荐")
            var kind = row.Presence switch
            {
                PlayerPresenceKind.InGame => OverlayVisorMemberState.InGame,
                PlayerPresenceKind.AppOnline => OverlayVisorMemberState.AppOnly,
                PlayerPresenceKind.Away => OverlayVisorMemberState.Away,
                null => OverlayVisorMemberState.Unknown,
                _ => OverlayVisorMemberState.Offline,
            };
            // outside the game there is no ship or place to show: one tag says why
            var inGame = kind == OverlayVisorMemberState.InGame;
            return new OverlayVisorMember(
                row.DisplayName,
                inGame ? row.Ship ?? "" : "",
                inGame ? row.Location ?? "" : "",
                kind switch
                {
                    OverlayVisorMemberState.AppOnly => VisorText("应用在线", "應用在線", "APP ONLINE"),
                    OverlayVisorMemberState.Away => VisorText("离开", "離開", "AWAY"),
                    OverlayVisorMemberState.Offline => VisorText("离线", "離線", "OFFLINE"),
                    OverlayVisorMemberState.Unknown => VisorText("未知", "未知", "UNKNOWN"),
                    _ => "",
                },
                kind,
                row.Group == OverlayRosterGroup.Pinned,
                row.Group == OverlayRosterGroup.SameServer,
                row.IsSelf ? local.Vitals : OverlayVisorVitals.Unknown,
                row.IsSelf ? local.Health : 0);
        }).ToArray();
        var total = facts?.Total ?? rows.Length;
        var youAt = string.Join(" · ", new[] { facts?.OwnPlace, facts?.OwnShard?.Label }.Where(part => !string.IsNullOrWhiteSpace(part)));
        var paging = state.MemberPaging;
        // 11-07 ("2放"): the existing line counts apply to the visor
        var eventsCount = OverlayDisplaySettings.NormalizeEventNotificationMaxVisibleCount(_settings.EventNotificationMaxVisibleCount);
        var chatCount = OverlayDisplaySettings.NormalizeChatVisibleCount(_settings.ChatMaxVisibleCount);
        // build 86 (user: "从贴边处展开", "可以"): an event opens from the screen edge and closes back to it, so it does not
        // fade while it leaves; the leaving progress drives the closing instead
        var eventRows = state.EventRows.Take(eventsCount).ToArray();
        var events = eventRows.Select(row =>
        {
            // one event across frames: the view model's own row (two events can read the same)
            var key = row.Source ?? (row.Title, row.Detail, row.Timestamp);
            if (row.IsExiting)
            {
                // an event that leaves part way through opening closes from where it got to, from its very first
                // leaving frame (progress 0 there) (reviews CX-VISOR-B86-R1, R2)
                if (!_visorEventLeaveFrom.TryGetValue(key, out var from))
                    _visorEventLeaveFrom[key] = from = _visorEventReveal.TryGetValue(key, out var got) ? got : 1;
                return new OverlayVisorEvent(row.Title, row.Detail, row.Timestamp, 1, 1,
                    MathF.Max(OverlayVisorDraw.LeavingStarted, Math.Clamp(row.MotionProgress, 0, 1)), from, EventTone(row.EventType, row.Negative));
            }
            var reveal = row.IsEntering ? Math.Clamp(row.MotionProgress, 0, 1) : 1;
            _visorEventReveal[key] = reveal;
            // the opening is the line from the edge, not a fade: full strength while it opens (and while it leaves)
            return new OverlayVisorEvent(row.Title, row.Detail, row.Timestamp, reveal, row.IsEntering ? 1 : Math.Clamp(row.Opacity, 0, 1),
                Tone: EventTone(row.EventType, row.Negative));
        }).ToArray();
        // forget the events that are gone
        var present = eventRows.Select(row => row.Source ?? (row.Title, row.Detail, row.Timestamp)).ToHashSet();
        foreach (var gone in _visorEventReveal.Keys.Where(k => !present.Contains(k)).ToList()) _visorEventReveal.Remove(gone);
        foreach (var gone in _visorEventLeaveFrom.Keys.Where(k => !present.Contains(k)).ToList()) _visorEventLeaveFrom.Remove(gone);
        var chat = state.ChatRows.Skip(Math.Max(0, state.ChatRows.Count - chatCount)).Select(row => new OverlayVisorChatLine(
            row.Title, row.Detail, Math.Clamp(row.Opacity, 0, 1))).ToArray();
        var showNotice = state.ShowNotice && !string.IsNullOrWhiteSpace(state.FleetNotice);
        // 0.7.3: a room invite is a reminder card and never takes the top slot (rallies keep the top). The DM badge
        // that marked unread messages and invites is gone (11-13 user: "私信角标 … 整个都不要"); they are seen in the
        // menu overlay instead.
        if (showNotice && !state.NoticeAccent && _viewModel.LiveReminderActive) showNotice = false;
        return new OverlayVisorScene(
            ShowTeam: state.ShowMembers,
            TeamTitle: string.IsNullOrWhiteSpace(state.MembersTitle) ? VisorText("成员", "成員", "MEMBERS") : state.MembersTitle,
            Online: facts?.Online ?? members.Count(m => m.State is OverlayVisorMemberState.InGame or OverlayVisorMemberState.AppOnly or OverlayVisorMemberState.Away),
            InGame: facts?.InGame ?? members.Count(m => m.State == OverlayVisorMemberState.InGame),
            SameServer: facts?.OwnShard?.Count ?? members.Count(m => m.SameServer),
            YouAt: youAt,
            Members: members,
            PageLabel: paging.PageCount > 1
                ? VisorText($"第 {paging.PageIndex + 1} / {paging.PageCount} 页", $"第 {paging.PageIndex + 1} / {paging.PageCount} 頁",
                    $"PAGE {paging.PageIndex + 1} / {paging.PageCount}")
                : "",
            ShowEvents: state.ShowEvents,
            EventsTitle: VisorText("事件", "事件", "EVENTS"),
            Events: events,
            // as barrage, the chat runs across the screen instead of sitting in a visor group (DrawVisorBarrage)
            ShowChat: state.ShowChat && state.ChatDisplayMode != OverlayChatDisplayMode.FullScreenBarrage,
            ChatTitle: string.IsNullOrWhiteSpace(state.ChatTitle) ? VisorText("聊天", "聊天", "CHAT") : state.ChatTitle,
            Chat: chat,
            ShowNotice: showNotice,
            NoticeTitle: state.FleetNoticeTitle,
            NoticeBody: state.FleetNotice,
            NoticeTimer: state.NoticeTimerLabel,
            NoticeHint: state.NoticeMeta ?? "",
            NoticeIsRally: state.NoticeAccent,
            DirectMessage: null,
            TeamCalm: (float)CalmFactor(state.MembersRect),
            EventsCalm: (float)CalmFactor(state.EventRect),
            ChatCalm: (float)CalmFactor(state.ChatRect),
            NoticeCalm: (float)CalmFactor(state.NoticeRect),
            Opacity: (float)Math.Clamp(state.Opacity, OverlayVisorStyle.MinimumOpacity, 1),
            Style: OverlayVisorStyle.FromSettings(VisorColor(state.Palette.Title), VisorColor(state.Palette.Text),
                // 0.7.3 (user, 11-07: "浮层先不做节日"): the holiday gold stays saved but is not drawn.
                _settings.VisorSize, holidayGold: false, tilt: _settings.VisorTilt, distance: _settings.VisorViewingDistance))
        {
            // the frame's own size: same aspect as the render target, known before the first swap-chain frame
            ChatPlate = _settings.VisorChatPlate,
            CountLabels = [VisorText("在线", "線上", "ONLINE"), VisorText("游戏中", "遊戲中", "IN GAME"), VisorText("同服", "同服", "SAME SERVER")],
            RealtimeUnknown = state.RealtimeStatusUnknown ? VisorText("实时状态未知", "即時狀態未知", "REALTIME STATUS UNKNOWN") : "",
            MembersAutoWidth = _settings.VisorMembersAutoWidth,
            // 11-10 user: "不希望模块上下自适应了，老是会变位置，就要固定上下高度": the members always keep the set
            // height; the saved adaptive-height switch is kept for older versions but no longer read
            MembersAutoHeight = false,
            MembersWidth = (float)OverlayDisplaySettings.NormalizeVisorMembersWidth(_settings.VisorMembersWidth),
            MembersHeight = (float)OverlayDisplaySettings.NormalizeVisorMembersHeight(_settings.VisorMembersHeight),
            EventsAutoWidth = _settings.VisorEventsAutoWidth,
            ChatAutoWidth = _settings.VisorChatAutoWidth,
            EventsWidth = (float)OverlayDisplaySettings.NormalizeVisorMembersWidth(_settings.VisorEventsWidth),
            ChatWidth = (float)OverlayDisplaySettings.NormalizeVisorMembersWidth(_settings.VisorChatWidth),
            EventsCount = eventsCount,
            ChatCount = chatCount,
            // their places are kept by their settings, so the members never move when events or chat come and go
            EventsPlaced = _settings.ShowEventNotifications,
            TeamCount = VisorText($"共 {total} 人", $"共 {total} 人", $"{total} TOTAL"),
            ModuleOpacity = new Dictionary<string, OverlayVisorModuleOpacity>
            {
                ["team"] = VisorOpacity(state.MembersStyle),
                ["events"] = VisorOpacity(state.EventStyle),
                ["chat"] = VisorOpacity(state.ChatStyle),
                ["top"] = VisorOpacity(state.NoticeStyle),
            },
            ChatPlaced = _settings.ShowChat && state.ChatDisplayMode != OverlayChatDisplayMode.FullScreenBarrage,
            Spots = VisorSpots((float)(Math.Max(1, state.Width) / (Math.Max(1, state.Height) / 1080.0))),
            RallyBottom = OverlayVisorPlacement.RallyAtBottom(_layout,
                (float)(Math.Max(1, state.Width) / (Math.Max(1, state.Height) / 1080.0))),
            Badge = OverlayVisorPlacement.Badge(_settings.VisorBadgeX, _settings.VisorBadgeY,
                (float)(Math.Max(1, state.Width) / (Math.Max(1, state.Height) / 1080.0))),
        };
    }
}
