using StarBridge.HostRuntime.Notifications;

// 0.7.3 (user 11-06: "合成一张"): within 60 s the third member onward is shown on one card.
internal static class PlayerActivityGroupTests
{
    private sealed class Sink : IDesktopNotificationSink {
        internal readonly List<DesktopNotification> Seen = [];
        public ValueTask<bool> TryPresentAsync(DesktopNotification notification, CancellationToken token) {
            lock (Seen) Seen.Add(notification);
            return ValueTask.FromResult(true);
        }
        public void Clear() { }
        public void Dispose() { }
    }

    internal static async Task Run()
    {
        var root = Path.Combine(Path.GetTempPath(), "player-activity-group-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        var hold = PlayerActivityRuntime.GroupHold;
        var settle = PlayerActivityRuntime.OfflineSettle;
        PlayerActivityRuntime.GroupHold = TimeSpan.FromMilliseconds(150);
        PlayerActivityRuntime.OfflineSettle = TimeSpan.FromMilliseconds(50);
        try {
            File.WriteAllText(Path.Combine(root, "notification.settings.json"), "{\"NotificationCooldownSeconds\":0}");
            var prefs = new PlayerActivityPreferencesStore(root);
            prefs.Save(new(Enabled: true, Scope: 7, Offline: true, StoppedGame: true), prefs.Read().Revision);
            var sink = new Sink();
            using var runtime = new PlayerActivityRuntime(root, () => 1, sink, () => new(true, true, false, false));
            var names = new[] { "Alpha", "Bravo", "Charlie", "Delta", "Echo" };
            long sequence = 0;
            Task Observe(params string[] online) => runtime.ObserveAsync(new(1, "scope", "friends", "friends", ++sequence, true,
                names.Select(name => new PlayerActivityObservedMember(name.ToLowerInvariant(), name, name.ToLowerInvariant(),
                    online.Contains(name) ? "online" : "offline", false, true)).ToArray(), () => true));
            int Count() { lock (sink.Seen) return sink.Seen.Count; }
            DesktopNotification Last() { lock (sink.Seen) return sink.Seen[^1]; }
            async Task Settle() => await Task.Delay(500);

            await Observe();
            await Observe("Alpha", "Bravo", "Charlie");
            Check(Count() == 0, "three members coming online together are held for one card");
            await Settle();
            Check(Count() == 1, "the held members arrive as one card");
            var group = Last().Activity!;
            Check(group.Kind == "Online" && group.GroupNames!.SequenceEqual(new[] { "Alpha", "Bravo", "Charlie" }),
                "the grouped card names each member once");
            Check(group.OnlineNow == 3 && group.Tracked == 5, "the grouped card counts online members: 3/5");
            Check(group.MemberKey is null && group.AvatarImageData is null, "a grouped card carries no single member identity");
            Check(Last().IsCurrent(), "a grouped card stays current while its members stay online");
            var grouped = Last();
            await Observe("Alpha", "Bravo");
            Check(!grouped.IsCurrent(), "a grouped card naming someone who left again is no longer current");

            sink.Seen.Clear(); runtime.Reset();
            await Observe();
            await Observe("Alpha");
            await Observe("Alpha", "Bravo");
            Check(Count() == 2 && sink.Seen.All(notice => notice.Activity!.GroupNames is null),
                "the first two members within a minute keep their own cards");
            await Observe("Alpha", "Bravo", "Charlie");
            await Observe("Alpha", "Bravo", "Charlie", "Delta");
            Check(Count() == 2, "from the third member on, arrivals are held");
            await Settle();
            Check(Count() == 3 && Last().Activity!.GroupNames!.SequenceEqual(new[] { "Charlie", "Delta" }),
                "later arrivals join one card; cards already shown are not repeated");
            await Observe("Alpha", "Bravo", "Charlie", "Delta", "Echo");
            await Settle();
            Check(Count() == 4 && Last().Activity!.GroupNames is null && Last().Activity!.Callsign == "Echo",
                "a single held member still gets an ordinary card");

            sink.Seen.Clear();
            await Observe("Delta", "Echo");
            Check(Count() == 0, "three members going offline together are held too");
            await Settle();
            Check(Count() == 1 && Last().Activity!.Kind == "Offline" && Last().Activity!.GroupNames!.Length == 3 &&
                Last().Activity!.OnlineNow == 2, "going offline follows the same rule");

            sink.Seen.Clear(); runtime.Reset();
            await Observe();
            await Observe("Alpha", "Bravo", "Charlie");
            await Observe();
            await Settle();
            Check(Count() == 1 && Last().Activity!.Kind == "Offline",
                "members who left again before the card was shown get only the offline card");

            sink.Seen.Clear(); runtime.Reset();
            await Observe();
            await Observe("Alpha", "Bravo", "Charlie");
            runtime.Reset();
            await Settle();
            Check(Count() == 0, "a reset (account or settings change) discards the held card");

            sink.Seen.Clear(); runtime.Reset();
            await Observe();
            await Observe("Alpha", "Bravo");
            Check(Count() == 2, "two members together keep two cards");
            await PolicyChangeDuringHold();
            Console.WriteLine("PASS 0.7.3 activity cards: the third member onward within a minute shares one card");
        } finally {
            PlayerActivityRuntime.GroupHold = hold;
            PlayerActivityRuntime.OfflineSettle = settle;
            Directory.Delete(root, true);
        }
    }

    // A notification policy change while a card is held drops that held card and keeps later cards coming.
    private static async Task PolicyChangeDuringHold()
    {
        var root = Path.Combine(Path.GetTempPath(), "player-activity-group-policy-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try {
            File.WriteAllText(Path.Combine(root, "notification.settings.json"), "{\"NotificationCooldownSeconds\":0}");
            var prefs = new PlayerActivityPreferencesStore(root);
            prefs.Save(new(Enabled: true, Scope: 7, Offline: true, StoppedGame: true), prefs.Read().Revision);
            var owner = new StarBridge.NativeBridge.BridgeAccountContext("fixture", "fixture", "owner");
            var policies = new NotificationPolicyStore(root);
            void SavePolicies() => policies.Save(owner, policies.Read(owner).Revision, Guid.NewGuid().ToString("N"), [], () => true);
            SavePolicies();
            var sink = new Sink();
            using var runtime = new PlayerActivityRuntime(root, () => 1, sink, () => new(true, true, false, false));
            runtime.ConfigurePolicyOwner(() => owner);
            var names = new[] { "Alpha", "Bravo", "Charlie", "Delta" };
            long sequence = 0;
            Task Observe(params string[] online) => runtime.ObserveAsync(new(1, "scope", "friends", "friends", ++sequence, true,
                names.Select(name => new PlayerActivityObservedMember(name.ToLowerInvariant(), name, name.ToLowerInvariant(),
                    online.Contains(name) ? "online" : "offline", false, true)).ToArray(), () => true));
            int Count() { lock (sink.Seen) return sink.Seen.Count; }

            await Observe();
            await Observe("Alpha", "Bravo", "Charlie");
            Check(Count() == 0, "policy case: three arrivals are held");
            SavePolicies();
            await Observe("Alpha", "Bravo", "Charlie");
            await Observe("Alpha", "Bravo", "Charlie", "Delta");
            await Task.Delay(500);
            Check(sink.Seen.Count(notice => notice.Activity?.Callsign == "Delta") == 1,
                "after a policy change during the hold, the next arrival still gets its card");
        } finally {
            Directory.Delete(root, true);
        }
    }

    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
}
