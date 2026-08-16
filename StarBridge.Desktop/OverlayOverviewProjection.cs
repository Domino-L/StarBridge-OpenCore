namespace StarBridge.Desktop;

using System.Globalization;
using System.Windows.Media;
using StarBridge.Core.Presence;

public sealed record OverlayOverviewLocationCount(
    string Key,
    string DisplayName,
    int Count,
    int OnlineCount = 0,
    string MetricText = "")
{
    public string CountRatioText => OnlineCount > 0
        ? $"{Count.ToString(CultureInfo.InvariantCulture)} / {OnlineCount.ToString(CultureInfo.InvariantCulture)}"
        : Count.ToString(CultureInfo.InvariantCulture);
    public string DisplayMetricText => string.IsNullOrWhiteSpace(MetricText)
        ? CountRatioText
        : MetricText;
    internal string Text => $"{DisplayName} {CountRatioText}";
}

internal sealed record OverlayOverviewProjectionResult(
    string Title,
    string Primary,
    string Summary,
    string ServerSummary,
    string Focus,
    string Secondary,
    string LocationPlaceholder,
    string LocationPlaceholderMetric,
    Brush StatusBrush,
    IReadOnlyList<OverlayOverviewLocationCount> TopLocations,
    bool ShowsPlaceholder);

/// <summary>
/// Projects an already-authorized, closed player set into the overview copy used by
/// every overlay renderer. The local presence argument is authoritative local state,
/// not the self row's outbound privacy projection. It deliberately has no squad input:
/// fleet and party-room overviews are derived from presence plus the active scene context.
/// </summary>
internal static class OverlayOverviewProjection
{
    internal static OverlayOverviewProjectionResult Project(
        IReadOnlyCollection<PlayerRow> closedPlayers,
        OverlaySceneContext sceneContext,
        bool hasFleet,
        PlayerPresenceKind localPresence,
        string? localShard,
        string? language)
    {
        ArgumentNullException.ThrowIfNull(closedPlayers);
        ArgumentNullException.ThrowIfNull(sceneContext);

        var players = closedPlayers as PlayerRow[] ?? closedPlayers.ToArray();
        var zh = language?.Equals("zh", StringComparison.OrdinalIgnoreCase) == true;
        return sceneContext.Kind == OverlaySceneKind.PartyRoom
            ? ProjectPartyRoom(players, sceneContext, localPresence, localShard, language, zh)
            : ProjectFleet(players, hasFleet, localPresence, localShard, language, zh);
    }

    private static OverlayOverviewProjectionResult ProjectFleet(
        IReadOnlyCollection<PlayerRow> players,
        bool hasFleet,
        PlayerPresenceKind localPresence,
        string? localShard,
        string? language,
        bool zh)
    {
        var online = players.Count(player =>
            PlayerPresence.IsOnline(ResolveFleetPresence(player, localPresence)));
        var inGame = players.Count(player =>
            ResolveFleetPresence(player, localPresence) == PlayerPresenceKind.InGame);
        var hasComparableLocalServer =
            localPresence == PlayerPresenceKind.InGame &&
            FleetServerRelationship.IsRecognizedShard(localShard);
        var sameServer = !hasComparableLocalServer
            ? 0
            : players.Count(player =>
                FleetServerRelationship.Resolve(
                    player.SharedPresence,
                    player.IsSelf,
                    player.ServerShard,
                    localPresence,
                    localShard) == FleetServerRelationshipKind.SameServer);
        var sameShardSummary = hasComparableLocalServer
            ? zh ? $"与你同分线 {Number(sameServer)} 人" : $"Same shard as you {Number(sameServer)}"
            : zh ? "你尚未进入服务器" : "You are not in a server";
        var busiestServerSummary = ProjectBusiestServerSummary(
            players,
            localPresence,
            localShard,
            inGame,
            zh);
        var topLocations = ProjectTopLocations(
            players,
            localPresence,
            localShard,
            hasComparableLocalServer,
            language,
            online,
            zh);

        if (!hasFleet)
        {
            return new OverlayOverviewProjectionResult(
                zh ? "舰队总览" : "FLEET OVERVIEW",
                zh ? "无舰队" : "No fleet",
                zh ? $"在线 {Number(online)}" : $"Online {Number(online)}",
                busiestServerSummary,
                zh ? "请先加入或创建组织" : "Join or create an organization first",
                "",
                "",
                "",
                StatusPalette.DisabledBrush,
                [],
                ShowsPlaceholder: true);
        }

        if (players.Count == 0)
        {
            return new OverlayOverviewProjectionResult(
                zh ? "\u8230\u961f\u603b\u89c8" : "FLEET OVERVIEW",
                zh ? "\u5728\u7ebf \u2014" : "Online —",
                zh ? "\u6e38\u620f\u4e2d \u2014" : "In game —",
                zh ? "\u4eba\u6570\u6700\u591a\u670d\u52a1\u5668 \u2014" : "Busiest server —",
                zh
                    ? "\u540c\u6b65\u540e\u5c06\u5728\u8fd9\u91cc\u663e\u793a\u5728\u7ebf\u3001\u6e38\u620f\u4e2d\u4e0e\u540c\u670d\u4fe1\u606f"
                    : "Fleet status will appear after synchronization",
                "",
                "",
                "",
                StatusPalette.DisabledBrush,
                [],
                ShowsPlaceholder: true);
        }

        return new OverlayOverviewProjectionResult(
            zh ? "舰队总览" : "FLEET OVERVIEW",
            zh
                ? $"在线 {Number(online)} / {Number(players.Count)}"
                : $"Online {Number(online)} / {Number(players.Count)}",
            zh
                ? $"游戏中 {Number(inGame)} / {Number(online)}"
                : $"In game {Number(inGame)} / {Number(online)}",
            busiestServerSummary,
            sameShardSummary,
            FormatLocation(topLocations.ElementAtOrDefault(1)),
            topLocations.Count == 0
                ? zh ? "暂无可显示地点" : "No visible locations"
                : "",
            topLocations.Count == 0
                ? zh
                    ? $"该地点 - / {Number(online)}"
                    : $"At location - / {Number(online)}"
                : "",
            ResolveStatusBrush(players, online),
            topLocations,
            ShowsPlaceholder: false);
    }

