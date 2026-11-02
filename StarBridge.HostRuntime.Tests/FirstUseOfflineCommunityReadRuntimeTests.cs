using System.Net;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;
using StarBridge.NativeBridge;

internal static partial class FirstUseModeTests
{
    internal static async Task OfflineCommunityReadAdmissionAndTransient()
    {
        using var http = new OfflineCommunityHttp();
        using var communities = new CommunityClient(new Uri("https://communities.invalid/"), http);
        using var f = new LocalAccountStopTests.Fixture(sampling: true, communities: communities);
        var mode = await RootMode(f);
        await using var native = new NativeAccountRuntimeBinding(f.Runtime);
        var owner = f.Host.CurrentContext!;
        var generation = f.Host.Generation;
        await native.DispatchAsync(BridgeEnvelope.Request("account.getCurrent", Op(), generation, new { schemaVersion = 1 }));
        async Task<BridgeEnvelope> Read(string query = "") => (await native.DispatchAsync(BridgeEnvelope.Request("communities.read", Op(), generation,
            new { schemaVersion = 1, view = "mine", query }, owner))).Response;
        Require((await Read()).Status == "ok", "Warm actual directory");
        var reader = new OfflineAccountStore(f.Root);
        var before = reader.ReadSelectedOrganizations(owner, () => true)!;
        http.Failure = HttpStatusCode.Forbidden;
        Require((await Read("scoped search")).Error?.Code == "communities.notAllowed", "Search refusal remains explicit");
        Require(reader.ReadSelectedOrganizations(owner, () => true)?.Version == before.Version, "A scoped search cannot revoke the unfiltered directory");
        http.Failure = HttpStatusCode.ServiceUnavailable;
        Require((await Read()).Error?.Code == "communities.readTransient", "Actual temporary failure remains typed");
        var after = reader.ReadSelectedOrganizations(owner, () => true)!;
        Require(after.Version == before.Version && after.CachedAtUtc == before.CachedAtUtc && after.Items[0].LogoImageData == OfflineAvatar,
            "Transient HTTP failure keeps names, bytes and original time");
        var traffic = http.Reads;
        var policyPath = Path.Combine(f.Root, "offline-account-v1", "organizations-policy.bin");
        using (File.Open(policyPath, FileMode.Open, FileAccess.Read, FileShare.Read))
            Require((await Read()).Error?.Code == "communities.readTransient" && http.Reads == traffic,
                "An unrecordable read guard cannot start unprotected remote IO");
        Require(reader.ReadSelectedOrganizations(owner, () => true)?.Version == before.Version, "Failed admission does not advance or erase eligible old data");
        Require((await mode.ApplyRootOfflineAsync(0, Op(), generation, native)).State == "offline", "Explicit offline remains available");
        using var cold = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, NoOnline);
        await using var coldNative = new NativeAccountRuntimeBinding(cold);
        using var dispatcher = coldNative.CreateModeDispatcher()!;
        var response = (await dispatcher.DispatchAsync(BridgeEnvelope.Request("onboarding.mode.communities", Op(), cold.FirstUseMode!.ControlGeneration,
            new { schemaVersion = 1, revision = cold.FirstUseMode.Current.Revision }))).Response;
        Require(response.Status == "ok" && response.Payload.GetProperty("cachedAtUtc").GetDateTimeOffset() == before.CachedAtUtc,
            "Cold offline retains exactly the previously confirmed directory after temporary failure");
        Require(http.Reads == traffic && f.Vault.Loads == 0 && f.Vault.Deletions == 0, "Cache policy neither restores nor retires credentials");
    }

    internal static async Task OfflineCommunityLateHttpSuccess()
    {
        using var http = new OfflineCommunityHttp();
        using var communities = new CommunityClient(new Uri("https://communities.invalid/"), http);
        using var f = new LocalAccountStopTests.Fixture(sampling: true, communities: communities);
        await RootMode(f);
        await using var native = new NativeAccountRuntimeBinding(f.Runtime);
        var owner = f.Host.CurrentContext!;
        var generation = f.Host.Generation;
        await native.DispatchAsync(BridgeEnvelope.Request("account.getCurrent", Op(), generation, new { schemaVersion = 1 }));
        async Task<BridgeEnvelope> Read() => (await native.DispatchAsync(BridgeEnvelope.Request("communities.read", Op(), generation,
            new { schemaVersion = 1, view = "mine", query = "" }, owner))).Response;
        Require((await Read()).Status == "ok", "Warm actual directory before concurrent reads");
        var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var release = new TaskCompletionSource<HttpResponseMessage>(TaskCreationOptions.RunContinuationsAsynchronously);
        var count = 0;
        http.Reply = _ => {
            if (Interlocked.Increment(ref count) != 1) return Task.FromResult(new HttpResponseMessage(HttpStatusCode.Forbidden));
            entered.TrySetResult(); return release.Task;
        };
        // Background overlay reads bypass the page's serialized private lane.
        var late = ((StarBridge.HostRuntime.Overlay.IOverlayCommunityReader)f.Host).ReadTargetsAsync(owner, default);
        try
        {
            await entered.Task.WaitAsync(TimeSpan.FromSeconds(3));
            Require((await Read().WaitAsync(TimeSpan.FromSeconds(3))).Error?.Code == "communities.notAllowed", "Independent refusal completes while old HTTP is held");
        }
        finally { release.TrySetResult(OfflineCommunityHttp.OrganizationReply("Late success")); await late.WaitAsync(TimeSpan.FromSeconds(5)); }
        Require(new OfflineAccountStore(f.Root).ReadSelectedOrganizations(owner, () => true) is null,
            "An actual late HTTP success cannot restore rejected names and bytes");
    }
}
