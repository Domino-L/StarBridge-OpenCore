namespace StarBridge.HostRuntime.Realtime;

/// Local bounded gateway lifecycle codes only (2026-10-21): whether the Host
/// asked for a ticket, what the relay answered, and the client state. Never
/// accepts credentials, tickets, URLs, identities or message content.
internal sealed class RealtimeGatewayJournal(string root)
{
    private static readonly object Gate = new();

    internal void Record(string kind, string value)
    {
        if (kind is not ("ticket" or "state" or "attempt") || value.Length is 0 or > 48 ||
            !value.All(char.IsAsciiLetterOrDigit)) return;
        try {
            lock (Gate) {
                var directory = Path.GetFullPath(root);
                for (var parent = new DirectoryInfo(directory); parent is not null; parent = parent.Parent)
                    if (parent.Exists && parent.Attributes.HasFlag(FileAttributes.ReparsePoint)) return;
                var path = Path.Combine(directory, "realtime-gateway-diagnostics.log");
                if (File.Exists(path) && File.GetAttributes(path).HasFlag(FileAttributes.ReparsePoint)) return;
                Directory.CreateDirectory(directory);
                var line = $"{DateTimeOffset.UtcNow:O} {kind}={value}{Environment.NewLine}";
                if (File.Exists(path) && new FileInfo(path).Length >= 128 * 1024) File.WriteAllText(path, line);
                else File.AppendAllText(path, line);
            }
        } catch (Exception error) when (error is IOException or UnauthorizedAccessException or System.Security.SecurityException) { }
    }
}
