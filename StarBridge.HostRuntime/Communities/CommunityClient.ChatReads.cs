using System.Collections.Concurrent;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StarBridge.Core.Chat;
using StarBridge.Core.FleetChat;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Chat;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    private sealed record ChatTarget(string Code, string Scope, string ChannelId, long Sequence,
        string MessageId, string SenderId, DateTimeOffset Expires, bool OfficialFleet = false, string? SenderRef = null);
    private readonly ConcurrentDictionary<string, ChatTarget> _chatTargets = new();
    private const int ChatDetailChunkBytes = 192 * 1024;
    private static readonly JsonSerializerOptions ChatJson = new(JsonSerializerDefaults.Web);

    internal Task<object> ReadChatAsync(string bearer, JsonElement body, string scope, Action current, CancellationToken token, string? archiveAccount = null) =>
        ReadChatPageAsync(bearer, body, scope, current, token, archiveAccount, false);

    internal Task<object> ReadChatAuthorRenewalAsync(string bearer, JsonElement body, string scope, Action current, CancellationToken token, string? archiveAccount = null) =>
        ReadChatPageAsync(bearer, body, scope, current, token, archiveAccount, true);

    private Task<object> ReadChatPageAsync(string bearer, JsonElement body, string scope, Action current, CancellationToken token, string? archiveAccount, bool renewal) =>
        GuardWorkspace(async () =>
        {
            var publicationToken = token; var operationStarted = System.Diagnostics.Stopwatch.GetTimestamp();
            if (renewal) Validate(body, "targetRef", "after", "limit", "observeMessageRefs", "surface");
            else Validate(body, "targetRef", "after", "before", "localHistory", "authorIdentitySchemaVersion", "observeMessageRefs");
            var preview = renewal;
            if (renewal && body.TryGetProperty("surface", out var surface))
            {
                if (surface.ValueKind != JsonValueKind.String || surface.GetString() is not ("preview" or "chat")) throw Invalid();
                preview = surface.GetString() == "preview";
            }
            var reference = Text(body, "targetRef", 32);
            long after = ChatSequence(body, "after"), before = renewal ? 0 : ChatSequence(body, "before");
            var limit = renewal ? Number(body, "limit", 1, preview ? 8 : 50) : 50;
            if (after > 0 && before > 0) throw Invalid();
            current();
            var target = ResolveForRead(reference, scope, allowWpfS2: true);
            using var operation = target.OfficialFleet ? CancellationTokenSource.CreateLinkedTokenSource(token) : null;
            operation?.CancelAfter(TimeSpan.FromSeconds(12)); if (operation is not null) token = operation.Token;
            var withAuthors = OfficialAuthorOptIn(body, target, "observeMessageRefs", renewal, preview);
            if (body.TryGetProperty("localHistory", out var local))
            {
                if (archiveAccount is null || after != 0 || before != 0 || local.GetString() is not ("read" or "clear")) throw Invalid();
                var cached = await ChatHistoryArchive.Read(archiveAccount, "organization:" + target.Code, local.GetString()!, neutralNames: target.OfficialFleet);
                token.ThrowIfCancellationRequested(); current();
                return cached;
            }
            var channel = FleetChatIdentity.FleetChannelId(target.Code);
            var unreadCount = 0; var channelCanSend = false;
            if (!renewal)
            {
                var channels = await WorkspaceJson(bearer, CommunicationPath(target, "/chat/channels?fleetCode=") + Uri.EscapeDataString(target.Code), token);
                ChatObject(channels);
                current();
                var rows = Rows(channels, "channels", 1);
                foreach (var row in rows) ChatObject(row);
                if (rows.Length != 1 || Text(rows[0], "type", 16) != FleetChatChannelTypes.Fleet ||
                    !Text(rows[0], "channelId", 272).Equals(channel, StringComparison.OrdinalIgnoreCase)) throw Invalid();
                unreadCount = Number(rows[0], "unreadCount", 0, 500);
                if (Number(channels, "totalUnread", 0, 500) != unreadCount) throw Invalid();
                channelCanSend = rows[0].GetProperty("canSend").GetBoolean();
            }
            OfficialAuthorRead? authors = null;
            try
            {
                if (withAuthors) authors = await ReadOfficialChatAuthors(bearer, target, body, scope, after, before, token, limit, preview, allowChatAuthorsFallback: !renewal, renewal: renewal);
            }
            catch (OfficialChatAuthorsDisabledException) when (!renewal)
            {
                // A stale author-capable context must still deliver ordinary content.
                // This is one read's downgrade, never a cached authorization decision.
            }
            var root = authors is not null ? authors.Page : target.WpfS2ViewerId is not null
                ? await WpfS2ChatPage(bearer, target, channel, after, before, token)
                : await WorkspaceJson(bearer, CommunicationPath(target, ChatHistoryPath(target.Code, channel)["/api/fleets".Length..]) +
                $"&projection=client&after={after}&before={before}&limit=50", token);
            token.ThrowIfCancellationRequested(); current();
            ChatObject(root);
            if (Number(root, "schemaVersion", 1, 1) != 1 ||
                !Text(root, "channelId", 272).Equals(channel, StringComparison.OrdinalIgnoreCase)) throw Invalid();
            long latest = ChatSequence(root, "latestSequence"), oldest = ChatSequence(root, "oldestSequence");
            var hasOlder = root.GetProperty("hasOlder").GetBoolean();
            var canSend = root.GetProperty("canSend").GetBoolean() && channelCanSend;
            var serverTime = Timestamp(root, "serverTime") ?? throw Invalid();
            var messages = Rows(root, "messages", limit);
            long previous = 0;
            var pending = new List<(string Reference, ChatTarget Target, string SenderRef)>();
            var confirmations = new List<(string Id, long Sequence)>();
            var items = messages.Select(message =>
            {
                ChatObject(message);
                var sequence = ChatSequence(message, "sequence", positive: true);
                if (sequence <= previous || sequence > latest || after > 0 && sequence <= after || before > 0 && sequence >= before) throw Invalid();
                previous = sequence;
                string id = Text(message, "messageId", 128), sender = Text(message, "senderAccountId", 512);
                if (string.IsNullOrWhiteSpace(id) || string.IsNullOrWhiteSpace(sender)) throw Invalid();
                var color = Text(message, "senderRoleColor", 7);
                if (color.Length != 7 || color[0] != '#' || color.Skip(1).Any(c => !Uri.IsHexDigit(c))) throw Invalid();
                var existing = _chatTargets.FirstOrDefault(pair => pair.Value.Code == target.Code && pair.Value.Scope == scope &&
                    pair.Value.Sequence == sequence && pair.Value.MessageId == id && pair.Value.SenderId == sender && pair.Value.OfficialFleet == target.OfficialFleet && (target.OfficialFleet || pair.Value.Expires > DateTimeOffset.UtcNow));
                var messageRef = existing.Key ?? Guid.NewGuid().ToString("N");
                var isSelf = message.GetProperty("isSelf").GetBoolean();
                var messageText = Text(message, "text", 1000, multiline: true);
                var hasAttachment = message.GetProperty("hasAttachment").GetBoolean();
                var avatarVersion = Optional(message, "avatarVersion", 64);
                if (avatarVersion is not null && !LowerHex(avatarVersion, 64)) throw Invalid();
                var localRequestId = preview ? null : ChatRequestId(id, target.Code, scope, isSelf, messageText, hasAttachment);
                if (localRequestId is not null) confirmations.Add((id, sequence));
                var preferredSenderRef = target.OfficialFleet ? existing.Value?.SenderRef : null;
                var senderRef = MemberReferenceFor("account:" + sender, target.Code, scope, preferredReference: preferredSenderRef)!;
                pending.Add((messageRef, new(target.Code, scope, channel, sequence, id, sender, (target.OfficialFleet ? _targetClock.GetUtcNow() : DateTimeOffset.UtcNow).AddMinutes(5), target.OfficialFleet, senderRef), senderRef));
                return new
                {
                    sequence,
                    messageRef,
                    senderRef,
                    senderCallsign = target.OfficialFleet ? "" : Text(message, "senderCallsign", 512),
                    senderGameId = target.OfficialFleet ? "" : Text(message, "senderGameId", 512),
                    senderRoleTitle = target.OfficialFleet ? "" : Text(message, "senderRoleTitle", 128),
                    senderRoleColor = target.OfficialFleet ? "#9DAAB3" : color,
                    text = messageText,
                    createdAt = Timestamp(message, "createdAt") ?? throw Invalid(),
                    isSelf,
                    localRequestId,
                    hasAvatar = !target.OfficialFleet && message.GetProperty("hasAvatar").GetBoolean(),
                    avatarVersion = target.OfficialFleet ? null : avatarVersion,
                    hasAttachment,
                };
            }).ToArray();
            if (oldest != (items.FirstOrDefault()?.sequence ?? 0) || items.Length == 0 && hasOlder) throw Invalid();
            foreach (var expired in _chatTargets.Where(p => !p.Value.OfficialFleet && p.Value.Expires <= DateTimeOffset.UtcNow).ToArray()) _chatTargets.TryRemove(expired.Key, out _);
            if (target.OfficialFleet) TrimOfficialChatAddresses(target, scope, pending.Select(p => p.Reference).ToHashSet(StringComparer.Ordinal));
            if (_chatTargets.Count + pending.Count(p => !_chatTargets.ContainsKey(p.Reference)) > 2000)
                throw new AccountBridgeHostException("communities.refreshRequired");
            current(); token.ThrowIfCancellationRequested();
            PublishMemberTargets(pending.Select(entry => new KeyValuePair<string, MemberTarget>(entry.SenderRef,
                new("account:" + entry.Target.SenderId, target.Code, scope, entry.Target.Expires))));
            foreach (var entry in pending)
            {
                _chatTargets[entry.Reference] = entry.Target;
            }
            foreach (var confirmation in confirmations) ConfirmChatRequest(confirmation.Id, target.Code, scope, confirmation.Sequence);
            RenewTarget(reference, target, token);
            var saved = preview || await ChatHistoryArchive.Save(archiveAccount, "organization:" + target.Code,
                items.Select(m => new LocalChatLine(m.sequence, target.OfficialFleet ? "" : (m.senderCallsign.Length == 0 ? m.senderGameId : m.senderCallsign),
                    m.text, DateTimeOffset.Parse(m.createdAt, System.Globalization.CultureInfo.InvariantCulture), m.isSelf, m.hasAttachment)).ToArray());
            token.ThrowIfCancellationRequested(); current();
            object result = new
            {
                schemaVersion = 1,
                targetRef = reference,
                unreadCount,
                canSend,
                latestSequence = latest,
                oldestSequence = oldest,
                hasOlder,
                serverTime,
                messages = items,
                localHistoryUnavailable = !saved
            };
            return authors is null ? result : CompleteOfficialChatAuthors(result, authors, pending.Select(row => (row.Reference, row.Target.SenderId)), current, publicationToken, operationStarted, reference, preview);
        });

    internal Task<object> ReadChatDetailAsync(string bearer, JsonElement body, string scope, Action current, CancellationToken token) =>
        GuardWorkspace(async () =>
        {
            Validate(body, "targetRef", "messageRef", "offset", "version", "authorIdentitySchemaVersion", "expectedAuthorIdentityVersion");
            string reference = Text(body, "targetRef", 32), messageRef = Text(body, "messageRef", 32);
            var offset = Number(body, "offset", 0, 2 * 1024 * 1024);
            var version = Optional(body, "version", 64);
            if (offset % ChatDetailChunkBytes != 0 || offset > 0 && version is null || version is not null && !LowerHex(version, 64)) throw Invalid();
            current();
            var target = Resolve(reference, scope, allowWpfS2: true);
            if (!_chatTargets.TryGetValue(messageRef, out var message) || message.Code != target.Code || message.Scope != scope ||
                message.Expires <= (target.OfficialFleet ? _targetClock.GetUtcNow() : DateTimeOffset.UtcNow)) throw new AccountBridgeHostException("communities.refreshRequired");
            if (OfficialAuthorDetailOptIn(body, target, false)) return await ReadOfficialChatAuthorDetail(bearer, body, reference, messageRef, target, message, scope, offset, version, current, token);
            var root = await WorkspaceJson(bearer, CommunicationPath(target, ChatHistoryPath(target.Code, message.ChannelId)["/api/fleets".Length..]) +
                $"&before={message.Sequence + 1}&limit=1", token, maximumBytes: 2 * 1024 * 1024);
            current();
            ChatObject(root);
            if (!Text(root, "channelId", 272).Equals(message.ChannelId, StringComparison.OrdinalIgnoreCase) || Optional(root, "error", 512) is not null) throw Invalid();
            var rows = Rows(root, "messages", 1);
            if (rows.Length != 1 || ChatSequence(rows[0], "sequence", positive: true) != message.Sequence ||
                Text(rows[0], "messageId", 128) != message.MessageId || Text(rows[0], "senderAccountId", 512) != message.SenderId)
                throw new AccountBridgeHostException("communities.notFound");
            var row = rows[0];
            ChatObject(row);
            if (!Text(row, "channelId", 272).Equals(message.ChannelId, StringComparison.OrdinalIgnoreCase)) throw Invalid();
            var avatar = target.WpfS2ViewerId is not null
                ? AnnouncementAvatar(Optional(row, "senderAvatarImageData", 720 * 1024))
                : ChatAvatar(Optional(row, "senderAvatarImageData", 700000));
            if (target.OfficialFleet) avatar = null;
            ChatAttachmentContract? attachment = null;
            if (row.TryGetProperty("attachment", out var raw) && raw.ValueKind != JsonValueKind.Null)
            {
                var candidate = raw.Deserialize<ChatAttachmentContract>(ChatJson);
                if (!ChatAttachmentPolicy.TryNormalize(candidate, out attachment, out _) ||
                    attachment is not null && attachment.Kind != ChatAttachmentKinds.OverlayPreset) throw Invalid();
            }
            var bytes = JsonSerializer.SerializeToUtf8Bytes(new { avatarImageData = avatar, attachment }, ChatJson);
            if (bytes.Length > 2 * 1024 * 1024 || offset >= bytes.Length) throw Invalid();
            var hash = Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
            if (version is not null && version != hash) throw new AccountBridgeHostException("communities.mediaChanged");
            var length = Math.Min(ChatDetailChunkBytes, bytes.Length - offset);
            int? next = offset + length < bytes.Length ? offset + length : null;
            token.ThrowIfCancellationRequested(); current();
            return new
            {
                schemaVersion = 1,
                targetRef = reference,
                messageRef,
                offset,
                next,
                totalBytes = bytes.Length,
                version = hash,
                data = Convert.ToBase64String(bytes, offset, length)
            };
        });

    private static string ChatHistoryPath(string code, string channel) => "/api/fleets/chat/messages?fleetCode=" +
        Uri.EscapeDataString(code) + "&channelId=" + Uri.EscapeDataString(channel);
    private static void ChatObject(JsonElement value)
    {
        if (value.ValueKind != JsonValueKind.Object || value.EnumerateObject().Select(p => p.Name).Distinct().Count() != value.EnumerateObject().Count()) throw Invalid();
    }
    private static long ChatSequence(JsonElement value, string key, bool positive = false)
    {
        var result = value.GetProperty(key).GetInt64();
        return result >= (positive ? 1 : 0) && result < long.MaxValue ? result : throw Invalid();
    }
    private static string? ChatAvatar(string? value)
    {
        if (string.IsNullOrEmpty(value)) return null;
        if (!value.StartsWith("data:image/", StringComparison.Ordinal)) throw Invalid();
        var split = value.IndexOf(";base64,", StringComparison.Ordinal);
        if (split < 0 || split > 32) throw Invalid();
        var mime = value[5..split];
        var bytes = Convert.FromBase64String(value[(split + 8)..]);
        if (bytes.Length is < 8 or > 512 * 1024) throw Invalid();
        var detected = bytes.AsSpan() switch
        {
            [137, 80, 78, 71, 13, 10, 26, 10, ..] => "image/png",
            [255, 216, 255, ..] => "image/jpeg",
            [66, 77, ..] => "image/bmp",
            [71, 73, 70, 56, 55 or 57, 97, ..] => "image/gif",
            [82, 73, 70, 70, _, _, _, _, 87, 69, 66, 80, ..] => "image/webp",
            _ => null,
        };
        if (mime != detected) throw Invalid();
        return "data:" + mime + ";base64," + Convert.ToBase64String(bytes);
    }
}
