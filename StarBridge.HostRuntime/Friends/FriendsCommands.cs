namespace StarBridge.HostRuntime.Friends;

using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StarBridge.Core.Friends;
using StarBridge.HostRuntime.Account;

internal sealed record FriendCommandView(string Status, string? Error = null, FriendsView? Directory = null)
{ public int SchemaVersion => 1; }

internal sealed partial class FriendsReader
{
    private sealed record Target(string Owner, string Id, string Relation, string? Query, DateTimeOffset Expires);
    private readonly byte[] _conversationKey = RandomNumberGenerator.GetBytes(32);
    private string ConversationKey(string owner, string id, string scope) => Convert.ToHexString(
        HMACSHA256.HashData(_conversationKey, Encoding.UTF8.GetBytes((scope.Length == 0 ? owner : scope) + "\n" + id.ToUpperInvariant())));
    private readonly object _targetGate = new();
    private readonly Dictionary<string, Target> _targets = new(StringComparer.Ordinal);
    private readonly HashSet<string> _friendChatTargets = new(StringComparer.Ordinal);
    private readonly SemaphoreSlim _commandGate = new(1, 1);
    private static string Owner(string bearer, string scope) => Convert.ToHexString(
        SHA256.HashData(Encoding.UTF8.GetBytes(scope + "\n" + bearer)));

    internal static string[] AllowedActions(string relation) => relation switch {
        "none" => ["send", "block"], "friend" => ["remove", "block"],
        "incoming" => ["accept", "reject", "block"], "outgoing" => ["cancel", "block"],
        "blocked" => ["unblock"], _ => []
    };
    private static IEnumerable<FriendView> All(FriendsView view) =>
        view.Friends.Concat(view.Incoming).Concat(view.Outgoing).Concat(view.Blocked).Concat(view.Results);

    private FriendsView IssueTargets(FriendsView view, string bearer, string scope, bool append = false)
    {
        lock (_targetGate)
        {
            var owner = Owner(bearer, scope);
            if (!append) {
                _targets.Clear(); // An explicit directory refresh replaces its command targets.
                foreach (var old in _friendChatTargets) _conversations.Remove(old);
                _friendChatTargets.Clear();
            } else {
                // Avatar reads must not invalidate another visible card or open chat.
                foreach (var key in _targets.Where(p => p.Value.Owner != owner || p.Value.Expires <= DateTimeOffset.UtcNow)
                             .Select(p => p.Key).ToArray()) _targets.Remove(key);
                foreach (var key in _friendChatTargets.Where(key => !_conversations.TryGetValue(key, out var chat) ||
                             chat.Owner != owner || chat.Expires <= DateTimeOffset.UtcNow).ToArray()) {
                    _friendChatTargets.Remove(key);
                    _conversations.Remove(key);
                }
                if (_targets.Count + All(view).Count() > 8192) throw Invalid();
                if (_friendChatTargets.Count + All(view).Count() > 8192) throw Invalid();
            }
            FriendView[] Rows(FriendView[] rows) => rows.Select(row => {
                var actions = AllowedActions(row.Relationship);
                if (actions.Length == 0) return row;
                var reference = Guid.NewGuid().ToString("N");
                _targets.Add(reference, new(owner, row.AccountId, row.Relationship, view.Query, DateTimeOffset.UtcNow.AddMinutes(5)));
                RememberAvatar(reference, _targets[reference]);
                string? chatReference = null;
                if (row.Relationship == "friend") {
                    chatReference = Guid.NewGuid().ToString("N");
                    _conversations[chatReference] = new(owner, row.AccountId, DateTimeOffset.UtcNow.AddMinutes(30), DisplayName: row.Callsign);
                    _friendChatTargets.Add(chatReference);
                }
                return row with { TargetRef = reference, ChatTargetRef = chatReference, Actions = actions,
                    ConversationKey = chatReference is null ? null : ConversationKey(owner, row.AccountId, scope) };
            }).ToArray();
            return view with { Friends = Rows(view.Friends), Incoming = Rows(view.Incoming),
                Outgoing = Rows(view.Outgoing), Blocked = Rows(view.Blocked), Results = Rows(view.Results) };
        }
    }

