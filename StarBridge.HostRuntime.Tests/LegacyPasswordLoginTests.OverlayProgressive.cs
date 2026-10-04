using System.Net;
using System.Net.Http.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;
using StarBridge.HostRuntime.Overlay;
using StarBridge.NativeBridge;

internal static partial class LegacyPasswordLoginTests
{
    internal static async Task OverlayRosterDoesNotWaitForManagementIdentity()
    {
        using var login = new LegacyPasswordLoginClient(new Uri("https://example.invalid/"), new Store(), new Transport());
        using var transport = new ProgressiveCommunityTransport { OwnerLoginName = true, BlockManagementIdentity = true, MemberCount = 31 };
        transport.Release.TrySetResult();
        using var communities = new CommunityClient(new Uri("https://example.invalid/"), transport);
        using var host = CreateHost(login, communities: communities);
        await host.LoginLegacyAsync(BridgePayload.From(new { schemaVersion = 1, email = "old@example.invalid", password = "synthetic" }), 0, default);
        using var source = new OverlayCommunitySource(() => (host.CurrentContext, host.Generation), (IOverlayCommunityReader)host, false);
        var refresh = source.RefreshAsync();
        try
        {
            await refresh.WaitAsync(TimeSpan.FromSeconds(2));
            Check(source.Read()?.Members.Count == 31 && transport.ManagementReads == 0,
                "The complete overlay roster must not wait for unrelated management identity HTTP.");
            Check(transport.FleetReads == 2,
                "Directory plus complete S2 roster must use two downloads total, not re-download all members per UI page.");
        }
        finally { transport.ManagementRelease.TrySetResult(); await refresh; }
        // The optimization must not silently remove owner actions from the client.
        var directory = (CommunityPage)await host.ReadCommunitiesAsync(host.CurrentContext!,
            BridgePayload.From(new { schemaVersion = 1, view = "mine", query = "", after = (string?)null }), default);
        Check(directory.Items.Single().Relationship == "owner" && transport.ManagementReads > 0,
            "Normal organization pages still resolve the authenticated owner identity.");
        transport.Revoked = true;
        await source.RefreshAsync();
        Check(source.Read() is null, "Removing the optional lookup never bypasses fresh membership authorization.");
        Console.WriteLine("PASS actual Host/HTTP roster does not wait for management identity; owner UI and revocation preserved");
    }
    internal static async Task OverlayProgressiveAdapter()
    {
        using var login = new LegacyPasswordLoginClient(new Uri("https://example.invalid/"), new Store(), new Transport());
        using var transport = new ProgressiveCommunityTransport();
        using var communities = new CommunityClient(new Uri("https://example.invalid/"), transport);
        using var host = CreateHost(login, communities: communities);
        await host.LoginLegacyAsync(BridgePayload.From(new { schemaVersion = 1, email = "old@example.invalid", password = "synthetic" }), 0, default);
        using var source = new OverlayCommunitySource(() => (host.CurrentContext, host.Generation), (IOverlayCommunityReader)host, false);
        await source.RefreshAsync(includeCommunication: false);
        Check(source.Read()?.Members.Count == 1 && !transport.Started.Task.IsCompleted,
            "Idle preparation reads complete authorized members without downloading announcements or chat.");
        var refresh = source.RefreshAsync();
        try
        {
            await transport.Started.Task.WaitAsync(TimeSpan.FromSeconds(3));
            Check(source.Read()?.Members.Count == 1, "Actual Host adapter publishes complete authorized members before announcement HTTP completes.");
        }
        finally { transport.Release.TrySetResult(); await refresh; }
        Check(source.Read()?.Members.Count == 1, "Actual announcement HTTP 503 cannot clear a newly validated roster.");
        transport.Revoked = true;
        await source.RefreshAsync();
        Check(source.Read() is null, "Actual membership revocation must still clear immediately.");
        await OverlayOptionalActivityDoesNotBlockRoster(false);
        await OverlayOptionalActivityDoesNotBlockRoster(true);
        await OverlayGenerationChangeBetweenRosterAndCommunication();
        Console.WriteLine("PASS actual Host/HTTP progressive roster, failed communication and membership revocation");
    }

