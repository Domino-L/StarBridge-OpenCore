using System.Net;
using StarBridge.HostRuntime.Account;
using StarBridge.NativeBridge;

internal static partial class LegacyPasswordLoginTests
{
    private static async Task ScmProfileBackgroundRead()
    {
        using var transport = new ScmBackgroundTransport();
        var uri = new Uri("http://127.0.0.1:9/");
        var options = new StarBridge.HostRuntime.Auth.ScmOAuthOptions("synthetic", uri, uri, uri,
            "synthetic", "synthetic", "openid profile.read", "/callback");
        var oauth = new StarBridge.HostRuntime.Auth.OAuthPkceClient(
            new StarBridge.HostRuntime.Auth.ScmHttpClient(transport), new ScmBackgroundVault(), options);
        var authorization = new ScmBackgroundAuthorization();
        using var host = new ScmAccountBridgeHost(oauth, new StarBridge.HostRuntime.Auth.ScmProfileCacheStore(),
            "integration", () => null, initialSession: new StarBridge.HostRuntime.Auth.ScmOAuthSession(
                "synthetic", "owner", "Pilot", "synthetic-read-token", DateTimeOffset.UtcNow.AddHours(1), ["profile.read"]),
            profileAuthorization: authorization);
        using var dispatcher = new AccountBridgeDispatcher(host);
        var context = host.CurrentContext!;
        var generation = host.Generation;
        async Task<AccountBridgeDispatchResult> Read(object payload) => await dispatcher.DispatchAsync(
            BridgeEnvelope.Request("personalProfile.readBackground", "scm-background", generation, payload, context));
        var result = await Read(new { schemaVersion = 1 });
        Check(result.Response.Error is null, "pure SCM background read must not require a legacy account: " + result.Response.Error?.Code);
        Check(result.Response.Payload.GetProperty("wallpaperId").GetString() == "aurora" &&
            result.Response.Payload.GetProperty("revision").GetInt64() == 7,
            "SCM background uses Java profile revision and wallpaper");
        Check(result.Response.Payload.EnumerateObject().Count() == 3, "background returns only its dedicated projection");
        var calls = transport.Calls;
        result = await Read(new { schemaVersion = 1, subject = "other" });
        Check(result.Response.Error is not null && transport.Calls == calls, "invalid SCM background payload never queries Java");
        async Task<AccountBridgeDispatchResult> Save(object payload) => await dispatcher.DispatchAsync(
            BridgeEnvelope.Request("personalProfile.saveBackground", "scm-background-save", generation, payload, context));
        var savePayload = new { schemaVersion = 1, expectedRevision = 7, wallpaperId = "aurora" };
        var save = await Save(savePayload);
        Check(save.Response.Error is null && save.Response.Payload.GetProperty("revision").GetInt64() == 8 &&
            transport.Patches == 1 && authorization.Calls == 1, "pure SCM background save uses one authorized patch");
        await Read(new { schemaVersion = 1 }); // Transport asserts the normal read bearer survived the write.
        foreach (var mode in new[] { "denied", "wrong-subject", "missing-scope" })
        {
            authorization.Mode = mode;
            calls = transport.Calls;
            save = await Save(savePayload);
            Check(save.Response.Error is not null && transport.Calls == calls, "invalid write grant never sends background: " + mode);
        }
        authorization.Mode = "granted";
        var authCalls = authorization.Calls;
        save = await Save(new { schemaVersion = 1, expectedRevision = "7", wallpaperId = "aurora" });
        Check(save.Response.Error is not null && authorization.Calls == authCalls, "invalid payload never opens authorization");
        transport.Status = HttpStatusCode.Conflict;
        calls = transport.Patches;
        save = await Save(savePayload);
        Check(save.Response.Error?.Code == "profile.background_conflict" && transport.Patches == calls + 1,
            "SCM background revision conflict is not retried");
        transport.Status = HttpStatusCode.OK;
        transport.WrongAck = true;
        save = await Save(savePayload);
        Check(save.Response.Error is not null, "mismatched write acknowledgement cannot report saved");
        transport.WrongAck = false;
        transport.WallpaperId = "../invalid";
        result = await Read(new { schemaVersion = 1 });
        Check(result.Response.Error is not null, "unsupported remote wallpaper never becomes a usable background");
        transport.WallpaperId = "aurora";
        calls = transport.Calls;
        transport.Status = HttpStatusCode.ServiceUnavailable;
        result = await Read(new { schemaVersion = 1 });
        Check(result.Response.Error is not null && transport.Calls == calls + 1,
            "Java failure is visible without legacy fallback");
        await host.LogoutAsync(context, default);
        calls = transport.Calls;
        result = await Read(new { schemaVersion = 1 });
        Check(result.Response.Error is not null && transport.Calls == calls, "stale SCM context cannot read background");
        authCalls = authorization.Calls;
        save = await Save(savePayload);
        Check(save.Response.Error is not null && transport.Calls == calls && authorization.Calls == authCalls,
            "stale SCM save cannot authorize or write");
    }

