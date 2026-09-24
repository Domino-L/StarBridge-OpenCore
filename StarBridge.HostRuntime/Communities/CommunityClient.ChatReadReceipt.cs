using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.Core.FleetChat;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    internal async Task<object> MarkChatReadAsync(string bearer, JsonElement body, string scope, Action current, CancellationToken token)
    {
        // No arbitrary sequence or raw channel is accepted from the UI. A receipt
        // must refer to a message this account actually fetched in this organization.
        Validate(body, "targetRef", "messageRef");
        string targetRef = Text(body, "targetRef", 32), messageRef = Text(body, "messageRef", 32);
        if (!LowerHex(targetRef, 32) || !LowerHex(messageRef, 32)) throw Invalid();
        var sent = false;
        object Result(string status, string? error = null, long? through = null) => new
        {
            schemaVersion = 1, targetRef, messageRef, status, error, readThroughSequence = through,
        };
        try
        {
            current();
            var target = Resolve(targetRef, scope, allowWpfS2: true);
            if (!_chatTargets.TryGetValue(messageRef, out var message) || message.Code != target.Code ||
                message.Scope != scope || message.Expires <= DateTimeOffset.UtcNow)
                return Result("rejected", "refreshRequired");
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
            deadline.CancelAfter(TimeSpan.FromSeconds(12));
            using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(_origin, "/api/fleets/chat/read"))
            {
                Content = JsonContent.Create(new FleetChatMarkReadRequestContract(target.Code, message.ChannelId, message.Sequence)),
            };
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
            current();
            deadline.Token.ThrowIfCancellationRequested();
            sent = true;
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
            current();
            if (response.StatusCode != HttpStatusCode.OK)
                return Result(response.StatusCode is HttpStatusCode.BadRequest or HttpStatusCode.Unauthorized or
                    HttpStatusCode.Forbidden or HttpStatusCode.NotFound or HttpStatusCode.TooManyRequests ? "rejected" : "unknown",
                    response.StatusCode switch
                    {
                        HttpStatusCode.BadRequest => "dataInvalid",
                        HttpStatusCode.Unauthorized => "identityUnavailable",
                        HttpStatusCode.Forbidden => "notAllowed",
                        HttpStatusCode.NotFound => "refreshRequired",
                        HttpStatusCode.TooManyRequests => "rateLimited",
                        _ => "outcomeUnknown",
                    });
            using var stream = await response.Content.ReadAsStreamAsync(deadline.Token);
            var bytes = new byte[4097];
            var length = 0;
            int count;
            while (length < bytes.Length && (count = await stream.ReadAsync(bytes.AsMemory(length), deadline.Token)) > 0) length += count;
            if (length > 4096) return Result("unknown", "outcomeUnknown");
            using var document = JsonDocument.Parse(bytes.AsMemory(0, length));
            var root = document.RootElement;
            ChatObject(root);
            var through = ChatSequence(root, "readThroughSequence", positive: true);
            // Another device may already have advanced farther. Never clamp its
            // cursor back to this page, or pretend an incomplete receipt succeeded.
            if (!Text(root, "channelId", 272).Equals(message.ChannelId, StringComparison.OrdinalIgnoreCase) ||
                through < message.Sequence || Optional(root, "error", 512) is not null)
                return Result("unknown", "outcomeUnknown");
            deadline.Token.ThrowIfCancellationRequested();
            current();
            return Result("accepted", through: through);
        }
        catch (Exception e) when (e is HttpRequestException or IOException or OperationCanceledException or JsonException or
            InvalidOperationException or KeyNotFoundException or FormatException or OverflowException or AccountBridgeHostException or
            StarBridge.NativeBridge.BridgeStaleGenerationException)
        {
            // Never trigger the OAuth retry path after POST, and never clear the
            // badge based on an unconfirmed response. The same visible reference
            // can be explicitly submitted again: the server cursor is monotonic.
            return Result(sent ? "unknown" : "rejected", sent ? "outcomeUnknown" : "refreshRequired");
        }
    }
}
