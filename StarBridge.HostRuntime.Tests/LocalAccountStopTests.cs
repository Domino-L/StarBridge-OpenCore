using System.Net;
using System.Security.Cryptography;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Onboarding;
using StarBridge.HostRuntime.Lifecycle;
using StarBridge.HostRuntime.Privacy;
using StarBridge.NativeBridge;

internal static class LocalAccountStopTests
{
    internal static async Task Run()
    {
        await Case("request retirement waits for exit, rejects new work and preserves cancellation", Admission);
        await Case("retirement races and throwing cancellation callbacks cannot reopen admission", AdmissionRaces);
        await Case("SCM realtime retirement waits for cancellation-ignoring ticket work", RealtimeDrain);
        await Case("actual account stop drains requests and discards late results", ForegroundDrain);
        await Case("actual sign-out does not acknowledge while a session loop remains alive", SessionDrain);
        await Case("cancelled stop remains sealed and can resume explicit retirement", CancelAndRetry);
        await Case("credential deletion failure retains original-owner stops and permits actual retry", FailedSignOutAndRetry);
        await Case("cancellation after our actual sign-out resumes loop drain without a second logout", CancelAfterSignOut);
        await Case("cancelled revocation cannot fabricate sign-out and can finish on explicit retry", CancelRevocationAndRetry);
        await Case("failed publication withdrawal cannot acknowledge local sign-out", PublicationPending);
        await Case("actual withdrawal retry precedes sign-out and preserves saved sharing settings", PublicationRetry);
        await Case("cancelled publication drain resumes its actual exit before clearing credentials", PublicationDrainRetry);
        await Case("a faulted physical publisher exit cannot acknowledge local mode on retry", PublicationDrainFailure);
        await Case("native account binding preserves shutdown withdrawal before lifecycle dispatch", NativeShutdownWithdrawal);
        await Case("account generation changing during drain cannot be signed out by an old transition", GenerationChangesDuringDrain);
        await Case("local sign-out rechecks generation after waiting for the actual account writer lane", GenerationChangesInWriterQueue);
        await Case("unknown session and stale generations cannot claim sign-out or inspect credentials", UnknownAndStale);
        await Case("a stopped account cannot resume session loops without a new runtime", NoSilentResume);
        await Case("actual account transition drains the installed observer without disabling local controls", BusinessComposition);
        await Case("background configuration admitted before retirement cannot escape its receipt", BackgroundConfiguration);
        await Case("installed sampling recovery exits before real sign-out and preserves its files", SamplingComposition);
    }
    private static async Task Case(string name, Func<Task> run)
    { await run(); Console.WriteLine("PASS first-use account stop: " + name); }

    private static async Task Admission()
    {
        var owner = new AsyncWorkRetirement();
        using var cancellation = new CancellationTokenSource();
        using var first = owner.Enter(cancellation.Token)!;
        using var second = owner.Enter(default)!;
        cancellation.Cancel();
        Require(first.Token.IsCancellationRequested && !first.IsCurrent && second.IsCurrent, "caller cancellation is local to one request");
        var drained = owner.Close();
        Require(owner.IsClosed && !drained.IsCompleted && !second.IsCurrent && second.Token.IsCancellationRequested &&
            owner.Enter(default) is null, "closed admission is not a completed drain");
        first.Dispose(); Require(!drained.IsCompleted, "second request has not exited");
        second.Dispose(); await drained.WaitAsync(TimeSpan.FromSeconds(3));
        Require(ReferenceEquals(drained, owner.Close()), "idempotent one-way receipt");
        try { owner.Enter(cancellation.Token); }
        catch (OperationCanceledException) { return; }
        throw new InvalidOperationException("cancelled entry must not be admitted");
    }

    private static async Task AdmissionRaces()
    {
        var owner = new AsyncWorkRetirement();
        var leases = Enumerable.Range(0, 48).Select(_ => owner.Enter(default)!).ToArray();
        using var failingCallback = leases[0].Token.Register(() => throw new InvalidOperationException("Synthetic callback failure"));
        var exits = leases.Select(lease => Task.Run(() => { lease.Dispose(); lease.Dispose(); })).ToArray();
        var drain = owner.Close();
        await Task.WhenAll(exits).WaitAsync(TimeSpan.FromSeconds(3));
        await drain.WaitAsync(TimeSpan.FromSeconds(3));
        Require(owner.IsClosed && owner.Enter(default) is null, "racing finishes cannot reopen admission");
        var other = new AsyncWorkRetirement();
        using var lease = other.Enter(default)!;
        using var callback = lease.Token.Register(() => throw new InvalidOperationException("Synthetic callback failure"));
        var pending = other.Close();
        Require(!pending.IsCompleted, "a callback failure is not a completed request");
        lease.Dispose(); await pending.WaitAsync(TimeSpan.FromSeconds(3));
    }

