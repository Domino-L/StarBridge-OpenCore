namespace StarBridge.HostRuntime.Presence;

public sealed record GameLogLocation(string State, string? Path = null);

/// <summary>Checks only known install locations and process/selection siblings, never a recursive disk scan.</summary>
public sealed class GameLogLocator(Func<IReadOnlyList<string>>? installationRoots = null)
{
    public static bool ValidChannel(string? channel) =>
        channel is { Length: >= 2 and <= 32 } &&
        channel.All(character => character is >= 'A' and <= 'Z' or >= '0' and <= '9' or '_' or '-');
    public static string NormalizeChannel(string? channel) => channel?.Trim().ToUpperInvariant() ?? "";
    public static IReadOnlyList<string> Channels(string stored) => stored.Split('|', StringSplitOptions.RemoveEmptyEntries)
        .Select(NormalizeChannel).Where(ValidChannel).Distinct(StringComparer.Ordinal).Take(16).ToArray();
    public static string AddChannel(string stored, string channel)
    {
        channel = NormalizeChannel(channel);
        if (!ValidChannel(channel)) throw new ArgumentException(nameof(channel));
        var existing = Channels(stored);
        var required = existing.Contains("PTU", StringComparer.Ordinal)
            ? new[] { "LIVE", "PTU", channel }
            : new[] { "LIVE", channel };
        return string.Join('|', required.Concat(existing)
            .Distinct(StringComparer.Ordinal).Take(16));
    }
    public static string RemoveChannel(string stored, string channel)
    {
        channel = NormalizeChannel(channel);
        if (!ValidChannel(channel) || channel == "LIVE") throw new ArgumentException(nameof(channel));
        return string.Join('|', Channels(stored).Where(item => item != channel).Prepend("LIVE")
            .Distinct(StringComparer.Ordinal).Take(16));
    }
    public static string AddOptionalChannel(string stored, string channel)
    {
        channel = NormalizeChannel(channel);
        if (!ValidChannel(channel)) throw new ArgumentException(nameof(channel));
        return string.Join('|', Channels(stored).Prepend(channel)
            .Distinct(StringComparer.Ordinal).Take(16));
    }
    public static string RemoveChannelIfPresent(string stored, string channel)
    {
        channel = NormalizeChannel(channel);
        return string.Join('|', Channels(stored).Where(item => item != channel));
    }
    public static bool ContainsChannel(string stored, string channel) =>
        Channels(stored).Contains(NormalizeChannel(channel), StringComparer.Ordinal);
    public static string? ChannelOf(string? logPath)
    {
        if (string.IsNullOrWhiteSpace(logPath)) return null;
        try
        {
            var channel = Path.GetFileName(Path.GetDirectoryName(logPath))?.ToUpperInvariant();
            return ValidChannel(channel) ? channel : null;
        }
        catch { return null; }
    }

    public GameLogLocation Find(string channel, GameProcessSession process, string? previousPath)
    {
        channel = NormalizeChannel(channel);
        if (!ValidChannel(channel)) throw new ArgumentException(nameof(channel));
        // The running selected version is stronger evidence than another installed copy.
        if (process.State == "running" && ChannelOf(process.LogPath) == channel &&
            SafePath(process.LogPath) is { } running) return new("found", running);
        var roots = new List<string>();
        foreach (var path in new[] { previousPath, process.LogPath })
            if (ChannelOf(path) is not null && Path.GetDirectoryName(Path.GetDirectoryName(path!)) is { } root)
                roots.Add(root);
        roots.AddRange((installationRoots ?? CommonInstallationRoots)());
        var candidates = roots.Distinct(StringComparer.OrdinalIgnoreCase).Take(256)
            .Select(root => SafePath(Path.Combine(root, channel, "Game.log")))
            .Where(path => path is not null).Distinct(StringComparer.OrdinalIgnoreCase).Take(2).ToArray();
        return candidates.Length switch
        {
            0 => new("notFound"), 1 => new("found", candidates[0]), _ => new("multipleLogs")
        };
    }

    private static string? SafePath(string? path)
    {
        if (path is null || !File.Exists(path)) return null;
        try { return GameLogIdentityReader.ValidatePath(path); }
        catch { return null; }
    }

