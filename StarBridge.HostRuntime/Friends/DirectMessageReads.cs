namespace StarBridge.HostRuntime.Friends;

using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.PartyRooms;
using StarBridge.HostRuntime.Chat;

internal sealed record ConversationView(string TargetRef, string Callsign, string GameId, string? AvatarImageData,
    string Preview, DateTimeOffset LastMessageAt, int UnreadCount, string State)
{
    public string? ConversationKey { get; init; }
    public long? LatestSequence { get; init; }
    public bool? LastMessageIncoming { get; init; }
}
internal sealed record ConversationsView(ConversationView[] Conversations, int TotalUnread, DateTimeOffset ServerTime)
{ public int SchemaVersion => 1; }
internal sealed record DirectMessageView(long Sequence, string MessageId, bool Incoming, string Text,
    DateTimeOffset CreatedAt, string? AttachmentKind)
{ public DirectCommunityInvitationView? CommunityInvitation { get; init; } }
internal sealed record DirectCommunityInvitationView(string Title, string Summary, string InviteCode, DateTimeOffset? ExpiresAt);
internal sealed record DirectHistoryView(string TargetRef, DirectMessageView[] Messages, long LatestSequence,
    long OldestSequence, bool HasOlder, string State, bool CanSend)
{ public int SchemaVersion => 1; public bool LocalHistoryUnavailable { get; init; } }

internal sealed partial class FriendsReader
{
    private sealed record ConversationTarget(string Owner, string Id, DateTimeOffset Expires,
        long Oldest = 0, long Newest = 0, string? Viewer = null, string DisplayName = "");
    private readonly Dictionary<string, ConversationTarget> _conversations = new(StringComparer.Ordinal);
    private static AccountBridgeHostException ChatError(string code) => new("directMessages." + code);
    private static string ChatState(JsonElement value) => Text(value, "conversationState", 64) is var state &&
        state is "none" or "friend" or "accepted" or "request_incoming" or "request_outgoing" ? state : "unknown";
    internal static (string? Reference, long Before, long After) ParseChatRead(JsonElement payload)
    {
        try {
            var names = payload.EnumerateObject().Select(p => p.Name).ToArray();
            if (names.Distinct().Count() != names.Length || names.Any(n => n is not ("schemaVersion" or "targetRef" or "before" or "after" or "localHistory")) ||
                payload.GetProperty("schemaVersion").GetInt32() != 1) throw ChatError("invalid_request");
            var reference = payload.TryGetProperty("targetRef", out var r) ? r.GetString() : null;
            var before = payload.TryGetProperty("before", out var b) ? b.GetInt64() : 0;
            var after = payload.TryGetProperty("after", out var a) ? a.GetInt64() : 0;
            if (reference is null ? names.Length != 1 : !Guid.TryParseExact(reference, "N", out _)) throw ChatError("invalid_request");
            if (before < 0 || after < 0 || (before > 0 && after > 0)) throw ChatError("invalid_request");
            if (payload.TryGetProperty("localHistory", out var local) &&
                (reference is null || before != 0 || after != 0 || local.GetString() is not ("read" or "clear"))) throw ChatError("invalid_request");
            return (reference, before, after);
        } catch (Exception e) when (e is InvalidOperationException or KeyNotFoundException or FormatException or OverflowException) { throw ChatError("invalid_request"); }
    }

