using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Overlay;
using StarBridge.NativeBridge;

internal static class OverlayWorkspaceReuseTests
{
    internal static async Task Run()
    {
        var owner = new BridgeAccountContext("test", "example.invalid", "viewer");
        var now = DateTimeOffset.Parse("2026-09-30T00:00:00Z");
        long generation = 1;
        var reader = new Reader();
        using var source = new OverlayCommunitySource(() => (owner, generation), reader, false, () => now);
        var roster = new InformationOverlayCommunityContent("A", "Fixture",
            [new("Fixture", "Fixture", "", "InGame", "Ship", "Location", "US", true)]);
        source.ObserveWorkspace(owner, 1, 1, now, roster);
        var first = source.ReadForDisplay();
        Check(first?.Members.Count == 1 && reader.Reads == 0, "first frame reuses the authorized UI result without network");
        var continuity = first!.ContinuityId;
        for (var i = 2; i <= 8; i++)
        {
            now += TimeSpan.FromSeconds(15);
            source.ObserveWorkspace(owner, 1, i, now, roster);
            Check(source.Read()?.ContinuityId == continuity, "successful UI updates renew one source without blank transitions");
        }
        var offline = roster with { Members = [roster.Members[0] with { Presence = "Offline" }] };
        source.ObserveWorkspace(owner, 1, 9, now, offline);
        Check(source.Read()?.Members[0].Presence == "Offline", "presence change updates a row, not organization membership");
        source.ObserveWorkspace(owner, 1, 8, now, roster);
        Check(source.Read()?.Members[0].Presence == "Offline", "out-of-order UI completion cannot restore an older row");
        var acceptedAt = now;
        source.SuspendDisplayDemand();
        now += TimeSpan.FromSeconds(39);
        Check(source.ReadForDisplay() is not null, "close/reopen reuses the original bounded lease");
        now = acceptedAt.AddSeconds(40);
        Check(source.Read() is null, "accessors never renew authority and exact expiry still clears");
        source.ObserveWorkspace(owner, 1, 10, acceptedAt, roster);
        Check(source.Read() is null, "a response held longer than its authority budget cannot seed display");
        source.ObserveWorkspace(owner, 1, 11, now, roster);
        reader.Failure = new AccountBridgeHostException("communities.notAllowed");
        await source.RefreshAsync();
        Check(source.Read() is null && source.ReadForDisplay() is null, "terminal revocation cannot resurrect from the UI cache");
        reader.Failure = null;
        source.ObserveWorkspace(owner, 1, 12, now, roster);
        generation++;
        Check(source.Read() is null, "account generation clears shared UI snapshots");
        source.ObserveWorkspace(owner, 1, 13, now, roster);
        Check(source.Read() is null, "late old-account UI callback is discarded");
        source.Select("B");
        source.ObserveWorkspace(owner, 2, 14, now, roster);
        Check(source.Read() is null, "manual organization selection cannot fall through to the visible page");
        source.Select("A");
        Check(source.Read()?.Code == "A", "switching back reuses only the matching unexpired roster");
        await LateOverlayFailure();
        await FirstOpenAfterIdle();
        await IdlePreparationHonorsSourceAndAuthority();
        await ColdOpeningWaitsForExistingRead();
        await DirectoryReuseBoundaries();
    }

