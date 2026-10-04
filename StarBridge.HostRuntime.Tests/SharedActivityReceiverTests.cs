using StarBridge.Core.Events;
using StarBridge.HostRuntime.Privacy;
using StarBridge.NativeBridge;

internal static class SharedActivityReceiverTests
{
    private sealed class Reader : ISharedActivityReader
    {
        internal SharedActivityEvent[] Events = [];
        internal bool Fail;
        public Task<SharedActivityRead> ReadActivityAsync(BridgeAccountContext owner, long generation, string scope,
            string id, CancellationToken token) => Fail ? throw new HttpRequestException() :
            Task.FromResult(new SharedActivityRead(1, DateTimeOffset.UtcNow, [new("synthetic-publisher", "Pilot", Events)]));
    }
    private sealed class Sink : ISharedActivitySink
    {
        internal readonly List<SharedActivityNotice> Notices = [];
        public ValueTask<bool> TryPresentActivityAsync(SharedActivityNotice notice, CancellationToken token)
        { Notices.Add(notice); return ValueTask.FromResult(true); }
    }
    internal static async Task Run()
    {
        await UsesPureProbeWithoutRecapturing();
        var reader = new Reader(); var sink = new Sink();
        var contextFails = false;
        (BridgeAccountContext? Owner, long Generation, string? Scope, string? Id) current =
            (new("test", "legacy", "synthetic-viewer"), 1, "organization", "TEST");
        SharedActivityEvent Entry() => new(Guid.NewGuid().ToString("N"), "PlayerDied", DateTimeOffset.UtcNow);
        reader.Events = [Entry()];
        using var receiver = new SharedActivityReceiver(reader, sink, () => contextFails ? throw new IOException("synthetic context failure") : current);
        await receiver.TickAsync();
        Check(sink.Notices.Count == 0, "first read does not replay history");
        reader.Events = [..reader.Events, Entry()];
        await receiver.TickAsync();
        Check(sink.Notices.Count == 1 && sink.Notices[0].IsCurrent(), "new event reaches existing overlay sink");
        contextFails = true;
        Check(!sink.Notices[0].IsCurrent(), "authority probe exceptions fail closed instead of escaping into the native UI");
        contextFails = false;
        Check(sink.Notices[0].SourceKey == "Community:TEST", "receiver carries the authorized read scope, not the selected renderer context");
        await receiver.TickAsync();
        Check(sink.Notices.Count == 1, "polls deduplicate events");
        reader.Events = [];
        await receiver.TickAsync();
        Check(!sink.Notices[0].IsCurrent(), "withdrawn permission invalidates queued and displayed events");
        reader.Events = [Entry()];
        await receiver.TickAsync();
        Check(sink.Notices.Count == 2, "new live event is accepted after withdrawal");
        current = current with { Generation = 2 };
        Check(!sink.Notices[1].IsCurrent(), "generation change invalidates without waiting for next poll");
        await receiver.TickAsync();
        Check(sink.Notices.Count == 2, "new generation establishes baseline");
        reader.Fail = true;
        await receiver.TickAsync();
        reader.Fail = false; reader.Events = [Entry()];
        await receiver.TickAsync();
        Check(sink.Notices.Count == 2, "reconnect never replays missed events");
        reader.Events = [..reader.Events, Entry()];
        await receiver.TickAsync();
        Check(sink.Notices.Count == 3, "live events resume after baseline");
        current = current with { Scope = "room", Id = "ROOM" };
        Check(!sink.Notices[2].IsCurrent(), "switching overlay context invalidates queued events immediately");
        await receiver.TickAsync();
        Check(sink.Notices.Count == 3, "room baseline is independent");
    }
    private static async Task UsesPureProbeWithoutRecapturing()
    {
        var reader = new Reader(); var sink = new Sink();
        var stamp = new object(); var captures = 0; var failProbe = false;
        using var receiver = new SharedActivityReceiver(reader, sink, () =>
        {
            captures++;
            return new SharedActivitySubscription(new("test", "legacy", "fixture-probe"), 1, "organization", "A", stamp)
            { IsAuthorized = () => failProbe ? throw new IOException("synthetic probe failure") : true };
        });
        await receiver.TickAsync();
        reader.Events = [new("fixture-event", "PlayerDied", DateTimeOffset.UtcNow)];
        await receiver.TickAsync();
        Check(captures == 2 && sink.Notices.Count == 1, "Fresh validation closures do not replace subscription identity or reset history.");
        for (var i = 0; i < 100; i++) Check(sink.Notices[0].IsCurrent(), "Pure probe remains current.");
        Check(captures == 2, "Queue validity probes never recapture the subscription payload.");
        failProbe = true;
        Check(!sink.Notices[0].IsCurrent(), "A pure-probe exception fails closed without escaping to the UI.");
    }
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
}
