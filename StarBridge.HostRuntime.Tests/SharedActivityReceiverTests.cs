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
        var reader = new Reader(); var sink = new Sink();
        (BridgeAccountContext? Owner, long Generation, string? Scope, string? Id) current =
            (new("test", "legacy", "synthetic-viewer"), 1, "organization", "TEST");
        SharedActivityEvent Entry() => new(Guid.NewGuid().ToString("N"), "PlayerDied", DateTimeOffset.UtcNow);
        reader.Events = [Entry()];
        using var receiver = new SharedActivityReceiver(reader, sink, () => current);
        await receiver.TickAsync();
        Check(sink.Notices.Count == 0, "first read does not replay history");
        reader.Events = [..reader.Events, Entry()];
        await receiver.TickAsync();
        Check(sink.Notices.Count == 1 && sink.Notices[0].IsCurrent(), "new event reaches existing overlay sink");
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
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
}
