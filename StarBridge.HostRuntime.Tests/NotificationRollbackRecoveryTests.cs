using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Notifications;
using StarBridge.NativeBridge;

internal static class NotificationRollbackRecoveryTests
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    private static readonly BridgeAccountContext Owner = new("fixture", "fixture", "rollback-synthetic");
    private static readonly string OwnerHash = Hash(JsonSerializer.SerializeToUtf8Bytes(new[] { Owner.Environment, Owner.Authority, Owner.Subject }));
    private static readonly string Official = NotificationPolicyStore.OfficialFleet("officialFleet:7");
    private static readonly string Community = NotificationPolicyStore.Organization("SYNTHETIC", DateTimeOffset.UnixEpoch);
    private static readonly string[] Sources = [Official, Community, "room", "friends", "directMessages"];
    private static int checks;
    private static void Check(bool ok, string message) { checks++; if (!ok) throw new Exception(message); }
    private static string Hash(byte[] bytes) => Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
    private static string PathFor(string root, int v) => Path.Combine(root, $"notification-policies-v{v}", OwnerHash + ".json");
    private static NotificationPolicyRule[] Rules(NotificationSourceMode mode, bool extended) => Sources.Select(s =>
        new NotificationPolicyRule(s, mode) {
            TypeRules = extended && (s == Official || s == Community) ? [new("chat", "disabled")] : null,
            QuietHours = extended && (s == Official || s == Community) ? new(true, s == Official ? 1320 : 540, s == Official ? 480 : 600) : null
        }).ToArray();
    private static void Legacy(string root, NotificationSourceMode mode, bool omit = false)
    {
        var path = PathFor(root, 1); Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var snapshot = new NotificationPolicySnapshot(2, Guid.NewGuid().ToString("N"), omit ? [new("room", mode)] : Rules(mode, false));
        var integrity = Hash(JsonSerializer.SerializeToUtf8Bytes(new { owner = OwnerHash, snapshot }, Json));
        File.WriteAllBytes(path, JsonSerializer.SerializeToUtf8Bytes(new { schemaVersion = 1, owner = OwnerHash, snapshot, integrity }, Json));
    }
    private static void Reject(Action action, string message)
    {
        try { action(); } catch (Exception e) when (e is IOException or InvalidDataException or NotificationSettingsConflictException or OperationCanceledException) {
            Check(true, message); return;
        }
        Check(false, message);
    }
    internal static async Task Run()
    {
        checks = 0;
        var root = Path.Combine(Path.GetTempPath(), "sb-notify-rollback-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try {
            foreach (var seeded in new[] { false, true })
            foreach (var extended in new[] { false, true })
                await RoundTrip(Path.Combine(root, $"c-{seeded}-{extended}"), seeded, extended);
            await Deletion(Path.Combine(root, "deleted"));
            await Damage(Path.Combine(root, "damage"));
            LocksAndCancellation(Path.Combine(root, "locks"));
            Console.WriteLine($"PASS CX-NOTIFY-V2-F: {checks} assertions, 0 failed");
        } finally { Directory.Delete(root, true); }
    }
    private static async Task RoundTrip(string root, bool seeded, bool extended)
    {
        var store = new NotificationPolicyStore(root);
        if (seeded) Legacy(root, NotificationSourceMode.ImportantOnly);
        var saved = store.Save(Owner, seeded ? 2 : 0, Guid.NewGuid().ToString("N"), Rules(NotificationSourceMode.DoNotDisturb, extended), () => true, true);
        Legacy(root, NotificationSourceMode.Normal);
        var bytes = File.ReadAllBytes(PathFor(root, 1));
        var recovered = store.Read(Owner);
        Check(Sources.All(s => recovered.For(s) == NotificationSourceMode.Normal), "c group uses latest old-version base modes for all sources");
        Check(recovered.Revision == saved.Revision + 1, "Recovery advances revision");
        foreach (var source in new[] { Official, Community }) {
            Check(JsonSerializer.Serialize(recovered.Rule(source), Json) == JsonSerializer.Serialize(saved.Rule(source) with { Mode = NotificationSourceMode.Normal }, Json),
                "c group preserves all extended rule data");
        }
        Check(bytes.SequenceEqual(File.ReadAllBytes(PathFor(root, 1))), "v1 remains byte-for-byte old-readable");
        var modernBytes = File.ReadAllBytes(PathFor(root, 2));
        Check(new NotificationPolicyStore(root).Read(Owner).Revision == recovered.Revision && modernBytes.SequenceEqual(File.ReadAllBytes(PathFor(root, 2))),
            "Fingerprint updated: reopen does not reconcile again");
        await Bridge(root, true);
        var next = store.Save(Owner, recovered.Revision, Guid.NewGuid().ToString("N"), Rules(NotificationSourceMode.ImportantOnly, false), () => true);
        Check((next.Rule(Official).QuietHours?.Enabled == true) == extended, "Subsequent basic save retains extended fields");
        Check(next.SuppressionRevision(Official) == next.Revision, "New narrowing records suppression revision");
    }
    private static async Task Deletion(string root)
    {
        Legacy(root, NotificationSourceMode.ImportantOnly);
        var store = new NotificationPolicyStore(root);
        var saved = store.Save(Owner, 2, Guid.NewGuid().ToString("N"), Rules(NotificationSourceMode.DoNotDisturb, true), () => true, true);
        File.Delete(PathFor(root, 1));
        var read = store.Read(Owner);
        Check(Sources.All(s => read.For(s) == NotificationSourceMode.Normal), "Deleted v1 means old-version default mode");
        Check(read.Rule(Official).TypeRules![0].Mode == "disabled" && read.Rule(Community).QuietHours!.Enabled, "Deleted v1 keeps extensions");
        Check(!File.Exists(PathFor(root, 1)), "Recovery never recreates v1 JSON");
        Check(read.SuppressionRevision(Official) == saved.SuppressionRevision(Official), "Existing suppression history survives recovery");
        await Bridge(root, true);
        // Omitted v1 sources reset modes, but still retain extensions from v2.
        Legacy(root, NotificationSourceMode.ImportantOnly, omit: true);
        read = store.Read(Owner);
        Check(read.For("room") == NotificationSourceMode.ImportantOnly && read.For(Official) == NotificationSourceMode.Normal && read.Rule(Official).QuietHours!.Enabled,
            "Omitted source retains extension with default base mode");
        Check(read.SuppressionRevision("room") == read.Revision, "Old writer narrowing suppresses earlier queued output");
    }
    private static async Task Damage(string root)
    {
        foreach (var damage in new[] { "truncated", "empty", "integrity", "duplicate", "schema", "oversize" }) {
            var path = Path.Combine(root, damage); Legacy(path, NotificationSourceMode.ImportantOnly);
            var store = new NotificationPolicyStore(path);
            store.Save(Owner, 2, Guid.NewGuid().ToString("N"), Rules(NotificationSourceMode.DoNotDisturb, true), () => true, true);
            var file = PathFor(path, 2); var text = File.ReadAllText(file); var node = JsonNode.Parse(text)!;
            if (damage == "integrity") node["integrity"] = "invalid";
            if (damage == "schema") node["schemaVersion"] = 99;
            File.WriteAllText(file, damage switch {
                "truncated" => "{", "empty" => "", "duplicate" => "{\"schemaVersion\":2," + text[1..],
                "oversize" => new string(' ', 131073), _ => node.ToJsonString()
            });
            var broken = File.ReadAllBytes(file); var legacy = File.ReadAllBytes(PathFor(path, 1));
            var fallback = store.Read(Owner);
            Check(Sources.All(s => fallback.For(s) == NotificationSourceMode.ImportantOnly), "Bad v2 falls back to v1: " + damage);
            Check(fallback.Rules.All(r => r.TypeRules == null && r.QuietHours == null), "Bad v2 cannot supply extensions: " + damage);
            Check(broken.SequenceEqual(File.ReadAllBytes(file)), "Read preserves corrupt evidence: " + damage);
            await Bridge(path, true);
            var saved = store.Save(Owner, fallback.Revision, Guid.NewGuid().ToString("N"), Rules(NotificationSourceMode.Normal, false), () => true);
            Check(store.Read(Owner).Revision == saved.Revision && legacy.SequenceEqual(File.ReadAllBytes(PathFor(path, 1))), "Save repairs v2 only: " + damage);
            File.WriteAllText(file, "{"); File.WriteAllText(PathFor(path, 1), "{");
            await Bridge(path, false); // Both damaged: error stays inside the actual dispatcher.
        }
    }
    private static void LocksAndCancellation(string root)
    {
        Legacy(root, NotificationSourceMode.ImportantOnly);
        var store = new NotificationPolicyStore(root);
        store.Save(Owner, 2, Guid.NewGuid().ToString("N"), Rules(NotificationSourceMode.DoNotDisturb, true), () => true, true);
        Legacy(root, NotificationSourceMode.Normal);
        var v1 = File.ReadAllBytes(PathFor(root, 1)); var v2 = File.ReadAllBytes(PathFor(root, 2));
        foreach (var version in new[] { 1, 2 }) {
            using var held = new FileStream(PathFor(root, version) + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
            Reject(() => store.Read(Owner), "Recovery obeys generation lock " + version);
            Check(v1.SequenceEqual(File.ReadAllBytes(PathFor(root, 1))) && v2.SequenceEqual(File.ReadAllBytes(PathFor(root, 2))), "Locked recovery changes neither JSON");
        }
        var calls = 0;
        Reject(() => store.Save(Owner, 3, Guid.NewGuid().ToString("N"), [], () => ++calls == 1), "Cancel before atomic reconciliation replace");
        Check(v1.SequenceEqual(File.ReadAllBytes(PathFor(root, 1))) && v2.SequenceEqual(File.ReadAllBytes(PathFor(root, 2))), "Interrupted recovery leaves both prior files intact");
        Check(Directory.GetFiles(Path.GetDirectoryName(PathFor(root, 2))!, "*.tmp").Length == 0, "Interrupted recovery cleans only its temporary file");
        Check(store.Read(Owner).For(Official) == NotificationSourceMode.Normal, "Next read retries interrupted recovery");
    }
    private sealed class DirectoryReader : IBridgeRequestDispatcher
    {
        public event Action<BridgeEnvelope>? EventReady { add { } remove { } }
        public void Dispose() { }
        public ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken token = default) =>
            ValueTask.FromResult(new BridgeDispatchBatch(BridgeEnvelope.Response(request, new {
                schemaVersion = 2, communities = Array.Empty<object>()
            }, Owner, preserveRequestAccountContext: false), []));
    }
    private static async Task Bridge(string root, bool ok)
    {
        using var settings = new NotificationSettingsBridgeDispatcher(root, () => 1);
        using var bridge = new NotificationPolicyBridgeDispatcher(settings, new DirectoryReader(), () => (Owner, 1));
        var response = (await bridge.DispatchAsync(BridgeEnvelope.Request("notificationPolicies.read", Guid.NewGuid().ToString("N"), 1,
            new { schemaVersion = 1 }, Owner))).Response;
        Check((response.Status == "ok") == ok, "Real bridge returns expected response without escaping exceptions");
    }
}
