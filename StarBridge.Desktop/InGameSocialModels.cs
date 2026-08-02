using StarBridge.Core.Friends;
using StarBridge.Core.Presence;
using StarBridge.Core.Chat;
using System.Windows;
using MediaBrush = System.Windows.Media.Brush;
using WpfButton = System.Windows.Controls.Button;

namespace StarBridge.Desktop;

internal enum InGameSocialSection
{
    Friends,
    DirectMessages,
    Channels
}

internal enum InGameChatChannelKind
{
    Private,
    Fleet,
    Squad,
    Room
}

internal enum InGameFriendDirectoryState
{
    Unavailable,
    Loading,
    Ready,
    Failed
}

internal sealed record InGameChatChannelRow(
    InGameChatChannelKind Kind,
    string Key,
    string Callsign,
    string Preview,
    string ContextText,
    string? AvatarSource,
    string AvatarFallbackText,
    MediaBrush PresenceBrush,
    string UpdatedAtText,
    string ConversationStateText,
    Visibility RequestBadgeVisibility,
    string UnreadText,
    Visibility UnreadVisibility,
    FriendUserContract? User = null);

internal sealed record InGameConversationPaneSnapshot(
    InGameChatChannelRow[] Conversations,
    object[] Messages,
    InGameChatChannelRow? ActiveConversation,
    FriendUserContract? ActiveUser,
    bool CanSend,
    string StatusText);

internal sealed record InGameSocialSnapshot(
    bool IsAvailable,
    FriendCenterRow[] Friends,
    FriendCenterRow[] IncomingRequests,
    FriendCenterRow[] SearchResults,
    InGameConversationPaneSnapshot DirectMessages,
    InGameConversationPaneSnapshot Channels,
    InGameFriendDirectoryState FriendDirectoryState,
    string FriendStatusText,
    string SearchStatusText,
    bool IsSearchActive,
    string LocalCallsign,
    string LocalGameId,
    string? LocalAvatarSource,
    string LocalAvatarFallbackText,
    PlayerPresenceVisibilityMode LocalVisibilityMode,
    string LocalPresenceText,
    MediaBrush LocalPresenceBrush);

internal sealed class InGameSocialConversationRequestedEventArgs(
    FriendUserContract user) : EventArgs
{
    internal FriendUserContract User { get; } = user;
}

internal sealed class InGameSocialChannelRequestedEventArgs(
    InGameChatChannelRow channel) : EventArgs
{
    internal InGameChatChannelRow Channel { get; } = channel;
}

internal sealed class InGameSocialMessageRequestedEventArgs(
    string text,
    InGameChatChannelKind channelKind,
    string channelKey) : EventArgs
{
    internal string Text { get; } = text;
    internal InGameChatChannelKind ChannelKind { get; } = channelKind;
    internal string ChannelKey { get; } = channelKey;
}

internal sealed class InGameSocialAttachmentRequestedEventArgs(
    WpfButton anchor,
    InGameChatChannelKind channelKind,
    string channelKey) : EventArgs
{
    internal WpfButton Anchor { get; } = anchor;
    internal InGameChatChannelKind ChannelKind { get; } = channelKind;
    internal string ChannelKey { get; } = channelKey;
}

internal sealed class InGameChatAttachmentActionRequestedEventArgs(
    ChatAttachmentContract attachment) : EventArgs
{
    internal ChatAttachmentContract Attachment { get; } = attachment;
}

internal sealed class InGameSocialFriendSearchRequestedEventArgs(
    string query) : EventArgs
{
    internal string Query { get; } = query;
}

internal sealed class InGameSocialFriendActionRequestedEventArgs(
    FriendCenterRow row,
    string action) : EventArgs
{
    internal FriendCenterRow Row { get; } = row;
    internal string Action { get; } = action;
}

internal sealed class InGameFriendPresenceChangedEventArgs(
    PlayerPresenceVisibilityMode mode) : EventArgs
{
    internal PlayerPresenceVisibilityMode Mode { get; } = mode;
}