    private static async Task RealtimeDrain()
    {
        using var f = new Fixture();
        var tickets = new Queue<TaskCompletionSource<ScmWebSocketTicketResult>>();
        var one = Completion<ScmWebSocketTicketResult>(); var two = Completion<ScmWebSocketTicketResult>();
        tickets.Enqueue(one); tickets.Enqueue(two);
        var callbacks = 0;
        var client = new ScmRealtimeClient(f.OAuth, f.Options, "synthetic-device",
            (_, _) => callbacks++, (_, _) => callbacks++, (_, _) => callbacks++, (_, _, _, _) => callbacks++,
            issueTicket: _ => tickets.Dequeue().Task);
        client.Start(f.Session);
        client.Stop();
        Require(!client.StopCompletion.IsCompleted && !client.IsCurrentGeneration(1), "Stop cannot discard a still-running task");
        // A new generation must not hide the unfinished first generation.
        client.Start(f.Session with { Subject = "synthetic-second" });
        var disposing = client.DisposeAsync().AsTask();
        Require(!disposing.IsCompleted, "async disposal waits for both former generations");
        two.SetResult(new(new("synthetic-ticket", DateTimeOffset.UtcNow.AddMinutes(1)), f.Session));
        Require(!disposing.IsCompleted, "old generation still alive");
        one.SetResult(new(new("synthetic-ticket", DateTimeOffset.UtcNow.AddMinutes(1)), f.Session));
        await disposing.WaitAsync(TimeSpan.FromSeconds(3));
        Require(callbacks == 0, "late ticket cannot start a socket or publish authority");
    }

    private static async Task ForegroundDrain()
    {
        using var f = new Fixture();
        f.Transport.HoldProfile = true;
        var request = Request("profile.getSelf", f.Host);
        var read = f.Runtime.DispatchAsync(request).AsTask();
        await f.Transport.ProfileStarted.Task.WaitAsync(TimeSpan.FromSeconds(3));
        var stopping = f.Runtime.StopAccountForLocalModeAsync(f.Host.Generation);
        Require(!stopping.IsCompleted && f.Transport.ProfileToken.IsCancellationRequested && !f.Vault.Deleted,
            "foreground drain comes before logout");
        var denied = await f.Runtime.DispatchAsync(Request("account.login", f.Host));
        Require(denied.Response.Error?.Code == "account.local_mode" && f.Transport.ProfileReads == 1, "new login cannot queue behind retirement");
        f.Transport.ProfileRelease.TrySetResult();
        var late = await read.WaitAsync(TimeSpan.FromSeconds(3));
        Require(late.Response.Status == BridgeResponseStatuses.Cancelled && late.Events.Count == 0, "late result and its invalidations are revoked");
        var result = await stopping.WaitAsync(TimeSpan.FromSeconds(3));
        Require(result is { State: "sessionStopped", RequestsDrained: true, PublicationStopped: true, SessionLoopsStopped: true } &&
            f.Vault.Deleted && f.Host.CurrentContext is null, "actual account lifecycle facts");
        f.RequireLocalStateUnchanged();
    }

    private static async Task SessionDrain()
    {
        using var f = new Fixture();
        f.Transport.HoldTicket = true;
        await f.Host.GetCurrentAsync(default);
        await f.Transport.TicketStarted.Task.WaitAsync(TimeSpan.FromSeconds(3));
        var signedOut = Completion();
        f.Host.AccountChanged += _ => { if (f.Host.CurrentContext is null) signedOut.TrySetResult(); };
        var stop = f.Runtime.StopAccountForLocalModeAsync(f.Host.Generation);
        Require(!stop.IsCompleted && f.Transport.TicketToken.IsCancellationRequested && !f.Vault.Deleted && f.Host.CurrentContext is not null,
            "ticket admission holds the account mutation gate until actual exit; cancellation alone cannot sign out or acknowledge");
        f.Transport.TicketRelease.TrySetResult();
        await signedOut.Task.WaitAsync(TimeSpan.FromSeconds(3));
        var result = await stop.WaitAsync(TimeSpan.FromSeconds(3));
        Require(result is { State: "sessionStopped", SessionLoopsStopped: true }, "session loop exits before receipt");
        f.RequireLocalStateUnchanged();
    }

    private static async Task CancelAndRetry()
    {
        using var f = new Fixture();
        f.Transport.HoldProfile = true;
        var read = f.Runtime.DispatchAsync(Request("profile.getSelf", f.Host)).AsTask();
        await f.Transport.ProfileStarted.Task.WaitAsync(TimeSpan.FromSeconds(3));
        using var cancellation = new CancellationTokenSource();
        var stop = f.Runtime.StopAccountForLocalModeAsync(f.Host.Generation, cancellation.Token);
        cancellation.Cancel();
        await Cancelled(stop);
        Require(!f.Vault.Deleted && (await f.Runtime.DispatchAsync(Request("profile.getSelf", f.Host))).Response.Error?.Code == "account.local_mode",
            "cancelling the wait cannot silently restore online admission");
        f.Transport.ProfileRelease.TrySetResult(); await read.WaitAsync(TimeSpan.FromSeconds(3));
        Require((await f.Runtime.StopAccountForLocalModeAsync(f.Host.Generation)).State == "sessionStopped", "explicit retry drains and signs out");
    }

    private static async Task UnknownAndStale()
    {
        using var f = new Fixture(initialSession: false);
        Require((await f.Runtime.StopAccountForLocalModeAsync(f.Host.Generation)).State == "sessionUnchecked" &&
            f.Vault.Loads == 0 && !f.Vault.Deleted && f.Transport.AllRequests == 0,
            "a null session cannot trigger restore or prove credentials absent");
        using var signedIn = new Fixture();
        Require((await signedIn.Runtime.StopAccountForLocalModeAsync(-1)).State == "contextChanged" &&
            !signedIn.Vault.Deleted, "stale transition does not close or mutate the current account");
        var read = await signedIn.Runtime.DispatchAsync(Request("profile.getSelf", signedIn.Host));
        Require(read.Response.Error?.Code != "account.local_mode", "stale request did not retire admission");
        using var locked = AccountBridgeRuntime.CreateIsolatedSandboxShell();
        Require((await locked.StopAccountForLocalModeAsync(locked.Generation)).State == "unsupported", "an unsupported owner cannot forge a stop receipt");
    }

