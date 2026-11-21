using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Achievements;
using StarBridge.HostRuntime.Communities;
using StarBridge.HostRuntime.Notifications;
using StarBridge.NativeBridge;

internal static class FleetPrivacyNotificationTests
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    private static readonly BridgeAccountContext Owner = new("fixture", "fixture", "privacy-notify-synthetic");
    private static readonly DateTimeOffset Day = new(2026, 11, 3, 0, 0, 0, TimeSpan.Zero);
    private static string Key => NotificationPolicyStore.Organization("SYNTHETIC", Day);
    private static string Official => NotificationPolicyStore.OfficialFleet("officialFleet:7");
    private static int _checks;
    private static void Check(bool value, string message) { _checks++; if (!value) throw new Exception(message); }
    private static void Reject(Action action, string message)
    {
        try { action(); } catch (Exception e) when (e is IOException or InvalidDataException or JsonException or NotificationSettingsConflictException) { Check(true, message); return; }
        Check(false, message);
    }
    internal static async Task Run()
    {
        _checks = 0;
        var root = Path.GetFullPath(Path.Combine(Path.GetTempPath(), "sb-privacy-notify-" + Guid.NewGuid().ToString("N")));
        Directory.CreateDirectory(root);
        try {
            Storage(Path.Combine(root, "storage"));
            Boundaries(Path.Combine(root, "boundaries"));
            await Bridge(Path.Combine(root, "bridge"));
            await Delivery(Path.Combine(root, "delivery"));
            await Activity(Path.Combine(root, "activity"));
            Console.WriteLine($"PASS CX-FLEET-PRIVACY-IMPL: {_checks} assertions, 0 failed");
        } finally {
            if (!root.StartsWith(Path.GetFullPath(Path.GetTempPath()).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar,
                StringComparison.OrdinalIgnoreCase)) throw new IOException("Unsafe fixture cleanup.");
            Directory.Delete(root, true);
        }
    }
    private static string Hash(byte[] bytes) => Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
    private static string OwnerHash => Hash(JsonSerializer.SerializeToUtf8Bytes(new[] { Owner.Environment, Owner.Authority, Owner.Subject }));
    private static string FilePath(string root, int version) => Path.Combine(root, "notification-policies-v" + version, OwnerHash + ".json");
    private static void WriteLegacy(string root)
    {
        var path = FilePath(root, 1); Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var snapshot = new NotificationPolicySnapshot(4, Guid.NewGuid().ToString("N"), [new(Key, NotificationSourceMode.ImportantOnly)]) {
            SuppressionRevisions = new() { [Key] = 3 }
        };
        var integrity = Hash(JsonSerializer.SerializeToUtf8Bytes(new { owner = OwnerHash, snapshot }, Json));
        File.WriteAllBytes(path, JsonSerializer.SerializeToUtf8Bytes(new { schemaVersion = 1, owner = OwnerHash, snapshot, integrity }, Json));
    }
    private static void Rewrite(string path, Action<JsonObject> edit)
    {
        var file = JsonNode.Parse(File.ReadAllBytes(path))!.AsObject(); edit(file);
        var snapshot = JsonSerializer.SerializeToElement(file["snapshot"], Json);
        file["integrity"] = Hash(JsonSerializer.SerializeToUtf8Bytes(new {
            schemaVersion = 2, owner = file["owner"]!.GetValue<string>(), snapshot,
            legacyFingerprint = file["legacyFingerprint"]!.GetValue<string>()
        }, Json));
        File.WriteAllText(path, file.ToJsonString(Json));
    }
    private static void Storage(string root)
    {
        var store = new NotificationPolicyStore(root);
        Check(store.Read(Owner).Revision == 0 && !Directory.Exists(root), "Reading defaults creates no files.");
        WriteLegacy(root); var old = File.ReadAllBytes(FilePath(root, 1));
        var read = store.Read(Owner);
        Check(read.Revision == 4 && read.For(Key) == NotificationSourceMode.ImportantOnly && read.Rule(Key).TypeRules == null &&
            read.Rule(Key).QuietHours == null && !File.Exists(FilePath(root, 2)), "Legacy read keeps defaults without migration.");
        var operation = Guid.NewGuid().ToString("N");
        var rules = new[] { new NotificationPolicyRule(Key, NotificationSourceMode.Normal) {
            TypeRules = [new("chat", "disabled")], QuietHours = new(true, 1320, 480) } };
        var saved = store.Save(Owner, 4, operation, rules, () => true, extended: true);
        Check(saved.Revision == 5 && File.Exists(FilePath(root, 2)) && File.ReadAllBytes(FilePath(root, 1)).SequenceEqual(old),
            "First save writes v2 only and preserves legacy bytes.");
        Check(saved.SuppressionRevision(Key) == 5 && saved.SuppressionRevisions![Key + "#chat"] == 5 &&
            saved.SuppressionRevisions[Key + "#quiet"] == 5, "Narrowing tracks source, type and quiet suppression history.");
        Check(store.Save(Owner, 4, operation, rules, () => true, extended: true).Revision == 5, "v2 uncertain retry is idempotent.");
        var path = FilePath(root, 2);
        Rewrite(path, file => {
            file["futureEnvelope"] = new JsonObject { ["value"] = 9 };
            file["snapshot"]!["futureSnapshot"] = true;
            var rule = file["snapshot"]!["rules"]![0]!;
            rule["futureRule"] = "keep";
            rule["quietHours"]!["futureQuiet"] = 7;
            rule["typeRules"]![0]!["futureType"] = "keep";
        });
        saved = store.Save(Owner, 5, Guid.NewGuid().ToString("N"), [new(Key, NotificationSourceMode.ImportantOnly)], () => true);
        var reread = new NotificationPolicyStore(root).Read(Owner);
        Check(reread.Rule(Key).TypeRules![0].Mode == "disabled" && reread.Rule(Key).QuietHours!.Enabled,
            "Old-format save merges and preserves v2 fields.");
        var future = JsonNode.Parse(File.ReadAllBytes(path))!;
        Check(future["futureEnvelope"]!["value"]!.GetValue<int>() == 9 && future["snapshot"]!["futureSnapshot"]!.GetValue<bool>() &&
            reread.Rule(Key).Extra!["futureRule"].GetString() == "keep" && reread.Rule(Key).QuietHours!.Extra!["futureQuiet"].GetInt32() == 7 &&
            reread.Rule(Key).TypeRules![0].Extra!["futureType"].GetString() == "keep", "Unknown fields at every level survive old saves.");
        saved = store.Save(Owner, 6, Guid.NewGuid().ToString("N"), [new(Key, NotificationSourceMode.Normal) {
            TypeRules = [new("chat", "enabled")], QuietHours = new(false, 1380, 420) }], () => true, extended: true);
        Check(saved.Rule(Key).QuietHours!.Extra!["futureQuiet"].GetInt32() == 7 && saved.Rule(Key).TypeRules![0].Extra != null &&
            saved.SuppressionRevision(Key) == 6, "New editor also preserves unknown fields and old suppression history.");
        saved = store.Save(Owner, 7, Guid.NewGuid().ToString("N"), [], () => true);
        Check(saved.Rule(Key).TypeRules![0].Mode == "enabled" && saved.Rule(Key).QuietHours != null,
            "An omitted source from an old editor cannot erase its extended data.");
        Check(store.Read(Owner with { Subject = "another-synthetic-owner" }).Revision == 0, "Accounts remain isolated.");
        Reject(() => store.Save(Owner, 0, Guid.NewGuid().ToString("N"), [], () => true), "Stale revision cannot overwrite.");
        File.AppendAllText(FilePath(root, 1), " ");
        var modernBytes = File.ReadAllBytes(path);
        Check(store.Read(Owner).For(Key) == NotificationSourceMode.ImportantOnly, "An old Host write supplies current base modes.");
        Check(store.Read(Owner).Rule(Key).TypeRules![0].Mode == "enabled", "Reconciliation preserves extended choices.");
        Check(JsonNode.Parse(File.ReadAllBytes(path))!["futureEnvelope"]!["value"]!.GetValue<int>() == 9 &&
            store.Read(Owner).Rule(Key).TypeRules![0].Extra!["futureType"].GetString() == "keep", "Reconciliation preserves unknown envelope and extension fields.");
        Check(!File.ReadAllBytes(path).SequenceEqual(modernBytes), "Reconciliation atomically refreshes v2.");
        File.WriteAllBytes(FilePath(root, 1), old);
        var valid = File.ReadAllBytes(path);
        File.WriteAllText(path, "{\"schemaVersion\":2," + File.ReadAllText(path)[1..]);
        Check(store.Read(Owner).Rule(Key).TypeRules == null, "Duplicate JSON keys fall back to valid v1."); File.WriteAllBytes(path, valid);
        Rewrite(path, file => file["snapshot"]!["rules"]![0]!["typeRules"]![0]!["type"] = "unknown");
        Check(store.Read(Owner).Rule(Key).TypeRules == null, "Invalid v2 event type falls back to v1."); File.WriteAllBytes(path, valid);
        File.WriteAllText(path, new string(' ', 131073));
        Check(store.Read(Owner).Rule(Key).TypeRules == null, "Oversized v2 falls back to v1."); File.WriteAllBytes(path, valid);
        File.WriteAllText(path, "{");
        Check(store.Read(Owner).For(Key) == NotificationSourceMode.ImportantOnly, "Corrupt v2 falls back to valid v1.");
    }
    private static void Boundaries(string root)
    {
        var store = new NotificationPolicyStore(root); var clock = new Clock { Now = Day.AddHours(12) };
        foreach (var source in new[] { Key, Official })
        foreach (var mode in Enum.GetValues<NotificationSourceMode>())
        foreach (var chat in new[] { "inherit", "enabled", "disabled" }) {
            var rule = new NotificationPolicyRule(source, mode) { TypeRules = [new("chat", chat)] };
            Check(NotificationOrganizationPolicy.Allows(rule, NotificationEventKind.OrganizationChat, clock.Now, clock.Zone) ==
                (mode == NotificationSourceMode.Normal && chat != "disabled"), "All chat options respect base policy for both source kinds.");
        }
        var q = new NotificationQuietHours(true, 1320, 480);
        foreach (var (minute, expected) in new[] { (1319, false), (1320, true), (1439, true), (0, true), (479, true), (480, false) })
            Check(NotificationOrganizationPolicy.Quiet(q, Day.AddMinutes(minute), TimeZoneInfo.Utc) == expected, "Cross-midnight boundary " + minute);
        var sameDay = new NotificationQuietHours(true, 600, 660);
        Check(!NotificationOrganizationPolicy.Quiet(sameDay, Day.AddMinutes(599), TimeZoneInfo.Utc) &&
            NotificationOrganizationPolicy.Quiet(sameDay, Day.AddMinutes(600), TimeZoneInfo.Utc) &&
            !NotificationOrganizationPolicy.Quiet(sameDay, Day.AddMinutes(660), TimeZoneInfo.Utc), "Same-day half-open boundaries.");
        foreach (var bad in new[] { new NotificationQuietHours(true, 5, 5), new(true, -1, 60), new(true, 0, 1440), new(true, 0, 60, "utc") })
            Reject(() => store.Save(Owner, 0, Guid.NewGuid().ToString("N"), [new(Key, NotificationSourceMode.Normal) { QuietHours = bad }], () => true, true), "Invalid schedules rejected.");
        store.Save(Owner, 0, Guid.NewGuid().ToString("N"), [new(Key, NotificationSourceMode.Normal) { QuietHours = q }], () => true, true);
        var at = Day.AddHours(21);
        clock.Now = at.AddMinutes(1);
        Check(NotificationOrganizationPolicy.Current(store, Owner, Key, NotificationEventKind.OrganizationChat, 1, at, clock.Zone, clock), "Fresh output before quiet time.");
        clock.Now = Day.AddDays(1).AddHours(9); // No timer callbacks during simulated sleep.
        Check(!NotificationOrganizationPolicy.Current(store, Owner, Key, NotificationEventKind.OrganizationChat, 1, at, clock.Zone, clock), "Sleep over entire quiet period retires pending output.");
        clock.Now = Day.AddHours(21); clock.Zone = TimeZoneInfo.CreateCustomTimeZone("fixture-plus-two", TimeSpan.FromHours(2), "fixture", "fixture");
        Check(NotificationOrganizationPolicy.Quiet(q, clock.Now, clock.Zone) &&
            !NotificationOrganizationPolicy.Current(store, Owner, Key, NotificationEventKind.OrganizationChat, 1, at, TimeZoneInfo.Utc, clock),
            "New local time zone applies immediately and retires queued output.");
        var eastern = TimeZoneInfo.FindSystemTimeZoneById("Eastern Standard Time");
        Check(NotificationOrganizationPolicy.Quiet(new(true, 60, 120), new(2026, 11, 1, 5, 30, 0, TimeSpan.Zero), eastern) &&
            NotificationOrganizationPolicy.Quiet(new(true, 60, 120), new(2026, 11, 1, 6, 30, 0, TimeSpan.Zero), eastern), "DST repeated hour remains quiet on both occurrences.");
        Check(NotificationOrganizationPolicy.CrossedQuiet(new(true, 60, 120), new(2026, 11, 1, 4, 59, 0, TimeSpan.Zero),
            new(2026, 11, 1, 7, 1, 0, TimeSpan.Zero), eastern), "DST restore cannot revive pending output.");
        Check(!NotificationOrganizationPolicy.CrossedQuiet(new(true, 120, 180), new(2026, 3, 8, 6, 59, 0, TimeSpan.Zero),
            new(2026, 3, 8, 7, 1, 0, TimeSpan.Zero), eastern), "A skipped DST interval is not invented.");
    }
    private sealed class DirectoryReader : IBridgeRequestDispatcher
    {
        public event Action<BridgeEnvelope>? EventReady { add { } remove { } }
        public void Dispose() { }
        public ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken token = default) =>
            ValueTask.FromResult(new BridgeDispatchBatch(BridgeEnvelope.Response(request, request.Name switch {
                "privacy.communityTargets" => new { schemaVersion = 2, communities = new[] { new {
                    code = "SYNTHETIC", name = "Synthetic organization", joinedAt = Day } } },
                "account.getCurrent" => (object)new { schemaVersion = 1, state = "signedIn" },
                "officialFleet.getIdentity" => new { schemaVersion = 1, state = "member", freshness = "live", fleet = new { sourceRef = "officialFleet:7", name = "Synthetic fleet" } },
                _ => throw new Exception("Unexpected synthetic command")
            }, Owner, preserveRequestAccountContext: false), []));
    }
    private static async Task Bridge(string root)
    {
        using var settings = new NotificationSettingsBridgeDispatcher(root, () => 1);
        using var bridge = new NotificationPolicyBridgeDispatcher(settings, new DirectoryReader(), () => (Owner, 1));
        async Task<BridgeEnvelope> Send(int version, object body, bool save = true) =>
            (await bridge.DispatchAsync(BridgeEnvelope.Request("notificationPolicies." + (save ? "save" : "read") + (version == 1 ? "" : "V" + version),
                Guid.NewGuid().ToString("N"), 1, body, Owner))).Response;
        var first = await Send(3, new { schemaVersion = 3 }, false);
        Check(first.Status == "ok" && first.Payload.GetProperty("sources").GetArrayLength() == 2, "v3 advertises both community and official settings.");
        var save = await Send(3, new { schemaVersion = 3, expectedRevision = 0, operationId = Guid.NewGuid().ToString("N"),
            rules = new[] { new { sourceRef = Key, mode = "normal", typeRules = new[] { new { type = "chat", mode = "disabled" } },
                quietHours = new { enabled = true, startMinute = 1320, endMinute = 480, clock = "local" } } } });
        Check(save.Status == "ok", "v3 persists chat and schedule.");
        foreach (var version in new[] { 1, 2 }) {
            var legacy = await Send(version, new { schemaVersion = version, expectedRevision = version, operationId = Guid.NewGuid().ToString("N"),
                rules = new[] { new { sourceRef = Key, mode = "importantOnly" } } });
            Check(legacy.Status == "ok" && settings.ReadPolicies(Owner).Rule(Key).QuietHours!.Enabled &&
                settings.ReadPolicies(Owner).Rule(Key).TypeRules![0].Mode == "disabled", "Old bridge " + version + " keeps v2 extensions.");
        }
        var invalid = await Send(3, new { schemaVersion = 3, expectedRevision = 3, operationId = Guid.NewGuid().ToString("N"),
            rules = new[] { new { sourceRef = Key, mode = "normal", typeRules = new[] { new { type = "chat", mode = "bogus" } } } } });
        Check(invalid.Status != "ok" && settings.ReadPolicies(Owner).Revision == 3, "Invalid v3 choice cannot write.");
    }
    private sealed class Clock : TimeProvider
    {
        internal DateTimeOffset Now = Day;
        internal TimeZoneInfo Zone = TimeZoneInfo.Utc;
        public override DateTimeOffset GetUtcNow() => Now;
        public override TimeZoneInfo LocalTimeZone => Zone;
        public override long TimestampFrequency => TimeSpan.TicksPerSecond;
        public override long GetTimestamp() => Now.UtcTicks;
    }
    private sealed class Sink : IDesktopNotificationSink
    {
        internal readonly List<DesktopNotification> Notices = [];
        public ValueTask<bool> TryPresentAsync(DesktopNotification notice, CancellationToken token) { Notices.Add(notice); return ValueTask.FromResult(true); }
        public void ClearMessages() { }
        public void Clear() { }
        public void Dispose() { }
    }
    private sealed class Output : INotificationAudioOutput
    {
        internal int Count;
        public bool TryPlay(byte[] wave) { Count++; return true; }
        public void Stop() { }
        public void Dispose() { }
    }
    private sealed class Reader : ICommunityNotificationReader
    {
        internal CommunityNotificationFeed Feed = new(Day, []);
        public Task<CommunityNotificationFeed> ReadNotificationsAsync(BridgeAccountContext owner, long generation, CancellationToken token) => Task.FromResult(Feed);
    }
    private static async Task Delivery(string root)
    {
        Directory.CreateDirectory(root);
        var clock = new Clock { Now = Day.AddHours(21).AddMinutes(59) }; var sink = new Sink(); var store = new NotificationPolicyStore(root);
        var q = new NotificationQuietHours(true, 1320, 480);
        // 0.7.3: chat cards only when turned on for the source.
        store.Save(Owner, 0, Guid.NewGuid().ToString("N"), [new(Key, NotificationSourceMode.Normal) { QuietHours = q, TypeRules = [new("chat", "enabled")] },
            new(Official, NotificationSourceMode.Normal) { QuietHours = q, TypeRules = [new("chat", "enabled")] }], () => true, true);
        using var settings = new NotificationSettingsBridgeDispatcher(root, () => 1, () => true, desktop: sink, time: clock);
        var channels = await settings.DispatchAsync(BridgeEnvelope.Request("notificationSettings.save", Guid.NewGuid().ToString("N"), 1,
            new { schemaVersion = 1, expectedRevision = 0, inAppEnabled = true, windowsEnabled = true, position = "bottomRight", preview = "sourceOnly" }));
        Check(channels.Response.Status == "ok", "Synthetic desktop channel configured.");
        var source = new CommunityNotificationSource("source", "Synthetic", Day, true, null, false, [], Key);
        CommunityNotificationSource OfficialSource() => source with { PolicyKey = Official, JoinedAt = null, SourceKind = OrganizationNotificationSourceKind.OfficialFleet };
        CommunityNotificationNotice Notice(CommunityNotificationSource s) => new(Owner, s, NotificationEventKind.OrganizationChat, () => true);
        await settings.PresentCommunityAsync(Notice(source), default);
        Check(sink.Notices.Count == 1 && sink.Notices[0].IsCurrent(), "Pre-quiet desktop card admitted.");
        clock.Now = Day.AddHours(22);
        await settings.PresentCommunityAsync(Notice(source), default); await settings.PresentCommunityAsync(Notice(OfficialSource()), default);
        Check(sink.Notices.Count == 1 && !sink.Notices[0].IsCurrent(), "Quiet start suppresses both organizations and retires an outstanding card.");
        clock.Now = Day.AddDays(1).AddHours(8);
        Check(!sink.Notices[0].IsCurrent(), "Desktop card stays retired after resume beyond quiet hours.");
        clock.Now = clock.Now.AddSeconds(1);
        await settings.PresentCommunityAsync(Notice(source) with { OccurredAt = clock.Now.AddSeconds(-2) }, default);
        Check(sink.Notices.Count == 1, "Message created during quiet hours cannot alert when its poll arrives just after the end.");
        var wave = NotificationAudioTests.Wave(); File.WriteAllBytes(Path.Combine(root, "soft.wav"), wave);
        File.WriteAllBytes(Path.Combine(root, "rally.wav"), wave);
        File.WriteAllText(Path.Combine(root, "cue-catalog.v1.json"), JsonSerializer.Serialize(new { schemaVersion = 1,
            assets = new[] { new { assetId = "soft", cueId = "notify.soft", fileName = "soft.wav", tier = "approved", priority = 320, sha256 = Hash(wave) },
                new { assetId = "rally", cueId = "notify.rally", fileName = "rally.wav", tier = "approved", priority = 320, sha256 = Hash(wave) } } }));
        new NotificationAudioSettingsStore(root).Save(0, true, .5);
        var output = new Output(); var activity = new AchievementCelebrationActivity();
        using var audio = new NotificationAudioBridgeDispatcher(root, NotificationAudioCatalog.Load(root), output, () => 1,
            () => true, clock, canPlaySocial: () => true, celebration: activity);
        clock.Now = Day.AddHours(21).AddMinutes(59); activity.Report(true);
        Check(!audio.TryPlayCommunity(Notice(source)) && output.Count == 0, "Ordinary sound queued before quiet hours.");
        clock.Now = Day.AddDays(1).AddHours(8); activity.Report(false); audio.DrainDeferred();
        Check(output.Count == 0, "Deferred sound crossing sleep and quiet hours never replays.");
        clock.Now = Day.AddHours(23);
        Check(!audio.TryPlayCommunity(Notice(OfficialSource())) && output.Count == 0, "Fresh official chat remains silent during quiet hours.");
        Check(audio.TryPlayRally(() => true) && output.Count == 1, "Independent rally sound bypasses organization quiet hours.");
        clock.Now = Day.AddDays(1).AddHours(8).AddSeconds(1);
        Check(!audio.TryPlayCommunity(Notice(OfficialSource()) with { OccurredAt = clock.Now.AddSeconds(-2) }) && output.Count == 1,
            "Official chat created in quiet hours cannot produce late audio.");
        clock.Now = Day.AddHours(23);
        var reader = new Reader(); using var runtime = new CommunityNotificationRuntime(reader, () => (Owner, 1), settings.PresentCommunityAsync, clock);
        void Feed(long seq) => reader.Feed = new(clock.Now, [source with { Chat = new(seq, 1, true, clock.Now, clock.Now, "", "fixture") }]);
        Feed(1); await runtime.TickAsync(); clock.Now = clock.Now.AddSeconds(1); Feed(2); await runtime.TickAsync();
        var count = sink.Notices.Count;
        clock.Now = Day.AddDays(1).AddHours(8); Feed(2); await runtime.TickAsync();
        Check(sink.Notices.Count == count, "Consumed quiet-period message is not replayed when hours end.");
        clock.Now = clock.Now.AddSeconds(1); Feed(3); await runtime.TickAsync();
        Check(sink.Notices.Count == count + 1, "Next new message after resume can alert.");
        clock.Now = Day.AddDays(2).AddHours(8).AddSeconds(-2);
        var delayedReader = new Reader();
        using var delayed = new CommunityNotificationRuntime(delayedReader, () => (Owner, 1), settings.PresentCommunityAsync, clock);
        void DelayedFeed(long seq, DateTimeOffset created) => delayedReader.Feed = new(clock.Now, [source with {
            Chat = new(seq, 1, true, created, clock.Now, "", "fixture") }]);
        DelayedFeed(1, clock.Now); await delayed.TickAsync();
        clock.Now = clock.Now.AddSeconds(1); DelayedFeed(2, clock.Now); await delayed.TickAsync();
        var quietMessage = clock.Now.AddMilliseconds(500);
        clock.Now = clock.Now.AddSeconds(2); DelayedFeed(3, quietMessage); await delayed.TickAsync();
        Check(sink.Notices.Count == count + 1, "Actual observer carries quiet-period creation time across the end boundary.");
        clock.Now = clock.Now.AddSeconds(1); DelayedFeed(4, clock.Now); await delayed.TickAsync();
        Check(sink.Notices.Count == count + 2, "Actual observer still admits the next post-quiet event.");
    }
    private static async Task Activity(string root)
    {
        Directory.CreateDirectory(root);
        var prefs = new PlayerActivityPreferencesStore(root);
        prefs.Save(new(Enabled: true, Scope: 2, Offline: true, StoppedGame: true, BackgroundOnly: false), prefs.Read().Revision);
        var clock = new Clock { Now = Day.AddHours(21).AddMinutes(59) };
        var policies = new NotificationPolicyStore(root);
        policies.Save(Owner, 0, Guid.NewGuid().ToString("N"), [new(Key, NotificationSourceMode.Normal) {
            QuietHours = new(true, 1320, 480) }], () => true, true);
        var sink = new Sink(); long sequence = 0;
        using var runtime = new PlayerActivityRuntime(root, () => 1, sink, () => new(true, true, false, false), time: clock);
        runtime.ConfigurePolicyOwner(() => Owner);
        Task Observe(string presence) => runtime.ObserveAsync(new(1, "fixture", "organization", "organization", ++sequence, true,
            [new("pilot", "Pilot", "pilot", presence, false, true, PolicySources: [Key],
                Organizations: [new(Key, "Synthetic")])], () => true));
        await Observe("offline"); await Observe("online");
        Check(sink.Notices.Count == 1 && sink.Notices[0].IsCurrent(), "Community player activity uses the organization policy.");
        clock.Now = Day.AddHours(22); await Observe("inGame");
        Check(sink.Notices.Count == 1 && !sink.Notices[0].IsCurrent(), "Community player activity is quiet and pending cards retire.");
        clock.Now = Day.AddDays(1).AddHours(8); await Observe("inGame");
        Check(sink.Notices.Count == 1 && !sink.Notices[0].IsCurrent(), "Activity consumed during quiet hours is not replayed after sleep.");
        clock.Now = clock.Now.AddSeconds(1); await Observe("online");
        Check(sink.Notices.Count == 2, "New activity resumes after quiet hours.");
        clock.Zone = TimeZoneInfo.CreateCustomTimeZone("activity-zone-change", TimeSpan.FromHours(2), "fixture", "fixture");
        Check(!sink.Notices.Last().IsCurrent(), "Time zone changes retire pending activity cards.");
    }
}
