using StarBridge.HostRuntime.Account;

internal static partial class AccountDispatchConcurrencyTests
{
    // DL-129: SCM sessions serialize every account request. Device traces showed the
    // in-memory account projection and the organization directory queued 3–5 s behind
    // background media reads. The lane stays exclusive; only its order changes.
    private static async Task ForegroundReadsPassQueuedBackgroundMedia()
    {
        var (host, probe) = Create();
        probe.ConcurrentReads = false;
        using var dispatcher = new AccountBridgeDispatcher(host);
        var slow = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.ReadCommunities));
        await Until(() => probe.Reads == 1);
        var media = Enumerable.Range(0, 3)
            .Select(_ => dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.ReadCommunityMedia))).ToArray();
        await Task.Delay(20);
        var current = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.GetCurrent));
        var friends = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.ReadFriends));
        var avatar = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.ReadAvatar));
        await Task.Delay(20);
        try
        {
            Check(probe.Currents == 0 && probe.MediaStarted == 0, "The exclusive lane still runs one request at a time.");
            probe.ReadRelease.TrySetResult(new { schemaVersion = 1 });
            await slow;
            Check(await Task.WhenAny(current, Task.Delay(1000)) == current && (await current).Response.Status == "ok",
                "A queued account projection waits behind background media reads.");
            Check(await Task.WhenAny(friends, Task.Delay(1000)) == friends && (await friends).Response.Status == "ok",
                "A queued page read waits behind background media reads.");
            Check(await Task.WhenAny(avatar, Task.Delay(1000)) == avatar && (await avatar).Response.Status == "ok" && probe.Avatars == 1,
                "The shell call sign read waits behind background media reads.");
            Check(probe.MediaStarted <= 1, "Foreground reads must be admitted before queued background media.");
        }
        finally { probe.ReadRelease.TrySetResult(new { schemaVersion = 1 }); probe.MediaRelease.TrySetResult(new { schemaVersion = 1 }); }
        foreach (var read in media)
            Check((await read.WaitAsync(TimeSpan.FromSeconds(2))).Response.Status == "ok", "Background media still completes after foreground reads.");
        Check(probe.MediaStarted == 3, "Every queued media read eventually runs.");
    }

    internal interface IProjectingHost : IAccountBridgeHost, IAccountBridgeCurrentProjection { }

    public class ProjectingProbe : Probe
    {
        internal AccountBridgeSessionProjection? Fast;
        internal int FastCalls;
        protected override object? Invoke(System.Reflection.MethodInfo? method, object?[]? args)
        {
            if (method!.Name != nameof(IAccountBridgeCurrentProjection.TryProjectCurrent)) return base.Invoke(method, args);
            Interlocked.Increment(ref FastCalls);
            return Fast;
        }
    }

    // DL-129 option 2: a repeated current read is answered beside the serialized
    // read lane, but never beside or ahead of a queued account mutation.
    private static async Task RepeatedCurrentSkipsReadQueueButNotMutations()
    {
        var host = System.Reflection.DispatchProxy.Create<IProjectingHost, ProjectingProbe>();
        var probe = (ProjectingProbe)(object)host;
        probe.ConcurrentReads = false;
        probe.Fast = new("signedIn", 1, Probe.Owner, "Fixture", null);
        using var dispatcher = new AccountBridgeDispatcher(host);
        var slow = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.ReadCommunities));
        await Until(() => probe.Reads == 1);
        var media = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.ReadCommunityMedia));
        Task<AccountBridgeDispatchResult>? fenced = null;
        Task<AccountBridgeDispatchResult>? write = null;
        try
        {
            var current = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.GetCurrent));
            Check(await Task.WhenAny(current, Task.Delay(1000)) == current && (await current).Response.Status == "ok" &&
                probe.Currents == 0 && probe.FastCalls == 1, "A repeated current read waits behind the serialized read lane.");
            write = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.Login));
            fenced = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.GetCurrent));
            await Task.Delay(20);
            Check(probe.FastCalls == 1 && !fenced.IsCompleted, "Current must not be answered beside a queued account mutation.");
        }
        finally
        {
            probe.ReadRelease.TrySetResult(new { schemaVersion = 1 });
            probe.MediaRelease.TrySetResult(new { schemaVersion = 1 });
            probe.WriteRelease.TrySetResult(new("signedIn", 1, Probe.Owner, "Fixture", null));
        }
        await Task.WhenAll(slow, media);
        Check((await write!).Response.Status == "ok", "The queued mutation completes.");
        Check((await fenced!).Response.Status == "ok" && probe.Currents == 1, "A fenced current read takes the full queued path.");
        probe.Fast = null;
        var fallback = await dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.GetCurrent));
        Check(fallback.Response.Status == "ok" && probe.Currents == 2, "A host that cannot project falls back to the queue.");
    }

    // Writes keep their fence: a background read never overtakes a queued mutation,
    // and a foreground read queued after a writer does not bypass it either.
    private static async Task PriorityKeepsWriteFence()
    {
        var (host, probe) = Create();
        probe.ConcurrentReads = false;
        using var dispatcher = new AccountBridgeDispatcher(host);
        var slow = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.ReadCommunities));
        await Until(() => probe.Reads == 1);
        var write = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.Login));
        await Task.Delay(20);
        var media = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.ReadCommunityMedia));
        var current = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.GetCurrent));
        await Task.Delay(20);
        try
        {
            probe.ReadRelease.TrySetResult(new { schemaVersion = 1 });
            await slow;
            await Until(() => probe.Writes == 1);
            Check(probe.Currents == 0 && probe.MediaStarted == 0, "No read may overlap or overtake a queued account mutation.");
            probe.WriteRelease.TrySetResult(new("signedIn", 1, Probe.Owner, "Fixture", null));
            Check((await write).Response.Status == "ok", "The mutation completes.");
            Check((await current.WaitAsync(TimeSpan.FromSeconds(2))).Response.Status == "ok", "Reads resume after the mutation.");
        }
        finally
        {
            probe.ReadRelease.TrySetResult(new { schemaVersion = 1 });
            probe.WriteRelease.TrySetResult(new("signedIn", 1, Probe.Owner, "Fixture", null));
            probe.MediaRelease.TrySetResult(new { schemaVersion = 1 });
        }
        Check((await media.WaitAsync(TimeSpan.FromSeconds(2))).Response.Status == "ok", "Queued background media completes.");
    }
}
