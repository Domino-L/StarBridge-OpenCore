using System.Text.Json;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    public Task<object> ReadOfficialFleetAnnouncementEditorAsync(BridgeAccountContext context, JsonElement body, CancellationToken token) =>
        ObserveOfficialAnnouncement("official-announcement-editor", () => OfficialAnnouncementManagementAsync(context, body, "editor", token));
    public Task<object> ManageOfficialFleetAnnouncementsAsync(BridgeAccountContext context, JsonElement body, CancellationToken token) =>
        OfficialAnnouncementManagementAsync(context, body, "manage", token);
    public Task<object> ReadOfficialFleetAnnouncementOutcomeAsync(BridgeAccountContext context, JsonElement body, CancellationToken token) =>
        OfficialAnnouncementManagementAsync(context, body, "outcome", token);

    private async Task<object> OfficialAnnouncementManagementAsync(BridgeAccountContext context, JsonElement body,
        string action, CancellationToken token)
    {
        _ = RequireSession(context); // Legacy sessions cannot create or query official governance operations.
        var session = RequireRelaySession(context);
        var generation = Generation;
        if (_reauthorizationRequired || _credentialTemporarilyUnavailable)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        var client = _communities ?? throw new AccountBridgeHostException("communities.unavailable");
        var accountKey = JsonSerializer.Serialize(context);
        var scope = FriendScope(context, generation);
        void Current()
        {
            token.ThrowIfCancellationRequested();
            if (_disposed || Generation != generation) throw new BridgeStaleGenerationException(generation, Generation);
            _ = RequireSession(context);
            RequireSameRelaySession(RequireRelaySession(context), session);
        }
        Current();
        var result = await SendRelayRequestAsync<object>(session, (active, ct) => action switch
        {
            "editor" => client.ReadOfficialAnnouncementEditorAsync(active.AccessToken, body, scope, Current, ct),
            "manage" => client.ManageOfficialAnnouncementsAsync(active.AccessToken, body, accountKey, scope, Current, ct),
            _ => client.ReadOfficialAnnouncementOutcomeAsync(active.AccessToken, body, accountKey, Current, ct)
        }, token);
        Current();
        CommitSharingSession(session, result.ActiveSession);
        return result.Result;
    }
}
