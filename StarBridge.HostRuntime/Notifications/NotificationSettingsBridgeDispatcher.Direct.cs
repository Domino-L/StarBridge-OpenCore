namespace StarBridge.HostRuntime.Notifications;

using StarBridge.NativeBridge;
using System.Text.Json;

public sealed partial class NotificationSettingsBridgeDispatcher
{
    private long _directEpoch;

    private async ValueTask<BridgeEnvelope> ObserveDirectAsync(BridgeEnvelope request, BridgeEnvelope response, CancellationToken token)
    {
        DesktopNotification? notice = null;
        lock (_gate) {
            if (_disposed || token.IsCancellationRequested || request.SessionGeneration != generation()) return response;
            // Consume the sequence before any preference, foreground or system gate.
            if (!_direct.Observe(request, response, generation())) return response;
            try {
                var settings = Read();
                if (request.AccountContext is null || !NotificationSourcePolicy.Allows(
                    _policies.Read(request.AccountContext).For("directMessages"), NotificationEventKind.DirectMessage)) return response;
                if (!settings.WindowsEnabled || !settings.DirectMessageWindowsEnabled || desktop == null ||
                    !(canNotifyDesktop?.Invoke() ?? false)) return response;
                var keys = _direct.FreshKeys.ToHashSet(StringComparer.Ordinal);
                var rows = response.Payload.GetProperty("conversations").EnumerateArray()
                    .Where(row => keys.Contains(row.GetProperty("conversationKey").GetString()!)).ToArray();
                if (rows.Length == 0) return response;
                var row = rows.OrderByDescending(value => value.GetProperty("lastMessageAt").GetDateTimeOffset()).First();
                var name = row.GetProperty("callsign").GetString() ?? "";
                var preview = row.GetProperty("preview").GetString() ?? "";
                if (name.Length > 512 || preview.Length > 4096) return response;
                var id = Guid.NewGuid();
                var epoch = Interlocked.Read(ref _directEpoch);
                var started = System.Diagnostics.Stopwatch.GetTimestamp();
                bool Current() => !_disposed && epoch == Interlocked.Read(ref _directEpoch) &&
                    request.SessionGeneration == generation() && System.Diagnostics.Stopwatch.GetElapsedTime(started) < TimeSpan.FromSeconds(30);
                notice = CreateDesktop(id, false, 0, 0, settings, Current) with {
                    DirectMessage = new(settings.Preview == "hiddenDetails" ? "" : name,
                        settings.Preview == "fullContent" ? preview : "", rows.Length),
                    Activated = activationEvent == null ? null : () => Activate(id, Current, "directMessages")
                };
            } catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException or
                InvalidOperationException or KeyNotFoundException or StarBridge.HostRuntime.Settings.ApplicationPreferencesException) {
                return response;
            }
        }
        try {
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
            deadline.CancelAfter(TimeSpan.FromSeconds(1));
            await desktop!.TryPresentDetailedAsync(notice, deadline.Token).ConfigureAwait(false);
        } catch (Exception) { /* Uncertain native delivery must never replay a consumed message. */ }
        return response;
    }
}
