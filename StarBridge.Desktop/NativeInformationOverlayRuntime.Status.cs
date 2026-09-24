namespace StarBridge.Desktop;

using StarBridge.HostRuntime.Support;
using System.Windows.Threading;

public sealed partial class NativeInformationOverlayRuntime : IRuntimeOverlayStatusReader
{
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
