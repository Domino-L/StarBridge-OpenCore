using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Onboarding;
using StarBridge.NativeBridge;

internal static partial class FirstUseModeTests
{
    internal static async Task RunRootOffline()
    {
        await Case("offline retains only a display snapshot across cold startup", OfflineAccountDisplay);
        await Case("offline cache is account isolated and cannot pin stale or corrupted records", OfflineAccountIsolation);
        await Case("ordinary online root retains authorization and reconstructs local and Native owners", RootOffline);
        await Case("ordinary offline waits for a held Native callback despite observer cancellation", () => RootOfflineHeld(false));
        await Case("ordinary offline Close waits for the original held callback without sign-out", () => RootOfflineHeld(true));
        await Case("ordinary offline drains cancellation-ignoring actual account reads", RootOfflineAccountRead);
        await Case("ordinary offline waits for actual SCM session loop exit", RootOfflineLoop);
        await Case("ordinary intent writer failure leaves the online root intact and retryable", RootOfflineIntentFailure);
        await Case("ordinary final writer failure preserves pending intent and authorization", RootOfflineFinalFailure);
        await Case("ordinary offline cannot adopt a changed account generation", RootOfflineGeneration);
        await Case("ordinary Close before intent still waits for the original physical session loop", RootOfflineQueuedClose);
        await Case("ordinary offline requires exact root Native provenance before any write", RootOfflineGuards);
        await RunModeBridge();
    }

