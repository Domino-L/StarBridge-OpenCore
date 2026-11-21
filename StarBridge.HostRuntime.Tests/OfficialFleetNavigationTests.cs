using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Reflection;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Communities;
using StarBridge.HostRuntime.Privacy;
using StarBridge.HostRuntime.Notifications;
using StarBridge.HostRuntime.Overlay;
using StarBridge.NativeBridge;

internal static class OfficialFleetNavigationTests
{
    private sealed class Clock : TimeProvider
    {
        private DateTimeOffset _now = DateTimeOffset.UtcNow;
        private long _timestampOffset;
        internal Action? DuringTimestamp;
        public override DateTimeOffset GetUtcNow() => _now;
        public override long GetTimestamp() { var action = DuringTimestamp; DuringTimestamp = null; action?.Invoke(); return _now.UtcTicks + _timestampOffset; }
        public override long TimestampFrequency => TimeSpan.TicksPerSecond;
        internal void Advance(TimeSpan elapsed) => _now += elapsed;
        internal void ExpireNavigationTtl() => _timestampOffset += TimeSpan.TicksPerMinute * 5;
    }

    private sealed class Vault : ITokenVault
    {
        internal bool AllowSyntheticRefresh;
        public void SaveRefreshToken(string a, string b) { if (!AllowSyntheticRefresh) throw new Exception("Unexpected storage write"); }
        public string? LoadRefreshToken(string a) => AllowSyntheticRefresh ? "synthetic-refresh" : null;
        public string? LoadActiveAccountKey() => AllowSyntheticRefresh ? "fixture-scm:fixture-owner" : null;
        public void DeleteRefreshToken(string a) => throw new Exception("Unexpected storage delete");
    }

