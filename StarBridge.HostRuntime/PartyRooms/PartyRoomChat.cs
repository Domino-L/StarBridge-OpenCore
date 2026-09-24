namespace StarBridge.HostRuntime.PartyRooms;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.Core.Chat;
using StarBridge.Core.PartyRooms;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Overlay;

internal sealed record RoomChatMessageView(long Sequence, string MessageId, string Kind, string SenderCallsign,
    string SenderGameId, string Text, DateTimeOffset CreatedAt, ChatAttachmentContract? Attachment)
{
    public string? AvatarImageData { get; init; }
    public bool IsSelf { get; init; }
    [System.Text.Json.Serialization.JsonIgnore] public string? SenderAccountId { get; init; }
    public string? UserRef { get; init; }
}
internal sealed record RoomChatPageView(RoomChatMessageView[] Messages, long LatestSequence, bool HasOlder, long OldestSequence);
internal sealed partial class PartyRoomReader
{
    private static RoomChatMessageView ReadChatMessage(JsonElement value) {
        var sequence = value.GetProperty("sequence").GetInt64();
        if (sequence <= 0) throw Invalid();
        ChatAttachmentContract? attachment = null;
        if (value.TryGetProperty("attachment", out var raw) && raw.ValueKind != JsonValueKind.Null) {
            var contract = raw.Deserialize<ChatAttachmentContract>(new JsonSerializerOptions(JsonSerializerDefaults.Web));
            if (!ChatAttachmentPolicy.TryNormalize(contract, out attachment, out _)) throw Invalid();
        }
        return new(sequence, Text(value, "messageId", true), Text(value, "kind", true), Text(value, "senderCallsign"),
            Text(value, "senderGameId"), Text(value, "text"), value.GetProperty("createdAt").GetDateTimeOffset(), attachment)
        { SenderAccountId = value.TryGetProperty("senderAccountId", out var sender) && sender.ValueKind == JsonValueKind.String
            ? Text(value, "senderAccountId") : null,
          AvatarImageData = value.TryGetProperty("senderAvatarImageData", out var avatar) && avatar.ValueKind == JsonValueKind.String
            ? RoomAvatarProjection.Normalize(avatar.GetString()) : null };
    }
    private async Task<RoomCommandView> ExecuteChatAsync(string bearer, JsonElement payload, CancellationToken token) {
        string roomId, operation, text;
        ChatAttachmentContract? attachment = null;
        long after = 0, before = 0;
        try {
            if (payload.GetProperty("schemaVersion").GetInt32() != 1 ||
                payload.EnumerateObject().Any(item => item.Name is not ("schemaVersion" or "operation" or "data"))) throw Invalid();
            operation = Text(payload, "operation", true);
            var data = payload.GetProperty("data");
            var allowed = operation == "chatRead" ? new[] { "roomId", "after", "before" } : ["roomId", "text", "attachment"];
            if (data.EnumerateObject().Any(item => !allowed.Contains(item.Name))) throw Invalid();
            roomId = Text(data, "roomId", true);
            if (roomId.Length > 128) throw Invalid();
            text = operation == "chatSend" ? Text(data, "text").Trim() : "";
            if (operation == "chatSend" && data.TryGetProperty("attachment", out var raw) && raw.ValueKind != JsonValueKind.Null)
            {
                var candidate = raw.Deserialize<ChatAttachmentContract>(new JsonSerializerOptions(JsonSerializerDefaults.Web));
                if (!ChatAttachmentPolicy.TryNormalize(candidate, out attachment, out _) ||
                    attachment?.Kind != ChatAttachmentKinds.OverlayPreset) throw Invalid();
                try { _ = OverlaySharedPreset.Parse(attachment.OverlayPresetPackage); }
                catch (OverlaySettingsException) { throw Invalid(); }
            }
            if (text.Length > 300 || (operation == "chatSend" && text.Length == 0 && attachment is null)) throw Invalid();
            if (operation == "chatRead") {
                after = data.GetProperty("after").GetInt64(); before = data.GetProperty("before").GetInt64();
                if (after < 0 || before < 0 || (after > 0 && before > 0)) throw Invalid();
            }
        } catch (Exception error) when (error is InvalidOperationException or KeyNotFoundException or FormatException or JsonException) { throw Invalid(); }
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
        deadline.CancelAfter(TimeSpan.FromSeconds(12));
        RoomDirectoryView directory;
        try { directory = await ReadAsync(bearer, deadline.Token); }
        catch (AccountBridgeHostException error) when (error.Code is not ("party_rooms.identity_unavailable" or "party_rooms.forbidden"))
        { throw new AccountBridgeHostException("party_rooms.command_unavailable"); }
        if (directory.CurrentRoomId != roomId) return new("rejected", "notMember", directory, null);
        if (operation == "chatRead") {
            using var result = await ReadRoomJsonAsync(bearer, $"/api/party-rooms/chat?roomId={Uri.EscapeDataString(roomId)}&after={after}&before={before}&limit=50", deadline.Token);
            try {
                var root = result.RootElement;
                if (root.TryGetProperty("error", out var error) && error.ValueKind != JsonValueKind.Null) throw Invalid();
                var raw = root.GetProperty("messages");
                if (raw.GetArrayLength() > 50) throw Invalid();
                var messages = raw.EnumerateArray().Select(ReadChatMessage).ToArray();
                if (messages.Select(item => item.Sequence).Distinct().Count() != messages.Length ||
                    messages.Select(item => item.MessageId).Distinct().Count() != messages.Length) throw Invalid();
                var latest = root.GetProperty("latestSequence").GetInt64();
                var oldest = root.TryGetProperty("oldestSequence", out var oldestValue) ? oldestValue.GetInt64() : 0;
                if (latest < 0 || oldest < 0 || messages.Any(item => item.Sequence > latest)) throw Invalid();
                return new("chat", null, null, null) { AuthorizedOverlayDirectory = directory, Chat = new(messages, latest,
                    root.TryGetProperty("hasOlder", out var older) && older.GetBoolean(), oldest) };
            } catch (Exception error) when (error is InvalidOperationException or KeyNotFoundException or FormatException) { throw Invalid(); }
        }
        using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(_endpoint, "/api/party-rooms/chat"));
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
        request.Content = JsonContent.Create(new PartyRoomChatSendRequest(roomId, text, attachment));
        try {
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
            if (response.StatusCode == HttpStatusCode.Unauthorized) throw new AccountBridgeHostException("party_rooms.identity_unavailable");
            if (response.StatusCode == HttpStatusCode.Forbidden) throw new AccountBridgeHostException("party_rooms.forbidden");
            if (!response.IsSuccessStatusCode && response.StatusCode != HttpStatusCode.BadRequest) throw new AccountBridgeHostException("party_rooms.outcome_unknown");
            using var result = await ReadBoundedRoomJsonAsync(response, deadline.Token);
            if (!response.IsSuccessStatusCode) return new("rejected", "chatRejected", null, null);
            return new("sent", null, null, null) { AuthorizedOverlayDirectory = directory, Message = ReadChatMessage(result.RootElement.GetProperty("message")) };
        } catch (AccountBridgeHostException error) when (error.Code == "party_rooms.data_invalid") { throw new AccountBridgeHostException("party_rooms.outcome_unknown"); }
        catch (Exception error) when (error is HttpRequestException or IOException or OperationCanceledException or JsonException or InvalidOperationException or KeyNotFoundException)
        { throw new AccountBridgeHostException("party_rooms.outcome_unknown"); }
    }
}
