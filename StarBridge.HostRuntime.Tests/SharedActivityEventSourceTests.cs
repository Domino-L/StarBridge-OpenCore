using System.Text.Json;
using StarBridge.Core.Events;
using StarBridge.HostRuntime.Privacy;
using StarBridge.HostRuntime.Support;
using StarBridge.NativeBridge;

internal static class SharedActivityEventSourceTests
{
    private sealed class Clock : TimeProvider
    {
        internal DateTimeOffset Now = DateTimeOffset.UnixEpoch.AddDays(20000);
        public override DateTimeOffset GetUtcNow() => Now;
    }

    internal static async Task Run()
    {
        var root = Path.Combine(Path.GetTempPath(), "starbridge-event-source-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var clock = new Clock();
            using var journal = new LocalGameEventJournal(Path.Combine(root, "local-event-log.json"), () => clock.Now);
            journal.Load();
            using var source = new SharedActivityEventSource(journal, clock);
            var lease = new EventSourceLease(new BridgeAccountContext("test", "legacy", "synthetic-event-owner"),
                1, 1, SharedActivityEventTypes.All);
            void Add(string type, string title = "synthetic-title")
            {
                clock.Now = clock.Now.AddMilliseconds(1);
                journal.Append("other", type, title, "private-local-detail");
            }

            Add("GameStarted");
            source.Activate(lease);
            Check(source.Take(lease).Length == 0, "activation does not upload journal history");
            foreach (var type in new[] { "GameStopped", "ServerJoined", "PlayerEnteredShip", "PlayerLocationChanged", "PlayerDowned" })
                Add(type);
            Add("PlayerOnline"); Add("PlayerNavigationTargetChanged"); Add("Unknown");
            var batch = source.Take(lease);
            Check(batch.Length == 5, "five independent categories, no identity/navigation/unknown events");
            Check(!JsonSerializer.Serialize(batch).Contains("private-local-detail") &&
                !JsonSerializer.Serialize(batch).Contains("synthetic-title"), "local presentation never enters wire payload");
            Check(source.Take(lease).Length == 0, "destructive take prevents replay");

            Add("PlayerDied"); Add("PlayerDied");
            Check(source.Take(lease).Length == 1, "reuse journal duplicate suppression");
            Add("PlayerRevived");
            source.Activate(null);
            Add("ServerLeft");
            source.Activate(lease);
            Check(source.Take(lease).Length == 0, "withdrawal discards pending and disabled events");
            Add("GameStarted");
            var next = lease with { Generation = 2, Revision = 2, Types = SharedActivityEventTypes.Life };
            source.Activate(next);
            Add("GameStopped"); Add("PlayerRespawned");
            Check(source.Take(lease).Length == 0, "stale account generation cannot take events");
            Check(source.Take(next) is [{ Type: "PlayerRespawned" }], "new selection excludes old pending and presence");
            Add("PlayerDowned");
            clock.Now = clock.Now.AddMinutes(3);
            Check(source.Take(next).Length == 0, "expired events never leave source");
            for (var i = 0; i < 80; i++) Add("PlayerDied", "synthetic-" + i);
            Check(source.Take(next).Length == SharedActivityEventSource.MaximumPending, "pending events bounded");
            using (journal.SubscribeNewEntries(_ => throw new InvalidOperationException("synthetic consumer failure")))
            {
                Add("PlayerRevived");
                Check(source.Take(next).Length == 1, "consumer failure cannot break journal or other consumers");
            }
            await journal.FlushAsync();
        }
        finally
        {
            if (Path.GetDirectoryName(root) != Path.TrimEndingDirectorySeparator(Path.GetTempPath()) ||
                !Path.GetFileName(root).StartsWith("starbridge-event-source-", StringComparison.Ordinal))
                throw new InvalidOperationException("Unexpected fixture root.");
            Directory.Delete(root, true);
        }
    }

    private static void Check(bool value, string message)
    { if (!value) throw new InvalidOperationException(message); }
}
