namespace StarBridge.HostRuntime.Friends;

using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;
using System.Text.Json.Serialization;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.PartyRooms;
using StarBridge.Core.Friends;

// A scoped projection: internal account IDs, presence and raw URLs never cross the bridge.
internal sealed record FriendView(string Callsign, string GameId, string Relationship,
    string? AvatarImageData, DateTimeOffset UpdatedAt)
{
    [JsonIgnore] public string AccountId { get; init; } = "";
    [JsonIgnore] public string? ObservedPresence { get; init; }
    public string? TargetRef { get; init; }
    public string? ConversationKey { get; init; }
    public string? ChatTargetRef { get; init; }
    public string[] Actions { get; init; } = [];
    public FriendSharedView? Shared { get; init; }
}
internal sealed record FriendsView(string? Query, DateTimeOffset? RefreshedAt,
    FriendView[] Friends, FriendView[] Incoming, FriendView[] Outgoing, FriendView[] Blocked,
    FriendView[] Results)
{
    public int SchemaVersion => 1;
}

internal sealed partial class FriendsReader : IDisposable
{
    internal const int MaxBytes = 2 * 1024 * 1024;
    private readonly Uri _origin;
    private readonly HttpClient _http;
    internal FriendsReader(Uri origin, HttpMessageHandler? handler = null)
    {
        if (!origin.IsAbsoluteUri || origin.UserInfo.Length != 0 || origin.Query.Length != 0 ||
            origin.Fragment.Length != 0 || (origin.Scheme != "https" && !(origin.Scheme == "http" && origin.IsLoopback)))
            throw new ArgumentException("A trusted Relay origin is required.", nameof(origin));
        _origin = origin;
        _http = new(handler ?? new HttpClientHandler { AllowAutoRedirect = false }) { Timeout = TimeSpan.FromSeconds(12) };
    }

    internal static string? ParseQuery(JsonElement payload)
    {
        try
        {
            var names = payload.EnumerateObject().Select(p => p.Name).ToArray();
            if (names.Distinct().Count() != names.Length || names.Any(n => n is not ("schemaVersion" or "query")) ||
                payload.GetProperty("schemaVersion").GetInt32() != 1) throw InvalidRequest();
            if (!payload.TryGetProperty("query", out var value)) return null;
            var query = value.GetString()?.Trim();
            if (query is null || query.Length is < 2 or > 128 || query.Any(char.IsControl)) throw InvalidRequest();
            return query;
        }
        catch (Exception error) when (error is JsonException or InvalidOperationException or KeyNotFoundException or FormatException)
        { throw InvalidRequest(); }
    }

    internal async Task<FriendsView> ReadAsync(string bearer, string? query, CancellationToken token, string scope = "", bool observePresence = false, bool sharing = false, bool issueTargets = true)
    {
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
        deadline.CancelAfter(TimeSpan.FromSeconds(12));
        // Only the enabled authenticated activity observer may request friend presence. Search never does.
        var path = query is null ? "/api/friends?includePresence=" + (observePresence ? "true" : sharing ? "false&includeSharing=true" : "false") :
            "/api/friends/search?includePresence=false&q=" + Uri.EscapeDataString(query);
        using var request = new HttpRequestMessage(HttpMethod.Get, new Uri(_origin, path));
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
        try
        {
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
            // A missing ACTIVE Link is not proof that the SCM login expired.
            if (response.StatusCode == HttpStatusCode.Unauthorized) throw new AccountBridgeHostException("friends.identity_unavailable");
            if (response.StatusCode == HttpStatusCode.Forbidden) throw new AccountBridgeHostException("friends.forbidden");
            if (!response.IsSuccessStatusCode) throw new AccountBridgeHostException("friends.read_unavailable", true);
            if (response.Content.Headers.ContentLength > MaxBytes) throw Invalid();
            using var stream = await response.Content.ReadAsStreamAsync(deadline.Token);
            using var buffer = new MemoryStream();
            var chunk = new byte[8192];
            int count;
            while ((count = await stream.ReadAsync(chunk, deadline.Token)) != 0)
            {
                if (buffer.Length + count > MaxBytes) throw Invalid();
                buffer.Write(chunk, 0, count);
            }
            var view = Parse(buffer.ToArray(), query, observePresence, sharing);
            return issueTargets ? IssueTargets(view, bearer, scope) : view;
        }
        catch (OperationCanceledException) when (!token.IsCancellationRequested)
        { throw new AccountBridgeHostException("friends.read_unavailable", true); }
        catch (Exception error) when (error is HttpRequestException or IOException)
        { throw new AccountBridgeHostException("friends.read_unavailable", true); }
    }

