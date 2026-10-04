using StarBridge.HostRuntime.Notifications;

internal static class PlayerActivityTransitionReliabilityTests
{
    private sealed class Sink : IDesktopNotificationSink
    {
        internal readonly List<DesktopNotification> Seen = [];
        private TaskCompletionSource<DesktopNotification>? _next;
        internal Task<DesktopNotification> Next() {
            var next = new TaskCompletionSource<DesktopNotification>(TaskCreationOptions.RunContinuationsAsynchronously);
            Interlocked.Exchange(ref _next, next);
            return next.Task;
        }
        public ValueTask<bool> TryPresentAsync(DesktopNotification notice, CancellationToken token)
        { Seen.Add(notice); notice.ReportDiagnostic("windowShown"); Interlocked.Exchange(ref _next, null)?.TrySetResult(notice); return ValueTask.FromResult(true); }
        public void Clear() { }
        public void Dispose() { }
    }

    internal static async Task Run()
    {
        var root = Path.Combine(Path.GetTempPath(), "starbridge-transition-fixture-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var store = new PlayerActivityPreferencesStore(root);
            store.Save(new(Enabled: true, Scope: 4, Offline: true, StoppedGame: true), store.Read().Revision);
            var sink = new Sink();
            PlayerActivityEnvironment environment = new(true, true, false, false);
            long timestamp = System.Diagnostics.Stopwatch.GetTimestamp();
            var deliveryEnvironmentUnknown = false;
            var transientHandoffUnknown = false;
            var recoveryUnknownReads = 0;
            var environmentReads = 0;
            PlayerActivityEnvironment ReadEnvironment() =>
                (deliveryEnvironmentUnknown && ++environmentReads >= 2 ||
                    transientHandoffUnknown && ++environmentReads == 2 ||
                    recoveryUnknownReads > 0 && ++environmentReads >= 2 && environmentReads < recoveryUnknownReads + 2)
                    ? new(false, true, true, false) : environment;
            using var runtime = new PlayerActivityRuntime(root, () => 1, sink, ReadEnvironment, () => timestamp);
            long sequence = 0;
            Task Observe(string state, string? avatar = null) => runtime.ObserveAsync(new(1, "fixture", "friends", "friends", ++sequence,
                true, [new("peer", "Fixture", "fixture", state, false, true, avatar)], () => true));
            await Observe("online");
            // Each observed transition is new, including repeated kinds. Identical
            // snapshots are duplicates; a real intervening state is not.
            for (var i = 0; i < 3; i++) { await Observe("offline"); await Observe("online"); }
            if (sink.Seen.Count != 6)
                throw new Exception($"Repeated real offline/online transitions: expected 6, got {sink.Seen.Count}");
            await Observe("online");
            if (sink.Seen.Count != 6) throw new Exception("Identical snapshot must not replay a notification");
            sink.Seen.Clear(); runtime.Reset();
            await Observe("offline");
            await Observe("inGame");
            if (sink.Seen.Single().Activity?.Kind != "Online")
                throw new Exception("Returning from peer-visible offline while already playing must announce Online");
            sink.Seen.Clear(); runtime.Reset();
            await Observe("online");
            for (var i = 0; i < 3; i++) { await Observe("inGame"); await Observe("online"); }
            if (!sink.Seen.Select(n => n.Activity!.Kind).SequenceEqual(
                Enumerable.Range(0, 3).SelectMany(_ => new[] { "StartedGame", "StoppedGame" })))
                throw new Exception("Repeated game starts/stops must preserve every observed transition");
            var deliveryPath = Path.Combine(root, "notification-delivery-diagnostics.log");
            if (!File.Exists(deliveryPath))
                throw new Exception("Player activity needs an event-to-card diagnostic trace for real-device misses");
            var delivery = File.ReadAllText(deliveryPath);
            if (!delivery.Contains("Activity FreshEvent", StringComparison.Ordinal) ||
                !delivery.Contains("Activity NativeAccepted", StringComparison.Ordinal) ||
                !delivery.Contains("Activity NativeLifecycle", StringComparison.Ordinal) ||
                delivery.Contains("Fixture", StringComparison.Ordinal) || delivery.Contains("pilot", StringComparison.Ordinal))
                throw new Exception("Player activity trace must show event, native receipt and card lifecycle without identity");
            var startLine = delivery.Split('\n').First(line => line.Contains("Activity FreshEvent", StringComparison.Ordinal) &&
                line.Contains("result=StartedGame", StringComparison.Ordinal));
            var trace = startLine.Split("trace=", 2)[1].Split(' ', 2)[0];
            if (!delivery.Contains("Activity NativeAccepted trace=" + trace, StringComparison.Ordinal) ||
                !delivery.Contains("Activity NativeLifecycle trace=" + trace, StringComparison.Ordinal))
                throw new Exception("One game-start event must retain its opaque trace through native submission and card lifecycle");
            if (sink.Seen.Any(n => n.Invitations != 0 || n.Activated != null || n.Activity == null))
                throw new Exception("Activity remains a transient activity card, not an inbox item");
            sink.Seen.Clear(); runtime.Reset();
            await Observe("online", "old-avatar");
            await Observe("online", "new-avatar");
            if (sink.Seen.Count != 0) throw new Exception("Avatar-only refresh must not manufacture a status notification");
            await Observe("inGame", "new-avatar");
            if (sink.Seen.Single().Activity?.AvatarImageData != "new-avatar")
                throw new Exception("Activity must carry the latest permitted avatar, not the baseline avatar");
            sink.Seen.Clear(); runtime.Reset();
            await Observe("online");
            await Observe("away"); await Observe("online");
            if (sink.Seen.Count != 0) throw new Exception("Away and return to app online must be silent");
            runtime.Reset();
            await Observe("inGame");
            await Observe("away"); await Observe("inGame");
            if (sink.Seen.Count != 0) throw new Exception("Away must not manufacture game stop/start notifications");
            await Observe("away"); await Observe("offline");
            if (sink.Seen.Single().Activity?.Kind != "Offline")
                throw new Exception("Real disconnection while away still announces offline");
            sink.Seen.Clear(); runtime.Reset();
            store.Save(new(Enabled: true, Scope: 6, StartedGame: true, StoppedGame: true), store.Read().Revision);
            Task ObserveSource(string source, long sourceSequence, string state) => runtime.ObserveAsync(new(
                1, "fixture", source, source, sourceSequence, true,
                [new("peer", "Fixture", "fixture", state, false, true, null)], () => true));
            await ObserveSource("organization", 1, "online");
            await ObserveSource("friends", 2, "online");
            await ObserveSource("friends", 3, "inGame");
            if (sink.Seen.Single().Activity?.Kind != "StartedGame")
                throw new Exception("Friend game-start edge must be visible across overlapping sources");
            await ObserveSource("organization", 4, "online");
            if (sink.Seen.Count != 1)
                throw new Exception("A later stale organization read must not turn a playing friend back online or announce game stop");
            await ObserveSource("organization", 5, "offline");
            if (sink.Seen.Count != 1)
                throw new Exception("A stale organization offline read must not make a live friend flicker offline");
            await ObserveSource("friends", 6, "online");
            if (sink.Seen.Select(notice => notice.Activity?.Kind).SequenceEqual(new[] { "StartedGame", "StoppedGame" }) == false)
                throw new Exception("The next authorized friend-live edge must still announce the real game stop");
            sink.Seen.Clear(); runtime.Reset();
            store.Save(new(Enabled: true, Scope: 4, Online: false, StartedGame: true), store.Read().Revision);
            await Observe("offline"); await Observe("inGame");
            if (sink.Seen.Count != 0) throw new Exception("Hidden game launch must not bypass disabled online notification");
            sink.Seen.Clear(); runtime.Reset();
            store.Save(new(Enabled: true, Scope: 4, StartedGame: true, StoppedGame: true), store.Read().Revision);
            await Observe("online");
            // The game process may become visible before the native overlay
            // status reader completes. That short unknown interval must not
            // consume the online -> in-game edge forever.
            var recovered = sink.Next();
            environment = new(false, true, true, false);
            await Observe("inGame");
            if (sink.Seen.Count != 0) throw new Exception("Unknown environment must not submit an activity card");
            environment = new(true, true, true, false);
            try { await recovered.WaitAsync(TimeSpan.FromSeconds(1)); }
            catch (TimeoutException) { throw new Exception("A lone game-start observation must recover after a transient unknown environment without another source event"); }
            if (sink.Seen.SingleOrDefault()?.Activity?.Kind != "StartedGame")
                throw new Exception("A transient unknown game environment must not lose the observed game-start edge");
            await Observe("inGame");
            if (sink.Seen.Count != 1)
                throw new Exception("A later identical source refresh must not replay the recovered game-start card");
            sink.Seen.Clear(); runtime.Reset();
            environment = new(true, true, false, false);
            await Observe("online");
            environment = new(false, true, true, false);
            await Observe("inGame");
            timestamp += 31L * System.Diagnostics.Stopwatch.Frequency;
            environment = new(true, true, true, false);
            await Observe("inGame");
            if (sink.Seen.Count != 0)
                throw new Exception("A long unknown interval must establish a new baseline, not replay a stale game start");
            await Observe("online");
            if (sink.Seen.SingleOrDefault()?.Activity?.Kind != "StoppedGame")
                throw new Exception("A later real game stop must still notify after stale catch-up was baselined");
            sink.Seen.Clear(); runtime.Reset();
            environment = new(true, true, true, false);
            await Observe("online");
            environmentReads = 0;
            deliveryEnvironmentUnknown = true;
            var handoffRecovered = sink.Next();
            await Observe("inGame");
            if (sink.Seen.Count != 0)
                throw new Exception("Unknown environment during native handoff must not submit a card");
            deliveryEnvironmentUnknown = false;
            try { await handoffRecovered.WaitAsync(TimeSpan.FromSeconds(1)); }
            catch (TimeoutException) { throw new Exception("A native-handoff deferral must recover without another source event"); }
            if (sink.Seen.SingleOrDefault()?.Activity?.Kind != "StartedGame")
                throw new Exception("A game-start card deferred at native handoff must remain current when retried");
            sink.Seen.Clear(); runtime.Reset();
            environment = new(true, true, false, false);
            await Observe("online");
            environmentReads = 0;
            deliveryEnvironmentUnknown = true;
            var recoveryFlap = sink.Next();
            await Observe("inGame");
            deliveryEnvironmentUnknown = false;
            recoveryUnknownReads = 1;
            environmentReads = 0;
            try { await recoveryFlap.WaitAsync(TimeSpan.FromSeconds(1)); }
            catch (TimeoutException) { throw new Exception("A deferred game-start card must survive a one-read unknown environment during recovery"); }
            recoveryUnknownReads = 0;
            if (sink.Seen.SingleOrDefault()?.Activity?.Kind != "StartedGame")
                throw new Exception("Recovery must still present only the current game-start card");
            sink.Seen.Clear(); runtime.Reset();
            environment = new(true, true, false, false);
            await Observe("online");
            environmentReads = 0;
            deliveryEnvironmentUnknown = true;
            var prolongedRecoveryFlap = sink.Next();
            await Observe("inGame");
            deliveryEnvironmentUnknown = false;
            recoveryUnknownReads = 2;
            environmentReads = 0;
            try { await prolongedRecoveryFlap.WaitAsync(TimeSpan.FromSeconds(2)); }
            catch (TimeoutException) { throw new Exception("A deferred card must remain pending when recovery itself is briefly unknown"); }
            recoveryUnknownReads = 0;
            if (sink.Seen.SingleOrDefault()?.Activity?.Kind != "StartedGame")
                throw new Exception("A later stable environment must present the pending game-start card once");
            sink.Seen.Clear(); runtime.Reset();
            environment = new(true, true, false, false);
            await Observe("online");
            environmentReads = 0;
            transientHandoffUnknown = true;
            await Observe("inGame");
            transientHandoffUnknown = false;
            if (sink.Seen.SingleOrDefault()?.Activity?.Kind != "StartedGame")
                throw new Exception("A one-read unknown native environment must not discard a now-current game-start card");
            sink.Seen.Clear(); runtime.Reset();
            await Observe("online");
            environmentReads = 0;
            deliveryEnvironmentUnknown = true;
            await Observe("inGame");
            deliveryEnvironmentUnknown = false;
            timestamp += 31L * System.Diagnostics.Stopwatch.Frequency;
            await Observe("inGame");
            if (sink.Seen.Count != 0)
                throw new Exception("A deferred native card must expire instead of appearing more than 30 seconds late");
            sink.Seen.Clear(); runtime.Reset();
            await Observe("online");
            environmentReads = 0;
            deliveryEnvironmentUnknown = true;
            await Observe("inGame");
            deliveryEnvironmentUnknown = false;
            await Observe("online");
            await Task.Delay(TimeSpan.FromMilliseconds(350));
            if (sink.Seen.Any(notice => notice.Activity?.Kind == "StartedGame"))
                throw new Exception("A game-start card must not reappear after the friend has already stopped playing");
            sink.Seen.Clear(); runtime.Reset();
            environment = new(true, true, false, false);
            await Observe("online");
            environment = new(false, true, true, false);
            await Observe("inGame");
            runtime.Reset();
            environment = new(true, true, true, false);
            await Task.Delay(TimeSpan.FromMilliseconds(350));
            if (sink.Seen.Count != 0)
                throw new Exception("Reset must cancel an unknown-environment retry instead of showing a stale card");
            delivery = File.ReadAllText(deliveryPath);
            if (!delivery.Contains("Activity EnvironmentSuppressed", StringComparison.Ordinal) ||
                !delivery.Contains("result=environmentUnknown", StringComparison.Ordinal))
                throw new Exception("Transient native environment gaps need an anonymous reason code for real-device verification");
        }
        finally { Directory.Delete(root, true); }
    }
}
