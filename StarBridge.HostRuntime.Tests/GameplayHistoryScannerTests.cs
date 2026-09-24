using System.Reflection;
using System.Runtime.ExceptionServices;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Win32.SafeHandles;
using StarBridge.HostRuntime.Presence;

internal static class GameplayHistoryScannerTests
{
    private const string Handle = "synthetic-pilot";
    private static readonly DateTimeOffset Epoch = new(2020, 1, 1, 0, 0, 0, TimeSpan.Zero);

    // Register in the existing Program test table:
    // ("Gameplay history scanner bounds, identity and interval semantics", GameplayHistoryScannerTests.Verify),
    internal static Task Verify()
    {
        var cases = new (string Name, Action Test)[]
        {
            ("LIVE import only", LiveOnly),
            ("read-only scope and WPF overlap semantics", ScopeAndOverlap),
            ("canonical local identity and ambiguity", IdentityEvidence),
            ("cutoff and clean exit evidence", CutoffAndExit),
            ("invalid, future and nonmonotonic sessions", InvalidSessions),
            ("streaming line and encoding boundaries", StreamingBoundaries),
            ("path, empty and unavailable codes", PathsAndFailures),
            ("file count and byte limits", ResourceLimits),
            ("cooperative cancellation and deadline", CancellationAndDeadline),
            ("reparse leaves and ancestors", ReparsePoints)
        };
        foreach (var test in cases)
        {
            test.Test();
            Console.WriteLine("PASS gameplay history: " + test.Name);
        }
        return Task.CompletedTask;
    }

    private static void LiveOnly()
    {
        foreach (var version in new[] { "PTU", "EPTU", "TECH-PREVIEW", "LIVE-copy" })
        {
            using var fixture = new Fixture(version);
            fixture.Write("session.log", Log(0, 3600));
            Code("path", () => fixture.Scan());
        }
        using var live = new Fixture("live");
        live.Write("session.log", Log(0, 3600));
        Equal(new(3600, 1, 1, 0), live.Scan(), "LIVE directory comparison is case insensitive.");
    }

    private static void ScopeAndOverlap()
    {
        using var fixture = new Fixture();
        // The selected live file is only an anchor; its contents must never be scanned.
        File.WriteAllText(fixture.GameLog, Log(0, 86400));
        fixture.Write("complete.log", Log(0, 3600, clean: true));
        fixture.Write("duplicate.log", Log(0, 3600, clean: true));
        fixture.Write("overlap.LOG", Log(1800, 5400));
        fixture.Write("other.log", Log(7200, 10800, player: "synthetic-other"));
        fixture.Write("ignored.txt", Log(10800, 14400));
        var nested = Directory.CreateDirectory(Path.Combine(fixture.Backups, "nested")).FullName;
        File.WriteAllText(Path.Combine(nested, "ignored.log"), Log(14400, 18000));
        var before = Snapshot(fixture.Root);

        Equal(new(5400, 2, 1, 1), fixture.Scan(), "Distinct sessions, merged seconds and foreign file count.");
        Equal(new(3600, 2, 1, 1), fixture.Scan(Epoch.AddHours(1)), "WPF cutoff excludes live overlap.");
        Require(before.SequenceEqual(Snapshot(fixture.Root)), "Scanning must not write inputs or create files.");

        fixture.Write("duplicate.log", Log(0, 3600));
        Equal(new(5400, 2, 2, 1), fixture.Scan(), "Conflicting duplicate exits are conservatively incomplete.");

        using var fractional = new Fixture();
        fractional.Write("a.log", Log(0, 0.25));
        fractional.Write("b.log", Log(0.25, 0.5));
        Equal(new(1, 2, 2, 0), fractional.Scan(), "Touching intervals merge before away-from-zero rounding.");
        using var tiny = new Fixture();
        tiny.Write("tiny.log", Log(0, 0.1));
        Code("empty", () => tiny.Scan());
    }

