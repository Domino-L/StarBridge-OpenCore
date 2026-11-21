using StarBridge.HostRuntime.Presence;
using static StarBridge.HostRuntime.Presence.CheckedGameLogAccess;

namespace StarBridge.HostRuntime.Onboarding;

internal sealed record LocalGameLogCandidate(string Path, string Version);

// Complete is false when the scan's own time budget ended it early: the
// candidates are only those fully checked before then, not "nothing more".
internal sealed record LocalGameLogSearchResult(IReadOnlyList<LocalGameLogCandidate> Candidates, bool Complete);

// Metadata-only discovery. No selection, evidence read, persistence or new process API.
internal sealed class LocalGameLogSearch(GameLogLocator? locator = null,
    Func<GameProcessSession>? process = null, TimeProvider? time = null)
{
    internal const int MaximumCandidates = 8;
    internal static readonly TimeSpan MaximumDuration = TimeSpan.FromSeconds(2);
    // The caller stops waiting here even if one filesystem call blocks. Tests
    // that drive a fake clock turn it off and test it on its own.
    internal TimeSpan HardStop { get; set; } = MaximumDuration + TimeSpan.FromSeconds(3);
    // `checkedSink` receives each fully checked candidate under its own lock,
    // so a caller that stops waiting can still use what was finished.
    internal LocalGameLogSearchResult Find(IEnumerable<string> previousPaths, Action current, CancellationToken token,
        List<LocalGameLogCandidate>? checkedSink = null)
    {
        var clock = time ?? TimeProvider.System;
        var started = clock.GetTimestamp();
        var result = new List<LocalGameLogCandidate>();
        var complete = true;
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        void Check()
        {
            token.ThrowIfCancellationRequested(); current();
            if (clock.GetElapsedTime(started) >= MaximumDuration) throw new TimeoutException();
        }
        try
        {
            Check();
            var session = (process ?? GameLogIdentityReader.Probe)();
            foreach (var path in (locator ?? new()).CandidatePaths(session, previousPaths, Check))
            {
                Check();
                try
                {
                    var version = GameLogLocator.ChannelOf(path);
                    if (version is null) continue;
                    var safe = LocalGameEvidenceValidation.SelectionPath(path, version);
                    if (!seen.Add(safe)) continue;
                    using var parents = PinnedDirectories.Open(System.IO.Path.GetDirectoryName(safe)!, Check);
                    Check();
                    using var file = OpenChecked(safe, directory: false, readContent: false);
                    Describe(file, safe); // Reject links, including hard links and redirected paths.
                    Check();
                    result.Add(new(safe, version));
                    if (checkedSink is not null) lock (checkedSink) checkedSink.Add(result[^1]);
                    if (result.Count == MaximumCandidates) break;
                }
                catch (Exception error) when (error is IOException or UnauthorizedAccessException or
                    GameplayTimeException or LocalFirstUseException { Code: "firstUse.source_invalid" } or ArgumentException) { }
            }
        }
        catch (TimeoutException)
        {
            // Return only candidates fully checked before the deadline, marked
            // as an unfinished search.
            complete = false;
        }
        token.ThrowIfCancellationRequested(); current();
        return new(result, complete);
    }
}
