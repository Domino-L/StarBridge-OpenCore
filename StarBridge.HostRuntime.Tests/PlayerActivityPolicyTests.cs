using StarBridge.HostRuntime.Notifications;
using StarBridge.NativeBridge;

internal static class PlayerActivityPolicyTests
{
    private sealed class Sink : IDesktopNotificationSink {
        internal readonly List<DesktopNotification> Seen = [];
        public ValueTask<bool> TryPresentAsync(DesktopNotification notification, CancellationToken token) {
            Seen.Add(notification); return ValueTask.FromResult(true);
        }
        public void Clear() { }
        public void Dispose() { }
    }
    internal static async Task Run()
    {
        var root = Path.Combine(Path.GetTempPath(), "player-source-policy-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try {
            File.WriteAllText(Path.Combine(root, "notification.settings.json"), "{\"NotificationCooldownSeconds\":0}");
            var prefs = new PlayerActivityPreferencesStore(root);
            prefs.Save(new(Enabled: true, Scope: 7, Offline: true, StoppedGame: true), prefs.Read().Revision);
            var owner = new BridgeAccountContext("fixture", "fixture", "owner");
            var policies = new NotificationPolicyStore(root);
            var a = NotificationPolicyStore.Organization("A", DateTimeOffset.UnixEpoch);
            var b = NotificationPolicyStore.Organization("B", DateTimeOffset.UnixEpoch);
            void Save(params NotificationPolicyRule[] rules) => policies.Save(owner, policies.Read(owner).Revision,
                Guid.NewGuid().ToString("N"), rules, () => true);
            var sink = new Sink();
            using var runtime = new PlayerActivityRuntime(root, () => 1, sink, () => new(true, true, false, false));
            runtime.ConfigurePolicyOwner(() => owner);
            long sequence = 0;
            Task Observe(string source, string presence, string[]? paths = null, bool permits = true) => runtime.ObserveAsync(
                new(1, "scope", source, source, ++sequence, true,
                    [new("pilot", "Pilot", "pilot", presence, false, permits, PolicySources: paths,
                        Organizations: paths?.Select(path => new PlayerActivityOrganization(path, path == a ? "Muted" : "Visible")).ToArray())], () => true));
            Save(new(a, NotificationSourceMode.DoNotDisturb), new(b, NotificationSourceMode.Normal));
            await Observe("organization", "offline", [a, b]);
            await Observe("organization", "online", [a, b]);
            Check(sink.Seen.Count == 1, "another allowed organization can deliver the same player's transition once");
            Check(sink.Seen[0].Activity!.Sources!.SequenceEqual(new[] { "organization:Visible" }), "muted organization names never enter the card");
            Save(new(a, NotificationSourceMode.DoNotDisturb), new(b, NotificationSourceMode.ImportantOnly));
            Check(!sink.Seen[0].IsCurrent(), "muting all paths invalidates an already queued card");
            await Observe("organization", "inGame", [a, b]);
            Check(sink.Seen.Count == 1, "player dynamics are not important tasks");
            Save();
            await Observe("organization", "inGame", [a, b]);
            Check(sink.Seen.Count == 1, "unmuting baselines quietly without replaying old activity");
            await Observe("organization", "online", [a, b], permits: false);
            Check(sink.Seen.Count == 1, "delivery rules never grant privacy eligibility");
            foreach (var source in new[] { "friends", "room" }) {
                runtime.Reset(); Save(new NotificationPolicyRule(source, NotificationSourceMode.ImportantOnly));
                await Observe(source, "offline"); await Observe(source, "online");
                Check(sink.Seen.Count == 1, "important-only suppresses ordinary " + source + " transitions");
                Save(); await Observe(source, "online"); await Observe(source, "inGame");
                Check(sink.Seen.Count == 2, "normal mode permits new " + source + " transitions");
                sink.Seen.RemoveAt(1);
            }
            sink.Seen.Clear(); runtime.Reset(); Save();
            await Observe("friends", "offline");
            var file = Directory.GetFiles(Path.Combine(root, "notification-policies-v1"), "*.json").Single();
            var original = File.ReadAllBytes(file);
            File.WriteAllText(file, "invalid");
            await Observe("friends", "online");
            Check(sink.Seen.Count == 0, "Unreadable source preferences fail closed");
            File.WriteAllBytes(file, original);
            await Observe("friends", "inGame");
            Check(sink.Seen.Count == 0, "Storage recovery quietly establishes a fresh baseline");
            await Observe("friends", "online");
            Check(sink.Seen.Count == 1, "New transitions resume after storage recovery");
        } finally { Directory.Delete(root, true); }
    }
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
}
