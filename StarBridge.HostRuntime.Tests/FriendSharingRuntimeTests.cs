using StarBridge.Core.Friends;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Privacy;
using StarBridge.HostRuntime.Presence;
using StarBridge.NativeBridge;

internal static class FriendSharingRuntimeTests
{
    internal sealed class Remote : IFriendSharingRemote
    {
        internal FriendSharingRemoteSnapshot Saved = new(1, 1, Guid.NewGuid().ToString("N"), DateTimeOffset.UtcNow, FriendSharedFields.All);
        internal List<string> Calls = [];
        internal bool FailPublish, FailStop, FailRead, RejectStaleRevision;
        internal int Reads;
        internal List<long> Sequences = [];
        internal List<FriendSharingSource> Sources = [];
        internal TaskCompletionSource? PublishEntered, PublishRelease;
        public Task<FriendSharingRemoteSnapshot> ReadFriendSharingAsync(BridgeAccountContext owner, long generation, CancellationToken token)
        {
            Reads++;
            return FailRead ? Task.FromException<FriendSharingRemoteSnapshot>(new HttpRequestException()) : Task.FromResult(Saved);
        }
        public Task<FriendSharingRemoteSnapshot> SaveFriendSharingAsync(BridgeAccountContext owner, long generation, long revision, string operation,
            FriendSharedFields fields, CancellationToken token) => Task.FromResult(Saved = new(1, revision + 1, operation, DateTimeOffset.UtcNow, fields));
        public Task<string> WriteFriendLiveAsync(PrivacyPublicationInput input, string action, long revision, string? session, long sequence, FriendSharingSource? source, CancellationToken token)
        {
            Calls.Add(action);
            if (action == "publish" && RejectStaleRevision && revision != Saved.Revision)
                throw new HttpRequestException("revision changed", null, System.Net.HttpStatusCode.Conflict);
            if (action == "publish") { Sequences.Add(sequence); Sources.Add(source!); }
            if (action == "publish" && PublishRelease is { } release) {
                PublishRelease = null;
                PublishEntered?.TrySetResult();
                return Delayed();
                async Task<string> Delayed() { await release.Task; return session!; }
            }
            if (action == "publish" && FailPublish || action == "stop" && FailStop) throw new HttpRequestException();
            return Task.FromResult(session ?? Guid.NewGuid().ToString("N"));
        }
    }
    internal static async Task Run()
    {
        await VerifyTransportContinuity();
        await VerifyPendingRefresh();
        var remote = new Remote();
        var input = new PrivacyPublicationInput(new("test", "legacy", "synthetic"), 1, "Fixture", true, null, GameLogSessionSnapshot.Empty);
        var allowed = false;
        var visibility = PlayerPresenceVisibilityMode.Online;
        using var runtime = new FriendSharingRuntime(remote, () => input, () => allowed, () => visibility, false);
        var diagnostics = new List<(string Action, string Outcome)>();
        runtime.Diagnostic = (action, outcome) => diagnostics.Add((action, outcome));
        await runtime.TickAsync();
        Check(remote.Calls.Count == 0, "no global consent");
        allowed = true;
        await runtime.TickAsync();
        Check(remote.Calls.SequenceEqual(new[] { "start", "publish" }) && runtime.State == "active", "actual publication delegates reached");
        Check(diagnostics.Contains(("read", "succeeded")) && diagnostics.Contains(("start", "succeeded")) &&
            diagnostics.Contains(("publish", "succeeded")), "publication lifecycle exposes stages without identity data");
        runtime.Pause();
        try
        {
            await runtime.StopAsync(default);
            var stoppedCount = remote.Calls.Count;
            await runtime.TickAsync();
            Check(remote.Calls.Count == stoppedCount, "paused stop cannot republish before consent is stored");
            allowed = false;
        }
        finally { runtime.Resume(); }
        await runtime.TickAsync();
        Check(runtime.State == "inactive", "durable global stop remains inactive after resume");
        allowed = true;
        await runtime.TickAsync();
        remote.FailPublish = true; remote.FailStop = true;
        await runtime.TickAsync();
        visibility = PlayerPresenceVisibilityMode.Invisible;
        await runtime.TickAsync();
        var count = remote.Calls.Count;
        await runtime.TickAsync();
        Check(remote.Calls.Skip(count).All(c => c == "stop") && runtime.State == "unconfirmed", "uncertain stop blocks publishing");
        Check(diagnostics.Contains(("publish", "transportFailed")) && diagnostics.Contains(("stop", "transportFailed")),
            "failed publish and failed retirement remain distinguishable");
        remote.FailPublish = remote.FailStop = false;
        visibility = PlayerPresenceVisibilityMode.Online;
        await runtime.TickAsync();
        Check(runtime.State == "active", "recovers without manual apply");
        visibility = PlayerPresenceVisibilityMode.Invisible;
        await runtime.TickAsync();
        Check(remote.Calls[^1] == "stop" && runtime.State == "inactive", "invisible withdraws");
        visibility = PlayerPresenceVisibilityMode.Online;
        await runtime.TickAsync();
        await runtime.SaveAsync(input.Owner, input.Generation, 1, Guid.NewGuid().ToString("N"), FriendSharedFields.None, default);
        await runtime.TickAsync();
        Check(runtime.State == "inactive", "saved off remains off");
        using var cancelled = new CancellationTokenSource(); cancelled.Cancel();
        try { await runtime.SaveAsync(input.Owner, input.Generation, 2, Guid.NewGuid().ToString("N"), FriendSharedFields.All, cancelled.Token); }
        catch (OperationCanceledException) { }
        await runtime.SaveAsync(input.Owner, input.Generation, 2, Guid.NewGuid().ToString("N"), FriendSharedFields.All, default);
        await runtime.TickAsync();
        Check(runtime.State == "active", "cancelled save does not leave pause stuck");
        runtime.Diagnostic = (_, _) => throw new IOException("synthetic diagnostic failure");
        await runtime.TickAsync();
        Check(runtime.State == "active" && remote.Calls[^1] == "publish", "diagnostic failure cannot interrupt publication");
        await runtime.StopAsync(default, shutdown: true);
        count = remote.Calls.Count;
        await runtime.TickAsync();
        Check(remote.Calls.Count == count, "shutdown cannot restart");
        VerifyJournal();
    }
    private static async Task VerifyPendingRefresh()
    {
        var remote = new Remote {
            PublishEntered = new(TaskCreationOptions.RunContinuationsAsynchronously),
            PublishRelease = new(TaskCreationOptions.RunContinuationsAsynchronously)
        };
        var release = remote.PublishRelease;
        var input = new PrivacyPublicationInput(new("test", "legacy", "pending"), 1, "Fixture", true, null, GameLogSessionSnapshot.Empty);
        using var runtime = new FriendSharingRuntime(remote, () => input, () => true,
            () => PlayerPresenceVisibilityMode.Online, false);
        var first = runtime.TickAsync();
        await remote.PublishEntered.Task.WaitAsync(TimeSpan.FromSeconds(2));
        input = input with { GameVersion = "LIVE" };
        await runtime.TickAsync(); await runtime.TickAsync(); await runtime.TickAsync();
        release.SetResult();
        await first.WaitAsync(TimeSpan.FromSeconds(2));
        Check(remote.Sources.Count == 2 && remote.Sources[^1].Presence == "InGame",
            "busy publication must coalesce and immediately drain the latest state instead of waiting another heartbeat");
    }
    private static async Task VerifyTransportContinuity()
    {
        var remote = new Remote();
        var clock = new ManualTimeProvider();
        var input = new PrivacyPublicationInput(new("test", "legacy", "continuity"), 1, "Fixture", true, null, GameLogSessionSnapshot.Empty);
        var visibility = PlayerPresenceVisibilityMode.Online;
        using var runtime = new FriendSharingRuntime(remote, () => input, () => true, () => visibility, false, clock);
        await runtime.TickAsync();
        remote.FailPublish = true;
        await runtime.TickAsync();
        Check(!remote.Calls.Contains("stop"), "transport failure must not author an explicit offline withdrawal");
        remote.FailPublish = false;
        remote.FailRead = true;
        clock.Advance(TimeSpan.FromSeconds(16));
        await runtime.TickAsync();
        Check(remote.Reads == 2 && remote.Calls.Count(c => c == "publish") == 3 &&
            !remote.Calls.Contains("stop") && runtime.State == "active",
            "transient policy refresh failure keeps publishing under the server-checked revision");
        clock.Advance(TimeSpan.FromSeconds(16));
        await runtime.TickAsync();
        Check(remote.Reads == 3 && remote.Calls.Count(c => c == "publish") == 4,
            "repeated transient policy reads cannot let an authorized source lease expire");
        remote.FailRead = false;
        clock.Advance(TimeSpan.FromSeconds(16));
        input = input with { GameVersion = "LIVE" };
        await runtime.TickAsync();
        Check(remote.Reads == 4 && remote.Calls.Count(c => c == "start") == 1 &&
            remote.Sequences.SequenceEqual(new long[] { 1, 2, 3, 4, 5 }), "recovery rechecks permission and sends a fresh sequence, never replaying");
        Check(remote.Sources[^1].Presence == "InGame" && remote.Sources[0].Presence == "AppOnline",
            "recovery samples current gameplay rather than resending the failed payload");
        remote.Saved = remote.Saved with { Revision = 2 };
        remote.RejectStaleRevision = true;
        remote.FailRead = true;
        clock.Advance(TimeSpan.FromSeconds(16));
        await runtime.TickAsync();
        Check(remote.Calls[^1] == "stop" && runtime.State == "unconfirmed",
            "server revision rejection retires a cached policy instead of bypassing revocation");
        visibility = PlayerPresenceVisibilityMode.Invisible;
        await runtime.TickAsync();
        Check(remote.Calls[^1] == "stop", "explicit invisibility withdraws even while permission reads fail");
        Check(!FriendSharingPublication.IsTransient(new AccountBridgeHostException("events.forbidden"), default) &&
            !FriendSharingPublication.IsTransient(new System.Text.Json.JsonException(), default) &&
            !FriendSharingPublication.IsTransient(new HttpRequestException("fixture", null, System.Net.HttpStatusCode.Unauthorized), default),
            "permission rejection and invalid responses are never softened to transport continuity");
    }
    private sealed class ManualTimeProvider : TimeProvider
    {
        private DateTimeOffset _now = DateTimeOffset.UtcNow;
        public override DateTimeOffset GetUtcNow() => _now;
        internal void Advance(TimeSpan amount) => _now += amount;
    }
    private static void VerifyJournal()
    {
        var root = Directory.CreateTempSubdirectory("friend-sharing-journal-test-").FullName;
        try {
            var journal = new FriendSharingJournal(root);
            var path = Path.Combine(root, "friend-sharing-diagnostics.log");
            journal.Record("private-handle", "succeeded");
            journal.Record("publish", "exception containing a private token");
            Check(!File.Exists(path), "diagnostic whitelist rejects arbitrary text before writing");
            journal.Record("publish", "transportFailed");
            var line = File.ReadAllText(path);
            Check(line.Contains("action=publish outcome=transportFailed") && !line.Contains("private"), "journal stores only fixed lifecycle codes");
            File.WriteAllText(path, new string('x', 128 * 1024));
            journal.Record("stop", "succeeded");
            Check(new FileInfo(path).Length < 512 && File.ReadAllText(path).Contains("action=stop"), "journal remains bounded");
        } finally { Directory.Delete(root, true); }
    }
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
}
