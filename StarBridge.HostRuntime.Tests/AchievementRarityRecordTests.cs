using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.Core.Achievements;
using StarBridge.Core.Events;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Achievements;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

internal static class AchievementRarityRecordTests
{
    private static readonly BridgeAccountContext Owner = new("test", "scm", "synthetic-record-owner");
    private static readonly DateTimeOffset Start = DateTimeOffset.Parse("2026-11-03T12:00:00Z");
    private const string Mission = "8db7ff56-42a9-479c-9597-1eb9d7da5090";
    private static ContractAchievementRecord Facts => new("需要战术打击群", Start, Start.AddMinutes(61), Start.AddMinutes(81), 38, true, 0);
    private static ContractObservation Observation => new(1, FirstEntryObservation.HashHandle("Synthetic"), Mission,
        ContractAchievementPolicy.Tsg, null, "completed", true, true, 0, Facts.AcceptedAt, Facts.ArrivedAt, Facts.CompletedAt);
    private static AchievementSnapshot Snapshot => new(1, ContractAchievementPolicy.AwardIds.ToDictionary(id => id, _ => Facts.CompletedAt));
    private static ContractAchievementReceipt Receipt => new(1, Snapshot.EarnedAt, ContractAchievementPolicy.AwardIds.ToArray());
    private static void Require(bool value, string message) { if (!value) throw new Exception(message); }
    private static void Invalid(Action action, string message)
    {
        try { action(); } catch (InvalidDataException) { return; }
        throw new Exception("Expected invalid data: " + message);
    }
    internal static async Task Run()
    {
        var cases = new (string, Func<Task>)[] {
            ("rarity authenticated wire and failures", Wire),
            ("rarity validation boundaries", () => { Validation(); return Task.CompletedTask; }),
            ("rarity cache, failure isolation and owner", RarityRuntime),
            ("five records in three languages", () => { Lines(); return Task.CompletedTask; }),
            ("record storage, integrity and owner", () => { Storage(); return Task.CompletedTask; }),
            ("best swift run persists without regranting", () => { BestRun(); return Task.CompletedTask; }),
            ("new grants and celebration ordering", NewGrant),
            ("acceptance name and stage capture", () => { Capture(); return Task.CompletedTask; })
        };
        var failed = 0;
        foreach (var (name, test) in cases)
        {
            try { await test(); Console.WriteLine("PASS RARITY RECORD " + name); }
            catch (Exception e) { failed++; Console.WriteLine("FAIL RARITY RECORD " + name + ": " + e.Message); }
        }
        Console.WriteLine($"SUMMARY RARITY RECORD passed={cases.Length-failed} failed={failed}");
        Require(failed == 0, "rarity/record regressions");
    }
    private sealed class Vault : ITokenVault
    {
        public void SaveRefreshToken(string a, string b) => throw new Exception("Unexpected vault write");
        public string? LoadRefreshToken(string a) => null;
        public string? LoadActiveAccountKey() => null;
        public void DeleteRefreshToken(string a) => throw new Exception("Unexpected vault delete");
    }
    private sealed class Handler : HttpMessageHandler
    {
        internal HttpStatusCode Status = HttpStatusCode.OK;
        internal bool Held;
        internal AchievementRarity Value = Valid;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Require(request.Method == HttpMethod.Get && request.RequestUri!.AbsolutePath == "/app-api/starbridge/v1/achievements/rarity",
                "only the exact rarity GET is sent");
            Require(request.Headers.Authorization?.Parameter == "synthetic-access", "normal bearer authentication");
            if (Held) await Task.Delay(Timeout.Infinite, token);
            return new(Status) { Content = JsonContent.Create(Value) };
        }
    }
    private static AchievementRarity Valid => new(1, 30, 50, Start.AddDays(-1), new() { ["contract-first"] = 100 }, new() { ["contract-first"] = "veryRare" });
    private static async Task Wire()
    {
        using var handler = new Handler();
        var options = new ScmOAuthOptions("fixture", new("http://127.0.0.1:3000/"), new("http://127.0.0.1:18080/"),
            new("http://127.0.0.1:18082/"), "starbridge-desktop", "starbridge-api", "profile.read", "/oauth/callback");
        var session = new ScmOAuthSession("fixture", "synthetic-record-owner", "Synthetic", "synthetic-access",
            DateTimeOffset.UtcNow.AddHours(1), ["profile.read"]);
        var oauth = new OAuthPkceClient(new ScmHttpClient(handler), new Vault(), options);
        Require((await oauth.ReadAchievementRarityAsync(session, default)).Result.Percentages["contract-first"] == 100, "valid decoded");
        handler.Status = HttpStatusCode.NotFound;
        try { await oauth.ReadAchievementRarityAsync(session, default); throw new Exception("404 accepted"); }
        catch (Exception e) when (e.Message != "404 accepted") { }
        handler.Status = HttpStatusCode.OK; handler.Value = Valid with { Percentages = new() { ["bad id"] = 10 } };
        try { await oauth.ReadAchievementRarityAsync(session, default); throw new Exception("invalid accepted"); }
        catch (InvalidDataException) { }
        handler.Held = true;
        using var budget = new CancellationTokenSource(TimeSpan.FromMilliseconds(30));
        try { await oauth.ReadAchievementRarityAsync(session, budget.Token); throw new Exception("timeout accepted"); }
        catch (OperationCanceledException) { }
    }
    private static void Validation()
    {
        Valid.Validate(); (Valid with { ActiveAccounts = 49, Percentages = [], Tiers = [] }).Validate();
        foreach (var value in new[] {
            Valid with { Tiers = new() { ["contract-first"] = "ultraRare" } },
            Valid with { Tiers = new() { ["other"] = "rare" } },
            Valid with { SchemaVersion = 2 }, Valid with { WindowDays = 29 }, Valid with { ActiveAccounts = -1 },
            Valid with { ActiveAccounts = 49 }, Valid with { ComputedAt = DateTimeOffset.UnixEpoch },
            Valid with { Percentages = new() { ["bad id"] = 3 } },
            Valid with { Percentages = new() { ["contract-first"] = -1 } },
            Valid with { Percentages = new() { ["contract-first"] = 10001 } },
            Valid with { Percentages = Enumerable.Range(0,257).ToDictionary(i => "id-" + i, _ => 1) } })
            Invalid(value.Validate, "finite schema, window, count, id and basis points");
        foreach (var n in new[] { 0, 10, 100, 1000, 10000 }) (Valid with { Percentages = new() { ["contract-first"] = n } }).Validate();
        (Valid with { Percentages = new() { ["contract-first"] = 100 }, Tiers = new() { ["contract-first"] = "rare" } }).Validate();
        (Valid with { Percentages = new() { ["contract-first"] = 1000 }, Tiers = [] }).Validate();
        var encoded = JsonSerializer.Serialize(Valid, new JsonSerializerOptions(JsonSerializerDefaults.Web));
        Require(encoded.Contains("\"tiers\":{\"contract-first\":\"veryRare\"}"), "server tier round trip");
        using var fixture = JsonDocument.Parse(File.ReadAllText("contracts/achievements/rarity-response.json"));
        foreach (var sample in fixture.RootElement.EnumerateObject())
            JsonSerializer.Deserialize<AchievementRarity>(sample.Value, new JsonSerializerOptions(JsonSerializerDefaults.Web))!.Validate();
    }
    private sealed class Clock : TimeProvider
    {
        internal DateTimeOffset Now = Start;
        public override DateTimeOffset GetUtcNow() => Now;
    }
    private sealed class Remote : IAchievementRemote
    {
        internal int RarityReads;
        internal ContractAchievementReceipt Response = Receipt;
        internal Exception? Error;
        internal TaskCompletionSource<AchievementRarity?>? Held;
        public async Task<AchievementRarity?> ReadRarityAsync(BridgeAccountContext o, long g, CancellationToken t)
        { RarityReads++; if (Error is not null) throw Error; return Held is null ? Valid : await Held.Task.WaitAsync(t); }
        public Task<AchievementSnapshot> ReadAchievementsAsync(BridgeAccountContext o, long g, CancellationToken t) => Task.FromResult(new AchievementSnapshot(1, []));
        public Task<AchievementReceipt> ObserveFirstEntryAsync(BridgeAccountContext o, long g, FirstEntryObservation e, CancellationToken t) => throw new NotSupportedException();
        public Task<ContractAchievementReceipt> ObserveContractAsync(BridgeAccountContext o, long g, ContractObservation e, CancellationToken t) => Task.FromResult(Response);
    }
    private static string Root() => Path.Combine(Path.GetTempPath(), "cx-rarity-" + Guid.NewGuid().ToString("N"));
    private static async Task RarityRuntime()
    {
        var root = Root(); var time = new Clock(); var remote = new Remote();
        (BridgeAccountContext? Context, long Generation) current = (Owner, 1);
        using var runtime = new AchievementRuntime(new(root), remote, () => current, () => null, _ => { }, time, false);
        await runtime.RefreshRarityAsync(current); Require(runtime.ReadRarity(current)?.Percentages.Count == 1, "publication");
        await runtime.RefreshRarityAsync(current); Require(remote.RarityReads == 1, "one attempt per hour");
        time.Now = time.Now.AddHours(1); remote.Error = new HttpRequestException("old backend", null, HttpStatusCode.NotFound);
        await runtime.RefreshRarityAsync(current); Require(runtime.ReadRarity(current) is null, "404 hidden");
        await runtime.TickAsync(true);
        var response = await runtime.DispatchAsync(BridgeEnvelope.Request("achievements.read", "r", 1, new { schemaVersion = 1 }, Owner), default);
        Require(response.Response.Status == BridgeResponseStatuses.Ok, "rarity failure leaves collection available");
        time.Now = time.Now.AddHours(1); remote.Error = new OperationCanceledException("timeout");
        await runtime.RefreshRarityAsync(current); Require(runtime.ReadRarity(current) is null, "timeout hidden");
        time.Now = time.Now.AddHours(1); remote.Error = null; remote.Held = new();
        var old = current; var reading = runtime.RefreshRarityAsync(old);
        current = (Owner with { Subject = "synthetic-other" }, 2); runtime.Invalidate(2);
        remote.Held.SetResult(Valid); await reading;
        Require(runtime.ReadRarity(current) is null && runtime.ReadRarity(old) is null, "late old-owner ratio cannot leak");
    }
    private static void Lines()
    {
        Require(Facts.Lines("contract-first")!.ZhCN == "第一单：需要战术打击群 · 11月3日", "first name/date");
        Require(Facts.Lines("contract-tsg-lead")!.ZhCN == "作为任务主完成战术打击群：1 小时 21 分", "hours");
        Require(Facts.Lines("contract-tsg-complete")!.ZhCN == "完整完成一次战术打击群：1 小时 21 分", "acceptance elapsed");
        Require(Facts.Lines("contract-tsg-swift")!.ZhCN == "最佳：在到达后 20 分 内完成战术打击群", "arrival elapsed");
        Require(Facts.Lines("contract-tsg-deathless")!.ZhCN == "无死亡完成战术打击群：1 小时 21 分", "deathless");
        Require((Facts with { DisplayName = null }).Lines("contract-first")!.ZhCN == "11月3日", "name unavailable means date only");
        Require((Facts with { CompletedAt = Start.AddMinutes(30), ArrivedAt = Start.AddMinutes(5) }).Lines("contract-tsg-lead")!.ZhCN == "作为任务主完成战术打击群：30 分", "sub-hour");
        foreach (var id in ContractAchievementPolicy.AwardIds)
        {
            var lines = Facts.Lines(id)!;
            Require(lines.ZhCN.Length > 0 && lines.ZhTW.Length > 0 && lines.En.Length > 0 && lines.For("en-US") == lines.En &&
                lines.For("zh-TW") == lines.ZhTW, "all languages: " + id);
        }
    }
    private static void BestRun()
    {
        const string swift = "contract-tsg-swift";
        var root = Root(); var store = new ContractRecordStore(root);
        store.Capture(Owner, Mission, Facts.DisplayName, Facts, () => true);
        store.Confirm(Owner, Observation, Receipt with { NewlyEarned = [] }, () => true);
        Require(store.ReadLines(Owner, Snapshot).Keys.SequenceEqual(new[] { swift }),
            "a confirmed later run can establish a local best without reconstructing other award records");
        store.Confirm(Owner, Observation, Receipt, () => true);
        var original = store.ReadLines(Owner, Snapshot);
        var subsequent = Receipt with { NewlyEarned = [] };
        var sequence = 0;
        void Complete(int minutes, bool complete = true, string? contract = null, bool arrival = true,
            bool match = true, ContractAchievementReceipt? receipt = null)
        {
            var at = Start.AddDays(++sequence);
            var run = Facts with { AcceptedAt = at, ArrivedAt = arrival ? at.AddMinutes(5) : null,
                CompletedAt = at.AddMinutes(5 + minutes) };
            var mission = Guid.NewGuid().ToString("D");
            store.Capture(Owner, mission, run.DisplayName, run, () => true);
            var observation = Observation with { MissionId = mission, AcceptedAt = at, ArrivedAt = run.ArrivedAt,
                CompletedAt = match ? run.CompletedAt : run.CompletedAt.AddMinutes(1),
                CompleteRun = complete, Contract = contract ?? ContractAchievementPolicy.Tsg };
            store.Confirm(Owner, observation, receipt ?? subsequent, () => true);
        }
        Complete(21); Complete(20); // Slower and equal runs preserve the winning run.
        using (var lease = store.Open(Owner))
            Require(lease.Read().Awards[swift].Run == Facts, "slower/equal runs leave facts intact");
        Complete(10, complete: false); Complete(10, contract: "unknown"); Complete(10, arrival: false);
        Complete(10, match: false);
        Complete(10, receipt: subsequent with { EarnedAt = new(Snapshot.EarnedAt) { [swift] = Start.AddDays(30) } });
        Require(store.ReadLines(Owner, Snapshot)[swift] == original[swift], "ineligible/unmatched runs do not improve best");
        Complete(19);
        Require(new ContractRecordStore(root).ReadLines(Owner, Snapshot)[swift].ZhCN ==
            "最佳：在到达后 19 分 内完成战术打击群", "faster confirmed run survives restart");
        foreach (var id in ContractAchievementPolicy.AwardIds.Where(id => id != swift))
            Require(store.ReadLines(Owner, Snapshot)[id] == original[id], "other awards retain original run");
        using (var lease = store.Open(Owner))
            Require(lease.Read().Awards[swift].EarnedAt == Facts.CompletedAt, "award date remains original");

        // A pre-existing record over the limit must not accept a faster but still over-limit run.
        using (var lease = store.Open(Owner))
        {
            var state = lease.Read();
            state.Awards[swift] = new(Facts.CompletedAt, Facts with { CompletedAt = Start.AddMinutes(161) });
            lease.Save(state, () => true);
        }
        Complete(91);
        Require(store.ReadLines(Owner, Snapshot)[swift].ZhCN.Contains("1 小时 40 分"), "over 90 minutes rejected");
        Complete(90);
        Require(store.ReadLines(Owner, Snapshot)[swift].ZhCN.Contains("1 小时 30 分"), "90 minute boundary accepted");
    }

    private static void Storage()
    {
        var root = Root(); var store = new ContractRecordStore(root);
        store.Capture(Owner, Mission, Facts.DisplayName, Facts, () => true);
        store.Confirm(Owner, Observation, Receipt with { NewlyEarned = [], EarnedAt = [] }, () => true);
        Require(store.ReadLines(Owner, Snapshot).Count == 0, "no grant means no record");
        store.Confirm(Owner, Observation, Receipt, () => true);
        Require(new ContractRecordStore(root).ReadLines(Owner, Snapshot).Count == 5, "restart reads five records");
        var other = Owner with { Subject = "synthetic-other" };
        Require(store.ReadLines(other, Snapshot).Count == 0, "different owner has no records");
        var directory = Path.Combine(root, "achievements-contract-records-v1");
        var source = Directory.GetFiles(directory, "*.json").Single();
        var bytes = File.ReadAllText(source);
        using (var lease = store.Open(other)) lease.Save(ContractRecordStore.State.Empty, () => true);
        var target = Directory.GetFiles(directory, "*.json").Single(p => p != source);
        File.Copy(source, target, true);
        using (var lease = store.Open(other)) Invalid(() => lease.Read(), "owner mismatch");
        File.WriteAllText(source, bytes.Replace("需要战术打击群", "tampered").Replace("\"stageObjectives\":38", "\"stageObjectives\":39"));
        using (var lease = store.Open(Owner)) Invalid(() => lease.Read(), "integrity mismatch");
        File.WriteAllText(source, bytes);
        var canceled = false;
        using (var lease = store.Open(Owner))
        { try { lease.Save(ContractRecordStore.State.Empty, () => false); } catch (OperationCanceledException) { canceled = true; } }
        Require(canceled && store.ReadLines(Owner, Snapshot).Count == 5, "account change cannot rewrite");
    }
    private sealed class Sink : IAchievementCelebrationSink
    {
        internal AchievementCelebration? Notice;
        public void Submit(AchievementCelebration notice) => Notice = notice;
        public void Clear() => Notice = null;
    }
    private static async Task NewGrant()
    {
        var root = Root(); var records = new ContractRecordStore(root); var contracts = new ContractAchievementStore(root);
        records.Capture(Owner, Mission, Facts.DisplayName, Facts, () => true);
        using (var lease = contracts.Open(Owner))
            lease.Save(new([new(Mission, Observation.HandleHash, Guid.NewGuid(), AcceptedAt: Start, Pending: Observation)]), () => true);
        var delivered = 0;
        using var delivery = new AchievementCelebrationDelivery(() => (Owner, 1)); var sink = new Sink(); delivery.Configure(sink);
        var remote = new Remote();
        using var runtime = new AchievementRuntime(new(root), remote, () => (Owner, 1), () => null, _ => { },
            startTimer: false, contractStore: contracts, contractRecords: records,
            seriesEarned: (g, id, rank, at) => {
                var lines = records.ReadLines(Owner, Snapshot).GetValueOrDefault(id);
                Require(lines is not null, "record committed before celebration");
                delivery.SeriesEarned(g, id, rank, at, lines); delivered++;
                Require(sink.Notice?.ContractRecord == lines, "celebration receives record");
            });
        await runtime.TickAsync(true); Require(delivered == 5, "five new awards");
        var response = await runtime.DispatchAsync(BridgeEnvelope.Request("achievements.read", "records", 1, new { schemaVersion = 1 }, Owner), default);
        Require(response.Response.Payload.GetProperty("contractRecords").GetProperty("contract-first").GetProperty("zhCN").GetString() ==
            Facts.Lines("contract-first")!.ZhCN, "bridge returns the same local record in the Flutter wire casing");
        await runtime.TickAsync(true); Require(delivered == 5, "no replay of existing grants");
        var nextMission = Guid.NewGuid().ToString("D");
        var faster = Facts with { AcceptedAt = Start.AddDays(1), ArrivedAt = Start.AddDays(1).AddMinutes(5),
            CompletedAt = Start.AddDays(1).AddMinutes(20) };
        var observation = Observation with { MissionId = nextMission, AcceptedAt = faster.AcceptedAt,
            ArrivedAt = faster.ArrivedAt, CompletedAt = faster.CompletedAt };
        records.Capture(Owner, nextMission, faster.DisplayName, faster, () => true);
        using (var lease = contracts.Open(Owner))
            lease.Save(new(lease.Read().Runs.Append(new(nextMission, observation.HandleHash, Guid.NewGuid(),
                AcceptedAt: faster.AcceptedAt, Pending: observation)).ToArray()), () => true);
        remote.Response = Receipt with { NewlyEarned = [] };
        await runtime.TickAsync(true);
        Require(delivered == 5, "best update does not replay celebrations");
        response = await runtime.DispatchAsync(BridgeEnvelope.Request("achievements.read", "best", 1, new { schemaVersion = 1 }, Owner), default);
        Require(response.Response.Payload.GetProperty("contractRecords").GetProperty("contract-tsg-swift").GetProperty("zhCN").GetString() ==
            "最佳：在到达后 15 分 内完成战术打击群", "later acknowledgement updates the bridge best");
    }
    private static void Capture()
    {
        var root = Root(); var records = new ContractRecordStore(root); var store = new ContractAchievementStore(root);
        var tracker = new ContractRunTracker(store, records: records);
        FleetEvent Event(FleetEventType type, ContractLogEvidence data, DateTimeOffset at) => new(type, "LocalPlayer", Timestamp: at, Contract: data);
        var events = new[] {
            (Event(FleetEventType.ContractAccepted, new(Mission, Text: "真实显示名"), Start), true),
            (Event(FleetEventType.ContractObjective, new(Mission, "stage-1", Created: true), Start.AddMinutes(1)), true),
            (Event(FleetEventType.ContractObjective, new(Mission, "stage-1", State: "COMPLETED"), Start.AddMinutes(2)), true),
            (Event(FleetEventType.ContractObjective, new(Mission, "stage-2", State: "COMPLETED"), Start.AddMinutes(3)), true),
            (Event(FleetEventType.ContractEnded, new(Mission, State: "COMPLETED"), Start.AddMinutes(30)), true)
        };
        Require(tracker.Observe(Owner, Observation.HandleHash, events, () => true, ownershipCovered: true), "completion enqueued");
        using var lease = records.Open(Owner);
        var run = lease.Read().Runs[Mission];
        Require(run.DisplayName == "真实显示名" && run.StageObjectives == 2 && run.CompletedAt == Start.AddMinutes(30), "HUD name, distinct objectives including update-only evidence, and clocks");
    }
}