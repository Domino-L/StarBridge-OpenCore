using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;

internal static class CommunityCreationClientTests
{
    internal static async Task Verify()
    {
        var options = JsonSerializer.SerializeToElement(CommunityClient.CreationOptions(JsonSerializer.SerializeToElement(new { schemaVersion = 1 })));
        Check(options.GetProperty("categories").GetArrayLength() == 9 && options.GetProperty("tags").GetArrayLength() == 81, "full WPF options cross Host");
        Check(options.GetProperty("timeZones").EnumerateArray().Any(zone => zone.GetProperty("id").GetString() == options.GetProperty("defaultTimeZoneId").GetString()), "local default always belongs to offered time zones");
        var writes = 0;
        var paths = new List<string>();
        var behavior = "success";
        var stale = false;
        using var handler = new Handler(async request =>
        {
            paths.Add(request.Method + " " + request.RequestUri!.AbsolutePath);
            Check(request.Headers.Authorization?.Parameter == "test-bearer", "only current bearer is forwarded");
            if (request.Method == HttpMethod.Post)
            {
                writes++;
                Check(request.RequestUri.AbsolutePath == "/api/fleets/create", "never use old upsert path");
                var body = await request.Content!.ReadFromJsonAsync<JsonElement>();
                Check(!body.TryGetProperty("requestId", out _) && !body.TryGetProperty("ownerAccount", out _), "transport metadata and owner are not forwarded");
                if (behavior == "drop") throw new HttpRequestException("fixture response lost");
                if (behavior == "old") return new(HttpStatusCode.NotFound);
                if (behavior == "conflict") return new(HttpStatusCode.Conflict);
                if (behavior == "large") return new(HttpStatusCode.OK) { Content = new StringContent(new string('x', 9000)) };
                if (behavior == "stale") stale = true;
                return new(HttpStatusCode.OK) { Content = JsonContent.Create(new { schemaVersion = 1, status = "created", code = behavior == "wrongCode" ? "OTHER" : "NEWORG" }) };
            }
            Check(request.RequestUri.Query.Contains("code=NEWORG"), "confirmation read uses only acknowledged draft code");
            return new(HttpStatusCode.OK) { Content = JsonContent.Create(new
            {
                schemaVersion = 1, membershipModelVersion = 2, directoryVersion = 2,
                view = "mine", query = "", next = (string?)null, items = new[]
                {
                    new { code = "NEWORG", name = "New Organization", description = "", language = "zh-CN", activeTime = "",
                        memberCount = 1, relationship = behavior == "nonOwner" ? "member" : "owner", joinMode = "direct", actions = Array.Empty<string>() }
                }
            }) };
        });
        using var client = new CommunityClient(new Uri("https://communities.invalid"), handler);
        void Current() { if (stale) throw new AccountBridgeHostException("account.stale_generation"); }
        var command = Command("1");
        var result = await client.CreateAsync("test-bearer", command, "A:1", Current, default);
        Check(result.Status == "accepted" && result.Organization?.Relationship == "owner", "fresh owner confirmation is required");
        Check(paths.SequenceEqual(["POST /api/fleets/create", "GET /api/fleets/directory"]), "one create and one authoritative read");
        await client.CreateAsync("test-bearer", command, "A:1", Current, default);
        Check(writes == 1, "same intent does not send again");
        result = await client.CreateAsync("test-bearer", Command("1", "Changed Name"), "A:1", Current, default);
        Check(result.Error == "requestChanged" && writes == 1, "same intent cannot change payload");

        foreach (var mode in new[] { "drop", "wrongCode", "nonOwner", "large", "old", "conflict", "stale" })
        {
            behavior = mode;
            stale = false;
            var unique = Guid.NewGuid().ToString("N");
            var request = Command(unique);
            result = await client.CreateAsync("test-bearer", request, "A:1", Current, default);
            Check(result.Status == (mode is "old" or "conflict" ? "rejected" : "unknown"), "fail closed: " + mode);
            var before = writes;
            stale = false;
            await client.CreateAsync("test-bearer", request, "A:1", Current, default);
            Check(writes == before, "uncertain or rejected intent not replayed: " + mode);
        }
        behavior = "success";
        await client.CreateAsync("test-bearer", command, "B:1", Current, default);
        Check(paths.Count(path => path == "POST /api/fleets") == 0, "no downgrade to legacy upsert");

        var invalid = JsonSerializer.SerializeToNode(Command("2"))!;
        invalid["draft"]!["ownerAccount"] = "other";
        try { CommunityClient.ParseCreation(JsonSerializer.SerializeToElement(invalid)); throw new Exception("owner injected"); }
        catch (AccountBridgeHostException e) when (e.Code == "communities.dataInvalid") { }
        invalid["draft"]!.AsObject().Remove("ownerAccount");
        invalid["draft"]!["bannerImageData"] = "data:image/png;base64,AQ==";
        try { CommunityClient.ParseCreation(JsonSerializer.SerializeToElement(invalid)); throw new Exception("disabled banner accepted"); }
        catch (AccountBridgeHostException e) when (e.Code == "communities.dataInvalid") { }
        invalid["draft"]!.AsObject().Remove("bannerImageData");
        invalid["draft"]!["tagIds"] = true;
        try { CommunityClient.ParseCreation(JsonSerializer.SerializeToElement(invalid)); throw new Exception("malformed tags accepted"); }
        catch (AccountBridgeHostException e) when (e.Code == "communities.dataInvalid") { }
    }

    private static JsonElement Command(string id, string name = "New Organization") => JsonSerializer.SerializeToElement(new
    {
        schemaVersion = 1, requestId = id.PadLeft(32, '0'), draft = new
        {
            schemaVersion = 1, name, code = "NEWORG", description = "", joinPolicy = "Open", tagIds = new[] { "combat_pvp" },
            activeSystemIds = new[] { "stanton" }, activeFrom = "19:00", activeTo = "22:00", timeZoneId = "UTC"
        }
    });
    private static void Check(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
    private sealed class Handler(Func<HttpRequestMessage, Task<HttpResponseMessage>> send) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) => send(request);
    }
}
