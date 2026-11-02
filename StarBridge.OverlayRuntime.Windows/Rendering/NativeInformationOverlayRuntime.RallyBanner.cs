namespace StarBridge.Desktop;

using System.Windows.Threading;
using StarBridge.Core.Overlay;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Overlay;

// A running rally owns the top notice slot. With the overlay open it is drawn there; with
// the overlay closed the same slot is drawn alone at the same place over the game, click-
// through, and it goes away when the rally is answered, ended or over.
public sealed partial class NativeInformationOverlayRuntime : IRallyBannerSink
{
    private InformationOverlayReminder? _rally;
    private bool _rallyIsSample;
    private OverlayCompositionHudWindow? _rallyBanner;
    private OverlayCompositionHudWindow? _rallyShownOn;

    public async ValueTask<bool> TryPresentAsync(RallyBannerNotice notice, CancellationToken cancellationToken)
    {
        var dispatcher = _dispatcher;
        if (_disposed || dispatcher is null || dispatcher.HasShutdownStarted) return false;
        var reminder = new InformationOverlayReminder(notice.Id, 0, 0, notice.Preview, notice.IsCurrent)
            { Rally = new(notice.Text, notice.ExpiresAt, notice.Sample) };
        var operation = dispatcher.InvokeAsync(() =>
        {
            cancellationToken.ThrowIfCancellationRequested();
            return PresentRallyOnControlThread(reminder);
        }, DispatcherPriority.Send, cancellationToken);
        return await operation.Task.WaitAsync(cancellationToken).ConfigureAwait(false);
    }

    public void Clear(Guid id)
    {
        var dispatcher = _dispatcher;
        if (dispatcher is null || dispatcher.HasShutdownStarted || dispatcher.HasShutdownFinished) return;
        dispatcher.BeginInvoke(() => { if (_rally?.Id == id) ClearRallyOnControlThread(); }, DispatcherPriority.Send);
    }

    // True when the rally is on screen now. A real rally that arrives while the game is in
    // the background is kept and shown once the game is in front again, while it is current.
    private bool PresentRallyOnControlThread(InformationOverlayReminder reminder)
    {
        if (_disposed || _workspace is null || !reminder.IsCurrent()) return false;
        // "Try it" never takes the slot from a running real rally.
        if (reminder.Rally!.Sample && _rally is { } held && !_rallyIsSample && held.IsCurrent()) return false;
        ClearRallyOnControlThread();
        _rally = reminder;
        // "Try it" in the client shows the banner even with the game in the background.
        _rallyIsSample = reminder.Rally!.Sample;
        SyncRally(StarCitizenProcessProbe.IsForeground());
        return _rallyShownOn is not null;
    }

    private void SyncRally(bool gameForeground)
    {
        if (_rally is not { } rally) return;
        if (_disposed || !rally.IsCurrent() || _workspace is null) { ClearRallyOnControlThread(); return; }
        var bannerAllowed = !MenuActive && _livePreviewSurface is null && (gameForeground || _rallyIsSample);
        OverlayCompositionHudWindow? target = _window is { IsVisible: true } open ? open
            : bannerAllowed ? _rallyBanner ?? OpenRallyBanner() : null;
        if (!ReferenceEquals(target, _rallyBanner)) CloseRallyBanner();
        if (ReferenceEquals(target, _rallyShownOn)) return;
        _rallyShownOn?.ClearRally(rally.Id);
        _rallyShownOn = target is not null && target.ShowRally(RallySlotFor(rally, _workspace.Language)) ? target : null;
    }

    private void ClearRallyOnControlThread()
    {
        var rally = _rally;
        _rally = null;
        _rallyIsSample = false;
        if (rally is not null) _rallyShownOn?.ClearRally(rally.Id);
        _rallyShownOn = null;
        CloseRallyBanner();
    }

    // Runs before the menu and live-preview early returns of the game-window check: a
    // revoked message preview and a banner that must not show never wait for them.
    private void SyncNoticeSafety()
    {
        RevokeReminderPreview();
        if (_livePreviewSurface is not null || MenuActive) SyncRally(gameForeground: false);
    }

    private OverlayCompositionHudWindow? OpenRallyBanner()
    {
        if (_livePreviewSurface is not null || MenuActive || _workspace is not { } workspace) return null;
        var surface = ResolveTargetSurfaceBounds(out var dpi);
        // Only the notice slot: every other module, the crosshair and the startup transition stay off.
        var settings = OverlaySkinCatalog.Resolve(workspace.Settings, SafeReadEntitlements()).Settings with
        {
            ShowNotice = false, ShowSquads = false, ShowMission = false, ShowMembers = false, ShowChat = false,
            ShowEventNotifications = false, ShowCrosshair = false, EnableStartupTransition = false,
            AutoFocusGameWindowOnOpen = false
        };
        var banner = new OverlayCompositionHudWindow(new OverlayAuthorizedRoster([]), [], ToDesktopLayout(workspace.Layout),
            settings, ReadRosterSettings(), workspace.Language, hasFleet: false, BuildCommandState(workspace.Language) with
            { NoticeTitle = "", NoticeText = "" }, PlayerPresenceKind.AppOnline, string.Empty, surface,
            OverlayStartupTransitionContext.ForLanguage(workspace.Language), OverlaySceneContext.Local(settings.ScenePreference), dpi);
        banner.SetMenuAbove(_menuWindow);
        Exception? failure = null;
        if (!OverlayStartupBoundary.TryShow(banner.Show, banner.Close, exception => failure = exception))
        {
            DesktopRuntimeDiagnostics.WriteDiagnosticLog($"native-overlay-rally-banner-failed | {failure}");
            return null;
        }
        banner.Closed += RallyBannerClosed;
        return _rallyBanner = banner;
    }

    private void CloseRallyBanner()
    {
        if (_rallyBanner is not { } banner) return;
        _rallyBanner = null;
        if (ReferenceEquals(_rallyShownOn, banner)) _rallyShownOn = null;
        if (_rally is { } rally) banner.ClearRally(rally.Id); // stops its minute clock
        banner.Closed -= RallyBannerClosed;
        try { banner.Close(); }
        catch (Exception exception) { DesktopRuntimeDiagnostics.WriteDiagnosticLog($"native-overlay-rally-banner-close-failed | {exception}"); }
    }

    private void RallyBannerClosed(object? sender, EventArgs e)
    {
        if (sender is OverlayCompositionHudWindow banner) banner.Closed -= RallyBannerClosed;
        if (!ReferenceEquals(_rallyBanner, sender)) return;
        _rallyBanner = null;
        if (ReferenceEquals(_rallyShownOn, sender)) _rallyShownOn = null;
    }
}
