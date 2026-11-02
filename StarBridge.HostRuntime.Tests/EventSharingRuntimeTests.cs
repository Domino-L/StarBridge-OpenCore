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
            await LateSettingsCannotStart(root, revokeIdentity: true);
            await LateSettingsCannotStart(root, revokeIdentity: false);
            await LateStartWithdrawsOriginalSession(root);
        }
        finally
        {
            if (Path.GetDirectoryName(root) != Path.TrimEndingDirectorySeparator(Path.GetTempPath()) ||
                !Path.GetFileName(root).StartsWith("starbridge-event-runtime-", StringComparison.Ordinal)) throw new InvalidOperationException();
            Directory.Delete(root, true);
        }
    }
    private static TaskCompletionSource Signal() => new(TaskCreationOptions.RunContinuationsAsynchronously);
    private static Task Finish(Task task) => task.WaitAsync(TimeSpan.FromSeconds(8));
    private static PrivacyPublicationInput SyntheticInput() => new(new("test", "legacy", "synthetic-owner"),
        1, "Synthetic_Handle", true, null, GameLogSessionSnapshot.Empty);

    private static async Task LateSettingsCannotStart(string root, bool revokeIdentity)
    {
        using var journal = new LocalGameEventJournal(Path.Combine(root,
            revokeIdentity ? "late-settings-identity" : "late-settings-consent", "local-event-log.json"));
        journal.Load();
        var remote = new HeldRemote(holdRead: true, holdStart: false);
        var input = SyntheticInput(); var original = input; var allowed = true;
        using var runtime = new EventSharingRuntime(remote, remote, journal, () => input, () => allowed, false);
        var tick = runtime.TickAsync();
        try
        {
            await Finish(remote.ReadEntered.Task);
            Check(!tick.IsCompleted && remote.Calls.Count == 0, "original settings read remains physically in flight");
            if (revokeIdentity) input = input with { IdentityConfirmed = false };
            else allowed = false;
            Check(input.Owner == original.Owner && input.Generation == original.Generation,
                "positive admission closes without replacing the original withdrawal owner");
            journal.Append("life", "PlayerRespawned", "synthetic event during a closed settings read");
            remote.ReadRelease.TrySetResult();
            await Finish(tick);
            await Finish(runtime.TickAsync());
            Check(remote.Calls.Count == 0 && runtime.State == "inactive",
                revokeIdentity ? "late settings cannot start or append after identity confirmation closes"
                    : "late settings cannot start or append after publication consent closes");
        }
        finally
        {
            remote.ReadRelease.TrySetResult();
            await Finish(tick);
            await Finish(runtime.RetireAsync());
        }
    }

    private static async Task LateStartWithdrawsOriginalSession(string root)
    {
        using var journal = new LocalGameEventJournal(Path.Combine(root, "late-start-identity", "local-event-log.json"));
        journal.Load();
        var remote = new HeldRemote(holdRead: false, holdStart: true);
        var input = SyntheticInput(); var original = input;
        using var runtime = new EventSharingRuntime(remote, remote, journal, () => input, () => true, false);
        var tick = runtime.TickAsync();
        try
        {
            await Finish(remote.StartEntered.Task);
            Check(!tick.IsCompleted && remote.Calls is [{ Action: "start" }],
                "original start receipt remains physically in flight");
            input = input with { IdentityConfirmed = false };
            journal.Append("life", "PlayerRespawned", "synthetic event while start admission closes");
            remote.StartRelease.TrySetResult();
            await Finish(tick);
            journal.Append("life", "PlayerDowned", "synthetic event after original withdrawal");
            await Finish(runtime.TickAsync());
            Check(remote.Calls is [{ Action: "start" }, { Action: "stop" }] && runtime.State == "inactive",
                "late start is compensated by stop, never append or publication from the local event source");
            var stopped = remote.Calls[1];
            Check(stopped.Owner == original.Owner && stopped.Generation == original.Generation &&
                stopped.Session == remote.Session && stopped.Sequence == 1 && stopped.Events.Length == 0,
                "withdrawal retains the exact original owner, generation and returned start session");
        }
        finally
        {
            remote.StartRelease.TrySetResult();
            await Finish(tick);
            await Finish(runtime.RetireAsync());
        }
    }

    private sealed class HeldRemote(bool holdRead, bool holdStart) : IEventSharingRemote, IEventFeedRemote
    {
        internal readonly TaskCompletionSource ReadEntered = Signal(), ReadRelease = Signal(),
            StartEntered = Signal(), StartRelease = Signal();
        internal readonly string Session = Guid.NewGuid().ToString("N");
        internal readonly List<(BridgeAccountContext Owner, long Generation, string Action, string? Session,
            long Sequence, SharedActivityEvent[] Events)> Calls = [];
        private readonly EventSharingRemoteSnapshot _saved = new(1, 1, Guid.NewGuid().ToString("N"),
            DateTimeOffset.UtcNow, true, new(new(true, SharedActivityEventTypes.All), []));
        public async Task<EventSharingRemoteSnapshot> ReadEventsAsync(BridgeAccountContext owner, long generation,
            CancellationToken token)
        {
            ReadEntered.TrySetResult();
            if (holdRead) await ReadRelease.Task.ConfigureAwait(false);
            return _saved;
        }
        public Task<EventSharingRemoteSnapshot> SaveEventsAsync(BridgeAccountContext owner, long generation, long revision,
            string operation, bool enabled, SharedEventPreferences settings, CancellationToken token) =>
            Task.FromResult(_saved);
        public async Task<EventFeedReceipt> WriteEventFeedAsync(BridgeAccountContext owner, long generation,
            string action, long revision, string? session, long sequence, SharedActivityEvent[] events, CancellationToken token)
        {
            Calls.Add((owner, generation, action, session, sequence, events));
            if (action == "start")
            {
                StartEntered.TrySetResult();
                if (holdStart) await StartRelease.Task.ConfigureAwait(false);
            }
            return new(session ?? Session, sequence);
        }
    }
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
}
