using System.Text;
using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Presence;
using StarBridge.HostRuntime.Support;
using StarBridge.NativeBridge;

internal static class LocalMissionRecordsTests
{
    internal static readonly BridgeAccountContext Owner = new("test", "scm", "synthetic-mission-owner");
    internal const string Mission = "00000000-0000-0000-0000-000000000073";
    internal const string Definition = "00000000-0000-0000-0000-000000000074";
    internal const string Code = "InterSec_Nyx_TSG_FullStrikeOnStation";
    internal static readonly DateTimeOffset At = DateTimeOffset.Parse("2026-10-18T03:30:00Z");
    private static readonly UTF8Encoding Utf8 = new(false);
    internal static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
    internal static string Accepted(string mission = Mission, int seconds = 0) =>
        $"<{At.AddSeconds(seconds):O}> <SHUDEvent_OnNotification> Added notification \"Contract Accepted: [Synthetic]示例合约\" MissionId: {mission}";
    private static string[] AcceptedMultiline(string mission = Mission) =>
        [$"<{At:O}> [Notice] <SHUDEvent_OnNotification> Added notification \"已接受合约：需要战术打击群",
         $"<{At.AddSeconds(5):O}> [互安防务 - 战术打击群]<EM4>[蓝图]</EM4>: \" [10] to queue. New queue size: 1, MissionId: [{mission}], ObjectiveId: [] [Team_CoreGameplayFeatures][Missions][Comms]"];
    internal static string Defined(string mission = Mission) =>
        $"<{At.AddSeconds(1):O}> <CLocalMissionPhaseMarker::CreateMarker> contract[{Code}][{Definition}] missionId [{mission}]";
    internal static string Ended(string mission = Mission, string state = "COMPLETED", int seconds = 60) =>
        $"<{At.AddSeconds(seconds):O}> <MissionEnded> mission_id [{mission}] mission_state MISSION_STATE_{state}";
    private static string Identity(string name = "Pilot_A") => $"<{At:O}> [Notice] nickname=\"{name}\" playerGEID=12345";
    private static LocalMissionRecord Row(string mission = Mission, string? definition = Definition, string? code = Code,
        DateTimeOffset? accepted = null, DateTimeOffset? completed = null) => new(mission, definition, code, accepted, completed ?? At.AddSeconds(60), "import", false, false, null, 0);

    internal static string Shared(string mission = Mission, int seconds = -1) =>
        $"<{At.AddSeconds(seconds):O}> [Notice] <MissionShared> Received share push message: ownerId[67890] - missionId[{mission}] [Team_GameServices][Missions]";
    internal static string PlayerJoined(string player = "67890", int seconds = 1, string mission = Mission) =>
        $"<{At.AddSeconds(seconds):O}> [Notice] <PlayerJoined> Received PlayerJoined push message for: mission_id {mission} - player_id {player} [Team_GameServices][Missions]";
    private static string Objective(string state = "INPROGRESS", int created = 1, int seconds = 0, string prefix = "") =>
        $"<{At.AddSeconds(seconds):O}> [Notice] <ObjectiveUpserted> Received ObjectiveUpserted push message for: mission_id {Mission} - objective_id {prefix}{Definition} - state MISSION_OBJECTIVE_STATE_{state} - created {created} [Team_GameServices][Missions]";
    internal static string LiveObjective() => Objective(seconds: 2);

    private static Task Participation()
    {
        var cases = new (string Name, string[] Evidence, bool Full)[] {
            ("new in-progress objective", [Objective()], true),
            ("completion within ten seconds", [Objective(), Objective("COMPLETED", 0, 10)], false),
            ("completion after ten seconds", [Objective(), Objective("COMPLETED", 0, 11)], true),
            ("no objective", [], false),
            ("first objective already existed", [Objective(created: 0)], false),
            ("first objective completed", [Objective("COMPLETED"), Objective(seconds: 2)], false),
            ("phase objectives ignored", [Objective("COMPLETED", 0, 0, "phase_"), Objective(seconds: 1)], true),
            ("only phase objective", [Objective(prefix: "phase_")], false),
            ("HUD objective is not a push", [Objective().Replace("<ObjectiveUpserted>", "<ObjectiveComplete>")], false),
            ("objective before sharing ignored", [Objective(seconds: -2)], false),
            ("objective after completion ignored", [Objective(seconds: 61)], false)
        };
        foreach (var test in cases)
        {
            using var f = new Fixture();
            f.Write("joined.log", [Identity(), Shared(), Accepted(), Defined(), .. test.Evidence,
                PlayerJoined(seconds: -1), PlayerJoined(), PlayerJoined("12345"), Ended()]);
            var row = GameplayHistoryScanner.ScanMissions(f.Log, "Pilot_A").Records.Single();
            var group = LocalMissionRecords.Summarize([row]).Single();
            Check(row.Joined == true && row.JoinedFromStart == test.Full && row.Teammates == 1, test.Name + " classification and distinct teammates");
            Check(group.Count == 1 && group.FastestSeconds is null && group.SoloFastestSeconds is null &&
                group.TeamFastestSeconds is null && group.JoinedFullFastestSeconds == (test.Full ? (double?)60 : null) &&
                group.JoinedPartialFastestSeconds == (test.Full ? null : (double?)60), test.Name + " joined timing only");
        }
        using var noAcceptance = new Fixture();
        noAcceptance.Write("joined.log", Identity(), Shared(), Objective(), Ended());
        var missing = GameplayHistoryScanner.ScanMissions(noAcceptance.Log, "Pilot_A").Records.Single();
        Check(missing.Joined == true && missing.JoinedFromStart == false && missing.AcceptedAt is null,
            "missing acceptance and marker counts without timing");
        using var markerOnly = new Fixture();
        markerOnly.Write("joined.log", Identity(), Shared(), Defined(), Objective(seconds: 2), Ended());
        var marked = GameplayHistoryScanner.ScanMissions(markerOnly.Log, "Pilot_A").Records.Single();
        var markedGroup = LocalMissionRecords.Summarize([marked]).Single();
        Check(marked.Joined == true && marked.JoinedFromStart == true && marked.AcceptedAt == At.AddSeconds(1) &&
            markedGroup.JoinedFullFastestSeconds == 59 && markedGroup.JoinedPartialFastestSeconds is null,
            "joined acceptance falls back to the first marker");
        return Task.CompletedTask;
    }