    private static void IdentityEvidence()
    {
        string[] invalid =
        [
            $"nickname=\"{Handle}\"", // nickname alone is other-player mention evidence.
            $"Player[{Handle}] joined channel 'ship : {Handle}'",
            $"PLAYER_ONLINE player={Handle}",
            $"nickname=\"{Handle}\" other=true playerGEID=1",
            $"othernickname=\"{Handle}\" playerGEID=1",
            $"nickname=\"{Handle}\" playerGEIDOther=1",
            Identity("synthetic-other"),
            Identity(Handle) + " " + Identity("synthetic-other"),
            Identity("synthetic-other") + " " + Identity(Handle),
            Identity(Handle, "100") + " " + Identity(Handle, "200")
        ];
        foreach (var evidence in invalid)
        {
            using var fixture = new Fixture();
            fixture.Write("case.log", Line(0, evidence) + Line(60, "last"));
            Code("empty", () => fixture.Scan());
        }

        using var accepted = new Fixture();
        accepted.Write("canonical.log",
            Line(0, "start") +
            Line(1, "NICKNAME=\"SYNTHETIC-PILOT\" playerGEID = \"123\"") +
            Line(2, Identity(Handle, "123")) +
            Line(3, "nickname=\"synthetic-other\" ship owner mention only") +
            Line(60, "<SystemQuit> CSystem::Quit"));
        Equal(new(60, 1, 0, 0),
            GameplayHistoryScanner.Scan(accepted.GameLog, "  SYNTHETIC-PILOT  ", Epoch.AddDays(1)),
            "Case-insensitive verified nickname; unrelated mentions do not change owner.");

        using var optionalId = new Fixture();
        optionalId.Write("optional.log", Line(0, $"nickname=\"{Handle}\" playerGEID") + Line(60, "last"));
        Equal(new(60, 1, 1, 0), optionalId.Scan(), "Canonical rule permits an omitted numeric GEID.");

        using var untimed = new Fixture();
        untimed.Write("untimed.log", Line(0, "start") + Identity(Handle) + "\n" + Line(60, "last"));
        Code("empty", () => untimed.Scan());
    }

    private static void CutoffAndExit()
    {
        using var fixture = new Fixture();
        fixture.Write("case.log", Log(0, 120, clean: true));
        Equal(new(60, 1, 1, 0), fixture.Scan(Epoch.AddSeconds(60)),
            "Clip crossing session; a later quit cannot complete its historical portion.");
        Equal(new(120, 1, 0, 0), fixture.Scan(Epoch.AddSeconds(120)), "Cutoff is inclusive.");
        Code("empty", () => fixture.Scan(Epoch));
        Code("empty", () => fixture.Scan(Epoch.AddSeconds(-1)));

        fixture.Write("case.log", Line(0, "start") + Line(90, Identity(Handle)) + Line(120, "last"));
        Code("empty", () => fixture.Scan(Epoch.AddSeconds(60)));
        fixture.Write("case.log", Log(0, 60) + Line(120, Identity("synthetic-other")));
        Code("empty", () => fixture.Scan(Epoch.AddSeconds(60)));

        foreach (var marker in new[] { "<SystemQuit>", "CSystem::Quit", "<SystemQuit> unrelated\nCSystem::Quit" })
        {
            fixture.Write("case.log", Line(0, Identity(Handle)) + Line(60, marker));
            Equal(new(60, 1, 1, 0), fixture.Scan(), "Both clean-exit tokens must occur on the same timed line.");
        }
        fixture.Write("case.log", Line(0, Identity(Handle)) + "<SystemQuit> CSystem::Quit\n" + Line(60, "last"));
        Equal(new(60, 1, 1, 0), fixture.Scan(), "Untimed quit cannot prove a clean historical exit.");
    }

