using System.Text.Json;
using StarBridge.Core.Events;
using StarBridge.Core.Friends;
using StarBridge.Core.Identity;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Privacy;
using StarBridge.HostRuntime.Settings;
using StarBridge.HostRuntime.Support;
using StarBridge.NativeBridge;

internal static partial class SharingReviewRegressionTests
{
    internal static async Task M04h()
    {
        var tests = new List<(string Name, Func<Task> Run)>();
        foreach (var mode in new[] { "latched", "persisted", "recreated" })
            tests.Add(("all publishers honor " + mode + " pause", () => CrossPublisherPause(mode)));
        foreach (var lane in new[] { "friend", "event", "room" })
            tests.Add((lane + " transport rechecks pause at final admission", () => TransportPause(lane)));
        foreach (int? observation in new int?[] { null, 0 })
        {
            foreach (var restart in new[] { false, true })
                tests.Add(($"empty handle stop {observation} restart={restart}", () => EmptyHandleStop(observation, restart)));
            tests.Add(($"empty handle network projection {observation}", () => EmptyHandleNetwork(observation)));
        }
        var failed = 0;
        foreach (var (name, run) in tests)
        {
            try { await run(); Console.WriteLine("PASS M04h " + name); }
            catch (Exception e) { failed++; Console.WriteLine("FAIL M04h " + name + ": " + e.Message); }
        }
        Console.WriteLine($"M04h cases: {tests.Count - failed} passed, {failed} failed");
        Check(failed == 0, "M04h regression failures");
    }

    private sealed class M04hRuntime : IDisposable
    {
        internal readonly Fixture Data = new();
        internal readonly ScmAccountBridgeHost Host;
        internal readonly AccountBridgeRuntime Runtime;
        internal readonly PrivacyPublication Main;
        internal readonly FriendSharingRuntime Friends;
        internal readonly EventSharingRuntime Events;
        internal readonly M04hRemote Remote = new();
        internal readonly LocalGameEventJournal Journal;
        private readonly M04fHandler _handler = new();
        internal int Positives, Clears;
        internal BridgeAccountContext Owner => Host.GameplayTimeContext!;
        internal M04hRuntime(bool emptyHandle = false)
        {
            var session = new ScmOAuthSession("fixture-scm", "fixture-subject", "Fixture", "synthetic-only",
                DateTimeOffset.UtcNow.AddMinutes(5), [], GameIdentityHandle: emptyHandle ? null : "Fixture",
                GameIdentityStatus: emptyHandle ? ScmGameIdentityStatus.Unverified : ScmGameIdentityStatus.Verified);
            Host = new(new OAuthPkceClient(new ScmHttpClient(_handler), new NoM04gVault(), ScmOAuthOptions.CreateDefault()),
                new ScmProfileCacheStore(), "fixture", () => null, initialSession: session);
            using var choiceHandler = new AdmissionHandler("official");
            var settings = emptyHandle ? Data.Settings with {
                Fleet = new(PlayerSharedStateFields.None, false, false, []), Communities = [], OfficialFleet = choiceHandler.Choice
            } : Data.Settings;
            Data.Store.Save(Owner, 0, Guid.NewGuid().ToString("N"), settings, () => true);
            Journal = new(Path.Combine(Data.Root, "local-event-log.json"));
            Journal.Load();
            SetM04gObservation(Host, 1);
            Runtime = new(Host, privacy: Data.Store, visibility: new(Data.Root), eventJournal: Journal,
                backgroundTime: new SharingTestClock());
            Main = emptyHandle ? PrivacyPublicationTestAccess.Official(Runtime) : PrivacyPublicationTestAccess.Ordinary(Runtime);
            Friends = Field<FriendSharingRuntime>(Runtime, "_friendSharing");
            Events = Field<EventSharingRuntime>(Runtime, "_eventSharing");
            typeof(PrivacyPublication).GetField("_send", PrivateInstance)!.SetValue(Main,
                new Func<PrivacyPublicationInput, JsonElement, CancellationToken, Task>(Send));
            typeof(FriendSharingRuntime).GetField("_remote", PrivateInstance)!.SetValue(Friends, Remote);
            typeof(EventSharingRuntime).GetField("_settings", PrivateInstance)!.SetValue(Events, Remote);
            typeof(EventSharingRuntime).GetField("_remote", PrivateInstance)!.SetValue(Events, Remote);
        }
        internal Task Send(PrivacyPublicationInput input, JsonElement body, CancellationToken ct)
        {
            Runtime.RequireCurrentPrivacyPublication(input, body, ct);
            if (body.GetProperty("online").GetBoolean()) Positives++; else Clears++;
            return Task.CompletedTask;
        }
        internal PrivacyPublicationInput? Input(string method) =>
            (PrivacyPublicationInput?)typeof(AccountBridgeRuntime).GetMethod(method, PrivateInstance)!.Invoke(Runtime, null);
        internal async Task Start()
        {
            await Main.ApplyAsync(Owner, Host.Generation, 1, default);
            Check(Positives == 1, "main publisher starts");
        }
        public void Dispose() { Runtime.Dispose(); Host.Dispose(); Journal.Dispose(); _handler.Dispose(); Data.Dispose(); }
    }

