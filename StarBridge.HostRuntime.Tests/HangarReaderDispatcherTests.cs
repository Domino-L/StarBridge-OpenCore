using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.Core.Identity;
using StarBridge.HostRuntime;
using StarBridge.NativeBridge;
using static HangarLockedScanTests;

internal static class HangarReaderDispatcherTests
{
    public static void VerifyNativeCaptures(JsonElement fixtures)
    {
        var expected = new[] { "reading", "identityMismatch", "awaitingIdentity", "reading" };
        var entries = fixtures.EnumerateArray().ToArray();
        if (entries.Length != expected.Length) throw new Exception("Incomplete Runner capture matrix");
        for (var index = 0; index < entries.Length; index++) {
            using var test = new Harness();
            var capture = SimulateSource(entries[index].GetProperty("observation"), 1);
            var body = test.Initial(); body["observation"] = capture;
            Expect(test.Send("verify", body), expected[index], "Production initial identity capture");
        }
        Console.WriteLine("PASS Production Runner capture -> Host initial identity contract: 4/4");
    }

    public static void VerifyNativeContinuousScan(JsonElement fixtures)
    {
        using var test = new Harness();
        var fixture = fixtures[0]; var observations = 0;
        if (fixture.GetProperty("clicks").GetInt32() != 0 || fixture.GetProperty("identityReads").GetInt32() != 1)
            throw new Exception("A scan must read Handle once and must never click the avatar");
        BridgeEnvelope? last = null;
        foreach (var step in fixture.GetProperty("steps").EnumerateArray()) {
            var page = step.GetProperty("page").GetInt32();
            var body = test.Page(page, step.GetProperty("generation").GetInt32());
            body["observation"] = SimulateSource(step.GetProperty("observation"), page);
            var action = step.GetProperty("kind").GetString()!;
            last = test.Send(action, body);
            var phase = last.Error?.Code ?? last.Payload.GetProperty("phase").GetString();
            if (phase is not ("reading" or "verifying" or "complete"))
                throw new Exception($"Locked scan stopped on page {page}: {phase}");
            if (action == "observe") observations++;
            if (last.Payload.GetProperty("shipCount").GetInt32() > 0 && last.Payload.GetProperty("ships").GetArrayLength() == 0)
                throw new Exception("Accepted ships must remain visible during scanning");
        }
        if (observations != 6 || last is null) throw new Exception("Incomplete continuous scan");
        Expect(last, "complete", "First-page bookend finishes without another identity read");
        Console.WriteLine("PASS One Handle read, zero avatar clicks, six page observations through completion");
    }

    public static void VerifyNativePreparation(JsonElement fixtures)
    {
        if (fixtures.GetArrayLength() != 2) throw new Exception("Missing locked capture fixtures");
        foreach (var fixture in fixtures.EnumerateArray())
            if (fixture.GetProperty("identityReads").GetInt32() != 0 || fixture.GetProperty("hasIdentity").GetBoolean())
                throw new Exception("Locked page capture accessed identity, whether panel is open or closed");
        Console.WriteLine("PASS Locked page captures do not access the account panel: 2/2");
    }

    private static JsonObject SimulateSource(JsonElement observation, int page)
    {
        // Offline engine remains about:blank. Only this test simulator substitutes a trusted source.
        var capture = JsonNode.Parse(observation.GetRawText())!.AsObject();
        var source = "https://robertsspaceindustries.com/en/account/pledges?page=" + page;
        foreach (var key in new[] { "identity", "page" }) if (capture[key] is JsonObject part) {
            if (part["documentUrl"]!.GetValue<string>() != "about:blank") throw new Exception("Probe escaped synthetic origin");
            part["documentUrl"] = source;
        }
        return capture;
    }

    public static async Task ReadOnlyPreviewMatrix()
    {
        foreach (var (handles, expected) in new[] {
            (Array.Empty<string>(), "awaitingIdentity"), (new[] { "Pilot_Beta" }, "identityMismatch"),
            (new[] { "Pilot_Alpha", "Pilot_Beta" }, "identityAmbiguous") }) {
            using var test = new Harness(); var body = test.Initial();
            body["observation"]!["identity"]!["handles"] = JsonSerializer.SerializeToNode(handles);
            Expect(test.Send("verify", body), expected, "Explicit initial identity state");
        }
        foreach (var malformed in new[] { true, false }) {
            using var test = new Harness(); var body = test.Initial();
            if (malformed) body["observation"]!["identity"] = JsonSerializer.SerializeToNode(new[] { "Pilot_Alpha" });
            else body["observation"]!["identity"]!["documentUrl"] = "https://example.invalid/";
            Expect(test.Send("verify", body), "identityReadFailed", "Bad envelope is not account mismatch");
        }
        foreach (var kind in new[] { "Ship", "Unknown Type" }) {
            using var test = new Harness(); test.Send("verify", test.Initial());
            JsonObject Page() {
                var body = test.Page(1, 1); var page = body["observation"]!["page"]!;
                page["totalPages"] = 1; page["nextPage"] = null; page["pledges"]![0]!["items"]![0]!["kind"] = kind;
                return body;
            }
            test.Send("observe", Page()); var result = test.Send("observe", Page());
            Expect(result, "complete", "Stable pages complete regardless of ancillary item types");
            if (result.Payload.GetProperty("shipCount").GetInt32() != (kind == "Ship" ? 1 : 0))
                throw new Exception("Only explicitly typed ships belong to the inventory.");
            if (result.Payload.GetProperty("canSave").GetBoolean() || result.Payload.GetRawText().Contains("synthetic-1"))
                throw new Exception("Preview leaked internal keys or offered saving");
        }
        using (var test = new Harness()) {
            test.Send("verify", test.Initial()); test.Send("observe", test.Page(1, 3));
            Expect(test.Send("observe", test.Page(1, 2)), "pageChanged", "Stale native document");
        }
        using (var test = new Harness()) {
            test.Owner = test.Owner with { Identity = test.Owner.Identity with { Status = ScmGameIdentityStatus.Revoked } };
            Expect(test.Send("verify", test.Initial()), "accountChanged", "Revoked app identity");
            if (test.Send("begin", new JsonObject()).Error?.Code != "hangar.identity_unavailable") throw new Exception("Revoked start accepted");
        }
        using var lifecycle = new RouteProbe(); using var account = new RouteProbe(); using var preferences = new RouteProbe();
        using var composite = new CompositeBridgeDispatcher(lifecycle, account, preferences);
        foreach (var name in new[] { "begin", "verify", "observe", "cancel", "browserProfile" })
            await composite.DispatchAsync(BridgeEnvelope.Request("hangarReader." + name, "synthetic", 7));
        if (account.Count != 5 || lifecycle.Count != 0 || preferences.Count != 0) throw new Exception("Reader ownership moved");
    }
    private sealed class RouteProbe : IBridgeRequestDispatcher {
        public int Count;
        public event Action<BridgeEnvelope>? EventReady { add {} remove {} }
        public ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken cancellationToken = default) {
            Count++; return ValueTask.FromResult(new BridgeDispatchBatch(BridgeEnvelope.Response(request), []));
        }
        public void Dispose() {}
    }
}
