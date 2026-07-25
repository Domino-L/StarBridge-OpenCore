using StarBridge.Core.Friends;

namespace StarBridge.Desktop;

internal sealed record FriendCommunicationEvent(string Title, string Detail);

internal sealed class FriendOverlayNotificationTracker
{
    private readonly HashSet<string> _incomingRequestAccountIds =
        new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, ConversationBaseline> _conversations =
        new(StringComparer.OrdinalIgnoreCase);
    private bool _hasFriendBaseline;
    private bool _hasConversationBaseline;

    public void Reset()
    {
        _incomingRequestAccountIds.Clear();
        _conversations.Clear();
        _hasFriendBaseline = false;
        _hasConversationBaseline = false;
    }

    public IReadOnlyList<FriendCommunicationEvent> ObserveFriends(
        FriendCenterSnapshotContract snapshot,
        bool canSynchronize,
        string language)
    {
        if (!canSynchronize)
        {
            Reset();
            return [];
        }

        var nextIncoming = snapshot.IncomingRequests
            .Where(entry => !string.IsNullOrWhiteSpace(entry.User.AccountId))
            .ToDictionary(entry => entry.User.AccountId, entry => entry.User, StringComparer.OrdinalIgnoreCase);
        if (!_hasFriendBaseline)
        {
            Replace(_incomingRequestAccountIds, nextIncoming.Keys);
            _hasFriendBaseline = true;
            return [];
        }

        var zh = language.Equals("zh", StringComparison.OrdinalIgnoreCase);
        var events = nextIncoming
            .Where(entry => !_incomingRequestAccountIds.Contains(entry.Key))
            .Select(entry => new FriendCommunicationEvent(
                zh ? "新的好友申请" : "New friend request",
                zh
                    ? $"{DisplayName(entry.Value)} 请求添加你为好友"
                    : $"{DisplayName(entry.Value)} sent you a friend request"))
            .ToArray();
        Replace(_incomingRequestAccountIds, nextIncoming.Keys);
        return events;
    }

    public IReadOnlyList<FriendCommunicationEvent> ObserveConversations(
        FriendChatConversationListContract snapshot,
        string? localAccountId,
        string? visibleConversationAccountId,
        bool canSynchronize,
        bool includeMessagePreview,
        string language)
    {
        if (!canSynchronize)
        {
            Reset();
            return [];
        }

        var next = snapshot.Conversations
            .Where(conversation => !string.IsNullOrWhiteSpace(conversation.User.AccountId))
            .ToDictionary(
                conversation => conversation.User.AccountId,
                conversation => new ConversationBaseline(conversation.LatestSequence),
                StringComparer.OrdinalIgnoreCase);
        if (!_hasConversationBaseline)
        {
            Replace(_conversations, next);
            _hasConversationBaseline = true;
            return [];
        }

        var zh = language.Equals("zh", StringComparison.OrdinalIgnoreCase);
        var events = new List<FriendCommunicationEvent>();
        foreach (var conversation in snapshot.Conversations)
        {
            var accountId = conversation.User.AccountId;
            if (string.IsNullOrWhiteSpace(accountId))
            {
                continue;
            }

            _conversations.TryGetValue(accountId, out var previous);
            var incoming = (previous is null || conversation.LatestSequence > previous.LatestSequence) &&
                           conversation.UnreadCount > 0 &&
                           conversation.LastSenderAccountId.Equals(accountId, StringComparison.OrdinalIgnoreCase) &&
                           !conversation.LastSenderAccountId.Equals(localAccountId, StringComparison.OrdinalIgnoreCase);
            if (!incoming || accountId.Equals(visibleConversationAccountId, StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            if (conversation.ConversationState == DirectMessageConversationStates.RequestIncoming)
            {
                events.Add(new FriendCommunicationEvent(
                    zh ? "新的消息请求" : "New message request",
                    zh
                        ? $"{DisplayName(conversation.User)} 希望与你开始私聊"
                        : $"{DisplayName(conversation.User)} wants to start a private chat"));
                continue;
            }

            var detail = zh
                ? $"{DisplayName(conversation.User)} 发来一条新私信"
                : $"New private message from {DisplayName(conversation.User)}";
            if (includeMessagePreview && !string.IsNullOrWhiteSpace(conversation.LastMessagePreview))
            {
                detail = $"{detail} · {NormalizePreview(conversation.LastMessagePreview)}";
            }

            events.Add(new FriendCommunicationEvent(zh ? "好友私信" : "Friend message", detail));
        }

        Replace(_conversations, next);
        return events;
    }

    private static string DisplayName(FriendUserContract user) =>
        !string.IsNullOrWhiteSpace(user.Callsign)
            ? user.Callsign.Trim()
            : !string.IsNullOrWhiteSpace(user.GameId)
                ? user.GameId.Trim()
                : user.AccountId;

    private static string NormalizePreview(string value)
    {
        var normalized = string.Join(' ', value.Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries));
        return normalized.Length <= 80 ? normalized : $"{normalized[..77]}...";
    }

    private static void Replace<TKey, TValue>(Dictionary<TKey, TValue> target, Dictionary<TKey, TValue> source)
        where TKey : notnull
    {
        target.Clear();
        foreach (var (key, value) in source)
        {
            target[key] = value;
        }
    }

    private static void Replace(HashSet<string> target, IEnumerable<string> source)
    {
        target.Clear();
        target.UnionWith(source);
    }

    private sealed record ConversationBaseline(long LatestSequence);
}
