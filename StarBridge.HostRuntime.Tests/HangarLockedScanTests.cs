using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.Core.Identity;
using StarBridge.HostRuntime.Hangar;
using StarBridge.NativeBridge;

internal static class HangarLockedScanTests
{
    public static Task Verify()
    {
        using var test = new Harness();
        var first = test.Send("verify", test.Initial());
        Expect(first, "reading", "The initial locked Handle check must authorize this scan once");
        foreach (var (page, doc) in new[] { (1, 1), (1, 1), (2, 2), (2, 2), (1, 3), (1, 3) })
        {
            var result = test.Send("observe", test.Page(page, doc));
            var expected = page == 2 && doc == 2 ? "verifying" : "reading";
            if (result.Error is not null || result.Payload.GetProperty("phase").GetString() is not ("reading" or "verifying" or "complete"))
                throw new Exception("A locked scan must continue without reading or clicking the avatar again");
            _ = expected;
        }
        Expect(test.Send("observe", test.Page(1, 3)), "complete", "Complete scan remains terminal");
        foreach (var mutation in new Action<JsonObject>[] {
            b => b["scanId"] = new string('b', 32), b => b["locked"] = false,
            b => b["documentGeneration"] = 0, b => b["source"] = "https://example.invalid/",
            b => b["observation"]!["identity"] = new JsonObject(),
        })
        {
            using var rejected = new Harness();
            Expect(rejected.Send("verify", rejected.Initial()), "reading", "initial identity");
            var page = rejected.Page(1, 1); mutation(page);
            Expect(rejected.Send("observe", page), "pageChanged", "Unlocked, foreign or stale captures must stop");
        }
        using (var missing = new Harness())
            Expect(missing.Send("observe", missing.Page(1, 1)), "identityReadFailed", "No page may skip the initial identity gate");
        using (var mismatch = new Harness())
            Expect(mismatch.Send("verify", mismatch.Initial("Pilot_Beta")), "identityMismatch", "Wrong initial account");
        using (var repeat = new Harness()) {
            repeat.Send("verify", repeat.Initial());
            Expect(repeat.Send("verify", repeat.Initial()), "pageChanged", "Cannot replace identity mid-scan");
        }
        using (var cancelled = new Harness()) {
            cancelled.Send("verify", cancelled.Initial()); cancelled.Send("cancel", new JsonObject());
            Expect(cancelled.Send("observe", cancelled.Page(1, 1)), "cancelled", "Late capture after cancellation");
        }
        using (var changed = new Harness()) {
            changed.Send("verify", changed.Initial()); changed.Owner = changed.Owner with { Generation = 8 };
            Expect(changed.Send("observe", changed.Page(1, 1)), "accountChanged", "SCM account changes still invalidate the scan");
        }
        using (var profile = new Harness()) {
            var key = profile.Send("browserProfile", new JsonObject()).Payload.GetProperty("profileKey").GetString();
            if (key is null || key.Length != 64 || key.Contains("subject")) throw new Exception("No opaque browser profile key");
            profile.Owner = profile.Owner with { Generation = 100 };
            if (profile.Send("browserProfile", new JsonObject()).Payload.GetProperty("profileKey").GetString() != key)
                throw new Exception("Restoring the same account must preserve the browser session profile");
            foreach (var account in new[] { profile.Owner.Account with { Subject = "other" }, profile.Owner.Account with { Environment = "production" }, profile.Owner.Account with { Authority = "other" } }) {
                profile.Owner = profile.Owner with { Account = account };
                if (profile.Send("browserProfile", new JsonObject()).Payload.GetProperty("profileKey").GetString() == key)
                    throw new Exception("Other accounts/environments must not share the RSI session profile");
            }
        }
        Console.WriteLine("PASS One initial identity, locked multi-page scan, invalidation and account-scoped browser profiles");
        return Task.CompletedTask;
    }

    internal static void Expect(BridgeEnvelope result, string phase, string message) {
        var actual = result.Error?.Code ?? result.Payload.GetProperty("phase").GetString();
        if (actual != phase) throw new Exception($"{message}: expected {phase}, actual {actual}");
    }
    internal sealed class Harness : IDisposable {
        public HangarAccountIdentity Owner = new(new("development", "synthetic-issuer", "subject-a"), 7,
            new(ScmGameIdentityStatus.Verified, "Pilot_Alpha", "pilot_alpha"));
        public const string ScanId = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";
        private readonly HangarReaderDispatcher _reader;
        public string Operation = "";
        public Harness(LocalHangarStore? store = null) { _reader = new(() => Owner, store); Operation = Send("begin", new JsonObject()).Payload.GetProperty("operationId").GetString()!; }
        public BridgeEnvelope Send(string action, JsonObject body) {
            body["schemaVersion"] = 1; body["operationId"] = Operation;
            return _reader.Dispatch(BridgeEnvelope.Request("hangarReader." + action, Guid.NewGuid().ToString("N"), Owner.Generation, body, Owner.Account)).Response;
        }
        public JsonObject Initial(string handle = "Pilot_Alpha") {
            var body = Page(1, 1); var source = body["source"]!.GetValue<string>();
            body["observation"]!["identity"] = JsonSerializer.SerializeToNode(new { schemaVersion = 1, sourceKind = "current-account", documentUrl = source, handles = new[] { handle } });
            return body;
        }
        public JsonObject Page(int page, int document) {
            var source = "https://robertsspaceindustries.com/en/account/pledges?page=" + page;
            return JsonSerializer.SerializeToNode(new { scanId = ScanId, locked = true, source, documentGeneration = document,
                observation = new { page = new { schemaVersion = 1, status = "ready", documentUrl = source, page, totalPages = 2,
                    nextPage = page == 1 ? (int?)2 : null, unfiltered = true, pledges = new[] { new { sourceKey = "synthetic-" + page,
                        acquiredText = (string?)null, items = new[] { new { title = "Test Ship", kind = "Ship", liner = "Test Builder" } } } } } } })!.AsObject();
        }
        public void Dispose() => _reader.Dispose();
    }
}
