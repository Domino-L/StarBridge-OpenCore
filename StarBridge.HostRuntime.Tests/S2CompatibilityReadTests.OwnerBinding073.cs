using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.LegacyRelay;
using StarBridge.HostRuntime.Privacy;
using StarBridge.NativeBridge;

internal static partial class S2CompatibilityReadTests
{
    private static async Task VerifyOwnerJoinedCancellation073()
    {
        using var fixture = new OwnerFixture073();
        var host = fixture.Host;
        var pending = new TaskCompletionSource<AccountBridgeCompatibilityProjection>(TaskCreationOptions.RunContinuationsAsynchronously);
        fixture.Coordinator.Pending = pending;
        var original = host.GetCompatibilityStateAsync(host.CurrentContext!, default);
        using var cancellation = new CancellationTokenSource();
        var joined = host.GetCompatibilityStateAsync(host.CurrentContext!, cancellation.Token);
        cancellation.Cancel();
        var outcome = await CaptureRead073(joined.WaitAsync(TimeSpan.FromSeconds(2)));
        var originalStillPending = !original.IsCompleted;
        pending.SetResult(Coordinator.LinkedProjection);
        await original;
        await CaptureRead073(joined);
        Check(outcome.Error is OperationCanceledException && originalStillPending && fixture.Coordinator.Reads == 1,
            "A joining caller can cancel its own wait without cancelling or duplicating the original read");
        Console.WriteLine("PASS OWNER-BINDING-073 joined cancellation preserves the original physical read");
    }

    private static async Task VerifyOwnerFailureKinds073()
    {
        foreach (var error in new Exception[] { new HttpRequestException(), new IOException(),
            new System.Text.Json.JsonException(), new InvalidOperationException(), new OperationCanceledException(), new TimeoutException() })
        {
            using var fixture = new OwnerFixture073();
            fixture.Coordinator.ReadError = error;
            await ReadUnavailable073(fixture.Host);
            OwnerUnavailable073(fixture.Host, "A failed first read must not invent ownership");
            fixture.Coordinator.ReadError = null;
            await fixture.Host.GetCompatibilityStateAsync(fixture.Host.CurrentContext!, default);
            fixture.Clock.Advance(TimeSpan.FromMinutes(4));
            fixture.Coordinator.ReadError = error;
            await ReadUnavailable073(fixture.Host);
            Check(fixture.Host.ResolveLocalDataOwner(fixture.Host.CurrentContext!) == fixture.LegacyOwner && fixture.Relay.Resets == 2,
                "Every transport failure keeps confirmed ownership and still resets the compatibility reader");
        }
        using (var fixture = new OwnerFixture073())
        {
            await fixture.Host.GetCompatibilityStateAsync(fixture.Host.CurrentContext!, default);
            fixture.Clock.Advance(TimeSpan.FromMinutes(4));
            using var cancelled = new CancellationTokenSource();
            cancelled.Cancel();
            var outcome = await CaptureRead073(fixture.Host.GetCompatibilityStateAsync(fixture.Host.CurrentContext!, cancelled.Token));
            Check(outcome.Error is OperationCanceledException, "Caller cancellation retains its cancellation semantics");
            OwnerUnavailable073(fixture.Host, "Caller cancellation alone must not extend owner freshness");
        }
        Console.WriteLine("PASS OWNER-BINDING-073 six transport failures, reset, no initial owner and caller cancellation");
    }

