using System.Net;
using System.Net.Http;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Onboarding;
using StarBridge.NativeBridge;

internal static class FirstUseOnlineReturnTests
{
    private static string Id() => Guid.NewGuid().ToString("N");
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
    private static TaskCompletionSource Signal() => new(TaskCreationOptions.RunContinuationsAsynchronously);
    private static async Task Case(string name, Func<Task> test)
    { await test(); Console.WriteLine("PASS first-use online return: " + name); }
    internal static async Task Run()
    {
        await Case("pending sign-in preserves the original local source and epoch", Continuity);
        await Case("cancel before construction keeps all local data and ignores old credentials", NoCandidate);
        await Case("cold pending with a trusted unstarted origin remains local and can cancel", Cold);
        await Case("unknown or stale origins cannot authorize local activation", UnknownOrigin);
        await Case("damaged origin and busy writers preserve original private bytes", OriginStorage);
        await Case("construction that ignores cancellation must actually exit before return", SlowConstruction);
        await Case("cancelled UI wait does not abandon the original candidate cleanup", CancelledWait);
        await Case("cancel waits for actual OAuth transport exit without clearing old credentials", LoginDrain);
        await Case("completed fresh OAuth login is cleared through its original credential owner", CompletedLogin);
        await Case("newer credential versions are retained and prevent cancellation completion", NewerCredential);
        await Case("cold started candidate cannot claim credential cleanup from process metadata", ColdStarted);
        await Case("construction failure is not a login and can return without restoring credentials", ConstructionFailure);
        await Case("failed final mode commit retries the same already retired candidate", FinalCommit);
        await Case("closing the mode retires even a late construction result", CloseConstruction);
        await Case("cancellation callback failure still waits for actual candidate construction exit", CancellationCallback);
        await Case("strict encrypted origin rejects missing, duplicate, unknown and invalid provenance", StrictOrigin);
        await Case("candidate retirement cancellation can observe the same exit from another thread", RetirementReentry);
        await Case("cancelled online return permits a later explicit fresh sign-in with a new candidate", RepeatOnlineReturn);
    }

    private static async Task RepeatOnlineReturn()
    {
        using var f = new Fixture(); await f.Prepare();
        f.Mode.RequestOnline(2, Id()); await f.Stage(); await f.Login();
        var first = f.Candidate!;
        var firstGeneration = first.Generation;
        Check((await f.Cancel()).State == "local" && f.Vault.LoadActiveAccountKey() is null,
            "first explicit cancel actually clears its fresh credential");
        var requests = f.Transport.Requests;
        var next = f.Mode.RequestOnline(f.Store.Read().Revision, Id());
        var second = await f.Stage();
        Check(!ReferenceEquals(first, second) && second.Generation > firstGeneration &&
            second.FirstUseSignInState(f.Intent!) == "signInRequired" && f.Transport.Requests == requests,
            "second selection constructs a distinct higher generation without implicit sign-in");
        Check((await f.Login()).Response.Status == BridgeResponseStatuses.Ok &&
            f.Transport.TokenRequests == 2 && f.Mode.Current.Revision == next.Revision,
            "only a second explicit login authorizes the second candidate");
        Check((await f.Cancel()).State == "local" && f.Vault.LoadActiveAccountKey() is null,
            "second cancellation drains its own candidate without retaining a credential");
        f.Local.RequireLocalStateUnchanged();
    }

