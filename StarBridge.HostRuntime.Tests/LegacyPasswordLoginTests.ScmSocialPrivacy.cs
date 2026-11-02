using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Friends;
using StarBridge.NativeBridge;

internal static partial class LegacyPasswordLoginTests
{
    internal static async Task ScmSocialPrivacyPipeline()
    {
        using var legacyTransport = new Transport();
        using var legacy = new LegacyPasswordLoginClient(new Uri("https://example.invalid/"), new Store(), legacyTransport);
        using var transport = new ScmSocialPrivacyTransport();
        using var friends = new FriendsReader(new Uri("https://example.invalid/"), transport);
        using var host = CreateHost(legacy, new ScmOAuthSession("scm-development", "synthetic", "Pilot",
            "synthetic-scm-bearer", DateTimeOffset.UtcNow.AddHours(1), ["profile.read"]), friends: friends);
        using var runtime = new AccountBridgeRuntime(host);
        var context = host.CurrentContext!;
        var generation = host.Generation;
        async Task<BridgeDispatchBatch> Send(string operation, object payload) => await runtime.DispatchAsync(
            BridgeEnvelope.Request("friendRequests." + operation, "scm-social", generation, payload, context));
        var read = await Send("privacyRead", new { schemaVersion = 1 });
        Check(read.Response.Error is null && read.Response.Payload.GetProperty("allowFriendRequests").GetBoolean(),
            "actual SCM runtime reads friend request privacy without a legacy owner");
        var saved = await Send("privacyWrite", new { schemaVersion = 1, allowFriendRequests = false });
        Check(saved.Response.Error is null && !saved.Response.Payload.GetProperty("allowFriendRequests").GetBoolean() && transport.Posts == 1,
            "actual SCM runtime writes privacy exactly once");
        var calls = transport.Calls;
        var invalid = await Send("privacyWrite", new { schemaVersion = 1, allowFriendRequests = true, subject = "other" });
        Check(invalid.Response.Error is not null && transport.Calls == calls, "caller-selected subject rejected before HTTP");
        transport.FailRead = true;
        read = await Send("privacyRead", new { schemaVersion = 1 });
        Check(read.Response.Error?.Code == "friendRequests.privacy_unavailable", "failed read cannot report default-open success");
        transport.FailRead = false;
        transport.LoseWriteResponse = true;
        saved = await Send("privacyWrite", new { schemaVersion = 1, allowFriendRequests = true });
        Check(saved.Response.Error?.Code == "friendRequests.privacy_outcome_unknown" && transport.Posts == 2,
            "lost write acknowledgement stays uncertain and is never replayed");
        read = await Send("privacyRead", new { schemaVersion = 1 });
        Check(read.Response.Error is null && read.Response.Payload.GetProperty("allowFriendRequests").GetBoolean(),
            "explicit read can confirm an uncertain SCM write");
        Check(legacyTransport.Calls == 0, "SCM privacy never reads or creates legacy identity");
        host.Dispose();
        calls = transport.Calls;
        saved = await Send("privacyWrite", new { schemaVersion = 1, allowFriendRequests = false });
        Check(saved.Response.Error is not null && transport.Calls == calls, "disposed SCM host rejects late save");
    }

    private sealed class ScmSocialPrivacyTransport : HttpMessageHandler
    {
        internal int Calls, Posts;
        internal bool FailRead, LoseWriteResponse;
        private bool allowed = true;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Calls++;
            Check(request.RequestUri!.AbsolutePath == "/api/friends/request-privacy" &&
                request.Headers.Authorization?.Parameter == "synthetic-scm-bearer", "SCM bearer stays on scoped privacy route");
            if (request.Method == HttpMethod.Post)
            {
                Posts++;
                using var body = JsonDocument.Parse(request.Content!.ReadAsStringAsync(token).GetAwaiter().GetResult());
                Check(body.RootElement.EnumerateObject().Count() == 1, "no owner or unrelated fields in privacy write");
                allowed = body.RootElement.GetProperty("allowFriendRequests").GetBoolean();
                if (LoseWriteResponse) throw new HttpRequestException("synthetic response lost");
            }
            if (request.Method == HttpMethod.Get && FailRead) return Task.FromResult(new HttpResponseMessage(HttpStatusCode.ServiceUnavailable));
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(
                new { allowFriendRequests = allowed, updatedAt = (DateTimeOffset?)DateTimeOffset.UtcNow }) });
        }
    }
}
