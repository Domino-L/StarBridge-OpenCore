using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;
using StarBridge.Core.Achievements;
using StarBridge.HostRuntime.Achievements;
using StarBridge.NativeBridge;

internal static class CityOutboxCompatibilityTests
{
    private static readonly BridgeAccountContext Owner = new("test", "scm", "synthetic-compat-owner");
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    { PropertyNameCaseInsensitive = false, UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow, MaxDepth = 8 };
    private static string Hash(byte[] bytes) => Convert.ToHexString(SHA256.HashData(bytes));
    private static string OwnerHash => Hash(JsonSerializer.SerializeToUtf8Bytes(new[] { Owner.Environment, Owner.Authority, Owner.Subject }));
    private static string Integrity<T>(string owner, T cities) => Hash(JsonSerializer.SerializeToUtf8Bytes(new { schemaVersion = 1, owner, cities }, Json));
    private static string DirectoryPath(string root) => Path.Combine(root, "achievements-city-pending-v1");
    private static string CityPath(string root) => Path.Combine(DirectoryPath(root), OwnerHash + ".json");
    private static string ExtraPath(string root) => Path.Combine(DirectoryPath(root), OwnerHash + ".journey-extra-v1.json");
    private static CityObservation Observation(string city) => new(1, new string('a', 64), city, "RequestLocationInventory");
    private static void Require(bool value, string reason) { if (!value) throw new Exception(reason); }

