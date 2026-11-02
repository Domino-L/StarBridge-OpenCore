using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Onboarding;
using StarBridge.NativeBridge;

internal static class FirstUseOnlineCandidateTests
{
    private static string Id() => Guid.NewGuid().ToString("N");
    private static void Check(bool condition, string message)
    { if (!condition) throw new InvalidOperationException(message); }
    internal static async Task Run()
    {
        await Case("candidate construction owns no business timer or session loop", QuietCandidate);
        await Case("only exact authentication commands reach the candidate owner", Commands);
        await Case("changed or damaged intent invalidates the original candidate", Intent);
        await Case("construction rejects an old intent or an already active SCM owner", Preparation);
        await Case("fresh candidate reads cannot restore either credential authority", Fresh);
        await Case("Native composition cannot attach candidate background consumers", Composition);
        await Case("ordinary account construction retains its original background cadence", Ordinary);
    }
    private static async Task Case(string name, Func<Task> test)
    { await test(); Console.WriteLine("PASS first-use online candidate: " + name); }
    private sealed class Transport : HttpMessageHandler
    {
        internal int Requests;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        { Interlocked.Increment(ref Requests); throw new InvalidOperationException("Synthetic candidate attempted background traffic."); }
    }
    private sealed class Vault : ITokenVault
    {
        internal int Reads, Writes, Deletes;
        public void SaveRefreshToken(string key, string token) => Writes++;
        public string? LoadRefreshToken(string key) { Reads++; return "synthetic-old-token"; }
        public string? LoadActiveAccountKey() { Reads++; return "synthetic-old-selected-account"; }
        public void DeleteRefreshToken(string key) => Deletes++;
    }
    private sealed class Clock : TimeProvider
    {
        internal int Timers;
        public override ITimer CreateTimer(TimerCallback callback, object? state, TimeSpan dueTime, TimeSpan period)
        { Timers++; return new QuietTimer(); }
        private sealed class QuietTimer : ITimer
        {
            public bool Change(TimeSpan dueTime, TimeSpan period) => true;
            public void Dispose() { }
            public ValueTask DisposeAsync() => ValueTask.CompletedTask;
        }
    }
    private sealed class Fixture : IDisposable
    {
        internal string Root { get; } = Path.Combine(Path.GetTempPath(), "starbridge-online-candidate", Id());
        internal readonly Transport Transport = new();
        internal readonly Vault Vault = new();
        internal readonly Clock Clock = new();
        internal readonly FirstUseModeStore Mode;
        internal readonly FirstUseModeChoice Pending;
        internal Fixture()
        {
            Directory.CreateDirectory(Root); Mode = new(Root);
            var localPending = Mode.Save(0, Id(), "localPending", () => true);
            var local = Mode.Save(localPending.Revision, Id(), "local", () => true);
            Pending = Mode.BeginOnline(local, Id(), () => true);
            Mode.MarkOnlineCandidateStarted(Pending, () => true);
        }
        internal ScmAccountBridgeHost Host(bool fresh = false, bool deferred = true)
        {
            var uri = new Uri("http://127.0.0.1:1/");
            var oauth = new OAuthPkceClient(new ScmHttpClient(Transport), Vault,
                new ScmOAuthOptions("synthetic-scm", uri, uri, uri, "synthetic", "synthetic", "openid profile.read", "/callback"));
            var host = new ScmAccountBridgeHost(oauth, new ScmProfileCacheStore(Root), "synthetic", () => "Pilot-Example",
                initialSession: fresh ? null : new("synthetic-scm", "synthetic-subject", "Pilot-Example", "synthetic-access",
                    DateTimeOffset.UtcNow.AddHours(1), ["profile.read"]),
                initialGeneration: fresh ? 0 : 3, requireFreshSignIn: fresh, deferBusinessStartup: deferred,
                partyRooms: new StarBridge.HostRuntime.PartyRooms.PartyRoomReader(uri));
            if (deferred) { host.EnableParticipantSynchronization(); host.EnableRoomMembershipKeepalive(); }
            return host;
        }
        internal AccountBridgeRuntime Runtime(ScmAccountBridgeHost host, bool candidate = true) => new(host,
            new StarBridge.HostRuntime.Hangar.LocalHangarStore(Root),
            new StarBridge.HostRuntime.Profiles.LocalPersonalProfileStore(Root),
            new StarBridge.HostRuntime.Presence.GameplayTimeStore(Root),
            new StarBridge.HostRuntime.Presence.GameLogSettingsStore(Root),
            new StarBridge.HostRuntime.Privacy.LocalPrivacyStore(Root),
            new StarBridge.HostRuntime.Support.LocalGameEventJournal(Path.Combine(Root, "local-event-log.json")),
            new StarBridge.HostRuntime.Settings.PresenceVisibilityStore(Root), Root,
            firstUseCandidate: candidate, backgroundTime: Clock,
            candidateIntent: candidate ? new(Mode, Pending) : null);
        internal BridgeEnvelope Request(AccountBridgeRuntime runtime, string name) =>
            BridgeEnvelope.Request(name, Id(), runtime.Generation, new { schemaVersion = 1 });
        public void Dispose()
        {
            Transport.Dispose();
            var full = Path.GetFullPath(Root);
            var parent = Path.GetFullPath(Path.Combine(Path.GetTempPath(), "starbridge-online-candidate"));
            if (Path.GetDirectoryName(full) != parent || !Guid.TryParseExact(Path.GetFileName(full), "N", out _))
                throw new InvalidOperationException("Unsafe candidate fixture path.");
            for (var directory = new DirectoryInfo(full); directory is not null; directory = directory.Parent)
                if (directory.Exists && directory.Attributes.HasFlag(FileAttributes.ReparsePoint))
                    throw new InvalidOperationException("Unsafe candidate fixture ancestor.");
            Directory.Delete(full, recursive: true);
        }
    }
    private static async Task QuietCandidate()
    {
        using var f = new Fixture(); using var host = f.Host(); using var runtime = f.Runtime(host);
        var files = Directory.GetFiles(f.Root, "*", SearchOption.AllDirectories);
        var state = await host.GetCurrentAsync(default);
        Check(state.Context is not null && host.GameplayTimeContext is null && f.Clock.Timers == 0 &&
            host.ParticipantLoopCompletion.IsCompleted && host.RoomKeepaliveCompletion.IsCompleted &&
            f.Transport.Requests == 0 && f.Vault.Reads == 0 && f.Vault.Writes == 0 &&
            files.SequenceEqual(Directory.GetFiles(f.Root, "*", SearchOption.AllDirectories)),
            "Candidate status can describe an authenticated identity without background startup, files, restored credentials or participation.");
    }
    private static async Task Commands()
    {
        using var f = new Fixture(); using var host = f.Host(); using var runtime = f.Runtime(host);
        foreach (var name in new[] { "gameLog.select", "gameplayTime.setConsent", "achievements.read", "privacy.read",
            "privacy.save", "friends.list", "personalProfile.updateSelf", "account.updateAvatar", "account.legacyLogin", "account.supportRead" })
        {
            var result = await runtime.DispatchAsync(f.Request(runtime, name));
            Check(result.Response.Error?.Code == "firstUse.candidate_not_attached", "Business request escaped the auth-only candidate: " + name);
        }
        var read = await runtime.DispatchAsync(f.Request(runtime, AccountBridgeRequestNames.GetCurrent));
        var cancel = await runtime.DispatchAsync(f.Request(runtime, AccountBridgeRequestNames.CancelLogin));
        Check(read.Response.Status == BridgeResponseStatuses.Ok && cancel.Response.Status == BridgeResponseStatuses.Ok &&
            f.Clock.Timers == 0 && f.Transport.Requests == 0 && f.Vault.Writes == 0 && f.Vault.Deletes == 0,
            "Existing status/cancel contracts are retained without granting business authority or clearing an account.");
    }
    private static async Task Intent()
    {
        using var f = new Fixture(); using var host = f.Host(); using var runtime = f.Runtime(host);
        f.Mode.Save(f.Pending.Revision, Id(), "onlinePending", () => true);
        var changed = await runtime.DispatchAsync(f.Request(runtime, AccountBridgeRequestNames.GetCurrent));
        Check(changed.Response.Error?.Code == "firstUse.context_changed" && f.Transport.Requests == 0,
            "A different actual mode revision cannot be adopted by the old candidate.");
        var path = Path.Combine(f.Root, "first-use-mode-v1", "state.bin");
        File.WriteAllBytes(path, [1, 2, 3, 4]);
        var damaged = await runtime.DispatchAsync(f.Request(runtime, AccountBridgeRequestNames.CancelLogin));
        Check(damaged.Response.Error?.Code == "firstUse.context_changed" && File.ReadAllBytes(path).SequenceEqual(new byte[] { 1, 2, 3, 4 }),
            "Damaged intent remains intact and does not fall back to an old authorization.");
        using var other = new Fixture(); using var otherHost = other.Host(); using var otherRuntime = other.Runtime(otherHost);
        var originPath = Path.Combine(other.Root, "first-use-mode-v1", "online-origin.bin");
        File.WriteAllBytes(originPath, [5, 6, 7]);
        var lostOrigin = await otherRuntime.DispatchAsync(other.Request(otherRuntime, AccountBridgeRequestNames.GetCurrent));
        Check(lostOrigin.Response.Error?.Code == "firstUse.context_changed" && other.Transport.Requests == 0 &&
            File.ReadAllBytes(originPath).SequenceEqual(new byte[] { 5, 6, 7 }),
            "The exact candidate also requires its actual persisted start/origin record, not only the pending phase.");
    }
    private static async Task Fresh()
    {
        using var f = new Fixture(); using var host = f.Host(fresh: true); using var runtime = f.Runtime(host);
        await runtime.DispatchAsync(f.Request(runtime, AccountBridgeRequestNames.GetCurrent));
        await runtime.DispatchAsync(f.Request(runtime, AccountBridgeRequestNames.GetCurrent));
        Check(host.CurrentContext is null && f.Vault.Reads == 0 && f.Transport.Requests == 0 && f.Clock.Timers == 0,
            "A production-style fresh candidate never consults the formerly selected refresh credential.");
    }
    private static Task Preparation()
    {
        using var f = new Fixture(); using var host = f.Host();
        f.Mode.Save(f.Pending.Revision, Id(), "onlinePending", () => true);
        try { using var runtime = f.Runtime(host); throw new InvalidOperationException("Old candidate intent was accepted."); }
        catch (LocalFirstUseException error) { Check(error.Code == "firstUse.context_changed", "Constructor retains the exact original intent fence."); }
        using var ordinary = f.Host(deferred: false);
        try { using var runtime = f.Runtime(ordinary); throw new InvalidOperationException("Active SCM owner was accepted as a staged candidate."); }
        catch (ArgumentException) { }
        Check(f.Clock.Timers == 0 && f.Transport.Requests == 0 && f.Vault.Reads == 0,
            "Rejected preparation creates no business owner or credential traffic.");
        return Task.CompletedTask;
    }
    private static Task Composition()
    {
        using var f = new Fixture(); using var host = f.Host(); using var runtime = f.Runtime(host);
        var configured = 0;
        Check(!runtime.TryConfigureAccountBusiness(_ => configured++) && configured == 0,
            "Original Native business configuration cannot start a staged candidate's timers.");
        Check(!runtime.ConfigureCommunityNotifications(null!) && !runtime.ConfigurePlayerActivity(null!),
            "Candidate cannot register live notification or player activity consumers.");
        foreach (var attach in new Action[] { () => runtime.ConfigureOverlayCommunitySource(f.Root),
            () => runtime.ConfigureSharedActivity(null!), () => runtime.ConfigureLiveOverlayUpdates(null!) })
        {
            try { attach(); throw new InvalidOperationException("Candidate background attachment was accepted."); }
            catch (InvalidOperationException error) when (error.Message == "Account background work has retired.") { }
        }
        Check(f.Clock.Timers == 0 && f.Transport.Requests == 0, "Native configuration cannot start candidate background work.");
        return Task.CompletedTask;
    }
    private static Task Ordinary()
    {
        using var f = new Fixture(); using var host = f.Host(deferred: false); using var runtime = f.Runtime(host, candidate: false);
        Check(f.Clock.Timers >= 7 && host.GameplayTimeContext is not null,
            "Existing normal-account log, statistics, achievements and sharing timers are not disabled by candidate staging.");
        var timers = f.Clock.Timers; var configured = 0;
        Check(runtime.TryConfigureAccountBusiness(_ => configured++) && runtime.TryConfigureAccountBusiness(_ => configured++) &&
            configured == 2 && f.Clock.Timers == timers,
            "Repeated real Native configuration reuses each original timer without allocating another sampler or publisher.");
        return Task.CompletedTask;
    }

    internal static async Task OriginalScmLifecycle()
    {
        using var f = new Fixture();
        var previous = HostDataRoot.CurrentRoot;
        HostDataRoot.UsePreparedRoot(f.Root);
        try
        {
            await LegacyPasswordLoginTests.ScmParticipantEnrollment();
            await ScmRealtimeLifecycleTests.Verify();
            Console.WriteLine("PASS candidate staging retains original SCM participation and realtime lifecycle");
        }
        finally { HostDataRoot.UsePreparedRoot(previous); }
    }
}
