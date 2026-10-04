using System.Net;
using System.Text;
using System.Text.Json;
using StarBridge.Core.PartyRooms;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.PartyRooms;
using StarBridge.NativeBridge;

internal static partial class LegacyPasswordLoginTests
{
    internal static async Task RoomOverlayIdentityPipeline()
    {
        using var login = new LegacyPasswordLoginClient(new Uri("https://example.invalid/"), new Store(), new Transport());
        using var roomTransport = new OverlayRoomTransport();
        using var rooms = new PartyRoomReader(new Uri("https://example.invalid/"), roomTransport);
        using var host = CreateHost(login, partyRooms: rooms);
        await host.LoginLegacyAsync(BridgePayload.From(new { schemaVersion = 1, email = "old@example.invalid", password = "synthetic" }), 0, default);
        using var runtime = new StarBridge.HostRuntime.AccountBridgeRuntime(host);
        runtime.ConfigureOverlayCommunitySource(Path.Combine(Path.GetTempPath(), "starbridge-budget-fixture-unused"), startDriver: false);
        var sink = new RoomInvalidationSink();
        runtime.ConfigureLiveOverlayUpdates(sink);
        var context = host.CurrentContext!;
        var directory = await host.GetPartyRoomsAsync(context, default);
        Check(sink.Changes > 0, "Actual Host room publication reaches the native invalidation sink without a periodic read.");
        Check(directory.Rooms.Single().Members[0].IsSelf, "Flutter authorized room directory identifies the current account.");
        Check(host.CurrentRoomOverlay?.Members[0].IsSelf == true,
            "Actual room read must identify self BEFORE publishing the Native overlay roster; otherwise local F8C/state cannot replace shared placeholders.");
        Check(host.CurrentRoomOverlay!.Members[1].IsSelf == false, "Same callsign cannot identify the peer as self.");
        Check(host.CurrentRoomOverlay.Members[0].Presence == "InGame", "Localized versioned presence becomes a wire state before Native projection.");
        Check(host.CurrentRoomOverlay.Members[1].Presence == "InGame", "Peer traditional-Chinese versioned presence is counted as in-game too.");
        await host.ExecutePartyRoomAsync(context, BridgePayload.From(new { schemaVersion = 1, operation = "chatRead",
            data = new { roomId = "fixture-room", after = 0L, before = 0L } }), default);
        Check(host.CurrentRoomOverlay?.Members[0].IsSelf == true,
            "Chat's AuthorizedOverlayDirectory must not overwrite the marked self row with an unmarked raw directory.");
        var ownerKey = StarBridge.HostRuntime.Overlay.OverlaySceneChoiceStore.Hash(host.GameplayTimeContext!);
        StarBridge.Core.Overlay.OverlaySourceBinding Org(string code) => new(StarBridge.Core.Overlay.OverlaySourceMode.Community, code, ownerKey);
        var policy = new StarBridge.Core.Overlay.OverlayPresetSources(Org("A"), modules:
            new Dictionary<StarBridge.Core.Overlay.OverlaySourceModule, StarBridge.Core.Overlay.OverlaySourceBinding>
            {
                [StarBridge.Core.Overlay.OverlaySourceModule.Chat] = Org("B"),
                [StarBridge.Core.Overlay.OverlaySourceModule.Events] = Org("C"),
                [StarBridge.Core.Overlay.OverlaySourceModule.Members] = new(StarBridge.Core.Overlay.OverlaySourceMode.Room)
            }, chatSources: Enumerable.Range('B', 7).Select(c => Org(((char)c).ToString())).ToArray());
        var sequence = 1L;
        foreach (var code in Enumerable.Range('A', 8).Select(c => ((char)c).ToString()))
            host.CommunityRosterObserved!(host.GameplayTimeContext!, host.Generation, sequence++, DateTimeOffset.UtcNow, new(code, code, []));
        Check(runtime.ReadOverlayModules(policy).FailureCode == "overlay.sources_limit_exceeded", "Actual Host display rejects nine authorized sources.");
        roomTransport.InvalidDirectory = true;
        try { await host.GetPartyRoomsAsync(context, default); }
        catch (AccountBridgeHostException) { }
        Check(host.CurrentRoomOverlay is null && runtime.ReadOverlayModules(policy).FailureCode == "overlay.sources_limit_exceeded",
            "Protocol failure and payload clearing cannot unlock a previously exceeded module budget.");
        roomTransport.InvalidDirectory = false;
        roomTransport.Joined = false;
        sink.Changes = 0;
        sink.Demand = new(policy, Enum.GetValues<StarBridge.Core.Overlay.OverlaySourceModule>());
        sink.Visible = true;
        // Remote exit: no Flutter page read/command is allowed to unlock it.
        using (var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(2)))
            while (runtime.ReadOverlayModules(policy).FailureCode is not null) await Task.Delay(10, deadline.Token);
        sink.Visible = false;
        Check(host.CurrentRoomOverlay is null && sink.Changes > 0, "Leaving revokes and notifies the entire local overlay source immediately.");
        Check(runtime.ReadOverlayModules(policy) is { FailureCode: null, Frame: not null },
            "Authenticated room exit unlocks the shared Host budget without changing source choices.");
        sink.Changes = 0;
        await host.LogoutAsync(context, default);
        Check(sink.Changes > 0, "Account invalidation wakes the native sink even without room reads or polling demand.");
    }

    private sealed class RoomInvalidationSink : StarBridge.HostRuntime.Overlay.IInformationOverlayLiveUpdateSink
    {
        internal bool Visible;
        internal StarBridge.HostRuntime.Overlay.InformationOverlayModuleDemand? Demand;
        public bool IsVisible => Volatile.Read(ref Visible);
        public StarBridge.HostRuntime.Overlay.InformationOverlayModuleDemand? ModuleDemand => Volatile.Read(ref Demand);
        internal int Changes;
        public void RequestContentRefresh() => Interlocked.Increment(ref Changes);
    }

    private sealed class OverlayRoomTransport : HttpMessageHandler
    {
        internal bool Joined = true;
        internal HttpStatusCode? DirectoryFailure;
        internal HttpStatusCode? ChatFailure;
        internal bool InvalidDirectory;
        internal bool InvalidChat;
        internal bool CancelDirectory;
        internal Action? CancelDirectoryAction;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            if (request.RequestUri!.AbsolutePath.EndsWith("/chat"))
                return Task.FromResult(new HttpResponseMessage(ChatFailure ?? HttpStatusCode.OK) { Content = new StringContent(
                    InvalidChat ? "{}" : "{\"messages\":[],\"latestSequence\":0,\"oldestSequence\":0,\"hasOlder\":false}", Encoding.UTF8, "application/json") });
            if (DirectoryFailure is { } failure)
                return Task.FromResult(new HttpResponseMessage(failure));
            if (CancelDirectory) { CancelDirectoryAction?.Invoke(); return Task.FromException<HttpResponseMessage>(new OperationCanceledException(token)); }
            if (InvalidDirectory)
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent("{}", Encoding.UTF8, "application/json") });
            var now = DateTimeOffset.UtcNow;
            var room = new PartyRoomSnapshot("fixture-room", "fixture-code", "legacy-synthetic", "Fixture", "", [], [], 4,
                true, "everyone", "direct", false, "recommended", "zh", null, now.AddHours(1),
                [new("", "Same callsign", "Self_Handle", null, true, "游戏中 · LIVE", "尚未识别", "", "US", now) { PublicProfileId = "legacy-synthetic" },
                 new("", "Same callsign", "Peer_Handle", null, false, "遊戲中 · PTU", "", "", "EU", now) { PublicProfileId = "peer-fixture" }], now, now, 1)
                { ViewerIsHost = true };
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(
                JsonSerializer.Serialize(new PartyRoomDirectoryResponse([room], Joined ? room.RoomId : null, now),
                    new JsonSerializerOptions(JsonSerializerDefaults.Web)), Encoding.UTF8, "application/json") });
        }
    }

    internal static async Task RoomOverlayTransientReadPipeline()
    {
        using var login = new LegacyPasswordLoginClient(new Uri("https://example.invalid/"), new Store(), new Transport());
        using var transport = new OverlayRoomTransport();
        using var reader = new PartyRoomReader(new Uri("https://example.invalid/"), transport);
        using var host = CreateHost(login, partyRooms: reader);
        await host.LoginLegacyAsync(BridgePayload.From(new { schemaVersion = 1, email = "old@example.invalid", password = "synthetic" }), 0, default);
        var owner = host.CurrentContext!;
        async Task Fail(Func<Task> action, bool cancellation = false)
        {
            try { await action(); }
            catch (AccountBridgeHostException) { return; }
            catch (OperationCanceledException) when (cancellation) { return; }
            throw new Exception("The failed read must still report its error to the client.");
        }
        await host.GetPartyRoomsAsync(owner, default);
        var previous = host.CurrentRoomOverlay!;
        transport.DirectoryFailure = HttpStatusCode.ServiceUnavailable;
        await Fail(() => host.GetPartyRoomsAsync(owner, default));
        Check(ReferenceEquals(host.CurrentRoomOverlay, previous),
            "Transient directory failure must not erase all still-authorized room overlay information.");
        var chat = BridgePayload.From(new { schemaVersion = 1, operation = "chatRead", data = new { roomId = "fixture-room", after = 0L, before = 0L } });
        await Fail(() => host.ExecutePartyRoomAsync(owner, chat, default));
        Check(ReferenceEquals(host.CurrentRoomOverlay, previous), "Chat preflight outage must not erase the valid room scene.");
        transport.DirectoryFailure = null;
        transport.CancelDirectory = true;
        using (var cancellation = new CancellationTokenSource())
        {
            transport.CancelDirectoryAction = cancellation.Cancel;
            await Fail(() => host.GetPartyRoomsAsync(owner, cancellation.Token), cancellation: true);
        }
        Check(ReferenceEquals(host.CurrentRoomOverlay, previous), "Cancelled directory GET does not revoke a still-valid lease.");
        using (var cancellation = new CancellationTokenSource())
        {
            transport.CancelDirectoryAction = cancellation.Cancel;
            await Fail(() => host.ExecutePartyRoomAsync(owner, chat, cancellation.Token), cancellation: true);
        }
        Check(ReferenceEquals(host.CurrentRoomOverlay, previous), "Cancelled chat preflight does not blank the valid scene.");
        transport.CancelDirectory = false;
        transport.CancelDirectoryAction = null;
        transport.ChatFailure = HttpStatusCode.ServiceUnavailable;
        await Fail(() => host.ExecutePartyRoomAsync(owner, chat, default));
        Check(ReferenceEquals(host.CurrentRoomOverlay, previous), "Chat-only read outage must not blank the valid roster.");
        transport.ChatFailure = null;
        await host.GetPartyRoomsAsync(owner, default);
        Check(host.CurrentRoomOverlay!.ContinuityId == previous.ContinuityId, "Recovery preserves scene continuity and does not replay history.");
        transport.ChatFailure = HttpStatusCode.Forbidden;
        await Fail(() => host.ExecutePartyRoomAsync(owner, chat, default));
        Check(host.CurrentRoomOverlay is null, "Chat authority rejection clears the room scene immediately.");
        transport.ChatFailure = null;
        await host.GetPartyRoomsAsync(owner, default);
        transport.InvalidChat = true;
        await Fail(() => host.ExecutePartyRoomAsync(owner, chat, default));
        Check(host.CurrentRoomOverlay is null, "Invalid chat schema cannot preserve authorization.");
        transport.InvalidChat = false;
        await host.GetPartyRoomsAsync(owner, default);
        transport.DirectoryFailure = HttpStatusCode.ServiceUnavailable;
        await Fail(() => host.ExecutePartyRoomAsync(owner, BridgePayload.From(new { schemaVersion = 1,
            operation = "chatSend", data = new { roomId = "fixture-room", text = "Synthetic" } }), default));
        Check(host.CurrentRoomOverlay is null, "A mutation failure is never treated as a harmless GET outage.");
        transport.DirectoryFailure = null;
        await host.GetPartyRoomsAsync(owner, default);
        transport.DirectoryFailure = HttpStatusCode.Forbidden;
        await Fail(() => host.GetPartyRoomsAsync(owner, default));
        Check(host.CurrentRoomOverlay is null, "Authority rejection clears immediately.");
        transport.DirectoryFailure = null;
        await host.GetPartyRoomsAsync(owner, default);
        transport.InvalidDirectory = true;
        await Fail(() => host.GetPartyRoomsAsync(owner, default));
        Check(host.CurrentRoomOverlay is null, "Invalid directory schema still fails closed.");
        transport.InvalidDirectory = false;
        await host.GetPartyRoomsAsync(owner, default);
        transport.Joined = false;
        await host.GetPartyRoomsAsync(owner, default);
        Check(host.CurrentRoomOverlay is null, "Verified loss of membership still clears immediately.");
    }
}
