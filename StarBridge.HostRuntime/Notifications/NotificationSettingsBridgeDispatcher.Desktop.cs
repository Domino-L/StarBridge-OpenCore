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

    private (string Id, Func<bool> Current, long Started, string Destination)? _activation;
    private Guid? _activatedDesktop;
    private void Activate(Guid id, Func<bool> current, string destination = "roomReminders") {
        lock (_gate) {
            if (_disposed || !current() || activationEvent == null) return;
            var key = id.ToString("N");
            if (_activatedDesktop == id) return;
            _activatedDesktop = id;
            _activation = (key, current, System.Diagnostics.Stopwatch.GetTimestamp(), destination);
            EventReady?.Invoke(activationEvent(generation(), new { schemaVersion = 1, activationId = key }));
        }
    }

    private BridgeDispatchBatch ConsumeActivation(BridgeEnvelope request) {
        lock (_gate) {
            try {
                ObjectDisposedException.ThrowIf(_disposed, this);
                BridgeEnvelopeValidator.ValidateWireShape(request); BridgeEnvelopeValidator.RequireCurrentVersion(request);
                if (request.SessionGeneration != generation()) throw new BridgeStaleGenerationException(request.SessionGeneration, generation());
                if (request.MessageType != BridgeMessageTypes.Request || request.AccountContext != null) throw new ArgumentException();
                Fields(request.Payload, "schemaVersion", "activationId");
                if (request.Payload.GetProperty("schemaVersion").GetInt32() != 1) throw new ArgumentException();
                var id = request.Payload.GetProperty("activationId").GetString();
                var valid = _activation is { } active && active.Id == id && active.Current() &&
                    System.Diagnostics.Stopwatch.GetElapsedTime(active.Started) < TimeSpan.FromSeconds(30);
                var destination = valid ? _activation?.Destination : null;
                if (valid) _activation = null;
                return new(BridgeEnvelope.Response(request, new { schemaVersion = 1, destination }, preserveRequestAccountContext: false), []);
            } catch (BridgeProtocolException e) { return new(BridgeEnvelope.ErrorResponse(request, new(e.Code, "Activation rejected.")), []); }
            catch { return new(BridgeEnvelope.ErrorResponse(request, new("notificationSettings.activation_unavailable", "Activation unavailable.")), []); }
        }
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
