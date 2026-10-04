using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime.Communities;
using StarBridge.HostRuntime.PartyRooms;
using StarBridge.HostRuntime.Presence;
using StarBridge.NativeBridge;

internal static class RuntimeShipLabelsTests
{
    internal static async Task Verify()
    {
        var room = JsonNode.Parse("""
            {"currentRoomId":"one","serverTime":"2026-09-30T12:00:00Z","rooms":[{
              "roomId":"one","title":"Example","goal":"","capacity":6,"isPublic":true,
              "eligibility":"everyone","admissionMode":"direct","passwordRequired":false,
              "voiceRequirement":"recommended","language":"zh","expiresAt":"2026-10-01T12:00:00Z",
              "recruitmentClosesAt":null,"viewerIsHost":false,"members":[{
                "callsign":"Example","gameId":"Example_Citizen","isHost":true,"presenceText":"游戏中",
                "locationText":"Unknown","shipText":"Unknown","shardText":"US"}]}]}
            """)!;
        var roomMember = room["rooms"]![0]!["members"]![0]!;
        var workspace = CommunityWorkspaceClientTests.Workspace();
        var source = workspace["members"]![0]!;
        source["online"] = true;
        source["liveStatus"] = "InGame";
        source["hasServerSession"] = true;
        using var handler = new Handler(request => request.RequestUri!.AbsolutePath == "/api/fleets/directory"
            ? new(HttpStatusCode.OK) { Content = JsonContent.Create(new {
                schemaVersion = 1, membershipModelVersion = 2, view = "mine", query = "", next = (string?)null,
                items = new[] { new { code = "A", name = "Example", description = "", language = "", activeTime = "",
                    memberCount = 1, relationship = "member", joinMode = "direct", actions = new[] { "leave" }, logoImageData = (string?)null } }
            }) } : new(HttpStatusCode.OK) { Content = JsonContent.Create(workspace) });
        using var client = new CommunityClient(new Uri("https://ship-labels.invalid"), handler);
        var directory = await client.ReadAsync("test-bearer", new("mine", "", null, null), "scope", default);
        var query = JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = directory.Items.Single().TargetRef, query = "", offset = 0 });
        async Task<JsonElement> CommunityMember() => JsonSerializer.SerializeToElement(
            await client.ReadWorkspaceAsync("test-bearer", query, "scope", default)).GetProperty("members")[0];
        JsonElement RoomMember() => BridgePayload.From(PartyRoomReader.Parse(JsonSerializer.SerializeToUtf8Bytes(room)))
            .GetProperty("rooms")[0].GetProperty("members")[0];
        roomMember["locationText"] = "Previous Port";
        roomMember["arrivalPendingConfirmation"] = true;
        roomMember["arrivalTargetCode"] = "Current Target";
        var pendingRoom = RoomMember();
        Check(pendingRoom.TryGetProperty("arrivalPendingConfirmation", out var pending) && pending.GetBoolean() &&
            pendingRoom.GetProperty("arrivalTargetCode").GetString() == "Current Target",
            "Room bridge must carry authorized arrival target and confirmation status, not just previous place");
        roomMember["arrivalPendingConfirmation"] = false;
        Check(!RoomMember().GetProperty("arrivalPendingConfirmation").GetBoolean() &&
            (!RoomMember().TryGetProperty("arrivalTargetCode", out var clearedTarget) || clearedTarget.ValueKind == JsonValueKind.Null),
            "Confirmed room location clears stale arrival target");
        source["location"] = "Previous Port";
        source["arrivalPendingConfirmation"] = true;
        source["arrivalTargetCode"] = "Current Target";
        var pendingCommunity = await CommunityMember();
        Check(pendingCommunity.GetProperty("arrivalPendingConfirmation").GetBoolean() &&
            pendingCommunity.GetProperty("arrivalTargetCode").GetString() == "Current Target",
            "Workspace bridge preserves only the current authorized arrival target");
        source["location"] = null;
        var hiddenCommunity = await CommunityMember();
        Check(!hiddenCommunity.GetProperty("arrivalPendingConfirmation").GetBoolean() &&
            hiddenCommunity.GetProperty("arrivalTargetCode").ValueKind == JsonValueKind.Null &&
            hiddenCommunity.GetProperty("arrivalTargetLabels").ValueKind == JsonValueKind.Null,
            "Withheld workspace location cannot reveal pending target or translated labels");
        source["arrivalPendingConfirmation"] = true;
        foreach (var place in new[] { "Orbituary", "New Babbage" })
        {
            var expectedPlace = GameLogSessionTracker.FindSharedLocationName(place);
            if (expectedPlace is null) continue; // Optional catalog is a valid open-core omission.
            source["location"] = place;
            source["arrivalTargetCode"] = place;
            var localizedCommunity = await CommunityMember();
            foreach (var field in new[] { "locationLabels", "arrivalTargetLabels" })
                Check(localizedCommunity.GetProperty(field).GetProperty("en").GetString() == expectedPlace.EnglishName &&
                    localizedCommunity.GetProperty(field).GetProperty("zhHans").GetString() == expectedPlace.ChineseName,
                    "Actual workspace HTTP and default JSON preserve the same location catalog as rooms and Native");
        }
        static JsonElement Labels(JsonElement member) => member.TryGetProperty("shipLabels", out var labels) ? labels : default;
        using var stream = typeof(GameShipNames).Assembly.GetManifestResourceStream("StarBridge.ShipNamePack.json")!;
        using var catalog = JsonDocument.Parse(stream);
        var rawNames = new HashSet<string>(StringComparer.Ordinal);
        foreach (var entry in catalog.RootElement.GetProperty("entries").EnumerateArray())
        {
            foreach (var key in new[] { "runtimeId", "englishName", "chineseName", "traditionalChineseName" })
                if (entry.TryGetProperty(key, out var value) && !string.IsNullOrWhiteSpace(value.GetString())) rawNames.Add(value.GetString()!);
            foreach (var alias in entry.GetProperty("aliases").EnumerateArray()) rawNames.Add(alias.GetString()!);
        }
        using var optionalCatalog = typeof(GameShipNames).Assembly.GetManifestResourceStream("StarBridge.ShipDisplayCatalog.tsv");
        if (optionalCatalog is not null)
        {
            using var reader = new StreamReader(optionalCatalog);
            foreach (var line in (await reader.ReadToEndAsync()).Split('\n').Skip(1))
            {
                var fields = line.Split('\t');
                if (fields.Length > 2) { rawNames.Add(fields[1]); rawNames.Add(fields[2]); }
            }
        }
        var translated = 0;
        foreach (var raw in rawNames.Where(value => value.Length > 0))
        {
            source["ship"] = raw;
            roomMember["shipText"] = raw;
            var expected = GameShipNames.Find(raw);
            foreach (var projected in new[] { RoomMember(), await CommunityMember() })
            {
                var labels = Labels(projected);
                if (expected is null) { Check(labels.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined, "Unmapped name invents no labels"); continue; }
                Check(labels.GetProperty("en").GetString() == expected.EnglishName &&
                    labels.GetProperty("zhHans").GetString() == expected.ChineseName &&
                    (labels.TryGetProperty("zhHant", out var traditional) ? traditional.GetString() : null) == expected.TraditionalChineseName,
                    "All ship labels must use the same vocabulary in room, workspace and Native");
                Check(labels.EnumerateObject().All(field => field.Name is "en" or "zhHans" or "zhHant"),
                    "Labels cannot expose runtime or ownership identifiers");
            }
            if (expected is not null) translated++;
        }
        foreach (var raw in new string?[] { null, "", "Unknown", "Unknown_new_model" })
        {
            source["ship"] = raw;
            roomMember["shipText"] = raw ?? "";
            Check(Labels(await CommunityMember()).ValueKind is JsonValueKind.Null or JsonValueKind.Undefined &&
                Labels(RoomMember()).ValueKind is JsonValueKind.Null or JsonValueKind.Undefined,
                "Withheld and unknown ship fields must never be enriched from another row");
        }
        source["ship"] = "ANVL_Lightning_F8C";
        roomMember["shipText"] = "ANVL_Lightning_F8C";
        foreach (var status in new[] { "Offline", "AppOnline", "Away", "Paused", "Unknown" })
        {
            source["liveStatus"] = status;
            roomMember["presenceText"] = status;
            Check(Labels(await CommunityMember()).ValueKind is JsonValueKind.Null or JsonValueKind.Undefined &&
                Labels(RoomMember()).ValueKind is JsonValueKind.Null or JsonValueKind.Undefined,
                "Non-game states must not carry stale language enrichment");
        }
        source["liveStatus"] = "InGame";
        source["hasServerSession"] = false;
        Check(Labels(await CommunityMember()).ValueKind is JsonValueKind.Null or JsonValueKind.Undefined,
            "Explicit absence of a game server cannot resurrect ship labels");
        source["hasServerSession"] = true;
        source["online"] = false;
        Check(Labels(await CommunityMember()).ValueKind is JsonValueKind.Null or JsonValueKind.Undefined,
            "Offline flag overrides stale InGame status");
        Check(translated >= 324, "Public ship-name resource must be present in the actual Host assembly");
        Console.WriteLine($"PASS ship-label bridge vocabulary: {translated}/{rawNames.Count} mapped input names; optional catalog={optionalCatalog is not null}");
    }
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
    private sealed class Handler(Func<HttpRequestMessage, HttpResponseMessage> read) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => Task.FromResult(read(request));
    }
}
