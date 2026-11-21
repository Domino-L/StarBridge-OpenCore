using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Notifications;
using StarBridge.NativeBridge;

internal static class NotificationRollbackAvailabilityTests
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    private static readonly BridgeAccountContext Owner = new("fixture", "fixture", "availability-synthetic");
    private static readonly string OwnerHash = Hash(JsonSerializer.SerializeToUtf8Bytes(new[] { Owner.Environment, Owner.Authority, Owner.Subject }));
    private static int checks;
    private static string Hash(byte[] bytes) => Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
    private static void Check(bool ok, string message) { checks++; if (!ok) throw new Exception(message); }
    private static string FileFor(string root, int version) => Path.Combine(root, $"notification-policies-v{version}", OwnerHash + ".json");
    private static void Legacy(string root, NotificationPolicyRule[] rules)
    {
        var snapshot = new NotificationPolicySnapshot(1, Guid.NewGuid().ToString("N"), rules);
        var integrity = Hash(JsonSerializer.SerializeToUtf8Bytes(new { owner = OwnerHash, snapshot }, Json));
        var file = FileFor(root, 1); Directory.CreateDirectory(Path.GetDirectoryName(file)!);
        File.WriteAllBytes(file, JsonSerializer.SerializeToUtf8Bytes(new { schemaVersion = 1, owner = OwnerHash, snapshot, integrity }, Json));
    }
    internal static async Task Run()
    {
        checks = 0;
        var root = Path.Combine(Path.GetTempPath(), "sb-notify-availability-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        var failed = 0;
        try {
            foreach (var (name, run) in new (string, Func<string, Task>)[] {
                ("capacity-129", Capacity), ("corrupt-v1", CorruptLegacy), ("corrupt-casing", CorruptCasing),
                ("byte-budget-and-write-failure", NotificationReconciliationWriteTests.Run)
            }) {
                try { await run(Path.Combine(root, name)); Console.WriteLine("PASS F2 " + name); }
                catch (Exception e) { failed++; Console.WriteLine("FAIL F2 " + name + ": " + e.GetType().Name + ": " + e.Message); }
            }
            Console.WriteLine($"SUMMARY F2 passed={4 - failed} failed={failed}; assertions={checks} (F4 assertions reported separately)");
            if (failed != 0) throw new Exception("Notification rollback availability regression failed.");
        } finally { Directory.Delete(root, true); }
    }
    private static async Task Capacity(string root)
    {
        var extensions = Enumerable.Range(1, 128).Select(i => new NotificationPolicyRule(
            NotificationPolicyStore.Organization("CAPACITY-" + i, DateTimeOffset.UnixEpoch), NotificationSourceMode.DoNotDisturb) {
                TypeRules = [new("chat", "disabled")], QuietHours = new(true)
            }).Reverse().ToArray();
        var store = new NotificationPolicyStore(root);
        var original = store.Save(Owner, 0, Guid.NewGuid().ToString("N"), extensions, () => true, true);
        Legacy(root, [new("room", NotificationSourceMode.ImportantOnly)]);
        var v1 = File.ReadAllBytes(FileFor(root, 1));
        var recovered = store.Read(Owner);
        var kept = extensions.Select(r => r.Source).Append("room").Order(StringComparer.Ordinal);
        Check(recovered.Rules.Length == 129 && recovered.Rules.Select(r => r.Source).SequenceEqual(kept), "All 128 extensions and the new v1 source survive");
        Check(recovered.For("room") == NotificationSourceMode.ImportantOnly, "All current v1 sources and modes take priority");
        Check(recovered.Rules.Where(r => r.Source != "room").All(r => r.Mode == NotificationSourceMode.Normal && r.TypeRules![0].Mode == "disabled" && r.QuietHours!.Enabled), "Retained v2 extensions survive reconciliation");
        Check(recovered.Revision == original.Revision + 1 && new NotificationPolicyStore(root).Read(Owner).Revision == recovered.Revision, "Bounded result is written once under locks");
        await Bridge(root);
        var saved = store.Save(Owner, recovered.Revision, Guid.NewGuid().ToString("N"), recovered.Rules.Select(r => r with { Mode = NotificationSourceMode.DoNotDisturb }).ToArray(), () => true);
        Check(saved.Rules.Length == 129 && saved.For("room") == NotificationSourceMode.DoNotDisturb, "Editing 129 existing sources keeps every extension and v1 source");
        Check(store.Read(Owner).Revision == saved.Revision && v1.SequenceEqual(File.ReadAllBytes(FileFor(root, 1))), "Save remains readable and never changes v1");
        var saveStore = new NotificationPolicyStore(Path.Combine(root, "save-only"));
        var saveBase = saveStore.Save(Owner, 0, Guid.NewGuid().ToString("N"), extensions, () => true, true);
        try { saveStore.Save(Owner, saveBase.Revision, Guid.NewGuid().ToString("N"), [new("friends", NotificationSourceMode.ImportantOnly)], () => true); Check(false, "Adding a 129th source must fail"); }
        catch (InvalidDataException) { Check(JsonSerializer.Serialize(saveStore.Read(Owner), Json) == JsonSerializer.Serialize(saveBase, Json), "New source limit rejects the write without losing any of the 128 extensions"); }
        // Two full, disjoint generations must retain every setting, up to 256.
        var allLegacy = Enumerable.Range(1, 127).Select(i => new NotificationPolicyRule(
            NotificationPolicyStore.Organization("LEGACY-" + i, DateTimeOffset.UnixEpoch), NotificationSourceMode.ImportantOnly)).Append(new("room", NotificationSourceMode.DoNotDisturb)).ToArray();
        Legacy(root, allLegacy);
        recovered = store.Read(Owner);
        Check(recovered.Rules.Length == 256 && allLegacy.All(r => recovered.For(r.Source) == r.Mode) &&
            extensions.All(r => recovered.Rule(r.Source).TypeRules![0].Mode == "disabled" && recovered.Rule(r.Source).QuietHours!.Enabled), "128 current v1 sources and all 128 extensions survive");
        var edited = store.Save(Owner, recovered.Revision, Guid.NewGuid().ToString("N"), recovered.Rules.Select(r => r with { Mode = NotificationSourceMode.ImportantOnly }).ToArray(), () => true);
        Check(edited.Rules.Length == 256 && store.Read(Owner).Revision == edited.Revision, "Editing all 256 existing sources is allowed and readable");
        var before = File.ReadAllBytes(FileFor(root, 2));
        try { store.Save(Owner, edited.Revision, Guid.NewGuid().ToString("N"), allLegacy.Append(new("friends", NotificationSourceMode.Normal)).ToArray(), () => true); Check(false, "New sources above the write limit must fail"); }
        catch (InvalidDataException) { Check(before.SequenceEqual(File.ReadAllBytes(FileFor(root, 2))), "New source request is rejected without changing v2"); }
        var excessive = JsonNode.Parse(File.ReadAllText(FileFor(root, 2)))!;
        excessive["snapshot"]!["rules"]!.AsArray().Add(JsonSerializer.SerializeToNode(new NotificationPolicyRule("friends", NotificationSourceMode.DoNotDisturb), Json));
        SignModern(excessive);
        File.WriteAllText(FileFor(root, 2), excessive.ToJsonString());
        var damaged = File.ReadAllBytes(FileFor(root, 2));
        var fallback = store.Read(Owner);
        Check(fallback.Rules.Length == 128 && allLegacy.All(r => fallback.For(r.Source) == r.Mode), "257-row v2 is corrupt and falls back to valid v1");
        Check(damaged.SequenceEqual(File.ReadAllBytes(FileFor(root, 2))), "Oversized source file is preserved on read");
        await Bridge(root);
        File.WriteAllBytes(FileFor(root, 2), before);
        var newLegacy = allLegacy.Select(r => r.Source == "room" ? new NotificationPolicyRule("friends", r.Mode) : r).ToArray();
        Legacy(root, newLegacy);
        // Give every previous source an extension, simulating a manually edited 256-row v2.
        var manual = JsonNode.Parse(File.ReadAllText(FileFor(root, 2)))!;
        foreach (var row in manual["snapshot"]!["rules"]!.AsArray())
            row!["typeRules"] = JsonSerializer.SerializeToNode(new[] { new NotificationTypeRule("chat", "disabled") }, Json);
        SignModern(manual); File.WriteAllText(FileFor(root, 2), manual.ToJsonString());
        before = File.ReadAllBytes(FileFor(root, 2)); v1 = File.ReadAllBytes(FileFor(root, 1));
        Check(store.Read(Owner).Rules.Length == 256, "Over-256 merge uses the readable v2 without truncation");
        Check(before.SequenceEqual(File.ReadAllBytes(FileFor(root, 2))) && v1.SequenceEqual(File.ReadAllBytes(FileFor(root, 1))), "Over-256 merge overwrites neither generation");
        await Bridge(root);
    }
    private static void SignModern(JsonNode file) => file["integrity"] = Hash(JsonSerializer.SerializeToUtf8Bytes(new {
        schemaVersion = 2, owner = OwnerHash, snapshot = file["snapshot"], legacyFingerprint = file["legacyFingerprint"]!.GetValue<string>()
    }, Json));
    private static async Task CorruptCasing(string root)
    {
        foreach (var version in new[] { 1, 2, 0 }) {
            var path = Path.Combine(root, version.ToString());
            Legacy(path, [new("room", NotificationSourceMode.ImportantOnly)]);
            var store = new NotificationPolicyStore(path);
            var modern = store.Save(Owner, 1, Guid.NewGuid().ToString("N"), [new("room", NotificationSourceMode.DoNotDisturb)], () => true);
            foreach (var damagedVersion in version == 0 ? new[] { 1, 2 } : new[] { version }) {
                var file = FileFor(path, damagedVersion);
                File.WriteAllText(file, File.ReadAllText(file).Replace("\"snapshot\":", "\"Snapshot\":"));
            }
            var v1 = File.ReadAllBytes(FileFor(path, 1)); var v2 = File.ReadAllBytes(FileFor(path, 2));
            if (version == 0) {
                try { store.Read(Owner); Check(false, "Both corrupt files must report a storage error"); }
                catch (InvalidDataException) { Check(true, "Both corrupt files report a storage error"); }
            } else {
                var read = store.Read(Owner);
                Check(read.For("room") == (version == 1 ? NotificationSourceMode.DoNotDisturb : NotificationSourceMode.ImportantOnly), "Snapshot casing corruption uses the other valid generation: " + version);
                if (version == 1) Check(read.Revision == modern.Revision, "Bad v1 does not reconcile or overwrite valid v2");
            }
            using var settings = new NotificationSettingsBridgeDispatcher(path, () => 1);
            using var bridge = new NotificationPolicyBridgeDispatcher(settings, new DirectoryReader(), () => (Owner, 1));
            var response = (await bridge.DispatchAsync(BridgeEnvelope.Request("notificationPolicies.read", Guid.NewGuid().ToString("N"), 1, new { schemaVersion = 1 }, Owner))).Response;
            Check(response.Status == (version == 0 ? "error" : "ok"), "Casing corruption stays inside Bridge and uses recovery: " + version);
            Check(v1.SequenceEqual(File.ReadAllBytes(FileFor(path, 1))) && v2.SequenceEqual(File.ReadAllBytes(FileFor(path, 2))), "Casing corruption read preserves both files: " + version);
        }
    }
    private static async Task CorruptLegacy(string root)
    {
        foreach (var damage in new[] { "truncated", "empty", "integrity", "duplicate", "schema", "oversize" }) {
            var path = Path.Combine(root, damage);
            Legacy(path, [new("room", NotificationSourceMode.ImportantOnly)]);
            var store = new NotificationPolicyStore(path);
            var saved = store.Save(Owner, 1, Guid.NewGuid().ToString("N"), [new("room", NotificationSourceMode.DoNotDisturb) {
                TypeRules = [new("chat", "disabled")], QuietHours = new(true)
            }], () => true, true);
            var file = FileFor(path, 1); var text = File.ReadAllText(file); var node = JsonNode.Parse(text)!;
            if (damage == "integrity") node["integrity"] = "invalid";
            if (damage == "schema") node["schemaVersion"] = 99;
            File.WriteAllText(file, damage switch {
                "truncated" => "{", "empty" => "", "duplicate" => "{\"schemaVersion\":1," + text[1..],
                "oversize" => new string(' ', 32769), _ => node.ToJsonString()
            });
            var broken = File.ReadAllBytes(file); var modern = File.ReadAllBytes(FileFor(path, 2));
            Check(JsonSerializer.Serialize(store.Read(Owner), Json) == JsonSerializer.Serialize(saved, Json), "Invalid v1 means unknown, preserving all v2 values: " + damage);
            Check(modern.SequenceEqual(File.ReadAllBytes(FileFor(path, 2))), "Reading invalid v1 leaves v2 unchanged: " + damage);
            await Bridge(path);
            // An actual edit, followed by reopen and idempotent retry, proves the settings are repairable.
            var operation = Guid.NewGuid().ToString("N");
            var rules = new[] { new NotificationPolicyRule("room", NotificationSourceMode.ImportantOnly) };
            var repaired = store.Save(Owner, saved.Revision, operation, rules, () => true);
            Check(repaired.For("room") == NotificationSourceMode.ImportantOnly && repaired.Rule("room").QuietHours!.Enabled && repaired.Rule("room").TypeRules![0].Mode == "disabled", "Save keeps extensions with damaged v1: " + damage);
            Check(JsonSerializer.Serialize(new NotificationPolicyStore(path).Read(Owner), Json) == JsonSerializer.Serialize(repaired, Json), "Reopen uses repaired v2: " + damage);
            Check(store.Save(Owner, saved.Revision, operation, rules, () => true).Revision == repaired.Revision, "Retry remains idempotent: " + damage);
            Check(JsonNode.Parse(File.ReadAllText(FileFor(path, 2)))!["legacyFingerprint"]!.GetValue<string>() == Hash(broken), "Fingerprint hashes actual damaged bytes: " + damage);
            Check(broken.SequenceEqual(File.ReadAllBytes(file)), "Damaged v1 is never rewritten: " + damage);
            // A later usable old writer must still reconcile normally after the damaged-byte fingerprint.
            Legacy(path, [new("room", NotificationSourceMode.Normal)]);
            var resumed = store.Read(Owner);
            Check(resumed.For("room") == NotificationSourceMode.Normal && resumed.Rule("room").QuietHours!.Enabled && resumed.Revision == repaired.Revision + 1, "Later valid v1 edits reconcile: " + damage);
        }
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
    private static async Task Bridge(string root)
    {
        using var settings = new NotificationSettingsBridgeDispatcher(root, () => 1);
        using var bridge = new NotificationPolicyBridgeDispatcher(settings, new DirectoryReader(), () => (Owner, 1));
        var response = (await bridge.DispatchAsync(BridgeEnvelope.Request("notificationPolicies.read", Guid.NewGuid().ToString("N"), 1,
            new { schemaVersion = 1 }, Owner))).Response;
        Check(response.Status == "ok", "Actual settings bridge remains available");
    }
}
