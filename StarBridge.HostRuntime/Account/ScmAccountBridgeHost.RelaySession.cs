using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    // Transport identity for still-live Relay domains only. Never a synthetic OAuth session.
    private sealed class RelayRequestSession(ScmOAuthSession? scm, LegacyMigrationCredential? legacy = null)
    {
        internal ScmOAuthSession? Scm { get; } = scm;
        internal LegacyMigrationCredential? Legacy { get; } = legacy;
        internal string AccessToken => Scm?.AccessToken ?? Legacy!.AuthToken;
    }

    private RelayRequestSession RequireRelaySession(BridgeAccountContext context)
    {
        if (_disposed) throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        if (_session is not null) return new(RequireSession(context));
        if (_legacySession is { } legacy && !_legacyRestoreUnavailable && LegacyContext == context)
            return new(null, legacy);
        throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
    }

    private static void RequireSameRelaySession(RelayRequestSession expected, RelayRequestSession actual)
    {
        if (expected.Scm is { } scm && actual.Scm is { } active)
        {
            RequireSameSession(scm, active);
            return;
        }
        if (expected.Legacy is not null && ReferenceEquals(expected.Legacy, actual.Legacy)) return;
        throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
    }

    private async Task<(T Result, RelayRequestSession ActiveSession)> SendRelayRequestAsync<T>(
        RelayRequestSession session, Func<RelayRequestSession, CancellationToken, Task<T>> send, CancellationToken token)
    {
        if (session.Scm is { } scm)
        {
            var result = await _oauth.SendResourceRequestAsync(scm,
                (active, ct) => send(new(active), ct), token);
            return (result.Result, new(result.ActiveSession));
        }
        token.ThrowIfCancellationRequested();
        var generation = Generation;
        if (!ReferenceEquals(_legacySession, session.Legacy) || _legacyRestoreUnavailable || _disposed)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        // No SCM bootstrap, token exchange, refresh, fallback or automatic replay of a write.
        var legacyResult = await send(session, token);
        token.ThrowIfCancellationRequested();
        if (_disposed || generation != Generation || !ReferenceEquals(_legacySession, session.Legacy))
            throw new BridgeStaleGenerationException(generation, Generation);
        return (legacyResult, session);
    }
}
