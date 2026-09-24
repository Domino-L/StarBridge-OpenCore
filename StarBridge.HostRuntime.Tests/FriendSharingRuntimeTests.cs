using StarBridge.Core.Friends;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Privacy;
using StarBridge.HostRuntime.Presence;
using StarBridge.NativeBridge;

internal static class FriendSharingRuntimeTests
{
    private sealed class Remote : IFriendSharingRemote
    {
        internal FriendSharingRemoteSnapshot Saved = new(1, 1, Guid.NewGuid().ToString("N"), DateTimeOffset.UtcNow, FriendSharedFields.All);
        internal List<string> Calls = [];
        internal bool FailPublish, FailStop;
        public Task<FriendSharingRemoteSnapshot> ReadFriendSharingAsync(BridgeAccountContext owner, long generation, CancellationToken token) => Task.FromResult(Saved);
        public Task<FriendSharingRemoteSnapshot> SaveFriendSharingAsync(BridgeAccountContext owner, long generation, long revision, string operation,
            FriendSharedFields fields, CancellationToken token) => Task.FromResult(Saved = new(1, revision + 1, operation, DateTimeOffset.UtcNow, fields));
        public Task<string> WriteFriendLiveAsync(PrivacyPublicationInput input, string action, long revision, string? session, long sequence, FriendSharingSource? source, CancellationToken token)
        {
            Calls.Add(action);
            if (action == "publish" && FailPublish || action == "stop" && FailStop) throw new HttpRequestException();
            return Task.FromResult(session ?? Guid.NewGuid().ToString("N"));
        }
    }
    internal static async Task Run()
    {
        var remote = new Remote();
        var input = new PrivacyPublicationInput(new("test", "legacy", "synthetic"), 1, "Fixture", true, null, GameLogSessionSnapshot.Empty);
        var allowed = false;
        var visibility = PlayerPresenceVisibilityMode.Online;
        using var runtime = new FriendSharingRuntime(remote, () => input, () => allowed, () => visibility, false);
        await runtime.TickAsync();
        Check(remote.Calls.Count == 0, "no global consent");
        allowed = true;
        await runtime.TickAsync();
        Check(remote.Calls.SequenceEqual(new[] { "start", "publish" }) && runtime.State == "active", "actual publication delegates reached");
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
        var count = remote.Calls.Count;
        await runtime.TickAsync();
        Check(remote.Calls.Skip(count).All(c => c == "stop") && runtime.State == "unconfirmed", "uncertain stop blocks publishing");
        remote.FailPublish = remote.FailStop = false;
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
        await runtime.StopAsync(default, shutdown: true);
        count = remote.Calls.Count;
        await runtime.TickAsync();
        Check(remote.Calls.Count == count, "shutdown cannot restart");
    }
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
}
