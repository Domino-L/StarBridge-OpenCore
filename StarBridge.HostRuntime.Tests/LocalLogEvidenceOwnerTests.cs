using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime.Onboarding;
using StarBridge.HostRuntime.Presence;

internal static class LocalLogEvidenceOwnerTests
{
    private static readonly DateTimeOffset Start = new(2026, 1, 1, 12, 0, 0, TimeSpan.Zero);
    private static string Op() => Guid.NewGuid().ToString("N");
    private static string Line(DateTimeOffset at, string handle = "Pilot-Example", string id = "100", bool precise = true) =>
        $"<{at.ToString(precise ? "yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'" : "yyyy-MM-dd'T'HH:mm:ss'Z'")}> nickname=\"{handle}\" playerGEID={id}\n";

    internal static void Run()
    {
        var cases = new (string Name, Action Test)[] {
            ("sticky source gate, reopen and atomic explicit confirmation", Sticky),
            ("source/version separation and no automatic profile merge", Sources),
            ("live identity precedence and confirmed association after game exit", CurrentAndExit),
            ("pending confirmation rechecks source, session, content and context", Confirmation),
            ("fresh byte/session boundary, timestamps and complete records", FreshRecords),
            ("rotation, truncation and process replacement", FileGenerations),
            ("missing file and strict persisted source/baseline document", Persistence),
            ("cancellation, bounds, unsafe nodes and cooperative deadline", Failures)
        };
        foreach (var test in cases) { test.Test(); Console.WriteLine("PASS first-use evidence owner: " + test.Name); }
    }

    private static void Sticky()
    {
        using var f = new Fixture();
        var missing = f.Select();
        Require(missing is { State: "missing", RequiresFreshEvidence: true, Handle: null }, "Complete absence establishes a durable gate.");
        var before = f.Store.Read();
        var baseline = before.Sources.Single().Baseline!;
        Require(baseline.FileIdentity?.Length == 48 && baseline.PrefixHash?.Length == 64, "Real 128-bit file identity and prefix receipt are captured.");
        f.Backup(Line(Start.AddMinutes(-1)));
        f.Reopen();
        Require(f.Owner.Current is { State: "checking", RequiresFreshEvidence: true }, "Reopening cannot clear the gate or imply a scan.");
        var bytes = File.ReadAllBytes(f.StatePath);
        _ = f.Owner.Current;
        Require(bytes.SequenceEqual(File.ReadAllBytes(f.StatePath)), "Passive reads do not alter state.");
        f.Owner.Invalidate(); // Mode/login/Host epoch changes revoke only memory authority.
        Require(f.Refresh() is { RequiresFreshEvidence: true, Handle: null }, "A newly found old archive cannot clear the gate.");
        f.Store.SaveProgress(before.Revision, Op(), new("identity", "online", missing.SourceKey, null, null), () => true);
        Require(f.Store.Read().Sources.Single().Baseline == baseline, "UI/mode progress cannot move or clear the baseline.");
        var snapshot = f.Store.Read();
        Expect("firstUse.evidence_required", () => f.Store.ConfirmIdentity(snapshot.Revision, Op(),
            new(missing.SourceKey!, Op(), "Pilot-Example", Start.AddMinutes(-1), "history", true, false), () => true));
        f.Running(Start.AddMinutes(-1));
        f.Clock.Now = Start.AddMilliseconds(600);
        File.AppendAllText(f.Log, Line(Start, precise: false));
        var candidate = f.Refresh();
        Require(candidate is { State: "candidate", Origin: "freshSession", RequiresFreshEvidence: false, IdentityConfirmed: false },
            "A real newly completed record in an already-running game can fulfill the pending evidence requirement.");
        Require(f.Store.Read().Sources.Single().NeedsFreshGameEvidence, "Preview cannot clear the persisted gate.");
        var confirmed = f.Owner.Confirm(candidate.SourceKey!, candidate.EvidenceKey!);
        snapshot = f.Store.Read();
        Require(confirmed.IdentityConfirmed && snapshot.Profiles.Count == 1 && snapshot.ActiveProfileId is not null &&
            snapshot.Sources.Single() is { NeedsFreshGameEvidence: false, Baseline: null, ConfirmedOrigin: "freshSession" },
            "Gate clearance, profile association and activation commit together after confirmation.");
        f.Process = new("notRunning"); f.Reopen();
        Require(f.Refresh() is { State: "candidate", Origin: "confirmedLocal", IdentityConfirmed: true },
            "Game exit does not destroy an already confirmed local association.");
    }

