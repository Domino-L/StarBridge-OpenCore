using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Onboarding;
using StarBridge.HostRuntime.Settings;
using StarBridge.NativeBridge;

internal static class FirstUseCompositionTests
{
    private static string Id() => Guid.NewGuid().ToString("N");
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
    private static async Task Case(string name, Func<Task> test)
    { await test(); Console.WriteLine("PASS first-use composition: " + name); }
    internal static async Task Run()
    {
        await Case("ordinary Native configuration uses the original owning modules", Ordinary);
        await Case("bound Native composition retains account and device routes and drains before disposal", BoundNative);
        await Case("local cold composition preserves device and local statistics routing without account consumers", LocalCold);
        await Case("waiting and cold pending modes never construct account business consumers", Pending);
        await Case("unknown mode cannot become an account configuration grant", Unknown);
        await Case("environment-locked device shells never construct unavailable account consumers", LockedShell);
        await Case("the actual SCM deferral cannot be bypassed with a noncandidate runtime label", DeferredOwner);
        await Case("actual account retirement waits for an admitted configuration callback", Drain);
        await Case("failed and disposed configuration callbacks cannot leak admission or reopen it", Failure);
    }
    private static async Task Ordinary()
    {
        using var f = new LocalAccountStopTests.Fixture(sampling: true);
        await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, _ => Task.FromResult(f.Runtime));
        var calls = 0;
        Check(f.Runtime.TryConfigureAccountBusiness(owner => {
            Check(ReferenceEquals(owner, f.Runtime), "Configuration must target the existing actual account owner.");
            calls++; owner.ConfigureOverlayCommunitySource(f.Root, startDriver: false);
        }) && calls == 1 && f.Runtime.FirstUseMode!.Current.ActiveMode == "online",
            "Ordinary construction retains its owning modules, not an alternative business factory.");
        f.RequireLocalStateUnchanged();
    }
    private static async Task BoundNative()
    {
        using var f = new LocalAccountStopTests.Fixture(sampling: true);
        await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, _ => Task.FromResult(f.Runtime));
        await using var binding = new NativeAccountRuntimeBinding(f.Runtime);
        using var preferences = new ApplicationPreferencesBridgeDispatcher(f.Root, () => binding.Generation);
        using var lifecycle = new HostBridgeDispatcher(Id(), () => binding.Generation, []);
        using var dispatcher = new CompositeBridgeDispatcher(lifecycle, binding, preferences);
        var generation = binding.Generation;
        var accountRequest = BridgeEnvelope.Request("account.getCurrent", Id(), generation, new { schemaVersion = 1 }, f.Host.CurrentContext);
        var accountResponse = (await dispatcher.DispatchAsync(accountRequest)).Response;
        Check(accountResponse.Status == BridgeResponseStatuses.Ok,
            "The installed binding must preserve real account dispatch, got " + accountResponse.Error?.Code);
        Check((await dispatcher.DispatchAsync(BridgeEnvelope.Request(ApplicationPreferencesRequestNames.Get, Id(),
            binding.Generation, new { schemaVersion = 1 }))).Response.Status == BridgeResponseStatuses.Ok,
            "Account wrapping cannot replace the original device settings module.");
        foreach (var emit in new Func<long, object, BridgeEnvelope>[] {
            binding.NotificationActivation, binding.SocialNotification, binding.MenuHotkeyIntent, binding.UpdateProgress })
        {
            Check(emit(binding.Generation, new { schemaVersion = 1 }).SessionGeneration == binding.Generation,
                "Native event must retain the current account sequence source and generation.");
            try { emit(binding.Generation + 1, new { }); throw new InvalidOperationException("Stale native event was admitted."); }
            catch (OperationCanceledException) { }
        }
        var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var read = binding.ReadAsync(async (owner, token) => {
            Check(ReferenceEquals(owner, f.Runtime), "Native callback changed actual account owner.");
            entered.TrySetResult(); await release.Task; return owner.Generation;
        });
        try
        {
            await entered.Task.WaitAsync(TimeSpan.FromSeconds(3));
            var drain = binding.DrainCallbacksAsync();
            Check(!drain.IsCompleted && ReferenceEquals(drain, binding.DrainCallbacksAsync()) && binding.Generation == -1,
                "Native shutdown must retain the actual callback until exit, close new admission and share one drain.");
            Check((await dispatcher.DispatchAsync(accountRequest)).Response.Status != BridgeResponseStatuses.Ok,
                "Closed native pipe admission must not leak a live account response.");
            release.TrySetResult();
            try { await read; throw new InvalidOperationException("Late native callback result escaped."); }
            catch (OperationCanceledException) { }
            await drain.WaitAsync(TimeSpan.FromSeconds(3));
            Check((await f.Runtime.DispatchAsync(accountRequest)).Response.Status == BridgeResponseStatuses.Ok,
                "Draining native callbacks alone is not account disposal, logout or business activation.");
            Check(!f.Vault.Deleted, "Native drain cannot clear credentials.");
            f.RequireLocalStateUnchanged();
        }
        finally { release.TrySetResult(); }
    }

    private static async Task LocalCold()
    {
        using var f = new FirstUseOnlineReturnTests.Fixture(); await f.Prepare();
        var calls = 0;
        Check(!f.Local.Runtime.TryConfigureAccountBusiness(_ => calls++), "Retired account cannot install new consumers.");
        using var cold = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Local.Root,
            _ => throw new InvalidOperationException("Local cold startup must not construct OAuth or online business."));
        Check(!cold.TryConfigureAccountBusiness(_ => calls++) && calls == 0 && cold.FirstUseMode!.LocalMode().Active &&
            cold.FirstUseOverlaySource!.Capture() is not null && f.Transport.Requests == 0,
            "Device-only startup skips the consumer factory and preserves its single confirmed local source.");
        using var preferences = new ApplicationPreferencesBridgeDispatcher(f.Local.Root, () => cold.Generation);
        using var lifecycle = new HostBridgeDispatcher(Id(), () => cold.Generation, []);
        await using var binding = new NativeAccountRuntimeBinding(cold);
        using var dispatcher = new CompositeBridgeDispatcher(lifecycle, binding, preferences,
            firstUseStatistics: cold.FirstUseStatisticsDispatcher);
        var device = await dispatcher.DispatchAsync(BridgeEnvelope.Request(ApplicationPreferencesRequestNames.Get, Id(),
            cold.Generation, new { schemaVersion = 1 }));
        var stats = await dispatcher.DispatchAsync(BridgeEnvelope.Request(LocalStatisticsChoiceBridgeDispatcher.ReadRequest, Id(),
            cold.Generation, new { schemaVersion = 1 }));
        Check(device.Response.Status == BridgeResponseStatuses.Ok && stats.Response.Status == BridgeResponseStatuses.Ok &&
            cold.FirstUseMode!.LocalMode().Active && f.Transport.Requests == 0,
            "Skipping account setup must not remove actual device settings or independent local statistics bridge routing.");
        f.Local.RequireLocalStateUnchanged();
    }
    private static async Task Pending()
    {
        using var f = new FirstUseOnlineReturnTests.Fixture(); await f.Prepare(); f.Mode.RequestOnline(2, Id()); await f.Stage();
        var calls = 0;
        Check(!f.Candidate!.TryConfigureAccountBusiness(_ => calls++) && !f.Local.Runtime.TryConfigureAccountBusiness(_ => calls++),
            "Both auth-only candidate and retired original reject construction callbacks.");
        using var cold = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Local.Root,
            _ => throw new InvalidOperationException("Cold pending composition cannot restore authorization."));
        Check(!cold.TryConfigureAccountBusiness(_ => calls++) && calls == 0 && cold.FirstUseMode!.LocalMode().Active &&
            f.Transport.Requests == 0 && f.Clock.Timers == 0, "Pending isn't installed online business, even with a trusted local origin.");
        f.Local.RequireLocalStateUnchanged();
    }
    private static async Task Unknown()
    {
        using var f = new FirstUseOnlineReturnTests.Fixture(); await f.Prepare();
        var path = Path.Combine(f.Local.Root, "first-use-mode-v1", "state.bin");
        File.WriteAllBytes(path, [1, 2, 3]); // Only checked synthetic GUID fixture.
        using var cold = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Local.Root,
            _ => throw new InvalidOperationException("Unknown mode cannot authorize online construction."));
        var calls = 0;
        Check(!cold.TryConfigureAccountBusiness(_ => calls++) && calls == 0 && !cold.FirstUseMode!.LocalMode().Active &&
            f.Transport.Requests == 0 && File.ReadAllBytes(path).SequenceEqual(new byte[] { 1, 2, 3 }),
            "Unknown mode keeps the device shell but neither erases intent nor grants local/online business readiness.");
        f.Local.RequireLocalStateUnchanged();
    }
    private static async Task Drain()
    {
        using var f = new LocalAccountStopTests.Fixture(sampling: true);
        await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, _ => Task.FromResult(f.Runtime));
        var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        using var release = new ManualResetEventSlim();
        var configuration = Task.Run(() => f.Runtime.TryConfigureAccountBusiness(_ => {
            entered.TrySetResult();
            Check(release.Wait(TimeSpan.FromSeconds(3)), "Synthetic Native construction wasn't released.");
        }));
        try
        {
            await entered.Task.WaitAsync(TimeSpan.FromSeconds(3));
            var stop = f.Runtime.FirstUseMode!.ApplyLocalAsync(0, Id(), f.Host.Generation);
            Check(!stop.IsCompleted && !f.Runtime.TryConfigureAccountBusiness(_ =>
                throw new InvalidOperationException("Late consumer constructor was admitted.")),
                "Retirement closes new admission but cannot acknowledge unfinished real configuration.");
            release.Set();
            Check(!await configuration.WaitAsync(TimeSpan.FromSeconds(3)) &&
                (await stop.WaitAsync(TimeSpan.FromSeconds(3))).State == "local",
                "Only actual configuration exit completes the original owner's retirement.");
            f.RequireLocalStateUnchanged();
        }
        finally { release.Set(); }
    }
    private static Task LockedShell()
    {
        using var shell = AccountBridgeRuntime.CreateIsolatedSandboxShell(); var calls = 0;
        Check(!shell.TryConfigureAccountBusiness(_ => calls++) && calls == 0 && shell.FirstUseMode is null,
            "No SCM/transitional owner means no account consumer factory; it doesn't choose local mode or create intent.");
        return Task.CompletedTask;
    }
    private static Task DeferredOwner()
    {
        using var f = new FirstUseOnlineReturnTests.Fixture();
        var uri = new Uri("https://synthetic.example.invalid/");
        var oauth = new StarBridge.HostRuntime.Auth.OAuthPkceClient(new StarBridge.HostRuntime.Auth.ScmHttpClient(f.Transport), f.Vault,
            new("synthetic-scm", uri, uri, uri, "synthetic-client", "synthetic-resource", "openid profile.read", "/callback"));
        using var host = new StarBridge.HostRuntime.Account.ScmAccountBridgeHost(oauth,
            new StarBridge.HostRuntime.Auth.ScmProfileCacheStore(f.Local.Root), "synthetic", () => null,
            requireFreshSignIn: true, deferBusinessStartup: true);
        using var runtime = new AccountBridgeRuntime(host); var calls = 0;
        Check(!runtime.TryConfigureAccountBusiness(_ => calls++) && calls == 0 && f.Transport.Requests == 0,
            "Native configuration depends on the actual deferred auth owner, not merely the wrapper's candidate flag.");
        return Task.CompletedTask;
    }
    private static async Task Failure()
    {
        using var f = new LocalAccountStopTests.Fixture(sampling: true);
        await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, _ => Task.FromResult(f.Runtime));
        try
        {
            f.Runtime.TryConfigureAccountBusiness(_ => throw new InvalidOperationException("Synthetic Native configuration failure."));
            throw new InvalidOperationException("Expected the real configuration error.");
        }
        catch (InvalidOperationException error) when (error.Message == "Synthetic Native configuration failure.") { }
        Check((await f.Runtime.FirstUseMode!.ApplyLocalAsync(0, Id(), f.Host.Generation).WaitAsync(TimeSpan.FromSeconds(3))).State == "local",
            "Thrown constructor must release its actual lease so retirement can complete.");
        f.Runtime.Dispose();
        var calls = 0;
        Check(!f.Runtime.TryConfigureAccountBusiness(_ => calls++) && calls == 0, "Disposed owner cannot construct new consumers.");
        f.RequireLocalStateUnchanged();
    }
}
