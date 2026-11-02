namespace StarBridge.Desktop;

using StarBridge.Core.Presence;

internal enum FleetServerRelationshipKind
{
    NotInGame,
    InGame,
    SameServer,
    DifferentServer
}

/// <summary>
/// Resolves the actionable relationship between a visible fleet member and the
/// local player's server. Returns only the relationship; the overlay overview's
/// short shard form comes from OverlayShardPresentation.
/// </summary>
internal static class FleetServerRelationship
{
    internal static FleetServerRelationshipKind Resolve(
        PlayerPresenceKind memberPresence,
        bool isSelf,
        string? memberShard,
        PlayerPresenceKind localPresence,
        string? localShard)
    {
        if (memberPresence != PlayerPresenceKind.InGame)
        {
            return FleetServerRelationshipKind.NotInGame;
        }

        if (isSelf ||
            localPresence != PlayerPresenceKind.InGame ||
            !IsRecognizedShard(memberShard) ||
            !IsRecognizedShard(localShard))
        {
            return FleetServerRelationshipKind.InGame;
        }

        return memberShard!.Trim().Equals(localShard!.Trim(), StringComparison.OrdinalIgnoreCase)
            ? FleetServerRelationshipKind.SameServer
            : FleetServerRelationshipKind.DifferentServer;
    }

    internal static string Format(FleetServerRelationshipKind relationship, bool zh) =>
        relationship switch
        {
            FleetServerRelationshipKind.NotInGame => zh ? "未进入游戏" : "Not in game",
            FleetServerRelationshipKind.InGame => zh ? "游戏中" : "In game",
            FleetServerRelationshipKind.SameServer => zh ? "同服务器" : "Same server",
            _ => zh ? "不同服务器" : "Different server"
        };

    internal static bool IsRecognizedShard(string? value) =>
        PlayerSessionStatePresentation.HasRecognizedValue(value);
}
