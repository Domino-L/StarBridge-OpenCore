using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StarBridge.HostRuntime.Onboarding;
using StarBridge.HostRuntime.Presence;

internal static class LocalGameplayTimeTests
{
    private static readonly DateTimeOffset Start = new(2026, 1, 1, 12, 0, 0, TimeSpan.Zero);
    private static string Id() => Guid.NewGuid().ToString("N");
    private static string Identity(string handle, string geid, DateTimeOffset at) =>
        $"<{at:yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'}> nickname=\"{handle}\" playerGEID={geid}\n";

    internal static async Task Run()
    {
        await GameplayTimeAccumulatorTests.ConsentAndOwnership();
        await GameplayTimeAccumulatorTests.Sampling();
        await GameplayTimeAccumulatorTests.Uncertainty();
        Console.WriteLine("PASS local statistics: shared interval arithmetic preserves three account accumulator groups");
        var tests = new (string Name, Action Test)[] {
            ("identity and listening do not grant statistics consent", UnknownChoice),
            ("one log timer, five-second cadence and explicit decline", ConsentAndCadence),
            ("uncertainty, stale observations, sleep and final exit", EvidenceGaps),
            ("listening and mode transitions retain totals without backfill", ModeAndListening),
            ("actual Handle changes preserve separate profile totals", ProfileSwitch),
            ("reopening retains choices without replaying old account data", Reopening),
            ("failed choices and damaged files stop until explicit retry", FailedChoice),
            ("writer lease, revision and final guard preserve the original", StorageTransactions),
            ("protected documents reject foreign profiles and malformed state", ProtectedDocuments),
            ("linked statistics directories cannot read or write their target", LinkedStorage),
            ("only the matching local log owner can drive statistics", Ownership)
        };
        foreach (var test in tests) { test.Test(); Console.WriteLine("PASS local statistics: " + test.Name); }
        await Retirement();
        Console.WriteLine("PASS local statistics: retirement waits for admitted work and prevents late writes");
    }

    private static void UnknownChoice()
    {
        using var f = new Fixture();
        Check(f.Stats.Current is { State: "choiceRequired", Consent: "unknown", Seconds: 0, Recording: false },
            "Confirmed identity is not permission to record.");
        f.Tick(5); f.EnableListening(); f.Tick(5); f.Tick(5);
        Check(f.Game.Current.State == "ready" && f.Stats.Current is { Seconds: 0, Recording: false } &&
            !Directory.Exists(f.StatisticsDirectory) && f.AccountReads == 0,
            "History discovery, viewing settings and listening never create a statistics file or account context.");
        var metadata = f.Identities.Read();
        f.Identities.SaveProgress(metadata.Revision, Id(), new("summary", "local", f.Key, null, f.Profile), () => true);
        f.Tick(5);
        Check(f.Stats.Current.Consent == "unknown" && !Directory.Exists(f.StatisticsDirectory),
            "Saved presentation progress cannot become statistics consent.");
    }

    private static void ConsentAndCadence()
    {
        using var f = new Fixture(); f.EnableListening(); f.Allow(); f.Tick(0);
        Check(f.Clock.Timers.Count == 1 && f.Clock.Timers[0].Period == TimeSpan.FromMilliseconds(500),
            "The original log timer is the sole timer; statistics owns no watcher or timer.");
        for (var i = 0; i < 12; i++) f.Tick(.5);
        Check(f.Stats.Current is { Seconds: 5, SavedSeconds: 5, Recording: true } && f.Saved.Seconds == 5,
            "Half-second log polls cannot double-count rounded intervals.");
        Check(f.Stats.ApplyConsent(f.Key, false) is { State: "declined", Seconds: 5, Recording: false },
            "Explicit decline is immediate and does not clear the total.");
        f.Tick(20); f.Tick(5);
        Check(f.Saved is { Consent: GameplayRecordingConsent.Declined, Seconds: 5 }, "Declined time is not recorded.");
        f.Allow(); f.Tick(0); f.Tick(5);
        Check(f.Saved is { Consent: GameplayRecordingConsent.Allowed, Seconds: 10 }, "Re-allow starts a fresh interval.");
    }

