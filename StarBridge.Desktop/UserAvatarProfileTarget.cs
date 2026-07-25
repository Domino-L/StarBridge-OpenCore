namespace StarBridge.Desktop;

internal sealed record UserAvatarProfileTarget(
    string? AccountId,
    string GameId,
    string? Callsign,
    string? AvatarPath,
    string Status,
    bool IsSelf,
    string MessageOrigin);

internal static class UserAvatarProfileTargetResolver
{
    public static UserAvatarProfileTarget? Resolve(object? source) => source switch
    {
        PlayerRow player => new(
            player.AccountId,
            player.Name,
            player.Callsign,
            player.AvatarPath,
            player.PresenceText,
            player.IsSelf,
            StarBridge.Core.Friends.DirectMessageOrigins.FleetMember),
        SquadMemberStatusRow member => new(
            member.AccountId,
            member.GameId,
            member.Callsign,
            member.AvatarPath,
            member.PresenceText,
            member.IsSelf,
            StarBridge.Core.Friends.DirectMessageOrigins.SquadMember),
        MemberAvatarRow member => new(
            member.AccountId,
            member.GameId,
            member.Callsign ?? member.Name,
            member.AvatarPath,
            member.PresenceText,
            member.IsSelf,
            StarBridge.Core.Friends.DirectMessageOrigins.FleetMember),
        PartyLobbyMemberPreview member => new(
            member.AccountId,
            member.GameId,
            member.Callsign,
            member.AvatarImageData,
            member.PresenceText,
            false,
            StarBridge.Core.Friends.DirectMessageOrigins.PartyRoom),
        PartyLobbyJoinApplicationView application => new(
            application.AccountId,
            application.GameId,
            application.Callsign,
            application.AvatarImageData,
            "离线",
            false,
            StarBridge.Core.Friends.DirectMessageOrigins.PartyRoom),
        FleetMemberManagementRow member => new(
            member.AccountId,
            member.GameName,
            member.Callsign,
            member.AvatarPath,
            member.PresenceText,
            member.IsSelf,
            StarBridge.Core.Friends.DirectMessageOrigins.FleetMember),
        FriendCenterRow friend => new(
            friend.AccountId,
            friend.GameId,
            friend.Callsign,
            friend.AvatarSource,
            friend.PresenceText,
            false,
            StarBridge.Core.Friends.DirectMessageOrigins.FriendCenter),
        FleetChatMessageRow message => new(
            message.AccountId,
            message.SenderGameId,
            message.SenderCallsign,
            message.SenderAvatarImageData,
            "离线",
            message.IsSelf,
            StarBridge.Core.Friends.DirectMessageOrigins.FleetMember),
        FriendChatMessageRow message => new(
            message.AccountId,
            message.SenderGameId,
            message.SenderCallsign,
            message.SenderAvatarImageData,
            "离线",
            message.IsSelf,
            StarBridge.Core.Friends.DirectMessageOrigins.FriendCenter),
        PartyRoomChatMessageView message when !message.IsSystem => new(
            message.AccountId,
            message.SenderGameId,
            message.SenderCallsign,
            message.SenderAvatarImageData,
            "离线",
            message.IsSelf,
            StarBridge.Core.Friends.DirectMessageOrigins.PartyRoom),
        _ => null
    };
}

internal static class UserAvatarProfileIdentityPolicy
{
    public static string? PreserveKnownPublicId(string? incomingPublicId, string? existingPublicId)
    {
        var incoming = incomingPublicId?.Trim();
        if (!string.IsNullOrWhiteSpace(incoming))
        {
            return incoming;
        }

        var existing = existingPublicId?.Trim();
        return string.IsNullOrWhiteSpace(existing) ? null : existing;
    }
}