    private static void Sources()
    {
        using var f = new Fixture();
        var live = f.Select();
        var baseline = f.Store.Read().Sources.Single().Baseline;
        var ptu = f.NewLog("PTU");
        File.WriteAllText(ptu, Line(Start.AddMinutes(-1), "Other-Pilot", "200"));
        var candidate = f.Select(ptu, "PTU");
        f.Owner.Confirm(candidate.SourceKey!, candidate.EvidenceKey!);
        var ptuProfile = f.Store.Read().ActiveProfileId;
        var reselected = f.Select();
        Require(reselected.SourceKey == live.SourceKey && reselected.RequiresFreshEvidence &&
            f.Store.Read().ActiveProfileId is null && f.Store.Read().Sources.Single(s => s.SourceKey == live.SourceKey).Baseline == baseline,
            "Switching back restores its exact gate and does not activate the other version's profile.");
        f.Running(Start.AddSeconds(-10)); f.Clock.Now = Start.AddSeconds(1);
        File.AppendAllText(f.Log, Line(f.Clock.Now));
        candidate = f.Refresh(); f.Owner.Confirm(candidate.SourceKey!, candidate.EvidenceKey!);
        var liveProfile = f.Store.Read().ActiveProfileId;
        Require(liveProfile != ptuProfile && f.Store.Read().Profiles.Count == 2, "Different Handles retain independent IDs, never merge.");
        f.Process = new("notRunning");
        candidate = f.Select(ptu, "PTU");
        Require(candidate is { Origin: "confirmedLocal", IdentityConfirmed: false } && f.Store.Read().ActiveProfileId is null,
            "Even a remembered source requires explicit reactivation after a source switch.");
        f.Owner.Confirm(candidate.SourceKey!, candidate.EvidenceKey!);
        Require(f.Store.Read().ActiveProfileId == ptuProfile && f.Store.Read().Profiles.Count == 2, "Explicit confirmation reuses only that Handle's profile.");
        var secondInstall = f.NewLog("LIVE", "second-install");
        Require(f.Select(secondInstall).RequiresFreshEvidence && f.Store.Read().Sources.Count == 3,
            "A second installation is its own source even when the version label matches.");
        var s = f.Store.Read();
        Expect("firstUse.source_changed", () => f.Store.ConfirmIdentity(s.Revision, Op(),
            new(live.SourceKey!, Op(), "Pilot-Example", Start, "current", false, false), () => true));
    }

    private static void CurrentAndExit()
    {
        using var f = new Fixture();
        f.Backup(Line(Start.AddMinutes(-2), "Other-Pilot", "200"));
        File.WriteAllText(f.Log, Line(Start.AddMinutes(-1)));
        f.Running(Start.AddMinutes(-1));
        var current = f.Select();
        Require(current is { State: "candidate", Origin: "current", ScopeChecked: false }, "Verified current-game identity precedes conflicting history.");
        f.Owner.Confirm(current.SourceKey!, current.EvidenceKey!);
        var oldProfile = f.Store.Read().ActiveProfileId;
        f.Process = new("notRunning");
        var stored = f.Refresh();
        Require(stored is { Origin: "confirmedLocal", IdentityConfirmed: true } && stored.ObservedAt == Start.AddMinutes(-1),
            "Confirmed receipt preserves its original log time and never claims current live evidence.");
        f.Running(Start); File.WriteAllText(f.Log, Line(Start, "Other-Pilot", "200"));
        Expect("firstUse.context_changed", () => f.Owner.Confirm(stored.SourceKey!, stored.EvidenceKey!));
        Require(f.Store.Read().ActiveProfileId == oldProfile, "A stale receipt cannot activate a different Handle.");
        current = f.Refresh();
        Require(current is { Handle: "Other-Pilot", IdentityConfirmed: false } && f.Store.Read().ActiveProfileId is null &&
            f.Store.Read().Profiles.Count == 1, "Detecting a different Handle pauses the old association without deleting its profile.");
        f.Owner.Confirm(current.SourceKey!, current.EvidenceKey!);
        Require(f.Store.Read().Profiles.Count == 2 && f.Store.Read().ActiveProfileId != oldProfile, "Only explicit confirmation activates the second profile.");
    }