    private static void EvidenceGaps()
    {
        using var f = new Fixture(); f.RecordFive();
        File.AppendAllText(f.Log, "unfinished nickname="); f.Tick(.5);
        Check(f.Game.Current.State == "reading" && !f.Stats.Current.Recording, "Uncertainty pauses even inside the five-second cadence.");
        f.WriteIdentity(); f.Tick(.5); f.Tick(5);
        Check(f.Saved.Seconds == 10, "A partial-line gap is not counted after evidence recovers.");
        f.Tick(31); Check(f.Saved.Seconds == 10, "Sleep or a long sampling stall is not gameplay.");
        f.Tick(5); Check(f.Saved.Seconds == 15, "Normal sampling starts again without replaying the stall.");
        f.Process = new("notRunning"); f.Tick(5); f.Tick(5);
        Check(f.Saved.Seconds == 20 && !f.Stats.Current.Recording, "Confirmed exit adds the final valid interval only once.");
        f.Running(); f.WriteIdentity(); f.Tick(5); f.Tick(5);
        Check(f.Saved.Seconds == 25, "A new game starts a fresh interval.");
        f.Clock.Now = f.Clock.Now.AddSeconds(11); f.Stats.Sample();
        Check(!f.Stats.Current.Recording && f.Saved.Seconds == 25, "Expired live evidence cannot be attributed.");
        f.Tick(0); f.Tick(5);
        Check(f.Saved.Seconds == 30, "Refreshing the actual log cannot backfill expired observations.");
    }

    private static void ModeAndListening()
    {
        using var f = new Fixture(); f.RecordFive();
        f.Game.ApplyListening(f.Key, false); f.Tick(20);
        Check(f.Stats.Current is { State: "listeningStopped", Seconds: 5, Recording: false }, "Stopping the log also stops statistics.");
        f.EnableListening(); f.Tick(5); Check(f.Saved.Seconds == 10, "Restarting listening has no stopped-time interval.");
        f.Mode = (false, 2); f.Tick(20);
        Check(f.Stats.Current.State == "inactive" && f.Saved.Seconds == 10 && f.AccountReads == 0,
            "Inactive local mode cannot resurrect the retired account sampler.");
        f.Mode = (true, 3); f.Tick(0); f.Tick(5);
        Check(f.Saved.Seconds == 15, "A new mode generation starts its own sample baseline.");
        f.Mode = (true, -1); f.Tick(5);
        Check(f.Stats.Current.State == "unavailable" && f.Saved.Seconds == 15, "Unknown mode generation is not ready.");
        f.Mode = (true, 4); f.Tick(0); f.Tick(5);
        Check(f.Saved.Seconds == 20, "A valid generation cannot count the invalid interval.");
        f.StatisticsModeHook = () => throw new InvalidOperationException("synthetic unavailable mode");
        f.Tick(5); Check(f.Stats.Current.State == "unavailable" && f.Saved.Seconds == 20, "Mode failure stops attribution, not saved data.");
        f.StatisticsModeHook = null; f.Tick(0); f.Tick(5);
        Check(f.Saved.Seconds == 25 && f.AccountReads == 0, "Mode recovery requires fresh evidence and never borrows account ownership.");
    }

    private static void ProfileSwitch()
    {
        using var f = new Fixture(); f.RecordFive(); var first = f.Profile; var original = f.Bytes(first);
        f.WriteIdentity("Other-Pilot", "200"); f.Tick(5);
        Check(f.Stats.Current.State == "needsIdentity" && f.Identities.Read().ActiveProfileId is null &&
            original.SequenceEqual(f.Bytes(first)), "Another Handle cannot write into the former profile before explicit confirmation.");
        f.ConfirmCurrent(); f.Tick(0); var second = f.Profile;
        Check(second != first && f.Stats.Current is { Consent: "unknown", Seconds: 0 }, "A separate confirmed profile inherits neither consent nor totals.");
        f.Allow(); f.Tick(0); f.Tick(5); f.Tick(5);
        Check(f.Saved.Seconds == 10 && f.Storage.Read(first).Seconds == 5, "Independent profile totals are not merged.");
        var secondBytes = f.Bytes(second);
        f.WriteIdentity(); f.Tick(5); f.ConfirmCurrent(); f.Tick(0);
        Check(f.Profile == first && f.Stats.Current is { Consent: "allowed", Seconds: 5 }, "Returning explicitly reactivates the original independent profile.");
        f.Tick(5);
        Check(f.Saved.Seconds == 10 && secondBytes.SequenceEqual(f.Bytes(second)) && f.Identities.Read().Profiles.Count == 2,
            "Returning has no cross-profile interval and preserves the other profile's file.");
    }