    private static T Field<T>(object owner, string name) => (T)owner.GetType().GetField(name, PrivateInstance)!.GetValue(owner)!;

    private static async Task CrossPublisherPause(string mode)
    {
        using var f = new M04hRuntime();
        await f.Start();
        await f.Friends.TickAsync(); await f.Events.TickAsync();
        Check(f.Remote.Calls.SequenceEqual(new[] { "friend.start", "friend.publish", "event.start", "event.append" }),
            "both actual composed publishers must start before pausing");
        f.Main.ObserveVisibility(new(f.Owner, f.Host.Generation, "fixture", 3, PlayerPresenceVisibilityMode.Invisible, null));
        if (mode != "latched")
        {
            await f.Main.TickAsync();
            Check(f.Data.Store.IsPublicationPaused(f.Owner) && f.Clears > 0, "main persists and withdraws");
        }
        if (mode == "recreated")
        {
            // Remove the in-memory latch to isolate the durable-store gate.
            typeof(PrivacyPublication).GetField("_observedPause", PrivateInstance)!.SetValue(f.Main, null);
            typeof(PrivacyPublication).GetField("_pendingPause", PrivateInstance)!.SetValue(f.Main, null);
            f.Main.Invalidate();
        }
        SetM04gObservation(f.Host, 1);
        var count = f.Remote.Calls.Count;
        await f.Friends.TickAsync(); await f.Events.TickAsync();
        await f.Friends.TickAsync(); await f.Events.TickAsync();
        Check(f.Remote.Calls.Skip(count).All(c => c.EndsWith(".stop")), "paused channels must not start/publish/append after observed 1");
        await f.Main.TickAsync();
        Check(f.Positives == 1, "main remains paused too");
        await f.Main.ApplyAsync(f.Owner, f.Host.Generation, 1, default);
        await f.Friends.TickAsync(); await f.Events.TickAsync();
        Check(f.Remote.Calls.Skip(count).Count(c => !c.EndsWith(".stop")) == 4 && f.Positives == 2,
            "only explicit apply resumes all three publishers");
    }

    private static async Task EmptyHandleStop(int? observation, bool restart)
    {
        using var f = new M04hRuntime(true);
        await f.Start();
        SetM04gObservation(f.Host, observation);
        await f.Main.TickAsync();
        Check(f.Input("PublicationInput") is null, "positive input is absent");
        Check(await f.Main.StopAsync(default, explicitRequest: true), "explicit stop succeeds");
        Check(!new LocalPrivacyStore(f.Data.Root).HasPublicationConsent(f.Owner), "stop must durably revoke consent without Handle");
        Check(f.Clears > 0, "stop must clear remote sharing");
        SetM04gObservation(f.Host, 1);
        if (restart)
        {
            using var fresh = new PrivacyPublication(new(f.Data.Root), () => f.Input("PublicationInput"), f.Send,
                startTimer: false, currentOwner: () => f.Input("PublicationOwnerInput"));
            await fresh.TickAsync();
        }
        else { f.Main.Invalidate(); await f.Main.TickAsync(); }
        Check(f.Positives == 1, "online after restart/invalidate cannot restore revoked sharing");
    }

    private static async Task EmptyHandleNetwork(int? observation)
    {
        using var f = new M04hRuntime(true);
        await f.Start();
        SetM04gObservation(f.Host, observation);
        await f.Main.TickAsync();
        var status = f.Main.StatusFor(f.Owner);
        Check(status.State == "reconnecting" && status.ErrorCode == "privacy_publication.network_unavailable",
            "Host must project network problem, got " + status.State + "/" + status.ErrorCode);
        Check(f.Data.Store.HasPublicationConsent(f.Owner) && f.Positives == 1, "disconnect retains consent without positive writes");
        SetM04gObservation(f.Host, 1);
        await f.Main.TickAsync();
        Check(f.Positives == 2, "ordinary network recovery still resumes");
    }

