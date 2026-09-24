namespace StarBridge.HostRuntime.Friends;

using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.Core.Friends;
using StarBridge.HostRuntime.Account;

internal sealed record DirectReadReceiptView(string TargetRef, long ReadThroughSequence, int UnreadCount)
{ public int SchemaVersion => 1; }

internal sealed partial class FriendsReader
{
    internal static (string Reference, long Through) ParseChatMarkRead(JsonElement payload)
    {
        try {
            var names = payload.EnumerateObject().Select(p => p.Name).ToArray();
            if (names.Length != 3 || names.Distinct().Count() != 3 ||
                names.Any(n => n is not ("schemaVersion" or "targetRef" or "throughSequence")) ||
                payload.GetProperty("schemaVersion").GetInt32() != 1) throw ChatError("invalid_request");
            var reference = Text(payload, "targetRef", 32);
            var through = payload.GetProperty("throughSequence").GetInt64();
            if (!Guid.TryParseExact(reference, "N", out _) || through <= 0) throw ChatError("invalid_request");
            return (reference, through);
        } catch (Exception e) when (e is InvalidOperationException or KeyNotFoundException or FormatException or OverflowException ||
            e is AccountBridgeHostException a && a.Code != "directMessages.invalid_request") { throw ChatError("invalid_request"); }
    }

    internal async Task<DirectReadReceiptView> MarkChatReadAsync(string bearer, JsonElement payload,
        CancellationToken token, string scope, Action? ensureCurrent = null)
    {
        var (reference, through) = ParseChatMarkRead(payload);
        ConversationTarget target;
        lock (_targetGate) {
            if (!_conversations.TryGetValue(reference, out target!) || target.Owner != Owner(bearer, scope) ||
                target.Expires < DateTimeOffset.UtcNow || through > target.Newest || target.Viewer is null)
                throw ChatError("target_changed");
        }
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
        deadline.CancelAfter(TimeSpan.FromSeconds(12));
        try {
            ensureCurrent?.Invoke();
            deadline.Token.ThrowIfCancellationRequested();
            // Existing S2 endpoint rechecks block/access policy; cursor is limited to
            // history already delivered to this account-scoped target, not latest metadata.
            using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(_origin, "/api/friends/chat/read"));
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
            request.Content = JsonContent.Create(new FriendChatMarkReadRequestContract(target.Id, through));
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
            if (response.StatusCode == HttpStatusCode.Unauthorized) throw ChatError("identity_unavailable");
            if (response.StatusCode == HttpStatusCode.Forbidden) throw ChatError("forbidden");
            if (!response.IsSuccessStatusCode) throw ChatError("unavailable");
            using var body = JsonDocument.Parse(await CommandBody(response, deadline.Token));
            var root = body.RootElement; RejectDuplicates(root);
            var acknowledged = root.GetProperty("readThroughSequence").GetInt64();
            if (Text(root, "targetAccountId", 256) != target.Id || acknowledged < through) throw ChatError("data_invalid");
            ensureCurrent?.Invoke();
            using var counts = new HttpRequestMessage(HttpMethod.Get, new Uri(_origin, "/api/friends/chat/conversations?includePresence=false"));
            counts.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
            using var directory = await _http.SendAsync(counts, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
            if (!directory.IsSuccessStatusCode) throw ChatError("unavailable");
            using var data = JsonDocument.Parse(await CommandBody(directory, deadline.Token));
            RejectDuplicates(data.RootElement);
            var entries = data.RootElement.GetProperty("conversations");
            if (entries.GetArrayLength() > 2000) throw ChatError("data_invalid");
            var matching = entries.EnumerateArray().Where(e => Text(e.GetProperty("user"), "accountId", 256) == target.Id).ToArray();
            if (matching.Length != 1) throw ChatError("target_changed");
            var unread = matching[0].GetProperty("unreadCount").GetInt32();
            if (unread < 0) throw ChatError("data_invalid");
            ensureCurrent?.Invoke();
            lock (_targetGate) {
                if (!_conversations.TryGetValue(reference, out var current) || current.Owner != target.Owner ||
                    current.Id != target.Id) throw ChatError("target_changed");
            }
            // Do not regenerate conversation references or alter history paging.
            return new(reference, acknowledged, unread);
        } catch (OperationCanceledException) when (!token.IsCancellationRequested) { throw ChatError("unavailable"); }
        catch (Exception e) when (e is HttpRequestException or IOException) { throw ChatError("unavailable"); }
        catch (Exception e) when (e is JsonException or InvalidOperationException or KeyNotFoundException or FormatException or OverflowException)
        { throw ChatError("data_invalid"); }
    }
}