    private static void Reopening()
    {
        using var f = new Fixture();
        var legacy = Path.Combine(f.Root, "legacy-account-sentinel.bin");
        File.WriteAllBytes(legacy, [17, 29, 43]); f.RecordFive(); var profile = f.Profile;
        f.Clock.Now = f.Clock.Now.AddHours(2); f.Reopen(); f.Tick(0); f.Tick(5);
        Check(f.Profile == profile && f.Saved is { Consent: GameplayRecordingConsent.Allowed, Seconds: 10 } &&
            File.ReadAllBytes(legacy).SequenceEqual(new byte[] { 17, 29, 43 }) && f.AccountReads == 0,
            "Reopening restores only this random profile's saved choice and total, not downtime or old account data.");
        f.Stats.ApplyConsent(f.Key, false); var original = f.Bytes(profile); f.Reopen(); f.Tick(5);
        Check(f.Stats.Current is { State: "declined", Seconds: 10, Recording: false } && original.SequenceEqual(f.Bytes(profile)),
            "Reopening cannot silently re-allow or rewrite a declined choice.");
        Check(f.Clock.Timers.Count(t => !t.Disposed) == 1, "Reopening leaves only the new owning log timer alive.");
    }

    private static void FailedChoice()
    {
        using var f = new Fixture(); f.RecordFive(); var original = f.Bytes(f.Profile);
        File.WriteAllBytes(f.PathFor(f.Profile), [3, 5, 7]); var damaged = f.Bytes(f.Profile);
        Check(f.Stats.Current is { State: "unavailable", Recording: false } && damaged.SequenceEqual(f.Bytes(f.Profile)),
            "A damaged protected file is unavailable, not an empty replacement.");
        Check(f.Stats.ApplyConsent(f.Key, false) is { State: "unavailable", Consent: "declined", Recording: false },
            "A failed decline still suppresses recording while its explicit choice is pending.");
        f.Tick(5); f.Tick(5); Check(damaged.SequenceEqual(f.Bytes(f.Profile)), "Neither timer nor a failed choice overwrites corruption.");
        File.WriteAllBytes(f.PathFor(f.Profile), original); f.Tick(5);
        Check(f.Stats.Current.State == "unavailable" && original.SequenceEqual(f.Bytes(f.Profile)), "Repairing a file does not auto-retry or auto-allow.");
        Check(f.Stats.Retry(f.Key) is { State: "declined", Seconds: 5 } && f.Saved.Consent == GameplayRecordingConsent.Declined,
            "An explicit retry commits the pending decline without lost totals or backfill.");
        f.Stats.Suspend();
        using (var lease = f.Storage.Open(f.Profile, () => true))
        {
            Check(f.Stats.ApplyConsent(f.Key, true) is { State: "unavailable", Recording: false }, "A busy writer prevents an allow from becoming effective.");
            f.Tick(5); Check(f.Saved.Consent == GameplayRecordingConsent.Declined, "An unpersisted allow never records.");
        }
        f.Stats.Retry(f.Key); f.Tick(0); f.Tick(5);
        Check(f.Saved is { Consent: GameplayRecordingConsent.Allowed, Seconds: 10 }, "Only a successful explicit retry resumes with a new baseline.");
    }

