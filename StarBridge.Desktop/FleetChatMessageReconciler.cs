using StarBridge.Core.FleetChat;

namespace StarBridge.Desktop;

public static class FleetChatMessageReconciler
{
    /// <summary>
    /// 合并一条频道的消息流。<paramref name="channelId"/> 是闭集：任何不属于该频道的消息一律丢弃。
    /// 序号按频道各自计数，因此跨频道混入的消息不只是多余，还会打乱排序。
    /// 调用方是否记得在切换时清空列表，不应成为正确性的前提。
    /// </summary>
    public static FleetChatMessageContract[] Reconcile(
        string channelId,
        IEnumerable<FleetChatMessageContract>? existing,
        IEnumerable<FleetChatMessageContract>? incoming)
    {
        var rows = (existing ?? [])
            .Where(message => BelongsToChannel(message, channelId))
            .ToDictionary(message => message.MessageId, StringComparer.OrdinalIgnoreCase);
        foreach (var message in incoming ?? [])
        {
            if (!BelongsToChannel(message, channelId))
            {
                continue;
            }

            rows[message.MessageId] = message;
        }

        return rows.Values.OrderBy(message => message.Sequence).ToArray();
    }

    private static bool BelongsToChannel(FleetChatMessageContract message, string channelId) =>
        !string.IsNullOrWhiteSpace(message.MessageId) &&
        !string.IsNullOrWhiteSpace(channelId) &&
        message.ChannelId.Equals(channelId, StringComparison.OrdinalIgnoreCase);
}