    // 2025 builds wrote no HUD notification lines; the first CreateMarker stands in for acceptance.
    private static Task MarkerFallback()
    {
        static string Marker(string mission, int seconds) =>
            Defined(mission).Replace(At.AddSeconds(1).ToString("O"), At.AddSeconds(seconds).ToString("O"));
        using var f = new Fixture();
        // Later marker first: the earliest wins regardless of line order.
        f.Write("old.log", Identity(), Marker(Mission, 30), Defined(), Ended(seconds: 600));
        var solo = GameplayHistoryScanner.ScanMissions(f.Log, "Pilot_A").Records.Single();
        Check(solo.AcceptedAt == At.AddSeconds(1) && solo is { Joined: false, Team: false },
            "owner acceptance falls back to the earliest marker");
        Check(LocalMissionRecords.Summarize([solo]).Single().SoloFastestSeconds == 599, "marker fallback times solo runs");
        using var modern = new Fixture();
        var hud = Guid.NewGuid().ToString(); var rebuilt = Guid.NewGuid().ToString();
        modern.Write("modern.log", Identity(), Defined(hud), Accepted(hud, 5), Ended(hud, seconds: 65),
            Marker(rebuilt, 20), Ended(rebuilt, seconds: 90));
        var rows = GameplayHistoryScanner.ScanMissions(modern.Log, "Pilot_A").Records;
        Check(rows.Single(r => r.MissionId == hud).AcceptedAt == At.AddSeconds(5), "HUD acceptance wins over an earlier marker");
        Check(rows.Single(r => r.MissionId == rebuilt).AcceptedAt is null,
            "a file that writes HUD notices never uses markers (rebuilt after a reconnect)");
        using var joined = new Fixture();
        joined.Write("joined.log", Identity(), Defined(), Shared(seconds: 5), Marker(Mission, 10), Ended());
        var share = GameplayHistoryScanner.ScanMissions(joined.Log, "Pilot_A").Records.Single();
        Check(share.Joined == true && share.AcceptedAt == At.AddSeconds(10), "joined runs only use markers after the share push");
        // An earlier import that missed the share archive stored a pre-share marker; the joined side wins in both orders.
        var preShare = Row(accepted: At.AddSeconds(1));
        var joinedRow = Row(accepted: At.AddSeconds(10)) with { Joined = true, JoinedFromStart = false };
        Check(LocalMissionRecordsStore.MergeFields(preShare, joinedRow).AcceptedAt == At.AddSeconds(10) &&
            LocalMissionRecordsStore.MergeFields(joinedRow, preShare).AcceptedAt == At.AddSeconds(10),
            "stored merge keeps the share bound once the share is found");
        Check(LocalMissionRecordsStore.MergeFields(Row(accepted: At.AddSeconds(3)), Row(accepted: At.AddSeconds(1))).AcceptedAt == At.AddSeconds(1),
            "same-role merge keeps the earliest acceptance");
        using var split = new Fixture();
        split.Write("a.log", Identity(), Defined());
        split.Write("b.log", Identity(), Defined().Replace(At.AddSeconds(1).ToString("O"), At.AddSeconds(40).ToString("O")), Ended(seconds: 300));
        Check(GameplayHistoryScanner.ScanMissions(split.Log, "Pilot_A").Records.Single().AcceptedAt == At.AddSeconds(1),
            "earliest marker across archive files");
        return Task.CompletedTask;
    }

    private static Task OwnerTiming()
    {
        using var f = new Fixture();
        var teamId = Guid.NewGuid().ToString();
        f.Write("owners.log", Identity(), Accepted(), Defined(), PlayerJoined("12345"), PlayerJoined(seconds: -1),
            PlayerJoined(seconds: 61), Ended(), Accepted(teamId), Defined(teamId), PlayerJoined(mission: teamId),
            PlayerJoined(mission: teamId), PlayerJoined("98765", mission: teamId), Ended(teamId, seconds: 90));
        var rows = GameplayHistoryScanner.ScanMissions(f.Log, "Pilot_A").Records;
        Check(rows.Single(r => r.MissionId == Mission) is { Joined: false, Team: false, Teammates: 0 } &&
            rows.Single(r => r.MissionId == teamId) is { Joined: false, Team: true, Teammates: 2 }, "self, outside interval and duplicate players excluded");
        var group = LocalMissionRecords.Summarize(rows).Single();
        Check(group.Count == 2 && group.SoloFastestSeconds == 60 && group.TeamFastestSeconds == 90 && group.FastestSeconds == 60,
            "owner solo and team fastest separated");
        f.Write("owners.log", $"<{At:O}> nickname=\"Pilot_A\" playerGEID", Accepted(), Defined(), PlayerJoined(), Ended());
        Check(GameplayHistoryScanner.ScanMissions(f.Log, "Pilot_A").Records.Single() is { Team: false, Teammates: 0 },
            "unknown own GEID conservatively ignores joins");
        return Task.CompletedTask;
    }