    private static async Task DirectoryReuseBoundaries()
    {
        var owner = new BridgeAccountContext("test", "example.invalid", "viewer");
        var now = DateTimeOffset.Parse("2026-09-30T00:00:00Z");
        long generation = 1;
        var reader = new Reader();
        using var source = new OverlayCommunitySource(() => (owner, generation), reader, false, () => now);
        var a = new InformationOverlayCommunityContent("A", "First", []);
        var b = new InformationOverlayCommunityContent("B", "Second", []);
        source.ObserveDirectory(owner, 1, 1, now, [b, a]);
        Check(source.Read()?.Code == "A", "directory order cannot change automatic source selection");
        var continuity = source.Read()!.ContinuityId;
        now += TimeSpan.FromSeconds(10);
        source.ObserveDirectory(owner, 1, 2, now, [a, b]);
        Check(source.Read()?.ContinuityId == continuity, "directory refresh does not reopen the source or replay notices");
        source.Select("B");
        Check(source.Read()?.Code == "B", "manual choice uses its own authorized directory roster");
        now += TimeSpan.FromSeconds(1);
        source.ObserveDirectory(owner, 1, 3, now, [a]);
        Check(source.Read() is null, "revoked manual selection never falls through to another organization");
        source.ObserveDirectory(owner, 1, 2, now, [a, b]);
        Check(source.Read() is null, "late directory cannot revive revoked membership");
        source.Select(null);
        Check(source.Read()?.Code == "A", "automatic mode reuses the remaining authorized organization");
        now += TimeSpan.FromSeconds(40);
        Check(source.Read() is null, "directory data has the original 40 second lease");
        source.ObserveDirectory(owner, 1, 4, now.AddSeconds(-40), [a]);
        Check(source.Read() is null, "a delayed directory cannot restart an expired lease");
        var pending = new TaskCompletionSource<InformationOverlayCommunityContent>(TaskCreationOptions.RunContinuationsAsynchronously);
        reader.Pending = pending.Task;
        var refresh = source.RefreshAsync();
        now += TimeSpan.FromSeconds(1);
        source.ObserveDirectory(owner, 1, 5, now, []);
        pending.SetResult(a);
        await refresh;
        Check(source.Read() is null, "new empty directory invalidates an earlier in-flight overlay read even before first content");
        generation++;
        source.ObserveDirectory(owner, 1, 6, now, [a]);
        Check(source.Read() is null, "old account directory cannot seed the new generation");
        source.ObserveDirectory(owner, 2, 7, now, [a]);
        Check(source.Read()?.Code == "A", "current generation can accept its own fresh authorized directory");
    }

    private static async Task ColdOpeningWaitsForExistingRead()
    {
        var owner = new BridgeAccountContext("test", "example.invalid", "viewer");
        var pending = new TaskCompletionSource<InformationOverlayCommunityContent>(TaskCreationOptions.RunContinuationsAsynchronously);
        var reader = new Reader { Pending = pending.Task };
        using var source = new OverlayCommunitySource(() => (owner, 1), reader, false);
        var warmup = source.RefreshAsync();
        var opening = source.RefreshAsync(waitForGate: true);
        source.SuspendDisplayDemand(); // The activity receiver sees a not-yet-visible window.
        Check(!opening.IsCompleted, "cold open joins preparation rather than returning null at a busy gate");
        pending.SetResult(new("A", "Fixture", []));
        await Task.WhenAll(warmup, opening).WaitAsync(TimeSpan.FromSeconds(3));
        Check(reader.Reads == 1 && source.Read()?.Code == "A", "prepared source is reused without a duplicate request or visible-window demand");
    }

    private static async Task LateOverlayFailure()
    {
        var owner = new BridgeAccountContext("test", "example.invalid", "viewer");
        var now = DateTimeOffset.Parse("2026-09-30T00:00:00Z");
        var reader = new Reader();
        var pending = new TaskCompletionSource<InformationOverlayCommunityContent>(TaskCreationOptions.RunContinuationsAsynchronously);
        reader.Pending = pending.Task;
        using var source = new OverlayCommunitySource(() => (owner, 1), reader, false, () => now);
        var refresh = source.RefreshAsync();
        now += TimeSpan.FromSeconds(1);
        source.ObserveWorkspace(owner, 1, 1, now, new("A", "New result", []));
        pending.SetException(new AccountBridgeHostException("communities.notAllowed"));
        await refresh;
        Check(source.Read()?.Name == "New result", "old failed read cannot erase a newer independently authorized workspace");
    }

