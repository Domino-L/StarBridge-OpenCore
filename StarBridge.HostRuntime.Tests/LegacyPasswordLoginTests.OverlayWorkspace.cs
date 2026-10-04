using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;
using StarBridge.NativeBridge;

internal static partial class LegacyPasswordLoginTests
{
    internal static async Task OverlayAndPageShareInflightRoster()
    {
        using var login = new LegacyPasswordLoginClient(new Uri("https://example.invalid/"), new Store(), new Transport());
        using var transport = new ProgressiveCommunityTransport();
        transport.Release.TrySetResult();
        using var communities = new CommunityClient(new Uri("https://example.invalid/"), transport);
        using var host = CreateHost(login, communities: communities);
        await host.LoginLegacyAsync(BridgePayload.From(new { schemaVersion = 1, email = "old@example.invalid", password = "synthetic" }), 0, default);
        var owner = host.CurrentContext!;
        var directory = (CommunityPage)await host.ReadCommunitiesAsync(owner,
            BridgePayload.From(new { schemaVersion = 1, view = "mine", query = "", after = (string?)null }), default);
        var target = directory.Items.Single().TargetRef;
        var before = transport.FleetReads;
        transport.BlockFleet = true;
        var page = host.ReadCommunityWorkspaceAsync(owner,
            BridgePayload.From(new { schemaVersion = 1, targetRef = target, query = "", offset = 0 }), default);
        await transport.FleetStarted.Task.WaitAsync(TimeSpan.FromSeconds(2));
        var native = ((StarBridge.HostRuntime.Overlay.IOverlayCommunityReader)host).ReadRosterAsync(owner,
            new("A", "Fixture", target), default);
        try
        {
            await Task.Delay(100);
            Check(!page.IsCompleted && !native.IsCompleted && transport.FleetReads == before + 1,
                "Client page and native overlay must share the same in-flight authorized roster download.");
        }
        finally { transport.FleetRelease.TrySetResult(); await Task.WhenAll(page, native); }
        Check((await native).Members.Count == 1 &&
            JsonSerializer.SerializeToElement(await page).GetProperty("members").GetArrayLength() == 1,
            "Both real Host consumers receive the authorized roster from the shared request.");
    }

    internal static async Task OverlayReusesWorkspace()
    {
        var root = Directory.CreateTempSubdirectory("starbridge-overlay-workspace-").FullName;
        try
        {
            using var login = new LegacyPasswordLoginClient(new Uri("https://example.invalid/"), new Store(), new Transport());
            using var transport = new ProgressiveCommunityTransport();
            transport.Release.TrySetResult();
            using var communities = new CommunityClient(new Uri("https://example.invalid/"), transport);
            using var host = CreateHost(login, communities: communities);
            await host.LoginLegacyAsync(BridgePayload.From(new { schemaVersion = 1, email = "old@example.invalid", password = "synthetic" }), 0, default);
            using var runtime = new AccountBridgeRuntime(host);
            runtime.ConfigureOverlayCommunitySource(root, startDriver: false);
            var directory = (CommunityPage)await host.ReadCommunitiesAsync(host.CurrentContext!,
                BridgePayload.From(new { schemaVersion = 1, view = "mine", query = "", after = (string?)null }), default);
            Check(runtime.CurrentCommunityOverlay?.Members.Count == 1,
                "The authenticated S2 directory already contains the full roster; opening must reuse it before any workspace request.");
            var readsBeforeOpen = transport.FleetReads;
            await runtime.PrepareCommunityOverlayAsync(default).WaitAsync(TimeSpan.FromSeconds(1));
            Check(transport.FleetReads == readsBeforeOpen,
                "Opening after a complete directory result must perform zero additional roster HTTP requests.");
            var page = JsonSerializer.SerializeToElement(await host.ReadCommunityWorkspaceAsync(host.CurrentContext!,
                BridgePayload.From(new { schemaVersion = 1, targetRef = directory.Items.Single().TargetRef, query = "", offset = 0 }), default));
            Check(page.GetProperty("members").GetArrayLength() == 1, "The real client workspace has its authorized member.");
            Check(runtime.CurrentCommunityOverlay?.Members.Count == 1,
                "Opening the overlay after the client workspace loaded must immediately reuse its authorized roster, without another HTTP read.");
            transport.MemberCount = 31;
            await host.ReadCommunityWorkspaceAsync(host.CurrentContext!,
                BridgePayload.From(new { schemaVersion = 1, targetRef = directory.Items.Single().TargetRef, query = "Fixture1", offset = 0 }), default);
            Check(runtime.CurrentCommunityOverlay?.Members.Count == 31,
                "A filtered UI page must publish the complete privacy-projected S2 roster, not the filtered or first 20 rows.");
            transport.Revoked = true;
            try
            {
                await host.ReadCommunityWorkspaceAsync(host.CurrentContext!,
                    BridgePayload.From(new { schemaVersion = 1, targetRef = directory.Items.Single().TargetRef, query = "", offset = 0 }), default);
                throw new Exception("Expected withdrawn membership.");
            }
            catch (AccountBridgeHostException error) when (error.Code == "communities.notAllowed") { }
            Check(runtime.CurrentCommunityOverlay is null, "Revocation learned by the client page immediately clears the native source too.");
            transport.Revoked = false;
            await host.ReadCommunitiesAsync(host.CurrentContext!,
                BridgePayload.From(new { schemaVersion = 1, view = "mine", query = "", after = (string?)null }), default);
            Check(runtime.CurrentCommunityOverlay?.Members.Count == 31, "Unfiltered joined directory supplies all 31 members.");
            await host.ReadCommunitiesAsync(host.CurrentContext!,
                BridgePayload.From(new { schemaVersion = 1, view = "mine", query = "no-match", after = (string?)null }), default);
            Check(runtime.CurrentCommunityOverlay?.Members.Count == 31, "A search with no matches never revokes membership.");
            transport.Revoked = true;
            await host.ReadCommunitiesAsync(host.CurrentContext!,
                BridgePayload.From(new { schemaVersion = 1, view = "mine", query = "", after = (string?)null }), default);
            Check(runtime.CurrentCommunityOverlay is null, "A successful empty joined directory revokes cached members immediately.");
        }
        finally { Directory.Delete(root, true); }
    }
}