    private static void StorageTransactions()
    {
        using var f = new Fixture(); var empty = f.Storage.Read(f.Profile);
        using var lease = f.Storage.Open(f.Profile, () => true);
        Expect("firstUse.statistics_write_failed", () => f.Storage.Open(f.Profile, () => true));
        var saved = lease.Save(empty, empty with { Consent = GameplayRecordingConsent.Allowed }, () => true);
        var original = f.Bytes(f.Profile);
        Expect("firstUse.revision_conflict", () => lease.Save(empty, empty with { Consent = GameplayRecordingConsent.Declined }, () => true));
        var guards = 0;
        Expect("firstUse.context_changed", () => lease.Save(saved, saved with { Consent = GameplayRecordingConsent.Declined }, () => ++guards == 1));
        Check(guards == 2 && original.SequenceEqual(f.Bytes(f.Profile)) && !Directory.EnumerateFiles(f.StatisticsDirectory, "*.tmp").Any(),
            "Final mode changes retain the original and clean only the owned temporary write.");
        var recorded = lease.Save(saved, saved with { Seconds = 5, FirstRecordedAt = Start }, () => true);
        Expect("firstUse.invalid_request", () => lease.Save(recorded, recorded with { Seconds = 4 }, () => true));
        Expect("firstUse.invalid_request", () => lease.Save(recorded, recorded with { FirstRecordedAt = Start.AddSeconds(-1) }, () => true));
        Expect("firstUse.invalid_request", () => lease.Save(recorded, recorded with { Consent = GameplayRecordingConsent.Unknown }, () => true));
        var last = f.Bytes(f.Profile); lease.Dispose();
        Expect("firstUse.statistics_write_failed", () => lease.Save(recorded, recorded, () => true));
        Check(last.SequenceEqual(f.Bytes(f.Profile)), "Closed writers and invalid transitions cannot reset or rewrite statistics.");
    }

    private static void ProtectedDocuments()
    {
        using var f = new Fixture(); f.RecordFive(); f.Stats.Suspend(); var profile = f.Profile; var original = f.Bytes(profile);
        var other = Id(); File.WriteAllBytes(f.PathFor(other), original);
        Expect("firstUse.statistics_read_failed", () => f.Storage.Read(other));
        var valid = JsonSerializer.Serialize(new { schemaVersion = 1, profileId = profile,
            value = new { revision = 1, consent = 1, seconds = 5, firstRecordedAt = Start } });
        foreach (var bad in new[] {
            valid.Replace("\"schemaVersion\":1", "\"schemaVersion\":2"),
            valid.Replace("\"schemaVersion\":1", "\"schemaVersion\":1,\"schemaVersion\":1"),
            valid.Replace("\"seconds\":5", "\"seconds\":5,\"seconds\":5"),
            valid.Replace("\"seconds\":5", "\"seconds\":-1"),
            valid.Replace("\"consent\":1", "\"consent\":0"),
            valid.Replace("\"consent\":1", "\"consent\":9"),
            valid.Replace("\"revision\":1", "\"revision\":9223372036854775807"),
            valid.Replace(JsonSerializer.Serialize(Start), "null"),
            valid.Replace(JsonSerializer.Serialize(Start), JsonSerializer.Serialize(Start.AddYears(1))),
            valid.Replace(JsonSerializer.Serialize(Start), JsonSerializer.Serialize(Start.ToOffset(TimeSpan.FromHours(1)))),
            valid.Replace("\"seconds\":5", "\"extra\":true,\"seconds\":5"),
            "{}"
        })
        {
            Check(bad != valid, "Every malformed-document fixture must actually change the valid document.");
            var clear = Encoding.UTF8.GetBytes(bad);
            try { File.WriteAllBytes(f.PathFor(profile), ProtectedData.Protect(clear,
                Encoding.UTF8.GetBytes("StarBridge.local-gameplay-time.v1"), DataProtectionScope.CurrentUser)); }
            finally { CryptographicOperations.ZeroMemory(clear); }
            var bytes = f.Bytes(profile); Expect("firstUse.statistics_read_failed", () => f.Storage.Read(profile));
            Check(bytes.SequenceEqual(f.Bytes(profile)), "Strict protected-document reads never replace invalid state.");
        }
        foreach (var length in new[] { 0, 8193 })
        {
            File.WriteAllBytes(f.PathFor(profile), new byte[length]); var bytes = f.Bytes(profile);
            Expect("firstUse.statistics_read_failed", () => f.Storage.Read(profile));
            Check(bytes.SequenceEqual(f.Bytes(profile)), "Empty and over-limit files are not replaced with default state.");
        }
        File.WriteAllBytes(f.PathFor(profile), ProtectedData.Protect("{}"u8.ToArray(), "Other.purpose"u8.ToArray(), DataProtectionScope.CurrentUser));
        Expect("firstUse.statistics_read_failed", () => f.Storage.Read(profile));
        File.WriteAllBytes(f.PathFor(profile), original);
        Check(f.Storage.Read(profile).Seconds == 5, "The original protected document remains readable without migration.");
        Expect("firstUse.profile_changed", () => f.Storage.Read("../not-a-profile"));
    }