    private sealed class Reader : IOverlayCommunityReader
    {
        internal int Reads;
        internal Exception? Failure;
        internal Task<InformationOverlayCommunityContent>? Pending;
        public Task<IReadOnlyList<OverlayCommunityTarget>> ReadTargetsAsync(BridgeAccountContext owner, CancellationToken token) =>
            Task.FromResult<IReadOnlyList<OverlayCommunityTarget>>([new("A", "Fixture", "ref")]);
        public Task<InformationOverlayCommunityContent> ReadContentAsync(BridgeAccountContext owner, OverlayCommunityTarget target, CancellationToken token)
        {
            Reads++;
            if (Failure is not null) throw Failure;
            return Pending ?? Task.FromResult(new InformationOverlayCommunityContent("A", "Fixture", []));
        }
    }
    private static async Task IdlePreparationHonorsSourceAndAuthority()
    {
        var owner = new BridgeAccountContext("test", "example.invalid", "viewer");
        var now = DateTimeOffset.Parse("2026-09-30T00:00:00Z");
        var waits = System.Threading.Channels.Channel.CreateUnbounded<TaskCompletionSource>();
        var count = 0;
        async Task Wait(TimeSpan delay, CancellationToken token)
        {
            if (++count == 1) return;
            var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            waits.Writer.TryWrite(release);
            await release.Task.WaitAsync(token);
        }
        var reader = new Reader();
        InformationOverlayRoomContent? room = null;
        BridgeAccountContext? current = owner;
        using var source = new OverlayCommunitySource(() => (current, 1), reader, now: () => now,
            waitForWake: Wait, prepareWhenIdle: true, room: () => room);
        var idle = await waits.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(3));
        Check(reader.Reads == 1 && source.Read() is not null, "account initialization prepares one authorized source before display demand");
        now += TimeSpan.FromSeconds(16);
        idle.SetResult();
        idle = await waits.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(3));
        Check(reader.Reads == 2, "closed selected source renews before the original authority expires");
        room = new("fixture", "Room", "", 6, "", [], []);
        now += TimeSpan.FromSeconds(16);
        idle.SetResult();
        idle = await waits.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(3));
        Check(reader.Reads == 2, "automatic room source must not download unrelated organization rosters");
        room = null;
        reader.Failure = new AccountBridgeHostException("communities.forbidden");
        now += TimeSpan.FromSeconds(16);
        idle.SetResult();
        idle = await waits.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(3));
        Check(source.Read() is null, "idle preparation does not retain a revoked roster");
        current = null;
        var beforeLogout = reader.Reads;
        idle.SetResult();
        await waits.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(3));
        Check(reader.Reads == beforeLogout && source.Read() is null, "logout stops idle reads and clears authority");
        source.Dispose();
        await source.Completion.WaitAsync(TimeSpan.FromSeconds(3));
    }
    private static async Task FirstOpenAfterIdle()
    {
        var owner = new BridgeAccountContext("test", "example.invalid", "viewer");
        var now = DateTimeOffset.Parse("2026-09-30T00:00:00Z");
        var waits = System.Threading.Channels.Channel.CreateUnbounded<TaskCompletionSource>();
        var count = 0;
        async Task Wait(TimeSpan delay, CancellationToken token)
        {
            if (++count == 1) return;
            var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            waits.Writer.TryWrite(release);
            await release.Task.WaitAsync(token);
        }
        var reader = new Reader();
        using var source = new OverlayCommunitySource(() => (owner, 1), reader, now: () => now,
            waitForWake: Wait, prepareWhenIdle: true);
        var tick = await waits.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(3));
        for (var i = 0; i < 8; i++)
        {
            now += TimeSpan.FromSeconds(15);
            tick.SetResult();
            tick = await waits.Reader.ReadAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(3));
        }
        // The real native OpenCore first reads this source, then waits for a
        // network preparation if it is absent. This must still be ready after
        // login followed by two minutes on Home, with no organization UI reads.
        Check(source.ReadForDisplay() is not null,
            "first open after two idle minutes must not block on a fresh organization download");
        source.Dispose();
        await source.Completion.WaitAsync(TimeSpan.FromSeconds(3));
    }
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
}
