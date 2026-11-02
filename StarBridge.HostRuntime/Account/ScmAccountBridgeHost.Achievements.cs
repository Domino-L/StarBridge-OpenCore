using StarBridge.HostRuntime.Achievements;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost : IAchievementRemote
{
    public async Task TriggerScmAchievementsAsync(BridgeAccountContext owner, CancellationToken token) =>
        _ = await WithAchievementSession(owner, Generation, (session, ready) => _oauth.TriggerScmAchievementsAsync(session, token, ready), token);
    public Task<ScmAchievementCatalog> ReadScmAchievementsAsync(BridgeAccountContext owner, CancellationToken token) =>
        WithAchievementSession(owner, Generation, (session, ready) => _oauth.ReadScmAchievementsAsync(session, token, ready), token);
    public Task<AchievementSnapshot> ReadAchievementsAsync(BridgeAccountContext owner, long generation, CancellationToken token) =>
        WithAchievementSession(owner, generation, (session, ready) => _oauth.ReadAchievementsAsync(session, token, ready), token);
    public Task<AchievementReceipt> ObserveFirstEntryAsync(BridgeAccountContext owner, long generation, FirstEntryObservation observation, CancellationToken token) =>
        WithAchievementSession(owner, generation, (session, ready) => _oauth.ObserveFirstEntryAsync(session, observation, token, ready), token);
    public Task<CityAchievementReceipt> ObserveCityAsync(BridgeAccountContext owner, long generation, CityObservation observation, CancellationToken token) =>
        WithAchievementSession(owner, generation, (session, ready) => _oauth.ObserveCityAsync(session, observation, token, ready), token);
    public Task<HangarAchievementReceipt> ObserveHangarAsync(BridgeAccountContext owner, long generation, HangarAchievementObservation observation, CancellationToken token) =>
        WithAchievementSession(owner, generation, (session, ready) => _oauth.ObserveHangarAchievementsAsync(session, observation, token, ready), token);

    private async Task<T> WithAchievementSession<T>(BridgeAccountContext owner, long generation,
        Func<Auth.ScmOAuthSession, Action<Auth.ScmOAuthSession>, Task<(T Result, Auth.ScmOAuthSession ActiveSession)>> send, CancellationToken token)
    {
        await _mutationGate.WaitAsync(token).ConfigureAwait(false);
        try
        {
            void Current() {
                token.ThrowIfCancellationRequested();
                if (_disposed || generation != Generation || GameplayTimeContext != owner || _session is null)
                    throw new AccountBridgeHostException("achievements.account_changed");
            }
            Current(); var session = RequireSession(owner);
            var originalContext = CurrentContext;
            void Adopt(Auth.ScmOAuthSession active)
            {
                // OAuth has committed this exact refresh. Adopt before resource
                // IO and admission checks, including on a failed resource request.
                // Request cancellation cannot undo an already committed refresh.
                if (_disposed || generation != Generation || CurrentContext != originalContext ||
                    _session is null || _legacySession is not null || _localModeSessionLoopsStopped ||
                    active.AuthoritativeGameIdentity != session.AuthoritativeGameIdentity ||
                    !_oauth.IsInstalledFirstUseSessionOrRefreshOf(session, active))
                    throw new AccountBridgeHostException("achievements.account_changed");
                RequireSameSession(session, active);
                RequireSameSession(session, RequireSession(owner));
                CommitSharingSession(new RelayRequestSession(session), new RelayRequestSession(active));
            }
            var result = await send(session, Adopt).ConfigureAwait(false);
            Adopt(result.ActiveSession); Current();
            return result.Result;
        }
        finally { if (!_disposed) _mutationGate.Release(); }
    }
}
