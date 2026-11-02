using System.Diagnostics;
using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;
using StarBridge.Core.Identity;
using StarBridge.Core.Parsing;

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
    private long? _liveFrom;
    private bool _following;
    private long _lineStart;
    private readonly Dictionary<(string Handle, string Id), string> _identities = [];
    private bool _quit;
    private bool _invalidIdentityEvidence;
    private byte[] _anchor = [];
    private readonly List<byte> _line = [];
    private bool _longLine;
    private DateTimeOffset? _recentIdentityAt;
    private long? _recentWriteStamp;
    private readonly GameLogSessionTracker? _session;
    private readonly Support.GameLogJournalBatch? _journal;
    private readonly bool _strictLocalEvidence;

    public GameLogIdentityReader()
    {
    }

    internal GameLogIdentityReader(GameLogSessionTracker session, Support.GameLogJournalBatch? journal = null,
        bool strictLocalEvidence = false)
    {
        _session = session ?? throw new ArgumentNullException(nameof(session));
        _journal = journal;
        _strictLocalEvidence = strictLocalEvidence;
    }

    internal GameLogSessionSnapshot SessionSnapshot(DateTimeOffset now) =>
        _session?.Snapshot(now) ?? GameLogSessionSnapshot.Empty;

    // Runtime candidates belong to this reader source and must not survive its reset.
    internal event Action? SourceReset;
    internal bool IdentityInvalidated => _quit || _invalidIdentityEvidence || _identities.Count > 1;

    public void Reset()
    {
        _source = null; _position = 0; _identities.Clear(); _quit = false;
        _liveFrom = null; _lineStart = 0; _following = false;
        _invalidIdentityEvidence = false;
        _anchor = []; _line.Clear(); _longLine = false;
        _recentIdentityAt = null;
        _recentWriteStamp = null;
        _session?.Reset();
        _journal?.Reset();
        SourceReset?.Invoke();
    }
    private static readonly Regex Identity = new(
        "nickname=\"(?<handle>[^\"]{2,64})\"\\s+playerGEID\\s*=?\\s*\"?(?<id>[0-9]{1,24})(?:\"|\\s|,|$)",
        RegexOptions.CultureInvariant, TimeSpan.FromMilliseconds(100));

    private static readonly GameProcessSnapshotCache Processes = new(new WindowsGameProcessSource());

    public static GameProcessSession Probe() => GameProcessSnapshotCache.Resolve(Processes.Observe());

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
        if (_strictLocalEvidence && (process.StartedAt.Value.Offset != TimeSpan.Zero ||
            process.StartedAt < DateTimeOffset.UnixEpoch || process.StartedAt > now ||
            process.SessionId.Length is 0 or > 256 || process.SessionId.Any(char.IsControl)))
        { Reset(); return new("unknown"); }
        return ReadFile(path, process, now);
    }

    /// <summary>Latest valid identity in the selected log, never live presence or gameplay events.</summary>
    public GameLogIdentityObservation ReadRecent(string path, DateTimeOffset now)
    {
        if (_session is not null || _journal is not null)
            throw new InvalidOperationException("Historical identity must use an identity-only reader.");
        return ReadFile(path, null, now);
    }

    private GameLogIdentityObservation ReadFile(string path, GameProcessSession? process, DateTimeOffset now)
    {
        var recent = process is null;
        try
        {
            path = ValidatePath(path);
            // The independent local profile opts into the strict source contract.
            // Existing account readers retain their accepted compatibility policy.
            using var pinned = _strictLocalEvidence
                ? CheckedGameLogAccess.PinnedDirectories.Open(Path.GetDirectoryName(path)!, () => { }) : null;
            if (!recent && !path.Equals(Path.GetFullPath(process!.LogPath!), StringComparison.OrdinalIgnoreCase))
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
            if (_strictLocalEvidence && fileInfo.Links != 1) throw new IOException();
            var length = stream.Length;
            if (_strictLocalEvidence && length > 64L * 1024 * 1024) { Reset(); return new("limit"); }
            var writeStamp = ((long)fileInfo.Write.dwHighDateTime << 32) | (uint)fileInfo.Write.dwLowDateTime;
            var fileIdentity = _strictLocalEvidence ? CheckedGameLogAccess.PersistentIdentity(stream.SafeFileHandle) :
                fileInfo.Volume + ":" + fileInfo.IndexHigh + ":" + fileInfo.IndexLow;
            var source = path + "|" + (process?.SessionId ?? "recent-identity-only") + "|" + fileIdentity;
            if (_source != source || length < _position || !AnchorMatches() ||
                ((recent || _strictLocalEvidence) && length == _position && _recentWriteStamp is { } lastWrite && lastWrite != writeStamp))
            { Reset(); _source = source; }
            // Stay historical until catch-up reaches EOF; an old partial line remains historical.
            if (!_following) _liveFrom = length;
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
                                if (_strictLocalEvidence) _invalidIdentityEvidence = true;
                            }
                        }
                        _line.Clear(); _longLine = false;
                        _lineStart = _position + i + 1;
                    }
                    else if (!_longLine)
                    {
                        if (_line.Count >= 65536) {
                            _longLine = true; _line.Clear();
                            if (recent || _strictLocalEvidence) _invalidIdentityEvidence = true;
                        }
                        else _line.Add(buffer[i]);
                    }
                }
                remaining -= count; _position += count;
            }
            _anchor = new byte[(int)Math.Min(64, _position)];
            stream.Position = _position - _anchor.Length;
            stream.ReadExactly(_anchor);
            if (stream.Length < length) { Reset(); return new("waiting"); }
            if (recent || _strictLocalEvidence) {
                if (!GetFileInformationByHandle(stream.SafeFileHandle, out var after) ||
                    after.Write.dwHighDateTime != fileInfo.Write.dwHighDateTime ||
                    after.Write.dwLowDateTime != fileInfo.Write.dwLowDateTime ||
                    _strictLocalEvidence && (after.Links != 1 ||
                        (after.Attributes & (FileAttributes.Directory | FileAttributes.ReparsePoint)) != 0)) {
                    Reset(); return new("reading");
                }
                _recentWriteStamp = writeStamp;
            }
            // Do not skip the middle of a large file: it may contain a conflicting identity or quit.
            if (_position < stream.Length) return new("reading");
            _following = true;
            if ((!recent && _quit) || _invalidIdentityEvidence) return new("waiting");
            // An incomplete possible identity must not let a previous value authorize a rename.
            if ((recent || _strictLocalEvidence) && (_longLine || _line.Count != 0)) return new("reading");
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
                if (_strictLocalEvidence) { ObserveStrict(line); return; }
                var containsIdentity = line.Contains("nickname=", StringComparison.Ordinal);
                var containsQuit = line.Contains("SystemQuit", StringComparison.Ordinal);
                if (_journal is null && !containsIdentity && !containsQuit &&
                    (_session is null || !GameLogSessionTracker.MightContainEvidence(line))) return;
                if (line.Length < 22 || line[0] != '<') {
                    if (recent && containsIdentity) _invalidIdentityEvidence = true;
                    return;
                }
                var end = line.IndexOf('>');
                if (end is < 20 or > 40 ||
                    !DateTimeOffset.TryParse(line.AsSpan(1, end - 1), CultureInfo.InvariantCulture,
                        DateTimeStyles.AssumeUniversal | DateTimeStyles.AdjustToUniversal, out var timestamp) ||
                    (!recent && timestamp < process!.StartedAt!.Value.AddSeconds(-2)) || timestamp > now.AddSeconds(5)) {
                    if (recent && containsIdentity) _invalidIdentityEvidence = true;
                    return;
                }
                _session?.Observe(line, live: !recent && _following && _lineStart >= _liveFrom);
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
                    match.Groups["id"].Value.All(c => c == '0')) {
                    if (recent) _invalidIdentityEvidence = true;
                    return;
                }
                if (recent) {
                    if (_recentIdentityAt is { } previous && timestamp < previous) return;
                    if (_recentIdentityAt != timestamp) _identities.Clear();
                    _recentIdentityAt = timestamp;
                }
                if (_identities.Count < 2)
                    _identities.TryAdd((match.Groups["handle"].Value.ToLowerInvariant(), match.Groups["id"].Value),
                        match.Groups["handle"].Value);
            }
            void ObserveStrict(string line)
            {
                var state = LocalGameIdentityLine.Parse(line, now, out var identity);
                var quit = line.Contains("<SystemQuit>", StringComparison.OrdinalIgnoreCase) &&
                    line.Contains("CSystem::Quit", StringComparison.OrdinalIgnoreCase);
                if (!LocalGameIdentityLine.TryTimestamp(line, now, out var at, out var resolution))
                { if (state == LocalGameIdentityLineState.Invalid || quit) _invalidIdentityEvidence = true; return; }
                if (!LocalGameIdentityLine.MeetsSessionTime(new("", "", at) { ResolutionTicks = resolution },
                    process!.StartedAt!.Value, process.StartedAt.Value, now)) return;
                if (state == LocalGameIdentityLineState.Invalid) { _invalidIdentityEvidence = true; return; }
                if (quit) { _quit = true; _session?.Reset(); return; }
                // A remote/unrelated nickname must not change the session tracker's
                // local identity while the strict identity observer ignores it.
                if (state == LocalGameIdentityLineState.Unrelated &&
                    line.Contains("nickname", StringComparison.OrdinalIgnoreCase)) return;
                _session?.Observe(line, live: !recent && _following && _lineStart >= _liveFrom);
                if (identity is not null && _identities.Count < 2)
                    _identities.TryAdd((identity.Handle.ToLowerInvariant(), identity.PlayerId), identity.Handle);
            }
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or ArgumentException or
            NotSupportedException or DecoderFallbackException or RegexMatchTimeoutException or GameplayTimeException)
        { Reset(); return new("unreadable"); }
    }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern uint GetFinalPathNameByHandle(SafeFileHandle file, StringBuilder path, uint size, uint flags);
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
