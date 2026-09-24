namespace StarBridge.Core.Friends;

[Flags]
public enum FriendSharedFields
{
    None = 0,
    Presence = 1,
    ServerRelation = 2,
    ServerDetails = 4,
    Ship = 8,
    Location = 16,
    LastOnline = 32,
    All = 63
}

/// <summary>Suggestions are not authorization. Persist only an explicit account choice.</summary>
public sealed record FriendSharingPreferences(FriendSharedFields Fields)
{
    public static FriendSharingPreferences Disabled => new(FriendSharedFields.None);
    public static FriendSharingPreferences Suggested => new(
        FriendSharedFields.Presence | FriendSharedFields.ServerRelation | FriendSharedFields.LastOnline);

    public FriendSharingPreferences Validate()
    {
        if ((Fields & ~FriendSharedFields.All) != 0)
            throw new ArgumentOutOfRangeException(nameof(Fields));
        return this;
    }
}

/// <summary>
/// Authoritative input, never a viewer-authored request. ObservedAt is the
/// server receipt time. LastOnlineAt is an independently maintained last-seen
/// timestamp, not the profile edit time or this response's refresh time.
/// </summary>
public sealed record FriendSharingSource(
    DateTimeOffset ObservedAt,
    string? Presence,
    string? ServerId,
    string? ServerRegion,
    string? Ship,
    string? Location,
    bool ServerConfirmed,
    bool ShipConfirmed,
    bool LocationConfirmed,
    DateTimeOffset? LastOnlineAt);

public sealed record FriendSharedView(
    string? Presence = null,
    bool? SameServer = null,
    string? ServerId = null,
    string? ServerRegion = null,
    string? Ship = null,
    string? Location = null,
    DateTimeOffset? LastOnlineAt = null);

public static class FriendSharingPolicy
{
    public static readonly TimeSpan LiveLease = TimeSpan.FromSeconds(45);

    /// <summary>
    /// Friendship, block state, global consent and visibility must be resolved
    /// by the authenticated owner. No organization/room permission is inherited.
    /// A null preference never enables the suggested defaults.
    /// </summary>
    public static FriendSharedView Project(
        FriendSharingPreferences? preferences,
        FriendSharingSource? source,
        bool acceptedFriend,
        bool blocked,
        bool sharingActive,
        string? viewerCurrentServerId,
        DateTimeOffset now)
    {
        if (!acceptedFriend || blocked || !sharingActive || preferences is null || source is null)
            return new();
        var fields = preferences.Validate().Fields;
        bool Has(FriendSharedFields field) => (fields & field) != 0;
        var fresh = source.ObservedAt <= now && now - source.ObservedAt <= LiveLease;
        var presence = fresh && source.Presence is "AppOnline" or "InGame" or "Away" or "Offline"
            ? source.Presence : null;
        var playing = presence == "InGame";
        var server = playing && source.ServerConfirmed ? Known(source.ServerId) : null;
        var viewerServer = Known(viewerCurrentServerId);
        return new(
            Presence: Has(FriendSharedFields.Presence) ? presence : null,
            SameServer: Has(FriendSharedFields.ServerRelation) && server is not null && viewerServer is not null
                ? string.Equals(server, viewerServer, StringComparison.Ordinal) : null,
            ServerId: Has(FriendSharedFields.ServerDetails) ? server : null,
            ServerRegion: Has(FriendSharedFields.ServerDetails) && server is not null ? Known(source.ServerRegion) : null,
            Ship: Has(FriendSharedFields.Ship) && playing && source.ShipConfirmed ? Known(source.Ship) : null,
            Location: Has(FriendSharedFields.Location) && server is not null && source.LocationConfirmed ? Known(source.Location) : null,
            LastOnlineAt: Has(FriendSharedFields.LastOnline) && source.LastOnlineAt > DateTimeOffset.MinValue &&
                source.LastOnlineAt <= now ? source.LastOnlineAt : null);
    }

    private static string? Known(string? value) =>
        string.IsNullOrWhiteSpace(value) || value.Equals("Unknown", StringComparison.OrdinalIgnoreCase)
            ? null : value;
}
