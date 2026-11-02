namespace StarBridge.HostRuntime.Notifications;

using System.Text.Json;
using StarBridge.HostRuntime.Overlay;
using StarBridge.NativeBridge;

public sealed partial class NotificationSettingsBridgeDispatcher
{
    private InformationOverlayDirectUnread? _lastDirectUnread;
    private long _directUnreadGeneration;
    private bool _directUnreadPublished;

    // Called under _gate to serialize snapshots with Reset/Dispose. The native
    // sink only queues BeginInvoke; it must never wait for the renderer here.
    private void PublishDirectUnread(InformationOverlayDirectUnread? unread, bool reset = false)
    {
        if (reset) {
            _directUnreadPublished = false;
            _lastDirectUnread = null;
        }
        var current = generation();
        if (!reset && _directUnreadPublished && _directUnreadGeneration == current && _lastDirectUnread == unread) return;
        try {
            directUnread?.UpdateDirectUnread(unread);
            if (!reset) {
                _lastDirectUnread = unread;
                _directUnreadGeneration = current;
                _directUnreadPublished = true;
            }
        } catch (Exception) {
            // This visual projection cannot fail or change the domain response.
            // Leave the value unpublished so a later read can retry delivery.
        }
    }

    private void ObserveDirectUnread(BridgeEnvelope request, BridgeEnvelope response)
    {
        if (directUnread is null || request.Payload.TryGetProperty("targetRef", out _)) return;
        try {
            var current = generation();
            if (_directUnreadPublished && _directUnreadGeneration != current)
                PublishDirectUnread(null, reset: true);
            // An old response must never overwrite an already-current mark.
            if (request.SessionGeneration != current || response.SessionGeneration != current) return;
            if (request.AccountContext is null) { PublishDirectUnread(null); return; }
            var settings = Read();
            if (!settings.OverlayEnabled || !NotificationSourcePolicy.Allows(
                _policies.Read(request.AccountContext).For("directMessages"), NotificationEventKind.DirectMessage)) {
                PublishDirectUnread(null); return;
            }
            if (response.Status != BridgeResponseStatuses.Ok || response.AccountContext != request.AccountContext) return;
            var root = response.Payload;
            if (root.GetProperty("schemaVersion").GetInt32() != 1) return;
            var rows = root.GetProperty("conversations");
            if (rows.GetArrayLength() > 2000) return;
            var count = 0;
            var callsign = "";
            foreach (var row in rows.EnumerateArray()) {
                var unread = row.GetProperty("unreadCount").GetInt32();
                if (unread < 0) return;
                if (unread == 0) continue;
                count++;
                if (count == 1 && settings.Preview != "hiddenDetails" &&
                    row.TryGetProperty("callsign", out var name) && name.ValueKind == JsonValueKind.String &&
                    name.GetString() is { Length: <= 512 } value)
                    callsign = value;
            }
            if (request.SessionGeneration != generation()) {
                PublishDirectUnread(null, reset: true); return;
            }
            PublishDirectUnread(count == 0 ? null : new(count, count == 1 ? callsign : ""));
        } catch (Exception) {
            // Failed settings/policy reads and malformed snapshots are best effort.
            // No message text is retained, and the original response is preserved.
        }
    }
}
