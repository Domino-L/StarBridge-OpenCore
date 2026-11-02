using StarBridge.Core.Presence;

namespace StarBridge.Desktop;

/// <summary>What the renderer needs to draw the member pages: indicator, pending pages and flips.</summary>
public sealed record OverlayMemberPagingFrame(
    int PageIndex,
    int PageCount,
    IReadOnlyList<int> PendingPages,
    int FlipSequence)
{
    public static OverlayMemberPagingFrame Single { get; } = new(0, 1, [], 0);
    public long AuthorizationGeneration { get; init; }
}

/// <summary>
/// Remembers what changed on the authorized roster between refreshes so member
/// rotation can hold a page while one of its rows shows a change cue, and jump to
/// the page holding an unseen change that matters to the viewer. Missing data is
/// unknown, never a change (see IO-035).
/// </summary>
internal sealed class OverlayMemberPagingTracker
{
    internal static readonly TimeSpan CueDuration = TimeSpan.FromMilliseconds(2800);
    private static readonly TimeSpan HoldGrace = TimeSpan.FromMilliseconds(400);
    private static readonly TimeSpan PendingLifetime = TimeSpan.FromSeconds(90);

    private Dictionary<string, Snapshot> _last = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, DateTimeOffset> _cueStarted = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, DateTimeOffset> _pending = new(StringComparer.OrdinalIgnoreCase);
    private bool _baselined;

    internal static string KeyOf(PlayerRow player) =>
        OverlayRosterPreferenceIdentity.Resolve(player) ?? player.Name;

    internal void Reset()
    {
        _last.Clear();
        _cueStarted.Clear();
        _pending.Clear();
        _baselined = false;
    }

    internal void Observe(
        IReadOnlyList<(PlayerRow Player, bool SameServer, bool SameLocation, bool Online)> members,
        IReadOnlySet<string> visibleKeys,
        bool localShardKnown,
        DateTimeOffset now,
        bool localLocationKnown = true)
    {
        var next = new Dictionary<string, Snapshot>(StringComparer.OrdinalIgnoreCase);
        foreach (var member in members)
        {
            var key = KeyOf(member.Player);
            var snapshot = Snapshot.From(member, localShardKnown, localLocationKnown);
            if (_last.TryGetValue(key, out var previous))
            {
                // Without a known shard on either side, same-server cannot have changed.
                if (!localShardKnown || snapshot.Shard is null) snapshot = snapshot with { SameServer = previous.SameServer };
                if (snapshot.Location is null) snapshot = snapshot with { SameLocation = previous.SameLocation };
                // Keep recognized facts through a gap, but never promote a
                // missing comparison-side into known relationship evidence.
                snapshot = snapshot with
                {
                    Location = snapshot.Location ?? previous.Location,
                    Ship = snapshot.Ship ?? previous.Ship,
                    Shard = snapshot.Shard ?? previous.Shard
                };
            }

            next[key] = snapshot;
            if (!_baselined || previous is null || previous.Unknown || snapshot.Unknown ||
                previous.Presence == PlayerPresenceKind.Paused || snapshot.Presence == PlayerPresenceKind.Paused ||
                !snapshot.DiffersFrom(previous))
            {
                continue;
            }

            if (visibleKeys.Contains(key)) _cueStarted[key] = now;
            else if (snapshot.BecameRelevantSince(previous)) _pending[key] = now;
        }

        _last = next;
        _baselined = true;
        foreach (var key in _pending.Where(pair => !next.ContainsKey(pair.Key) || now - pair.Value > PendingLifetime)
                     .Select(pair => pair.Key).ToArray())
        {
            _pending.Remove(key);
        }

        foreach (var key in _cueStarted.Where(pair => now - pair.Value > CueDuration).Select(pair => pair.Key).ToArray())
        {
            _cueStarted.Remove(key);
        }
    }

    /// <summary>A visible rotating row still showing its cue keeps the page until the cue ends.</summary>
    internal bool TryHold(IEnumerable<string> visibleRotatingKeys, DateTimeOffset now, out TimeSpan wait)
    {
        var until = visibleRotatingKeys
            .Select(key => _cueStarted.TryGetValue(key, out var started) ? started + CueDuration : DateTimeOffset.MinValue)
            .DefaultIfEmpty(DateTimeOffset.MinValue)
            .Max();
        wait = until > now ? until - now + HoldGrace : TimeSpan.Zero;
        return until > now;
    }

    /// <summary>The page of the oldest unseen relevant change, if it is not already showing.</summary>
    internal bool TryTakeJump(IReadOnlyDictionary<string, int> pageByKey, int currentPage, DateTimeOffset now, out int page)
    {
        foreach (var (key, _) in _pending.OrderBy(pair => pair.Value))
        {
            if (!pageByKey.TryGetValue(key, out var target) || target == currentPage) continue;
            _pending.Remove(key);
            _cueStarted[key] = now;
            page = target;
            return true;
        }

        page = currentPage;
        return false;
    }

    internal IReadOnlyList<int> PendingPages(IReadOnlyDictionary<string, int> pageByKey, int currentPage) =>
        _pending.Keys
            .Select(key => pageByKey.TryGetValue(key, out var page) ? page : -1)
            .Where(page => page >= 0 && page != currentPage)
            .Distinct()
            .Order()
            .ToArray();

