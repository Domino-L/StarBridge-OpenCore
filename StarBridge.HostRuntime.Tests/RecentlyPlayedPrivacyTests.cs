using System.Net;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Friends;

internal static class RecentlyPlayedPrivacyTests
{
    private static readonly DateTimeOffset DisabledAt =
        DateTimeOffset.Parse("2026-09-12T13:00:00Z");

    internal static async Task Verify()
    {
        await ReadsDefaultAndWritesCurrentRevision();
        await RejectsConflictMalformedAndUncertainWrites();
        RejectsUnscopedPayloads();
    }

    private static async Task ReadsDefaultAndWritesCurrentRevision()
    {
        var methods = new List<HttpMethod>();
        using var reader = new FriendsReader(
            new Uri("https://relay.example.test"),
            new Handler(request =>
            {
                methods.Add(request.Method);
                Check(request.RequestUri!.AbsolutePath == "/api/friends/recently-played/privacy",
                    "Recently played privacy uses only its account route.");
                Check(request.Headers.Authorization?.Parameter == "token",
                    "Recently played privacy keeps the current account bearer.");
                if (request.Method == HttpMethod.Post)
                {
                    using var body = JsonDocument.Parse(
                        request.Content!.ReadAsStringAsync().GetAwaiter().GetResult());
                    Check(!body.RootElement.GetProperty("enabled").GetBoolean(),
                        "The selected privacy value is written without inversion.");
                    Check(body.RootElement.GetProperty("expectedRevision").GetInt64() == 0,
                        "The current revision crosses the Host seam.");
                }

                return request.Method == HttpMethod.Get
                    ? Ok(new
                    {
                        enabled = true,
                        enabledAt = (DateTimeOffset?)null,
                        disabledAt = (DateTimeOffset?)null,
                        revision = 0
                    })
                    : Ok(new
                    {
                        enabled = false,
                        enabledAt = (DateTimeOffset?)null,
                        disabledAt = DisabledAt,
                        revision = 1
                    });
            }));

        var initial = await reader.ReadRecentlyPlayedPrivacyAsync("token", default);
        Check(initial.Enabled && initial.Revision == 0,
            "New and migrated accounts default open without an invented revision.");
        var currentChecks = 0;
        var saved = await reader.SaveRecentlyPlayedPrivacyAsync(
            "token",
            new RecentlyPlayedPrivacyWrite(false, 0),
            default,
            () => currentChecks++);
        Check(!saved.Enabled && saved.DisabledAt == DisabledAt && saved.Revision == 1,
            "Write preserves the authority value and revision.");
        Check(currentChecks == 1 && methods.SequenceEqual([HttpMethod.Get, HttpMethod.Post]),
            "Write rechecks account context and never creates extra requests.");
    }

    private static async Task RejectsConflictMalformedAndUncertainWrites()
    {
        foreach (var fault in new[] { "read-shape", "write-shape", "write-transport", "write-status", "conflict" })
        {
            using var reader = new FriendsReader(
                new Uri("https://relay.example.test"),
                new Handler(request =>
                {
                    if (fault == "write-transport" && request.Method == HttpMethod.Post)
                        throw new HttpRequestException("private transport detail");
                    if (fault == "write-status" && request.Method == HttpMethod.Post)
                        return new HttpResponseMessage(HttpStatusCode.BadGateway);
                    if (fault == "conflict" && request.Method == HttpMethod.Post)
                        return new HttpResponseMessage(HttpStatusCode.Conflict);
                    if (fault == "read-shape" && request.Method == HttpMethod.Get)
                        return Ok(new { enabled = true, enabledAt = (DateTimeOffset?)null, disabledAt = (DateTimeOffset?)null, revision = 0, extra = true });
                    if (fault == "write-shape" && request.Method == HttpMethod.Post)
                        return Ok(new { enabled = false, enabledAt = (DateTimeOffset?)null, disabledAt = "invalid", revision = 1 });
                    return Ok(new { enabled = false, enabledAt = (DateTimeOffset?)null, disabledAt = DisabledAt, revision = 1 });
                }));
            try
            {
                if (fault == "read-shape")
                    await reader.ReadRecentlyPlayedPrivacyAsync("token", default);
                else
                    await reader.SaveRecentlyPlayedPrivacyAsync(
                        "token",
                        new RecentlyPlayedPrivacyWrite(false, 0),
                        default,
                        () => { });
                throw new Exception("Invalid recently played privacy response was accepted: " + fault);
            }
            catch (AccountBridgeHostException error)
            {
                var expected = fault switch
                {
                    "read-shape" => "recentlyPlayed.data_invalid",
                    "conflict" => "recentlyPlayed.write_conflict",
                    _ => "recentlyPlayed.privacy_outcome_unknown"
                };
                Check(error.Code == expected, "Stable recently played error classification is required.");
            }
        }
    }

    private static void RejectsUnscopedPayloads()
    {
        foreach (var value in new object[]
                 {
                     new { },
                     new { schemaVersion = 2 },
                     new { schemaVersion = 1, enabled = true }
                 })
        {
            ExpectInvalid(() => FriendsReader.ParseRecentlyPlayedPrivacyRead(Payload(value)));
        }

        foreach (var value in new object[]
                 {
                     new { schemaVersion = 1 },
                     new { schemaVersion = 1, enabled = true, expectedRevision = -1 },
                     new { schemaVersion = 1, enabled = true, expectedRevision = 0, extra = true }
                 })
        {
            ExpectInvalid(() => FriendsReader.ParseRecentlyPlayedPrivacyWrite(Payload(value)));
        }
    }

    private static void ExpectInvalid(Action action)
    {
        try
        {
            action();
            throw new Exception("Invalid recently played privacy payload was accepted.");
        }
        catch (AccountBridgeHostException error)
        {
            Check(error.Code == "recentlyPlayed.invalid_request",
                "Invalid payload uses the stable recently played error.");
        }
    }

    private static JsonElement Payload(object value) => JsonSerializer.SerializeToElement(value);
    private static void Check(bool value, string message)
    {
        if (!value) throw new Exception(message);
    }

    private static HttpResponseMessage Ok(object body) => new(HttpStatusCode.OK)
    {
        Content = new StringContent(JsonSerializer.Serialize(body))
    };

    private sealed class Handler(Func<HttpRequestMessage, HttpResponseMessage> send) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken token) => Task.FromResult(send(request));
    }
}
