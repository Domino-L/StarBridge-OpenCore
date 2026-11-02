using System.Net;
using System.Net.Http.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.LegacyRelay;

internal static partial class LegacyPasswordLoginTests
{
    internal static async Task ScmParticipantEnrollment()
    {
        await BackgroundEnrollmentWaitsForBusyMutationLane();
        await CancelQueuedBackgroundEnrollment();
        await OpaqueIssuerParticipantEnrollment();
        using var transport = new EnrollmentTransport();
        var uri = new Uri("http://127.0.0.1:9/");
        var oauth = new OAuthPkceClient(new ScmHttpClient(transport), new ScmVisitorVault(),
            new ScmOAuthOptions("synthetic", uri, uri, uri, "synthetic", "synthetic", "openid profile.read", "/callback"));
        var clock = new ParticipantTestClock();
        using var host = new ScmAccountBridgeHost(oauth, new ScmProfileCacheStore(), "integration", () => null,
            initialSession: new ScmOAuthSession("synthetic", "owner", "Pilot", "read-token",
                DateTimeOffset.UtcNow.AddHours(1), ["profile.read"])) { ParticipantClock = clock };
        await host.GetCurrentAsync(default);
        Check(transport.Registrations == 1,
            "authenticated SCM participant is registered without a room, friend action or legacy account");
        await host.GetCurrentAsync(default);
        Check(transport.Registrations == 1, "session polling does not repeatedly write the participant index");
        clock.Now = clock.Now.AddMinutes(1);
        await host.GetCurrentAsync(default);
        Check(transport.Registrations == 1 && transport.Refreshes == 1,
            "next session synchronization refreshes current owner data without repeating registration");
        await host.GetCurrentAsync(default);
        Check(transport.Refreshes == 1, "index refresh is bounded to one per minute");
        using (var backgroundTransport = new EnrollmentTransport()) {
            var backgroundClock = new ParticipantTestClock();
            var backgroundOauth = new OAuthPkceClient(new ScmHttpClient(backgroundTransport), new ScmVisitorVault(),
                new ScmOAuthOptions("synthetic", uri, uri, uri, "synthetic", "synthetic", "openid profile.read", "/callback"));
            using var backgroundHost = new ScmAccountBridgeHost(backgroundOauth, new ScmProfileCacheStore(), "integration", () => null,
                initialSession: new ScmOAuthSession("synthetic", "owner", "Pilot", "read-token",
                    DateTimeOffset.UtcNow.AddHours(1), ["profile.read"])) { ParticipantClock = backgroundClock };
            backgroundHost.EnableParticipantSynchronization(TimeSpan.FromMilliseconds(10));
            await backgroundTransport.RegistrationCompleted.Task.WaitAsync(TimeSpan.FromSeconds(3));
            backgroundClock.Now = backgroundClock.Now.AddMinutes(1);
            await backgroundTransport.RefreshCompleted.Task.WaitAsync(TimeSpan.FromSeconds(3));
            Check(backgroundTransport.Registrations == 1 && backgroundTransport.Refreshes == 1,
                "native lifecycle refreshes without Flutter account-page reads");
            backgroundHost.Dispose();
            await backgroundHost.ParticipantLoopCompletion.WaitAsync(TimeSpan.FromSeconds(3));
            Check(backgroundHost.ParticipantLoopCompletion.IsCompletedSuccessfully,
                "participant loop terminates cleanly when account host closes");
        }
        using (var cancelledTransport = new EnrollmentTransport { Mode = "cancel-before-write" }) {
            var cancelledOauth = new OAuthPkceClient(new ScmHttpClient(cancelledTransport), new ScmVisitorVault(),
                new ScmOAuthOptions("synthetic", uri, uri, uri, "synthetic", "synthetic", "openid profile.read", "/callback"));
            using var cancelledHost = new ScmAccountBridgeHost(cancelledOauth, new ScmProfileCacheStore(), "integration", () => null,
                initialSession: new ScmOAuthSession("synthetic", "owner", "Pilot", "read-token",
                    DateTimeOffset.UtcNow.AddHours(1), ["profile.read"]));
            using var cancellation = new CancellationTokenSource();
            var reading = cancelledHost.GetCurrentAsync(cancellation.Token);
            await cancelledTransport.IdentityReadStarted.Task.WaitAsync(TimeSpan.FromSeconds(2));
            cancellation.Cancel();
            try { await reading; throw new Exception("Expected cancelled identity read."); }
            catch (OperationCanceledException) { }
            Check(cancelledTransport.Registrations == 0, "cancelled identity read must not start a write");
            cancelledTransport.Mode = "ok";
            await cancelledHost.GetCurrentAsync(default);
            Check(cancelledTransport.Registrations == 1, "a read cancelled before any write must not permanently suppress enrollment");
        }
        foreach (var mode in new[] { "unavailable", "wrong-owner", "oversized" }) {
            using var failedTransport = new EnrollmentTransport { Mode = mode };
            var recoveryClock = new ParticipantTestClock();
            var failedOauth = new OAuthPkceClient(new ScmHttpClient(failedTransport), new ScmVisitorVault(),
                new ScmOAuthOptions("synthetic", uri, uri, uri, "synthetic", "synthetic", "openid profile.read", "/callback"));
            using var failedHost = new ScmAccountBridgeHost(failedOauth, new ScmProfileCacheStore(), "integration", () => null,
                initialSession: new ScmOAuthSession("synthetic", "owner", "Pilot", "read-token",
                    DateTimeOffset.UtcNow.AddHours(1), ["profile.read"])) { ParticipantClock = recoveryClock };
            await failedHost.GetCurrentAsync(default);
            await failedHost.GetCurrentAsync(default);
            Check(failedHost.CurrentContext?.Subject == "owner", "registration failure preserves SCM session");
            Check(failedTransport.Registrations == 1, "uncertain registration is not replayed by polling");
            failedTransport.Mode = "ok";
            recoveryClock.Now = recoveryClock.Now.AddMinutes(1);
            await failedHost.GetCurrentAsync(default);
            Check(failedTransport.Registrations == 1 && failedTransport.Refreshes == 1,
                "ambiguous registration recovery refreshes an existing identity only, never repeats creation");
        }
    }

