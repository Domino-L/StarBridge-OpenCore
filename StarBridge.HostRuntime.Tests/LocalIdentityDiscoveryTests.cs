using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using StarBridge.HostRuntime.Onboarding;

internal static class LocalIdentityDiscoveryTests
{
    private static readonly DateTimeOffset Now = new(2026, 1, 1, 12, 0, 0, TimeSpan.Zero);
    private static string Line(string handle = "Pilot-Example", string id = "100", int secondsAgo = 60) =>
        $"<{Now.AddSeconds(-secondsAgo):yyyy-MM-dd'T'HH:mm:ss.fff'Z'}> nickname=\"{handle}\" playerGEID={id}\n";

    internal static void Run()
    {
        var cases = new (string Name, Action Test)[] {
            ("current and allowed history scope only", Scope),
            ("unique identity and no latest-account guessing", Identity),
            ("incomplete, damaged and encoding evidence", Incomplete),
            ("file count, byte and line bounds", Limits),
            ("cancellation and cooperative deadline", Interrupted),
            ("changed scope and stable scan receipts", Changes),
            ("unsafe paths, hard links and pinned directories", Paths),
            ("unreadable member invalidates the whole scope", Unreadable),
            ("absent current log and exact baseline receipt", AbsentCurrent)
        };
        foreach (var test in cases) { test.Test(); Console.WriteLine("PASS first-use discovery: " + test.Name); }
    }

    private static void Scope()
    {
        using var fixture = new Fixture();
        Require(fixture.Scan() is { State: "missing", ScopeChecked: true, Handle: null }, "Empty complete scope is missing.");
        File.WriteAllText(fixture.GameLog, Line());
        var current = fixture.Scan();
        Require(current is { State: "candidate", ScopeChecked: true, Handle: "Pilot-Example" } &&
            current.ObservedAt == Now.AddMinutes(-1), "Game.log supplies historical identity, not live presence.");
        fixture.Write("consistent.LOG", Line(id: "000100", secondsAgo: 30));
        fixture.Write("ignored.txt", Line("Other-Pilot"));
        Directory.CreateDirectory(Path.Combine(fixture.Backups, "nested"));
        File.WriteAllText(Path.Combine(fixture.Backups, "nested", "ignored.log"), Line("Other-Pilot"));
        Directory.CreateDirectory(Path.Combine(fixture.Root, "PTU"));
        File.WriteAllText(Path.Combine(fixture.Root, "PTU", "Game.log"), Line("Other-Pilot"));
        var before = File.ReadAllBytes(fixture.GameLog);
        Require(fixture.Scan() is { State: "candidate", Handle: "Pilot-Example" } &&
            before.SequenceEqual(File.ReadAllBytes(fixture.GameLog)), "No recursion, cross-version borrowing or input writes.");
        using var ptu = new Fixture("PTU");
        File.WriteAllText(ptu.GameLog, Line("Other-Pilot"));
        Require(ptu.Scan() is { State: "candidate", Handle: "Other-Pilot" }, "Explicit PTU source is supported separately.");
        Require(ptu.Scanner.Scan(ptu.GameLog, "LIVE").State == "unsafe", "Version must match the selected installation.");
    }

    private static void Identity()
    {
        using var fixture = new Fixture();
        File.WriteAllText(fixture.GameLog, Line());
        fixture.Write("old.log", Line("Other-Pilot", "200", 120));
        Require(fixture.Scan() is { State: "conflict", ScopeChecked: true, Handle: null },
            "The newer account cannot erase a different historical identity.");
        fixture.Write("old.log", Line(id: "200"));
        Require(fixture.Scan().State == "conflict", "Same Handle and different numeric identity is not unique.");
        fixture.Write("old.log", Line("pilot-example", "000100", 120));
        Require(fixture.Scan().State == "candidate", "Case and numeric leading zeroes preserve one identity.");
        File.WriteAllText(fixture.GameLog, Line() + Line("Other-Pilot", "200", 30));
        Require(fixture.Scan().State == "conflict", "Current file includes old sessions too; latest is not automatic ownership.");
    }

