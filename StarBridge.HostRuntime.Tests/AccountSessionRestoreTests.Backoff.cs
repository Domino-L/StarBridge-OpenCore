using System.Net;
using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

internal static partial class AccountSessionRestoreTests
{
    // Program.cs scenarios use the same manual clock as the backoff fixture.
    internal static (TimeProvider Clock, Action<TimeSpan> Advance) ManualClock()
    {
        var clock = new CredentialClock();
        return (clock, delta => clock.Now = clock.Now.Add(delta));
    }

    internal static async Task Backoff404AndConcurrency()
    {
        using var f = new BackoffFixture();
        await f.Unavailable();
        await Task.WhenAll(Enumerable.Range(0, 20).Select(_ => f.Unavailable()));
        AssertEqual(1, f.Refreshes, "404 window suppresses all callers");
        AssertEqual(0, f.IdentityReads, "no identity traffic in refresh failure window");
        AssertEqual(0, f.Vault.Deletes, "temporary failure keeps credentials");
        var lines = File.ReadLines(Path.Combine(HostDataRoot.CurrentRoot, "scm-auth-diagnostics.log"))
            .Where(line => line.Contains("step=refresh-token outcome=backoff", StringComparison.Ordinal)).ToArray();
        AssertEqual(f.LogsBefore + 1, lines.Length, "only one backoff diagnostic per window");
        AssertEqual(true, lines[^1].EndsWith("attempts=1 waitSeconds=5", StringComparison.Ordinal), "bounded diagnostic fields");
    }

    internal static async Task BackoffDoublingAndCap()
    {
        using var f = new BackoffFixture();
        foreach (var seconds in new[] { 5, 10, 20, 40, 80, 160, 300, 300 })
        {
            await f.Unavailable();
            var attempts = f.Refreshes;
            f.Clock.Now = f.Clock.Now.AddSeconds(seconds).AddMilliseconds(-1);
            await f.Unavailable();
            AssertEqual(attempts, f.Refreshes, "window stays closed until deadline");
            f.Clock.Now = f.Clock.Now.AddMilliseconds(1);
        }
        await Task.WhenAll(Enumerable.Range(0, 12).Select(_ => Task.Run(() => f.Unavailable(checkOutcome: false))));
        AssertEqual(9, f.Refreshes, "expired window admits one failing attempt");
        AssertEqual(ScmSessionRestoreOutcome.CredentialTemporarilyUnavailable, f.OAuth.LastSessionRestoreOutcome, "temporary outcome after concurrent callers");
    }

    internal static async Task BackoffJitterBounds()
    {
        foreach (var (random, seconds) in new[] { (0d, 4d), (1d, 6d) })
        {
            using var f = new BackoffFixture(random);
            await f.Unavailable();
            f.Clock.Now = f.Clock.Now.AddSeconds(seconds).AddMilliseconds(-1);
            await f.Unavailable();
            AssertEqual(1, f.Refreshes, "jitter minimum/maximum wait");
            f.Clock.Now = f.Clock.Now.AddMilliseconds(1);
            await f.Unavailable();
            AssertEqual(2, f.Refreshes, "jitter deadline permits retry");
        }
    }

    internal static async Task BackoffSuccessResets()
    {
        using var f = new BackoffFixture();
        await f.Unavailable();
        f.Clock.Now = f.Clock.Now.AddSeconds(5);
        f.TokenStatus = HttpStatusCode.OK;
        AssertEqual("subject-1", (await f.OAuth.TryRestoreSessionAsync(default))?.Subject, "recovery succeeds");
        f.Clock.Now = f.Clock.Now.AddHours(2);
        f.TokenStatus = HttpStatusCode.NotFound;
        await f.Unavailable();
        f.Clock.Now = f.Clock.Now.AddSeconds(5);
        await f.Unavailable();
        AssertEqual(4, f.Refreshes, "success resets next wait to five seconds");
    }

    internal static async Task BackoffInvalidGrantResets()
    {
        using var f = new BackoffFixture();
        await f.Unavailable();
        f.Clock.Now = f.Clock.Now.AddSeconds(5);
        f.TokenStatus = HttpStatusCode.BadRequest;
        f.Rejected = true;
        AssertEqual<ScmOAuthSession?>(null, await f.OAuth.TryRestoreSessionAsync(default), "invalid_grant rejects");
        AssertEqual(ScmSessionRestoreOutcome.ReauthorizationRequired, f.OAuth.LastSessionRestoreOutcome, "rejected outcome");
        AssertEqual(1, f.Vault.Deletes, "invalid_grant deletes credential once");
        f.Vault.SaveRefreshToken(f.Key, "synthetic-new-login");
        f.Rejected = false;
        f.TokenStatus = HttpStatusCode.NotFound;
        await f.Unavailable();
        f.Clock.Now = f.Clock.Now.AddSeconds(5);
        await f.Unavailable();
        AssertEqual(4, f.Refreshes, "rejection clears failure count and window");
    }

