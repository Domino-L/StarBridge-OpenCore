namespace StarBridge.HostRuntime.Notifications;

using StarBridge.NativeBridge;
using StarBridge.HostRuntime.Settings;
using System.Text.Json;

public sealed partial class NotificationSettingsBridgeDispatcher
{
    private DesktopNotification? _desktopTicket;
    private Guid? _submittedDesktop;
    private long _lastDesktopTest;

    private DesktopNotification CreateDesktop(Guid id, bool test, int invitations, int applications,
        LocalNotificationSettings settings, Func<bool> current)
    {
        // Read the existing atomic preference store; do not create a second theme/locale store.
        var presentation = new ApplicationPreferencesStore(dataRoot).Load().Snapshot;
        return new(id, test, invitations, applications, settings.Preview, settings.Position,
            presentation.LocaleOverride ?? System.Globalization.CultureInfo.CurrentUICulture.Name,
            presentation.AppearanceMode, current, presentation.MotionPreference == "reduce",
            test || activationEvent == null ? null : () => Activate(id, current));
    }

    private readonly TimeProvider _activationTime = time ?? TimeProvider.System;
    private (string Id, Func<bool> Current, long Started, long Generation, string Destination,
        Func<CancellationToken, Task<bool>>? Revalidate, string? Reference)? _activation;
    private Guid? _activatedDesktop;
    private void Activate(Guid id, Func<bool> current, string destination = "roomReminders",
        Func<CancellationToken, Task<bool>>? revalidate = null, string? reference = null) {
        lock (_gate) {
            if (_disposed || !current() || activationEvent == null) return;
            var key = id.ToString("N");
            if (_activatedDesktop == id) return;
            BridgeEnvelope envelope;
            var sessionGeneration = generation();
            try { envelope = activationEvent(sessionGeneration, new { schemaVersion = 1, activationId = key }); }
            catch (OperationCanceledException) { return; } // No intent was created by the retired Native owner.
            _activatedDesktop = id;
            // Routing data stays in this one in-memory intent, never in the click event.
            var opaqueRef = destination is "trade" or "tradeChat" && reference is { Length: 32 } &&
                reference.All(char.IsAsciiHexDigit) ? reference : null;
            _activation = (key, current, _activationTime.GetTimestamp(), sessionGeneration, destination, revalidate, opaqueRef);
            EventReady?.Invoke(envelope);
        }
    }

    private async ValueTask<BridgeDispatchBatch> ConsumeActivationAsync(BridgeEnvelope request, CancellationToken token) {
        try {
            string? destination = null;
            string? reference = null;
            Func<bool>? current = null;
            Func<CancellationToken, Task<bool>>? revalidate = null;
            lock (_gate) {
                ObjectDisposedException.ThrowIf(_disposed, this);
                token.ThrowIfCancellationRequested();
                BridgeEnvelopeValidator.ValidateWireShape(request); BridgeEnvelopeValidator.RequireCurrentVersion(request);
                if (request.SessionGeneration != generation()) throw new BridgeStaleGenerationException(request.SessionGeneration, generation());
                if (request.MessageType != BridgeMessageTypes.Request || request.AccountContext != null) throw new ArgumentException();
                Fields(request.Payload, "schemaVersion", "activationId");
                if (request.Payload.GetProperty("schemaVersion").GetInt32() != 1) throw new ArgumentException();
                var id = request.Payload.GetProperty("activationId").GetString();
                if (_activation is { } active && active.Id == id) {
                    // Consume before awaiting the authoritative policy. Concurrent
                    // clicks cannot race into duplicate navigation/confirmation.
                    // Expired or retired intents also release their reference here.
                    _activation = null;
                    if (active.Generation == request.SessionGeneration && active.Current() &&
                        _activationTime.GetElapsedTime(active.Started) < TimeSpan.FromSeconds(30)) {
                        destination = active.Destination;
                        current = active.Current;
                        revalidate = active.Revalidate;
                        reference = active.Reference;
                    }
                }
            }
            if (revalidate != null && !await revalidate(token).ConfigureAwait(false)) destination = null;
            lock (_gate) {
                if (destination != null && (_disposed || request.SessionGeneration != generation() || current?.Invoke() != true))
                    destination = null;
            }
            return new(BridgeEnvelope.Response(request, new { schemaVersion = 1, destination,
                @ref = destination is "trade" or "tradeChat" ? reference : null }, preserveRequestAccountContext: false), []);
        }
        catch (OperationCanceledException) { return new(BridgeEnvelope.CancelledResponse(request), []); }
        catch (BridgeProtocolException e) { return new(BridgeEnvelope.ErrorResponse(request, new(e.Code, "Activation rejected.")), []); }
        catch { return new(BridgeEnvelope.ErrorResponse(request, new("notificationSettings.activation_unavailable", "Activation unavailable.")), []); }
    }