    private static void Confirmation()
    {
        using (var f = new Fixture())
        {
            File.WriteAllText(f.Log, Line(Start.AddMinutes(-1)));
            var candidate = f.Select();
            f.Backup(Line(Start.AddMinutes(-2), "Other-Pilot", "200"));
            var bytes = File.ReadAllBytes(f.StatePath);
            Expect("firstUse.context_changed", () => f.Owner.Confirm(candidate.SourceKey!, candidate.EvidenceKey!));
            Require(bytes.SequenceEqual(File.ReadAllBytes(f.StatePath)), "Changed history is rejected at the actual commit guard.");
        }
        using (var f = new Fixture())
        {
            f.Select(); f.Running(Start); f.Clock.Now = Start.AddSeconds(1);
            File.AppendAllText(f.Log, Line(f.Clock.Now)); var candidate = f.Refresh();
            f.Process = new("notRunning");
            Expect("firstUse.context_changed", () => f.Owner.Confirm(candidate.SourceKey!, candidate.EvidenceKey!));
            Require(f.Store.Read().Sources.Single().NeedsFreshGameEvidence && f.Store.Read().Profiles.Count == 0,
                "Ending an unconfirmed session cannot clear the gate.");
        }
        using (var f = new Fixture())
        {
            File.WriteAllText(f.Log, Line(Start.AddMinutes(-1))); var candidate = f.Select();
            f.Clock.Now = Start.AddSeconds(11);
            Expect("firstUse.evidence_required", () => f.Owner.Confirm(candidate.SourceKey!, candidate.EvidenceKey!));
            f.Clock.Now = Start.AddTicks(-1);
            Require(f.Owner.Current.State == "checking", "Clock rollback expires cached authority too.");
        }
        using (var f = new Fixture())
        {
            File.WriteAllText(f.Log, Line(Start.AddMinutes(-1))); var candidate = f.Select();
            var original = File.ReadAllBytes(f.StatePath);
            var checks = 0;
            f.Context = () => ++checks < 3;
            Expect("firstUse.context_changed", () => f.Owner.Confirm(candidate.SourceKey!, candidate.EvidenceKey!));
            Require(original.SequenceEqual(File.ReadAllBytes(f.StatePath)) && !Directory.EnumerateFiles(Path.GetDirectoryName(f.StatePath)!, "*.tmp").Any(),
                "Losing Host generation during confirmation preserves state and cleans only its own temporary file.");
        }
    }

    private static void FreshRecords()
    {
        using var f = new Fixture();
        f.Running(Start.AddMinutes(-1));
        File.WriteAllText(f.Log, "ordinary\n"); var baseline = f.Reader.Capture(f.Log, "LIVE");
        foreach (var process in new[] { new GameProcessSession("notRunning"), new("unknown"),
            new("running", Path.Combine(f.Root, "RSI Launcher.exe"), Start, "launcher"),
            new("running", f.Log, Start.AddSeconds(2), "future-session") })
        {
            f.Process = process;
            Require(f.Reader.Read(f.Log, "LIVE", baseline).State is "notRunning" or "processUnknown", "Launcher/unknown/foreign/future processes are not game evidence.");
        }
        f.Running(Start.AddMinutes(-1)); f.Clock.Now = Start.AddSeconds(1);
        File.AppendAllText(f.Log, Line(Start.AddMinutes(-2)));
        Require(f.Reader.Read(f.Log, "LIVE", baseline).State == "waiting", "Replayed old timestamps do not fulfill fresh evidence.");
        File.AppendAllText(f.Log, Line(f.Clock.Now));
        var evidence = f.Reader.Read(f.Log, "LIVE", baseline);
        Require(evidence.State == "candidate", "New complete identity is accepted.");
        File.AppendAllText(f.Log, "ordinary heartbeat\n");
        Require(f.Reader.Read(f.Log, "LIVE", baseline).EvidenceStamp == evidence.EvidenceStamp,
            "Ordinary passive log appends do not churn semantic evidence.");
        File.AppendAllText(f.Log, "unfinished");
        Require(f.Reader.Read(f.Log, "LIVE", baseline).State == "incomplete", "An incomplete tail cannot borrow the earlier candidate.");
        File.AppendAllText(f.Log, "\n" + Line(f.Clock.Now, id: "200"));
        Require(f.Reader.Read(f.Log, "LIVE", baseline).State == "conflict", "Different numeric identities cannot be collapsed by Handle.");
        File.WriteAllText(f.Log, Line(f.Clock.Now).TrimEnd()); baseline = f.Reader.Capture(f.Log, "LIVE");
        File.AppendAllText(f.Log, "\n");
        Require(f.Reader.Read(f.Log, "LIVE", baseline).State == "waiting", "Completing a pre-baseline partial identity is not a new record.");
        File.AppendAllText(f.Log, Line(f.Clock.Now));
        Require(f.Reader.Read(f.Log, "LIVE", baseline).State == "candidate", "A subsequent genuine full record may fulfill the gate.");
        File.AppendAllText(f.Log, "\uFEFF" + Line(f.Clock.Now));
        Require(f.Reader.Read(f.Log, "LIVE", baseline).State == "conflict", "Mid-file BOM cannot impersonate a canonical line prefix.");
        f.Clock.Now = Start.AddTicks(-1);
        Require(f.Reader.Read(f.Log, "LIVE", baseline).State == "clockChanged", "Persisted capture time cannot be bypassed by a rolled-back clock.");
    }