    private sealed class Handler(Clock clock) : HttpMessageHandler
    {
        internal int Bootstraps, Pages, Identities, RuntimeReads, BusinessReads, Refreshes, Activities;
        internal string Sid = "ASTER";
        internal long FleetId = 7;
        internal bool NoFleet;
        internal string? Failure;
        internal bool Visible;
        internal Action? DuringPage, DuringRuntime;
        internal string? NotificationSource = "officialFleet:7";
        internal TaskCompletionSource? BootstrapStarted, BootstrapRelease;
        internal TaskCompletionSource? PageStarted, PageRelease;
        internal TaskCompletionSource? G1Started, G1Release;
        internal TaskCompletionSource? SelfStarted, SelfRelease;
        internal TaskCompletionSource? RuntimeStarted, RuntimeRelease;
        internal Action? AfterG1;
        internal bool FailHeldPage;
        internal bool UnauthorizedG1Once;
        internal TaskCompletionSource? RefreshedG1Started, RefreshedG1Release, ActivityStarted, ActivityRelease;
        internal readonly List<string> PageQueries = [];
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            var path = request.RequestUri!.AbsolutePath;
            if (path == "/open-api/oauth2/token") {
                Refreshes++;
                return Ok(new { access_token = "synthetic-refreshed", refresh_token = "synthetic-next", token_type = "Bearer", expires_in = 3600 });
            }
            if (path == "/app-api/starbridge/v1/me") return Ok(new { subject = "fixture-owner", displayName = "Pilot",
                capabilities = new[] { "profile.read", "organizations.read" } });
            if (path == "/app-api/starbridge/v1/bootstrap")
            {
                Bootstraps++;
                var fleet = new ScmBootstrapFleet(FleetId, Sid, "Aster", null, true, "Officer", 4, []);
                if (BootstrapStarted is { } started) {
                    started.TrySetResult(); await BootstrapRelease!.Task.WaitAsync(token);
                }
                return Ok(new ScmBootstrapSnapshot(new(request.Headers.Authorization?.Parameter == "synthetic-other" ? "other-owner" : "fixture-owner", "Pilot", null, false), new(false, null),
                    NoFleet ? [] : [fleet], NoFleet ? null : fleet, 0, 1, new() { ["fleets"] = 1 },
                    clock.GetUtcNow(), ["profile.read", "organizations.read"]));
            }
            if (path == "/app-api/member/organization/member/page")
            {
                Pages++; PageQueries.Add(request.RequestUri.Query);
                if (PageStarted is { } started) {
                    PageStarted = null; started.TrySetResult(); await PageRelease!.Task.WaitAsync(token);
                    if (FailHeldPage) return Ok(new { code = 0, data = new { total = -1, list = Array.Empty<object>() } });
                }
                DuringPage?.Invoke();
                if (Failure == "page403") return new(HttpStatusCode.Forbidden);
                if (Failure == "pageInvalid") return Ok(new { code = 0, data = new { total = -1, list = Array.Empty<object>() } });
                return Ok(new { code = 0, data = new { total = 1, list = new[] {
                    new { userId = 101, nickname = "Pilot", organizationRank = "Member" } } } });
            }
            if (path == "/app-api/starbridge/v1/official-fleet/member-identities")
            {
                Identities++;
                if (G1Started is { } started) {
                    G1Started = null; started.TrySetResult(); await G1Release!.Task.WaitAsync(token);
                }
                if (UnauthorizedG1Once) { UnauthorizedG1Once = false; return new(HttpStatusCode.Unauthorized); }
                if (request.Headers.Authorization?.Parameter == "synthetic-refreshed" && RefreshedG1Started is { } refreshed) {
                    RefreshedG1Started = null; refreshed.TrySetResult(); await RefreshedG1Release!.Task.WaitAsync(token);
                }
                if (Failure == "g1") return new(HttpStatusCode.ServiceUnavailable);
                if (Failure == "auth") throw new ScmApiAuthenticationException("Synthetic rejection");
                using var body = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
                var source = body.RootElement.GetProperty("sourceRef").GetString();
                var version = body.RootElement.GetProperty("schemaVersion").GetInt32();
                object member = Visible
                    ? new { memberId = 101, state = "visible", businessSubjectId = "scm-v1:" + new string('a', 64), callsign = "Pilot" }
                    : new { memberId = 101, state = "unlinked" };
                var after = AfterG1; AfterG1 = null;
                if (version == 1) return new CompletedResponse(new { schemaVersion = 1, sourceRef = source, members = new[] { member } }, after);
                var row = JsonSerializer.SerializeToNode(member)!.AsObject();
                row["identityObservedAtUtc"] = clock.GetUtcNow().ToString("O");
                row["identityValidUntilUtc"] = clock.GetUtcNow().AddSeconds(5).ToString("O");
                return new CompletedResponse(new { schemaVersion = 2, sourceRef = source, members = new[] { row } }, after);
            }
            if (path == "/api/official-fleets/realtime/activity") {
                Activities++;
                if (ActivityStarted is { } started) {
                    ActivityStarted = null; started.TrySetResult(); await ActivityRelease!.Task.WaitAsync(token);
                }
                if (Failure == "activity401") return new(HttpStatusCode.Unauthorized);
                using var body = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
                return Ok(new { schemaVersion = 4, sourceRef = body.RootElement.GetProperty("sourceRef").GetString(), changed = true });
            }
            if (path == "/api/official-fleets/realtime/read") {
                RuntimeReads++;
                if (RuntimeStarted is { } started) {
                    RuntimeStarted = null; started.TrySetResult(); await RuntimeRelease!.Task.WaitAsync(token);
                }
                DuringRuntime?.Invoke();
                if (Failure == "runtime401") return new(HttpStatusCode.Unauthorized);
                using var body = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
                return Ok(new { schemaVersion = 4, sourceRef = body.RootElement.GetProperty("sourceRef").GetString(),
                    coverage = "requestedOwners", requestedOwnerCount = 0, members = Array.Empty<object>(),
                    supportedFilters = new[] { "all" }, runtimeCapabilities = new {
                        presence = true, server = true, ship = true, location = true, onlineCount = false, inGameCount = false } });
            }
            if (path == "/app-api/starbridge/v1/business-identity") {
                BusinessReads++;
                if (SelfStarted is { } started) {
                    SelfStarted = null; started.TrySetResult(); await SelfRelease!.Task.WaitAsync(token);
                    if (Failure == "self401") return new(HttpStatusCode.Unauthorized);
                    return Ok(new { schemaVersion = 1, subject = "fixture-owner", issuer = "fixture",
                        businessSubjectId = "scm-v1:" + new string('a', 64), scopes = new[] { "profile.read" } });
                }
                return new(HttpStatusCode.ServiceUnavailable);
            }
            if (path == "/api/official-fleets/context")
                return NotificationSource is null ? new(HttpStatusCode.Forbidden) : Ok(new {
                    schemaVersion = 1, sourceRef = NotificationSource, fleetCode = NotificationSource.ToUpperInvariant(),
                    name = "Aster", chatAvailable = true, canManageAnnouncements = false });
            if (path.StartsWith("/api/", StringComparison.Ordinal)) return new(HttpStatusCode.NotFound);
            throw new Exception("Unexpected mock route: " + path);
        }
        private static HttpResponseMessage Ok(object value) => new(HttpStatusCode.OK) { Content = JsonContent.Create(value) };
    }

    // Dispose occurs after the real OAuth parser has consumed the G1 response.
    private sealed class CompletedResponse : HttpResponseMessage
    {
        private Action? _completed;
        internal CompletedResponse(object value, Action? completed) : base(HttpStatusCode.OK)
        { Content = JsonContent.Create(value); _completed = completed; }
        protected override void Dispose(bool disposing)
        { base.Dispose(disposing); if (disposing) Interlocked.Exchange(ref _completed, null)?.Invoke(); }
    }

    private sealed class Fixture : IDisposable
    {
        internal readonly Clock Clock = new();
        internal readonly Handler Handler;
        internal readonly ScmAccountBridgeHost Host;
        internal readonly OAuthPkceClient OAuth;
        internal readonly CommunityClient Communities;
        internal readonly Vault Vault = new();
        internal Fixture()
        {
            Handler = new(Clock);
            var options = new ScmOAuthOptions("fixture-scm", new("http://127.0.0.1:3000/"),
                new("http://127.0.0.1:18080/"), new("http://127.0.0.1:18082/"),
                "starbridge-desktop", "starbridge-api", "organizations.read", "/oauth/callback");
            OAuth = new(new ScmHttpClient(Handler), Vault, options) {
                SessionClock = Clock, OfficialFleetIdentityObservationClock = Clock };
            var session = new ScmOAuthSession("fixture-scm", "fixture-owner", "Pilot", "synthetic-access",
                Clock.GetUtcNow().AddHours(3), ["organizations.read", "profile.read"]);
            Communities = new(new Uri("https://mock.example.invalid/"), Handler, Clock);
            Host = new(OAuth, new ScmProfileCacheStore(Path.GetTempPath()), "fixture", () => null,
                initialSession: session, initialGeneration: 1, communities: Communities);
        }
        internal Task<object> Read(string source = "officialFleet:7") => Host.GetOfficialFleetMembersAsync(
            Host.CurrentContext!, JsonSerializer.SerializeToElement(new {
                schemaVersion = 1, sourceRef = source, search = "", filter = "all", pageNumber = 1, pageSize = 50 }), default);
        internal Task<object> ReadRuntime(string source = "officialFleet:7") => Host.GetOfficialFleetRuntimeMembersAsync(
            Host.CurrentContext!, JsonSerializer.SerializeToElement(new {
                schemaVersion = 2, sourceRef = source, search = "", filter = "all", pageNumber = 1, pageSize = 50 }), default);
        internal Task<object> WaitRuntime() => Host.WaitOfficialFleetRuntimeActivityAsync(
            Host.CurrentContext!, JsonSerializer.SerializeToElement(new {
                schemaVersion = 2, sourceRef = "officialFleet:7", search = "", filter = "all", pageNumber = 1, pageSize = 50 }), default);
        internal void Runtime() {
            // Only this in-memory mock Host is configured; no environment/product switch changes.
            Host.ConfigurePrivacyWriter(new PrivacyRelayWriter(new Uri("https://mock.example.invalid/"), Handler));
            Host.ConfigureOfficialRealtime(true);
        }
        internal ScmOAuthSession Session => (ScmOAuthSession)Field(Host, "_session")!;
        internal void ReplaceSession(ScmOAuthSession session) {
            SetField(Host, "_session", session); SetField(OAuth, "_currentSession", session);
        }
        internal void Publish(ScmOAuthSession? session) {
            typeof(ScmAccountBridgeHost).GetMethod("PublishSession", BindingFlags.NonPublic | BindingFlags.Instance)!
                .Invoke(Host, [session, false, null, false, null, null, null, null]);
            SetField(OAuth, "_currentSession", session);
        }
        public void Dispose() { Host.Dispose(); Handler.Dispose(); }
    }

    private static void Equal(int expected, int actual, string message)
    {
        if (expected != actual) throw new InvalidOperationException($"{message}: expected {expected}, got {actual}");
    }

    private static object? Field(object target, string name) => target.GetType()
        .GetField(name, BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(target);
    private static void SetField(object target, string name, object? value) => target.GetType()
        .GetField(name, BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(target, value);
    private static async Task Reject(Func<Task<object>> action) {
        try { await action(); } catch (AccountBridgeHostException) { return; }
        throw new InvalidOperationException("Expected fail-closed member read");
    }
    private static void NoNavigation(Fixture f) {
        if (Field(f.Host, "_fleetNavigation") is not null) throw new InvalidOperationException("Navigation was retained");
    }

    private sealed class OverlayReader : IOverlayCommunityReader, IOverlayFleetReader
    {
        public Task<IReadOnlyList<OverlayCommunityTarget>> ReadTargetsAsync(BridgeAccountContext owner, CancellationToken token) => throw new Exception("Unexpected overlay read");
        public Task<InformationOverlayCommunityContent> ReadContentAsync(BridgeAccountContext owner, OverlayCommunityTarget target, CancellationToken token) => throw new Exception("Unexpected overlay read");
        public Task<OverlayCommunityTarget?> ReadFleetTargetAsync(BridgeAccountContext owner, CancellationToken token) => throw new Exception("Unexpected overlay read");
        public Task<InformationOverlayCommunityContent> ReadFleetContentAsync(BridgeAccountContext owner, OverlayCommunityTarget target,
            Action<InformationOverlayCommunityContent>? ready, bool communication, CancellationToken token) => throw new Exception("Unexpected overlay read");
        public Task<OverlayActivityCursor> WaitFleetChangesAsync(BridgeAccountContext owner, long generation, OverlayActivityCursor after, CancellationToken token) => throw new Exception("Unexpected overlay wait");
    }

    internal static async Task ObservationOrder()
    {
        using var f = new Fixture();
        using var overlay = new OverlayCommunitySource(() => (f.Host.CurrentContext, f.Host.Generation), new OverlayReader(), false);
        var snapshot = new AnnouncementObservationStore.Snapshot();
        var slot = AnnouncementObservationStore.Slot("official", true);
        var observations = new List<string?>();
        f.Host.FleetMembershipObserved = (owner, generation, source) => {
            observations.Add(source);
            snapshot.Observe(slot, source is null ? null : AnnouncementObservationStore.Binding(source, "fixture"), true);
            overlay.ObserveFleetMembership(owner, generation, source);
        };
        await f.Read();
        // Reuse has captured its local entry when it asks the monotonic clock for
        // its age. Complete a real departure before that cached read can resume.
        f.Clock.DuringTimestamp = () => f.Host.ObserveFleetNotificationMembership(f.Host.CurrentContext!, f.Host.Generation, null);
        await Reject(() => f.Read());
        var fleetOverlay = Field(overlay, "_fleetSource")!;
        if (snapshot.Slots[slot].Active || Field(fleetOverlay, "_fleetNotMember") is not true)
            throw new Exception("Old cached source restored announcement membership or overlay _fleetNotMember");
        if (!observations.SequenceEqual(new string?[] { "officialFleet:7", null }))
            throw new Exception("Only the real bootstrap and departure may be observed, in that order");
    }

    internal static async Task BootstrapSessionRotation()
    {
        using var f = new Fixture();
        var observed = new List<string?>();
        f.Host.FleetMembershipObserved = (_, _, source) => observed.Add(source);
        f.Handler.BootstrapStarted = new(TaskCreationOptions.RunContinuationsAsynchronously);
        f.Handler.BootstrapRelease = new(TaskCreationOptions.RunContinuationsAsynchronously);
        var pending = f.Read();
        await f.Handler.BootstrapStarted.Task.WaitAsync(TimeSpan.FromSeconds(5));
        // The resource response belongs to V1, but metadata publication sees V2.
        SetField(f.OAuth, "_currentSession", f.Session with { CredentialVersion = Guid.NewGuid() });
        f.Handler.Sid = "ROTATED";
        f.Handler.BootstrapRelease.SetResult();
        await Reject(() => pending); NoNavigation(f);
        Equal(0, observed.Count, "Old snapshot cannot publish membership under V2");
        await f.Read(); await f.Read();
        Equal(2, f.Handler.Bootstraps, "Only a real V2 response may fill navigation");
        if (f.Handler.PageQueries.Any(q => !q.Contains("organizationSid=ROTATED"))) throw new Exception("V1 SID used as V2 navigation");
    }

    internal static async Task EquivalentRefresh()
    {
        using var f = new Fixture(); await f.Read();
        f.Handler.PageStarted = new(TaskCreationOptions.RunContinuationsAsynchronously);
        f.Handler.PageRelease = new(TaskCreationOptions.RunContinuationsAsynchronously);
        var started = f.Handler.PageStarted;
        var pending = f.Read(); await started.Task.WaitAsync(TimeSpan.FromSeconds(5));
        f.Clock.Advance(TimeSpan.FromMinutes(5));
        try { await f.Read(); }
        finally { f.Handler.PageRelease.TrySetResult(); }
        await pending;
        await f.Read();
        Equal(2, f.Handler.Bootstraps, "Equivalent TTL refresh preserves both reads and the replacement cache");
        Equal(4, f.Handler.Identities, "All successful reads perform their own G1");
    }

    internal static async Task FailureOwnsOnlyItsEntry()
    {
        using var f = new Fixture(); await f.Read();
        f.Handler.FailHeldPage = true;
        f.Handler.PageStarted = new(TaskCreationOptions.RunContinuationsAsynchronously);
        f.Handler.PageRelease = new(TaskCreationOptions.RunContinuationsAsynchronously);
        var started = f.Handler.PageStarted;
        var pending = f.Read(); await started.Task.WaitAsync(TimeSpan.FromSeconds(5));
        f.Clock.Advance(TimeSpan.FromMinutes(5));
        try { await f.Read(); }
        finally { f.Handler.PageRelease.TrySetResult(); }
        await Reject(() => pending);
        await f.Read();
        Equal(2, f.Handler.Bootstraps, "A failed old page must not clear another request's refreshed entry");
    }

    internal static async Task SameSourceObservationDuringBootstrap()
    {
        foreach (var expired in new[] { false, true }) {
            using var f = new Fixture();
            var observations = new List<string?>();
            f.Host.FleetMembershipObserved = (_, _, source) => observations.Add(source);
            if (expired) { await f.Read(); f.Clock.Advance(TimeSpan.FromMinutes(5)); }
            f.Handler.BootstrapStarted = new(TaskCreationOptions.RunContinuationsAsynchronously);
            f.Handler.BootstrapRelease = new(TaskCreationOptions.RunContinuationsAsynchronously);
            var pending = f.Read(); await f.Handler.BootstrapStarted.Task.WaitAsync(TimeSpan.FromSeconds(5));
            f.Host.ObserveFleetNotificationMembership(f.Host.CurrentContext!, f.Host.Generation, "officialFleet:7");
            var count = observations.Count;
            f.Handler.BootstrapRelease.SetResult();
            await pending;
            Equal(count, observations.Count, "Bootstrap must not publish after a newer same-source observation");
            NoNavigation(f);
            await f.Read(); await f.Read();
            Equal(expired ? 3 : 2, f.Handler.Bootstraps, "Newer observation prevents old cache fill but permits this read");
        }
    }

    internal static async Task UnauthorizedRefreshAndReauthorization()
    {
        foreach (var reauthorize in new[] { false, true }) {
            using var f = new Fixture(); await f.Read();
            f.Vault.AllowSyntheticRefresh = true;
            f.Handler.UnauthorizedG1Once = true;
            f.Handler.RefreshedG1Started = new(TaskCreationOptions.RunContinuationsAsynchronously);
            f.Handler.RefreshedG1Release = new(TaskCreationOptions.RunContinuationsAsynchronously);
            var started = f.Handler.RefreshedG1Started;
            var pending = f.Read(); await started.Task.WaitAsync(TimeSpan.FromSeconds(5));
            Equal(1, f.Handler.Refreshes, "Real resource 401 refreshes once before retry");
            if (reauthorize) {
                // Model the already verified reauthorization commit, without a
                // browser, real credentials or a persistent vault.
                f.Publish(f.Session with { CredentialVersion = Guid.NewGuid(), AccessToken = "synthetic-reauthorized" });
                f.Handler.Sid = "REAUTHORIZED";
                await f.Read();
            }
            f.Handler.RefreshedG1Release.SetResult();
            if (reauthorize) await Reject(() => pending); else await pending;
            await f.Read(); await f.Read();
            Equal(2, f.Handler.Bootstraps, "Refreshed/reauthorized session gets its own navigation once");
            Equal(1, f.Handler.Refreshes, "Late request cannot rotate the replacement session");
            Equal(reauthorize ? 6 : 5, f.Handler.Identities, "Each round and 401 retry reads G1 independently");
        }
    }

    internal static async Task ActivityWaitRefreshAndOwner()
    {
        foreach (var boundary in new[] { "ttl", "reauthorize", "g1" }) {
            using var f = new Fixture(); f.Runtime(); await f.ReadRuntime();
            f.Handler.ActivityStarted = new(TaskCreationOptions.RunContinuationsAsynchronously);
            f.Handler.ActivityRelease = new(TaskCreationOptions.RunContinuationsAsynchronously);
            var started = f.Handler.ActivityStarted;
            var pending = f.WaitRuntime(); await started.Task.WaitAsync(TimeSpan.FromSeconds(5));
            Equal(2, f.Handler.Identities, "Wait enters with its own real G1 observation");
            if (boundary == "ttl") f.Clock.Advance(TimeSpan.FromMinutes(5));
            if (boundary == "reauthorize") f.Publish(f.Session with { CredentialVersion = Guid.NewGuid() });
            if (boundary != "g1") await f.ReadRuntime();
            else f.Handler.Failure = "g1";
            f.Handler.ActivityRelease.SetResult();
            if (boundary == "ttl") {
                await pending;
                Equal(4, f.Handler.Identities, "Expired pre-wait G1 is replaced with final G1, even across TTL refresh");
            } else await Reject(() => pending);
            f.Handler.Failure = null;
            await f.ReadRuntime();
            Equal(2, f.Handler.Bootstraps, "Wait failure only clears its own entry; current owner reuses navigation");
            Equal(1, f.Handler.Activities, "One authenticated activity wait");
        }
    }

    internal static async Task LeaveDuringG1()
    {
        foreach (var mode in new[] { "page", "runtime", "wait" }) {
            using var f = new Fixture();
            if (mode != "page") f.Runtime();
            f.Handler.Visible = true;
            f.Handler.G1Started = new(TaskCreationOptions.RunContinuationsAsynchronously);
            f.Handler.G1Release = new(TaskCreationOptions.RunContinuationsAsynchronously);
            var started = f.Handler.G1Started;
            var pending = mode == "page" ? f.Read() : mode == "runtime" ? f.ReadRuntime() : f.WaitRuntime();
            await started.Task.WaitAsync(TimeSpan.FromSeconds(5));
            f.Host.ObserveFleetNotificationMembership(f.Host.CurrentContext!, f.Host.Generation, null);
            f.Handler.G1Release.SetResult();
            await RejectRevoked(pending); NoNavigation(f);
            Equal(1, f.Handler.Identities, mode + " sends only the in-flight G1");
            Equal(0, f.Handler.BusinessReads, mode + " cannot send self identity after leave");
            Equal(0, f.Handler.RuntimeReads, mode + " cannot send relay after leave");
            Equal(0, f.Handler.Activities, mode + " cannot start activity wait after leave");
        }
    }

    internal static async Task LeaveDuringSelf()
    {
        using var f = new Fixture(); f.Handler.Visible = true;
        f.Handler.SelfStarted = new(TaskCreationOptions.RunContinuationsAsynchronously);
        f.Handler.SelfRelease = new(TaskCreationOptions.RunContinuationsAsynchronously);
        var started = f.Handler.SelfStarted;
        var pending = f.Read(); await started.Task.WaitAsync(TimeSpan.FromSeconds(5));
        f.Host.ObserveFleetNotificationMembership(f.Host.CurrentContext!, f.Host.Generation, null);
        f.Handler.SelfRelease.SetResult();
        await RejectRevoked(pending); NoNavigation(f);
        Equal(1, f.Handler.BusinessReads, "No request follows revoked self identity");
        Equal(1, f.Handler.Pages, "No second public page after revoked self identity");
        Equal(1, f.Handler.Identities, "No second G1 after revoked self identity");
    }

    internal static async Task LeaveDuringRuntimeAndWait()
    {
        foreach (var phase in new[] { "beforeRelay", "relay", "wait", "waitG1" }) {
            using var f = new Fixture(); f.Runtime();
            void Leave() => f.Host.ObserveFleetNotificationMembership(f.Host.CurrentContext!, f.Host.Generation, null);
            Task<object> pending;
            if (phase == "beforeRelay") { f.Handler.AfterG1 = Leave; pending = f.ReadRuntime(); }
            else if (phase == "relay") {
                f.Handler.RuntimeStarted = new(TaskCreationOptions.RunContinuationsAsynchronously);
                f.Handler.RuntimeRelease = new(TaskCreationOptions.RunContinuationsAsynchronously);
                var started = f.Handler.RuntimeStarted; pending = f.ReadRuntime();
                await started.Task.WaitAsync(TimeSpan.FromSeconds(5));
                Leave(); f.Handler.RuntimeRelease.SetResult();
            } else {
                f.Handler.ActivityStarted = new(TaskCreationOptions.RunContinuationsAsynchronously);
                f.Handler.ActivityRelease = new(TaskCreationOptions.RunContinuationsAsynchronously);
                var started = f.Handler.ActivityStarted; pending = f.WaitRuntime();
                await started.Task.WaitAsync(TimeSpan.FromSeconds(5));
                if (phase == "waitG1") {
                    f.Handler.G1Started = new(TaskCreationOptions.RunContinuationsAsynchronously);
                    f.Handler.G1Release = new(TaskCreationOptions.RunContinuationsAsynchronously);
                    var g1 = f.Handler.G1Started; f.Handler.ActivityRelease.SetResult();
                    await g1.Task.WaitAsync(TimeSpan.FromSeconds(5));
                    Leave(); f.Handler.G1Release.SetResult();
                } else { Leave(); f.Handler.ActivityRelease.SetResult(); }
            }
            await RejectRevoked(pending); NoNavigation(f);
            Equal(phase == "waitG1" ? 2 : 1, f.Handler.Identities, phase + " stops following G1 reads");
            Equal(phase == "relay" ? 1 : 0, f.Handler.RuntimeReads, phase + " stops following relay reads");
            Equal(phase.StartsWith("wait") ? 1 : 0, f.Handler.Activities, phase + " stops following activity waits");
        }
    }

    internal static async Task EquivalentRefreshAtLaterStages()
    {
        // Advance only the navigation's monotonic age. G1 UTC proofs remain
        // current, so this tests TTL replacement rather than permission expiry.
        foreach (var phase in new[] { "g1-page", "g1-runtime", "g1-wait", "self", "relay", "wait", "waitG1" }) {
            using var f = new Fixture(); f.Runtime();
            Task<object> pending; Task started; Action release;
            if (phase.StartsWith("g1-")) {
                f.Handler.G1Started = new(TaskCreationOptions.RunContinuationsAsynchronously);
                f.Handler.G1Release = new(TaskCreationOptions.RunContinuationsAsynchronously);
                started = f.Handler.G1Started.Task; release = () => f.Handler.G1Release.SetResult();
                pending = phase == "g1-page" ? f.Read() : phase == "g1-runtime" ? f.ReadRuntime() : f.WaitRuntime();
            } else if (phase == "self") {
                f.Handler.Visible = true;
                f.Handler.SelfStarted = new(TaskCreationOptions.RunContinuationsAsynchronously);
                f.Handler.SelfRelease = new(TaskCreationOptions.RunContinuationsAsynchronously);
                started = f.Handler.SelfStarted.Task; release = () => f.Handler.SelfRelease.SetResult(); pending = f.Read();
            } else if (phase == "relay") {
                f.Handler.RuntimeStarted = new(TaskCreationOptions.RunContinuationsAsynchronously);
                f.Handler.RuntimeRelease = new(TaskCreationOptions.RunContinuationsAsynchronously);
                started = f.Handler.RuntimeStarted.Task; release = () => f.Handler.RuntimeRelease.SetResult(); pending = f.ReadRuntime();
            } else {
                f.Handler.ActivityStarted = new(TaskCreationOptions.RunContinuationsAsynchronously);
                f.Handler.ActivityRelease = new(TaskCreationOptions.RunContinuationsAsynchronously);
                started = f.Handler.ActivityStarted.Task; release = () => f.Handler.ActivityRelease.SetResult(); pending = f.WaitRuntime();
                if (phase == "waitG1") {
                    await started.WaitAsync(TimeSpan.FromSeconds(5));
                    f.Handler.G1Started = new(TaskCreationOptions.RunContinuationsAsynchronously);
                    f.Handler.G1Release = new(TaskCreationOptions.RunContinuationsAsynchronously);
                    release(); started = f.Handler.G1Started.Task; release = () => f.Handler.G1Release.SetResult();
                }
            }
            await started.WaitAsync(TimeSpan.FromSeconds(5));
            f.Clock.ExpireNavigationTtl(); f.Handler.Visible = false;
            await f.ReadRuntime();
            Equal(2, f.Handler.Bootstraps, phase + " refreshes the same source/Sid once");
            release(); var result = JsonSerializer.SerializeToElement(await pending);
            if (phase is "g1-wait" or "wait" or "waitG1") {
                if (!result.GetProperty("changed").GetBoolean()) throw new Exception("Missing activity hint after TTL refresh");
            } else Equal(1, result.GetProperty("members").GetArrayLength(), phase + " still returns members");
            Equal(phase is "g1-wait" or "wait" or "waitG1" ? 3 : 2, f.Handler.Identities, phase + " never reuses G1");
            await f.ReadRuntime(); Equal(2, f.Handler.Bootstraps, phase + " preserves the refreshed cache");
        }
    }

    internal static async Task RevokedAuthenticationDoesNotRefresh()
    {
        foreach (var phase in new[] { "g1", "self", "relay", "wait" }) {
            using var f = new Fixture(); f.Runtime(); f.Vault.AllowSyntheticRefresh = true;
            Task<object> pending; Task started; Action release;
            if (phase == "g1") {
                f.Handler.UnauthorizedG1Once = true;
                f.Handler.G1Started = new(TaskCreationOptions.RunContinuationsAsynchronously);
                f.Handler.G1Release = new(TaskCreationOptions.RunContinuationsAsynchronously);
                started = f.Handler.G1Started.Task; release = () => f.Handler.G1Release.SetResult(); pending = f.Read();
            } else if (phase == "self") {
                f.Handler.Visible = true; f.Handler.Failure = "self401";
                f.Handler.SelfStarted = new(TaskCreationOptions.RunContinuationsAsynchronously);
                f.Handler.SelfRelease = new(TaskCreationOptions.RunContinuationsAsynchronously);
                started = f.Handler.SelfStarted.Task; release = () => f.Handler.SelfRelease.SetResult(); pending = f.Read();
            } else if (phase == "relay") {
                f.Handler.Failure = "runtime401";
                f.Handler.RuntimeStarted = new(TaskCreationOptions.RunContinuationsAsynchronously);
                f.Handler.RuntimeRelease = new(TaskCreationOptions.RunContinuationsAsynchronously);
                started = f.Handler.RuntimeStarted.Task; release = () => f.Handler.RuntimeRelease.SetResult(); pending = f.ReadRuntime();
            } else {
                f.Handler.Failure = "activity401";
                f.Handler.ActivityStarted = new(TaskCreationOptions.RunContinuationsAsynchronously);
                f.Handler.ActivityRelease = new(TaskCreationOptions.RunContinuationsAsynchronously);
                started = f.Handler.ActivityStarted.Task; release = () => f.Handler.ActivityRelease.SetResult(); pending = f.WaitRuntime();
            }
            await started.WaitAsync(TimeSpan.FromSeconds(5));
            f.Host.ObserveFleetNotificationMembership(f.Host.CurrentContext!, f.Host.Generation, null);
            release(); await RejectRevoked(pending);
            Equal(0, f.Handler.Refreshes, phase + " revoked 401 cannot start authentication refresh/retry");
            Equal(1, f.Handler.Identities, phase + " no follow-up G1");
        }
    }

    private static async Task RejectRevoked(Task<object> pending)
    {
        try { await pending; }
        catch (AccountBridgeHostException error) when (error.Code == "official_fleet.data_invalid") { return; }
        throw new InvalidOperationException("Revoked navigation must not return former member data");
    }

    internal static async Task Hour()
    {
        using var f = new Fixture();
        var observed = 0;
        f.Host.FleetMembershipObserved = (_, _, source) => { if (source == "officialFleet:7") observed++; };
        // 660 polls in [0, 1h), on exact five-minute boundaries without wall-clock sleeps.
        for (var poll = 0; poll < 660; poll++)
        {
            await f.Read();
            f.Clock.Advance(TimeSpan.FromTicks(TimeSpan.TicksPerHour / 660));
        }
        Equal(660, f.Handler.Pages, "Every poll still reads member/page");
        Equal(660, f.Handler.Identities, "Every poll still reads Java G1");
        Equal(12, observed, "Only real bootstrap results inform membership observers; cache hits emit zero");
        // Tick rounding may put the first poll after a boundary one interval later.
        Equal(12, f.Handler.Bootstraps, "One hour bootstrap navigation reads");
        Console.WriteLine($"POLL-NAV hour bootstrap={f.Handler.Bootstraps}, member/page={f.Handler.Pages}, G1={f.Handler.Identities}, observations={observed}");
    }

    internal static async Task Boundaries()
    {
        foreach (var kind in new[] { "account", "generation", "session", "rotation", "retirement" }) {
            using var f = new Fixture(); await f.Read();
            var session = f.Session;
            f.Handler.Sid = "NEW-SID";
            switch (kind) {
                case "account": f.Publish(session with { Subject = "other-owner", AccessToken = "synthetic-other", CredentialVersion = Guid.NewGuid() }); break;
                case "generation": f.Publish(session); break;
                case "session": f.ReplaceSession(session with { CredentialVersion = Guid.NewGuid() }); break;
                case "rotation": SetField(f.OAuth, "_currentSession", session with { CredentialVersion = Guid.NewGuid() }); break;
                case "retirement":
                    f.Publish(null); NoNavigation(f); f.Publish(session with { CredentialVersion = Guid.NewGuid() }); break;
            }
            await f.Read();
            Equal(2, f.Handler.Bootstraps, "Boundary bootstrap: " + kind);
            if (!f.Handler.PageQueries.Last().Contains("organizationSid=NEW-SID")) throw new Exception("Old SID after " + kind);
        }
        using (var f = new Fixture()) {
            await f.Read(); f.Handler.FleetId = 8; f.Handler.Sid = "NEXT";
            await f.Read("officialFleet:8");
            Equal(2, f.Handler.Bootstraps, "Changed source rechecks bootstrap");
            if (!f.Handler.PageQueries.Last().Contains("organizationSid=NEXT")) throw new Exception("Cross-fleet SID reused");
        }
        using (var f = new Fixture()) {
            await f.Read(); f.Handler.NoFleet = true;
            f.Host.ObserveFleetNotificationMembership(f.Host.CurrentContext!, f.Host.Generation, null);
            NoNavigation(f); await Reject(() => f.Read()); NoNavigation(f);
            Equal(2, f.Handler.Bootstraps, "Leaving rechecks bootstrap immediately");
            Equal(1, f.Handler.Pages, "Leaving does not use the old SID");
        }
        using (var f = new Fixture()) {
            await f.Read(); f.Host.Dispose(); NoNavigation(f);
            await Reject(() => f.Read()); Equal(1, f.Handler.Bootstraps, "Disposed Host admits no I/O");
            // Replacement owner, rather than a disposed Host, owns the next round.
            using var replacement = new Fixture(); replacement.Handler.Sid = "REPLACEMENT";
            await replacement.Read(); Equal(1, replacement.Handler.Bootstraps, "Replacement reads its own bootstrap");
        }
    }

    internal static async Task Failures()
    {
        foreach (var runtime in new[] { false, true }) foreach (var failure in new[] { "page403", "pageInvalid", "g1", "auth" }) {
            using var f = new Fixture(); if (runtime) f.Runtime();
            Task<object> Read() => runtime ? f.ReadRuntime() : f.Read();
            await Read();
            f.Handler.Failure = failure;
            await Reject(Read); NoNavigation(f);
            f.Handler.Failure = null; f.Handler.Sid = "RECOVERED";
            // A real authentication rejection may retire the session. Install a new
            // synthetic lifecycle explicitly, never recover from local storage.
            if (failure == "auth") f.Publish(new ScmOAuthSession("fixture-scm", "fixture-owner", "Pilot", "synthetic-access",
                f.Clock.GetUtcNow().AddHours(3), ["organizations.read", "profile.read"]));
            await Read();
            Equal(2, f.Handler.Bootstraps, "Failure requires bootstrap: " + failure);
            if (!f.Handler.PageQueries.Last().Contains("organizationSid=RECOVERED")) throw new Exception("Failed read reused SID");
        }
    }

    internal static async Task Lifetime()
    {
        using (var f = new Fixture()) {
            await f.Read(); f.Clock.Advance(TimeSpan.FromMinutes(5).Subtract(TimeSpan.FromTicks(1)));
            await f.Read(); Equal(1, f.Handler.Bootstraps, "Before TTL");
            f.Clock.Advance(TimeSpan.FromTicks(1)); f.Handler.Sid = "CHECKED";
            await f.Read(); Equal(2, f.Handler.Bootstraps, "Exact TTL");
        }
        foreach (var expired in new[] { false, true }) {
            using var f = new Fixture();
            f.ReplaceSession(f.Session with { ExpiresAt = f.Clock.GetUtcNow().AddMinutes(3) });
            await f.Read();
            // Change no session object/version; only the injected OAuth clock moves.
            f.Clock.Advance(TimeSpan.FromMinutes(expired ? 3 : 2));
            await Reject(() => f.Read()); NoNavigation(f);
            Equal(1, f.Handler.Pages, "Refresh/expiry cannot use cached SID before authentication");
            f.ReplaceSession(f.Session with { ExpiresAt = f.Clock.GetUtcNow().AddHours(3), CredentialVersion = Guid.NewGuid() });
            f.Handler.Sid = "FRESH"; await f.Read();
            Equal(2, f.Handler.Bootstraps, "Restored session rechecks navigation");
        }
        using (var f = new Fixture()) {
            await f.Read();
            // OAuth has expired a rejected version; the Host still holds its old metadata copy.
            SetField(f.OAuth, "_currentSession", f.Session with { ExpiresAt = DateTimeOffset.MinValue });
            await Reject(() => f.Read()); NoNavigation(f);
            Equal(1, f.Handler.Pages, "OAuth expiry is checked even before Host metadata catches up");
        }
    }

    internal static async Task RuntimeHour()
    {
        using var f = new Fixture(); f.Runtime();
        for (var poll = 0; poll < 660; poll++) {
            await f.ReadRuntime(); f.Clock.Advance(TimeSpan.FromTicks(TimeSpan.TicksPerHour / 660));
        }
        Equal(12, f.Handler.Bootstraps, "Runtime one-hour bootstrap reads");
        Equal(660, f.Handler.Pages, "Runtime pages unchanged");
        Equal(660, f.Handler.Identities, "Runtime G1 unchanged");
        Equal(660, f.Handler.RuntimeReads, "Runtime relay reads unchanged");
        Console.WriteLine("POLL-NAV runtime hour bootstrap=12, member/page=660, G1=660, relay=660");
    }

    internal static async Task NotificationsAndRaces()
    {
        using (var f = new Fixture()) {
            var changes = 0; f.Host.NotificationMembershipChanged += (_, _) => changes++;
            await f.Read(); await f.Read();
            Equal(1, f.Handler.Bootstraps, "Repeated observations preserve navigation");
            f.Handler.Sid = "NOTIFIED";
            f.Host.ObserveFleetNotificationMembership(f.Host.CurrentContext!, f.Host.Generation, "officialFleet:8");
            NoNavigation(f); Equal(1, changes, "Fresh membership change notification preserved");
            // Bootstrap now confirms the same new membership as the observer.
            f.Handler.FleetId = 8; await f.Read("officialFleet:8");
            Equal(2, f.Handler.Bootstraps, "Membership notification rechecks bootstrap");
        }
        using (var f = new Fixture()) {
            f.Handler.BootstrapStarted = new(TaskCreationOptions.RunContinuationsAsynchronously);
            f.Handler.BootstrapRelease = new(TaskCreationOptions.RunContinuationsAsynchronously);
            var first = f.Read(); await f.Handler.BootstrapStarted.Task;
            var second = f.Read(); f.Handler.BootstrapRelease.SetResult();
            await Task.WhenAll(first, second);
            Equal(1, f.Handler.Bootstraps, "Concurrent requests share only navigation bootstrap");
            Equal(2, f.Handler.Identities, "Concurrent G1 authorization remains separate");
        }
        using (var f = new Fixture()) {
            f.Handler.BootstrapStarted = new(TaskCreationOptions.RunContinuationsAsynchronously);
            f.Handler.BootstrapRelease = new(TaskCreationOptions.RunContinuationsAsynchronously);
            var pending = f.Read(); await f.Handler.BootstrapStarted.Task;
            f.Host.ObserveFleetNotificationMembership(f.Host.CurrentContext!, f.Host.Generation, null);
            f.Handler.BootstrapRelease.SetResult(); await Reject(() => pending); NoNavigation(f);
            Equal(0, f.Handler.Pages, "Late bootstrap cannot resurrect invalidated navigation");
        }
        using (var f = new Fixture()) {
            await f.Read();
            f.Handler.DuringPage = () => f.Host.ObserveFleetNotificationMembership(f.Host.CurrentContext!, f.Host.Generation, null);
            await Reject(() => f.Read()); NoNavigation(f);
            Equal(1, f.Handler.Identities, "Invalidated public page never reaches G1");
        }
        using (var f = new Fixture()) {
            await f.Read(); f.Handler.NotificationSource = null; f.Handler.NoFleet = true;
            // Real notification-reader observation remains active even when the
            // feed as a whole fails. No mounted page/overlay is required.
            try { await f.Host.ReadNotificationsAsync(f.Host.CurrentContext!, f.Host.Generation, default); }
            catch (AccountBridgeHostException) { }
            NoNavigation(f); await Reject(() => f.Read());
            Equal(2, f.Handler.Bootstraps, "Independent notification membership loss invalidates navigation");
            Equal(1, f.Handler.Pages, "Notification leave never uses the old SID");
        }
    }

    internal static async Task AuthorizationIsNotCached()
    {
        using (var f = new Fixture()) {
            f.Handler.Visible = true;
            // An optional self-identity failure is not membership evidence: the page
            // still returns (nobody marked as self) and navigation stays valid.
            await f.Read();
            Equal(1, f.Handler.BusinessReads, "Self identity read still runs");
            await f.Read();
            Equal(1, f.Handler.Bootstraps, "Optional self identity failure does not invalidate navigation");
            Equal(2, f.Handler.BusinessReads, "Failed self read is retried normally");
        }
        using (var f = new Fixture()) {
            f.Runtime(); await f.ReadRuntime();
            f.Handler.DuringRuntime = () => f.Clock.Advance(TimeSpan.FromSeconds(16));
            await Reject(() => f.ReadRuntime()); NoNavigation(f);
            Equal(1, f.Handler.Bootstraps, "Final G1 deadline failure happens during navigation reuse");
            Equal(2, f.Handler.Identities, "Fresh G1 requested on both rounds");
            f.Handler.DuringRuntime = null; await f.ReadRuntime();
            Equal(2, f.Handler.Bootstraps, "Final authorization failure rechecks navigation next round");
        }
    }
}