    /// <summary>A pending member that becomes visible by other means is simply shown with its cue.</summary>
    internal void ShowPendingIfVisible(IReadOnlySet<string> visibleKeys, DateTimeOffset now)
    {
        foreach (var key in _pending.Keys.Where(visibleKeys.Contains).ToArray())
        {
            _pending.Remove(key);
            _cueStarted[key] = now;
        }
    }

    internal DateTimeOffset? CueStartedAt(string key, DateTimeOffset now) =>
        _cueStarted.TryGetValue(key, out var started) && now - started < CueDuration ? started : null;

    private sealed record Snapshot(
        PlayerPresenceKind Presence,
        bool Unknown,
        string? Location,
        string? Ship,
        string? Shard,
        bool SameServer,
        bool SameLocation,
        bool ServerEvidenceKnown,
        bool LocationEvidenceKnown)
    {
        internal static Snapshot From((PlayerRow Player, bool SameServer, bool SameLocation, bool Online) member,
            bool localShardKnown, bool localLocationKnown)
        {
            var player = member.Player;
            return new Snapshot(
                PlayerPresencePresentation.Resolve(player.SharedLiveStatusValue, player.SharedOnlineStatusValue),
                player.RealtimeStateUnknown,
                Known(player.SharedLocation) ?? Known(player.RawLocation),
                Known(player.RawShip) ?? Known(player.Ship),
                Known(player.ServerShard),
                member.SameServer,
                member.SameLocation,
                localShardKnown && Known(player.ServerShard) is not null,
                localLocationKnown && (Known(player.SharedLocation) ?? Known(player.RawLocation)) is not null);
        }

        internal bool DiffersFrom(Snapshot previous) =>
            Presence != previous.Presence ||
            Changed(Location, previous.Location) ||
            Changed(Ship, previous.Ship) ||
            Changed(Shard, previous.Shard) ||
            ServerEvidenceKnown && previous.ServerEvidenceKnown && SameServer != previous.SameServer ||
            LocationEvidenceKnown && previous.LocationEvidenceKnown && SameLocation != previous.SameLocation;

        internal bool BecameRelevantSince(Snapshot previous) =>
            ServerEvidenceKnown && previous.ServerEvidenceKnown && SameServer && !previous.SameServer ||
            LocationEvidenceKnown && previous.LocationEvidenceKnown && SameLocation && !previous.SameLocation ||
            Presence == PlayerPresenceKind.InGame && previous.Presence != PlayerPresenceKind.InGame;

        // Only two known, different values are a change; a gap on either side is not.
        private static bool Changed(string? next, string? previous) =>
            next is not null && previous is not null && !next.Equals(previous, StringComparison.OrdinalIgnoreCase);

        private static string? Known(string? value) =>
            PlayerSessionStatePresentation.HasRecognizedValue(value) &&
            !string.Equals(value!.Trim(), "Unknown", StringComparison.OrdinalIgnoreCase)
                ? value.Trim()
                : null;
    }
}

/// <summary>Bounded header geometry only; page ordering and rotation stay in the planner.</summary>
internal sealed record OverlayMemberPageIndicatorLayout(string Label, float LabelWidth, IReadOnlyList<int?> Pages, float Width)
{
    internal const float DotSize = 5, ActiveWidth = 14, Gap = 5, EllipsisWidth = 10, MinimumLabelWidth = 26;
    internal static OverlayMemberPageIndicatorLayout Resolve(int index, int count, float availableWidth, float labelWidth = MinimumLabelWidth)
    {
        if (count <= 1 || !float.IsFinite(availableWidth) || availableWidth <= 0) return new("", 0, [], 0);
        index = Math.Clamp(index, 0, count - 1);
        var label = $"{index + 1}/{count}";
        labelWidth = Math.Min(Math.Max(1, float.IsFinite(labelWidth) ? labelWidth : MinimumLabelWidth), availableWidth);
        float Width(IReadOnlyList<int?> pages) => pages.Sum(page => page is null ? EllipsisWidth : page == index ? ActiveWidth : DotSize)
            + pages.Count * Gap + labelWidth + 1;
        IReadOnlyList<int?> Window(int radius, bool endpoints)
        {
            var selected = new SortedSet<int>();
            for (var page = Math.Max(0, index - radius); page <= Math.Min(count - 1, index + radius); page++) selected.Add(page);
            if (endpoints) { selected.Add(0); selected.Add(count - 1); }
            var result = new List<int?>();
            var previous = -1;
            foreach (var page in selected) { if (page > previous + 1) result.Add(null); result.Add(page); previous = page; }
            if (previous < count - 1) result.Add(null);
            return result;
        }
        if (count <= 5)
        {
            var all = Enumerable.Range(0, count).Select(page => (int?)page).ToArray();
            if (Width(all) <= availableWidth) return new(label, labelWidth, all, Width(all));
        }
        for (var radius = 2; radius >= 0; radius--)
        {
            var pages = Window(radius, endpoints: true);
            if (Width(pages) <= availableWidth) return new(label, labelWidth, pages, Width(pages));
        }
        var nearby = Window(0, endpoints: false);
        return Width(nearby) <= availableWidth
            ? new(label, labelWidth, nearby, Width(nearby))
            : new(label, labelWidth, [], labelWidth);
    }
}
