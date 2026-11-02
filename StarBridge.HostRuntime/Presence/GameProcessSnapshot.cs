using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace StarBridge.HostRuntime.Presence;

internal readonly record struct GameProcessEntry(int Pid, string Name);
internal sealed record GameProcessEvidence(int Pid, string? Executable, DateTimeOffset? StartedAt,
    bool Uncertain = false);
internal interface IGameProcessSnapshot : IDisposable
{
    IEnumerable<GameProcessEntry> Entries { get; }
}
internal interface IGameProcessHandle : IDisposable
{
    // Null means the process is confirmed to have exited, never access denied.
    GameProcessEvidence? Read();
}
internal interface IGameProcessSource
{
    IGameProcessSnapshot Capture();
    IGameProcessHandle Open(GameProcessEntry entry);
}

// Shared observations contain only process evidence, never account identity or log contents.
internal sealed class GameProcessSnapshotCache(IGameProcessSource source, TimeProvider? time = null)
{
    private static readonly HashSet<string> Names = new(StringComparer.OrdinalIgnoreCase)
    {
        "StarCitizen", "StarCitizen_LIVE", "StarCitizen_PTUR", "StarCitizen_EPTU",
        "StarCitizen_HOTFIX", "StarCitizen_TECH-PREVIEW"
    };
    private readonly object _gate = new();
    private static readonly TimeSpan OpenRetry = TimeSpan.FromSeconds(5);
    // Longer than the slowest regular caller (5 seconds plus its request), so ordinary
    // polling never reopens a running game; only a real stop in watching does.
    private static readonly TimeSpan MaxWatchGap = TimeSpan.FromSeconds(30);
    private readonly TimeProvider _time = time ?? TimeProvider.System;
    // A live game keeps its path and start time; only a new PID opens a handle.
    private readonly Dictionary<GameProcessEntry, GameProcessEvidence> _known = [];
    private readonly Dictionary<GameProcessEntry, long> _refused = [];
    private GameProcessEvidence[]? _cached;
    private long _capturedAt;
    private long? _watchedAt;

    internal GameProcessEvidence[] Observe()
    {
        lock (_gate)
        {
            var now = _time.GetTimestamp();
            if (_cached is not null && _time.GetElapsedTime(_capturedAt, now) is var age &&
                age >= TimeSpan.Zero && age < TimeSpan.FromMilliseconds(500)) return _cached;
            var evidence = new List<GameProcessEvidence>();
            try
            {
                // A PID can only be trusted as the same process if it was watched without a gap.
                if (_watchedAt is { } watched && _time.GetElapsedTime(watched, now) is var gap &&
                    (gap < TimeSpan.Zero || gap > MaxWatchGap)) _known.Clear();
                _watchedAt = null;
                using var snapshot = source.Capture();
                var live = new HashSet<GameProcessEntry>();
                foreach (var entry in snapshot.Entries)
                {
                    if (!Names.Contains(Path.GetFileNameWithoutExtension(entry.Name))) continue;
                    live.Add(entry);
                    if (_known.TryGetValue(entry, out var known)) { evidence.Add(known); continue; }
                    if (_refused.TryGetValue(entry, out var refusedAt) &&
                        _time.GetElapsedTime(refusedAt, now) is var waited && waited >= TimeSpan.Zero && waited < OpenRetry)
                    { evidence.Add(new(entry.Pid, null, null, true)); continue; }
                    GameProcessEvidence? read;
                    try
                    {
                        using var process = source.Open(entry);
                        read = process.Read();
                    }
                    catch { read = new(entry.Pid, null, null, true); }
                    if (read is null) continue; // Already gone: not remembered, and not running.
                    evidence.Add(read);
                    if (IsUncertain(read)) _refused[entry] = now;
                    else { _known[entry] = read; _refused.Remove(entry); }
                }
                foreach (var gone in _known.Keys.Where(entry => !live.Contains(entry)).ToArray()) _known.Remove(gone);
                foreach (var gone in _refused.Keys.Where(entry => !live.Contains(entry)).ToArray()) _refused.Remove(gone);
                _watchedAt = now;
            }
            catch
            {
                // Continuity is lost, but a repeating failure must not reopen the game each time.
                foreach (var entry in _known.Keys) _refused[entry] = now;
                _known.Clear();
                evidence.Add(new(0, null, null, true));
            }
            var result = evidence.ToArray();
            // Transient enumeration/target failures are retried by the next caller.
            _cached = result.Any(IsUncertain) ? null : result;
            _capturedAt = now;
            return result;
        }
    }