    internal async Task<object> ReadChatAsync(string bearer, JsonElement payload, CancellationToken token, string scope, string? archiveAccount = null)
    {
        var (reference, before, after) = ParseChatRead(payload);
        ConversationTarget? target = null;
        if (reference is not null) lock (_targetGate) {
            if (!_conversations.TryGetValue(reference, out target) || target.Owner != Owner(bearer, scope) || target.Expires < DateTimeOffset.UtcNow ||
                (before > 0 && before != target.Oldest) || (after > 0 && after != target.Newest)) throw ChatError("target_changed");
        }
        if (payload.TryGetProperty("localHistory", out var local))
        {
            if (target is null || archiveAccount is null) throw ChatError("identity_unavailable");
            token.ThrowIfCancellationRequested();
            return await ChatHistoryArchive.Read(archiveAccount, "private:" + target.Id, local.GetString()!);
        }
        var path = target is null ? "/api/friends/chat/conversations?includePresence=false" :
            "/api/friends/chat/messages?targetAccountId=" + Uri.EscapeDataString(target.Id) + $"&before={before}&after={after}&limit=50";
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
        deadline.CancelAfter(TimeSpan.FromSeconds(12));
        using var request = new HttpRequestMessage(HttpMethod.Get, new Uri(_origin, path));
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
        try {
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
            if (response.StatusCode == HttpStatusCode.Unauthorized) throw ChatError("identity_unavailable");
            if (response.StatusCode == HttpStatusCode.Forbidden) throw ChatError("forbidden");
            if (response.StatusCode == HttpStatusCode.NotFound) throw ChatError("target_changed");
            if (!response.IsSuccessStatusCode) throw ChatError("unavailable");
            using var document = JsonDocument.Parse(await CommandBody(response, deadline.Token));
            var root = document.RootElement;
            RejectDuplicates(root);
            if (target is null) return ParseConversations(root, bearer, scope);
            var history = ParseHistory(root, reference!, target, before, after);
            token.ThrowIfCancellationRequested();
            var saved = await ChatHistoryArchive.Save(archiveAccount, "private:" + target.Id,
                history.Messages.Select(m => new LocalChatLine(m.Sequence, m.Incoming ? target.DisplayName : "", m.Text, m.CreatedAt, !m.Incoming, m.AttachmentKind is not null)).ToArray());
            return history with { LocalHistoryUnavailable = !saved };
        } catch (OperationCanceledException) when (!token.IsCancellationRequested) { throw ChatError("unavailable"); }
        catch (Exception e) when (e is HttpRequestException or IOException) { throw ChatError("unavailable"); }
        catch (Exception e) when (e is JsonException or InvalidOperationException or FormatException or KeyNotFoundException or OverflowException) { throw ChatError("data_invalid"); }
        catch (AccountBridgeHostException e) when (e.Code.StartsWith("friends.", StringComparison.Ordinal)) { throw ChatError("data_invalid"); }
    }

    private ConversationsView ParseConversations(JsonElement root, string bearer, string scope)
    {
        var array = root.GetProperty("conversations");
        if (array.GetArrayLength() > 2000) throw ChatError("data_invalid");
        var targets = new Dictionary<string, ConversationTarget>(StringComparer.Ordinal);
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        var rows = array.EnumerateArray().Select(entry => {
            var user = entry.GetProperty("user"); var id = Text(user, "accountId", 256);
            if (string.IsNullOrWhiteSpace(id) || !seen.Add(id)) throw ChatError("data_invalid");
            var reference = Guid.NewGuid().ToString("N");
            targets.Add(reference, new(Owner(bearer, scope), id, DateTimeOffset.UtcNow.AddMinutes(30), DisplayName: Text(user, "callsign", 512)));
            var unread = entry.GetProperty("unreadCount").GetInt32();
            if (unread < 0) throw ChatError("data_invalid");
            long? sequence = entry.TryGetProperty("latestSequence", out var latest) ? latest.GetInt64() : null;
            if (sequence < 0) throw ChatError("data_invalid");
            var sender = entry.TryGetProperty("lastSenderAccountId", out _) ? Text(entry, "lastSenderAccountId", 256) : null;
            return new ConversationView(reference, Text(user, "callsign", 512), Text(user, "gameId", 512),
                user.TryGetProperty("avatarImageData", out var avatar) && avatar.ValueKind == JsonValueKind.String ? RoomAvatarProjection.Normalize(avatar.GetString()) : null,
                MessageText(entry, "lastMessagePreview", 4096), entry.GetProperty("lastMessageAt").GetDateTimeOffset(), unread, ChatState(entry)) {
                    ConversationKey = ConversationKey(Owner(bearer, scope), id, scope),
                    LatestSequence = sequence,
                    LastMessageIncoming = string.IsNullOrWhiteSpace(sender) ? null : sender == id,
                };
        }).ToArray();
        var total = root.GetProperty("totalUnread").GetInt32();
        if (total < 0 || rows.Sum(r => (long)r.UnreadCount) != total) throw ChatError("data_invalid");
        var result = new ConversationsView(rows, total, root.GetProperty("serverTime").GetDateTimeOffset());
        lock (_targetGate) {
            // A background inbox refresh must not replace an open chat's command
            // reference or paging state, including a history read still in flight.
            var existing = _conversations.Where(pair => !_friendChatTargets.Contains(pair.Key) &&
                    pair.Value.Owner == Owner(bearer, scope) && pair.Value.Expires >= DateTimeOffset.UtcNow)
                .GroupBy(pair => pair.Value.Id, StringComparer.Ordinal)
                .ToDictionary(group => group.Key, group => group.First(), StringComparer.Ordinal);
            for (var index = 0; index < rows.Length; index++) {
                var issued = rows[index].TargetRef;
                if (!existing.TryGetValue(targets[issued].Id, out var active)) continue;
                targets.Remove(issued);
                targets.Add(active.Key, active.Value);
                rows[index] = rows[index] with { TargetRef = active.Key };
            }
            // The recent-conversation directory must not retire the independent
            // friend-card references when returning from private messages.
            foreach (var key in _conversations.Keys.Where(key => !_friendChatTargets.Contains(key)).ToArray())
                _conversations.Remove(key);
            foreach (var pair in targets) _conversations.Add(pair.Key, pair.Value);
        }
        return result;
    }

