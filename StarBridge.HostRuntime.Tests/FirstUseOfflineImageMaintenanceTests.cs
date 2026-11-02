using System.Net;
using System.Security.Cryptography;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;
using StarBridge.HostRuntime.Support;
using StarBridge.NativeBridge;

internal static partial class FirstUseModeTests
{
    internal static async Task ActualNativeMediaMaintenanceFence()
    {
        var source = new DeferredOrganizationHttp();
        using var handler = new MaintenanceMediaGate(source);
        using var client = new CommunityClient(new("https://communities.invalid/"), handler);
        using var f = new LocalAccountStopTests.Fixture(sampling: true, communities: client);
        await RootMode(f);
        await using var native = new NativeAccountRuntimeBinding(f.Runtime);
        var owner = f.Host.CurrentContext!;
        await native.DispatchAsync(BridgeEnvelope.Request("account.getCurrent", Op(), f.Host.Generation, new { schemaVersion = 1 }));
        var directory = await native.DispatchAsync(BridgeEnvelope.Request("communities.read", Op(), f.Host.Generation,
            new { schemaVersion = 1, view = "mine", query = "" }, owner));
        Require(directory.Response.Status == "ok", "actual Native directory is admitted before optional media");
        var reference = directory.Response.Payload.GetProperty("items")[0].GetProperty("targetRef").GetString();
        var store = new OfflineAccountStore(f.Root);
        var first = store.ReadSelectedOrganizations(owner, () => true)!;
        var snapshot = Path.Combine(f.Root, "offline-account-v1", "snapshot.bin");
        var accountHash = Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(snapshot)));
        async Task<BridgeEnvelope> Read(int offset) => (await native.DispatchAsync(BridgeEnvelope.Request("communities.media", Op(), f.Host.Generation,
            new { schemaVersion = 1, targetRef = reference, kind = "logo", offset, version = offset == 0 ? null : source.Version }, owner))).Response;
        Require((await Read(0)).Status == "ok", "actual original first media chunk");
        handler.Hold = true;
        var pending = Read(192 * 1024);
        await handler.Entered.Task.WaitAsync(TimeSpan.FromSeconds(5));
        try
        {
            using var support = new ApplicationSupportBridgeDispatcher(f.Root, null,
                generation: () => f.Host.Generation, clearImageReadCaches: f.Runtime.ClearDownloadableImageReadCaches);
            var cleared = await support.DispatchAsync(BridgeEnvelope.Request("diagnostics.clearImageCache", Op(), f.Host.Generation, new { schemaVersion = 1 }));
            Require(cleared.Response.Status == "ok" && cleared.Response.Payload.GetProperty("count").GetInt32() == 0,
                "actual zero-count maintenance retires incomplete media through the runtime callback");
        }
        finally { handler.Release.TrySetResult(true); }
        Require((await pending).Status == "ok", "the original held transport still exits through the original Host path");
        var after = new OfflineAccountStore(f.Root).ReadSelectedOrganizations(owner, () => true)!;
        Require(after.Items.Single().LogoImageData is null && after.Items.Single().Id == first.Items.Single().Id &&
            after.Complete == first.Complete && after.CachedAtUtc == first.CachedAtUtc,
            "late actual media cannot repersist the logo or alter retained directory metadata");
        Require(Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(snapshot))) == accountHash,
            "actual maintenance does not rewrite account selection or avatar/profile data");
        handler.Hold = false;
        Require((await Read(0)).Status == "ok" && (await Read(192 * 1024)).Status == "ok", "fresh media still uses the same actual scoped target");
        Require(new OfflineAccountStore(f.Root).ReadSelectedOrganizations(owner, () => true)!.Items.Single().LogoImageData == source.Image,
            "fresh original media pipeline can cache a complete image after maintenance");
    }

    private sealed class MaintenanceMediaGate(HttpMessageHandler inner) : DelegatingHandler(inner)
    {
        internal bool Hold;
        internal TaskCompletionSource<bool> Entered = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal TaskCompletionSource<bool> Release = new(TaskCreationOptions.RunContinuationsAsynchronously);
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            var response = await base.SendAsync(request, token);
            if (Hold && request.RequestUri!.Query.Contains("offset=196608", StringComparison.Ordinal))
            {
                Entered.TrySetResult(true);
                try { await Release.Task.WaitAsync(token); }
                catch { response.Dispose(); throw; }
            }
            return response;
        }
    }
}
