using StarBridge.Core.Friends;
using StarBridge.Core.Chat;
using StarBridge.Core.Presence;
using System.ComponentModel;
using System.Windows;
using System.Windows.Media;

namespace StarBridge.Desktop;

internal enum FriendCenterSection
{
    Conversations,
    Friends,
    Incoming,
    Outgoing,
    Blocked,
    Search
}

internal static class FriendCenterAvatarResolver
{
    public static FriendUserContract Resolve(
        FriendUserContract user,
        IEnumerable<NetworkPlayerSnapshot> playerSnapshots)
    {
        if (!string.IsNullOrWhiteSpace(user.AvatarImageData))
        {
            return user;
        }

        var candidates = !string.IsNullOrWhiteSpace(user.AccountId)
            ? playerSnapshots.Where(snapshot =>
                !string.IsNullOrWhiteSpace(snapshot.AccountId) &&
                snapshot.AccountId.Equals(user.AccountId, StringComparison.OrdinalIgnoreCase))
            : playerSnapshots.Where(snapshot =>
                !string.IsNullOrWhiteSpace(user.GameId) &&
                snapshot.Name.Equals(user.GameId, StringComparison.OrdinalIgnoreCase));
        var avatarImageData = candidates
            .OrderByDescending(snapshot => snapshot.LastUpdated)
            .Select(snapshot => snapshot.AvatarImageData)
            .FirstOrDefault(value => !string.IsNullOrWhiteSpace(value));
        return string.IsNullOrWhiteSpace(avatarImageData)
            ? user
            : user with { AvatarImageData = avatarImageData };
    }
}

internal sealed record FriendCenterRow(FriendUserContract User, DateTimeOffset RelationshipUpdatedAt)
{
    public string AccountId => User.AccountId;
    public string Callsign => User.Callsign;
    public string GameId => User.GameId;
    public string? AvatarSource => User.AvatarImageData;
    public string Initials => GetInitials(string.IsNullOrWhiteSpace(Callsign) ? GameId : Callsign);
    public PlayerPresenceKind Presence => PlayerPresencePresentation.ResolveShared(User.Presence, User.Presence);
    public string PresenceText => PlayerPresencePresentation.Format(Presence);
    public System.Windows.Media.Brush PresenceBrush => PlayerPresencePresentation.Brush(Presence);
    public string RelationshipText => User.RelationshipState switch
    {
        FriendRelationshipStates.Friend => "好友",
        FriendRelationshipStates.Incoming => "收到的申请",
        FriendRelationshipStates.Outgoing => "等待对方接受",
        FriendRelationshipStates.Blocked => "已屏蔽",
        _ => "未添加"
    };

    public string PrimaryAction => User.RelationshipState switch
    {
        FriendRelationshipStates.Friend => "profile",
        FriendRelationshipStates.Incoming => FriendActions.Accept,
        FriendRelationshipStates.Outgoing => FriendActions.Cancel,
        FriendRelationshipStates.Blocked => FriendActions.Unblock,
        _ => FriendActions.Send
    };

    public string PrimaryActionText => User.RelationshipState switch
    {
        FriendRelationshipStates.Friend => "查看资料",
        FriendRelationshipStates.Incoming => "接受",
        FriendRelationshipStates.Outgoing => "撤回申请",
        FriendRelationshipStates.Blocked => "解除屏蔽",
        _ => "添加好友"
    };

    public string? SecondaryAction => User.RelationshipState switch
    {
        FriendRelationshipStates.Friend => FriendActions.Remove,
        FriendRelationshipStates.Incoming => FriendActions.Reject,
        _ => null
    };

    public string SecondaryActionText => User.RelationshipState switch
    {
        FriendRelationshipStates.Friend => "删除好友",
        FriendRelationshipStates.Incoming => "拒绝",
        _ => ""
    };

    public Visibility SecondaryActionVisibility => SecondaryAction is null ? Visibility.Collapsed : Visibility.Visible;
    public Visibility ChatActionVisibility => User.RelationshipState == FriendRelationshipStates.Friend
        ? Visibility.Visible
        : Visibility.Collapsed;
    public Visibility BlockActionVisibility => User.RelationshipState == FriendRelationshipStates.Blocked
        ? Visibility.Collapsed
        : Visibility.Visible;

