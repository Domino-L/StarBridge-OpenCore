using System.Diagnostics;
using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
using StarBridge.Core.Identity;

namespace StarBridge.HostRuntime.Presence;

public sealed record GameProcessSession(string State, string? LogPath = null,
    DateTimeOffset? StartedAt = null, string? SessionId = null);
public sealed record GameLogIdentityObservation(string State, string? Handle = null);

/// <summary>Bounded, read-only identity snapshot. Never treats a display name or old session as current identity.</summary>
public sealed class GameLogIdentityReader
{
    private const int WindowBytes = 16 * 1024 * 1024;
    private string? _source;
    private long _position;
    private readonly Dictionary<(string Handle, string Id), string> _identities = [];
    private bool _quit;
    private bool _invalidIdentityEvidence;
    private byte[] _anchor = [];
    private readonly List<byte> _line = [];
    private bool _longLine;
    private readonly GameLogSessionTracker? _session;
    private readonly Support.GameLogJournalBatch? _journal;

    public GameLogIdentityReader()
    {
    }

    internal GameLogIdentityReader(GameLogSessionTracker session, Support.GameLogJournalBatch? journal = null)
    {
        _session = session ?? throw new ArgumentNullException(nameof(session));
        _journal = journal;
    }

    internal GameLogSessionSnapshot SessionSnapshot(DateTimeOffset now) =>
        _session?.Snapshot(now) ?? GameLogSessionSnapshot.Empty;

    public void Reset()
    {
        _source = null; _position = 0; _identities.Clear(); _quit = false;
        _invalidIdentityEvidence = false;
        _anchor = []; _line.Clear(); _longLine = false;
        _session?.Reset();
        _journal?.Reset();
    }
    private static readonly Regex Identity = new(
        "nickname=\"(?<handle>[^\"]{2,64})\"\\s+playerGEID\\s*=?\\s*\"?(?<id>[0-9]{1,24})(?:\"|\\s|,|$)",
        RegexOptions.CultureInvariant, TimeSpan.FromMilliseconds(100));

    public static GameProcessSession Probe()
    {
        var sessions = new List<GameProcessSession>();
        var uncertain = false;
        foreach (var name in new[] { "StarCitizen", "StarCitizen_LIVE", "StarCitizen_PTUR", "StarCitizen_EPTU",
                     "StarCitizen_HOTFIX", "StarCitizen_TECH-PREVIEW" })
        {
            Process[] processes;
            try { processes = Process.GetProcessesByName(name); }
            catch { uncertain = true; continue; }
            foreach (var process in processes)
                using (process)
                    try
                    {
                        if (process.HasExited) continue;
                        using var processHandle = OpenProcess(0x1000, false, process.Id);
                        var executableBuffer = new StringBuilder(2048);
                        var executableLength = (uint)executableBuffer.Capacity;
                        if (processHandle.IsInvalid || !QueryFullProcessImageName(processHandle, 0, executableBuffer, ref executableLength))
                        { uncertain = true; continue; }
                        var executable = executableBuffer.ToString();
                        var bin = Path.GetDirectoryName(executable);
                        if (bin is null || !Path.GetFileName(bin).Equals("Bin64", StringComparison.OrdinalIgnoreCase))
                        { uncertain = true; continue; }
                        var started = new DateTimeOffset(process.StartTime.ToUniversalTime());
                        sessions.Add(new("running", Path.Combine(Path.GetDirectoryName(bin)!, "Game.log"),
                            started, process.Id + ":" + started.UtcTicks));
                    }
                    catch { uncertain = true; }
        }
        return uncertain || sessions.Count > 1 ? new("unknown") :
            sessions.Count == 0 ? new("notRunning") : sessions[0];
    }

    public static string ValidatePath(string path)
    {
        if (!OperatingSystem.IsWindows() || string.IsNullOrWhiteSpace(path) || path.Length > 1024 ||
            !Path.IsPathFullyQualified(path) || path.StartsWith(@"\\") || path.IndexOf(':', 2) >= 0 ||
            path.Split(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar).Any(p => p is "." or "..") ||
            !Path.GetFileName(path).Equals("Game.log", StringComparison.OrdinalIgnoreCase))
            throw new IOException("Invalid game log path.");
        var full = Path.GetFullPath(path);
        var root = Path.GetPathRoot(full)!;
        if (new DriveInfo(root).DriveType != DriveType.Fixed) throw new IOException("Local disk required.");
        for (var current = full; current.Length > root.Length; current = Path.GetDirectoryName(current)!)
            if ((File.GetAttributes(current) & FileAttributes.ReparsePoint) != 0)
                throw new IOException("Linked paths are not supported.");
        return full;
    }

    public static GameLogIdentityObservation Read(string path, GameProcessSession process, DateTimeOffset now) =>
        new GameLogIdentityReader().ReadCurrent(path, process, now);

