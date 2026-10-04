namespace StarBridge.HostRuntime.Notifications;

using StarBridge.NativeBridge;
using System.Text.Json;
using StarBridge.HostRuntime.Overlay;

public sealed partial class NotificationSettingsBridgeDispatcher
{
    private long _directEpoch;

    private async ValueTask<BridgeEnvelope> ObserveDirectAsync(BridgeEnvelope request, BridgeEnvelope response, CancellationToken token)
    {
        string? trace = null;
        void RecordDesktop(NotificationDeliveryStage stage, string? result = null) =>
            _delivery.Record(NotificationDeliveryChannel.Desktop, stage, trace, desktop?.DiagnosticTransport, result);
        DesktopNotification? notice = null;
        InformationOverlayReminder? overlayNotice = null;
        Action? publishSocial = null;
        Func<bool>? stillCurrent = null;
        lock (_gate) {
            if (_disposed || token.IsCancellationRequested || request.SessionGeneration != generation()) return response;
            // Consume the sequence before any preference, foreground or system gate.
            if (!_direct.Observe(request, response, generation())) {
                if (_direct.LastStage is NotificationDeliveryStage.InvalidResponse or NotificationDeliveryStage.ContractUnavailable or
                    NotificationDeliveryStage.BaselineEstablished or NotificationDeliveryStage.ContinuityReset)
                    Interlocked.Increment(ref _directEpoch);
                if (!request.Payload.TryGetProperty("targetRef", out _)) RecordDesktop(_direct.LastStage);
                return response;
            }
            trace = NotificationDeliveryJournal.TraceFor(request);
            RecordDesktop(NotificationDeliveryStage.FreshEvent);
            try {
                var settings = Read();
                if (request.AccountContext is null || !NotificationSourcePolicy.Allows(
                    _policies.Read(request.AccountContext).For("directMessages"), NotificationEventKind.DirectMessage)) {
                    RecordDesktop(NotificationDeliveryStage.SourceMuted); return response;
                }
                var keys = _direct.FreshKeys.ToHashSet(StringComparer.Ordinal);
                var rows = response.Payload.GetProperty("conversations").EnumerateArray()
                    .Where(row => keys.Contains(row.GetProperty("conversationKey").GetString()!)).ToArray();
                var latest = rows.OrderByDescending(value => value.GetProperty("lastMessageAt").GetDateTimeOffset()).FirstOrDefault();
                string? socialSender = null, socialPreview = null;
                if (rows.Length == 1 && latest.ValueKind == JsonValueKind.Object) {
                    socialSender = latest.TryGetProperty("callsign", out var sender) && sender.ValueKind == JsonValueKind.String
                        ? sender.GetString() : null;
                    socialPreview = latest.TryGetProperty("preview", out var content) && content.ValueKind == JsonValueKind.String
                        ? content.GetString() : null;
                    if (socialSender?.Length > 512 || socialPreview?.Length > 4096) {
                        socialSender = null; socialPreview = null;
                    }
                }
                var desktopReason = DesktopSuppressionReason();
                var freshKeys = _direct.FreshKeys.ToArray();
                publishSocial = () => PublishSocial("direct", freshKeys.Length, settings, request.SessionGeneration,
                    desktopReason.Length == 0, freshKeys, socialSender, socialPreview);
                if (rows.Length == 0) { RecordDesktop(NotificationDeliveryStage.Failed); return response; }
                var row = latest;
                var name = row.GetProperty("callsign").GetString() ?? "";
                var preview = row.GetProperty("preview").GetString() ?? "";
                if (name.Length > 512 || preview.Length > 4096) { RecordDesktop(NotificationDeliveryStage.Failed); return response; }
                var id = Guid.NewGuid();
                var epoch = Interlocked.Read(ref _directEpoch);
                var started = System.Diagnostics.Stopwatch.GetTimestamp();
                bool Current() => !_disposed && epoch == Interlocked.Read(ref _directEpoch) &&
                    request.SessionGeneration == generation() && System.Diagnostics.Stopwatch.GetElapsedTime(started) < TimeSpan.FromSeconds(30) &&
                    DirectSourceStillAllowed(request.AccountContext);
                stillCurrent = Current;
                if (settings.OverlayEnabled && overlay != null)
                    overlayNotice = new(id, 0, 0, settings.Preview, Current) {
                        DirectMessage = new(settings.Preview == "hiddenDetails" || rows.Length != 1 ? "" : name,
                            settings.Preview == "fullContent" && rows.Length == 1 ? preview : "", rows.Length)
                    };
                if (!settings.WindowsEnabled || !settings.DirectMessageWindowsEnabled || desktop == null)
                    RecordDesktop(NotificationDeliveryStage.ChannelDisabled);
                else if (desktopReason.Length != 0)
                    RecordDesktop(NotificationDeliveryStage.EnvironmentSuppressed, desktopReason);
                else
                notice = CreateDesktop(id, false, 0, 0, settings, Current) with {
                    Diagnostic = outcome => RecordDesktop(NotificationDeliveryStage.NativeLifecycle, outcome),
                    DirectMessage = new(settings.Preview == "hiddenDetails" ? "" : name,
                        settings.Preview == "fullContent" ? preview : "", rows.Length,
                        settings.Preview != "hiddenDetails" && rows.Length == 1 &&
                            row.TryGetProperty("avatarImageData", out var avatar) && avatar.ValueKind == JsonValueKind.String
                            ? PartyRooms.RoomAvatarProjection.Normalize(avatar.GetString(), 512 * 1024) : null),
                    Activated = activationEvent == null ? null : () => Activate(id, Current, "directMessages")
                };
            } catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException or
                InvalidOperationException or KeyNotFoundException or StarBridge.HostRuntime.Settings.ApplicationPreferencesException) {
                RecordDesktop(NotificationDeliveryStage.Failed);
                return response;
            }
        }
        if (overlayNotice != null) {
            using var overlayDeadline = CancellationTokenSource.CreateLinkedTokenSource(token);
            overlayDeadline.CancelAfter(TimeSpan.FromSeconds(1));
            try {
                if (overlayNotice.IsCurrent() && await overlay!.TryPresentAsync(overlayNotice, overlayDeadline.Token).ConfigureAwait(false))
                    return response;
            } catch (Exception) {
                // A timed-out submission may already be visible. Never duplicate or replay it.
                return response;
            }
        }
        if (token.IsCancellationRequested || stillCurrent?.Invoke() != true) return response;
        publishSocial?.Invoke();
        if (notice == null || !notice.IsCurrent()) return response;
        try {
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
            deadline.CancelAfter(TimeSpan.FromSeconds(1));
            var result = await desktop!.TryPresentDetailedAsync(notice, deadline.Token).ConfigureAwait(false);
            RecordDesktop(result.Submitted ? NotificationDeliveryStage.NativeAccepted : NotificationDeliveryStage.NativeRejected,
                result.DiagnosticOutcome ?? result.Reason);
        } catch (Exception) {
            RecordDesktop(NotificationDeliveryStage.Failed);
            // Uncertain native delivery must never replay a consumed message.
        }
        return response;
    }

    private bool DirectSourceStillAllowed(BridgeAccountContext owner)
    {
        try { return NotificationSourcePolicy.Allows(_policies.Read(owner).For("directMessages"), NotificationEventKind.DirectMessage); }
        catch { return false; }
    }

    private void PublishSocial(string kind, int count, LocalNotificationSettings settings, long sessionGeneration,
        bool desktopEligible,
        IReadOnlyList<string>? conversationKeys = null, string? senderName = null, string? messagePreview = null)
    {
        if (settings.InAppEnabled && socialEvent != null && !desktopEligible)
            EventReady?.Invoke(socialEvent(sessionGeneration, new {
                schemaVersion = 1, kind, count, revision = settings.Revision, conversationKeys,
                senderName = settings.Preview == "hiddenDetails" ? null : senderName,
                messagePreview = settings.Preview == "fullContent" ? messagePreview : null
            }));
    }

    private async ValueTask<BridgeEnvelope> ObserveFriendsAsync(BridgeEnvelope request, BridgeEnvelope response, CancellationToken token)
    {
        DesktopNotification? notice = null;
        lock (_gate) {
            if (_disposed || token.IsCancellationRequested) return response;
            var count = _friends.Observe(request, response, generation());
            if (count == 0 || request.AccountContext is null) return response;
            try {
                if (!NotificationSourcePolicy.Allows(_policies.Read(request.AccountContext).For("friends"), NotificationEventKind.JoinRequest)) return response;
                var settings = Read();
                var desktopReason = DesktopSuppressionReason();
                PublishSocial("friend", count, settings, request.SessionGeneration, desktopReason.Length == 0);
                if (!settings.WindowsEnabled || desktop == null || desktopReason.Length != 0) return response;
                var epoch = _directEpoch;
                var started = System.Diagnostics.Stopwatch.GetTimestamp();
                bool Current() => !_disposed && epoch == _directEpoch && request.SessionGeneration == generation() &&
                    System.Diagnostics.Stopwatch.GetElapsedTime(started) < TimeSpan.FromSeconds(30);
                var id = Guid.NewGuid();
                notice = CreateDesktop(id, false, 0, 0, settings, Current) with {
                    FriendRequests = count,
                    Activated = activationEvent == null ? null : () => Activate(id, Current, "notificationInbox")
                };
            } catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException or InvalidOperationException or Settings.ApplicationPreferencesException) { return response; }
        }
        try {
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
            deadline.CancelAfter(TimeSpan.FromSeconds(1));
            await desktop!.TryPresentDetailedAsync(notice, deadline.Token);
        } catch (Exception) { }
        return response;
    }
}