    private static string GetInitials(string value)
    {
        var trimmed = value.Trim();
        if (trimmed.Length == 0)
        {
            return "?";
        }

        var parts = trimmed.Split([' ', '_', '-'], StringSplitOptions.RemoveEmptyEntries);
        return parts.Length >= 2
            ? string.Concat(parts[0][0], parts[1][0]).ToUpperInvariant()
            : trimmed[..Math.Min(2, trimmed.Length)].ToUpperInvariant();
    }
}

internal sealed record FriendChatConversationRow(FriendChatConversationContract Conversation) : INotifyPropertyChanged
{
    private string _updatedAtText = CommunicationTimeFormatter.Format(Conversation.LastMessageAt);
    public event PropertyChangedEventHandler? PropertyChanged;
    public FriendUserContract User => Conversation.User;
    public string AccountId => User.AccountId;
    public string Callsign => User.Callsign;
    public string? AvatarSource => User.AvatarImageData;
    public string Initials => GetInitials(string.IsNullOrWhiteSpace(Callsign) ? User.GameId : Callsign);
    public PlayerPresenceKind Presence => PlayerPresencePresentation.ResolveShared(User.Presence, User.Presence);
    public string PresenceText => PlayerPresencePresentation.Format(Presence);
    public System.Windows.Media.Brush PresenceBrush => PlayerPresencePresentation.Brush(Presence);
    public string Preview => string.IsNullOrWhiteSpace(Conversation.LastMessagePreview)
        ? "开始一段私聊"
        : Conversation.LastSenderAccountId.Equals(AccountId, StringComparison.OrdinalIgnoreCase)
            ? Conversation.LastMessagePreview
            : $"你：{Conversation.LastMessagePreview}";
    public string UpdatedAtText => _updatedAtText;
    public string UnreadText => Conversation.UnreadCount > 99 ? "99+" : Conversation.UnreadCount.ToString();
    public Visibility UnreadVisibility => Conversation.UnreadCount > 0 ? Visibility.Visible : Visibility.Collapsed;
    public string ConversationStateText => DirectMessagePresentation.FormatState(Conversation.ConversationState);
    public string ContextText => DirectMessagePresentation.FormatContext(Conversation.Context);
    public Visibility RequestBadgeVisibility => Conversation.ConversationState is
        DirectMessageConversationStates.RequestIncoming or DirectMessageConversationStates.RequestOutgoing
            ? Visibility.Visible
            : Visibility.Collapsed;

    public void RefreshTime(DateTimeOffset now)
    {
        var next = CommunicationTimeFormatter.Format(Conversation.LastMessageAt, now);
        if (string.Equals(_updatedAtText, next, StringComparison.Ordinal))
        {
            return;
        }

        _updatedAtText = next;
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(UpdatedAtText)));
    }

    private static string GetInitials(string value)
    {
        var trimmed = value.Trim();
        if (trimmed.Length == 0)
        {
            return "?";
        }

        var parts = trimmed.Split([' ', '_', '-'], StringSplitOptions.RemoveEmptyEntries);
        return parts.Length >= 2
            ? string.Concat(parts[0][0], parts[1][0]).ToUpperInvariant()
            : trimmed[..Math.Min(2, trimmed.Length)].ToUpperInvariant();
    }
}

internal static class DirectMessagePresentation
{
    public static string FormatState(string? state) => state switch
    {
        DirectMessageConversationStates.RequestIncoming => "消息请求",
        DirectMessageConversationStates.RequestOutgoing => "等待接受",
        DirectMessageConversationStates.Accepted => "已接受的私信",
        DirectMessageConversationStates.Friend => "好友私信",
        _ => "新私信"
    };