    private static async Task FailedSignOutAndRetry()
    {
        using var f = new Fixture();
        var owner = f.Host.CurrentContext;
        var generation = f.Host.Generation;
        f.Vault.FailDeletion = true;
        var first = await f.Runtime.StopAccountForLocalModeAsync(generation);
        Require(first is { State: "unavailable", RequestsDrained: true, PublicationStopped: true,
            BusinessBackgroundStopped: true, SessionLoopsStopped: false } && !f.Vault.Deleted &&
            f.Host.CurrentContext == owner && f.Host.Generation == generation && !f.Runtime.IsLocalAccountStopped(generation),
            "a failed credential delete retains actual prior exits, not a completed sign-out");
        Require((await f.Runtime.DispatchAsync(Request("account.login", f.Host))).Response.Error?.Code == "account.local_mode",
            "failure cannot reopen login admission");
        f.Vault.FailDeletion = false;
        var retry = await f.Runtime.StopAccountForLocalModeAsync(generation);
        Require(retry is { State: "sessionStopped", SessionLoopsStopped: true, BusinessBackgroundStopped: true } &&
            f.Vault.Deleted && f.Vault.Deletions == 1 && f.Runtime.IsLocalAccountStopped(retry.Generation),
            "same-owner retry performs the actual delete and final loop drain");
        f.RequireLocalStateUnchanged();
    }

    private static async Task CancelAfterSignOut()
    {
        using var f = new Fixture();
        using var cancellation = new CancellationTokenSource();
        f.Host.AccountChanged += _ => { if (f.Host.CurrentContext is null) cancellation.Cancel(); };
        var generation = f.Host.Generation;
        await Cancelled(f.Runtime.StopAccountForLocalModeAsync(generation, cancellation.Token));
        Require(f.Vault.Deletions == 1 && f.Host.CurrentContext is null && f.Host.Generation == generation + 1 &&
            !f.Runtime.IsLocalAccountStopped(f.Host.Generation), "own logout is not an acknowledged loop drain after cancellation");
        var traffic = f.Transport.AllRequests; var loads = f.Vault.Loads;
        var retry = await f.Runtime.StopAccountForLocalModeAsync(f.Host.Generation);
        Require(retry is { State: "sessionStopped", SessionLoopsStopped: true } && f.Vault.Deletions == 1 &&
            f.Transport.AllRequests == traffic && f.Vault.Loads == loads && f.Runtime.IsLocalAccountStopped(retry.Generation),
            "retry follows only our signed-out generation without restoring or deleting credentials again");
        f.RequireLocalStateUnchanged();
    }

    private static async Task CancelRevocationAndRetry()
    {
        using var f = new Fixture();
        using var cancellation = new CancellationTokenSource();
        var generation = f.Host.Generation; var owner = f.Host.CurrentContext;
        f.Transport.RevokeReply = () => { cancellation.Cancel(); throw new OperationCanceledException(cancellation.Token); };
        await Cancelled(f.Runtime.StopAccountForLocalModeAsync(generation, cancellation.Token));
        Require(f.Vault.Deleted && f.Host.CurrentContext == owner && f.Host.Generation == generation &&
            !f.Runtime.IsLocalAccountStopped(generation), "local credential deletion alone cannot acknowledge memory session or loop exit");
        f.Transport.RevokeReply = null;
        var traffic = f.Transport.AllRequests;
        var retry = await f.Runtime.StopAccountForLocalModeAsync(generation);
        Require(retry is { State: "sessionStopped", RequestsDrained: true, PublicationStopped: true,
            SessionLoopsStopped: true, BusinessBackgroundStopped: true } && f.Host.CurrentContext is null &&
            f.Transport.AllRequests == traffic, "actual owner finishes logout without restoring a deleted refresh credential");
        f.RequireLocalStateUnchanged();
    }

    private static async Task PublicationRetry()
    {
        using var f = new Fixture(publication: true);
        var owner = f.Host.CurrentContext!;
        var saved = f.Privacy!.Save(owner, 0, Guid.NewGuid().ToString("N"), LocalPrivacySettings.EditorDefaults, () => true);
        await f.Runtime.DispatchAsync(BridgeEnvelope.Request("privacy.applyPublication", Guid.NewGuid().ToString("N"),
            f.Host.Generation, new { schemaVersion = 1, expectedRevision = saved.Revision }, owner));
        var privacyDirectory = Path.Combine(f.Root, "privacy-local-v1");
        var files = Directory.GetFiles(privacyDirectory, "*", SearchOption.AllDirectories)
            .Where(path => !path.EndsWith(".lock", StringComparison.Ordinal)).ToArray();
        Require(files.Length > 0, "real saved sharing policy exists before retirement");
        var hashes = files.Select(path => SHA256.HashData(File.ReadAllBytes(path))).ToArray();
        Require((await f.Runtime.StopAccountForLocalModeAsync(f.Host.Generation)).State == "publicationPending" && !f.Vault.Deleted,
            "first unconfirmed withdrawal cannot sign out");
        f.Transport.HandleWithdrawal = true;
        f.Transport.WithdrawalBeforeReply = () => Require(!f.Vault.Deleted, "actual withdrawal must precede credential deletion");
        f.Host.ConfigurePrivacyWriter(new PrivacyRelayWriter(new Uri("https://relay.example.invalid/"), f.Transport));
        f.Vault.FailDeletion = true;
        var second = await f.Runtime.StopAccountForLocalModeAsync(f.Host.Generation);
        Require(second is { State: "unavailable", PublicationStopped: true, SessionLoopsStopped: false } &&
            f.Transport.Withdrawals == 1 && !f.Vault.Deleted, "actual validated withdrawal precedes the failing logout");
        f.Vault.FailDeletion = false;
        Require((await f.Runtime.StopAccountForLocalModeAsync(f.Host.Generation)).State == "sessionStopped" &&
            f.Transport.Withdrawals == 1 && f.Vault.Deletions == 1,
            "explicit retry retains confirmed withdrawal and finishes the same logout, not publication");
        Require(files.Select((path, index) => hashes[index].SequenceEqual(SHA256.HashData(File.ReadAllBytes(path)))).All(v => v),
            "withdrawal and retries do not change saved audiences or consent");
        f.RequireLocalStateUnchanged();
    }

