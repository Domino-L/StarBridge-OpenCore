using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Notifications;
using StarBridge.NativeBridge;

internal static class NotificationReconciliationWriteTests
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    private static readonly BridgeAccountContext Owner = new("fixture", "fixture", "write-recovery-synthetic");
    private static readonly string OwnerHash = Hash(JsonSerializer.SerializeToUtf8Bytes(new[] { Owner.Environment, Owner.Authority, Owner.Subject }));
    private static readonly string Extended = NotificationPolicyStore.Organization("EXTENDED", DateTimeOffset.UnixEpoch);
    private static int checks;
    private static string Hash(byte[] bytes) => Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
    private static string FileFor(string root, int version) => Path.Combine(root, $"notification-policies-v{version}", OwnerHash + ".json");
    private static void Check(bool ok, string message) { checks++; if (!ok) throw new Exception(message); }
    private static string Canon(object value) => JsonSerializer.Serialize(value, Json);

    // Valid signed synthetic documents carry opaque extensions at every level.
    private static NotificationPolicyStore Seed(string root, int padding)
    {
        var store = new NotificationPolicyStore(root);
        store.Save(Owner, 0, Guid.NewGuid().ToString("N"), [new(Extended, NotificationSourceMode.DoNotDisturb) {
            TypeRules = [new("chat", "disabled") { Extra = new() { ["futureType"] = JsonSerializer.SerializeToElement(7) } }],
            QuietHours = new(true) { Extra = new() { ["futureQuiet"] = JsonSerializer.SerializeToElement(8) } },
            Extra = new() { ["futureRule"] = JsonSerializer.SerializeToElement("preserve") }
        }], () => true, true);
        var file = JsonNode.Parse(File.ReadAllText(FileFor(root, 2)))!;
        file["futureFile"] = "preserve";
        file["snapshot"]!["futureSnapshot"] = new string('x', padding);
        file["integrity"] = Hash(JsonSerializer.SerializeToUtf8Bytes(new {
            schemaVersion = 2, owner = OwnerHash, snapshot = file["snapshot"],
            legacyFingerprint = file["legacyFingerprint"]!.GetValue<string>()
        }, Json));
        File.WriteAllText(FileFor(root, 2), file.ToJsonString());
        return store;
    }
    private static NotificationPolicyRule[] Legacy(string root)
    {
        var rules = Enumerable.Range(1, 32).Select(i => new NotificationPolicyRule(
            NotificationPolicyStore.Organization("ADDED-" + i, DateTimeOffset.UnixEpoch), NotificationSourceMode.ImportantOnly))
            .Append(new("room", NotificationSourceMode.ImportantOnly)).ToArray();
        var snapshot = new NotificationPolicySnapshot(1, Guid.NewGuid().ToString("N"), rules);
        var integrity = Hash(JsonSerializer.SerializeToUtf8Bytes(new { owner = OwnerHash, snapshot }, Json));
        Directory.CreateDirectory(Path.GetDirectoryName(FileFor(root, 1))!);
        File.WriteAllBytes(FileFor(root, 1), JsonSerializer.SerializeToUtf8Bytes(new { schemaVersion = 1, owner = OwnerHash, snapshot, integrity }, Json));
        return rules;
    }
    private static void Complete(NotificationPolicySnapshot read, NotificationPolicyRule[] legacy, int padding)
    {
        Check(read.Rules.Length == legacy.Length + 1 && legacy.All(r => read.For(r.Source) == r.Mode), "Every v1 source and mode survives");
        var extended = read.Rule(Extended);
        Check(extended.Mode == NotificationSourceMode.Normal && extended.TypeRules![0].Mode == "disabled" && extended.QuietHours!.Enabled,
            "Extended settings survive the base-mode reset");
        Check(extended.Extra!["futureRule"].GetString() == "preserve" && extended.TypeRules![0].Extra!["futureType"].GetInt32() == 7 &&
            extended.QuietHours!.Extra!["futureQuiet"].GetInt32() == 8 && read.Extra!["futureSnapshot"].GetString()!.Length == padding,
            "All opaque snapshot/rule/type/quiet extensions survive");
        Check(read.SuppressionRevisions?.ContainsKey(Extended) == true && legacy.All(r => read.SuppressionRevision(r.Source) == read.Revision),
            "Existing and reconciled suppression history survives");
    }
    internal static async Task Run(string root)
    {
        checks = 0;
        await ByteBudget(Path.Combine(root, "near-limit"));
        foreach (var fault in new[] { "io", "permission", "size" }) await WriteFailure(Path.Combine(root, fault), fault);
        Console.WriteLine($"PASS F4: {checks} assertions, 0 failed");
    }
    private static async Task ByteBudget(string root)
    {
        var store = Seed(root, 129000);
        var initial = File.ReadAllBytes(FileFor(root, 2));
        Check(initial.Length is > 125000 and <= 131072, "Valid v2 is near the ordinary byte limit");
        var legacy = Legacy(root); var v1 = File.ReadAllBytes(FileFor(root, 1));
        Check(v1.Length <= 32768, "Legacy document is independently valid");
        var read = store.Read(Owner); Complete(read, legacy, 129000);
        var merged = File.ReadAllBytes(FileFor(root, 2));
        Check(merged.Length is > 131072 and <= 262144, "Reconciliation persists above 128 KiB within combined budget");
        Check(Canon(new NotificationPolicyStore(root).Read(Owner)) == Canon(read), "Large reconciled v2 reopens without another revision");
        var saved = store.Save(Owner, read.Revision, Guid.NewGuid().ToString("N"), read.Rules.Select(r => r.Source == "room"
            ? r with { Mode = NotificationSourceMode.Normal } : r).ToArray(), () => true);
        Check(saved.Rules.Length == read.Rules.Length && saved.For("room") == NotificationSourceMode.Normal, "Non-growing edit above 128 KiB succeeds");
        var before = File.ReadAllBytes(FileFor(root, 2));
        try {
            store.Save(Owner, saved.Revision, Guid.NewGuid().ToString("N"), saved.Rules.Select(r => r.Source == Extended
                ? r with { TypeRules = [new("announcement", "disabled")] } : r).ToArray(), () => true, true);
            Check(false, "Growing ordinary save must fail");
        } catch (NotificationPolicySaveException) { Check(before.SequenceEqual(File.ReadAllBytes(FileFor(root, 2))), "Growth rejection preserves v2 bytes"); }
        Check(v1.SequenceEqual(File.ReadAllBytes(FileFor(root, 1))) && JsonNode.Parse(File.ReadAllText(FileFor(root, 2)))!["futureFile"]!.GetValue<string>() == "preserve",
            "Legacy bytes and file extensions survive saves");
        await Dispatch(root, false, 0, "ok");
    }
    private static async Task WriteFailure(string root, string fault)
    {
        var padding = fault == "size" ? 260000 : 100;
        var store = Seed(root, padding); var legacy = Legacy(root);
        var v1 = File.ReadAllBytes(FileFor(root, 1)); var v2 = File.ReadAllBytes(FileFor(root, 2));
        FileStream? held = null;
        try {
            if (fault == "io") held = new FileStream(FileFor(root, 2), FileMode.Open, FileAccess.Read, FileShare.Read);
            if (fault == "permission") File.SetAttributes(FileFor(root, 2), FileAttributes.ReadOnly);
            var read = store.Read(Owner); Complete(read, legacy, padding);
            Check(read.Revision == 2 && new NotificationPolicyStore(root).Read(Owner).Revision == 2, "Failed write leaves retryable stable revision: " + fault);
            await Dispatch(root, false, 0, "ok");
            await Dispatch(root, true, read.Revision, "error", "notificationPolicies.save_failed");
            Check(v1.SequenceEqual(File.ReadAllBytes(FileFor(root, 1))) && v2.SequenceEqual(File.ReadAllBytes(FileFor(root, 2))), "Failed read/save never updates either file or fingerprint: " + fault);
            Check(Directory.GetFiles(Path.GetDirectoryName(FileFor(root, 2))!, "*.tmp").Length == 0, "Failed repair cleans its temporary file: " + fault);
        } finally {
            held?.Dispose();
            if (fault == "permission") File.SetAttributes(FileFor(root, 2), FileAttributes.Normal);
        }
        if (fault == "size") return;
        // Save retries reconciliation first, then commits the user's edit.
        await Dispatch(root, true, 2, "ok");
        var recovered = new NotificationPolicyStore(root).Read(Owner);
        Check(recovered.Revision == 3 && recovered.For("room") == NotificationSourceMode.Normal && recovered.Rule(Extended).QuietHours!.Enabled,
            "Next successful save repairs and commits the edit: " + fault);
        var bytes = File.ReadAllBytes(FileFor(root, 2));
        Check(new NotificationPolicyStore(root).Read(Owner).Revision == 3 && bytes.SequenceEqual(File.ReadAllBytes(FileFor(root, 2))), "Successful repair updates fingerprint once: " + fault);
        Check(v1.SequenceEqual(File.ReadAllBytes(FileFor(root, 1))), "Recovery never modifies v1: " + fault);
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
    private static async Task Dispatch(string root, bool save, long revision, string status, string? code = null)
    {
        using var settings = new NotificationSettingsBridgeDispatcher(root, () => 1);
        using var bridge = new NotificationPolicyBridgeDispatcher(settings, new DirectoryReader(), () => (Owner, 1));
        object body = save ? new { schemaVersion = 1, expectedRevision = revision, operationId = Guid.NewGuid().ToString("N"),
            rules = new[] { new { sourceRef = "room", mode = "normal" } } } : new { schemaVersion = 1 };
        var response = (await bridge.DispatchAsync(BridgeEnvelope.Request("notificationPolicies." + (save ? "save" : "read"),
            Guid.NewGuid().ToString("N"), 1, body, Owner))).Response;
        Check(response.Status == status, "Actual settings bridge status: " + (save ? "save" : "read"));
        if (code != null) Check(response.Error?.Code == code, "Save failure has a distinct error code");
    }
}
