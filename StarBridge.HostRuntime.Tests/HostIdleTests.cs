using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Presence;
using System.Collections.Concurrent;

internal static class HostIdleTests
{
    // The cache's timing rules below were written for a 500 ms window; the default is longer.
    private static readonly TimeSpan HalfSecond = TimeSpan.FromMilliseconds(500);

    private static void Check(bool value, string message)
    { if (!value) throw new InvalidOperationException(message); }

    internal static Task Processes()
    {
        void Test(string name, Action test) { test(); Console.WriteLine("PASS CX78 process " + name); }
        Test("case insensitive names and Bin64", () =>
        {
            var source = new Source { Entries = [new(1, "sTaRcItIzEn_LiVe.ExE")] };
            var result = GameProcessSnapshotCache.Resolve(new GameProcessSnapshotCache(source).Observe());
            Check(result.State == "running" && result.LogPath == @"C:\Game\Game.log" &&
                result.SessionId == "1:" + source.Start.UtcTicks, "Lost path/time/session evidence");
        });
        Test("multiple target processes remain unknown", () =>
        {
            var source = new Source { Entries = [new(1, "StarCitizen.exe"), new(2, "StarCitizen_EPTU.exe")] };
            Check(GameProcessSnapshotCache.Resolve(new GameProcessSnapshotCache(source).Observe()).State == "unknown", "Ambiguous processes");
        });
        Test("exited target is not running and releases handles", () =>
        {
            var source = new Source { Exit = true };
            Check(GameProcessSnapshotCache.Resolve(new GameProcessSnapshotCache(source).Observe()).State == "notRunning", "Confirmed exit");
            Check(source.SnapshotDisposed == 1 && source.HandleDisposed == 1, "Exit leaked handles");
        });
        Test("access denied is unknown, releases handles and retries after 5 seconds", () =>
        {
            var source = new Source { Denied = true }; var time = new Clock();
            var cache = new GameProcessSnapshotCache(source, time, HalfSecond);
            Check(GameProcessSnapshotCache.Resolve(cache.Observe()).State == "unknown", "Denied became absence");
            Check(source.SnapshotDisposed == 1 && source.HandleDisposed == 1, "Denied leaked handles");
            source.Denied = false;
            time.Advance(TimeSpan.FromMilliseconds(4999));
            Check(GameProcessSnapshotCache.Resolve(cache.Observe()).State == "unknown" && source.Opened.Count == 1, "Reopened during the wait");
            time.Advance(TimeSpan.FromMilliseconds(1));
            Check(GameProcessSnapshotCache.Resolve(cache.Observe()).State == "running" && source.Opened.Count == 2, "Sticky failure");
        });
        Test("a live game is opened once however long it runs", () =>
        {
            var source = new Source(); var time = new Clock();
            var cache = new GameProcessSnapshotCache(source, time, HalfSecond);
            var session = GameProcessSnapshotCache.Resolve(cache.Observe());
            for (var i = 0; i < 100; i++)
            {
                time.Advance(TimeSpan.FromMilliseconds(500));
                Check(GameProcessSnapshotCache.Resolve(cache.Observe()) == session, "Session changed while running");
            }
            Check(source.Opened.Count == 1 && source.HandleDisposed == 1 && source.Captures == 101, "Opened beyond the new PID");
        });
        Test("a game gone from the snapshot is not running, and its return is a new session", () =>
        {
            var source = new Source(); var time = new Clock();
            var cache = new GameProcessSnapshotCache(source, time, HalfSecond);
            var first = GameProcessSnapshotCache.Resolve(cache.Observe());
            var entries = source.Entries;
            source.Entries = [];
            time.Advance(TimeSpan.FromMilliseconds(500));
            Check(GameProcessSnapshotCache.Resolve(cache.Observe()).State == "notRunning" && source.Opened.Count == 1, "Exit needed a handle");
            source.Entries = entries; source.Start = source.Start.AddMinutes(1);
            time.Advance(TimeSpan.FromMilliseconds(500));
            var next = GameProcessSnapshotCache.Resolve(cache.Observe());
            Check(next.State == "running" && next.SessionId != first.SessionId && source.Opened.Count == 2, "Return reused the old session");
        });
        Test("a failed enumeration cannot hide a same-name process taking the PID", () =>
        {
            var source = new Source(); var time = new Clock();
            var cache = new GameProcessSnapshotCache(source, time, HalfSecond);
            var session = GameProcessSnapshotCache.Resolve(cache.Observe());
            source.Entries = [];
            source.EnumerationFails = true;
            time.Advance(TimeSpan.FromMilliseconds(500));
            Check(GameProcessSnapshotCache.Resolve(cache.Observe()).State == "unknown", "Partial enumeration trusted");
            source.Entries = [new(1, "StarCitizen.exe")];
            source.EnumerationFails = false;
            source.Start = source.Start.AddMinutes(1);
            time.Advance(TimeSpan.FromSeconds(5));
            var next = GameProcessSnapshotCache.Resolve(cache.Observe());
            Check(next.State == "running" && next.SessionId != session.SessionId && source.Opened.Count == 2, "Old session survived the failure");
        });
        Test("a gap in watching cannot hide a same-name process taking the PID", () =>
        {
            var source = new Source(); var time = new Clock();
            var cache = new GameProcessSnapshotCache(source, time, HalfSecond);
            var session = GameProcessSnapshotCache.Resolve(cache.Observe());
            for (var i = 0; i < 20; i++)
            {
                time.Advance(TimeSpan.FromSeconds(6)); // A slow regular caller, not a stop in watching.
                Check(GameProcessSnapshotCache.Resolve(cache.Observe()) == session && source.Opened.Count == 1, "Ordinary polling reopened the game");
            }
            source.Start = source.Start.AddMinutes(1);
            time.Advance(TimeSpan.FromSeconds(30) + TimeSpan.FromTicks(1));
            var next = GameProcessSnapshotCache.Resolve(cache.Observe());
            Check(next.SessionId != session.SessionId && source.Opened.Count == 2, "Old session survived the gap");
        });
        Test("unrelated protected processes are never opened", () =>
        {
            var source = new Source { Entries = [new(9, "Protected.exe"), new(1, "StarCitizen.exe")] };
            new GameProcessSnapshotCache(source).Observe();
            Check(source.Opened.SequenceEqual([1]) && source.SnapshotDisposed == 1, "Opened unrelated process");
        });
        Test("enumeration failure releases snapshot and retries", () =>
        {
            var source = new Source { EnumerationFails = true }; var time = new Clock();
            var cache = new GameProcessSnapshotCache(source, time, HalfSecond);
            Check(GameProcessSnapshotCache.Resolve(cache.Observe()).State == "unknown", "Partial enumeration trusted");
            Check(source.SnapshotDisposed == 1, "Snapshot leaked on enumeration failure");
            for (var i = 0; i < 4; i++)
            {
                time.Advance(TimeSpan.FromSeconds(1));
                Check(GameProcessSnapshotCache.Resolve(cache.Observe()).State == "unknown" && source.Opened.Count == 1, "Repeating failure reopened the game");
            }
            source.EnumerationFails = false;
            time.Advance(TimeSpan.FromSeconds(1));
            Check(GameProcessSnapshotCache.Resolve(cache.Observe()).State == "running" && source.Opened.Count == 2, "Enumeration not retried");
        });
        Test("capture failure is unknown and recovers", () =>
        {
            var source = new Source { CaptureFails = true };
            var cache = new GameProcessSnapshotCache(source);
            Check(GameProcessSnapshotCache.Resolve(cache.Observe()).State == "unknown", "Capture failure became absence");
            source.CaptureFails = false;
            Check(GameProcessSnapshotCache.Resolve(cache.Observe()).State == "running", "Capture not retried");
        });
        Test("shared observation expires at 500ms; a PID reused by another game name is a new session", () =>
        {
            var source = new Source(); var time = new Clock();
            var cache = new GameProcessSnapshotCache(source, time, HalfSecond);
            var first = cache.Observe();
            var oldSession = GameProcessSnapshotCache.Resolve(first);
            source.Start = source.Start.AddSeconds(1);
            time.Advance(TimeSpan.FromMilliseconds(499));
            Check(ReferenceEquals(first, cache.Observe()) && source.Captures == 1, "Observation was not shared");
            time.Advance(TimeSpan.FromMilliseconds(1));
            source.Entries = [new(1, "StarCitizen_EPTU.exe")];
            var next = GameProcessSnapshotCache.Resolve(cache.Observe());
            Check(source.Captures == 2 && next.SessionId != oldSession.SessionId &&
                next.StartedAt == source.Start && source.HandleDisposed == 2, "PID-only identity or stale cache");
        });
        foreach (var (name, invalidate) in new (string, Action<Source>)[]
        {
            ("invalid executable path", source => source.Executable = @"C:\Game\Other\StarCitizen.exe"),
            ("missing executable path", source => source.Executable = null),
            ("missing start time", source => source.MissingStart = true),
            ("explicit uncertainty", source => source.Uncertain = true)
        })
        Test(name + " retries after 5 seconds once repaired", () =>
        {
            var source = new Source(); var time = new Clock();
            invalidate(source);
            var cache = new GameProcessSnapshotCache(source, time, HalfSecond);
            Check(GameProcessSnapshotCache.Resolve(cache.Observe()).State == "unknown", "Invalid evidence was trusted");
            source.Executable = @"C:\Game\Bin64\StarCitizen.exe";
            source.MissingStart = source.Uncertain = false;
            Check(GameProcessSnapshotCache.Resolve(cache.Observe()).State == "unknown" && source.Opened.Count == 1,
                "Reopened during the wait");
            time.Advance(TimeSpan.FromSeconds(5));
            var repaired = cache.Observe();
            Check(GameProcessSnapshotCache.Resolve(repaired).State == "running" && source.Captures == 3 && source.Opened.Count == 2,
                "Uncertain evidence stayed after repair");
            Check(ReferenceEquals(repaired, cache.Observe()) && source.Captures == 3, "Repaired observation was not shared");
        });
        Test("the default observation is shared for 2.5 seconds", () =>
        {
            var source = new Source { Entries = [] }; var time = new Clock();
            var cache = new GameProcessSnapshotCache(source, time);
            Check(GameProcessSnapshotCache.Resolve(cache.Observe()).State == "notRunning", "Absent game");
            source.Entries = [new(1, "StarCitizen.exe")];
            time.Advance(TimeSpan.FromMilliseconds(2499));
            Check(GameProcessSnapshotCache.Resolve(cache.Observe()).State == "notRunning" && source.Captures == 1, "Listed again too soon");
            time.Advance(TimeSpan.FromMilliseconds(1));
            Check(GameProcessSnapshotCache.Resolve(cache.Observe()).State == "running" && source.Captures == 2, "A launch waited past 2.5 seconds");
        });
        Test("a watched game is not listed again, and its exit is seen at once", () =>
        {
            var source = new Source { Watchable = true }; var time = new Clock();
            var cache = new GameProcessSnapshotCache(source, time);
            var session = GameProcessSnapshotCache.Resolve(cache.Observe());
            Check(session.State == "running" && source.HandleDisposed == 0, "The handle was not kept");
            for (var i = 0; i < 9; i++)
            {
                time.Advance(TimeSpan.FromSeconds(1));
                Check(GameProcessSnapshotCache.Resolve(cache.Observe()) == session && source.Captures == 1, "A watched game was listed again");
            }
            time.Advance(TimeSpan.FromSeconds(1));
            Check(GameProcessSnapshotCache.Resolve(cache.Observe()) == session && source.Captures == 2 && source.Opened.Count == 1,
                "The 10 second refresh reopened the game or did not run");
            source.Gone = true; // Still listed, as a closing process can briefly be.
            time.Advance(TimeSpan.FromMilliseconds(100));
            Check(GameProcessSnapshotCache.Resolve(cache.Observe()).State == "notRunning" && source.Captures == 3 &&
                source.HandleDisposed == 1, "Exit waited for the list to go stale");
            source.Gone = false; source.Start = source.Start.AddMinutes(1);
            time.Advance(TimeSpan.FromMilliseconds(2500));
            var next = GameProcessSnapshotCache.Resolve(cache.Observe());
            Check(next.State == "running" && next.SessionId != session.SessionId && source.Opened.Count == 2, "A relaunch was not a new session");
        });
        Test("a game that exits right after its first read is not running", () =>
        {
            var source = new Source { Watchable = true, Gone = true }; var time = new Clock();
            var cache = new GameProcessSnapshotCache(source, time);
            Check(GameProcessSnapshotCache.Resolve(cache.Observe()).State == "notRunning" && source.HandleDisposed == 1, "A confirmed exit was reported as running");
            source.Gone = false;
            Check(GameProcessSnapshotCache.Resolve(cache.Observe()).State == "notRunning" && source.Captures == 1, "An empty answer was not shared");
        });
        Test("a second instance beside a watched game is noticed within 10 seconds", () =>
        {
            var source = new Source { Watchable = true }; var time = new Clock();
            var cache = new GameProcessSnapshotCache(source, time);
            Check(GameProcessSnapshotCache.Resolve(cache.Observe()).State == "running", "First instance");
            source.Entries = [new(1, "StarCitizen.exe"), new(2, "StarCitizen_PTUR.exe")];
            time.Advance(TimeSpan.FromSeconds(10));
            Check(GameProcessSnapshotCache.Resolve(cache.Observe()).State == "unknown", "Second instance hidden");
        });
        Test("a watching handle that cannot answer forces a fresh list and a new read", () =>
        {
            var source = new Source { Watchable = true }; var time = new Clock();
            var cache = new GameProcessSnapshotCache(source, time);
            Check(GameProcessSnapshotCache.Resolve(cache.Observe()).State == "running", "First read");
            source.WatchFails = true;
            time.Advance(TimeSpan.FromMilliseconds(100));
            Check(GameProcessSnapshotCache.Resolve(cache.Observe()).State == "running" && source.Captures == 2 &&
                source.Opened.Count == 2 && source.HandleDisposed == 2, "A failed watch was trusted, or read as an exit");
        });
        Test("a watched game is released when watching stops for too long", () =>
        {
            var source = new Source { Watchable = true }; var time = new Clock();
            var cache = new GameProcessSnapshotCache(source, time);
            cache.Observe();
            time.Advance(TimeSpan.FromSeconds(31));
            Check(GameProcessSnapshotCache.Resolve(cache.Observe()).State == "running" && source.HandleDisposed == 1 &&
                source.Opened.Count == 2, "A gap kept the old handle");
        });
        Test("startup and running answers keep names-only meaning", () =>
        {
            GameProcessEvidence Known(int pid) => new(pid, @"C:\Game\Bin64\StarCitizen.exe", DateTimeOffset.UnixEpoch.AddDays(pid));
            GameProcessEvidence Unreadable(int pid) => new(pid, null, null, true);
            Check(SharedGameProcesses.Startup([]) == new StarBridge.HostRuntime.Overlay.GameStartupSession("notRunning") &&
                !SharedGameProcesses.IsRunning([]), "Nothing found");
            Check(SharedGameProcesses.Startup([Known(7)]) == new StarBridge.HostRuntime.Overlay.GameStartupSession("running", 7, DateTimeOffset.UnixEpoch.AddDays(7)) &&
                SharedGameProcesses.IsRunning([Known(7)]), "One readable game");
            Check(SharedGameProcesses.Startup([Unreadable(8)]) == new StarBridge.HostRuntime.Overlay.GameStartupSession("running", 8) &&
                SharedGameProcesses.IsRunning([Unreadable(8)]), "An unreadable game process still counts by name");
            Check(SharedGameProcesses.Startup([Known(7), Unreadable(8)]).State == "unknown", "Two games");
            Check(SharedGameProcesses.Startup([Unreadable(0)]).State == "unknown" && !SharedGameProcesses.IsRunning([Unreadable(0)]),
                "A failed list is unknown for startup and not running, as before");
        });
        Test("concurrent callers share one enumeration", () =>
        {
            var source = new Source(); var cache = new GameProcessSnapshotCache(source);
            Parallel.For(0, 20, _ => Check(GameProcessSnapshotCache.Resolve(cache.Observe()).State == "running", "Concurrent result"));
            Check(source.Captures == 1 && source.HandleDisposed == 1, "Duplicate concurrent snapshots");
        });
        Test("native metadata and image mismatch use opened handle", () =>
        {
            var source = new WindowsGameProcessSource();
            using var process = source.Open(new(Environment.ProcessId, Path.GetFileName(Environment.ProcessPath!)));
            var evidence = process.Read();
            Check(evidence is { Uncertain: false, StartedAt: not null } && evidence.Pid == Environment.ProcessId &&
                evidence.Executable!.Equals(Environment.ProcessPath, StringComparison.OrdinalIgnoreCase), "Native metadata failed");
            using var replaced = source.Open(new(Environment.ProcessId, "StarCitizen.exe"));
            Check(replaced.Read() is { Uncertain: true }, "Replacement executable was trusted");
        });
        Test("native handle confirms exit code 259", () =>
        {
            var start = new System.Diagnostics.ProcessStartInfo(Environment.ProcessPath!)
            { UseShellExecute = false, RedirectStandardInput = true, CreateNoWindow = true };
            if (string.Equals(Path.GetFileNameWithoutExtension(Environment.ProcessPath), "dotnet", StringComparison.OrdinalIgnoreCase))
                start.ArgumentList.Add(typeof(HostIdleTests).Assembly.Location);
            start.ArgumentList.Add("--cx78-native-exit-259-child");
            using var child = System.Diagnostics.Process.Start(start)!;
            Console.WriteLine("START CX78 native exit child PID=" + child.Id);
            try
            {
                var source = new WindowsGameProcessSource();
                using var handle = source.Open(new(child.Id, Path.GetFileName(Environment.ProcessPath!)));
                Check(handle.Read() is { Uncertain: false }, "Live child was not observed");
                Check(handle.Exited() == false, "A live child read as exited");
                child.StandardInput.WriteLine();
                child.StandardInput.Close();
                Check(child.WaitForExit(10000), "Exit child timed out; PID=" + child.Id);
                Check(child.ExitCode == 259, "Exit fixture did not return 259");
                Check(handle.Read() is null, "Exit code 259 was mistaken for a live process");
                Check(handle.Exited() == true, "The handle missed the exit");
            }
            finally
            {
                child.StandardInput.Close();
                if (!child.WaitForExit(10000)) Console.WriteLine("PENDING CX78 child PID=" + child.Id);
            }
        });
        Test("an exited process another program still holds open is not listed", () =>
        {
            var start = new System.Diagnostics.ProcessStartInfo(Environment.ProcessPath!)
            { UseShellExecute = false, RedirectStandardInput = true, CreateNoWindow = true };
            if (string.Equals(Path.GetFileNameWithoutExtension(Environment.ProcessPath), "dotnet", StringComparison.OrdinalIgnoreCase))
                start.ArgumentList.Add(typeof(HostIdleTests).Assembly.Location);
            start.ArgumentList.Add("--cx78-native-exit-259-child");
            using var child = System.Diagnostics.Process.Start(start)!; // Holds a handle after the exit.
            var source = new WindowsGameProcessSource();
            bool Listed() { using var snapshot = source.Capture(); return snapshot.Entries.Any(entry => entry.Pid == child.Id); }
            try
            {
                using var held = source.Open(new(child.Id, Path.GetFileName(Environment.ProcessPath!)));
                Check(Listed() && ProcessSnapshotNames.Find((uint)child.Id) is not null, "Live child missing from the snapshot");
                child.StandardInput.WriteLine();
                child.StandardInput.Close();
                Check(child.WaitForExit(10000), "Exit child timed out; PID=" + child.Id);
                Check(!Listed(), "Exited process held open is still listed");
                Check(ProcessSnapshotNames.Find((uint)child.Id) is null, "Exited process still has a name");
            }
            finally
            {
                child.StandardInput.Close();
                if (!child.WaitForExit(10000)) Console.WriteLine("PENDING child PID=" + child.Id);
            }
        });
        Test("process names come from the snapshot", () =>
        {
            Check(string.Equals(ProcessSnapshotNames.Find((uint)Environment.ProcessId), Path.GetFileName(Environment.ProcessPath!), StringComparison.OrdinalIgnoreCase), "Own name");
            Check(ProcessSnapshotNames.Any(name => string.Equals(name, Path.GetFileName(Environment.ProcessPath!), StringComparison.OrdinalIgnoreCase)), "Own name not found");
            Check(!ProcessSnapshotNames.Any(_ => false), "A match that never holds was found");
            var self = (uint)Environment.ProcessId;
            Check(string.Equals(ProcessSnapshotNames.FindForeground(self), Path.GetFileName(Environment.ProcessPath!), StringComparison.OrdinalIgnoreCase), "Own foreground name");
            Check(ProcessSnapshotNames.FindForeground(uint.MaxValue - 3) is null, "A process that does not exist has a name");
            Check(ProcessSnapshotNames.FindForeground(self) is not null, "A miss must not stick");
            Check(ProcessSnapshotNames.IsFresh(1000, 1000) && ProcessSnapshotNames.IsFresh(1000, 5999), "Fresh within the age limit");
            Check(!ProcessSnapshotNames.IsFresh(1000, 6000) && !ProcessSnapshotNames.IsFresh(1000, 999), "A stale or future read is reread");
        });
        Test("native snapshot and target handles are released", () =>
        {
            var source = new WindowsGameProcessSource();
            using var self = System.Diagnostics.Process.GetCurrentProcess();
            void Observe()
            {
                using var snapshot = source.Capture();
                Check(snapshot.Entries.Any(entry => entry.Pid == Environment.ProcessId), "Native snapshot missing self");
                using var process = source.Open(new(Environment.ProcessId, Path.GetFileName(Environment.ProcessPath!)));
                Check(process.Read() is { Uncertain: false }, "Native handle read");
            }
            Observe(); self.Refresh(); var before = self.HandleCount;
            for (var i = 0; i < 20; i++) Observe();
            self.Refresh(); Check(self.HandleCount <= before + 4, "Native handles accumulated");
        });
        return Task.CompletedTask;
    }

