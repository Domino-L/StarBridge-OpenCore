using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Notifications;
using StarBridge.NativeBridge;
using StarBridge.HostRuntime.Overlay;

internal static class NotificationSettingsTests
{
    private sealed class Domain : IBridgeRequestDispatcher {
        internal object Value = new { }; internal bool Failed;
        public event Action<BridgeEnvelope>? EventReady { add { } remove { } }
        public ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken token = default) =>
            ValueTask.FromResult(new BridgeDispatchBatch(Failed ? BridgeEnvelope.ErrorResponse(request, new("unavailable", "unavailable")) : BridgeEnvelope.Response(request, Value), []));
        public void Dispose() { }
    }
    private static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
    internal static async Task Run() {
        var root = Path.Combine(Path.GetTempPath(), "starbridge-notification-settings-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try {
            long generation = 3;
            bool desktopEligible = true;
            using var settings = new NotificationSettingsBridgeDispatcher(root, () => generation, () => desktopEligible);
            var domain = new Domain();
            using var composite = new CompositeBridgeDispatcher(domain, domain, domain, notifications: settings);
            async Task<BridgeEnvelope> Call(string name, object payload, long gen = 3, BridgeAccountContext? account = null) =>
                (await composite.DispatchAsync(BridgeEnvelope.Request(name, Guid.NewGuid().ToString("N"), gen, payload, account))).Response;
            Task<BridgeEnvelope> Save(int revision, bool enabled = true, string position = "topLeft") => Call("notificationSettings.save",
                new { schemaVersion = 1, expectedRevision = revision, inAppEnabled = enabled, position, preview = "hiddenDetails" });
            var read = await Call("notificationSettings.read", new { schemaVersion = 1 });
            Check(read.Status == "ok" && read.Payload.GetProperty("inAppEnabled").GetBoolean(), "Default device preference available without an account");
            Check(!read.Payload.GetProperty("windowsEnabled").GetBoolean(), "Desktop notification opt-in defaults off");
            File.WriteAllText(Path.Combine(root, "notification-settings.v1.json"), "{\"schemaVersion\":1,\"revision\":0,\"inAppEnabled\":true,\"position\":\"bottomRight\",\"preview\":\"sourceOnly\"}");
            foreach (var name in NotificationSettingsBridgeDispatcher.AdvertisedCapabilities) Check(!BridgeRequestPolicy.RequiresAccountContext(name), "No account for local preferences");
            Check((await Save(0)).Status == "ok", "Save through composite");
            using (var reopened = new NotificationSettingsBridgeDispatcher(root, () => generation)) {
                var saved = (await reopened.DispatchAsync(BridgeEnvelope.Request("notificationSettings.read", "reopen", 3, new { schemaVersion = 1 }))).Response;
                Check(saved.Payload.GetProperty("position").GetString() == "topLeft" && saved.Payload.GetProperty("revision").GetInt32() == 1, "Actual disk reopen");
            }
            Check((await Save(0)).Error?.Code == "notificationSettings.write_conflict", "Stale settings cannot overwrite");
            Check((await Save(1, position: "invalid")).Status == "error", "Reject unsupported position");
            Check((await Call("notificationSettings.read", new { schemaVersion = 1 }, 2)).Status == "error", "Reject stale generation");
            var owner = new BridgeAccountContext("test", "scm", "one");
            Check((await Call("notificationSettings.read", new { schemaVersion = 1 }, account: owner)).Status == "error", "Reject account-scoped local settings request");
            var start = DateTimeOffset.Parse("2026-01-01T00:00:00Z");
            var invites = new List<object>();
            async Task<BridgeEnvelope> Rooms(int seconds, BridgeAccountContext? actor = null) {
                domain.Value = System.Text.Json.JsonSerializer.SerializeToElement(new { schemaVersion = 1, serverTime = start.AddSeconds(seconds), currentRoomId = (string?)null,
                    rooms = Array.Empty<object>(), receivedInvitations = invites });
                return await Call("partyRooms.getDirectory", new { schemaVersion = 1 }, account: actor ?? owner);
            }
            void Invite(string id, int seconds) => invites.Add(new { invitationId = id, createdAt = start.AddSeconds(seconds), expiresAt = start.AddHours(1) });
            Check(!(await Rooms(0)).Payload.TryGetProperty("localReminder", out _), "First read quiet");
            Invite("first", 1);
            var fresh = await Rooms(2);
            Check(fresh.Payload.GetProperty("localReminder").GetProperty("invitations").GetInt32() == 1 && fresh.AccountContext == owner, "Fresh authenticated reminder and owner retained");
            Check(fresh.Payload.GetProperty("localReminder").EnumerateObject().Count() == 5, "Only version, revision, counts and desktop eligibility exposed");
            Check(!(await Rooms(3)).Payload.TryGetProperty("localReminder", out _), "Refresh never repeats");
            await Save(1, false); Invite("muted", 4);
            Check(!(await Rooms(5)).Payload.TryGetProperty("localReminder", out _), "Disabled consumes fresh events");
            await Save(2);
            Check(!(await Rooms(6)).Payload.TryGetProperty("localReminder", out _), "Enable never replays muted history");
            domain.Failed = true; await Rooms(7); domain.Failed = false; Invite("recovery", 8);
            Check(!(await Rooms(9)).Payload.TryGetProperty("localReminder", out _), "Recovery quiet");
            Invite("different-owner", 10);
            Check(!(await Rooms(11, new("test", "scm", "two"))).Payload.TryGetProperty("localReminder", out _), "Account switch quiet");
            Check((await Call("notificationSettings.save", new { schemaVersion = 1, expectedRevision = 3,
                inAppEnabled = false, windowsEnabled = true, position = "bottomRight", preview = "hiddenDetails" })).Status == "ok", "Desktop independently enabled");
            Invite("desktop", 12);
            var desktop = await Rooms(13, new("test", "scm", "two"));
            Check(desktop.Payload.GetProperty("localReminder").GetProperty("desktopEligible").GetBoolean(), "Desktop works without in-app enabled");
            desktopEligible = false; Invite("game", 14);
            Check(!(await Rooms(15, new("test", "scm", "two"))).Payload.GetProperty("localReminder").GetProperty("desktopEligible").GetBoolean(), "Foreground or game state suppresses desktop");
            desktopEligible = true;
            Check(!(await Rooms(16, new("test", "scm", "two"))).Payload.TryGetProperty("localReminder", out _), "Suppressed desktop does not replay");
            Check((await Save(4)).Payload.GetProperty("windowsEnabled").GetBoolean(), "Older save preserves desktop preference");
            var file = Path.Combine(root, "notification-settings.v1.json"); File.WriteAllText(file, "{}");
            Check((await Save(3)).Status == "error" && File.ReadAllText(file) == "{}", "Corrupt settings preserved");
            Check(!Directory.EnumerateFiles(root, "*.tmp").Any(), "No abandoned temporary writes");
        } finally { Directory.Delete(root, true); }
        await VerifyOverlay();
        VerifyExpiryBudget();
    }

    private static void VerifyExpiryBudget() {
        var observer = new RoomAudioObserver();
        var instant = DateTimeOffset.Parse("2026-01-01T00:00:00Z");
        var request = BridgeEnvelope.Request("partyRooms.getDirectory", "expiry", 1, new { schemaVersion = 1 }, new("test", "scm", "one"));
        BridgeEnvelope Snapshot(int seconds, object[] invites) => BridgeEnvelope.Response(request,
            System.Text.Json.JsonSerializer.SerializeToElement(new { serverTime = instant.AddSeconds(seconds),
                currentRoomId = (string?)null, rooms = Array.Empty<object>(), receivedInvitations = invites }));
        observer.Observe(request, Snapshot(0, []), 1);
        Check(observer.Observe(request, Snapshot(2, [new { invitationId = "soon", createdAt = instant.AddSeconds(1), expiresAt = instant.AddSeconds(3) }]), 1),
            "Near-expiry invite is a current event");
        Check(observer.FreshLifetime == TimeSpan.FromSeconds(1), "Presentation budget never outlives server expiry");
        Check(!observer.Observe(request, Snapshot(3, [new { invitationId = "soon", createdAt = instant.AddSeconds(1), expiresAt = instant.AddSeconds(3) }]), 1) &&
            !observer.ContainsAll(["invite:soon"]), "Expired target is removed from visible reminder eligibility");
    }

    private sealed class OverlaySink : IInformationOverlayReminderSink {
        internal readonly List<InformationOverlayReminder> Seen = [];
        internal bool Accept = true;
        internal int Clears;
        internal Func<Task>? DuringPresent;
        public async ValueTask<bool> TryPresentAsync(InformationOverlayReminder reminder, CancellationToken token) {
            Seen.Add(reminder);
            if (DuringPresent != null) await DuringPresent();
            return Accept && reminder.IsCurrent();
        }
        public void ClearReminder() => Clears++;
    }

    private static async Task VerifyOverlay() {
        var root = Path.Combine(Path.GetTempPath(), "starbridge-overlay-reminder-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try {
            long generation = 1;
            var sink = new OverlaySink();
            var domain = new Domain();
            using var settings = new NotificationSettingsBridgeDispatcher(root, () => generation, () => true, sink);
            using var composite = new CompositeBridgeDispatcher(domain, domain, domain, notifications: settings);
            var owner = new BridgeAccountContext("test", "scm", "one");
            async Task<BridgeEnvelope> Call(string name, object payload, bool account = false) =>
                (await composite.DispatchAsync(BridgeEnvelope.Request(name, Guid.NewGuid().ToString("N"), generation,
                    payload, account ? owner : null))).Response;
            Task<BridgeEnvelope> Save(int revision, bool enabled) => Call("notificationSettings.save", new {
                schemaVersion = 1, expectedRevision = revision, inAppEnabled = false, windowsEnabled = true,
                overlayEnabled = enabled, position = "bottomRight", preview = "hiddenDetails" });
            var path = Path.Combine(root, "notification-settings.v1.json");
            var legacy = "{\"schemaVersion\":1,\"revision\":0,\"inAppEnabled\":true,\"position\":\"bottomRight\",\"preview\":\"sourceOnly\"}";
            File.WriteAllText(path, legacy);
            var read = await Call("notificationSettings.read", new { schemaVersion = 1 });
            Check(read.Payload.GetProperty("overlayEnabled").GetBoolean() && File.ReadAllText(path) == legacy,
                "New sink supports overlay; reading old settings never rewrites them");
            await Save(0, true);
            var time = DateTimeOffset.Parse("2026-01-01T00:00:00Z");
            var invites = new List<object>();
            void Invite(string id, int second) => invites.Add(new { invitationId = id, createdAt = time.AddSeconds(second), expiresAt = time.AddHours(1) });
            async Task<BridgeEnvelope> Rooms(int second) {
                domain.Value = System.Text.Json.JsonSerializer.SerializeToElement(new { serverTime = time.AddSeconds(second), currentRoomId = (string?)null,
                    rooms = Array.Empty<object>(), receivedInvitations = invites });
                return await Call("partyRooms.getDirectory", new { schemaVersion = 1 }, true);
            }
            await Rooms(0); Check(sink.Seen.Count == 0, "Cold start never calls overlay");
            Invite("one", 1);
            var first = await Rooms(2);
            Check(sink.Seen.Count == 1 && sink.Seen[0].Preview == "hiddenDetails" && sink.Seen[0].IsCurrent(), "Real new invite reaches trusted sink with saved privacy");
            Check(first.Payload.GetProperty("localReminder").GetProperty("overlayHandled").GetBoolean() &&
                !first.Payload.GetProperty("localReminder").GetProperty("desktopEligible").GetBoolean(), "Only one visual channel");
            await Rooms(3); Check(sink.Seen.Count == 1, "Same event not repeated");
            invites.Clear(); await Rooms(4);
            Check(!sink.Seen[0].IsCurrent(), "Withdrawn or expired target invalidates visible reminder");
            sink.Accept = false; Invite("closed", 5);
            var fallback = await Rooms(6);
            Check(fallback.Payload.GetProperty("localReminder").GetProperty("desktopEligible").GetBoolean(), "Unavailable overlay allows eligible desktop");
            await Save(1, false); Invite("muted", 7); await Rooms(8);
            Check(sink.Seen.Count == 2, "Disabled overlay never calls sink");
            var oldSave = await Call("notificationSettings.save", new { schemaVersion = 1, expectedRevision = 2,
                inAppEnabled = true, position = "topLeft", preview = "hiddenDetails" });
            Check(!oldSave.Payload.GetProperty("overlayEnabled").GetBoolean(), "Old save preserves disabled overlay");
            await Save(3, true); await Rooms(9); Check(sink.Seen.Count == 2, "Enable never replays history");
            sink.Accept = true;
            sink.DuringPresent = async () => { await Save(4, false); };
            Invite("race", 10);
            Check(!(await Rooms(11)).Payload.TryGetProperty("localReminder", out _), "Save during native dispatch cancels late visual metadata");
            Check(!sink.Seen.Last().IsCurrent(), "Queued render guard invalidates immediately on save");
            sink.DuringPresent = null;
            await Save(5, true); Invite("owner", 12); await Rooms(13);
            generation++;
            Check(!sink.Seen.Last().IsCurrent(), "Owner generation change invalidates queued render without another room read");
            await Rooms(14); Check(sink.Seen.Count == 4, "New generation establishes quiet baseline");
            domain.Failed = true; await Rooms(15);
            Check(sink.Clears > 0, "Cleanup forwarded to existing renderer");
        } finally { Directory.Delete(root, true); }
    }
}