    private static void AbsentCurrent()
    {
        using var fixture = new Fixture();
        File.Delete(fixture.GameLog);
        Require(fixture.Scan() is { State: "missing", ScopeChecked: true, Baseline.FileIdentity: null, Baseline.Cursor: 0 },
            "An absent Game.log is complete absence in the explicitly selected existing installation.");
        fixture.Write("old.log", Line());
        Require(fixture.Scan() is { State: "candidate", ScopeChecked: true, Handle: "Pilot-Example", Baseline.FileIdentity: null },
            "A complete unique permitted archive may supply history even before Game.log exists.");
        fixture.Clock.OnRead = () => File.WriteAllText(fixture.GameLog, Line());
        Require(fixture.Scan() is { State: "changed", ScopeChecked: false, Baseline: null },
            "A current log created after scope enumeration invalidates the absence receipt.");
        var stable = fixture.Scan();
        Require(stable.Baseline is { FileIdentity.Length: 48, PrefixHash.Length: 64 } &&
            stable.Baseline.Cursor == new FileInfo(fixture.GameLog).Length,
            "A stable receipt describes the exact scanned current file, not a post-scan cursor.");
    }

    private static void Incomplete()
    {
        using var fixture = new Fixture();
        File.WriteAllText(fixture.GameLog, Line() + "ordinary unfinished tail");
        Require(fixture.Scan() is { State: "incomplete", ScopeChecked: false, Handle: null }, "Tail cannot borrow a preceding candidate.");
        fixture.Write("tail.log", Line().TrimEnd());
        File.WriteAllText(fixture.GameLog, Line());
        Require(fixture.Scan().State == "incomplete", "Archives require completed lines too.");
        fixture.Write("tail.log", "<2026-02-30T11:59:00Z> nickname=\"Pilot-Example\" playerGEID=100\n");
        Require(fixture.Scan().State == "conflict", "Damaged identity is uncertainty, not absence.");
        fixture.Write("tail.log", Line(secondsAgo: -1));
        Require(fixture.Scan().State == "conflict", "Future identity cannot authorize the local profile.");
        File.WriteAllBytes(Path.Combine(fixture.Backups, "tail.log"), [0xff, 0xfe, 0x0a]);
        Require(fixture.Scan() is { State: "unavailable", ScopeChecked: false }, "Invalid encoding is not a skipped file.");
        fixture.Write("tail.log", "\uFEFF" + Line().Replace("\n", "\r\n"));
        File.WriteAllText(fixture.GameLog, new string('x', 16360) + "\n" + Line().Replace("\n", "\r"));
        Require(fixture.Scan().State == "candidate", "BOM, CRLF, CR and block-split records are accepted.");
    }

    private static void Limits()
    {
        using (var files = new Fixture())
        {
            for (var i = 0; i < 512; i++) files.Write(i + ".log", "");
            Require(files.Scan() is { State: "missing", ScopeChecked: true }, "Exactly 512 archives remains within scope.");
            files.Write("512.log", "");
            Require(files.Scan() is { State: "limit", ScopeChecked: false }, "Too many archives is not missing.");
        }
        using (var large = new Fixture())
        {
            using (var stream = File.OpenWrite(large.GameLog)) stream.SetLength(64L * 1024 * 1024 + 1);
            Require(large.Scan().State == "limit", "Single-file byte cap is checked before reading.");
        }
        using (var total = new Fixture())
        {
            for (var i = 0; i < 5; i++)
            {
                total.Write(i + ".log", "");
                using var stream = File.OpenWrite(Path.Combine(total.Backups, i + ".log"));
                stream.SetLength(64L * 1024 * 1024);
            }
            Require(total.Scan().State == "limit", "Whole-scope bytes are bounded before parsing.");
        }
        using var longLine = new Fixture();
        File.WriteAllText(longLine.GameLog, new string('x', 65537) + "\n" + Line());
        Require(longLine.Scan().State == "limit", "Overlong lines never return a partial candidate.");
    }

