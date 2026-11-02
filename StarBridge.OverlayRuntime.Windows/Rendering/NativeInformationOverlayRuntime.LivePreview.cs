using System.Diagnostics;
using System.Windows.Threading;
using StarBridge.Core.Overlay;
using StarBridge.HostRuntime.Overlay;

namespace StarBridge.Desktop;

public sealed partial class NativeInformationOverlayRuntime : IInformationOverlayLivePreviewRuntime, IInformationOverlayLivePreviewControls, IInformationOverlayLivePreviewPlayback
{
    private OverlayAppearancePreviewSurface? _livePreviewSurface;
    private string? _livePreviewSession;
    private InformationOverlayLivePreviewScope? _livePreviewScope;
    private DispatcherTimer? _livePreviewWatch;
    private long _livePreviewDeadline;
    private bool _livePreviewRestore;
    private long _livePreviewProtectionRevision;
    private long _livePreviewPlaybackRevision;
    private long _livePreviewRenewalRevision;
    private OverlayPreviewClientViewport? _livePreviewClient;
    private OverlayPreviewControlArea[] _livePreviewControlAreas = [];
    internal TimeSpan? TestLivePreviewLifetime;
    internal IntPtr TestLivePreviewHandle => _livePreviewSurface?.Hud.NativeHandle ?? IntPtr.Zero;

    public async ValueTask<IReadOnlyList<OverlayAppearancePlacementState>?> ReadLivePreviewPlacementStatesAsync(
        string sessionId, long revision, CancellationToken cancellationToken = default)
    {
        if (!Guid.TryParseExact(sessionId, "N", out _) || revision is < 0 or > 9007199254740991) return null;
        return await PreviewDispatcher().InvokeAsync<IReadOnlyList<OverlayAppearancePlacementState>?>(() =>
        {
            cancellationToken.ThrowIfCancellationRequested();
            ValidateLivePreviewScope();
            return _livePreviewSession == sessionId && _livePreviewSurface is { } surface && surface.AppliedRevision == revision
                ? surface.Hud.ReadPreviewPlacementStates() : null;
        }, DispatcherPriority.Send, cancellationToken).Task.ConfigureAwait(false);
    }

    public IReadOnlyList<string> GetLiveAppearancePreviewIds() => _disposed ? [] :
        OverlaySkinCatalog.Listed.Where(p => p.IsPreviewAvailable).Select(p => p.Id.ToString()).Take(8).ToArray();

