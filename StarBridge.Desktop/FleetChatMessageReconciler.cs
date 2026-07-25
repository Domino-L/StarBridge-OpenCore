using StarBridge.Core.FleetChat;

namespace StarBridge.Desktop;

public static class FleetChatMessageReconciler
{
    public static FleetChatMessageContract[] Reconcile(
        IEnumerable<FleetChatMessageContract>? existing,
        IEnumerable<FleetChatMessageContract>? incoming)
    {
        var rows = (existing ?? [])
            .Where(message => !string.IsNullOrWhiteSpace(message.MessageId))
            .ToDictionary(message => message.MessageId, StringComparer.OrdinalIgnoreCase);
        foreach (var message in incoming ?? [])
        {
            if (string.IsNullOrWhiteSpace(message.MessageId))
            {
                continue;
            }

            rows[message.MessageId] = message;
        }

        return rows.Values.OrderBy(message => message.Sequence).ToArray();
    }
}
