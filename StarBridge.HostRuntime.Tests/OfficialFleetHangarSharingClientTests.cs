using System.Net;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using StarBridge.HostRuntime.Communities;
using StarBridge.HostRuntime.Hangar;

internal static class OfficialFleetHangarSharingClientTests
{
    private static JsonElement J(object value) => JsonSerializer.SerializeToElement(value);
    internal static async Task Run()
    {
        var version = new string('a', 64); var revision = new string('b', 32);
        var rawTarget = new { authorityNamespace = "https://issuer.example.test", organizationId = 7, sid = "ASTER", membershipEpoch = "scm-observed-membership-row-v1:30" };
        var selected = Enumerable.Range(0, 10000).Select(i => "instance-" + i.ToString("D5")).ToArray();
        var inventory = new LocalHangarSnapshot(1, DateTimeOffset.UtcNow, "private-operation", selected.Select(id =>
            new LocalHangarShip(id, "private-pledge", "Arrow", "private-liner", "private-purchase", DateTimeOffset.UtcNow, null)).ToArray());
        var currentStatus = HttpStatusCode.OK; var writeStatus = HttpStatusCode.OK;
        var writes = 0; var localReads = 0; var hold = false; var wrongAck = false;
        var started = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously); JsonElement outgoing = default; string? route = null;
        using var handler = new Handler(async request => {
            Check(request.Headers.Authorization?.Parameter == "fixture", "current bearer only");
            if (request.Method == HttpMethod.Get && request.RequestUri!.AbsolutePath.EndsWith("/intents")) return Reply(new { schemaVersion = 1,
                intents = new { state = "available", totalCount = 1, offset = 0, limit = 20, hasMore = false,
                    items = new[] { new { target = rawTarget, revision, strategy = "organizationPool", selectedCount = selected.Length, instanceRefs = Array.Empty<string>() } } } });
            if (request.Method == HttpMethod.Get) return currentStatus == HttpStatusCode.OK ? Reply(new { schemaVersion = 1, target = rawTarget,
                intentRevision = revision, sharing = new { state = "available", version, strategy = "organizationPool", instanceRefs = selected } }) : new(currentStatus);
            writes++; route = request.RequestUri!.AbsolutePath; outgoing = await request.Content!.ReadFromJsonAsync<JsonElement>();
            if (hold) { started.TrySetResult(); await release.Task; }
            if (writeStatus != HttpStatusCode.OK) return new(writeStatus);
            if (wrongAck) return Reply(new { schemaVersion = 1, sharing = new { strategy = outgoing.GetProperty("strategy").GetString(),
                instanceRefs = outgoing.GetProperty("instanceRefs") } });
            return route.EndsWith("/reduce") ? Reply(new { schemaVersion = 1, intent = new { target = rawTarget, revision = new string('c', 32),
                strategy = outgoing.GetProperty("strategy").GetString(), instanceRefs = outgoing.GetProperty("instanceRefs") } }) : Reply(new { schemaVersion = 1,
                intentRevision = new string('c', 32), sharing = new { state = "available", version = new string('c',64),
                strategy = outgoing.GetProperty("strategy").GetString(), instanceRefs = outgoing.GetProperty("instanceRefs") } });
        });
        using var client = new CommunityClient(new Uri("https://relay.example.test/"), handler);
        LocalHangarSnapshot Local() { localReads++; return inventory; }
        async Task<JsonElement> Open() => J(await client.ReadOfficialHangarSharingAsync("fixture", J(new { schemaVersion = 1, sourceRef = "officialFleet:7" }), "account:g1", () => {}, Local, default));
        JsonElement Command(JsonElement editor, string strategy, IEnumerable<string> refs) => J(new { schemaVersion = 1,
            editRef = editor.GetProperty("editRef").GetString(), sourceRef = editor.GetProperty("sourceRef").GetString(), strategy, selectedRefs = refs.ToArray() });
        string[] Refs(JsonElement e) => e.GetProperty("selectedRefs").EnumerateArray().Select(x => x.GetString()!).ToArray();
        var read = await Open();
        var bytes = Encoding.UTF8.GetByteCount(read.GetRawText());
        Check(bytes < 768 * 1024 && Refs(read).Length == 10000 && read.GetProperty("page").GetProperty("options").GetArrayLength() == 100,
            "10000 selected private refs fit Bridge payload and option page remains100");
        Check(!read.GetRawText().Contains("instance-") && !read.GetRawText().Contains("membershipEpoch") && !read.GetRawText().Contains("authorityNamespace") &&
            !read.GetRawText().Contains("private-"), "projection contains no raw instance, authority, account, pledge or purchase metadata");
        var frame = StarBridge.NativeBridge.BridgeEnvelope.Response(StarBridge.NativeBridge.BridgeEnvelope.Request("officialFleet.hangarSharing", "fixture", 1, new {schemaVersion=1}), read);
        Check(JsonSerializer.SerializeToUtf8Bytes(frame).Length < StarBridge.NativeBridge.BridgeProtocol.MaximumFrameBytes, "full10000 selected response envelope fits actual native frame bound");
        inventory = inventory with { Ships = [], Partial = true };
        read = await Open();
        var page = J(client.ReadOfficialHangarSharingPage(J(new { schemaVersion = 1, sourceRef = "officialFleet:7", editRef = read.GetProperty("editRef").GetString(), offset = 9900 }), "account:g1", () => {}));
        Check(page.GetProperty("options").GetArrayLength() == 100 && page.GetProperty("options").EnumerateArray().All(x => x.GetProperty("missing").GetBoolean()),
            "all10000 selected missing instances remain paged and cannot be fabricated as local inventory");
        var before = localReads;
        var outcome = await client.SaveOfficialHangarSharingAsync("fixture", Command(read, "organizationPool", Refs(read).Skip(1)), "account:g1", () => {},
            () => throw new Exception("Reduction must not read inventory"), default);
        Check(outcome.Status == "accepted" && route!.EndsWith("/reduce") && localReads == before && outgoing.GetProperty("instanceRefs").GetArrayLength() == 9999,
            "partial/missing inventory permits exact subset reduction with no inventory read");
        read = await Open();
        var blocked = await client.SaveOfficialHangarSharingAsync("fixture", Command(read, "organizationPool", Refs(read)), "account:g1", () => {}, Local, default);
        Check(blocked.Status == "rejected", "partial inventory cannot grant even if old refs are supplied");
        currentStatus = HttpStatusCode.ServiceUnavailable;
        read = await Open();
        Check(!read.GetProperty("canGrant").GetBoolean() && read.GetProperty("canReduce").GetBoolean() && !read.GetProperty("selectionKnown").GetBoolean() &&
            read.GetProperty("selectedCount").GetInt32() == 10000, "outage keeps exact old revision for whole withdrawal without exposing unavailable selection as empty");
        var saved = await client.SaveOfficialHangarSharingAsync("fixture", Command(read, "notShared", []), "account:g1", () => {}, () => throw new Exception(), default);
        Check(saved.Status == "accepted" && route!.EndsWith("/reduce"), "outage owner can withdraw exact old scope");
        currentStatus = HttpStatusCode.OK;
        foreach (var status in new[] { HttpStatusCode.Unauthorized, HttpStatusCode.ServiceUnavailable }) {
            read = await Open(); writeStatus = status; var count = writes;
            var command = Command(read, "notShared", []);
            saved = await client.SaveOfficialHangarSharingAsync("fixture", command, "account:g1", () => {}, Local, default);
            Check(saved.Status == (status == HttpStatusCode.Unauthorized ? "rejected" : "unknown") && writes == count + 1, "401/unknown produces value outcome without replay");
            saved = await client.SaveOfficialHangarSharingAsync("fixture", command, "account:g1", () => {}, Local, default);
            Check(saved.Status == "rejected" && writes == count + 1, "consumed editor cannot be replayed after uncertain write");
        }
        writeStatus = HttpStatusCode.OK;
        read = await Open(); var priorWrites = writes;
        saved = await client.SaveOfficialHangarSharingAsync("fixture", Command(read, "notShared", []), "another-account:g1", () => {}, Local, default);
        Check(saved.Status == "rejected" && writes == priorWrites, "wrong account cannot write retained editor");
        saved = await client.SaveOfficialHangarSharingAsync("fixture", J(new {schemaVersion=1,editRef=read.GetProperty("editRef").GetString(),sourceRef="officialFleet:8",strategy="notShared",selectedRefs=Array.Empty<string>()}), "account:g1", () => {}, Local, default);
        Check(saved.Status == "rejected" && writes == priorWrites, "wrong source cannot write retained editor");
        client.InvalidateHangarEdits();
        saved = await client.SaveOfficialHangarSharingAsync("fixture", Command(read, "notShared", []), "account:g1", () => {}, Local, default);
        Check(saved.Status == "rejected" && writes == priorWrites, "existing session invalidation retires official editor too");
        inventory = inventory with { Partial=false };
        read = await Open(); var revisionAtOpen = inventory.Revision; inventory = inventory with {Revision=revisionAtOpen+1};
        saved = await client.SaveOfficialHangarSharingAsync("fixture", Command(read, "organizationPool", Refs(read)), "account:g1", () => {}, Local, default);
        Check(saved.Status == "rejected" && writes == priorWrites, "local revision changed after opening cannot republish or grant");
        read = J(await client.ReadOfficialHangarSharingAsync("fixture", J(new {schemaVersion=1,sourceRef="officialFleet:7"}), "account:g1", () => {},
            () => throw new LocalHangarStoreException("hangar.unavailable", "synthetic missing inventory"), default));
        saved = await client.SaveOfficialHangarSharingAsync("fixture", Command(read, "operationOnly", []), "account:g1", () => {}, () => throw new Exception("operation strategy must not read inventory"), default);
        Check(saved.Status == "accepted" && route == "/api/official-fleets/hangar-sharing", "fresh operation-only choice needs no local inventory and does not publish it");
        read = await Open(); wrongAck=true;
        saved = await client.SaveOfficialHangarSharingAsync("fixture", Command(read, "operationOnly", []), "account:g1", () => {}, Local, default);
        Check(saved.Status == "unknown", "matching selection without fresh durable acknowledgement is not accepted"); wrongAck=false;
        read = await Open(); hold=true; var pending=client.SaveOfficialHangarSharingAsync("fixture", Command(read,"notShared",[]), "account:g1", () => {}, Local, default);
        await started.Task.WaitAsync(TimeSpan.FromSeconds(3)); var concurrent=await client.SaveOfficialHangarSharingAsync("fixture", Command(read,"notShared",[]), "account:g1", () => {}, Local, default);
        Check(concurrent.Status=="rejected" && concurrent.Error=="busy", "same existing write lane rejects concurrent command without replay");
        hold=false;release.SetResult();Check((await pending).Status=="accepted", "first owner write completes after concurrency rejection");
        Console.WriteLine($"PASS own sharing bounded editor responseBytes={bytes}; no real account or service");
    }
    private sealed class Handler(Func<HttpRequestMessage,Task<HttpResponseMessage>> handle) : HttpMessageHandler {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request,CancellationToken token) => handle(request);
    }
    private static HttpResponseMessage Reply(object body) => new(HttpStatusCode.OK) {Content=JsonContent.Create(body)};
    private static void Check(bool condition,string message) {if(!condition)throw new InvalidOperationException(message);Console.WriteLine("PASS "+message);}
}
