using System.Net;
using System.Reflection;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.LegacyRelay;
using StarBridge.HostRuntime.Presence;
using StarBridge.HostRuntime.Privacy;
using StarBridge.NativeBridge;

internal static class OwnerGate073Tests
{
    internal static async Task<int> Run()
    {
        var failures = 0;
        foreach (var (name, run) in new (string, Func<Task>)[] {
            ("BackgroundLinkedOwnerSurvivesEnrollmentHostException", () => Background(false)),
            ("BackgroundLinkedOwnerSurvivesEnrollmentTimeout", () => Background(true)),
            ("BackgroundOwnerRetriesCompatibilityHostException", () => Background(false, true)),
            ("BackgroundOwnerRetriesCompatibilityTimeout", () => Background(true, true)),
            ("DeferredOwnerStartsRenewalOnLiveAdmission", FirstUseBusinessOwnerTests.OwnerGate073Admission),
            ("LiveAdmissionRecoversOwnerCompatibilityOutage", FirstUseBusinessOwnerTests.OwnerGate073AdmissionOutage),
            ("LateStartupOwnerRecoversPublication", LateStartupOwnerRecoversPublication),
            ("DiagnosticChangedUsesInjectedSink", OwnerGate073DiagnosticsTests.ChangedUsesInjectedSink),
            ("LegacyHttpCodesAreWhitelisted", OwnerGate073DiagnosticsTests.LegacyHttpCodesAreWhitelisted),
        })
        {
            try { await run(); Console.WriteLine("PASS CX073 " + name); }
            catch (Exception error) { failures++; Console.WriteLine("FAIL CX073 " + name + " " + error.GetType().Name + " " + error.Message); }
        }
        Console.WriteLine($"CX073 owner: {9 - failures} passed, {failures} failed");
        return failures;
    }

    private static async Task Background(bool timeout, bool compatibilityFault = false)
    {
        var root = Directory.CreateTempSubdirectory("sb-cx073-owner-").FullName;
        using var transport = new EnrollmentFailure(timeout);
        using var legacy = new LegacyPasswordLoginClient(new Uri("https://relay.example.invalid/"), new NoLegacy());
        var coordinator = new Linked();
        using var reader = new S2CompatibilityReader(coordinator, new Relay());
        var clock = new CelebrationTestClock();
        var uri = new Uri("http://127.0.0.1:9/");
        using var host = new ScmAccountBridgeHost(new OAuthPkceClient(new ScmHttpClient(transport), new Vault(),
                new("fixture", uri, uri, uri, "fixture", "fixture", "profile.read", "/callback")),
            new ScmProfileCacheStore(root), "test", () => null,
            initialSession: new("fixture", "owner", "Synthetic", "synthetic-access", DateTimeOffset.UtcNow.AddHours(1), ["profile.read"]),
            compatibilityReader: reader, legacyPasswordLogin: legacy)
            { LocalDataOwnerClock = clock, ParticipantClock = clock };
        var owner = host.CurrentContext!;
        var expected = new BridgeAccountContext("test", legacy.AuthorityId, "synthetic-legacy");
        var logs = new GameLogSettingsStore(root) { ResolveOwner = host.ResolveLocalDataOwner };
        var time = new GameplayTimeStore(root) { ResolveOwner = host.ResolveLocalDataOwner };
        var privacy = new LocalPrivacyStore(root) { ResolveOwner = host.ResolveLocalDataOwner };
        using var capture = StarBridge.HostRuntime.Support.IdentityGateJournal.Capture((_, _) => { });
        host.EnableParticipantSynchronization();
        try
        {
            await transport.Attempt.Task.WaitAsync(TimeSpan.FromSeconds(3));
            // No get-current or compatibility UI reads: wake only the actual background loop.
            for (var minute = 0; minute <= 10; minute++)
            {
                if (minute > 0)
                {
                    await CelebrationTestClock.Until(() => clock.Waiting(TimeSpan.FromMinutes(1)) || host.ParticipantLoopCompletion.IsCompleted);
                    coordinator.Failure = compatibilityFault && minute == 1
                        ? timeout ? new TimeoutException() : new AccountBridgeHostException("synthetic.compatibility")
                        : null;
                    clock.Advance(TimeSpan.FromMinutes(1));
                    await CelebrationTestClock.Until(() => clock.Waiting(TimeSpan.FromMinutes(1)) || host.ParticipantLoopCompletion.IsCompleted);
                }
                Check(host.ResolveLocalDataOwner(owner) == expected, "Background-only linked storage binding must remain fresh for ten minutes.");
                using (var lease = logs.Open(owner)) _ = lease.Read();
                using (var lease = time.Open(owner)) _ = lease.Read();
                _ = privacy.Read(owner);
            }
        }
        finally
        {
            host.Dispose();
            try { await host.ParticipantLoopCompletion.WaitAsync(TimeSpan.FromSeconds(3)); }
            catch (AccountBridgeHostException) { }
            catch (TimeoutException) { }
            Directory.Delete(root, true);
        }
    }