    private static void Interrupted()
    {
        using var fixture = new Fixture();
        using var cancelled = new CancellationTokenSource();
        cancelled.Cancel();
        Require(fixture.Scanner.Scan(fixture.GameLog, fixture.Version, cancelled.Token).State == "cancelled", "Cancellation remains explicit.");
        var clock = new FixtureClock { TimestampStep = TimeSpan.TicksPerSecond * 16 };
        Require(new LocalIdentityDiscovery(clock).Scan(fixture.GameLog, fixture.Version).State == "limit", "Deadline does not produce absence.");
        using var duringRead = new CancellationTokenSource();
        fixture.Clock.OnRead = duringRead.Cancel;
        Require(fixture.Scanner.Scan(fixture.GameLog, fixture.Version, duringRead.Token).State == "cancelled", "Cancellation after file capture is not a partial result.");
        using var exclusive = new FileStream(fixture.GameLog, FileMode.Open, FileAccess.ReadWrite, FileShare.None);
        Require(exclusive.CanRead, "Interrupted scans release all file handles.");
    }

    private static void Changes()
    {
        using var fixture = new Fixture();
        File.WriteAllText(fixture.GameLog, Line());
        var first = fixture.Scan();
        Require(first.ScopeStamp == fixture.Scan().ScopeStamp, "Stable bytes, names and stamps preserve the receipt.");
        fixture.Write("new.log", Line());
        Require(first.ScopeStamp != fixture.Scan().ScopeStamp, "Scope additions change the evidence generation.");
        fixture.Clock.OnRead = () => File.AppendAllText(fixture.GameLog, "new event\n");
        Require(fixture.Scan() is { State: "changed", ScopeChecked: false, Handle: null }, "Writes after capture invalidate the whole scan.");
        fixture.Clock.OnRead = () => fixture.Write("late.log", Line());
        Require(fixture.Scan().State == "changed", "Late archive additions invalidate a previously enumerated scope.");
        fixture.Clock.OnRead = () => {
            try { File.Move(fixture.GameLog, fixture.GameLog + ".moved"); }
            catch (IOException) { return; }
            throw new InvalidOperationException("A scanned file must stay pinned against replacement.");
        };
        Require(fixture.Scan().State == "candidate", "Rename refusal preserves a valid read-only scope.");

        using var rewritten = new Fixture();
        File.WriteAllText(rewritten.GameLog, Line());
        var originalWrite = File.GetLastWriteTimeUtc(rewritten.GameLog);
        rewritten.Clock.OnRead = () => {
            var checks = 0;
            rewritten.Clock.OnTick = () => {
                // A deterministic clock advances past the first complete file pass.
                if (++checks != 4) return;
                File.WriteAllText(rewritten.GameLog, Line("Other-Example"));
                File.SetLastWriteTimeUtc(rewritten.GameLog, originalWrite);
            };
        };
        Require(rewritten.Scan() is { State: "changed", ScopeChecked: false, Handle: null },
            "An in-place rewrite with identical length/metadata must be caught by the content recheck.");
    }