    private static async Task RoleEnrichment()
    {
        using var f = new Fixture();
        var old = Row(accepted: At) with { Joined = null, Team = null, JoinedFromStart = null, Teammates = null };
        await f.Save(old);
        Check(LocalMissionRecords.Summarize((await f.Read()).Records).Single().FastestSeconds is null,
            "unclassified old record never enters fastest");
        f.Write("roles.log", Identity(), Shared(), Accepted(), Defined(), Objective(), PlayerJoined(), Ended(seconds: 90));
        var merged = await f.Save(GameplayHistoryScanner.ScanMissions(f.Log, "Pilot_A").Records);
        var row = (await f.Read()).Records.Single();
        Check(merged == new MissionRecordsMergeResult(0, 1) && row is { Joined: true, Team: false, JoinedFromStart: true, Teammates: 1 } &&
            row.CompletedAt == old.CompletedAt, "reimport enriches roles without changing completion or count");
        var group = LocalMissionRecords.Summarize([row]).Single();
        Check(group.FastestSeconds is null && group.JoinedFullFastestSeconds == 60, "shared enrichment excluded from owner fastest");
        await f.Save(row with { Joined = true, Team = true, JoinedFromStart = false, Teammates = 3 });
        await f.Save(row);
        Check((await f.Read()).Records.Single() is { Joined: true, Team: true, JoinedFromStart: false, Teammates: 3 },
            "role OR, full AND, teammate maximum are monotonic");
        var json = File.ReadAllText(Path.Combine(f.Store.DirectoryFor(Owner)!, "records.json"));
        Check(!json.Contains("67890") && !json.Contains("12345") && !json.Contains("playerId"), "only teammate count persists");
    }

    private static Task NonJoinedParticipation()
    {
        using var f = new Fixture();
        f.Write("owner.log", Identity(), Accepted(), Defined(), Objective(), Ended());
        Check(GameplayHistoryScanner.ScanMissions(f.Log, "Pilot_A").Records.Single() is
            { Joined: false, JoinedFromStart: null }, "owner record has no joined participation marker");
        return Task.CompletedTask;
    }

    private static async Task JoinedMergeAcrossSources()
    {
        var full = Row(accepted: At) with { Joined = true, JoinedFromStart = true };
        var cases = new (string Name, LocalMissionRecord Other, bool? Joined, bool? Full)[] {
            ("live owner without share", Row(accepted: At) with { Source = "live" }, true, true),
            ("old live owner false marker", Row(accepted: At) with { Source = "live", JoinedFromStart = false }, true, true),
            ("unclassified false marker", Row(accepted: At) with { Joined = null, JoinedFromStart = false }, true, true),
            ("joined partial", full with { Source = "live", JoinedFromStart = false }, true, false),
            ("joined unknown", full with { Source = "live", JoinedFromStart = null }, true, true)
        };
        foreach (var test in cases)
        foreach (var reverse in new[] { false, true })
        {
            using var f = new Fixture();
            await f.Save(reverse ? full : test.Other);
            await f.Save(reverse ? test.Other : full);
            var row = (await f.Read()).Records.Single();
            Check(row.Joined == test.Joined && row.JoinedFromStart == test.Full,
                test.Name + " participation merge, reverse=" + reverse);
        }
        var unknown = full with { JoinedFromStart = null };
        Check(LocalMissionRecordsStore.MergeFields(unknown, unknown).JoinedFromStart is null,
            "joined records without participation stay unknown");
        var owner = full with { Joined = false };
        Check(LocalMissionRecordsStore.MergeFields(owner, owner).JoinedFromStart is null,
            "merged owner records discard participation markers");
    }

    private static Task RepeatedObjectivePushes()
    {
        foreach (var partial in new[] { false, true })
        {
            using var f = new Fixture();
            string[] ending = partial ? [Objective("COMPLETED", 0, 10), Ended()] : [Ended()];
            f.Write("joined.log", [Identity(), Shared(), Accepted(), Defined(), Objective(), .. ending]);
            var expected = GameplayHistoryScanner.ScanMissions(f.Log, "Pilot_A").Records.Single();
            f.Write("joined.log", [Identity(), Shared(), Accepted(), Defined(),
                .. Enumerable.Repeat(Objective(), 10000), .. ending]);
            var repeated = GameplayHistoryScanner.ScanMissions(f.Log, "Pilot_A").Records.Single();
            Check(expected.JoinedFromStart == !partial && repeated == expected,
                "duplicate objective pushes preserve full/partial classification, partial=" + partial);
        }
        return Task.CompletedTask;
    }

    private static Task EvidenceLimits()
    {
        using var f = new Fixture();
        f.Write("a.log", [Identity(), Shared(), Accepted(), Defined(),
            .. Enumerable.Range(11, 300).Select(i => Objective(created: 0, seconds: i)), Objective(),
            .. Enumerable.Range(20000, 300).Select(i => PlayerJoined(i.ToString())), Ended(seconds: 400)]);
        var row = GameplayHistoryScanner.ScanMissions(f.Log, "Pilot_A").Records.Single();
        Check(row is { JoinedFromStart: true, Teammates: 300 },
            "many distinct objectives and participants keep the classification inputs");
        f.Write("b.log", Identity(), Objective("COMPLETED", 0, 10));
        row = GameplayHistoryScanner.ScanMissions(f.Log, "Pilot_A").Records.Single();
        Check(row is { JoinedFromStart: false, Teammates: 300 },
            "cross-file early completion is never dropped by later evidence");
        return Task.CompletedTask;
    }