    private static async Task BackgroundEnrollmentWaitsForBusyMutationLane()
    {
        using var transport = new EnrollmentTransport();
        var coordinator = new StartupOwnerCoordinator();
        using var reader = new S2CompatibilityReader(coordinator, UnavailableLegacyRelayAccountPort.Instance);
        using var host = StartupParticipantHost(transport, reader);
        var gate = (AccountMutationGate)typeof(ScmAccountBridgeHost).GetField("_mutationGate",
            System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)!.GetValue(host)!;
        var held = await gate.EnterSharedAsync(default);
        try
        {
            // Exercise the real background lifecycle and its real Host gate.
            // A one-hour cadence prevents a missed cycle from hiding the bug.
            host.EnableParticipantSynchronization(TimeSpan.FromHours(1));
            await coordinator.BackgroundStarted.Task.WaitAsync(TimeSpan.FromSeconds(3));
            coordinator.ReleaseBackground.TrySetResult();
            // Keep real read admission occupied beyond a zero-timeout attempt.
            await Task.Delay(TimeSpan.FromSeconds(1));
            Check(transport.Registrations == 0, "enrollment must preserve the existing shared read barrier");
            await held.DisposeAsync();
            await transport.RegistrationCompleted.Task.WaitAsync(TimeSpan.FromSeconds(3));
            Check(transport.Registrations == 1,
                "background enrollment must wait for a brief busy lane instead of losing its entire cycle");
        }
        finally
        {
            await held.DisposeAsync();
            coordinator.ReleaseBackground.TrySetResult();
            host.Dispose();
            await host.ParticipantLoopCompletion.WaitAsync(TimeSpan.FromSeconds(3));
        }
    }

    private static async Task CancelQueuedBackgroundEnrollment()
    {
        using var transport = new EnrollmentTransport();
        var coordinator = new StartupOwnerCoordinator();
        using var reader = new S2CompatibilityReader(coordinator, UnavailableLegacyRelayAccountPort.Instance);
        using var host = StartupParticipantHost(transport, reader);
        var flags = System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic;
        var gate = (AccountMutationGate)typeof(ScmAccountBridgeHost).GetField("_mutationGate", flags)!.GetValue(host)!;
        await using var held = await gate.EnterSharedAsync(default);
        host.EnableParticipantSynchronization(TimeSpan.FromHours(1));
        await coordinator.BackgroundStarted.Task.WaitAsync(TimeSpan.FromSeconds(3));
        coordinator.ReleaseBackground.TrySetResult();
        await Task.Delay(TimeSpan.FromMilliseconds(200));
        typeof(ScmAccountBridgeHost).GetMethod("StopParticipantLoop", flags)!.Invoke(host, null);
        await host.ParticipantLoopCompletion.WaitAsync(TimeSpan.FromSeconds(3));
        Check(transport.Registrations == 0, "retiring a queued background owner cannot start registration");
        await using var nextRead = await gate.EnterSharedAsync(default).AsTask().WaitAsync(TimeSpan.FromSeconds(1));
        Check(host.ParticipantLoopCompletion.IsCompletedSuccessfully,
            "queued enrollment cancellation releases read admission and drains its actual loop");
    }

