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

    internal static IReadOnlyList<string> CommonInstallationRoots()
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
            try
            {
                if (drive.DriveType != DriveType.Fixed || !drive.IsReady) continue;
                foreach (var prefix in prefixes) result.Add(Path.Combine(drive.RootDirectory.FullName, prefix, "StarCitizen"));
            }
            catch { /* A drive may disappear or deny access. Manual selection remains available. */ }
        return result;
    }
}
