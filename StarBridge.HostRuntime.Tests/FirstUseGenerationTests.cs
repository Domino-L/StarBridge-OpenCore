using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Lifecycle;
using StarBridge.HostRuntime.Onboarding;
using StarBridge.NativeBridge;

internal static class FirstUseGenerationTests
{
    private static string Id() => Guid.NewGuid().ToString("N");
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
    private static async Task Case(string name, Func<Task> test)
    { await test(); Console.WriteLine("PASS first-use generation: " + name); }
    internal static async Task Run()
    {
        await Case("actual construction starts beyond the retired original generation", Construction);
        await Case("real PKCE login and re-login advance the same composition sequence", Login);
        await Case("stale original and candidate requests cannot authenticate under a reused generation", StaleRequests);
        await Case("cancel and later reconstruction retain the completed candidate high-water mark", Reconstruction);
        await Case("a live authorization cannot be relabeled or rebound", Rebinding);
        await Case("generation exhaustion rejects construction before authentication or business startup", Exhaustion);
        await Case("shared Native construction allocates distinct generations concurrently", Concurrent);
        await Case("identity readback retains generation and does not manufacture account changes", Readback);
    }
    private static async Task Construction()
    {
        foreach (var initial in new long[] { 0, 100, 5_000_000_000 })
        {
            using var f = new FirstUseOnlineReturnTests.Fixture(initial); await f.Prepare();
            var previous = f.Local.Runtime.Generation; var local = f.Mode.LocalMode();
            f.Mode.RequestOnline(2, Id()); var candidate = await f.Stage();
            Check(candidate.Generation > previous && candidate.Generation == f.Host!.Generation &&
                f.Mode.LocalMode() == local && f.Transport.Requests == 0 && f.Clock.Timers == 0,
                "The original actual generation, not zero or a UI label, bounds fresh construction.");
            f.Local.RequireLocalStateUnchanged();
        }
    }
    private static async Task Login()
    {
        using var f = new FirstUseOnlineReturnTests.Fixture(); await f.Prepare(); f.Mode.RequestOnline(2, Id()); await f.Stage();
        var constructed = f.Candidate!.Generation;
        var first = await f.Login(); var signedIn = f.Candidate.Generation;
        Check(first.Response.Status == BridgeResponseStatuses.Ok && signedIn > constructed &&
            first.Events.Any(value => value.Name == "account.changed" && value.SessionGeneration == signedIn),
            "The real session publication and its bridge event share the allocated generation.");
        f.Transport.Subject = "synthetic-next-subject";
        var second = await f.Login(); var next = f.Candidate.Generation;
        Check(second.Response.Status == BridgeResponseStatuses.Ok && next > signedIn &&
            second.Events.Any(value => value.Name == "account.changed" && value.SessionGeneration == next) &&
            f.Host!.CurrentContext?.Subject == "synthetic-next-subject" && f.Clock.Timers == 0,
            "Changed authenticated owners do not restart a per-host counter.");
        f.Local.RequireLocalStateUnchanged();
    }
    private static async Task StaleRequests()
    {
        using var f = new FirstUseOnlineReturnTests.Fixture(); await f.Prepare(); var original = f.Local.Runtime.Generation;
        f.Mode.RequestOnline(2, Id()); await f.Stage(); var constructed = f.Candidate!.Generation;
        var rejected = await f.Candidate.DispatchAsync(BridgeEnvelope.Request("account.login", Id(), original,
            new { schemaVersion = 1 }));
        Check(rejected.Response.Status != BridgeResponseStatuses.Ok && f.Transport.Requests == 0,
            "An original delayed login cannot be admitted by the new candidate.");
        await f.Login(); var signedIn = f.Candidate.Generation; var requests = f.Transport.Requests;
        foreach (var obsolete in new[] { original, constructed })
        {
            var logout = await f.Candidate.DispatchAsync(BridgeEnvelope.Request("account.logout", Id(), obsolete,
                new { schemaVersion = 1 }, f.Host!.CurrentContext));
            Check(logout.Response.Status != BridgeResponseStatuses.Ok && f.Candidate.Generation == signedIn &&
                f.Transport.Requests == requests && f.Vault.LoadActiveAccountKey() is not null,
                "Old same-number lifecycles cannot log out the current authenticated owner.");
        }
    }
    private static async Task Reconstruction()
    {
        using var f = new FirstUseOnlineReturnTests.Fixture(); await f.Prepare(); f.Mode.RequestOnline(2, Id()); await f.Stage();
        await f.Login(); await f.Login(); var first = f.Candidate!; var high = first.Generation;
        Check((await f.Cancel()).State == "local" && first.Generation > high,
            "Actual candidate cleanup publication advances the same sequence.");
        high = first.Generation; var local = f.Mode.LocalMode();
        f.Mode.RequestOnline(f.Store.Read().Revision, Id()); var next = await f.Stage();
        Check(!ReferenceEquals(first, next) && next.Generation > high && f.Mode.LocalMode() == local,
            "A second construction cannot reuse generations from a disposed earlier candidate.");
        var login = await f.Login();
        Check(login.Response.Status == BridgeResponseStatuses.Ok && next.Generation > high && f.Clock.Timers == 0,
            "A new real PKCE lifecycle retains the original composition lineage without enabling business.");
        f.Local.RequireLocalStateUnchanged();
    }
    private static async Task Rebinding()
    {
        using var f = new FirstUseOnlineReturnTests.Fixture(); await f.Prepare(); f.Mode.RequestOnline(2, Id()); await f.Stage();
        var generation = f.Host!.Generation;
        try { f.Host.BindFirstUseGenerations(new()); throw new InvalidOperationException("A bound candidate was relabeled."); }
        catch (InvalidOperationException error) when (error.Message == "Account generation source cannot be rebound.") { }
        await f.Login(); generation = f.Host.Generation; var context = f.Host.CurrentContext;
        try { f.Host.BindFirstUseGenerations(new()); throw new InvalidOperationException("A live login was relabeled."); }
        catch (InvalidOperationException error) when (error.Message == "Account generation source cannot be rebound.") { }
        Check(f.Host.Generation == generation && f.Host.CurrentContext == context && f.Clock.Timers == 0,
            "Binding cannot mutate an existing login, even with another legitimate allocator.");
    }
    private static async Task Exhaustion()
    {
        using var f = new FirstUseOnlineReturnTests.Fixture(); await f.Prepare(); f.Mode.RequestOnline(2, Id());
        f.Store.MarkOnlineCandidateStarted(f.Store.Read(), () => true);
        var generations = new AccountGenerationSequence(); generations.Observe(long.MaxValue);
        var uri = new Uri("https://synthetic.example.invalid/");
        var oauth = new OAuthPkceClient(new ScmHttpClient(f.Transport), f.Vault,
            new("synthetic-scm", uri, uri, uri, "synthetic-client", "synthetic-resource", "openid profile.read", "/callback"));
        using var host = new ScmAccountBridgeHost(oauth, new ScmProfileCacheStore(f.Local.Root), "synthetic", () => null,
            requireFreshSignIn: true, deferBusinessStartup: true);
        try
        {
            using var candidate = new AccountBridgeRuntime(host, firstUseCandidate: true,
                candidateIntent: new(f.Store, f.Store.Read(), generations));
            throw new InvalidOperationException("Exhausted sequence wrapped into an older generation.");
        }
        catch (InvalidOperationException error) when (error.Message == "Account generation sequence is exhausted.") { }
        Check(host.Generation == 0 && host.CurrentContext is null && f.Transport.Requests == 0 && f.Clock.Timers == 0 &&
            !File.Exists(f.VaultPath), "Failed binding doesn't authenticate, alter credentials or partially assign the sequence.");
        f.Local.RequireLocalStateUnchanged();
    }
    private static async Task Concurrent()
    {
        using var f = new FirstUseOnlineReturnTests.Fixture(); await f.Prepare(); f.Mode.RequestOnline(2, Id());
        f.Store.MarkOnlineCandidateStarted(f.Store.Read(), () => true);
        var generations = new AccountGenerationSequence(); generations.Observe(f.Local.Runtime.Generation);
        var uri = new Uri("https://synthetic.example.invalid/");
        var values = await Task.WhenAll(Enumerable.Range(0, 16).Select(_ => Task.Run(() =>
        {
            var oauth = new OAuthPkceClient(new ScmHttpClient(f.Transport), f.Vault,
                new("synthetic-scm", uri, uri, uri, "synthetic-client", "synthetic-resource", "openid profile.read", "/callback"));
            using var host = new ScmAccountBridgeHost(oauth, new ScmProfileCacheStore(f.Local.Root), "synthetic", () => null,
                requireFreshSignIn: true, deferBusinessStartup: true);
            using var candidate = new AccountBridgeRuntime(host, firstUseCandidate: true,
                candidateIntent: new(f.Store, f.Store.Read(), generations));
            return candidate.Generation;
        })));
        Check(values.Distinct().Count() == values.Length && values.Min() > f.Local.Runtime.Generation &&
            f.Transport.Requests == 0 && f.Clock.Timers == 0,
            "Actual concurrent fresh constructors share a monotonic allocator, not time/random/fixed strides.");
    }
    private static async Task Readback()
    {
        using var f = new FirstUseOnlineReturnTests.Fixture(); await f.Prepare(); f.Mode.RequestOnline(2, Id()); await f.Stage();
        await f.Login(); var generation = f.Candidate!.Generation; var events = new List<BridgeEnvelope>();
        f.Candidate.EventReady += events.Add;
        var review = await f.Mode.ReadOnlineIdentityAsync(3);
        Check((await f.Mode.ConfirmOnlineIdentityAsync(3, review.ConfirmationKey!)).State == "confirmedForHandoff" &&
            f.Candidate.Generation == generation && events.Count == 0 && f.Mode.LocalMode().Active &&
            f.Store.Read().Phase == "onlinePending" && f.Clock.Timers == 0,
            "Reading/confirming identity does not fabricate generation, account-change event or installed runtime.");
        f.Candidate.EventReady -= events.Add;
        f.Local.RequireLocalStateUnchanged();
    }
}