    internal static GameProcessSession Resolve(IEnumerable<GameProcessEvidence> evidence)
    {
        var sessions = new List<GameProcessSession>();
        var uncertain = false;
        foreach (var item in evidence)
        {
            if (IsUncertain(item))
            { uncertain = true; continue; }
            var bin = Path.GetDirectoryName(item.Executable!)!;
            var started = item.StartedAt!.Value;
            sessions.Add(new("running", Path.Combine(Path.GetDirectoryName(bin)!, "Game.log"),
                started, item.Pid + ":" + started.UtcTicks));
        }
        return uncertain || sessions.Count > 1 ? new("unknown") :
            sessions.Count == 0 ? new("notRunning") : sessions[0];
    }

    // Cache admission and session resolution must reject exactly the same incomplete evidence.
    private static bool IsUncertain(GameProcessEvidence item)
    {
        if (item.Uncertain || item.Executable is null || item.StartedAt is null) return true;
        var bin = Path.GetDirectoryName(item.Executable);
        return bin is null || !Path.GetFileName(bin).Equals("Bin64", StringComparison.OrdinalIgnoreCase);
    }
}

// Names of running processes without opening any of them. Never throws: an unavailable
// snapshot reads as nothing found.
public static class ProcessSnapshotNames
{
    private const long ForegroundMaxAgeMilliseconds = 5000;
    private sealed record Foreground(uint ProcessId, string Name, long ReadAt);
    private static Foreground? _foreground;

    // For checks that run on a timer: the foreground process rarely changes, and a
    // snapshot is not free, so one is taken only when it does. The age limit bounds how
    // long a PID reused by another process can read as the old name.
    public static string? FindForeground(uint processId)
    {
        var now = Environment.TickCount64;
        if (Volatile.Read(ref _foreground) is { } known && known.ProcessId == processId &&
            IsFresh(known.ReadAt, now)) return known.Name;
        var name = Find(processId);
        Volatile.Write(ref _foreground, name is null ? null : new Foreground(processId, name, now));
        return name;
    }

    internal static bool IsFresh(long readAt, long now) =>
        now >= readAt && now - readAt < ForegroundMaxAgeMilliseconds;

    public static string? Find(uint processId)
    {
        try
        {
            using var snapshot = new WindowsGameProcessSource().Capture();
            foreach (var entry in snapshot.Entries)
                if (entry.Pid == processId) return entry.Name;
        }
        catch (Exception error) when (error is Win32Exception or InvalidOperationException) { }
        return null;
    }

    public static bool Any(Func<string, bool> match)
    {
        try
        {
            using var snapshot = new WindowsGameProcessSource().Capture();
            foreach (var entry in snapshot.Entries)
                if (match(entry.Name)) return true;
        }
        catch (Exception error) when (error is Win32Exception or InvalidOperationException) { }
        return false;
    }
}

// Toolhelp supplies names without opening unrelated processes (including protected ones).
// Path, creation time and exit status all come from ONE opened handle, preventing PID reuse
// from mixing an old process's StartTime with a replacement process's executable path.
internal sealed class WindowsGameProcessSource : IGameProcessSource
{
    public IGameProcessSnapshot Capture() => new Snapshot();
    public IGameProcessHandle Open(GameProcessEntry entry) => new Target(entry.Pid, entry.Name);

