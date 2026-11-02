using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Communities;
using StarBridge.HostRuntime.Onboarding;
using StarBridge.NativeBridge;

internal static partial class FirstUseModeTests
{
    internal static Task OfflineCommunityColdRead() => OfflineCommunityCore(null);
    internal static async Task<string> OfflineCommunityWire()
    {
        var messages = new Dictionary<string, BridgeEnvelope>();
        await OfflineCommunityCore((name, message) => messages.Add(name, message));
        return JsonSerializer.Serialize(messages, BridgeProtocol.JsonOptions);
    }

    private static async Task OfflineCommunityCore(Action<string, BridgeEnvelope>? observe)
    {
        using var http = new OfflineCommunityHttp();
        using var communities = new CommunityClient(new Uri("https://communities.invalid/"), http);
        using var f = new LocalAccountStopTests.Fixture(sampling: true, communities: communities);
        var mode = await RootMode(f);
        await using var native = new NativeAccountRuntimeBinding(f.Runtime);
        var owner = f.Host.CurrentContext!;
        Require((await native.DispatchAsync(BridgeEnvelope.Request("account.getCurrent", Op(), f.Host.Generation,
            new { schemaVersion = 1 }))).Response.Status == "ok", "Fresh root owner before caching organization presentation");
        var online = await native.DispatchAsync(BridgeEnvelope.Request("communities.read", Op(), f.Host.Generation,
            new { schemaVersion = 1, view = "mine", query = "" }, owner));
        Require(online.Response.Status == "ok" && online.Response.Payload.GetProperty("items")[0].GetProperty("name").GetString() == "Retained Organization",
            "Read actual authenticated organization directory before retaining display");
        Require((await mode.ApplyRootOfflineAsync(0, Op(), f.Host.Generation, native)).State == "offline", "Explicit offline transition");
        var traffic = http.Reads;
        async Task Check(string label, NativeAccountRuntimeBinding binding, FirstUseModeRuntime current)
        {
            using var reader = binding.CreateModeDispatcher()!;
            var response = await reader.DispatchAsync(BridgeEnvelope.Request("onboarding.mode.communities", Op(), current.ControlGeneration,
                new { schemaVersion = 1, revision = current.Current.Revision }));
            Require(response.Response.Status == "ok", "Warm and cold offline directory must be locally readable");
            var payload = response.Response.Payload;
            observe?.Invoke(label, response.Response);
            var row = payload.GetProperty("items")[0];
            Require(response.Response.AccountContext is null && payload.GetProperty("source").GetString() == "cached" &&
                row.GetProperty("name").GetString() == "Retained Organization", "Offline name is display-only, never a live membership");
            foreach (var field in new[] { "targetRef", "organizationRef", "relationship", "actions", "memberCount", "online", "role" })
                Require(!row.TryGetProperty(field, out _), "Cached row must omit live authority: " + field);
            var media = await reader.DispatchAsync(BridgeEnvelope.Request("onboarding.mode.communityMedia", Op(), current.ControlGeneration,
                new { schemaVersion = 1, revision = current.Current.Revision, id = row.GetProperty("id").GetString(), offset = 0 }));
            Require(media.Response.Status == "ok" && media.Response.AccountContext is null &&
                media.Response.Payload.GetProperty("data").GetString() == OfflineAvatar[22..], "Offline logo contains the original validated image bytes");
            observe?.Invoke(label + "Media", media.Response);
            foreach (var invalid in new object[] {
                new { schemaVersion = 1, revision = current.Current.Revision + 1 },
                new { schemaVersion = 1, revision = current.Current.Revision, subject = "other" }
            }) Require((await reader.DispatchAsync(BridgeEnvelope.Request("onboarding.mode.communities", Op(), current.ControlGeneration, invalid)))
                .Response.Status == "error", "Caller cannot choose another mode revision or account");
        }
        await Check("warm", native, mode);
        using var cold = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, NoOnline);
        await using var coldNative = new NativeAccountRuntimeBinding(cold);
        await Check("cold", coldNative, cold.FirstUseMode!);
        Require(http.Reads == traffic && f.Vault.Loads == 0 && f.Vault.Deletions == 0, "Cached directory and media cannot authorize or contact the server");
    }

    private sealed class OfflineCommunityHttp : HttpMessageHandler
    {
        internal int Reads;
        internal HttpStatusCode? Failure;
        internal Func<CancellationToken, Task<HttpResponseMessage>>? Reply;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            token.ThrowIfCancellationRequested();
            Reads++;
            Require(request.Method == HttpMethod.Get && request.Headers.Authorization?.Parameter == "synthetic-access",
                "Only the original authenticated GET may warm the fixture");
            if (Reply is { } reply) return reply(token);
            if (Failure is { } failure) return Task.FromResult(new HttpResponseMessage(failure));
            return Task.FromResult(OrganizationReply());
        }
        internal static HttpResponseMessage OrganizationReply(string name = "Retained Organization") =>
            new(HttpStatusCode.OK) { Content = JsonContent.Create(new {
                schemaVersion = 1, membershipModelVersion = 2, view = "mine", query = "", next = (string?)null,
                items = new[] { new { code = "SYNTHETIC-ORG", name, description = "Synthetic description",
                    language = "en", activeTime = "weekends", memberCount = 1, relationship = "member", joinMode = "inviteOnly",
                    actions = new[] { "leave" }, logoImageData = OfflineAvatar } }
            }) };
    }
}
