using System.Net;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;

internal static class OfficialFleetProjectionNegotiationTests
{
    private const string Source = "officialFleet:7";
    private const string Id = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
    private static readonly DateTimeOffset Started = new(2026, 10, 21, 20, 0, 0, TimeSpan.Zero);

    internal static async Task RunAsync()
    {
        await Governance();
        await Rally();
        var capabilities = AccountBridgeRuntime.AdvertisedCapabilities;
        Check(capabilities.Contains("officialFleet.governanceRole") && capabilities.Contains("officialFleet.rallyStarter") &&
            capabilities.Contains("officialFleet.readGovernanceContext") &&
            !capabilities.Contains("officialFleet.governance.activate") &&
            !capabilities.Contains("officialFleet.governance.revokeActivation"), "static projection capabilities exclude writes");
    }

    private static async Task Governance()
    {
        var legacy = new
        {
            schemaVersion = 1, sourceRef = Source, policyRevision = 2,
            capabilities = new[] { "announcements.manage", "audit.view", "organization.roles.manage" }
                .Select(capability => new { capability, state = "denied", reason = "notGranted" }).ToArray(),
            rootAuthority = new { providerState = "observed", controls = new[] { "activate", "recover", "delegate" }
                .Select(action => new { action, state = "denied", reason = "notGranted" }).ToArray() }
        };
        var expected = JsonSerializer.Serialize(legacy);
        var wire = JsonSerializer.SerializeToNode(legacy)!;
        wire["scopeKey"] = new string('a', 64);
        using var relay = new Relay();
        using var client = new CommunityClient(new Uri("https://projection.invalid/"), relay);
        async Task<JsonElement> Call(JsonObject request) => (JsonElement)await client.ReadOfficialGovernanceContextAsync(
            "synthetic", JsonSerializer.SerializeToElement(request), () => { }, default);
        JsonObject Request() => new() { ["schemaVersion"] = 1, ["sourceRef"] = Source };
        foreach (var role in new string?[] { null, "leader", "admin", "editor", "member" })
        {
            if (role is not null) wire["role"] = role;
            wire["membershipUpdatedAt"] = "2026-10-20T00:00:00Z";
            relay.Body = wire.ToJsonString();
            foreach (var empty in new[] { false, true })
            {
                var request = Request();
                if (empty) request["include"] = new JsonArray();
                var row = await Call(request);
                Check(row.GetRawText() == expected && row.EnumerateObject().Count() == 5 && relay.RoleHeader,
                    "legacy context bytes and relay header: " + (role ?? "old relay") + "/empty=" + empty);
            }
            var optedIn = Request(); optedIn["include"] = new JsonArray("role");
            var extended = await Call(optedIn);
            Check((role is null ? !extended.TryGetProperty("role", out _) : extended.GetProperty("role").GetString() == role) &&
                extended.GetProperty("membershipUpdatedAt").GetString() == "2026-10-20T00:00:00Z",
                "explicit role projection: " + (role ?? "absent"));
        }
        wire.AsObject().Remove("role"); wire.AsObject().Remove("membershipUpdatedAt");
        relay.Body = wire.ToJsonString();
        var oldRelayRequest = Request(); oldRelayRequest["include"] = new JsonArray("role");
        Check((await Call(oldRelayRequest)).GetRawText() == expected, "include role preserves old relay response bytes");
        foreach (var include in InvalidIncludes("role", "starter"))
        {
            var request = Request(); request["include"] = JsonNode.Parse(include);
            var before = relay.Calls;
            await Invalid(() => Call(request));
            Check(relay.Calls == before, "invalid context include rejected before relay: " + include);
        }
        using var duplicate = JsonDocument.Parse("{\"schemaVersion\":1,\"sourceRef\":\"officialFleet:7\",\"include\":[],\"include\":[\"role\"]}");
        await Invalid(() => client.ReadOfficialGovernanceContextAsync("synthetic", duplicate.RootElement, () => { }, default));
    }