    private static async Task RetirementReentry()
    {
        using var f = new Fixture(); await f.Prepare(); f.Mode.RequestOnline(2, Id()); await f.Stage();
        var candidate = f.Candidate!;
        var work = (StarBridge.HostRuntime.Lifecycle.AsyncWorkRetirement)typeof(AccountBridgeRuntime)
            .GetField("_requestRetirement", System.Reflection.BindingFlags.NonPublic |
                System.Reflection.BindingFlags.Instance)!.GetValue(candidate)!;
        using var lease = work.Enter(default)!;
        using var entered = new ManualResetEventSlim();
        using var observed = new ManualResetEventSlim();
        var reentered = false;
        var observer = Task.Factory.StartNew(() =>
        {
            if (!entered.Wait(TimeSpan.FromSeconds(3))) throw new InvalidOperationException("Cancellation was not observed.");
            var exit = candidate.RetireFirstUseOnlineCandidateAsync();
            observed.Set(); return exit;
        }, CancellationToken.None, TaskCreationOptions.LongRunning, TaskScheduler.Default);
        using var callback = lease.Token.Register(() =>
        {
            entered.Set(); reentered = observed.Wait(TimeSpan.FromSeconds(3));
        });
        Task<bool>? retirement = null;
        try
        {
            retirement = candidate.RetireFirstUseOnlineCandidateAsync();
            var second = await observer.WaitAsync(TimeSpan.FromSeconds(3));
            Check(reentered && ReferenceEquals(retirement, second),
                "Candidate retirement holds its reservation lock during cancellation callbacks.");
            Check(!retirement.IsCompleted && work.IsClosed,
                "Cancellation does not acknowledge a live original request lease.");
        }
        finally
        {
            entered.Set(); lease.Dispose();
            if (retirement is not null) await retirement.WaitAsync(TimeSpan.FromSeconds(3));
            await observer.WaitAsync(TimeSpan.FromSeconds(3));
        }
        Check(await retirement! && (await f.Cancel()).State == "local" && f.Clock.Timers == 0,
            "Only actual candidate exit permits local return without business activation.");
        f.Local.RequireLocalStateUnchanged();
    }

