using System.Text.Json;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    public Task<object> ReadOfficialFleetRoleTemplatesAsync(BridgeAccountContext context, JsonElement body, CancellationToken token) =>
        OfficialRoleTemplatesAsync(context, body, "read", token);
    public Task<object> ManageOfficialFleetRoleTemplatesAsync(BridgeAccountContext context, JsonElement body, CancellationToken token) =>
        OfficialRoleTemplatesAsync(context, body, "manage", token);
    public Task<object> ReadOfficialFleetRoleTemplateOutcomeAsync(BridgeAccountContext context, JsonElement body, CancellationToken token) =>
        OfficialRoleTemplatesAsync(context, body, "outcome", token);

    private async Task<object> OfficialRoleTemplatesAsync(BridgeAccountContext context, JsonElement body, string action, CancellationToken token)
    {
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token); deadline.CancelAfter(TimeSpan.FromSeconds(12));
        _ = RequireSession(context);
        var session = RequireRelaySession(context); var generation = Generation;
        if (_reauthorizationRequired || _credentialTemporarilyUnavailable)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        var client = _communities ?? throw new AccountBridgeHostException("communities.unavailable");
        var account = JsonSerializer.Serialize(context); var scope = FriendScope(context, generation);
        void Current()
        {
            deadline.Token.ThrowIfCancellationRequested();
            if (_disposed || Generation != generation) throw new BridgeStaleGenerationException(generation, Generation);
            _ = RequireSession(context);
            RequireSameRelaySession(RequireRelaySession(context), session);
        }
        Current();
        var result = await SendRelayRequestAsync<object>(session, (active, cancel) => action switch
        {
            "read" => client.ReadOfficialRoleTemplatesAsync(active.AccessToken, body, scope, Current, cancel),
            "manage" => client.ManageOfficialRoleTemplatesAsync(active.AccessToken, body, account, scope, Current, cancel),
            _ => client.ReadOfficialRoleTemplateOutcomeAsync(active.AccessToken, body, account, Current, cancel)
        }, deadline.Token);
        Current();
        CommitSharingSession(session, result.ActiveSession);
        Current();
        return result.Result;
    }
}
