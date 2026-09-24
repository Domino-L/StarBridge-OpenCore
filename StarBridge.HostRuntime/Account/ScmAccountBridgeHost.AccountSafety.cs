namespace StarBridge.HostRuntime.Account;

using System.Text.Json;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

internal sealed partial class ScmAccountBridgeHost
{
    public async Task<object> SubmitAccountAppealAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token)
    {
        var input = AccountSafetyRequest.Appeal(payload);
        var session = RequireRelaySession(context);
        var generation = Generation;
        if (_reauthorizationRequired || _credentialTemporarilyUnavailable)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        var client = _accountSafety ?? throw new AccountBridgeHostException("accountSafety.read_unavailable");
        void Current()
        {
            if (_disposed || generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
            RequireSameRelaySession(RequireRelaySession(context), session);
        }
        // Do not replay a possibly accepted POST through an OAuth resource retry.
        Current();
        var result = await client.AppealAsync(session.AccessToken, input, Current, token);
        Current();
        return result;
    }

    public async Task<AccountSafetyView> ReadAccountSafetyAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token)
    {
        AccountSafetyRequest.Read(payload);
        var session = RequireRelaySession(context);
        var generation = Generation;
        if (_reauthorizationRequired || _credentialTemporarilyUnavailable)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        var reader = _accountSafety ?? throw new AccountBridgeHostException("accountSafety.read_unavailable");
        try
        {
            var result = await SendRelayRequestAsync(session,
                (active, ct) => reader.ReadAsync(active.AccessToken, ct), token);
            token.ThrowIfCancellationRequested();
            if (_disposed || generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
            RequireSameRelaySession(RequireRelaySession(context), result.ActiveSession);
            _session = result.ActiveSession.Scm;
            return result.Result;
        }
        catch (ScmApiAuthenticationException)
        { throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired); }
    }
}