    // Same source order as Find, extended only to immediate version folders.
    // The caller supplies the shared deadline/lifecycle check and validates files.
    internal IEnumerable<string> CandidatePaths(GameProcessSession process, IEnumerable<string> previousPaths, Action check)
    {
        var previous = previousPaths.Take(32).ToArray();
        if (process.State == "running" && ChannelOf(process.LogPath) is not null)
            yield return process.LogPath!;
        foreach (var path in previous) { check(); yield return path; }
        // Common installation folders first, so a large earlier folder cannot
        // use up the shared limit before them.
        var installed = installationRoots is { } custom ? custom() : CommonInstallationRoots(check);
        var roots = new List<string>(installed);
        check();
        foreach (var path in previous.Prepend(process.LogPath))
            if (ChannelOf(path) is not null && Path.GetDirectoryName(Path.GetDirectoryName(path!)) is { } root)
                roots.Add(root);
        var inspected = 0;
        foreach (var root in roots.Distinct(StringComparer.OrdinalIgnoreCase).Take(256))
        {
            check();
            // Check every parent for links before enumerating. The handles do not
            // stop a later rename; Describe and the Host recheck on selection do.
            CheckedGameLogAccess.PinnedDirectories? guard = null;
            IEnumerator<string>? folders = null;
            try
            {
                var drive = Path.GetPathRoot(root);
                if (!Path.IsPathFullyQualified(root) || drive is not { Length: 3 } ||
                    !char.IsAsciiLetter(drive[0]) || drive[1] != ':' || root.AsSpan(2).Contains(':') ||
                    root.Any(char.IsControl) || new DriveInfo(drive).DriveType != DriveType.Fixed ||
                    root[drive.Length..].Split([Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar])
                        .Any(p => p is "." or ".." || p.EndsWith(' ') || p.EndsWith('.')))
                    continue;
                guard = CheckedGameLogAccess.PinnedDirectories.Open(root, check);
                folders = Directory.EnumerateDirectories(root).GetEnumerator();
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException or GameplayTimeException or ArgumentException)
            { guard?.Dispose(); continue; }
            using (guard)
            using (folders)
            {
                foreach (var channel in new[] { "LIVE", "PTU", "EPTU" })
                { check(); yield return Path.Combine(root, channel, "Game.log"); }
                // Other version names are read only in installation folders or a
                // StarCitizen folder; an earlier Game.log in Downloads must not
                // list its siblings as versions.
                if (!installed.Contains(root, StringComparer.OrdinalIgnoreCase) &&
                    !Path.GetFileName(Path.TrimEndingDirectorySeparator(root)).Equals("StarCitizen", StringComparison.OrdinalIgnoreCase))
                    continue;
                var perRoot = 0;
                while (true)
                {
                    check();
                    string folder;
                    try { if (!folders.MoveNext()) break; folder = folders.Current; }
                    catch (Exception error) when (error is IOException or UnauthorizedAccessException) { break; }
                    if (++inspected > 1024) yield break;
                    if (++perRoot > 64) break;
                    if (ValidChannel(NormalizeChannel(Path.GetFileName(folder))))
                        yield return Path.Combine(folder, "Game.log");
                }
            }
        }
    }

    internal static IReadOnlyList<string> CommonInstallationRoots() => CommonInstallationRoots(null);

    // `check` runs before each drive, so a stopped search does not go on to the
    // next drive after one slow drive query returns.
    internal static IReadOnlyList<string> CommonInstallationRoots(Action? check)
    {
        var result = new List<string>();
        foreach (var folder in new[] { Environment.SpecialFolder.ProgramFiles, Environment.SpecialFolder.ProgramFilesX86 })
        {
            var path = Environment.GetFolderPath(folder);
            if (!string.IsNullOrWhiteSpace(path)) result.Add(Path.Combine(path, "Roberts Space Industries", "StarCitizen"));
        }
        string[] prefixes = ["", "Roberts Space Industries", "Games", Path.Combine("Games", "Roberts Space Industries"),
            "RSI", Path.Combine("Program Files", "Roberts Space Industries"), Path.Combine("Program Files (x86)", "Roberts Space Industries")];
        foreach (var drive in DriveInfo.GetDrives())
        {
            check?.Invoke();
            try
            {
                if (drive.DriveType != DriveType.Fixed || !drive.IsReady) continue;
                foreach (var prefix in prefixes) result.Add(Path.Combine(drive.RootDirectory.FullName, prefix, "StarCitizen"));
            }
            catch { /* A drive may disappear or deny access. Manual selection remains available. */ }
        }
        return result;
    }
}