    private async ValueTask<BridgeDispatchBatch> DispatchDesktopAsync(BridgeEnvelope request, CancellationToken token)
    {
        BridgeEnvelope response;
        try
        {
            DesktopNotification? notice = null;
            var reason = "unavailable";
            lock (_gate)
            {
                ObjectDisposedException.ThrowIf(_disposed, this);
                token.ThrowIfCancellationRequested();
                BridgeEnvelopeValidator.ValidateWireShape(request);
                BridgeEnvelopeValidator.RequireCurrentVersion(request);
                if (request.SessionGeneration != generation()) throw new BridgeStaleGenerationException(request.SessionGeneration, generation());
                if (request.AccountContext != null || request.MessageType != BridgeMessageTypes.Request) throw new ArgumentException();
                var test = request.Name == "notificationSettings.testDesktop";
                Fields(request.Payload, request.Name == "notificationSettings.presentDesktop" ? ["schemaVersion", "ticket"] : ["schemaVersion"]);
                if (request.Payload.GetProperty("schemaVersion").GetInt32() != 1) throw new ArgumentException();
                if (request.Name == "notificationSettings.clearDesktop") desktop?.ClearMessages();
                else
                {
                    var settings = Read();
                    if (!settings.WindowsEnabled) reason = "disabled";
                    if (desktop != null && settings.WindowsEnabled)
                    {
                        if (test)
                        {
                            var now = System.Diagnostics.Stopwatch.GetTimestamp();
                            if (_lastDesktopTest == 0 || System.Diagnostics.Stopwatch.GetElapsedTime(_lastDesktopTest, now) >= TimeSpan.FromSeconds(2))
                            {
                                _lastDesktopTest = now;
                                var epoch = Interlocked.Read(ref _reminderEpoch);
                                notice = CreateDesktop(Guid.NewGuid(), true, 0, 0, settings,
                                    () => epoch == Interlocked.Read(ref _reminderEpoch) && request.SessionGeneration == generation() &&
                                        System.Diagnostics.Stopwatch.GetElapsedTime(now) < TimeSpan.FromSeconds(60));
                            }
                            else reason = "throttled";
                        }
                        else if (Guid.TryParseExact(request.Payload.GetProperty("ticket").GetString(), "N", out var id) &&
                            _desktopTicket is { } ticket && ticket.Id == id && _submittedDesktop != id &&
                            ticket.IsCurrent() && (canNotifyDesktop?.Invoke() ?? false))
                        {
                            // Consume before awaiting native output. Uncertain delivery must not retry.
                            _submittedDesktop = id;
                            notice = ticket;
                        }
                    }
                }
            }
            var submitted = false;
            if (notice != null)
            {
                using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
                deadline.CancelAfter(TimeSpan.FromSeconds(1));
                var result = await desktop!.TryPresentDetailedAsync(notice, deadline.Token).ConfigureAwait(false);
                submitted = result.Submitted;
                reason = result.Reason;
            }
            response = BridgeEnvelope.Response(request, new { schemaVersion = 1, submitted, reason = submitted ? "submitted" : reason }, preserveRequestAccountContext: false);
        }
        catch (OperationCanceledException) { response = BridgeEnvelope.CancelledResponse(request); }
        catch (BridgeProtocolException e) { response = BridgeEnvelope.ErrorResponse(request, new(e.Code, "Desktop request rejected.")); }
        catch (Exception) { response = BridgeEnvelope.ErrorResponse(request, new("notificationSettings.desktop_unavailable", "Desktop reminder unavailable.")); }
        return new(response, []);
    }
}