    internal static (string Action, string Reference) ParseCommand(JsonElement payload)
    {
        try {
            var names = payload.EnumerateObject().Select(p => p.Name).ToArray();
            if (names.Length != 3 || names.Distinct().Count() != 3 ||
                names.Any(n => n is not ("schemaVersion" or "action" or "targetRef")) ||
                payload.GetProperty("schemaVersion").GetInt32() != 1) throw InvalidRequest();
            var action = Text(payload, "action", 16);
            var reference = Text(payload, "targetRef", 32);
            if (!Guid.TryParseExact(reference, "N", out _) ||
                action is not ("send" or "accept" or "reject" or "cancel" or "remove" or "block" or "unblock")) throw InvalidRequest();
            return (action, reference);
        } catch (Exception error) when (error is InvalidOperationException or KeyNotFoundException or FormatException) { throw InvalidRequest(); }
    }

    internal async Task<FriendCommandView> ExecuteAsync(string bearer, JsonElement payload,
        CancellationToken token, string scope = "", Action? ensureCurrent = null)
    {
        var (action, reference) = ParseCommand(payload);
        if (!await _commandGate.WaitAsync(0, token)) return new("rejected", "busy");
        try {
            Target? target;
            lock (_targetGate) {
                if (!_targets.TryGetValue(reference, out target) || target.Owner != Owner(bearer, scope) ||
                    target.Expires < DateTimeOffset.UtcNow || !AllowedActions(target.Relation).Contains(action))
                    return new("rejected", "targetChanged");
                _targets.Clear(); // Consume before any await; retries require an explicit fresh read.
            }
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
            deadline.CancelAfter(TimeSpan.FromSeconds(12));
            FriendsView current;
            try { current = await ReadAsync(bearer, target.Query, deadline.Token, scope); }
            catch (AccountBridgeHostException error) {
                return new("rejected", error.Code switch {
                    "friends.identity_unavailable" => "identityUnavailable", "friends.forbidden" => "forbidden", _ => "refreshRequired"
                });
            }
            var selected = All(current).SingleOrDefault(row => row.AccountId == target.Id);
            if (selected is null || selected.Relationship != target.Relation) return new("rejected", "targetChanged");
            token.ThrowIfCancellationRequested();
            ensureCurrent?.Invoke(); // Recheck identity after preflight, immediately before the POST.
            using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(_origin, "/api/friends/actions"));
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
            request.Content = JsonContent.Create(new FriendActionRequestContract(action, target.Id, IncludePresence: false));
            try {
                using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
                if (response.StatusCode == HttpStatusCode.Unauthorized) return new("rejected", "identityUnavailable");
                if (response.StatusCode == HttpStatusCode.Forbidden) return new("rejected", "forbidden");
                if (response.StatusCode == HttpStatusCode.NotFound) return new("rejected", "targetChanged");
                if (response.StatusCode == HttpStatusCode.TooManyRequests) return new("rejected", "rateLimited");
                if (response.StatusCode == HttpStatusCode.BadRequest) {
                    using var rejection = JsonDocument.Parse(await CommandBody(response, deadline.Token));
                    var status = rejection.RootElement.TryGetProperty("status", out var value) ? value.GetString() : null;
                    return new("rejected", status switch {
                        "request_cooldown" => "cooldown", "too_many_pending" => "tooManyPending",
                        "not_incoming" or "not_outgoing" or "not_friends" or "not_blocked" or "incoming_pending" => "targetChanged", _ => "rejected"
                    });
                }
                if (!response.IsSuccessStatusCode) return new("unknown", "outcomeUnknown");
                var result = Parse(await CommandBody(response, deadline.Token));
                var relation = All(result).SingleOrDefault(row => row.AccountId == target.Id)?.Relationship;
                var expected = action switch { "send" => "outgoing", "accept" => "friend", "block" => "blocked", _ => null };
                if (relation != expected) return new("unknown", "outcomeUnknown");
                return new("accepted", null, IssueTargets(result, bearer, scope));
            } catch (Exception error) when (error is HttpRequestException or IOException or OperationCanceledException or
                AccountBridgeHostException or JsonException or InvalidOperationException or FormatException) {
                return new("unknown", "outcomeUnknown"); // Never replay a POST with an uncertain result.
            }
        } finally { _commandGate.Release(); }
    }

    private static async Task<byte[]> CommandBody(HttpResponseMessage response, CancellationToken token)
    {
        if (response.Content.Headers.ContentLength > MaxBytes) throw Invalid();
        using var stream = await response.Content.ReadAsStreamAsync(token);
        using var buffer = new MemoryStream();
        var bytes = new byte[8192]; int count;
        while ((count = await stream.ReadAsync(bytes, token)) != 0) {
            if (buffer.Length + count > MaxBytes) throw Invalid();
            buffer.Write(bytes, 0, count);
        }
        return buffer.ToArray();
    }
}
