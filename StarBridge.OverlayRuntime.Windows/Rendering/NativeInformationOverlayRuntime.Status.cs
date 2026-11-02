namespace StarBridge.Desktop;

using StarBridge.HostRuntime.Support;
using StarBridge.HostRuntime.Onboarding;
using System.Windows.Threading;

public sealed partial class NativeInformationOverlayRuntime : IRuntimeOverlayStatusReader, INativeOverlayObservationReader
{
    private readonly string _firstUseOverlayRuntimeId = Guid.NewGuid().ToString("N");
    private long _firstUseAcceptedHotkeyInputs;
    private string? _firstUseLastHotkeyOutcome;

    public async ValueTask<NativeOverlayObservation?> ReadNativeOverlayObservationAsync(CancellationToken token = default)
    {
        token.ThrowIfCancellationRequested();
        Dispatcher? dispatcher;
        lock (_lifetimeLock) { ObjectDisposedException.ThrowIf(_disposed, this); dispatcher = _dispatcher; }
        if (dispatcher is null || dispatcher.HasShutdownStarted || dispatcher.HasShutdownFinished) return null;
        return await dispatcher.InvokeAsync<NativeOverlayObservation?>(() =>
        {
            // Pure observation on the actual control STA. Never validates or
            // renews a preview lease, applies settings, opens a HUD or samples data.
            if (_disposed || _controlThreadCleanedUp) return null;
            var window = _window;
            var preview = _livePreviewSurface;
            return new(_firstUseOverlayRuntimeId, _snapshot.AppliedRevision, _snapshot.WindowState,
                window?.NativeWindowIsVisible == true, window?.FirstFrameCommitted == true,
                new(_hotkeyState, _workspace?.HotkeyBinding, Interlocked.Read(ref _hotkeyConfigurationRevision),
                    _firstUseAcceptedHotkeyInputs, _firstUseLastHotkeyOutcome),
                preview is not null && _livePreviewSession is not null
                    ? new(_livePreviewSession, preview.AppliedRevision, preview.Hud.NativeWindowIsVisible,
                        preview.Hud.FirstFrameCommitted)
                    : new(null, null, false, false));
        }, DispatcherPriority.Background, token).Task.WaitAsync(token).ConfigureAwait(false);
    }

    public async ValueTask<RuntimeOverlayStatus> ReadStatusAsync(CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        Dispatcher? dispatcher;
        lock (_lifetimeLock)
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            dispatcher = _dispatcher;
        }
        if (dispatcher is null || dispatcher.HasShutdownStarted || dispatcher.HasShutdownFinished)
            return new("unavailable", "unavailable", null, 0);
        var operation = dispatcher.InvokeAsync(() =>
        {
            // Observe on the owning STA. Do not call ApplyWorkspace,
            // SynchronizeCore, ConfigureHotkey, or EvaluateGameWindowRules.
            if (_disposed || _controlThreadCleanedUp)
                return new RuntimeOverlayStatus("unavailable", "unavailable", null, 0);
            var state = _window is { IsVisible: true } ? "open" :
                _snapshot.WindowState is "failed" or "unavailable" ? _snapshot.WindowState : "closed";
            return new RuntimeOverlayStatus(state, _hotkeyState, _workspace?.HotkeyBinding, _snapshot.AppliedRevision);
        }, DispatcherPriority.Background, cancellationToken);
        return await operation.Task.WaitAsync(cancellationToken).ConfigureAwait(false);
    }
}
