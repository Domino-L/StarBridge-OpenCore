using System.Text.Json;
using StarBridge.Core.Achievements;
using StarBridge.Core.Events;
using StarBridge.Core.Parsing;
using StarBridge.HostRuntime.Achievements;
using StarBridge.NativeBridge;

internal static partial class ContractAchievementTests
{
    internal const string Mission = "8db7ff56-42a9-479c-9597-1eb9d7da5090";
    internal static readonly BridgeAccountContext Owner = new("test", "scm", "synthetic-contract-owner");
    internal static readonly string HandleHash = FirstEntryObservation.HashHandle("Pilot_A");
    internal static readonly DateTimeOffset Ended = DateTimeOffset.Parse("2026-10-18T06:05:21.734Z");
    internal sealed class Clock : TimeProvider
    {
        internal DateTimeOffset Now = Ended.AddMinutes(1);
        public override DateTimeOffset GetUtcNow() => Now;
    }
    internal static void Require(bool condition, string message) { if (!condition) throw new Exception(message); }
    internal static string Root() { var path = Path.Combine(Path.GetTempPath(), "sb-contract-" + Guid.NewGuid().ToString("N")); Directory.CreateDirectory(path); return path; }
    internal static string SamplePath(string name)
    {
        for (var dir = new DirectoryInfo(AppContext.BaseDirectory); dir is not null; dir = dir.Parent)
        { var path = Path.Combine(dir.FullName, "contracts", "achievements", name); if (File.Exists(path)) return path; }
        throw new FileNotFoundException(name);
    }
    internal static (string Source, string Line)[] Lines()
    {
        using var sample = JsonDocument.Parse(File.ReadAllText(SamplePath("tsg-replay.json")));
        return sample.RootElement.GetProperty("lines").EnumerateArray().Select(v =>
            (v.GetProperty("source").GetString()!, v.GetProperty("line").GetString()!)).ToArray();
    }
    internal static (FleetEvent Event, bool Live)[] Replay(bool live = true, bool deaths = true)
    {
        var parser = new RegexLogEventParser();
        var events = Lines().Select(l => parser.TryParse(l.Line)).Where(e => e is not null).Select(e => (Event: e! with { SourceLine = null }, Live: live)).ToList();
        if (deaths)
        {
            // Reports supply the mission timeline, not the two death line timestamps. These
            // normalized parser events are deliberately synthetic, between acceptance and end.
            foreach (var at in new[] { "2026-10-18T04:35:00Z", "2026-10-18T05:20:00Z" })
            {
                var time = DateTimeOffset.Parse(at);
                events.Add((new(FleetEventType.PlayerDied, "LocalPlayer", Timestamp: time), live));
                events.Add((new(FleetEventType.PlayerRespawned, "LocalPlayer", Timestamp: time.AddSeconds(10)), live));
            }
        }
        return events.OrderBy(e => e.Event.Timestamp).ToArray();
    }
    internal static ContractAchievementStore.State Read(ContractAchievementStore store, BridgeAccountContext? owner = null)
    { using var lease = store.Open(owner ?? Owner); return lease.Read(); }
    internal static ContractObservation Pending(ContractAchievementStore store) => Read(store).Runs.Single(r => r.MissionId == Mission).Pending ?? throw new Exception("no pending contract");