    private static OverlayOverviewProjectionResult ProjectPartyRoom(
        IReadOnlyCollection<PlayerRow> players,
        OverlaySceneContext sceneContext,
        PlayerPresenceKind localPresence,
        string? localShard,
        string? language,
        bool zh)
    {
        var memberCount = sceneContext.RoomMemberCount > 0
            ? sceneContext.RoomMemberCount
            : players.Count;
        var online = players.Count(player =>
            PlayerPresence.IsOnline(ResolveFleetPresence(player, localPresence)));
        var inGame = players.Count(player =>
            ResolveFleetPresence(player, localPresence) == PlayerPresenceKind.InGame);
        var hasComparableLocalServer =
            localPresence == PlayerPresenceKind.InGame &&
            FleetServerRelationship.IsRecognizedShard(localShard);
        var sameServer = !hasComparableLocalServer
            ? 0
            : players.Count(player =>
                FleetServerRelationship.Resolve(
                    player.SharedPresence,
                    player.IsSelf,
                    player.ServerShard,
                    localPresence,
                    localShard) == FleetServerRelationshipKind.SameServer);
        var sameShardSummary = hasComparableLocalServer
            ? zh ? $"与你同分线 {Number(sameServer)} 人" : $"Same shard as you {Number(sameServer)}"
            : zh ? "你尚未进入服务器" : "You are not in a server";
        var busiestServerSummary = ProjectBusiestServerSummary(
            players,
            localPresence,
            localShard,
            inGame,
            zh);
        var topLocations = ProjectTopLocations(
            players,
            localPresence,
            localShard,
            hasComparableLocalServer,
            language,
            online,
            zh);

        return new OverlayOverviewProjectionResult(
            zh ? "房间概况" : "PARTY OVERVIEW",
            zh
                ? $"在线 {Number(online)} / {Number(memberCount)}"
                : $"Online {Number(online)} / {Number(memberCount)}",
            zh
                ? $"游戏中 {Number(inGame)} / {Number(online)}"
                : $"In game {Number(inGame)} / {Number(online)}",
            busiestServerSummary,
            sameShardSummary,
            FormatLocation(topLocations.ElementAtOrDefault(1)),
            topLocations.Count == 0
                ? zh ? "暂无可显示地点" : "No visible locations"
                : "",
            topLocations.Count == 0
                ? zh
                    ? $"该地点 - / {Number(online)}"
                    : $"At location - / {Number(online)}"
                : "",
            ResolveStatusBrush(players, online),
            topLocations,
            ShowsPlaceholder: false);
    }

