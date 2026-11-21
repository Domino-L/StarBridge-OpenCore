using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Hangar;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

/// <summary>The account hangar copy goes only to the signed-in SCM principal's own archive endpoint.</summary>
public interface IHangarArchiveRemote
{
    /// <summary>SCM sign-in only; legacy (non-SCM) accounts never upload or restore.</summary>
    bool Supports(BridgeAccountContext owner, long generation);
    Task<HangarArchiveReadResult> ReadArchiveAsync(BridgeAccountContext owner, long generation, CancellationToken token);
    Task<HangarArchiveWriteResult> WriteArchiveAsync(BridgeAccountContext owner, long generation, long expectedRevision,
        byte[] archiveJson, CancellationToken token);
    Task<HangarArchiveWriteResult> DeleteArchiveAsync(BridgeAccountContext owner, long generation, CancellationToken token);
}

internal sealed partial class ScmAccountBridgeHost : IHangarArchiveRemote
{
    public bool Supports(BridgeAccountContext owner, long generation) =>
        !_disposed && generation == Generation && _session is not null && _legacySession is null &&
        // Same precondition as the other concurrent resource lanes (restored, not deferred, not local mode).
        SupportsConcurrentResourceReads &&
        HangarIdentity is { } identity && identity.Account == owner && identity.Generation == generation;

    public Task<HangarArchiveReadResult> ReadArchiveAsync(BridgeAccountContext owner, long generation, CancellationToken token) =>
        WithHangarArchiveSession(owner, generation, (session, ready, ct) => _oauth.ReadHangarArchiveAsync(session, ct, ready), token);

    public Task<HangarArchiveWriteResult> WriteArchiveAsync(BridgeAccountContext owner, long generation, long expectedRevision,
        byte[] archiveJson, CancellationToken token) =>
        WithHangarArchiveSession(owner, generation,
            (session, ready, ct) => _oauth.WriteHangarArchiveAsync(session, expectedRevision, archiveJson, ct, ready), token);

    public Task<HangarArchiveWriteResult> DeleteArchiveAsync(BridgeAccountContext owner, long generation, CancellationToken token) =>
        WithHangarArchiveSession(owner, generation, (session, ready, ct) => _oauth.DeleteHangarArchiveAsync(session, ct, ready), token);

    private async Task<T> WithHangarArchiveSession<T>(BridgeAccountContext owner, long generation,
        Func<ScmOAuthSession, Action<ScmOAuthSession>, CancellationToken, Task<(T Result, ScmOAuthSession ActiveSession)>> send,
        CancellationToken token)
    {
        // Background copy of local data: a shared admission (account changes still wait for it, other
        // shared readers do not) with one bounded budget for the whole request, response body included,
        // so a stalled network can never hold sign-out or an account switch for long.
        using var budget = CancellationTokenSource.CreateLinkedTokenSource(token);
        budget.CancelAfter(HangarArchiveRequestBudget);
        token = budget.Token;
        await using var admission = await _mutationGate.EnterSharedAsync(token).ConfigureAwait(false);
        {
            void Current()
            {
                token.ThrowIfCancellationRequested();
                if (!Supports(owner, generation)) throw new AccountBridgeHostException("hangar.account_changed");
            }
            Current();
            var session = RequireSession(owner);
            var originalContext = CurrentContext;
            void Adopt(ScmOAuthSession active)
            {
                // Same adoption rules as the achievement lane: a refresh committed by OAuth is adopted before
                // resource IO; anything that is not the same owner's session or its refresh stops the request.
                if (_disposed || generation != Generation || CurrentContext != originalContext ||
                    _session is null || _legacySession is not null || _localModeSessionLoopsStopped ||
                    active.AuthoritativeGameIdentity != session.AuthoritativeGameIdentity ||
                    !_oauth.IsInstalledFirstUseSessionOrRefreshOf(session, active))
                    throw new AccountBridgeHostException("hangar.account_changed");
                RequireSameSession(session, active);
                RequireSameSession(session, RequireSession(owner));
                CommitSharingSession(new RelayRequestSession(session), new RelayRequestSession(active));
            }
            var result = await send(session, Adopt, token).ConfigureAwait(false);
            Adopt(result.ActiveSession);
            Current();
            return result.Result;
        }
    }

    // Short on purpose: sign-out or an account switch waits for at most one of these requests.
    internal static TimeSpan HangarArchiveRequestBudget { get; set; } = TimeSpan.FromSeconds(10);
}