    private static async Task VerifyOwnerExplicitAnswers073()
    {
        foreach (var answer in new[] { "unlinked", "other-owner", "accountMismatch", "authorizationRequired", "unavailable", "notEstablished", "unknown" })
        {
            using var fixture = new OwnerFixture073();
            var host = fixture.Host;
            var owner = host.CurrentContext!;
            await host.GetCompatibilityStateAsync(owner, default);
            fixture.Clock.Advance(TimeSpan.FromMinutes(4));
            fixture.Coordinator.Failure = true;
            await ReadUnavailable073(host);
            fixture.Coordinator.Failure = false;
            if (answer == "unlinked") fixture.Coordinator.Linked = false;
            else if (answer == "other-owner") fixture.Coordinator.Projection = Coordinator.LinkedProjection with { LegacyAccountId = "synthetic-other" };
            else if (answer == "unknown") fixture.Coordinator.Projection = new("unavailable", "notEstablished", false, false, [], null);
            else fixture.Relay.State = answer switch {
                "accountMismatch" => LegacyRelayAccessState.AccountMismatch,
                "authorizationRequired" => LegacyRelayAccessState.AuthorizationRequired,
                "notEstablished" => LegacyRelayAccessState.NotEstablished,
                _ => LegacyRelayAccessState.Unavailable
            };
            await host.GetCompatibilityStateAsync(owner, default);
            if (answer == "unlinked") Check(host.ResolveLocalDataOwner(owner) == owner, "Explicit unlink immediately selects SCM storage");
            else if (answer == "other-owner") Check(host.ResolveLocalDataOwner(owner) == fixture.LegacyOwner with { Subject = "synthetic-other" },
                "A different confirmed legacy account immediately replaces storage ownership");
            else OwnerUnavailable073(host, "An explicit nonready answer immediately removes ownership");
            fixture.Coordinator.Failure = true;
            await ReadUnavailable073(host);
            if (answer is not ("unlinked" or "other-owner")) OwnerUnavailable073(host, "Later failures must not resurrect an owner cleared by an explicit answer");
        }
        Console.WriteLine("PASS OWNER-BINDING-073 seven explicit answers replace or clear ownership immediately");
    }

    private static async Task VerifyOwnerSessionFences073()
    {
        foreach (var change in new[] { "generation", "session", "identity" })
        foreach (var failOld in new[] { false, true })
        {
            using var fixture = new OwnerFixture073();
            var host = fixture.Host;
            var pending = new TaskCompletionSource<AccountBridgeCompatibilityProjection>(TaskCreationOptions.RunContinuationsAsynchronously);
            fixture.Coordinator.Pending = pending;
            var oldRead = host.GetCompatibilityStateAsync(host.CurrentContext!, default);
            // Install only synthetic session changes; the outcome still crosses the production observer.
            var flags = System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic;
            if (change == "generation") typeof(ScmAccountBridgeHost).GetField("_generation", flags)!.SetValue(host, host.Generation + 1);
            else typeof(ScmAccountBridgeHost).GetField("_session", flags)!.SetValue(host, fixture.Session with {
                Subject = change == "identity" ? "synthetic-other-subject" : fixture.Session.Subject });
            fixture.Coordinator.Pending = null;
            fixture.Coordinator.Linked = false;
            await host.GetCompatibilityStateAsync(host.CurrentContext!, default);
            if (failOld) pending.SetException(new IOException());
            else pending.SetResult(Coordinator.LinkedProjection);
            var outcome = await CaptureRead073(oldRead);
            Check(outcome.Error is AccountBridgeHostException && fixture.Coordinator.Reads == 2 &&
                host.ResolveLocalDataOwner(host.CurrentContext!) == host.CurrentContext,
                "An old generation, session object or identity cannot overwrite a newer unlink observation");
            fixture.Clock.Advance(TimeSpan.FromMinutes(3));
            OwnerUnavailable073(host, "An old session's failure cannot extend the new session's confirmed owner");
        }
        Console.WriteLine("PASS OWNER-BINDING-073 late success and failure fenced by generation, session and identity");
    }

    private static void OwnerUnavailable073(ScmAccountBridgeHost host, string message)
    {
        try { host.ResolveLocalDataOwner(host.CurrentContext!); }
        catch (LocalPrivacyOwnerUnavailableException) { return; }
        throw new Exception(message);
    }

