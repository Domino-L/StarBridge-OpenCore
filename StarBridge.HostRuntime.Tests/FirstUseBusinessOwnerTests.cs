using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.LegacyRelay;
using StarBridge.HostRuntime.Onboarding;
using StarBridge.NativeBridge;

internal static partial class FirstUseBusinessOwnerTests
{
    private static string Id() => Guid.NewGuid().ToString("N");
    private static void Check(bool condition, string message)
    { if (!condition) throw new InvalidOperationException(message); }
    private static TaskCompletionSource Signal() => new(TaskCreationOptions.RunContinuationsAsynchronously);
    private static async Task<T> Finish<T>(Task<T> task) => await task.WaitAsync(TimeSpan.FromSeconds(5));
    private static async Task Finish(Task task) => await task.WaitAsync(TimeSpan.FromSeconds(5));
    internal static async Task Run()
    {
        await Case("full candidate graph borrows the device journal without starting or disposing it", DeferredJournalGraph);
        await Case("candidate cleanup awaits each original publisher's physical work before returning local", PublisherGraphExit);
        await Case("unconfirmed authentication cannot read business ownership", Unconfirmed);
        await Case("unlinked read keeps the same SCM owner with no timers or profile writes", Unlinked);
        await Case("an intentionally absent compatibility module retains its original SCM storage semantics", WithoutCompatibility);
        await Case("verified existing linkage selects only the original legacy storage owner", Linked);
        await Case("unknown linkage or nonready Relay cannot become SCM storage fallback", Unavailable);
        await Case("caller cancellation releases mode observation but cleanup waits for original read exit", CancelledRead);
        await Case("explicit mode cancellation can stop a pending read without abandoning its observer", DirectCancelRead);
        await Case("a changed credential version invalidates a held read without clearing the newer vault", ChangedCredential);
        await Case("a changed confirmed local source rejects the late business result", ChangedSource);
        await Case("confirmation expiry during original IO cannot create business preparation", ExpiredRead);
        await Case("replaced authoritative storage binding invalidates the old prepared object", ReplacedBinding);
        await Case("closed mode rejects late business ownership and drains before credential clear", ClosedMode);
        await Case("native cancellation can reenter ownership from another thread without holding the binding lock", NativeCancellationReentry);
        await Case("abandoning a native drain wait cannot reopen callbacks or duplicate preparation", NativeDrainWait);
        await Case("foreign preparation cannot close another native owner and cancellation invalidates receipts", NativePreparationOwnership);
        await Case("cancelled handoff rebuilds native callbacks only after original exit and local source recovery", NativeLocalRecovery);
        await Case("business admission consumes exact Native and local exit receipts without reopening auth", BusinessAdmissionReceipts);
        await Case("activated SCM ownership survives review expiry but not retirement or identity replacement", BusinessAdmissionLifetime);
        await Case("candidate cancellation drains installed business before clearing credentials", BusinessAdmissionExit);
        await Case("held original SCM ownership read prevents admission exit and discards stale completion", BusinessAdmissionReadExit);
        await Case("expired access token retains installed ownership and refreshes through the real resource path", BusinessAdmissionTokenRefresh);
        await Case("staged admission cannot activate after cancellation or borrow another Native preparation", BusinessAdmissionInvalidStage);
        await Case("a newer real vault version invalidates installed admission without clearing that credential", BusinessAdmissionChangedVault);
        await Case("original installation configures its Native graph while all business remains dormant", InstallationDormant);
        await Case("original Host installation activates six timers once without reopening authentication", InstallationActivation);
        await Case("installation cleanup awaits its original synchronous configuration and rejects late allocation", InstallationConfigurationExit);
        await Case("configuration authority cannot escape to a child task", InstallationConfigurationThread);
        await Case("independent installed business lane retains original slow IO through graph exit", InstallationRequestExit);
        await Case("failed Native configuration retires the original partially allocated graph", InstallationConfigurationFailure);
        await Case("activated original installation survives temporary review expiry", InstallationExpiredReview);
        await Case("candidate full sampler physically exits before original credential removal", InstallationSamplerExit);
        await Case("partial timer activation preserves its original exit fault and recovery state", InstallationActivationFailure);
        await Case("sealed installation cancels queued positive writes but withdraws its original scoped publication", InstallationPublicationExit);
        await Case("first-use achievement trigger refresh preserves admission on success", () => AchievementTriggerRefresh(false));
        await Case("first-use achievement trigger refresh preserves admission on failure", () => AchievementTriggerRefresh(true));
        await Case("achievement refresh rejects a same-owner vault replacement before capture", AchievementRefreshReplacedVault);
        await Case("new login cannot restore an old installed admission", NewLoginCannotRestoreAdmission);
        await RunAchievementConcurrencyRegression();
        await RunNativeInstallation();
        await RunCandidateShutdown();
        await RunOnlineCommit();
        await RunOffline();
        await RunRetainedOnline();
        await RunOnlineInstallationFlow();
        await RunNativeComposition();
        await RunOnlineInstallationBridge();
    }
    private static async Task Case(string name, Func<Task> work)
    { await work(); Console.WriteLine("PASS first-use business owner: " + name); }
    internal static async Task RunInstallation()
    {
        await Case("dormant configuration", InstallationDormant);
        await Case("unique graph activation", InstallationActivation);
        await Case("slow configuration exit", InstallationConfigurationExit);
        await Case("original configuration thread", InstallationConfigurationThread);
        await Case("actual request exit and auth rejection", InstallationRequestExit);
        await Case("partial configuration failure", InstallationConfigurationFailure);
        await Case("review expiry after activation", InstallationExpiredReview);
        await Case("actual sampler exit before credentials", InstallationSamplerExit);
        await Case("partial activation fault", InstallationActivationFailure);
        await Case("actual scoped publication exit", InstallationPublicationExit);
    }
    private sealed class Coordinator : IAccountCompatibilityCoordinator
    {
        internal AccountBridgeCompatibilityProjection Projection = new("unlinked", "notApplicable", false, false, [], null);
        internal bool Hold, Fail;
        internal int Reads, Writes;
        internal ScmOAuthSession? Session;
        internal CancellationToken Token;
        internal readonly TaskCompletionSource Entered = Signal(), Release = Signal();
        public async Task<AccountBridgeCompatibilityProjection> ReadAsync(ScmOAuthSession session, CancellationToken token)
        {
            Reads++; Session = session; Token = token; Entered.TrySetResult();
            if (Hold) await Release.Task; // Deliberately ignore cancellation until actual exit.
            if (Fail) throw new HttpRequestException("Synthetic unavailable ownership read.");
            return Projection;
        }
        public Task<AccountBridgeCompatibilityProjection> LinkExistingAsync(ScmOAuthSession session,
            LegacyIdentityLinkPasswordCredential? credential, CancellationToken token)
        { Writes++; throw new InvalidOperationException("Onboarding ownership read must never link."); }
        public Task<AccountBridgeCompatibilityProjection> CreateCompatibilityIdentityAsync(ScmOAuthSession session, CancellationToken token)
        { Writes++; throw new InvalidOperationException("Onboarding ownership read must never provision."); }
    }
    private sealed class Relay : ILegacyRelayAccountPort
    {
        internal LegacyRelayAccessState State = LegacyRelayAccessState.Ready;
        internal ScmOAuthSession? Session;
        internal string? ExpectedOwner;
        internal int Establishes, ProfileReads;
        public Task<LegacyRelayAccessState> EstablishAsync(ScmOAuthSession session, string expected, CancellationToken token)
        { token.ThrowIfCancellationRequested(); Establishes++; Session = session; ExpectedOwner = expected; return Task.FromResult(State); }
        public Task<LegacyRelayProfileReadResult> ReadOwnProfileAsync(ScmOAuthSession session, string expected, CancellationToken token)
        { ProfileReads++; throw new InvalidOperationException("Ownership preparation must not read or modify a personal profile."); }
        public void Reset() { }
    }
    private sealed class NoCredentials : ILegacyMigrationCredentialStore
    {
        internal int Operations;
        public LegacyMigrationCredential? Load() { Operations++; throw new InvalidOperationException("No legacy login restore."); }
        public void Save(LegacyMigrationCredential credential) { Operations++; throw new InvalidOperationException("No migration write."); }
        public void Delete() { Operations++; throw new InvalidOperationException("No legacy credential clear."); }
    }
    private sealed class Fixture : IDisposable
    {
        internal readonly Coordinator Coordinator = new();
        internal readonly Relay Relay = new();
        internal readonly NoCredentials Credentials = new();
        internal readonly FirstUseOnlineReturnTests.Fixture Original = new();
        internal Fixture()
        {
            Original.Compatibility = new(Coordinator, Relay);
            Original.Legacy = new(new Uri("https://synthetic-relay.example.invalid/"), Credentials);
        }
        internal async Task Start(bool confirm = true, TimeProvider? modeTime = null)
        {
            await Original.Prepare(modeTime); Original.Mode.RequestOnline(2, Id()); await Original.Stage();
            Check((await Finish(Original.Login())).Response.Status == BridgeResponseStatuses.Ok, "Actual PKCE login is required.");
            if (confirm)
            {
                var review = await Original.Mode.ReadOnlineIdentityAsync(3);
                Check((await Original.Mode.ConfirmOnlineIdentityAsync(3, review.ConfirmationKey!)).State == "confirmedForHandoff",
                    "Actual local source and authoritative SCM identity are explicitly confirmed.");
            }
        }
        internal Task<AccountBridgeRuntime.PreparedFirstUseBusinessOwner?> Prepare(CancellationToken token = default) =>
            Original.Mode.PrepareOnlineBusinessOwnerAsync(Original.Store.Read().Revision, token);
        internal void Quiet()
        {
            Check(Coordinator.Writes == 0 && Relay.ProfileReads == 0 && Credentials.Operations == 0 &&
                Original.Clock.Timers == 0 && Original.Host!.BusinessStartupDeferred && Original.Host.GameplayTimeContext is null &&
                Original.Mode.LocalMode().Active && Original.Store.Read().Phase == "onlinePending",
                "Read preserves local mode, original storage and deferred business without writes, restore, timers or publication.");
            Original.Local.RequireLocalStateUnchanged();
        }
        public void Dispose() { Coordinator.Release.TrySetResult(); Original.Dispose(); }
    }
    private static async Task Unconfirmed()
    {
        using var f = new Fixture(); await f.Start(confirm: false);
        Check(await f.Prepare() is null && f.Coordinator.Reads == 0, "Authentication alone cannot authorize the storage read.");
        f.Quiet();
    }
    private static async Task DeferredJournalGraph()
    {
        using var f = new Fixture();
        using var journal = new StarBridge.HostRuntime.Support.LocalGameEventJournal(
            Path.Combine(f.Original.Local.Root, "local-event-log.json"));
        journal.Load();
        f.Original.EventJournal = journal;
        await f.Start();
        var candidate = f.Original.Candidate!;
        object? Field(string name) => typeof(AccountBridgeRuntime).GetField(name,
            System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)!.GetValue(candidate);
        Check(ReferenceEquals(Field("_eventJournal"), journal), "Candidate must borrow the exact device journal.");
        foreach (var name in new[] { "_gameLog", "_gameplayTime", "_achievements", "_privacyPublication",
                     "_friendSharing", "_eventSharing", "_eventSharingBridge" })
            Check(Field(name) is not null, "Actual factory graph is missing " + name);
        Check(!candidate.TryConfigureAccountBusiness(_ => throw new InvalidOperationException("Candidate activated business.")),
            "Complete dormant graph is not installation authority.");
        Check(await f.Prepare() is { IsCurrent: true }, "Business owner preparation remains usable with the full dormant graph.");
        f.Quiet();
        Check((await Finish(f.Original.Cancel())).State == "local" && journal.IsWritable && f.Original.Clock.Timers == 0,
            "Candidate retirement must not close the borrowed device journal or ever start a timer.");
        f.Original.Local.Runtime.Dispose();
        using (var cold = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Original.Local.Root,
                   _ => throw new InvalidOperationException("Local restart must not construct an online account."),
                   eventJournal: journal))
        {
            Check(ReferenceEquals(typeof(AccountBridgeRuntime).GetField("_eventJournal",
                    System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)!.GetValue(cold), journal),
                "Device-only cold startup must retain the same borrowed journal for a later candidate.");
        }
        Check(journal.IsWritable, "Device-local runtime disposal does not own the device journal lifetime.");
    }
    private static async Task PublisherGraphExit()
    {
        foreach (var name in new[] { "_privacyPublication", "_officialPublication", "_friendSharing", "_eventSharing" })
        {
            using var f = new Fixture();
            using var journal = new StarBridge.HostRuntime.Support.LocalGameEventJournal(
                Path.Combine(f.Original.Local.Root, "local-event-log.json")); journal.Load();
            f.Original.EventJournal = journal;
            await f.Start();
            var candidate = f.Original.Candidate!;
            const System.Reflection.BindingFlags flags = System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic;
            var publisher = name == "_privacyPublication" ? (object)PrivacyPublicationTestAccess.Ordinary(candidate) : name == "_officialPublication" ? (object)PrivacyPublicationTestAccess.Official(candidate) : typeof(AccountBridgeRuntime).GetField(name, flags)!.GetValue(candidate)!;
            var work = (StarBridge.HostRuntime.Lifecycle.AsyncWorkRetirement)publisher.GetType().GetField("_work", flags)!.GetValue(publisher)!;
            using var lease = work.Enter(default)!;
            var exit = f.Original.Cancel();
            try
            {
                Check(!exit.IsCompleted && work.IsClosed && lease.Token.IsCancellationRequested,
                    "Candidate return acknowledged before " + name + " original work exited.");
                Check(work.Enter(default) is null && f.Original.Store.Read().Phase == "onlinePending",
                    "Candidate cleanup must close old publication admission without committing local early.");
                lease.Dispose();
                Check((await Finish(exit)).State == "local" && journal.IsWritable,
                    "Physical publisher cleanup did not return local or disposed the borrowed device journal.");
                Check(await Finish(candidate.RetireFirstUseOnlineCandidateAsync()), "Repeated candidate exit must retain successful original cleanup.");
                f.Original.Local.RequireLocalStateUnchanged();
            }
            finally { lease.Dispose(); }
        }
    }
    private static async Task Unlinked()
    {
        using var f = new Fixture(); await f.Start();
        var generation = f.Original.Candidate!.Generation; var requests = f.Original.Transport.Requests;
        var prepared = await f.Prepare(); var repeated = await f.Prepare();
        Check(prepared is { IsCurrent: true } && ReferenceEquals(prepared, repeated) &&
            ReferenceEquals(prepared.Owner, f.Original.Candidate) && prepared.StorageOwner == f.Original.Host!.CurrentContext &&
            f.Coordinator.Reads == 1 && f.Relay.Establishes == 0 && f.Original.Candidate.Generation == generation &&
            f.Original.Transport.Requests == requests,
            "Reuse the original fresh session, storage and read result; no relogin, generations or extra network.");
        var configured = 0;
        Check(!prepared!.Owner.TryConfigureAccountBusiness(_ => configured++) && configured == 0 &&
            !FirstUseOnlineReviewBridgeDispatcher.Handles("onboarding.onlineReview.businessOwner"),
            "Native storage facts do not authorize business installation or expose a new pipe command.");
        f.Quiet();
        Check((await Finish(f.Original.Cancel())).State == "local" && !prepared.IsCurrent, "Actual cancel invalidates the live owner.");
    }
    private static async Task Linked()
    {
        using var f = new Fixture();
        f.Coordinator.Projection = new("linked", "notEstablished", false, false, [], "synthetic-original-legacy");
        await f.Start(); var prepared = await f.Prepare();
        Check(prepared is { IsCurrent: true } && prepared.StorageOwner ==
            new BridgeAccountContext("synthetic", f.Original.Legacy!.AuthorityId, "synthetic-original-legacy") &&
            ReferenceEquals(f.Coordinator.Session, f.Relay.Session) && f.Relay.ExpectedOwner == "synthetic-original-legacy" &&
            f.Relay.Establishes == 1 && f.Original.Host!.ResolveLocalDataOwner(f.Original.Host.CurrentContext!) == prepared.StorageOwner,
            "Actual S2 ownership and ready bearer lease choose existing storage without a synthetic login or file merge.");
        f.Quiet();
    }
    private static async Task WithoutCompatibility()
    {
        using var original = new FirstUseOnlineReturnTests.Fixture(); await original.Prepare();
        original.Mode.RequestOnline(2, Id()); await original.Stage(); await Finish(original.Login());
        var review = await original.Mode.ReadOnlineIdentityAsync(3);
        await original.Mode.ConfirmOnlineIdentityAsync(3, review.ConfirmationKey!);
        var requests = original.Transport.Requests;
        var prepared = await original.Mode.PrepareOnlineBusinessOwnerAsync(3);
        Check(prepared is { IsCurrent: true } && prepared.StorageOwner == original.Host!.CurrentContext &&
            original.Transport.Requests == requests && original.Clock.Timers == 0 && original.Host.BusinessStartupDeferred,
            "An absent optional module is not a failed Java read and does not restore legacy authority or enable business.");
        original.Local.RequireLocalStateUnchanged();
    }
    private static async Task Unavailable()
    {
        foreach (var state in new[] { LegacyRelayAccessState.Unavailable, LegacyRelayAccessState.AuthorizationRequired,
            LegacyRelayAccessState.AccountMismatch, LegacyRelayAccessState.NotEstablished })
        {
            using var f = new Fixture(); f.Coordinator.Projection = new("linked", "notEstablished", false, false, [], "synthetic-legacy");
            f.Relay.State = state; await f.Start();
            Check(await f.Prepare() is null, "An unverified existing storage owner must not fall back to SCM-owned files."); f.Quiet();
        }
        foreach (var fail in new[] { false, true })
        {
            using var f = new Fixture(); f.Coordinator.Projection = new("unknown", "unknown", false, false, [], null);
            f.Coordinator.Fail = fail; await f.Start();
            Check(await f.Prepare() is null, "Unknown or unavailable ownership remains blocked."); f.Quiet();
        }
    }
    private static async Task CancelledRead()
    {
        using var f = new Fixture(); await f.Start(); f.Coordinator.Hold = true;
        using var caller = new CancellationTokenSource(); var read = f.Prepare(caller.Token);
        await Finish(f.Coordinator.Entered.Task); caller.Cancel();
        try { await Finish(read); throw new InvalidOperationException("Caller must cancel observation."); }
        catch (OperationCanceledException) { }
        var cancel = f.Original.Cancel();
        Check(!cancel.IsCompleted && f.Coordinator.Token.IsCancellationRequested && f.Original.Vault.LoadActiveAccountKey() is not null,
            "Original credential cleanup cannot acknowledge exit of an ignored-cancellation read.");
        f.Coordinator.Release.TrySetResult();
        Check((await Finish(cancel)).State == "local" && f.Original.Vault.LoadActiveAccountKey() is null &&
            f.Coordinator.Reads == 1 && f.Coordinator.Writes == 0,
            "Actual read exit permits the original credential clear and local return.");
    }
    private static async Task ChangedCredential()
    {
        using var f = new Fixture(); await f.Start(); f.Coordinator.Hold = true;
        var read = f.Prepare(); await Finish(f.Coordinator.Entered.Task);
        f.Original.Vault.SaveRefreshToken("synthetic-replacement:other", "synthetic-new-refresh");
        var bytes = File.ReadAllBytes(f.Original.VaultPath); f.Coordinator.Release.TrySetResult();
        Check(await Finish(read) is null && (await Finish(f.Original.Cancel())).State == "recoveryRequired" &&
            File.ReadAllBytes(f.Original.VaultPath).SequenceEqual(bytes), "Late facts cannot authorize or clear a newer vault version.");
        f.Quiet();
    }
    private static async Task DirectCancelRead()
    {
        using var f = new Fixture(); await f.Start(); f.Coordinator.Hold = true;
        var read = f.Prepare(); await Finish(f.Coordinator.Entered.Task);
        Check(await f.Prepare() is null && f.Coordinator.Reads == 1,
            "Repeated mode preparation cannot open a second physical read behind the held owner.");
        var cancel = f.Original.Cancel();
        Check(!cancel.IsCompleted && !read.IsCompleted && f.Coordinator.Token.IsCancellationRequested &&
            f.Original.Vault.LoadActiveAccountKey() is not null,
            "Mode cancellation closes original read admission without a busy-writer response or premature clear.");
        f.Coordinator.Release.TrySetResult();
        Check(await Finish(read) is null && (await Finish(cancel)).State == "local" &&
            f.Original.Vault.LoadActiveAccountKey() is null && f.Coordinator.Reads == 1,
            "The pending observer cannot preserve a prepared owner after the same physical read exits.");
    }
    private static async Task ChangedSource()
    {
        using var f = new Fixture(); await f.Start(); f.Coordinator.Hold = true;
        var read = f.Prepare(); await Finish(f.Coordinator.Entered.Task);
        var identities = new LocalFirstUseStore(f.Original.Local.Root); var saved = identities.Read();
        identities.InvalidateSourceIdentity(saved.Revision, Id(), saved.SelectedSourceKey!, () => true);
        f.Coordinator.Release.TrySetResult();
        Check(await Finish(read) is null && f.Original.Clock.Timers == 0 && f.Original.Store.Read().Phase == "onlinePending",
            "Changed local evidence invalidates the live business result without owner merge or activation.");
    }
    private static async Task ReplacedBinding()
    {
        using var f = new Fixture(); await f.Start(); var old = await f.Prepare();
        Check(old is { IsCurrent: true }, "Original facts are current.");
        f.Coordinator.Projection = new("unknown", "unknown", false, false, [], null);
        await f.Original.Host!.GetCompatibilityStateAsync(f.Original.Host.CurrentContext!, default);
        Check(!old!.IsCurrent && await f.Prepare() is null, "A newer unknown binding cannot preserve old authorization.");
        f.Quiet();
    }
    private sealed class ModeClock : TimeProvider
    {
        internal DateTimeOffset Now = DateTimeOffset.UtcNow.AddSeconds(1);
        public override DateTimeOffset GetUtcNow() => Now;
    }
    private static async Task ExpiredRead()
    {
        var clock = new ModeClock(); using var f = new Fixture(); await f.Start(modeTime: clock); f.Coordinator.Hold = true;
        var read = f.Prepare(); await Finish(f.Coordinator.Entered.Task); clock.Now = clock.Now.AddMinutes(10);
        f.Coordinator.Release.TrySetResult();
        Check(await Finish(read) is null && f.Original.Clock.Timers == 0 &&
            f.Original.Mode.CurrentOnlineIdentity(3).State == "operationInProgress",
            "The original completed read cannot extend an expired confirmation or activate business.");
        Check((await Finish(f.Original.Cancel())).State == "local", "Expired preparation retains real cleanup.");
    }
    private static async Task ClosedMode()
    {
        using var f = new Fixture(); await f.Start(); f.Coordinator.Hold = true;
        var read = f.Prepare(); await Finish(f.Coordinator.Entered.Task); f.Original.Mode.Close();
        var retired = f.Original.Candidate!.RetireFirstUseOnlineCandidateAsync();
        Check(!retired.IsCompleted && f.Original.Vault.LoadActiveAccountKey() is not null,
            "Mode closure cannot abandon original business IO or prematurely clear credentials.");
        f.Coordinator.Release.TrySetResult();
        Check(await Finish(read) is null && await Finish(retired) && f.Original.Vault.LoadActiveAccountKey() is null,
            "No late prepared facts survive actual mode exit.");
    }

    private static async Task NativeCancellationReentry()
    {
        using var f = new Fixture(); await f.Start(); var prepared = await f.Prepare();
        var binding = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var release = Signal();
        using var ready = new ManualResetEventSlim();
        using var inspect = new ManualResetEventSlim();
        using var inspected = new ManualResetEventSlim();
        var readResult = true;
        var callbackCouldInspect = false;
        var worker = new Thread(() =>
        {
            ready.Set();
            if (!inspect.Wait(TimeSpan.FromSeconds(5))) return;
            readResult = binding.Read(_ => true, false);
            inspected.Set();
        }) { IsBackground = true };
        worker.Start();
        Check(ready.Wait(TimeSpan.FromSeconds(3)), "The independent callback consumer is ready before cancellation.");
        var read = binding.ReadAsync(async (_, token) =>
        {
            using var registration = token.Register(() =>
            {
                inspect.Set();
                callbackCouldInspect = inspected.Wait(TimeSpan.FromSeconds(3));
            });
            await release.Task; // Cancellation must not be mistaken for actual exit.
            return true;
        });
        try
        {
            var handoff = binding.PrepareHandoffAsync(prepared!);
            Check(callbackCouldInspect && !readResult,
                "Native cancellation must permit cross-thread ownership inspection; holding the binding lock causes a cancellation deadlock.");
            Check(!handoff.IsCompleted, "A responsive cancellation callback is still not the physical read exit.");
            release.TrySetResult();
            try { await Finish(read); throw new InvalidOperationException("Retired callback must not return old data."); }
            catch (OperationCanceledException) { }
            Check(await Finish(handoff) is { IsCurrent: true }, "Only actual callback exit permits the native drain receipt.");
            f.Quiet();
        }
        finally
        {
            release.TrySetResult(); inspect.Set();
            worker.Join(TimeSpan.FromSeconds(5));
            try { await Finish(read); } catch (OperationCanceledException) { }
            await binding.DisposeAsync();
        }
    }

    private static async Task NativeDrainWait()
    {
        using var f = new Fixture(); await f.Start(); var prepared = await f.Prepare();
        var binding = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var release = Signal();
        using var observer = new CancellationTokenSource();
        var cancellationSeen = false;
        var read = binding.ReadAsync(async (_, token) =>
        {
            using var registration = token.Register(() =>
            {
                cancellationSeen = true;
                throw new InvalidOperationException("Synthetic native cancellation failure.");
            });
            await release.Task;
            return true;
        });
        try
        {
            var abandoned = binding.PrepareHandoffAsync(prepared!, observer.Token);
            Check(cancellationSeen && !abandoned.IsCompleted, "Cancellation callback failure cannot acknowledge physical exit.");
            observer.Cancel();
            try { await Finish(abandoned); throw new InvalidOperationException("Only the observer must cancel."); }
            catch (OperationCanceledException) { }
            var repeated = binding.PrepareHandoffAsync(prepared!);
            var repeatedAgain = binding.PrepareHandoffAsync(prepared!);
            Check(!repeated.IsCompleted && ReferenceEquals(repeated, repeatedAgain) &&
                !binding.Read(_ => true, false), "There is one drain and no reopened callback admission after wait abandonment.");
            var reply = await binding.DispatchAsync(BridgeEnvelope.Request("account.read", Id(), f.Original.Local.Runtime.Generation,
                new { schemaVersion = 1 }));
            Check(reply.Response.Status != BridgeResponseStatuses.Ok, "The stopped native pipe cannot bypass callback retirement.");
            release.TrySetResult();
            try { await Finish(read); throw new InvalidOperationException("No stale callback result is allowed."); }
            catch (OperationCanceledException) { }
            var receipt = await Finish(repeated);
            Check(receipt is { IsCurrent: true } && ReferenceEquals(receipt, await Finish(repeatedAgain)),
                "Repeated observers receive the same receipt only after actual exit.");
            f.Quiet();
            Check((await Finish(f.Original.Cancel())).State == "local" && !receipt!.IsCurrent,
                "Explicit mode cancellation invalidates a previously completed native receipt.");
        }
        finally
        {
            release.TrySetResult();
            try { await Finish(read); } catch (OperationCanceledException) { }
            await binding.DisposeAsync();
        }
    }

    private static async Task NativeLocalRecovery()
    {
        using var f = new Fixture(); await f.Start(); var prepared = await f.Prepare();
        await using var binding = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var localGeneration = f.Original.Mode.LocalMode().Generation;
        var release = Signal();
        var read = binding.ReadAsync(async (_, _) => { await release.Task; return true; });
        try
        {
            var pending = binding.PrepareHandoffAsync(prepared!);
            Check(!pending.IsCompleted && !await binding.RestoreLocalCallbacksAsync(prepared!, localGeneration),
                "pending online intent cannot reopen Native callbacks");
            Check((await f.Original.Cancel()).State == "local", "explicit cancellation restores durable local intent");
            using var cancelled = new CancellationTokenSource();
            var abandonedWait = binding.RestoreLocalCallbacksAsync(prepared!, localGeneration, cancelled.Token);
            Check(!abandonedWait.IsCompleted, "local callback recovery must wait for original callback exit");
            cancelled.Cancel();
            try { await Finish(abandonedWait); throw new InvalidOperationException("Cancelled observer must exit"); }
            catch (OperationCanceledException) { }
            Check(!binding.Read(_ => true, false), "observer cancellation cannot revive a closed Native lane");
            release.TrySetResult();
            try { await Finish(read); throw new InvalidOperationException("No old callback result may return"); }
            catch (OperationCanceledException) { }
            Check(await Finish(pending) is null, "cancelled facts cannot become an online installation receipt");
            var exit = f.Original.Local.Runtime.RetireFirstUseLocalSourcesAsync(); await Finish(exit);
            Check(!await binding.RestoreLocalCallbacksAsync(prepared!, localGeneration),
                "retired device sources cannot authorize a ready Native lane");
            Check(await f.Original.Local.Runtime.RestoreFirstUseLocalSourcesAsync(exit, localGeneration),
                "actual local reconstruction precedes callback restoration");
            var bytes = File.ReadAllBytes(Path.Combine(f.Original.Local.Root, "first-use-mode-v1", "state.bin"));
            Check(!await binding.RestoreLocalCallbacksAsync(prepared!, localGeneration + 1) &&
                await binding.RestoreLocalCallbacksAsync(prepared!, localGeneration) &&
                binding.Read(owner => ReferenceEquals(owner, f.Original.Local.Runtime), false),
                "only matching local epoch reconstructs one callback lane on the retained root");
            Check(!await binding.RestoreLocalCallbacksAsync(prepared!, localGeneration) &&
                bytes.SequenceEqual(File.ReadAllBytes(Path.Combine(f.Original.Local.Root, "first-use-mode-v1", "state.bin"))) &&
                f.Original.Vault.LoadActiveAccountKey() is null,
                "recovery consumes old preparation, preserves mode and never restores account credentials");
            var response = await binding.DispatchAsync(BridgeEnvelope.Request("account.login", Id(), binding.Generation,
                new { schemaVersion = 1 }));
            Check(response.Response.Error?.Code == "account.local_mode", "restored Native callbacks cannot reopen retired account login");
            f.Original.Local.RequireLocalStateUnchanged();
        }
        finally
        {
            release.TrySetResult();
            try { await Finish(read); } catch (OperationCanceledException) { }
        }
    }

    private static async Task NativePreparationOwnership()
    {
        using var first = new Fixture(); using var other = new Fixture();
        await first.Start(); await other.Start();
        var firstPrepared = await first.Prepare(); var otherPrepared = await other.Prepare();
        await using var binding = new NativeAccountRuntimeBinding(first.Original.Local.Runtime);
        Check(await binding.PrepareHandoffAsync(otherPrepared!) is null && binding.Read(_ => true, false),
            "Even valid preparation from another actual mode cannot retire this owner.");
        using var cancelled = new CancellationTokenSource(); cancelled.Cancel();
        try { await binding.PrepareHandoffAsync(firstPrepared!, cancelled.Token); throw new InvalidOperationException("Precancelled observer must not enter."); }
        catch (OperationCanceledException) { }
        Check(binding.Read(_ => true, false), "Precancelled preparation has no admission side effects.");
        var receipt = await binding.PrepareHandoffAsync(firstPrepared!);
        Check(receipt is { IsCurrent: true } && !binding.Read(_ => true, false), "The matching mode alone can drain this binding.");
        first.Quiet(); other.Quiet();
        var review = first.Original.Local.Runtime.FirstUseOnlineReviewDispatcher!;
        var cancel = await review.DispatchAsync(BridgeEnvelope.Request(
            StarBridge.HostRuntime.Onboarding.FirstUseOnlineReviewBridgeDispatcher.CancelRequest, Id(),
            first.Original.Local.Runtime.Generation,
            new { schemaVersion = 1, revision = first.Original.Mode.Current.Revision }));
        Check(cancel.Response.Status == BridgeResponseStatuses.Ok && first.Original.Mode.Current.State == "local" &&
            !receipt!.IsCurrent && otherPrepared!.IsCurrent,
            "The real review bridge remains cancellable after Native drain, invalidates only its preparation, and preserves another mode.");
    }
}


