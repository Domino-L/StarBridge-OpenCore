using System.Globalization;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using Microsoft.Win32.SafeHandles;

namespace StarBridge.HostRuntime.Presence;

public record GameplayHistoryPreview(long Seconds, int Sessions, int IncompleteSessions, int SkippedFiles);

/// <summary>
/// Read-only preview of top-level logbackups/*.log beside a local Game.log.
/// Like the WPF importer, each file supplies one first/last timestamp interval,
/// clipped at the recording cutoff; distinct intervals count as sessions while
/// their union supplies seconds (rounded away from zero).
/// </summary>
/// <remarks>
/// UTF-8 (optional BOM), CR/LF/CRLF and a final unterminated line are supported.
/// Missing/foreign/ambiguous identities and invalid sessions are skipped.
/// Duplicate intervals are complete only if every copy reports a clean exit.
/// Bounds fail the whole preview rather than returning a silently partial total.
/// Windows directory handles pin ancestors against rename/replacement during the
/// scan; files are opened with OPEN_REPARSE_POINT and verified by handle.
/// Only each file's initial length is read; concurrent in-place writes are not an
/// atomic snapshot. Read handles briefly prevent rename/deletion of scanned files.
/// Cancellation throws OperationCanceledException. The time budget is cooperative:
/// it cannot interrupt an OS filesystem call already in progress.
/// GameplayTimeException codes: gameplay.history_path (unsafe input),
/// gameplay.history_empty (no attributable duration), gameplay.history_unavailable
/// (filesystem/encoding unavailable), gameplay.history_limit (resource/deadline bound).
/// </remarks>
public static class GameplayHistoryScanner
{
    private const int MaximumFiles = 512;
    private const int MaximumLineBytes = 64 * 1024;
    private const long MaximumFileBytes = 64L * 1024 * 1024;
    private const long MaximumTotalBytes = 256L * 1024 * 1024;
    private static readonly TimeSpan TimeBudget = TimeSpan.FromSeconds(15);
    private static readonly TimeSpan MaximumSessionLength = TimeSpan.FromHours(24);
    private static readonly UTF8Encoding Utf8 = new(false, true);

    // Canonical PlayerOnline rule from RegexLogEventParser, with token boundaries.
    // A nickname alone (chat, party, ship owner, etc.) is not local identity evidence.
    private static readonly Regex Identity = new(
        """\bnickname="(?<player>[^"]+)"\s+playerGEID\b\s*=?\s*"?(?<playerId>\d+)?""",
        RegexOptions.IgnoreCase | RegexOptions.CultureInvariant | RegexOptions.NonBacktracking,
        TimeSpan.FromMilliseconds(100));
    private static readonly string[] TimestampFormats =
    [
        "yyyy-MM-dd'T'HH:mm:ssK", "yyyy-MM-dd'T'HH:mm:ss.FFFFFFFK"
    ];

    public static GameplayHistoryPreview Scan(string gameLogPath, string verifiedHandle,
        DateTimeOffset cutoff, CancellationToken cancellation = default) =>
        ScanCore(gameLogPath, verifiedHandle, cutoff, cancellation, TimeProvider.System);

