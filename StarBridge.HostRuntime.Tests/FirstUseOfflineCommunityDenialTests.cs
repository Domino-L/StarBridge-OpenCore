using System.Net;
using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Communities;
using StarBridge.NativeBridge;

internal static partial class FirstUseModeTests
{
    internal static Task OfflineCommunityDenialWithdraws() => OfflineCommunityDenialCore(false);
    internal static Task OfflineCommunityLockedDenialWithdraws() => OfflineCommunityDenialCore(true);
    internal static async Task<string> OfflineCommunityDenialWire()
    {
        var baseline = JsonSerializer.Deserialize<Dictionary<string, BridgeEnvelope>>(await OfflineCommunityWire(), BridgeProtocol.JsonOptions)!;
        var messages = new Dictionary<string, BridgeEnvelope> { ["before"] = baseline["warm"] };
        await OfflineCommunityDenialCore(true, (name, response) => messages.Add(name, response));
        return JsonSerializer.Serialize(messages, BridgeProtocol.JsonOptions);
    }

    private static async Task OfflineCommunityDenialCore(bool locked, Action<string, BridgeEnvelope>? observe = null)
    {
        using var http = new OfflineCommunityHttp();
        using var communities = new CommunityClient(new Uri("https://communities.invalid/"), http);
        using var f = new LocalAccountStopTests.Fixture(sampling: true, communities: communities);
        var mode = await RootMode(f);
        await using var native = new NativeAccountRuntimeBinding(f.Runtime);
        var owner = f.Host.CurrentContext!;
        var generation = f.Host.Generation;
        Require((await native.DispatchAsync(BridgeEnvelope.Request("account.getCurrent", Op(), generation,
            new { schemaVersion = 1 }))).Response.Status == "ok", "Root selected before observing cached directory");
        async Task<BridgeEnvelope> Read() => (await native.DispatchAsync(BridgeEnvelope.Request("communities.read", Op(), generation,
            new { schemaVersion = 1, view = "mine", query = "" }, owner))).Response;
        var online = await Read();
        Require(online.Status == "ok", "Authenticated read persists actual names and logo bytes");
        observe?.Invoke("online", online);
        var file = Path.Combine(f.Root, "offline-account-v1", "organizations.bin");
        using var held = locked ? File.Open(file, FileMode.Open, FileAccess.Read, FileShare.Read) : null;
        http.Failure = HttpStatusCode.Forbidden;
        var denied = await Read();
        Require(denied.Error?.Code == "communities.notAllowed", "Resource refusal remains explicit");
        observe?.Invoke("denied", denied);
        Require(f.Host.CurrentContext == owner && f.Host.Generation == generation && f.Vault.Deletions == 0,
            "Organization refusal cannot sign out the root account or delete its credential");
        Require((await mode.ApplyRootOfflineAsync(0, Op(), generation, native)).State == "offline", "Offline still works after a field refusal");
        async Task Check(string label, NativeAccountRuntimeBinding binding, StarBridge.HostRuntime.Onboarding.FirstUseModeRuntime current)
        {
            using var reader = binding.CreateModeDispatcher()!;
            var response = (await reader.DispatchAsync(BridgeEnvelope.Request("onboarding.mode.communities", Op(), current.ControlGeneration,
                new { schemaVersion = 1, revision = current.Current.Revision }))).Response;
            Require(response.Error?.Code == "offlineAccount.unavailable",
                "Explicit refusal withdraws cached directory before warm and cold offline reads, including blocked data-file deletion");
            observe?.Invoke(label, response);
        }
        await Check("warmUnavailable", native, mode);
        using var cold = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, NoOnline);
        await using var coldNative = new NativeAccountRuntimeBinding(cold);
        await Check("coldUnavailable", coldNative, cold.FirstUseMode!);
        Require(http.Reads == 2 && f.Vault.Loads == 0 && f.Vault.Deletions == 0,
            "Withdrawal and cold reads cannot restore credentials or contact the server");
    }
}
