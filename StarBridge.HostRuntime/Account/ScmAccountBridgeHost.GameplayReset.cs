using StarBridge.Core.Profiles;
using StarBridge.HostRuntime.Presence;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost : IGameplayTimeResetRemote, IGameplayHistoryRemote
{
    public Task<GameplayTimeResetState> ReadAsync(BridgeAccountContext context, CancellationToken token) =>
        WithGameplayRelaySession(context, (bearer, ct) => _legacyPasswordLogin!.ReadGameplayResetAsync(bearer, ct), token);

    public Task<GameplayTimeResetResult> ResetAsync(BridgeAccountContext context, GameplayTimeResetRequest request, CancellationToken token) =>
        WithGameplayRelaySession(context, (bearer, ct) => _legacyPasswordLogin!.ResetGameplayTimeAsync(bearer, request, ct), token);

    public Task<bool> PublishGameplayStatisticsAsync(BridgeAccountContext context,
        PersonalProfileGameplayStatisticsUpdateRequestContract update, CancellationToken token) =>
        WithGameplayRelaySession(context,
            (bearer, ct) => _legacyPasswordLogin!.PublishGameplayStatisticsAsync(bearer, update, ct), token);

    private async Task<T> WithGameplayRelaySession<T>(BridgeAccountContext context,
        Func<string, CancellationToken, Task<T>> send, CancellationToken token)
    {
        // WPF S2 publishes gameplay statistics via Relay for both login modes.
        // Relay verifies SCM's linked identity; no fabricated legacy credential or Java-failure fallback.
        if (_legacyPasswordLogin is null || GameplayTimeContext != context)
            throw new GameplayTimeException("gameplay.reset_unsupported");
        var generation = Generation;
        var session = RequireRelaySession(context);
        token.ThrowIfCancellationRequested();
        // Bypass the refresh/replay wrapper for destructive operations. Normal account lifecycle owns reauthorization.
        var result = await send(session.AccessToken, token).ConfigureAwait(false);
        token.ThrowIfCancellationRequested();
        if (generation != Generation || GameplayTimeContext != context)
            throw new BridgeStaleGenerationException(generation, Generation);
        RequireSameRelaySession(session, RequireRelaySession(context));
        return result;
    }
}