    private sealed class Snapshot : IGameProcessSnapshot
    {
        private readonly SafeSnapshotHandle _handle;
        private readonly int _captureError;
        internal Snapshot()
        {
            _handle = CreateToolhelp32Snapshot(2, 0);
            _captureError = Marshal.GetLastWin32Error();
        }
        public IEnumerable<GameProcessEntry> Entries
        {
            get
            {
                if (_handle.IsInvalid) throw new Win32Exception(_captureError);
                var entry = new ProcessEntry { Size = (uint)Marshal.SizeOf<ProcessEntry>() };
                if (!Process32First(_handle, ref entry))
                {
                    var error = Marshal.GetLastWin32Error();
                    if (error == 18) yield break;
                    throw new Win32Exception(error);
                }
                do { yield return new((int)entry.Pid, entry.Name); }
                while (Process32Next(_handle, ref entry));
                var nextError = Marshal.GetLastWin32Error();
                if (nextError != 18) throw new Win32Exception(nextError);
            }
        }
        public void Dispose() => _handle.Dispose();
    }

    private sealed class Target : IGameProcessHandle
    {
        private readonly int _pid;
        private readonly string _name;
        private readonly SafeProcessHandle _handle;
        private readonly int _openError;
        internal Target(int pid, string name)
        {
            _pid = pid; _name = name;
            _handle = OpenProcess(0x1000 | 0x00100000, false, pid); // QUERY_LIMITED_INFORMATION | SYNCHRONIZE
            _openError = Marshal.GetLastWin32Error();
        }
        public GameProcessEvidence? Read()
        {
            if (_handle.IsInvalid)
            {
                if (_openError == 87) return null; // PID disappeared after the snapshot.
                throw new Win32Exception(_openError);
            }
            var path = new StringBuilder(2048);
            var length = (uint)path.Capacity;
            if (!QueryFullProcessImageName(_handle, 0, path, ref length))
            {
                var error = Marshal.GetLastWin32Error();
                return FailedQuery(error);
            }
            if (!GetProcessTimes(_handle, out var creation, out _, out _, out _))
            {
                var error = Marshal.GetLastWin32Error();
                return FailedQuery(error);
            }
            if (HasExited()) return null;
            // A PID replaced between snapshot and OpenProcess must not identify another executable.
            if (!Path.GetFileName(path.ToString()).Equals(_name, StringComparison.OrdinalIgnoreCase))
                return new(_pid, null, null, true);
            return new(_pid, path.ToString(), new DateTimeOffset(DateTime.FromFileTimeUtc(creation)));
        }

        private GameProcessEvidence? FailedQuery(int error)
        {
            if (HasExited()) return null;
            throw new Win32Exception(error);
        }

        private bool HasExited()
        {
            var result = WaitForSingleObject(_handle, 0);
            var error = Marshal.GetLastWin32Error();
            return result switch
            {
                0 => true, // WAIT_OBJECT_0: confirmed exit, regardless of the exit code.
                258 => false, // WAIT_TIMEOUT: still running.
                uint.MaxValue => throw new Win32Exception(error), // WAIT_FAILED: uncertain.
                _ => throw new InvalidOperationException("Unexpected process wait result.")
            };
        }
        public void Dispose() => _handle.Dispose();
    }

    private sealed class SafeSnapshotHandle : SafeHandleZeroOrMinusOneIsInvalid
    {
        public SafeSnapshotHandle() : base(true) { }
        protected override bool ReleaseHandle() => CloseHandle(handle);
    }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct ProcessEntry
    {
        internal uint Size, Usage, Pid;
        internal UIntPtr DefaultHeap;
        internal uint Module, Threads, ParentPid;
        internal int Priority;
        internal uint Flags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 260)] internal string Name;
    }
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern SafeSnapshotHandle CreateToolhelp32Snapshot(uint flags, uint pid);
    [DllImport("kernel32.dll", EntryPoint = "Process32FirstW", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool Process32First(SafeSnapshotHandle handle, ref ProcessEntry entry);
    [DllImport("kernel32.dll", EntryPoint = "Process32NextW", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool Process32Next(SafeSnapshotHandle handle, ref ProcessEntry entry);
    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool CloseHandle(IntPtr handle);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern SafeProcessHandle OpenProcess(uint access, [MarshalAs(UnmanagedType.Bool)] bool inherit, int pid);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool QueryFullProcessImageName(SafeProcessHandle handle, uint flags, StringBuilder path, ref uint size);
    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetProcessTimes(SafeProcessHandle handle, out long creation, out long exit, out long kernel, out long user);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern uint WaitForSingleObject(SafeProcessHandle handle, uint milliseconds);
}