    private static async Task LegacyAndCrossFileRoles()
    {
        using var f = new Fixture();
        var path = Path.Combine(f.Store.DirectoryFor(Owner)!, "records.json");
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, JsonSerializer.Serialize(new { records = new[] { new { missionId = Mission,
            definitionId = Definition, contractCode = Code, acceptedAt = At, completedAt = At.AddSeconds(60), source = "import" } }, dropped = 0 }), Utf8);
        var legacy = (await f.Read()).Records.Single();
        Check(legacy.Joined is null && legacy.Team is null && legacy.JoinedFromStart is null && legacy.Teammates is null,
            "legacy JSON without new fields reads with null values");
        f.Write("a.log", Shared(), PlayerJoined(seconds: -1), Identity());
        f.Write("b.log", Identity(), Accepted(), Defined(), Objective(), Ended());
        var rows = GameplayHistoryScanner.ScanMissions(f.Log, "Pilot_A").Records;
        Check(rows.Single() is { Joined: true, JoinedFromStart: true, Teammates: 1 }, "cross-file sharing, late identity and objectives merged before classification");
        Check(await f.Save(rows) == new MissionRecordsMergeResult(0, 1), "cross-file reimport enriches existing ID");
    }

    private sealed class Fixture : IDisposable
    {
        internal readonly string Root = Directory.CreateTempSubdirectory("sb-mission-records-").FullName;
        internal readonly LocalMissionRecords Store;
        internal string Log => Path.Combine(Root, "LIVE", "Game.log");
        internal string Backups => Path.Combine(Root, "LIVE", "logbackups");
        internal Fixture()
        {
            Store = new(Root);
            Directory.CreateDirectory(Backups);
            File.WriteAllText(Log, Identity() + "\n" + Ended(Guid.NewGuid().ToString()), Utf8);
        }
        internal void Write(string file, params string[] lines) => File.WriteAllText(Path.Combine(Backups, file), string.Join("\n", lines) + "\n", Utf8);
        internal Task<MissionRecordsMergeResult> Save(params LocalMissionRecord[] rows) => Store.MergeAsync(Owner, rows, () => true);
        internal Task<MissionRecordsSnapshot> Read() => Store.ReadAsync(Owner);
        public void Dispose() { Store.DisposeAsync().AsTask().GetAwaiter().GetResult(); Directory.Delete(Root, true); }
    }

    private static async Task Storage()
    {
        using var f = new Fixture();
        var first = Row(definition: null, code: null, accepted: At.AddSeconds(10));
        Check((await f.Save(first)).Added == 1, "first completion added");
        var merged = await f.Save(Row(accepted: At), first with { AcceptedAt = null, CompletedAt = At.AddHours(1) });
        var row = (await f.Read()).Records.Single();
        Check(merged == new MissionRecordsMergeResult(0, 1) && row.AcceptedAt == At && row.DefinitionId == Definition &&
            row.ContractCode == Code && row.CompletedAt == first.CompletedAt, "dedup enriches; immutable first completion; earliest acceptance");
        using var otherOrder = new Fixture();
        await otherOrder.Save(Row(accepted: At), first);
        Check((await otherOrder.Read()).Records.Single() == row, "empty fields and acceptance independent of input order");
        await f.Save(Row(Guid.Empty.ToString()), Row("not-a-guid"));
        Check((await f.Read()).Records.Length == 1, "only nonzero GUIDs");
        var other = Owner with { Subject = "synthetic-other" };
        Check((await f.Store.ReadAsync(other)).Records.Length == 0 && f.Store.DirectoryFor(other) != f.Store.DirectoryFor(Owner), "account isolation");
        try { f.Store.DirectoryFor(Owner with { Subject = "" }); throw new Exception("incomplete owner accepted"); }
        catch (InvalidDataException) { }
        using var history = new LocalContractHistory(f.Root);
        Check(Path.GetFileName(f.Store.DirectoryFor(Owner)) == Path.GetFileName(history.DirectoryFor(Owner)), "canonical account hash");
        try { await f.Store.MergeAsync(Owner, [Row(Guid.NewGuid().ToString())], () => false); throw new Exception("stale commit accepted"); }
        catch (OperationCanceledException) { }
        Check((await f.Read()).Records.Length == 1, "stale commit writes nothing");
    }

    private static async Task Capacity()
    {
        using var f = new Fixture();
        var rows = Enumerable.Range(0, 20002).Select(i => Row(new Guid(i + 1, 0, 0, new byte[8]).ToString(), completed: At.AddSeconds(i))).ToArray();
        await f.Store.MergeAsync(Owner, rows, () => true);
        var disk = await f.Read();
        Check(disk.Records.Length == 20000 && disk.Dropped == 2 && disk.Records.Min(r => r.CompletedAt) == At.AddSeconds(2), "cap evicts oldest and persists count");
        Check(disk.Records.Any(r => r.CompletedAt == At.AddSeconds(20001)), "latest retained without day retention");
    }

    private static async Task Backup()
    {
        using var f = new Fixture();
        await f.Save(Row());
        await f.Save(Row(Guid.NewGuid().ToString()));
        var path = Path.Combine(f.Store.DirectoryFor(Owner)!, LocalMissionRecordsStore.FileName);
        File.WriteAllText(path, "{broken", Utf8);
        Check((await f.Read()).Records.Single().MissionId == Mission, "backup restores corrupt primary");
        await f.Save(Row());
        Check((await f.Read()).Records.Length == 1, "recovered snapshot writable");
        File.WriteAllText(path, "null", Utf8); File.WriteAllText(path + ".bak", "[]", Utf8);
        Check((await f.Read()).Records.Length == 0, "both invalid files become empty");
        using (var lease = new FileStream(path + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None))
        {
            try { await f.Read(); throw new Exception("lease ignored"); } catch (IOException) { }
        }
        Check(!Directory.EnumerateFiles(Path.GetDirectoryName(path)!, "*.tmp").Any(), "atomic temporary cleanup");
    }

    private static async Task Summary()
    {
        using var f = new Fixture();
        await f.Save(Row(accepted: At), Row(Guid.NewGuid().ToString(), accepted: At.AddSeconds(30)),
            Row(Guid.NewGuid().ToString(), accepted: At.AddSeconds(60)),
            Row(Guid.NewGuid().ToString(), accepted: At.AddSeconds(90)),
            Row(Guid.NewGuid().ToString(), definition: null), Row(Guid.NewGuid().ToString(), definition: null, code: null));
        var snapshot = await f.Read();
        var groups = LocalMissionRecords.Summarize(snapshot.Records);
        var known = groups.Single(g => g.Key == Definition);
        Check(groups.Count == 2 && known.Count == 4 && known.FastestSeconds == 30 && known.LastCompletedAt == At.AddSeconds(60), "definition groups and positive complete timings");
        var unknown = groups.Single(g => g.Key == "code:" + Code);
        Check(unknown.Count == 1 && unknown.FastestSeconds is null && snapshot.Records.Length == 6, "fallback code; unkeyed completion still stored");
    }

    private static async Task ImportReplay()
    {
        using var f = new Fixture();
        f.Write("a.log", Identity(), Accepted(), Defined());
        f.Write("b.log", Identity(), Ended(), Ended(seconds: 70));
        var scan = GameplayHistoryScanner.ScanMissions(f.Log, "Pilot_A");
        Check(scan.FilesScanned == 2 && scan.FilesSkipped == 0 && scan.Records.Single().AcceptedAt == At &&
            scan.Records.Single().DefinitionId == Definition, "cross-file acceptance definition and completion");
        var first = await f.Store.MergeAsync(Owner, scan.Records, () => true);
        var second = await f.Store.MergeAsync(Owner, GameplayHistoryScanner.ScanMissions(f.Log, "Pilot_A").Records, () => true);
        Check(first == new MissionRecordsMergeResult(1, 0) && second == new MissionRecordsMergeResult(0, 1) &&
            LocalMissionRecords.Summarize((await f.Read()).Records).Single().Count == 1, "unlimited repeat import dedup");
        f.Write("a.log", Identity(), Accepted(seconds: -10), Defined());
        await f.Store.MergeAsync(Owner, GameplayHistoryScanner.ScanMissions(f.Log, "Pilot_A").Records, () => true);
        Check((await f.Read()).Records.Single().AcceptedAt == At.AddSeconds(-10), "later import enriches acceptance");
    }

    private static async Task ImportMultiline()
    {
        using var f = new Fixture();
        var english = Guid.NewGuid().ToString();
        f.Write("multiline.log", [Identity(), .. AcceptedMultiline(), Defined(), Ended(),
            Accepted(english, 10), Defined(english), Ended(english, seconds: 90)]);
        var scan = GameplayHistoryScanner.ScanMissions(f.Log, "Pilot_A");
        Check(scan.FilesSkipped == 0 && scan.Records.Length == 2, "both localized multiline and English single-line accepted");
        var localized = scan.Records.Single(r => r.MissionId == Mission);
        var single = scan.Records.Single(r => r.MissionId == english);
        Check(localized.AcceptedAt == At && localized.DefinitionId == Definition && localized.CompletedAt == At.AddSeconds(60),
            "multiline acceptance keeps first physical timestamp, definition and completion");
        Check(single.AcceptedAt == At.AddSeconds(10) && single.DefinitionId == Definition && single.CompletedAt == At.AddSeconds(90),
            "English single-line acceptance unchanged");
        Check(await f.Save(scan.Records) == new MissionRecordsMergeResult(2, 0), "first mixed import adds two missions");
        var repeated = GameplayHistoryScanner.ScanMissions(f.Log, "Pilot_A");
        Check(await f.Save(repeated.Records) == new MissionRecordsMergeResult(0, 2) && (await f.Read()).Records.Length == 2 &&
            LocalMissionRecords.Summarize((await f.Read()).Records).Single().Count == 2, "repeated multiline import never double counts");
    }

    private static async Task ImportMultilineEnrichment()
    {
        await using var f = new BridgeFixture();
        f.Files.Write("enrich.log", Identity(), Ended());
        var id = (await f.Call("importStart")).Payload.GetProperty("scanId").GetString()!;
        var first = (await f.Finish(id)).Payload.GetProperty("result");
        var original = (await f.Files.Read()).Records.Single();
        Check(first.GetProperty("added").GetInt32() == 1 && original.AcceptedAt is null && original.DefinitionId is null,
            "old import lacks acceptance and marker");
        f.Files.Write("enrich.log", [Identity(), .. AcceptedMultiline(), Defined(), Ended(seconds: 90)]);
        id = (await f.Call("importStart")).Payload.GetProperty("scanId").GetString()!;
        var result = (await f.Finish(id)).Payload.GetProperty("result");
        var rows = (await f.Files.Read()).Records;
        var row = rows.Single();
        var summary = LocalMissionRecords.Summarize(rows).Single();
        Check(result.GetProperty("added").GetInt32() == 0 && result.GetProperty("alreadyKnown").GetInt32() == 1,
            "enrichment import reports Added 0, AlreadyKnown 1");
        Check(row.AcceptedAt == At && row.CompletedAt == original.CompletedAt && row.DefinitionId == Definition,
            "reimport fills acceptance without changing first completion");
        Check(summary.Count == 1 && summary.FastestSeconds == 60, "enrichment restores fastest duration without incrementing count");
    }

    private static Task ImportMultilineBoundaries()
    {
        var parts = AcceptedMultiline();
        var diagnostic = $"<{At.AddSeconds(2):O}> [Notice] <PlayerOnline> diagnostic";
        var cases = new (string Name, string[] Lines)[] {
            ("non-trailer diagnostic cannot continue", [Identity(), parts[0], diagnostic, Defined(), Ended()]),
            ("intervening diagnostic discards pending", [Identity(), parts[0], diagnostic, parts[1], Defined(), Ended()]),
            ("non-queue trailer cannot continue", [Identity(), parts[0], parts[1].Replace("to queue.", "diagnostic."), Defined(), Ended()]),
            ("incomplete EOF discarded", [Identity(), Defined(), Ended(), parts[0]]),
            ("combined length exceeds shared limit", [Identity(), parts[0] + new string('x', 65000),
                parts[1].Replace("[互安防务", new string('y', 1000) + "[互安防务"), Defined(), Ended()]),
        };
        foreach (var test in cases)
        {
            using var f = new Fixture();
            f.Write("boundary.log", test.Lines);
            var row = GameplayHistoryScanner.ScanMissions(f.Log, "Pilot_A").Records.Single();
            // The file writes HUD lines, so its marker is not a fallback either.
            Check(row.AcceptedAt is null && row.DefinitionId == Definition && row.CompletedAt == At.AddSeconds(60), test.Name);
        }
        using var split = new Fixture();
        split.Write("first.log", Identity(), parts[0]);
        split.Write("second.log", Identity(), parts[1], Defined(), Ended());
        // second.log has only the trailer (no HUD tag), so its marker is the fallback (At+1), not the notice (At).
        Check(GameplayHistoryScanner.ScanMissions(split.Log, "Pilot_A").Records.Single().AcceptedAt == At.AddSeconds(1),
            "pending notification never crosses archive files");
        using var identity = new Fixture();
        identity.Write("identity.log", Identity(), parts[0], Identity("Other_Pilot"), parts[1], Defined(), Ended());
        var scan = GameplayHistoryScanner.ScanMissions(identity.Log, "Pilot_A");
        Check(scan.FilesSkipped == 1 && scan.Records.Length == 0, "intervening identity is still observed on its physical line");
        return Task.CompletedTask;
    }

    private static Task ImportIdentity()
    {
        using var f = new Fixture();
        f.Write("foreign.log", Identity("Other_Pilot"), Ended());
        f.Write("missing.log", Ended());
        f.Write("ambiguous.log", Identity(), Identity("Other_Pilot"), Ended());
        f.Write("valid.log", Identity(), Ended());
        f.Write("failure.log", Identity(), Ended(Guid.NewGuid().ToString(), "FAILED"), Ended(Guid.NewGuid().ToString(), "ABANDONED"), Ended(Guid.NewGuid().ToString(), "WITHDRAWN"));
        using (var locked = new FileStream(Path.Combine(f.Backups, "locked.log"), FileMode.CreateNew, FileAccess.ReadWrite, FileShare.None))
        {
            var scan = GameplayHistoryScanner.ScanMissions(f.Log, "Pilot_A");
            Check(scan.FilesScanned == 6 && scan.FilesSkipped == 4 && scan.Records.Length == 1 && scan.Records[0].AcceptedAt is null,
                "identity missing foreign ambiguous and unreadable skipped; anchor content excluded; completion alone retained");
        }
        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();
        try { GameplayHistoryScanner.ScanMissions(f.Log, "Pilot_A", cancellation.Token); throw new Exception("cancel ignored"); }
        catch (OperationCanceledException) { }
        using var duringScan = new CancellationTokenSource();
        try
        {
            GameplayHistoryScanner.ScanMissions(f.Log, "Pilot_A", duringScan.Token,
                p => { if (p.ProcessedFiles == 1) duringScan.Cancel(); });
            throw new Exception("in-progress cancellation ignored");
        }
        catch (OperationCanceledException) { }
        try { GameplayHistoryScanner.ScanMissions(f.Log.Replace("LIVE", "PTU"), "Pilot_A"); throw new Exception("PTU allowed"); }
        catch (GameplayTimeException e) { Check(e.Code == "gameplay.history_path", "LIVE path only"); }
        return Task.CompletedTask;
    }

    private sealed class BridgeFixture : IAsyncDisposable
    {
        internal readonly Fixture Files = new();
        internal readonly MissionRecordsRuntime Runtime;
        internal (BridgeAccountContext? Context, long Generation) Current = (Owner, 1);
        internal string? Reason;
        internal string Handle = "Pilot_A";
        internal BridgeFixture() => Runtime = new(Files.Store, () => Current, () => Reason, () => Handle, () => Files.Log);
        internal async Task<BridgeEnvelope> Call(string name, object? payload = null, long? generation = null) =>
            (await Runtime.DispatchAsync(BridgeEnvelope.Request("missionRecords." + name, Guid.NewGuid().ToString("N"),
                generation ?? Current.Generation, payload ?? new { schemaVersion = 1 }, Current.Context))).Response;
        internal async Task<BridgeEnvelope> Finish(string id)
        {
            for (var i = 0; i < 500; i++)
            {
                var response = await Call("importRead", new { schemaVersion = 1, scanId = id });
                if (response.Payload.GetProperty("phase").GetString() is "done" or "cancelled" or "failed") return response;
                await Task.Delay(10);
            }
            throw new Exception("scan did not exit");
        }
        public async ValueTask DisposeAsync() { await Runtime.DisposeAsync(); Files.Dispose(); }
    }

    // All rows saved before the role split are counted until a reimport classifies them.
    private static async Task BridgeUnclassified()
    {
        await using var f = new BridgeFixture();
        await f.Files.Save(new LocalMissionRecord(Guid.NewGuid().ToString(), Definition, Code, At, At.AddSeconds(60), "import"),
            Row(Guid.NewGuid().ToString(), accepted: At),
            new LocalMissionRecord(Guid.NewGuid().ToString(), Definition, Code, null, At.AddSeconds(60), "import"));
        var summary = (await f.Call("summary")).Payload;
        Check(summary.GetProperty("unclassified").GetInt32() == 2 && summary.GetProperty("total").GetInt32() == 3,
            "unclassified counts legacy rows with and without acceptance");
    }

    private static async Task Bridge()
    {
        await using var f = new BridgeFixture();
        f.Files.Write("done.log", Identity(), Accepted(), Defined(), Ended());
        var summary = await f.Call("summary");
        Check(summary.Payload.GetProperty("schemaVersion").GetInt32() == 1 && summary.Payload.GetProperty("total").GetInt32() == 0 &&
            summary.Payload.GetProperty("importAvailable").GetBoolean() && !summary.Payload.TryGetProperty("importUnavailableReason", out _) &&
            summary.Payload.GetProperty("unclassified").GetInt32() == 0, "summary shape");
        var start = await f.Call("importStart");
        var id = start.Payload.GetProperty("scanId").GetString()!;
        Check(start.Payload.EnumerateObject().Count() == 1 && Guid.TryParseExact(id, "N", out _), "start shape");
        var done = (await f.Finish(id)).Payload;
        Check(done.GetProperty("phase").GetString() == "done" && done.GetProperty("filesDone").GetInt32() == 1 &&
            done.GetProperty("bytesDone").GetInt64() > 0 && done.GetProperty("result").GetProperty("completedFound").GetInt32() == 1 &&
            done.GetProperty("result").GetProperty("added").GetInt32() == 1, "poll shape and result");
        var group = (await f.Call("summary")).Payload.GetProperty("groups")[0];
        Check(group.GetProperty("key").GetString() == Definition && group.GetProperty("definitionId").GetString() == Definition &&
            group.GetProperty("contractCode").GetString() == Code && group.GetProperty("count").GetInt32() == 1 &&
            group.GetProperty("fastestSeconds").GetDouble() == 60 && group.GetProperty("lastCompletedAt").GetDateTimeOffset().Offset == TimeSpan.Zero,
            "summary group shape and UTC");
        Check(group.GetProperty("soloFastestSeconds").GetDouble() == 60 &&
            group.GetProperty("teamFastestSeconds").ValueKind == JsonValueKind.Null &&
            group.GetProperty("joinedFullFastestSeconds").ValueKind == JsonValueKind.Null &&
            group.GetProperty("joinedPartialFastestSeconds").ValueKind == JsonValueKind.Null, "camelCase role timing payload");
        var repeated = (await f.Call("importStart")).Payload.GetProperty("scanId").GetString()!;
        Check((await f.Finish(repeated)).Payload.GetProperty("result").GetProperty("alreadyKnown").GetInt32() == 1, "bridge repeat allowed");
        f.Runtime.Scanner = (_, _, _, _) => throw new IOException("synthetic unreadable archive scope");
        var failed = (await f.Call("importStart")).Payload.GetProperty("scanId").GetString()!;
        Check((await f.Finish(failed)).Payload.GetProperty("phase").GetString() == "failed", "failed scan phase");
        foreach (var name in new[] { "summary", "importStart", "importRead", "importCancel" })
            Check((await f.Call(name, name is "importRead" or "importCancel" ? new { schemaVersion = 1, scanId = id } : null,
                generation: 0)).Error?.Code == "missionRecords.accountChanged", "old generation rejected: " + name);
        Check((await f.Call("importRead", new { schemaVersion = 1, scanId = "bad" })).Error?.Code == "missionRecords.invalidRequest", "strict scan id");
        Check((await f.Call("summary", new { schemaVersion = 2 })).Error?.Code == "missionRecords.invalidRequest", "strict schema");
        foreach (var reason in new[] { "signedOut", "identityUnverified", "consentMissing", "localMode" })
        {
            f.Reason = reason;
            var unavailable = await f.Call("importStart");
            summary = await f.Call("summary");
            Check(unavailable.Error?.Code == "missionRecords.unavailable" && unavailable.Payload.GetProperty("reason").GetString() == reason &&
                !summary.Payload.GetProperty("importAvailable").GetBoolean() && summary.Payload.GetProperty("importUnavailableReason").GetString() == reason, "admission: " + reason);
        }
    }

    private static async Task CancelBusy()
    {
        await using var f = new BridgeFixture();
        f.Runtime.Scanner = (_, _, token, report) => {
            report(new("scanning", 0, 1, 0, 100));
            token.WaitHandle.WaitOne(); token.ThrowIfCancellationRequested(); throw new Exception("unreachable");
        };
        var id = (await f.Call("importStart")).Payload.GetProperty("scanId").GetString()!;
        Check((await f.Call("importStart")).Error?.Code == "missionRecords.busy", "second simultaneous start busy");
        Check((await f.Call("importCancel", new { schemaVersion = 1, scanId = id })).Payload.GetProperty("cancelled").GetBoolean(), "cancel shape");
        Check((await f.Finish(id)).Payload.GetProperty("phase").GetString() == "cancelled" && (await f.Files.Read()).Records.Length == 0, "cancel finishes without commit");
    }

    private static async Task OwnerChange()
    {
        await using var f = new BridgeFixture();
        using var entered = new ManualResetEventSlim();
        using var release = new ManualResetEventSlim();
        f.Runtime.Scanner = (_, _, token, report) => {
            entered.Set(); release.Wait(token); report(new("scanning", 1, 1, 100, 100));
            return new([Row()], 1, 0);
        };
        var id = (await f.Call("importStart")).Payload.GetProperty("scanId").GetString()!;
        Check(entered.Wait(TimeSpan.FromSeconds(5)), "scanner started");
        f.Current = (Owner with { Subject = "new-owner" }, 2);
        release.Set();
        Check((await f.Call("importRead", new { schemaVersion = 1, scanId = id })).Error?.Code == "missionRecords.scanNotFound", "new owner cannot read old scan");
        await f.Runtime.DisposeAsync();
        Check((await f.Files.Store.ReadAsync(Owner)).Records.Length == 0 &&
            (await f.Files.Store.ReadAsync(f.Current.Context!)).Records.Length == 0, "switch cannot commit to either account");
    }

    private sealed class Routed(string target) : IBridgeRequestDispatcher
    {
        public event Action<BridgeEnvelope>? EventReady { add { } remove { } }
        public ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken cancellationToken = default) =>
            ValueTask.FromResult(new BridgeDispatchBatch(BridgeEnvelope.Response(request, new { routed = target }), []));
        public void Dispose() { }
    }
    private static async Task Routes()
    {
        // Distinct markers: every mission-record request must reach the account dispatcher.
        using var composite = new CompositeBridgeDispatcher(new Routed("host"), new Routed("account"), new Routed("preferences"));
        foreach (var name in new[] { "summary", "importStart", "importRead", "importCancel" })
            Check((await composite.DispatchAsync(BridgeEnvelope.Request("missionRecords." + name, Guid.NewGuid().ToString("N"), 1,
                new { schemaVersion = 1 }, Owner))).Response.Payload.GetProperty("routed").GetString() == "account", "composite route to account: " + name);
        Check(AccountBridgeRuntime.AdvertisedCapabilities.Contains("missionRecords.read") &&
            AccountBridgeRuntime.AdvertisedCapabilities.Contains("missionRecords.import"), "capabilities");
        using var local = new AccountBridgeRuntime(new StarBridge.HostRuntime.Account.EnvironmentLockedAccountBridgeHost("test"));
        foreach (var name in new[] { "importStart", "importRead", "importCancel" })
        {
            var response = (await local.DispatchAsync(BridgeEnvelope.Request("missionRecords." + name,
                Guid.NewGuid().ToString("N"), 0, name == "importStart" ? new { schemaVersion = 1 } :
                    (object)new { schemaVersion = 1, scanId = Guid.NewGuid().ToString("N") }))).Response;
            Check(response.Error?.Code == "missionRecords.unavailable" && response.Payload.GetProperty("reason").GetString() == "localMode",
                "cold local mode route explicitly unavailable");
        }
    }

    internal static async Task Run()
    {
        var cases = new (string Name, Func<Task> Run)[] {
            ("joined participation and timing matrix", Participation), ("owner solo team and distinct teammates", OwnerTiming),
            ("owner records have no participation marker", NonJoinedParticipation), ("marker stands in for missing acceptance", MarkerFallback),
            ("joined merge excludes owner markers in both write orders", JoinedMergeAcrossSources),
            ("repeated objective pushes preserve classification", RepeatedObjectivePushes),
            ("bounded evidence retains earliest objectives across files", EvidenceLimits),
            ("role reimport and monotonic enrichment", RoleEnrichment), ("legacy JSON and cross-file role evidence", LegacyAndCrossFileRoles),
            ("storage merge, GUID and owner isolation", Storage), ("capacity and eviction diagnostic", Capacity),
            ("backup recovery and exclusive lease", Backup), ("summary grouping and timing", Summary),
            ("real live reader and independent consumers", ContractAchievementTests.MissionRecordsLive),
            ("live shared and owner-team roles", ContractAchievementTests.MissionRecordsLiveRoles),
            ("cross-file pairing and unlimited repeat import", ImportReplay), ("archive scope identity unreadable and cancellation", ImportIdentity),
            ("multiline acceptance, English acceptance and repeat dedup", ImportMultiline),
            ("multiline reimport enriches immutable completion", ImportMultilineEnrichment),
            ("multiline interruption EOF length and identity boundaries", ImportMultilineBoundaries),
            ("bridge shapes and all unavailable reasons", Bridge), ("bridge counts unclassified legacy rows", BridgeUnclassified),
            ("cancel and single flight", CancelBusy),
            ("owner change fences scan commit and polling", OwnerChange), ("composite routing and capabilities", Routes)
        };
        var failures = 0;
        foreach (var test in cases)
        {
            try { await test.Run(); Console.WriteLine("PASS MISSION RECORDS " + test.Name); }
            catch (Exception e) { failures++; Console.WriteLine("FAIL MISSION RECORDS " + test.Name + ": " + e.Message); }
        }
        Console.WriteLine($"SUMMARY MISSION RECORDS passed={cases.Length - failures} failed={failures} skipped=0");
        if (failures > 0) throw new Exception("Mission records regressions failed.");
    }
}