    // Instance clock seam keeps deadline/cancellation tests deterministic without global state.
    private static GameplayHistoryPreview ScanCore(string gameLogPath, string verifiedHandle,
        DateTimeOffset cutoff, CancellationToken cancellation, TimeProvider clock)
    {
        var budget = new ScanBudget(clock, cancellation);
        budget.Check();
        if (!OperatingSystem.IsWindows()) throw Error("unavailable");
        var path = ValidatePath(gameLogPath);
        if (string.IsNullOrWhiteSpace(verifiedHandle) || verifiedHandle.Length > 256 ||
            verifiedHandle.Any(char.IsControl))
            throw Error("empty");
        var handle = verifiedHandle.Trim();
        var now = clock.GetUtcNow();
        var intervals = new Dictionary<(DateTimeOffset Start, DateTimeOffset End), Interval>();
        var skipped = 0;
        var unreadable = 0;

        try
        {
            using var liveGuard = PinnedDirectories.Open(Path.GetDirectoryName(path)!, budget);
            CheckTree(path, directory: false, budget);
            using (OpenChecked(path, directory: false, readContent: false)) { }
            var backups = Path.Combine(Path.GetDirectoryName(path)!, "logbackups");
            try { CheckTree(backups, directory: true, budget); }
            catch (Exception e) when (e is FileNotFoundException or DirectoryNotFoundException)
            { throw Error("empty"); }
            using var backupGuard = PinnedDirectories.Open(backups, budget);

            var files = new List<(string Path, long Length)>();
            long totalBytes = 0;
            var options = new EnumerationOptions
            {
                RecurseSubdirectories = false, IgnoreInaccessible = false,
                AttributesToSkip = 0, MatchType = MatchType.Simple,
                MatchCasing = MatchCasing.CaseInsensitive, ReturnSpecialDirectories = false
            };
            foreach (var file in Directory.EnumerateFiles(backups, "*.log", options))
            {
                budget.Check();
                if (files.Count == MaximumFiles) throw Error("limit");
                CheckTree(file, directory: false, budget);
                var length = new FileInfo(file).Length;
                if (length > MaximumFileBytes || length > MaximumTotalBytes - totalBytes)
                    throw Error("limit");
                totalBytes += length;
                files.Add((file, length));
            }

            var block = new byte[16 * 1024];
            var line = new byte[MaximumLineBytes];
            foreach (var file in files)
            {
                budget.Check();
                Interval? interval;
                try
                {
                    interval = ReadInterval(file.Path, file.Length, handle, cutoff, now, budget, block, line);
                }
                catch (Exception e) when (ReadError(e))
                {
                    unreadable++;
                    skipped++;
                    continue;
                }
                if (interval is null) { skipped++; continue; }
                var key = (interval.Start, interval.End);
                if (intervals.TryGetValue(key, out var previous))
                    interval = interval with { CleanExit = previous.CleanExit && interval.CleanExit };
                intervals[key] = interval;
            }

            budget.Check();
            if (intervals.Count == 0)
                throw Error(files.Count > 0 && unreadable == files.Count ? "unavailable" : "empty");

            var ordered = intervals.Values.OrderBy(v => v.Start).ThenBy(v => v.End).ToArray();
            var start = ordered[0].Start;
            var end = ordered[0].End;
            long seconds = 0;
            foreach (var interval in ordered.Skip(1))
            {
                budget.Check();
                if (interval.Start > end)
                {
                    seconds += Seconds(start, end);
                    start = interval.Start;
                    end = interval.End;
                }
                else if (interval.End > end) end = interval.End;
            }
            seconds += Seconds(start, end);
            budget.Check();
            if (seconds <= 0) throw Error("empty");
            return new(seconds, ordered.Length, ordered.Count(v => !v.CleanExit), skipped);
        }
        catch (RegexMatchTimeoutException) { throw Error("limit"); }
        catch (Exception e) when (ReadError(e)) { throw Error("unavailable"); }
    }

    private static Interval? ReadInterval(string path, long expectedLength, string handle,
        DateTimeOffset cutoff, DateTimeOffset now, ScanBudget budget, byte[] block, byte[] line)
    {
        CheckTree(path, directory: false, budget);
        using var fileHandle = OpenChecked(path, directory: false, readContent: true);
        using var stream = new FileStream(fileHandle, FileAccess.Read, block.Length);
        CheckTree(path, directory: false, budget);
        var length = stream.Length;
        if (length > MaximumFileBytes) throw Error("limit");
        if (length != expectedLength) throw new IOException();

        var state = new Session(handle, cutoff, now);
        var used = 0;
        var firstLine = true;
        var afterCr = false;
        var remaining = length;
        while (remaining > 0)
        {
            budget.Check();
            var read = stream.Read(block, 0, (int)Math.Min(remaining, block.Length));
            if (read == 0) throw new IOException(); // Truncated during the snapshot.
            remaining -= read;
            for (var i = 0; i < read; i++)
            {
                var value = block[i];
                if (afterCr && value == (byte)'\n') { afterCr = false; continue; }
                afterCr = false;
                if (value is (byte)'\r' or (byte)'\n')
                {
                    budget.Check();
                    ConsumeLine(state, line.AsSpan(0, used), firstLine);
                    firstLine = false;
                    used = 0;
                    afterCr = value == (byte)'\r';
                }
                else
                {
                    if (used == line.Length) throw Error("limit");
                    line[used++] = value;
                }
            }
        }
        if (used > 0)
        {
            budget.Check();
            ConsumeLine(state, line.AsSpan(0, used), firstLine);
        }
        budget.Check();
        // Appends after the initial length are intentionally not followed.
        if (stream.Length < length) throw new IOException();
        CheckTree(path, directory: false, budget);
        return state.Finish();
    }

