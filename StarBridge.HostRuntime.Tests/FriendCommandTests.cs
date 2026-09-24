using System.Net;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Friends;

internal static class FriendCommandTests
{
    private static readonly DateTimeOffset Now = DateTimeOffset.Parse("2026-09-06T12:00:00Z");
    internal static object User(string relation) => new { accountId = "private-target", callsign = "测试好友", gameId = "Example",
        relationshipState = relation, lastUpdated = Now, avatarImageData = (string?)null };
    internal static byte[] Snapshot(string? relation) {
        object[] Entries(string group) => relation == group ? [new { user = User(group), relationshipUpdatedAt = Now }] : [];
        return JsonSerializer.SerializeToUtf8Bytes(new {
            friends = Entries("friend"), incomingRequests = Entries("incoming"), outgoingRequests = Entries("outgoing"),
            blockedUsers = Entries("blocked"), refreshedAt = Now
        });
    }
    private static HttpResponseMessage Directory(string? relation) {
        return new(HttpStatusCode.OK) { Content = new ByteArrayContent(Snapshot(relation)) };
    }
    private static JsonElement Command(string action, string reference) => JsonSerializer.SerializeToElement(new { schemaVersion = 1, action, targetRef = reference });
    private static FriendView First(FriendsView view) => view.Friends.Concat(view.Incoming).Concat(view.Outgoing).Concat(view.Blocked).Concat(view.Results).Single();
    private static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
    private sealed class Handler(Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> send) : HttpMessageHandler
    { protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => send(request, token); }

    internal static async Task Lifecycle()
    {
        foreach (var (action, before, after) in new (string, string, string?)[] {
            ("send", "none", "outgoing"), ("accept", "incoming", "friend"), ("reject", "incoming", null),
            ("cancel", "outgoing", null), ("remove", "friend", null), ("block", "friend", "blocked"), ("unblock", "blocked", null)
        }) {
            var writes = 0; var reads = 0;
            using var reader = new FriendsReader(new Uri("https://relay.example.test/"), new Handler(async (request, _) => {
                Check(request.Headers.Authorization?.ToString() == "Bearer fixture-token", "Scoped bearer");
                if (request.Method == HttpMethod.Get) {
                    reads++;
                    Check(request.RequestUri!.Query.Contains("includePresence=false"), "No presence opt-in");
                    return before == "none" ? new(HttpStatusCode.OK) { Content = new StringContent(JsonSerializer.Serialize(new { results = new[] { User(before) } })) } : Directory(before);
                }
                writes++;
                Check(request.RequestUri!.AbsolutePath == "/api/friends/actions", "Fixed action endpoint");
                using var body = JsonDocument.Parse(await request.Content!.ReadAsStringAsync());
                Check(body.RootElement.GetProperty("action").GetString() == action &&
                    body.RootElement.GetProperty("targetAccountId").GetString() == "private-target" &&
                    !body.RootElement.GetProperty("includePresence").GetBoolean(), "Host resolves identity with false presence");
                return Directory(after);
            }));
            var view = await reader.ReadAsync("fixture-token", before == "none" ? "测试" : null, default, "account:1");
            var row = First(view);
            Check(row.TargetRef?.Length == 32 && row.Actions.Contains(action), "Opaque target and eligible action");
            Check(!JsonSerializer.Serialize(view).Contains("private-target"), "Internal identity never crosses bridge");
            var result = await reader.ExecuteAsync("fixture-token", Command(action, row.TargetRef!), default, "account:1");
            Check(result.Status == "accepted" && result.Directory is not null && reads == 2 && writes == 1, "Authoritative acknowledgement and fresh preflight");
            var replay = await reader.ExecuteAsync("fixture-token", Command(action, row.TargetRef!), default, "account:1");
            Check(replay.Status == "rejected" && writes == 1, "No replay of consumed command target");
        }
    }

