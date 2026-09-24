using System.Text.Json;
using System.Text.Json.Nodes;
using System.Security.Cryptography;
using System.Text;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    private static string? AvatarContentVersion(string? avatar) => string.IsNullOrEmpty(avatar) ? null :
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(avatar))).ToLowerInvariant();
    // Explicit S2-only normalization into existing, bounded client projections.
    // Existing endpoints remain authoritative for membership on every request.
    private async Task<JsonElement> WpfS2ChatPage(string bearer, Target target, string channel,
        long after, long before, CancellationToken token, int limit = 50)
    {
        if (limit is not (1 or 50)) throw Invalid();
        var raw = await WorkspaceJson(bearer, ChatHistoryPath(target.Code, channel) +
            $"&after={after}&before={before}&limit={limit}", token, limit == 1 ? 2 * 1024 * 1024 : 32 * 1024 * 1024);
        ChatObject(raw);
        if (Optional(raw, "error", 512) is not null ||
            !Text(raw, "channelId", 272).Equals(channel, StringComparison.OrdinalIgnoreCase)) throw Invalid();
        var rows = Rows(raw, "messages", limit).Select(message =>
        {
            ChatObject(message);
            if (!Text(message, "channelId", 272).Equals(channel, StringComparison.OrdinalIgnoreCase)) throw Invalid();
            var sender = Text(message, "senderAccountId", 512);
            var avatar = Optional(message, "senderAvatarImageData", 720 * 1024);
            return new
            {
                sequence = ChatSequence(message, "sequence", true), messageId = Text(message, "messageId", 128),
                senderAccountId = sender, senderCallsign = Text(message, "senderCallsign", 512),
                senderGameId = Text(message, "senderGameId", 512), senderRoleTitle = Text(message, "senderRoleTitle", 128),
                senderRoleColor = Text(message, "senderRoleColor", 7), text = Text(message, "text", 1000, true),
                createdAt = Timestamp(message, "createdAt") ?? throw Invalid(),
                isSelf = string.Equals(sender, target.WpfS2ViewerId, StringComparison.Ordinal),
                hasAvatar = !string.IsNullOrEmpty(avatar),
                avatarVersion = AvatarContentVersion(avatar),
                hasAttachment = message.TryGetProperty("attachment", out var attachment) && attachment.ValueKind != JsonValueKind.Null
            };
        }).ToArray();
        return JsonSerializer.SerializeToElement(new { schemaVersion = 1, channelId = channel,
            latestSequence = ChatSequence(raw, "latestSequence"), oldestSequence = ChatSequence(raw, "oldestSequence"),
            hasOlder = raw.GetProperty("hasOlder").GetBoolean(), canSend = raw.GetProperty("canSend").GetBoolean(),
            serverTime = Timestamp(raw, "serverTime") ?? throw Invalid(), messages = rows }, ChatJson);
    }

    private async Task<JsonElement> WpfS2AnnouncementPage(string bearer, Target target, int offset,
        long? expected, string? detailId, CancellationToken token)
    {
        var raw = await AnnouncementJsonAsync(bearer, "/api/fleets/announcements?fleetCode=" +
            Uri.EscapeDataString(target.Code), token, 32 * 1024 * 1024);
        return ProjectWpfS2Announcements(raw, target, offset, expected, detailId);
    }

    private JsonElement ProjectWpfS2Announcements(JsonElement raw, Target target, int offset = 0,
        long? expected = null, string? detailId = null)
    {
        AnnouncementObject(raw);
        if (!Text(raw, "fleetCode", 256).Equals(target.Code, StringComparison.OrdinalIgnoreCase)) throw Invalid();
        var revision = AnnouncementRevision(raw, "revision");
        if (expected is not null && revision != expected) throw new AccountBridgeHostException("communities.announcementsChanged");
        var active = raw.GetProperty("current");
        var history = Rows(raw, "history", 100);
        var all = active.ValueKind == JsonValueKind.Null ? history : [active, .. history];
        if (all.Length > 100 || all.Select(x => Text(x, "id", 128)).Distinct(StringComparer.OrdinalIgnoreCase).Count() != all.Length)
            throw Invalid();

        JsonElement Entry(JsonElement item, bool detail)
        {
            // Reuse the existing metadata/avatar validator; strip images only from list responses.
            AnnouncementObject(item);
            var node = JsonNode.Parse(item.GetRawText())!.AsObject();
            var author = item.GetProperty("author"); var editor = item.GetProperty("lastEditor");
            AnnouncementObject(author); AnnouncementObject(editor);
            var hasAuthor = !string.IsNullOrEmpty(Optional(author, "avatarImageData", 720 * 1024));
            var hasEditor = !string.IsNullOrEmpty(Optional(editor, "avatarImageData", 720 * 1024));
            if (!detail)
            {
                node["author"]!["avatarImageData"] = null;
                node["lastEditor"]!["avatarImageData"] = null;
            }
            var wrapper = JsonSerializer.SerializeToElement(new { announcement = node, authorHasAvatar = hasAuthor,
                lastEditorHasAvatar = hasEditor }, AnnouncementJson);
            var record = Announcement(wrapper, target.Code, detail);
            if (record.Revision > revision) throw Invalid();
            return wrapper;
        }
        // Validate every retained record, not only the currently requested page.
        foreach (var item in all) _ = Entry(item, false);
        if (active.ValueKind != JsonValueKind.Null && !Text(active, "state", 16).Equals("Published", StringComparison.OrdinalIgnoreCase)
            || history.Any(x => Text(x, "state", 16).Equals("Published", StringComparison.OrdinalIgnoreCase))) throw Invalid();
        var refreshedAt = Timestamp(raw, "refreshedAt") ?? throw Invalid();
        var canManage = raw.GetProperty("canManage").GetBoolean();
        if (detailId is not null)
        {
            var entry = all.SingleOrDefault(x => Text(x, "id", 128) == detailId);
            if (entry.ValueKind == JsonValueKind.Undefined) throw new AccountBridgeHostException("communities.notFound");
            return JsonSerializer.SerializeToElement(new { schemaVersion = 1, membershipModelVersion = 1,
                fleetCode = target.Code, revision, canManage, refreshedAt, entry = Entry(entry, true) }, AnnouncementJson);
        }
        if (offset > history.Length) throw new AccountBridgeHostException("communities.announcementsChanged");
        var ordered = history.OrderByDescending(x => DateTimeOffset.Parse(Timestamp(x, "updatedAt")!))
            .ThenBy(x => Text(x, "id", 128), StringComparer.Ordinal).ToArray();
        return JsonSerializer.SerializeToElement(new { schemaVersion = 1, membershipModelVersion = 1,
            fleetCode = target.Code, revision, canManage, refreshedAt, offset,
            next = offset + 20 < history.Length ? (int?)(offset + 20) : null, totalHistoryCount = history.Length,
            current = active.ValueKind == JsonValueKind.Null ? (JsonElement?)null : Entry(active, false),
            history = ordered.Skip(offset).Take(20).Select(x => Entry(x, false)).ToArray() }, AnnouncementJson);
    }
}