    private static async Task Rally()
    {
        using var relay = new Relay();
        using var client = new CommunityClient(new Uri("https://projection.invalid/"), relay);
        async Task<JsonElement> Call(JsonElement request) => (JsonElement)await client.OfficialRallyAsync("synthetic", request, () => { }, default);
        foreach (var action in new[] { "read", "eligibility", "start", "respond", "end" })
        {
            var request = new JsonObject { ["schemaVersion"] = 1, ["action"] = action, ["sourceRef"] = Source };
            switch (action)
            {
                case "read": request["online"] = false; break;
                case "start": request["operationId"] = Id; request["text"] = "Rally"; request["minutes"] = 30; break;
                case "respond": request["rallyId"] = Id; request["response"] = "coming"; break;
                case "end": request["rallyId"] = Id; break;
            }
            object legacy = action == "eligibility"
                ? new { schemaVersion = 1, sourceRef = Source, canStart = true, onlineCount = 37, remainingThisHour = 2,
                    durations = new[] { 15, 30, 60 }, maximumText = 40 }
                : new { schemaVersion = 1, sourceRef = Source,
                    state = action switch { "read" => null, "start" => "started", "respond" => "accepted", _ => "ended" },
                    onlineCount = 37, rally = new { rallyId = Id, text = "Rally", minutes = 30,
                        startedAt = Started, expiresAt = Started.AddMinutes(30), state = action == "end" ? "ended" : "active",
                        coming = 9, cannot = 3, pending = 25, response = (string?)null } };
            var expected = JsonSerializer.Serialize(legacy);
            var wire = JsonNode.Parse(expected)!;
            if (action != "eligibility") wire["rally"]!["starter"] = new JsonObject { ["displayName"] = "Leader", ["isSelf"] = false };
            relay.Body = wire.ToJsonString();
            foreach (var include in new string?[] { null, "[]", "[\"starter\"]" })
            {
                request.Remove("include");
                if (include is not null) request["include"] = JsonNode.Parse(include);
                var row = await Call(JsonSerializer.SerializeToElement(request));
                Check(relay.StarterHeader && (relay.Request is null || !relay.Request.Contains("include", StringComparison.Ordinal)),
                    action + " always negotiates with relay without forwarding include");
                if (include != "[\"starter\"]" || action == "eligibility")
                    Check(row.GetRawText() == expected && (action == "eligibility" || row.GetProperty("rally").EnumerateObject().Count() == 10),
                        action + " legacy response bytes: " + (include ?? "omitted"));
                else
                    Check(row.GetProperty("rally").GetProperty("starter").EnumerateObject().Count() == 2 &&
                        row.GetProperty("rally").GetProperty("starter").GetProperty("displayName").GetString() == "Leader",
                        action + " explicit starter projection");
            }
            relay.Body = expected;
            Check((await Call(JsonSerializer.SerializeToElement(request))).GetRawText() == expected, action + " old relay remains compatible");
            foreach (var include in InvalidIncludes("starter", "role"))
            {
                request["include"] = JsonNode.Parse(include);
                var before = relay.Calls;
                await Invalid(() => Call(JsonSerializer.SerializeToElement(request)));
                Check(relay.Calls == before, action + " invalid include rejected before relay: " + include);
            }
            request["include"] = new JsonArray();
            using var duplicate = JsonDocument.Parse(request.ToJsonString()[..^1] + ",\"include\":[\"starter\"]}");
            await Invalid(() => Call(duplicate.RootElement));
        }
    }

    private static string[] InvalidIncludes(string known, string other) =>
        ["null", "true", "1", "{}", "\"" + known + "\"", "[null]", "[1]", "[{}]", "[\"unknown\"]",
            "[\"" + other + "\"]", "[\"" + known + "\",\"" + known + "\"]", "[\"" + known + "\",\"unknown\"]"];

    private static async Task Invalid(Func<Task> call)
    {
        try { await call(); }
        catch (AccountBridgeHostException error) when (error.Code == "communities.dataInvalid") { return; }
        throw new InvalidOperationException("Expected communities.dataInvalid");
    }

    private sealed class Relay : HttpMessageHandler
    {
        internal string Body = "{}";
        internal string? Request;
        internal int Calls;
        internal bool RoleHeader, StarterHeader;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Calls++;
            RoleHeader = request.Headers.TryGetValues("X-StarBridge-Governance-Role", out var role) && role.Single() == "1";
            StarterHeader = request.Headers.TryGetValues("X-StarBridge-Rally-Starter", out var starter) && starter.Single() == "1";
            Request = request.Content is null ? null : await request.Content.ReadAsStringAsync(token);
            return new(HttpStatusCode.OK) { Content = new StringContent(Body, Encoding.UTF8, "application/json") };
        }
    }

    private static void Check(bool value, string message)
    {
        if (!value) throw new InvalidOperationException(message);
        Console.WriteLine("PASS CX-L03b " + message);
    }
}
