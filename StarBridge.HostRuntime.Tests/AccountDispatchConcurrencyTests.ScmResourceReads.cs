using System.Reflection;
using StarBridge.HostRuntime.Account;

internal static partial class AccountDispatchConcurrencyTests
{
    internal interface IResourceReadHost : IAccountBridgeHost, IAccountBridgeConcurrentResourceReads { }

    public class ResourceReadProbe : Probe
    {
        internal bool ResourceReads = true;
        protected override object? Invoke(MethodInfo? method, object?[]? args) =>
            method!.Name == "get_SupportsConcurrentResourceReads" ? ResourceReads : base.Invoke(method, args);
    }

    // DL-129 option 3 (build 12 traces, 2026-10-21): under an SCM session the
    // three startup organization reads ran one after another, about 0.8 s
    // apart. Audited resource reads now overlap; projections and writes do not.
    private static async Task ScmResourceReadsOverlap()
    {
        var host = DispatchProxy.Create<IResourceReadHost, ResourceReadProbe>();
        var probe = (ResourceReadProbe)(object)host;
        probe.ConcurrentReads = false;
        using var dispatcher = new AccountBridgeDispatcher(host);
        var reads = Enumerable.Range(0, 3)
            .Select(_ => dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.ReadCommunities))).ToArray();
        try
        {
            await Until(() => probe.Reads == 3);
        }
        catch (TimeoutException)
        {
            throw new InvalidOperationException("SCM organization reads still run one at a time.");
        }
        finally { probe.ReadRelease.TrySetResult(new { schemaVersion = 1 }); }
        foreach (var read in reads)
            Check((await read.WaitAsync(TimeSpan.FromSeconds(2))).Response.Status == "ok", "Overlapping reads complete.");
    }

    private static async Task ScmProjectionAndWritesStayExclusive()
    {
        var host = DispatchProxy.Create<IResourceReadHost, ResourceReadProbe>();
        var probe = (ResourceReadProbe)(object)host;
        probe.ConcurrentReads = false;
        using var dispatcher = new AccountBridgeDispatcher(host);
        var slow = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.ReadCommunities));
        await Until(() => probe.Reads == 1);
        var current = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.GetCurrent));
        var policy = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.GetGameIdentityPolicy));
        var write = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.Login));
        var after = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.ReadCommunities));
        await Task.Delay(30);
        try
        {
            Check(probe.Currents == 0 && probe.Policies == 0,
                "An SCM account projection must not overlap a resource read.");
            Check(probe.Writes == 0 && probe.Reads == 1,
                "No write may overlap a read, and no read may pass a queued write.");
        }
        finally
        {
            probe.ReadRelease.TrySetResult(new { schemaVersion = 1 });
            probe.WriteRelease.TrySetResult(new("signedIn", 1, Probe.Owner, "Fixture", null));
        }
        await Task.WhenAll(slow, current, policy, write, after).WaitAsync(TimeSpan.FromSeconds(2));
        Check(probe.Writes == 1 && probe.Reads == 2, "Queued work completes in order after the fence.");
    }

    private static async Task ScmResourceReadsNeedHealthySession()
    {
        var host = DispatchProxy.Create<IResourceReadHost, ResourceReadProbe>();
        var probe = (ResourceReadProbe)(object)host;
        probe.ConcurrentReads = false;
        probe.ResourceReads = false;
        using var dispatcher = new AccountBridgeDispatcher(host);
        var first = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.ReadCommunities));
        await Until(() => probe.Reads == 1);
        var second = dispatcher.DispatchAsync(Request(AccountBridgeRequestNames.ReadCommunities));
        await Task.Delay(30);
        try { Check(probe.Reads == 1, "A session that cannot share resource reads must keep them serialized."); }
        finally { probe.ReadRelease.TrySetResult(new { schemaVersion = 1 }); }
        await Task.WhenAll(first, second).WaitAsync(TimeSpan.FromSeconds(2));
    }
}