    private static void FileGenerations()
    {
        using var f = new Fixture();
        f.Running(Start.AddMinutes(-1)); File.WriteAllText(f.Log, "ordinary baseline\n");
        var baseline = f.Reader.Capture(f.Log, "LIVE"); var write = File.GetLastWriteTimeUtc(f.Log);
        File.WriteAllText(f.Log, "changed! baseline\n"); File.SetLastWriteTimeUtc(f.Log, write);
        Require(f.Reader.Read(f.Log, "LIVE", baseline).State == "changed", "Same-length prefix rewriting is caught despite restored metadata.");
        File.WriteAllText(f.Log, "");
        Require(f.Reader.Read(f.Log, "LIVE", baseline).State == "changed", "Same-file truncation cannot reuse an old cursor.");
        File.Move(f.Log, f.Log + ".fixture-old"); f.Clock.Now = Start.AddSeconds(1);
        File.WriteAllText(f.Log, Line(Start.AddMinutes(-1)));
        Require(f.Reader.Read(f.Log, "LIVE", baseline).State == "waiting", "A replacement file alone is not fresh game evidence.");
        File.AppendAllText(f.Log, Line(f.Clock.Now));
        Require(f.Reader.Read(f.Log, "LIVE", baseline).State == "candidate", "New process-matched evidence in the replacement is accepted.");
        File.WriteAllText(f.Log, Line(Start.AddMinutes(-1)) +
            "<2026-01-01T11:59:00Z> nickname=\"Old-Pilot\" playerGEID=broken\n" +
            "<2026-01-01T11:59:00Z> <SystemQuit> CSystem::Quit\n");
        baseline = f.Reader.Capture(f.Log, "LIVE");
        f.Clock.Now = Start.AddSeconds(2); f.Running(f.Clock.Now, "fixture-second-session");
        File.AppendAllText(f.Log, Line(f.Clock.Now));
        Require(f.Reader.Read(f.Log, "LIVE", baseline).State == "candidate", "New process session ignores old quit/identity records even when the file ID is unchanged.");
        File.AppendAllText(f.Log, "<2026-01-01T12:00:02Z> nickname=\"Pilot-Example\" playerGEID=broken\n");
        Require(f.Reader.Read(f.Log, "LIVE", baseline).State == "conflict", "Damaged identity in this session cannot be hidden by an earlier valid record.");
        File.WriteAllText(f.Log, Line(f.Clock.Now));
        File.AppendAllText(f.Log, "<2026-01-01T12:00:02Z> <SystemQuit> CSystem::Quit\n");
        Require(f.Reader.Read(f.Log, "LIVE", baseline).State == "waiting", "A quit in this new session blocks resurrection of its candidate.");

        using var owner = new Fixture(); File.WriteAllText(owner.Log, "baseline row\n"); owner.Select();
        var saved = owner.Store.Read(); var old = saved.Sources.Single().Baseline!;
        Expect("firstUse.evidence_required", () => owner.Store.RequireFreshGameEvidence(saved.Revision, Op(), saved.SelectedSourceKey!,
            old with { Cursor = 0 }, () => true));
        owner.Running(Start.AddMinutes(-1)); File.WriteAllText(owner.Log, "new baseline\n");
        Require(owner.Refresh() is { State: "waiting", RequiresFreshEvidence: true }, "Changed source is rebased conservatively, not marked complete.");
        owner.Clock.Now = Start.AddSeconds(1); File.AppendAllText(owner.Log, Line(owner.Clock.Now));
        Require(owner.Refresh().State == "candidate", "Only the subsequent record fulfills the replacement baseline.");
    }

