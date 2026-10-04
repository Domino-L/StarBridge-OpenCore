namespace StarBridge.HostRuntime.Privacy;

// Bounded local transition evidence. Never records identities, payloads, URLs,
// credentials, server bodies or exception messages.
internal sealed class PrivacyPublicationJournal(string root)
{
    private static readonly object Gate = new();
    internal void Record(string state, string? error)
    {
        if (state is not ("inactive" or "identityRequired" or "publishing" or "pending" or "applied" or
            "withdrawn" or "failed" or "reconnecting" or "withdrawalPending")) return;
        var reason = error switch
        {
            null => "none",
            "privacy_publication.temporarily_unavailable" => "transportOrDeadline",
            "privacy_publication.network_unavailable" => "network",
            "privacy_publication.timeout" => "timeout",
            "privacy_publication.server_error" => "server",
            "privacy_publication.rate_limited" => "rateLimited",
            "privacy_publication.forbidden" => "forbidden",
            "privacy_publication.identity_required" or "privacy_publication.identity_unavailable" => "identity",
            "privacy_publication.account_changed" => "accountChanged",
            "privacy_publication.response_invalid" => "invalidReceipt",
            "privacy_publication.route_retired" => "retiredRoute",
            "privacy_local.read_failed" or "privacy_local.write_failed" or "privacy_local.conflict" => "localPolicy",
            _ => "unclassified"
        };
        try
        {
            lock (Gate)
            {
                var directory = Path.GetFullPath(root);
                for (var parent = new DirectoryInfo(directory); parent is not null; parent = parent.Parent)
                    if (parent.Exists && parent.Attributes.HasFlag(FileAttributes.ReparsePoint)) return;
                var path = Path.Combine(directory, "realtime-sharing-diagnostics.log");
                if (File.Exists(path) && File.GetAttributes(path).HasFlag(FileAttributes.ReparsePoint)) return;
                Directory.CreateDirectory(directory);
                var line = $"{DateTimeOffset.UtcNow:O} state={state} reason={reason}{Environment.NewLine}";
                if (File.Exists(path) && new FileInfo(path).Length >= 128 * 1024) File.WriteAllText(path, line);
                else File.AppendAllText(path, line);
            }
        }
        catch (Exception errorWriting) when (errorWriting is IOException or UnauthorizedAccessException or System.Security.SecurityException) { }
    }
}
