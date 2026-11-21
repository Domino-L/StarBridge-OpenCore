using System.Net;
using System.Net.Http.Json;
using System.Text;
using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Achievements;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Presence;
using StarBridge.HostRuntime.Support;
using StarBridge.NativeBridge;

internal static partial class ContractAchievementTests
{
    private sealed class ReaderHarness : IDisposable
    {
        internal readonly string DirectoryRoot = Root();
        internal string Log => Path.Combine(DirectoryRoot, "LIVE", "Game.log");
        internal readonly ContractAchievementStore Store;
        internal readonly ContractRecordStore Records;
        internal readonly LocalContractHistory History;
        internal readonly GameLogRuntime Game;
        internal readonly Clock Time = new();
        internal string Expected = "Pilot_A", ProcessState = "running", Session = "synthetic-game-1";
        internal DateTimeOffset StartedAt = DateTimeOffset.Parse("2026-10-18T03:00:00Z");
        internal int Queued;
        internal (BridgeAccountContext? Context, long Generation) Current = (Owner, 1);
        internal static string Header(string time) => $"<{time}> [Notice] nickname=\"Pilot_A\" playerGEID=12345\n<{time}> <Join PU> connected to shard[pub_sc_alpha_apse1_123]\n";
        internal ReaderHarness(string history = "", bool connected = true, bool contracts = true)
        {
            Directory.CreateDirectory(Path.GetDirectoryName(Log)!);
            var header = Header("2026-10-18T03:00:01Z");
            if (!connected) header = header[..header.IndexOf('\n')];
            File.WriteAllText(Log, header + "\n" + history, new UTF8Encoding(false));
            Store = new(DirectoryRoot); Records = new(DirectoryRoot); History = new(DirectoryRoot, () => Time.Now);
            Game = new(new GameLogSettingsStore(DirectoryRoot), () => Current, () => Expected,
                () => new(ProcessState, Log, StartedAt, Session), Time, false);
            if (contracts) Game.ConfigureContracts(Store, Records, History);
            Game.ContractQueued += () => Queued++;
        }
        internal void Select()
        {
            Game.Dispatch(BridgeEnvelope.Request("gameLog.select", Guid.NewGuid().ToString("N"), 1,
                new { schemaVersion = 1, path = Log }, Owner));
            Game.Sample(); Require(Game.DetectedHandle == Expected || Expected != "Pilot_A", "synthetic reader identity reaches EOF");
        }
        internal void Append(string lines) { File.AppendAllText(Log, lines, new UTF8Encoding(false)); Game.Sample(); }
        public void Dispose() { Game.Dispose(); History.Dispose(); }
    }
    private static Task RuntimeReading()
    {
        var groups = Lines().GroupBy(l => l.Source).ToArray();
        using (var live = new ReaderHarness())
        {
            live.Select();
            for (var i = 0; i < groups.Length; i++)
            {
                var text = string.Join("\n", groups[i].Select(l => l.Line.Replace(" ⏎ ", "\n"))) + "\n";
                if (i == 0) live.Append(text);
                else
                {
                    // These are our synthetic files only. A game restart changes the process/source,
                    // while the same Host tracker and heartbeat continue; startup catch-up stays historical.
                    live.ProcessState = "notRunning"; live.Game.Sample();
                    File.Move(live.Log, live.Log + ".previous-" + i);
                    live.ProcessState = "running";
                    live.StartedAt = DateTimeOffset.Parse(i switch { 1 => "2026-10-18T05:12:00Z", 2 => "2026-10-18T05:32:00Z", _ => "2026-10-18T05:57:00Z" });
                    live.Session = "synthetic-game-" + (i + 1);
                    File.WriteAllText(live.Log, ReaderHarness.Header(live.StartedAt.AddSeconds(1).ToString("O")) + text, new UTF8Encoding(false));
                    live.Game.Sample();
                }
            }
            var observation = Pending(live.Store);
            using (var records = live.Records.Open(Owner))
            {
                var facts = records.Read().Runs[observation.MissionId];
                Require(facts.StageObjectives == 38 && facts.DisplayName is { Length: > 0 } &&
                    facts.AcceptedAt == observation.AcceptedAt && facts.ArrivedAt == observation.ArrivedAt &&
                    facts.CompletedAt == observation.CompletedAt, "real reader record retains HUD name, 38 distinct stages and run clocks");
            }
            Require(observation.CompleteRun && observation.ArrivedAt == DateTimeOffset.Parse("2026-10-18T04:17:34.311Z") &&
                observation.Deaths == 0 && live.Queued == 1, "real reader: physical multiline, four sources, preserved earliest arrival, game reentry is not death");
        }
        var full = string.Join("\n", Lines().Select(l => l.Line)) + "\n";
        using (var history = new ReaderHarness(full))
        {
            history.Select(); history.Append(full);
            Require(history.Queued == 0 && Read(history.Store).Runs.All(r => r.Pending is null), "offline historical replay cannot report");
        }
        using (var disconnected = new ReaderHarness(connected: false))
        {
            disconnected.Select(); disconnected.Append(full);
            Require(disconnected.Queued == 0 && Read(disconnected.Store).Runs.Length == 0, "not connected cannot track or report");
        }
        using (var wrong = new ReaderHarness())
        {
            wrong.Expected = "Other_Pilot"; wrong.Select(); wrong.Append(full);
            Require(wrong.Queued == 0 && Read(wrong.Store).Runs.Length == 0, "verified handle mismatch cannot track or report");
        }
        using (var stopped = new ReaderHarness())
        {
            stopped.Select(); stopped.ProcessState = "notRunning"; stopped.Append(full);
            Require(stopped.Queued == 0 && Read(stopped.Store).Runs.Length == 0, "game offline cannot report");
        }
        using (var gap = new ReaderHarness())
        {
            gap.Select(); gap.Append(string.Join("\n", groups[0].Select(l => l.Line)) + "\n");
            gap.Time.Now = gap.Time.Now.AddSeconds(11);
            gap.Append(string.Join("\n", groups.Skip(1).SelectMany(g => g).Select(l => l.Line)) + "\n");
            Require(!Pending(gap.Store).CompleteRun, "missed Host sampling heartbeat is a read gap, independent of log silence");
        }
        using (var other = new ReaderHarness())
        {
            other.Select();
            var head = Lines().Where(l => !l.Line.Contains("<MissionEnded>") && !l.Line.Contains("<EndMission>")).Select(l => l.Line);
            other.Append(string.Join("\n", head) + "\n" + Lines().Single(l => l.Line.Contains("<EndMission>")).Line.Replace("Player[Pilot_A]", "Player[Other_Pilot]") + "\n");
            Require(other.Queued == 0 && Read(other.Store).Runs.All(r => r.Pending is null), "another player's EndMission is not the local outcome");
        }
        using (var fault = new ReaderHarness())
        {
            fault.Select(); fault.Append(string.Join("\n", groups[0].Select(l => l.Line)) + "\n");
            var path = Directory.GetFiles(Path.Combine(fault.DirectoryRoot, "achievements-contract-v1"), "*.json").Single();
            File.WriteAllText(path, "{}");
            fault.Append(string.Join("\n", groups.Skip(1).SelectMany(g => g).Select(l => l.Line)) + "\n");
            Require(fault.Game.CurrentSession.Server.State == "connected" && fault.Queued == 0 && File.ReadAllText(path) == "{}",
                "contract journal fault cannot invalidate existing Game.log presence");
        }
        return Task.CompletedTask;
    }