    private static void InvalidSessions()
    {
        using var fixture = new Fixture();
        string[] invalid =
        [
            Log(60, 0),
            Log(0, 0),
            Line(0, Identity(Handle)),
            Log(0, 86400.001),
            Line(0, Identity(Handle)) + Line(50, "middle") + Line(40, "backward") + Line(60, "last"),
            Line(0, Identity(Handle)) + "<2020-02-30T00:00:00Z> bad\n" + Line(60, "last"),
            Line(0, Identity(Handle)) + "<2020-01-01T25:00:00Z> bad\n" + Line(60, "last"),
            Line(0, Identity(Handle)) + "<2020-01-01T00:00:30Z bad\n" + Line(60, "last"),
            Line(0, Identity(Handle)) + "<12:30:00> time without date\n" + Line(60, "last"),
            Line(0, Identity(Handle)) + $"<{DateTimeOffset.UtcNow.AddDays(1):O}> future\n"
        ];
        foreach (var log in invalid)
        {
            fixture.Write("case.log", log);
            Code("empty", () => fixture.Scan(Epoch.AddSeconds(30)));
        }
        fixture.Write("case.log", Log(0, 86400, clean: true));
        Equal(new(86400, 1, 0, 0), fixture.Scan(), "Exactly 24 hours remains valid.");
        fixture.Write("case.log", Line(0, Identity(Handle)) + Line(0, "same timestamp") +
            "<ordinary-tag> continuation\n" + Line(60, "last"));
        Equal(new(60, 1, 1, 0), fixture.Scan(), "Equal timestamps and non-timestamp tags are allowed.");
        fixture.Write("case.log", "<2020-01-01T00:00:00> " + Identity(Handle) + "\n" +
            "<2020-01-01T01:01:00+01:00> last\n");
        Equal(new(60, 1, 1, 0), fixture.Scan(), "Timezone-less timestamps assume UTC; offsets normalize.");
    }

    private static void StreamingBoundaries()
    {
        using var fixture = new Fixture();
        foreach (var newline in new[] { "\n", "\r\n", "\r" })
        {
            var log = Log(0, 60).TrimEnd('\n').Replace("\n", newline, StringComparison.Ordinal);
            File.WriteAllText(Path.Combine(fixture.Backups, "case.log"), log, new UTF8Encoding(true));
            Equal(new(60, 1, 1, 0), fixture.Scan(), "BOM, newline variants and unterminated final lines.");
        }
        fixture.Write("case.log", Line(0, Identity(Handle)) + new string('x', 65536) + "\n" + Line(60, "last"));
        Equal(new(60, 1, 1, 0), fixture.Scan(), "Exactly 64 KiB line accepted across read blocks.");
        fixture.Write("case.log", Line(0, Identity(Handle)) + new string('x', 65537) + "\n" + Line(60, "last"));
        Code("limit", () => fixture.Scan());
        fixture.Write("case.log", Line(0, Identity(Handle)) + new string('x', 65537));
        Code("limit", () => fixture.Scan());
        fixture.Write("case.log", Line(0, Identity(Handle)) + new string('\u00e9', 32769) + "\n" + Line(60, "last"));
        Code("limit", () => fixture.Scan()); // Bound is UTF-8 bytes, not character count.
        var prefix = Line(0, Identity(Handle));
        fixture.Write("case.log", prefix + new string('x', 16383 - Encoding.UTF8.GetByteCount(prefix)) +
            "\r\n" + Line(60, "last"));
        Equal(new(60, 1, 1, 0), fixture.Scan(), "Block crossings preserve CRLF handling.");
        fixture.Write("case.log", prefix + new string('\u00e9', 32768) + "\n" + Line(60, "last"));
        Equal(new(60, 1, 1, 0), fixture.Scan(), "UTF-8 characters spanning read blocks remain intact.");

        File.WriteAllBytes(Path.Combine(fixture.Backups, "case.log"), [0xFF, 0xFE, 0xFF]);
        Code("unavailable", () => fixture.Scan());
        fixture.Write("good.log", Log(0, 60));
        Equal(new(60, 1, 1, 1), fixture.Scan(), "Undecodable files are skipped without concealing valid history.");
    }

