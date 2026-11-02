using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;
using StarBridge.HostRuntime.Settings;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    private readonly object _realtimeGate = new();
    private ScmRealtimeClient? _accountRealtime;
    private Task _accountRealtimeStopCompletion = Task.CompletedTask;
    private sealed record RealtimeObservation(long Generation, int Status, DateTimeOffset ExpiresAt);
    private RealtimeObservation? _realtimeObservation;
    private long _realtimeObservationVersion;

    private void SetRealtimeObservation(RealtimeObservation? value)
    {
        System.Diagnostics.Debug.Assert(Monitor.IsEntered(_realtimeGate));
        Volatile.Write(ref _realtimeObservation, value);
        ++_realtimeObservationVersion;
    }

    internal event Action<long>? RealtimePresenceChanged;
    internal event Action<long>? MarketplaceChanged;

    // A short-lived server observation, not a local preference or sharing grant.
    private int? RealtimePresenceStatus
    {
        get
        {
            var observation = Volatile.Read(ref _realtimeObservation);
            return !_disposed && GameplayTimeContext is not null && observation?.Generation == Generation &&
                   observation.ExpiresAt > DateTimeOffset.UtcNow ? observation.Status : null;
        }
    }

    private PresenceVisibilityBridge? _publicationVisibility;

    // The raw getter is private and is handed only to the snapshot producer.
    // Consumers receive the producer's already-observed full snapshot.
    internal PresenceVisibilityBridge ConfigurePublicationVisibility(
        Func<Func<int?>, PresenceVisibilityBridge> create)
        => _publicationVisibility = create(() => RealtimePresenceStatus);

    internal PublicationVisibilitySnapshot? ReadObservedPublicationVisibility(bool wakePublication = true)
        => _publicationVisibility?.ReadPublicationSnapshot(wakePublication: wakePublication);

    private void StopAccountRealtime()
    {
        lock (_realtimeGate)
        {
            var client = _accountRealtime;
            _accountRealtime = null;
            ObserveInboxPush(false);
            SetRealtimeObservation(null);
            client?.Stop();
            if (client is not null)
                _accountRealtimeStopCompletion = Task.WhenAll(_accountRealtimeStopCompletion, client.StopCompletion);
            _oauth.ClearNotificationTradeReferences();
        }
        // Relay realtime v1 follows the same session lifetime; the next activity
        // wait reconnects with the then-current credential.
        _friends?.RealtimeClient?.Stop();
        _ = _oauth.StopChatAsync();
    }

    private void EnsureAccountRealtime()
    {
        lock (_realtimeGate)
        {
            var session = _session;
            if (IsBusinessStartupDeferred || _disposed || _localModeSessionLoopsStopped || _reauthorizationRequired || _credentialTemporarilyUnavailable ||
                session is null || _accountRealtime is not null) return;
            var generation = Generation;
            var owner = ToContext(session);
            ScmRealtimeClient? client = null;
            bool IsCurrent() => !_disposed && Generation == generation && CurrentContext == owner &&
                                ReferenceEquals(_accountRealtime, client);
            void Observe(int? status)
            {
                bool changed;
                lock (_realtimeGate)
                {
                    if (!IsCurrent()) return;
                    changed = ReadObservedPublicationVisibility(wakePublication: false)?.Observation != status;
                    SetRealtimeObservation(status is { } value
                        ? new(generation, value, DateTimeOffset.UtcNow.AddSeconds(30)) : null);
                    // Capture while replacement is excluded. This only latches;
                    // the event below wakes persistence outside the transport lock.
                    _ = ReadObservedPublicationVisibility(wakePublication: false);
                }
                if (changed) RealtimePresenceChanged?.Invoke(generation);
            }
            client = _oauth.CreateRealtimeClient(
                (_, status) => Observe(status),
                (_, _) =>
                {
                    // Remove usable account context immediately, before awaiting
                    // credential deletion. The ticket/subject cannot revive it.
                    lock (_realtimeGate)
                    {
                        if (!IsCurrent()) return;
                        _reauthorizationRequired = true;
                        SetRealtimeObservation(null);
                        PublishSession(null, reauthorizationRequired: true);
                    }
                    _ = ClearRealtimeRevokedCredentialAsync(session);
                },
                async token =>
                {
                    await _mutationGate.WaitAsync(token).ConfigureAwait(false);
                    try
                    {
                        token.ThrowIfCancellationRequested();
                        if (!IsCurrent() || GameplayTimeContext != owner)
                            throw new OperationCanceledException(token);
                        var current = RequireSession(owner);
                        var result = await _oauth.IssueWebSocketTicketAsync(current, token).ConfigureAwait(false);
                        token.ThrowIfCancellationRequested();
                        lock (_realtimeGate)
                        {
                            if (!IsCurrent()) throw new OperationCanceledException(token);
                            RequireSameSession(current, result.ActiveSession);
                            _session = result.ActiveSession;
                        }
                        return result;
                    }
                    finally { _mutationGate.Release(); }
                }, _ =>
                {
                    Observe(null);
                    lock (_realtimeGate) { if (IsCurrent()) ObserveInboxPush(false); }
                    if (!IsCurrent()) return;
                    Interlocked.Increment(ref _marketplaceRevision);
                    MarketplaceChanged?.Invoke(generation);
                }, _ =>
                {
                    if (!IsCurrent()) return;
                    Interlocked.Increment(ref _marketplaceRevision);
                    MarketplaceChanged?.Invoke(generation);
                }, (unusedSequence, row) =>
                {
                    // A parameter named `_` would turn the discard below into an assignment.
                    lock (_realtimeGate) {
                        if (!IsCurrent()) return;
                        ObserveInboxPush(InboxPushHealthy);
                        _ = DeliverStationPushAsync(session, owner, generation, row.Clone(), IsCurrent);
                    }
                }, _ => { lock (_realtimeGate) { if (IsCurrent()) ObserveInboxPush(true); } });
            _accountRealtime = client;
            client?.Start(session);
            StartTradeChatWithRealtime(session, owner, generation);
        }
    }

    private async Task ClearRealtimeRevokedCredentialAsync(ScmOAuthSession revoked)
    {
        try
        {
            await _mutationGate.WaitAsync().ConfigureAwait(false);
            try
            {
                // Once this current socket's explicit force-logout is accepted,
                // delete that account unconditionally, including a rotated token.
                await _oauth.DeleteCredentialForRemoteLogoutAsync(revoked, CancellationToken.None).ConfigureAwait(false);
            }
            finally { _mutationGate.Release(); }
        }
        catch (Exception error) when (error is IOException or InvalidDataException or ScmLocalCredentialRetirementException or UnauthorizedAccessException or
            System.Security.Cryptography.CryptographicException or ObjectDisposedException)
        {
            // The current process stays signed out even if local storage fails.
            ScmAuthDiagnostics.Write("realtime", "credential-clear", "unavailable", "storageFailure=true");
        }
    }
}
