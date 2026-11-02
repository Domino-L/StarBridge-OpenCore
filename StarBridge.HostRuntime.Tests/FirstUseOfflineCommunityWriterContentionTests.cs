using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Communities;
using StarBridge.HostRuntime.Overlay;
using StarBridge.NativeBridge;

internal static partial class FirstUseModeTests
{
    internal static Task OfflineCommunityWriterContention() => OrganizationWriterContention(false);
    internal static Task OfflineCommunityWriterWaitCancellation() => OrganizationWriterContention(true);
    internal static Task OfflineCommunityWriterWaitRetirement() => OrganizationWriterContention(false, retire: true);
    internal static Task OfflineCommunityWriterWaitBounded() => OrganizationWriterContention(false, bounded: true);

    private static async Task OrganizationWriterContention(bool cancel, bool retire = false, bool bounded = false)
    {
        using var http = new OfflineCommunityHttp();
        using var communities = new CommunityClient(new Uri("https://communities.invalid/"), http);
        using var f = new LocalAccountStopTests.Fixture(sampling: true, communities: communities);
        await RootMode(f);
        await using var native = new NativeAccountRuntimeBinding(f.Runtime);
        var owner = f.Host.CurrentContext!;
        var generation = f.Host.Generation;
        await native.DispatchAsync(BridgeEnvelope.Request("account.getCurrent", Op(), generation, new { schemaVersion = 1 }));
        using var cancellation = new CancellationTokenSource();
        var reader = (IOverlayCommunityReader)f.Host;
        Task<IReadOnlyList<OverlayCommunityTarget>> pending;
        using (File.Open(Path.Combine(f.Root, "offline-account-v1", "snapshot.bin.lock"), FileMode.OpenOrCreate,
                   FileAccess.ReadWrite, FileShare.None))
        {
            // This real callback enters synchronously up to its first wait.
            // No delayed scheduler or artificial HTTP timeout creates the race.
            pending = reader.ReadTargetsAsync(owner, cancellation.Token);
            Require(http.Reads == 0, "Remote IO cannot start before the durable display guard");
            if (cancel) cancellation.Cancel();
            if (retire) f.Host.Dispose();
            if (bounded)
            {
                try { await pending.WaitAsync(TimeSpan.FromSeconds(3)); throw new Exception("Permanent contention unexpectedly succeeded"); }
                catch (StarBridge.HostRuntime.Account.AccountBridgeHostException error) when (error.Code == "communities.readTransient") { }
                Require(http.Reads == 0, "The bounded writer wait ends without starting unprotected HTTP");
            }
        }
        if (bounded) return;
        if (retire)
        {
            try { await pending; throw new Exception("Retired owner started a directory read"); }
            catch (Exception error) when (error is OperationCanceledException or BridgeStaleGenerationException) { }
            Require(http.Reads == 0, "Retirement while waiting prevents late HTTP admission");
            return;
        }
        if (cancel)
        {
            try { await pending; throw new Exception("Cancelled writer wait completed successfully"); }
            catch (OperationCanceledException) { }
            Require(http.Reads == 0, "Cancellation during writer contention never reaches HTTP");
        }
        else
        {
            var targets = await pending.WaitAsync(TimeSpan.FromSeconds(3));
            Require(targets.Count == 1 && http.Reads == 1, "Brief ordinary cache writing must not fail a valid directory read or repeat HTTP");
        }
        Require(f.Host.CurrentContext == owner && f.Host.Generation == generation && f.Vault.Deletions == 0,
            "Writer contention does not change account authority");
    }
}
