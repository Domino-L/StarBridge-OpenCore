using StarBridge.HostRuntime.Communities;
using StarBridge.HostRuntime.Notifications;
using StarBridge.NativeBridge;

internal static class CommunityNotificationDeliveryTests
{
    private sealed class Clock : TimeProvider {
        internal Timer? Scheduled;
        public override ITimer CreateTimer(TimerCallback callback, object? state, TimeSpan dueTime, TimeSpan period) =>
            Scheduled = new(callback, state, dueTime);
        internal sealed class Timer(TimerCallback callback, object? state, TimeSpan due) : ITimer {
            internal TimeSpan Due = due;
            private bool _disposed;
            internal void Fire() { if (!_disposed) callback(state); }
            public bool Change(TimeSpan dueTime, TimeSpan period) { Due = dueTime; return !_disposed; }
            public void Dispose() => _disposed = true;
            public ValueTask DisposeAsync() { Dispose(); return ValueTask.CompletedTask; }
        }
    }
    private sealed class Sink : IDesktopNotificationSink {
        internal List<DesktopNotification> Notices = [];
        public ValueTask<bool> TryPresentAsync(DesktopNotification notice, CancellationToken token) { Notices.Add(notice); return ValueTask.FromResult(true); }
        public void Clear() { }
        public void Dispose() { }
    }
    private sealed class Reader : ICommunityNotificationReader {
        internal required CommunityNotificationFeed Feed;
        internal int Calls;
        internal bool Fail;
        internal TaskCompletionSource<CommunityNotificationFeed>? Pending;
        public async Task<CommunityNotificationFeed> ReadNotificationsAsync(BridgeAccountContext owner, long generation, CancellationToken token) {
            Calls++;
            if (Fail) throw new IOException();
            return Pending == null ? Feed : await Pending.Task.WaitAsync(token);
        }
    }
    internal static async Task Run()
    {
        var schedulingReader = new Reader { Feed = new(DateTimeOffset.UtcNow, []) };
        var clock = new Clock();
        BridgeAccountContext? schedulingOwner = new("fixture", "fixture", "schedule");
        using (var scheduling = new CommunityNotificationRuntime(schedulingReader, () => (schedulingOwner, 1), (_, _) => ValueTask.CompletedTask, clock)) {
            scheduling.Start(); Check(clock.Scheduled!.Due == TimeSpan.FromSeconds(5), "Startup is delayed.");
            clock.Scheduled.Fire(); Check(clock.Scheduled.Due == TimeSpan.FromSeconds(15), "Healthy refresh interval is bounded.");
            schedulingReader.Fail = true;
            foreach (var seconds in new[] { 30, 60, 120, 120 }) {
                clock.Scheduled.Fire(); Check(clock.Scheduled.Due == TimeSpan.FromSeconds(seconds), "Failures back off without unbounded retries.");
            }
            scheduling.Invalidate(); Check(clock.Scheduled.Due == TimeSpan.FromSeconds(5), "Account changes do not inherit another account's long backoff.");
            schedulingOwner = null; var calls = schedulingReader.Calls;
            clock.Scheduled.Fire(); Check(schedulingReader.Calls == calls, "Signed-out timer does not read protected data.");
            scheduling.Dispose(); clock.Scheduled.Fire(); Check(schedulingReader.Calls == calls, "Disposed timer cannot poll.");
        }
        var root = Path.Combine(Path.GetTempPath(), "organization-notice-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try {
            var account = new BridgeAccountContext("fixture", "fixture", "owner");
            var other = account with { Subject = "other" };
            var now = DateTimeOffset.UtcNow;
            var key = NotificationPolicyStore.Organization("A", now.AddDays(-1));
            var store = new NotificationPolicyStore(root);
            Check(store.Read(account).Revision == 0 && store.Read(account).For(key) == NotificationSourceMode.Normal, "Default is normal without a write.");
            var operation = Guid.NewGuid().ToString("N");
            NotificationPolicyRule[] rules = [new(key, NotificationSourceMode.ImportantOnly), new("directMessages", NotificationSourceMode.ImportantOnly)];
            var saved = store.Save(account, 0, operation, rules, () => true);
            Check(saved.Revision == 1 && store.Save(account, 0, operation, rules, () => true).Revision == 1, "Identical retry is acknowledged without duplicate save.");
            Check(new NotificationPolicyStore(root).Read(account).For(key) == NotificationSourceMode.ImportantOnly && store.Read(other).Revision == 0, "Restart persistence and owner isolation.");
            Check(NotificationPolicyStore.Organization("a", now.AddDays(-1).ToOffset(TimeSpan.FromHours(8))) == key && NotificationPolicyStore.Organization("A", now) != key,
                "Case and timezone normalize but rejoining changes policy identity.");
            try { store.Save(account, 0, Guid.NewGuid().ToString("N"), [], () => true); throw new Exception("Expected conflict"); }
            catch (NotificationSettingsConflictException) { }
            try { store.Save(account, 1, Guid.NewGuid().ToString("N"), [], () => false); throw new Exception("Expected owner cancellation"); }
            catch (OperationCanceledException) { }

            var sink = new Sink(); long generation = 1;
            using var delivery = new NotificationSettingsBridgeDispatcher(root, () => generation, () => true,
                desktop: sink, activationEvent: (g, payload) => BridgeEnvelope.Event("notificationSettings.activated", g, 1, payload));
            async Task Channels(int revision, string preview) {
                var response = (await delivery.DispatchAsync(BridgeEnvelope.Request("notificationSettings.save", Guid.NewGuid().ToString("N"), generation,
                    new { schemaVersion = 1, expectedRevision = revision, inAppEnabled = true, windowsEnabled = true,
                        position = "bottomRight", preview }))).Response;
                Check(response.Status == "ok", "Channel preferences save.");
            }
            await Channels(0, "sourceOnly");
            CommunityNotificationFeed Feed(int tick, long sequence, string task) => new(now.AddSeconds(tick), [
                new("scope-key", "Fixture organization", now.AddDays(-1), true,
                    new(sequence, 1, true, now.AddSeconds(tick), now.AddSeconds(tick), "Fixture sender", "Private fixture text"),
                    true, [new(task, now.AddSeconds(tick))], key)
            ]);
            var reader = new Reader { Feed = Feed(0, 1, "old") };
            BridgeAccountContext? current = account;
            using var runtime = new CommunityNotificationRuntime(reader, () => (current, generation), delivery.PresentCommunityAsync);
            await runtime.TickAsync();
            reader.Feed = Feed(1, 2, "new"); await runtime.TickAsync();
            Check(sink.Notices.Count == 1 && sink.Notices[0].Community is { Management: true, Callsign: "", Text: "" }, "Important-only drops ordinary chat and preserves management; content redacted before sink.");
            var notice = sink.Notices[0]; notice.Activated!();
            var activation = (await delivery.DispatchAsync(BridgeEnvelope.Request("notificationSettings.consumeActivation", Guid.NewGuid().ToString("N"), 1,
                new { schemaVersion = 1, activationId = notice.Id.ToString("N") }))).Response;
            Check(activation.Payload.GetProperty("destination").GetString() == "communities", "Click is directory navigation, not a receipt or approval.");
            delivery.SavePolicies(account, 1, Guid.NewGuid().ToString("N"), [new(key, NotificationSourceMode.DoNotDisturb)], () => true);
            Check(!notice.IsCurrent(), "Policy save invalidates pending cards.");
            reader.Feed = Feed(2, 3, "muted"); await runtime.TickAsync();
            Check(sink.Notices.Count == 1, "DND suppresses both kinds.");
            delivery.SavePolicies(account, 2, Guid.NewGuid().ToString("N"), [], () => true);
            reader.Feed = Feed(3, 3, "muted"); await runtime.TickAsync();
            Check(sink.Notices.Count == 1, "Unmuting does not replay consumed events.");
            await Channels(1, "hiddenDetails");
            reader.Feed = Feed(4, 4, "fresh"); await runtime.TickAsync();
            Check(sink.Notices.Count == 3 && sink.Notices.Skip(1).All(item => item.Community is { Name: "", Callsign: "", Text: "" }), "Hidden mode strips identities and content from both events.");
            reader.Fail = true; await runtime.TickAsync(); reader.Fail = false;
            reader.Feed = Feed(5, 5, "outage"); await runtime.TickAsync();
            Check(sink.Notices.Count == 3, "Recovery is quiet.");
            reader.Pending = new(TaskCreationOptions.RunContinuationsAsynchronously);
            var pending = runtime.TickAsync(); var calls = reader.Calls;
            await runtime.TickAsync(); Check(reader.Calls == calls, "Reads cannot overlap.");
            current = null; generation++; runtime.Invalidate(); await pending;
            Check(sink.Notices.All(item => !item.IsCurrent()), "Logout cancels work and invalidates every old card.");
            runtime.Dispose(); await runtime.TickAsync(); Check(reader.Calls == calls, "Disposed loops cannot restart.");
            var policyFile = Directory.GetFiles(Path.Combine(root, "notification-policies-v1"), "*.json").Single();
            File.WriteAllText(policyFile, "{");
            try { store.Read(account); throw new Exception("Corrupt data must not restore normal mode"); }
            catch (System.Text.Json.JsonException) { }
            var beforeCorrupt = sink.Notices.Count;
            await delivery.PresentCommunityAsync(new(account, Feed(6, 6, "corrupt").Sources[0], NotificationEventKind.OrganizationChat, () => true), default);
            Check(sink.Notices.Count == beforeCorrupt, "Corrupt policy storage fails delivery closed.");
        } finally { Directory.Delete(root, true); }
    }
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
}