    private static void PathsAndFailures()
    {
        using var fixture = new Fixture();
        foreach (var path in new[]
        {
            "", " ", "Game.log", "relative/Game.log", "\0Game.log",
            @"\\synthetic-host\share\Game.log", "//synthetic-host/share/Game.log",
            @"\\?\C:\synthetic\Game.log", @"\\.\C:\synthetic\Game.log",
            Path.Combine(fixture.Root, "wrong.log"),
            Path.Combine(fixture.Root, "..", Path.GetFileName(fixture.Root), "Game.log")
        })
            Code("path", () => GameplayHistoryScanner.Scan(path, Handle, Epoch.AddDays(1)));
        if (OperatingSystem.IsWindows())
            Code("path", () => GameplayHistoryScanner.Scan(fixture.GameLog + ":other", Handle, Epoch.AddDays(1)));
        foreach (var handle in new[] { "", " ", "bad\nhandle", new string('x', 257) })
            Code("empty", () => GameplayHistoryScanner.Scan(fixture.GameLog, handle, Epoch.AddDays(1)));
        Code("empty", () => fixture.Scan());
        Directory.Delete(fixture.Backups); // Exact empty directory created by this fixture.
        Code("empty", () => fixture.Scan());
        Directory.CreateDirectory(fixture.Backups);
        fixture.Write("locked.log", Log(0, 60));
        using (var locked = new FileStream(Path.Combine(fixture.Backups, "locked.log"),
                   FileMode.Open, FileAccess.ReadWrite, FileShare.None))
        {
            Code("unavailable", () => fixture.Scan());
            fixture.Write("good.log", Log(120, 180));
            Equal(new(60, 1, 1, 1), fixture.Scan(), "An unreadable candidate increments skipped files.");
        }
        File.Delete(fixture.GameLog); // Exact synthetic anchor only.
        Code("unavailable", () => fixture.Scan());
        Require(!File.Exists(fixture.GameLog), "Missing Game.log must never be recreated.");
    }

    private static void ResourceLimits()
    {
        using (var fixture = new Fixture())
        {
            fixture.Write("valid.log", Log(0, 60));
            for (var i = 1; i < 512; i++) fixture.Write($"{i:D4}.log", "");
            Equal(new(60, 1, 1, 511), fixture.Scan(), "Exactly 512 candidates remains valid.");
            fixture.Write("excess.log", "");
            Code("limit", () => fixture.Scan());
        }
        using (var fixture = new Fixture())
        {
            using (var sparse = File.Create(Path.Combine(fixture.Backups, "oversized.log")))
                sparse.SetLength(64L * 1024 * 1024 + 1);
            Code("limit", () => fixture.Scan());
        }
        using (var fixture = new Fixture())
        {
            for (var i = 0; i < 5; i++)
                using (var sparse = File.Create(Path.Combine(fixture.Backups, $"{i}.log")))
                    sparse.SetLength(64L * 1024 * 1024);
            Code("limit", () => fixture.Scan()); // Metadata preflight; never reads 320 MiB.
        }
    }

    private static void CancellationAndDeadline()
    {
        using var fixture = new Fixture();
        fixture.Write("valid.log", Log(0, 60));
        using var cancelled = new CancellationTokenSource();
        cancelled.Cancel();
        Cancelled(cancelled.Token, () => GameplayHistoryScanner.Scan(fixture.GameLog, Handle,
            Epoch.AddDays(1), cancelled.Token));
        var baselineClock = new TestClock();
        Equal(new(60, 1, 1, 0), WithClock(fixture, baselineClock), "Clock seam exercises the full scanner.");

        // Many short lines ensure expiration happens during streaming, not just at entry.
        fixture.Write("valid.log", Line(0, Identity(Handle)) +
            string.Concat(Enumerable.Repeat("synthetic continuation\n", 1000)) + Line(60, "last"));
        var deadline = new TestClock { TriggerAt = baselineClock.Calls + 10 };
        Code("limit", () => WithClock(fixture, deadline));
        using var active = new CancellationTokenSource();
        var duringRead = new TestClock { TriggerAt = baselineClock.Calls + 10, Cancel = active };
        Cancelled(active.Token, () => WithClock(fixture, duringRead, active.Token));
        Require(active.IsCancellationRequested, "Caller cancellation was delivered during the scan.");
    }

