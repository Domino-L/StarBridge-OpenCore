namespace StarBridge.HostRuntime.Friends;

using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Account;

internal sealed record DirectSendView(string TargetRef, string Status, string? Error = null, DirectMessageView? Message = null)
{ public int SchemaVersion => 1; }

internal sealed partial class FriendsReader
{
    // Never replay an uncertain POST. Cached outcomes are scoped to the authenticated owner,
    // recipient and immutable intent, not a UI conversation reference that can be refreshed.
    private readonly Dictionary<string, (string Text, DirectSendView Result)> _chatSends = new();

    internal static (string Reference, string Id, string Text) ParseChatSend(JsonElement payload)
    {
        try {
            var names = payload.EnumerateObject().Select(p => p.Name).ToArray();
            if (names.Length != 4 || names.Distinct().Count() != 4 ||
                names.Any(n => n is not ("schemaVersion" or "targetRef" or "clientMessageId" or "text")) ||
                payload.GetProperty("schemaVersion").GetInt32() != 1) throw ChatError("invalid_request");
            var reference = Text(payload, "targetRef", 32); var id = Text(payload, "clientMessageId", 32);
            var text = MessageText(payload, "text", 1000).Trim();
            if (!Guid.TryParseExact(reference, "N", out _) || !Guid.TryParseExact(id, "N", out _) || text.Length == 0)
                throw ChatError("invalid_request");
            return (reference, id, text);
        } catch (Exception e) when (e is InvalidOperationException or KeyNotFoundException or FormatException or OverflowException ||
            e is AccountBridgeHostException a && a.Code != "directMessages.invalid_request") { throw ChatError("invalid_request"); }
    }

    internal async Task<DirectSendView> SendChatAsync(string bearer, JsonElement payload, CancellationToken token,
        string scope, Action? ensureCurrent = null)
    {
        var (reference, id, text) = ParseChatSend(payload);
        DirectSendView Rejected(string reason) => new(reference, "rejected", reason);
        if (!await _commandGate.WaitAsync(0, token)) return Rejected("busy");
        try {
            ConversationTarget? target;
            lock (_targetGate) {
                if (!_conversations.TryGetValue(reference, out target) || target.Owner != Owner(bearer, scope) || target.Expires < DateTimeOffset.UtcNow)
                    return Rejected("target_changed");
            }
            var key = target.Owner + ":" + target.Id + ":" + id;
            if (_chatSends.TryGetValue(key, out var previous))
                return previous.Text == text ? previous.Result with { TargetRef = reference } : Rejected("invalid_request");
            if (_chatSends.Count >= 2048) return Rejected("limit");
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
            deadline.CancelAfter(TimeSpan.FromSeconds(12));
            // Fresh permission, without changing the history cursor or writing a read receipt.
            try {
                using var check = new HttpRequestMessage(HttpMethod.Get, new Uri(_origin,
                    "/api/friends/chat/messages?targetAccountId=" + Uri.EscapeDataString(target.Id) + "&limit=1"));
                check.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
                using var permission = await _http.SendAsync(check, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
                if (!permission.IsSuccessStatusCode) return Rejected(permission.StatusCode switch {
                    HttpStatusCode.Unauthorized => "identity_unavailable", HttpStatusCode.Forbidden => "forbidden",
                    HttpStatusCode.NotFound => "target_changed", _ => "unavailable" });
                using var document = JsonDocument.Parse(await CommandBody(permission, deadline.Token));
                var root = document.RootElement; RejectDuplicates(root);
                if (Text(root, "targetAccountId", 256) != target.Id) return Rejected("data_invalid");
                var state = ChatState(root);
                if (!root.GetProperty("canSend").GetBoolean() || state is not ("friend" or "accepted" or "none"))
                    return Rejected(state is "request_incoming" or "request_outgoing" ? "request_pending" : "forbidden");
            } catch (Exception e) when (e is HttpRequestException or IOException or OperationCanceledException or JsonException or
                InvalidOperationException or KeyNotFoundException or FormatException or AccountBridgeHostException) { return Rejected("unavailable"); }
            token.ThrowIfCancellationRequested();
            ensureCurrent?.Invoke();
            lock (_targetGate) {
                if (!_conversations.TryGetValue(reference, out var active) || active != target) return Rejected("target_changed");
            }
            var unknown = new DirectSendView(reference, "unknown", "outcome_unknown");
            _chatSends[key] = (text, unknown); // Consume before any write; cancellation also leaves an uncertain outcome.
            try {
                using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(_origin, "/api/friends/chat/messages"));
                request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
                request.Content = JsonContent.Create(new { targetAccountId = target.Id, text, clientMessageId = id, origin = "friend_center" });
                using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
                if (response.StatusCode is HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden or HttpStatusCode.NotFound or
                    HttpStatusCode.TooManyRequests or HttpStatusCode.BadRequest or HttpStatusCode.Conflict) {
                    var reason = response.StatusCode switch {
                        HttpStatusCode.Unauthorized => "identity_unavailable", HttpStatusCode.Forbidden => "forbidden",
                        HttpStatusCode.NotFound => "target_changed", HttpStatusCode.TooManyRequests => "rate_limited",
                        HttpStatusCode.Conflict => "request_pending", _ => "rejected" };
                    _chatSends.Remove(key); // Explicit rejection permits a deliberate retry.
                    return Rejected(reason);
                }
                if (!response.IsSuccessStatusCode) return unknown;
                using var document = JsonDocument.Parse(await CommandBody(response, deadline.Token));
                var root = document.RootElement; RejectDuplicates(root);
                var status = Text(root, "status", 64);
                if (status is not ("sent" or "duplicate" or "request_sent")) return unknown;
                var message = root.GetProperty("message");
                var sender = Text(message, "senderAccountId", 256);
                if (Text(message, "recipientAccountId", 256) != target.Id || string.IsNullOrWhiteSpace(sender) || sender == target.Id ||
                    (target.Viewer is not null && sender != target.Viewer) || Text(message, "messageId", 256) != id ||
                    MessageText(message, "text", 1000) != text || (message.TryGetProperty("attachment", out var attachment) && attachment.ValueKind != JsonValueKind.Null)) return unknown;
                var sequence = message.GetProperty("sequence").GetInt64();
                if (sequence <= 0) return unknown;
                var result = new DirectSendView(reference, status, Message: new(sequence, id, false, text, message.GetProperty("createdAt").GetDateTimeOffset(), null));
                _chatSends[key] = (text, result);
                return result;
            } catch (Exception e) when (e is HttpRequestException or IOException or OperationCanceledException or JsonException or
                InvalidOperationException or KeyNotFoundException or FormatException or OverflowException or AccountBridgeHostException) { return unknown; }
        } finally { _commandGate.Release(); }
    }
}