    internal static Task Diagnostics()
    {
        void Test(string name, Action test) { test(); Console.WriteLine("PASS CX78 diagnostics " + name); }
        Test("projection aggregates sums maxima and five minute timer", () =>
        {
            var lines = new ConcurrentQueue<string>(); var time = new Clock();
            using var summary = new AccountCurrentDiagnosticSummary(lines.Enqueue, time);
            summary.Record(true, CurrentProjectionReason.none, 3, 7, 1, 0);
            summary.Record(true, CurrentProjectionReason.none, 5, 2, 1, 0);
            Check(lines.IsEmpty && time.Period == TimeSpan.FromMinutes(5), "Projection wrote per call or wrong timer");
            time.Fire();
            var line = lines.Single();
            Check(line.Contains("path=projection reason=none count=2") && line.Contains("waitMsMax=5 waitMsTotal=8") &&
                line.Contains("workMsMax=7 workMsTotal=9"), "Incorrect aggregate");
            summary.Flush(); Check(lines.Count == 1, "Double counted flush");
        });
        Test("full rate limit per reason per minute and summary includes suppressed", () =>
        {
            var lines = new ConcurrentQueue<string>(); var time = new Clock();
            using var summary = new AccountCurrentDiagnosticSummary(lines.Enqueue, time);
            for (var i = 0; i < 14; i++) summary.Record(false, CurrentProjectionReason.hostDeclined, 1, 2, 0, 0);
            summary.Record(false, CurrentProjectionReason.pendingEvents, 1, 2, 0, 0);
            summary.Flush();
            Check(lines.Count(line => !line.Contains(" summary ") && line.Contains("reason=hostDeclined")) == 10, "Rate cap");
            Check(lines.Any(line => line.Contains("reason=hostDeclined count=14 detailed=10 suppressed=4")), "Suppressed not counted");
            Check(lines.Count(line => !line.Contains(" summary ") && line.Contains("reason=pendingEvents")) == 1, "Reasons share budget");
            time.Advance(TimeSpan.FromSeconds(59));
            summary.Record(false, CurrentProjectionReason.hostDeclined, 0, 0, 0, 0); summary.Flush();
            Check(lines.Count(line => !line.Contains(" summary ") && line.Contains("reason=hostDeclined")) == 10, "Flush reset budget");
            time.Advance(TimeSpan.FromSeconds(1));
            summary.Record(false, CurrentProjectionReason.hostDeclined, 0, 0, 0, 0); summary.Flush();
            Check(lines.Count(line => !line.Contains(" summary ") && line.Contains("reason=hostDeclined")) == 11, "Minute did not reset budget");
        });
        Test("exit disposal flushes pending summary once", () =>
        {
            var lines = new ConcurrentQueue<string>();
            var summary = new AccountCurrentDiagnosticSummary(lines.Enqueue, new Clock());
            summary.Record(true, CurrentProjectionReason.none, 1, 2, 0, 0);
            summary.Dispose(); summary.Dispose();
            Check(lines.Count == 1 && lines.Single().Contains("count=1"), "Exit lost or duplicated summary");
        });
        Test("write failures never escape record timer or exit", () =>
        {
            var time = new Clock();
            var summary = new AccountCurrentDiagnosticSummary(_ => throw new IOException("fixture"), time);
            summary.Record(false, CurrentProjectionReason.hostDeclined, 1, 2, 0, 0);
            time.Fire();
            summary.Record(true, CurrentProjectionReason.none, 1, 2, 0, 0);
            summary.Dispose();
        });
        Test("blocked IO does not hold collection lock or caller", () =>
        {
            using var entered = new ManualResetEventSlim(); using var release = new ManualResetEventSlim();
            using var summary = new AccountCurrentDiagnosticSummary(_ => { entered.Set(); release.Wait(); }, new Clock());
            summary.Record(false, CurrentProjectionReason.hostDeclined, 0, 0, 0, 0);
            try
            {
                Check(entered.Wait(TimeSpan.FromSeconds(5)), "Background writer did not run");
                var record = Task.Run(() => summary.Record(true, CurrentProjectionReason.none, 0, 0, 0, 0));
                Check(record.Wait(TimeSpan.FromSeconds(2)), "Disk IO held collection lock");
            }
            finally { release.Set(); summary.Flush(); }
        });
        Test("background file handle permits data root retirement", () =>
        {
            var root = Directory.CreateTempSubdirectory("cx78-log-retirement-").FullName;
            var path = Path.Combine(root, "diagnostic.log");
            try
            {
                using var stream = AccountCurrentDiagnostics.OpenLogStream(path, FileMode.Append);
                stream.WriteByte(0);
                Directory.Delete(root, true);
                Check(!Directory.Exists(root), "Diagnostic handle blocked root retirement");
            }
            finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
        });
        return Task.CompletedTask;
    }