    public static string FormatContext(DirectMessageContextContract? context)
    {
        if (context is null)
        {
            return "";
        }

        var parts = new List<string>();
        if (!string.IsNullOrWhiteSpace(context.SharedFleetName))
        {
            parts.Add($"同舰队 · {context.SharedFleetName}");
        }
        if (!string.IsNullOrWhiteSpace(context.SharedRoomTitle))
        {
            parts.Add($"同房间 · {context.SharedRoomTitle}");
        }

        parts.Add(context.Origin switch
        {
            DirectMessageOrigins.PersonalProfile => "通过个人资料发起",
            DirectMessageOrigins.FriendCenter => "通过好友中心发起",
            DirectMessageOrigins.FleetMember => "通过舰队成员发起",
            DirectMessageOrigins.SquadMember => "通过小队成员发起",
            DirectMessageOrigins.PartyRoom => "通过组队房间发起",
            _ => "通过玩家入口发起"
        });
        return string.Join("   ", parts);
    }
}

internal static class DirectMessagePrivacyAvailabilityPolicy
{
    public static bool CanConfigure(bool isLoggedIn, bool canSynchronizeUserData) =>
        isLoggedIn;
}

internal sealed record FriendChatMessageRow(
    FriendChatMessageContract Message,
    bool IsLocal,
    string SenderCallsign,
    string SenderGameId,
    string? SenderAvatarImageData) : INotifyPropertyChanged
{
    private string _timeText = CommunicationTimeFormatter.Format(Message.CreatedAt);
    public event PropertyChangedEventHandler? PropertyChanged;
    public string AccountId => Message.SenderAccountId;
    public string Text => Message.Text;
    public ChatAttachmentContract? Attachment => Message.Attachment;
    public Visibility TextVisibility => ChatAttachmentPresentation.TextVisibility(Text);
    public Visibility AttachmentVisibility => ChatAttachmentPresentation.AttachmentVisibility(Attachment);
    public string AttachmentTitle => Attachment?.Title ?? "";
    public string AttachmentSummary => Attachment?.Summary ?? "";
    public string AttachmentActionText => ChatAttachmentPresentation.ActionText(Attachment);
    public bool AttachmentActionEnabled => ChatAttachmentPresentation.ActionEnabled(Attachment);
    public string AttachmentTypeText => ChatAttachmentPresentation.TypeText(Attachment);
    public string AttachmentStatusText => ChatAttachmentPresentation.StatusText(Attachment);
    public string AttachmentStatusBrush => ChatAttachmentPresentation.StatusBrush(Attachment);
    public Visibility AttachmentStatusVisibility => ChatAttachmentPresentation.StatusVisibility(Attachment);
    public string AttachmentRoomActivityText => ChatAttachmentPresentation.RoomActivityText(Attachment);
    public string AttachmentRoomFactsText => ChatAttachmentPresentation.RoomFactsText(Attachment);
    public Visibility AttachmentRoomDetailsVisibility => ChatAttachmentPresentation.RoomDetailsVisibility(Attachment);
    public string TimeText => _timeText;
    public string SenderGameIdText => string.IsNullOrWhiteSpace(SenderGameId) ||
                                      SenderGameId.Equals(SenderCallsign, StringComparison.OrdinalIgnoreCase)
        ? ""
        : $"@ {SenderGameId}";
    public string SenderRoleTitle => "";
    public string SenderRoleBrush => IsLocal ? "#29AFFF" : "#69CCFF";
    public Visibility RoleVisibility => Visibility.Collapsed;
    public bool IsSystem => false;
    public bool IsSelf => IsLocal;
    public string Initials => GetInitials(string.IsNullOrWhiteSpace(SenderCallsign) ? SenderGameId : SenderCallsign);

    public void RefreshTime(DateTimeOffset now)
    {
        var next = CommunicationTimeFormatter.Format(Message.CreatedAt, now);
        if (string.Equals(_timeText, next, StringComparison.Ordinal))
        {
            return;
        }

        _timeText = next;
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(TimeText)));
    }

    private static string GetInitials(string value)
    {
        var trimmed = value.Trim();
        if (trimmed.Length == 0)
        {
            return "?";
        }

        var parts = trimmed.Split([' ', '_', '-'], StringSplitOptions.RemoveEmptyEntries);
        return parts.Length >= 2
            ? string.Concat(parts[0][0], parts[1][0]).ToUpperInvariant()
            : trimmed[..Math.Min(2, trimmed.Length)].ToUpperInvariant();
    }
}
