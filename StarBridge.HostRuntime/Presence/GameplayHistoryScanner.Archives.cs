using System.Text.RegularExpressions;
using StarBridge.Core.Events;
using StarBridge.Core.Parsing;
using StarBridge.HostRuntime.Support;
using static StarBridge.HostRuntime.Presence.CheckedGameLogAccess;
using static StarBridge.HostRuntime.Presence.ContractNotificationLines;

namespace StarBridge.HostRuntime.Presence;

public sealed record MissionRecordsImportResult(int FilesScanned, int FilesSkipped, int CompletedFound,
    int Added, int AlreadyKnown);
internal sealed record MissionArchiveResult(LocalMissionRecord[] Records, int FilesScanned, int FilesSkipped);

public static partial class GameplayHistoryScanner
{
    // Shared archive scope retains the original gameplay-time pinning, enumeration,
    // progress and live-anchor checks. Game.log content is deliberately never read.
    private sealed class ArchiveScope : IDisposable
    {
        internal PinnedDirectories? Live, Backups;
        internal readonly List<(string Path, long Length)> Files = [];
        internal long TotalBytes;
        public void Dispose() { Backups?.Dispose(); Live?.Dispose(); }
    }
    private static ArchiveScope DiscoverArchives(string path, ScanBudget budget, bool skipUnreadable = false)
    {
        var scope = new ArchiveScope();
        try
        {
            scope.Live = PinnedDirectories.Open(Path.GetDirectoryName(path)!, budget.Check);
            CheckTree(path, directory: false, budget);
            using (OpenChecked(path, directory: false, readContent: false)) { }
            var backups = Path.Combine(Path.GetDirectoryName(path)!, "logbackups");
            try { CheckTree(backups, directory: true, budget); }
            catch (Exception e) when (e is FileNotFoundException or DirectoryNotFoundException) { throw Error("empty"); }
            scope.Backups = PinnedDirectories.Open(backups, budget.Check);
            budget.Report(new("discovering", 0, 0, 0, 0));
            var options = new EnumerationOptions {
                RecurseSubdirectories = false, IgnoreInaccessible = false, AttributesToSkip = 0,
                MatchType = MatchType.Simple, MatchCasing = MatchCasing.CaseInsensitive, ReturnSpecialDirectories = false
            };
            foreach (var file in Directory.EnumerateFiles(backups, "*.log", options))
            {
                budget.Check();
                long length;
                try { CheckTree(file, directory: false, budget); length = new FileInfo(file).Length; }
                catch (Exception e) when (skipUnreadable && ReadError(e)) { length = -1; }
                scope.TotalBytes = checked(scope.TotalBytes + Math.Max(0, length));
                scope.Files.Add((file, length));
                budget.Report(new("discovering", 0, scope.Files.Count, 0, scope.TotalBytes));
            }
            return scope;
        }
        catch { scope.Dispose(); throw; }
    }

    private sealed class ArchiveIdentity(string handle)
    {
        private string? _identity, _geid;
        private bool _matched, _invalid;
        internal bool Valid => _matched && !_invalid;
        internal string? PlayerId => Valid ? _geid : null;
        internal void Observe(string line, DateTimeOffset? stamp, DateTimeOffset cutoff)
        {
            foreach (Match match in Identity.Matches(line))
            {
                var player = match.Groups["player"].Value;
                var geid = match.Groups["playerId"].Value;
                if ((_identity is not null && !player.Equals(_identity, StringComparison.OrdinalIgnoreCase)) ||
                    (_geid is not null && geid.Length > 0 && geid != _geid)) _invalid = true;
                _identity ??= player;
                if (geid.Length > 0) _geid ??= geid;
                if (player.Equals(handle, StringComparison.OrdinalIgnoreCase) && stamp is { } at && at <= cutoff) _matched = true;
            }
        }
    }

    internal static MissionArchiveResult ScanMissions(string gameLogPath, string verifiedHandle,
        CancellationToken token = default, Action<GameplayHistoryProgress>? progress = null)
    {
        var budget = new ScanBudget(TimeProvider.System, token, progress);
        budget.Check();
        if (!OperatingSystem.IsWindows()) throw Error("unavailable");
        var path = ValidatePath(gameLogPath);
        if (string.IsNullOrWhiteSpace(verifiedHandle) || verifiedHandle.Length > 256 || verifiedHandle.Any(char.IsControl))
            throw Error("empty");
        var now = DateTimeOffset.UtcNow;
        using var archives = DiscoverArchives(path, budget, skipUnreadable: true);
        var all = new Dictionary<string, MissionEvidence>();
        var parser = new RegexLogEventParser();
        var block = new byte[16 * 1024];
        var line = new byte[64 * 1024];
        var skipped = 0;
        budget.Report(new("scanning", 0, archives.Files.Count, 0, archives.TotalBytes), force: true);
        foreach (var file in archives.Files)
        {
            budget.Check();
            var identity = new ArchiveIdentity(verifiedHandle.Trim());
            var events = new Dictionary<string, MissionEvidence>();
            string? pendingNotification = null;
            var hudLines = false;
            try
            {
                if (file.Length < 0) throw new IOException();
                ReadArchiveLines(file.Path, file.Length, budget, block, ref line, text => {
                    var stamp = ParseTimestamp(text, out _);
                    identity.Observe(text, stamp, now);
                    hudLines |= text.Contains("<SHUDEvent_OnNotification>", StringComparison.Ordinal);
                    // Identity always sees physical lines. Pending HUD text is scoped
                    // to this file and is discarded on interruption or end of file.
                    if (pendingNotification is { } pending)
                    {
                        pendingNotification = null;
                        if (TryContractContinuation(pending, text, out var body))
                        {
                            text = pending + " " + body;
                            if (text.Length > MaximumLength) return;
                            stamp = ParseTimestamp(text, out _);
                        }
                    }
                    if (IsIncompleteContractNotification(text))
                    {
                        pendingNotification = text;
                        return;
                    }
                    if (stamp is null || stamp > now || parser.TryParse(text) is not { Contract: { } data } e ||
                        e.Type is not (FleetEventType.ContractAccepted or FleetEventType.ContractDefined or FleetEventType.ContractEnded or
                            FleetEventType.ContractShared or FleetEventType.ContractPlayerJoined or FleetEventType.ContractObjective) ||
                        // EndMission names the player; ignore endings attributed to another player.
                        e.Player != "LocalPlayer" && !e.Player.Equals(verifiedHandle, StringComparison.OrdinalIgnoreCase)) return;
                    if (!events.TryGetValue(data.MissionId, out var evidence)) events[data.MissionId] = evidence = new();
                    evidence.Observe(e);
                });
                if (!identity.Valid) { skipped++; continue; }
                foreach (var (id, observed) in events)
                {
                    budget.Check();
                    observed.Identify(identity.PlayerId);
                    if (hudLines) observed.ForgetMarkers();
                    if (!all.TryGetValue(id, out var evidence)) all[id] = evidence = new();
                    evidence.Merge(observed);
                }
            }
            catch (Exception e) when (ReadError(e)) { skipped++; }
            finally { budget.FileFinished(); }
        }
        budget.Check();
        return new(all.Values.Select(e => e.Record("import")).OfType<LocalMissionRecord>().ToArray(),
            archives.Files.Count, skipped);
    }
}