    private static async Task NativeShutdownWithdrawal()
    {
        foreach (var wrapped in new[] { false, true })
        {
            using var f = new Fixture(publication: true);
            var owner = f.Host.CurrentContext!;
            var saved = f.Privacy!.Save(owner, 0, Guid.NewGuid().ToString("N"), LocalPrivacySettings.EditorDefaults, () => true);
            var applied = await f.Runtime.DispatchAsync(BridgeEnvelope.Request("privacy.applyPublication", Guid.NewGuid().ToString("N"),
                f.Host.Generation, new { schemaVersion = 1, expectedRevision = saved.Revision }, owner));
            var publisher = PrivacyPublicationTestAccess.Ordinary(f.Runtime);
            Require(applied.Response.Error is null && applied.Response.Payload.GetProperty("state").GetString() == "reconnecting" && publisher.ClearPending,
                "shutdown fixture must retain a real withdrawal obligation");
            f.Transport.HandleWithdrawal = true;
            f.Host.ConfigurePrivacyWriter(new PrivacyRelayWriter(new Uri("https://relay.example.invalid/"), f.Transport));
            using var binding = new NativeAccountRuntimeBinding(f.Runtime);
            var lifecycle = new ShutdownObserver(request =>
            {
                if (request.SessionGeneration == f.Host.Generation)
                    Require(f.Transport.Withdrawals == 1, "shutdown must await actual withdrawal before lifecycle dispatch, wrapped=" + wrapped);
            });
            using var dispatcher = new CompositeBridgeDispatcher(lifecycle,
                wrapped ? binding : f.Runtime, new ShutdownObserver(_ => throw new InvalidOperationException("Unexpected preference route")));
            await dispatcher.DispatchAsync(BridgeEnvelope.Request("host.shutdown", Guid.NewGuid().ToString("N"), f.Host.Generation + 1));
            Require(f.Transport.Withdrawals == 0, "stale shutdown cannot stop current publication");
            await dispatcher.DispatchAsync(BridgeEnvelope.Request("host.shutdown", Guid.NewGuid().ToString("N"), f.Host.Generation));
            Require(lifecycle.Calls == 2 && f.Transport.Withdrawals == 1 && !f.Vault.Deleted,
                "shutdown preserves lifecycle routing and is not account logout");
            f.RequireLocalStateUnchanged();
        }
    }

