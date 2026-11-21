using System.Text.Json;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    public async Task<object> RefreshRsiDataAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token)
    {
        if (payload.ValueKind != JsonValueKind.Object || payload.EnumerateObject().Count() != 1 ||
            !payload.TryGetProperty("schemaVersion", out var schema) || !schema.TryGetInt32(out var version) || version != 1)
            throw new AccountBridgeHostException("communities.dataInvalid");
        await _mutationGate.WaitAsync(token);
        try
        {
            var owner = RequireSession(context);
            var generation = Generation;
            bool Current() => !_disposed && Generation == generation && CurrentContext == context;
            var result = await _oauth.RefreshRsiDataAsync(owner, Current, token);
            if (!Current()) throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
            RequireSameSession(owner, RequireSession(context));
            CommitSharingSession(new(owner), new(result.ActiveSession));
            return result.Result;
        }
        catch (ScmApiAuthenticationException) { return new OAuthPkceClient.RsiRefreshResult(1, "signInRequired"); }
        catch (Exception e) when (e is HttpRequestException or IOException or JsonException or OperationCanceledException)
        { return new OAuthPkceClient.RsiRefreshResult(1, "unavailable"); }
        finally { if (!_disposed) _mutationGate.Release(); }
    }
}
