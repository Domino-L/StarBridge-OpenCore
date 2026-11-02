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
        await ScmRoomOverlayIdentityPipeline();
        await ScmRoomKeepaliveGenerationPipeline();
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
        internal string? ViewerAccountId;
        internal bool SupportsMembershipKeepalive;
        internal int KeepaliveCalls;
        internal string? LastKeepaliveBearer;
        internal TaskCompletionSource<bool> KeepaliveSeen = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal TaskCompletionSource<HttpResponseMessage>? HeldDirectory;
        internal TaskCompletionSource<bool> DirectoryHeld = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal bool Joined = true;
        internal HttpStatusCode? DirectoryFailure;
        internal HttpStatusCode? ChatFailure;
        internal bool InvalidDirectory;
        internal bool InvalidChat;
        internal object[] ChatMessages = [];
        internal object? SentMessage;
        internal string? SentChatBody;
        internal string? SentChatBearer;
        internal bool CancelDirectory;
        internal Action? CancelDirectoryAction;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            if (request.RequestUri!.AbsolutePath.EndsWith("/keepalive"))
            {
                LastKeepaliveBearer = request.Headers.Authorization?.Parameter;
                Interlocked.Increment(ref KeepaliveCalls);
                KeepaliveSeen.TrySetResult(true);
                return Task.FromResult(new HttpResponseMessage(Joined ? HttpStatusCode.NoContent : HttpStatusCode.Conflict));
            }
            if (request.RequestUri!.AbsolutePath.EndsWith("/chat") && request.Method == HttpMethod.Post && SentMessage is not null)
            {
                SentChatBody = request.Content!.ReadAsStringAsync(token).GetAwaiter().GetResult();
                SentChatBearer = request.Headers.Authorization?.Parameter;
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(
                    JsonSerializer.Serialize(new { message = SentMessage }), Encoding.UTF8, "application/json") });
            }
            if (request.RequestUri!.AbsolutePath.EndsWith("/chat"))
                return Task.FromResult(new HttpResponseMessage(ChatFailure ?? HttpStatusCode.OK) { Content = new StringContent(
                    InvalidChat ? "{}" : JsonSerializer.Serialize(new { messages = ChatMessages,
                        latestSequence = ChatMessages.Length, oldestSequence = ChatMessages.Length == 0 ? 0 : 1,
                        hasOlder = false }), Encoding.UTF8, "application/json") });
            if (HeldDirectory is { } held)
            {
                DirectoryHeld.TrySetResult(true);
                return held.Task; // Deliberately ignores cancellation to exercise late completion.
            }
            if (DirectoryFailure is { } failure)
                return Task.FromResult(new HttpResponseMessage(failure));
            if (CancelDirectory) { CancelDirectoryAction?.Invoke(); return Task.FromException<HttpResponseMessage>(new OperationCanceledException(token)); }
            if (InvalidDirectory)
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent("{}", Encoding.UTF8, "application/json") });
            var now = DateTimeOffset.UtcNow;
            var room = new PartyRoomSnapshot("fixture-room", "fixture-code", ViewerAccountId ?? "legacy-synthetic", "Fixture", "", [], [], 4,
                true, "everyone", "direct", false, "recommended", "zh", null, now.AddHours(1),
                [new("", "Same callsign", "Self_Handle", null, true, "游戏中 · LIVE", "尚未识别", "", "US", now) { PublicProfileId = ViewerAccountId ?? "legacy-synthetic" },
                 new("", "Same callsign", "Peer_Handle", null, false, "遊戲中 · PTU", "", "", "EU", now) { PublicProfileId = "peer-fixture" }], now, now, 1)
                { ViewerIsHost = true };
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(
                JsonSerializer.Serialize(new { Rooms = new[] { room }, CurrentRoomId = Joined ? room.RoomId : null, ServerTime = now,
                    ViewerAccountId, SupportsMembershipKeepalive,
                    ViewerMembershipToken = SupportsMembershipKeepalive && Joined ? "0123456789abcdef0123456789abcdef" : null },
                    new JsonSerializerOptions(JsonSerializerDefaults.Web)), Encoding.UTF8, "application/json") });
        }
    }

    private static async Task ScmRoomOverlayIdentityPipeline()
    {
        using var loginTransport = new Transport();
        using var login = new LegacyPasswordLoginClient(new Uri("https://example.invalid/"), new Store(), loginTransport);
        using var transport = new OverlayRoomTransport { ViewerAccountId = "scm-v1:" + new string('a', 64) };
        using var rooms = new PartyRoomReader(new Uri("https://example.invalid/"), transport);
        using var host = CreateHost(login, new StarBridge.HostRuntime.Auth.ScmOAuthSession(
            "scm-development", "synthetic", "Synthetic", "synthetic-bearer", DateTimeOffset.UtcNow.AddMinutes(5), []), partyRooms: rooms);
        var context = host.CurrentContext!;
        var directory = await host.GetPartyRoomsAsync(context, default);
        Check(directory.Rooms.Single().Members[0].IsSelf && !directory.Rooms.Single().Members[1].IsSelf,
            "Pure SCM identifies self by authoritative Relay identity, never matching callsigns.");
        Check(host.CurrentRoomOverlay?.Members[0].IsSelf == true, "Pure SCM identity reaches native room overlay.");
        object Message(int sequence, string sender) => new { sequence, messageId = "scm-message-" + sequence,
            kind = "player", senderCallsign = "Same callsign", senderGameId = "", senderAccountId = sender,
            text = "Synthetic", createdAt = DateTimeOffset.UtcNow };
        transport.ChatMessages = [Message(1, transport.ViewerAccountId), Message(2, "peer-fixture")];
        var chatRead = await host.ExecutePartyRoomAsync(context, BridgePayload.From(new { schemaVersion = 1, operation = "chatRead",
            data = new { roomId = "fixture-room", after = 0L, before = 0L } }), default);
        Check(chatRead.AuthorizedOverlayDirectory?.ViewerAccountId == transport.ViewerAccountId &&
            chatRead.Chat!.Messages[0].SenderAccountId == transport.ViewerAccountId,
            "authenticated viewer and sender survive transport to Host projection");
        Check(chatRead.Chat!.Messages[0].IsSelf && !chatRead.Chat.Messages[1].IsSelf,
            "pure SCM history identifies self by authenticated business subject without RSI Handle");
        Check(!BridgePayload.From(chatRead).GetRawText().Contains(transport.ViewerAccountId, StringComparison.Ordinal),
            "chat self projection does not disclose the private business identity to Flutter");
        Check(host.CurrentRoomOverlay?.Members[0].IsSelf == true, "SCM chat preflight preserves self identity.");
        var package = new StarBridge.HostRuntime.Overlay.OverlaySharedPreset(1, "Synthetic preset",
            "0,CallsignAndGameName,0,0,0", "Chat,0,0,0.2,0.2").Serialize();
        var attachment = new StarBridge.Core.Chat.ChatAttachmentContract("overlay_preset", "Synthetic preset", "Layout", package);
        transport.SentMessage = new { sequence = 3, messageId = "scm-preset-3", kind = "player",
            senderCallsign = "Same callsign", senderGameId = "", senderAccountId = transport.ViewerAccountId,
            text = "", createdAt = DateTimeOffset.UtcNow, attachment };
        var sentPreset = await host.ExecutePartyRoomAsync(context, BridgePayload.From(new { schemaVersion = 1,
            operation = "chatSend", data = new { roomId = "fixture-room", text = "", attachment } }), default);
        Check(sentPreset.Message?.IsSelf == true && sentPreset.Message.Attachment?.OverlayPresetPackage == package,
            "pure SCM Host accepts authenticated preset acknowledgement without RSI or legacy identity");
        Check(transport.SentChatBearer == "synthetic-bearer" && transport.SentChatBody is not null,
            "preset send uses current SCM bearer");
        using (var posted = JsonDocument.Parse(transport.SentChatBody!))
            Check(posted.RootElement.GetProperty("attachment").GetProperty("overlayPresetPackage").GetString() == package,
                "actual Host sends the selected local preset package");
        Check(!BridgePayload.From(sentPreset).GetRawText().Contains(transport.ViewerAccountId, StringComparison.Ordinal),
            "preset acknowledgement does not disclose business identity");
        Check(loginTransport.Calls == 0, "SCM room use does not authenticate or create a legacy account.");
        Check(!BridgePayload.From(directory).GetRawText().Contains(transport.ViewerAccountId, StringComparison.Ordinal),
            "SCM business identity never crosses the Flutter bridge.");
        transport.SupportsMembershipKeepalive = true;
        host.EnableRoomMembershipKeepalive(TimeSpan.FromMilliseconds(30));
        await transport.KeepaliveSeen.Task.WaitAsync(TimeSpan.FromSeconds(3));
        Check(transport.KeepaliveCalls > 0, "SCM Host renews with no Flutter page or overlay demand");
        transport.Joined = false;
        await Task.Delay(150);
        var count = Volatile.Read(ref transport.KeepaliveCalls);
        await Task.Delay(150);
        Check(transport.KeepaliveCalls == count && host.CurrentRoomOverlay is null,
            "authoritative room departure stops renewals and clears stale room content");
        transport.HeldDirectory = new(TaskCreationOptions.RunContinuationsAsynchronously);
        await transport.DirectoryHeld.Task.WaitAsync(TimeSpan.FromSeconds(3));
        host.Dispose();
        transport.HeldDirectory.TrySetResult(new HttpResponseMessage(HttpStatusCode.ServiceUnavailable));
        await host.RoomKeepaliveCompletion.WaitAsync(TimeSpan.FromSeconds(3));
        Check(transport.KeepaliveCalls == count, "disposal cancels background liveness even when a late read ignores cancellation");
        Check(host.HangarIdentity is null, "disposed SCM Host cannot authorize a continuing local hangar scan");
    }

    private static async Task ScmRoomKeepaliveGenerationPipeline()
    {
        foreach (var nextSubject in new[] { "synthetic", "different-subject" })
        {
            using var login = new LegacyPasswordLoginClient(new Uri("https://example.invalid/"), new Store(), new Transport());
            var held = new TaskCompletionSource<HttpResponseMessage>(TaskCreationOptions.RunContinuationsAsynchronously);
            using var transport = new OverlayRoomTransport {
                ViewerAccountId = "scm-v1:" + new string('a', 64), SupportsMembershipKeepalive = true, HeldDirectory = held };
            using var rooms = new PartyRoomReader(new Uri("https://example.invalid/"), transport);
            using var host = CreateHost(login, new StarBridge.HostRuntime.Auth.ScmOAuthSession(
                "scm-development", "synthetic", "Synthetic", "old-generation-bearer", DateTimeOffset.UtcNow.AddMinutes(5), []), partyRooms: rooms);
            host.EnableRoomMembershipKeepalive(TimeSpan.FromMilliseconds(30));
            await transport.DirectoryHeld.Task.WaitAsync(TimeSpan.FromSeconds(3));
            var oldCompletion = host.RoomKeepaliveCompletion;
            transport.HeldDirectory = null;
            // Exercise the actual private login publication boundary with synthetic sessions,
            // not a fake authorization server or a new production bypass/test API.
            var publish = typeof(ScmAccountBridgeHost).GetMethod("PublishSession",
                System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)!;
            var replacement = new StarBridge.HostRuntime.Auth.ScmOAuthSession(
                "scm-development", nextSubject, "Synthetic", "new-generation-bearer", DateTimeOffset.UtcNow.AddMinutes(5), []);
            // Real login commits OAuth before Host publication. This fixture's
            // existing reflection publication must reproduce both owner states.
            var oauth = typeof(ScmAccountBridgeHost).GetField("_oauth",
                System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)!.GetValue(host)!;
            oauth.GetType().GetField("_currentSession",
                System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)!.SetValue(oauth, replacement);
            publish.Invoke(host, [replacement, false, null, false, null, null, null, null]);
            held.TrySetResult(new HttpResponseMessage(HttpStatusCode.OK) {
                Content = new ByteArrayContent(PartyRoomReaderTests.Wire("one", PartyRoomReaderTests.Room("one"))) });
            await oldCompletion.WaitAsync(TimeSpan.FromSeconds(3));
            await transport.KeepaliveSeen.Task.WaitAsync(TimeSpan.FromSeconds(3));
            Check(host.Generation == 1 && host.CurrentContext?.Subject == nextSubject &&
                transport.LastKeepaliveBearer == "new-generation-bearer",
                "late room read cannot restore old session or bearer after same-subject login or account change");
            host.Dispose();
            await host.RoomKeepaliveCompletion.WaitAsync(TimeSpan.FromSeconds(3));
        }
        Console.WriteLine("PASS SCM keepalive generation: cancelled late read, same-account relogin and different account");
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
