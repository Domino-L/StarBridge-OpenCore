using StarBridge.Core.Events;
using StarBridge.HostRuntime.Privacy;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal interface IEventSharingRemote
{
    Task<EventSharingRemoteSnapshot> ReadEventsAsync(BridgeAccountContext owner, long generation, CancellationToken token);
    Task<EventSharingRemoteSnapshot> SaveEventsAsync(BridgeAccountContext owner, long generation, long expectedRevision,
        string operationId, bool publicationEnabled, SharedEventPreferences settings, CancellationToken token);
}

internal interface IEventFeedRemote
{
    Task<EventFeedReceipt> WriteEventFeedAsync(BridgeAccountContext owner, long generation, string action,
        long revision, string? session, long sequence, SharedActivityEvent[] events, CancellationToken token);
}

internal sealed partial class ScmAccountBridgeHost : IEventSharingRemote, IEventFeedRemote, ISharedActivityReader
{
    private CancellationTokenSource? _eventPrivacyRead;
    private readonly SemaphoreSlim _eventWriteLane = new(1, 1);
    private readonly SemaphoreSlim _friendWriteLane = new(1, 1);
    public Task<SharedActivityRead> ReadActivityAsync(BridgeAccountContext owner, long generation, string scope, string id, CancellationToken token) =>
        WithEventSessionAsync(owner, generation, false, (writer, bearer, _, ct) => writer.ReadEventFeedAsync(bearer, scope, id, ct), token, yieldableRead: true);
    public Task<EventFeedReceipt> WriteEventFeedAsync(BridgeAccountContext owner, long generation, string action,
        long revision, string? session, long sequence, SharedActivityEvent[] events, CancellationToken token) =>
        WithEventSessionAsync(owner, generation, action != "stop",
            (writer, bearer, current, ct) => writer.WriteEventFeedAsync(bearer, action, revision, session, sequence, events, current, ct), token,
            positivePublication: action != "stop");
    public Task<EventSharingRemoteSnapshot> ReadEventsAsync(BridgeAccountContext owner, long generation, CancellationToken token) =>
        WithEventSessionAsync(owner, generation, false,
            (writer, bearer, _, ct) => writer.ReadEventsAsync(bearer, ct), token, yieldableRead: true);

    public Task<EventSharingRemoteSnapshot> SaveEventsAsync(BridgeAccountContext owner, long generation, long expectedRevision,
        string operationId, bool publicationEnabled, SharedEventPreferences settings, CancellationToken token) =>
        WithEventSessionAsync(owner, generation, publicationEnabled,
            (writer, bearer, current, ct) => writer.SaveEventsAsync(bearer, expectedRevision, operationId,
                publicationEnabled, settings, current, ct), token);

    private async Task<T> WithEventSessionAsync<T>(BridgeAccountContext owner, long generation,
        bool publishing, Func<PrivacyRelayWriter, string, Action, CancellationToken, Task<T>> send,
        CancellationToken token, bool yieldableRead = false, bool friendLane = false, bool positivePublication = false)
    {
        var lane = friendLane ? _friendWriteLane : _eventWriteLane;
        if (!yieldableRead) await lane.WaitAsync(token).ConfigureAwait(false);
        IAsyncDisposable admission;
        try { admission = await _mutationGate.EnterSharedAsync(token).ConfigureAwait(false); }
        catch { if (!yieldableRead) lane.Release(); throw; }
        var callerToken = token;
        using var readCancellation = yieldableRead ? CancellationTokenSource.CreateLinkedTokenSource(token) : null;
        if (readCancellation is not null)
        {
            Interlocked.Exchange(ref _eventPrivacyRead, readCancellation);
            token = readCancellation.Token;
        }
        var gateWatch = System.Diagnostics.Stopwatch.StartNew();
        try
        {
            void EnsureCurrent()
            {
                if (_disposed || Generation != generation || GameplayTimeContext != owner)
                    throw new AccountBridgeHostException("events.account_changed");
                if (positivePublication) RequireSharedPublication(owner, generation);
            }
            EnsureCurrent();
            token.ThrowIfCancellationRequested();
            var writer = _privacyWriter ?? throw new AccountBridgeHostException("events.unavailable");
            var session = RequireRelaySession(owner);
            if (publishing && !(await GetGameIdentityPolicyAsync(owner, token)).SensitiveWritesAllowed)
                throw new AccountBridgeHostException("events.identity_required");
            EnsureCurrent();
            var result = await SendRelayRequestAsync(session, async (active, ct) =>
            {
                using var positiveLease = positivePublication && _sharedPublicationAdmission is { } positiveAdmission
                    ? await positiveAdmission.EnterAsync(ct).ConfigureAwait(false) : null;
                EnsureCurrent();
                // Priority cancellation applies only to the read request, not
                // the surrounding OAuth refresh/credential rotation.
                return await send(writer, active.AccessToken, EnsureCurrent, readCancellation?.Token ?? ct).ConfigureAwait(false);
            }, callerToken).ConfigureAwait(false);
            EnsureCurrent();
            RequireSameRelaySession(RequireRelaySession(owner), result.ActiveSession);
            CommitSharingSession(session, result.ActiveSession);
            return result.Result;
        }
        catch (OperationCanceledException) when (readCancellation?.IsCancellationRequested == true && !callerToken.IsCancellationRequested)
        { throw new AccountBridgeHostException("events.temporarily_unavailable", retryable: true); }
        finally
        {
            if (readCancellation is not null) Interlocked.CompareExchange(ref _eventPrivacyRead, null, readCancellation);
            try { PrivacyPublicationDiagnostic?.Invoke(yieldableRead ? "account-gate-event-read" : "account-gate-event-write", "ok", null, gateWatch.ElapsedMilliseconds); }
            catch { /* [DEBUG-community-read] Diagnostics must not affect release. */ }
            await admission.DisposeAsync().ConfigureAwait(false);
            if (!yieldableRead) lane.Release();
        }
    }
}
