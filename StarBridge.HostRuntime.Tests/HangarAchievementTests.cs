using StarBridge.Core.Achievements;
using StarBridge.HostRuntime.Achievements;
using StarBridge.HostRuntime.Hangar;
using StarBridge.NativeBridge;

internal static class HangarAchievementTests
{
    private sealed class Cloud : IAchievementRemote
    {
        internal bool Offline; internal int Reports;
        private readonly Dictionary<BridgeAccountContext, AchievementSnapshot> _saved = [];
        public Task<AchievementSnapshot> ReadAchievementsAsync(BridgeAccountContext owner, long generation, CancellationToken token)
        {
            if (Offline) throw new IOException();
            return Task.FromResult(_saved.GetValueOrDefault(owner) ?? new(1, []));
        }
        public Task<AchievementReceipt> ObserveFirstEntryAsync(BridgeAccountContext owner, long generation, FirstEntryObservation observation, CancellationToken token) => throw new Exception("No game evidence in hangar tests");
        public Task<HangarAchievementReceipt> ObserveHangarAsync(BridgeAccountContext owner, long generation, HangarAchievementObservation observation, CancellationToken token)
        {
            Reports++; var previous = _saved.GetValueOrDefault(owner) ?? new(1, []);
            var progress = new Dictionary<string, int>(previous.Progress ?? []); var earned = new Dictionary<string, DateTimeOffset>(previous.EarnedAt); var newly = new List<string>();
            foreach (var id in HangarAchievementPolicy.Ids)
            {
                var peak = Math.Max(progress.GetValueOrDefault(id), HangarAchievementPolicy.Progress(id, observation.Counts)); progress[id] = peak;
                for (var rank = 1; rank <= 5; rank++)
                    if (peak >= HangarAchievementPolicy.Thresholds(id)[rank - 1] && earned.TryAdd($"{id}-{rank}", DateTimeOffset.UtcNow)) newly.Add($"{id}-{rank}");
            }
            _saved[owner] = new(1, earned, progress);
            return Task.FromResult(new HangarAchievementReceipt(1, earned, progress, newly.ToArray()));
        }
    }
    internal static async Task Run()
    {
        Classifier();
        var root = Path.Combine(Path.GetTempPath(), "sb-hangar-awards-" + Guid.NewGuid().ToString("N")); Directory.CreateDirectory(root);
        try
        {
            var owner = new BridgeAccountContext("test", "scm", "synthetic-hangar"); var current = (Context: (BridgeAccountContext?)owner, Generation: 1L);
            HangarAchievementEvidence? evidence = new(owner, 1, new(1, 1, 20, 20, 6)); var cloud = new Cloud { Offline = true };
            var notices = new List<(string Id, int Rank)>();
            AchievementRuntime Create(string directory) => new(new(directory), cloud, () => current, () => null, _ => { }, startTimer: false,
                hangarStore: new(directory), hangarEvidence: () => evidence, seriesEarned: (_, id, rank, _) => notices.Add((id, rank)));
            using (var runtime = Create(root)) await runtime.TickAsync(true);
            Require(Directory.GetFiles(Path.Combine(root, "achievements-hangar-pending-v1"), "*.json").Length == 1 && cloud.Reports == 0,
                "Complete simultaneous peaks persist before unavailable cloud IO");
            evidence = null; cloud.Offline = false;
            using (var restarted = Create(root))
            {
                await restarted.TickAsync(true);
                Require(notices.Count == 3 && notices.All(n => n.Rank == 5), "One five-level jump presents only the highest new rank for each series");
                var read = await restarted.DispatchAsync(BridgeEnvelope.Request("achievements.read", "read", 1, new { schemaVersion = 1 }, owner), default);
                Require(read.Response.Payload.GetProperty("earnedAt").EnumerateObject().Count() == 15 && read.Response.Payload.GetProperty("progress").GetProperty("hangar-paths").GetInt32() == 6,
                    "All fifteen rank dates and independent peaks are restored through the ordinary account bridge");
                evidence = new(owner, 1, new(1, 1, 1, 1, 1)); await restarted.TickAsync(true);
                Require(cloud.Reports == 1 && notices.Count == 3, "Downsize never removes rank history, reduces progress, or repeats a popup");
                current = (owner with { Subject = "other-synthetic" }, 2); restarted.Invalidate(2); await restarted.TickAsync(true);
                var other = await restarted.DispatchAsync(BridgeEnvelope.Request("achievements.read", "other", 2, new { schemaVersion = 1 }, current.Context), default);
                Require(other.Response.Payload.GetProperty("earnedAt").EnumerateObject().Count() == 0, "Changing accounts discards old inventory evidence");
            }
            current = (owner, 3); evidence = null;
            var device = Path.Combine(root, "device"); using var restored = Create(device); await restored.TickAsync(true);
            Require(notices.Count == 3 && cloud.Reports == 1, "Another device restores all ranks without manufacturing new awards");
            Console.WriteLine("PASS five-rank hangar: full inventory, duplicates/ground/partial, offline restart, fifteen dates, three highest notices, downsizing and cross-device/account isolation");
        }
        finally { Directory.Delete(root, true); }
    }
    private static void Classifier()
    {
        var classifier = new HangarAchievementClassifier("英文飞船名\t定位\t隐藏标签\nA\tCombat\t\nB\tIndustrial / Mining\t\nC\tCompetition\t\nRover\tCombat\tvehicle\n");
        var ships = new[] { Ship("A"), Ship("A"), Ship("B"), Ship("C"), Ship("Rover"), Ship("Unknown") };
        var snapshot = new LocalHangarSnapshot(1, DateTimeOffset.UtcNow, "test", ships, false, [Ship("Old")]);
        var observed = classifier.Capture(snapshot, name => "catalog-" + name.ToLowerInvariant());
        Require(observed == new HangarAchievementObservation(1, 1, 4, 3, 3), "Copies count separately, models deduplicate, racing survives, and ground/former/unknown are excluded");
        Require(classifier.Capture(snapshot with { Partial = true }, n => "catalog-" + n.ToLowerInvariant()) is null, "Partial scans never merge historical simultaneous ownership");
        Require(new HangarAchievementClassifier(null).Capture(snapshot, n => n) is null,
            "Missing optional catalog is unknown progress rather than a confirmed empty fleet");
        Require(!new HangarAchievementObservation(1, 1, 1, 2, 1).IsValid, "Inconsistent count payload is invalid");
        var invalid = new AchievementSnapshot(1, new() { ["hangar-home-2"] = DateTimeOffset.UtcNow }, new() { ["hangar-home"] = 1 });
        var rejected = false;
        try { invalid.Validate(); } catch (InvalidDataException) { rejected = true; }
        Require(rejected, "An inconsistent remote rank cannot reach the celebration sink");
        var editions = new HangarAchievementClassifier("英文飞船名\t定位\t隐藏标签\nAvenger Titan\tTransport\t\nAvenger Titan Renegade\tTransport\t\nSabre\tCombat\t\nSabre Comet\tCombat\t\nP-72 Archimedes\tCompetition\tvehicle\nP-72 Archimedes Emerald\tCompetition\tvehicle\nMPUV Cargo\tTransport\tvehicle\nRover\tGround\tvehicle\n");
        var editionShips = new[] { "Avenger Titan", "Avenger Titan Renegade", "Sabre", "Sabre Comet", "P-72 Archimedes", "P-72 Archimedes Emerald", "MPUV Cargo", "Rover" }.Select(Ship).ToArray();
        var editionSnapshot = snapshot with { Ships = editionShips };
        Require(editions.Capture(editionSnapshot, n => "catalog-" + string.Concat(n.Where(char.IsLetterOrDigit)).ToLowerInvariant()) == new HangarAchievementObservation(1, 1, 7, 4, 3),
            "Livery/loadout editions retain physical ship counts but share models; verified snubs count even with broad vehicle tags");
    }
    private static LocalHangarShip Ship(string name) => new(Guid.NewGuid().ToString("N"), "test", name, null, null, DateTimeOffset.UtcNow);
    private static void Require(bool ok, string message) { if (!ok) throw new Exception(message); }
}