    private static Task Timeline()
    {
        var root = Root(); var store = new ContractAchievementStore(root); var tracker = new ContractRunTracker(store);
        var original = Replay();
        var accepted = original.First(e => e.Event.Type == FleetEventType.ContractAccepted);
        var events = original.Concat(Enumerable.Range(1, 14).Select(i =>
            (accepted.Event with { Timestamp = accepted.Event.Timestamp!.Value.AddMinutes(i) }, true)))
            .OrderBy(e => e.Item1.Timestamp).Select(e => (Event: e.Item1, Live: e.Item2)).ToArray();
        Require(events.Select(e => e.Event.Contract?.ObjectiveId).Where(id => id is not null).Distinct().Count() == 38, "fixture contains all 38 actual objective keys");
        tracker.Observe(Owner, HandleHash, events, () => true, ownershipCovered: true);
        var run = Read(store).Runs.Single(); var observation = Pending(store);
        Require(run.Objectives!.Length == 38 && observation.Owner && observation.CompleteRun && observation.Deaths == 2, "one owner, 38 stages, two deaths, uninterrupted complete run");
        Require(observation.AcceptedAt == DateTimeOffset.Parse("2026-10-18T03:29:57.165Z") &&
            observation.ArrivedAt == DateTimeOffset.Parse("2026-10-18T04:17:34.311Z") && observation.CompletedAt == Ended &&
            observation.CompletedAt - observation.ArrivedAt == TimeSpan.FromMilliseconds(6467423), "earliest arrival retained through repeated navigation and four logs");
        var awarded = Cloud.Awards(observation);
        Require(awarded.SetEquals(["contract-first", "contract-tsg-lead", "contract-tsg-complete"]), "90-minute server fixture: no swift or deathless");
        tracker.Observe(Owner, HandleHash, events, () => true, ownershipCovered: true);
        Require(Read(store).Runs.Length == 1 && Pending(store) == observation, "duplicate notifications and endings preserve the first observation");
        return Task.CompletedTask;
    }
    private static Task GapsAndRestart()
    {
        foreach (var restart in new[] { false, true })
        {
            var store = new ContractAchievementStore(Root()); var tracker = new ContractRunTracker(store); var events = Replay();
            var boundary = DateTimeOffset.Parse("2026-10-18T05:11:00Z");
            tracker.Observe(Owner, HandleHash, events.Where(e => e.Event.Timestamp < boundary).ToArray(), () => true, ownershipCovered: true);
            if (restart) tracker = new(store); else tracker.Break(Owner);
            tracker.Observe(Owner, HandleHash, events.Where(e => e.Event.Timestamp >= boundary).ToArray(), () => true, ownershipCovered: true);
            Require(!Pending(store).CompleteRun && Pending(store).Owner && Pending(store).Deaths == 2, "Host gap/restart preserves original owner, deaths and disables completeRun");
            Require(Cloud.Awards(Pending(store)).SetEquals(["contract-first", "contract-tsg-lead"]), "incomplete run cannot grant triumphant/swift/deathless");
        }
        var historyStore = new ContractAchievementStore(Root()); var history = new ContractRunTracker(historyStore);
        history.Observe(Owner, HandleHash, Replay(false), () => true, ownershipCovered: true);
        history.Observe(Owner, HandleHash, Replay(), () => true, ownershipCovered: true);
        Require(Read(historyStore).Runs.All(r => r.Pending is null), "historical acceptance blocks later replayed acceptance");
        return Task.CompletedTask;
    }
    private static Task OwnershipAndOutcomes()
    {
        var events = Replay();
        var share = new FleetEvent(FleetEventType.ContractShared, "LocalPlayer", Timestamp: events[0].Event.Timestamp!.Value.AddSeconds(-1), Contract: new(Mission));
        var store = new ContractAchievementStore(Root()); var tracker = new ContractRunTracker(store);
        tracker.Observe(Owner, HandleHash, [(share, true), .. events], () => true, ownershipCovered: true);
        Require(!Pending(store).Owner && Pending(store).CompleteRun, "share before acceptance is not owner");
        foreach (var outcome in new[] { "FAILED", "WITHDRAWN", "ABANDONED", "UNKNOWN" })
        {
            store = new(Root()); tracker = new(store);
            var input = events.Where(e => e.Event.Type != FleetEventType.ContractEnded).Append((new FleetEvent(FleetEventType.ContractEnded,
                "LocalPlayer", Timestamp: Ended, Contract: new(Mission, State: outcome)), true)).ToArray();
            tracker.Observe(Owner, HandleHash, input, () => true, ownershipCovered: true);
            Require(Read(store).Runs.All(r => r.Pending is null), "noncompletion never queues: " + outcome);
        }
        store = new(Root()); tracker = new(store);
        tracker.Observe(Owner, HandleHash, events.Where(e => e.Event.Type != FleetEventType.ContractEnded).ToArray(), () => true, ownershipCovered: true);
        Require(Read(store).Runs.All(r => r.Pending is null), "unknown ending and objective completions do not queue");
        tracker.Observe(Owner, HandleHash, [(new(FleetEventType.ContractEnded, "LocalPlayer", Timestamp: Ended, Contract: new(Mission, State: "COMPLETED")), true),
            (new(FleetEventType.ContractEnded, "LocalPlayer", Timestamp: Ended, Contract: new(Mission, State: "FAILED")), true)], () => true, ownershipCovered: true);
        Require(Read(store).Runs.Single().Outcome == "CONFLICT" && Read(store).Runs.Single().Pending is null, "contradictory terminal evidence blocks upload");
        return Task.CompletedTask;
    }
    private static Task StageSemantics()
    {
        var events = Replay(deaths: false);
        var store = new ContractAchievementStore(Root()); var tracker = new ContractRunTracker(store);
        // Preserve a withdrawn ObjectiveComplete and revived/downed: none is a whole-mission completion/death.
        var extra = new[] {
            (new FleetEvent(FleetEventType.PlayerDowned, "LocalPlayer", Timestamp: Ended.AddMinutes(-1)), true),
            (new FleetEvent(FleetEventType.PlayerRevived, "LocalPlayer", Timestamp: Ended.AddSeconds(-30)), true) };
        tracker.Observe(Owner, HandleHash, events.Concat(extra).OrderBy(e => e.Item1.Timestamp).ToArray(), () => true, ownershipCovered: true);
        Require(Pending(store).Deaths == 0 && Cloud.Awards(Pending(store)).Contains("contract-tsg-deathless"), "downed and rescued is deathless");
        var valid = Pending(store) with { ArrivedAt = Ended.AddMinutes(-90) };
        Require(Cloud.Awards(valid).Contains("contract-tsg-swift") && !Cloud.Awards(valid with { ArrivedAt = Ended.AddMinutes(-90).AddMilliseconds(-1) }).Contains("contract-tsg-swift"), "90-minute inclusive timing boundary, plus one millisecond rejected");
        store = new(Root()); tracker = new(store);
        tracker.Observe(Owner, HandleHash, events.Where(e => e.Event.Type != FleetEventType.ContractObjective).ToArray(), () => true, ownershipCovered: true);
        Require(!Pending(store).CompleteRun && Pending(store).ArrivedAt is null, "markers alone cannot establish first stage");
        store = new(Root()); tracker = new(store);
        var firstCombat = DateTimeOffset.Parse("2026-10-18T04:17:53Z");
        tracker.Observe(Owner, HandleHash, events.Where(e => !(e.Event.Type == FleetEventType.ContractObjective && e.Event.Timestamp < firstCombat && e.Event.Contract?.State == "COMPLETED")).ToArray(), () => true, ownershipCovered: true);
        Require(Pending(store).ArrivedAt is null, "late return/reentry navigation cannot replace a missing initial arrival");
        foreach (var needsCompletion in new[] { false, true })
        {
            store = new(Root()); tracker = new(store, _ => new(["前往 QV 采矿站"], [new(["护送加布"], needsCompletion)]));
            tracker.Observe(Owner, HandleHash, events, () => true, ownershipCovered: true);
            Require(Pending(store).CompleteRun != needsCompletion, "required-stage extension matches roles/text, never per-instance UUIDs or fabricated escort completion");
        }
        store = new(Root()); tracker = new(store);
        tracker.Observe(Owner, HandleHash, events.Where(e => e.Event.Type != FleetEventType.ContractDefined).ToArray(), () => true, ownershipCovered: true);
        Require(Pending(store).Contract == "unknown" && Cloud.Awards(Pending(store)).SetEquals(["contract-first"]), "missing template still supports first contract without guessing TSG");
        return Task.CompletedTask;
    }
    private static Task CorruptionAndIsolation()
    {
        var root = Root(); var store = new ContractAchievementStore(root); var tracker = new ContractRunTracker(store);
        tracker.Observe(Owner, HandleHash, Replay(), () => true, ownershipCovered: true);
        Require(Read(store, Owner with { Subject = "other-synthetic" }).Runs.Length == 0, "account partition");
        var path = Directory.GetFiles(Path.Combine(root, "achievements-contract-v1"), "*.json").Single();
        File.WriteAllText(path, "{}");
        try { tracker.Observe(Owner, HandleHash, Replay(), () => true, ownershipCovered: true); throw new Exception("corruption overwritten"); }
        catch (InvalidDataException) { }
        Require(File.ReadAllText(path) == "{}", "corrupt state fails closed");
        var observation = new ContractObservation(1, HandleHash, Mission, ContractAchievementPolicy.Tsg, ContractAchievementPolicy.TsgDefinition,
            "completed", true, true, 0, Ended.AddHours(-2), Ended.AddHours(-1), Ended);
        Require(observation.IsValid && !(observation with { MissionId = Guid.Empty.ToString() }).IsValid &&
            !(observation with { ArrivedAt = Ended.AddSeconds(1) }).IsValid && !(observation with { Deaths = -1 }).IsValid,
            "observation validation and order");
        return Task.CompletedTask;
    }
    internal sealed class Cloud : IAchievementRemote
    {
        internal bool Offline, Invalid, Reject; internal int Reports;
        internal readonly Dictionary<string, DateTimeOffset> Earned = [];
        internal static HashSet<string> Awards(ContractObservation o)
        {
            // Fake server only: production Host never grants or applies a timing limit.
            var result = new HashSet<string> { "contract-first" };
            if (!ContractAchievementPolicy.TsgContracts.Contains(o.Contract)) return result;
            if (o.Owner) result.Add("contract-tsg-lead");
            if (!o.CompleteRun) return result;
            result.Add("contract-tsg-complete");
            if (o.Deaths == 0) result.Add("contract-tsg-deathless");
            if (o.ArrivedAt is { } at && o.CompletedAt - at <= TimeSpan.FromMinutes(90)) result.Add("contract-tsg-swift");
            return result;
        }
        public Task<AchievementSnapshot> ReadAchievementsAsync(BridgeAccountContext owner, long generation, CancellationToken token) =>
            Task.FromResult(new AchievementSnapshot(1, new(Earned)));
        public Task<AchievementReceipt> ObserveFirstEntryAsync(BridgeAccountContext owner, long generation, FirstEntryObservation observation, CancellationToken token) => throw new Exception("unexpected entry");
        public Task<ContractAchievementReceipt> ObserveContractAsync(BridgeAccountContext owner, long generation, ContractObservation observation, CancellationToken token)
        {
            Reports++; if (Offline) throw new IOException("synthetic outage");
            if (Reject) throw new HttpRequestException("synthetic reject", null, System.Net.HttpStatusCode.Forbidden);
            var newly = Awards(observation).Where(id => !Earned.ContainsKey(id)).ToArray();
            foreach (var id in newly) Earned[id] = observation.CompletedAt;
            return Task.FromResult(new ContractAchievementReceipt(1, new(Earned), Invalid ? ["unknown-id"] : newly));
        }
    }
    private static async Task DurableUpload()
    {
        var root = Root(); var store = new ContractAchievementStore(root); var tracker = new ContractRunTracker(store);
        tracker.Observe(Owner, HandleHash, Replay(), () => true, ownershipCovered: true);
        var cloud = new Cloud { Offline = true }; var clock = new Clock(); var celebrated = new List<string>();
        AchievementRuntime Runtime() => new(new(root), cloud, () => (Owner, 1), () => null, _ => { }, time: clock,
            startTimer: false, contractStore: store, seriesEarned: (_, id, _, _) => celebrated.Add(id));
        using (var runtime = Runtime())
        {
            await runtime.TickAsync(true); await runtime.TickAsync(true);
            Require(cloud.Reports == 1 && Pending(store).IsValid, "offline retained, forced reads respect upload backoff");
            cloud.Offline = false; clock.Now = clock.Now.AddSeconds(4); await runtime.TickAsync(true);
            Require(cloud.Reports == 2 && Read(store).Runs.Single().Confirmed && celebrated.Count == 3, "durable acknowledgement, three visible celebrations");
        }
        using (var runtime = Runtime()) await runtime.TickAsync(true);
        Require(cloud.Reports == 2 && celebrated.Count == 3, "restart cannot upload confirmed mission or celebrate cached read");
        // A new mission must still upload even when all its achievements are already in the read snapshot.
        var mission = Guid.NewGuid().ToString();
        var next = Replay().Select(e => (e.Event.Contract is { } d ? e.Event with { Contract = d with { MissionId = mission } } : e.Event, e.Live)).ToArray();
        tracker.Observe(Owner, HandleHash, next, () => true, ownershipCovered: true);
        using (var runtime = Runtime()) await runtime.TickAsync(true);
        Require(cloud.Reports == 3 && celebrated.Count == 3 && Read(store).Runs.All(r => r.Confirmed), "mission idempotency independent of already-earned IDs");
    }
    private static async Task RejectedReceipt()
    {
        var root = Root(); var store = new ContractAchievementStore(root); new ContractRunTracker(store).Observe(Owner, HandleHash, Replay(), () => true, ownershipCovered: true);
        var cloud = new Cloud { Invalid = true }; var clock = new Clock(); var notices = 0;
        using var runtime = new AchievementRuntime(new(root), cloud, () => (Owner, 1), () => null, _ => { },
            time: clock, startTimer: false, contractStore: store, seriesEarned: (_, _, _, _) => notices++);
        await runtime.TickAsync(true); cloud.Invalid = false; clock.Now = clock.Now.AddSeconds(299); await runtime.TickAsync(true);
        Require(cloud.Reports == 1 && notices == 0 && Pending(store).IsValid, "invalid receipt stays pending for 300 seconds, without celebration");
        clock.Now = clock.Now.AddSeconds(1); await runtime.TickAsync(true);
        Require(cloud.Reports == 2 && Read(store).Runs.Single().Confirmed && notices == 0, "idempotent retry acknowledges without inventing newly earned");
    }
    private static async Task RejectedUpload()
    {
        var root = Root(); var store = new ContractAchievementStore(root); new ContractRunTracker(store).Observe(Owner, HandleHash, Replay(), () => true, ownershipCovered: true);
        var cloud = new Cloud { Reject = true }; var clock = new Clock();
        using var runtime = new AchievementRuntime(new(root), cloud, () => (Owner, 1), () => null, _ => { },
            time: clock, startTimer: false, contractStore: store);
        await runtime.TickAsync(true); clock.Now = clock.Now.AddSeconds(299); await runtime.TickAsync(true);
        Require(cloud.Reports == 1 && Pending(store).IsValid, "403 keeps evidence for the full read period");
        cloud.Reject = false; clock.Now = clock.Now.AddSeconds(1); await runtime.TickAsync(true);
        Require(cloud.Reports == 2 && Read(store).Runs.Single().Confirmed, "rejected upload recovers after deadline");
    }
    private static async Task StorageFaultIsolation()
    {
        var root = Root(); var store = new ContractAchievementStore(root); new ContractRunTracker(store).Observe(Owner, HandleHash, Replay(), () => true, ownershipCovered: true);
        var path = Directory.GetFiles(Path.Combine(root, "achievements-contract-v1"), "*.json").Single(); File.WriteAllText(path, "{}");
        var cloud = new Cloud(); cloud.Earned["journey-orison"] = Ended; AchievementSnapshot? confirmed = null;
        using var runtime = new AchievementRuntime(new(root), cloud, () => (Owner, 1), () => null, _ => { },
            time: new Clock(), startTimer: false, contractStore: store, confirmed: (_, snapshot, _) => confirmed = snapshot);
        await runtime.TickAsync(true);
        Require(cloud.Reports == 0 && confirmed?.EarnedAt.ContainsKey("journey-orison") == true && File.ReadAllText(path) == "{}",
            "contract corruption neither uploads nor overwrites evidence nor suppresses confirmed city snapshot");
    }
    internal static async Task Run()
    {
        var tests = new (string Name, Func<Task> Run)[] {
            ("timestamped physical notification lines", TimestampedPhysicalLines),
            ("unread medical death then exit", () => UnreadDeathExit(false)),
            ("unread corpse death then exit", () => UnreadDeathExit(true)),
            ("unread medical death then same-length replacement and exit", () => SameLengthReplacementExit(false)),
            ("unread corpse death then same-length replacement and exit", () => SameLengthReplacementExit(true)),
            ("metadata-only EOF exit", MetadataOnlyExit),
            ("old file identity across exit and path switches", BoundaryFileIdentity),
            ("normal medical death then EOF exit", () => ConsumedDeathExit(false)),
            ("normal corpse death then EOF exit", () => ConsumedDeathExit(true)),
            ("EOF exit and same-contract reentry", EndOfFileExit),
            ("rotation without old length", () => SourceBoundaryGap("rotation")),
            ("truncation gap", () => SourceBoundaryGap("truncation")),
            ("deleted source gap", () => SourceBoundaryGap("deletion")),
            ("partial line at EOF", PartialLineExit),
            ("normal reader disconnect and rejoin", NormalReaderSessionTransitions),
            ("historical share and startup coverage", HistoricalShareOwnership),
            ("Java contract grammar and unknown fallback", ContractCodeGrammar),
            ("real 38-objective timeline and two synthetic deaths", Timeline), ("gaps, restart and historical guard", GapsAndRestart),
            ("ownership and noncompletion", OwnershipAndOutcomes), ("stage and timing semantics", StageSemantics),
            ("integrity and account isolation", CorruptionAndIsolation), ("durable upload and retry", DurableUpload),
            ("receipt admission and retry", RejectedReceipt), ("lasting upload refusal", RejectedUpload), ("contract storage fault isolation", StorageFaultIsolation),
            ("runtime reader eligibility and rotation", RuntimeReading),
            ("in-memory HTTP wire contract", WireContract) };
        var failed = 0;
        foreach (var (name, run) in tests)
            try { await run(); Console.WriteLine("PASS CONTRACT HOST " + name); }
            catch (Exception e) { failed++; Console.WriteLine("FAIL CONTRACT HOST " + name + ": " + e.Message); }
        Console.WriteLine($"SUMMARY CONTRACT HOST passed={tests.Length - failed} failed={failed}");
        if (failed > 0) throw new Exception("Contract achievement regressions failed.");
    }
}