    private static void LinkedStorage()
    {
        using var f = new Fixture(); f.RecordFive(); f.Stats.Suspend();
        var directory = Path.GetFullPath(f.StatisticsDirectory);
        var target = Path.GetFullPath(Path.Combine(f.Root, "statistics-fixture-target"));
        Check(Path.GetDirectoryName(directory) == Path.GetFullPath(f.Root) && Path.GetDirectoryName(target) == Path.GetFullPath(f.Root),
            "Both directory move targets must remain inside this owned random fixture.");
        Directory.Move(directory, target);
        var original = File.ReadAllBytes(Path.Combine(target, f.Profile + ".bin"));
        try
        {
            var start = new ProcessStartInfo("powershell.exe") { UseShellExecute = false, CreateNoWindow = true,
                RedirectStandardOutput = true, RedirectStandardError = true };
            foreach (var argument in new[] { "-NoProfile", "-NonInteractive", "-Command",
                "New-Item -ItemType Junction -Path $env:STARBRIDGE_STATISTICS_FIXTURE_LINK -Target $env:STARBRIDGE_STATISTICS_FIXTURE_TARGET -ErrorAction Stop | Out-Null" })
                start.ArgumentList.Add(argument);
            start.Environment["STARBRIDGE_STATISTICS_FIXTURE_LINK"] = directory;
            start.Environment["STARBRIDGE_STATISTICS_FIXTURE_TARGET"] = target;
            using var process = Process.Start(start) ?? throw new InvalidOperationException("Fixture junction helper did not start.");
            if (!process.WaitForExit(10000)) { process.Kill(true); throw new InvalidOperationException("Fixture junction helper timed out."); }
            Check(process.ExitCode == 0 && File.GetAttributes(directory).HasFlag(FileAttributes.ReparsePoint),
                "The linked-directory fixture must really exist; missing coverage cannot be treated as a pass.");
            Expect("firstUse.statistics_read_failed", () => f.Storage.Read(f.Profile));
            Expect("firstUse.statistics_write_failed", () => f.Storage.Open(f.Profile, () => true));
            Check(f.Stats.Current is { State: "unavailable", Recording: false } &&
                f.Stats.ApplyConsent(f.Key, false).State == "unavailable", "Runtime reads and explicit choices do not traverse linked storage.");
            f.Tick(5);
            Check(original.SequenceEqual(File.ReadAllBytes(Path.Combine(target, f.Profile + ".bin"))) &&
                Directory.EnumerateFiles(target).All(p => Path.GetFileName(p) == f.Profile + ".bin" || Path.GetFileName(p) == f.Profile + ".bin.lock"),
                "The linked target keeps its original file and receives no temporary write.");
        }
        finally
        {
            if (Directory.Exists(directory) && File.GetAttributes(directory).HasFlag(FileAttributes.ReparsePoint))
                Directory.Delete(directory); // Only this owned fixture link, never recursive or its target.
            Directory.Move(target, directory);
        }
        Check(f.Stats.Current.State == "unavailable", "Restoring a safe directory does not silently resume a failed choice.");
        Check(f.Stats.Retry(f.Key) is { State: "declined", Seconds: 5 }, "An explicit retry can persist the pending decline after safe storage returns.");
    }

