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
    public Task<SharedActivityRead> ReadActivityAsync(BridgeAccountContext owner, long generation, string scope, string id, CancellationToken token) =>
        WithEventSessionAsync(owner, generation, false, (writer, bearer, _, ct) => writer.ReadEventFeedAsync(bearer, scope, id, ct), token);
    public Task<EventFeedReceipt> WriteEventFeedAsync(BridgeAccountContext owner, long generation, string action,
        long revision, string? session, long sequence, SharedActivityEvent[] events, CancellationToken token) =>
        WithEventSessionAsync(owner, generation, action != "stop",
            (writer, bearer, current, ct) => writer.WriteEventFeedAsync(bearer, action, revision, session, sequence, events, current, ct), token);
    public Task<EventSharingRemoteSnapshot> ReadEventsAsync(BridgeAccountContext owner, long generation, CancellationToken token) =>
        WithEventSessionAsync(owner, generation, false,
            (writer, bearer, _, ct) => writer.ReadEventsAsync(bearer, ct), token);

    public Task<EventSharingRemoteSnapshot> SaveEventsAsync(BridgeAccountContext owner, long generation, long expectedRevision,
        string operationId, bool publicationEnabled, SharedEventPreferences settings, CancellationToken token) =>
        WithEventSessionAsync(owner, generation, publicationEnabled,
            (writer, bearer, current, ct) => writer.SaveEventsAsync(bearer, expectedRevision, operationId,
                publicationEnabled, settings, current, ct), token);

    private async Task<T> WithEventSessionAsync<T>(BridgeAccountContext owner, long generation,
        bool publishing, Func<PrivacyRelayWriter, string, Action, CancellationToken, Task<T>> send,
        CancellationToken token)
    {
        await _mutationGate.WaitAsync(token).ConfigureAwait(false);
        try
        {
            void EnsureCurrent()
            {
                if (_disposed || Generation != generation || GameplayTimeContext != owner)
                    throw new AccountBridgeHostException("events.account_changed");
            }
            EnsureCurrent();
            var writer = _privacyWriter ?? throw new AccountBridgeHostException("events.unavailable");
            var session = RequireRelaySession(owner);
            if (publishing && !(await GetGameIdentityPolicyAsync(owner, token)).SensitiveWritesAllowed)
                throw new AccountBridgeHostException("events.identity_required");
            EnsureCurrent();
            var result = await SendRelayRequestAsync(session, (active, ct) =>
            {
                EnsureCurrent();
                return send(writer, active.AccessToken, EnsureCurrent, ct);
            }, token).ConfigureAwait(false);
            EnsureCurrent();
            RequireSameRelaySession(RequireRelaySession(owner), result.ActiveSession);
            _session = result.ActiveSession.Scm;
            return result.Result;
        }
        finally { _mutationGate.Release(); }
    }
}
