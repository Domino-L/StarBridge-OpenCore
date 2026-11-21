using StarBridge.Core.Presence;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Privacy;
using StarBridge.NativeBridge;

// Build 71 (11-06): after a long session every main fleet save failed with
// privacy_local.account_changed. Each read issues a positive and a cancel
// context into a 64-entry cache; eviction by Keys.First() removed the context
// just issued, so the client always held an evicted reference.
internal static class OfficialFleetContextCacheTests
{
    private static readonly OfficialFleetRealtimeTarget Target = new("synthetic", 7, "TEST", "scm-observed-membership-row-v1:1");
    private static readonly BridgeAccountContext Owner = new("test", "https://context-cache.invalid", "synthetic");

    internal static async Task Run()
    {
        var root = Path.Combine(Path.GetTempPath(), "sb-official-context-cache-" + Guid.NewGuid().ToString("N"));
        var store = new LocalPrivacyStore(root);
        long generation = 1;
        var bridge = new OfficialFleetRealtimePrivacyBridge(store, () => (Owner, generation),
            (_, _, _) => Task.FromResult(new OfficialRealtimeContextWire(4, "officialFleet:7", Target, null, "initial", true)), () => true);
        async Task<BridgeEnvelope> Read() => (await bridge.DispatchAsync(BridgeEnvelope.Request("privacy.officialFleetRead",
            Guid.NewGuid().ToString("N"), generation, new { schemaVersion = 1 }, Owner), default)).Response;
        async Task<BridgeEnvelope> Save(string? contextRef, int fields) => (await bridge.DispatchAsync(BridgeEnvelope.Request(
            "privacy.officialFleetSave", Guid.NewGuid().ToString("N"), generation, new { schemaVersion = 1, contextRef,
                expectedRevision = store.Read(Owner).Revision, operationId = Guid.NewGuid().ToString("N"), fields }, Owner), default)).Response;
        static string? Context(BridgeEnvelope scope) => scope.Payload.GetProperty("contextRef").GetString();

        // A saved choice makes every read issue two contexts (positive and cancel).
        var first = await Read();
        Check(first.Status == "ok" && (await Save(Context(first), 7)).Status == "ok", "initial choice saves");
        var earliest = await Read();
        BridgeEnvelope latest = earliest;
        for (var i = 0; i < 100; i++) latest = await Read();
        var saved = await Save(Context(latest), 7);
        Check(saved.Status == "ok", "a save after 100 reads uses the context just issued: " + saved.Error?.Code);
        Check(store.Read(Owner).Settings!.OfficialFleet!.Fields == (PlayerSharedStateFields)7, "the reconfirmed choice is stored");

        // With the cache full, both contexts issued by one read stay usable:
        // the positive one saves and the cancel one withdraws.
        var full = await Read();
        Check(await Save(Context(full), 7) is { Status: "ok" }, "the positive context of one read at a full cache saves");
        var withdrawn = await Save(full.Payload.GetProperty("cancelContextRef").GetString(), 0);
        Check(withdrawn.Status == "ok" && store.Read(Owner).Settings!.OfficialFleet!.Fields == PlayerSharedStateFields.None,
            "the cancel context of the same read at a full cache withdraws: " + withdrawn.Error?.Code);

        // Each read's two contexts never evict each other; recent reads stay valid.
        var recent = new List<BridgeEnvelope>();
        for (var i = 0; i < 20; i++) recent.Add(await Read());
        foreach (var scope in recent)
            Check(await Save(Context(scope), 3) is { Status: "ok" }, "each of the last 20 reads can still save");

        // Only genuinely old references expire, and expiry asks for a fresh read.
        var revision = store.Read(Owner).Revision;
        var expired = await Save(Context(earliest), 5);
        Check(expired.Error?.Code == "privacy_local.refresh_required" && store.Read(Owner).Revision == revision,
            "an evicted reference asks for a fresh read and saves nothing: " + expired.Error?.Code);
        var unknown = await Save(Guid.NewGuid().ToString("N"), 5);
        Check(unknown.Error?.Code == "privacy_local.refresh_required" && store.Read(Owner).Revision == revision,
            "an unknown reference is not reported as an account change");

        // A real account generation change is still an account change.
        var current = await Read();
        generation = 2;
        Check((await Save(Context(current), 5)).Error?.Code == "privacy_local.account_changed" && store.Read(Owner).Revision == revision,
            "a context from another account generation still fails closed as an account change");
    }

    private static void Check(bool condition, string text) { if (!condition) throw new InvalidOperationException(text); }
}
