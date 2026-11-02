namespace StarBridge.Core.Presence;

/// <summary>
/// Public organization-member presence. Privacy choices are indistinguishable
/// from an ordinary offline member, including ordering before pagination.
/// This does not change the owner's status settings or friend presentation.
/// </summary>
public static class OrganizationMemberPresence
{
    public static PlayerPresenceKind Resolve(string? liveStatus, bool online)
    {
        if (!online) return PlayerPresenceKind.Offline;
        // Match the existing public organization vocabulary. Unknown values and
        // general-only aliases must not become online through a default policy.
        return liveStatus?.Trim().ToLowerInvariant() switch
        {
            "ingame" => PlayerPresenceKind.InGame,
            "apponline" or "online" => PlayerPresenceKind.AppOnline,
            "away" => PlayerPresenceKind.Away,
            _ => PlayerPresenceKind.Offline,
        };
    }

    public static bool IsOffline(string? liveStatus, bool online) =>
        Resolve(liveStatus, online) == PlayerPresenceKind.Offline;

    public static int SortRank(string? liveStatus, bool online) => Resolve(liveStatus, online) switch
    {
        PlayerPresenceKind.InGame => 0,
        PlayerPresenceKind.AppOnline or PlayerPresenceKind.Away => 1,
        _ => 2,
    };
}
