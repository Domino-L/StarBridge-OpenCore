using System.Net;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Friends;

internal static class FriendRequestPrivacyTests
{
    private static readonly DateTimeOffset Now = DateTimeOffset.Parse("2026-09-12T12:00:00Z");
    private static JsonElement Payload(object value) => JsonSerializer.SerializeToElement(value);
    private static void Check(bool value, string message)
    {
        if (!value) throw new Exception(message);
    }

    internal static async Task Verify()
    {
        await ReadsDefaultAndWritesTheAccountPolicy();
        await RejectsMalformedAndUncertainWrites();
        RejectsUnscopedPayloads();
    }

    private static async Task ReadsDefaultAndWritesTheAccountPolicy()
    {
        var methods = new List<HttpMethod>();
        using var reader = new FriendsReader(
            new Uri("https://relay.example.test"),
            new Handler(request =>
            {
                methods.Add(request.Method);
                Check(request.RequestUri!.AbsolutePath == "/api/friends/request-privacy",
                    "Friend request privacy uses only its account route.");
                Check(request.Headers.Authorization?.Parameter == "token",
                    "Friend request privacy keeps the current account bearer.");
                if (request.Method == HttpMethod.Post)
                {
                    using var body = JsonDocument.Parse(request.Content!.ReadAsStringAsync().GetAwaiter().GetResult());
                    Check(!body.RootElement.GetProperty("allowFriendRequests").GetBoolean(),
                        "The selected friend request value is written without inversion.");
                }
                return request.Method == HttpMethod.Get
                    ? Ok(new { allowFriendRequests = true, updatedAt = (DateTimeOffset?)null })
                    : Ok(new { allowFriendRequests = false, updatedAt = Now });
            }));

        var initial = await reader.ReadFriendRequestPrivacyAsync("token", default);
        Check(initial.AllowFriendRequests && initial.UpdatedAt is null,
            "New accounts default to accepting requests without inventing a save time.");
        var currentChecks = 0;
        var saved = await reader.SaveFriendRequestPrivacyAsync("token", false, default, () => currentChecks++);
        Check(!saved.AllowFriendRequests && saved.UpdatedAt == Now && currentChecks == 1,
            "Write preserves the authority value and rechecks account context before POST.");
        Check(methods.SequenceEqual(new[] { HttpMethod.Get, HttpMethod.Post }),
            "Read and write never create extra requests.");
    }

    private static async Task RejectsMalformedAndUncertainWrites()
    {
        foreach (var fault in new[] { "read-shape", "write-shape", "write-transport", "write-status" })
        {
            using var reader = new FriendsReader(
                new Uri("https://relay.example.test"),
                new Handler(request =>
                {
                    if (fault == "write-transport" && request.Method == HttpMethod.Post)
                        throw new HttpRequestException("private transport detail");
                    if (fault == "write-status" && request.Method == HttpMethod.Post)
                        return new HttpResponseMessage(HttpStatusCode.BadGateway);
                    if (fault == "read-shape" && request.Method == HttpMethod.Get)
                        return Ok(new { allowFriendRequests = true, updatedAt = Now, extra = true });
                    if (fault == "write-shape" && request.Method == HttpMethod.Post)
                        return Ok(new { allowFriendRequests = false, updatedAt = "invalid" });
                    return Ok(new { allowFriendRequests = false, updatedAt = Now });
                }));
            try
            {
                if (fault == "read-shape") await reader.ReadFriendRequestPrivacyAsync("token", default);
                else await reader.SaveFriendRequestPrivacyAsync("token", false, default, () => { });
                throw new Exception("Malformed or uncertain friend request privacy response was accepted: " + fault);
            }
            catch (AccountBridgeHostException error)
            {
                Check(
                    error.Code == (fault == "read-shape"
                        ? "friendRequests.data_invalid"
                        : "friendRequests.privacy_outcome_unknown"),
                    "Stable friend request privacy error classification is required.");
            }
        }
    }

    private static void RejectsUnscopedPayloads()
    {
        foreach (var value in new object[]
                 {
                     new { },
                     new { schemaVersion = 2 },
                     new { schemaVersion = 1, allowFriendRequests = true },
                 })
        {
            try
            {
                FriendsReader.ParseFriendRequestPrivacyRead(Payload(value));
                throw new Exception("Invalid friend request privacy read payload was accepted.");
            }
            catch (AccountBridgeHostException error)
            {
                Check(error.Code == "friendRequests.invalid_request",
                    "Read payload uses the stable invalid request error.");
            }
        }
        foreach (var value in new object[]
                 {
                     new { schemaVersion = 1 },
                     new { schemaVersion = 1, allowFriendRequests = true, extra = true },
                 })
        {
            try
            {
                FriendsReader.ParseFriendRequestPrivacyWrite(Payload(value));
                throw new Exception("Invalid friend request privacy write payload was accepted.");
            }
            catch (AccountBridgeHostException error)
            {
                Check(error.Code == "friendRequests.invalid_request",
                    "Write payload uses the stable invalid request error.");
            }
        }
    }

    private static HttpResponseMessage Ok(object body) => new(HttpStatusCode.OK)
    {
        Content = new StringContent(JsonSerializer.Serialize(body))
    };

    private sealed class Handler(Func<HttpRequestMessage, HttpResponseMessage> send) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) =>
            Task.FromResult(send(request));
    }
}