    internal static async Task BackoffTransportAndTimeout()
    {
        foreach (var error in new Exception[] { new HttpRequestException("Synthetic transport"),
            new TaskCanceledException("Synthetic deadline"), new TimeoutException("Synthetic timeout") })
        {
            using var f = new BackoffFixture();
            f.TransportError = error;
            await f.Unavailable();
            await f.Unavailable();
            AssertEqual(1, f.Refreshes, "transport/deadline is backed off");
            AssertEqual(0, f.Vault.Deletes, "transport/deadline retains credential");
            f.Clock.Now = f.Clock.Now.AddSeconds(5);
            await f.Unavailable();
            AssertEqual(2, f.Refreshes, "transport/deadline retries at deadline");
        }
    }

    internal static async Task BackoffIdentityReusesRotation()
    {
        foreach (var status in new[] { HttpStatusCode.BadGateway, HttpStatusCode.Unauthorized })
        {
            using var f = new BackoffFixture();
            f.TokenStatus = HttpStatusCode.OK;
            f.IdentityStatus = status;
            await f.Unavailable();
            await f.Unavailable();
            AssertEqual(1, f.Refreshes, "identity outage rotates once");
            AssertEqual(1, f.IdentityReads, "identity retry suppressed inside window");
            f.Clock.Now = f.Clock.Now.AddSeconds(5);
            f.IdentityStatus = HttpStatusCode.OK;
            AssertEqual("subject-1", (await f.OAuth.TryRestoreSessionAsync(default))?.Subject, "identity recovers");
            AssertEqual(1, f.Refreshes, "committed rotation reused after deadline");
            AssertEqual(2, f.IdentityReads, "only identity is retried");
        }
    }

    internal static async Task BackoffSwitchAndLogoutReset()
    {
        using var f = new BackoffFixture();
        await f.Unavailable();
        f.Clock.Now = f.Clock.Now.AddSeconds(5);
        await f.Unavailable(); // ten-second window for the old owner
        f.Vault.SaveRefreshToken(f.Options.AuthorityId + ":subject-2", "synthetic-other");
        await f.Unavailable();
        AssertEqual(3, f.Refreshes, "switch clears previous owner's window");
        f.Clock.Now = f.Clock.Now.AddSeconds(5);
        await f.Unavailable();
        AssertEqual(4, f.Refreshes, "switch restarts at five seconds");
        await f.OAuth.DeleteCredentialForRemoteLogoutAsync(null, default);
        f.Vault.SaveRefreshToken(f.Options.AuthorityId + ":subject-2", "synthetic-relogin");
        await f.Unavailable();
        AssertEqual(5, f.Refreshes, "logout clears existing window");
    }

    internal static async Task BackoffHostProjection()
    {
        // 404, a remote timeout and a transport deadline all project the same retryable state.
        foreach (var error in new Exception?[] { null, new TimeoutException("Synthetic timeout"),
            new TaskCanceledException("Synthetic deadline") })
            await BackoffHostProjection(error);
    }

    private static async Task BackoffHostProjection(Exception? transportError)
    {
        using var f = new BackoffFixture();
        f.TransportError = transportError;
        using var host = new ScmAccountBridgeHost(f.OAuth, new ScmProfileCacheStore(), "development", () => null);
        using var runtime = new AccountBridgeRuntime(host);
        var generation = runtime.Generation;
        for (var i = 0; i < 2; i++)
        {
            var response = (await ReadCurrent(runtime, "backoff-host-" + i)).Response;
            AssertEqual(BridgeResponseStatuses.Ok, response.Status, "restore is a state projection");
            AssertEqual("credentialTemporarilyUnavailable", response.Payload.GetProperty("state").GetString(), "temporary state before and during backoff");
            AssertEqual(generation, runtime.Generation, "temporary state preserves generation");
            // Exercise the common business guard before it can misclassify a missing session.
            try
            {
                await host.ReadFriendsAsync(new BridgeAccountContext("development", f.Options.AuthorityId, "subject-1"),
                    JsonSerializer.SerializeToElement(new { schemaVersion = 1 }), default);
                throw new Exception("Expected temporary business guard");
            }
            catch (AccountBridgeHostException error)
            {
                AssertEqual(AccountBridgeStableErrors.CredentialTemporarilyUnavailable, error.Code, "business guard is temporary");
                AssertEqual(true, error.Retryable, "business guard can retry");
            }
        }
        AssertEqual(1, f.Refreshes, "Host polling observes backoff without traffic");
        AssertEqual(0, f.Vault.Deletes, "Host keeps credentials");
    }