    private static void ReparsePoints()
    {
        using var fixture = new Fixture();
        fixture.Write("good.log", Log(0, 60));
        var target = Path.Combine(fixture.Root, "target");
        Directory.CreateDirectory(target);
        File.WriteAllText(Path.Combine(target, "Game.log"), "");
        Directory.CreateDirectory(Path.Combine(target, "logbackups"));
        File.WriteAllText(Path.Combine(target, "logbackups", "good.log"), Log(0, 60));
        var alias = Path.Combine(fixture.Root, "alias");
        CreateJunction(alias, target);
        try
        {
            Code("path", () => GameplayHistoryScanner.Scan(Path.Combine(alias, "Game.log"), Handle, Epoch.AddDays(1)));
            Directory.CreateDirectory(Path.Combine(target, "child"));
            File.WriteAllText(Path.Combine(target, "child", "Game.log"), "");
            Code("path", () => GameplayHistoryScanner.Scan(Path.Combine(alias, "child", "Game.log"), Handle, Epoch.AddDays(1)));
        }
        finally { Directory.Delete(alias); } // Remove the link itself, never the target.

        File.Delete(Path.Combine(fixture.Backups, "good.log"));
        Directory.Delete(fixture.Backups);
        CreateJunction(fixture.Backups, Path.Combine(target, "logbackups"));
        try { Code("path", () => fixture.Scan()); }
        finally { Directory.Delete(fixture.Backups); }
        Directory.CreateDirectory(fixture.Backups);
        var linkedFile = Path.Combine(fixture.Backups, "linked.log");
        try { File.CreateSymbolicLink(linkedFile, Path.Combine(target, "logbackups", "good.log")); }
        catch (Exception e) when (e is UnauthorizedAccessException ||
                                 e is IOException && (e.HResult & 0xFFFF) == 1314)
        {
            Console.WriteLine("SKIP gameplay history file symlink subcases: OS privilege unavailable; directory junction checks passed.");
            return;
        }
        try { Code("path", () => fixture.Scan()); }
        finally { File.Delete(linkedFile); }
        File.Delete(fixture.GameLog);
        File.CreateSymbolicLink(fixture.GameLog, Path.Combine(target, "Game.log"));
        try { Code("path", () => fixture.Scan()); }
        finally { File.Delete(fixture.GameLog); }
    }

