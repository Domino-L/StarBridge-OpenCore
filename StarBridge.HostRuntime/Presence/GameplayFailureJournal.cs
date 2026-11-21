namespace StarBridge.HostRuntime.Presence;

/// <summary>
/// Gameplay-time failure lines for the local journal (build 71 diagnostics).
/// The first occurrence of each reason in a run is written in full; repeats only
/// as a count, at 2, 4, 8, ... so a failure that keeps retrying never floods the
/// journal. One instance per GameplayTimeStore, shared by its runtime: one per run.
/// Callers pass fixed tokens only: reason codes, check names, exception type names
/// and the first 8 characters of the file hash. Never contents, paths or account ids.
/// </summary>
internal sealed class GameplayFailureJournal
{
    private readonly object _gate = new();
    private readonly Dictionary<string, long> _counts = new(StringComparer.Ordinal);
    private readonly Dictionary<string, string> _states = new(StringComparer.Ordinal);

    /// <summary>
    /// For a state polled on every sample (the recording owner): only a change of
    /// [state] counts as an occurrence, and each state then follows <see cref="Record"/>:
    /// full the first time in the run, afterwards a count at 2, 4, 8, ...
    /// </summary>
    internal void RecordChange(string stage, string state)
    {
        lock (_gate)
        {
            if (_states.TryGetValue(stage, out var last) && last == state) return;
            _states[stage] = state;
        }
        Record(stage, state, state);
    }

    internal void Record(string stage, string key, string firstLine)
    {
        long count;
        lock (_gate)
        {
            _counts.TryGetValue(stage + " " + key, out count);
            _counts[stage + " " + key] = ++count;
        }
        if (count == 1) Support.IdentityGateJournal.Event(stage, firstLine);
        else if ((count & (count - 1)) == 0)
            Support.IdentityGateJournal.Event(stage, key + " count=" +
                count.ToString(System.Globalization.CultureInfo.InvariantCulture));
    }
}