    // State.Validate and Read below are copied from fe6c1cfc, 0.7.2.1 CityAchievementOutbox.
    // The observation predicate is frozen too: that version's IsValid accepted only four cities.
    private sealed record LegacyObservation(int SchemaVersion, string HandleHash, string City, string Evidence)
    {
        [JsonIgnore]
        public bool IsValid => SchemaVersion == 1 && HandleHash is { Length: 64 } &&
            HandleHash.All(c => c is >= '0' and <= '9' or >= 'a' and <= 'f') &&
            JourneyAchievementPolicy.IsCity(City) && Evidence is "RequestLocationInventory" or "PLAYER_LOCATION";
    }
    private sealed record LegacyState(LegacyObservation[] Pending, string[] Confirmed)
    {
        internal static LegacyState Empty => new([], []);
        internal void Validate()
        {
            if (Pending is null || Confirmed is null || Pending.Length > 4 || Confirmed.Length > 4 ||
                Pending.Any(p => p is null || !p.IsValid || Confirmed.Contains(p.City)) ||
                Pending.Select(p => p.City).Distinct().Count() != Pending.Length ||
                Confirmed.Any(c => !JourneyAchievementPolicy.IsCity(c)) || Confirmed.Distinct().Count() != Confirmed.Length)
                throw new InvalidDataException("Invalid city outbox.");
        }
    }
    private sealed record LegacySaved(int SchemaVersion, string OwnerHash, LegacyState Cities, string Integrity);
    private static bool Check(string path, bool directory)
    {
        FileAttributes value;
        try { value = File.GetAttributes(path); }
        catch (FileNotFoundException) { return false; }
        catch (DirectoryNotFoundException) { return false; }
        if (value.HasFlag(FileAttributes.ReparsePoint) || value.HasFlag(FileAttributes.Directory) != directory) throw new IOException();
        return true;
    }
    private static LegacyState LegacyRead(string path, string hash)
    {
        Check(Path.GetDirectoryName(path)!, true);
        if (!Check(path, false)) return LegacyState.Empty;
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete);
        if (stream.Length is <= 0 or > 8192) throw new InvalidDataException();
        var bytes = new byte[(int)stream.Length]; stream.ReadExactly(bytes);
        using var document = JsonDocument.Parse(bytes);
        StarBridge.HostRuntime.Profiles.LocalPersonalProfileStore.RejectDuplicates(document.RootElement);
        var data = JsonSerializer.Deserialize<LegacySaved>(bytes, Json);
        if (data is null || data.SchemaVersion != 1 || data.OwnerHash != hash || data.Cities is null ||
            data.Integrity != Integrity(hash, data.Cities)) throw new InvalidDataException();
        data.Cities.Validate();
        return data.Cities;
    }
    private static void InRoot(Action<string> run)
    {
        var root = Path.Combine(Path.GetTempPath(), "sb-outbox-compat-" + Guid.NewGuid().ToString("N"));
        try { Directory.CreateDirectory(root); run(root); }
        finally { Directory.Delete(root, true); }
    }
    internal static void LegacyCompatibility() => InRoot(root =>
    {
        var store = new CityAchievementOutbox(root);
        using (var lease = store.Open(Owner))
            lease.Save(new([Observation("orison"), Observation("station-rr-p6-leo")],
                ["lorville", "area18", "levski", "station-rr-p2-l4", "station-rr-p3-leo", "grimhex"]), () => true);
        var old = LegacyRead(CityPath(root), OwnerHash);
        Require(old.Confirmed.SequenceEqual(new[] { "lorville", "area18" }) && old.Pending.Single().City == "orison", "legacy sees only four cities");
        Require(File.Exists(ExtraPath(root)), "extra file is separate");
        using var reopened = store.Open(Owner);
        Require(reopened.Read().Confirmed.Length == 6 && reopened.Read().Pending.Length == 2, "combined round trip");
    });
    internal static void AssertLegacy(string root, BridgeAccountContext owner, int pending, int confirmed)
    {
        var hash = Hash(JsonSerializer.SerializeToUtf8Bytes(new[] { owner.Environment, owner.Authority, owner.Subject }));
        var state = LegacyRead(Path.Combine(DirectoryPath(root), hash + ".json"), hash);
        Require(state.Pending.Length == pending && state.Confirmed.Length == confirmed, "released reader partition counts");
    }
    private static void WriteRecord(string path, CityAchievementOutbox.State state, string? owner = null)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        owner ??= OwnerHash;
        File.WriteAllBytes(path, JsonSerializer.SerializeToUtf8Bytes(new
        { schemaVersion = 1, ownerHash = owner, cities = state, integrity = Integrity(owner, state) }, Json));
    }
    private static CityAchievementOutbox.State ReadExtra(string root)
    {
        using var doc = JsonDocument.Parse(File.ReadAllBytes(ExtraPath(root)));
        return doc.RootElement.GetProperty("cities").Deserialize<CityAchievementOutbox.State>(Json)!;
    }
    private static CityAchievementOutbox.State Read(string root)
    { using var lease = new CityAchievementOutbox(root).Open(Owner); return lease.Read(); }
    private static void Reject(Action run)
    {
        try { run(); } catch (Exception e) when (e is InvalidDataException or JsonException or IOException) { return; }
        throw new Exception("invalid record accepted");
    }
    private static void SameState(CityAchievementOutbox.State actual, CityAchievementOutbox.State expected)
    {
        Require(actual.Pending.OrderBy(p => p.City).SequenceEqual(expected.Pending.OrderBy(p => p.City)) &&
            actual.Confirmed.Order().SequenceEqual(expected.Confirmed.Order()), "all pending payloads and confirmation markers survive");
    }
    internal static void ExtraCapacity() => InRoot(root =>
    {
        var tokens = JourneyAchievementPolicy.Tokens.Where(t => !JourneyAchievementPolicy.IsCity(t)).ToArray();
        Require(tokens.Length == 25 && tokens.Last() == "grimhex", "fixed extra token capacity");
        using (var lease = new CityAchievementOutbox(root).Open(Owner))
            lease.Save(new(tokens.Select(Observation).ToArray(), []), () => true);
        Require(ReadExtra(root).Pending.Length == 25 && new FileInfo(ExtraPath(root)).Length <= 8192, "25 pending fit byte cap");
        SameState(Read(root), new(tokens.Select(Observation).ToArray(), []));
        AssertLegacy(root, Owner, 0, 0);
        using (var lease = new CityAchievementOutbox(root).Open(Owner)) lease.Save(new([], tokens), () => true);
        SameState(Read(root), new([], tokens));
        Require(ReadExtra(root).Confirmed.Length == 25, "25 confirmed round trip");
        // An older client may continue writing the original four-city record independently.
        WriteRecord(CityPath(root), new([Observation("orison")], ["lorville"]));
        Require(Read(root).Confirmed.Length == 26 && ReadExtra(root).Confirmed.Length == 25, "older client cannot erase extra markers");
    });
    internal static void ExtraGuards()
    {
        var extra = JourneyAchievementPolicy.Tokens.Where(t => !JourneyAchievementPolicy.IsCity(t)).ToArray();
        var invalid = new CityAchievementOutbox.State[] {
            new(extra.Append(extra[0]).Select(Observation).ToArray(), []), new([], [.. extra, extra[0]]),
            new([Observation("lorville")], []), new([], ["area18"]),
            new([Observation("levski")], ["levski"]), new([Observation("levski") with { HandleHash = "bad" }], []),
            new([], ["Bad Token"]), new([Observation("levski") with { City = "x", HandleHash = "bad" }], [])
        };
        // A well-formed token this build does not know (a newer build's, after a rollback) is
        // skipped and written back unchanged, not treated as corruption.
        InRoot(root =>
        {
            WriteRecord(ExtraPath(root), new([], ["station-rr-p1-l1", "levski"]));
            Require(Read(root).Confirmed.SequenceEqual(new[] { "levski" }), "unknown extra token is skipped");
            using (var lease = new CityAchievementOutbox(root).Open(Owner))
                lease.Save(new([Observation("station-rr-p2-l4")], ["levski"]), () => true);
            var saved = ReadExtra(root);
            Require(saved.Confirmed.Contains("station-rr-p1-l1") && saved.Pending.Single().City == "station-rr-p2-l4",
                "unknown extra token survives a save next to new entries");
        });
        foreach (var state in invalid) InRoot(root =>
        {
            WriteRecord(ExtraPath(root), state);
            var bytes = File.ReadAllBytes(ExtraPath(root));
            Reject(() => Read(root));
            Reject(() => { using var lease = new CityAchievementOutbox(root).Open(Owner); lease.Save(new([], []), () => true); });
            Require(bytes.SequenceEqual(File.ReadAllBytes(ExtraPath(root))) && !File.Exists(CityPath(root)), "invalid extra is never overwritten");
        });
        foreach (var fault in new[] { "owner", "integrity", "duplicate", "size", "schema" }) InRoot(root =>
        {
            WriteRecord(ExtraPath(root), new([], ["levski"]), fault == "owner" ? new string('0', 64) : null);
            var text = File.ReadAllText(ExtraPath(root));
            if (fault == "integrity") text = text.Replace("levski", "station-rr-p2-l4");
            if (fault == "duplicate") text = text.Replace("\"schemaVersion\":1", "\"schemaVersion\":1,\"schemaVersion\":1");
            if (fault == "size") text = new string(' ', 8193);
            if (fault == "schema") text = text.Replace("\"schemaVersion\":1", "\"schemaVersion\":2");
            File.WriteAllText(ExtraPath(root), text);
            Reject(() => Read(root));
            Reject(() => { using var lease = new CityAchievementOutbox(root).Open(Owner); lease.Save(new([], []), () => true); });
            Require(File.ReadAllText(ExtraPath(root)) == text, "extra guard preserves " + fault);
        });
    }
    private static CityAchievementOutbox.State Mixed => new(
        [Observation("orison"), Observation("levski"), Observation("station-rr-p2-l4") with { Evidence = "PLAYER_LOCATION" }],
        ["lorville", "area18", "station-rr-p3-leo", "station-rr-p6-leo"]);
    internal static void Migration() => InRoot(root =>
    {
        WriteRecord(CityPath(root), Mixed);
        SameState(Read(root), Mixed);
        AssertLegacy(root, Owner, 1, 2);
        SameState(ReadExtra(root), new(Mixed.Pending.Where(p => !JourneyAchievementPolicy.IsCity(p.City)).ToArray(),
            Mixed.Confirmed.Where(c => !JourneyAchievementPolicy.IsCity(c)).ToArray()));
        var original = File.ReadAllBytes(CityPath(root)); var extra = File.ReadAllBytes(ExtraPath(root));
        SameState(Read(root), Mixed);
        Require(original.SequenceEqual(File.ReadAllBytes(CityPath(root))) && extra.SequenceEqual(File.ReadAllBytes(ExtraPath(root))), "reopen does not rewrite settled files");
    });
    internal static void InterruptedMigration()
    {
        foreach (var stage in new[] { "before-extra", "after-extra" }) InRoot(root =>
        {
            WriteRecord(CityPath(root), Mixed);
            var original = File.ReadAllBytes(CityPath(root));
            if (stage == "before-extra") WriteRecord(ExtraPath(root), new([], []));
            var lockedPath = stage == "before-extra" ? ExtraPath(root) : CityPath(root);
            using (new FileStream(lockedPath, FileMode.Open, FileAccess.Read, FileShare.Read))
            {
                Reject(() => Read(root));
                Require(original.SequenceEqual(File.ReadAllBytes(CityPath(root))), "failed migration preserves source: " + stage);
                if (stage == "after-extra") Require(ReadExtra(root).Pending.Length == 2 && ReadExtra(root).Confirmed.Length == 2, "destination durable before source replace");
            }
            SameState(Read(root), Mixed);
            AssertLegacy(root, Owner, 1, 2);
        });
        InRoot(root =>
        {
            WriteRecord(CityPath(root), Mixed);
            // A previous interrupted attempt (or subsequent receipt) may already confirm a token.
            WriteRecord(ExtraPath(root), new([Observation("station-rr-p3-leo"), Mixed.Pending.Single(p => p.City == "station-rr-p2-l4")], ["levski"]));
            var expected = Mixed with { Pending = Mixed.Pending.Where(p => p.City != "levski").ToArray(), Confirmed = [.. Mixed.Confirmed, "levski"] };
            SameState(Read(root), expected);
            SameState(Read(root), expected);
            AssertLegacy(root, Owner, 1, 2);
        });
    }
    internal static void CorruptMigration()
    {
        foreach (var corruptExtra in new[] { false, true }) InRoot(root =>
        {
            WriteRecord(CityPath(root), Mixed);
            var path = corruptExtra ? ExtraPath(root) : CityPath(root);
            if (corruptExtra) WriteRecord(path, new([], ["levski"]));
            File.WriteAllText(path, File.ReadAllText(path).Replace("levski", "station-rr-p1-l2"));
            var original = File.ReadAllBytes(CityPath(root));
            var damaged = File.ReadAllBytes(path);
            Reject(() => Read(root));
            Reject(() => { using var lease = new CityAchievementOutbox(root).Open(Owner); lease.Save(new([], []), () => true); });
            Require(original.SequenceEqual(File.ReadAllBytes(CityPath(root))) && damaged.SequenceEqual(File.ReadAllBytes(path)), "corrupt source or target blocks all migration writes");
            if (!corruptExtra) Require(!File.Exists(ExtraPath(root)), "corrupt mixed source is never migrated");
        });
    }
    internal static Task Run()
    {
        var cases = new (string Name, Action Run)[] {
            ("released reader", LegacyCompatibility), ("extra capacity and older writer", ExtraCapacity),
            ("extra validation integrity and owner", ExtraGuards), ("mixed migration", Migration),
            ("interrupted migration recovery", InterruptedMigration), ("corrupt migration preservation", CorruptMigration)
        };
        var failed = 0;
        foreach (var (name, run) in cases)
            try { run(); Console.WriteLine("PASS OUTBOX " + name); }
            catch (Exception error) { failed++; Console.WriteLine("FAIL OUTBOX " + name + ": " + error.Message); }
        Console.WriteLine($"SUMMARY OUTBOX passed={cases.Length - failed} failed={failed}");
        if (failed != 0) throw new Exception("Outbox compatibility regression failed.");
        return Task.CompletedTask;
    }
}