    private sealed class ScmBackgroundVault : StarBridge.HostRuntime.Auth.ITokenVault
    {
        public void SaveRefreshToken(string key, string value) => throw new InvalidOperationException("Read cannot save credentials");
        public string? LoadRefreshToken(string key) => null;
        public string? LoadActiveAccountKey() => null;
        public void DeleteRefreshToken(string key) { }
    }

    private sealed class ScmBackgroundAuthorization : StarBridge.HostRuntime.Auth.IProfileWriteAuthorizationClient
    {
        internal int Calls;
        internal string Mode = "granted";
        public Task<StarBridge.HostRuntime.Auth.ScmOAuthSession> AuthorizeProfileWriteAsync(
            StarBridge.HostRuntime.Auth.ScmOAuthSession session, CancellationToken token, Action<string>? reportProgress = null)
        {
            Calls++;
            if (Mode == "denied") throw new StarBridge.HostRuntime.Auth.ScmApiForbiddenException("synthetic");
            return Task.FromResult(session with { AccessToken = "synthetic-write-token",
                Subject = Mode == "wrong-subject" ? "other" : session.Subject,
                Capabilities = Mode == "missing-scope" ? [] : ["profile.write"] });
        }
    }

    private sealed class ScmBackgroundTransport : HttpMessageHandler
    {
        internal int Calls;
        internal int Patches;
        internal bool WrongAck;
        internal HttpStatusCode Status = HttpStatusCode.OK;
        internal string WallpaperId = "aurora";
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Calls++;
            if (request.Method == HttpMethod.Patch)
            {
                Patches++;
                Check(request.RequestUri!.AbsolutePath == "/app-api/starbridge/v1/personal-profile/background" &&
                    request.Headers.Authorization?.Parameter == "synthetic-write-token", "dedicated Java route and scoped write bearer");
                using var json = System.Text.Json.JsonDocument.Parse(request.Content!.ReadAsStringAsync(token).GetAwaiter().GetResult());
                Check(json.RootElement.EnumerateObject().Count() == 2 &&
                    json.RootElement.GetProperty("expectedRevision").GetInt64() == 7 &&
                    json.RootElement.GetProperty("wallpaperId").GetString() == "aurora", "write cannot include unrelated profile fields");
                return Task.FromResult(new HttpResponseMessage(Status) { Content = System.Net.Http.Json.JsonContent.Create(
                    new { schemaVersion = 1, revision = 8, wallpaperId = WrongAck ? "wrong" : "aurora" }) });
            }
            Check(request.Method == HttpMethod.Get && request.RequestUri!.AbsolutePath == "/app-api/starbridge/v1/personal-profile",
                "SCM background queries only Java self profile");
            Check(request.Headers.Authorization?.Parameter == "synthetic-read-token", "SCM read bearer remains in Host");
            var profile = new StarBridge.Core.Profiles.PersonalProfileDocumentContract(
                StarBridge.Core.Profiles.PersonalProfileContractPolicy.CurrentSchemaVersion, "synthetic-public", false, 7,
                DateTimeOffset.UtcNow, new("Pilot", ""), StarBridge.Core.Profiles.PersonalProfileContentContract.Empty,
                null, WallpaperId: WallpaperId);
            return Task.FromResult(new HttpResponseMessage(Status) { Content = System.Net.Http.Json.JsonContent.Create(profile) });
        }
    }

}
