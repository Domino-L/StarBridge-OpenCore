namespace StarBridge.HostRuntime.Friends;

using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Serialization;
using StarBridge.HostRuntime.Account;

internal sealed record FriendRequestPrivacyView(
    bool AllowFriendRequests,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.Never)] DateTimeOffset? UpdatedAt)
{
    public int SchemaVersion => 1;
}

internal sealed partial class FriendsReader
{
    internal static void ParseFriendRequestPrivacyRead(JsonElement payload)
    {
        try
        {
            var names = payload.EnumerateObject().Select(property => property.Name).ToArray();
            if (names.Length != 1 || names[0] != "schemaVersion" ||
                payload.GetProperty("schemaVersion").GetInt32() != 1)
                throw FriendRequestPrivacyError("invalid_request");
        }
        catch (Exception error) when (error is InvalidOperationException or KeyNotFoundException or FormatException)
        {
            throw FriendRequestPrivacyError("invalid_request");
        }
    }

    internal static bool ParseFriendRequestPrivacyWrite(JsonElement payload)
    {
        try
        {
            var names = payload.EnumerateObject().Select(property => property.Name).ToArray();
            if (names.Length != 2 || names.Distinct().Count() != names.Length ||
                names.Any(name => name is not ("schemaVersion" or "allowFriendRequests")) ||
                payload.GetProperty("schemaVersion").GetInt32() != 1)
                throw FriendRequestPrivacyError("invalid_request");
            return payload.GetProperty("allowFriendRequests").GetBoolean();
        }
        catch (Exception error) when (error is InvalidOperationException or KeyNotFoundException or FormatException)
        {
            throw FriendRequestPrivacyError("invalid_request");
        }
    }

    internal Task<FriendRequestPrivacyView> ReadFriendRequestPrivacyAsync(
        string bearer,
        CancellationToken token) =>
        SendFriendRequestPrivacyAsync(bearer, allowFriendRequests: null, token);

    internal Task<FriendRequestPrivacyView> SaveFriendRequestPrivacyAsync(
        string bearer,
        bool allowFriendRequests,
        CancellationToken token,
        Action ensureCurrent) =>
        SendFriendRequestPrivacyAsync(bearer, allowFriendRequests, token, ensureCurrent);

    private async Task<FriendRequestPrivacyView> SendFriendRequestPrivacyAsync(
        string bearer,
        bool? allowFriendRequests,
        CancellationToken token,
        Action? ensureCurrent = null)
    {
        var writing = allowFriendRequests is not null;
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
        deadline.CancelAfter(TimeSpan.FromSeconds(12));
        using var request = new HttpRequestMessage(
            writing ? HttpMethod.Post : HttpMethod.Get,
            new Uri(_origin, "/api/friends/request-privacy"));
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
        if (writing)
        {
            ensureCurrent?.Invoke();
            request.Content = JsonContent.Create(new
            {
                AllowFriendRequests = allowFriendRequests!.Value
            });
        }

        try
        {
            using var response = await _http.SendAsync(
                request,
                HttpCompletionOption.ResponseHeadersRead,
                deadline.Token);
            if (response.StatusCode == HttpStatusCode.Unauthorized)
                throw FriendRequestPrivacyError("identity_unavailable");
            if (response.StatusCode == HttpStatusCode.Forbidden)
                throw FriendRequestPrivacyError("forbidden");
            if (!response.IsSuccessStatusCode)
                throw FriendRequestPrivacyError(writing ? "privacy_outcome_unknown" : "privacy_unavailable");

            using var document = JsonDocument.Parse(await CommandBody(response, deadline.Token));
            RejectDuplicates(document.RootElement);
            var result = ParseFriendRequestPrivacyResponse(document.RootElement);
            if (writing && result.AllowFriendRequests != allowFriendRequests)
                throw FriendRequestPrivacyError("privacy_outcome_unknown");
            return result;
        }
        catch (OperationCanceledException) when (!token.IsCancellationRequested)
        {
            throw FriendRequestPrivacyError(writing ? "privacy_outcome_unknown" : "privacy_unavailable");
        }
        catch (Exception error) when (error is HttpRequestException or IOException)
        {
            throw FriendRequestPrivacyError(writing ? "privacy_outcome_unknown" : "privacy_unavailable");
        }
        catch (Exception error) when (error is JsonException or InvalidOperationException or
                                      FormatException or KeyNotFoundException or OverflowException)
        {
            throw FriendRequestPrivacyError(writing ? "privacy_outcome_unknown" : "data_invalid");
        }
    }

    private static FriendRequestPrivacyView ParseFriendRequestPrivacyResponse(JsonElement root)
    {
        var names = root.EnumerateObject().Select(property => property.Name).ToArray();
        if (names.Length != 2 || names.Distinct().Count() != names.Length ||
            names.Any(name => name is not ("allowFriendRequests" or "updatedAt")))
            throw new FormatException();
        var updatedAtValue = root.GetProperty("updatedAt");
        var updatedAt = updatedAtValue.ValueKind == JsonValueKind.Null
            ? (DateTimeOffset?)null
            : updatedAtValue.GetDateTimeOffset();
        return new FriendRequestPrivacyView(
            root.GetProperty("allowFriendRequests").GetBoolean(),
            updatedAt);
    }

    private static AccountBridgeHostException FriendRequestPrivacyError(string code) =>
        new("friendRequests." + code);
}
