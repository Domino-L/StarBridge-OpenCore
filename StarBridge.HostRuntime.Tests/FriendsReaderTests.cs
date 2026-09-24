using System.Net;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Friends;

internal static class FriendsReaderTests
{
    internal static readonly DateTimeOffset Now = DateTimeOffset.Parse("2026-09-06T12:00:00Z");
    internal static object User(string id = "private-account", string relation = "friend", string? avatar = null) => new {
        accountId = id, callsign = "测试呼号", gameId = "Citizen_CN", relationshipState = relation,
        avatarImageData = avatar, presence = "InGame", lastUpdated = Now, authToken = "must-not-cross"
    };
    internal static byte[] Directory(object? user = null) => JsonSerializer.SerializeToUtf8Bytes(new {
        friends = new[] { new { user = user ?? User(), relationshipUpdatedAt = Now } },
        incomingRequests = Array.Empty<object>(), outgoingRequests = Array.Empty<object>(), blockedUsers = Array.Empty<object>(), refreshedAt = Now
    });
    internal static Task Projection()
    {
        var view = FriendsReader.Parse(Directory(User(avatar: "https://untrusted.example/avatar")));
        Check(view.Friends.Single().Callsign == "测试呼号" && view.Friends.Single().GameId == "Citizen_CN", "Display fields preserved.");
        Check(view.Friends.Single().AvatarImageData is null, "No arbitrary remote avatar.");
        var wire = JsonSerializer.Serialize(view);
        Check(!wire.Contains("private-account") && !wire.Contains("must-not-cross") && !wire.Contains("InGame"), "No identity, bearer or presence projection.");
        Check(FriendsReader.Parse(Directory(User(relation: "future-state"))).Friends.Single().Relationship == "unknown", "Unknown relation is not permission.");
        var search = FriendsReader.Parse(JsonSerializer.SerializeToUtf8Bytes(new { results = new[] { User(relation: "none") } }), "测试");
        Check(search.Query == "测试" && search.Results.Length == 1 && search.Friends.Length == 0 && search.RefreshedAt is null, "Search cannot masquerade as directory.");
        foreach (var json in new[] {
            "{}", "{\"friends\":[],\"friends\":[]}",
            JsonSerializer.Serialize(new { friends = new[] { new { user = User(), relationshipUpdatedAt = Now }, new { user = User(), relationshipUpdatedAt = Now } }, incomingRequests = Array.Empty<object>(), outgoingRequests = Array.Empty<object>(), blockedUsers = Array.Empty<object>(), refreshedAt = Now })
        }) Reject(() => FriendsReader.Parse(System.Text.Encoding.UTF8.GetBytes(json)), "friends.data_invalid");
        Reject(() => FriendsReader.Parse(Directory(User(relation: "blocked"))), "friends.data_invalid");
        Reject(() => FriendsReader.Parse(new byte[FriendsReader.MaxBytes + 1]), "friends.data_invalid");
        Reject(() => FriendsReader.Parse(JsonSerializer.SerializeToUtf8Bytes(new { results = Enumerable.Range(0,21).Select(i => User(i.ToString())).ToArray() }), "test"), "friends.data_invalid");
        return Task.CompletedTask;
    }
    internal static async Task HttpAndRequest()
    {
        var calls = 0;
        using var reader = new FriendsReader(new Uri("https://relay.example.test/base"), new Handler((request, _) => {
            calls++;
            Check(request.Method == HttpMethod.Get && request.Content is null, "Only GET.");
            Check(request.Headers.Authorization?.ToString() == "Bearer test-token", "SCM bearer stays in header.");
            Check(request.RequestUri!.Query.Contains("includePresence=false"), "No realtime opt-in.");
            if (calls == 2)
            {
                Check(request.RequestUri.AbsolutePath == "/api/friends/search" && request.RequestUri.Query.Contains("%26"), "Search encoded on fixed origin.");
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent("{\"results\":[]}") });
            }
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent(Directory()) });
        }));
        await reader.ReadAsync("test-token", null, default);
        await reader.ReadAsync("test-token", "a&b", default);
        Check(calls == 2, "No session creation or extra writes.");
        foreach (var pair in new[] { (HttpStatusCode.Unauthorized, "friends.identity_unavailable"), (HttpStatusCode.Forbidden, "friends.forbidden"),
            (HttpStatusCode.ServiceUnavailable, "friends.read_unavailable"), (HttpStatusCode.Redirect, "friends.read_unavailable") })
        {
            using var failed = new FriendsReader(new Uri("https://relay.example.test/"), new Handler((_, _) => Task.FromResult(new HttpResponseMessage(pair.Item1))));
            try { await failed.ReadAsync("test-token", null, default); throw new Exception("Failure accepted."); }
            catch (AccountBridgeHostException error) { Check(error.Code == pair.Item2, "Stable error, no raw upstream body."); }
        }
        using var cancelled = new FriendsReader(new Uri("https://relay.example.test/"), new Handler(async (_, ct) => {
            await Task.Delay(Timeout.Infinite, ct); return new(HttpStatusCode.OK);
        }));
        using var cts = new CancellationTokenSource();
        var pending = cancelled.ReadAsync("test-token", null, cts.Token);
        cts.Cancel();
        try { await pending; throw new Exception("Cancellation ignored."); } catch (OperationCanceledException) { }
        Check(FriendsReader.ParseQuery(JsonSerializer.SerializeToElement(new { schemaVersion = 1, query = "  test  " })) == "test", "Normalized query.");
        foreach (var json in new[] { "{}", "{\"schemaVersion\":1,\"query\":\"a\"}", "{\"schemaVersion\":1,\"includePresence\":true}",
            "{\"schemaVersion\":1,\"schemaVersion\":1}", "{\"schemaVersion\":1,\"query\":null}" })
        { using var parsed = JsonDocument.Parse(json); Reject(() => FriendsReader.ParseQuery(parsed.RootElement), "friends.invalid_request"); }
        foreach (var origin in new[] { "http://example.test/", "https://user" + "@example.test/", "https://example.test/?secret=x" })
        { try { using var bad = new FriendsReader(new Uri(origin)); throw new Exception("Unsafe origin accepted."); } catch (ArgumentException) { } }
    }
    private static void Reject(Action action, string code)
    { try { action(); throw new Exception("Invalid data accepted."); } catch (AccountBridgeHostException error) { Check(error.Code == code, "Expected rejection."); } }
    private static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
    private sealed class Handler(Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> send) : HttpMessageHandler
    { protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => send(request, token); }
}