    private static void Ownership()
    {
        using var f = new Fixture();
        f.Game.AttachStatistics(f.Stats);
        var otherGame = new LocalGameLogRuntime(f.Identities, () => f.Mode, () => f.Process, f.Clock);
        ExpectOther<InvalidOperationException>(() => otherGame.AttachStatistics(f.Stats));
        var otherStats = new LocalGameplayTimeRuntime(f.Identities, f.Storage, f.Game, () => f.Mode, f.Clock);
        ExpectOther<InvalidOperationException>(() => f.Game.AttachStatistics(otherStats));
        Check(f.Clock.Timers.Count == 1 && !Directory.Exists(f.StatisticsDirectory), "Attachment does not start polling or decide consent.");
    }

    private static async Task Retirement()
    {
        using var f = new Fixture(); f.RecordFive(); var original = f.Bytes(f.Profile);
        var started = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        f.Clock.Now = f.Clock.Now.AddSeconds(5);
        f.StatisticsModeHook = () => { started.TrySetResult(); Check(release.Task.Wait(TimeSpan.FromSeconds(5)), "Bounded fixture release timed out."); };
        var sample = Task.Run(f.Stats.Sample);
        try
        {
            await started.Task.WaitAsync(TimeSpan.FromSeconds(5)); var stop = f.Stats.RetireAsync();
            Check(!stop.IsCompleted && f.Stats.Current.State == "inactive", "Closed admission is immediate but a blocked admitted observation still owns its work.");
            release.TrySetResult(); await sample.WaitAsync(TimeSpan.FromSeconds(5)); await stop.WaitAsync(TimeSpan.FromSeconds(5));
            f.StatisticsModeHook = null; f.Tick(5); f.Stats.Sample();
            Check(f.Stats.Current.State == "inactive" && original.SequenceEqual(f.Bytes(f.Profile)), "Late work and later log ticks cannot reopen a retired statistics module.");
            Expect("firstUse.context_changed", () => f.Stats.ApplyConsent(f.Key, true));
            using var lease = f.Storage.Open(f.Profile, () => true);
            Check(f.Saved.Seconds == 5, "Retirement releases the writer and preserves the total and choice.");
        }
        finally { release.TrySetResult(); await sample.WaitAsync(TimeSpan.FromSeconds(5)); f.StatisticsModeHook = null; }
    }

