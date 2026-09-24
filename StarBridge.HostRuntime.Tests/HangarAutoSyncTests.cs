using StarBridge.HostRuntime.Hangar;
using StarBridge.NativeBridge;

internal static class HangarAutoSyncTests
{
    internal static async Task Verify()
    {
        var owner = new BridgeAccountContext("development", "fixture", "owner");
        var calls = 0;
        var notifications = 0;
        var delays = new List<double>();
        using (var sync = new HangarAutoSync((context, generation, revision, token) =>
        {
            Check(context == owner && generation == 7 && revision == 3, "retry identity and revision changed");
            return Task.FromResult(++calls < 9 ? HangarPublicationOutcome.Retryable : HangarPublicationOutcome.Complete);
        }, generation => { Check(generation == 7, "event generation changed"); notifications++; },
        (delay, token) => { delays.Add(delay.TotalSeconds); return Task.CompletedTask; }))
        {
            await sync.Queue(owner, 7, 3).WaitAsync(TimeSpan.FromSeconds(2));
            await sync.Queue(owner, 7, 3);
            Check(calls == 9 && notifications == 1, "same committed import was duplicated");
            Check(delays.SequenceEqual(new double[] { 2, 4, 8, 16, 32, 60, 60, 60 }), "retry backoff is not bounded");
        }
        foreach (var outcome in new[] { HangarPublicationOutcome.Unknown, HangarPublicationOutcome.Rejected })
        {
            calls = 0;
            using var sync = new HangarAutoSync((_, _, _, _) => { calls++; return Task.FromResult(outcome); },
                _ => throw new Exception("failed write emitted success"),
                (_, _) => throw new Exception("uncertain or rejected write was retried"));
            await sync.Queue(owner, 7, 3).WaitAsync(TimeSpan.FromSeconds(2));
            Check(calls == 1, "unsafe replay");
        }
        foreach (var dispose in new[] { false, true })
        {
            var waiting = Signal();
            calls = 0;
            using var sync = new HangarAutoSync((_, _, _, _) =>
            { calls++; return Task.FromResult(HangarPublicationOutcome.Retryable); },
            _ => throw new Exception("cancelled upload emitted success"),
            async (_, token) => { waiting.TrySetResult(); await Task.Delay(Timeout.Infinite, token); });
            var pending = sync.Queue(owner, 7, 3);
            await waiting.Task.WaitAsync(TimeSpan.FromSeconds(2));
            if (dispose) sync.Dispose(); else sync.Invalidate(8);
            await pending.WaitAsync(TimeSpan.FromSeconds(2));
            Check(calls == 1, "cancelled account kept retrying");
        }
        // Even if a transport ignores cancellation and returns success late,
        // only the new committed revision may publish a refresh event.
        var started = Signal();
        var release = Signal();
        notifications = 0;
        using (var sync = new HangarAutoSync(async (_, _, revision, _) =>
        {
            if (revision == 3) { started.TrySetResult(); await release.Task; }
            return HangarPublicationOutcome.Complete;
        }, _ => notifications++))
        {
            var old = sync.Queue(owner, 7, 3);
            await started.Task.WaitAsync(TimeSpan.FromSeconds(2));
            await sync.Queue(owner, 7, 4).WaitAsync(TimeSpan.FromSeconds(2));
            release.TrySetResult();
            await old.WaitAsync(TimeSpan.FromSeconds(2));
            Check(notifications == 1, "superseded upload emitted another refresh");
        }
    }
    private static TaskCompletionSource Signal() => new(TaskCreationOptions.RunContinuationsAsynchronously);
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
}