    internal static async Task Guards()
    {
        var writes = 0; var relation = "friend";
        using var reader = new FriendsReader(new Uri("https://relay.example.test/"), new Handler((request, _) => {
            if (request.Method == HttpMethod.Post) writes++;
            return Task.FromResult(Directory(relation));
        }));
        var row = First(await reader.ReadAsync("token", null, default, "account:1"));
        foreach (var scope in new[] { "account:2", "other:1" }) {
            var result = await reader.ExecuteAsync("token", Command("remove", row.TargetRef!), default, scope);
            Check(result.Error == "targetChanged", "Scope-bound target");
        }
        Check((await reader.ExecuteAsync("other-token", Command("remove", row.TargetRef!), default, "account:1")).Error == "targetChanged", "Token-bound target");
        Check((await reader.ExecuteAsync("token", Command("accept", row.TargetRef!), default, "account:1")).Error == "targetChanged", "Impossible action refused");
        relation = "blocked";
        Check((await reader.ExecuteAsync("token", Command("remove", row.TargetRef!), default, "account:1")).Error == "targetChanged", "Preflight detects concurrent relation change");
        row = First(await reader.ReadAsync("token", null, default, "account:1"));
        try { await reader.ExecuteAsync("token", Command("unblock", row.TargetRef!), default, "account:1", () => throw new AccountBridgeHostException("test.changed")); throw new Exception("Identity change ignored"); }
        catch (AccountBridgeHostException e) { Check(e.Code == "test.changed", "Pre-POST identity check"); }
        Check(writes == 0, "No unsafe write");
        foreach (var json in new[] {
            "{}", "{\"schemaVersion\":1,\"action\":\"remove\",\"targetRef\":\"x\"}",
            "{\"schemaVersion\":1,\"action\":\"remove\",\"targetRef\":\"00000000000000000000000000000001\",\"targetAccountId\":\"injected\"}",
            "{\"schemaVersion\":1,\"action\":\"remove\",\"action\":\"block\",\"targetRef\":\"00000000000000000000000000000001\"}"
        }) {
            using var doc = JsonDocument.Parse(json);
            try { FriendsReader.ParseCommand(doc.RootElement); throw new Exception("Invalid command accepted"); }
            catch (AccountBridgeHostException e) { Check(e.Code == "friends.invalid_request", "Strict payload"); }
        }
    }

    internal static async Task FailureAndConcurrency()
    {
        foreach (var code in new[] { 400, 401, 403, 404, 429, 503, 302, 200, 0 }) {
            var writes = 0;
            using var reader = new FriendsReader(new Uri("https://relay.example.test/"), new Handler((request, _) => {
                if (request.Method == HttpMethod.Get) return Task.FromResult(Directory("friend"));
                writes++;
                if (code == 0) throw new HttpRequestException("test loss after send");
                return Task.FromResult(new HttpResponseMessage((HttpStatusCode)code) { Content = new StringContent(code == 400 ? "{\"status\":\"request_cooldown\",\"error\":\"private detail\"}" : "invalid") });
            }));
            var row = First(await reader.ReadAsync("token", null, default));
            var result = await reader.ExecuteAsync("token", Command("remove", row.TargetRef!), default);
            Check(result.Status == (code is 0 or 200 or 302 or 503 ? "unknown" : "rejected"), "Failure phase classified");
            Check(code != 400 || result.Error == "cooldown", "Bounded cooldown error");
            Check(!JsonSerializer.Serialize(result).Contains("private detail"), "No raw error exposure");
            await reader.ExecuteAsync("token", Command("remove", row.TargetRef!), default);
            Check(writes == 1, "Uncertain write never replays");
        }
        var arrived = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var gets = 0; var posts = 0;
        using var concurrent = new FriendsReader(new Uri("https://relay.example.test/"), new Handler(async (request, token) => {
            if (request.Method == HttpMethod.Post) { posts++; return Directory(null); }
            if (++gets == 2) { arrived.SetResult(); await release.Task.WaitAsync(token); }
            return Directory("friend");
        }));
        var target = First(await concurrent.ReadAsync("token", null, default));
        var first = concurrent.ExecuteAsync("token", Command("remove", target.TargetRef!), default);
        await arrived.Task;
        Check((await concurrent.ExecuteAsync("token", Command("remove", target.TargetRef!), default)).Error == "busy", "No queued duplicate writes");
        release.SetResult(); await first;
        Check(posts == 1, "One concurrent write only");
    }
}
