using System.Text.Json;
using StarBridge.HostRuntime.Notifications;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    internal async Task<CommunityNotificationFeed> ReadScmNotificationsAsync(string bearer, string scope, Action current, CancellationToken token)
    {
        if (string.IsNullOrWhiteSpace(scope)) throw Invalid();
        current();
        var body = await WorkspaceJson(bearer, "/api/fleets/notification-sources", token);
        current(); token.ThrowIfCancellationRequested();
        try
        {
            if (Number(body, "schemaVersion", 1, 1) != 1) throw Invalid();
            var server = DateTimeOffset.Parse(Timestamp(body, "serverTime") ?? throw Invalid());
            var rows = Rows(body, "sources", 64);
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var sources = rows.Select(row => {
                var code = Text(row, "code", 256);
                if (string.IsNullOrWhiteSpace(code) || !seen.Add(code)) throw Invalid();
                var joined = DateTimeOffset.Parse(Timestamp(row, "joinedAt") ?? throw Invalid());
                if (joined == default || joined > server) throw Invalid();
                var management = row.GetProperty("managementAvailable").GetBoolean();
                var tasks = Rows(row, "tasks", 10000);
                if (!management && tasks.Length != 0 || tasks.Select(task => Text(task, "id", 128)).Distinct(StringComparer.Ordinal).Count() != tasks.Length) throw Invalid();
                var chat = row.GetProperty("chat");
                var sequence = ChatSequence(chat, "sequence");
                var created = Timestamp(chat, "createdAt") is { } timestamp ? DateTimeOffset.Parse(timestamp) : (DateTimeOffset?)null;
                if (created > server || (sequence == 0) != (created is null) || sequence == 0 && chat.GetProperty("incoming").GetBoolean()) throw Invalid();
                if (tasks.Any(task => DateTimeOffset.Parse(Timestamp(task, "createdAt") ?? throw Invalid()) > server)) throw Invalid();
                return new CommunityNotificationSource(NotificationKey(scope, code.ToUpperInvariant(), joined, "source"), Text(row, "name", 512), joined,
                    true, new(sequence, Number(chat, "unread", 0, 500), chat.GetProperty("incoming").GetBoolean(), server, created,
                        Text(chat, "callsign", 512), Text(chat, "text", 1000, true)), management,
                    tasks.Select(task => new CommunityNotificationTask(NotificationKey(scope, code.ToUpperInvariant(), joined, Text(task, "id", 128)),
                        DateTimeOffset.Parse(Timestamp(task, "createdAt") ?? throw Invalid()))).ToArray(), NotificationPolicyStore.Organization(code, joined));
            }).ToArray();
            current(); token.ThrowIfCancellationRequested();
            return new(_targetClock.GetUtcNow(), sources);
        }
        catch (Exception error) when (error is JsonException or InvalidOperationException or KeyNotFoundException or FormatException or OverflowException)
        { throw Invalid(); }
    }
}
