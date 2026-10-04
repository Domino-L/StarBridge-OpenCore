using System.Net;
using System.Text.Json;
using StarBridge.HostRuntime.Friends;
using StarBridge.NativeBridge;

internal static class SocialActivityReadTests
{
    private sealed class Handler : HttpMessageHandler {
        internal TaskCompletionSource<HttpResponseMessage> Reply = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal HttpRequestMessage? Request;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) {
            Request = request;
            return await Reply.Task.WaitAsync(token);
        }
    }
    internal static async Task Run()
    {
        var handler = new Handler();
        using var reader = new FriendsReader(new Uri("https://fixture.invalid"), handler);
        var cursor = new string('a', 32);
        var pending = reader.WaitActivityAsync("fixture-only", BridgePayload.From(new { schemaVersion = 1, instance = cursor, version = 4 }), default);
        if (pending.IsCompleted || handler.Request?.Headers.Authorization?.Parameter != "fixture-only" ||
            handler.Request.RequestUri?.AbsolutePath != "/api/social/activity" ||
            !handler.Request.RequestUri.Query.Contains("waitSeconds=8")) throw new Exception("Activity must use bounded authenticated wait.");
        handler.Reply.SetResult(new(HttpStatusCode.OK) { Content = new StringContent(JsonSerializer.Serialize(new { instanceId = cursor, version = 5 })) });
        var result = BridgePayload.From(await pending.WaitAsync(TimeSpan.FromSeconds(2)));
        if (result.GetProperty("version").GetInt64() != 5) throw new Exception("Activity cursor not advanced.");
        foreach (var advertised in new[] { false, true })
        {
            handler.Reply = new(TaskCreationOptions.RunContinuationsAsynchronously);
            var community = reader.WaitActivityAsync("fixture-only", BridgePayload.From(new {
                schemaVersion = 1, instance = cursor, version = 5 }), default, community: true);
            if (handler.Request?.RequestUri?.AbsolutePath != "/api/fleets/activity")
                throw new Exception("Organization cursor must use its own authorized endpoint.");
            handler.Reply.SetResult(new(HttpStatusCode.OK) { Content = new StringContent(JsonSerializer.Serialize(
                advertised ? (object)new { instanceId = cursor, version = 6, presenceEvents = true }
                    : new { instanceId = cursor, version = 6 })) });
            var reply = BridgePayload.From(await community);
            if (reply.GetProperty("presenceEvents").GetBoolean() != advertised)
                throw new Exception("Only upgraded services can suppress presence reconciliation.");
        }
        handler.Reply = new(TaskCreationOptions.RunContinuationsAsynchronously);
        using var cancelled = new CancellationTokenSource();
        var next = reader.WaitActivityAsync("fixture-only", BridgePayload.From(new { schemaVersion = 1, instance = cursor, version = 5 }), cancelled.Token);
        cancelled.Cancel();
        try { await next; throw new Exception("Cancelled activity accepted."); } catch (OperationCanceledException) { }
        foreach (var invalid in new[] {
            "{\"schemaVersion\":1,\"instance\":\"../bad\",\"version\":0}",
            "{\"schemaVersion\":1,\"instance\":\"\",\"version\":-2}",
            "{\"schemaVersion\":1,\"instance\":\"\",\"version\":0,\"version\":1}",
            "{\"schemaVersion\":1,\"instance\":\"\",\"version\":999999999999999999999999999999}"
        }) {
            using var json = JsonDocument.Parse(invalid);
            try { FriendsReader.ParseActivity(json.RootElement); throw new Exception("Invalid cursor accepted."); }
            catch (StarBridge.HostRuntime.Account.AccountBridgeHostException) { }
        }
        handler.Reply = new(TaskCreationOptions.RunContinuationsAsynchronously);
        var denied = reader.WaitActivityAsync("fixture-only", BridgePayload.From(new { schemaVersion = 1, instance = cursor, version = 5 }), default);
        handler.Reply.SetResult(new(HttpStatusCode.Unauthorized));
        try { await denied; throw new Exception("Unauthorized activity accepted."); }
        catch (StarBridge.HostRuntime.Account.AccountBridgeHostException e) when (e.Code == "friends.identity_unavailable") { }
    }
}