    private static async Task OpaqueIssuerParticipantEnrollment()
    {
        foreach (var issuer in new[] { "scm-production", "SCM-Production", "https://issuer.example/", "http://127.0.0.1:9/" })
            await CheckIssuerEnrollment(issuer, expectedRegistrations: 1);
        foreach (var issuer in new string?[] { null, "", " ", " scm-production", "scm-production ", "scm\nproduction", new('x', 161) })
            await CheckIssuerEnrollment(issuer, expectedRegistrations: 0);
    }

    private static async Task CheckIssuerEnrollment(string? issuer, int expectedRegistrations)
    {
        using var transport = new EnrollmentTransport { Issuer = issuer };
        var uri = new Uri("http://127.0.0.1:9/");
        var oauth = new OAuthPkceClient(new ScmHttpClient(transport), new ScmVisitorVault(),
            new ScmOAuthOptions("synthetic", uri, uri, uri, "synthetic", "synthetic", "openid profile.read", "/callback"));
        using var host = new ScmAccountBridgeHost(oauth, new ScmProfileCacheStore(), "integration", () => null,
            initialSession: new ScmOAuthSession("synthetic", "owner", "Pilot", "read-token",
                DateTimeOffset.UtcNow.AddHours(1), ["profile.read"]));
        await host.GetCurrentAsync(default);
        Check(transport.Registrations == expectedRegistrations,
            "Java opaque issuer reaches self enrollment; malformed issuers cannot register");
        Check(host.CurrentContext?.Subject == "owner", "issuer rejection does not erase the SCM login");
    }

    private sealed class EnrollmentTransport : HttpMessageHandler
    {
        internal int Registrations;
        internal int Refreshes;
        internal string Mode = "ok";
        internal string? Issuer = "http://127.0.0.1:9/";
        internal TaskCompletionSource IdentityReadStarted = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal TaskCompletionSource RegistrationCompleted = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal TaskCompletionSource RefreshCompleted = new(TaskCreationOptions.RunContinuationsAsynchronously);
        private static readonly string Id = "scm-v1:" + new string('a', 64);
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Check(request.Headers.Authorization?.Parameter == "read-token", "registration uses current SCM bearer only");
            if (request.RequestUri!.AbsolutePath == "/app-api/starbridge/v1/business-identity") {
                IdentityReadStarted.TrySetResult();
                if (Mode == "cancel-before-write") await Task.Delay(Timeout.InfiniteTimeSpan, token);
                return Reply(new { schemaVersion = 1, issuer = Issuer, subject = "owner",
                    businessSubjectId = Id, scopes = new[] { "profile.read" } });
            }
            var refresh = request.RequestUri.AbsolutePath == "/app-api/starbridge/v1/business-identity/registration/discovery";
            Check(refresh || request.RequestUri.AbsolutePath == "/app-api/starbridge/v1/business-identity/registration",
                "participant lifecycle never calls legacy registration");
            Check(request.Method == (refresh ? HttpMethod.Put : HttpMethod.Post) && request.RequestUri.Query == "", "explicit self registration or refresh");
            Check(await request.Content!.ReadAsStringAsync(token) == "{}", "no target identity or private Handle supplied");
            if (refresh) Refreshes++; else Registrations++;
            if (refresh) RefreshCompleted.TrySetResult(); else RegistrationCompleted.TrySetResult();
            if (Mode == "hold-registration") await Task.Delay(Timeout.InfiniteTimeSpan, token);
            if (Mode == "unavailable") return new(HttpStatusCode.ServiceUnavailable);
            if (Mode == "oversized") return new(HttpStatusCode.OK) { Content = new StringContent(new string('x', 4097)) };
            if (Mode == "wrong-owner") return Reply(new { schemaVersion = 1, businessSubjectId = "scm-v1:" + new string('b', 64) });
            return Reply(new { schemaVersion = 1, businessSubjectId = Id });
        }
        private static HttpResponseMessage Reply(object body) => new(HttpStatusCode.OK) { Content = JsonContent.Create(body) };
    }

    private sealed class ParticipantTestClock : TimeProvider
    {
        internal DateTimeOffset Now = DateTimeOffset.UtcNow;
        public override DateTimeOffset GetUtcNow() => Now;
    }
}
