namespace StarBridge.Desktop;

using StarBridge.Core.Presence;

/// <summary>One shard (or, without a shard id, one region) and how many visible members are on it.</summary>
public sealed record OverlayOverviewShard(string Id, string Label, int Count, bool IsOwn);

public sealed record OverlayOverviewPlace(string Name, int Count, bool IsOwn);

/// <summary>
/// The organization overview as facts rather than sentences, so the renderer
/// can show more or less of them as the module grows or shrinks. Counts cover
/// only the already-authorized rows the viewer received.
/// </summary>
public sealed record OverlayOverviewFacts(
    int Online,
    int Total,
    int InGame,
    int AppOnline,
    int Away,
    int Offline,
    string? OwnPlace,
    OverlayOverviewShard? OwnShard,
    IReadOnlyList<OverlayOverviewShard> Shards,
    IReadOnlyList<OverlayOverviewPlace> Places,
    bool ViewerInGame);

internal static class OverlayShardPresentation
{
    /// <summary>"欧服 #040": the region word players use plus the shard number they read.</summary>
    internal static string? Label(string? shard, bool zh)
    {
        if (!PublicShardId.TryParse(shard, out var parsed)) return null;
        var region = GameServerRegionPresentation.ResolveRegion(parsed.Id, zh) ?? parsed.Region.ToUpperInvariant();
        return region + " #" + parsed.Tail;
    }

    /// <summary>
    /// Groups in-game rows by shard; rows that shared only a region fall into a
    /// region group. Labels that collide (same region and number on different
    /// game versions) get the version suffix so they stay tellable apart.
    /// </summary>
    internal static IReadOnlyList<OverlayOverviewShard> Group(
        IEnumerable<(string? Shard, string? Region)> rows, string? ownShard, bool zh)
    {
        var groups = new Dictionary<string, (string Label, int Count, string? Instance)>(StringComparer.OrdinalIgnoreCase);
        foreach (var (shard, region) in rows)
        {
            string id, label; string? instance = null;
            if (PublicShardId.TryParse(shard, out var parsed))
            {
                id = parsed.Id; label = Label(parsed.Id, zh)!; instance = parsed.Instance;
            }
            else
            {
                var code = GameServerRegionPresentation.ResolvePreferredCode(shard, region);
                if (code is null) continue;
                id = "region:" + code; label = GameServerRegionPresentation.ResolveRegion(code, zh) ?? code;
            }
            groups[id] = groups.TryGetValue(id, out var existing)
                ? (existing.Label, existing.Count + 1, existing.Instance)
                : (label, 1, instance);
        }
        var byLabel = groups.GroupBy(pair => pair.Value.Label, StringComparer.OrdinalIgnoreCase)
            .Where(group => group.Count() > 1)
            .SelectMany(group => group.Select(pair => pair.Key))
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        var own = PublicShardId.TryParse(ownShard, out var ownParsed) ? ownParsed.Id : null;
        var ownRegion = own is null ? null : GameServerRegionPresentation.ResolveCode(ownParsed.Id);
        string RegionOf(string id) => id.StartsWith("region:", StringComparison.Ordinal) ? id[7..] : GameServerRegionPresentation.ResolveCode(id) ?? "";
        return groups
            .Select(pair => new OverlayOverviewShard(pair.Key,
                byLabel.Contains(pair.Key) && pair.Value.Instance is { } version && version.Length > 0
                    ? pair.Value.Label + " (" + version[Math.Max(0, version.Length - 4)..] + ")"
                    : pair.Value.Label,
                pair.Value.Count,
                own is not null && pair.Key.Equals(own, StringComparison.OrdinalIgnoreCase)))
            .OrderByDescending(shard => shard.IsOwn)
            .ThenBy(shard => shard.Id.StartsWith("region:", StringComparison.Ordinal))
            .ThenBy(shard => ownRegion is not null && RegionOf(shard.Id) == ownRegion ? 0 : 1)
            .ThenBy(shard => RegionOf(shard.Id), StringComparer.Ordinal)
            .ThenByDescending(shard => shard.Count)
            .ThenBy(shard => shard.Label, StringComparer.OrdinalIgnoreCase)
            .ToArray();
    }
}