    private static void ConsumeLine(Session state, ReadOnlySpan<byte> bytes, bool firstLine)
    {
        if (firstLine && bytes.StartsWith("\uFEFF"u8)) bytes = bytes[3..];
        state.Observe(Utf8.GetString(bytes));
    }

    private sealed class Session(string handle, DateTimeOffset cutoff, DateTimeOffset now)
    {
        private DateTimeOffset? _first;
        private DateTimeOffset? _last;
        private string? _identity;
        private string? _geid;
        private bool _matchedBeforeCutoff;
        private bool _invalid;
        private bool _cleanExit;

        internal void Observe(string line)
        {
            // Read the entire file even after invalid evidence: byte/line limits still apply.
            var stamp = ParseTimestamp(line, out var malformed);
            if (malformed) _invalid = true;
            if (stamp is { } timestamp)
            {
                if (timestamp > now || (_last is { } last && timestamp < last)) _invalid = true;
                _first ??= timestamp;
                _last = timestamp;
            }
            foreach (Match match in Identity.Matches(line))
            {
                var player = match.Groups["player"].Value;
                var geid = match.Groups["playerId"].Value;
                if ((_identity is not null && !player.Equals(_identity, StringComparison.OrdinalIgnoreCase)) ||
                    (_geid is not null && geid.Length > 0 && geid != _geid))
                    _invalid = true;
                _identity ??= player;
                if (geid.Length > 0) _geid ??= geid;
                if (player.Equals(handle, StringComparison.OrdinalIgnoreCase) &&
                    stamp is { } observed && observed <= cutoff)
                    _matchedBeforeCutoff = true;
            }
            if (stamp is { } quitAt && quitAt <= cutoff &&
                line.Contains("<SystemQuit>", StringComparison.OrdinalIgnoreCase) &&
                line.Contains("CSystem::Quit", StringComparison.OrdinalIgnoreCase))
                _cleanExit = true;
        }

        internal Interval? Finish()
        {
            if (_invalid || !_matchedBeforeCutoff || _first is not { } first || _last is not { } last ||
                last <= first || last - first > MaximumSessionLength)
                return null;
            var end = last > cutoff ? cutoff : last;
            return end > first ? new(first, end, _cleanExit) : null;
        }
    }

    private static DateTimeOffset? ParseTimestamp(string line, out bool malformed)
    {
        malformed = false;
        if (line.Length < 2 || line[0] != '<') return null;
        var close = line.IndexOf('>');
        // Non-timestamp tags/continuations are ordinary log text, not timestamps.
        // Any digit-leading timestamp-like prefix must be a full invariant ISO date.
        if (!char.IsAsciiDigit(line[1])) return null;
        if (close is < 0 or > 40 || !DateTimeOffset.TryParseExact(
                line.AsSpan(1, close - 1), TimestampFormats, CultureInfo.InvariantCulture,
                DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out var timestamp))
        { malformed = true; return null; }
        return timestamp;
    }

    private static string ValidatePath(string path)
    {
        if (string.IsNullOrWhiteSpace(path) || path.Length > 4096 || path.Any(char.IsControl) ||
            path.StartsWith(@"\\", StringComparison.Ordinal) || path.StartsWith("//", StringComparison.Ordinal))
            throw Error("path");
        try
        {
            if (!Path.IsPathFullyQualified(path)) throw Error("path");
            var root = Path.GetPathRoot(path)!;
            if (OperatingSystem.IsWindows() &&
                (root.Length != 3 || !char.IsAsciiLetter(root[0]) || root[1] != ':' ||
                 path.AsSpan(2).Contains(':')))
                throw Error("path");
            foreach (var part in path[root.Length..].Split(
                         [Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar], StringSplitOptions.None))
            {
                if (part.Length == 0 || part is "." or ".." ||
                    part.EndsWith(' ') || part.EndsWith('.') ||
                    part.IndexOfAny(Path.GetInvalidFileNameChars()) >= 0)
                    throw Error("path");
            }
            var full = Path.GetFullPath(path);
            if (!Path.GetFileName(full).Equals("Game.log", StringComparison.OrdinalIgnoreCase) ||
                !string.Equals(Path.GetFileName(Path.GetDirectoryName(full)), "LIVE", StringComparison.OrdinalIgnoreCase))
                throw Error("path");
            if (OperatingSystem.IsWindows() && new DriveInfo(root).DriveType == DriveType.Network)
                throw Error("path");
            return full;
        }
        catch (Exception e) when (e is ArgumentException or NotSupportedException or PathTooLongException)
        { throw Error("path"); }
        catch (Exception e) when (ReadError(e)) { throw Error("unavailable"); }
    }

