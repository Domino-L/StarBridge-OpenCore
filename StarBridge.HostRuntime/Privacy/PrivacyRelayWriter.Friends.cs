using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using StarBridge.Core.Friends;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Privacy;

internal sealed record FriendSharingRemoteSnapshot(
    [property: JsonRequired] int SchemaVersion, [property: JsonRequired] long Revision,
    [property: JsonRequired, JsonIgnore(Condition = JsonIgnoreCondition.Never)] string? OperationId,
    [property: JsonRequired, JsonIgnore(Condition = JsonIgnoreCondition.Never)] DateTimeOffset? AppliedAt,
    [property: JsonRequired, JsonIgnore(Condition = JsonIgnoreCondition.Never)] FriendSharedFields? Fields);

internal sealed partial class PrivacyRelayWriter
{
    internal async Task<FriendSharingRemoteSnapshot> ReadFriendsAsync(string bearer, CancellationToken token)
    {
        using var request = Request(HttpMethod.Get, new Uri(_players, "/api/friends/sharing"), bearer);
        using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
        RequireEventSuccess(response);
        using var document = await ReadAsync(response, token);
        return ParseFriends(document.RootElement);
    }

    private static FriendSharingRemoteSnapshot ParseFriends(JsonElement root)
    {
        LocalPrivacyStore.RejectDuplicates(root);
        var result = root.Deserialize<FriendSharingRemoteSnapshot>(LocalPrivacyStore.Json) ?? throw new JsonException();
        if (result.SchemaVersion != 1 || result.Revision < 0 || (result.Revision == 0
            ? result.Fields is not null || result.OperationId is not null || result.AppliedAt is not null
            : result.Fields is null || !Guid.TryParseExact(result.OperationId, "N", out _) || result.AppliedAt <= DateTimeOffset.UnixEpoch || result.AppliedAt is null))
            throw new JsonException();
        if (result.Fields is { } fields) new FriendSharingPreferences(fields).Validate();
        return result;
    }

    internal async Task<FriendSharingRemoteSnapshot> SaveFriendsAsync(string bearer, long expectedRevision,
        string operationId, FriendSharedFields fields, Action ensureCurrent, CancellationToken token)
    {
        new FriendSharingPreferences(fields).Validate();
        if (expectedRevision < 0 || expectedRevision == long.MaxValue || !Guid.TryParseExact(operationId, "N", out _)) throw new JsonException();
        bool Matches(FriendSharingRemoteSnapshot value) => value.Revision == expectedRevision + 1 &&
            value.OperationId == operationId && value.Fields == fields;
        ensureCurrent();
        try
        {
            using var request = Request(HttpMethod.Post, new Uri(_players, "/api/friends/sharing"), bearer);
            request.Content = JsonContent.Create(new { schemaVersion = 1, expectedRevision, operationId, fields = (int)fields });
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
            ensureCurrent(); RequireEventSuccess(response);
            using var document = await ReadAsync(response, token);
            var result = ParseFriends(document.RootElement);
            ensureCurrent();
            if (!Matches(result)) throw new JsonException();
            return result;
        }
        catch (Exception error) when (error is HttpRequestException or JsonException ||
            error is OperationCanceledException && !token.IsCancellationRequested ||
            error is AccountBridgeHostException { Code: "events.temporarily_unavailable" or "privacy_publication.response_invalid" })
        {
            ensureCurrent(); token.ThrowIfCancellationRequested();
            // A bounded readback may establish the receipt; never repeat POST.
            var saved = await ReadFriendsAsync(bearer, token);
            ensureCurrent();
            if (Matches(saved)) return saved;
            throw new AccountBridgeHostException("friendsSharing.write_unconfirmed");
        }
    }

    internal async Task<string> WriteFriendsLiveAsync(string bearer, string action, long revision,
        string? session, long sequence, FriendSharingSource? source, Action ensureCurrent, CancellationToken token)
    {
        ensureCurrent();
        using var request = Request(HttpMethod.Post, new Uri(_players, "/api/friends/live"), bearer);
        request.Content = JsonContent.Create(new { schemaVersion = 1, action, revision, session, sequence,
            source = source is null ? null : new { source.Presence, source.ServerId, source.ServerRegion,
                source.Ship, source.Location, source.ServerConfirmed, source.ShipConfirmed, source.LocationConfirmed } });
        using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
        ensureCurrent(); RequireEventSuccess(response);
        using var document = await ReadAsync(response, token);
        var root = document.RootElement;
        LocalPrivacyStore.RejectDuplicates(root);
        var received = root.GetProperty("session").GetString();
        if (root.EnumerateObject().Count() != 3 || root.GetProperty("schemaVersion").GetInt32() != 1 ||
            root.GetProperty("sequence").GetInt64() != sequence || !Guid.TryParseExact(received, "N", out _) ||
            action != "start" && session != received) throw new JsonException();
        return received!;
    }
}