    private sealed class Source : IGameProcessSource
    {
        internal GameProcessEntry[] Entries = [new(1, "StarCitizen.exe")];
        internal DateTimeOffset Start = DateTimeOffset.UnixEpoch.AddDays(1);
        internal string? Executable = @"C:\Game\Bin64\StarCitizen.exe";
        internal bool Exit, Denied, EnumerationFails, CaptureFails, MissingStart, Uncertain;
        // Watchable handles answer Exited(); Gone is what they answer. WatchFails throws instead.
        internal bool Watchable, Gone, WatchFails;
        internal int Captures, SnapshotDisposed, HandleDisposed;
        internal List<int> Opened = [];
        public IGameProcessSnapshot Capture()
        { Captures++; if (CaptureFails) throw new IOException(); return new Snapshot(this); }
        public IGameProcessHandle Open(GameProcessEntry entry) { Opened.Add(entry.Pid); return new Target(this, entry.Pid); }
        private sealed class Snapshot(Source source) : IGameProcessSnapshot
        {
            public IEnumerable<GameProcessEntry> Entries
            {
                get
                {
                    foreach (var item in source.Entries) yield return item;
                    if (source.EnumerationFails) throw new IOException();
                }
            }
            public void Dispose() => source.SnapshotDisposed++;
        }
        private sealed class Target(Source source, int pid) : IGameProcessHandle
        {
            public GameProcessEvidence? Read()
            {
                if (source.Denied) throw new UnauthorizedAccessException();
                return source.Exit ? null : new(pid, source.Executable, source.MissingStart ? null : source.Start, source.Uncertain);
            }
            public bool? Exited() => source.WatchFails ? throw new IOException() : source.Watchable ? source.Gone : null;
            public void Dispose() => source.HandleDisposed++;
        }
    }

    private sealed class Clock : TimeProvider
    {
        private long _stamp;
        private Timer? _timer;
        internal TimeSpan Period;
        public override long TimestampFrequency => TimeSpan.TicksPerSecond;
        public override long GetTimestamp() => _stamp;
        public override DateTimeOffset GetUtcNow() => DateTimeOffset.UnixEpoch.AddTicks(_stamp);
        internal void Advance(TimeSpan value) => _stamp += value.Ticks;
        internal void Fire() => _timer!.Fire();
        public override ITimer CreateTimer(TimerCallback callback, object? state, TimeSpan dueTime, TimeSpan period)
        { Period = period; return _timer = new Timer(callback, state); }
        private sealed class Timer(TimerCallback callback, object? state) : ITimer
        {
            internal void Fire() => callback(state);
            public bool Change(TimeSpan dueTime, TimeSpan period) => true;
            public void Dispose() { }
            public ValueTask DisposeAsync() => ValueTask.CompletedTask;
        }
    }
}
