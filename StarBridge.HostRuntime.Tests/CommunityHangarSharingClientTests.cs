using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;
using StarBridge.HostRuntime.Hangar;

internal static class CommunityHangarSharingClientTests
{
    internal static async Task Verify()
    {
        var scanTime = DateTimeOffset.UtcNow.AddDays(-1);
        var scan = new LocalHangarSnapshot(1, scanTime, "local-operation", [new("ship-one", "private-pledge", "Arrow", "private-liner", "private-purchase", scanTime, "C:/private/image.png")]);
        var publicationJson = JsonSerializer.Serialize(CommunityHangarPublication.Build(scan));
        Check(!publicationJson.Contains("private") && !publicationJson.Contains("local-operation"), "publication omits local account, purchase and custom image metadata");
        Check(CommunityHangarPublication.Build(scan with { Ships = [] }).Length == 0, "confirmed complete empty scan may clear published inventory");
        foreach (var incomplete in new[] { scan with { Revision = 0 }, scan with { SavedAt = null }, scan with { Partial = true } }) {
            try { CommunityHangarPublication.Build(incomplete); throw new InvalidOperationException("incomplete scan accepted"); }
            catch (LocalHangarStoreException) { }
        }
        var version = new string('a', 64);
        string[] selected = ["A"];
        var mode = "ok";
        var writes = 0;
        var gets = 0;
        JsonElement outgoing = default;
        CommunityClient? client = null;
        using var handler = new Handler(async request =>
        {
            Check(request.Headers.Authorization?.Parameter == "fixture-bearer", "only current bearer is forwarded");
            if (request.RequestUri!.AbsolutePath == "/api/fleets/directory")
            {
                Check(request.Method == HttpMethod.Get && request.RequestUri.Query.Contains("view=mine"), "only joined directory is read");
                if (mode == "invalidate") client!.InvalidateHangarEdits();
                var second = request.RequestUri.Query.Contains("after=");
                return Reply(new { schemaVersion = 1, membershipModelVersion = 2, view = "mine", query = "",
                    next = second ? null : "page-two", items = new[] { new { code = second ? "B" : "A",
                    name = second ? "Org B" : "Org A", description = "", language = "", activeTime = "", memberCount = 1,
                    relationship = "member", joinMode = "direct", actions = Array.Empty<string>() } } });
            }
            var publish = request.RequestUri.PathAndQuery == "/api/fleets/hangar-sharing/publish";
            Check(publish || request.RequestUri.PathAndQuery == "/api/fleets/hangar-sharing", "no legacy full-player publication");
            if (request.Method == HttpMethod.Get)
            {
                gets++;
                if (mode == "unsupported") return new(HttpStatusCode.NotFound);
                if (mode == "read-offline") throw new HttpRequestException("fixture private transport details");
                if (mode == "malformed") return Reply(new { schemaVersion = 1, version, selectedCodes = selected });
                if (mode == "changed-read") version = Guid.NewGuid().ToString("N") + new string('a', 32);
                return Reply(new { schemaVersion = 1, version, usesExplicitTargets = true, selectedCodes = selected });
            }
            Check(request.Method == HttpMethod.Put, "writes use exact PUT contract");
            writes++;
            outgoing = await request.Content!.ReadFromJsonAsync<JsonElement>();
            Check(outgoing.EnumerateObject().Count() == (publish ? 4 : 3), "no account IDs or realtime fields in write");
            if (mode == "conflict") return new(HttpStatusCode.Conflict);
            if (mode == "drop") throw new HttpRequestException("lost fixture reply");
            if (mode == "redirect") return new(HttpStatusCode.Redirect);
            if (mode == "oversized") return new(HttpStatusCode.OK) { Content = new StringContent(new string(' ', 20000)) };
            selected = outgoing.GetProperty("selectedCodes").EnumerateArray().Select(x => x.GetString()!).ToArray();
            if (mode != "same-version") version = Guid.NewGuid().ToString("N") + new string('a', 32);
            if (publish) return Reply(new { schemaVersion = 1, publishedShips = mode == "wrong-count" ? 99 : outgoing.GetProperty("ships").GetArrayLength(),
                sharing = new { schemaVersion = 1, version, usesExplicitTargets = true, selectedCodes = selected } });
            return Reply(new { schemaVersion = 1, version, usesExplicitTargets = true,
                selectedCodes = mode == "wrong-targets" ? new[] { "C" } : selected });
        });
        using (client = new CommunityClient(new Uri("https://sharing.invalid"), handler))
        {
            var read = await Read();
            Check(writes == 0 && gets == 2 && read.GetProperty("options").GetArrayLength() == 2, "read pages all memberships without writes");
            var options = read.GetProperty("options").EnumerateArray().ToArray();
            Check(options[0].GetProperty("selected").GetBoolean() && !options[1].GetProperty("selected").GetBoolean(), "new membership is not auto selected");
            var command = Command(read, options.Select(o => o.GetProperty("targetRef").GetString()!).ToArray());
            Check((await client.SaveHangarSharingAsync("fixture-bearer", command, "other-account", () => { }, default)).Status == "rejected" && writes == 0,
                "another account cannot save the editor");
            var saved = await client.SaveHangarSharingAsync("fixture-bearer", command, "owner:1", () => { }, default);
            Check(saved.Status == "accepted" && writes == 1 && selected.SequenceEqual(["A", "B"]), "selected refs resolve to exact server codes");
            Check(outgoing.GetProperty("version").GetString() == new string('a', 64), "Host captured version, not caller input");
            Check((await client.SaveHangarSharingAsync("fixture-bearer", command, "owner:1", () => { }, default)).Status == "rejected" && writes == 1,
                "consumed editor cannot replay");
            foreach (var failure in new[] { "conflict", "drop", "redirect", "oversized", "same-version", "wrong-targets" })
            {
                mode = "ok";
                read = await Read();
                mode = failure;
                var before = writes;
                var result = await client.SaveHangarSharingAsync("fixture-bearer", Command(read, []), "owner:1", () => { }, default);
                Check(result.Status == (failure == "conflict" ? "rejected" : "unknown"), "failed/unverified save is not success: " + failure);
                Check(writes == before + 1, "no automatic retry: " + failure);
                Check((await client.SaveHangarSharingAsync("fixture-bearer", Command(read, []), "owner:1", () => { }, default)).Status == "rejected" && writes == before + 1,
                    "uncertain write requires fresh read: " + failure);
            }
            foreach (var (failure, error) in new[] { ("unsupported", "communities.upgradeRequired"), ("read-offline", "communities.unavailable"), ("malformed", "communities.dataInvalid"),
                ("changed-read", "communities.refreshRequired"), ("invalidate", "communities.refreshRequired") })
            {
                mode = failure;
                var before = writes;
                try { await Read(); throw new InvalidOperationException("expected " + error); }
                catch (AccountBridgeHostException e) when (e.Code == error) { }
                Check(writes == before, "failed reads cannot create consent");
            }
            mode = "ok";
            var inventoryReads = 0;
            CommunityPublishedShip[] Inventory() { inventoryReads++; return [new("one", "arrow", "Arrow", DateTimeOffset.UtcNow.AddDays(-1)), new("two", "arrow", "Arrow", DateTimeOffset.UtcNow.AddDays(-1))]; }
            read = await Read();
            var all = read.GetProperty("options").EnumerateArray().Select(r => r.GetProperty("targetRef").GetString()!).ToArray();
            var publication = await client.SaveHangarSharingAsync("fixture-bearer", Command(read, all), "owner:1", () => { }, default, Inventory);
            Check(publication.Status == "accepted" && inventoryReads == 1 && outgoing.GetProperty("ships").GetArrayLength() == 2,
                "explicit publication includes distinct owned instances and verifies response count");
            read = await Read();
            all = read.GetProperty("options").EnumerateArray().Select(r => r.GetProperty("targetRef").GetString()!).ToArray();
            publication = await client.SaveHangarSharingAsync("fixture-bearer", Command(read, all[..1]), "owner:1", () => { }, default, Inventory);
            Check(publication.Status == "accepted" && inventoryReads == 1 && !outgoing.TryGetProperty("ships", out _), "narrowing does not require or republish local inventory");
            read = await Read();
            all = read.GetProperty("options").EnumerateArray().Select(r => r.GetProperty("targetRef").GetString()!).ToArray();
            var beforeUnavailable = writes;
            publication = await client.SaveHangarSharingAsync("fixture-bearer", Command(read, all), "owner:1", () => { }, default,
                () => throw new LocalHangarStoreException("hangar.unavailable", "fixture"));
            Check(publication.Status == "rejected" && publication.Error == "localHangarRequired" && writes == beforeUnavailable, "missing complete local inventory rejects before network write");
            mode = "wrong-count";
            publication = await client.SaveHangarSharingAsync("fixture-bearer", Command(read, all), "owner:1", () => { }, default, Inventory);
            Check(publication.Status == "unknown", "mismatched publication acknowledgement is not success");
            mode = "ok";
            read = await Read();
            var recoveryCommand = JsonSerializer.SerializeToElement(new { schemaVersion = 1,
                editRef = read.GetProperty("editRef").GetString(), selectedRefs = read.GetProperty("options").EnumerateArray()
                    .Select(row => row.GetProperty("targetRef").GetString()!).ToArray(), inventoryMode = "saved" });
            var recovery = await client.SaveHangarSharingAsync("fixture-bearer", recoveryCommand, "owner:1", () => { }, default,
                () => throw new LocalHangarStoreException("hangar.unavailable", "uninitialized local inventory"));
            Check(recovery.Status == "accepted" && !outgoing.TryGetProperty("ships", out _),
                "explicit saved-inventory choice works without reading or uploading an uninitialized local inventory");
            read = await Read();
            JsonElement AutoCommand(JsonElement editor) => JsonSerializer.SerializeToElement(new { schemaVersion = 1,
                editRef = editor.GetProperty("editRef").GetString(), selectedRefs = editor.GetProperty("options").EnumerateArray()
                    .Select(row => row.GetProperty("targetRef").GetString()!).ToArray(), inventoryMode = "auto" });
            var automatic = await client.SaveHangarSharingAsync("fixture-bearer", AutoCommand(read), "owner:1", () => { }, default, Inventory);
            Check(automatic.Status == "accepted" && outgoing.GetProperty("ships").GetArrayLength() == 2,
                "default auto mode publishes complete local inventory without a user toggle");
            read = await Read();
            automatic = await client.SaveHangarSharingAsync("fixture-bearer", AutoCommand(read), "owner:1", () => { }, default,
                () => CommunityHangarPublication.Build(scan with { Partial = true }));
            Check(automatic.Status == "accepted" && !outgoing.TryGetProperty("ships", out _),
                "default mode keeps remote inventory when the local scan is incomplete");
            selected = ["A"];
            automatic = await client.UpdateSharedHangarAsync("fixture-bearer", () => { }, Inventory, default);
            Check(automatic.Status == "accepted" && selected.SequenceEqual(["A"]) && outgoing.GetProperty("ships").GetArrayLength() == 2,
                "a saved import updates only the existing explicit audience, not all memberships");
            var beforeAutomatic = writes;
            selected = [];
            automatic = await client.UpdateSharedHangarAsync("fixture-bearer", () => { }, Inventory, default);
            Check(automatic.Status == "accepted" && writes == beforeAutomatic, "import cannot enable withdrawn sharing");
            automatic = await client.UpdateSharedHangarAsync("fixture-bearer", () => { },
                () => CommunityHangarPublication.Build(scan with { Revision = 0 }), default);
            Check(automatic.Status == "rejected" && writes == beforeAutomatic, "uninitialized inventory cannot be automatically published");
            selected = ["A"];
            mode = "read-offline";
            automatic = await client.UpdateSharedHangarAsync("fixture-bearer", () => { }, Inventory, default);
            Check(automatic.Status == "rejected" && automatic.Error == "unavailable" && writes == beforeAutomatic,
                "offline consent read is safely retryable without sending inventory");
            mode = "unsupported";
            automatic = await client.UpdateSharedHangarAsync("fixture-bearer", () => { }, Inventory, default);
            Check(automatic.Status == "rejected" && automatic.Error != "unavailable" && writes == beforeAutomatic,
                "missing capability is not retried as an outage");
            mode = "drop";
            automatic = await client.UpdateSharedHangarAsync("fixture-bearer", () => { }, Inventory, default);
            Check(automatic.Status == "unknown" && writes == beforeAutomatic + 1, "uncertain automatic update is never blindly replayed");
            mode = "ok";
            read = await Read();
            client.InvalidateHangarEdits();
            Check((await client.SaveHangarSharingAsync("fixture-bearer", Command(read, []), "owner:1", () => { }, default)).Status == "rejected",
                "invalidated editor cannot write");
            foreach (var body in new[] { new { schemaVersion = 1, editRef = new string('a', 32), selectedRefs = new[] { "A" } } })
            {
                try { CommunityClient.ParseHangarSharingSave(JsonSerializer.SerializeToElement(body)); throw new InvalidOperationException("raw code accepted"); }
                catch (AccountBridgeHostException e) when (e.Code == "communities.dataInvalid") { }
            }
        }
        async Task<JsonElement> Read() => JsonSerializer.SerializeToElement(await client!.ReadHangarSharingAsync(
            "fixture-bearer", JsonSerializer.SerializeToElement(new { schemaVersion = 1 }), "owner:1", () => { }, default));
    }
    private static JsonElement Command(JsonElement read, string[] refs) => JsonSerializer.SerializeToElement(new
        { schemaVersion = 1, editRef = read.GetProperty("editRef").GetString(), selectedRefs = refs });
    private static HttpResponseMessage Reply(object body) => new(HttpStatusCode.OK) { Content = JsonContent.Create(body) };
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
    private sealed class Handler(Func<HttpRequestMessage, Task<HttpResponseMessage>> send) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => send(request);
    }
}