    private sealed class ShutdownObserver(Action<BridgeEnvelope> observe) : IBridgeRequestDispatcher
    {
        internal int Calls;
        public event Action<BridgeEnvelope>? EventReady { add { } remove { } }
        public ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken cancellationToken = default)
        {
            observe(request); Calls++;
            return ValueTask.FromResult(new BridgeDispatchBatch(BridgeEnvelope.Response(request, new { }), []));
        }
        public void Dispose() { }
    }

    private static async Task PublicationPending()
    {
        using var f = new Fixture(publication: true);
        var owner = f.Host.CurrentContext!;
        var saved = f.Privacy!.Save(owner, 0, Guid.NewGuid().ToString("N"), LocalPrivacySettings.EditorDefaults, () => true);
        // Real publication owner and dispatcher, with no Relay writer installed.
        // An uncertain send retains a clear obligation; it cannot prove withdrawal.
        var applied = await f.Runtime.DispatchAsync(BridgeEnvelope.Request("privacy.applyPublication", Guid.NewGuid().ToString("N"),
            f.Host.Generation, new { schemaVersion = 1, expectedRevision = saved.Revision }, owner));
        var publisher = PrivacyPublicationTestAccess.Ordinary(f.Runtime);
        // Automatic recovery is a presentation state, never a withdrawal receipt.
        Require(applied.Response.Error is null && applied.Response.Payload.GetProperty("state").GetString() == "reconnecting" && publisher.ClearPending,
            "actual publisher keeps an unconfirmed withdrawal obligation");
        var result = await f.Runtime.StopAccountForLocalModeAsync(f.Host.Generation);
        Require(publisher.ClearPending && publisher.Status.State == "withdrawalPending",
            "retirement retains the actual clear obligation and stops automatic recovery");
        Require(result is { State: "publicationPending", RequestsDrained: true, PublicationStopped: false, SessionLoopsStopped: false } &&
            !f.Vault.Deleted && f.Host.CurrentContext == owner, "failed clear cannot remove credentials or fabricate a stop receipt");
        Require((await f.Runtime.DispatchAsync(Request("account.getCurrent", f.Host))).Response.Error?.Code == "account.local_mode",
            "failed withdrawal cannot silently reopen online admission");
        Require((await f.Runtime.StopAccountForLocalModeAsync(f.Host.Generation)).State == "publicationPending" && !f.Vault.Deleted,
            "explicit retry still requires actual withdrawal confirmation");
        f.RequireLocalStateUnchanged();
    }
    private static async Task PublicationDrainRetry()
    {
        using var f = new Fixture(publication: true);
        const System.Reflection.BindingFlags flags = System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic;
        var publisher = PrivacyPublicationTestAccess.Ordinary(f.Runtime);
        var work = (AsyncWorkRetirement)typeof(PrivacyPublication).GetField("_work", flags)!.GetValue(publisher)!;
        using var held = work.Enter(default)!;
        var owner = f.Host.CurrentContext;
        var generation = f.Host.Generation;
        using var observer = new CancellationTokenSource();
        var stopping = f.Runtime.StopAccountForLocalModeAsync(generation, observer.Token);
        try
        {
            Require(!stopping.IsCompleted && work.IsClosed && held.Token.IsCancellationRequested &&
                !f.Vault.Deleted && f.Host.CurrentContext == owner,
                "Account stop cleared credentials before publication callback exit.");
            var exit = publisher.RetireAsync();
            observer.Cancel();
            try { await stopping.WaitAsync(TimeSpan.FromSeconds(3)); throw new InvalidOperationException("Expected observer cancellation."); }
            catch (OperationCanceledException) { }
            Require(!exit.IsCompleted && !f.Vault.Deleted && !f.Runtime.IsLocalAccountStopped(generation),
                "Cancelled observer fabricated publication exit or local readiness.");
            var retry = f.Runtime.StopAccountForLocalModeAsync(generation);
            Require(!retry.IsCompleted && ReferenceEquals(exit, publisher.RetireAsync()), "Retry did not await the same publisher exit.");
            held.Dispose();
            var completed = await retry.WaitAsync(TimeSpan.FromSeconds(3));
            Require(completed is { State: "sessionStopped", PublicationStopped: true } && f.Vault.Deletions == 1,
                "Retry tried withdrawing an already retired publisher or failed actual single logout.");
            f.RequireLocalStateUnchanged();
        }
        finally { held.Dispose(); }
    }
    private static async Task PublicationDrainFailure()
    {
        var clock = new PublicationRetirementTests.Clock { FailExit = true };
        using var f = new Fixture(publication: true, backgroundTime: clock);
        var owner = f.Host.CurrentContext;
        var generation = f.Host.Generation;
        var stopping = f.Runtime.StopAccountForLocalModeAsync(generation);
        try
        {
            Require(clock.Created.Count > 0, "Actual account publisher timers were not constructed.");
            foreach (var timer in clock.Created) await timer.ExitEntered.Task.WaitAsync(TimeSpan.FromSeconds(3));
            Require(!stopping.IsCompleted && !f.Vault.Deleted, "Physical publisher failure lost its actual drain.");
            foreach (var timer in clock.Created) timer.Release.TrySetResult();
            var failed = await stopping.WaitAsync(TimeSpan.FromSeconds(3));
            var retry = await f.Runtime.StopAccountForLocalModeAsync(generation).WaitAsync(TimeSpan.FromSeconds(3));
            Require(failed is { State: "unavailable", PublicationStopped: false } &&
                retry is { State: "unavailable", PublicationStopped: false } &&
                !f.Vault.Deleted && f.Host.CurrentContext == owner && !f.Runtime.IsLocalAccountStopped(generation) &&
                clock.Created.All(timer => timer.Disposals == 1),
                "Original faulted publisher exit became successful on retry or cleared credentials.");
            f.RequireLocalStateUnchanged();
        }
        finally { foreach (var timer in clock.Created) timer.Release.TrySetResult(); }
    }

    private static async Task GenerationChangesDuringDrain()
    {
        using var f = new Fixture();
        f.Transport.HoldProfile = true;
        var read = f.Runtime.DispatchAsync(Request("profile.getSelf", f.Host)).AsTask();
        await f.Transport.ProfileStarted.Task.WaitAsync(TimeSpan.FromSeconds(3));
        var generation = f.Host.Generation;
        var stopping = f.Runtime.StopAccountForLocalModeAsync(generation);
        // A separate, real account lifecycle event changes authority while the
        // cancellation-ignoring request is still draining. No session is forged.
        await f.Host.LogoutAsync(f.Host.CurrentContext!, default).WaitAsync(TimeSpan.FromSeconds(3));
        Require(f.Host.Generation != generation && !stopping.IsCompleted, "old transition still waits for foreground exit");
        f.Transport.ProfileRelease.TrySetResult();
        var late = await read.WaitAsync(TimeSpan.FromSeconds(3));
        var result = await stopping.WaitAsync(TimeSpan.FromSeconds(3));
        Require(late.Response.Status == BridgeResponseStatuses.Cancelled && late.Events.Count == 0 &&
            result is { State: "contextChanged", RequestsDrained: true, PublicationStopped: false, SessionLoopsStopped: false },
            "old generation cannot acknowledge or mutate the replacement lifecycle");
        var traffic = f.Transport.AllRequests; var loads = f.Vault.Loads;
        Require((await f.Runtime.StopAccountForLocalModeAsync(f.Host.Generation)).State == "contextChanged" &&
            !f.Runtime.IsLocalAccountStopped(f.Host.Generation) && f.Vault.Deletions == 1 &&
            f.Transport.AllRequests == traffic && f.Vault.Loads == loads,
            "retry cannot adopt an unrelated generation, even when its projection is signed out");
        f.RequireLocalStateUnchanged();
    }

    private static async Task GenerationChangesInWriterQueue()
    {
        using var f = new Fixture();
        f.Transport.HoldTicket = true;
        await f.Host.GetCurrentAsync(default);
        await f.Transport.TicketStarted.Task.WaitAsync(TimeSpan.FromSeconds(3));
        var generation = f.Host.Generation;
        var owner = f.Host.CurrentContext!;
        // Both calls wait behind the real ticket writer lane. The earlier normal
        // logout changes generation before the old local-mode operation enters.
        var earlierLogout = f.Host.LogoutAsync(owner, default);
        var staleLogout = f.Host.LogoutForLocalModeAsync(owner, generation, default);
        Require(!earlierLogout.IsCompleted && !staleLogout.IsCompleted && !f.Vault.Deleted,
            "generation guard is required after asynchronous writer admission");
        f.Transport.TicketRelease.TrySetResult();
        await earlierLogout.WaitAsync(TimeSpan.FromSeconds(3));
        Require(!await staleLogout.WaitAsync(TimeSpan.FromSeconds(3)) && f.Host.Generation != generation && f.Vault.Deletions == 1,
            "stale queued sign-out cannot delete credentials a second time");
        f.RequireLocalStateUnchanged();
    }

    private static async Task NoSilentResume()
    {
        using var f = new Fixture();
        var result = await f.Runtime.StopAccountForLocalModeAsync(f.Host.Generation);
        Require(result.State == "sessionStopped", "first explicit stop");
        var before = f.Transport.AllRequests;
        f.Host.EnableParticipantSynchronization(TimeSpan.FromMilliseconds(1));
        f.Host.EnableRoomMembershipKeepalive(TimeSpan.FromMilliseconds(1));
        await f.Host.GetCurrentAsync(default);
        Require(f.Transport.AllRequests == before && f.Host.CurrentContext is null && f.Host.ParticipantLoopCompletion.IsCompleted &&
            f.Host.RoomKeepaliveCompletion.IsCompleted, "stopped lifecycle cannot restart background enrollment");
        Require((await f.Runtime.DispatchAsync(Request("account.getCurrent", f.Host))).Response.Error?.Code == "account.local_mode",
            "switching online requires a new account runtime and explicit login");
        Require((await f.Runtime.StopAccountForLocalModeAsync(f.Host.Generation)).State == "sessionStopped", "idempotent explicit stop");
        f.RequireLocalStateUnchanged();
    }

    private static async Task BusinessComposition()
    {
        using var fixture = new Fixture();
        await BackgroundRetirementTests.AccountComposition(fixture.Runtime, fixture.Host, fixture.Root, () => fixture.Vault.Deleted);
        fixture.RequireLocalStateUnchanged();
    }

    private static async Task SamplingComposition()
    {
        using var fixture = new Fixture(sampling: true);
        fixture.Transport.HoldStatistics = true;
        try
        {
            // The production composition owns its existing recovery timer; no
            // test-only ready owner or direct private-field invocation is used.
            await fixture.Transport.StatisticsStarted.Task.WaitAsync(TimeSpan.FromSeconds(8));
            var files = Directory.GetFiles(fixture.Root, "*.json", SearchOption.AllDirectories)
                .Where(p => Path.GetDirectoryName(p)!.EndsWith("-local-v1", StringComparison.Ordinal)).ToArray();
            Require(files.Length == 2, "both real account sampling stores are installed");
            var hashes = files.Select(p => SHA256.HashData(File.ReadAllBytes(p))).ToArray();
            var stopping = fixture.Runtime.StopAccountForLocalModeAsync(fixture.Host.Generation);
            Require(!stopping.IsCompleted && !fixture.Vault.Deleted && fixture.Transport.StatisticsToken.IsCancellationRequested,
                "real sign-out waits for the installed recovery transport, not just foreground requests");
            fixture.Transport.StatisticsRelease.TrySetResult();
            var result = await stopping.WaitAsync(TimeSpan.FromSeconds(5));
            Require(result is { State: "sessionStopped", BusinessBackgroundStopped: true } && fixture.Vault.Deleted,
                "actual sampling exit precedes credential deletion");
            Require(files.Select((p, i) => hashes[i].SequenceEqual(SHA256.HashData(File.ReadAllBytes(p)))).All(v => v) &&
                fixture.Transport.StatisticsReads == 1, "saved statistics and stopped log choice remain unchanged without a second read");
            fixture.RequireLocalStateUnchanged();
        }
        finally { fixture.Transport.StatisticsRelease.TrySetResult(); }
    }

    private sealed class ConfiguringOverlaySink : StarBridge.HostRuntime.Overlay.IInformationOverlayLiveUpdateSink
    {
        internal readonly TaskCompletionSource Started = Completion(), Release = Completion();
        public bool IsVisible => false;
        public bool HasDisplayDemand
        {
            get { Started.TrySetResult(); Release.Task.Wait(TimeSpan.FromSeconds(5)); return false; }
        }
        public void RequestContentRefresh() { }
    }

    private static async Task BackgroundConfiguration()
    {
        using var fixture = new Fixture();
        var sink = new ConfiguringOverlaySink();
        var configuring = Task.Run(() => fixture.Runtime.ConfigureLiveOverlayUpdates(sink));
        try
        {
            await sink.Started.Task.WaitAsync(TimeSpan.FromSeconds(3));
            var stopping = fixture.Runtime.StopAccountForLocalModeAsync(fixture.Host.Generation);
            Require(!stopping.IsCompleted && !fixture.Vault.Deleted,
                "in-progress native driver configuration still owns the background admission");
            var rejected = false;
            try { fixture.Runtime.ConfigureLiveOverlayUpdates(sink); }
            catch (InvalidOperationException error) when (error.Message.Contains("retired", StringComparison.Ordinal)) { rejected = true; }
            Require(rejected, "retirement rejects a new native driver before the admitted configuration exits");
            sink.Release.TrySetResult();
            await configuring.WaitAsync(TimeSpan.FromSeconds(3));
            var stopped = await stopping.WaitAsync(TimeSpan.FromSeconds(3));
            Require(stopped is { State: "sessionStopped", BusinessBackgroundStopped: true } && fixture.Vault.Deleted,
                "driver assigned after retirement began must also exit before real sign-out");
            fixture.RequireLocalStateUnchanged();
        }
        finally { sink.Release.TrySetResult(); await configuring.WaitAsync(TimeSpan.FromSeconds(3)); }
    }

    private static BridgeEnvelope Request(string name, ScmAccountBridgeHost host) =>
        BridgeEnvelope.Request(name, Guid.NewGuid().ToString("N"), host.Generation, new { schemaVersion = 1 }, host.CurrentContext);
    private static TaskCompletionSource Completion() => new(TaskCreationOptions.RunContinuationsAsynchronously);
    private static TaskCompletionSource<T> Completion<T>() => new(TaskCreationOptions.RunContinuationsAsynchronously);
    private static void Require(bool condition, string label) { if (!condition) throw new InvalidOperationException(label); }
    private static async Task Cancelled(Task task)
    { try { await task; } catch (OperationCanceledException) { return; } throw new InvalidOperationException("Expected cancellation"); }

    internal sealed class Fixture : IDisposable
    {
        internal string Root { get; } = Path.Combine(Path.GetTempPath(), "starbridge-first-use-account-stop", Guid.NewGuid().ToString("N"));
        internal ScmOAuthOptions Options { get; }
        internal ScmOAuthSession Session { get; } = new("synthetic-scm", "synthetic-subject", "Synthetic Pilot", "synthetic-access",
            DateTimeOffset.UtcNow.AddHours(1), ["profile.read", "presence.write"]);
        internal Vault Vault { get; } = new();
        internal Transport Transport { get; } = new();
        internal OAuthPkceClient OAuth { get; }
        internal ScmAccountBridgeHost Host { get; }
        internal AccountBridgeRuntime Runtime { get; }
        internal LocalPrivacyStore? Privacy { get; }
        private readonly string _localState;
        private readonly byte[] _localHash;
        private readonly string _previousRoot;
        private readonly bool _preserveRoot;
        internal Fixture(bool initialSession = true, bool publication = false, bool sampling = false,
            string? sharedRoot = null, bool initializeLocalState = true, bool preserveRoot = false, long initialGeneration = 0,
            TimeProvider? backgroundTime = null, StarBridge.HostRuntime.Communities.CommunityClient? communities = null,
            Func<Uri, CancellationToken, Task<byte[]?>>? rsiAvatarDownload = null)
        {
            if (sharedRoot is not null) Root = Path.GetFullPath(sharedRoot);
            _preserveRoot = preserveRoot;
            CheckRoot();
            Directory.CreateDirectory(Root);
            _previousRoot = HostDataRoot.CurrentRoot;
            HostDataRoot.UsePreparedRoot(Root);
            var local = new LocalFirstUseStore(Root);
            if (initializeLocalState)
            {
                var value = local.SelectSource(0, Guid.NewGuid().ToString("N"), Path.Combine(Root, "install", "LIVE", "Game.log"), "LIVE", () => true);
                local.ConfirmIdentity(value.Revision, Guid.NewGuid().ToString("N"), new(value.SelectedSourceKey!, Guid.NewGuid().ToString("N"),
                    "Pilot-Example", DateTimeOffset.UtcNow, "history", true, false), () => true);
            }
            _localState = Path.Combine(Root, "local-first-use-v1", "state.bin");
            _localHash = File.Exists(_localState) ? SHA256.HashData(File.ReadAllBytes(_localState)) : [];
            var endpoint = new Uri("https://auth.example.invalid/");
            Options = new("synthetic-scm", endpoint, endpoint, endpoint, "synthetic-client", "synthetic-resource", "profile.read presence.write", "/callback");
            OAuth = new(new ScmHttpClient(Transport), Vault, Options, () => "synthetic-device");
            if (publication) Session = Session with { GameIdentityVerified = true, GameIdentityHandle = "Pilot-Example" };
            Host = new(OAuth, new ScmProfileCacheStore(Path.Combine(Root, "profile")), "synthetic-environment", () => null,
                initialSession: initialSession ? Session : null, initialGeneration: initialGeneration,
                legacyPasswordLogin: sampling ? new LegacyPasswordLoginClient(endpoint, new EmptyMigrationStore(), Transport) : null,
                communities: communities,
                // Fixtures never reach the real RSI site.
                rsiAvatarDownload: rsiAvatarDownload ?? ((_, _) => Task.FromResult<byte[]?>(null)));
            Privacy = publication ? new LocalPrivacyStore(Root) : null;
            var time = sampling ? new StarBridge.HostRuntime.Presence.GameplayTimeStore(Root) : null;
            var log = sampling ? new StarBridge.HostRuntime.Presence.GameLogSettingsStore(Root) : null;
            if (sampling)
            {
                using (var file = time!.Open(Host.CurrentContext!))
                {
                    var saved = file.Read();
                    file.Save(saved, saved with { Consent = StarBridge.HostRuntime.Presence.GameplayRecordingConsent.Declined,
                        Seconds = 37, ShowOnProfile = false }, () => true);
                }
                using (var file = log!.Open(Host.CurrentContext!))
                { var saved = file.Read(); file.Save(saved, saved with { Enabled = false }, () => true); }
            }
            Runtime = new(Host, privacy: Privacy, gameplayTime: time, gameLog: log, backgroundTime: backgroundTime);
        }
        internal void RequireLocalStateUnchanged() => Require(SHA256.HashData(File.ReadAllBytes(_localState)).SequenceEqual(_localHash),
            "logout cannot merge, delete or alter independent local profiles");
        public void Dispose()
        {
            Transport.ProfileRelease.TrySetResult(); Transport.TicketRelease.TrySetResult(); Transport.StatisticsRelease.TrySetResult();
            Runtime.Dispose();
            HostDataRoot.UsePreparedRoot(_previousRoot);
            if (_preserveRoot) return;
            CheckRoot();
            Directory.Delete(Root, recursive: true);
        }
        private void CheckRoot()
        {
            var full = Path.GetFullPath(Root);
            var parent = Path.GetFullPath(Path.Combine(Path.GetTempPath(), "starbridge-first-use-account-stop"));
            if (Path.GetDirectoryName(full) != parent || !Guid.TryParseExact(Path.GetFileName(full), "N", out _))
                throw new InvalidOperationException("Unsafe fixture target");
            for (var path = full; path is not null; path = Path.GetDirectoryName(path))
            {
                FileAttributes attributes;
                try { attributes = File.GetAttributes(path); }
                catch (FileNotFoundException) { continue; }
                catch (DirectoryNotFoundException) { continue; }
                if (attributes.HasFlag(FileAttributes.ReparsePoint)) throw new InvalidOperationException("Unsafe fixture target");
            }
        }
    }
    private sealed class EmptyMigrationStore : ILegacyMigrationCredentialStore
    {
        public LegacyMigrationCredential? Load() => null;
        public void Save(LegacyMigrationCredential credential) => throw new InvalidOperationException("No credential write is expected");
        public void Delete() { }
    }
    internal sealed class Vault : ITokenVault
    {
        internal int Loads;
        internal bool Deleted;
        internal int Deletions;
        internal bool FailDeletion;
        public string? LoadActiveAccountKey() { Loads++; return null; }
        public string? LoadRefreshToken(string key) { Loads++; return Deleted ? null : "synthetic-refresh"; }
        public void SaveRefreshToken(string key, string token) => throw new InvalidOperationException("Stop cannot save authorization");
        public void DeleteRefreshToken(string key)
        {
            if (FailDeletion) throw new IOException("Synthetic credential deletion failure");
            Deleted = true; Deletions++;
        }
    }
    internal sealed class Transport : HttpMessageHandler
    {
        internal bool HoldProfile, HoldTicket, HoldStatistics;
        internal StarBridge.Core.Profiles.PersonalProfileDocumentContract? SelfProfile;
        internal HttpStatusCode? SelfProfileStatus;
        internal int ProfileReads, AllRequests, StatisticsReads;
        internal Action? RevokeReply;
        internal bool HandleWithdrawal;
        internal int Withdrawals;
        internal Action? WithdrawalBeforeReply;
        internal CancellationToken ProfileToken, TicketToken, StatisticsToken;
        internal TaskCompletionSource ProfileStarted = Completion(), ProfileRelease = Completion(), TicketStarted = Completion(), TicketRelease = Completion();
        internal TaskCompletionSource StatisticsStarted = Completion(), StatisticsRelease = Completion();
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Interlocked.Increment(ref AllRequests);
            var path = request.RequestUri!.AbsolutePath;
            if (path == "/app-api/starbridge/v1/personal-profile" && SelfProfileStatus is { } status)
                return new(status) { Content = new StringContent("{}") };
            if (path == "/app-api/starbridge/v1/personal-profile" && SelfProfile is { } profile)
                return new(HttpStatusCode.OK) { Content = System.Net.Http.Json.JsonContent.Create(profile) };
            if (path == "/api/players/realtime" && HandleWithdrawal)
            {
                using var body = System.Text.Json.JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
                Require(!body.RootElement.GetProperty("online").GetBoolean(),
                    "this synthetic transport accepts only a withdrawal");
                WithdrawalBeforeReply?.Invoke();
                Interlocked.Increment(ref Withdrawals);
                var reply = new HttpResponseMessage(HttpStatusCode.OK) {
                    Content = System.Net.Http.Json.JsonContent.Create(body.RootElement.Clone())
                };
                reply.Headers.Add("X-StarBridge-Realtime-Version", "1");
                return reply;
            }
            if (path.EndsWith("/revoke", StringComparison.Ordinal))
            { RevokeReply?.Invoke(); return new(HttpStatusCode.OK); }
            if (path.EndsWith("/gameplay-time-reset", StringComparison.Ordinal))
            {
                Interlocked.Increment(ref StatisticsReads); StatisticsToken = token; StatisticsStarted.TrySetResult();
                if (HoldStatistics) await StatisticsRelease.Task;
            }
            else if (path.Contains("websocket", StringComparison.OrdinalIgnoreCase) || path.Contains("ws-ticket", StringComparison.OrdinalIgnoreCase))
            {
                TicketToken = token; TicketStarted.TrySetResult();
                if (HoldTicket) await TicketRelease.Task; // Deliberately ignore cancellation until fixture permits actual exit.
            }
            else if (path.EndsWith("/profile", StringComparison.Ordinal))
            {
                Interlocked.Increment(ref ProfileReads); ProfileToken = token; ProfileStarted.TrySetResult();
                if (HoldProfile) await ProfileRelease.Task;
            }
            return new(HttpStatusCode.ServiceUnavailable) { Content = new StringContent("{}") };
        }
    }
}

