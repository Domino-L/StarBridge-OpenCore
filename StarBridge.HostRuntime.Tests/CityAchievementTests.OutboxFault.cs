using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime.Achievements;
using StarBridge.HostRuntime.Presence;

// 11-05: a city outbox this build could not read (integrity mismatch, or a token written by a newer
// build before a rollback, e.g. 0.7.4 -> 0.7.3) threw InvalidDataException out of ObserveCity, through
// the sampler's CityArrival callback, and turned the whole Game.log recognition into "storage" on every
// sample. Unknown tokens are now skipped and preserved; a corrupt file stops city uploads only.
internal static partial class CityAchievementTests
{
    internal static async Task OutboxFaultRun()
    {
        var tests = new (string Name, Func<Task> Run)[] {
            ("newer build's unknown token is skipped, preserved and never uploaded", UnknownTokenIsPreserved),
            ("corrupt outbox keeps recognition and other achievements", CorruptOutboxIsIsolated)
        };
        var failed = 0;
        foreach (var (name, run) in tests)
            try { await run(); Console.WriteLine("PASS CITYHOST " + name); }
            catch (Exception error) { failed++; Console.WriteLine("FAIL CITYHOST " + name + ": " + error.Message); }
        Console.WriteLine($"SUMMARY CITYHOST-OUTBOX-FAULT passed={tests.Length - failed} failed={failed}");
        if (failed != 0) throw new Exception("City outbox fault regression failed.");
    }

    private static string? Error(Harness h) => (string?)typeof(GameLogRuntime).GetField("_error",
        System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)!.GetValue(h.Game);
    private static readonly JsonSerializerOptions WebJson = new(JsonSerializerDefaults.Web);
    private static string OutboxDirectory(Harness h) => Path.Combine(h.Root, "achievements-city-pending-v1");
    private static string MainFile(Harness h) => System.IO.Directory.GetFiles(OutboxDirectory(h), "*.json")
        .Single(p => !p.EndsWith(".journey-extra-v1.json", StringComparison.Ordinal));
    private static string Fingerprint(Harness h) => string.Join("|", System.IO.Directory.GetFiles(OutboxDirectory(h)).Order()
        .Select(p => Path.GetFileName(p) + ":" + Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(p)))));

    // An outbox with one pending Lorville, prepared through the real sampler.
    private static Harness Prepared()
    {
        var h = new Harness();
        h.Select(); h.Game.Sample();
        Require(h.Game.DetectedHandle == "Pilot_A", "identity before the outbox exists");
        h.Remote.Offline = true;
        h.Append(Inventory("Stanton1_Lorville"));
        Require(h.Evidence.Count == 1 && h.Read().Pending.Length == 1, "a valid outbox is written first");
        return h;
    }

    private static void RequireRecognitionHealthy(Harness h, string what)
    {
        for (var i = 0; i < 4; i++) h.Game.Sample();
        Require(Error(h) is null, what + ": recognition stays healthy, error=" + Error(h));
        Require(h.Game.DetectedHandle == "Pilot_A", what + ": identity is still published");
        Require(CandidateCount(h) == 0, what + ": the arrival does not repeat on later samples");
    }

    private static async Task UnknownTokenIsPreserved()
    {
        using var h = Prepared();
        // As written by a newer build: one confirmed and one pending token this build does not know.
        var main = MainFile(h);
        var owner = JsonNode.Parse(File.ReadAllBytes(main))!["ownerHash"]!.GetValue<string>();
        var future = new { schemaVersion = 1, handleHash = FirstEntryObservation.HashHandle("Pilot_A"), city = "future-pending", evidence = "RequestLocationInventory" };
        var cities = new { pending = new[] { future }, confirmed = new[] { "future-place" } };
        var integrity = Convert.ToHexString(SHA256.HashData(JsonSerializer.SerializeToUtf8Bytes(new { schemaVersion = 1, owner, cities }, WebJson)));
        File.WriteAllBytes(Path.ChangeExtension(main, ".journey-extra-v1.json"),
            JsonSerializer.SerializeToUtf8Bytes(new { schemaVersion = 1, ownerHash = owner, cities, integrity }, WebJson));

        Require(h.Read().Pending.Select(p => p.City).SequenceEqual(new[] { "lorville" }) && h.Read().Confirmed.Length == 0,
            "this build reads its own entries and skips the unknown ones");
        h.Append(Inventory("Stanton3_Area18"));
        RequireRecognitionHealthy(h, "unknown token");
        Require(h.Evidence.Count == 2 && h.Read().Pending.Select(p => p.City).Order().SequenceEqual(new[] { "area18", "lorville" }),
            "a new arrival is still recorded next to the unknown entries");

        h.Remote.Offline = false;
        await h.Runtime.TickAsync(true);
        Require(h.Remote.Reports == 2 && h.Read().Pending.Length == 0 &&
            h.Read().Confirmed.Order().SequenceEqual(new[] { "area18", "lorville" }), "known cities upload and confirm");
        var extra = JsonNode.Parse(File.ReadAllBytes(Path.ChangeExtension(main, ".journey-extra-v1.json")))!["cities"]!;
        Require(extra["confirmed"]!.AsArray().Select(n => n!.GetValue<string>()).Contains("future-place") &&
            extra["pending"]!.AsArray().Select(n => n!["city"]!.GetValue<string>()).SequenceEqual(new[] { "future-pending" }),
            "unknown entries are written back unchanged for the newer build");
    }

    private static async Task CorruptOutboxIsIsolated()
    {
        using var h = Prepared();
        var main = MainFile(h);
        var node = JsonNode.Parse(File.ReadAllBytes(main))!;
        var integrity = node["integrity"]!.GetValue<string>();
        node["integrity"] = (integrity[0] == '0' ? "1" : "0") + integrity[1..];
        File.WriteAllText(main, node.ToJsonString());
        var thrown = false;
        try { h.Read(); } catch (InvalidDataException) { thrown = true; }
        Require(thrown, "the prepared outbox really is unreadable");
        var before = Fingerprint(h);

        h.Append(Inventory("Stanton3_Area18"));
        RequireRecognitionHealthy(h, "corrupt outbox");
        Require(h.Evidence.Count == 2 && h.Evidence[1].Observation.City == "area18", "the arrival was delivered once");

        // The achievement refresh still reads the account and serves other achievements.
        h.Remote.Offline = false;
        var reads = h.Remote.Reads;
        await h.Runtime.TickAsync(true);
        Require(h.Remote.Reads > reads, "the achievement refresh is not stopped by the city outbox");
        Require(h.Remote.Reports == 0, "nothing is uploaded from an unreadable outbox");
        Require(Fingerprint(h) == before, "the corrupt outbox is never overwritten");
    }
}
