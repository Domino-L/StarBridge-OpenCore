using StarBridge.Core.Events;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Privacy;
using StarBridge.HostRuntime.Presence;
using StarBridge.HostRuntime.Support;
using StarBridge.NativeBridge;

internal static class EventSharingRuntimeTests
{
    private sealed class Remote : IEventSharingRemote, IEventFeedRemote
    {
        internal EventSharingRemoteSnapshot Saved = new(1, 1, Guid.NewGuid().ToString("N"), DateTimeOffset.UtcNow, true,
            new(new(true, SharedActivityEventTypes.All), []));
        internal readonly List<(string Action, SharedActivityEvent[] Events)> Calls = [];
        internal bool FailAppend, FailStop;
        public Task<EventSharingRemoteSnapshot> ReadEventsAsync(BridgeAccountContext o, long g, CancellationToken t) => Task.FromResult(Saved);
        public Task<EventSharingRemoteSnapshot> SaveEventsAsync(BridgeAccountContext o, long g, long rev, string op,
            bool enabled, SharedEventPreferences settings, CancellationToken t) => Task.FromResult(Saved = new(1, rev + 1, op, DateTimeOffset.UtcNow, enabled, settings));
        public Task<EventFeedReceipt> WriteEventFeedAsync(BridgeAccountContext o, long g, string action, long rev,
            string? session, long sequence, SharedActivityEvent[] events, CancellationToken t)
        {
            Calls.Add((action, events));
            if (action == "append" && FailAppend || action == "stop" && FailStop) throw new HttpRequestException();
            return Task.FromResult(new EventFeedReceipt(session ?? Guid.NewGuid().ToString("N"), sequence));
        }
    }
    internal static async Task Run()
    {
        var root = Path.Combine(Path.GetTempPath(), "starbridge-event-runtime-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            using var journal = new LocalGameEventJournal(Path.Combine(root, "local-event-log.json"));
            journal.Load();
            var remote = new Remote();
            var input = new PrivacyPublicationInput(new("test", "legacy", "synthetic-owner"), 1, "Synthetic_Handle", true,
                null, GameLogSessionSnapshot.Empty);
            var allowed = false;
            using var runtime = new EventSharingRuntime(remote, remote, journal, () => input, () => allowed, false);
            await runtime.TickAsync();
            Check(remote.Calls.Count == 0, "no global consent means no sends");
            allowed = true;
            journal.Append("life", "PlayerDied", "synthetic historical event");
            await runtime.TickAsync();
            Check(runtime.State == "active" && remote.Calls[^1].Events.Length == 0, "start establishes baseline without history");
            journal.Append("life", "PlayerRespawned", "synthetic new event");
            await runtime.TickAsync();
            Check(remote.Calls[^1].Events is [{ Type: "PlayerRespawned" }], "new event actually enters send callback");
            remote.FailAppend = true; remote.FailStop = true;
            journal.Append("life", "PlayerDowned", "synthetic uncertain event");
            await runtime.TickAsync();
            var count = remote.Calls.Count;
            await runtime.TickAsync();
            Check(runtime.State == "unconfirmed" && remote.Calls.Skip(count).All(c => c.Action == "stop"), "uncertain withdrawal cannot renew positive lease");
            remote.FailAppend = false; remote.FailStop = false;
            await runtime.TickAsync();
            Check(runtime.State == "active" && remote.Calls[^1].Events.Length == 0, "recovery starts fresh, no lost-event replay");
            remote.FailStop = true;
            Check(!await runtime.StopAsync(default), "explicit withdrawal reports uncertainty");
            count = remote.Calls.Count;
            await runtime.TickAsync();
            Check(remote.Calls.Skip(count).All(c => c.Action == "stop"), "explicit failed stop cannot renew a lease");
            remote.FailStop = false;
            await runtime.TickAsync();
            allowed = false;
            await runtime.TickAsync();
            Check(remote.Calls[^1].Action == "stop" && runtime.State == "inactive", "invisibility closes the active session");
            allowed = true; input = input with { Generation = 2 };
            await runtime.TickAsync();
            Check(remote.Calls[^1].Events.Length == 0, "new account generation gets fresh baseline");
            await runtime.SaveAsync(input.Owner, input.Generation, 1, Guid.NewGuid().ToString("N"), false, remote.Saved.Settings!, default);
            await runtime.TickAsync();
            Check(runtime.State == "inactive", "saving off cannot restart events");
            await journal.FlushAsync();
        }
        finally
        {
            if (Path.GetDirectoryName(root) != Path.TrimEndingDirectorySeparator(Path.GetTempPath()) ||
                !Path.GetFileName(root).StartsWith("starbridge-event-runtime-", StringComparison.Ordinal)) throw new InvalidOperationException();
            Directory.Delete(root, true);
        }
    }
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
}
