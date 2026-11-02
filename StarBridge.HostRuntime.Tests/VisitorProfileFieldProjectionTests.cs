using System.Text.Json;
using StarBridge.Core.Profiles;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;
using StarBridge.NativeBridge;

internal static partial class LegacyPasswordLoginTests
{
    private static async Task VisitorProfileFieldProjection()
    {
        using var transport = new Transport();
        using var client = new LegacyPasswordLoginClient(new Uri("https://example.invalid/"), new Store(), transport);
        using var directory = new VisitorDirectory();
        using var communities = new CommunityClient(new Uri("https://example.invalid/"), directory);
        using var host = CreateHost(client, communities: communities);
        await host.LoginLegacyAsync(BridgePayload.From(new { schemaVersion = 1, email = "old@example.invalid", password = "synthetic" }), 0, default);
        var context = host.CurrentContext!;
        var mine = (CommunityPage)await host.ReadCommunitiesAsync(context,
            BridgePayload.From(new { schemaVersion = 1, view = "mine", query = "" }), default);
        var target = mine.Items.Single().TargetRef;
        var roster = JsonSerializer.SerializeToElement(await host.ReadCommunityWorkspaceAsync(context,
            BridgePayload.From(new { schemaVersion = 1, targetRef = target, query = "", offset = 0 }), default));
        var peer = roster.GetProperty("members").EnumerateArray().Single(m => !m.GetProperty("isSelf").GetBoolean());
        var now = DateTimeOffset.Parse("2026-10-21T12:00:00Z");
        var profile = new PersonalProfileDocumentContract(3, "visitor-peer", false, 7, now,
            new("Chosen public callsign", ""), PersonalProfileContentContract.Empty with {
                Introduction = "Authorized visitor introduction",
                Modules = [new("favorite-ships", 1, true, 0), new("skilled-roles", 1, false, 1)]
            }, new("Authorized fleet", "FIXTURE", null, "Officer", "blue"),
            new([new("Fixture ship", "Fixture ship", now)]),
            new(3600, 1, 2, now), true, "friendsFleetAndOrganizations",
            Presentation: new(1, new() { ["introduction"] = "linkedLegacy", ["schedule"] = "unknown" }, null),
            FleetAffiliationStatus: "shown");
        transport.Body = JsonSerializer.Serialize(profile, new JsonSerializerOptions(JsonSerializerDefaults.Web));
        using var dispatcher = new AccountBridgeDispatcher(host);
        var response = await dispatcher.DispatchAsync(BridgeEnvelope.Request("users.profile", Guid.NewGuid().ToString("N"),
            host.Generation, new { schemaVersion = 1, source = "community", reference = peer.GetProperty("memberRef").GetString(), contextRef = target }, context), default);
        Check(response.Response.Error is null, "Authorized community profile reaches the real dispatcher");
        var payload = response.Response.Payload;
        var actual = payload.GetProperty("profile");
        Check(actual.GetProperty("fleetAffiliationStatus").GetString() == "shown", "Affiliation status reaches Flutter through the real dispatcher");
        Check(!payload.GetProperty("editable").GetBoolean() && actual.GetProperty("identity").GetProperty("callSign").GetString() == "Chosen public callsign",
            "Visitor callsign is the server-authorized profile value, never the entry hint or current owner");
        Check(actual.GetProperty("content").GetProperty("introduction").GetString() == "Authorized visitor introduction" &&
            actual.GetProperty("content").GetProperty("modules").GetArrayLength() == 2, "Authorized introduction and module visibility reach Flutter intact");
        Check(actual.GetProperty("fleetAffiliation").GetProperty("fleetCode").GetString() == "FIXTURE" &&
            actual.GetProperty("gameplayStatistics").GetProperty("playTimeSeconds").GetInt64() == 3600 &&
            actual.GetProperty("hangar").GetProperty("ships").GetArrayLength() == 1, "Returned affiliation, public playtime and hangar are not dropped");
        var presentation = actual.GetProperty("presentation");
        Check(presentation.GetProperty("origins").GetProperty("introduction").GetString() == "linkedLegacy" &&
            (!presentation.TryGetProperty("sourceVersion", out var version) || version.ValueKind == JsonValueKind.Null),
            "Visitor-safe field origins survive the typed bridge without an owner edit fingerprint");
        Check(!payload.GetRawText().Contains("visitor-peer"), "Internal target identity stays in Host");
    }
}
