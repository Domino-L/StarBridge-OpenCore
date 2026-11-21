using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Achievements;
using StarBridge.HostRuntime.Communities;
using StarBridge.HostRuntime.Notifications;
using StarBridge.NativeBridge;

internal static class AnnouncementRevisionTests
{
    private static readonly BridgeAccountContext Owner = new("fixture", "fixture", "f2-owner");
    private static readonly DateTimeOffset Day = new(2026, 11, 4, 0, 0, 0, TimeSpan.Zero);
    private static int _checks;
    private static void Check(bool condition, string message) { _checks++; if (!condition) throw new Exception(message); }
    private sealed class Clock : TimeProvider {
        internal DateTimeOffset Now = Day;
        public override DateTimeOffset GetUtcNow() => Now;
        public override long GetTimestamp() => Now.UtcTicks;
        public override long TimestampFrequency => TimeSpan.TicksPerSecond;
        public override TimeZoneInfo LocalTimeZone => TimeZoneInfo.Utc;
    }
    internal static async Task Run() {
        _checks = 0;
        var root = Path.Combine(Path.GetTempPath(), "sb-announce-f2-" + Guid.NewGuid().ToString("N"));
        try {
            await QuietRecovery(Path.Combine(root, "quiet"));
            await MembershipTransitions(Path.Combine(root, "membership"));
            await CommunityRevocation(Path.Combine(root, "community"));
            await DeferredAudio(Path.Combine(root, "audio"));
        } finally {
            if (!Path.GetFullPath(root).StartsWith(Path.TrimEndingDirectorySeparator(Path.GetFullPath(Path.GetTempPath())) +
                Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase)) throw new IOException();
            if (Directory.Exists(root)) Directory.Delete(root, true);
        }
        Console.WriteLine($"PASS CX-ANNOUNCE-F2: {_checks} assertions, 0 failed");
    }
    private static async Task QuietRecovery(string root) {
        foreach (var hour in new[] { 23, 21 }) {
            var path = Path.Combine(root, hour.ToString()); var clock = new Clock();
            var policy = NotificationPolicyStore.Organization("QUIET", Day.AddDays(-1));
            new NotificationPolicyStore(path).Save(Owner, 0, Guid.NewGuid().ToString("N"), [new(policy, NotificationSourceMode.Normal) {
                TypeRules = [new("announcement", "enabled")], QuietHours = new(true, 1320, 480)
            }], () => true, extended: true);
            using var settings = new NotificationSettingsBridgeDispatcher(path, () => 1, () => true, time: clock);
            CommunityNotificationFeed Page(DateTimeOffset received, bool publication) => new(received, [new("quiet", "Fixture", Day.AddDays(-1),
                false, null, false, [], policy, Announcements: new(received, publication ? [new("unseen", true, Day.AddHours(hour))] : []),
                AnnouncementSource: new string('a', 32), AnnouncementIdentity: "community:QUIET")]);
            var observer = settings.CreateAnnouncementObserver();
            Check(observer.Observe(Owner, 1, Page(Day.AddHours(20), false), () => true).Count == 0, "Initial baseline is quiet.");
            clock.Now = Day.AddDays(1).AddHours(8).AddMinutes(1);
            observer = settings.CreateAnnouncementObserver(); // durable reconnect/restart
            var result = observer.Observe(Owner, 1, Page(clock.Now, true), () => true);
            Check(hour == 23 ? result.Count == 0 : result is [{ AnnouncementSummaryCount: 1 }],
                $"22:00-08:00 quiet hours, publication at {hour}:00, recovery 08:01 must count {(hour == 23 ? 0 : 1)}.");
            Check(settings.CreateAnnouncementObserver().Observe(Owner, 1, Page(clock.Now.AddSeconds(1), true), () => true).Count == 0,
                "Both suppressed and admitted IDs are durably consumed.");
        }
        await Task.CompletedTask;
    }
    private sealed class Sink : IDesktopNotificationSink {
        internal readonly List<DesktopNotification> Notices = [];
        public ValueTask<bool> TryPresentAsync(DesktopNotification notice, CancellationToken token) {
            Notices.Add(notice); return ValueTask.FromResult(true);
        }
        public void Clear() { }
        public void Dispose() { }
    }
    private sealed class Vault : ITokenVault {
        public void SaveRefreshToken(string a, string b) => throw new Exception("Unexpected credential write");
        public string? LoadRefreshToken(string a) => null;
        public string? LoadActiveAccountKey() => null;
        public void DeleteRefreshToken(string a) => throw new Exception("Unexpected credential deletion");
    }
    private sealed class Handler(Clock clock) : HttpMessageHandler {
        internal int Fleet = 7;
        internal string? Id;
        internal bool MissingPublicationTime, AnnouncementDenied, DirectoryUnavailable;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) {
            Check(request.Method == HttpMethod.Get, "Only fake authorized GET projections are used.");
            var path = request.RequestUri!.AbsolutePath;
            if (path == "/api/fleets/notification-sources" && DirectoryUnavailable)
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.ServiceUnavailable));
            if (path == "/api/official-fleets/context" && Fleet == 0)
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.Forbidden));
            if (path.EndsWith("/chat/channels")) return Task.FromResult(new HttpResponseMessage(HttpStatusCode.ServiceUnavailable));
            if (path.EndsWith("/announcements") && AnnouncementDenied) return Task.FromResult(new HttpResponseMessage(HttpStatusCode.Forbidden));
            var source = "officialFleet:" + Fleet; var code = source.ToUpperInvariant();
            object body = path switch {
                "/api/fleets/notification-sources" => new { schemaVersion = 1, serverTime = clock.Now, sources = Array.Empty<object>() },
                "/api/official-fleets/context" => new { schemaVersion = 1, sourceRef = source, fleetCode = code,
                    name = "Fixture", chatAvailable = true, canManageAnnouncements = false },
                "/api/official-fleets/announcements" => new { schemaVersion = 1, membershipModelVersion = 2, fleetCode = code,
                    revision = 1, refreshedAt = clock.Now, offset = 0, next = (int?)null, totalHistoryCount = 0, history = Array.Empty<object>(),
                    current = Id == null ? null : new { announcement = new { id = Id, fleetCode = code, state = "Published", revision = 1,
                        publishedAt = MissingPublicationTime ? (DateTimeOffset?)null : clock.Now, updatedAt = clock.Now } } },
                _ => throw new Exception("Unexpected fixture route: " + path)
            };
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(body) });
        }
    }
    private static async Task EnableDesktop(NotificationSettingsBridgeDispatcher settings) {
        var result = await settings.DispatchAsync(BridgeEnvelope.Request("notificationSettings.save", "f2-desktop", 1,
            new { schemaVersion = 1, expectedRevision = 0, inAppEnabled = true, windowsEnabled = true, position = "bottomRight", preview = "fullContent" }));
        Check(result.Response.Status == "ok", "Fixture desktop channel is enabled only in isolated test data.");
    }
    private static async Task MembershipTransitions(string root) {
        var clock = new Clock(); using var handler = new Handler(clock);
        using var client = new CommunityClient(new("https://relay.invalid"), handler, clock);
        var options = new ScmOAuthOptions("fixture", new("http://127.0.0.1:3000/"), new("http://127.0.0.1:18080/"),
            new("http://127.0.0.1:18082/"), "fixture-client", "fixture-api", "organizations.read", "/oauth/callback");
        var session = new ScmOAuthSession("fixture", "f2-owner", "Fixture", "synthetic", DateTimeOffset.UtcNow.AddHours(1), ["organizations.read"]);
        using var host = new ScmAccountBridgeHost(new OAuthPkceClient(new ScmHttpClient(handler), new Vault(), options),
            new ScmProfileCacheStore(root), "fixture", () => null, initialSession: session, initialGeneration: 1, communities: client);
        var sink = new Sink();
        using var settings = new NotificationSettingsBridgeDispatcher(root, () => 1, () => true, desktop: sink, time: clock);
        await EnableDesktop(settings);
        var policy = NotificationPolicyStore.OfficialFleet("officialFleet:7");
        new NotificationPolicyStore(root).Save(host.GameplayTimeContext!, 0, Guid.NewGuid().ToString("N"),
            [new(policy, NotificationSourceMode.Normal) { TypeRules = [new("announcement", "enabled")] }], () => true, extended: true);
        using var account = new AccountBridgeRuntime(host);
        Check(account.ConfigureCommunityNotifications(settings), "Real account composition owns organization notifications.");
        var runtime = (CommunityNotificationRuntime)typeof(AccountBridgeRuntime).GetField("_communityNotifications",
            System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)!.GetValue(account)!;
        async Task Tick(string? id) { clock.Now = clock.Now.AddSeconds(1); handler.Id = id; await runtime.TickAsync(); }
        await Tick(null); await Tick("queued-A");
        Check(sink.Notices.Count == 1 && await sink.Notices[0].CanPresentAsync(default), "A fresh announcement can enter the celebration queue.");
        var queued = sink.Notices[0];
        handler.Fleet = 8;
        host.ObserveFleetNotificationMembership(host.GameplayTimeContext!, 1, "officialFleet:8");
        Check(!queued.IsCurrent() && !await queued.CanPresentAsync(default),
            "Confirmed A-to-B refresh retires A before the next notification poll or celebration end.");
        await Tick("B-history");
        handler.Fleet = 7;
        host.ObserveFleetNotificationMembership(host.GameplayTimeContext!, 1, "officialFleet:7");
        await Tick("offline-A");
        Check(sink.Notices.Count == 1, "A-to-B-to-A starts a new membership baseline without a summary.");
        await Tick("new-A");
        Check(sink.Notices.Count == 2, "Only newly published content after the rejoin baseline can notify.");
        handler.AnnouncementDenied = true;
        Check(await sink.Notices.Last().CanPresentAsync(default), "Dequeue uses the last confirmed local projection without a new network read.");
        await Tick("denied");
        Check(!await sink.Notices.Last().CanPresentAsync(default), "A polling-confirmed denial retires a queued announcement.");
        handler.AnnouncementDenied = false;
        handler.Fleet = 8;
        host.ObserveFleetNotificationMembership(host.GameplayTimeContext!, 1, "officialFleet:8");
        Check(!await sink.Notices.Last().CanPresentAsync(default), "A local membership observation retires the queued organization without another read.");
        handler.Fleet = 7;
        host.ObserveFleetNotificationMembership(host.GameplayTimeContext!, 1, null);
        host.ObserveFleetNotificationMembership(host.GameplayTimeContext!, 1, "officialFleet:7");
        await Tick("rejoined-A");
        Check(sink.Notices.Count == 2, "Departure and same-organization rejoin also establish quiet history.");
        handler.MissingPublicationTime = true;
        await Tick("unknown-date");
        Check(sink.Notices.Count == 2, "Missing first publication time is consumed without output.");
        handler.MissingPublicationTime = false;
        await Tick("unknown-date");
        Check(sink.Notices.Count == 2, "Adding a timestamp to an already consumed ID cannot replay it.");
        handler.Fleet = 0; handler.DirectoryUnavailable = true;
        await Tick("observed-departure-with-failed-feed");
        handler.Fleet = 7; handler.DirectoryUnavailable = false;
        await Tick("returned-after-failed-feed");
        Check(sink.Notices.Count == 2, "A confirmed departure persists even when both feed domains fail; returning to A cannot inherit its old baseline.");
        var held = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        var current = true;
        var raced = queued with { IsCurrent = () => current, RevalidateBeforePresent = _ => held.Task };
        var pending = raced.CanPresentAsync(default); current = false; held.SetResult(true);
        Check(!await pending, "Membership changed while authorization was in flight is checked again immediately before output.");
    }
    private sealed class Reader : ICommunityNotificationReader {
        internal CommunityNotificationFeed Feed = new(Day, []);
        public Task<CommunityNotificationFeed> ReadNotificationsAsync(BridgeAccountContext owner, long generation, CancellationToken token) => Task.FromResult(Feed);
    }
    private static async Task CommunityRevocation(string root) {
        var clock = new Clock(); var reader = new Reader(); var sink = new Sink();
        var policy = NotificationPolicyStore.Organization("A", Day.AddDays(-1));
        using var settings = new NotificationSettingsBridgeDispatcher(root, () => 1, () => true, desktop: sink, time: clock);
        await EnableDesktop(settings);
        new NotificationPolicyStore(root).Save(Owner, 0, Guid.NewGuid().ToString("N"),
            [new(policy, NotificationSourceMode.Normal) { TypeRules = [new("announcement", "enabled")] }], () => true, extended: true);
        using var runtime = new CommunityNotificationRuntime(reader, () => (Owner, 1), settings.PresentCommunityAsync, clock,
            announcements: settings.CreateAnnouncementObserver());
        async Task Tick(string id) {
            clock.Now = clock.Now.AddSeconds(1);
            reader.Feed = new(clock.Now, [new("A-source", "A", Day.AddDays(-1), false, null, false, [], policy,
                Announcements: new(clock.Now, [new(id, true, clock.Now)]), AnnouncementSource: new string('a', 32), AnnouncementIdentity: "community:A")]);
            await runtime.TickAsync();
        }
        await Tick("history"); await Tick("queued");
        var notice = sink.Notices.Single();
        runtime.RevokeCommunity(Owner, 2, "A");
        Check(notice.IsCurrent(), "A stale account generation cannot revoke a current reminder.");
        runtime.RevokeCommunity(Owner, 1, "A");
        Check(!notice.IsCurrent(), "Community membership revocation retires queued notices without polling.");
        await Tick("baseline"); await Tick("queued-again");
        notice = sink.Notices.Last();
        runtime.ConfirmCommunityDirectory(Owner, 1, ["B"]);
        Check(!notice.IsCurrent(), "Confirmed directory removal retires old-organization notices immediately.");
    }
    private sealed class Audio : INotificationAudioOutput {
        internal int Count;
        internal TaskCompletionSource Played = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public bool TryPlay(byte[] wave) { Count++; Played.TrySetResult(); return true; }
        public void Stop() { }
        public void Dispose() { }
    }
    private static readonly TimeSpan Hang = TimeSpan.FromSeconds(60);
    private static async Task Until(Func<bool> done) {
        var deadline = DateTime.UtcNow + Hang;
        while (!done()) {
            if (DateTime.UtcNow > deadline) throw new TimeoutException("Deferred audio state did not settle within the hang bound.");
            await Task.Delay(10);
        }
    }
    private static async Task DeferredAudio(string root) {
        Directory.CreateDirectory(root);
        var clock = new Clock(); var output = new Audio(); var celebration = new AchievementCelebrationActivity();
        var wave = NotificationAudioTests.Wave(); File.WriteAllBytes(Path.Combine(root, "notify.soft.wav"), wave);
        File.WriteAllText(Path.Combine(root, "cue-catalog.v1.json"), JsonSerializer.Serialize(new { schemaVersion = 1,
            assets = new[] { new { assetId = "notify.soft", cueId = "notify.soft", fileName = "notify.soft.wav", tier = "approved", priority = 320,
                sha256 = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(wave)) } } }));
        new NotificationAudioSettingsStore(root).Save(0, true, .5);
        var policy = NotificationPolicyStore.Organization("AUDIO", Day.AddDays(-1));
        new NotificationPolicyStore(root).Save(Owner, 0, Guid.NewGuid().ToString("N"),
            [new(policy, NotificationSourceMode.Normal) { TypeRules = [new("announcement", "enabled")] }], () => true, extended: true);
        using var audio = new NotificationAudioBridgeDispatcher(root, NotificationAudioCatalog.Load(root), output,
            () => 1, () => true, clock, celebration: celebration);
        var source = new CommunityNotificationSource("audio", "Audio", Day.AddDays(-1), false, null, false, [], policy,
            Announcements: new(Day, []), AnnouncementIdentity: "community:AUDIO");
        var requested = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var permission = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        var notice = new CommunityNotificationNotice(Owner, source, NotificationEventKind.OrganizationAnnouncement, () => true, Day,
            _ => { requested.TrySetResult(); return permission.Task; });
        celebration.Report(true);
        Check(!audio.TryPlayCommunity(notice) && output.Count == 0, "Celebration holds announcement audio.");
        celebration.Report(false); audio.DrainDeferred();
        // Waits below are signals or monotone state; the long bound only stops a hang, it does not decide the result.
        await requested.Task.WaitAsync(Hang);
        Check(output.Count == 0, "Deferred audio waits for fresh reading permission before playback.");
        permission.SetResult(false);
        var authorizationPending = typeof(NotificationAudioBridgeDispatcher).GetField("_audioAuthorizationPending",
            System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)!;
        await Until(() => !(bool)authorizationPending.GetValue(audio)!);
        Check(output.Count == 0, "Revoked reading permission finishes and discards deferred announcement audio.");
        // Permission is already granted when revalidation asks, so the dispatcher's own 3-second
        // revalidation timeout cannot expire while a busy machine delays this test's continuation.
        requested = new(TaskCreationOptions.RunContinuationsAsynchronously);
        permission = new(TaskCreationOptions.RunContinuationsAsynchronously);
        permission.SetResult(true);
        celebration.Report(true); audio.TryPlayCommunity(notice);
        Check(output.Count == 0, "Celebration holds the second announcement audio.");
        celebration.Report(false); audio.DrainDeferred();
        await output.Played.Task.WaitAsync(Hang);
        Check(requested.Task.IsCompleted, "Playback happened only after fresh reading permission was requested.");
        await Until(() => !(bool)authorizationPending.GetValue(audio)!);
        Check(output.Count == 1, "A still-authorized deferred announcement plays once after revalidation.");
    }
}
