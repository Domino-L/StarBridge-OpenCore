using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;

internal static class CommunityClientTests
{
    internal static async Task Verify()
    {
        var state = "none";
        var requests = new List<string>();
        var writes = 0;
        var dropWrite = false;
        var hidden = false;
        var legacy = false;
        var directoryVersion = 2;
        string? forwardedFilters = null;
        using var handler = new Handler(async request =>
        {
            requests.Add(request.Method + " " + request.RequestUri!.AbsolutePath);
            if (request.Method == HttpMethod.Get && request.RequestUri.Query.Contains("filters="))
                forwardedFilters = Uri.UnescapeDataString(request.RequestUri.Query.Split("filters=")[1].Split('&')[0]);
            Check(request.Headers.Authorization?.Parameter == "test-bearer", "Only the supplied SCM bearer is sent");
            if (request.Method == HttpMethod.Post)
            {
                writes++;
                var body = await request.Content!.ReadFromJsonAsync<JsonElement>();
                Check(body.GetProperty("fleetCode").GetString() == "B", "Target code comes from the scoped reference");
                state = "member";
                if (dropWrite) throw new HttpRequestException("test response lost");
                return new(HttpStatusCode.OK) { Content = JsonContent.Create(new { privateField = "must-not-cross-bridge" }) };
            }
            if (legacy) return new(HttpStatusCode.NotFound);
            return new(HttpStatusCode.OK) { Content = JsonContent.Create(new
            {
                schemaVersion = 1, membershipModelVersion = 2, directoryVersion, totalCount = 1, view = "discover", query = "", next = (string?)null,
                items = hidden ? [] : new[] { new { code = "B", name = "Community B", description = "Public description",
                    language = "English", activeTime = "", memberCount = 2, relationship = state, joinMode = "direct",
                    recruiting = true, recruitingNote = "Weekend crews\nNew players welcome",
                    actions = new[] { state == "member" ? "leave" : "join" }, logoImageData = (string?)null } }
            }) };
        });
        using var client = new CommunityClient(new Uri("https://communities.invalid"), handler);
        var page = await client.ReadAsync("test-bearer", new("discover", "", null, null), "account:A:generation:1", default);
        Check(page.Items.Length == 1 && page.Items[0].TargetRef.Length == 32, "Directory issues opaque targets");
        Check(page.Items[0].RecruitingNote == "Weekend crews\nNew players welcome", "Public recruitment copy permits multiline text without failing the directory");
        var repeat = await client.ReadAsync("test-bearer", new("discover", "", null, null, "{\"scale\":[\"small\"]}"), "account:A:generation:1", default);
        Check(repeat.Items[0].OrganizationRef == page.Items[0].OrganizationRef && repeat.Items[0].TargetRef != page.Items[0].TargetRef,
            "Stable account-scoped display identity is separate from single-use action targets");
        Check(forwardedFilters == "{\"scale\":[\"small\"]}" && repeat.TotalCount == 1, "Filter and total count cross the Host without local filtering");
        var other = await client.ReadAsync("test-bearer", new("discover", "", null, null), "account:B:generation:1", default);
        Check(other.Items[0].OrganizationRef != page.Items[0].OrganizationRef, "Organization references are scoped to the account");
        directoryVersion = 1;
        try { await client.ReadAsync("test-bearer", new("discover", "", null, null, "{}"), "account:A:generation:1", default); throw new Exception("Expected filter capability gate"); }
        catch (AccountBridgeHostException e) when (e.Code == "communities.upgradeRequired") { }
        directoryVersion = 2;
        var serialized = JsonSerializer.Serialize(page);
        Check(!serialized.Contains("\"Code\"") && !serialized.Contains("test-bearer"), "Bridge view contains neither legacy code nor credential");
        JsonElement Command(string action, string reference) => JsonSerializer.SerializeToElement(new { schemaVersion = 1, action, targetRef = reference });
        var target = page.Items[0].TargetRef;
        var rejected = await client.ExecuteAsync("test-bearer", Command("join", target), "account:B:generation:1", () => {}, default);
        Check(rejected.Status == "rejected" && writes == 0, "Other account cannot reuse the target");
        var accepted = await client.ExecuteAsync("test-bearer", Command("join", target), "account:A:generation:1", () => {}, default);
        Check(accepted.Status == "accepted" && writes == 1, "Admission is confirmed by a fresh membership read");
        Check(requests.TakeLast(3).SequenceEqual(new[] { "GET /api/fleets/directory", "POST /api/fleets/apply", "GET /api/fleets/directory" }), "Preflight, one write, and verification use exact active routes");
        rejected = await client.ExecuteAsync("test-bearer", Command("join", target), "account:A:generation:1", () => {}, default);
        Check(rejected.Status == "rejected" && writes == 1, "Consumed write targets cannot be replayed");

        state = "none";
        page = await client.ReadAsync("test-bearer", new("discover", "", null, null), "A:2", default);
        hidden = true;
        rejected = await client.ExecuteAsync("test-bearer", Command("join", page.Items[0].TargetRef), "A:2", () => {}, default);
        Check(rejected.Status == "rejected" && writes == 1, "Lost visibility prevents write");
        hidden = false;
        page = await client.ReadAsync("test-bearer", new("discover", "", null, null), "A:2", default);
        dropWrite = true;
        var unknown = await client.ExecuteAsync("test-bearer", Command("join", page.Items[0].TargetRef), "A:2", () => {}, default);
        Check(unknown.Status == "unknown" && writes == 2, "A lost response never retries a membership write");
        rejected = await client.ExecuteAsync("test-bearer", Command("join", page.Items[0].TargetRef), "A:2", () => {}, default);
        Check(rejected.Status == "rejected" && writes == 2, "Uncertain targets are consumed too");

        legacy = true;
        try { await client.ReadAsync("test-bearer", new("discover", "", null, null), "A:2", default); throw new Exception("Expected old-service gate"); }
        catch (AccountBridgeHostException e) when (e.Code == "communities.upgradeRequired") { }
        Check(writes == 2, "Old service does not trigger a fallback write");
        await VerifyDeparture();
    }
    private static async Task VerifyDeparture()
    {
        foreach (var scenario in new[] { "confirmed", "private-hidden", "reply-lost", "still-member", "identity-failed" })
        {
            var member = true;
            var writes = 0;
            var reads = 0;
            using var handler = new Handler(async request =>
            {
                Check(request.Headers.Authorization?.Parameter == "scm-only", "Departure uses SCM bearer only");
                if (request.Method == HttpMethod.Post)
                {
                    writes++;
                    Check(request.RequestUri!.AbsolutePath == "/api/fleets/leave" && request.RequestUri.Query == "",
                        "Departure uses ordinary exit, not ownership transfer or disband");
                    var body = await request.Content!.ReadFromJsonAsync<JsonElement>();
                    Check(body.EnumerateObject().Count() == 1 && body.GetProperty("fleetCode").GetString() == "SCM",
                        "Departure sends only the Host-resolved organization code");
                    member = scenario == "still-member";
                    if (scenario == "reply-lost") throw new HttpRequestException("Synthetic lost response");
                    return new(HttpStatusCode.OK) { Content = JsonContent.Create(new { schemaVersion = 1, status = "accepted" }) };
                }
                reads++;
                if (scenario == "identity-failed" && reads > 1) return new(HttpStatusCode.Unauthorized);
                return new(HttpStatusCode.OK) { Content = JsonContent.Create(new {
                    schemaVersion = 1, membershipModelVersion = 2, view = "discover", query = "", next = (string?)null,
                    items = !member && scenario == "private-hidden" ? [] : new[] { new {
                        code = "SCM", name = "Synthetic organization", description = "", language = "", activeTime = "",
                        memberCount = 1, relationship = member ? "member" : "none", joinMode = "direct",
                        actions = member ? new[] { "leave" } : new[] { "join" }, logoImageData = (string?)null
                    } }
                }) };
            });
            using var client = new CommunityClient(new Uri("https://communities.invalid"), handler);
            var page = await client.ReadAsync("scm-only", new("discover", "", null, null), "SCM:1", default);
            var command = JsonSerializer.SerializeToElement(new { schemaVersion = 1, action = "leave", targetRef = page.Items[0].TargetRef });
            var result = await client.ExecuteAsync("scm-only", command, "SCM:1", () => { }, default);
            var expected = scenario is "confirmed" or "private-hidden" ? "accepted" : scenario == "identity-failed" ? "rejected" : "unknown";
            Check(result.Status == expected && writes == (scenario == "identity-failed" ? 0 : 1),
                "Departure outcome requires authoritative membership confirmation: " + scenario);
            var replay = await client.ExecuteAsync("scm-only", command, "SCM:1", () => { }, default);
            Check(replay.Status == "rejected" && writes == (scenario == "identity-failed" ? 0 : 1),
                "Departure cannot replay a consumed or identity-rejected command");
        }
    }
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
    private sealed class Handler(Func<HttpRequestMessage, Task<HttpResponseMessage>> send) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) => send(request);
    }
}
