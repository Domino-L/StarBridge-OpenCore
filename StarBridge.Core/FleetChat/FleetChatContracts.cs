using System.Security.Cryptography;
using StarBridge.Core.Chat;

namespace StarBridge.Core.FleetChat;

public static class FleetChatChannelTypes
{
    public const string Fleet = "fleet";
}

public static class FleetChatIdentity
{
    public static string NormalizeFleetCode(string? fleetCode) =>
        (fleetCode ?? "").Trim().ToUpperInvariant();

    public static string FleetChannelId(string? fleetCode) =>
        $"fleet:{NormalizeFleetCode(fleetCode)}";
}

public sealed record FleetChatChannelContract(
    string ChannelId,
    string Type,
    string DisplayName,
    int UnreadCount,
    long LatestSequence,
    string LastMessagePreview,
    DateTimeOffset? LastMessageAt,
    bool CanSend);

public sealed record FleetChatChannelListContract(
    FleetChatChannelContract[] Channels,
    int TotalUnread,
    DateTimeOffset ServerTime);

public sealed record FleetChatMessageContract(
    long Sequence,
    string MessageId,
    string ChannelId,
    string SenderAccountId,
    string SenderCallsign,
    string SenderGameId,
    string SenderRoleTitle,
    string SenderRoleColor,
    string? SenderAvatarImageData,
    string Text,
    DateTimeOffset CreatedAt,
    ChatAttachmentContract? Attachment = null);

public sealed record FleetChatHistoryContract(
    string ChannelId,
    FleetChatMessageContract[] Messages,
    long LatestSequence,
    DateTimeOffset ServerTime,
    bool CanSend,
    string? Error = null,
    bool HasOlder = false,
    long OldestSequence = 0);

public sealed record FleetChatSendRequestContract(
    string FleetCode,
    string ChannelId,
    string Text,
    string ClientMessageId,
    ChatAttachmentContract? Attachment = null);

public sealed record FleetChatMutationResponseContract(
    FleetChatMessageContract? Message,
    string? Error = null,
    string? Status = null);

public sealed record FleetChatMarkReadRequestContract(
    string FleetCode,
    string ChannelId,
    long ThroughSequence);

public sealed record FleetChatMarkReadResponseContract(
    string ChannelId,
    long ReadThroughSequence);
