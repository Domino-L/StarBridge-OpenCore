using System.Diagnostics;
using System.Net;
using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

internal static partial class AccountSessionRestoreTests
{
    // Native first-content contract probe, separate from Flutter/device acceptance.
    // --require checks actual read-only data while restore waits, never fake Ready.
    internal static async Task<(bool LocalFirstObserved, string Json)> ColdFirstContent(string stage)
    {
        if (stage is not ("token" or "identity" or "none"))
            throw new ArgumentException("Expected token, identity or none.", nameof(stage));
        var root = Path.Combine(Path.GetTempPath(), "StarBridge-cold-first-content-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var settings = CreateEnvironmentSettings();
            var options = ScmOAuthOptions.Create(settings);
            var vault = new WindowsTokenVault(Path.Combine(root, "vault.json"));
            vault.SaveRefreshToken(options.AuthorityId + ":synthetic-cold-owner", "synthetic-cold-refresh");
            var owner = new BridgeAccountContext(settings.EnvironmentName, options.AuthorityId, "synthetic-cold-owner");
            var cache = new OfflineAccountStore(root);
            const string avatar = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAAB";
            using (var warmHandler = new ColdContentHandler(options, "none"))
            using (var warm = Runtime(warmHandler))
            {
                var first = (await ReadCurrent(warm, "synthetic-cold-seed")).Response;
                AssertEqual("signedIn", first.Payload.GetProperty("state").GetString(), "warm control authenticates");
                AssertEqual("Synthetic Cold Pilot", first.Payload.GetProperty("displayName").GetString(), "warm display control");
                AssertEqual(0L, first.SessionGeneration, "response preserves its original request generation");
                AssertEqual(1L, warm.Generation, "first restore advances the actual account generation");
                AssertEqual(owner, first.AccountContext, "warm result has the actual authenticated owner");
                AssertEqual(true, cache.ReadSelectedDisplay(owner, () => true) is not null,
                    "accepted first root must persist display before runtime disposal without a second root read");
                new StarBridge.HostRuntime.Profiles.LocalPersonalProfileStore(root).Save(owner, 0,
                    Guid.NewGuid().ToString("N"), new("Synthetic Cold Pilot", "Stored cold introduction", 0, "none", [], []), () => true);
                cache.ObserveProfile(owner, JsonSerializer.SerializeToElement(new {
                    schemaVersion = 1, editable = true,
                    profile = new { identity = new { callSign = "Synthetic Cold Pilot", avatarAssetId = avatar }, content = new { } }
                }), () => true);
            }
            var stored = cache.ReadSelectedDisplay(owner, () => true);
            AssertEqual(true, stored is not null, "actual warm root must persist display before cold restart");
            using var handler = new ColdContentHandler(options, stage);
            using var cold = Runtime(handler);
            BridgeEnvelope? preparing = null;
            cold.EventReady += frame =>
            {
                if (frame.Name == "account.restoreDisplay") preparing = frame;
            };
            var clock = Stopwatch.StartNew();
            var restoring = cold.DispatchAsync(BridgeEnvelope.Request("account.getCurrent", "synthetic-cold-held", cold.Generation,
                new { schemaVersion = 1, restoreDisplayProgress = true })).AsTask();
            try
            {
                await handler.Entered.Task.WaitAsync(TimeSpan.FromSeconds(10));
                // This is a deterministic network barrier, not a wall-clock
                // latency threshold. Do not release until observations are taken.
                var pending = !restoring.IsCompleted;
                var dataStillOnDisk = cache.ReadSelectedDisplay(owner, () => true) is not null;
                var retainedDisplayPublished = preparing is not null;
                BridgeEnvelope? cachedProfile = null;
                if (preparing is not null)
                {
                    AssertEqual<BridgeAccountContext?>(null, preparing.AccountContext, "preparing display has no authority");
                    var readId = preparing.Payload.GetProperty("retainedDisplay").GetProperty("readId").GetString();
                    cachedProfile = (await cold.DispatchAsync(BridgeEnvelope.Request("account.offlineData.read",
                        "synthetic-cold-profile-read", preparing.SessionGeneration,
                        new { schemaVersion = 1, readId, kind = "profile" }))).Response;
                }
                var cachedProfileReadable = cachedProfile?.Status == "ok" &&
                    cachedProfile.Payload.GetProperty("content").GetProperty("introduction").GetString() == "Stored cold introduction";
                var authorityBeforeRelease = cold.Generation != 0;
                if (stage != "none")
                {
                    AssertEqual(true, pending, "fixture must actually hold the selected original HTTP request");
                    AssertEqual(false, authorityBeforeRelease, "cache must not install an authenticated session");
                }
                AssertEqual(true, dataStillOnDisk, "network wait must not delete the warm display");
                handler.Release.TrySetResult();
                var response = (await restoring.WaitAsync(TimeSpan.FromSeconds(10))).Response;
                AssertEqual("signedIn", response.Payload.GetProperty("state").GetString(), "original restore must complete after release");
                AssertEqual(owner, response.AccountContext, "fresh authority belongs to the real synthetic response");
                AssertEqual(avatar, response.Payload.GetProperty("avatarImageData").GetString(),
                    "first authenticated root reuses the exact owner's cached avatar without another remote profile read");
                AssertEqual(handler.Requests, handler.Kinds.Count, "all HTTP requests must belong to the finite fixture contract");
                var localFirst = stage != "none" && retainedDisplayPublished && cachedProfileReadable;
                return (localFirst, JsonSerializer.Serialize(new
                {
                    schemaVersion = 1, stage, storedDisplayAvailable = dataStillOnDisk,
                    heldNetworkRequestObserved = stage != "none", rootPendingAtBarrier = pending,
                    retainedDisplayPublishedAtBarrier = retainedDisplayPublished,
                    cachedProfileReadableAtBarrier = cachedProfileReadable, prepared = preparing,
                    completed = response, cachedProfile,
                    authenticatedGenerationChangedAtBarrier = authorityBeforeRelease,
                    originalRootCompletedAfterRelease = true, httpRequests = handler.Requests,
                    requestKinds = handler.Kinds.ToArray(), observationElapsedMs = clock.Elapsed.TotalMilliseconds,
                    nativeFirstContentObserved = localFirst, deviceMeasurement = false, frontendAcceptance = false,
                    scope = "original account.getCurrent chain; no compatibility/local-owner reader configured"
                }, BridgeProtocol.JsonOptions));
            }
            finally
            {
                handler.Release.TrySetResult();
                // Drain this fixture's own request before disposing its stores.
                await restoring.WaitAsync(TimeSpan.FromSeconds(10));
            }

            AccountBridgeRuntime Runtime(HttpMessageHandler transport)
            {
                var runtime = new AccountBridgeRuntime(new ScmAccountBridgeHost(
                    new OAuthPkceClient(new ScmHttpClient(transport), vault, options),
                    new ScmProfileCacheStore(Path.Combine(root, "profile")), settings.EnvironmentName, () => null));
                runtime.InitializeOfflineAccount(root);
                return runtime;
            }
        }
        finally { Directory.Delete(root, recursive: true); }
    }

