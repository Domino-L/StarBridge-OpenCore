namespace StarBridge.HostRuntime.Friends;

using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Account;

internal sealed record DirectMessagePrivacyView(
    bool AllowStrangerDirectMessages,
    DateTimeOffset UpdatedAt)
{
    public int SchemaVersion => 1;
}

internal sealed partial class FriendsReader
{
    internal static void ParsePrivacyRead(JsonElement payload)
    {
        try
        {
            var names = payload.EnumerateObject().Select(property => property.Name).ToArray();
            if (names.Length != 1 || names[0] != "schemaVersion" ||
                payload.GetProperty("schemaVersion").GetInt32() != 1)
                throw PrivacyError("invalid_request");
        }
        catch (Exception error) when (error is InvalidOperationException or KeyNotFoundException or FormatException)
        {
            throw PrivacyError("invalid_request");
        }
    }

    internal static bool ParsePrivacyWrite(JsonElement payload)
    {
        try
        {
            var names = payload.EnumerateObject().Select(property => property.Name).ToArray();
            if (names.Length != 2 || names.Distinct().Count() != names.Length ||
                names.Any(name => name is not ("schemaVersion" or "allowStrangerDirectMessages")) ||
                payload.GetProperty("schemaVersion").GetInt32() != 1)
                throw PrivacyError("invalid_request");
            return payload.GetProperty("allowStrangerDirectMessages").GetBoolean();
        }
        catch (Exception error) when (error is InvalidOperationException or KeyNotFoundException or FormatException)
        {
            throw PrivacyError("invalid_request");
        }
    }

    internal Task<DirectMessagePrivacyView> ReadPrivacyAsync(string bearer, CancellationToken token) =>
        SendPrivacyAsync(bearer, allowStrangerDirectMessages: null, token);

    internal Task<DirectMessagePrivacyView> SavePrivacyAsync(
        string bearer,
        bool allowStrangerDirectMessages,
        CancellationToken token,
        Action ensureCurrent) =>
        SendPrivacyAsync(bearer, allowStrangerDirectMessages, token, ensureCurrent);

    private async Task<DirectMessagePrivacyView> SendPrivacyAsync(
        string bearer,
        bool? allowStrangerDirectMessages,
        CancellationToken token,
        Action? ensureCurrent = null)
    {
        var writing = allowStrangerDirectMessages is not null;
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
        deadline.CancelAfter(TimeSpan.FromSeconds(12));
        using var request = new HttpRequestMessage(
            writing ? HttpMethod.Post : HttpMethod.Get,
            new Uri(_origin, "/api/friends/chat/privacy"));
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
        if (writing)
        {
            ensureCurrent?.Invoke();
            request.Content = JsonContent.Create(new
            {
                FriendsOnly = !allowStrangerDirectMessages!.Value
            });
        }

        try
        {
            using var response = await _http.SendAsync(
                request,
                HttpCompletionOption.ResponseHeadersRead,
                deadline.Token);
            if (response.StatusCode == HttpStatusCode.Unauthorized)
                throw PrivacyError("identity_unavailable");
            if (response.StatusCode == HttpStatusCode.Forbidden)
                throw PrivacyError("forbidden");
            if (!response.IsSuccessStatusCode)
                throw PrivacyError(writing ? "privacy_outcome_unknown" : "privacy_unavailable");

            using var document = JsonDocument.Parse(await CommandBody(response, deadline.Token));
            RejectDuplicates(document.RootElement);
            var result = ParsePrivacyResponse(document.RootElement);
            if (writing && result.AllowStrangerDirectMessages != allowStrangerDirectMessages)
                throw PrivacyError("privacy_outcome_unknown");
            return result;
        }
        catch (OperationCanceledException) when (!token.IsCancellationRequested)
        {
            throw PrivacyError(writing ? "privacy_outcome_unknown" : "privacy_unavailable");
        }
        catch (Exception error) when (error is HttpRequestException or IOException)
        {
            throw PrivacyError(writing ? "privacy_outcome_unknown" : "privacy_unavailable");
        }
        catch (Exception error) when (error is JsonException or InvalidOperationException or
                                      FormatException or KeyNotFoundException or OverflowException)
        {
            throw PrivacyError(writing ? "privacy_outcome_unknown" : "data_invalid");
        }
    }

    private static DirectMessagePrivacyView ParsePrivacyResponse(JsonElement root)
    {
        var names = root.EnumerateObject().Select(property => property.Name).ToArray();
        if (names.Length != 2 || names.Distinct().Count() != names.Length ||
            names.Any(name => name is not ("friendsOnly" or "updatedAt")))
            throw new FormatException();
        return new DirectMessagePrivacyView(
            !root.GetProperty("friendsOnly").GetBoolean(),
            root.GetProperty("updatedAt").GetDateTimeOffset());
    }

    private static AccountBridgeHostException PrivacyError(string code) =>
        new("directMessages." + code);
}