    private static async Task VerifyOwnerWriteBarrier073()
    {
        foreach (var writeOutcome in new[] { "success", "failure", "cancel" })
        {
            using var fixture = new OwnerFixture073();
            var host = fixture.Host;
            var owner = host.CurrentContext!;
            var before = new TaskCompletionSource<AccountBridgeCompatibilityProjection>(TaskCreationOptions.RunContinuationsAsynchronously);
            fixture.Coordinator.Pending = before;
            var oldRead = host.GetCompatibilityStateAsync(owner, default);
            var link = new TaskCompletionSource<AccountBridgeCompatibilityProjection>(TaskCreationOptions.RunContinuationsAsynchronously);
            fixture.Coordinator.AllowLink = true;
            fixture.Coordinator.LinkWait = link.Task;
            using var cancellation = new CancellationTokenSource();
            var write = host.LinkLegacyAccountAsync(owner, new("synthetic-name", "synthetic-password"), cancellation.Token);
            var during = new TaskCompletionSource<AccountBridgeCompatibilityProjection>(TaskCreationOptions.RunContinuationsAsynchronously);
            fixture.Coordinator.Pending = during;
            var duringRead = host.GetCompatibilityStateAsync(owner, default);
            fixture.Coordinator.Pending = null;
            if (writeOutcome == "cancel") cancellation.Cancel();
            if (writeOutcome == "failure") link.SetException(new HttpRequestException());
            else link.SetResult(Coordinator.LinkedProjection);
            var writeResult = await CaptureRead073(write);
            // Always release the fixture's physical reads before checking outcomes.
            var afterRead = host.GetCompatibilityStateAsync(owner, default);
            during.SetResult(Coordinator.LinkedProjection);
            before.SetResult(Coordinator.LinkedProjection);
            var outcomes = await Task.WhenAll(new[] { oldRead, duringRead, afterRead }.Select(CaptureRead073));
            Check(writeOutcome switch {
                "failure" => writeResult.Error is AccountBridgeHostException,
                "cancel" => writeResult.Error is OperationCanceledException,
                _ => writeResult.Error is null },
                "A successful binding write must not be invalidated by a read started during that write");
            Check(outcomes[0].Error is AccountBridgeHostException && outcomes[1].Error is AccountBridgeHostException &&
                outcomes[2].Error is null,
                "Reads after a completed or failed write must not reuse pre-write or during-write results");
            Check(host.ResolveLocalDataOwner(owner) == fixture.LegacyOwner, "Late pre-write results must not remove the current owner");
        }
        Console.WriteLine("PASS OWNER-BINDING-073 write barriers before, during and after mutation");
    }

    private static async Task VerifyOwnerSingleFlight073()
    {
        foreach (var fail in new[] { false, true })
        {
            using var fixture = new OwnerFixture073();
            var entries = new System.Collections.Concurrent.ConcurrentQueue<(string Stage, string Code)>();
            using var capture = StarBridge.HostRuntime.Support.IdentityGateJournal.Capture((stage, code) => entries.Enqueue((stage, code)));
            var pending = new TaskCompletionSource<AccountBridgeCompatibilityProjection>(TaskCreationOptions.RunContinuationsAsynchronously);
            fixture.Coordinator.Pending = pending;
            var calls = Enumerable.Range(0, 3).Select(_ => fixture.Host.GetCompatibilityStateAsync(fixture.Host.CurrentContext!, default)).ToArray();
            if (fail) pending.SetException(new HttpRequestException());
            else pending.SetResult(Coordinator.LinkedProjection);
            var outcomes = await Task.WhenAll(calls.Select(CaptureRead073));
            Check(fixture.Coordinator.Reads == 1, "Three concurrent callers must issue only one compatibility request");
            Check(!entries.Any(e => e.Stage == "owner-observe" && e.Code == "code=stale") &&
                entries.Count(e => e.Stage == "owner-compat") == (fail ? 1 : 0) &&
                fixture.Relay.Calls == (fail ? 0 : 1) && fixture.Relay.Resets == (fail ? 1 : 0),
                "Joined callers must not duplicate relay work, resets, failure logs or stale observations");
            if (fail)
                Check(outcomes.All(o => o.Error is AccountBridgeHostException error &&
                        error.Code == AccountBridgeStableErrors.CompatibilityReadUnavailable) &&
                    outcomes.All(o => ReferenceEquals(o.Error, outcomes[0].Error)),
                    "Concurrent callers must receive the same compatibility exception instance");
            else
                Check(outcomes.All(o => o.Error is null && ReferenceEquals(o.Result, outcomes[0].Result)),
                    "Concurrent callers must receive the same compatibility result instance");
            fixture.Coordinator.Pending = null;
            await fixture.Host.GetCompatibilityStateAsync(fixture.Host.CurrentContext!, default);
            Check(fixture.Coordinator.Reads == 2, "A completed flight must not cache the next read");
        }
        Console.WriteLine("PASS OWNER-BINDING-073 single-flight result and exception sharing");
    }

