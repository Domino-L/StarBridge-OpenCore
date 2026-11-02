using StarBridge.HostRuntime.Overlay;

namespace StarBridge.Desktop;

public sealed partial class NativeInformationOverlayRuntime : IInformationOverlayRuntimeStateSource
{
    private InformationOverlayRuntimeSnapshot? _publishedState;
    private string? _publishedRegistrationFailures;

    public event Action<InformationOverlayRuntimeSnapshot>? StateChanged;

    // Control thread only. Commands, hotkeys and window closes publish at once;
    // the 750ms follow-game tick is the backstop for every other _snapshot write.
    // Record equality coalesces repeated writes of the same state.
    private void PublishStateIfChanged()
    {
        if (_disposed) return;
        var current = Volatile.Read(ref _snapshot);
        var failures = HotkeyRegistrationFailures;
        if (current == _publishedState && failures == _publishedRegistrationFailures) return;
        _publishedRegistrationFailures = failures;
        _publishedState = current;
        if (StateChanged is not { } handlers) return;
        foreach (Action<InformationOverlayRuntimeSnapshot> handler in handlers.GetInvocationList())
        {
            try { handler(current); }
            catch (Exception exception)
            {
                DesktopRuntimeDiagnostics.WriteDiagnosticLog($"native-overlay-state-event-failed | {exception.GetType().Name}");
            }
        }
    }
}
