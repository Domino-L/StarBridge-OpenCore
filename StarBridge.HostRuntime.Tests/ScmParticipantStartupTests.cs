using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.LegacyRelay;

internal static partial class LegacyPasswordLoginTests
{
    internal static async Task ScmParticipantRootReadDoesNotWaitForDiscovery()
    {
        using var transport = new EnrollmentTransport { Mode = "hold-registration" };
        var coordinator = new StartupOwnerCoordinator();
        using var reader = new S2CompatibilityReader(coordinator, UnavailableLegacyRelayAccountPort.Instance);
        using var host = StartupParticipantHost(transport, reader);
        using var cancellation = new CancellationTokenSource();
        Task<AccountBridgeSessionProjection>? reading = null;
        host.EnableParticipantSynchronization();
        try
        {
            // Hold the original background owner read before it can enter
            // enrollment. The root request must still verify its own owner.
            await coordinator.BackgroundStarted.Task.WaitAsync(TimeSpan.FromSeconds(3));
            reading = host.GetCurrentAsync(cancellation.Token);
            var current = await reading.WaitAsync(TimeSpan.FromSeconds(2));
            Check(current.Context == host.CurrentContext && current.Context is not null,
                "Root read must project the real current account independently of discovery");
            Check(coordinator.Reads == 2 && host.ResolveLocalDataOwner(current.Context!) == current.Context,
                "Root readiness must retain fresh local storage ownership verification");
            Check(transport.Registrations == 0, "Root read must not steal the background registration");
            coordinator.ReleaseBackground.TrySetResult();
            await transport.RegistrationCompleted.Task.WaitAsync(TimeSpan.FromSeconds(3));
            await host.GetCurrentAsync(cancellation.Token).WaitAsync(TimeSpan.FromSeconds(2));
            Check(transport.Registrations == 1, "Polling while registration is pending must not replay it");
        }
        finally
        {
            cancellation.Cancel();
            host.Dispose();
            coordinator.ReleaseBackground.TrySetResult();
            if (reading is not null) try { await reading; } catch (OperationCanceledException) { }
            await host.ParticipantLoopCompletion.WaitAsync(TimeSpan.FromSeconds(3));
        }
        Check(host.ParticipantLoopCompletion.IsCompletedSuccessfully,
            "The owned loop must cancel and exit while discovery is still held");
    }

    internal static async Task ScmParticipantRootReadStillWaitsForOwner()
    {
        using var transport = new EnrollmentTransport();
        var coordinator = new StartupOwnerCoordinator { HoldRoot = true };
        using var reader = new S2CompatibilityReader(coordinator, UnavailableLegacyRelayAccountPort.Instance);
        using var host = StartupParticipantHost(transport, reader);
        using var cancellation = new CancellationTokenSource();
        Task<AccountBridgeSessionProjection>? reading = null;
        host.EnableParticipantSynchronization();
        try
        {
            await coordinator.BackgroundStarted.Task.WaitAsync(TimeSpan.FromSeconds(3));
            reading = host.GetCurrentAsync(cancellation.Token);
            await coordinator.RootStarted.Task.WaitAsync(TimeSpan.FromSeconds(3));
            Check(!reading.IsCompleted, "Root read cannot declare readiness before its storage owner check");
            cancellation.Cancel();
            try { await reading; throw new Exception("Expected cancelled owner read"); }
            catch (OperationCanceledException) { }
            Check(transport.Registrations == 0, "Cancelled owner verification cannot start registration");
        }
        finally
        {
            cancellation.Cancel();
            host.Dispose();
            coordinator.ReleaseBackground.TrySetResult();
            if (reading is not null) try { await reading; } catch (OperationCanceledException) { }
            await host.ParticipantLoopCompletion.WaitAsync(TimeSpan.FromSeconds(3));
        }
    }

    private static ScmAccountBridgeHost StartupParticipantHost(EnrollmentTransport transport, S2CompatibilityReader reader)
    {
        var uri = new Uri("http://127.0.0.1:9/");
        var oauth = new OAuthPkceClient(new ScmHttpClient(transport), new ScmVisitorVault(),
            new ScmOAuthOptions("synthetic", uri, uri, uri, "synthetic", "synthetic", "openid profile.read", "/callback"));
        return new(oauth, new ScmProfileCacheStore(), "integration", () => null,
            initialSession: new ScmOAuthSession("synthetic", "owner", "Pilot", "read-token",
                DateTimeOffset.UtcNow.AddHours(1), ["profile.read"]), compatibilityReader: reader);
    }

    private sealed class StartupOwnerCoordinator : IAccountCompatibilityCoordinator
    {
        internal int Reads;
        internal bool HoldRoot;
        internal readonly TaskCompletionSource BackgroundStarted = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource RootStarted = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource ReleaseBackground = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public async Task<AccountBridgeCompatibilityProjection> ReadAsync(ScmOAuthSession session, CancellationToken token)
        {
            if (Interlocked.Increment(ref Reads) == 1)
            {
                BackgroundStarted.TrySetResult();
                await ReleaseBackground.Task.WaitAsync(token);
            }
            else
            {
                RootStarted.TrySetResult();
                if (HoldRoot) await Task.Delay(Timeout.InfiniteTimeSpan, token);
            }
            return new("unlinked", "notApplicable", false, false, ["linkExistingAccount"], null);
        }
        public Task<AccountBridgeCompatibilityProjection> LinkExistingAsync(ScmOAuthSession session,
            LegacyIdentityLinkPasswordCredential? credential, CancellationToken token) => throw new Exception("Unexpected link");
        public Task<AccountBridgeCompatibilityProjection> CreateCompatibilityIdentityAsync(ScmOAuthSession session,
            CancellationToken token) => throw new Exception("Unexpected provision");
    }
}
