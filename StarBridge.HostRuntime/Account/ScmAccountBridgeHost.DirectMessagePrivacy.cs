namespace StarBridge.HostRuntime.Account;

using System.Text.Json;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Friends;
using StarBridge.NativeBridge;

internal sealed partial class ScmAccountBridgeHost
{
    public async Task<object> ReadDirectMessagePrivacyAsync(
        BridgeAccountContext context,
        JsonElement payload,
        CancellationToken token)
    {
        FriendsReader.ParsePrivacyRead(payload);
        var session = RequireRelaySession(context);
        var generation = Generation;
        if (_reauthorizationRequired || _credentialTemporarilyUnavailable)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        var reader = _friends ?? throw new AccountBridgeHostException("directMessages.privacy_unavailable");
        try
        {
            var result = await SendRelayRequestAsync(
                session,
                (active, cancellation) => reader.ReadPrivacyAsync(active.AccessToken, cancellation),
                token);
            if (_disposed || generation != Generation)
                throw new BridgeStaleGenerationException(generation, Generation);
            RequireSameRelaySession(RequireRelaySession(context), result.ActiveSession);
            _session = result.ActiveSession.Scm;
            return result.Result;
        }
        catch (ScmApiAuthenticationException)
        {
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        }
    }

    public async Task<object> SaveDirectMessagePrivacyAsync(
        BridgeAccountContext context,
        JsonElement payload,
        CancellationToken token)
    {
        var allowStrangerDirectMessages = FriendsReader.ParsePrivacyWrite(payload);
        var session = RequireRelaySession(context);
        var generation = Generation;
        if (_reauthorizationRequired || _credentialTemporarilyUnavailable)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        var reader = _friends ?? throw new AccountBridgeHostException("directMessages.privacy_unavailable");

        void EnsureCurrent()
        {
            if (_disposed || generation != Generation)
                throw new BridgeStaleGenerationException(generation, Generation);
            RequireSameRelaySession(RequireRelaySession(context), session);
        }

        try
        {
            var result = await SendRelayRequestAsync(
                session,
                (active, cancellation) => reader.SavePrivacyAsync(
                    active.AccessToken,
                    allowStrangerDirectMessages,
                    cancellation,
                    EnsureCurrent),
                token);
            EnsureCurrent();
            _session = result.ActiveSession.Scm;
            return result.Result;
        }
        catch (ScmApiAuthenticationException)
        {
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        }
    }
}
