using System.Text;
using StarBridge.Core.Achievements;
using StarBridge.HostRuntime.Achievements;
using StarBridge.HostRuntime.Presence;
using StarBridge.NativeBridge;

internal static class CityAchievementTests
{
    private static readonly BridgeAccountContext Owner = new("test", "scm", "synthetic-city-owner");
    private static readonly DateTimeOffset Now = DateTimeOffset.Parse("2026-10-28T12:00:30Z");
    private sealed class Clock : TimeProvider
    {
        internal DateTimeOffset UtcNow = Now;
        public override DateTimeOffset GetUtcNow() => UtcNow;
        internal void Advance(int seconds) => UtcNow = UtcNow.AddSeconds(seconds);
    }
    private sealed class Cloud : IAchievementRemote
    {
        internal bool Offline, LoseReceipt, IncludeStanton, HangarOffline;
        internal int Reports, Reads;
        internal int HangarReports;
        internal Exception? CityFailure;
        internal string? FailedCity;
        internal Action? BeforeReport;
        internal Action? BeforeReceipt;
        internal readonly Dictionary<BridgeAccountContext, Dictionary<string, DateTimeOffset>> Earned = [];
        public Task<AchievementSnapshot> ReadAchievementsAsync(BridgeAccountContext owner, long generation, CancellationToken token)
        {
            Reads++;
            if (Offline) throw new IOException("synthetic outage");
            return Task.FromResult(new AchievementSnapshot(1, new(Earned.GetValueOrDefault(owner) ?? [])));
        }
        public Task<AchievementReceipt> ObserveFirstEntryAsync(BridgeAccountContext owner, long generation, FirstEntryObservation observation, CancellationToken token) =>
            Task.FromResult(new AchievementReceipt(1, new() { ["first-entry"] = Now }, false));
        public Task<HangarAchievementReceipt> ObserveHangarAsync(BridgeAccountContext owner, long generation, HangarAchievementObservation observation, CancellationToken token)
        {
            HangarReports++;
            if (HangarOffline) throw new IOException("synthetic hangar outage");
            return Task.FromResult(new HangarAchievementReceipt(1, new() { ["hangar-home-1"] = Now },
                new() { ["hangar-home"] = 1, ["hangar-collection"] = 1, ["hangar-paths"] = 1 }, []));
        }
        public Task<CityAchievementReceipt> ObserveCityAsync(BridgeAccountContext owner, long generation, CityObservation observation, CancellationToken token)
        {
            Require(observation.IsValid, "bounded city payload");
            if (Offline) throw new IOException("synthetic outage");
            Reports++;
            BeforeReport?.Invoke();
            if (CityFailure is not null && (FailedCity is null || FailedCity == observation.City)) throw CityFailure;
            if (!Earned.TryGetValue(owner, out var earned)) Earned[owner] = earned = [];
            var added = new List<string>();
            var id = JourneyAchievementPolicy.Id(observation.City);
            if (earned.TryAdd(id, Now)) added.Add(id);
            if (IncludeStanton && earned.TryAdd(JourneyAchievementPolicy.StantonId, Now)) added.Add(JourneyAchievementPolicy.StantonId);
            BeforeReceipt?.Invoke();
            if (LoseReceipt) { LoseReceipt = false; throw new IOException("synthetic lost receipt"); }
            return Task.FromResult(new CityAchievementReceipt(1, new(earned), added.ToArray(),
                new() { [JourneyAchievementPolicy.StantonId] = earned.Keys.Count(k => k != JourneyAchievementPolicy.StantonId) }));
        }
    }
    private sealed class Harness : IDisposable
    {
        internal readonly string Root;
        internal string Log => Path.Combine(Root, "StarCitizen", "LIVE", "Game.log");
        internal (BridgeAccountContext? Context, long Generation) Current = (Owner, 1);
        internal string Expected = "Pilot_A";
        internal readonly Cloud Remote;
        internal readonly GameLogRuntime Game;
        internal readonly AchievementRuntime Runtime;
        internal readonly List<CityArrivalEvidence> Evidence = [];
        internal readonly List<string> Celebrated = [];
        internal Harness(Cloud? cloud = null, string? root = null, string? history = null)
        {
            Root = root ?? Path.Combine(Path.GetTempPath(), "sb-city-" + Guid.NewGuid().ToString("N"));
            Remote = cloud ?? new();
            Directory.CreateDirectory(Path.GetDirectoryName(Log)!);
            File.WriteAllText(Log, Identity + Join + (history ?? ""), new UTF8Encoding(false));
            Game = new(new GameLogSettingsStore(Root), () => Current, () => Expected,
                () => new("running", Log, Now.AddMinutes(-1), "synthetic-process"), new Clock(), false);
            Runtime = new(new(Root), Remote, () => Current, () => null, _ => { }, new Clock(), false,
                cityStore: new(Root), seriesEarned: (_, id, rank, _) => { Require(rank == 0, "city rank"); Celebrated.Add(id); });
            Game.CityArrival += e => { Evidence.Add(e); Runtime.ObserveCity(e); };
        }
        internal void Select() => Game.Dispatch(BridgeEnvelope.Request("gameLog.select", Guid.NewGuid().ToString("N"),
            Current.Generation, new { schemaVersion = 1, path = Log }, Current.Context));
        internal void Append(string lines) { File.AppendAllText(Log, lines); Game.Sample(); }
        internal CityAchievementOutbox.State Read(BridgeAccountContext? owner = null)
        { using var lease = new CityAchievementOutbox(Root).Open(owner ?? Current.Context!); return lease.Read(); }
        public void Dispose() { Game.Dispose(); Runtime.Dispose(); if (Directory.Exists(Root)) Directory.Delete(Root, true); }
    }
    private const string Stamp = "<2026-10-28T12:00:20Z> ";
    private const string Identity = Stamp + "[Notice] nickname=\"Pilot_A\" playerGEID=12345\n";
    private const string Join = Stamp + "<Join PU> connected to shard[pub_sc_alpha_apse1_123]\n";
    private static string Inventory(string code, string player = "Pilot_A") => Stamp +
        $"<RequestLocationInventory> Player[{player}] requested inventory for Location[{code}]\n";
    private static string Explicit(string code, string player = "Pilot_A") => Stamp + $"PLAYER_LOCATION player={player} location={code}\n";
    private static void Require(bool value, string reason) { if (!value) throw new Exception(reason); }

