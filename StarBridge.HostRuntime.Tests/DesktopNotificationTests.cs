using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Notifications;
using StarBridge.NativeBridge;
using System.Text.Json;

internal static class DesktopNotificationTests
{
    private sealed class Sink : IDesktopNotificationSink {
        internal readonly List<DesktopNotification> Seen = [];
        internal int Clears;
        internal bool Accept = true;
        internal string Reason = "doNotDisturb";
        public ValueTask<bool> TryPresentAsync(DesktopNotification notification, CancellationToken token) { Seen.Add(notification); return ValueTask.FromResult(Accept); }
        public async ValueTask<DesktopNotificationResult> TryPresentDetailedAsync(DesktopNotification notification, CancellationToken token) => new(await TryPresentAsync(notification, token), Reason);
        public void Clear() => Clears++;
        public void Dispose() { }
    }
    internal static async Task Run()
    {
        await VerifySharedSinkIsolation();
        var root = Path.Combine(Path.GetTempPath(), "starbridge-desktop-ticket-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try {
            new StarBridge.HostRuntime.Settings.ApplicationPreferencesStore(root).Save(
                StarBridge.HostRuntime.Settings.ApplicationPreferencesSnapshot.Default with { MotionPreference = "reduce" });
            long gen = 1; var eligible = true; var sink = new Sink();
            long sequence = 0;
            using var settings = new NotificationSettingsBridgeDispatcher(root, () => gen, () => eligible, desktop: sink,
                activationEvent: (g, payload) => BridgeEnvelope.Event("notificationSettings.activated", g, ++sequence, payload));
            var activations = new List<BridgeEnvelope>(); settings.EventReady += activations.Add;
            BridgeEnvelope Request(string name, object data) => BridgeEnvelope.Request("notificationSettings." + name, Guid.NewGuid().ToString("N"), gen, data);
            async Task<BridgeEnvelope> Call(string name, object data) => (await settings.DispatchAsync(Request(name, data))).Response;
            void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
            async Task Save(int rev, bool enabled = true) => _ = await Call("save", new { schemaVersion = 1, expectedRevision = rev,
                inAppEnabled = true, windowsEnabled = enabled, position = "topLeft", preview = "hiddenDetails" });
            var schema = new { schemaVersion = 1 };
            Check(!(await Call("testDesktop", schema)).Payload.GetProperty("submitted").GetBoolean(), "Disabled tests never bypass the master channel");
            Check((await Call("testDesktop", schema)).Payload.GetProperty("reason").GetString() == "disabled", "Disabled test explains channel state");
            await Save(0);
            Check((await Call("testDesktop", schema)).Payload.GetProperty("submitted").GetBoolean(), "Actual sink handles test");
            Check(sink.Seen.Single().Test && sink.Seen[0].Preview == "hiddenDetails" && sink.Seen[0].Position == "topLeft", "Host-generated synthetic content honors saved privacy/position");
            Check(sink.Seen[0].ReduceMotion, "Native card honors the existing saved app motion preference");
            Check(sink.Seen[0].Activated == null, "Synthetic tests never create a business navigation intent");
            Check(!(await Call("testDesktop", schema)).Payload.GetProperty("submitted").GetBoolean(), "Test click throttled");
            Check((await Call("testDesktop", schema)).Payload.GetProperty("reason").GetString() == "throttled", "Rate limiting has an actionable result");
            Check((await Call("testDesktop", new { schemaVersion = 1, title = "Injected" })).Status == "error", "Reject arbitrary presentation fields");
            Check(!(await Call("presentDesktop", new { schemaVersion = 1, ticket = Guid.NewGuid().ToString("N") })).Payload.GetProperty("submitted").GetBoolean(), "Forged ticket cannot display");
            var time = DateTimeOffset.UtcNow; var invites = new List<object>();
            async Task<BridgeEnvelope> Rooms(int second) {
                var request = BridgeEnvelope.Request("partyRooms.getDirectory", Guid.NewGuid().ToString("N"), gen, schema, new("test", "scm", "one"));
                var response = BridgeEnvelope.Response(request, JsonSerializer.SerializeToElement(new { serverTime = time.AddSeconds(second),
                    currentRoomId = (string?)null, rooms = Array.Empty<object>(), receivedInvitations = invites }));
                return await settings.ObserveAsync(request, response, CancellationToken.None);
            }
            await Rooms(0);
            invites.Add(new { invitationId = "one", createdAt = time.AddSeconds(1), expiresAt = time.AddMinutes(1) });
            var fresh = await Rooms(2);
            var ticket = fresh.Payload.GetProperty("localReminder").GetProperty("desktopTicket").GetString();
            var redeem = new { schemaVersion = 1, ticket };
            eligible = false;
            Check(!(await Call("presentDesktop", redeem)).Payload.GetProperty("submitted").GetBoolean(), "Recheck foreground before native dispatch");
            eligible = true; sink.Accept = false;
            var suppressed = await Call("presentDesktop", redeem);
            Check(!suppressed.Payload.GetProperty("submitted").GetBoolean() && suppressed.Payload.GetProperty("reason").GetString() == "doNotDisturb", "System suppression reason survives dispatch");
            sink.Accept = true;
            var count = sink.Seen.Count;
            Check(!(await Call("presentDesktop", redeem)).Payload.GetProperty("submitted").GetBoolean() && count == sink.Seen.Count, "No replay after an uncertain/suppressed submission");
            await Save(1);
            Check(sink.Seen.All(n => !n.IsCurrent()), "Saving invalidates both synthetic and real queued content");
            invites.Add(new { invitationId = "two", createdAt = time.AddSeconds(3), expiresAt = time.AddMinutes(1) });
            fresh = await Rooms(4); ticket = fresh.Payload.GetProperty("localReminder").GetProperty("desktopTicket").GetString();
            Check((await Call("presentDesktop", new { schemaVersion = 1, ticket })).Payload.GetProperty("submitted").GetBoolean(), "Fresh authorized event can display");
            var real = sink.Seen.Last();
            Check(activations.Count == 0, "Showing a card does not activate or mark it read");
            real.Activated!(); real.Activated!();
            Check(activations.Count == 1 && activations[0].SessionGeneration == gen, "Native activation is emitted once in the current generation");
            var click = new { schemaVersion = 1, activationId = activations[0].Payload.GetProperty("activationId").GetString() };
            Check(!(await Call("consumeActivation", new { schemaVersion = 1, activationId = "forged" })).Payload.TryGetProperty("destination", out _), "Forged activation never routes");
            Check((await Call("consumeActivation", click)).Payload.GetProperty("destination").GetString() == "roomReminders", "A valid click routes only to the known room reminder surface");
            Check(!(await Call("consumeActivation", click)).Payload.TryGetProperty("destination", out _), "Activation cannot be replayed");
            real.Activated!(); Check(activations.Count == 1, "A consumed native click cannot republish");
            gen++; Check(!sink.Seen.Last().IsCurrent(), "Switch-account invalidates content without another fetch");
            real.Activated!(); Check(activations.Count == 1, "Old account cannot publish a navigation intent");
            Check(sink.Clears > 0, "Preference invalidation reaches native window");
            // A source preference is a delivery gate, not a change to room data.
            var owner = new BridgeAccountContext("test", "scm", "one");
            settings.SavePolicies(owner, 0, Guid.NewGuid().ToString("N"),
                [new("room", NotificationSourceMode.DoNotDisturb)], () => true);
            await Rooms(5); // Quiet baseline for the new generation.
            invites.Add(new { invitationId = "muted", createdAt = time.AddSeconds(6), expiresAt = time.AddMinutes(1) });
            Check(!(await Rooms(7)).Payload.TryGetProperty("localReminder", out _),
                "Muted rooms provide neither in-app reminder metadata nor desktop tickets");
            settings.SavePolicies(owner, 1, Guid.NewGuid().ToString("N"),
                [new("room", NotificationSourceMode.ImportantOnly)], () => true);
            Check(!(await Rooms(8)).Payload.TryGetProperty("localReminder", out _), "Unmuting never replays an observed invitation");
            invites.Add(new { invitationId = "important", createdAt = time.AddSeconds(9), expiresAt = time.AddMinutes(1) });
            Check((await Rooms(10)).Payload.TryGetProperty("localReminder", out _), "New room invitations remain important reminders");
        } finally { Directory.Delete(root, true); }
    }

