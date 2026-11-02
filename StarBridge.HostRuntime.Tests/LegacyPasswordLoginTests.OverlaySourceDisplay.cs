using StarBridge.Core.Overlay;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Overlay;
using StarBridge.HostRuntime.PartyRooms;
using StarBridge.NativeBridge;

internal static partial class LegacyPasswordLoginTests
{
    // P3: the actual Host batch read names module sources, tells a confirmed
    // room absence from a lapsed room, and marks a signed-out display. All data
    // is synthetic; authority paths are the shipping ones.
    internal static async Task OverlaySourceDisplay()
    {
        using var login = new LegacyPasswordLoginClient(new Uri("https://example.invalid/"), new Store(), new Transport());
        using var transport = new OverlayRoomTransport();
        using var rooms = new PartyRoomReader(new Uri("https://example.invalid/"), transport);
        using var host = CreateHost(login, partyRooms: rooms);
        await host.LoginLegacyAsync(BridgePayload.From(new { schemaVersion = 1, email = "old@example.invalid", password = "synthetic" }), 0, default);
        using var runtime = new AccountBridgeRuntime(host);
        runtime.ConfigureOverlayCommunitySource(Path.Combine(Path.GetTempPath(), "starbridge-source-display-unused"), startDriver: false);
        await host.GetPartyRoomsAsync(host.CurrentContext!, default);
        var owner = host.GameplayTimeContext!;
        host.CommunityRosterObserved!(owner, host.Generation, 1, DateTimeOffset.UtcNow, new("A", "Voyagers", []));
        var policy = new OverlayPresetSources(new(OverlaySourceMode.Community, "A", OverlaySceneChoiceStore.Hash(owner)), modules:
            new Dictionary<OverlaySourceModule, OverlaySourceBinding> { [OverlaySourceModule.Members] = new(OverlaySourceMode.Room) });
        IReadOnlyDictionary<OverlaySourceModule, InformationOverlayModuleContent> Read() =>
            runtime.ReadOverlayModules(policy).Frame!.ReadModules(DateTimeOffset.UtcNow);

        var joined = Read();
        Check(joined[OverlaySourceModule.Members].Display is { Name: "Fixture", OwnSource: true, SignedOut: false, RoomAbsent: false } &&
            joined[OverlaySourceModule.Overview].Display is { Name: "Voyagers", OwnSource: false },
            "Actual Host names the room and organization each module shows, and marks only the own binding.");

        transport.Joined = false;
        await host.GetPartyRoomsAsync(host.CurrentContext!, default);
        var left = Read()[OverlaySourceModule.Members];
        Check(left.Source is { Available: false, UnavailableReason: "room_unavailable" } && left.Display is { RoomAbsent: true, Name: null },
            "A confirmed departure reads as no room, not as an unreachable one.");

        await host.LogoutAsync(host.CurrentContext!, default);
        var signedOut = Read();
        Check(signedOut.Values.All(content => content.Display.SignedOut) && !signedOut[OverlaySourceModule.Members].Source.Available &&
            signedOut.Values.All(content => content.Display.Name is null),
            "After sign-out every module is explained as signed out and no earlier name survives.");
    }
}