    private static void Paths()
    {
        using var fixture = new Fixture();
        foreach (var path in new[] { "Game.log", @"\\server\share\LIVE\Game.log", fixture.GameLog + ":data",
            Path.Combine(Path.GetDirectoryName(fixture.GameLog)!, "..", "LIVE", "Game.log") })
            Require(fixture.Scanner.Scan(path, "LIVE").State == "unsafe", "Unsafe paths never get scanned.");
        var outside = Path.Combine(fixture.Root, "outside.log");
        File.WriteAllText(outside, Line());
        Directory.CreateDirectory(fixture.Backups);
        var link = Path.Combine(fixture.Backups, "linked.log");
        Require(CreateHardLink(link, outside, IntPtr.Zero), "Hard-link fixture creation must succeed.");
        Require(fixture.Scan() is { State: "unavailable", ScopeChecked: false }, "Hard links are not scope members.");
        File.Delete(link); // Only this fixture link; retain and verify the target.
        Require(File.ReadAllText(outside) == Line(), "Rejected link target remains untouched.");
        Directory.Delete(fixture.Backups);
        var target = Directory.CreateDirectory(Path.Combine(fixture.Root, "outside-backups")).FullName;
        var start = new ProcessStartInfo("powershell.exe") { UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardOutput = true, RedirectStandardError = true };
        foreach (var value in new[] { "-NoProfile", "-NonInteractive", "-Command",
            "New-Item -ItemType Junction -Path '" + fixture.Backups.Replace("'", "''") + "' -Target '" + target.Replace("'", "''") + "' -ErrorAction Stop | Out-Null" })
            start.ArgumentList.Add(value);
        using var process = Process.Start(start)!;
        process.WaitForExit();
        Require(process.ExitCode == 0, "Junction fixture must be real, not skipped.");
        try { Require(fixture.Scan().State == "unsafe", "A linked historical directory is rejected before traversal."); }
        finally { Directory.Delete(fixture.Backups); } // Remove link only, never recursively traverse it.
        Require(Directory.Exists(target), "Junction rejection must not mutate its target.");
    }

    private static void Unreadable()
    {
        using var fixture = new Fixture();
        File.WriteAllText(fixture.GameLog, Line());
        fixture.Write("locked.log", "");
        using var lease = new FileStream(Path.Combine(fixture.Backups, "locked.log"), FileMode.Open, FileAccess.ReadWrite, FileShare.None);
        Require(fixture.Scan() is { State: "unavailable", ScopeChecked: false, Handle: null },
            "An unreadable empty member still invalidates complete scope authority.");
    }

    private sealed class FixtureClock : TimeProvider
    {
        private long _timestamp;
        internal long TimestampStep { get; init; } = 1;
        internal Action? OnRead { get; set; }
        internal Action? OnTick { get; set; }
        public override long TimestampFrequency => TimeSpan.TicksPerSecond;
        public override long GetTimestamp() { OnTick?.Invoke(); _timestamp += TimestampStep; return _timestamp; }
        public override DateTimeOffset GetUtcNow() { var action = OnRead; OnRead = null; action?.Invoke(); return Now; }
    }
    private sealed class Fixture : IDisposable
    {
        internal string Root { get; } = Path.Combine(Path.GetTempPath(), "starbridge-first-use-discovery", Guid.NewGuid().ToString("N"));
        internal string Version { get; }
        internal string GameLog { get; }
        internal string Backups => Path.Combine(Path.GetDirectoryName(GameLog)!, "logbackups");
        internal FixtureClock Clock { get; } = new();
        internal LocalIdentityDiscovery Scanner { get; }
        internal Fixture(string version = "LIVE")
        {
            Version = version;
            GameLog = Path.Combine(Root, version, "Game.log");
            Directory.CreateDirectory(Path.GetDirectoryName(GameLog)!);
            File.WriteAllText(GameLog, "");
            Scanner = new(Clock);
        }
        internal void Write(string name, string contents)
        {
            Directory.CreateDirectory(Backups);
            File.WriteAllText(Path.Combine(Backups, name), contents, new UTF8Encoding(false));
        }
        internal LocalIdentityDiscoveryResult Scan() => Scanner.Scan(GameLog, Version);
        public void Dispose()
        {
            var full = Path.GetFullPath(Root);
            var allowed = Path.GetFullPath(Path.Combine(Path.GetTempPath(), "starbridge-first-use-discovery"));
            if (Path.GetDirectoryName(full) != allowed || !Guid.TryParseExact(Path.GetFileName(full), "N", out _))
                throw new InvalidOperationException("Unsafe fixture cleanup target.");
            Directory.Delete(full, recursive: true);
        }
    }
    [DllImport("kernel32.dll", EntryPoint = "CreateHardLinkW", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CreateHardLink(string file, string existing, IntPtr security);
    private static void Require(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }
}