    private static async Task<(AccountBridgeCompatibilityProjection? Result, Exception? Error)> CaptureRead073(
        Task<AccountBridgeCompatibilityProjection> read)
    {
        try { return (await read, null); }
        catch (Exception error) { return (null, error); }
    }

    private static async Task VerifyOwnerFailureLifetime073()
    {
        using var fixture = new OwnerFixture073();
        var host = fixture.Host;
        var owner = host.CurrentContext!;
        await host.GetCompatibilityStateAsync(owner, default);
        fixture.Coordinator.Failure = true;
        for (var minute = 1; minute <= 30; minute++)
        {
            fixture.Clock.Advance(TimeSpan.FromMinutes(1));
            await ReadUnavailable073(host);
            if (minute < 30)
                Check(host.ResolveLocalDataOwner(owner) == fixture.LegacyOwner,
                    $"A confirmed owner must survive transport failures for minute {minute}");
        }
        try { host.ResolveLocalDataOwner(owner); throw new Exception("Owner survived the thirty-minute failure limit"); }
        catch (LocalPrivacyOwnerUnavailableException) { }
        fixture.Coordinator.Failure = false;
        await host.GetCompatibilityStateAsync(owner, default);
        Check(host.ResolveLocalDataOwner(owner) == fixture.LegacyOwner, "The first successful read must restore ownership immediately");
        fixture.Clock.Advance(TimeSpan.FromMinutes(3));
        try { host.ResolveLocalDataOwner(owner); throw new Exception("A binding without read attempts survived normal expiry"); }
        catch (LocalPrivacyOwnerUnavailableException) { }
        Console.WriteLine("PASS OWNER-BINDING-073 failure lifetime, recovery and ordinary expiry");
    }

    private static async Task<AccountBridgeHostException> ReadUnavailable073(ScmAccountBridgeHost host)
    {
        try { await host.GetCompatibilityStateAsync(host.CurrentContext!, default); }
        catch (AccountBridgeHostException error)
        {
            Check(error.Code == AccountBridgeStableErrors.CompatibilityReadUnavailable, "Compatibility failure keeps its stable code");
            return error;
        }
        throw new Exception("Expected compatibility read unavailable");
    }

    private sealed class OwnerFixture073 : IDisposable
    {
        private readonly string _root = Directory.CreateTempSubdirectory("sb-owner-binding-073-").FullName;
        private readonly LegacyPasswordLoginClient _legacy = new(new Uri("https://fixture-relay.invalid/"), new NoCredentials());
        internal readonly Coordinator Coordinator = new();
        internal readonly OwnershipClock Clock = new();
        internal readonly Relay Relay = new();
        internal readonly ScmOAuthSession Session = new("fixture-scm", "fixture-subject", "Fixture", "synthetic-token",
            DateTimeOffset.UtcNow.AddHours(1), []);
        internal ScmAccountBridgeHost Host { get; }
        internal BridgeAccountContext LegacyOwner => new("development", _legacy.AuthorityId, "synthetic-legacy");

        internal OwnerFixture073()
        {
            Host = new(new OAuthPkceClient(new ScmHttpClient(new OfflineScm()), new Vault(), ScmOAuthOptions.CreateDefault()),
                new ScmProfileCacheStore(_root), "development", () => null, initialSession: Session,
                compatibilityReader: new(Coordinator, Relay), legacyPasswordLogin: _legacy) { LocalDataOwnerClock = Clock };
        }

        public void Dispose()
        {
            Host.Dispose();
            _legacy.Dispose();
            Directory.Delete(_root, true);
        }
    }
}
