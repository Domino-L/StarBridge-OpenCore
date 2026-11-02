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
    bool ShowsPlaceholder)
{
    // Organization sources only; rooms keep their sentence layout.
    public OverlayOverviewFacts? Facts { get; init; }
}

/// <summary>
/// Projects an already-authorized, closed player set into the overview copy used by
/// every overlay renderer. Local self state is authoritative unless the scene is
/// a complete shared-fields-only privacy projection. It deliberately has no squad input:
/// fleet and party-room overviews are derived from presence plus the active scene context.
/// </summary>
internal static class OverlayOverviewProjection
{
    // User-facing shard wording lives only in this file; a Desktop test holds the rest of the client to it.
    internal static string ShardLabel(bool zh) => zh ? "分线" : "Shard";

    internal static string OtherShardsLabel(bool zh) => zh ? "其他分线" : "Other shards";

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
        var zh = language?.StartsWith("zh", StringComparison.OrdinalIgnoreCase) == true;
        if (hasFleet && players.Any(player => player.RealtimeStateUnknown))
            return new(sceneContext.Kind == OverlaySceneKind.PartyRoom ? zh ? "房间概况" : "PARTY OVERVIEW"
                    : zh ? "组织概况" : "ORGANIZATION OVERVIEW",
                zh ? "实时状态未知" : "Realtime status unknown",
                zh ? $"成员 {players.Length}" : $"Members {players.Length}", "—", "", "", "—", "",
                StatusPalette.DisabledBrush, [], ShowsPlaceholder: false);
        if (!hasFleet && sceneContext.Kind is OverlaySceneKind.Community or OverlaySceneKind.PartyRoom)
        {
            var organization = sceneContext.Kind == OverlaySceneKind.Community;
            var traditional = language is "zh-Hant" or "zh-TW";
            return new(organization ? zh ? "组织概况" : "ORGANIZATION OVERVIEW" : zh ? "房间概况" : "PARTY OVERVIEW",
                traditional ? organization ? "組織資訊暫不可用" : "房間資訊暫不可用"
                    : zh ? organization ? "组织信息暂不可用" : "房间信息暂不可用"
                    : organization ? "Organization information unavailable" : "Room information unavailable",
                "", "", "", "", "", "", StatusPalette.DisabledBrush, [], ShowsPlaceholder: true);
        }
        if (sceneContext.Kind == OverlaySceneKind.Community)
        {
            var organization = ProjectFleet(players, hasFleet, localPresence, localShard, language, zh, sceneContext.SharedFieldsOnly, sceneContext.LocalOwnPlace);
            return organization with
            {
                Title = zh ? "组织概况" : "ORGANIZATION OVERVIEW",
                Focus = players.Length == 0
                    ? zh ? "暂无可见成员" : "No visible members"
                    : organization.Focus
            };
        }
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
        bool zh,
        bool sharedFieldsOnly = false,
        string? localOwnPlace = null)
    {
        var online = players.Count(player =>
            PlayerPresence.IsOnline(ResolveFleetPresence(player, localPresence, sharedFieldsOnly)));
        var inGame = players.Count(player =>
            ResolveFleetPresence(player, localPresence, sharedFieldsOnly) == PlayerPresenceKind.InGame);
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
            zh,
            sharedFieldsOnly);
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
            ShowsPlaceholder: false)
        { Facts = ProjectFacts(players, localPresence, localShard, language, zh, sharedFieldsOnly, localOwnPlace) };
    }

    /// <summary>
    /// The same closed, authorized rows as facts. Organization totals follow the same
    /// rule as the rest of the overview: a shared-fields-only self row stays as shared.
    /// The viewer's own shard and place always come from local evidence, because that
    /// line and the "people on your shard" count only ever appear on their own screen.
    /// </summary>
    private static OverlayOverviewFacts ProjectFacts(
        IReadOnlyCollection<PlayerRow> players,
        PlayerPresenceKind localPresence,
        string? localShard,
        string? language,
        bool zh,
        bool sharedFieldsOnly,
        string? localOwnPlace)
    {
        PlayerPresenceKind Presence(PlayerRow player) => ResolveFleetPresence(player, localPresence, sharedFieldsOnly);
        string? Shard(PlayerRow player) => player.IsSelf && !sharedFieldsOnly ? localShard : player.ServerShard;
        var self = players.FirstOrDefault(player => player.IsSelf);
        var inGame = players.Where(player => Presence(player) == PlayerPresenceKind.InGame).ToArray();
        var viewerInGame = localPresence == PlayerPresenceKind.InGame;
        var localShardValid = PublicShardId.IsValid(localShard);
        var ownShardId = !viewerInGame ? null
            : localShardValid ? localShard
            : self is not null && !sharedFieldsOnly ? Shard(self) : null;
        // A self row hidden from the organization still counts on the viewer's own shard.
        var selfCountedOnOwnShard = self is not null && inGame.Contains(self) &&
            string.Equals(Shard(self)?.Trim(), ownShardId?.Trim(), StringComparison.OrdinalIgnoreCase);
        // A stale shared self row must not count the viewer a second time on another shard.
        var selfMovedAway = sharedFieldsOnly && viewerInGame && localShardValid && !selfCountedOnOwnShard;
        var shardRows = inGame
            .Where(player => !(player.IsSelf && selfMovedAway))
            .Select(player => (Shard(player), player.IsSelf && !sharedFieldsOnly ? (string?)null : player.ServerRegion));
        if (PublicShardId.IsValid(ownShardId) && !selfCountedOnOwnShard) shardRows = shardRows.Append((ownShardId, null));
        var shards = OverlayShardPresentation.Group(shardRows, ownShardId, zh);
        var ownPlace = !viewerInGame ? null
            : localOwnPlace ?? (self is not null && !sharedFieldsOnly && inGame.Contains(self) ? FleetLocationProjection.Resolve(self, language)?.DisplayName : null);
        var placeNames = inGame
            .Where(player => !player.IsSelf || localOwnPlace is null)
            .Select(player => FleetLocationProjection.Resolve(player, language))
            .Where(location => location.HasValue)
            .Select(location => location!.Value.DisplayName.Trim());
        if (localOwnPlace is not null) placeNames = placeNames.Append(localOwnPlace.Trim());
        var places = placeNames
            .GroupBy(name => name, StringComparer.OrdinalIgnoreCase)
            .Select(group => new OverlayOverviewPlace(group.Key, group.Count(),
                ownPlace is not null && group.Key.Equals(ownPlace.Trim(), StringComparison.OrdinalIgnoreCase)))
            .OrderByDescending(place => place.IsOwn)
            .ThenByDescending(place => place.Count)
            .ThenBy(place => place.Name, StringComparer.OrdinalIgnoreCase)
            .ToArray();
        return new OverlayOverviewFacts(
            players.Count(player => PlayerPresence.IsOnline(Presence(player))),
            players.Count,
            inGame.Length,
            players.Count(player => Presence(player) == PlayerPresenceKind.AppOnline),
            players.Count(player => Presence(player) == PlayerPresenceKind.Away),
            players.Count(player => !PlayerPresence.IsOnline(Presence(player))),
            ownPlace,
            shards.FirstOrDefault(shard => shard.IsOwn),
            shards,
            places,
            viewerInGame);
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
        var peers = players.Where(player => !player.IsSelf && player.SharedPresence == PlayerPresenceKind.InGame).ToArray();
        var hasCompleteServerEvidence = StarBridge.Core.Overlay.InformationOverlayServerEvidence.CanReportPeerCount(
            localPresence == PlayerPresenceKind.InGame, hasComparableLocalServer,
            peers.Length, peers.Count(player => FleetServerRelationship.IsRecognizedShard(player.ServerShard)));
        var sameShardSummary = !hasComparableLocalServer
            ? zh ? "你尚未进入服务器" : "You are not in a server"
            : !hasCompleteServerEvidence
                ? zh ? "同服务器人数待确认" : "Same-server count unavailable"
                : zh ? $"房间内与你同服务器 {Number(sameServer)} 人" : $"Room peers on your server {Number(sameServer)}";
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
                ? $"成员 {Number(memberCount)} / {(sceneContext.RoomCapacity > 0 ? Number(sceneContext.RoomCapacity) : "—")}"
                : $"Members {Number(memberCount)} / {(sceneContext.RoomCapacity > 0 ? Number(sceneContext.RoomCapacity) : "—")}",
            zh
                ? $"游戏中 {Number(inGame)} / {Number(memberCount)}"
                : $"In game {Number(inGame)} / {Number(memberCount)}",
            busiestServerSummary,
            string.Join("\n", new[] {
                string.Join(" · ", new[] { sceneContext.RoomTitle,
                    string.IsNullOrWhiteSpace(sceneContext.RoomHostDisplay) ? null : (zh ? "房主 " : "Host ") + sceneContext.RoomHostDisplay }
                    .Where(value => !string.IsNullOrWhiteSpace(value))),
                sceneContext.RoomGoal, sameShardSummary }.Where(value => !string.IsNullOrWhiteSpace(value))),
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
        bool zh,
        bool sharedFieldsOnly = false)
    {
        var busiest = players
            .Where(player => ResolveFleetPresence(player, localPresence, sharedFieldsOnly) == PlayerPresenceKind.InGame)
            .Select(player => ResolveServerRegionCode(player, localShard, sharedFieldsOnly))
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

    private static string? ResolveServerRegionCode(PlayerRow player, string? localShard, bool sharedFieldsOnly)
    {
        if (player.IsSelf && !sharedFieldsOnly)
        {
            return GameServerRegionPresentation.ResolvePreferredCode(localShard, player.ServerRegion);
        }

        return GameServerRegionPresentation.ResolvePreferredCode(
            player.ServerShard,
            player.ServerRegion);
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
        PlayerPresenceKind localPresence,
        bool sharedFieldsOnly = false) =>
        player.IsSelf && !sharedFieldsOnly
            ? localPresence
            : player.SharedPresence;

    private static string FormatLocation(OverlayOverviewLocationCount? location) =>
        location is null
            ? ""
            : location.Text;

    private static string Number(int value) =>
        value.ToString(CultureInfo.InvariantCulture);
}
