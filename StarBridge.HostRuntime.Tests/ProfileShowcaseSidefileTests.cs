using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Text.Json.Serialization;
using StarBridge.Core.Profiles;
using StarBridge.HostRuntime.Profiles;
using StarBridge.NativeBridge;

internal static partial class ProfileShowcaseSidefileTests
{
    // Copied from fe6c1cfc LocalPersonalProfileStore: independent 0.7.2.1 disk contract.
    private sealed record OldLayout(string Id, int Span, bool IsVisible, int Position,
        [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] IReadOnlyList<string>? FavoriteShipIds = null);
    private sealed record OldPlayStyle(
        [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] IReadOnlyList<string>? Roles = null,
        [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] IReadOnlyList<string>? Interests = null,
        [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] IReadOnlyList<string>? Support = null);
    private sealed record OldTimeWindow(IReadOnlyList<int> Days, string StartTime, string EndTime);
    private sealed record OldSchedule(string TimeZoneId, string Rhythm, IReadOnlyList<OldTimeWindow> Windows);
    private sealed record OldContent(string CallSign, string Introduction, int AvatarStyle,
        string WallpaperId, IReadOnlyList<OldLayout> Modules, IReadOnlyList<string>? FavoriteShipIds,
        [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] OldPlayStyle? PlayStyle = null,
        [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] OldSchedule? Schedule = null,
        [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingDefault)] bool PreserveEmptyFields = false);
    private sealed record OldSnapshot(long Revision, DateTimeOffset? SavedAt, string? OperationId, OldContent? Content);
    private sealed record OldSavedFile(int SchemaVersion, string OwnerHash, OldSnapshot Snapshot, string Integrity);
    private static readonly JsonSerializerOptions OldJson = new(JsonSerializerDefaults.Web) {
        PropertyNameCaseInsensitive = false, UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow, MaxDepth = 12
    };
    private static string Hash(byte[] data) => Convert.ToHexString(SHA256.HashData(data));
    private static string OldIntegrity(string owner, OldSnapshot snapshot) =>
        Hash(JsonSerializer.SerializeToUtf8Bytes(new { schemaVersion = 1, owner, snapshot }, OldJson));
    private static readonly BridgeAccountContext Owner = new("Test", "https://authority.invalid", "synthetic-sidefile");
    private static LocalProfileContent Content => new("展柜兼容", "简介", 0, "none", [], null,
        Showcases: [new("achievements", true)], AchievementShowcase: ["first-flight"]);
    private static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
    private sealed class Fixture : IDisposable
    {
        internal readonly string Root = Path.Combine(Path.GetTempPath(), "StarBridge-PSIDEFILE-" + Guid.NewGuid().ToString("N"));
        internal LocalPersonalProfileStore Store => new(Root);
        internal string Main => Directory.GetFiles(Path.Combine(Root, "personal-profile-local-v1"), "*.json").Single();
        internal string Side => Path.ChangeExtension(Main, ".showcases");
        internal LocalProfileSnapshot Save(LocalProfileContent? content = null, long revision = 0, string? operation = null,
            Func<bool>? canCommit = null) => Store.Save(Owner, revision, operation ?? Guid.NewGuid().ToString("N"), content ?? Content, canCommit ?? (() => true));
        public void Dispose() { if (Directory.Exists(Root)) Directory.Delete(Root, true); }
    }
    internal static Task Run()
    {
        var cases = new (string Name, Action Run)[] {
            ("old Disallow contract and integrity", OldReader),
            ("m101 reads showcases after an explicit default save", M101ReadsShowcasesAfterExplicitClear),
            ("older main-only save invalidates explicit defaults", OldSaveInvalidatesFieldStates),
            ("mismatched commits keep the main content", FieldStateInterruption),
            ("unusable field state files leave profile content readable", UnusableFieldStates),
            ("main role lives only in the sidefile", MainRole),
            ("missing sidefile", () => Damaged("missing")),
            ("invalid JSON", () => Damaged("json")),
            ("wrong owner with valid hash", () => Damaged("owner")),
            ("invalid integrity", () => Damaged("integrity")),
            ("duplicate keys", () => Damaged("duplicate")),
            ("nested duplicate keys", () => Damaged("nested-duplicate")),
            ("unknown fields", () => Damaged("unknown")),
            ("oversized sidefile", () => Damaged("size")),
            ("invalid showcase with valid hash", () => Damaged("content")),
            ("unsupported schema", () => Damaged("schema")),
            ("build61 read then split save", Build61),
            ("old client writes, preserve, clear, retry and conflict", OldClientEdit),
            ("sidefile failure leaves committed main readable", SideFailure),
            ("main commit failure leaves both files unchanged", MainFailure),
            ("shared main lock protects both files", SharedLock),
            ("base integrity still fails closed", BaseIntegrity),
            ("existing storage guards", () => LocalPersonalProfileTests.Storage().GetAwaiter().GetResult()),
            ("failed B preserves original A replay", () => HalfCommitReplay(false)),
            ("failed B rejects changed A replay", () => HalfCommitReplay(true)),
            ("build61 inline layout and side achievements survive ordinary save", () => MixedBuild61(false)),
            ("build61 inline achievements and side layout survive ordinary save", () => MixedBuild61(true)),
            ("side commit failure retries without another revision", SideRetry),
            ("pre-operation sidefile remains readable", LegacySidefile),
            ("operation identity is integrity protected", () => Damaged("operation")),
            ("invalid operation with valid hash", () => Damaged("invalid-operation")),
            ("missing sidefile after first main commit is repairable", MissingSideRetry),
            ("build61 side directory failure preserves inline values and retry", () => InlineSideFailure(false, true)),
            ("build61 blocked old side cannot revive inline clear", () => InlineSideFailure(true, false)),
            ("build61 side directory failure preserves inline clear", () => InlineSideFailure(true, true)),
            ("build61 main migration failure preserves inline values and retry", () => InlineMainFailure(false)),
            ("build61 main migration failure preserves inline clear and retry", () => InlineMainFailure(true)),
            ("build61 original A replay migrates without revision change", InlineOriginalReplay),
            ("build61 changed A layout replay conflicts", () => InlineChangedReplay(false)),
            ("build61 changed A achievements replay conflicts", () => InlineChangedReplay(true))
        };
        var failures = 0;
        foreach (var (name, run) in cases)
        {
            try { run(); Console.WriteLine("PASS PSIDEFILE " + name); }
            catch (Exception e) { failures++; Console.WriteLine("FAIL PSIDEFILE " + name + ": " + e); }
        }
        Console.WriteLine($"SUMMARY PSIDEFILE passed={cases.Length - failures} failed={failures}");
        if (failures != 0) throw new Exception("PSIDEFILE regression failed");
        return Task.CompletedTask;
    }
    private static OldSavedFile ReadOld(string path)
    {
        var bytes = File.ReadAllBytes(path);
        var file = JsonSerializer.Deserialize<OldSavedFile>(bytes, OldJson)!;
        Check(file.SchemaVersion == 1 && file.Integrity == OldIntegrity(file.OwnerHash, file.Snapshot), "old integrity mismatch");
        Check(bytes.SequenceEqual(JsonSerializer.SerializeToUtf8Bytes(file, OldJson)), "old contract bytes differ");
        return file;
    }
    private static void OldReader()
    {
        foreach (var content in new[] { Content, Content with {
            Modules = [new("favorite-ships", 1, true, 0, [new string('a', 32)])], FavoriteShipIds = [new string('a', 32)],
            PlayStyle = new(["pilot"], ["exploration"], ["medical"]),
            Schedule = new("America/Regina", "weekends", [new([1, 3], "23:30", "02:15")]), PreserveEmptyFields = true
        } })
        {
            using var f = new Fixture();
            var saved = f.Save(content);
            var old = ReadOld(f.Main);
            Check(old.Snapshot.Revision == saved.Revision && old.Snapshot.Content!.CallSign == "展柜兼容", "old reader lost base content");
            Check(File.Exists(f.Side) && !f.Side.EndsWith(".json"), "sidefile name");
            var read = f.Store.Read(Owner);
            Check(read.Content!.Showcases!.SequenceEqual(Content.Showcases!) &&
                read.Content.AchievementShowcase!.SequenceEqual(Content.AchievementShowcase!), "sidefile round trip");
        }
    }
    private static void RehashSide(JsonObject side)
    {
        var payload = new JsonObject {
            ["schemaVersion"] = side["schemaVersion"]!.DeepClone(), ["ownerHash"] = side["ownerHash"]!.DeepClone(),
            ["showcases"] = side["showcases"]?.DeepClone(), ["achievementShowcase"] = side["achievementShowcase"]?.DeepClone()
        };
        if (side["operationId"] is { } operation) payload["operationId"] = operation.DeepClone();
        side["integrity"] = Hash(JsonSerializer.SerializeToUtf8Bytes(payload, OldJson));
    }
    private static void Damaged(string mode)
    {
        using var f = new Fixture(); f.Save();
        var side = JsonNode.Parse(File.ReadAllBytes(f.Side))!.AsObject();
        switch (mode)
        {
            case "missing": File.Delete(f.Side); break;
            case "json": File.WriteAllText(f.Side, "{"); break;
            case "size": File.WriteAllText(f.Side, new string(' ', 65537)); break;
            case "duplicate": File.WriteAllText(f.Side, side.ToJsonString()[..^1] + ",\"schemaVersion\":1}"); break;
            case "nested-duplicate": File.WriteAllText(f.Side, side.ToJsonString().Replace("\"isVisible\":true", "\"isVisible\":true,\"isVisible\":true")); break;
            default:
                if (mode == "owner") { side["ownerHash"] = new string('A', 64); RehashSide(side); }
                if (mode == "integrity") side["integrity"] = new string('0', 64);
                if (mode == "content") { side["achievementShowcase"] = new JsonArray("BAD"); RehashSide(side); }
                if (mode == "schema") { side["schemaVersion"] = 2; RehashSide(side); }
                if (mode == "unknown") side["unexpected"] = true;
                if (mode == "operation") side["operationId"] = Guid.NewGuid().ToString("N");
                if (mode == "invalid-operation") { side["operationId"] = "invalid"; RehashSide(side); }
                File.WriteAllBytes(f.Side, JsonSerializer.SerializeToUtf8Bytes(side, OldJson)); break;
        }
        var read = f.Store.Read(Owner);
        Check(read.Revision == 1 && read.Content!.CallSign == "展柜兼容" &&
            read.Content.Showcases is null && read.Content.AchievementShowcase is null, "sidefile damage broke base or retained fields");
        ReadOld(f.Main);
    }
    private static void Build61()
    {
        using var f = new Fixture(); f.Save();
        var path = f.Main;
        var old = JsonNode.Parse(File.ReadAllBytes(path))!.AsObject();
        var snapshot = new LocalProfileSnapshot(1, DateTimeOffset.UnixEpoch, Guid.NewGuid().ToString("N"), Content);
        var owner = old["ownerHash"]!.GetValue<string>();
        old["snapshot"] = JsonSerializer.SerializeToNode(snapshot, OldJson);
        old["integrity"] = Hash(JsonSerializer.SerializeToUtf8Bytes(new { schemaVersion = 1, owner, snapshot }, OldJson));
        File.WriteAllBytes(path, JsonSerializer.SerializeToUtf8Bytes(old, OldJson));
        if (File.Exists(f.Side)) File.Delete(f.Side);
        var read = f.Store.Read(Owner);
        Check(read.Revision == 1 && read.Content!.Showcases!.SequenceEqual(Content.Showcases!) &&
            read.Content.AchievementShowcase!.SequenceEqual(Content.AchievementShowcase!), "build61 lost inline fields");
        f.Save(Content with { Showcases = null, AchievementShowcase = null }, 1);
        Check(ReadOld(path).Snapshot.Revision == 2, "split changed revision");
        Check(f.Store.Read(Owner).Content!.AchievementShowcase!.SequenceEqual(Content.AchievementShowcase!), "split lost fields");
    }
    private static void OldClientEdit()
    {
        using var f = new Fixture(); f.Save();
        var old = ReadOld(f.Main);
        var snapshot = old.Snapshot with { Revision = 2, OperationId = Guid.NewGuid().ToString("N"),
            Content = old.Snapshot.Content! with { Introduction = "旧版编辑" } };
        File.WriteAllBytes(f.Main, JsonSerializer.SerializeToUtf8Bytes(old with {
            Snapshot = snapshot, Integrity = OldIntegrity(old.OwnerHash, snapshot) }, OldJson));
        var read = f.Store.Read(Owner);
        Check(read.Revision == 2 && read.Content!.Introduction == "旧版编辑" &&
            read.Content.Showcases!.SequenceEqual(Content.Showcases!), "old client edit invalidated sidefile");
        var operation = Guid.NewGuid().ToString("N");
        var missing = Content with { Showcases = null, AchievementShowcase = null };
        f.Save(missing, 2, operation);
        Check(f.Save(missing, 2, operation).Revision == 3, "retry incremented revision");
        Check(f.Store.Read(Owner).Content!.Showcases!.SequenceEqual(Content.Showcases!), "missing fields cleared");
        try { f.Save(missing, 1); throw new Exception("stale revision accepted"); }
        catch (LocalProfileException e) when (e.Code == "profile_local.conflict") { }
        f.Save(Content with { Showcases = [], AchievementShowcase = [] }, 3);
        f.Save(missing, 4);
        Check(f.Store.Read(Owner).Content is { Showcases.Count: 0, AchievementShowcase.Count: 0 }, "clear/preserve changed");
        ReadOld(f.Main);
    }
    private static void SideFailure()
    {
        using var f = new Fixture(); f.Save();
        var operation = Guid.NewGuid().ToString("N");
        File.Delete(f.Side); Directory.CreateDirectory(f.Side);
        try { f.Save(Content with { Showcases = [] }, 1, operation); throw new Exception("sidefile write unexpectedly succeeded"); }
        catch (LocalProfileException e) when (e.Code == "profile_local.write_failed") { }
        Check(ReadOld(f.Main).Snapshot is { Revision: 2 } s && s.OperationId == operation, "main commit missing");
        Check(f.Store.Read(Owner).Revision == 2, "bad side path broke read");
    }
    private static void MainFailure()
    {
        using var f = new Fixture(); f.Save();
        var path = f.Main;
        var bytes = File.ReadAllBytes(path);
        var side = File.ReadAllBytes(f.Side);
        var operation = Guid.NewGuid().ToString("N");
        using (var block = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read))
        {
            try { f.Save(Content with { Showcases = [], AchievementShowcase = [] }, 1, operation); throw new Exception("main write unexpectedly succeeded"); }
            catch (LocalProfileException e) when (e.Code == "profile_local.write_failed") { }
        }
        Check(File.ReadAllBytes(path).SequenceEqual(bytes), "failed main changed bytes");
        Check(File.ReadAllBytes(f.Side).SequenceEqual(side), "main failure changed sidefile");
        Check(f.Store.Read(Owner) is { Revision: 1, Content.Showcases.Count: 1, Content.AchievementShowcase.Count: 1 },
            "main failure changed visible showcases");
        Check(!Directory.GetFiles(Path.GetDirectoryName(path)!, "*.tmp").Any(), "temporary files leaked");
        Check(f.Save(Content with { Showcases = [], AchievementShowcase = [] }, 1, operation).Revision == 2, "partial save retry failed");
        ReadOld(path);
    }
    private static void SharedLock()
    {
        using var f = new Fixture(); f.Save();
        var main = File.ReadAllBytes(f.Main); var side = File.ReadAllBytes(f.Side);
        using (var gate = new FileStream(f.Main + ".lock", FileMode.Open, FileAccess.ReadWrite, FileShare.None))
        {
            try { f.Save(Content with { Showcases = [] }, 1); throw new Exception("locked save succeeded"); }
            catch (LocalProfileException e) when (e.Code == "profile_local.write_failed") { }
        }
        Check(File.ReadAllBytes(f.Main).SequenceEqual(main) && File.ReadAllBytes(f.Side).SequenceEqual(side), "lock failed to protect pair");
    }
    private static void BaseIntegrity()
    {
        using var f = new Fixture(); f.Save();
        var main = JsonNode.Parse(File.ReadAllBytes(f.Main))!.AsObject();
        main["integrity"] = "invalid";
        File.WriteAllBytes(f.Main, JsonSerializer.SerializeToUtf8Bytes(main, OldJson));
        try { f.Store.Read(Owner); throw new Exception("invalid main accepted"); }
        catch (LocalProfileException e) when (e.Code == "profile_local.read_failed") { }
    }
}
