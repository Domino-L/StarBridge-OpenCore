using StarBridge.Core.Overlay;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Overlay;
using StarBridge.HostRuntime.PartyRooms;
using StarBridge.NativeBridge;
using StarBridge.Core.Events;
using StarBridge.HostRuntime.Privacy;

internal static partial class LegacyPasswordLoginTests
{
    internal static async Task OverlayEventSources()
    {
        using var login = new LegacyPasswordLoginClient(new Uri("https://example.invalid/"), new Store(), new Transport());
        using var transport = new OverlayRoomTransport();
        using var rooms = new PartyRoomReader(new Uri("https://example.invalid/"), transport);
        using var host = CreateHost(login, partyRooms: rooms);
        await host.LoginLegacyAsync(BridgePayload.From(new { schemaVersion = 1, email = "old@example.invalid", password = "synthetic" }), 0, default);
        using var runtime = new AccountBridgeRuntime(host);
        runtime.ConfigureOverlayCommunitySource(Path.Combine(Path.GetTempPath(), "starbridge-event-source-unused"), startDriver: false);
        var sink = new RoomInvalidationSink();
        runtime.ConfigureLiveOverlayUpdates(sink);
        await host.GetPartyRoomsAsync(host.CurrentContext!, default);
        var owner = host.GameplayTimeContext!;
        var key = OverlaySceneChoiceStore.Hash(owner);
        foreach (var (code, sequence) in new[] { ("A", 1L), ("B", 2L), ("C", 3L) })
            host.CommunityRosterObserved!(owner, host.Generation, sequence, DateTimeOffset.UtcNow, new(code, code, []));
        OverlaySourceBinding Org(string code) => new(OverlaySourceMode.Community, code, key);
        sink.Demand = new(new(Org("A"), modules: new Dictionary<OverlaySourceModule, OverlaySourceBinding>
            { [OverlaySourceModule.Events] = Org("B") }), [OverlaySourceModule.Overview, OverlaySourceModule.Events]);
        sink.Visible = true;
        var selected = runtime.CaptureSharedActivityContext();
        Check(selected.Scope == "organization" && selected.Id == "B",
            "Events must subscribe to module organization B, not legacy room or preset organization A.");
        var reader = new ModuleEventReader();
        var notices = new ModuleEventSink();
        using var receiver = new SharedActivityReceiver(reader, notices, runtime.CaptureSharedActivityContext);
        reader.Events = [new("history", "PlayerDied", DateTimeOffset.UtcNow)];
        await receiver.TickAsync();
        Check(reader.Calls.SequenceEqual([("organization", "B")]) && notices.Values.Count == 0,
            "The real receiver reads B once and establishes a silent baseline.");
        reader.Events = [..reader.Events, new("live", "PlayerRevived", DateTimeOffset.UtcNow)];
        await receiver.TickAsync();
        var notice = notices.Values.Single();
        Check(notice.SourceKey == "Community:B" && notice.IsCurrent(), "B's live event carries B's source to Native.");
        long ProbeAllocations()
        {
            for (var i = 0; i < 10; i++) Check(notice.IsCurrent(), "probe warmup remains authorized");
            var start = GC.GetAllocatedBytesForCurrentThread();
            for (var i = 0; i < 100; i++) Check(notice.IsCurrent(), "probe remains authorized");
            return GC.GetAllocatedBytesForCurrentThread() - start;
        }
        var smallProbeBytes = ProbeAllocations();
        var members = Enumerable.Range(0, 512).Select(i => new InformationOverlayCommunityMember(
            "synthetic-" + i, "Fixture", "member", "AppOnline", "", "", "", false)).ToArray();
        host.CommunityRosterObserved!(owner, host.Generation, 4, DateTimeOffset.UtcNow, new("B", "B updated", members));
        var largeProbeBytes = ProbeAllocations();
        Console.WriteLine($"MEASURE 100 event authority probes: empty={smallProbeBytes} bytes, 512 members={largeProbeBytes} bytes");
        Check(largeProbeBytes <= smallProbeBytes + 65536,
            "Queued event authorization must not allocate in proportion to roster payload size.");
        Check(runtime.CaptureSharedActivityContext() == selected && notice.IsCurrent(),
            "Ordinary roster replacement does not reset event baselines or discard a valid queued event.");
        host.CommunityRosterRevoked!(owner, host.Generation, 5, "B");
        Check(runtime.CaptureSharedActivityContext().Scope is null && !notice.IsCurrent(), "Revocation clears B immediately.");
        host.CommunityRosterObserved!(owner, host.Generation, 6, DateTimeOffset.UtcNow, new("B", "B", []));
        Check(runtime.CaptureSharedActivityContext().Id == "B" && !notice.IsCurrent(),
            "Same-source rejoin between ticks must never revive an old event.");
        await receiver.TickAsync();
        Check(notices.Values.Count == 1, "Rejoin starts a new silent event baseline.");
        var withEvents = sink.Demand;
        sink.Demand = new(sink.Demand.Sources, [OverlaySourceModule.Overview]);
        Check(runtime.CaptureSharedActivityContext().Scope is null, "Hidden events do not subscribe to another visible module's source.");
        var reads = reader.Calls.Count;
        await receiver.TickAsync();
        Check(reader.Calls.Count == reads, "Hidden Events issues no feed request.");
        sink.Demand = new(null, [OverlaySourceModule.Events]);
        Check(runtime.CaptureSharedActivityContext().Scope is null, "Malformed v2 never falls back to legacy event scope.");
        foreach (var code in new[] { "D", "E", "F", "G", "H" })
            host.CommunityRosterObserved!(owner, host.Generation, 6, DateTimeOffset.UtcNow, new(code, code, []));
        sink.Demand = new(new(Org("A"), modules: new Dictionary<OverlaySourceModule, OverlaySourceBinding>
        {
            [OverlaySourceModule.Events] = Org("B"), [OverlaySourceModule.Chat] = Org("C"),
            [OverlaySourceModule.Members] = new(OverlaySourceMode.Room)
        }, chatSources: Enumerable.Range('B', 7).Select(c => Org(((char)c).ToString())).ToArray()), Enum.GetValues<OverlaySourceModule>());
        Check(runtime.CaptureSharedActivityContext().Scope is null &&
            runtime.ReadOverlayModules(sink.Demand.Sources!).FailureCode == "overlay.sources_limit_exceeded",
            "Events cannot ignore the other visible modules to admit nine sources beyond the shared limit.");
        sink.Demand = withEvents;
        Check(runtime.CaptureSharedActivityContext().Id == "B", "Changing selections resolves the limit without changing authority.");
        reader.Pending = new(TaskCreationOptions.RunContinuationsAsynchronously);
        reader.Cancelled = new(TaskCreationOptions.RunContinuationsAsynchronously);
        var pending = receiver.TickAsync();
        await reader.Pending.Task.WaitAsync(TimeSpan.FromSeconds(2));
        host.CommunityRosterRevoked!(owner, host.Generation, 7, "B");
        host.CommunityRosterObserved!(owner, host.Generation, 8, DateTimeOffset.UtcNow, new("B", "B", []));
        await reader.Cancelled.Task.WaitAsync(TimeSpan.FromSeconds(2));
        await pending;
        Check(notices.Values.Count == 1, "A rejoin while a request is pending cancels the previous membership read.");
        reader.Pending = new(TaskCreationOptions.RunContinuationsAsynchronously);
        reader.Cancelled = new(TaskCreationOptions.RunContinuationsAsynchronously);
        pending = receiver.TickAsync();
        await reader.Pending.Task.WaitAsync(TimeSpan.FromSeconds(2));
        sink.Visible = false;
        await reader.Cancelled.Task.WaitAsync(TimeSpan.FromSeconds(2));
        await pending;
        Check(runtime.CaptureSharedActivityContext().Scope is null, "Closing cancels an in-flight event feed.");
        sink.Visible = true;
        sink.Demand = new(new(Org("A"), modules: new Dictionary<OverlaySourceModule, OverlaySourceBinding>
            { [OverlaySourceModule.Events] = new(OverlaySourceMode.Room) }), [OverlaySourceModule.Events]);
        var roomEvents = runtime.CaptureSharedActivityContext();
        Check(roomEvents.Scope == "room" && roomEvents.Id == "fixture-room" && roomEvents.AuthorityStamp is not null,
            "An explicit room event module carries the authorized room membership stamp.");
        sink.Demand = new(new(OverlaySourceBinding.Automatic), [OverlaySourceModule.Events]);
        var automaticEvents = runtime.CaptureSharedActivityContext();
        Check(automaticEvents.Scope == "room" && automaticEvents.IsAuthorized?.Invoke() == true,
            "Automatic Events uses the authorized room before any fallback source.");
        transport.Joined = false;
        await host.GetPartyRoomsAsync(host.CurrentContext!, default);
        Check(automaticEvents.IsAuthorized?.Invoke() == false,
            "An automatic room event becomes invalid on confirmed departure without recapturing its subscription.");
        transport.Joined = true;
        await host.GetPartyRoomsAsync(host.CurrentContext!, default);
        Check(automaticEvents.IsAuthorized?.Invoke() == false &&
            runtime.CaptureSharedActivityContext().IsAuthorized?.Invoke() == true,
            "Automatic room rejoin authorizes only the new membership, never the old queued event.");
        sink.Demand = null; // Production v1 still needs the same revocation safety.
        reader.Pending = null;
        await receiver.TickAsync();
        reader.Events = [..reader.Events, new("legacy-live", "PlayerDied", DateTimeOffset.UtcNow)];
        await receiver.TickAsync();
        var legacyNotice = notices.Values.Last();
        Check(legacyNotice.Event.Id == "legacy-live" && legacyNotice.IsCurrent(), "Legacy event path still delivers live room events.");
        transport.Joined = false;
        await host.GetPartyRoomsAsync(host.CurrentContext!, default);
        transport.Joined = true;
        await host.GetPartyRoomsAsync(host.CurrentContext!, default);
        Check(!legacyNotice.IsCurrent(), "Legacy same-room rejoin must not revive a queued event either.");
        await host.LogoutAsync(host.CurrentContext!, default);
        Check(runtime.CaptureSharedActivityContext().Scope is null, "Logout cannot keep a module event subscription alive.");
    }

    private sealed class ModuleEventReader : ISharedActivityReader
    {
        internal SharedActivityEvent[] Events = [];
        internal List<(string Scope, string Id)> Calls = [];
        internal TaskCompletionSource? Pending, Cancelled;
        public async Task<SharedActivityRead> ReadActivityAsync(BridgeAccountContext owner, long generation,
            string scope, string id, CancellationToken token)
        {
            Calls.Add((scope, id));
            if (Pending is not null)
            {
                Pending.TrySetResult();
                try { await Task.Delay(Timeout.Infinite, token); }
                catch (OperationCanceledException) { Cancelled!.TrySetResult(); throw; }
            }
            return new(1, DateTimeOffset.UtcNow, [new("fixture-publisher", "Fixture", Events)]);
        }
    }
    private sealed class ModuleEventSink : ISharedActivitySink
    {
        internal List<SharedActivityNotice> Values = [];
        public ValueTask<bool> TryPresentActivityAsync(SharedActivityNotice notice, CancellationToken token)
        { Values.Add(notice); return ValueTask.FromResult(true); }
    }
}
