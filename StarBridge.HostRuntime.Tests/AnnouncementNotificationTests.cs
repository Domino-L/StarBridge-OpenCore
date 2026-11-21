using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Communities;
using StarBridge.HostRuntime.Notifications;
using StarBridge.NativeBridge;

internal static class AnnouncementNotificationTests
{
    private static readonly BridgeAccountContext Owner = new("fixture", "fixture", "synthetic-announcement-owner");
    private static readonly DateTimeOffset Day = new(2026, 11, 4, 12, 0, 0, TimeSpan.Zero);
    private static readonly string Policy = NotificationPolicyStore.Organization("SYNTHETIC", Day.AddDays(-1));
    private static int _checks;
    private static void Check(bool value, string message) { _checks++; if (!value) throw new Exception(message); }
    private sealed class Clock : TimeProvider {
        internal DateTimeOffset Now = Day;
        public override DateTimeOffset GetUtcNow() => Now;
        public override long GetTimestamp() => Now.UtcTicks;
        public override long TimestampFrequency => TimeSpan.TicksPerSecond;
        public override TimeZoneInfo LocalTimeZone => TimeZoneInfo.Utc;
    }
    private static CommunityNotificationFeed Feed(int second, string id, bool published = true, string key = "source", bool available = true) =>
        new(Day.AddSeconds(second), [new(key, "Synthetic organization", Day.AddDays(-1), false, null, false, [], Policy,
            Announcements: available ? new(Day.AddSeconds(second), [new(id, published, Day.AddSeconds(second))]) : null,
            AnnouncementSource: new string('a', 32), AnnouncementIdentity: "community:SYNTHETIC")]);
    internal static async Task Run() {
        _checks = 0;
        var root = Path.Combine(Path.GetTempPath(), "sb-announce-" + Guid.NewGuid().ToString("N"));
        try {
            Compatibility(Path.Combine(root, "compatibility"));
            Observations(Path.Combine(root, "observations"));
            Failures(Path.Combine(root, "failures"));
            await Delivery(Path.Combine(root, "delivery"));
            await Reads();
            Console.WriteLine($"PASS CX-ANNOUNCE-ALERTS: {_checks} assertions, 0 failed");
        } finally {
            if (!Path.GetFullPath(root).StartsWith(Path.GetFullPath(Path.GetTempPath()), StringComparison.OrdinalIgnoreCase)) throw new IOException();
            if (Directory.Exists(root)) Directory.Delete(root, true);
        }
    }
    private static void Compatibility(string root) {
        var json = new JsonSerializerOptions(JsonSerializerDefaults.Web);
        var owner = AnnouncementObservationStore.Owner(Owner);
        var legacy = Path.Combine(root, "notification-policies-v1", owner + ".json");
        Directory.CreateDirectory(Path.GetDirectoryName(legacy)!);
        var snapshot = new NotificationPolicySnapshot(1, Guid.NewGuid().ToString("N"), [new(Policy, NotificationSourceMode.Normal)]);
        var integrity = AnnouncementObservationStore.Hash(JsonSerializer.SerializeToUtf8Bytes(new { owner, snapshot }, json));
        File.WriteAllBytes(legacy, JsonSerializer.SerializeToUtf8Bytes(new { schemaVersion = 1, owner, snapshot, integrity }, json));
        var before = File.ReadAllBytes(legacy);
        var store = new NotificationPolicyStore(root);
        var saved = store.Save(Owner, 1, Guid.NewGuid().ToString("N"), [new(Policy, NotificationSourceMode.Normal) {
            TypeRules = [new("announcement", "enabled")] }], () => true, extended: true);
        Check(saved.Revision == 2 && File.ReadAllBytes(legacy).SequenceEqual(before), "Saving an actual announcement rule leaves all v1 bytes unchanged.");
        using var modern = JsonDocument.Parse(File.ReadAllBytes(Path.Combine(root, "notification-policies-v2", owner + ".json")));
        Check(modern.RootElement.GetProperty("schemaVersion").GetInt32() == 2 &&
            store.Read(Owner).Rule(Policy).TypeRules!.Single().Mode == "enabled", "Announcement selection persists only in the existing v2 document.");
    }
    private static void Observations(string root) {
        var store = new AnnouncementObservationStore(root);
        var clock = new Clock();
        var observer = new AnnouncementNotificationObserver(store, clock);
        var unidentified = Feed(0, "unidentified");
        unidentified = unidentified with { Sources = [unidentified.Sources[0] with { AnnouncementIdentity = null }] };
        Check(observer.Observe(Owner, 1, unidentified, () => true).Count == 0 &&
            !File.Exists(store.PathFor(AnnouncementObservationStore.Owner(Owner))), "Missing canonical organization identity cannot create observations from temporary references.");
        IReadOnlyList<CommunityNotificationCandidate> See(int tick, string id, bool published = true, string key = "source", bool available = true,
            BridgeAccountContext? owner = null, long generation = 1) {
            clock.Now = Day.AddSeconds(tick);
            return observer.Observe(owner ?? Owner, generation, Feed(tick, id, published, key, available), () => true);
        }
        Check(See(0, "old").Count == 0, "First success is a persisted quiet baseline.");
        Check(See(1, "new").Count == 1, "Continuously observed new server ID produces an announcement candidate.");
        Check(See(2, "new").Count == 0, "Editing the same ID, including a changed publication date, does not replay.");
        Check(See(3, "withdrawn", false).Count == 0 && See(4, "withdrawn").Count == 0, "Withdrawal is consumed before any later reappearance.");
        Check(See(5, "archived", false).Count == 0, "Archive is consumed silently.");
        Check(See(6, "gap", available: false).Count == 0 && See(7, "gap") is [{ AnnouncementSummaryCount: 1 }], "Read recovery summarizes unseen IDs with a durable organization baseline.");
        Check(See(8, "after-gap").Count == 1, "New event after recovery can notify.");
        Check(See(50, "sleep") is [{ AnnouncementSummaryCount: 1 }], "Observation discontinuity emits one durable-baseline summary.");
        Check(See(51, "generation", generation: 2) is [{ AnnouncementSummaryCount: 1 }], "A session generation change preserves membership and summarizes new IDs.");
        Check(See(52, "organization", key: "other-source", generation: 2) is [{ AnnouncementSummaryCount: 1 }], "A temporary source-reference change preserves stable organization history.");
        var other = Owner with { Subject = "another-synthetic-owner" };
        Check(See(53, "account", owner: other, generation: 3).Count == 0, "Account switch cannot inherit a baseline.");
        Check(See(54, "after-account", owner: other, generation: 3).Count == 1, "New account can observe new events.");
        Check(store.PathFor(AnnouncementObservationStore.Owner(Owner)) != store.PathFor(AnnouncementObservationStore.Owner(other)), "Files are account isolated.");
        var bytes = File.ReadAllText(store.PathFor(AnnouncementObservationStore.Owner(Owner)));
        Check(!bytes.Contains(Owner.Subject) && !bytes.Contains("Synthetic") && !bytes.Contains("after-gap") && !bytes.Contains("source"), "Only derived keys and integrity metadata are persisted.");
        var restarted = new AnnouncementNotificationObserver(new(root), clock);
        Check(restarted.Observe(Owner, 4, Feed(55, "after-gap", key: "new-process-source"), () => true).Count == 0, "Restart baselines and keeps durable tombstones.");
        clock.Now = Day.AddSeconds(56);
        Check(restarted.Observe(Owner, 4, Feed(56, "new", key: "new-process-source"), () => true).Count == 0, "Consumed publication survives restart and new temporary references.");
        var rejoined = Feed(57, "rejoin-baseline", key: "rejoined-source");
        var rejoinedPolicy = NotificationPolicyStore.Organization("SYNTHETIC", Day);
        rejoined = rejoined with { Sources = [rejoined.Sources[0] with { PolicyKey = rejoinedPolicy }] };
        Check(restarted.Observe(Owner, 4, rejoined, () => true).Count == 0, "Rejoined membership begins quietly with its new delivery policy.");
        var edited = Feed(58, "new", key: "rejoined-source");
        edited = edited with { Sources = [edited.Sources[0] with { PolicyKey = rejoinedPolicy }] };
        Check(restarted.Observe(Owner, 4, edited, () => true).Count == 0, "A changed membership policy cannot replay an already consumed server ID.");
        File.Delete(store.PathFor(AnnouncementObservationStore.Owner(Owner)));
        Check(restarted.Observe(Owner, 4, Feed(57, "missing", key: "new-process-source"), () => true).Count == 0 &&
            !File.Exists(store.PathFor(AnnouncementObservationStore.Owner(Owner))), "A disappeared observed file closes output instead of recreating an empty history.");
    }
    private static void Failures(string root) {
        var hash = AnnouncementObservationStore.Owner(Owner);
        var store = new AnnouncementObservationStore(root);
        var path = store.PathFor(hash);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, "broken");
        var observer = new AnnouncementNotificationObserver(store);
        Check(observer.Observe(Owner, 1, Feed(0, "first"), () => true).Count == 0 && store.Read(hash).Count > 0, "Corrupt data is atomically replaced with a quiet baseline and cannot authorize catch-up.");
        File.Delete(path);
        Check(observer.Observe(Owner, 1, Feed(1, "second"), () => true).Count == 0 && !File.Exists(path), "Corruption cannot clear into catch-up output.");
        var deniedRoot = Path.Combine(root, "not-a-directory"); File.WriteAllText(deniedRoot, "fixture");
        var failing = new AnnouncementNotificationObserver(new(deniedRoot));
        Check(failing.Observe(Owner, 1, Feed(0, "old"), () => true).Count == 0 &&
            failing.Observe(Owner, 1, Feed(1, "new"), () => true).Count == 0, "Atomic write failure cannot emit or replay.");
        var keys = Enumerable.Range(0, AnnouncementObservationStore.MaximumKeys)
            .Select(i => AnnouncementObservationStore.Key(hash, "source", i.ToString())).ToHashSet();
        store.Write(hash, keys, () => true);
        Check(store.Read(hash).Count == AnnouncementObservationStore.MaximumKeys, "Maximum count is supported.");
        var before = File.ReadAllBytes(path);
        Check(new AnnouncementNotificationObserver(store).Observe(Owner, 1, Feed(0, "overflow"), () => true).Count == 0 &&
            File.ReadAllBytes(path).SequenceEqual(before), "Saturation closes output without eviction or clearing.");
    }
    private sealed class Reader : ICommunityNotificationReader {
        internal CommunityNotificationFeed Feed = new(Day, []);
        public Task<CommunityNotificationFeed> ReadNotificationsAsync(BridgeAccountContext owner, long generation, CancellationToken token) => Task.FromResult(Feed);
    }
    private sealed class Sink : IDesktopNotificationSink {
        internal List<DesktopNotification> Notices = [];
        public ValueTask<bool> TryPresentAsync(DesktopNotification notice, CancellationToken token) { Notices.Add(notice); throw new IOException("Unknown synthetic output result"); }
        public void Clear() { }
        public void Dispose() { }
    }
    private sealed class AudioOutput : INotificationAudioOutput {
        internal int Count;
        public bool TryPlay(byte[] wave) { Count++; return true; }
        public void Stop() { }
        public void Dispose() { }
    }
    private static async Task Delivery(string root) {
        var clock = new Clock(); var reader = new Reader(); var sink = new Sink();
        Directory.CreateDirectory(root);
        var wave = NotificationAudioTests.Wave();
        File.WriteAllBytes(Path.Combine(root, "notify.soft.wav"), wave);
        File.WriteAllBytes(Path.Combine(root, "notify.rally.wav"), wave);
        File.WriteAllText(Path.Combine(root, "cue-catalog.v1.json"), JsonSerializer.Serialize(new { schemaVersion = 1,
            assets = new[] { "notify.soft", "notify.rally" }.Select(cue => new { assetId = cue, cueId = cue, fileName = cue + ".wav",
                tier = "approved", priority = 320, sha256 = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(wave)) }).ToArray() }));
        new NotificationAudioSettingsStore(root).Save(0, true, .5);
        var output = new AudioOutput();
        using var audio = new NotificationAudioBridgeDispatcher(root, NotificationAudioCatalog.Load(root), output,
            () => 1, () => true, clock, canPlaySocial: () => true);
        using var settings = new NotificationSettingsBridgeDispatcher(root, () => 1, () => true, desktop: sink, time: clock,
            activationEvent: (g, p) => BridgeEnvelope.Event("notificationSettings.activated", g, 1, p));
        await settings.DispatchAsync(BridgeEnvelope.Request("notificationSettings.save", "synthetic", 1, new {
            schemaVersion = 1, expectedRevision = 0, inAppEnabled = true, position = "bottomRight", preview = "fullContent", windowsEnabled = true }));
        var store = new NotificationPolicyStore(root);
        void Rule(NotificationSourceMode mode, NotificationQuietHours? quiet = null, string type = "enabled") {
            store.Save(Owner, store.Read(Owner).Revision, Guid.NewGuid().ToString("N"), [new(Policy, mode) {
                TypeRules = [new("announcement", type)], QuietHours = quiet }], () => true, extended: true);
        }
        var observations = new AnnouncementObservationStore(root);
        var attempted = 0;
        using var runtime = new CommunityNotificationRuntime(reader, () => (Owner, 1), async (notice, ct) => {
            attempted++;
            Check(observations.Read(AnnouncementObservationStore.Owner(Owner)).Contains(
                AnnouncementObservationStore.Key(AnnouncementObservationStore.Owner(Owner), "community:SYNTHETIC", reader.Feed.Sources[0].Announcements!.Entries[0].Id)),
                "Consumed key exists on disk before either output channel.");
            audio.TryPlayCommunity(notice);
            await settings.PresentCommunityAsync(notice, ct);
        }, clock, announcements: new(observations, clock));
        async Task Tick(int second, string id) { clock.Now = Day.AddSeconds(second); reader.Feed = Feed(second, id); await runtime.TickAsync(); }
        await Tick(0, "baseline");
        Check(sink.Notices.Count == 0 && output.Count == 0, "First use only records announcements, even with the default follow mode.");
        await Tick(1, "default-follow");
        Check(sink.Notices.Count == 1 && output.Count == 1, "Missing announcement type follows the normal source for card and sound.");
        sink.Notices.Clear();
        output.Count = 0; // Keep the following explicit-choice/channel checks independent of the default delivery.
        Rule(NotificationSourceMode.Normal); await Tick(2, "enabled");
        Check(sink.Notices.Count == 1 && output.Count == 1 && sink.Notices[0].Community is { Announcement: true, Callsign: "", Text: "" }, "Announcement desktop/audio use only organization label, never author/title/body.");
        sink.Notices[0].Activated!();
        var activated = (await settings.DispatchAsync(BridgeEnvelope.Request("notificationSettings.consumeActivation", "synthetic-click", 1,
            new { schemaVersion = 1, activationId = sink.Notices[0].Id.ToString("N") }))).Response;
        Check(activated.Payload.GetProperty("destination").GetString() == "communityAnnouncements" &&
            activated.Payload.GetProperty("ref").GetString() == new string('a', 32), "Click reauthorizes the current feed and returns only its current announcement-page reference.");
        await Tick(3, "enabled"); Check(sink.Notices.Count == 1, "Unknown output result never replays.");
        Rule(NotificationSourceMode.DoNotDisturb); await Tick(4, "muted");
        Check(audio.TryPlayRally(() => true) && output.Count == 2, "Independent rally sound still plays while announcement source is DND.");
        Rule(NotificationSourceMode.Normal); await Tick(5, "muted");
        Check(sink.Notices.Count == 1 && output.Count == 2, "Source DND is absolute for desktop/audio and unmuting never catches up.");
        Rule(NotificationSourceMode.ImportantOnly); await Tick(6, "important");
        Check(sink.Notices.Count == 1 && output.Count == 2, "Enabled type cannot expand importantOnly for either channel.");
        Rule(NotificationSourceMode.Normal, new(true, 720, 721)); await Tick(7, "quiet");
        await Tick(20, "quiet"); await Tick(40, "quiet"); await Tick(59, "quiet"); await Tick(60, "quiet");
        Check(sink.Notices.Count == 1 && output.Count == 2, "Ending daily quiet hours does not catch up on either channel.");
        Check(attempted == 5, "Suppressed events are consumed through the sole runtime.");
        foreach (var mode in new[] { "inherit", "enabled" }) {
            var rule = new NotificationPolicyRule(Policy, NotificationSourceMode.Normal) { TypeRules = [new("announcement", mode)] };
            Check(NotificationOrganizationPolicy.Allows(rule, NotificationEventKind.OrganizationAnnouncement, Day, TimeZoneInfo.Utc), "Explicit inherit and enabled follow a normal source.");
        }
        await Tick(61, "after-quiet");
        Check(sink.Notices.Count == 2 && output.Count == 3, "A newly published post-quiet announcement resumes both channels.");
        reader.Feed = Feed(62, "after-quiet", available: false);
        sink.Notices.Last().Activated!();
        var revoked = (await settings.DispatchAsync(BridgeEnvelope.Request("notificationSettings.consumeActivation", "synthetic-revoked-click", 1,
            new { schemaVersion = 1, activationId = sink.Notices.Last().Id.ToString("N") }))).Response;
        Check(revoked.Status == "ok" && (!revoked.Payload.TryGetProperty("destination", out var revokedDestination) ||
            revokedDestination.ValueKind == JsonValueKind.Null), "Click with revoked announcement access cannot navigate using cached content.");
        await settings.DispatchAsync(BridgeEnvelope.Request("notificationSettings.save", "synthetic-no-windows", 1, new {
            schemaVersion = 1, expectedRevision = 1, inAppEnabled = true, position = "bottomRight", preview = "sourceOnly", windowsEnabled = false }));
        await Tick(63, "audio-only");
        Check(sink.Notices.Count == 2 && output.Count == 4, "Announcement audio remains independent of the Windows channel setting.");
    }
    private sealed class Handler(Func<HttpRequestMessage, HttpResponseMessage> send) : HttpMessageHandler {
        internal bool HoldAnnouncements;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct) {
            if (HoldAnnouncements && request.RequestUri!.AbsolutePath.EndsWith("/announcements")) await Task.Delay(Timeout.Infinite, ct);
            return send(request);
        }
    }
    private static async Task Reads() {
        bool broken = false, conflict = false; int pages = 0;
        object Row(string id, string state) => new { id, fleetCode = "SYNTHETIC", state, revision = 1,
            publishedAt = Day.AddSeconds(-1), updatedAt = Day.AddSeconds(-1) };
        using var handler = new Handler(request => {
            Check(request.Method == HttpMethod.Get, "Announcement observer only reads authorized lists.");
            var path = request.RequestUri!.AbsolutePath;
            if (path == "/api/fleets/notification-sources") return new(HttpStatusCode.OK) { Content = JsonContent.Create(new {
                schemaVersion = 1, serverTime = Day, sources = new[] { new { code = "SYNTHETIC", name = "Fixture", joinedAt = Day.AddDays(-1),
                    managementAvailable = false, tasks = Array.Empty<object>(), chat = new { sequence = 0, createdAt = (string?)null, incoming = false,
                        unread = 0, callsign = "", text = "" } } } }) };
            if (path == "/api/fleets/announcements") {
                pages++;
                Check(!request.RequestUri.Query.Contains("author") && !request.RequestUri.Query.Contains("detail"), "No author identities or detail reads.");
                if (broken) return new(HttpStatusCode.ServiceUnavailable);
                var offset = request.RequestUri.Query.Contains("offset=20") ? 20 : 0;
                if (offset == 20) Check(request.RequestUri.Query.Contains("expectedRevision=1"), "Pagination pins expected revision.");
                return new(HttpStatusCode.OK) { Content = JsonContent.Create(new { schemaVersion = 1, membershipModelVersion = 2,
                    fleetCode = "SYNTHETIC", revision = conflict && offset == 20 ? 2 : 1, refreshedAt = Day, offset,
                    next = offset == 0 ? (int?)20 : null, totalHistoryCount = 21,
                    current = new { announcement = Row("raw-stable-id", "Published") },
                    history = Enumerable.Range(offset, offset == 0 ? 20 : 1).Select(i => new { announcement = Row("history-" + i, "Withdrawn") }).ToArray() }) };
            }
            throw new Exception("Unexpected synthetic route");
        });
        using var client = new CommunityClient(new("https://relay.invalid"), handler);
        var source = (await client.ReadScmNotificationsAsync("synthetic", "synthetic-scope", () => { }, default)).Sources.Single();
        Check(source.Announcements is { Entries.Length: 22 } && source.Announcements.Entries[0].Id == "raw-stable-id" && pages == 2,
            "Reader observes all bounded raw server IDs across pages, never announcementRef.");
        conflict = true;
        source = (await client.ReadScmNotificationsAsync("synthetic", "synthetic-scope", () => { }, default)).Sources.Single();
        Check(source.Announcements == null && source.ChatAvailable, "Revision conflict invalidates only announcements.");
        broken = true;
        source = (await client.ReadScmNotificationsAsync("synthetic", "synthetic-scope", () => { }, default)).Sources.Single();
        Check(source.Announcements == null && source.ChatAvailable, "Announcement read failure preserves chat observation.");
        handler.HoldAnnouncements = true;
        source = (await client.ReadScmNotificationsAsync("synthetic", "synthetic-scope", () => { }, default)).Sources.Single();
        Check(source.Announcements == null && source.ChatAvailable, "An announcement-domain timeout returns confirmed chat without resetting its baseline.");
        await OfficialReads();
    }
    private static async Task OfficialReads() {
        var code = "OFFICIALFLEET:7";
        using var handler = new Handler(request => {
            if (request.RequestUri!.AbsolutePath == "/api/official-fleets/context")
                return new(HttpStatusCode.OK) { Content = JsonContent.Create(new { schemaVersion = 1, sourceRef = "officialFleet:7",
                    fleetCode = code, name = "Fixture official fleet", chatAvailable = true, canManageAnnouncements = false }) };
            if (request.RequestUri.AbsolutePath == "/api/official-fleets/chat/channels") return new(HttpStatusCode.ServiceUnavailable);
            if (request.RequestUri.AbsolutePath == "/api/official-fleets/announcements") return new(HttpStatusCode.OK) { Content = JsonContent.Create(new {
                schemaVersion = 1, membershipModelVersion = 2, fleetCode = code, revision = 1, refreshedAt = Day,
                offset = 0, next = (int?)null, totalHistoryCount = 0, history = Array.Empty<object>(), current = new {
                    announcement = new { id = "official-stable-id", fleetCode = code, state = "Published", revision = 1, publishedAt = Day, updatedAt = Day } } }) };
            throw new Exception("Unexpected official synthetic route");
        });
        using var client = new CommunityClient(new("https://relay.invalid"), handler);
        var source = await client.ReadOfficialFleetNotificationAsync("synthetic", "synthetic-scope", () => { }, default);
        Check(!source.ChatAvailable && source.Announcements?.Entries.Single().Id == "official-stable-id" &&
            source.AnnouncementSource == "officialFleet:7", "Authorized official announcements remain available during an independent chat outage.");
    }
}