    internal static Task Catalog()
    {
        var index = GameLogLocationNameIndex.Load();
        var cases = new (string Code, string City)[] {
            ("Stanton1_Lorville", "lorville"), ("Hospital_Stanton1_Lorville", "lorville"),
            ("Stanton3_Area18", "area18"), ("Hospital_Stanton3_Area18", "area18"),
            ("FleetWeek_Area18_Tower", "area18"), ("BevicCenter", "area18"), ("BevicCenter_Analytics", "area18"),
            ("Stanton2_Orison", "orison"), ("Hospital_Stanton2_Orison", "orison"),
            ("VisionCenter", "orison"), ("VisionCenter_Analytics", "orison"),
            ("Stanton4_NewBabbage", "new-babbage"), ("Hospital_Stanton4_NewBabbage", "new-babbage"),
            ("TobinExpoCenter", "new-babbage")
        };
        foreach (var (code, city) in cases)
        {
            Require(index.FindCity(code) == city, "catalog " + code);
            Require(index.FindCity(" loc_" + code.ToUpperInvariant() + " [42] ") == city, "normalization " + code);
        }
        foreach (var code in new[] { "EverusHarbor", "PortTressler", "GrimHEX", "Stanton1", "Synthetic_Lorville_Hospital" })
            Require(index.FindCity(code) is null, "non-city " + code);
        using var input = new MemoryStream(Encoding.UTF8.GetBytes("""
            {"schemaVersion":1,"entries":[
            {"canonicalCode":"Stanton1_Lorville","nameEn":"Lorville"},
            {"canonicalCode":"Synthetic_Leaf","nameEn":"Leaf","parentCode":"Stanton1_Lorville"}],
            "aliases":[{"code":"OOC_Alias","canonicalCode":"Synthetic_Leaf","normalizedCode":"Alias2"}]}
            """));
        var synthetic = GameLogLocationNameIndex.Load(input);
        Require(synthetic.FindCity("LOC_OOC_Alias [9]") == "lorville" && synthetic.FindCity("Alias2") == "lorville", "catalog aliases");
        Require(GameLogLocationNameIndex.Load(null).FindCity("Stanton1_Lorville") is null, "absent catalog");
        return Task.CompletedTask;
    }
    internal static Task EvidenceGuards()
    {
        using var h = new Harness(history: Inventory("Stanton1_Lorville") + Explicit("Stanton2_Orison"));
        h.Select(); h.Game.Sample();
        Require(h.Evidence.Count == 0 && h.Read().Pending.Length == 0, "historical catch-up and restored snapshot never grant");
        h.Append(Inventory("Hospital_Stanton1_Lorville") + Explicit("VisionCenter"));
        Require(h.Evidence.Count == 2 && h.Evidence[0].Observation.Evidence == "RequestLocationInventory" &&
            h.Evidence[1].Observation.Evidence == "PLAYER_LOCATION" && h.Read().Pending.Length == 2, "95 and 90 are event evidence");
        h.Append(Inventory("Stanton3_Area18", "Other_Pilot") + Explicit("Stanton4_NewBabbage", "Other_Pilot"));
        Require(h.Evidence.Count == 2, "other player");
        var route = Stamp + "<Calculate Route> | AUTH | AEGS_Avenger_Titan_123[1]| Projected Start Location is Stanton4_NewBabbage for route to destination Stanton3_Area18\n";
        var arrival = Stamp + "<Quantum Drive Arrived - Arrived at Final Destination> CSCItemNavigation::OnQuantumDriveArrived\n";
        var parser = new StarBridge.Core.Parsing.RegexLogEventParser();
        Require(parser.TryParse(route)?.LocationEvidenceScore == 60 && parser.TryParse(arrival)?.LocationEvidenceScore == 45, "negative fixtures exercise real parser scores");
        h.Append(route +
            Stamp + "<Quantum Drive Arrived - Arrived at Final Destination> CSCItemNavigation::OnQuantumDriveArrived\n");
        Require(h.Evidence.Count == 2, "60 route and 45 arrival cannot grant");
        h.Expected = "Other_Pilot"; h.Append(Inventory("Stanton4_NewBabbage"));
        Require(h.Evidence.Count == 2, "verified handle mismatch");
        h.Expected = "Pilot_A";
        h.Append(Stamp + "<Channel Disconnection> gamerules=\"SC_Default\" reason=\"Player requested disconnect\"\n" + Inventory("Stanton4_NewBabbage"));
        Require(h.Evidence.Count == 2, "disconnected");
        h.Append(Join + Inventory("Stanton4_NewBabbage") +
            Stamp + "<Channel Disconnection> gamerules=\"SC_Default\" reason=\"Player requested disconnect\"\n");
        Require(h.Evidence.Count == 3, "later disconnect must not erase already connected arrival");
        return Task.CompletedTask;
    }
    internal static Task CatchupAndPartialLines()
    {
        using var h = new Harness(history: new string('x', 16 * 1024 * 1024) + "\n" + Inventory("Stanton1_Lorville"));
        h.Select(); // First bounded read cannot reach EOF.
        h.Append(Explicit("Stanton2_Orison")); // Still catching up; this line is not live.
        Require(h.Evidence.Count == 0, "lines appended before catch-up completes are historical");
        h.Append(Inventory("Stanton3_Area18"));
        Require(h.Evidence.Count == 1, "post-catch-up line is live");
        using var partial = new Harness(history: Inventory("Stanton1_Lorville").TrimEnd('\n'));
        partial.Select(); partial.Append("\n");
        Require(partial.Evidence.Count == 0, "old incomplete tail is not a new arrival");
        partial.Append(Inventory("Stanton1_Lorville"));
        Require(partial.Evidence.Count == 1, "new complete line after tail");
        return Task.CompletedTask;
    }
    private static void StartLiveChunk(Harness h, string tail = "")
    {
        h.Select(); h.Game.Sample();
        Require(h.Game.DetectedHandle == "Pilot_A", "initial identity read reaches EOF");
        h.Append(Inventory("Stanton1_Lorville") + new string('x', 16 * 1024 * 1024) + "\n" + tail);
        Require(h.Game.DetectedHandle is null && h.Evidence.Count == 0 && h.Read().Pending.Length == 0,
            "live candidate awaits complete identity verification across chunks");
    }
    private static void FinishLiveChunk(Harness h)
    {
        // The payload is just over one bounded read; extra samples also check one-time delivery.
        for (var i = 0; i < 4; i++) h.Game.Sample();
    }
    private static int CandidateCount(Harness h) =>
        ((System.Collections.ICollection)typeof(GameLogRuntime).GetField("_cityArrivals",
            System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)!.GetValue(h.Game)!).Count;
    private static void RequireReading(Harness h)
    {
        var observation = (GameLogIdentityObservation)typeof(GameLogRuntime).GetField("_observation",
            System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)!.GetValue(h.Game)!;
        Require(observation.State == "reading" && h.Evidence.Count == 0 && h.Read().Pending.Length == 0,
            "each appended chunk must remain reading without early delivery");
    }
    internal static Task RepeatedLiveCityIsBounded()
    {
        using var h = new Harness();
        h.Select(); h.Game.Sample();
        Require(h.Game.DetectedHandle == "Pilot_A", "initial EOF before live repeated arrivals");
        for (var round = 0; round < 8; round++)
        {
            h.Append(Inventory("Stanton1_Lorville") + new string('x', 16 * 1024 * 1024) + "\n");
            RequireReading(h);
            Require(CandidateCount(h) == 1, $"same city round {round}: candidates={CandidateCount(h)}, expected=1");
        }
        FinishLiveChunk(h);
        Require(h.Game.DetectedHandle == "Pilot_A" && CandidateCount(h) == 0 && h.Evidence.Count == 1 &&
            h.Evidence[0].Observation.City == "lorville" && h.Read().Pending.Length == 1,
            "EOF delivers the repeated city once and clears candidates");
        return Task.CompletedTask;
    }
    internal static Task RepeatedFourCitiesAreBounded()
    {
        using var h = new Harness();
        h.Select(); h.Game.Sample();
        Require(h.Game.DetectedHandle == "Pilot_A", "initial EOF before live mixed arrivals");
        var codes = new[] { "Stanton1_Lorville", "Stanton3_Area18", "Stanton2_Orison", "Stanton4_NewBabbage" };
        for (var round = 0; round < 14; round++)
        {
            // Repeat Lorville at capacity too: it must never evict another city's valid arrival.
            var code = codes[round < 12 ? round % codes.Length : 0];
            h.Append(Inventory(code, "Other_Pilot") + Inventory(code) +
                new string('x', 16 * 1024 * 1024) + "\n");
            RequireReading(h);
            var expected = Math.Min(round + 1, 4);
            Require(CandidateCount(h) == expected,
                $"mixed city round {round}: candidates={CandidateCount(h)}, expected={expected}");
        }
        FinishLiveChunk(h);
        Require(h.Game.DetectedHandle == "Pilot_A" && CandidateCount(h) == 0 && h.Evidence.Count == 4 &&
            h.Evidence.GroupBy(e => e.Observation.City).All(group => group.Count() == 1) &&
            h.Evidence.Select(e => e.Observation.City).Order().SequenceEqual(JourneyAchievementPolicy.Cities.Order()) &&
            h.Read().Pending.Length == 4, "EOF delivers every city once, preserves all four and clears candidates");
        return Task.CompletedTask;
    }
    internal static Task LiveChunkArrival()
    {
        using var h = new Harness();
        StartLiveChunk(h); FinishLiveChunk(h);
        Require(h.Game.DetectedHandle == "Pilot_A" && h.Evidence.Count == 1 &&
            h.Evidence[0].Observation.City == "lorville" && h.Read().Pending.Length == 1,
            "live arrival survives bounded reads and enters evidence/outbox exactly once");
        return Task.CompletedTask;
    }
    internal static Task LiveChunkAccountChange()
    {
        using var h = new Harness();
        StartLiveChunk(h);
        h.Current = (Owner with { Subject = "synthetic-chunk-other" }, 2);
        h.Select(); FinishLiveChunk(h);
        Require(h.Game.DetectedHandle == "Pilot_A" && h.Evidence.Count == 0 &&
            h.Read().Pending.Length == 0 && h.Read(Owner).Pending.Length == 0 && h.Remote.Reports == 0,
            "account/generation change discards the unverified candidate for both owners");
        return Task.CompletedTask;
    }
    internal static Task LiveChunkSourceReset()
    {
        using var h = new Harness();
        StartLiveChunk(h);
        File.WriteAllText(h.Log, Identity + Join, new UTF8Encoding(false)); // Truncation resets this same path.
        FinishLiveChunk(h);
        Require(h.Game.DetectedHandle == "Pilot_A" && h.Evidence.Count == 0 &&
            h.Read().Pending.Length == 0 && h.Remote.Reports == 0, "source reset discards the unverified candidate");
        h.Append(Inventory("Stanton3_Area18"));
        Require(h.Evidence.Count == 1 && h.Evidence[0].Observation.City == "area18" &&
            h.Read().Pending.Length == 1, "new source still accepts its own live arrival");
        return Task.CompletedTask;
    }
    internal static Task LiveChunkIdentityConflict()
    {
        using var h = new Harness();
        StartLiveChunk(h, Identity.Replace("Pilot_A", "Other_Pilot").Replace("12345", "67890"));
        FinishLiveChunk(h);
        Require(h.Game.DetectedHandle is null && h.Evidence.Count == 0 &&
            h.Read().Pending.Length == 0 && h.Remote.Reports == 0, "later conflicting identity discards the candidate");
        return Task.CompletedTask;
    }
    internal static async Task DurableQueueAndCelebration()
    {
        using var h = new Harness(); h.Select(); h.Remote.Offline = true;
        h.Append(Inventory("Stanton1_Lorville") + Inventory("Stanton3_Area18"));
        h.Append(Inventory("Stanton1_Lorville"));
        await h.Runtime.TickAsync(true);
        Require(h.Read().Pending.Length == 2 && h.Remote.Reports == 0, "offline multi-city durable queue");
        h.Runtime.Dispose();
        var celebrated = new List<string>();
        using var restarted = new AchievementRuntime(new(h.Root), h.Remote, () => h.Current, () => null, _ => { }, new Clock(), false,
            cityStore: new(h.Root), seriesEarned: (_, id, rank, _) => { Require(rank == 0, "rank zero"); celebrated.Add(id); });
        h.Remote.Offline = false; h.Remote.IncludeStanton = true;
        await restarted.TickAsync(true);
        Require(h.Remote.Reports == 2 && h.Read().Pending.Length == 0 && h.Read().Confirmed.Length == 2, "restart drains every city");
        Require(celebrated.SequenceEqual(new[] { "journey-lorville", "journey-stanton", "journey-area18" }), "only receipt newlyEarned celebrates aggregate");
        restarted.ObserveCity(new(Owner, 1, new(1, FirstEntryObservation.HashHandle("Pilot_A"), "lorville", "PLAYER_LOCATION")));
        await restarted.TickAsync(true);
        Require(h.Remote.Reports == 2 && celebrated.Count == 3, "confirmed repeat suppressed");
        h.Current = (Owner with { Subject = "synthetic-city-other" }, 2); restarted.Invalidate(2);
        restarted.ObserveCity(new(Owner, 1, new(1, FirstEntryObservation.HashHandle("Pilot_A"), "orison", "PLAYER_LOCATION")));
        restarted.ObserveCity(new(h.Current.Context, 2, new(1, FirstEntryObservation.HashHandle("Pilot_A"), "lorville", "PLAYER_LOCATION")));
        await restarted.TickAsync(true);
        Require(h.Remote.Reports == 3 && h.Read().Confirmed.SequenceEqual(new[] { "lorville" }) && h.Read(Owner).Confirmed.Length == 2,
            "account isolation and stale evidence rejection");
    }
    internal static async Task LostReceiptAndOwnerRace()
    {
        using var h = new Harness(); h.Select(); h.Remote.LoseReceipt = true;
        h.Append(Inventory("Stanton2_Orison")); await h.Runtime.TickAsync(true);
        Require(h.Read().Pending.Length == 1 && h.Celebrated.Count == 0, "lost receipt remains pending without local award");
        await h.Runtime.TickAsync(true);
        Require(h.Remote.Reports == 1 && h.Read().Confirmed.Length == 1 && h.Celebrated.Count == 0, "cloud read confirms silently");
        h.Append(Inventory("Stanton4_NewBabbage"));
        h.Remote.BeforeReceipt = () => h.Current = (Owner with { Subject = "synthetic-raced-owner" }, 2);
        await h.Runtime.TickAsync(true);
        Require(h.Celebrated.Count == 0 && h.Read(Owner).Pending.Length == 1 && h.Read().Pending.Length == 0, "late old-owner receipt is ignored");
    }
    internal static async Task ArrivalDuringReport()
    {
        using var h = new Harness(); h.Select();
        h.Append(Inventory("Stanton1_Lorville"));
        h.Remote.BeforeReceipt = () => {
            h.Remote.BeforeReceipt = null;
            h.Runtime.ObserveCity(new(Owner, 1, new(1, FirstEntryObservation.HashHandle("Pilot_A"), "area18", "PLAYER_LOCATION")));
        };
        await h.Runtime.TickAsync(true);
        Require(h.Read().Pending.Length == 1, "arrival during an in-flight report remains queued");
        await h.Runtime.TickAsync();
        Require(h.Read().Pending.Length == 0 && h.Remote.Reports == 2,
            "next ordinary tick drains a newly queued city without the five-minute refresh delay");
    }
    internal static Task ReceiptValidationAndDelivery()
    {
        var receipt = new CityAchievementReceipt(1, new() { ["journey-orison"] = Now, ["journey-stanton"] = Now },
            ["journey-orison", "journey-stanton"], new() { ["journey-stanton"] = 4 });
        receipt.Validate();
        foreach (var invalid in new[] {
            receipt with { NewlyEarned = ["unknown"] }, receipt with { NewlyEarned = ["journey-orison", "journey-orison"] },
            receipt with { EarnedAt = [] }, receipt with { Progress = new() { ["journey-stanton"] = 5 } },
            receipt with { SchemaVersion = 2 } })
        {
            try { invalid.Validate(); throw new Exception("invalid receipt accepted"); } catch (InvalidDataException) { }
        }
        var notices = new Sink();
        using var delivery = new AchievementCelebrationDelivery(() => (Owner, 1));
        delivery.Configure(notices);
        foreach (var id in JourneyAchievementPolicy.Ids)
        {
            delivery.SeriesEarned(1, id, 0, Now);
            delivery.SeriesEarned(1, id, 0, Now);
        }
        Require(notices.Items.Select(n => n.AchievementId).SequenceEqual(JourneyAchievementPolicy.Ids) &&
            notices.Items.All(n => n.CanPresent && n.Rank == 0), "all journey ids reach existing delivery once");
        return Task.CompletedTask;
    }
    internal static async Task IndependentHangarReceipts()
    {
        foreach (var offline in new[] { false, true })
        {
            var root = Path.Combine(Path.GetTempPath(), "sb-city-hangar-" + Guid.NewGuid().ToString("N"));
            try
            {
                var remote = new Cloud { HangarOffline = offline };
                AchievementSnapshot? confirmed = null;
                using var runtime = new AchievementRuntime(new(root), remote, () => (Owner, 1), () => null, _ => { }, new Clock(), false,
                    cityStore: new(root), hangarStore: new(root),
                    hangarEvidence: () => new(Owner, 1, new(1, 1, 1, 1, 1)), confirmed: (_, snapshot, _) => confirmed = snapshot);
                runtime.ObserveCity(new(Owner, 1, new(1, FirstEntryObservation.HashHandle("Pilot_A"), "orison", "PLAYER_LOCATION")));
                await runtime.TickAsync(true);
                var value = confirmed ?? throw new Exception("Missing confirmed snapshot");
                Require(value.EarnedAt.ContainsKey("journey-orison") &&
                    value.Progress?.GetValueOrDefault("journey-stanton") == 1,
                    "same-tick hangar success/failure preserves independently acknowledged journey progress");
                Require(offline ? !value.EarnedAt.ContainsKey("hangar-home-1") : value.EarnedAt.ContainsKey("hangar-home-1"),
                    "hangar status remains independent");
            }
            finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
        }
    }
    internal static async Task CityFailureIsolationAndBackoff()
    {
        foreach (var status in new int?[] { 400, 401, 403, 429, 503, null })
        {
            var root = Path.Combine(Path.GetTempPath(), "sb-city-retry-" + Guid.NewGuid().ToString("N"));
            try
            {
                var clock = new Clock();
                var remote = new Cloud { FailedCity = "new-babbage", CityFailure = status == 429
                    ? new StarBridge.HostRuntime.Auth.ScmApiRateLimitException("synthetic rate limit", null)
                    : new HttpRequestException("synthetic city failure", null, status is { } code ? (System.Net.HttpStatusCode)code : null) };
                var store = new CityAchievementOutbox(root);
                var old = new CityObservation(1, FirstEntryObservation.HashHandle("Pilot_A"), "new-babbage", "RequestLocationInventory");
                using (var lease = store.Open(Owner)) lease.Save(new([old], []), () => true);
                AchievementSnapshot? published = null;
                using var runtime = new AchievementRuntime(new(root), remote, () => (Owner, 1), () => null, _ => { }, clock, false,
                    cityStore: store, hangarStore: new(root), hangarEvidence: () => new(Owner, 1, new(1, 1, 1, 1, 1)),
                    confirmed: (_, snapshot, _) => published = snapshot);
                runtime.ObserveCity(new(Owner, 1, old with { City = "orison", Evidence = "PLAYER_LOCATION" }));
                await runtime.TickAsync();
                Require(remote.Reports == 2 && remote.HangarReports == 1 && published?.EarnedAt.ContainsKey("hangar-home-1") == true &&
                    published.EarnedAt.ContainsKey("journey-orison"), "city failure preserves other city, hangar and read publication");
                using (var lease = store.Open(Owner)) Require(lease.Read().Pending.SequenceEqual(new[] { old }), "failed legacy observation retained verbatim");
                var response = await runtime.DispatchAsync(BridgeEnvelope.Request("achievements.read", "city-read", 1, new { schemaVersion = 1 }, Owner), default);
                Require(response.Response.Status == BridgeResponseStatuses.Ok && !response.Response.Payload.GetProperty("refreshFailed").GetBoolean(),
                    "successful read does not show refreshFailed for city upload failure");
                Require(remote.Reports == 2, "forced page refresh respects city deadline");
                var rejected = status is >= 400 and < 500 and not 401;
                var delay = rejected ? 300 : 4;
                for (var second = 2; second < delay; second += 2)
                {
                    clock.Advance(2); await runtime.TickAsync();
                    Require(remote.Reports == 2, "two-second timer cannot bypass upload backoff");
                }
                clock.Advance(2); await runtime.TickAsync();
                Require(remote.Reports == 3, "exactly one retry at deadline");
                var secondDelay = rejected ? 300 : 8;
                clock.Advance(secondDelay - 1); await runtime.TickAsync(true);
                Require(remote.Reports == 3, "read success and force do not reset failed city's counter");
                remote.CityFailure = null;
                clock.Advance(1); await runtime.TickAsync();
                Require(remote.Reports == 4, "recovery drains the retained city");
                using (var lease = store.Open(Owner)) Require(lease.Read().Pending.Length == 0 && lease.Read().Confirmed.Contains("new-babbage"), "recovered receipt commits");
            }
            finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
        }
    }
    internal static async Task CityCancellationAndOwnerChange()
    {
        foreach (var cancel in new[] { true, false })
        foreach (var throws in new[] { true, false })
        {
            var root = Path.Combine(Path.GetTempPath(), "sb-city-cancel-" + Guid.NewGuid().ToString("N"));
            try
            {
                using var cts = new CancellationTokenSource();
                (BridgeAccountContext? Context, long Generation) current = (Owner, 1);
                var remote = new Cloud(); var published = 0; var celebrations = 0;
                remote.BeforeReport = () => {
                    if (cancel) cts.Cancel(); else current = (Owner with { Subject = "changed" }, 2);
                    if (throws) throw cancel ? new OperationCanceledException(cts.Token) : new IOException("obsolete account failure");
                };
                using var runtime = new AchievementRuntime(new(root), remote, () => current, () => null, _ => { }, new Clock(), false,
                    cityStore: new(root), hangarStore: new(root), hangarEvidence: () => new(Owner, 1, new(1, 1, 1, 1, 1)),
                    confirmed: (_, _, _) => published++, seriesEarned: (_, _, _, _) => celebrations++);
                runtime.ObserveCity(new(Owner, 1, new(1, FirstEntryObservation.HashHandle("Pilot_A"), "orison", "PLAYER_LOCATION")));
                var cancelled = false;
                try { await runtime.TickAsync(true, cts.Token); }
                catch (OperationCanceledException) { cancelled = true; }
                Require(cancelled == cancel, "caller cancellation propagates");
                using var lease = new CityAchievementOutbox(root).Open(Owner);
                Require(lease.Read().Pending.Length == 1 && lease.Read().Confirmed.Length == 0 && published == 0 && celebrations == 0 &&
                    remote.HangarReports == 0, "cancelled/obsolete city cannot commit, celebrate, publish or continue to hangar");
            }
            finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
        }
    }
    internal static async Task CityRetryCeilingAndNewEvidence()
    {
        var root = Path.Combine(Path.GetTempPath(), "sb-city-ceiling-" + Guid.NewGuid().ToString("N"));
        try
        {
            var clock = new Clock();
            var remote = new Cloud { FailedCity = "new-babbage", CityFailure = new IOException("synthetic network outage") };
            (BridgeAccountContext? Context, long Generation) current = (Owner, 1);
            var old = new CityObservation(1, FirstEntryObservation.HashHandle("Pilot_A"), "new-babbage", "RequestLocationInventory");
            using var runtime = new AchievementRuntime(new(root), remote, () => current, () => null, _ => { }, clock, false, cityStore: new(root));
            runtime.ObserveCity(new(Owner, 1, old));
            await runtime.TickAsync();
            var reports = 1;
            foreach (var delay in new[] { 4, 8, 16, 30, 30 })
            {
                clock.Advance(delay - 1); await runtime.TickAsync(true);
                Require(remote.Reports == reports, "retry never precedes exponential deadline");
                clock.Advance(1); await runtime.TickAsync();
                Require(remote.Reports == ++reports, "one upload per deadline, capped at thirty seconds");
            }
            runtime.ObserveCity(new(Owner, 1, old with { City = "area18" }));
            await runtime.TickAsync();
            Require(remote.Reports == ++reports && remote.Earned[Owner].ContainsKey("journey-area18"),
                "new evidence wakes another city without bypassing failed city's deadline");
            current = (Owner, 2); runtime.Invalidate(2);
            await runtime.TickAsync();
            Require(remote.Reports == ++reports, "new generation owns a fresh retry sequence");
            clock.Advance(3); await runtime.TickAsync(true);
            Require(remote.Reports == reports, "new generation starts at four seconds");
            remote.CityFailure = null; clock.Advance(1); await runtime.TickAsync();
            using var lease = new CityAchievementOutbox(root).Open(Owner);
            Require(remote.Reports == reports + 1 && lease.Read().Pending.Length == 0, "network recovery drains legacy evidence at deadline");
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
    }
    internal static async Task CityLastingRefusalWaitsAReadPeriod()
    {
        foreach (var failure in new Exception[] { new StarBridge.HostRuntime.Auth.ScmApiForbiddenException("synthetic identity mismatch"),
            new StarBridge.HostRuntime.Auth.ScmApiProtocolException("synthetic bad receipt"), new InvalidDataException("synthetic bad receipt") })
        {
            var root = Path.Combine(Path.GetTempPath(), "sb-city-refusal-" + Guid.NewGuid().ToString("N"));
            try
            {
                var clock = new Clock();
                var remote = new Cloud { CityFailure = failure };
                using var runtime = new AchievementRuntime(new(root), remote, () => (Owner, 1), () => null, _ => { }, clock, false, cityStore: new(root));
                runtime.ObserveCity(new(Owner, 1, new(1, FirstEntryObservation.HashHandle("Pilot_A"), "new-babbage", "RequestLocationInventory")));
                await runtime.TickAsync();
                clock.Advance(299); await runtime.TickAsync(true);
                Require(remote.Reports == 1, "a lasting refusal is not retried early: " + failure.GetType().Name);
                clock.Advance(1); await runtime.TickAsync();
                Require(remote.Reports == 2, "a lasting refusal retries after one read period: " + failure.GetType().Name);
            }
            finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
        }
    }
    internal static async Task CityLocalCleanupFailureBacksOff()
    {
        var root = Path.Combine(Path.GetTempPath(), "sb-city-cleanup-" + Guid.NewGuid().ToString("N"));
        try
        {
            var clock = new Clock();
            var remote = new Cloud();
            remote.Earned[Owner] = new() { ["journey-new-babbage"] = Now };
            var store = new CityAchievementOutbox(root);
            var old = new CityObservation(1, FirstEntryObservation.HashHandle("Pilot_A"), "new-babbage", "RequestLocationInventory");
            using (var lease = store.Open(Owner)) lease.Save(new([old], []), () => true);
            var outbox = Directory.GetFiles(root, "*.json", SearchOption.AllDirectories).Single(file => File.ReadAllText(file).Contains("new-babbage"));
            using var runtime = new AchievementRuntime(new(root), remote, () => (Owner, 1), () => null, _ => { }, clock, false, cityStore: store);
            using (new FileStream(outbox, FileMode.Open, FileAccess.Read, FileShare.Read)) // Reads pass; the replace cannot.
            {
                await runtime.TickAsync();
                Require(remote.Reads == 1 && remote.Reports == 0, "a confirmed city is not uploaded again");
                foreach (var delay in new[] { 4, 8, 16, 30, 30 })
                {
                    var reads = remote.Reads;
                    clock.Advance(delay - 1); await runtime.TickAsync();
                    Require(remote.Reads == reads, "cleanup failure does not restart at four seconds");
                    clock.Advance(1); await runtime.TickAsync();
                    Require(remote.Reads == reads + 1, "one read per cleanup deadline");
                }
                using var pending = store.Open(Owner);
                Require(pending.Read().Pending.Length == 1, "the record stays until cleanup succeeds");
            }
            clock.Advance(30); await runtime.TickAsync();
            using (var lease = store.Open(Owner))
                Require(lease.Read().Pending.Length == 0 && lease.Read().Confirmed.Contains("new-babbage"), "cleanup finishes once the file is free");
            var settled = remote.Reads;
            clock.Advance(30); await runtime.TickAsync();
            Require(remote.Reads == settled, "a finished cleanup returns to the normal read period");
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
    }
    internal static async Task CityCleanupFailureAfterUploadFailure()
    {
        var root = Path.Combine(Path.GetTempPath(), "sb-city-sequence-" + Guid.NewGuid().ToString("N"));
        try
        {
            var clock = new Clock();
            var remote = new Cloud { CityFailure = new IOException("synthetic lost upload") };
            var store = new CityAchievementOutbox(root);
            var old = new CityObservation(1, FirstEntryObservation.HashHandle("Pilot_A"), "new-babbage", "RequestLocationInventory");
            using (var lease = store.Open(Owner)) lease.Save(new([old], []), () => true);
            var outbox = Directory.GetFiles(root, "*.json", SearchOption.AllDirectories).Single(file => File.ReadAllText(file).Contains("new-babbage"));
            using var runtime = new AchievementRuntime(new(root), remote, () => (Owner, 1), () => null, _ => { }, clock, false, cityStore: store);
            await runtime.TickAsync();
            Require(remote.Reports == 1, "the upload failed once");
            remote.CityFailure = null;
            remote.Earned[Owner] = new() { ["journey-new-babbage"] = Now };
            using (new FileStream(outbox, FileMode.Open, FileAccess.Read, FileShare.Read))
                await runtime.TickAsync(true); // A cloud confirmation ends the upload wait; the cleanup then fails.
            Require(remote.Reports == 1, "a confirmed city is not uploaded again");
            clock.Advance(7); await runtime.TickAsync(true);
            using (var lease = store.Open(Owner)) Require(lease.Read().Pending.Length == 1, "a forced read cannot jump the cleanup deadline");
            clock.Advance(1); await runtime.TickAsync();
            using (var lease = store.Open(Owner))
                Require(lease.Read().Pending.Length == 0 && lease.Read().Confirmed.Contains("new-babbage"), "failures carry over: cleanup retries at eight seconds");
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
    }
    private sealed class Sink : IAchievementCelebrationSink
    {
        internal readonly List<AchievementCelebration> Items = [];
        public void Submit(AchievementCelebration notice) => Items.Add(notice);
        public void Clear() => Items.Clear();
    }
    internal static async Task Run()
    {
        var tests = new (string Name, Func<Task> Run)[] {
            ("catalog hierarchy and aliases", Catalog), ("live identity/evidence", EvidenceGuards),
            ("catch-up and partial tail", CatchupAndPartialLines), ("durable multi-city and accounts", DurableQueueAndCelebration),
            ("lost receipt and owner race", LostReceiptAndOwnerRace), ("receipt and delivery", ReceiptValidationAndDelivery),
            ("independent hangar receipts", IndependentHangarReceipts),
            ("city failure isolation and backoff", CityFailureIsolationAndBackoff),
            ("city cancellation and account change", CityCancellationAndOwnerChange),
            ("city retry ceiling and new evidence", CityRetryCeilingAndNewEvidence),
            ("city lasting refusal", CityLastingRefusalWaitsAReadPeriod),
            ("city local cleanup failure", CityLocalCleanupFailureBacksOff),
            ("city cleanup failure after upload failure", CityCleanupFailureAfterUploadFailure),
            ("arrival during report", ArrivalDuringReport),
            ("live chunk arrival", LiveChunkArrival), ("live chunk account change", LiveChunkAccountChange),
            ("live chunk source reset", LiveChunkSourceReset), ("live chunk identity conflict", LiveChunkIdentityConflict),
            ("repeated live city bounded", RepeatedLiveCityIsBounded),
            ("repeated four cities bounded", RepeatedFourCitiesAreBounded),
            ("authenticated city transport", CityAchievementRemoteTests.Run)
        };
        var failed = 0;
        foreach (var (name, run) in tests)
            try { await run(); Console.WriteLine("PASS CITYHOST " + name); }
            catch (Exception error) { failed++; Console.WriteLine("FAIL CITYHOST " + name + ": " + error.Message); }
        Console.WriteLine($"SUMMARY CITYHOST passed={tests.Length - failed} failed={failed}");
        if (failed != 0) throw new Exception("City achievement regression failed.");
    }
}