    private sealed class NoVault : ITokenVault
    {
        public void SaveRefreshToken(string a, string b) => throw new Exception("Unexpected credential write");
        public string? LoadRefreshToken(string a) => null;
        public string? LoadActiveAccountKey() => null;
        public void DeleteRefreshToken(string a) => throw new Exception("Unexpected credential deletion");
    }
    private sealed class WireHandler : HttpMessageHandler
    {
        internal int Posts; internal bool Invalid;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Require(request.Method == HttpMethod.Post && request.RequestUri!.AbsolutePath == "/app-api/starbridge/v1/achievements/observations/contract", "exact contract POST route");
            using var payload = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
            using var sample = JsonDocument.Parse(File.ReadAllText(SamplePath("contract-observation.json")));
            var expected = sample.RootElement.GetProperty("request");
            Require(payload.RootElement.EnumerateObject().Select(p => p.Name).ToHashSet().SetEquals(expected.EnumerateObject().Select(p => p.Name)), "all 12 shared wire fields, no internal validity or progress fields");
            foreach (var field in expected.EnumerateObject())
                Require(field.Name.EndsWith("At", StringComparison.Ordinal)
                    ? payload.RootElement.GetProperty(field.Name).GetDateTimeOffset() == field.Value.GetDateTimeOffset()
                    : payload.RootElement.GetProperty(field.Name).ToString() == field.Value.ToString(), "shared example value: " + field.Name);
            Require(sample.RootElement.GetProperty("contracts").EnumerateArray().Select(v => v.GetString()).SequenceEqual(StarBridge.Core.Achievements.ContractAchievementPolicy.TsgContracts), "shared whitelist");
            Posts++;
            return new(HttpStatusCode.OK) { Content = JsonContent.Create(new ContractAchievementReceipt(1,
                new() { ["contract-first"] = Ended, ["contract-tsg-lead"] = Ended }, Invalid ? ["journey-station-rr-p2-l4"] : ["contract-first", "contract-tsg-lead"], new())) };
        }
    }
    private static async Task WireContract()
    {
        // Entire transport terminates in this in-memory handler. No socket or DNS request.
        using var handler = new WireHandler(); var http = new ScmHttpClient(handler);
        var options = new ScmOAuthOptions("fixture-scm", new("http://127.0.0.1:3000/"), new("http://127.0.0.1:18080/"),
            new("http://127.0.0.1:18082/"), "starbridge-desktop", "starbridge-api", "profile.read presence.write game_identity.read", "/oauth/callback");
        var session = new ScmOAuthSession("fixture-scm", "synthetic-contract", "Synthetic", "synthetic-access",
            DateTimeOffset.UtcNow.AddHours(1), ["profile.read", "presence.write", "game_identity.read"],
            GameIdentityHandle: "Pilot_A", GameIdentityStatus: StarBridge.Core.Identity.ScmGameIdentityStatus.Verified);
        using var host = new ScmAccountBridgeHost(new OAuthPkceClient(http, new NoVault(), options),
            new ScmProfileCacheStore(Root()), "fixture", () => null, initialSession: session, initialGeneration: 1);
        using var sample = JsonDocument.Parse(File.ReadAllText(SamplePath("contract-observation.json")));
        var observation = sample.RootElement.GetProperty("request").Deserialize<ContractObservation>(new JsonSerializerOptions(JsonSerializerDefaults.Web))!;
        var remote = (IAchievementRemote)host; var owner = host.CurrentContext!;
        var receipt = await remote.ObserveContractAsync(owner, 1, observation, default);
        Require(receipt.NewlyEarned.Length == 2 && receipt.Progress!.Count == 0, "contract receipt without new progress keys");
        try { await remote.ObserveContractAsync(owner, 0, observation, default); throw new Exception("stale generation admitted"); } catch (AccountBridgeHostException) { }
        try { await remote.ObserveContractAsync(owner with { Subject = "other" }, 1, observation, default); throw new Exception("foreign account admitted"); } catch (AccountBridgeHostException) { }
        try { await remote.ObserveContractAsync(owner, 1, observation with { Outcome = "failed" }, default); throw new Exception("failed outcome admitted"); } catch (ArgumentException) { }
        Require(handler.Posts == 1, "invalid context/input rejected before handler");
        handler.Invalid = true;
        try { await remote.ObserveContractAsync(owner, 1, observation, default); throw new Exception("hidden journey marker admitted as contract grant"); } catch (InvalidDataException) { }
        foreach (var invalid in new[] { new ContractAchievementReceipt(1, new() { ["contract-first"] = Ended }, ["contract-first", "contract-first"]),
            new(1, new(), ["contract-first"]), new(1, new(), [], new() { ["contract-tsg-swift"] = 1 }) })
        { try { invalid.Validate(); throw new Exception("invalid receipt admitted"); } catch (InvalidDataException) { } }
        using var reads = JsonDocument.Parse(File.ReadAllText(SamplePath("read-response.json")));
        var contracts = reads.RootElement.GetProperty("withContracts").Deserialize<AchievementSnapshot>(new JsonSerializerOptions(JsonSerializerDefaults.Web))!;
        contracts.Validate(); Require(contracts.EarnedAt.Count == 5 && contracts.Progress!.Count == 0, "old progress whitelist unchanged");
    }
}