    private static async Task OfflineAccountDisplay()
    {
        using var f = new LocalAccountStopTests.Fixture(sampling: true);
        var mode = await RootMode(f);
        var owner = f.Host.CurrentContext!;
        var profiles = new StarBridge.HostRuntime.Profiles.LocalPersonalProfileStore(f.Root);
        profiles.Save(owner, 0, Op(), new("Synthetic Pilot", "Retained introduction", 0, "none", [], []), () => true);
        var hangar = new StarBridge.HostRuntime.Hangar.LocalHangarStore(f.Root);
        hangar.Save(owner, 0, "synthetic-offline-inventory",
            Enumerable.Range(0, 201).Select(i => new StarBridge.Core.Hangar.CollectedHangarShip(
                "synthetic-pledge-" + i, 0, "Synthetic Ship", null, null)).ToArray(), false, false);
        hangar.Save(new(owner.Environment, owner.Authority, "synthetic-other"), 0, "synthetic-other-inventory",
            [new("other", 0, "Other account ship", null, null)], false, false);
        await using var native = new NativeAccountRuntimeBinding(f.Runtime);
        var online = await native.DispatchAsync(BridgeEnvelope.Request("account.getCurrent", Op(), f.Host.Generation,
            new { schemaVersion = 1 }));
        Require(online.Response.Status == "ok", "Real online account read must succeed before caching");
        new StarBridge.HostRuntime.Account.OfflineAccountStore(f.Root).ObserveAchievements(owner,
            new(1, new() { ["first-entry"] = DateTimeOffset.UtcNow.AddDays(-1) }), () => true);
        f.Transport.SelfProfile = new(3, "synthetic-public-profile", true, 3, DateTimeOffset.UtcNow,
            new("Server Pilot", "MustNotBeLive", "https://synthetic.invalid/avatar"),
            StarBridge.Core.Profiles.PersonalProfileContentContract.Empty with {
                Introduction = "Server confirmed introduction", PresenceIntent = "busy" },
            new("MustNotBeLive", "synthetic", null, "synthetic", "blue"));
        Require((await native.DispatchAsync(BridgeEnvelope.Request("personalProfile.getSelf", Op(), f.Host.Generation,
            new { schemaVersion = 1 }, owner))).Response.Status == "ok", "Read the actual authenticated own-profile route before retaining display");
        Require((await mode.ApplyRootOfflineAsync(0, Op(), f.Host.Generation, native)).State == "offline", "Offline transition");
        var traffic = f.Transport.AllRequests;
        async Task Check(NativeAccountRuntimeBinding binding, FirstUseModeRuntime current)
        {
            using var reader = binding.CreateModeDispatcher()!;
            var result = await reader.DispatchAsync(BridgeEnvelope.Request(FirstUseModeBridgeDispatcher.ReadRequest,
                Op(), current.ControlGeneration, new { schemaVersion = 1 }));
            Require(result.Response.Payload.TryGetProperty("offlineAccount", out var display) &&
                display.ValueKind == System.Text.Json.JsonValueKind.Object &&
                display.GetProperty("displayName").GetString() == "Synthetic Pilot",
                "Offline must retain the last confirmed account name, not become anonymous");
            Require(result.Response.AccountContext is null && !display.TryGetProperty("subject", out _) &&
                !display.TryGetProperty("accessToken", out _), "Display snapshot grants no account context or credentials");
            var achievements = await reader.DispatchAsync(BridgeEnvelope.Request(FirstUseModeBridgeDispatcher.AchievementsRequest,
                Op(), current.ControlGeneration, new { schemaVersion = 1, revision = current.Current.Revision }));
            Require(achievements.Response.Status == "ok" && achievements.Response.AccountContext is null &&
                achievements.Response.Payload.GetProperty("collection").GetProperty("earnedAt").GetProperty("first-entry").GetDateTimeOffset() < DateTimeOffset.UtcNow &&
                achievements.Response.Payload.GetProperty("cachedAtUtc").GetDateTimeOffset() > DateTimeOffset.UnixEpoch,
                "Cold and warm offline reads retain only confirmed collection and freshness, without a new grant");
            foreach (var invalid in new object[] { new { schemaVersion = 1, revision = current.Current.Revision + 1 },
                new { schemaVersion = 1, revision = current.Current.Revision, subject = "other" } })
                Require((await reader.DispatchAsync(BridgeEnvelope.Request(FirstUseModeBridgeDispatcher.AchievementsRequest,
                    Op(), current.ControlGeneration, invalid))).Response.Status != "ok", "Cache route rejects stale revision and owner injection");
            var inventory = await reader.DispatchAsync(BridgeEnvelope.Request(FirstUseModeBridgeDispatcher.HangarRequest,
                Op(), current.ControlGeneration, new { schemaVersion = 1, revision = current.Current.Revision }));
            var retainedProfile = await reader.DispatchAsync(BridgeEnvelope.Request(FirstUseModeBridgeDispatcher.ProfileRequest,
                Op(), current.ControlGeneration, new { schemaVersion = 1, revision = current.Current.Revision }));
            var cached = retainedProfile.Response.Payload.GetProperty("remote").GetProperty("payload");
            var projected = cached.GetProperty("profile");
            Require(!cached.GetProperty("editable").GetBoolean() && projected.GetProperty("identity").GetProperty("gameHandle").GetString() == "" &&
                projected.GetProperty("identity").GetProperty("avatarAssetId").ValueKind == System.Text.Json.JsonValueKind.Null &&
                !projected.TryGetProperty("fleetAffiliation", out _) &&
                projected.GetProperty("content").GetProperty("presenceIntent").ValueKind == System.Text.Json.JsonValueKind.Null &&
                projected.GetProperty("content").GetProperty("introduction").GetString() == "Server confirmed introduction",
                "Cold and warm cached self profile retains authored content, not remote image URLs or live permissions");
            Require(inventory.Response.Status == "ok" && inventory.Response.AccountContext is null &&
                inventory.Response.Payload.GetProperty("total").GetInt32() == 201 &&
                inventory.Response.Payload.GetProperty("ships").GetArrayLength() == 200,
                "Offline read uses the original owned file, preserving duplicate instances and pagination");
            var page = await reader.DispatchAsync(BridgeEnvelope.Request(FirstUseModeBridgeDispatcher.HangarRequest,
                Op(), current.ControlGeneration, new { schemaVersion = 1, revision = current.Current.Revision,
                    inventoryRevision = 1, offset = 200 }));
            Require(page.Response.Payload.GetProperty("ships").GetArrayLength() == 1, "Last offline inventory page");
            var injected = await reader.DispatchAsync(BridgeEnvelope.Request(FirstUseModeBridgeDispatcher.HangarRequest,
                Op(), current.ControlGeneration, new { schemaVersion = 1, revision = current.Current.Revision, subject = "synthetic-other" }));
            Require(injected.Response.Status != "ok", "Caller cannot select another account's file");
            var profile = await reader.DispatchAsync(BridgeEnvelope.Request("onboarding.mode.profile",
                Op(), current.ControlGeneration, new { schemaVersion = 1, revision = current.Current.Revision }));
            Require(profile.Response.Status == "ok" && profile.Response.AccountContext is null &&
                profile.Response.Payload.GetProperty("content").GetProperty("introduction").GetString() == "Retained introduction",
                "Offline profile must read original owned presentation without login or writes");
            foreach (var invalid in new object[] {
                new { schemaVersion = 1, revision = current.Current.Revision + 1 },
                new { schemaVersion = 1, revision = current.Current.Revision, subject = "synthetic-other" },
                new { schemaVersion = 1, revision = current.Current.Revision, content = "replacement" }
            }) {
                var rejected = await reader.DispatchAsync(BridgeEnvelope.Request("onboarding.mode.profile",
                    Op(), current.ControlGeneration, invalid));
                Require(rejected.Response.Status != "ok", "Offline profile cannot select another owner or write content");
            }
        }
        await Check(native, mode);
        using var cold = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, NoOnline);
        await using var coldNative = new NativeAccountRuntimeBinding(cold);
        await Check(coldNative, cold.FirstUseMode!);
        Require(mode.RequestResume(2, Op()).State == "signInRequired", "Begin explicit resume");
        Require((await mode.CancelOnlineAsync(3, Op())).State == "offline", "Cancelled resume retains offline data");
        await Check(native, mode);
        Require(f.Transport.AllRequests == traffic && f.Vault.Loads == 0 && f.Vault.Deletions == 0,
            "Cold display must not restore credentials or contact the network");
        Require(hangar.Read(owner).Revision == 1 && hangar.Read(owner).Ships.Count == 201, "Offline reads never rewrite inventory");
        Require(profiles.Read(owner).Revision == 1, "Offline profile reads never rewrite the original presentation");
    }

    private static Task OfflineAccountIsolation()
    {
        using var f = new LocalAccountStopTests.Fixture(sampling: true);
        var store = new StarBridge.HostRuntime.Account.OfflineAccountStore(f.Root);
        var a = f.Host.CurrentContext!;
        var b = new BridgeAccountContext(a.Environment, a.Authority, "synthetic-other");
        store.Observe(a, "A", () => true);
        var earned = new StarBridge.HostRuntime.Achievements.AchievementSnapshot(1,
            new() { ["first-entry"] = DateTimeOffset.UtcNow.AddDays(-1) });
        store.ObserveAchievements(a, earned, () => true);
        var self = System.Text.Json.JsonSerializer.SerializeToElement(new { schemaVersion = 1, editable = true,
            profile = new { identity = new { callSign = "A" }, content = new { introduction = "Original A" } } });
        store.ObserveProfile(a, self, () => true);
        store.Observe(a, "A", () => true);
        store.ObserveProfile(b, self, () => true);
        store.ObserveProfile(a, self, () => false);
        store.ObserveAchievements(b, new(1, []), () => true);
        store.ObserveAchievements(a, new(1, []), () => false);
        Require(store.ReadDisplay(2) is null, "Online observation is not offline selection");
        store.Pin(b, 2, () => true);
        Require(store.ReadDisplay(2) is null, "A different subject cannot select prior data");
        store.Pin(a, 2, () => false);
        Require(store.ReadDisplay(2) is null, "Stale owner cannot commit a selection");
        store.Pin(a, 2, () => true);
        Require(store.ReadDisplay(2)?.DisplayName == "A" && store.ReadDisplay(3) is null, "Exact mode revision required");
        Require(store.ReadAchievements(2)?.Collection.EarnedAt.ContainsKey("first-entry") == true &&
            store.ReadAchievements(3) is null, "Same-owner refresh retains collection; stale and different-owner writes cannot replace it");
        Require(store.ReadRemoteProfile(2)?.Payload.GetProperty("profile").GetProperty("content").GetProperty("introduction").GetString() == "Original A" &&
            store.ReadRemoteProfile(3) is null, "Confirmed self profile survives same-owner refresh and requires the exact offline revision");
        store.ObserveAchievements(a, new(1, []), () => true);
        Require(store.ReadAchievements(2)?.Collection.EarnedAt.Count == 1, "No late online write may overwrite a pinned offline collection");
        store.Observe(b, "B", () => false);
        Require(store.ReadDisplay(2)?.DisplayName == "A", "Late response cannot replace good snapshot");
        store.Observe(b, "B", () => true);
        Require(store.ReadDisplay(2) is null, "New account cannot inherit previous offline selection");
        store.Pin(b, 4, () => true);
        Require(store.ReadDisplay(4)?.DisplayName == "B", "Only current subject selected");
        Require(store.ReadAchievements(4) is null, "Missing collection is unavailable, never inherited or fabricated empty");
        Require(store.ReadRemoteProfile(4) is null, "A different owner cannot inherit private self presentation");
        var path = Path.Combine(f.Root, "offline-account-v1", "snapshot.bin");
        var encrypted = File.ReadAllBytes(path);
        Require(!System.Text.Encoding.UTF8.GetString(encrypted).Contains("synthetic-other", StringComparison.Ordinal), "No plaintext owner on disk");
        encrypted[encrypted.Length / 2] ^= 1;
        File.WriteAllBytes(path, encrypted);
        f.Runtime.InitializeOfflineAccount(f.Root);
        Require(f.Runtime.ReadOfflineAccount(4) is null, "Corrupt cache is unavailable, not another user or an empty profile");
        return Task.CompletedTask;
    }

    private static async Task<FirstUseModeRuntime> RootMode(LocalAccountStopTests.Fixture fixture)
    {
        await AccountBridgeRuntime.CreateWithFirstUseModeAsync(fixture.Root, _ => Task.FromResult(fixture.Runtime));
        return fixture.Runtime.FirstUseMode!;
    }
    private static async Task RootOffline()
    {
        using var f = new LocalAccountStopTests.Fixture(sampling: true);
        var mode = await RootMode(f); var context = f.Host.CurrentContext; var generation = f.Host.Generation;
        await using var native = new NativeAccountRuntimeBinding(f.Runtime);
        var op = Op(); var task = mode.ApplyRootOfflineAsync(0, op, generation, native);
        Require(ReferenceEquals(task, mode.ApplyRootOfflineAsync(0, op, generation, native)), "One physical ordinary transition");
        Require(await task.WaitAsync(TimeSpan.FromSeconds(5)) is { State: "offline", Revision: 2, PublicationSuspended: true } &&
            mode.Current.State == "offline" && mode.LocalMode().Active &&
            native.Read(owner => ReferenceEquals(owner, f.Runtime), false) &&
            f.Runtime.HasCurrentFirstUseLocalSources(mode.LocalMode().Generation), "Both actual owners must be restored before acknowledgement");
        Require(f.Vault.Deletions == 0 && f.Vault.Loads == 0 && f.Host.Generation == generation && f.Host.CurrentContext == context &&
            new FirstUseModeStore(f.Root).ReadCredentialCheckpoint() is null, "No credential inspection, deletion, logout or later-clear checkpoint");
        var denied = await native.DispatchAsync(Request(f));
        Require(denied.Response.Error?.Code == "account.local_mode", "Reconstructed Native callbacks cannot reopen online admission");
        var local = await f.Runtime.FirstUseStatisticsDispatcher!.DispatchAsync(BridgeEnvelope.Request(
            LocalStatisticsChoiceBridgeDispatcher.ReadRequest, Op(), mode.ControlGeneration, new { schemaVersion = 1 }));
        Require(local.Response.Status == "ok", "Actual independent local route remains usable");
        using var cold = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, NoOnline);
        Require(cold.FirstUseMode!.Current.State == "offline" && f.Vault.Loads == 0, "Cold offline startup never restores retained credentials");
        Require(mode.RequestResume(2, Op()).State == "signInRequired" && mode.LocalMode().Active, "Resume stays explicit and local until actual auth/review");
        Require((await mode.CancelOnlineAsync(3, Op())).State == "offline" && mode.LocalMode().Active,
            "Unstarted resume returns a new owned ordinary offline choice without losing local readiness");
        f.RequireLocalStateUnchanged();
    }

    private static TaskCompletionSource RootSignal() => new(TaskCreationOptions.RunContinuationsAsynchronously);
    private static async Task RootOfflineHeld(bool close)
    {
        using var f = new LocalAccountStopTests.Fixture(sampling: true); var mode = await RootMode(f);
        await using var native = new NativeAccountRuntimeBinding(f.Runtime);
        var release = RootSignal(); var cancelled = RootSignal();
        var read = native.ReadAsync(async (_, token) =>
        { using var registration = token.Register(() => cancelled.TrySetResult()); await release.Task; return true; });
        using var observer = new CancellationTokenSource(); var op = Op();
        var work = mode.ApplyRootOfflineAsync(0, op, f.Host.Generation, native, observer.Token);
        Task? closing = null;
        try
        {
            await cancelled.Task.WaitAsync(TimeSpan.FromSeconds(5));
            Require(!work.IsCompleted && !read.IsCompleted && f.Vault.Deletions == 0 &&
                new FirstUseModeStore(f.Root).Read().Phase == "offlinePending", "Intent precedes actual physical exit");
            if (close) closing = native.DisposeAsync().AsTask();
            else { observer.Cancel(); await Cancelled(work); }
            Require(!close || !closing!.IsCompleted, "Close must wait for the original callback, not cancellation requested");
        }
        finally { release.TrySetResult(); await Cancelled(read); }
        if (close)
        {
            await closing!.WaitAsync(TimeSpan.FromSeconds(5));
            Require((await work).State == "recoveryRequired" && new FirstUseModeStore(f.Root).Read().Phase == "offlinePending",
                "Close cannot commit offline readiness");
        }
        else Require((await mode.ApplyRootOfflineAsync(0, op, f.Host.Generation, native)).State == "offline", "Original transaction completes after observer leaves");
        Require(f.Vault.Deletions == 0 && f.Vault.Loads == 0, "Neither Close nor cancelled wait signs out");
        f.RequireLocalStateUnchanged();
    }

    private static async Task RootOfflineAccountRead()
    {
        using var f = new LocalAccountStopTests.Fixture(sampling: true); var mode = await RootMode(f);
        await using var native = new NativeAccountRuntimeBinding(f.Runtime);
        f.Transport.HoldProfile = true; var read = native.DispatchAsync(Request(f)).AsTask();
        await f.Transport.ProfileStarted.Task.WaitAsync(TimeSpan.FromSeconds(5));
        var work = mode.ApplyRootOfflineAsync(0, Op(), f.Host.Generation, native);
        try
        {
            using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(5));
            while (!f.Transport.ProfileToken.IsCancellationRequested) await Task.Delay(10, deadline.Token);
            Require(!work.IsCompleted && f.Vault.Deletions == 0, "Physical account transport exit precedes offline acknowledgement");
        }
        finally { f.Transport.ProfileRelease.TrySetResult(); }
        Require((await read).Response.Status == BridgeResponseStatuses.Cancelled && (await work).State == "offline",
            "Late account result cannot escape the original Native slot");
    }

    private static async Task RootOfflineLoop()
    {
        using var f = new LocalAccountStopTests.Fixture(sampling: true); var mode = await RootMode(f);
        await using var native = new NativeAccountRuntimeBinding(f.Runtime);
        f.Transport.HoldTicket = true; await f.Host.GetCurrentAsync(default);
        await f.Transport.TicketStarted.Task.WaitAsync(TimeSpan.FromSeconds(5));
        var work = mode.ApplyRootOfflineAsync(0, Op(), f.Host.Generation, native);
        try
        {
            using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(5));
            while (!f.Transport.TicketToken.IsCancellationRequested) await Task.Delay(10, deadline.Token);
            Require(!work.IsCompleted && f.Vault.Deletions == 0, "SCM loop's actual ignored-cancellation transport remains owned");
        }
        finally { f.Transport.TicketRelease.TrySetResult(); }
        Require((await work.WaitAsync(TimeSpan.FromSeconds(5))).State == "offline" && f.Vault.Loads == 0 && f.Vault.Deletions == 0,
            "Original loop drain is not credential retirement");
    }

    private static async Task RootOfflineIntentFailure()
    {
        using var f = new LocalAccountStopTests.Fixture(sampling: true); var mode = await RootMode(f);
        await using var native = new NativeAccountRuntimeBinding(f.Runtime);
        var path = ModePath(f.Root) + ".lock"; Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        using (var writer = new FileStream(path, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None))
            Require((await mode.ApplyRootOfflineAsync(0, Op(), f.Host.Generation, native)).State == "recoveryRequired" &&
                mode.Current.State == "online" && native.Generation == f.Host.Generation, "Proven unwritten intent cannot retire online owners");
        Require((await mode.ApplyRootOfflineAsync(0, Op(), f.Host.Generation, native)).State == "offline" && f.Vault.Deletions == 0,
            "Independent retry consumes actual untouched ordinary graph");
    }

    private static async Task RootOfflineFinalFailure()
    {
        using var f = new LocalAccountStopTests.Fixture(sampling: true); var mode = await RootMode(f);
        await using var native = new NativeAccountRuntimeBinding(f.Runtime);
        var release = RootSignal(); var cancelled = RootSignal();
        var read = native.ReadAsync(async (_, token) =>
        { using var registration = token.Register(() => cancelled.TrySetResult()); await release.Task; return true; });
        var work = mode.ApplyRootOfflineAsync(0, Op(), f.Host.Generation, native);
        try
        {
            await cancelled.Task.WaitAsync(TimeSpan.FromSeconds(5));
            using var writer = new FileStream(ModePath(f.Root) + ".lock", FileMode.Open, FileAccess.ReadWrite, FileShare.None);
            release.TrySetResult(); await Cancelled(read);
            Require((await work.WaitAsync(TimeSpan.FromSeconds(5))).State == "recoveryRequired" &&
                mode.Current.State == "recoveryRequired" && !mode.LocalMode().Active && native.Generation == -1 && f.Vault.Deletions == 0,
                "Physical exit without durable completion cannot acknowledge local readiness");
        }
        finally { release.TrySetResult(); try { await read; } catch (OperationCanceledException) { } }
        using var cold = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, NoOnline);
        Require(cold.FirstUseMode!.Current.State == "recoveryRequired", "Cold pending choice never reconnects automatically");
    }

    private static async Task RootOfflineGeneration()
    {
        using var f = new LocalAccountStopTests.Fixture(sampling: true); var mode = await RootMode(f);
        var native = new NativeAccountRuntimeBinding(f.Runtime);
        f.Transport.HoldTicket = true; await f.Host.GetCurrentAsync(default);
        await f.Transport.TicketStarted.Task.WaitAsync(TimeSpan.FromSeconds(5));
        var release = RootSignal(); var cancelled = RootSignal();
        var read = native.ReadAsync(async (_, token) =>
        {
            using var registration = token.Register(() =>
            {
                typeof(StarBridge.HostRuntime.Account.ScmAccountBridgeHost).GetField("_generation",
                    System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)!.SetValue(f.Host, f.Host.Generation + 1);
                cancelled.TrySetResult();
            });
            await release.Task; return true;
        });
        var work = mode.ApplyRootOfflineAsync(0, Op(), f.Host.Generation, native);
        try
        {
            await cancelled.Task.WaitAsync(TimeSpan.FromSeconds(5));
            release.TrySetResult(); await Cancelled(read);
            using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(5));
            while (!f.Transport.TicketToken.IsCancellationRequested) await Task.Delay(10, deadline.Token);
            Require(!work.IsCompleted, "Changed generation cannot abandon the original held SCM loop");
        }
        finally { release.TrySetResult(); f.Transport.TicketRelease.TrySetResult(); await Cancelled(read); }
        Require((await work.WaitAsync(TimeSpan.FromSeconds(5))).State == "recoveryRequired" && !mode.LocalMode().Active &&
            f.Vault.Deletions == 0 && native.Generation == -1, "Another account generation cannot become offline under an older proof");
        try { await native.DisposeAsync(); throw new Exception("Stale identity exit must remain failed at total close"); }
        catch (InvalidOperationException error) when (error.Message == "The installed first-use candidate did not confirm complete exit.") { }
    }

    private sealed class RootCommitQueue : SynchronizationContext
    {
        private SendOrPostCallback? _callback; private object? _state;
        public override void Post(SendOrPostCallback callback, object? state)
        { Require(_callback is null, "Only original offline continuation may queue"); _callback = callback; _state = state; }
        internal Task Start() => Task.Run(() => _callback!(_state));
    }
    private static async Task RootOfflineQueuedClose()
    {
        using var f = new LocalAccountStopTests.Fixture(sampling: true); var mode = await RootMode(f);
        await using var native = new NativeAccountRuntimeBinding(f.Runtime);
        f.Transport.HoldTicket = true; await f.Host.GetCurrentAsync(default);
        await f.Transport.TicketStarted.Task.WaitAsync(TimeSpan.FromSeconds(5));
        var queue = new RootCommitQueue(); var previous = SynchronizationContext.Current;
        Task<FirstUseModeObservation> work;
        SynchronizationContext.SetSynchronizationContext(queue);
        try { work = mode.ApplyRootOfflineAsync(0, Op(), f.Host.Generation, native); }
        finally { SynchronizationContext.SetSynchronizationContext(previous); }
        var closing = mode.CloseOwnedOnlineAsync()!;
        var disposal = native.DisposeAsync().AsTask();
        var continued = queue.Start();
        try
        {
            using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(5));
            while (!f.Transport.TicketToken.IsCancellationRequested) await Task.Delay(10, deadline.Token);
            Require(!work.IsCompleted && !closing.IsCompleted && !disposal.IsCompleted && f.Vault.Deletions == 0,
                "Close before intent owns every actual physical loop exit, even though durable offline cannot commit");
        }
        finally { f.Transport.TicketRelease.TrySetResult(); await continued; }
        Require((await work.WaitAsync(TimeSpan.FromSeconds(5))).State == "recoveryRequired" && await closing && f.Vault.Deletions == 0,
            "Close drains but cannot acknowledge obsolete offline mode or sign out");
        await disposal.WaitAsync(TimeSpan.FromSeconds(5));
    }

    private static async Task RootOfflineGuards()
    {
        using var f = new LocalAccountStopTests.Fixture(sampling: true); var mode = await RootMode(f);
        await using var native = new NativeAccountRuntimeBinding(f.Runtime);
        using var other = new LocalAccountStopTests.Fixture(sampling: true);
        await using var unrelated = new NativeAccountRuntimeBinding(other.Runtime);
        Expect("firstUse.context_changed", () => mode.ApplyRootOfflineAsync(0, Op(), f.Host.Generation, unrelated));
        Expect("firstUse.context_changed", () => mode.ApplyRootOfflineAsync(0, Op(), f.Host.Generation + 1, native));
        Expect("firstUse.context_changed", () => mode.ApplyRootOfflineAsync(1, Op(), f.Host.Generation, native));
        foreach (var phase in new[] { "offlinePending", "offline" })
            Expect("firstUse.mode_receipt_required", () => new FirstUseModeStore(f.Root).Save(0, Op(), phase, () => true));
        Require(new FirstUseModeStore(f.Root).Read() == FirstUseModeChoice.Unchosen &&
            native.Generation == f.Host.Generation && f.Vault.Loads == 0 && f.Vault.Deletions == 0, "Invalid requests have no intent, retirement or vault effects");
    }
}