    private static void Persistence()
    {
        using var f = new Fixture(); File.Delete(f.Log);
        var absent = f.Select();
        Require(absent.RequiresFreshEvidence && f.Store.Read().Sources.Single().Baseline is { FileIdentity: null, Cursor: 0 },
            "A selected existing installation may not yet contain Game.log.");
        f.Running(Start); f.Clock.Now = Start.AddSeconds(1); File.WriteAllText(f.Log, Line(f.Clock.Now));
        Require(f.Refresh().State == "candidate", "First log creation still needs a real matching game process and complete identity record.");
        var saved = f.Store.Read(); var original = File.ReadAllBytes(f.StatePath);
        var document = new JsonObject { ["schemaVersion"] = 3, ["value"] = JsonSerializer.SerializeToNode(saved, new JsonSerializerOptions(JsonSerializerDefaults.Web)) };
        var edits = new Action<JsonObject>[] {
            d => d["schemaVersion"] = 1,
            d => d["schemaVersion"] = 2,
            d => d["value"]!.AsObject().Remove("sources"),
            d => d["value"]!.AsObject().Remove("selectedSourceKey"),
            d => d["value"]!["selectedSourceKey"] = Op(),
            d => d["value"]!["sources"]![0]!["baseline"]!.AsObject().Remove("cursor"),
            d => d["value"]!["sources"]![0]!["baseline"]!["cursor"] = -1,
            d => d["value"]!["sources"]![0]!["baseline"]!["fileIdentity"] = "short",
            d => d["value"]!["sources"]![0]!["needsFreshGameEvidence"] = false,
            d => d["value"]!["sources"]![0]!.AsObject().Remove("listeningEnabled"),
            d => d["value"]!["sources"]![0]!["listeningEnabled"] = "true",
            d => d["value"]!["sources"]![0]!["logPath"] = f.Log + ":alternate"
        };
        foreach (var edit in edits)
        {
            var malformed = document.DeepClone().AsObject(); edit(malformed);
            Protect(f.StatePath, malformed.ToJsonString());
            Expect("firstUse.read_failed", () => f.Store.Read());
            var corrupted = File.ReadAllBytes(f.StatePath);
            Expect("firstUse.read_failed", () => f.Store.SaveProgress(saved.Revision, Op(), new("mode", "local", null, null, null), () => true));
            Require(corrupted.SequenceEqual(File.ReadAllBytes(f.StatePath)), "Malformed/draft documents are not reset or implicitly migrated.");
            File.WriteAllBytes(f.StatePath, original);
        }
        var raw = Encoding.UTF8.GetString(original);
        Require(!raw.Contains(f.Log) && !raw.Contains("fixture-game-session"), "Source paths and process metadata stay encrypted and never use Handle filenames.");
    }

    private static void Failures()
    {
        using var f = new Fixture(); f.Running(Start); var baseline = f.Reader.Capture(f.Log, "LIVE");
        using var cancel = new CancellationTokenSource(); cancel.Cancel();
        Require(f.Reader.Read(f.Log, "LIVE", baseline, cancel.Token).State == "cancelled", "Cancellation never supplies identity.");
        File.WriteAllBytes(f.Log, [0xff, 0xfe, 0x0a]);
        Require(f.Reader.Read(f.Log, "LIVE", baseline).State == "unavailable", "Invalid UTF-8 cannot be silently skipped.");
        File.WriteAllText(f.Log, new string('x', 65537) + "\n");
        Require(f.Reader.Read(f.Log, "LIVE", baseline).State == "limit", "Line work is bounded.");
        File.WriteAllText(f.Log, Line(Start));
        f.Clock.TimestampStep = TimeSpan.TicksPerSecond * 16;
        Require(f.Reader.Read(f.Log, "LIVE", baseline).State == "limit", "The read has a cooperative deadline.");
        f.Clock.TimestampStep = 1;
        using (var locked = new FileStream(f.Log, FileMode.Open, FileAccess.ReadWrite, FileShare.None))
            Require(f.Reader.Read(f.Log, "LIVE", baseline).State == "unavailable", "Unreadable source remains unavailable, not missing.");
        Require(f.Reader.Read(f.Log + ":data", "LIVE", baseline).State == "unsafe", "No alternate streams are read.");
        File.Delete(f.Log); Directory.CreateDirectory(f.Log);
        Require(f.Reader.Read(f.Log, "LIVE", baseline).State == "unsafe", "A directory named Game.log is not a source.");
    }