    private static async Task OverlayGenerationChangeBetweenRosterAndCommunication()
    {
        using var login = new LegacyPasswordLoginClient(new Uri("https://example.invalid/"), new Store(), new Transport());
        using var transport = new ProgressiveCommunityTransport();
        transport.Release.TrySetResult();
        using var communities = new CommunityClient(new Uri("https://example.invalid/"), transport);
        using var host = CreateHost(login, communities: communities);
        var payload = BridgePayload.From(new { schemaVersion = 1, email = "old@example.invalid", password = "synthetic" });
        await host.LoginLegacyAsync(payload, 0, default);
        var reader = (IOverlayCommunityReader)host;
        var owner = host.CurrentContext!;
        var generation = host.Generation;
        var target = (await reader.ReadTargetsAsync(owner, default)).Single();
        Exception? failure = null;
        try
        {
            await reader.ReadContentAsync(owner, target, _ =>
                host.LoginLegacyAsync(payload, generation, default).GetAwaiter().GetResult(), default);
        }
        catch (Exception error) when (error is BridgeStaleGenerationException or AccountBridgeHostException)
        { failure = error; }
        Check(host.Generation > generation && host.CurrentContext == owner && failure is not null && !transport.Started.Task.IsCompleted,
            "Same-account generation change after roster publication must stop before announcement HTTP or content publication.");
    }
    private static async Task OverlayOptionalActivityDoesNotBlockRoster(bool withdraw)
    {
        using var login = new LegacyPasswordLoginClient(new Uri("https://example.invalid/"), new Store(), new Transport());
        using var transport = new ProgressiveCommunityTransport { BlockPlayers = true };
        transport.Release.TrySetResult();
        using var communities = new CommunityClient(new Uri("https://example.invalid/"), transport);
        using var host = CreateHost(login, communities: communities);
        await host.LoginLegacyAsync(BridgePayload.From(new { schemaVersion = 1, email = "old@example.invalid", password = "synthetic" }), 0, default);
        var observations = 0;
        var enabled = true;
        host.PlayerActivityObserved = _ => Interlocked.Increment(ref observations);
        host.ShouldObservePlayerActivity = () => enabled;
        using var source = new OverlayCommunitySource(() => (host.CurrentContext, host.Generation), (IOverlayCommunityReader)host, false);
        var refresh = source.RefreshAsync();
        try
        {
            await refresh.WaitAsync(TimeSpan.FromSeconds(3));
            Check(source.Read()?.Members.Count == 1,
                "The overlay roster must not wait for the optional player-activity HTTP feed.");
            await transport.PlayersStarted.Task.WaitAsync(TimeSpan.FromSeconds(3));
            for (var i = 0; i < 5; i++) await source.RefreshAsync();
            Check(transport.PlayerReads == 1, "Refresh bursts must keep one active optional activity request.");
            if (withdraw) enabled = false;
        }
        finally { transport.PlayersRelease.TrySetResult(); await refresh; }
        await communities.BackgroundObservationCompletion.WaitAsync(TimeSpan.FromSeconds(3));
        Check(transport.PlayerReads == 2, "Only one coalesced latest activity request follows the blocked read.");
        Check(withdraw ? observations == 0 : observations > 0,
            "Background activity still delivers reminders, but honors policy withdrawal before completion.");
    }
    private sealed class ProgressiveCommunityTransport : HttpMessageHandler
    {
        internal bool Revoked;
        internal bool BlockPlayers;
        internal bool OwnerLoginName, BlockManagementIdentity;
        internal int ManagementReads;
        internal int FleetReads;
        internal bool BlockFleet;
        internal readonly TaskCompletionSource FleetStarted = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource FleetRelease = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource ManagementRelease = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal int PlayerReads;
        internal int MemberCount = 1;
        internal readonly TaskCompletionSource PlayersStarted = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource PlayersRelease = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource Started = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource Release = new(TaskCreationOptions.RunContinuationsAsynchronously);
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            object body;
            switch(request.RequestUri!.AbsolutePath)
            {
                case "/api/fleets/membership":
                    body = new { fleetCode = Revoked ? "" : "A", fleetCodes = Revoked ? Array.Empty<string>() : new[] { "A" } }; break;
                case "/api/fleets":
                    Interlocked.Increment(ref FleetReads);
                    if (BlockFleet) { FleetStarted.TrySetResult(); await FleetRelease.Task.WaitAsync(token); }
                    body = new[] { new { code = "A", name = "Fixture", totalMembers = MemberCount, ownerAccount = OwnerLoginName ? "fixture-login" : "legacy-synthetic",
                        members = Enumerable.Range(0, MemberCount).Select(i => new { accountId = i == 0 ? "legacy-synthetic" : "member-" + i,
                            gameName = "Fixture" + i, callsign = "Fixture" + i, roleTitle = "", online = true, liveStatus = "AppOnline" }).ToArray() } }; break;
                case "/api/auth/session":
                    ManagementReads++;
                    if (BlockManagementIdentity) await ManagementRelease.Task.WaitAsync(token);
                    body = new { accountId = "legacy-synthetic", userName = OwnerLoginName ? "fixture-login" : "legacy-synthetic" }; break;
                case "/api/players":
                    PlayerReads++;
                    PlayersStarted.TrySetResult();
                    if (BlockPlayers) await PlayersRelease.Task.WaitAsync(token);
                    body = Array.Empty<object>(); break;
                case "/api/fleets/announcements":
                    Started.TrySetResult(); await Release.Task.WaitAsync(token); return new(HttpStatusCode.ServiceUnavailable);
                default: return new(HttpStatusCode.NotFound);
            }
            return new(HttpStatusCode.OK) { Content = JsonContent.Create(body) };
        }
    }
}
