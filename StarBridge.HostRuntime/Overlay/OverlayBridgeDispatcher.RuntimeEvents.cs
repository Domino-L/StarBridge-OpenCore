namespace StarBridge.HostRuntime.Overlay;

using StarBridge.NativeBridge;

public sealed partial class OverlayBridgeDispatcher
{
    public const string RuntimeEventsCapability = "overlay.runtimeEvents";
    public const string RuntimeChangedEvent = "overlay.runtime.changed";

    private InformationOverlayRuntimeSnapshot? _pendingRuntimeState;
    private int _runtimeStateDrainScheduled;

    public event Action<BridgeEnvelope>? EventReady;

    // Raised on the runtime's control thread: hand off at once, latest state wins.
    // One drain at a time keeps publication order equal to change order, so a
    // burst (open, then a hotkey close) never ends on the older state.
    private void OnRuntimeStateChanged(InformationOverlayRuntimeSnapshot snapshot)
    {
        if (_disposed) return;
        Volatile.Write(ref _pendingRuntimeState, snapshot);
        if (Interlocked.Exchange(ref _runtimeStateDrainScheduled, 1) == 0)
            ThreadPool.UnsafeQueueUserWorkItem(_ => DrainRuntimeState(), null);
    }

    private void DrainRuntimeState()
    {
        while (true)
        {
            if (Interlocked.Exchange(ref _pendingRuntimeState, null) is { } snapshot) PublishRuntimeState(snapshot);
            Volatile.Write(ref _runtimeStateDrainScheduled, 0);
            if (Volatile.Read(ref _pendingRuntimeState) is null ||
                Interlocked.Exchange(ref _runtimeStateDrainScheduled, 1) != 0) return;
        }
    }

    // Same payload as overlay.runtime.getState. Device-level state: no account
    // context, tagged with the current control generation so a reconnect drops it.
    private void PublishRuntimeState(InformationOverlayRuntimeSnapshot snapshot)
    {
        if (_disposed || EventReady is not { } publish) return;
        try
        {
            var generation = _generation();
            if (generation < 0) return;
            publish(BridgeEnvelope.Event(RuntimeChangedEvent, generation, 0, RuntimePayload(snapshot)));
        }
        catch (Exception exception) when (exception is not OutOfMemoryException)
        {
            // A retired account slot or closed transport only loses this push;
            // the next open/getState still returns the authoritative snapshot.
        }
    }
}