    // NTFS junctions need no symbolic-link privilege. All targets are fixture-owned
    // directories and links are removed nonrecursively before fixture cleanup.
    private static void CreateJunction(string link, string target)
    {
        Directory.CreateDirectory(link);
        using var handle = OpenJunction(link, 0x40000000, 0, IntPtr.Zero, 3, 0x02200000, IntPtr.Zero);
        Require(!handle.IsInvalid, "Could not open synthetic junction.");
        var substitute = Encoding.Unicode.GetBytes(@"\??\" + Path.GetFullPath(target));
        var display = Encoding.Unicode.GetBytes(Path.GetFullPath(target));
        using var buffer = new MemoryStream();
        using (var writer = new BinaryWriter(buffer, Encoding.Unicode, leaveOpen: true))
        {
            writer.Write(0xA0000003u); // IO_REPARSE_TAG_MOUNT_POINT
            writer.Write((ushort)(8 + substitute.Length + display.Length + 4));
            writer.Write((ushort)0);
            writer.Write((ushort)0);
            writer.Write((ushort)substitute.Length);
            writer.Write((ushort)(substitute.Length + 2));
            writer.Write((ushort)display.Length);
            writer.Write(substitute);
            writer.Write((ushort)0);
            writer.Write(display);
            writer.Write((ushort)0);
        }
        var bytes = buffer.ToArray();
        Require(SetJunction(handle, 0x000900A4, bytes, bytes.Length, IntPtr.Zero, 0, out _, IntPtr.Zero),
            "Could not create synthetic junction.");
    }

    [DllImport("kernel32.dll", EntryPoint = "CreateFileW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern SafeFileHandle OpenJunction(string name, uint access, uint share,
        IntPtr security, uint disposition, uint flags, IntPtr template);
    [DllImport("kernel32.dll", EntryPoint = "DeviceIoControl", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetJunction(SafeFileHandle handle, uint code, byte[] input, int inputSize,
        IntPtr output, int outputSize, out int returned, IntPtr overlapped);

    private sealed class TestClock : TimeProvider
    {
        internal int Calls;
        internal int TriggerAt = int.MaxValue;
        internal CancellationTokenSource? Cancel;
        public override long TimestampFrequency => 1;
        public override DateTimeOffset GetUtcNow() => Epoch.AddYears(1);
        public override long GetTimestamp()
        {
            if (++Calls < TriggerAt) return 0;
            if (Cancel is null) return 15;
            Cancel.Cancel();
            return 0;
        }
    }

    private static GameplayHistoryPreview WithClock(Fixture fixture, TimeProvider clock,
        CancellationToken cancellation = default)
    {
        // Private seam avoids exposing configuration or sharing a mutable global test clock.
        var method = typeof(GameplayHistoryScanner).GetMethod("ScanCore", BindingFlags.Static | BindingFlags.NonPublic)!;
        try { return (GameplayHistoryPreview)method.Invoke(null,
            [fixture.GameLog, Handle, Epoch.AddDays(30), cancellation, clock])!; }
        catch (TargetInvocationException e) when (e.InnerException is not null)
        { ExceptionDispatchInfo.Capture(e.InnerException).Throw(); throw; }
    }

    private sealed class Fixture : IDisposable
    {
        internal string Root { get; } = Path.Combine(Path.GetTempPath(), "starbridge-history-synthetic-" + Guid.NewGuid().ToString("N"));
        private readonly string _version;
        internal string GameLog => Path.Combine(Root, _version, "Game.log");
        internal string Backups => Path.Combine(Root, _version, "logbackups");
        internal Fixture(string version = "LIVE")
        {
            _version = version;
            Directory.CreateDirectory(Backups);
            File.WriteAllText(GameLog, "");
        }
        internal void Write(string name, string content) => File.WriteAllText(Path.Combine(Backups, name), content, new UTF8Encoding(false));
        internal GameplayHistoryPreview Scan(DateTimeOffset? cutoff = null) =>
            GameplayHistoryScanner.Scan(GameLog, Handle, cutoff ?? Epoch.AddDays(30));
        public void Dispose()
        {
            // Only this fixture's generated absolute child of the OS temp directory.
            var root = Path.GetFullPath(Root);
            var temp = Path.TrimEndingDirectorySeparator(Path.GetFullPath(Path.GetTempPath()));
            if (Path.GetDirectoryName(root) != temp ||
                !Path.GetFileName(root).StartsWith("starbridge-history-synthetic-", StringComparison.Ordinal))
                throw new InvalidOperationException("Unexpected fixture cleanup target.");
            if (Directory.Exists(root)) Directory.Delete(root, recursive: true);
        }
    }

    private static string Identity(string player, string geid = "123") => $"nickname=\"{player}\" playerGEID={geid}";
    private static string Line(double second, string body) => $"<{Epoch.AddSeconds(second):O}> {body}\n";
    private static string Log(double start, double end, bool clean = false, string player = Handle) =>
        Line(start, Identity(player)) + Line(end, clean ? "<SystemQuit> CSystem::Quit" : "last");
    private static string[] Snapshot(string root) => Directory.GetFiles(root, "*", SearchOption.AllDirectories)
        .OrderBy(path => path, StringComparer.Ordinal)
        .Select(path => path + ":" + File.GetLastWriteTimeUtc(path).Ticks + ":" +
            Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path)))).ToArray();
    private static void Code(string suffix, Action action)
    {
        try { action(); }
        catch (GameplayTimeException e)
        {
            Require(e.Code == "gameplay.history_" + suffix && e.Message == e.Code && e.InnerException is null,
                $"Expected sanitized gameplay.history_{suffix}; got {e.Code}.");
            return;
        }
        throw new InvalidOperationException("Expected gameplay.history_" + suffix);
    }
    private static void Cancelled(CancellationToken token, Action action)
    {
        try { action(); }
        catch (OperationCanceledException e)
        { Require(e.CancellationToken == token, "Preserve caller cancellation token."); return; }
        throw new InvalidOperationException("Expected caller cancellation.");
    }
    private static void Equal(GameplayHistoryPreview expected, GameplayHistoryPreview actual, string message) =>
        Require(expected == actual, $"{message} Expected {expected}; got {actual}.");
    private static void Require(bool condition, string message)
    { if (!condition) throw new InvalidOperationException(message); }
}
