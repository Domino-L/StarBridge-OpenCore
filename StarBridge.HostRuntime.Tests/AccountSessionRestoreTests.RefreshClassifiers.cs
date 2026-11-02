using System.Net;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Friends;
using StarBridge.HostRuntime.OfficialFleet;
using StarBridge.NativeBridge;

internal static partial class AccountSessionRestoreTests
{
    internal static async Task RefreshTransientClassifiers()
    {
        var temporary = new ScmRefreshTemporarilyUnavailableException("Synthetic refresh failure");
        AssertEqual<HttpStatusCode?>(null, temporary.StatusCode, "refresh status cannot masquerade as a resource 401");
        foreach (var failure in new[] {
            AccountProfileReadFailures.Classify(temporary)!,
            PersonalProfileReadFailures.FromException(temporary, default),
            OfficialFleetReadFailures.FromException(temporary, default),
            FriendsReadFailures.FromTransport(temporary, default) })
        {
            AssertEqual(true, failure.Retryable, "refresh temporary classifier must be retryable");
            AssertEqual(false, failure.Code == AccountBridgeStableErrors.ReauthorizationRequired, "refresh temporary classifier cannot require login");
        }
        foreach (var error in new[] { "invalid_client", "invalid_grant" })
        foreach (var cached in new[] { true, false })
        foreach (var expired in new[] { false, true })
        {
            var root = Path.Combine(HostDataRoot.CurrentRoot, "cx-l07-" + Guid.NewGuid().ToString("N"));
            var options = ScmOAuthOptions.Create(CreateEnvironmentSettings());
            var vault = new RaceVault();
            var key = options.AuthorityId + ":subject-1";
            vault.SaveRefreshToken(key, "synthetic-refresh");
            var refreshes = 0;
            var failing = false;
            using var handler = new ScriptedHandler(request => {
                if (request.RequestUri == options.TokenEndpoint)
                {
                    refreshes++;
                    return failing ? JsonResponse(HttpStatusCode.Unauthorized, "{\"error\":\"" + error + "\"}") :
                        JsonResponse(HttpStatusCode.OK, "{\"access_token\":\"synthetic-access\",\"refresh_token\":\"synthetic-next\",\"expires_in\":3600}");
                }
                if (request.RequestUri?.AbsolutePath == options.MeEndpoint.AbsolutePath)
                    return JsonResponse(HttpStatusCode.OK, "{\"subject\":\"subject-1\",\"capabilities\":[\"profile.read\"]}");
                if (request.RequestUri == options.TimeZoneDirectoryEndpoint) return JsonResponse(HttpStatusCode.OK,
                    "{\"code\":0,\"data\":[{\"value\":\"UTC\",\"label\":\"UTC\",\"offset\":\"UTC+00:00\"}]}");
                return failing ? JsonResponse(HttpStatusCode.Unauthorized, "{}") :
                    JsonResponse(HttpStatusCode.OK, "{\"subject\":\"subject-1\",\"displayName\":\"Synthetic Pilot\",\"locale\":\"zh-CN\",\"timeZone\":\"UTC\"}");
            });
            var clock = new CredentialClock();
            var oauth = new OAuthPkceClient(new ScmHttpClient(handler), vault, options) { SessionClock = clock };
            var session = (await oauth.TryRestoreSessionAsync(default))!;
            var version = oauth.CurrentCredentialVersion;
            var cache = new ScmProfileCacheStore(root);
            using var host = new ScmAccountBridgeHost(oauth, cache, "development", () => null, session, 7);
            using var runtime = new AccountBridgeRuntime(host);
            var context = host.CurrentContext!;
            var route = AccountRouteIdentity.Create("development", options.AuthorityId, "subject-1", null);
            if (cached) await ReadProfile();
            var cacheBefore = cache.Load(route)?.CachedAtUtc;
            if (expired) clock.Now = clock.Now.AddHours(2);
            failing = true;
            var result = (await ReadProfile()).Response;
            if (error == "invalid_client")
            {
                AssertEqual(cached ? "ok" : "error", result.Status, "temporary failure display result");
                if (cached) AssertEqual("cache", result.Payload.GetProperty("source").GetString(), "temporary refresh retains cached display");
                else
                {
                    AssertEqual("profile.read_transient", result.Error?.Code, "temporary refresh stable error");
                    AssertEqual<bool?>(true, result.Error?.Retryable, "temporary refresh can retry");
                }
                AssertEqual(cacheBefore, cache.Load(route)?.CachedAtUtc, "temporary refresh does not clear or advance cache");
                AssertEqual(7L, runtime.Generation, "temporary refresh preserves generation");
                AssertEqual(version, oauth.CurrentCredentialVersion, "temporary refresh preserves credential version");
                AssertEqual(0, vault.Deletes, "temporary refresh preserves vault");
            }
            else
            {
                AssertEqual("account.reauthorization_required", result.Error?.Code, "invalid_grant requires reauthorization");
                AssertEqual(1, vault.Deletes, "invalid_grant deletes exactly once");
                AssertEqual<Guid?>(null, oauth.CurrentCredentialVersion, "rejected credential has no current version");
                AssertEqual(true, runtime.Generation > 7, "true rejection advances account generation");
                AssertEqual(true, cache.Load(route) is null, "true rejection clears cached display");
            }
            AssertEqual(2, refreshes, "resource 401 makes one refresh attempt");
            Console.WriteLine($"CX-L07 refresh {error} cached={cached} expired={expired}: refreshes=2 deletes={vault.Deletes} generation={runtime.Generation}");
            ValueTask<BridgeDispatchBatch> ReadProfile() => runtime.DispatchAsync(BridgeEnvelope.Request(
                "profile.getSelf", Guid.NewGuid().ToString("N"), runtime.Generation, new { schemaVersion = 1 }, context));
        }
    }

    private sealed class CredentialClock : TimeProvider
    {
        internal DateTimeOffset Now { get; set; } = DateTimeOffset.UtcNow;
        public override DateTimeOffset GetUtcNow() => Now;
    }
}