    private sealed class SharedSink : IDesktopNotificationSink
    {
        internal readonly List<DesktopNotification> Active = [];
        public ValueTask<bool> TryPresentAsync(DesktopNotification notification, CancellationToken token)
        { Active.Add(notification); return ValueTask.FromResult(true); }
        public void Clear() => Active.Clear();
        public void ClearMessages() => Active.RemoveAll(n => n.Activity is null);
        public void Dispose() => Clear();
    }

    private static async Task VerifySharedSinkIsolation()
    {
        var root = Path.Combine(Path.GetTempPath(), "starbridge-shared-notice-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var sink = new SharedSink();
            var player = new DesktopNotification(Guid.NewGuid(), false, 0, 0, "fullContent", "topRight", "en", "dark",
                () => true, Activity: new("Sample player", "sample", "Online", "Friends"));
            sink.Active.Add(player);
            using var settings = new NotificationSettingsBridgeDispatcher(root, () => 1, desktop: sink);
            var saved = await settings.DispatchAsync(BridgeEnvelope.Request("notificationSettings.save", "save", 1,
                new { schemaVersion = 1, expectedRevision = 0, inAppEnabled = true, position = "topLeft", preview = "sourceOnly" }));
            if (saved.Response.Status != "ok" || !sink.Active.Contains(player))
                throw new Exception("Saving room notification settings must not clear player activity cards.");
            var room = player with { Id = Guid.NewGuid(), Activity = null };
            sink.Active.Add(room);
            await settings.DispatchAsync(BridgeEnvelope.Request("notificationSettings.clearDesktop", "clear", 1,
                new { schemaVersion = 1 }));
            if (!sink.Active.SequenceEqual([player]))
                throw new Exception("Room desktop clear must remove only room notifications.");
            settings.Reset();
            if (!sink.Active.Contains(player)) throw new Exception("Room observer reset must not own player content.");
        }
        finally { Directory.Delete(root, true); }
    }
}
