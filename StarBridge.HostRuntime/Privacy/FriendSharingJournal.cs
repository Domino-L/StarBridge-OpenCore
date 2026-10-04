namespace StarBridge.HostRuntime.Privacy;

/// Local bounded lifecycle codes only. Never accepts identities, source data,
/// session IDs, exception messages, URLs or credential material.
internal sealed class FriendSharingJournal(string root)
{
    private static readonly object Gate = new();
    internal void Record(string action, string outcome)
    {
        if (action is not ("read" or "save" or "start" or "publish" or "stop" or "offline") ||
            outcome is not ("started" or "succeeded" or "cancelled" or "transportFailed" or
                "invalidResponse" or "accountOrServiceRejected" or "failed")) return;
        try {
            lock (Gate) {
                var directory = Path.GetFullPath(root);
                for (var parent = new DirectoryInfo(directory); parent is not null; parent = parent.Parent)
                    if (parent.Exists && parent.Attributes.HasFlag(FileAttributes.ReparsePoint)) return;
                var path = Path.Combine(directory, "friend-sharing-diagnostics.log");
                if (File.Exists(path) && File.GetAttributes(path).HasFlag(FileAttributes.ReparsePoint)) return;
                Directory.CreateDirectory(directory);
                var line = $"{DateTimeOffset.UtcNow:O} action={action} outcome={outcome}{Environment.NewLine}";
                if (File.Exists(path) && new FileInfo(path).Length >= 128 * 1024) File.WriteAllText(path, line);
                else File.AppendAllText(path, line);
            }
        } catch (Exception error) when (error is IOException or UnauthorizedAccessException or System.Security.SecurityException) { }
    }
}
