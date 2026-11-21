namespace StarBridge.Core.Overlay;

public enum OverlayMemberChangeKind
{
    Server,
    Ship,
    Place,
}

/// <summary>What the event list should do with one teammate change.</summary>
/// <param name="Key">Merge key of the line: a new line when <paramref name="Update"/> is false, else the line to rewrite.</param>
public readonly record struct OverlayMemberChangeLine(string Key, string Title, string Detail, bool Update);

/// <summary>
/// Flood control for teammate changes (server, ship, place), as decided for the visor overlay:
/// <list type="bullet">
/// <item>one person's changes within 20 s merge into that person's line;</item>
/// <item>when more than 8 people changed within 30 s, only pinned people keep their own lines,
/// people on your server share one line that names the latest changes, and everyone else goes
/// into one count line;</item>
/// <item>shared lines are rewritten in place and start a new line at most every 30 s.</item>
/// </list>
/// Pure and clock-driven so it can be tested without the overlay.
/// </summary>
public sealed class OverlayMemberChangeFlood
{
    public static readonly TimeSpan MergeWindow = TimeSpan.FromSeconds(20);
    public static readonly TimeSpan SummaryWindow = TimeSpan.FromSeconds(30);
    public const int ManyPeople = 8;

    public const string SameServerKey = "member-flood:same-server";
    public const string OthersKey = "member-flood:others";

    private readonly Dictionary<string, (DateTimeOffset Started, List<string> Parts)> _people = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, DateTimeOffset> _recent = new(StringComparer.OrdinalIgnoreCase);
    private (DateTimeOffset Started, List<string> Parts)? _same;
    private (DateTimeOffset Started, Dictionary<OverlayMemberChangeKind, int> Counts)? _others;

    public static string KindTitle(OverlayMemberChangeKind kind, bool zh) => kind switch
    {
        OverlayMemberChangeKind.Server => zh ? "换服" : "Changed server",
        OverlayMemberChangeKind.Ship => zh ? "换船" : "Changed ship",
        _ => zh ? "位置变化" : "Moved",
    };

    public static string PersonKey(string personKey) => "member-flood:" + personKey;

    /// <param name="part">Short form without the name for a merged line, e.g. "换船 Cutlass Black".</param>
    /// <param name="detail">Full sentence for a line of its own, e.g. "Vega 换船：Cutlass Black".</param>
    public OverlayMemberChangeLine Add(
        DateTimeOffset now,
        string personKey,
        string name,
        bool pinned,
        bool sameServer,
        OverlayMemberChangeKind kind,
        string part,
        string detail,
        bool zh)
    {
        _recent[personKey] = now;
        foreach (var stale in _recent.Where(pair => now - pair.Value > SummaryWindow).Select(pair => pair.Key).ToArray())
            _recent.Remove(stale);
        var many = _recent.Count > ManyPeople;

        if (!many || pinned)
        {
            if (_people.TryGetValue(personKey, out var line) && now - line.Started <= MergeWindow)
            {
                line.Parts.Add(part);
                var title = zh ? $"{name} 的变化（{line.Parts.Count} 条）" : $"{name}: {line.Parts.Count} changes";
                return new(PersonKey(personKey), title, string.Join(" · ", line.Parts.TakeLast(3)), Update: true);
            }
            _people[personKey] = (now, [part]);
            return new(PersonKey(personKey), KindTitle(kind, zh), detail, Update: false);
        }

        if (sameServer)
        {
            var update = _same is { } same && now - same.Started <= SummaryWindow;
            if (!update) _same = (now, []);
            var parts = _same!.Value.Parts;
            parts.Add($"{name} {part}");
            var text = string.Join(" · ", parts.TakeLast(2)) +
                (parts.Count > 2 ? zh ? $" 等 {parts.Count} 条" : $" and {parts.Count - 2} more" : "");
            return new(SameServerKey, zh ? "同服成员" : "Your server", text, update);
        }

        var countsUpdate = _others is { } others && now - others.Started <= SummaryWindow;
        if (!countsUpdate) _others = (now, []);
        var counts = _others!.Value.Counts;
        counts[kind] = counts.GetValueOrDefault(kind) + 1;
        var summary = string.Join(" · ",
            new[] { OverlayMemberChangeKind.Place, OverlayMemberChangeKind.Ship, OverlayMemberChangeKind.Server }
                .Where(counts.ContainsKey)
                .Select(k => zh ? $"{counts[k]} 人{KindTitle(k, zh)}" : $"{counts[k]} {KindTitle(k, zh).ToLowerInvariant()}"));
        return new(OthersKey, zh ? "其他成员" : "Other members", (zh ? "另有 " : "Also ") + summary, countsUpdate);
    }

    /// <summary>A new scene or account: nothing collected so far may merge into its lines.</summary>
    public void Reset()
    {
        _people.Clear();
        _recent.Clear();
        _same = null;
        _others = null;
    }
}
