using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime;

public sealed partial class NativeAccountRuntimeBinding
{
    // Explicit device-only projection: never reuse this path for account events
    // or social activity. The captured actual slot still owns the callback.
    private BridgeEnvelope DeviceEvent(long generation, object payload, string name, bool menu = false) =>
        Read(owner =>
        {
            var control = _root.FirstUseMode?.ControlGeneration ?? owner.Generation;
            if (control < 0 || generation != (menu ? owner.CurrentOverlaySourceScope.Generation : control)) return null;
            var envelope = BridgeEnvelope.Event(name, control, 0, payload);
            // Serialization may invoke external payload getters. A subsequent
            // epoch change can only reject the captured callback, never retag it.
            return control == (_root.FirstUseMode?.ControlGeneration ?? owner.Generation) ? envelope : null;
        }, (BridgeEnvelope?)null)
        ?? throw new OperationCanceledException("Native device callback ownership has changed.");

    public BridgeEnvelope DeviceNotificationActivation(long generation, object payload) =>
        DeviceEvent(generation, payload, "notificationSettings.activated");
    public BridgeEnvelope DeviceUpdateProgress(long generation, object payload) =>
        DeviceEvent(generation, payload, Updates.FlutterUpdateBridgeDispatcher.ProgressEventName);
    public BridgeEnvelope DeviceMenuHotkeyIntent(long generation, object payload) =>
        DeviceEvent(generation, payload, Overlay.MenuHotkeyBridgeDispatcher.IntentEvent, menu: true);
}
