using System.Security.Cryptography;
using System.Text.Json;
using StarBridge.Core.FleetChat;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    // Called only by the explicitly selected S2 owner. Never a fallback from a
    // failed SCM read. Reuse membership, permissions and chat normalization;
    // do not touch foreground targets, paging cursors or read receipts.
    internal async Task<CommunityNotificationFeed> ReadWpfS2NotificationsAsync(
        string bearer, string scope, string viewerId, Action current, CancellationToken token)
    {
        if (string.IsNullOrWhiteSpace(scope) || string.IsNullOrWhiteSpace(viewerId)) throw Invalid();
        try {
            current(); token.ThrowIfCancellationRequested();
            var fleets = await WpfS2Membership(bearer, token);
            if (fleets.Length > 64) throw Invalid();
            var sources = new List<CommunityNotificationSource>();
            foreach (var fleet in fleets) {
                current(); token.ThrowIfCancellationRequested();
                var code = Text(fleet, "code", 256);
                var name = Text(fleet, "name", 512);
                var members = Rows(fleet, "members", 10000).Where(row =>
                    string.Equals(Optional(row, "accountId", 512), viewerId, StringComparison.OrdinalIgnoreCase)).ToArray();
                if (members.Length != 1) throw Invalid();
                var joined = WpfTimestamp(members[0], "joinedAt") ?? throw Invalid();
                // Correlation only, not a persistent preference identity or a command ref.
                var key = NotificationKey(scope, code.ToUpperInvariant(), joined, "source");
                CommunityNotificationChat? chat = null;
                var chatAvailable = false;
                try {
                    chat = await ReadNotificationChat(bearer, code, name, viewerId, token);
                    chatAvailable = true;
                } catch (AccountBridgeHostException) { /* Fail this source closed, not every organization. */ }
                  catch (HttpRequestException) { }
                current(); token.ThrowIfCancellationRequested();
                var managementAvailable = false;
                CommunityNotificationTask[] tasks = [];
                try {
                    var ownership = await ReadWpfS2Ownership(bearer, fleet, viewerId, token);
                    if (WpfS2HasPermissionId(fleet, viewerId, "members.review", ownership)) {
                        var rows = WpfS2OptionalRows(fleet, "applications", 10000);
                        if (rows.Select(row => Text(row, "id", 128)).Distinct(StringComparer.OrdinalIgnoreCase).Count() != rows.Length)
                            throw Invalid();
                        tasks = rows.Where(row => string.IsNullOrWhiteSpace(WpfText(row, "status", 16)) ||
                            WpfText(row, "status", 16).Equals("Pending", StringComparison.OrdinalIgnoreCase))
                            .Select(row => new CommunityNotificationTask(
                                NotificationKey(scope, code.ToUpperInvariant(), joined, Text(row, "id", 128)),
                                WpfTimestamp(row, "createdAt") ?? throw Invalid())).ToArray();
                        managementAvailable = true;
                    }
                } catch (AccountBridgeHostException) { tasks = []; }
                  catch (HttpRequestException) { tasks = []; }
                current(); token.ThrowIfCancellationRequested();
                sources.Add(new(key, name, joined, chatAvailable, chat, managementAvailable, tasks,
                    Notifications.NotificationPolicyStore.Organization(code, joined)));
            }
            current(); token.ThrowIfCancellationRequested();
            return new(_targetClock.GetUtcNow(), sources.ToArray());
        } catch (Exception e) when (e is JsonException or InvalidOperationException or KeyNotFoundException or FormatException or OverflowException) {
            throw Invalid();
        }
    }

    private async Task<CommunityNotificationChat> ReadNotificationChat(
        string bearer, string code, string name, string viewerId, CancellationToken token)
    {
        var channel = FleetChatIdentity.FleetChannelId(code);
        var channels = await WorkspaceJson(bearer, "/api/fleets/chat/channels?fleetCode=" + Uri.EscapeDataString(code), token);
        ChatObject(channels);
        var rows = Rows(channels, "channels", 1);
        if (rows.Length != 1 || Text(rows[0], "type", 16) != FleetChatChannelTypes.Fleet ||
            !Text(rows[0], "channelId", 272).Equals(channel, StringComparison.OrdinalIgnoreCase)) throw Invalid();
        var unread = Number(rows[0], "unreadCount", 0, 500);
        if (Number(channels, "totalUnread", 0, 500) != unread) throw Invalid();
        var target = new Target(code, "notification-read", _targetClock.GetUtcNow(), name, viewerId);
        var page = await WpfS2ChatPage(bearer, target, channel, 0, 0, token, limit: 1);
        var sequence = ChatSequence(page, "latestSequence");
        var server = DateTimeOffset.Parse(Timestamp(page, "serverTime") ?? throw Invalid());
        var messages = Rows(page, "messages", 1);
        if (messages.Length == 0) {
            if (sequence != 0 || ChatSequence(page, "oldestSequence") != 0 || page.GetProperty("hasOlder").GetBoolean()) throw Invalid();
            return new(0, unread, false, server, null, "", "");
        }
        var message = messages[0];
        if (ChatSequence(message, "sequence", true) != sequence || ChatSequence(page, "oldestSequence") != sequence) throw Invalid();
        var created = DateTimeOffset.Parse(Timestamp(message, "createdAt") ?? throw Invalid());
        if (created > server) throw Invalid();
        return new(sequence, unread, !message.GetProperty("isSelf").GetBoolean(), server, created,
            Text(message, "senderCallsign", 512), Text(message, "text", 1000, true));
    }

    private static string NotificationKey(string scope, string code, DateTimeOffset joined, string id) =>
        Convert.ToHexString(SHA256.HashData(JsonSerializer.SerializeToUtf8Bytes(new { scope, code, joined, id }))).ToLowerInvariant();
}
