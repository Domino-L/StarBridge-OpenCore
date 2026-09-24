using StarBridge.HostRuntime.Communities;

namespace StarBridge.HostRuntime.Notifications;

internal sealed record CommunityNotificationCandidate(string SourceKey, NotificationEventKind Kind);

// No text is retained. First reads, gaps, rejoin and permission regrant are
// quiet baselines. Call before all delivery gates so suppressed events expire.
internal sealed class CommunityNotificationObserver(TimeProvider? time = null)
{
    private sealed record State(bool Chat, long Sequence, DateTimeOffset? Server,
        bool Management, HashSet<string> Tasks);
    private readonly TimeProvider _time = time ?? TimeProvider.System;
    private Dictionary<string, State> _sources = new(StringComparer.Ordinal);
    private string? _owner;
    private long _generation, _received;
    private DateTimeOffset? _last;
    internal void Reset() { _owner = null; _last = null; _sources.Clear(); }

    internal IReadOnlyList<CommunityNotificationCandidate> Observe(
        string owner, long generation, CommunityNotificationFeed feed)
    {
        if (string.IsNullOrWhiteSpace(owner) || feed.Sources.Length > 64 ||
            feed.Sources.Select(row => row.SourceKey).Distinct(StringComparer.Ordinal).Count() != feed.Sources.Length) {
            Reset(); return [];
        }
        var same = owner == _owner && generation == _generation;
        if (same && feed.ReceivedAt <= _last) return [];
        var continuous = same && _last is {} last && feed.ReceivedAt - last <= TimeSpan.FromSeconds(30) &&
            _time.GetElapsedTime(_received) <= TimeSpan.FromSeconds(30);
        var next = new Dictionary<string, State>(StringComparer.Ordinal);
        var candidates = new List<CommunityNotificationCandidate>();
        foreach (var source in feed.Sources) {
            var previous = same ? _sources.GetValueOrDefault(source.SourceKey) : null;
            var chat = source.ChatAvailable ? source.Chat : null;
            if (continuous && previous is { Chat: true, Server: {} server } && chat is {} incoming &&
                incoming.ServerTime > server && incoming.ServerTime - server <= TimeSpan.FromSeconds(30) &&
                incoming.Sequence > previous.Sequence && incoming.Incoming && incoming.Unread > 0 &&
                incoming.CreatedAt > server && incoming.CreatedAt <= incoming.ServerTime)
                candidates.Add(new(source.SourceKey, NotificationEventKind.OrganizationChat));

            var tasks = source.ManagementAvailable ? source.Tasks.Select(row => row.Key).ToHashSet(StringComparer.Ordinal) : [];
            if (continuous && source.ManagementAvailable && previous is { Management: true } &&
                source.Tasks.Any(row => !previous.Tasks.Contains(row.Key) && row.CreatedAt > _last && row.CreatedAt <= feed.ReceivedAt))
                candidates.Add(new(source.SourceKey, NotificationEventKind.OrganizationManagement));
            // Retain high water marks/tombstones across partial reads, but reset
            // availability so recovery never replays events from the gap.
            if (previous != null) tasks.UnionWith(previous.Tasks);
            if (tasks.Count > 20000) { Reset(); return []; }
            next[source.SourceKey] = new(chat != null, Math.Max(chat?.Sequence ?? 0, previous?.Sequence ?? 0),
                chat?.ServerTime, source.ManagementAvailable, tasks);
        }
        _sources = next; _owner = owner; _generation = generation;
        _last = feed.ReceivedAt; _received = _time.GetTimestamp();
        return candidates;
    }
}
