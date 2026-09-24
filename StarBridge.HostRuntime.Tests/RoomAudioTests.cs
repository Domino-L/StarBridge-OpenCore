using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Notifications;
using StarBridge.HostRuntime.PartyRooms;
using StarBridge.NativeBridge;

internal static class RoomAudioTests
{
    private sealed class Clock : TimeProvider {
        internal long Seconds;
        public override long TimestampFrequency => 1;
        public override long GetTimestamp() => Seconds;
        internal DateTimeOffset Server => DateTimeOffset.Parse("2026-01-01T00:00:00Z").AddSeconds(Seconds);
    }
    private sealed class Output : INotificationAudioOutput {
        internal int Plays; public bool TryPlay(byte[] bytes) { Plays++; return true; }
        public void Stop() { } public void Dispose() { }
    }
    private sealed class Domain : IBridgeRequestDispatcher {
        internal RoomDirectoryView? Value; internal bool Fail;
        public event Action<BridgeEnvelope>? EventReady { add { } remove { } }
        public ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken token = default) =>
            ValueTask.FromResult(new BridgeDispatchBatch(Fail ? BridgeEnvelope.ErrorResponse(request, new("unavailable", "unavailable")) : BridgeEnvelope.Response(request, Value!), []));
        public void Dispose() { }
    }
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
    internal static async Task Run()
    {
        var root = Path.Combine(Path.GetTempPath(), "starbridge-room-audio-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try {
            var wave = NotificationAudioTests.Wave();
            File.WriteAllBytes(Path.Combine(root, "soft.wav"), wave);
            File.WriteAllText(Path.Combine(root, "cue-catalog.v1.json"), NotificationAudioTests.Manifest(wave));
            File.WriteAllText(Path.Combine(root, "notification-audio.v1.json"), "{\"schemaVersion\":1,\"revision\":4,\"enabled\":true,\"volume\":0.3}");
            var store = new NotificationAudioSettingsStore(root);
            Check(!store.Read().DoNotDisturb && store.Read().Volume == .3, "Legacy v1 defaults without overwrite");
            store.Save(4, true, .3, true); store.Save(5, true, .4);
            Check(store.Read().DoNotDisturb, "Legacy flag remains readable without rewriting preferences");
            void Pause(bool pause) { var v = store.Read(); store.Save(v.Revision, !pause, .4); }
            Pause(false);
            var clock = new Clock(); var output = new Output(); var domain = new Domain();
            bool background = true; long generation = 1;
            using var audio = new NotificationAudioBridgeDispatcher(root, NotificationAudioCatalog.Load(root), output, () => generation, () => background, clock);
            using var composite = new CompositeBridgeDispatcher(domain, domain, domain, audio: audio);
            var owner = new BridgeAccountContext("test", "scm", "one");
            var invites = new List<RoomInvitationView>(); var applications = new List<RoomApplicationView>(); bool host = true;
            RoomView Room() => new("room", "Room", "", 4, true, "everyone", "application", false, "optional", "en",
                clock.Server.AddHours(1), null, host, []) { PendingApplications = applications.ToArray() };
            void Invite(string id, int? age = 1) => invites.Add(new(id, "other-room", "Room", "sender", "", "recipient", "", clock.Server.AddHours(1)) {
                CreatedAt = age is { } seconds ? clock.Server.AddSeconds(-seconds) : null });
            async Task Read(int seconds = 8) {
                clock.Seconds += seconds;
                domain.Value = new("room", clock.Server, [Room()]) { ReceivedInvitations = invites.ToArray() };
                domain.Value = PartyRoomReader.Parse(System.Text.Json.JsonSerializer.SerializeToUtf8Bytes(domain.Value,
                    new System.Text.Json.JsonSerializerOptions(BridgeProtocol.JsonOptions) { DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.Never }));
                var request = BridgeEnvelope.Request(AccountBridgeRequestNames.GetPartyRooms, Guid.NewGuid().ToString("N"), generation, new { schemaVersion = 1 }, owner);
                var batch = await composite.DispatchAsync(request);
                Check(batch.Response.Status == (domain.Fail ? "error" : "ok"), "Audio does not change room result");
            }
            Invite("initial"); await Read(); Check(output.Plays == 0, "Initial history silent");
            clock.Seconds += 3; Invite("new1"); Invite("new2"); await Read(); Check(output.Plays == 1, "Enabled master plays one fresh batch even with legacy DoNotDisturb=true");
            await Read(1); Check(output.Plays == 1, "Refresh does not replay");
            clock.Seconds += 2; Invite("cooldown"); await Read(1); Check(output.Plays == 1, "Burst cooldown consumes events");
            await Read(12); Check(output.Plays == 1, "No delayed queue");
            Pause(true); clock.Seconds += 2; Invite("muted"); await Read(); Check(output.Plays == 1, "Disabled master suppresses automatic audio");
            Pause(false); await Read(); Check(output.Plays == 1, "Re-enabling master does not replay muted events");
            background = false; clock.Seconds += 2; Invite("focused"); await Read();
            background = true; await Read(); Check(output.Plays == 1, "Foreground suppression is consumed");
            domain.Fail = true; await Read(); domain.Fail = false;
            clock.Seconds += 2; Invite("reconnect"); await Read(); Check(output.Plays == 1, "Recovery baseline is silent");
            clock.Seconds += 2; Invite("unknown-age", null); Invite("old", 100); await Read(); Check(output.Plays == 1, "Unknown timestamps and history silent");
            clock.Seconds += 2; applications.Add(new("application", "Applicant", "", clock.Server)); await Read(); Check(output.Plays == 2, "Fresh host application sounds");
            host = false; await Read(); host = true;
            clock.Seconds += 2; applications.Add(new("promotion", "Applicant", "", clock.Server)); await Read(); Check(output.Plays == 2, "Host promotion is not a new application event");
            clock.Seconds += 40; Invite("sleep"); await Read(); Check(output.Plays == 2, "Long gap is silent");
            generation++; owner = new("test", "scm", "two"); clock.Seconds += 2; Invite("switch"); await Read(); Check(output.Plays == 2, "Account switch baselines are silent");
            clock.Seconds += 2; Invite("new-owner"); await Read(); Check(output.Plays == 3, "Subsequent new-owner event sounds");
            audio.ResetAutomaticSession(); clock.Seconds += 2; Invite("reset"); await Read(); Check(output.Plays == 3, "Bootstrap reset stays silent");
            store.Save(store.Read().Revision, true, 0);
            clock.Seconds += 2; Invite("zero-volume"); await Read(); Check(output.Plays == 3, "Zero volume remains silent with master enabled");
            store.Save(store.Read().Revision, true, .4);
            await Read(); Check(output.Plays == 3, "Restoring volume does not replay muted events");
            clock.Seconds += 2; Invite("audible-again"); await Read(); Check(output.Plays == 4, "Fresh events sound after restoring volume");
            var policies = new NotificationPolicyStore(root);
            policies.Save(owner, 0, Guid.NewGuid().ToString("N"), [new("room", NotificationSourceMode.DoNotDisturb)], () => true);
            clock.Seconds += 2; Invite("source-muted"); await Read();
            Check(output.Plays == 4, "Room source mute suppresses sound independently of the device sound switch");
            policies.Save(owner, 1, Guid.NewGuid().ToString("N"), [new("room", NotificationSourceMode.ImportantOnly)], () => true);
            await Read(); Check(output.Plays == 4, "Unmuting the room source never replays muted audio");
            clock.Seconds += 2; Invite("source-important"); await Read();
            Check(output.Plays == 5, "Important-only room invitations still sound");
            var observer = new RoomAudioObserver(clock);
            bool Observe(int serverSecond, string id, int createdSecond, long requestGeneration = 2) {
                var start = DateTimeOffset.Parse("2026-01-01T00:00:00Z");
                var r = BridgeEnvelope.Request(AccountBridgeRequestNames.GetPartyRooms, "ordering", requestGeneration, new { schemaVersion = 1 }, owner);
                var data = new RoomDirectoryView(null, start.AddSeconds(serverSecond), []) {
                    ReceivedInvitations = [new("order-" + id, "room", "Room", "sender", "", "recipient", "", start.AddHours(1)) { CreatedAt = start.AddSeconds(createdSecond) }]
                };
                return observer.Observe(r, BridgeEnvelope.Response(r, data), 2);
            }
            Check(!Observe(10, "first", 9) && Observe(20, "second", 19), "Ordering baseline");
            Check(!Observe(15, "first", 9) && !Observe(21, "second", 19), "Older successful reply cannot rewind baseline");
            Check(!Observe(22, "stale", 22, 1) && Observe(23, "third", 22), "Stale generation cannot reset current baseline");
        } finally { Directory.Delete(root, true); }
    }
}