    internal static async Task LateStartupOwnerRecoversPublication()
    {
        var root = Directory.CreateTempSubdirectory("sb-cx073-startup-").FullName;
        try
        {
            var owner = new BridgeAccountContext("test", "fixture", "synthetic-owner");
            var input = new PrivacyPublicationInput(owner, 1, "Synthetic", true, null, GameLogSessionSnapshot.Empty);
            var store = new LocalPrivacyStore(root);
            store.Save(owner, 0, Guid.NewGuid().ToString("N"), new(true,
                new(StarBridge.Core.Presence.PlayerSharedStateFields.Presence, false, true, []), new(0, false)), () => true);
            await store.SetPublicationConsentAsync(owner, 1, true, () => true, default);
            var ready = false;
            store.ResolveOwner = context => ready ? context : throw new LocalPrivacyOwnerUnavailableException();
            var sent = 0;
            using var publication = new PrivacyPublication(store, () => input, (_, payload, _) => {
                if (payload.GetProperty("online").GetBoolean()) sent++;
                return Task.CompletedTask;
            }, startTimer: false);
            await publication.TickAsync();
            Check(sent == 0, "Unverified local owner must not publish.");
            ready = true;
            await publication.TickAsync();
            Check(sent == 1 && publication.Status.State == "applied", "Late owner must restore saved consent on the next tick without apply or login.");
        }
        finally { Directory.Delete(root, true); }
    }

    private static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
    private sealed class EnrollmentFailure(bool timeout) : HttpMessageHandler
    {
        internal readonly TaskCompletionSource Attempt = new(TaskCreationOptions.RunContinuationsAsynchronously);
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Attempt.TrySetResult();
            return Task.FromException<HttpResponseMessage>(timeout ? new TimeoutException() : new AccountBridgeHostException("synthetic.enrollment"));
        }
    }
    private sealed class Vault : ITokenVault
    {
        public string? LoadActiveAccountKey() => null;
        public string? LoadRefreshToken(string key) => null;
        public void SaveRefreshToken(string key, string value) => throw new Exception("Unexpected synthetic write");
        public void DeleteRefreshToken(string key) => throw new Exception("Unexpected synthetic delete");
    }
    private sealed class NoLegacy : ILegacyMigrationCredentialStore
    {
        public LegacyMigrationCredential? Load() => throw new Exception("Unexpected legacy restore");
        public void Save(LegacyMigrationCredential value) => throw new Exception("Unexpected legacy write");
        public void Delete() => throw new Exception("Unexpected legacy delete");
    }
    private sealed class Linked : IAccountCompatibilityCoordinator
    {
        internal Exception? Failure;
        public Task<AccountBridgeCompatibilityProjection> ReadAsync(ScmOAuthSession session, CancellationToken token) =>
            Failure is { } error ? Task.FromException<AccountBridgeCompatibilityProjection>(error) :
            Task.FromResult(new AccountBridgeCompatibilityProjection("linked", "notEstablished", false, false, [], "synthetic-legacy"));
        public Task<AccountBridgeCompatibilityProjection> LinkExistingAsync(ScmOAuthSession session, LegacyIdentityLinkPasswordCredential? credential, CancellationToken token) => throw new Exception("Unexpected link");
        public Task<AccountBridgeCompatibilityProjection> CreateCompatibilityIdentityAsync(ScmOAuthSession session, CancellationToken token) => throw new Exception("Unexpected provision");
    }
    private sealed class Relay : ILegacyRelayAccountPort
    {
        public Task<LegacyRelayAccessState> EstablishAsync(ScmOAuthSession session, string id, CancellationToken token) => Task.FromResult(LegacyRelayAccessState.Ready);
        public Task<LegacyRelayProfileReadResult> ReadOwnProfileAsync(ScmOAuthSession session, string id, CancellationToken token) => throw new Exception("Unexpected profile read");
        public void Reset() { }
    }
}