    private DirectHistoryView ParseHistory(JsonElement root, string reference, ConversationTarget target, long before, long after)
    {
        if (Text(root, "targetAccountId", 256) != target.Id) throw ChatError("data_invalid");
        var array = root.GetProperty("messages");
        if (array.GetArrayLength() > 50) throw ChatError("data_invalid");
        var ids = new HashSet<string>(StringComparer.Ordinal); long previous = 0; var viewer = target.Viewer;
        var rows = array.EnumerateArray().Select(entry => {
            var sequence = entry.GetProperty("sequence").GetInt64(); var id = Text(entry, "messageId", 256);
            var sender = Text(entry, "senderAccountId", 256); var recipient = Text(entry, "recipientAccountId", 256);
            if (sequence <= previous || (before > 0 && sequence >= before) || sequence <= after ||
                string.IsNullOrWhiteSpace(id) || !ids.Add(id) || string.IsNullOrWhiteSpace(sender) || string.IsNullOrWhiteSpace(recipient) ||
                (sender == target.Id) == (recipient == target.Id)) throw ChatError("data_invalid");
            var other = sender == target.Id ? recipient : sender;
            viewer ??= other;
            if (viewer != other) throw ChatError("data_invalid");
            previous = sequence;
            string? kind = null;
            DirectCommunityInvitationView? invitation = null;
            if (entry.TryGetProperty("attachment", out var attachment) && attachment.ValueKind != JsonValueKind.Null)
            {
                kind = Text(attachment, "kind", 64) is var k && k is "overlay_preset" or "party_room_invitation" or "fleet_invitation" ? k : "unknown";
                if (kind == "fleet_invitation")
                {
                    var title = Text(attachment, "title", 64);
                    var summary = Text(attachment, "summary", 240);
                    var code = Text(attachment, "fleetInviteCode", 40);
                    if (string.IsNullOrWhiteSpace(title) || string.IsNullOrWhiteSpace(summary) || code.Trim().Length < 6)
                        throw ChatError("data_invalid");
                    DateTimeOffset? expiry = attachment.TryGetProperty("expiresAt", out var value) && value.ValueKind != JsonValueKind.Null
                        ? value.GetDateTimeOffset() : null;
                    invitation = new(title, summary, code, expiry);
                }
            }
            return new DirectMessageView(sequence, id, sender == target.Id, MessageText(entry, "text", 4096), entry.GetProperty("createdAt").GetDateTimeOffset(), kind)
            { CommunityInvitation = invitation };
        }).ToArray();
        var latest = root.GetProperty("latestSequence").GetInt64(); var oldest = root.GetProperty("oldestSequence").GetInt64();
        var hasOlder = root.GetProperty("hasOlder").GetBoolean();
        if (latest < Math.Max(previous, after) || oldest != (rows.FirstOrDefault()?.Sequence ?? 0) || (hasOlder && oldest == 0)) throw ChatError("data_invalid");
        var result = new DirectHistoryView(reference, rows, latest, oldest, hasOlder, ChatState(root), root.GetProperty("canSend").GetBoolean());
        lock (_targetGate) {
            if (!_conversations.TryGetValue(reference, out var active) || active != target) throw ChatError("target_changed");
            _conversations[reference] = target with { Viewer = viewer, Expires = DateTimeOffset.UtcNow.AddMinutes(30),
                Oldest = after > 0 ? target.Oldest : oldest,
                Newest = before > 0 ? target.Newest : rows.LastOrDefault()?.Sequence ?? target.Newest };
        }
        return result;
    }
    private static string MessageText(JsonElement root, string key, int max)
    {
        var text = root.GetProperty(key).GetString() ?? "";
        if (text.Length > max || text.Any(c => char.IsControl(c) && c is not ('\n' or '\r' or '\t'))) throw ChatError("data_invalid");
        return text;
    }
}