    internal static Task BackoffBootstrap() => OverlayEntitlementRefreshTests.Verify();

    internal static async Task BackoffDeviceStatus()
    {
        using var f = new BackoffFixture(device: true);
        f.TokenStatus = HttpStatusCode.OK;
        await f.Unavailable();
        await f.Unavailable();
        AssertEqual(1, f.Refreshes, "device outage rotates only once");
        AssertEqual(1, f.DeviceReads, "device outage is backed off");
        f.Clock.Now = f.Clock.Now.AddSeconds(5);
        f.DeviceAvailable = true;
        AssertEqual("subject-1", (await f.OAuth.TryRestoreSessionAsync(default))?.Subject, "device recovers");
        AssertEqual(1, f.Refreshes, "device retry reuses committed rotation");
        AssertEqual(2, f.DeviceReads, "device retry after deadline");
    }

    private sealed class BackoffFixture : IDisposable
    {
        internal readonly CredentialClock Clock = new();
        internal readonly RaceVault Vault = new();
        internal readonly ScmOAuthOptions Options = ScmOAuthOptions.Create(CreateEnvironmentSettings());
        internal readonly OAuthPkceClient OAuth;
        internal readonly int LogsBefore;
        internal string Key => Options.AuthorityId + ":subject-1";
        internal HttpStatusCode TokenStatus = HttpStatusCode.NotFound;
        internal HttpStatusCode IdentityStatus = HttpStatusCode.OK;
        internal bool Rejected;
        internal Exception? TransportError;
        internal int Refreshes;
        internal int IdentityReads;
        internal int DeviceReads;
        internal bool DeviceAvailable;
        private readonly ScriptedHandler _handler;

        internal BackoffFixture(double random = 0.5, bool device = false)
        {
            var log = Path.Combine(HostDataRoot.CurrentRoot, "scm-auth-diagnostics.log");
            LogsBefore = File.Exists(log) ? File.ReadLines(log).Count(line => line.Contains("step=refresh-token outcome=backoff", StringComparison.Ordinal)) : 0;
            Vault.SaveRefreshToken(Key, "synthetic-refresh");
            _handler = new ScriptedHandler(request =>
            {
                if (request.RequestUri == Options.TokenEndpoint)
                {
                    Interlocked.Increment(ref Refreshes);
                    if (TransportError is not null) throw TransportError;
                    return JsonResponse(TokenStatus, Rejected ? "{\"error\":\"invalid_grant\"}" :
                        "{\"access_token\":\"synthetic-access\",\"refresh_token\":\"synthetic-rotated\",\"expires_in\":3600}");
                }
                if (request.RequestUri == Options.DeviceStatusEndpoint)
                {
                    DeviceReads++;
                    return JsonResponse(DeviceAvailable ? HttpStatusCode.OK : HttpStatusCode.BadGateway, "{\"trusted\":true}");
                }
                Interlocked.Increment(ref IdentityReads);
                return JsonResponse(IdentityStatus, "{\"subject\":\"subject-1\",\"capabilities\":[\"profile.read\"]}");
            });
            OAuth = new OAuthPkceClient(new ScmHttpClient(_handler), Vault, Options, device ? () => "synthetic-device" : null)
            { SessionClock = Clock, RestoreBackoffRandom = () => random };
        }

        // A remote failure keeps its original type (HttpRequestException, including
        // ScmRefreshTemporarilyUnavailableException, cancellation or timeout); a
        // blocked window throws ScmRefreshTemporarilyUnavailableException.
        internal async Task Unavailable() => await Unavailable(checkOutcome: true);

        internal async Task Unavailable(bool checkOutcome)
        {
            try { await OAuth.TryRestoreSessionAsync(default); throw new Exception("Expected temporary failure"); }
            catch (Exception error) when (error is HttpRequestException or OperationCanceledException or TimeoutException)
            {
                // LastSessionRestoreOutcome is one shared field; concurrent callers
                // can observe another flight's start, so only serial calls check it.
                if (checkOutcome)
                    AssertEqual(ScmSessionRestoreOutcome.CredentialTemporarilyUnavailable, OAuth.LastSessionRestoreOutcome, "temporary restore outcome");
            }
        }
        public void Dispose() => _handler.Dispose();
    }
}