    private static IReadOnlyList<OverlayOverviewLocationCount> ProjectTopLocations(
        IReadOnlyCollection<PlayerRow> players,
        PlayerPresenceKind localPresence,
        string? localShard,
        bool hasComparableLocalServer,
        string? language,
        int onlineCount,
        bool zh)
    {
        var locations = players
            .Where(player =>
                player.SharedPresence == PlayerPresenceKind.InGame &&
                (!hasComparableLocalServer ||
                 player.IsSelf ||
                 FleetServerRelationship.Resolve(
                     player.SharedPresence,
                     player.IsSelf,
                     player.ServerShard,
                     localPresence,
                     localShard) == FleetServerRelationshipKind.SameServer))
            .Select(player => FleetLocationProjection.Resolve(player, language))
            .Where(location => location.HasValue)
            .Select(location => location!.Value)
            // Runtime aliases can carry different source keys while resolving to
            // the same user-visible place (for example inventory and quantum
            // identifiers for New Babbage). The overview must not render those
            // aliases as two locations.
            .GroupBy(location => location.DisplayName.Trim(), StringComparer.OrdinalIgnoreCase)
            .Select(group => new OverlayOverviewLocationCount(
                group
                    .Select(location => location.Key)
                    .OrderBy(key => key, StringComparer.OrdinalIgnoreCase)
                    .First(),
                group.Key,
                group.Count(),
                onlineCount,
                zh
                    ? $"该地点 {Number(group.Count())} / {Number(onlineCount)}"
                    : $"At location {Number(group.Count())} / {Number(onlineCount)}"))
            .OrderByDescending(location => location.Count)
            .ThenBy(location => location.DisplayName, StringComparer.OrdinalIgnoreCase)
            .Take(2)
            .ToArray();
        return locations;
    }

    private static string ProjectBusiestServerSummary(
        IReadOnlyCollection<PlayerRow> players,
        PlayerPresenceKind localPresence,
        string? localShard,
        int inGame,
        bool zh)
    {
        var busiest = players
            .Where(player => ResolveFleetPresence(player, localPresence) == PlayerPresenceKind.InGame)
            .Select(player => ResolveServerRegionCode(player, localShard))
            .Where(region => !string.IsNullOrWhiteSpace(region))
            .Select(region => region!)
            .GroupBy(region => region, StringComparer.OrdinalIgnoreCase)
            .Select(group => new
            {
                Code = group.Key,
                Count = group.Count()
            })
            .OrderByDescending(server => server.Count)
            .ThenBy(server => server.Code, StringComparer.OrdinalIgnoreCase)
            .FirstOrDefault();

        if (busiest is not null)
        {
            var displayName = FormatOverviewRegionCode(busiest.Code, zh);
            return zh
                ? $"{displayName} · {Number(busiest.Count)} 人"
                : $"{displayName} · {Number(busiest.Count)}";
        }

        return inGame == 0
            ? zh ? "无人处于游戏中" : "No one is in game"
            : zh ? "暂无服务器区域" : "No server region data";
    }

    private static string? ResolveServerRegionCode(PlayerRow player, string? localShard)
    {
        if (player.IsSelf)
        {
            return GameServerRegionPresentation.ResolveCode(localShard);
        }

        return GameServerRegionPresentation.ResolveCode(player.ServerRegion) ??
               GameServerRegionPresentation.ResolveCode(player.ServerShard);
    }

    private static string FormatOverviewRegionCode(string code, bool zh) => code switch
    {
        "US" => zh ? "美服" : "US",
        "EU" => zh ? "欧服" : "EU",
        "AU" => zh ? "澳服" : "Australia",
        "ASIA" => zh ? "亚服" : "Asia",
        _ => code
    };

    private static Brush ResolveStatusBrush(IReadOnlyCollection<PlayerRow> players, int online)
    {
        if (players.Count == 0 || online == 0)
        {
            return StatusPalette.DisabledBrush;
        }

        return online == players.Count
            ? StatusPalette.SuccessBrush
            : StatusPalette.InfoBrush;
    }

    private static PlayerPresenceKind ResolveFleetPresence(
        PlayerRow player,
        PlayerPresenceKind localPresence) =>
        player.IsSelf
            ? localPresence
            : player.SharedPresence;

    private static string FormatLocation(OverlayOverviewLocationCount? location) =>
        location is null
            ? ""
            : location.Text;

    private static string Number(int value) =>
        value.ToString(CultureInfo.InvariantCulture);
}