    public GameLogIdentityObservation ReadCurrent(string path, GameProcessSession process, DateTimeOffset now)
    {
        _journal?.BeginRead();
        if (process.State != "running") { Reset(); return new(process.State == "notRunning" ? "notRunning" : "unknown"); }
        if (process.StartedAt is null || process.LogPath is null || process.SessionId is null)
        { Reset(); return new("unknown"); }
        try
        {
            path = ValidatePath(path);
            if (!path.Equals(Path.GetFullPath(process.LogPath), StringComparison.OrdinalIgnoreCase))
            {
                Reset();
                return new("differentInstallation");
            }
            // No delete sharing: the selected file cannot be swapped while it is inspected.
            using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
            var finalPath = new StringBuilder(2048);
            var finalLength = GetFinalPathNameByHandle(stream.SafeFileHandle, finalPath, (uint)finalPath.Capacity, 0);
            if (finalLength == 0 || finalLength >= finalPath.Capacity ||
                !finalPath.ToString().Equals(@"\\?\" + path, StringComparison.OrdinalIgnoreCase) ||
                !GetFileInformationByHandle(stream.SafeFileHandle, out var fileInfo) ||
                (fileInfo.Attributes & (FileAttributes.Directory | FileAttributes.ReparsePoint)) != 0)
                throw new IOException();
            var length = stream.Length;
            var source = path + "|" + process.SessionId + "|" + fileInfo.Volume + ":" + fileInfo.IndexHigh + ":" + fileInfo.IndexLow;
            if (_source != source || length < _position || !AnchorMatches())
            { Reset(); _source = source; }
            stream.Position = _position;
            var remaining = (int)Math.Min(length - _position, WindowBytes);
            var buffer = new byte[65536];
            while (remaining > 0)
            {
                var count = stream.Read(buffer, 0, Math.Min(buffer.Length, remaining));
                if (count == 0) { Reset(); return new("waiting"); }
                for (var i = 0; i < count; i++)
                {
                    if (buffer[i] == (byte)'\n')
                    {
                        if (!_longLine)
                        {
                            var lineBytes = _line.ToArray();
                            try
                            {
                                Observe(new UTF8Encoding(false, true).GetString(lineBytes).TrimEnd('\r').TrimStart('\uFEFF'));
                            }
                            catch (DecoderFallbackException)
                            {
                                // One damaged diagnostic line must not restart the whole file on
                                // every sample. Do not replace bytes and fabricate trusted evidence.
                                // A possible identity/quit in a damaged line invalidates this session
                                // until a new file/process establishes an unambiguous identity.
                                if (lineBytes.AsSpan().IndexOf("nickname="u8) >= 0 ||
                                    lineBytes.AsSpan().IndexOf("SystemQuit"u8) >= 0)
                                    _invalidIdentityEvidence = true;
                            }
                        }
                        _line.Clear(); _longLine = false;
                    }
                    else if (!_longLine)
                    {
                        if (_line.Count >= 65536) { _longLine = true; _line.Clear(); }
                        else _line.Add(buffer[i]);
                    }
                }
                remaining -= count; _position += count;
            }
            _anchor = new byte[(int)Math.Min(64, _position)];
            stream.Position = _position - _anchor.Length;
            stream.ReadExactly(_anchor);
            if (stream.Length < length) { Reset(); return new("waiting"); }
            // Do not skip the middle of a large file: it may contain a conflicting identity or quit.
            if (_position < stream.Length) return new("reading");
            if (_quit || _invalidIdentityEvidence) return new("waiting");
            return _identities.Count switch
            {
                0 => new("waiting"), 1 => new("identified", _identities.Single().Value), _ => new("ambiguous")
            };

            bool AnchorMatches()
            {
                if (_anchor.Length == 0) return true;
                var bytes = new byte[_anchor.Length];
                stream.Position = _position - bytes.Length; stream.ReadExactly(bytes);
                return bytes.AsSpan().SequenceEqual(_anchor);
            }
            void Observe(string line)
            {
                var containsIdentity = line.Contains("nickname=", StringComparison.Ordinal);
                var containsQuit = line.Contains("SystemQuit", StringComparison.Ordinal);
                if (_journal is null && !containsIdentity && !containsQuit &&
                    (_session is null || !GameLogSessionTracker.MightContainEvidence(line))) return;
                if (line.Length < 22 || line[0] != '<') return;
                var end = line.IndexOf('>');
                if (end is < 20 or > 40 ||
                    !DateTimeOffset.TryParse(line.AsSpan(1, end - 1), CultureInfo.InvariantCulture,
                        DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out var timestamp) ||
                    timestamp < process.StartedAt.Value.AddSeconds(-2) || timestamp > now.AddSeconds(5)) return;
                _session?.Observe(line);
                if (line.Contains("SystemQuit", StringComparison.Ordinal) && line.Contains("CSystem::Quit", StringComparison.Ordinal))
                {
                    _quit = true;
                    _session?.Reset();
                }
                if (!containsIdentity)
                {
                    return;
                }
                var match = Identity.Match(line);
                if (!match.Success || !IdentityBindingPolicy.IsValidGameName(match.Groups["handle"].Value) ||
                    match.Groups["id"].Value.All(c => c == '0')) return;
                if (_identities.Count < 2)
                    _identities.TryAdd((match.Groups["handle"].Value.ToLowerInvariant(), match.Groups["id"].Value),
                        match.Groups["handle"].Value);
            }
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or ArgumentException or
            NotSupportedException or DecoderFallbackException or RegexMatchTimeoutException)
        { Reset(); return new("unreadable"); }
    }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern uint GetFinalPathNameByHandle(SafeFileHandle file, StringBuilder path, uint size, uint flags);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern SafeProcessHandle OpenProcess(uint access, [MarshalAs(UnmanagedType.Bool)] bool inherit, int processId);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool QueryFullProcessImageName(SafeProcessHandle process, uint flags, StringBuilder path, ref uint size);
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
}
