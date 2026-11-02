using System.Net;
using System.Net.Http.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

internal static partial class LegacyPasswordLoginTests
{
    private static async Task ScmProfileVisibility()
    {
        using var transport = new ScmVisibilityTransport();
        var uri = new Uri("http://127.0.0.1:9/");
        var oauth = new OAuthPkceClient(new ScmHttpClient(transport), new ScmBackgroundVault(),
            new ScmOAuthOptions("synthetic", uri, uri, uri, "synthetic", "synthetic", "openid profile.read", "/callback"));
        var authorization = new ScmBackgroundAuthorization();
        using var host = new ScmAccountBridgeHost(oauth, new ScmProfileCacheStore(), "integration", () => null,
            initialSession: new ScmOAuthSession("synthetic", "owner", "Pilot", "synthetic-read-token",
                DateTimeOffset.UtcNow.AddHours(1), ["profile.read"]), profileAuthorization: authorization);
        using var dispatcher = new AccountBridgeDispatcher(host);
        var owner = host.CurrentContext!; var generation = host.Generation;
        Task<AccountBridgeDispatchResult> Request(bool save, object payload) => dispatcher.DispatchAsync(
            BridgeEnvelope.Request(save ? "personalProfile.saveVisibility" : "personalProfile.readVisibility",
                "scm-visibility", generation, payload, owner));
        var body = new { schemaVersion = 1, expectedRevision = 7, visibility = "friendsAndMainFleet" };
        var read = await Request(false, new { schemaVersion = 1 });
        Check(read.Response.Error is null && read.Response.Payload.GetProperty("visibility").GetString() == "private",
            "pure SCM privacy reads Java without a legacy account");
        Check(read.Response.Payload.GetProperty("availableVisibilities").ToString().Contains("friendsAndMainFleet") &&
            !read.Response.Payload.ToString().Contains("friendsFleetAndOrganizations"), "SCM scope is not broadened to organizations");
        var saved = await Request(true, body);
        Check(saved.Response.Error is null && saved.Response.Payload.GetProperty("revision").GetInt64() == 8,
            "SCM visibility writes through dedicated Java endpoint");
        await Request(false, new { schemaVersion = 1 }); // Transport asserts write grant did not replace read bearer.
        foreach (var mode in new[] { "denied", "wrong-subject", "missing-scope" })
        {
            authorization.Mode = mode;
            var calls = transport.Calls;
            Check((await Request(true, body)).Response.Error is not null && calls == transport.Calls,
                "invalid grant cannot write: " + mode);
        }
        authorization.Mode = "granted";
        var authCalls = authorization.Calls;
        Check((await Request(true, new { schemaVersion = 1, expectedRevision = 7, visibility = "friendsFleetAndOrganizations" }))
            .Response.Error is not null && authorization.Calls == authCalls, "legacy organization scope is not silently converted");
        transport.Status = HttpStatusCode.Conflict;
        var before = transport.Calls;
        Check((await Request(true, body)).Response.Error?.Code == "profile.visibility_conflict" && transport.Calls == before + 1,
            "CAS conflict is not retried");
        transport.Status = HttpStatusCode.OK;
        transport.WrongAck = true;
        Check((await Request(true, body)).Response.Error is not null, "wrong acknowledgement never reports success");
        transport.WrongAck = false;
        transport.Status = HttpStatusCode.ServiceUnavailable;
        before = transport.Calls;
        Check((await Request(false, new { schemaVersion = 1 })).Response.Error is not null && transport.Calls == before + 1,
            "Java read outage has no legacy fallback");
        await host.LogoutAsync(owner, default);
        before = transport.Calls; authCalls = authorization.Calls;
        Check((await Request(true, body)).Response.Error is not null && transport.Calls == before && authorization.Calls == authCalls,
            "stale owner cannot authorize or write");
    }

    private sealed class ScmVisibilityTransport : HttpMessageHandler
    {
        internal int Calls;
        internal bool WrongAck;
        internal HttpStatusCode Status = HttpStatusCode.OK;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Calls++;
            if (request.Method == HttpMethod.Patch)
            {
                Check(request.RequestUri!.AbsolutePath == "/app-api/starbridge/v1/personal-profile/visibility" &&
                    request.Headers.Authorization?.Parameter == "synthetic-write-token", "verified write endpoint and token");
                using var body = System.Text.Json.JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
                Check(body.RootElement.EnumerateObject().Count() == 2 && body.RootElement.GetProperty("expectedRevision").GetInt64() == 7 &&
                    body.RootElement.GetProperty("visibility").GetString() == "friendsAndMainFleet", "write contains only privacy and revision");
                return new(Status) { Content = JsonContent.Create(new { schemaVersion = 1, revision = WrongAck ? 7 : 8,
                    visibility = "friendsAndMainFleet" }) };
            }
            Check(request.Method == HttpMethod.Get && request.RequestUri!.AbsolutePath == "/app-api/starbridge/v1/personal-profile" &&
                request.Headers.Authorization?.Parameter == "synthetic-read-token", "normal Java read session survives privacy write");
            return new(Status) { Content = JsonContent.Create(new StarBridge.Core.Profiles.PersonalProfileDocumentContract(
                StarBridge.Core.Profiles.PersonalProfileContractPolicy.CurrentSchemaVersion, "synthetic-public", false, 7,
                DateTimeOffset.UtcNow, new("Pilot", ""), StarBridge.Core.Profiles.PersonalProfileContentContract.Empty, null)) };
        }
    }
}