    public async ValueTask<string?> OpenLiveAppearancePreviewAsync(InformationOverlayLivePreviewDraft draft,
        InformationOverlayLivePreviewScope scope, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(draft); ArgumentNullException.ThrowIfNull(scope);
        var dispatcher = PreviewDispatcher();
        var session = await dispatcher.InvokeAsync(() =>
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            cancellationToken.ThrowIfCancellationRequested();
            if (!scope.IsCurrent() || !GetLiveAppearancePreviewIds().Contains(draft.AppearanceId, StringComparer.Ordinal)) return null;
            // Validate everything before closing an accepted preview/normal HUD.
            var frame = LiveFrame(0, draft);
            var bounds = ResolveTargetSurfaceBounds(out var dpi);
            var restore = _livePreviewSurface is not null ? _livePreviewRestore : HasDisplayDemand || _openingCancellation is not null;
            CloseLivePreviewCore(restore: false);
            CloseAppearancePreviewCore();
            _livePreviewRestore = restore;
            _livePreviewScope = scope;
            TryCloseWindow();
            SetHealthySnapshot("closed", false); // normal source drivers and usage demand stop
            try
            {
                _livePreviewSurface = new(frame, bounds, dpi, protectControlsOnCreate: true); SyncRally(gameForeground: false);
                var ownedSurface = _livePreviewSurface;
                ownedSurface.TransitionStateChanged += () =>
                {
                    if (ReferenceEquals(_livePreviewSurface, ownedSurface)) ApplyLivePreviewProtection();
                };
                cancellationToken.ThrowIfCancellationRequested();
                if (!scope.IsCurrent()) { CloseLivePreviewCore(restore: false); return null; }
                _livePreviewSession = Guid.NewGuid().ToString("N");
                RenewLivePreviewDeadline();
                _livePreviewWatch = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(100) };
                _livePreviewWatch.Tick += (_, _) => ValidateLivePreviewScope();
                _livePreviewWatch.Start();
                return _livePreviewSession;
            }
            catch { CloseLivePreviewCore(restore: true); throw; }
        }, DispatcherPriority.Send, cancellationToken).Task.ConfigureAwait(false);
        if (cancellationToken.IsCancellationRequested)
        {
            if (session is not null) await CloseLiveAppearancePreviewAsync(session, CancellationToken.None);
            cancellationToken.ThrowIfCancellationRequested();
        }
        return session;
    }

    public async ValueTask<long?> UpdateLiveAppearancePreviewAsync(string sessionId, long revision,
        InformationOverlayLivePreviewDraft draft, CancellationToken cancellationToken = default)
    {
        if (!Guid.TryParseExact(sessionId, "N", out _) || revision is < 1 or > 9007199254740991) return null;
        var dispatcher = PreviewDispatcher();
        return await dispatcher.InvokeAsync<long?>(() =>
        {
            cancellationToken.ThrowIfCancellationRequested();
            ValidateLivePreviewScope();
            if (_livePreviewSession != sessionId || _livePreviewSurface is not { } surface) return null;
            var frame = LiveFrame(revision, draft);
            var bounds = ResolveTargetSurfaceBounds(out var dpi);
            if (!surface.Update(frame, bounds, dpi)) return null;
            ApplyLivePreviewProtection();
            return revision;
        }, DispatcherPriority.Send, cancellationToken).Task.ConfigureAwait(false);
    }
    private void RenewLivePreviewDeadline() => _livePreviewDeadline = Stopwatch.GetTimestamp() +
        (long)((TestLivePreviewLifetime ?? TimeSpan.FromMinutes(2)).TotalSeconds * Stopwatch.Frequency);

    public async ValueTask<long?> RenewLiveAppearancePreviewAsync(string sessionId, long revision,
        CancellationToken cancellationToken = default)
    {
        if (!Guid.TryParseExact(sessionId, "N", out _) || revision is < 1 or > 9007199254740991) return null;
        return await PreviewDispatcher().InvokeAsync<long?>(() =>
        {
            cancellationToken.ThrowIfCancellationRequested();
            ValidateLivePreviewScope(); // Checks expiry BEFORE renewal; no revival.
            if (_livePreviewSession != sessionId || _livePreviewSurface is null ||
                revision <= _livePreviewRenewalRevision) return null;
            _livePreviewRenewalRevision = revision;
            RenewLivePreviewDeadline();
            return revision;
        }, DispatcherPriority.Send, cancellationToken).Task.ConfigureAwait(false);
    }

    public async ValueTask CloseLiveAppearancePreviewAsync(string sessionId, CancellationToken cancellationToken = default)
    {
        if (!Guid.TryParseExact(sessionId, "N", out _)) return;
        var dispatcher = PreviewDispatcher();
        await dispatcher.InvokeAsync(() =>
        {
            if (_livePreviewSession == sessionId) CloseLivePreviewCore(restore: true);
        }, DispatcherPriority.Send, cancellationToken).Task.ConfigureAwait(false);
    }
    public async ValueTask<long?> ProtectLivePreviewControlsAsync(string sessionId, long revision,
        OverlayPreviewClientViewport viewport, IReadOnlyList<OverlayPreviewControlArea> areas,
        CancellationToken cancellationToken = default)
    {
        if (!Guid.TryParseExact(sessionId, "N", out _) || revision is < 1 or > 9007199254740991 ||
            !viewport.IsValid || areas.Count > 16 || areas.Any(a => !a.IsValid)) return null;
        var copy = areas.ToArray();
        return await PreviewDispatcher().InvokeAsync<long?>(() =>
        {
            cancellationToken.ThrowIfCancellationRequested();
            ValidateLivePreviewScope();
            if (_livePreviewSession != sessionId || _livePreviewSurface is not { } surface ||
                revision <= _livePreviewProtectionRevision) return null;
            OverlayPreviewControlRegion.Apply(surface.Hud.NativeHandle, viewport,
                surface.TransitionPlaying ? [] : copy);
            _livePreviewClient = viewport; _livePreviewControlAreas = copy;
            _livePreviewProtectionRevision = revision;
            return revision;
        }, DispatcherPriority.Send, cancellationToken).Task.ConfigureAwait(false);
    }
    private static OverlayAppearancePreviewFrame LiveFrame(long revision, InformationOverlayLivePreviewDraft draft)
    {
        var skin = Enum.Parse<OverlaySkin>(draft.AppearanceId, ignoreCase: false);
        var valid = true;
        ValidateInstalledLivePreviewOptions(skin, draft.Options, ref valid);
        if (!valid) throw new FormatException("Unsupported appearance choices.");
        return new(revision, skin, draft.Settings, draft.CopyLayout(), draft.Options, draft.Language, draft.ReduceMotion);
    }
    public async ValueTask<OverlayPreviewPlaybackReceipt?> PlayLivePreviewAsync(string sessionId, long revision,
        OverlayAppearancePreviewPlayback action, CancellationToken cancellationToken = default)
    {
        if (!Guid.TryParseExact(sessionId, "N", out _) || revision is < 1 or > 9007199254740991 || !Enum.IsDefined(action)) return null;
        return await PreviewDispatcher().InvokeAsync<OverlayPreviewPlaybackReceipt?>(() =>
        {
            cancellationToken.ThrowIfCancellationRequested();
            ValidateLivePreviewScope();
            if (_livePreviewSession != sessionId || _livePreviewSurface is not { } surface ||
                revision <= _livePreviewPlaybackRevision) return null;
            // Before the first control receipt the temporary HUD is empty.
            // An untrusted/unready page cannot use transition to uncover it.
            var ready = action != OverlayAppearancePreviewPlayback.Transition ||
                _livePreviewProtectionRevision > 0 && _livePreviewClient is { IsValid: true };
            var accepted = ready && surface.Play(action);
            _livePreviewPlaybackRevision = revision;
            return new(revision, accepted);
        }, DispatcherPriority.Send, cancellationToken).Task.ConfigureAwait(false);
    }
    static partial void ValidateInstalledLivePreviewOptions(OverlaySkin skin, OverlayAppearanceOptions options, ref bool valid);
    private void ValidateLivePreviewScope()
    {
        if (_livePreviewSurface is null) return;
        if (_livePreviewScope?.IsCurrent() != true) CloseLivePreviewCore(restore: false);
        else if (_livePreviewScope.HasClientViewport && _livePreviewScope.CurrentClientViewport() is not { IsValid: true })
            CloseLivePreviewCore(restore: true); // Lost primary presentation, not an account switch.
        else if (Stopwatch.GetTimestamp() >= _livePreviewDeadline) CloseLivePreviewCore(restore: true);
        else if (_livePreviewClient is not null && _livePreviewScope.HasClientViewport &&
            _livePreviewScope.CurrentClientViewport() is { IsValid: true } client && client != _livePreviewClient)
        {
            OverlayPreviewControlRegion.Apply(_livePreviewSurface.Hud.NativeHandle, client,
                _livePreviewSurface.TransitionPlaying ? [] : _livePreviewControlAreas);
            _livePreviewClient = client; // Follow physical client motion without relocating any module.
        }
    }
    private void ApplyLivePreviewProtection()
    {
        if (_livePreviewSurface is not { } surface) return;
        // Store the latest inspector/popup regions during playback, but never
        // punch holes through the actual full-screen startup. Completion,
        // interruption or a draft update restores the LATEST accepted regions.
        OverlayPreviewControlRegion.Apply(surface.Hud.NativeHandle, _livePreviewClient,
            surface.TransitionPlaying ? [] : _livePreviewControlAreas);
    }
    private void CloseLivePreviewCore(bool restore)
    {
        var canRestore = restore && _livePreviewRestore && _livePreviewScope?.IsCurrent() == true && !_disposed && !_controlThreadCleanedUp;
        _livePreviewWatch?.Stop(); _livePreviewWatch = null;
        var surface = _livePreviewSurface; _livePreviewSurface = null;
        _livePreviewSession = null; _livePreviewScope = null; _livePreviewRestore = false;
        _livePreviewClient = null; _livePreviewControlAreas = []; _livePreviewProtectionRevision = 0; _livePreviewPlaybackRevision = 0;
        _livePreviewRenewalRevision = 0; _livePreviewDeadline = 0;
        surface?.Dispose();
        if (canRestore && _workspace is { HasInvalidConfiguration: false })
        {
            // No old content/settings/credentials are cached. Normal Open reads
            // current sources and eligibility; no forced startup/focus on exit.
            var current = _workspace;
            _workspace = current with { Settings = current.Settings with { EnableStartupTransition = false, AutoFocusGameWindowOnOpen = false } };
            try { _ = OpenCore(retry: false); }
            finally { _workspace = current; }
        }
    }
}