    internal sealed class Clock : TimeProvider
    {
        internal DateTimeOffset Now = Start;
        internal List<Timer> Timers { get; } = [];
        public override DateTimeOffset GetUtcNow() => Now;
        public override ITimer CreateTimer(TimerCallback callback, object? state, TimeSpan dueTime, TimeSpan period)
        { var timer = new Timer(callback, state, period); Timers.Add(timer); return timer; }
    }
    internal sealed class Timer(TimerCallback callback, object? state, TimeSpan period) : ITimer
    {
        internal bool Disposed;
        private TimeSpan _period = period;
        internal TimeSpan Period => _period;
        internal void Fire() { if (!Disposed) callback(state); }
        public bool Change(TimeSpan dueTime, TimeSpan nextPeriod)
        { if (Disposed) return false; _period = nextPeriod; return true; }
        public void Dispose() => Disposed = true;
        public ValueTask DisposeAsync() { Dispose(); return ValueTask.CompletedTask; }
    }
    internal sealed class Fixture : IDisposable
    {
        internal string Root { get; } = Path.Combine(Path.GetTempPath(), "starbridge-first-use-local-statistics", Id());
        internal string Log { get; }
        internal Clock Clock { get; } = new();
        internal (bool Active, long Generation) Mode = (true, 1);
        internal GameProcessSession Process = new("notRunning");
        internal Action? StatisticsModeHook;
        internal int AccountReads;
        internal LocalFirstUseStore Identities = null!;
        internal LocalLogEvidenceOwner Evidence = null!;
        internal LocalGameLogRuntime Game = null!;
        internal LocalGameplayTimeStore Storage = null!;
        internal LocalGameplayTimeRuntime Stats = null!;
        private GameLogRuntime? _sampler;
        internal string Key => Identities.Read().SelectedSourceKey!;
        internal string Profile => Identities.Read().ActiveProfileId!;
        internal string StatisticsDirectory => Path.Combine(Root, "local-gameplay-time-v1");
        internal string PathFor(string profile) => Path.Combine(StatisticsDirectory, profile + ".bin");
        internal LocalGameplayTimeSaved Saved => Storage.Read(Profile);
        internal byte[] Bytes(string profile) => File.ReadAllBytes(PathFor(profile));
        internal Fixture()
        {
            Log = Path.Combine(Root, "install", "LIVE", "Game.log"); Directory.CreateDirectory(Path.GetDirectoryName(Log)!);
            File.WriteAllText(Log, Identity("Pilot-Example", "100", Start.AddMinutes(-1))); Reopen();
            var candidate = Evidence.Select(Identities.Read().Revision, Log, "LIVE");
            Evidence.Confirm(candidate.SourceKey!, candidate.EvidenceKey!); Running(); WriteIdentity();
        }
        internal void Reopen()
        {
            _sampler?.Dispose(); Stats?.RetireAsync().GetAwaiter().GetResult(); Mode = (Mode.Active, Mode.Generation + 1);
            Identities = new(Path.Combine(Root, "device"), Clock); Evidence = new(Identities, () => Process, Clock);
            Game = new(Identities, () => Mode, () => Process, Clock); Storage = new(Root, Clock);
            Stats = new(Identities, Storage, Game, () => { StatisticsModeHook?.Invoke(); return Mode; }, Clock); Game.AttachStatistics(Stats);
            _sampler = new(new(Path.Combine(Root, "account")), () => { AccountReads++; return (null, 1); },
                () => throw new InvalidOperationException("Unexpected account Handle read"),
                () => throw new InvalidOperationException("Unexpected account process probe"), Clock);
            _sampler.AttachLocalSlot(Game); _sampler.RetireAccountAsync().GetAwaiter().GetResult();
        }
        internal void Running() => Process = new("running", Log, Clock.Now, Id());
        internal void WriteIdentity(string handle = "Pilot-Example", string geid = "100") => File.WriteAllText(Log, Identity(handle, geid, Clock.Now));
        internal void ConfirmCurrent()
        { var candidate = Evidence.Refresh(Key); Evidence.Confirm(candidate.SourceKey!, candidate.EvidenceKey!); }
        internal void EnableListening() => Game.ApplyListening(Key, true);
        internal void Allow() => Stats.ApplyConsent(Key, true);
        internal void RecordFive() { EnableListening(); Allow(); Tick(0); Tick(5); Check(Saved.Seconds == 5, "Fixture records one actual interval."); }
        internal void Tick(double seconds)
        { Clock.Now = Clock.Now.AddSeconds(seconds); Clock.Timers.Single(t => !t.Disposed).Fire(); }
        public void Dispose()
        {
            StatisticsModeHook = null; _sampler?.Dispose(); Stats.RetireAsync().GetAwaiter().GetResult();
            var full = Path.GetFullPath(Root); var parent = Path.GetFullPath(Path.Combine(Path.GetTempPath(), "starbridge-first-use-local-statistics"));
            if (Path.GetDirectoryName(full) != parent || !Guid.TryParseExact(Path.GetFileName(full), "N", out _) ||
                File.GetAttributes(full).HasFlag(FileAttributes.ReparsePoint)) throw new InvalidOperationException("Unsafe fixture cleanup target.");
            Directory.Delete(full, recursive: true);
        }
    }
    private static void Expect(string code, Action action)
    { try { action(); } catch (LocalFirstUseException error) when (error.Code == code) { return; } throw new InvalidOperationException("Expected " + code); }
    private static void ExpectOther<T>(Action action) where T : Exception
    { try { action(); } catch (T) { return; } throw new InvalidOperationException("Expected " + typeof(T).Name); }
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
}
