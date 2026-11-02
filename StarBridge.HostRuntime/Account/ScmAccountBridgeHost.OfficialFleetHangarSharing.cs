using System.Text.Json;
using StarBridge.HostRuntime.Communities;
using StarBridge.HostRuntime.Hangar;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    public Task<object> ReadOfficialFleetHangarSharingAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token) =>
        OfficialFleetHangarSharingAsync(context, payload, "open", token, images:true);
    public Task<object> ReadOfficialFleetHangarSharingPageAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token) =>
        OfficialFleetHangarSharingAsync(context, payload, "page", token);
    public Task<object> SaveOfficialFleetHangarSharingAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token)
    {
        if(payload.TryGetProperty("kind",out var kind))
        {
            if(kind.ValueKind!=JsonValueKind.String || kind.GetString()!="clearImages" ||
                !payload.EnumerateObject().Select(p=>p.Name).Order(StringComparer.Ordinal).SequenceEqual(new[]{"schemaVersion","sourceRef","editRef","kind"}.Order(StringComparer.Ordinal)))
                throw new AccountBridgeHostException("communities.dataInvalid");
            var clear=JsonSerializer.SerializeToElement(payload.EnumerateObject().Where(p=>p.Name is "schemaVersion" or "sourceRef" or "editRef").ToDictionary(p=>p.Name,p=>p.Value));
            return ClearOfficialFleetHangarImagesAsync(context,clear,token);
        }
        var images=payload.TryGetProperty("includeImages",out var include)&&include.GetBoolean();
        if(images && (payload.GetProperty("strategy").GetString()!="organizationPool" || payload.GetProperty("selectedRefs").GetArrayLength()==0))
            throw new AccountBridgeHostException("communities.dataInvalid");
        var fields=JsonSerializer.SerializeToElement(payload.EnumerateObject().Where(p=>p.Name!="includeImages").ToDictionary(p=>p.Name,p=>p.Value));
        return OfficialFleetHangarSharingAsync(context,fields,"save",token,images,formalImages:images);
    }

    // Native typed entry points. Public Bridge admission remains unchanged until
    // all image read/report names are implemented and negotiated.
    internal Task<object> ReadOfficialFleetHangarImageDraftAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token) =>
        OfficialFleetHangarSharingAsync(context, payload, "open", token, images: true);
    internal Task<object> SaveOfficialFleetHangarImageDraftAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token) =>
        OfficialFleetHangarSharingAsync(context, payload, "save", token, images: true);
    internal Task<object> ClearOfficialFleetHangarImagesAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token) =>
        OfficialFleetHangarSharingAsync(context, payload, "clearImages", token, images: true);

    private async Task<object> OfficialFleetHangarSharingAsync(BridgeAccountContext context, JsonElement payload, string action, CancellationToken token, bool images = false, bool formalImages = false)
    {
        var started = System.Diagnostics.Stopwatch.GetTimestamp();
        var entryCode = "no-session";
        try
        {
            _ = RequireSession(context); // Official settings never use a legacy credential.
            entryCode = "relay-send-failed";
            if (action == "save") CommunityClient.ValidateOfficialHangarSave(payload);
            entryCode = "no-relay-session";
            var session = RequireRelaySession(context);
            var generation = Generation;
            if (_reauthorizationRequired || _credentialTemporarilyUnavailable)
            {
                entryCode = _reauthorizationRequired ? "reauthorization-required" : "credential-unavailable";
                throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
            }
            entryCode = "communities-unavailable";
            var client = _communities ?? throw new AccountBridgeHostException("communities.unavailable");
            var scope = FriendScope(context, generation);
            void Current()
            {
                if (_disposed || Generation != generation) throw new BridgeStaleGenerationException(generation, Generation);
                _ = RequireSession(context);
                RequireSameRelaySession(RequireRelaySession(context), session);
            }
            LocalHangarSnapshot Local()
            {
                Current();
                var source = _sharingHangarSource ?? throw new LocalHangarStoreException("hangar.unavailable", "Local inventory unavailable.");
                var result = source(context); Current(); return result;
            }
            Current();
            entryCode = "relay-send-failed";
            if (action == "page")
            {
                entryCode = "reached-client";
                return client.ReadOfficialHangarSharingPage(payload, scope, Current);
            }
            var response = await SendRelayRequestAsync<object>(session, async (active, ct) =>
            {
                entryCode = "reached-client";
                if (images && action == "clearImages") return await client.ClearOfficialHangarImagesAsync(active.AccessToken, payload, scope, Current, ct);
                if (images && action == "save")
                {
                    if(formalImages && !client.OfficialImageGrantEditorSupported(payload,scope)) return new CommunityCommand("rejected","upgradeRequired");
                    async Task<string> Owner(CancellationToken identityToken)
                    {
                        Current();
                        var identity = await _oauth.LoadBusinessIdentityAsync(active.Scm!, identityToken);
                        Current(); RequireSameSession(active.Scm!, identity.ActiveSession);
                        if (identity.ActiveSession.AccessToken != active.AccessToken) throw new AccountBridgeHostException("communities.refreshRequired");
                        return identity.BusinessSubjectId;
                    }
                    string? ReadImage(long revision, string id)
                    {
                        Current(); var read = _sharingHangarImages ?? throw new LocalHangarStoreException("hangar.unavailable", "Local images unavailable.");
                        var result = read(context, revision, id); Current(); return result;
                    }
                    return await client.SaveOfficialHangarImageDraftAsync(active.AccessToken, payload, scope, Current, Local, Owner, ReadImage, ct);
                }
                return action == "save" ? await client.SaveOfficialHangarSharingAsync(active.AccessToken, payload, scope, Current, Local, ct)
                    : images ? await client.ReadOfficialHangarImageDraftAsync(active.AccessToken, payload, scope, Current, Local, ct)
                    : await client.ReadOfficialHangarSharingAsync(active.AccessToken, payload, scope, Current, Local, ct);
            }, token);
            Current();
            CommitSharingSession(session, response.ActiveSession);
            return response.Result;
        }
        catch (BridgeStaleGenerationException) { entryCode = "stale-generation"; throw; }
        finally
        {
            RecordOfficialDiagnostic("official-hangar-entry", entryCode, null,
                (long)System.Diagnostics.Stopwatch.GetElapsedTime(started).TotalMilliseconds);
        }
    }
}