    private static void Protect(string path, string json)
    {
        var bytes = Encoding.UTF8.GetBytes(json);
        try { File.WriteAllBytes(path, ProtectedData.Protect(bytes, Encoding.UTF8.GetBytes("StarBridge.local-first-use.v1"), DataProtectionScope.CurrentUser)); }
        finally { CryptographicOperations.ZeroMemory(bytes); }
    }
    private sealed class Clock : TimeProvider
    {
        private long _timestamp;
        internal DateTimeOffset Now { get; set; } = Start;
        internal long TimestampStep { get; set; } = 1;
        public override long TimestampFrequency => TimeSpan.TicksPerSecond;
        public override long GetTimestamp() => _timestamp += TimestampStep;
        public override DateTimeOffset GetUtcNow() => Now;
    }
    private sealed class Fixture : IDisposable
    {
        internal string Root { get; } = Path.Combine(Path.GetTempPath(), "starbridge-first-use-owner", Op());
        internal string Log { get; }
        internal string StatePath => Path.Combine(Root, "device", "local-first-use-v1", "state.bin");
        internal Clock Clock { get; } = new();
        internal GameProcessSession Process { get; set; } = new("notRunning");
        internal Func<bool> Context { get; set; } = () => true;
        internal LocalFirstUseStore Store { get; private set; } = null!;
        internal LocalLogEvidenceOwner Owner { get; private set; } = null!;
        internal FreshGameEvidenceReader Reader { get; }
        internal Fixture()
        {
            Log = NewLog("LIVE");
            Reader = new(() => Process, Clock); Reopen();
        }
        internal string NewLog(string version, string install = "install")
        {
            var path = Path.Combine(Root, install, version, "Game.log");
            Directory.CreateDirectory(Path.GetDirectoryName(path)!); File.WriteAllText(path, ""); return path;
        }
        internal void Reopen()
        {
            Store = new(Path.Combine(Root, "device"), Clock);
            Owner = new(Store, () => Process, Clock, () => Context());
        }
        internal void Running(DateTimeOffset at, string session = "fixture-game-session") => Process = new("running", Log, at, session);
        internal void Backup(string text)
        {
            var dir = Directory.CreateDirectory(Path.Combine(Path.GetDirectoryName(Log)!, "logbackups"));
            File.WriteAllText(Path.Combine(dir.FullName, "history.log"), text);
        }
        internal LocalLogEvidenceObservation Select(string? log = null, string version = "LIVE") => Owner.Select(Store.Read().Revision, log ?? Log, version);
        internal LocalLogEvidenceObservation Refresh() => Owner.Refresh(Store.Read().SelectedSourceKey!);
        public void Dispose()
        {
            var full = Path.GetFullPath(Root);
            var allowed = Path.GetFullPath(Path.Combine(Path.GetTempPath(), "starbridge-first-use-owner"));
            if (Path.GetDirectoryName(full) != allowed || !Guid.TryParseExact(Path.GetFileName(full), "N", out _) ||
                File.GetAttributes(full).HasFlag(FileAttributes.ReparsePoint)) throw new InvalidOperationException("Unsafe fixture cleanup target.");
            Directory.Delete(full, recursive: true);
        }
    }
    private static void Expect(string code, Action operation)
    {
        try { operation(); } catch (LocalFirstUseException error) when (error.Code == code) { return; }
        throw new InvalidOperationException("Expected " + code);
    }
    private static void Require(bool condition, string message)
    { if (!condition) throw new InvalidOperationException(message); }
}
