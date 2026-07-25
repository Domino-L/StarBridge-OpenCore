using StarBridge.Core.Chat;

namespace StarBridge.Core.Friends;

public static class DirectMessageConversationStates
{
    public const string None = "none";
    public const string Friend = "friend";
    public const string RequestIncoming = "request_incoming";
    public const string RequestOutgoing = "request_outgoing";
    public const string Accepted = "accepted";
}

public static class DirectMessageRequestActions
{
    public const string Accept = "accept";
    public const string Reject = "reject";
    public const string Block = "block";
}

public static class DirectMessageOrigins
{
    public const string Unknown = "unknown";
    public const string PersonalProfile = "personal_profile";
    public const string FriendCenter = "friend_center";
    public const string FleetMember = "fleet_member";
    public const string SquadMember = "squad_member";
    public const string PartyRoom = "party_room";

    public static string Normalize(string? value) => value?.Trim().ToLowerInvariant() switch
    {
        PersonalProfile => PersonalProfile,
        FriendCenter => FriendCenter,
        FleetMember => FleetMember,
        SquadMember => SquadMember,
        PartyRoom => PartyRoom,
        _ => Unknown
    };
}

public sealed record DirectMessagePrivacyContract(
    bool FriendsOnly,
    DateTimeOffset UpdatedAt);

public sealed record DirectMessagePrivacyUpdateRequestContract(
    bool FriendsOnly);

public sealed record DirectMessageContextContract(
    string Origin,
    string? SharedFleetName = null,
    string? SharedRoomTitle = null);

public sealed record DirectMessageRequestActionContract(
    string TargetAccountId,
    string Action);

public sealed record DirectMessageRequestActionResponseContract(
    string TargetAccountId,
    string ConversationState);

public sealed record FriendChatMessageContract(
    long Sequence,
    string MessageId,
    string SenderAccountId,
    string RecipientAccountId,
    string Text,
    DateTimeOffset CreatedAt,
    ChatAttachmentContract? Attachment = null);

public sealed record FriendChatConversationContract(
    FriendUserContract User,
    string LastMessagePreview,
    DateTimeOffset LastMessageAt,
    string LastSenderAccountId,
    int UnreadCount,
    long LatestSequence,
    string ConversationState = DirectMessageConversationStates.Friend,
    DirectMessageContextContract? Context = null);

public sealed record FriendChatConversationListContract(
    FriendChatConversationContract[] Conversations,
    int TotalUnread,
    DateTimeOffset ServerTime);

public sealed record FriendChatHistoryContract(
    string TargetAccountId,
    FriendChatMessageContract[] Messages,
    long LatestSequence,
    DateTimeOffset ServerTime,
    bool CanSend,
    string? Error = null,
    string ConversationState = DirectMessageConversationStates.Friend,
    DirectMessageContextContract? Context = null,
    bool HasOlder = false,
    long OldestSequence = 0);

public sealed record FriendChatSendRequestContract(
    string TargetAccountId,
    string Text,
    string ClientMessageId,
    string Origin = DirectMessageOrigins.Unknown,
    ChatAttachmentContract? Attachment = null);

public sealed record FriendChatMutationResponseContract(
    FriendChatMessageContract? Message,
    string? Error = null,
    string? Status = null);

public sealed record FriendChatMarkReadRequestContract(
    string TargetAccountId,
    long ThroughSequence);

public sealed record FriendChatMarkReadResponseContract(
    string TargetAccountId,
    long ReadThroughSequence);