    private static async Task TransportPause(string lane)
    {
        using var f = new M04hRuntime();
        using var handler = new M04hTransport();
        using var writer = new PrivacyRelayWriter(new Uri("https://sharing.invalid"), handler);
        f.Host.ConfigurePrivacyWriter(writer);
        using var rooms = new StarBridge.HostRuntime.PartyRooms.PartyRoomReader(new Uri("https://sharing.invalid"), handler);
        typeof(ScmAccountBridgeHost).GetField("_partyRooms", PrivateInstance)!.SetValue(f.Host, rooms);
        await f.Start();
        Task Send() => lane switch {
            "friend" => f.Host.WriteFriendLiveAsync(f.Input("PublicationInput")!, "start", 1, null, 0, null, default),
            "event" => f.Host.WriteEventFeedAsync(f.Owner, f.Host.Generation, "start", 1, null, 0, [], default),
            _ => (Task)typeof(ScmAccountBridgeHost).GetMethod("RenewRoomMembershipAsync", PrivateInstance)!
                .Invoke(f.Host, [f.Owner, f.Host.Generation, CancellationToken.None])!
        };
        await Send();
        Check(handler.Posts == 1, lane + " initial transport must actually POST to the in-memory handler");
        var lease = await f.Data.Store.PositiveAdmission.EnterAsync(default);
        try
        {
            var pending = Send();
            Check(!pending.IsCompleted, lane + " must wait for shared admission");
            f.Main.ObserveVisibility(new(f.Owner, f.Host.Generation, "fixture", 3, PlayerPresenceVisibilityMode.Invisible, null));
            SetM04gObservation(f.Host, 1);
            lease.Dispose();
            try { await pending; throw new Exception("late positive send was admitted"); }
            catch (OperationCanceledException) { }
            Check(handler.Posts == 1, lane + " final guard must reject latched pause before POST");
        }
        finally { lease.Dispose(); }
        await f.Main.TickAsync();
        Check(f.Data.Store.IsPublicationPaused(f.Owner), "pause is durable");
        try { await Send(); } catch (OperationCanceledException) { }
        Check(handler.Posts == 1, lane + " remains blocked after ordinary online observation");
        await f.Main.ApplyAsync(f.Owner, f.Host.Generation, 1, default);
        await Send();
        Check(handler.Posts == 2, lane + " resumes only after explicit apply");
    }

    private sealed class M04hTransport : HttpMessageHandler
    {
        internal int Posts;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            if (request.Method == HttpMethod.Get)
            {
                var directory = System.Text.Json.Nodes.JsonNode.Parse(PartyRoomReaderTests.Wire("one", PartyRoomReaderTests.Room("one")))!;
                directory["supportsMembershipKeepalive"] = true;
                directory["viewerMembershipToken"] = "0123456789abcdef0123456789abcdef";
                return new(System.Net.HttpStatusCode.OK) { Content = new StringContent(directory.ToJsonString()) };
            }
            Posts++;
            if (request.RequestUri!.AbsolutePath == "/api/party-rooms/keepalive") return new(System.Net.HttpStatusCode.NoContent);
            using var body = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(ct));
            var sequence = body.RootElement.GetProperty("sequence").GetInt64();
            var session = Guid.NewGuid().ToString("N");
            object receipt = request.RequestUri.AbsolutePath == "/api/friends/live"
                ? new { schemaVersion = 1, session, sequence }
                : new { schemaVersion = 1, sessionId = session, sequence, expiresAt = DateTimeOffset.UtcNow.AddMinutes(1) };
            return new(System.Net.HttpStatusCode.OK) { Content = new StringContent(JsonSerializer.Serialize(receipt)) };
        }
    }

    private sealed class M04hRemote : IFriendSharingRemote, IEventSharingRemote, IEventFeedRemote
    {
        internal readonly List<string> Calls = [];
        public Task<FriendSharingRemoteSnapshot> ReadFriendSharingAsync(BridgeAccountContext o, long g, CancellationToken t) =>
            Task.FromResult(new FriendSharingRemoteSnapshot(1, 1, Guid.NewGuid().ToString("N"), DateTimeOffset.UtcNow, FriendSharedFields.Presence));
        public Task<FriendSharingRemoteSnapshot> SaveFriendSharingAsync(BridgeAccountContext o, long g, long r, string op, FriendSharedFields f, CancellationToken t) => throw new NotSupportedException();
        public Task<string> WriteFriendLiveAsync(PrivacyPublicationInput input, string action, long r, string? s, long seq, FriendSharingSource? source, CancellationToken t)
        { Calls.Add("friend." + action); return Task.FromResult(s ?? Guid.NewGuid().ToString("N")); }
        public Task<EventSharingRemoteSnapshot> ReadEventsAsync(BridgeAccountContext o, long g, CancellationToken t) =>
            Task.FromResult(new EventSharingRemoteSnapshot(1, 1, Guid.NewGuid().ToString("N"), DateTimeOffset.UtcNow, true,
                new(new(true, SharedActivityEventTypes.All), [])));
        public Task<EventSharingRemoteSnapshot> SaveEventsAsync(BridgeAccountContext o, long g, long r, string op, bool enabled, SharedEventPreferences p, CancellationToken t) => throw new NotSupportedException();
        public Task<EventFeedReceipt> WriteEventFeedAsync(BridgeAccountContext o, long g, string action, long r, string? s, long seq, SharedActivityEvent[] events, CancellationToken t)
        { Calls.Add("event." + action); return Task.FromResult(new EventFeedReceipt(s ?? Guid.NewGuid().ToString("N"), seq)); }
    }
}


