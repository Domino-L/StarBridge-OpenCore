using System.Text.Json;
using StarBridge.HostRuntime.Communities;
using StarBridge.HostRuntime.Notifications;
using StarBridge.NativeBridge;

internal static class AnnouncementSummaryTests
{
    private static readonly BridgeAccountContext Owner = new("fixture", "fixture", "summary-synthetic-owner");
    private static readonly DateTimeOffset Day = new(2026, 11, 4, 12, 0, 0, TimeSpan.Zero);
    private static readonly string Policy = NotificationPolicyStore.Organization("SUMMARY", Day.AddDays(-1));
    private const string Identity = "community:SUMMARY";
    private static int _checks;
    private static void Check(bool value, string message) { _checks++; if (!value) throw new Exception(message); }
    private sealed class Clock : TimeProvider {
        internal DateTimeOffset Now = Day;
        public override DateTimeOffset GetUtcNow() => Now;
        public override long GetTimestamp() => Now.UtcTicks;
        public override long TimestampFrequency => TimeSpan.TicksPerSecond;
        public override TimeZoneInfo LocalTimeZone => TimeZoneInfo.Utc;
    }
    private static CommunityNotificationFeed Feed(int second, int count, bool withdrawn = false) =>
        new(Day.AddSeconds(second), [new("summary-source", "Synthetic organization", Day.AddDays(-1), false, null, false, [], Policy,
            Announcements: new(Day.AddSeconds(second), Enumerable.Range(0, count)
                .Select(i => new CommunityNotificationAnnouncement("id-" + i, !withdrawn || i != count - 1, Day)).ToArray()),
            AnnouncementSource: new string('a', 32), AnnouncementIdentity: Identity)]);
    internal static async Task Run() {
        _checks = 0;
        var root = Path.Combine(Path.GetTempPath(), "sb-summary-" + Guid.NewGuid().ToString("N"));
        try {
            Observe(Path.Combine(root, "observe"));
            foreach (var kind in new[] { "normal", "default", "disabled", "dnd", "important", "quiet", "official",
                "default-dnd", "default-important", "default-quiet", "default-official" })
                await Delivery(Path.Combine(root, kind), kind);
        } finally {
            if (!Path.GetFullPath(root).StartsWith(Path.TrimEndingDirectorySeparator(Path.GetFullPath(Path.GetTempPath())) + Path.DirectorySeparatorChar,
                StringComparison.OrdinalIgnoreCase)) throw new IOException();
            if (Directory.Exists(root)) Directory.Delete(root, true);
        }
        Console.WriteLine($"PASS CX-ANNOUNCE-SUMMARY: {_checks} assertions, 0 failed" );
    }
    private static void Observe(string root) {
        var clock = new Clock(); var store = new AnnouncementObservationStore(root);
        var observer = new AnnouncementNotificationObserver(store, clock);
        Check(observer.Observe(Owner, 1, Feed(0, 0), () => true).Count == 0, "An empty first-use page persists a quiet organization baseline.");
        clock.Now = Day.AddHours(2);
        observer = new(store, clock);
        var result = observer.Observe(Owner, 1, Feed(7200, 4, withdrawn: true), () => true);
        Check(result is [{ AnnouncementSummaryCount: 3 }], "A restart with three offline publications and a withdrawn record yields one summary, count 3.");
        var owner = AnnouncementObservationStore.Owner(Owner);
        Check(Enumerable.Range(0, 4).All(i => store.Read(owner).Contains(AnnouncementObservationStore.Key(owner, Identity, "id-" + i))),
            "All IDs, including withdrawn ones, are durably consumed before returning the summary.");
        Check(new AnnouncementNotificationObserver(store, clock).Observe(Owner, 1, Feed(7201, 4), () => true).Count == 0,
            "Edited IDs and a withdrawn ID reappearing do not replay after restart.");
        Check(observer.Observe(Owner with { Subject = "new-synthetic-owner" }, 2, Feed(7202, 5), () => true).Count == 0,
            "A new account cannot inherit a different account's baseline.");
        observer = new(store, clock);
        var different = Feed(7203, 5);
        different = different with { Sources = [different.Sources[0] with { AnnouncementIdentity = "community:OTHER" }] };
        Check(observer.Observe(Owner, 1, different, () => true).Count == 0, "Another organization starts quietly even in an existing account file.");
        observer.Observe(Owner, 1, Feed(7204, 4), () => true);
        observer.Reset();
        Check(observer.Observe(Owner, 2, Feed(7205, 5), () => true) is [{ AnnouncementSummaryCount: 1 }], "A session generation change preserves the observed membership baseline.");
        var rejoined = Feed(7206, 6);
        rejoined = rejoined with { Sources = [rejoined.Sources[0] with { PolicyKey = NotificationPolicyStore.Organization("SUMMARY", Day) }] };
        Check(observer.Observe(Owner, 2, rejoined, () => true).Count == 0, "A new membership baseline cannot inherit the previous membership.");
        Check(new AnnouncementNotificationObserver(store, clock).Observe(Owner, 3, Feed(7207, 6), () => true).Count == 0,
            "A cold observer with a different generation also starts with a quiet baseline.");
        var reconnect = new AnnouncementNotificationObserver(store, clock);
        reconnect.Observe(Owner, 1, Feed(7207, 6), () => true);
        reconnect.Reset();
        Check(reconnect.Observe(Owner, 1, Feed(7300, 9), () => true) is [{ AnnouncementSummaryCount: 3 }],
            "Long reconnect uses durable baseline and emits a single summary.");
        foreach (var count in new[] { 99, 100 }) {
            var capped = new AnnouncementObservationStore(Path.Combine(root, "cap-" + count));
            new AnnouncementNotificationObserver(capped, clock).Observe(Owner, 1, Feed(0, 0), () => true);
            Check(new AnnouncementNotificationObserver(capped, clock).Observe(Owner, 1, Feed(7200, count), () => true)
                is [var summary] && summary.AnnouncementSummaryCount == count, "99 is exact; 100 is the 99+ display sentinel.");
            Check(new AnnouncementNotificationObserver(capped, clock).Observe(Owner, 1, Feed(7201, count), () => true).Count == 0,
                "Every ID above the visible cap is consumed too.");
        }
        var failingStore = new AnnouncementObservationStore(Path.Combine(root, "write-failure"));
        new AnnouncementNotificationObserver(failingStore, clock).Observe(Owner, 1, Feed(0, 0), () => true);
        var path = failingStore.PathFor(owner); var before = File.ReadAllBytes(path);
        var failing = new AnnouncementNotificationObserver(failingStore, clock);
        using (var lease = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read)) {
            Check(failing.Observe(Owner, 1, Feed(7200, 3), () => true).Count == 0 && File.ReadAllBytes(path).SequenceEqual(before),
                "A failed atomic replacement with a historical baseline cannot output a summary.");
        }
        Check(failing.Observe(Owner, 1, Feed(7201, 3), () => true).Count == 0, "A failed writer remains closed for this lifecycle.");
        var legacy = new AnnouncementObservationStore(Path.Combine(root, "no-marker"));
        var legacyMarker = AnnouncementObservationStore.Hash(JsonSerializer.SerializeToUtf8Bytes(
            new[] { "announcement-baseline-v1", owner, Identity, Policy, "0" }));
        legacy.Write(owner, [AnnouncementObservationStore.Key(owner, Identity, "id-0"), legacyMarker], () => true);
        Check(new AnnouncementNotificationObserver(legacy, clock).Observe(Owner, 1, Feed(7200, 4), () => true).Count == 0,
            "A v1 session-generation-0 marker cannot collide with a v2 membership-generation-0 baseline; upgrade remains quiet.");
    }
    private sealed class Reader : ICommunityNotificationReader {
        internal CommunityNotificationFeed Feed = new(Day, []);
        internal int Reads;
        public Task<CommunityNotificationFeed> ReadNotificationsAsync(BridgeAccountContext owner, long generation, CancellationToken token) {
            Reads++; return Task.FromResult(Feed);
        }
    }
    private sealed class Sink : IDesktopNotificationSink {
        internal readonly List<DesktopNotification> Notices = [];
        public ValueTask<bool> TryPresentAsync(DesktopNotification notice, CancellationToken token) {
            Notices.Add(notice); throw new IOException("Unknown synthetic output result");
        }
        public void Clear() { }
        public void Dispose() { }
    }
    private sealed class Audio : INotificationAudioOutput {
        internal int Count;
        public bool TryPlay(byte[] wave) { Count++; return true; }
        public void Stop() { }
        public void Dispose() { }
    }
    private static async Task Delivery(string root, string kind) {
        if (kind == "official") { await AnnouncementPersistenceTests.ColdStart(root); return; }
        Directory.CreateDirectory(root);
        var clock = new Clock(); var reader = new Reader(); var sink = new Sink(); var output = new Audio();
        var official = kind == "default-official";
        var policy = official ? NotificationPolicyStore.OfficialFleet("officialFleet:7") : Policy;
        CommunityNotificationFeed Page(int second, int count) {
            var feed = Feed(second, count);
            return official ? feed with { Sources = [feed.Sources[0] with { PolicyKey = policy, JoinedAt = null,
                SourceKind = OrganizationNotificationSourceKind.OfficialFleet, AnnouncementIdentity = "officialFleet:7",
                AnnouncementSource = "officialFleet:7" }] } : feed;
        }
        var wave = NotificationAudioTests.Wave();
        File.WriteAllBytes(Path.Combine(root, "notify.soft.wav"), wave);
        File.WriteAllBytes(Path.Combine(root, "notify.rally.wav"), wave);
        File.WriteAllText(Path.Combine(root, "cue-catalog.v1.json"), JsonSerializer.Serialize(new { schemaVersion = 1,
            assets = new[] { "notify.soft", "notify.rally" }.Select(cue => new { assetId = cue, cueId = cue, fileName = cue + ".wav",
                tier = "approved", priority = 320, sha256 = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(wave)) }).ToArray() }));
        new NotificationAudioSettingsStore(root).Save(0, true, .5);
        using var audio = new NotificationAudioBridgeDispatcher(root, NotificationAudioCatalog.Load(root), output,
            () => 1, () => true, clock, canPlaySocial: () => true);
        using var settings = new NotificationSettingsBridgeDispatcher(root, () => 1, () => true, desktop: sink, time: clock,
            activationEvent: (g, p) => BridgeEnvelope.Event("notificationSettings.activated", g, 1, p));
        await settings.DispatchAsync(BridgeEnvelope.Request("notificationSettings.save", "summary-fixture", 1, new {
            schemaVersion = 1, expectedRevision = 0, inAppEnabled = true, position = "bottomRight", preview = "fullContent", windowsEnabled = true }));
        var policies = new NotificationPolicyStore(root);
        void Rule(bool enabled) => policies.Save(Owner, policies.Read(Owner).Revision, Guid.NewGuid().ToString("N"), [new(policy,
            enabled ? NotificationSourceMode.Normal : kind.EndsWith("dnd") ? NotificationSourceMode.DoNotDisturb :
                kind.EndsWith("important") ? NotificationSourceMode.ImportantOnly : NotificationSourceMode.Normal) {
            TypeRules = kind.StartsWith("default") ? null : [new("announcement", !enabled && kind == "disabled" ? "disabled" : "enabled")],
            QuietHours = !enabled && kind.EndsWith("quiet") ? new(true, 720, 721) : null }], () => true, extended: true);
        Rule(false);
        var store = new AnnouncementObservationStore(root);
        new AnnouncementNotificationObserver(store, clock).Observe(Owner, 1, Page(0, 0), () => true);
        clock.Now = Day.AddSeconds(3600 * 24); // Noon next day: the scheduled quiet interval is active.
        reader.Feed = Page(3600 * 24, 3);
        using var runtime = new CommunityNotificationRuntime(reader, () => (Owner, 1), async (notice, ct) => {
            var hash = AnnouncementObservationStore.Owner(Owner);
            Check(Enumerable.Range(0, 3).All(i => store.Read(hash).Contains(AnnouncementObservationStore.Key(hash,
                official ? "officialFleet:7" : Identity, "id-" + i))), "All summary IDs are persisted before either output channel.");
            audio.TryPlayCommunity(notice);
            await settings.PresentCommunityAsync(notice, ct);
        }, clock, announcements: new(store, clock));
        await runtime.TickAsync();
        var allowed = kind is "normal" or "default" or "default-official";
        Check(sink.Notices.Count == (allowed ? 1 : 0) && output.Count == (allowed ? 1 : 0),
            "Startup summary honors both desktop/audio policy: " + kind);
        if (allowed) {
            Check(sink.Notices[0].Community is { Announcement: true, AnnouncementSummaryCount: 3, Callsign: "", Text: "" },
                "The runtime carries exactly one organization/count summary and no announcement detail.");
            var reads = reader.Reads;
            sink.Notices[0].Activated!();
            var activation = (await settings.DispatchAsync(BridgeEnvelope.Request("notificationSettings.consumeActivation", "summary-click", 1,
                new { schemaVersion = 1, activationId = sink.Notices[0].Id.ToString("N") }))).Response;
            Check(reader.Reads == reads + 1 && activation.Payload.GetProperty("destination").GetString() ==
                (official ? "officialFleetAnnouncements" : "communityAnnouncements"), "Summary activation performs another authorized read and opens announcements.");
        }
        if (kind == "dnd") Check(audio.TryPlayRally(() => true), "Rallies remain independent of summary DND.");
        var audioCount = output.Count;
        Rule(true); clock.Now = clock.Now.AddMinutes(1); reader.Feed = Page(86460, 3);
        await runtime.TickAsync();
        Check(sink.Notices.Count == (allowed ? 1 : 0) && output.Count == audioCount,
            "Ending suppression or an uncertain output never replays summary: " + kind);
    }
}
