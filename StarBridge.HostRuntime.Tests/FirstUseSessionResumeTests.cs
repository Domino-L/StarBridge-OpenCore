using System.Net;
using System.Net.Http.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;

internal static class FirstUseSessionResumeTests
{
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
    private static async Task Case(string name, Func<Task> work)
    { await work(); Console.WriteLine("PASS first-use retained session: " + name); }
    internal static async Task Run()
    {
        await Case("explicit restore stays auth-only and does not open a browser", Success);
        await Case("ordinary current read cannot restore the selected credential", ReadDoesNotRestore);
        await Case("empty or other-authority vault requires sign-in without network", Absent);
        await Case("stale mode before resume cannot inspect or mutate credentials", Stale);
        await Case("same and different-account replacement during refresh remains intact", TokenReplacement);
        await Case("replacement during identity read never grants authorization", IdentityReplacement);
        await Case("cancelled transport cannot rotate or install a late session", Cancelled);
        await Case("rejected refresh requires authorization without deleting credentials", Rejected);
        await Case("identity outage retains actual refresh rotation for explicit retry", Retry);
        await Case("mismatched, malformed and expired identity cannot authorize resume", Invalid);
        await Case("busy credential writer prevents rotation and authorization", WriterConflict);
        await Case("authentication denial with a busy credential writer remains retryable", DeniedWriterConflict);
        await Case("constructor provenance rejects live, fresh and non-deferred owners", Provenance);
        await Case("superseded mode discards late token and identity responses", ModeReplacement);
        await Case("configured device trust must be checked before publishing authorization", DeviceTrust);
        await Case("disposing the original auth owner discards held restore responses", Disposed);
        await Case("slow identity read cannot extend the actual access-token lifetime", ExpiredDuringIdentity);
        await Case("slow device trust read cannot publish an expired authorization", ExpiredDuringDevice);
        await Case("concurrent resume cannot select a second credential owner", Concurrent);
    }
    private sealed class Transport : HttpMessageHandler
    {
        internal int Tokens, Identities, Other;
        internal int Devices;
        internal bool DeviceTrusted = true;
        internal bool HoldToken, HoldIdentity, HoldDevice, Reject;
        internal string Subject = "synthetic-subject", Status = "VERIFIED";
        internal HttpStatusCode IdentityStatus = HttpStatusCode.OK;
        internal long Lifetime = 3600;
        internal readonly TaskCompletionSource TokenEntered = new(TaskCreationOptions.RunContinuationsAsynchronously),
            ReleaseToken = new(TaskCreationOptions.RunContinuationsAsynchronously),
            IdentityEntered = new(TaskCreationOptions.RunContinuationsAsynchronously),
            ReleaseIdentity = new(TaskCreationOptions.RunContinuationsAsynchronously),
            DeviceEntered = new(TaskCreationOptions.RunContinuationsAsynchronously),
            ReleaseDevice = new(TaskCreationOptions.RunContinuationsAsynchronously);
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Check(request.RequestUri?.Host == "synthetic.example.invalid", "Only injected synthetic transport is permitted.");
            if (request.RequestUri!.AbsolutePath.EndsWith("/token", StringComparison.Ordinal))
            {
                Tokens++; TokenEntered.TrySetResult();
                Check((await request.Content!.ReadAsStringAsync()).Contains("grant_type=refresh_token", StringComparison.Ordinal),
                    "Resume must use refresh, not browser authorization.");
                if (HoldToken) await ReleaseToken.Task;
                if (Reject) return new(HttpStatusCode.BadRequest) { Content = JsonContent.Create(new { error = "invalid_grant" }) };
                return new(HttpStatusCode.OK) { Content = JsonContent.Create(new { access_token = "synthetic-access",
                    refresh_token = "synthetic-rotated-" + Tokens, token_type = "Bearer", expires_in = Lifetime,
                    scope = "openid profile.read offline_access" }) };
            }
            if (request.RequestUri.AbsolutePath.EndsWith("/me", StringComparison.Ordinal))
            {
                Identities++; IdentityEntered.TrySetResult(); if (HoldIdentity) await ReleaseIdentity.Task;
                return new(IdentityStatus) { Content = JsonContent.Create(new { subject = Subject, displayName = "Synthetic Pilot",
                    capabilities = new[] { "profile.read" }, gameIdentity = new { status = Status, verified = true,
                        handle = "Pilot-Example", normalizedHandle = "pilot-example" } }) };
            }
            if (request.RequestUri.AbsolutePath.EndsWith("/device/status", StringComparison.Ordinal))
            {
                Devices++; DeviceEntered.TrySetResult(); if (HoldDevice) await ReleaseDevice.Task;
                return new(HttpStatusCode.OK) { Content = JsonContent.Create(new { trusted = DeviceTrusted }) };
            }
            Other++; throw new InvalidOperationException("Resume attempted non-authentication work.");
        }
    }
    private sealed class Fixture : IDisposable
    {
        internal readonly string Root = Path.Combine(Path.GetTempPath(), "starbridge-resume-" + Guid.NewGuid().ToString("N"));
        internal string PathName => Path.Combine(Root, "vault.json");
        internal readonly Transport Transport = new();
        internal readonly WindowsTokenVault Vault;
        internal readonly OAuthPkceClient OAuth;
        internal readonly ScmAccountBridgeHost Host;
        internal readonly List<string> RetiredOwners = new();
        internal bool Current = true;
        internal Fixture(bool seed = true, bool checkDevice = false)
        {
            Vault = new(PathName); if (seed) Vault.SaveRefreshToken("synthetic-scm:synthetic-subject", "synthetic-original");
            var uri = new Uri("https://synthetic.example.invalid/");
            OAuth = new(new ScmHttpClient(Transport), Vault, new("synthetic-scm", uri, uri, uri, "synthetic-client",
                "synthetic-resource", "openid profile.read offline_access", "/callback"),
                deviceIdProvider: checkDevice ? () => "synthetic-device" : null,
                authorizationBrowser: _ => throw new InvalidOperationException("Resume must not open a browser."));
            Host = new(OAuth, new ScmProfileCacheStore(Root), "synthetic", () => null,
                deferBusinessStartup: true, requireRetainedFirstUseSession: true);
            Host.AuthenticatedSessionRetired += owner => RetiredOwners.Add(owner.Authority + "/" + owner.Subject);
        }
        internal Task<FirstUseSessionResume> Resume(CancellationToken token = default) => Host.ResumeFirstUseSessionAsync(() => Current, token);
        public void Dispose()
        {
            Transport.ReleaseToken.TrySetResult(); Transport.ReleaseIdentity.TrySetResult(); Transport.ReleaseDevice.TrySetResult();
            Host.Dispose(); Transport.Dispose();
            if (Directory.Exists(Root)) Directory.Delete(Root, true);
        }
    }
    private static async Task Success()
    {
        using var f = new Fixture(); var generation = f.Host.Generation;
        var result = await f.Resume();
        Check(result is { State: "observed", Session: not null } && f.Host.Generation > generation &&
            f.Host.CurrentContext is not null && f.Host.GameplayTimeContext is null && f.Host.BusinessStartupDeferred &&
            f.Transport.Tokens == 1 && f.Transport.Identities == 1 && f.Transport.Other == 0 &&
            f.OAuth.IsFreshFirstUseSessionCurrent(result.Session) && f.Vault.LoadRefreshToken("synthetic-scm:synthetic-subject") == "synthetic-rotated-1",
            "Only actual rotated vault and checked identity can publish deferred authentication.");
        Check((await f.Resume()).State == "contextChanged" && f.Transport.Tokens == 1, "Installed auth cannot be reused as a new restore owner.");
    }
    private static async Task ReadDoesNotRestore()
    {
        using var f = new Fixture(); var bytes = File.ReadAllBytes(f.PathName);
        await f.Host.GetCurrentAsync(default);
        Check(!f.Host.IsKnownSignedOutForLocalMode && f.Host.CurrentContext is null && f.Transport.Tokens == 0 && f.Transport.Other == 0 &&
            File.ReadAllBytes(f.PathName).SequenceEqual(bytes), "General read cannot choose credentials or restore legacy business.");
    }
    private static async Task Absent()
    {
        foreach (var other in new[] { false, true })
        {
            using var f = new Fixture(false); if (other) f.Vault.SaveRefreshToken("synthetic-other:subject", "synthetic-other");
            Check((await f.Resume()).State == "signInRequired" && f.Transport.Tokens == 0 && f.Host.CurrentContext is null,
                "Absent or wrong authority cannot trigger network or authorization.");
        }
    }
    private static async Task Stale()
    {
        using var f = new Fixture(); var bytes = File.ReadAllBytes(f.PathName); f.Current = false;
        Check((await f.Resume()).State == "contextChanged" && f.Transport.Tokens == 0 && File.ReadAllBytes(f.PathName).SequenceEqual(bytes),
            "An obsolete owner does not read/refresh its vault.");
    }
    private static async Task TokenReplacement()
    {
        foreach (var key in new[] { "synthetic-scm:synthetic-subject", "synthetic-other:subject" })
        {
            using var f = new Fixture(); f.Transport.HoldToken = true; var work = f.Resume();
            await f.Transport.TokenEntered.Task.WaitAsync(TimeSpan.FromSeconds(3)); f.Vault.SaveRefreshToken(key, "synthetic-newer");
            var bytes = File.ReadAllBytes(f.PathName); f.Transport.ReleaseToken.TrySetResult();
            Check((await work).State == "contextChanged" && f.Host.CurrentContext is null && f.Transport.Identities == 0 &&
                File.ReadAllBytes(f.PathName).SequenceEqual(bytes), "A late refresh must not overwrite any newer selected version.");
            Check(f.RetiredOwners.Count == 0, "A late token result cannot retire the replacement login's proof.");
        }
    }
    private static async Task IdentityReplacement()
    {
        using var f = new Fixture(); f.Transport.HoldIdentity = true; var work = f.Resume();
        await f.Transport.IdentityEntered.Task.WaitAsync(TimeSpan.FromSeconds(3)); f.Vault.SaveRefreshToken("synthetic-scm:synthetic-subject", "synthetic-newer");
        var bytes = File.ReadAllBytes(f.PathName); f.Transport.ReleaseIdentity.TrySetResult();
        Check((await work).State == "contextChanged" && f.Host.CurrentContext is null && File.ReadAllBytes(f.PathName).SequenceEqual(bytes),
            "Identity cannot authorize the superseded rotated credential.");
        Check(f.RetiredOwners.Count == 0, "A late identity result cannot retire a same-owner replacement login's proof.");
    }
    private static async Task Cancelled()
    {
        using var f = new Fixture(); var bytes = File.ReadAllBytes(f.PathName); f.Transport.HoldToken = true;
        using var cancel = new CancellationTokenSource(); var work = f.Resume(cancel.Token);
        await f.Transport.TokenEntered.Task.WaitAsync(TimeSpan.FromSeconds(3)); cancel.Cancel();
        Check(!work.IsCompleted, "Actual transport ignoring cancellation remains owned.");
        f.Transport.ReleaseToken.TrySetResult();
        try { await work; throw new InvalidOperationException("Cancelled restore must remain cancelled."); } catch (OperationCanceledException) { }
        Check(f.Host.CurrentContext is null && File.ReadAllBytes(f.PathName).SequenceEqual(bytes), "Cancelled transport cannot install a late session.");
        Check(f.RetiredOwners.Count == 0, "Caller cancellation cannot retire retained appearance authorization.");
    }
    private static async Task Rejected()
    {
        using var f = new Fixture(); var bytes = File.ReadAllBytes(f.PathName); f.Transport.Reject = true;
        Check((await f.Resume()).State == "reauthorizationRequired" && f.Transport.Identities == 0 && f.Host.CurrentContext is null &&
            File.ReadAllBytes(f.PathName).SequenceEqual(bytes), "Expired/rejected login does not revoke or delete the selected version.");
        await f.Host.GetCurrentAsync(default); Check(f.Transport.Tokens == 1, "Reauthorization state cannot implicitly retry/restore.");
        Check(f.RetiredOwners.SequenceEqual(["synthetic-scm/synthetic-subject"]),
            "Explicit rejection must retire the original proof while preserving the credential.");
    }
    private static async Task Retry()
    {
        using var f = new Fixture(); f.Transport.IdentityStatus = HttpStatusCode.ServiceUnavailable;
        Check((await f.Resume()).State == "unavailable" && f.Host.CurrentContext is null &&
            f.Vault.LoadRefreshToken("synthetic-scm:synthetic-subject") == "synthetic-rotated-1", "Outage retains real rotation without business startup.");
        Check(f.RetiredOwners.Count == 0, "Identity service outage cannot revoke offline appearance proof.");
        f.Transport.IdentityStatus = HttpStatusCode.OK;
        Check((await f.Resume()).State == "observed" && f.Transport.Tokens == 2 && f.Transport.Other == 0, "Explicit retry may use the retained rotation.");
    }
    private static async Task Invalid()
    {
        foreach (var mutate in new Action<Transport>[] { t => t.Subject = "synthetic-wrong", t => t.Status = "NEW_STATUS",
            t => t.Lifetime = 0, t => t.Lifetime = long.MaxValue })
        {
            using var f = new Fixture(); mutate(f.Transport); var result = await f.Resume();
            Check(result.State is "unavailable" or "reauthorizationRequired" && result.Session is null && f.Host.CurrentContext is null &&
                f.Transport.Other == 0 && f.Vault.LoadActiveAccountKey() == "synthetic-scm:synthetic-subject", "Invalid identity is not online readiness or logout.");
            Check(f.RetiredOwners.Count == (f.Transport.Subject == "synthetic-wrong" ? 1 : 0),
                "Only a confirmed foreign identity retires proof; malformed or expired responses do not establish revocation.");
        }
    }
    private static async Task WriterConflict()
    {
        using var f = new Fixture(); var bytes = File.ReadAllBytes(f.PathName); f.Transport.HoldToken = true; var work = f.Resume();
        await f.Transport.TokenEntered.Task.WaitAsync(TimeSpan.FromSeconds(3));
        using var lease = new FileStream(f.PathName + ".lock", FileMode.Open, FileAccess.ReadWrite, FileShare.None);
        f.Transport.ReleaseToken.TrySetResult();
        Check((await work).State == "unavailable" && f.Host.CurrentContext is null && f.Transport.Identities == 0 &&
            File.ReadAllBytes(f.PathName).SequenceEqual(bytes), "Failed exact-version rotation cannot install authentication.");
    }
    private static async Task DeniedWriterConflict()
    {
        using var f = new Fixture();
        f.Transport.HoldIdentity = true;
        f.Transport.IdentityStatus = HttpStatusCode.Unauthorized;
        var work = f.Resume();
        await f.Transport.IdentityEntered.Task.WaitAsync(TimeSpan.FromSeconds(3));
        var bytes = File.ReadAllBytes(f.PathName);
        using var writer = new FileStream(f.PathName + ".lock", FileMode.Open, FileAccess.ReadWrite, FileShare.None);
        f.Transport.ReleaseIdentity.TrySetResult();
        Check((await work).State == "unavailable" && f.Host.CurrentContext is null && f.RetiredOwners.Count == 0 &&
            File.ReadAllBytes(f.PathName).SequenceEqual(bytes),
            "Failed rejection observation must stay retryable without changing or retiring an unverified credential version.");
    }

    private static Task Provenance()
    {
        using var f = new Fixture();
        foreach (var pair in new[] { (false, false), (true, true) })
        {
            try { using var host = new ScmAccountBridgeHost(f.OAuth, new ScmProfileCacheStore(f.Root), "synthetic", () => null,
                requireFreshSignIn: pair.Item1, deferBusinessStartup: pair.Item2, requireRetainedFirstUseSession: true);
                throw new InvalidOperationException("Conflicting provenance must be rejected."); }
            catch (ArgumentException) { }
        }
        try
        {
            using var host = new ScmAccountBridgeHost(f.OAuth, new ScmProfileCacheStore(f.Root), "synthetic", () => null,
                initialSession: new("synthetic-scm", "synthetic-subject", "Synthetic Pilot", "synthetic-access",
                    DateTimeOffset.UtcNow.AddHours(1), []), deferBusinessStartup: true, requireRetainedFirstUseSession: true);
            throw new InvalidOperationException("Preloaded auth cannot impersonate a retained restore owner.");
        }
        catch (ArgumentException) { }
        return Task.CompletedTask;
    }
    private static async Task ModeReplacement()
    {
        foreach (var identity in new[] { false, true })
        {
            using var f = new Fixture();
            if (identity) f.Transport.HoldIdentity = true; else f.Transport.HoldToken = true;
            var work = f.Resume();
            await (identity ? f.Transport.IdentityEntered.Task : f.Transport.TokenEntered.Task).WaitAsync(TimeSpan.FromSeconds(3));
            var bytes = File.ReadAllBytes(f.PathName); f.Current = false;
            (identity ? f.Transport.ReleaseIdentity : f.Transport.ReleaseToken).TrySetResult();
            Check((await work).State == "contextChanged" && f.Host.CurrentContext is null &&
                File.ReadAllBytes(f.PathName).SequenceEqual(bytes), "Obsolete mode cannot rotate or install a late session.");
        }
    }
    private static async Task DeviceTrust()
    {
        foreach (var trusted in new[] { false, true })
        {
            using var f = new Fixture(checkDevice: true); f.Transport.DeviceTrusted = trusted;
            var result = await f.Resume();
            Check(result.State == (trusted ? "observed" : "reauthorizationRequired") &&
                (f.Host.CurrentContext is not null) == trusted && f.Host.GameplayTimeContext is null &&
                f.Transport.Devices == 1 && f.Transport.Other == 0 &&
                f.Vault.LoadRefreshToken("synthetic-scm:synthetic-subject") == "synthetic-rotated-1",
                "Device trust is an actual authentication read, never device registration or business startup.");
            Check(f.RetiredOwners.Count == (trusted ? 0 : 1), "Only an explicitly untrusted device retires the original proof.");
        }
    }
    private static async Task Disposed()
    {
        using var f = new Fixture(); var bytes = File.ReadAllBytes(f.PathName); f.Transport.HoldToken = true;
        var work = f.Resume(); await f.Transport.TokenEntered.Task.WaitAsync(TimeSpan.FromSeconds(3)); f.Host.Dispose();
        Check(!work.IsCompleted, "A requested close is not the actual held transport exit.");
        f.Transport.ReleaseToken.TrySetResult();
        Check((await work).State == "contextChanged" && f.Host.CurrentContext is null &&
            File.ReadAllBytes(f.PathName).SequenceEqual(bytes), "Disposed owner cannot rotate or publish a late authorization.");
        Check((await f.Resume()).State == "contextChanged" && f.Transport.Tokens == 1,
            "Disposed owner cannot touch the retired mutation gate or retry authentication.");
    }
    private static async Task ExpiredDuringIdentity()
    {
        using var f = new Fixture(); f.Transport.Lifetime = 1; f.Transport.HoldIdentity = true;
        var work = f.Resume(); await f.Transport.IdentityEntered.Task.WaitAsync(TimeSpan.FromSeconds(3));
        // This bounded wait crosses a real one-second token expiry. No fake
        // clock can satisfy the production OAuth/current-session time checks.
        await Task.Delay(TimeSpan.FromMilliseconds(1250)); f.Transport.ReleaseIdentity.TrySetResult();
        Check((await work).State == "reauthorizationRequired" && f.Host.CurrentContext is null &&
            f.Vault.LoadRefreshToken("synthetic-scm:synthetic-subject") == "synthetic-rotated-1",
            "A delayed /me cannot reset access-token expiry while retaining the actual rotated credential.");
    }
    private static async Task ExpiredDuringDevice()
    {
        using var f = new Fixture(checkDevice: true); f.Transport.Lifetime = 1; f.Transport.HoldDevice = true;
        var work = f.Resume(); await f.Transport.DeviceEntered.Task.WaitAsync(TimeSpan.FromSeconds(3));
        await Task.Delay(TimeSpan.FromMilliseconds(1250)); f.Transport.ReleaseDevice.TrySetResult();
        Check((await work).State == "reauthorizationRequired" && f.Host.CurrentContext is null &&
            f.Vault.LoadRefreshToken("synthetic-scm:synthetic-subject") == "synthetic-rotated-1",
            "Trusted device response cannot extend or publish the expired token.");
    }
    private static async Task Concurrent()
    {
        using var f = new Fixture(); f.Transport.HoldToken = true; var work = f.Resume();
        await f.Transport.TokenEntered.Task.WaitAsync(TimeSpan.FromSeconds(3));
        Check((await f.Resume()).State == "operationInProgress" && f.Transport.Tokens == 1,
            "Concurrent resume must not select, refresh or replace the original credential owner.");
        f.Transport.ReleaseToken.TrySetResult();
        Check((await work).State == "observed" && f.Transport.Tokens == 1, "Only the original resume can publish authorization.");
    }
}
