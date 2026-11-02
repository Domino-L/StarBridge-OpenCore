using System.Globalization;

namespace StarBridge.HostRuntime.Privacy;

// Separate bounded files ensure frequent chat reads cannot rotate away other diagnostics.
internal sealed class OfficialChatAuthorReadJournal(string root, TimeProvider? clock = null)
{
    private static readonly object Gate = new();
    private readonly TimeProvider _clock = clock ?? TimeProvider.System;
    private long? _lastPage, _lastDetail;
    internal const string FileName = "official-chat-author-diagnostics.log";

    internal void Record(OfficialChatAuthorReadDiagnostic value)
    {
        try
        {
            var kind = value.Kind is "page" or "renewal" or "preview" or "detail" ? value.Kind : null;
            if (kind is null) return;
            var code = value.Code is "ok" or "http-error" or "parse-failed" or "disabled" or "cancelled" ? value.Code : "unclassified";
            var stage = kind == "detail" ? "official-chat-author-detail" : "official-chat-authors";
            lock (Gate)
            {
                // Stronger than identical-content suppression: at most one line per stage in five
                // monotonic seconds, even when elapsed/proof times or results change every read.
                var now = _clock.GetTimestamp();
                var last = kind == "detail" ? _lastDetail : _lastPage;
                if (last is { } stamp && _clock.GetElapsedTime(stamp, now) < TimeSpan.FromSeconds(5)) return;
                if (kind == "detail") _lastDetail = now; else _lastPage = now;
                var directory = Path.GetFullPath(root);
                for (var parent = new DirectoryInfo(directory); parent is not null; parent = parent.Parent)
                    if (parent.Exists && parent.Attributes.HasFlag(FileAttributes.ReparsePoint)) return;
                var path = Path.Combine(directory, FileName); var backup = path + ".1";
                if (IsReparsePoint(path) || IsReparsePoint(backup)) return;
                Directory.CreateDirectory(directory);
                static string N(long? number) => number?.ToString(CultureInfo.InvariantCulture) ?? "none";
                static int Count(int number) => Math.Clamp(number, 0, 100);
                var line = FormattableString.Invariant($"{_clock.GetUtcNow():O} [DEBUG-community-read] stage={stage} code={code} status={N(value.Status is >= 100 and <= 599 ? value.Status : null)} elapsedMs={Math.Clamp(value.ElapsedMs, 0, 3600000)} kind={kind} requested={Count(value.Requested)} visible={Count(value.Visible)} hidden={Count(value.Hidden)} unavailable={Count(value.Unavailable)} invalidVisible={Count(value.InvalidVisible)} arrivalAgeMs={N(value.ArrivalAgeMs)} remainingMs={N(value.RemainingMs)}");
                if (kind == "detail") line += $" avatarData={(value.AvatarData ? 1 : 0)} versionMatches={(value.VersionMatches ? 1 : 0)}";
                line += Environment.NewLine;
                if (File.Exists(path) && new FileInfo(path).Length + System.Text.Encoding.UTF8.GetByteCount(line) > 128 * 1024)
                    File.Move(path, backup, overwrite: true);
                File.AppendAllText(path, line, System.Text.Encoding.UTF8);
            }
        }
        catch { /* All diagnostics, including clock and filesystem errors, are best effort. */ }
    }

    private static bool IsReparsePoint(string path)
    {
        try { return File.GetAttributes(path).HasFlag(FileAttributes.ReparsePoint); }
        catch (FileNotFoundException) { return false; }
        catch (DirectoryNotFoundException) { return false; }
    }
}
