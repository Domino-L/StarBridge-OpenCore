using StarBridge.Core.Events;
using StarBridge.HostRuntime.Overlay;
using StarBridge.HostRuntime.Support;

internal static class LocalGameOverlayEventTests
{
    internal static async Task Verify()
    {
        var root = Path.Combine(Path.GetTempPath(), "starbridge-local-life-" + Guid.NewGuid().ToString("N"));
        var clock = new Clock();
        using var journal = new LocalGameEventJournal(Path.Combine(root, "local-event-log.json"), clock.GetUtcNow);
        journal.Load();
        var generation = 1L;
        var sink = new Sink();
        journal.Append("life", "PlayerDied", "old history");
        using var source = new LocalGameOverlayEventSource(journal, sink, () => generation, clock);
        using var shared = new StarBridge.HostRuntime.Privacy.SharedActivityEventSource(journal, clock);
        var lease = new StarBridge.HostRuntime.Privacy.EventSourceLease(
            new("test", "legacy", "synthetic-display-owner"), generation, 1, SharedActivityEventTypes.All);
        shared.Activate(lease);
        try
        {
            Check(sink.Notices.Count == 0, "opening the source never replays history");
            var batch = new GameLogJournalBatch(journal);
            batch.BeginRead(); batch.Complete(() => true);
            batch.BeginRead();
            foreach (var type in new[] { FleetEventType.PlayerDowned, FleetEventType.PlayerDied,
                         FleetEventType.PlayerRevived, FleetEventType.PlayerRespawned })
                batch.Add(new("life", type.ToString(), "Synthetic " + type, "",
                    type == FleetEventType.PlayerDowned ? LifeEventContext.SafeZoneMedicalResponse : LifeEventContext.Unknown,
                    DisplayPlayer: "AcceptedFixturePilot"));
            batch.Complete(() => true);
            Check(sink.Notices.Count == 4, "actual accepted parser batch must deliver all four local life events");
            Check(sink.Notices[0].Context == LifeEventContext.SafeZoneMedicalResponse, "typed safe-zone context reaches the sink");
            Check(sink.Notices.Take(4).All(n => n.DisplayPlayer == "AcceptedFixturePilot"),
                "accepted local display identity follows the original batch/journal/sink path");
            var wire = System.Text.Json.JsonSerializer.Serialize(shared.Take(lease));
            Check(!wire.Contains("AcceptedFixturePilot") && !wire.Contains("DisplayPlayer"),
                "optional local display identity is excluded from the shared event contract");
            Check(sink.Notices.All(n => n.IsCurrent()), "live generation is valid");
            generation++;
            Check(sink.Notices.All(n => !n.IsCurrent()), "account generation invalidates queued cards");
            foreach (var type in new[] { "GameStarted", "GameStopped", "ServerJoined", "ServerLeft", "PlayerEnteredShip",
                         "PlayerExitedShip", "PlayerControllingShip", "PlayerStoppedDrivingShip" })
                journal.Append("other", type, "Synthetic " + type, displayValue: type == "ServerJoined" ? "US" : "F8C 闪电");
            Check(sink.Notices.Count == 12, "all twelve direct local event types reach the sink");
            Check(sink.Notices.Single(n => n.Type == "ServerJoined").DisplayValue == "US", "parsed region preserved separately from shard detail");
            journal.Append("location", "PlayerLocationChanged", "snapshot already handles location");
            journal.Append("other", "Unknown", "unsupported event");
            Check(sink.Notices.Count == 12, "location snapshots and unsupported types do not create duplicate cards");
            journal.Append("life", "PlayerDied", "fresh death");
            var live = sink.Notices.Last();
            clock.Now = clock.Now.AddMinutes(3);
            Check(!live.IsCurrent(), "stale life cards expire while queued");
            clock.Now = clock.Now.AddMinutes(-3);
            await journal.FlushAsync();
            Check(!File.ReadAllText(journal.Path).Contains("lifeContext", StringComparison.OrdinalIgnoreCase) &&
                  !File.ReadAllText(journal.Path).Contains("displayValue", StringComparison.OrdinalIgnoreCase) &&
                  !File.ReadAllText(journal.Path).Contains("displayPlayer", StringComparison.OrdinalIgnoreCase) &&
                  !File.ReadAllText(journal.Path).Contains("AcceptedFixturePilot", StringComparison.Ordinal), "disk schema excludes ephemeral display identity");
            await journal.ClearAsync();
            Check(!live.IsCurrent(), "clearing history invalidates retained live notices");
        }
        finally
        {
            source.Dispose(); await journal.FlushAsync(); journal.Dispose();
            var full = Path.GetFullPath(root);
            Check(full.StartsWith(Path.GetFullPath(Path.GetTempPath()) + "starbridge-local-life-", StringComparison.OrdinalIgnoreCase), "fixture cleanup boundary");
            if (Directory.Exists(full)) Directory.Delete(full, true);
        }
    }

    private sealed class Clock : TimeProvider
    { internal DateTimeOffset Now = new(2026, 9, 30, 12, 0, 0, TimeSpan.Zero); public override DateTimeOffset GetUtcNow() => Now; }
    internal sealed class Sink : ILocalGameOverlayEventSink
    {
        internal readonly List<LocalGameOverlayNotice> Notices = [];
        public ValueTask<bool> TryPresentLocalGameEventAsync(LocalGameOverlayNotice notice, CancellationToken cancellation)
        { Notices.Add(notice); return new(true); }
    }
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
}
