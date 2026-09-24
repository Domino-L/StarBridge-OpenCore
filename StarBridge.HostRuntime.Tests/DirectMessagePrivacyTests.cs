using System.Net;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Friends;

internal static class DirectMessagePrivacyTests
{
    private static readonly DateTimeOffset Now = DateTimeOffset.Parse("2026-09-12T12:00:00Z");
    private static JsonElement Payload(object value) => JsonSerializer.SerializeToElement(value);
    private static void Check(bool value, string message)
    {
        if (!value) throw new Exception(message);
    }

    internal static async Task Verify()
    {
        await ReadsAndWritesExistingRelayContract();
        await RejectsMalformedAndUncertainWrites();
        RejectsUnscopedPayloads();
    }

    private static async Task ReadsAndWritesExistingRelayContract()
    {
        var methods = new List<HttpMethod>();
        using var reader = new FriendsReader(
            new Uri("https://relay.example.test"),
            new Handler(request =>
            {
                methods.Add(request.Method);
                Check(request.RequestUri!.AbsolutePath == "/api/friends/chat/privacy", "Only the existing privacy route is used.");
                Check(request.Headers.Authorization?.Parameter == "token", "Privacy requests keep the current account bearer.");
                if (request.Method == HttpMethod.Post)
                {
                    using var body = JsonDocument.Parse(request.Content!.ReadAsStringAsync().GetAwaiter().GetResult());
                    Check(!body.RootElement.GetProperty("friendsOnly").GetBoolean(), "Allowing strangers inverts the Relay friends-only flag.");
                }
                return Ok(new { friendsOnly = request.Method == HttpMethod.Get, updatedAt = Now });
            }));

        var read = await reader.ReadPrivacyAsync("token", default);
        Check(!read.AllowStrangerDirectMessages && read.UpdatedAt == Now, "Read projection preserves the authoritative value.");
        var currentChecks = 0;
        var saved = await reader.SavePrivacyAsync("token", true, default, () => currentChecks++);
        Check(saved.AllowStrangerDirectMessages && currentChecks == 1, "Write rechecks account context immediately before POST.");
        Check(methods.SequenceEqual(new[] { HttpMethod.Get, HttpMethod.Post }), "Read and write never create extra requests.");
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
                        return Ok(new { friendsOnly = false, updatedAt = Now, extra = true });
                    if (fault == "write-shape" && request.Method == HttpMethod.Post)
                        return Ok(new { friendsOnly = false, updatedAt = "invalid" });
                    return Ok(new { friendsOnly = false, updatedAt = Now });
                }));
            try
            {
                if (fault == "read-shape") await reader.ReadPrivacyAsync("token", default);
                else await reader.SavePrivacyAsync("token", true, default, () => { });
                throw new Exception("Malformed or uncertain privacy response was accepted: " + fault);
            }
            catch (AccountBridgeHostException error)
            {
                Check(
                    error.Code == (fault == "read-shape" ? "directMessages.data_invalid" : "directMessages.privacy_outcome_unknown"),
                    "Stable privacy error classification is required.");
            }
        }
    }

    private static void RejectsUnscopedPayloads()
    {
        foreach (var value in new object[]
                 {
                     new { },
                     new { schemaVersion = 2 },
                     new { schemaVersion = 1, allowStrangerDirectMessages = true },
                 })
        {
            try
            {
                FriendsReader.ParsePrivacyRead(Payload(value));
                throw new Exception("Invalid privacy read payload was accepted.");
            }
            catch (AccountBridgeHostException error)
            {
                Check(error.Code == "directMessages.invalid_request", "Read payload uses the stable invalid request error.");
            }
        }
        foreach (var value in new object[]
                 {
                     new { schemaVersion = 1 },
                     new { schemaVersion = 1, allowStrangerDirectMessages = true, extra = true },
                 })
        {
            try
            {
                FriendsReader.ParsePrivacyWrite(Payload(value));
                throw new Exception("Invalid privacy write payload was accepted.");
            }
            catch (AccountBridgeHostException error)
            {
                Check(error.Code == "directMessages.invalid_request", "Write payload uses the stable invalid request error.");
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
