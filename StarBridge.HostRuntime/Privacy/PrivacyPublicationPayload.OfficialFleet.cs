using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.Core.Presence;

namespace StarBridge.HostRuntime.Privacy;

internal static partial class PrivacyPublicationPayload
{
    internal static bool IsOfficialAppOnly(JsonElement payload) =>
        payload.TryGetProperty("officialFleet", out _) && !payload.GetProperty("gameObserved").GetBoolean() &&
        !HasOriginalPositiveAudience(payload);

    // Reuse the original audience masks; official App-only must not bypass their identity gate.
    internal static bool HasOriginalPositiveAudience(JsonElement payload) =>
        payload.GetProperty("friendsCanViewPresence").GetBoolean() ||
        payload.GetProperty("roomMembersCanView").GetBoolean() && payload.GetProperty("roomSharedStateFields").GetInt32() != 0 ||
        (payload.GetProperty("fleetMembersCanView").GetBoolean() || payload.GetProperty("fleetAdministratorsCanView").GetBoolean()) &&
            payload.GetProperty("fleetSharedStateFields").GetInt32() != 0 ||
        payload.TryGetProperty("communities", out var scopes) &&
            (scopes.Deserialize<CommunityRealtimeScope[]>(LocalPrivacyStore.Json) ?? []).Any(s => s.PotentialFields != 0);

    private static JsonElement AddOfficial(JsonElement payload, PrivacyPublicationInput input,
        OfficialFleetRealtimeChoice? choice, bool enabled, bool playing)
    {
        if (choice is null) return payload;
        var body = JsonNode.Parse(payload.GetRawText())!.AsObject();
        body["officialFleet"] = JsonSerializer.SerializeToNode(choice, LocalPrivacyStore.Json);
        body["appPresenceConfirmed"] = enabled && input.AppPresenceConfirmed;
        body["gameObserved"] = playing;
        body["hasServerSession"] = playing ? input.Game.Server.State == "connected" : (bool?)null;
        if (playing && choice.Fields.HasFlag(PlayerSharedStateFields.Location)) {
            body["arrivalPendingConfirmation"] = input.Game.Location.ArrivalPendingConfirmation;
            body["arrivalTargetCode"] = input.Game.Location.ArrivalPendingConfirmation ? input.Game.Location.ArrivalTargetCode : null;
        }
        if (!playing && body["online"]?.GetValue<bool>() == true)
            body["liveStatus"] = input.AppAway ? "Away" : "AppOnline";
        return JsonSerializer.SerializeToElement(body);
    }
}