    internal static FriendsView Parse(byte[] json, string? query = null, bool observePresence = false, bool sharing = false)
    {
        try
        {
            if (json.Length > MaxBytes) throw Invalid();
            using var document = JsonDocument.Parse(json);
            RejectDuplicates(document.RootElement);
            var root = document.RootElement;
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            FriendView[] Read(string key, bool wrapped, string? expected = null)
            {
                var array = root.GetProperty(key);
                if (array.GetArrayLength() > (wrapped ? 2000 : 20)) throw Invalid();
                return array.EnumerateArray().Select(entry =>
                {
                    var user = wrapped ? entry.GetProperty("user") : entry;
                    var id = Text(user, "accountId", 256);
                    if (string.IsNullOrWhiteSpace(id) || !seen.Add(id)) throw Invalid();
                    var relation = Text(user, "relationshipState", 64);
                    if (relation is not ("none" or "friend" or "incoming" or "outgoing" or "blocked")) relation = "unknown";
                    if (expected is not null && relation != expected && relation != "unknown") throw Invalid();
                    return new FriendView(Text(user, "callsign", 512), Text(user, "gameId", 512), relation,
                        user.TryGetProperty("avatarImageData", out var avatar) && avatar.ValueKind == JsonValueKind.String
                            ? RoomAvatarProjection.Normalize(avatar.GetString()) : null,
                        wrapped ? entry.GetProperty("relationshipUpdatedAt").GetDateTimeOffset() : user.GetProperty("lastUpdated").GetDateTimeOffset()) {
                            AccountId = id,
                            Shared = sharing && query is null && expected == "friend" ? ParseShared(user) : null,
                            ObservedPresence = observePresence && query is null && expected == "friend" &&
                                user.TryGetProperty("presence", out var presence) && presence.ValueKind == JsonValueKind.String
                                    ? Text(user, "presence", 64) : null
                        };
                }).ToArray();
            }
            if (query is not null) return new(query, null, [], [], [], [], Read("results", false));
            return new(null, root.GetProperty("refreshedAt").GetDateTimeOffset(),
                Read("friends", true, "friend"), Read("incomingRequests", true, "incoming"),
                Read("outgoingRequests", true, "outgoing"), Read("blockedUsers", true, "blocked"), []);
        }
        catch (Exception error) when (error is JsonException or InvalidOperationException or KeyNotFoundException or FormatException or OverflowException)
        { throw Invalid(); }
    }

    private static string Text(JsonElement value, string name, int max)
    {
        var text = value.GetProperty(name).GetString() ?? "";
        if (text.Length > max || text.Any(char.IsControl)) throw Invalid();
        return text;
    }
    private static FriendSharedView? ParseShared(JsonElement user)
    {
        if (!user.TryGetProperty("shared", out var value) || value.ValueKind == JsonValueKind.Null) return null;
        var shared = value.Deserialize<FriendSharedView>(Privacy.LocalPrivacyStore.Json) ?? throw Invalid();
        if (shared.Presence is not (null or "AppOnline" or "InGame" or "Away" or "Offline") ||
            new[] { shared.ServerId, shared.ServerRegion, shared.Ship, shared.Location }.Any(v => v is not null && (v.Length > 512 || v.Any(char.IsControl))) ||
            shared.LastOnlineAt is { } seen && (seen <= DateTimeOffset.UnixEpoch || seen > DateTimeOffset.UtcNow.AddMinutes(1))) throw Invalid();
        return shared;
    }
    private static void RejectDuplicates(JsonElement value)
    {
        if (value.ValueKind == JsonValueKind.Object)
        {
            var names = new HashSet<string>(StringComparer.Ordinal);
            foreach (var property in value.EnumerateObject())
            {
                if (!names.Add(property.Name)) throw Invalid();
                RejectDuplicates(property.Value);
            }
        }
        else if (value.ValueKind == JsonValueKind.Array)
            foreach (var item in value.EnumerateArray()) RejectDuplicates(item);
    }
    private static AccountBridgeHostException Invalid() => new("friends.data_invalid");
    private static AccountBridgeHostException InvalidRequest() => new("friends.invalid_request");
    public void Dispose() => _http.Dispose();
}
