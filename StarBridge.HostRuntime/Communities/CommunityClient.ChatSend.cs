using System.Collections.Concurrent;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StarBridge.Core.Chat;
using StarBridge.Core.FleetChat;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    private sealed record ChatSendResult(string Status, string? Error = null, long? Sequence = null);
    private sealed record ChatAttempt(string Code, string Scope, string RequestId, string Fingerprint, string TextHash, bool HasAttachment,
        ChatSendResult Result, DateTimeOffset CreatedAt);
    private readonly ConcurrentDictionary<string, ChatAttempt> _chatAttempts = new();

    internal async Task<object> SendChatAsync(string bearer, JsonElement body, string scope, Action current, CancellationToken token)
    {
        var (targetRef, requestId, text, attachment) = ParseChatSend(body);
        var fingerprint = Convert.ToHexString(SHA256.HashData(JsonSerializer.SerializeToUtf8Bytes(new { text, attachment }, ChatJson)));
        object Receipt(ChatSendResult result) => new
            { schemaVersion = 1, targetRef, requestId, status = result.Status, error = result.Error, sequence = result.Sequence };
        if (!await _write.WaitAsync(0, token)) return Receipt(new("rejected", "busy"));
        string? key = null;
        var sent = false;
        try
        {
            current();
            var target = Resolve(targetRef, scope, allowWpfS2: true);
            key = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(scope + "\0" + target.Code + "\0" + requestId))).ToLowerInvariant();
            if (_chatAttempts.TryGetValue(key, out var prior))
                return Receipt(prior.Fingerprint == fingerprint ? prior.Result : new("rejected", "intentConflict"));
            foreach (var old in _chatAttempts.Where(p => p.Value.Result.Status != "unknown" &&
                         p.Value.CreatedAt < DateTimeOffset.UtcNow.AddMinutes(-10)).ToArray())
                _chatAttempts.TryRemove(old.Key, out _);
            if (_chatAttempts.Count >= 2048) return Receipt(new("rejected", "refreshRequired"));
            var channel = FleetChatIdentity.FleetChannelId(target.Code);
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
            deadline.CancelAfter(TimeSpan.FromSeconds(12));
            using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(_origin, "/api/fleets/chat/messages"))
                { Content = JsonContent.Create(new FleetChatSendRequestContract(target.Code, channel, text, key, attachment)) };
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
            current();
            deadline.Token.ThrowIfCancellationRequested();
            _chatAttempts[key] = new(target.Code, scope, requestId, fingerprint, ChatTextHash(text), attachment is not null,
                new("unknown", "outcomeUnknown"), DateTimeOffset.UtcNow);
            sent = true;
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
            current();
            ChatSendResult result;
            if (response.StatusCode != HttpStatusCode.OK)
            {
                result = response.StatusCode switch
                {
                    HttpStatusCode.BadRequest => new("rejected", "dataInvalid"),
                    HttpStatusCode.Unauthorized => new("rejected", "identityUnavailable"),
                    HttpStatusCode.Forbidden => new("rejected", "notAllowed"),
                    HttpStatusCode.NotFound => new("rejected", "refreshRequired"),
                    HttpStatusCode.Conflict => new("rejected", "intentConflict"),
                    HttpStatusCode.TooManyRequests => new("rejected", "rateLimited"),
                    _ => new("unknown", "outcomeUnknown"),
                };
            }
            else
            {
                // Existing WPF response includes the publisher's original avatar
                // and attachment. Bound its read, then export only the receipt.
                using var stream = await response.Content.ReadAsStreamAsync(deadline.Token);
                using var buffer = new MemoryStream();
                var chunk = new byte[8192];
                int count;
                while ((count = await stream.ReadAsync(chunk, deadline.Token)) > 0)
                {
                    if (buffer.Length + count > 2 * 1024 * 1024) throw Invalid();
                    buffer.Write(chunk, 0, count);
                }
                using var document = JsonDocument.Parse(buffer.ToArray());
                var root = document.RootElement;
                ChatObject(root);
                var message = root.GetProperty("message");
                ChatObject(message);
                var status = Optional(root, "status", 16);
                if (Optional(root, "error", 512) is not null ||
                    status is not ("sent" or "duplicate") && !(status is null && target.WpfS2ViewerId is not null) ||
                    target.WpfS2ViewerId is not null && Text(message, "senderAccountId", 512) != target.WpfS2ViewerId ||
                    Text(message, "messageId", 128) != key ||
                    !Text(message, "channelId", 272).Equals(channel, StringComparison.OrdinalIgnoreCase) ||
                    Text(message, "text", 1000, multiline: true) != text) throw Invalid();
                ChatAttachmentContract? returned = null;
                if (message.TryGetProperty("attachment", out var returnedRaw) && returnedRaw.ValueKind != JsonValueKind.Null)
                {
                    if (!ChatAttachmentPolicy.TryNormalize(returnedRaw.Deserialize<ChatAttachmentContract>(ChatJson), out returned, out _)) throw Invalid();
                }
                if (returned != attachment) throw Invalid();
                result = new("accepted", Sequence: ChatSequence(message, "sequence", positive: true));
            }
            deadline.Token.ThrowIfCancellationRequested();
            current();
            // A concurrent authenticated history read may already have confirmed
            // a lost POST. Never replace that evidence with an uncertain result.
            if (!_chatAttempts.TryGetValue(key, out var entry)) return Receipt(new("unknown", "outcomeUnknown"));
            if (entry.Result.Status != "accepted") _chatAttempts.TryUpdate(key, entry with { Result = result }, entry);
            return Receipt(_chatAttempts.TryGetValue(key, out var latest) ? latest.Result : new("unknown", "outcomeUnknown"));
        }
        catch (Exception e) when (e is HttpRequestException or IOException or OperationCanceledException or JsonException or
            InvalidOperationException or KeyNotFoundException or FormatException or OverflowException or AccountBridgeHostException or
            StarBridge.NativeBridge.BridgeStaleGenerationException)
        {
            // No POST replay after an uncertain outcome. Reconcile via an actual
            // self-authored message during history refresh instead.
            return Receipt(new(sent ? "unknown" : "rejected", sent ? "outcomeUnknown" : "refreshRequired"));
        }
        finally { _write.Release(); }
    }

    private static (string TargetRef, string RequestId, string Text, ChatAttachmentContract? Attachment) ParseChatSend(JsonElement body)
    {
        try
        {
            Validate(body, "targetRef", "requestId", "text", "attachment");
            string targetRef = Text(body, "targetRef", 32), requestId = Text(body, "requestId", 32);
            if (!LowerHex(targetRef, 32) || !LowerHex(requestId, 32)) throw Invalid();
            var text = Text(body, "text", 1000, multiline: true).Trim();
            ChatAttachmentContract? attachment = null;
            if (body.TryGetProperty("attachment", out var raw) && raw.ValueKind != JsonValueKind.Null)
            {
                ChatObject(raw);
                if (raw.EnumerateObject().Any(p => p.Name is not ("kind" or "title" or "summary" or "overlayPresetPackage"))) throw Invalid();
                var candidate = new ChatAttachmentContract(Text(raw, "kind", 32), Text(raw, "title", 64),
                    Text(raw, "summary", 240), Text(raw, "overlayPresetPackage", 96 * 1024, multiline: true));
                if (!ChatAttachmentPolicy.TryNormalize(candidate, out attachment, out _) ||
                    attachment is null || attachment.Kind != ChatAttachmentKinds.OverlayPreset) throw Invalid();
            }
            if (text.Length == 0 && attachment is null) throw Invalid();
            return (targetRef, requestId, text, attachment);
        }
        catch (Exception e) when (e is InvalidOperationException or KeyNotFoundException or FormatException or OverflowException or JsonException)
        { throw Invalid(); }
    }

    private static string ChatTextHash(string text) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(text)));
    private string? ChatRequestId(string messageId, string code, string scope, bool isSelf, string text, bool hasAttachment) =>
        isSelf && _chatAttempts.TryGetValue(messageId, out var entry) && entry.Code == code && entry.Scope == scope &&
        entry.TextHash == ChatTextHash(text) && entry.HasAttachment == hasAttachment &&
        entry.Result.Status is "accepted" or "unknown" ? entry.RequestId : null;

    private void ConfirmChatRequest(string messageId, string code, string scope, long sequence)
    {
        if (_chatAttempts.TryGetValue(messageId, out var entry) && entry.Code == code && entry.Scope == scope && entry.Result.Status == "unknown")
            _chatAttempts.TryUpdate(messageId, entry with { Result = new("accepted", Sequence: sequence) }, entry);
    }
}
