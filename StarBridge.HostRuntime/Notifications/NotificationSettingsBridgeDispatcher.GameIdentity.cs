namespace StarBridge.HostRuntime.Notifications;

using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using StarBridge.Core.Identity;
using StarBridge.NativeBridge;

public sealed partial class NotificationSettingsBridgeDispatcher
{
    private (long Generation, BridgeAccountContext Context)? _identityOwner;
    private readonly HashSet<string> _identityObserved = new(StringComparer.Ordinal);
    private string? _identityCurrentKey;
    private long _identityReadSerial;
    private long _identityIssueEpoch;

    private void ResetIdentityNotifications()
    {
        _identityOwner = null;
        _identityObserved.Clear();
        _identityCurrentKey = null;
        _identityReadSerial++;
        _identityIssueEpoch++;
    }

    private static string? IdentityMismatchKey(GameIdentityNotificationPolicy policy)
    {
        if (policy.State != "mismatch" ||
            !IdentityBindingPolicy.IsValidGameName(policy.AuthoritativeHandle) ||
            !IdentityBindingPolicy.IsValidGameName(policy.DetectedHandle)) return null;
        var expected = policy.AuthoritativeHandle!.Trim().ToLowerInvariant();
        var detected = policy.DetectedHandle!.Trim().ToLowerInvariant();
        if (expected == detected) return null;
        // The issue fingerprint remains Host-local. Neither handles nor this key
        // are included in desktop content, bridge events or diagnostics.
        return Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(expected + "\0" + detected)));
    }

    private async ValueTask<BridgeDispatchBatch> DispatchIdentityMismatchAsync(BridgeEnvelope request, CancellationToken token)
    {
        BridgeDispatchBatch Result(bool submitted, string reason, GameIdentityNotificationPolicy? submittedPolicy = null) => new(
            // This account-scoped receipt binds the actual submitted issue; a
            // caller's earlier policy can have changed while the read was pending.
            // No identity values are added to desktop content/events/diagnostics.
            BridgeEnvelope.Response(request, new {
                schemaVersion = 1, submitted, reason,
                authoritativeHandle = submitted ? submittedPolicy?.AuthoritativeHandle?.Trim() : null,
                detectedHandle = submitted ? submittedPolicy?.DetectedHandle?.Trim() : null
            }), []);
        try
        {
            long serial;
            lock (_gate)
            {
                ObjectDisposedException.ThrowIf(_disposed, this);
                token.ThrowIfCancellationRequested();
                BridgeEnvelopeValidator.ValidateWireShape(request);
                BridgeEnvelopeValidator.RequireCurrentVersion(request);
                if (request.SessionGeneration != generation())
                    throw new BridgeStaleGenerationException(request.SessionGeneration, generation());
                if (request.MessageType != BridgeMessageTypes.Request || request.AccountContext is not { IsComplete: true })
                    throw new ArgumentException();
                Fields(request.Payload, "schemaVersion");
                if (request.Payload.GetProperty("schemaVersion").GetInt32() != 1) throw new ArgumentException();
                if (gameIdentityPolicy == null || isGameIdentityCurrent == null) return Result(false, "unavailable");
                serial = ++_identityReadSerial;
            }

            var owner = request.AccountContext!;
            // Adapter validates the actual current account. Client state and
            // arbitrary title/text can never authorize an identity warning.
            var policy = await gameIdentityPolicy(owner, token).ConfigureAwait(false);
            DesktopNotification? notice;
            lock (_gate)
            {
                token.ThrowIfCancellationRequested();
                ObjectDisposedException.ThrowIf(_disposed, this);
                if (request.SessionGeneration != generation())
                    throw new BridgeStaleGenerationException(request.SessionGeneration, generation());
                if (serial != _identityReadSerial) return new(BridgeEnvelope.CancelledResponse(request), []);
                var scope = (request.SessionGeneration, owner);
                if (_identityOwner != scope)
                {
                    _identityOwner = scope;
                    _identityObserved.Clear();
                    _identityCurrentKey = null;
                    _identityIssueEpoch++;
                }
                var key = IdentityMismatchKey(policy);
                if (_identityCurrentKey != key) _identityIssueEpoch++;
                _identityCurrentKey = key;
                if (key is null) return Result(false, "notMismatch");
                // Observe before preference/foreground/system gates. A suppressed
                // or uncertain delivery is never replayed by the polling loop.
                if (_identityObserved.Contains(key) || _identityObserved.Count >= 256)
                    return Result(false, "unchanged");
                _identityObserved.Add(key);
                var settings = Read();
                if (!settings.WindowsEnabled) return Result(false, "disabled");
                if (desktop is null) return Result(false, "unavailable");
                if (!(canNotifyGameIdentity?.Invoke() ?? false)) return Result(false, "appActiveOrUnknown");
                var revision = _reminderEpoch;
                var issueEpoch = _identityIssueEpoch;
                var started = Stopwatch.GetTimestamp();
                bool Current()
                {
                    lock (_gate)
                    {
                        if (_disposed || request.SessionGeneration != generation() || _identityOwner != scope ||
                            _identityCurrentKey != key || _reminderEpoch != revision || _identityIssueEpoch != issueEpoch ||
                            Stopwatch.GetElapsedTime(started) >= TimeSpan.FromSeconds(30)) return false;
                        // Native presentation and queue ticks cannot await a bridge
                        // request. The injected Host snapshot is synchronous/no-I/O,
                        // so recovery revokes the card even without another UI poll.
                        try { return isGameIdentityCurrent(owner, policy); }
                        catch { return false; }
                    }
                }
                async Task<bool> Revalidate(CancellationToken cancellation)
                {
                    long validationSerial;
                    lock (_gate) {
                        if (!Current()) return false;
                        validationSerial = _identityReadSerial;
                    }
                    var latest = await gameIdentityPolicy(owner, cancellation).ConfigureAwait(false);
                    lock (_gate)
                    {
                        if (!Current() || validationSerial != _identityReadSerial) return false;
                        if (IdentityMismatchKey(latest) == key) return true;
                        _identityCurrentKey = null;
                        _identityIssueEpoch++;
                        return false;
                    }
                }
                var id = Guid.NewGuid();
                notice = CreateDesktop(id, false, 0, 0, settings, Current) with
                {
                    GameIdentityMismatch = true,
                    Activated = activationEvent == null ? null : () => Activate(id, Current, "gameIdentity", Revalidate)
                };
            }
            if (!notice.IsCurrent()) return Result(false, "expired");
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
            deadline.CancelAfter(TimeSpan.FromSeconds(1));
            var output = await desktop!.TryPresentDetailedAsync(notice, deadline.Token).ConfigureAwait(false);
            return Result(output.Submitted, output.Submitted ? "submitted" : output.Reason, policy);
        }
        catch (OperationCanceledException) { return new(BridgeEnvelope.CancelledResponse(request), []); }
        catch (BridgeProtocolException e) { return new(BridgeEnvelope.ErrorResponse(request, new(e.Code, "Identity notification rejected.")), []); }
        catch { return new(BridgeEnvelope.ErrorResponse(request, new("gameIdentity.notification_unavailable", "Identity notification unavailable.")), []); }
    }
}
