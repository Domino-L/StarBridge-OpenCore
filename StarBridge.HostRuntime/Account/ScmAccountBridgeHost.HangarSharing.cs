using System.Text.Json;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Communities;
using StarBridge.HostRuntime.Hangar;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    private Func<BridgeAccountContext, LocalHangarSnapshot>? _sharingHangarSource;
    public void ConfigureHangarSharingSource(Func<BridgeAccountContext, LocalHangarSnapshot> read) => _sharingHangarSource = read;
    public async Task<HangarPublicationOutcome> UpdateSharedHangarAfterSaveAsync(BridgeAccountContext context, long generation, long revision, CancellationToken token)
    {
        if (_disposed || generation != Generation || _communities is null || _sharingHangarSource is null)
            return HangarPublicationOutcome.Rejected;
        if (_reauthorizationRequired || _credentialTemporarilyUnavailable)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        var session = RequireRelaySession(context);
        void Current()
        {
            if (_disposed || generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
            RequireSameRelaySession(RequireRelaySession(context), session);
        }
        var result = await SendRelayRequestAsync<object>(session, async (active, ct) =>
            await _communities.UpdateSharedHangarAsync(active.AccessToken, Current,
                () => {
                    Current();
                    var snapshot = _sharingHangarSource(context);
                    if (snapshot.Revision != revision)
                        throw new LocalHangarStoreException("hangar.revision_conflict", "The local import changed.");
                    return CommunityHangarPublication.Build(snapshot);
                }, ct), token);
        Current();
        _session = result.ActiveSession.Scm;
        return result.Result is CommunityCommand command ? command.Status switch
        {
            "accepted" => HangarPublicationOutcome.Complete,
            "rejected" when command.Error is "busy" or "unavailable" => HangarPublicationOutcome.Retryable,
            "unknown" => HangarPublicationOutcome.Unknown,
            _ => HangarPublicationOutcome.Rejected,
        } : HangarPublicationOutcome.Unknown;
    }
    public Task<object> ReadCommunityHangarSharingAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token) =>
        CommunityHangarSharingAsync(context, payload, false, token);
    public Task<object> SaveCommunityHangarSharingAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token) =>
        CommunityHangarSharingAsync(context, payload, true, token);
    private async Task<object> CommunityHangarSharingAsync(BridgeAccountContext context, JsonElement payload, bool save, CancellationToken token)
    {
        if (save) CommunityClient.ParseHangarSharingSave(payload);
        var session = RequireRelaySession(context);
        var generation = Generation;
        if (_reauthorizationRequired || _credentialTemporarilyUnavailable)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        var client = _communities ?? throw new AccountBridgeHostException("communities.unavailable");
        void Current()
        {
            if (_disposed || generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
            RequireSameRelaySession(RequireRelaySession(context), session);
        }
        var result = await SendRelayRequestAsync<object>(session, async (active, ct) => save
            ? await client.SaveHangarSharingAsync(active.AccessToken, payload, FriendScope(context, generation), Current, ct,
                () => { Current(); var source = _sharingHangarSource ?? throw new LocalHangarStoreException("hangar.unavailable", "Local hangar unavailable.");
                    var ships = CommunityHangarPublication.Build(source(context)); Current(); return ships; })
            : await client.ReadHangarSharingAsync(active.AccessToken, payload, FriendScope(context, generation), Current, ct,
                legacyViewerId: active.Legacy?.AccountId), token);
        Current();
        _session = result.ActiveSession.Scm;
        return result.Result;
    }
}