    internal static async Task FirstRootDisplayObservationGuards()
    {
        foreach (var boundary in new[] { "cancelled", "retired", "storageUnavailable" })
        {
            var root = Path.Combine(Path.GetTempPath(), "StarBridge-root-display-guard-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(root);
            try
            {
                var settings = CreateEnvironmentSettings();
                var options = ScmOAuthOptions.Create(settings);
                var vault = new WindowsTokenVault(Path.Combine(root, "vault.json"));
                vault.SaveRefreshToken(options.AuthorityId + ":synthetic-cold-owner", "synthetic-guard-refresh");
                using var handler = new ColdContentHandler(options, "none");
                using var cancellation = new CancellationTokenSource();
                var host = new ScmAccountBridgeHost(new OAuthPkceClient(new ScmHttpClient(handler), vault, options),
                    new ScmProfileCacheStore(Path.Combine(root, "profile")), settings.EnvironmentName, () => null);
                using var runtime = new AccountBridgeRuntime(host);
                await using var native = new NativeAccountRuntimeBinding(runtime);
                Task? retirement = null;
                // Run before the runtime's cache observer at the exact real
                // projection seam. No reflection or manufactured session state.
                host.AccountDisplayObserved += (_, _) =>
                {
                    if (boundary == "cancelled") cancellation.Cancel();
                    if (boundary == "retired") retirement = native.DisposeAsync().AsTask();
                };
                runtime.InitializeOfflineAccount(root);
                var path = Path.Combine(root, "offline-account-v1", "snapshot.bin");
                if (boundary == "storageUnavailable") Directory.CreateDirectory(path);
                var response = (await native.DispatchAsync(BridgeEnvelope.Request("account.getCurrent",
                    "synthetic-display-guard", native.Generation, new { schemaVersion = 1 }), cancellation.Token)).Response;
                if (retirement is not null) await retirement.WaitAsync(TimeSpan.FromSeconds(10));
                if (boundary == "storageUnavailable")
                {
                    AssertEqual("ok", response.Status, "optional display storage failure must not fail authentication");
                    AssertEqual("signedIn", response.Payload.GetProperty("state").GetString(), "real restore survives unavailable cache");
                    AssertEqual(true, Directory.Exists(path), "cache failure must not delete or replace the obstructing directory");
                }
                else AssertEqual("cancelled", response.Status, "retired or cancelled root cannot publish its response");
                AssertEqual(false, File.Exists(path), "cancelled, retired or unavailable observation must not create a display snapshot");
            }
            finally { Directory.Delete(root, recursive: true); }
        }
    }

    private sealed class ColdContentHandler(ScmOAuthOptions options, string holdStage) : HttpMessageHandler
    {
        internal readonly TaskCompletionSource Entered = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource Release = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal int Requests;
        internal bool IgnoreCancellation;
        internal string AfterHold = "success";
        internal readonly List<string> Kinds = [];
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Interlocked.Increment(ref Requests);
            var stage = request.RequestUri == options.TokenEndpoint ? "token" :
                request.RequestUri == options.MeEndpoint ? "identity" :
                request.RequestUri == options.BootstrapEndpoint ? "bootstrap" :
                request.RequestUri == options.RevokeEndpoint ? "revoke" :
                request.RequestUri == new Uri(options.ResourceServerBaseUri, "app-api/starbridge/v1/business-identity") ? "businessIdentity" :
                throw new InvalidOperationException("Unexpected endpoint in the cold-content fixture.");
            Kinds.Add(stage);
            if (stage == holdStage)
            {
                Entered.TrySetResult();
                if (IgnoreCancellation) await Release.Task;
                else await Release.Task.WaitAsync(token);
                if (AfterHold == "outage") throw new HttpRequestException("Synthetic held network outage");
                if (AfterHold == "reject") return JsonResponse(stage == "token" ? HttpStatusCode.BadRequest : HttpStatusCode.Unauthorized,
                    stage == "token" ? "{\"error\":\"invalid_grant\"}" : "{}");
            }
            if (holdStage == "none") Entered.TrySetResult();
            if (stage is "bootstrap" or "businessIdentity") return JsonResponse(HttpStatusCode.NotFound, "{}");
            if (stage == "revoke") return JsonResponse(HttpStatusCode.OK, "{}");
            return stage == "token"
                ? JsonResponse(HttpStatusCode.OK, "{\"access_token\":\"synthetic-cold-access\",\"refresh_token\":\"synthetic-cold-rotated\",\"token_type\":\"Bearer\",\"expires_in\":3600}")
                : JsonResponse(HttpStatusCode.OK, "{\"subject\":\"synthetic-cold-owner\",\"displayName\":\"Synthetic Cold Pilot\",\"capabilities\":[\"profile.read\"]}");
        }
    }
}