    private static void CheckTree(string path, bool directory, ScanBudget budget)
    {
        // Check from the volume root down, before traversing each next component.
        var parents = new Stack<string>();
        for (var parent = Path.GetDirectoryName(path); !string.IsNullOrEmpty(parent);
             parent = Path.GetDirectoryName(parent))
            parents.Push(parent);
        while (parents.TryPop(out var parent)) CheckNode(parent, directory: true, budget);
        CheckNode(path, directory, budget);
    }

    private static void CheckNode(string path, bool directory, ScanBudget budget)
    {
        budget.Check();
        var attributes = File.GetAttributes(path);
        if ((attributes & FileAttributes.ReparsePoint) != 0 ||
            ((attributes & FileAttributes.Directory) != 0) != directory)
            throw Error("path");
    }

    private sealed class PinnedDirectories : IDisposable
    {
        private readonly List<SafeFileHandle> _handles = [];
        internal static PinnedDirectories Open(string path, ScanBudget budget)
        {
            var guard = new PinnedDirectories();
            try
            {
                var parents = new Stack<string>();
                for (string? current = path; !string.IsNullOrEmpty(current); current = Path.GetDirectoryName(current))
                    parents.Push(current);
                while (parents.TryPop(out var parent))
                {
                    budget.Check();
                    guard._handles.Add(OpenChecked(parent, directory: true, readContent: false));
                }
                return guard;
            }
            catch { guard.Dispose(); throw; }
        }
        public void Dispose()
        {
            for (var i = _handles.Count - 1; i >= 0; i--) _handles[i].Dispose();
        }
    }

    private static SafeFileHandle OpenChecked(string path, bool directory, bool readContent)
    {
        // OPEN_EXISTING only. No DELETE sharing: checked objects cannot be replaced
        // while a descendant is opened. ReadWrite sharing still permits game writes.
        const uint openReparsePoint = 0x00200000;
        const uint backupSemantics = 0x02000000;
        const uint sequentialScan = 0x08000000;
        var handle = CreateFile(path, readContent ? 0x80000000u : 0u,
            directory ? FileShare.Read : FileShare.ReadWrite,
            IntPtr.Zero, 3, openReparsePoint | (directory ? backupSemantics : sequentialScan), IntPtr.Zero);
        try
        {
            if (handle.IsInvalid || !GetFileInformationByHandle(handle, out var info))
                throw new IOException();
            if ((info.Attributes & FileAttributes.ReparsePoint) != 0 ||
                ((info.Attributes & FileAttributes.Directory) != 0) != directory)
                throw Error("path");
            return handle;
        }
        catch { handle.Dispose(); throw; }
    }

    [DllImport("kernel32.dll", EntryPoint = "CreateFileW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern SafeFileHandle CreateFile(string name, uint access, FileShare share,
        IntPtr security, uint disposition, uint flags, IntPtr template);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetFileInformationByHandle(SafeFileHandle handle, out FileInformation information);

    [StructLayout(LayoutKind.Sequential)]
    private struct FileInformation
    {
        internal FileAttributes Attributes;
        internal System.Runtime.InteropServices.ComTypes.FILETIME Creation, Access, Write;
        internal uint Volume, SizeHigh, SizeLow, Links, IndexHigh, IndexLow;
    }

    private sealed class ScanBudget(TimeProvider clock, CancellationToken cancellation)
    {
        private readonly long _started = clock.GetTimestamp();
        internal void Check()
        {
            cancellation.ThrowIfCancellationRequested();
            if (clock.GetElapsedTime(_started) >= TimeBudget) throw Error("limit");
        }
    }

    private sealed record Interval(DateTimeOffset Start, DateTimeOffset End, bool CleanExit);
    private static long Seconds(DateTimeOffset start, DateTimeOffset end) =>
        (long)Math.Round((end - start).TotalSeconds, MidpointRounding.AwayFromZero);
    private static GameplayTimeException Error(string suffix) => new("gameplay.history_" + suffix);
    private static bool ReadError(Exception error) => error is IOException or UnauthorizedAccessException or
        System.Security.SecurityException or DecoderFallbackException;
}
