namespace StarBridge.Core.Friends;

public static class FriendRelationshipStates
{
    public const string None = "none";
    public const string Friend = "friend";
    public const string Incoming = "incoming";
    public const string Outgoing = "outgoing";
    public const string Blocked = "blocked";
}

public static class FriendActions
{
    public const string Send = "send";
    public const string Accept = "accept";
    public const string Reject = "reject";
    public const string Cancel = "cancel";
    public const string Remove = "remove";
    public const string Block = "block";
    public const string Unblock = "unblock";
}

public sealed record FriendUserContract(
    string AccountId,
    string Callsign,
    string GameId,
    string? AvatarImageData,
    string Presence,
    string RelationshipState,
    DateTimeOffset LastUpdated);

public sealed record FriendEntryContract(
    FriendUserContract User,
    DateTimeOffset RelationshipUpdatedAt);

public sealed record FriendCenterSnapshotContract(
    FriendEntryContract[] Friends,
    FriendEntryContract[] IncomingRequests,
    FriendEntryContract[] OutgoingRequests,
    FriendEntryContract[] BlockedUsers,
    DateTimeOffset RefreshedAt);

public sealed record FriendSearchResponseContract(
    FriendUserContract[] Results);

public sealed record FriendActionRequestContract(
    string Action,
    string TargetAccountId,
    bool IncludePresence = true);