    internal sealed class Transport : HttpMessageHandler
    {
        internal bool HoldToken;
        internal readonly TaskCompletionSource TokenEntered = Signal(), ReleaseToken = Signal();
        internal CancellationToken Token;
        internal int Requests, Revokes, IdentityRequests, TokenRequests;
        internal string? LastGrant;
        internal bool HoldIdentity, IncludeIdentity = true, IdentityVerified = true;
        internal string[] Capabilities = ["profile.read"];
        internal Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>>? GameIdentityRequest;
        internal string? IdentityStatus = "VERIFIED", Handle = "Pilot-Example", NormalizedHandle = "pilot-example";
        internal string Subject = "synthetic-subject", DisplayName = "Synthetic Pilot";
        internal HttpStatusCode IdentityResponseStatus = HttpStatusCode.OK;
        internal int TokenLifetimeSeconds = 3600;
        internal bool AllowProfileRead;
        internal bool AllowPresenceWrite;
        internal Func<CancellationToken, Task>? BeforeResourceReply;
        internal bool RotateAccessToken;
        internal bool RejectRefresh;
        internal int AchievementTriggers;
        // Other first-use cases retain their original unavailable business
        // request boundary. Achievement-specific cases explicitly enable success.
        internal bool FailAchievementTrigger = true;
        internal bool HoldAchievementTrigger;
        internal readonly TaskCompletionSource AchievementEntered = Signal(), ReleaseAchievement = Signal();
        internal readonly TaskCompletionSource IdentityEntered = Signal(), ReleaseIdentity = Signal();
        internal CancellationToken IdentityToken;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Check(request.RequestUri?.Host == "synthetic.example.invalid", "Only injected synthetic OAuth requests are allowed.");
            Requests++;
            var path = request.RequestUri!.AbsolutePath;
            if (path.EndsWith("/token", StringComparison.Ordinal))
            {
                TokenRequests++;
                LastGrant = await request.Content!.ReadAsStringAsync();
                if (RejectRefresh && LastGrant.Contains("grant_type=refresh_token", StringComparison.Ordinal))
                    return new(HttpStatusCode.BadRequest) { Content = JsonContent.Create(new { error = "invalid_grant" }) };
                Token = token; TokenEntered.TrySetResult();
                if (HoldToken) await ReleaseToken.Task; // Deliberately ignores cancellation.
                return new(HttpStatusCode.OK) { Content = JsonContent.Create(new
                { access_token = RotateAccessToken ? "synthetic-access-" + TokenRequests : "synthetic-access", refresh_token = "synthetic-refresh", token_type = "Bearer",
                    expires_in = TokenLifetimeSeconds, scope = "openid profile.read offline_access" }) };
            }
            if (path.EndsWith("/me", StringComparison.Ordinal))
            {
                IdentityRequests++; IdentityToken = token;
                if (HoldIdentity) { IdentityEntered.TrySetResult(); await ReleaseIdentity.Task; }
                return new(IdentityResponseStatus) { Content = JsonContent.Create(new
                { subject = Subject, displayName = DisplayName, capabilities = Capabilities,
                    gameIdentity = IncludeIdentity ? new { status = IdentityStatus, verified = IdentityVerified,
                        handle = Handle, normalizedHandle = NormalizedHandle } : null }) };
            }
            if (path.EndsWith("/revoke", StringComparison.Ordinal)) { Revokes++; return new(HttpStatusCode.OK); }
            if (GameIdentityRequest is { } gameIdentity && path.Contains("/game-identity/", StringComparison.Ordinal))
                return await gameIdentity(request, token);
            if (request.Method == HttpMethod.Get && path.EndsWith("/member/user/get", StringComparison.Ordinal))
            {
                Interlocked.Increment(ref AchievementTriggers); AchievementEntered.TrySetResult();
                if (HoldAchievementTrigger) await ReleaseAchievement.Task;
                if (FailAchievementTrigger) throw new HttpRequestException("Synthetic achievement trigger failure after refresh.");
                return new(HttpStatusCode.OK) { Content = JsonContent.Create(new { code = 0 }) };
            }
            if (AllowPresenceWrite && request.Method == HttpMethod.Put && path.EndsWith("/presence/status", StringComparison.Ordinal))
            {
                if (BeforeResourceReply is { } before) await before(token);
                using var body = System.Text.Json.JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
                Check(body.RootElement.GetProperty("status").GetInt32() == 1, "Publication fixture explicitly selects Online only.");
                return new(HttpStatusCode.OK) { Content = JsonContent.Create(new
                    { signInStatus = 1, timestamp = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(), anonymous = false }) };
            }
            if (AllowProfileRead && path.EndsWith("/profile", StringComparison.Ordinal))
            {
                if (BeforeResourceReply is { } before) await before(token);
                return new(HttpStatusCode.OK) { Content = JsonContent.Create(new
                    { schemaVersion = 1, subject = Subject, displayName = DisplayName, gameIdentityVerified = true }) };
            }
            if (AllowProfileRead && path.EndsWith("/timezone/list", StringComparison.Ordinal))
                return new(HttpStatusCode.OK) { Content = JsonContent.Create(new
                    { code = 0, data = new[] { new { value = "Etc/UTC", label = "UTC", offset = "+00:00" } } }) };
            throw new InvalidOperationException("Candidate attempted a business request.");
        }
    }
    internal sealed class Clock : TimeProvider
    {
        internal int Timers;
        internal bool AllowTimers;
        internal int FailAt;
        internal readonly List<TestTimer> Created = [];
        public override ITimer CreateTimer(TimerCallback callback, object? state, TimeSpan dueTime, TimeSpan period)
        {
            Timers++;
            if (!AllowTimers) throw new InvalidOperationException("Candidate created a business timer.");
            if (Timers == FailAt) throw new IOException("Synthetic installation timer failure.");
            var timer = new TestTimer(); Created.Add(timer); return timer;
        }
        internal sealed class TestTimer : ITimer
        {
            internal bool Disposed;
            internal bool FailDispose;
            internal int Changes;
            public bool Change(TimeSpan dueTime, TimeSpan period) { Changes++; return !Disposed; }
            public void Dispose() => Disposed = true;
            public ValueTask DisposeAsync()
            {
                Disposed = true;
                return FailDispose ? ValueTask.FromException(new IOException("Synthetic timer retirement failure."))
                    : ValueTask.CompletedTask;
            }
        }
    }
    // Frozen session time: a short token stays current until a test moves it,
    // however long setup takes on a loaded machine.
    internal sealed class FrozenSessionTime : TimeProvider
    {
        internal DateTimeOffset Now = DateTimeOffset.UtcNow;
        public override DateTimeOffset GetUtcNow() => Now;
    }
    internal sealed class Fixture : IDisposable
    {
        internal readonly LocalAccountStopTests.Fixture Local;
        internal readonly Transport Transport = new();
        internal readonly Clock Clock = new();
        internal readonly WindowsTokenVault Vault;
        internal readonly string VaultPath;
        internal FirstUseModeRuntime Mode => Local.Runtime.FirstUseMode!;
        internal FirstUseModeStore Store => new(Local.Root);
        internal AccountBridgeRuntime? Candidate;
        internal StarBridge.HostRuntime.Support.LocalGameEventJournal? EventJournal;
        internal ScmAccountBridgeHost? Host;
        internal S2CompatibilityReader? Compatibility;
        internal LegacyPasswordLoginClient? Legacy;
        internal DailySupportClient? DailySupport;
        internal StarBridge.HostRuntime.Communities.CommunityClient? Communities;
        internal FirstUseOnlineCandidateIntent? Intent;
        internal TimeProvider? DataOwnerTime;
        // Drives OAuth session expiry; null keeps the system clock.
        internal TimeProvider? SessionTime;
        internal Task? Callback;
        internal readonly TaskCompletionSource BuildEntered = Signal(), ReleaseBuild = Signal();
        internal bool HoldBuild, FailBuild, FailCancellationCallback;
        internal int BrowserOpens;
        internal Action<Uri>? ProfileOpened;
        internal Fixture(long initialGeneration = 0)
        {
            Local = new(sampling: true, initialGeneration: initialGeneration);
            VaultPath = Path.Combine(Local.Root, "candidate", "scm-token-vault.json"); Vault = new(VaultPath);
        }
        internal async Task Prepare(TimeProvider? modeTime = null)
        {
            await AccountBridgeRuntime.CreateWithFirstUseModeAsync(Local.Root, _ => Task.FromResult(Local.Runtime),
                candidateFactory: Build, modeTime: modeTime);
            Check((await Mode.ApplyLocalAsync(0, Id(), Local.Host.Generation)).State == "local", "Actual local retirement required.");
        }
        internal async Task PrepareOrdinary()
        {
            // A normal authenticated root, not a fabricated candidate install.
            // Only this checked synthetic fixture's real DPAPI vault is seeded.
            Vault.SaveRefreshToken("synthetic-scm:synthetic-subject", "synthetic-refresh");
            await AccountBridgeRuntime.CreateWithFirstUseModeAsync(Local.Root, _ => Task.FromResult(Local.Runtime),
                candidateFactory: Build);
        }
        internal Task<AccountBridgeRuntime> Stage() => Mode.StageOnlineCandidateAsync(Store.Read().Revision);
        internal Task<FirstUseModeObservation> Cancel(CancellationToken token = default) =>
            Mode.CancelOnlineAsync(Store.Read().Revision, Id(), token);
        private async Task<AccountBridgeRuntime> Build(FirstUseOnlineCandidateIntent intent, CancellationToken token)
        {
            Intent = intent;
            using var callback = FailCancellationCallback ? token.Register(() =>
                throw new InvalidOperationException("Synthetic cancellation callback failure.")) : default;
            BuildEntered.TrySetResult();
            if (HoldBuild) await ReleaseBuild.Task; // No dispatcher delivered until actual construction exits.
            if (FailBuild) throw new InvalidOperationException("Synthetic configuration failure before authentication.");
            var uri = new Uri("https://synthetic.example.invalid/");
            var oauth = new OAuthPkceClient(new ScmHttpClient(Transport), Vault,
                new("synthetic-scm", uri, uri, uri, "synthetic-client", "synthetic-resource",
                    "openid profile.read offline_access", "/callback"), authorizationBrowser: OpenBrowser)
                { SessionClock = SessionTime ?? TimeProvider.System };
            Host = new(oauth, new ScmProfileCacheStore(Path.Combine(Local.Root, "candidate-profile")), "synthetic",
                () => null, requireFreshSignIn: !intent.RetainSession, deferBusinessStartup: true,
                requireRetainedFirstUseSession: intent.RetainSession,
                compatibilityReader: Compatibility, legacyPasswordLogin: Legacy, dailySupport: DailySupport, communities: Communities)
                { LocalDataOwnerClock = DataOwnerTime ?? TimeProvider.System };
            return Candidate = AccountBridgeRuntime.CreateAccountBusinessRuntime(Host, Local.Root,
                EventJournal, firstUseCandidate: true, candidateIntent: intent, backgroundTime: Clock);
        }
        private void OpenBrowser(Uri authorization)
        {
            if (authorization.AbsoluteUri == "https://robertsspaceindustries.com/account/profile")
            { ProfileOpened?.Invoke(authorization); return; }
            BrowserOpens++;
            // Exercise the real PKCE listener and state validation without a
            // visible browser, external endpoint, real identity or saved token.
            var query = authorization.Query.TrimStart('?').Split('&').Select(value => value.Split('=', 2))
                .ToDictionary(value => Uri.UnescapeDataString(value[0]), value => Uri.UnescapeDataString(value[1]));
            var callback = new Uri(query["redirect_uri"] + "?code=synthetic-code&state=" + Uri.EscapeDataString(query["state"]));
            Check(callback.IsLoopback, "Synthetic browser may call only the actual loopback listener.");
            Callback = SendCallback(callback);
        }
        private static async Task SendCallback(Uri uri)
        {
            using var client = new HttpClient(new SocketsHttpHandler { UseProxy = false });
            using var response = await client.GetAsync(uri);
            response.EnsureSuccessStatusCode();
        }
        internal async Task<BridgeDispatchBatch> Login()
        {
            var result = await Candidate!.DispatchAsync(BridgeEnvelope.Request("account.login", Id(), Candidate.Generation,
                new { schemaVersion = 1 }));
            if (Callback is not null) await Callback.WaitAsync(TimeSpan.FromSeconds(3));
            return result;
        }
        public void Dispose()
        {
            ReleaseBuild.TrySetResult(); Transport.ReleaseToken.TrySetResult(); Transport.ReleaseIdentity.TrySetResult();
            Candidate?.Dispose(); Host?.Dispose(); Transport.Dispose(); Local.Dispose();
        }
    }

    private static async Task Continuity()
    {
        using var f = new Fixture(); await f.Prepare();
        var mode = f.Mode.LocalMode(); var frame = f.Local.Runtime.FirstUseOverlaySource!.Capture()!; var before = frame.Read();
        var pending = f.Mode.RequestOnline(2, Id());
        Check(pending is { State: "signInRequired", ActiveMode: "local", PublicationSuspended: true } &&
            f.Mode.LocalMode() == mode && frame.Read() == before && f.Clock.Timers == 0,
            "Pending sign-in must not change the local source generation or spawn account work.");
        f.Local.RequireLocalStateUnchanged();
    }
    private static async Task NoCandidate()
    {
        using var f = new Fixture(); await f.Prepare();
        f.Vault.SaveRefreshToken("synthetic-old:other", "synthetic-old-refresh");
        var bytes = File.ReadAllBytes(f.VaultPath); var loads = f.Local.Vault.Loads;
        var mode = f.Mode.LocalMode(); f.Mode.RequestOnline(2, Id());
        Check((await f.Cancel()) is { State: "local", ActiveMode: "local", Revision: 4 } && f.Mode.LocalMode() == mode &&
            f.Transport.Requests == 0 && f.Local.Vault.Loads == loads && File.ReadAllBytes(f.VaultPath).SequenceEqual(bytes),
            "No candidate means no selected credential read/deletion, network or local reset.");
        Check((await f.Local.Runtime.DispatchAsync(BridgeEnvelope.Request("account.login", Id(), f.Local.Runtime.Generation,
            new { schemaVersion = 1 }))).Response.Error?.Code == "account.local_mode", "Original retired account stays sealed.");
        f.Local.RequireLocalStateUnchanged();
    }
    private static async Task Cold()
    {
        using var f = new Fixture(); await f.Prepare(); f.Mode.RequestOnline(2, Id());
        using var cold = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Local.Root,
            _ => throw new InvalidOperationException("Cold pending may not construct OAuth or read its vault."));
        Check(cold.FirstUseMode!.Current.ActiveMode == "local" &&
            (await cold.FirstUseMode.CancelOnlineAsync(3, Id())).State == "local", "Trusted unstarted origin permits explicit local return.");
    }
    private static async Task UnknownOrigin()
    {
        using var f = new Fixture(); await f.Prepare();
        f.Store.Save(2, Id(), "onlinePending", () => true);
        using var unknown = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Local.Root, _ => throw new InvalidOperationException());
        Check(!unknown.FirstUseMode!.LocalMode().Active && unknown.FirstUseMode.Current.State == "recoveryRequired",
            "A phase string is not an established local origin.");
        using var other = new Fixture(); await other.Prepare(); other.Mode.RequestOnline(2, Id());
        other.Store.Save(3, Id(), "onlinePending", () => true);
        using var stale = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(other.Local.Root,
            _ => throw new InvalidOperationException());
        Check(!stale.FirstUseMode!.LocalMode().Active && stale.FirstUseMode.Current.State == "recoveryRequired",
            "An earlier exact origin cannot authorize a later pending revision.");
    }
    private static async Task OriginStorage()
    {
        using var f = new Fixture(); await f.Prepare();
        var state = File.ReadAllBytes(Path.Combine(f.Local.Root, "first-use-mode-v1", "state.bin"));
        var originPath = Path.Combine(f.Local.Root, "first-use-mode-v1", "online-origin.bin");
        using (var lease = new FileStream(Path.Combine(f.Local.Root, "first-use-mode-v1", "state.bin.lock"),
            FileMode.Open, FileAccess.ReadWrite, FileShare.None))
            await Expect("firstUse.mode_write_failed", () => Task.FromResult(f.Mode.RequestOnline(2, Id())));
        Check(!File.Exists(originPath) && f.Mode.LocalMode().Active, "Busy writer does not create an origin or retire local mode.");
        File.WriteAllBytes(originPath, [1, 2, 3]); // Malformed private test fixture only.
        await Expect("firstUse.mode_receipt_read_failed", () => Task.FromResult(f.Mode.RequestOnline(2, Id())));
        Check(File.ReadAllBytes(originPath).SequenceEqual(new byte[] { 1, 2, 3 }) &&
            File.ReadAllBytes(Path.Combine(f.Local.Root, "first-use-mode-v1", "state.bin")).SequenceEqual(state) &&
            f.Mode.LocalMode().Active, "Damaged origin cannot replace either original file or retire local mode.");
    }
    private static async Task SlowConstruction()
    {
        using var f = new Fixture(); await f.Prepare(); f.HoldBuild = true; f.Mode.RequestOnline(2, Id());
        var staging = f.Stage(); await f.BuildEntered.Task.WaitAsync(TimeSpan.FromSeconds(3));
        var cancel = f.Cancel();
        Check(!cancel.IsCompleted && f.Store.Read().Phase == "onlinePending" && f.Mode.LocalMode().Active,
            "Requested cancellation cannot acknowledge an unfinished factory.");
        f.ReleaseBuild.TrySetResult();
        Check((await cancel.WaitAsync(TimeSpan.FromSeconds(3))).State == "local" && f.Clock.Timers == 0,
            "Actual staged owner retirement precedes local return.");
        await Expect("firstUse.context_changed", () => staging);
    }
    private static async Task CancelledWait()
    {
        using var f = new Fixture(); await f.Prepare(); f.HoldBuild = true; f.Mode.RequestOnline(2, Id());
        var staging = f.Stage(); await f.BuildEntered.Task.WaitAsync(TimeSpan.FromSeconds(3));
        using var token = new CancellationTokenSource(); var cancel = f.Cancel(token.Token); token.Cancel();
        try { await cancel; throw new InvalidOperationException("Expected cancelled UI wait."); } catch (OperationCanceledException) { }
        Check(f.Mode.LocalMode().Active && f.Store.Read().Phase == "onlinePending", "Abandoned wait preserves pending ownership.");
        f.ReleaseBuild.TrySetResult();
        Check((await f.Cancel().WaitAsync(TimeSpan.FromSeconds(3))).State == "local", "Retry awaits the same original cleanup task.");
        await Expect("firstUse.context_changed", () => staging);
    }
    private static async Task LoginDrain()
    {
        using var f = new Fixture(); await f.Prepare(); f.Mode.RequestOnline(2, Id()); await f.Stage();
        f.Vault.SaveRefreshToken("synthetic-old:other", "synthetic-old-refresh"); var bytes = File.ReadAllBytes(f.VaultPath);
        f.Transport.HoldToken = true;
        var login = f.Login(); await f.Transport.TokenEntered.Task.WaitAsync(TimeSpan.FromSeconds(3));
        var cancel = f.Cancel();
        Check(!cancel.IsCompleted && f.Transport.Token.IsCancellationRequested && f.Mode.LocalMode().Active &&
            f.Store.Read().Phase == "onlinePending" && File.ReadAllBytes(f.VaultPath).SequenceEqual(bytes),
            "Actual ignored token work must exit, and old cached credential is not the candidate's credential.");
        f.Transport.ReleaseToken.TrySetResult();
        Check((await login.WaitAsync(TimeSpan.FromSeconds(3))).Response.Status == BridgeResponseStatuses.Cancelled &&
            (await cancel.WaitAsync(TimeSpan.FromSeconds(3))).State == "local" &&
            File.ReadAllBytes(f.VaultPath).SequenceEqual(bytes) && f.Transport.Revokes == 0,
            "Late authorization cannot commit or publish after retirement.");
    }
    private static async Task CompletedLogin()
    {
        using var f = new Fixture(); await f.Prepare(); f.Mode.RequestOnline(2, Id()); await f.Stage();
        var login = await f.Login().WaitAsync(TimeSpan.FromSeconds(3));
        Check(login.Response.Status == BridgeResponseStatuses.Ok && f.Host!.CurrentContext is not null &&
            f.Vault.LoadActiveAccountKey() == "synthetic-scm:synthetic-subject" && f.Clock.Timers == 0,
            "The real callback, token, identity and DPAPI writer complete while business work remains staged.");
        Check((await f.Cancel().WaitAsync(TimeSpan.FromSeconds(3))).State == "local" && f.Vault.LoadActiveAccountKey() is null &&
            f.Vault.LoadRefreshToken("synthetic-scm:synthetic-subject") is null && f.Transport.Revokes == 1,
            "Original OAuth writer clears precisely its credential before acknowledging return.");
        f.Local.RequireLocalStateUnchanged();
    }
    private static async Task NewerCredential()
    {
        foreach (var newerKey in new[] { "synthetic-scm:synthetic-subject", "synthetic-other:other" })
        {
            using var f = new Fixture(); await f.Prepare(); f.Mode.RequestOnline(2, Id()); await f.Stage(); await f.Login();
            f.Vault.SaveRefreshToken(newerKey, "synthetic-newer-refresh");
            var bytes = File.ReadAllBytes(f.VaultPath);
            Check((await f.Cancel().WaitAsync(TimeSpan.FromSeconds(3))).State == "recoveryRequired" &&
                f.Store.Read().Phase == "onlinePending" && f.Mode.LocalMode().Active &&
                File.ReadAllBytes(f.VaultPath).SequenceEqual(bytes) && f.Transport.Revokes == 0,
                "Cancellation never adopts a newer same/different-account credential or falsely completes.");
        }
    }
    private static async Task ColdStarted()
    {
        using var f = new Fixture(); await f.Prepare(); f.Mode.RequestOnline(2, Id()); await f.Stage();
        using var cold = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Local.Root, _ => throw new InvalidOperationException());
        Check(cold.FirstUseMode!.LocalMode().Active &&
            (await cold.FirstUseMode.CancelOnlineAsync(3, Id())).State == "recoveryRequired" && f.Transport.Requests == 0,
            "Lost candidate owner retains local functions but does not prove credential cleanup or restore login.");
        Check((await f.Cancel()).State == "local", "Only the actual live owner can acknowledge its candidate's exit.");
    }
    private static async Task ConstructionFailure()
    {
        using var f = new Fixture(); await f.Prepare(); f.FailBuild = true; f.Mode.RequestOnline(2, Id());
        try { await f.Stage(); throw new InvalidOperationException("Expected synthetic factory failure."); }
        catch (InvalidOperationException error) when (error.Message.StartsWith("Synthetic configuration", StringComparison.Ordinal)) { }
        Check((await f.Cancel()).State == "local" && f.Transport.Requests == 0 && !File.Exists(f.VaultPath),
            "Failed construction has never delivered an auth dispatcher or selected a credential.");
    }
    private static async Task FinalCommit()
    {
        using var f = new Fixture(); await f.Prepare(); f.Mode.RequestOnline(2, Id()); await f.Stage(); await f.Login();
        using (var lease = new FileStream(Path.Combine(f.Local.Root, "first-use-mode-v1", "state.bin.lock"),
            FileMode.Open, FileAccess.ReadWrite, FileShare.None))
            await Expect("firstUse.mode_write_failed", () => f.Cancel());
        Check(f.Mode.LocalMode().Active && f.Store.Read().Phase == "onlinePending" && f.Vault.LoadActiveAccountKey() is null &&
            f.Transport.Revokes == 1, "A failed mode commit keeps original cleanup completion, never restores authorization.");
        Check((await f.Cancel()).State == "local" && f.Transport.Revokes == 1,
            "Retry commits after the real writer is released without another authentication or revocation.");
    }
    private static async Task CloseConstruction()
    {
        using var f = new Fixture(); await f.Prepare(); f.HoldBuild = true; f.Mode.RequestOnline(2, Id());
        var stage = f.Stage(); await f.BuildEntered.Task.WaitAsync(TimeSpan.FromSeconds(3));
        f.Mode.Close(); f.ReleaseBuild.TrySetResult();
        await Expect("firstUse.context_changed", () => stage);
        Check(await f.Candidate!.RetireFirstUseOnlineCandidateAsync().WaitAsync(TimeSpan.FromSeconds(3)) &&
            !f.Mode.LocalMode().Active && f.Store.Read().Phase == "onlinePending" && f.Transport.Requests == 0,
            "Late candidate is truly retired, while close is not an implicit completed local-mode receipt.");
    }
    private static async Task CancellationCallback()
    {
        using var f = new Fixture(); await f.Prepare(); f.HoldBuild = true; f.FailCancellationCallback = true;
        f.Mode.RequestOnline(2, Id()); var stage = f.Stage(); await f.BuildEntered.Task.WaitAsync(TimeSpan.FromSeconds(3));
        var cancel = f.Cancel();
        Check(!cancel.IsCompleted && f.Mode.LocalMode().Active, "A throwing callback neither abandons cleanup nor acknowledges exit.");
        f.ReleaseBuild.TrySetResult();
        Check((await cancel.WaitAsync(TimeSpan.FromSeconds(3))).State == "local", "Actual factory exit still controls the result.");
        await Expect("firstUse.context_changed", () => stage);
    }
    private static async Task StrictOrigin()
    {
        using var f = new Fixture(); await f.Prepare(); f.Mode.RequestOnline(2, Id());
        var path = Path.Combine(f.Local.Root, "first-use-mode-v1", "online-origin.bin");
        var original = File.ReadAllBytes(path);
        var entropy = Encoding.UTF8.GetBytes("StarBridge.first-use-online-origin.v1");
        var clear = ProtectedData.Unprotect(original, entropy, DataProtectionScope.CurrentUser);
        string valid;
        try { valid = Encoding.UTF8.GetString(clear); }
        finally { CryptographicOperations.ZeroMemory(clear); }
        var bad = new List<string> { valid.Replace("\"schemaVersion\":1", "\"schemaVersion\":1,\"schemaVersion\":1", StringComparison.Ordinal) };
        foreach (var mutate in new Action<JsonObject>[] {
            value => value.Remove("candidateStarted"),
            value => value["unexpected"] = true,
            value => value["pending"]!["revision"] = 2,
            value => value["local"]!["phase"] = "online",
            value => value["owner"]!["processId"] = 0,
            value => value["pending"]!["savedAt"] = DateTimeOffset.UtcNow.AddDays(1).ToString("O") })
        {
            var node = JsonNode.Parse(valid)!; mutate((JsonObject)node["value"]!); bad.Add(node.ToJsonString());
        }
        var newerSchema = JsonNode.Parse(valid)!; newerSchema["schemaVersion"] = 2; bad.Add(newerSchema.ToJsonString());
        foreach (var document in bad)
        {
            var raw = Encoding.UTF8.GetBytes(document); byte[] encrypted;
            try { encrypted = ProtectedData.Protect(raw, entropy, DataProtectionScope.CurrentUser); }
            finally { CryptographicOperations.ZeroMemory(raw); }
            File.WriteAllBytes(path, encrypted);
            await Expect("firstUse.mode_receipt_read_failed", () => Task.FromResult(f.Store.ReadOnlineOrigin()));
            using var cold = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Local.Root,
                _ => throw new InvalidOperationException("Invalid provenance cannot restore an account."));
            Check(!f.Mode.LocalMode().Active && cold.FirstUseMode!.Current.State == "recoveryRequired" &&
                File.ReadAllBytes(path).SequenceEqual(encrypted), "Malformed private provenance is neither ignored nor overwritten.");
            f.Local.RequireLocalStateUnchanged();
        }
        File.WriteAllBytes(path, original); // Restore only our own synthetic fixture for the final observation.
        Check(f.Mode.LocalMode().Active && (await f.Cancel()).State == "local", "Original valid origin remains the only accepted provenance.");
    }
    private static async Task Expect(string code, Func<Task> work)
    {
        try { await work(); } catch (LocalFirstUseException error) when (error.Code == code) { return; }
        throw new InvalidOperationException("Expected " + code);
    }
}
