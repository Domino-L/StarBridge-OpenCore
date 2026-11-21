using System.Net;
using System.Net.Http.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Privacy;
using StarBridge.NativeBridge;

internal static partial class LegacyPasswordLoginTests
{
    internal static async Task SharingQueueProbe()
    {
        await SharingMutationBarrier();
        await SharingQueueCase(false);
        await SharingQueueCase(true);
        await SharingQueueCase(false, true);
        await SharingQueueCase(true, true);
        await SharingQueueCase(true, false, true);
        await SharingQueueCase(true, true, true);
        await SharingSettingsQueueCase(false);
        await SharingSettingsQueueCase(true);
    }
    private static async Task SharingMutationBarrier()
    {
        using var gate = new AccountMutationGate();
        var reads = new List<IAsyncDisposable>();
        for (var i = 0; i < 4; i++) reads.Add(await gate.EnterSharedAsync(default));
        using var fifthCancellation = new CancellationTokenSource();
        var fifth = gate.EnterSharedAsync(fifthCancellation.Token).AsTask();
        Check(!fifth.IsCompleted, "Sharing concurrency must remain bounded.");
        fifthCancellation.Cancel();
        try { await fifth; throw new Exception("Cancelled admission must not leak a slot."); }
        catch (OperationCanceledException) { }
        Check(!await gate.WaitAsync(0, default), "Account mutation cannot bypass in-flight sharing.");
        var mutation = gate.WaitAsync();
        var lateRead = gate.EnterSharedAsync(default).AsTask();
        Check(!mutation.IsCompleted && !lateRead.IsCompleted, "Pending account mutation must stop new sharing admission.");
        foreach (var read in reads) await read.DisposeAsync();
        await mutation.WaitAsync(TimeSpan.FromSeconds(2));
        Check(!lateRead.IsCompleted, "Sharing must not cross an active account mutation.");
        gate.Release();
        await using var admitted = await lateRead.WaitAsync(TimeSpan.FromSeconds(2));
    }
    private static async Task SharingSettingsQueueCase(bool friends)
    {
        using var transport = new ScmHandlePrivacyTransport();
        var uri = new Uri("http://127.0.0.1:9/");
        var oauth = new OAuthPkceClient(new ScmHttpClient(transport), new ScmVisitorVault(),
            new ScmOAuthOptions("synthetic", uri, uri, uri, "synthetic", "synthetic", "openid profile.read", "/callback"));
        using var host = new ScmAccountBridgeHost(oauth, new ScmProfileCacheStore(), "integration", () => null,
            initialSession: new ScmOAuthSession("synthetic", "owner", "Pilot", "synthetic-read-token",
                DateTimeOffset.UtcNow.AddHours(1), ["profile.read"], GameIdentityVerified: true, GameIdentityHandle: "Pilot"),
            profileAuthorization: new ScmVisibilityAuthorization());
        using var wire = new QueueProbeTransport { HeldSettingsPath = friends ? "/api/friends/sharing" : "/api/privacy/events" };
        host.ConfigurePrivacyWriter(new PrivacyRelayWriter(uri, wire));
        var owner = host.CurrentContext!;
        Task Read() => friends ? host.ReadFriendSharingAsync(owner, host.Generation, default) : host.ReadEventsAsync(owner, host.Generation, default);
        var read = Read();
        await wire.SettingsEntered.Task.WaitAsync(TimeSpan.FromSeconds(2));
        var queuedRead = Read();
        var input = new PrivacyPublicationInput(owner, host.Generation, "Pilot", true, null,
            StarBridge.HostRuntime.Presence.GameLogSessionSnapshot.Empty);
        var payload = PrivacyPublicationPayload.Build(input, LocalPrivacySettings.EditorDefaults with { Communities = [] }, false);
        var send = host.PublishPrivacyAsync(input, payload, default);
        var completed = false;
        try { await send.WaitAsync(TimeSpan.FromSeconds(3)); completed = true; }
        catch (TimeoutException) { }
        finally
        {
            wire.ReleaseSettings.TrySetResult();
            foreach (var pending in new[] { read, queuedRead })
                try { await pending; }
                catch (AccountBridgeHostException error) when (error.Code == "events.temporarily_unavailable") { }
            await send;
        }
        Check(completed, "Other sharing settings reads starve renewal; friends=" + friends);
        await Read();
        if (friends)
        {
            wire.HoldSettingsWrite = true;
            using var writeCancellation = new CancellationTokenSource();
            var save = host.SaveFriendSharingAsync(owner, host.Generation, 0, Guid.NewGuid().ToString("N"),
                StarBridge.Core.Friends.FriendSharedFields.None, writeCancellation.Token);
            await wire.SettingsWriteEntered.Task.WaitAsync(TimeSpan.FromSeconds(2));
            var afterWrite = host.PublishPrivacyAsync(input, payload, default);
            var independent = false;
            try
            {
                await afterWrite.WaitAsync(TimeSpan.FromSeconds(2));
                independent = true;
                Check(!save.IsCompleted, "Independent publication must not cancel a sharing settings write.");
            }
            catch (TimeoutException) { }
            finally
            {
                writeCancellation.Cancel();
                try { await save; throw new Exception("Caller cancelled settings write must stop."); }
                catch (OperationCanceledException) { }
                await afterWrite;
            }
            Check(independent, "Realtime publication is blocked by an unrelated friend settings write.");
            await Read();
        }
    }
    private static async Task SharingQueueCase(bool initialApply, bool communityRead = false, bool heartbeat = false)
    {
        // 11-15: SCM game ID settings read the Relay first (Hong Kong is only kept in step),
        // so the held read is the Relay display read.
        using var transport = new ScmHandlePrivacyTransport();
        var uri = new Uri("http://127.0.0.1:9/");
        var oauth = new OAuthPkceClient(new ScmHttpClient(transport), new ScmVisitorVault(),
            new ScmOAuthOptions("synthetic", uri, uri, uri, "synthetic", "synthetic", "openid profile.read", "/callback"));
        using var host = new ScmAccountBridgeHost(oauth, new ScmProfileCacheStore(), "integration", () => null,
            initialSession: new ScmOAuthSession("synthetic", "owner", "Pilot", "synthetic-read-token",
                DateTimeOffset.UtcNow.AddHours(1), ["profile.read"], GameIdentityVerified: true, GameIdentityHandle: "Pilot"),
            profileAuthorization: new ScmVisibilityAuthorization());
        using var wire = new QueueProbeTransport { HoldDirectory = communityRead };
        wire.Display.HoldRead = !communityRead;
        host.ConfigurePrivacyWriter(new PrivacyRelayWriter(uri, wire));
        var owner = host.CurrentContext!;
        Task read = communityRead ? host.ReadCommunitySharingTargetsAsync(owner, host.Generation, default) :
            host.ReadGameIdAsync(owner, host.Generation, default);
        await (communityRead ? wire.DirectoryEntered.Task : wire.Display.ReadEntered.Task).WaitAsync(TimeSpan.FromSeconds(2));
        wire.HoldDirectory = false;
        wire.Display.HoldRead = false;
        // Reads already queued behind the active read must also yield. Cancelling
        // just the current request leaves these able to consume the whole deadline.
        var queuedRead = host.ReadGameIdAsync(owner, host.Generation, default);
        var queuedDirectory = host.ReadCommunitySharingTargetsAsync(owner, host.Generation, default);
        var input = new PrivacyPublicationInput(owner, host.Generation, "Pilot", true, null,
            StarBridge.HostRuntime.Presence.GameLogSessionSnapshot.Empty, PrioritizeNetwork: initialApply && !heartbeat);
        var clear = PrivacyPublicationPayload.Build(input, LocalPrivacySettings.EditorDefaults with { Communities = [] }, !initialApply);
        try { await host.PublishPrivacyAsync(input with { Generation = input.Generation - 1 }, clear, default); }
        catch (AccountBridgeHostException error) when (error.Code == "privacy_publication.account_changed") { }
        Check(!read.IsCompleted, "A stale generation must not cancel the current owner's read.");
        var send = host.PublishPrivacyAsync(input, clear, default);
        if (heartbeat)
        {
            await Task.Delay(100);
            Check(!read.IsCompleted, "A background renewal must give an active read a grace period.");
        }
        var completed = false;
        try { await send.WaitAsync(TimeSpan.FromSeconds(heartbeat ? 3 : 1)); completed = true; }
        catch (TimeoutException) { }
        finally
        {
            transport.ReleaseRead.TrySetResult();
            wire.ReleaseDirectory.TrySetResult();
            wire.Display.ReleaseRead.TrySetResult();
            foreach (var pending in new Task[] { read, queuedRead, queuedDirectory })
            {
                try { await pending; }
                catch (AccountBridgeHostException error) when (error.Code is "gameId.unavailable" or "privacy_publication.temporarily_unavailable") { }
            }
            await send;
        }
        Check(completed, "Queued privacy reads block publication before HTTP; initialApply=" + initialApply + "; communityRead=" + communityRead + "; heartbeat=" + heartbeat);
        transport.HoldRead = false;
        await host.ReadGameIdAsync(owner, host.Generation, default);
        transport.HoldWrite = true;
        // Locations 4 differ from Hong Kong's 0, so the held PATCH is the Hong Kong mirror write.
        var save = host.SaveGameIdAsync(owner, host.Generation, wire.Display.Revision, wire.Display.Stamp, 4, default);
        await transport.WriteEntered.Task.WaitAsync(TimeSpan.FromSeconds(2));
        using var cancelledPriority = new CancellationTokenSource();
        var cancelledSend = host.PublishPrivacyAsync(input, clear, cancelledPriority.Token);
        cancelledPriority.Cancel();
        try { await cancelledSend; throw new Exception("Cancelled queued publication must not succeed."); }
        catch (OperationCanceledException) { }
        var afterWrite = host.PublishPrivacyAsync(input, clear, default);
        await Task.Delay(100);
        Check(!save.IsCompleted && !afterWrite.IsCompleted, "Withdrawal must not interrupt an authorized privacy write.");
        transport.ReleaseWrite.TrySetResult();
        await save;
        await afterWrite;
        await host.ReadGameIdAsync(owner, host.Generation, default);
        await host.ReadCommunitySharingTargetsAsync(owner, host.Generation, default);
    }
    private sealed class QueueProbeTransport : HttpMessageHandler
    {
        internal string? HeldSettingsPath;
        internal bool HoldSettingsWrite;
        internal readonly TaskCompletionSource SettingsWriteEntered = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource SettingsEntered = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource ReleaseSettings = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal bool HoldDirectory;
        // Queue mechanics only; decision 乙 refusals are covered in ScmSingleCallsignTests.
        internal readonly ScmDisplayRelayFake Display = new() { EnforceRuleB = false };
        internal readonly TaskCompletionSource DirectoryEntered = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource ReleaseDirectory = new(TaskCreationOptions.RunContinuationsAsynchronously);
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            if (ScmDisplayRelayFake.Handles(request)) return await Display.SendAsync(request, token);
            if (request.RequestUri!.AbsolutePath == HeldSettingsPath)
            {
                if (HoldSettingsWrite && request.Method == HttpMethod.Post)
                {
                    SettingsWriteEntered.TrySetResult();
                    await Task.Delay(Timeout.InfiniteTimeSpan, token);
                }
                SettingsEntered.TrySetResult();
                await ReleaseSettings.Task.WaitAsync(token);
                return new(HttpStatusCode.OK) { Content = new StringContent(HeldSettingsPath == "/api/friends/sharing"
                    ? "{\"schemaVersion\":1,\"revision\":0,\"operationId\":null,\"appliedAt\":null,\"fields\":null}"
                    : "{\"schemaVersion\":1,\"revision\":0,\"operationId\":null,\"appliedAt\":null,\"publicationEnabled\":false,\"settings\":null}") };
            }
            if (request.RequestUri!.AbsolutePath == "/api/privacy/community-scopes")
            {
                if (HoldDirectory)
                {
                    DirectoryEntered.TrySetResult();
                    await ReleaseDirectory.Task.WaitAsync(token);
                }
                return new(HttpStatusCode.OK) { Content = new StringContent("{\"schemaVersion\":2,\"primaryFleetCode\":null,\"communities\":[]}") };
            }
            Check(request.RequestUri!.AbsolutePath == "/api/players/realtime-scoped", "clear stays scoped");
            var response = new HttpResponseMessage(HttpStatusCode.OK) {
                Content = new StringContent(await request.Content!.ReadAsStringAsync(token))
            };
            response.Headers.Add("X-StarBridge-Realtime-Version", "3");
            return response;
        }
    }
    internal static async Task ScmHandlePrivacy()
    {
        await SharingQueueProbe();
        // 11-15 decision 甲: the Relay (r49) is the authority for SCM game ID locations;
        // Hong Kong handle-privacy is kept in step and read back.
        using var transport = new ScmHandlePrivacyTransport();
        var uri = new Uri("http://127.0.0.1:9/");
        var oauth = new OAuthPkceClient(new ScmHttpClient(transport), new ScmVisitorVault(),
            new ScmOAuthOptions("synthetic", uri, uri, uri, "synthetic", "synthetic", "openid profile.read", "/callback"));
        var authorization = new ScmVisibilityAuthorization();
        using var host = new ScmAccountBridgeHost(oauth, new ScmProfileCacheStore(), "integration", () => null,
            initialSession: new ScmOAuthSession("synthetic", "owner", "Pilot", "synthetic-read-token",
                DateTimeOffset.UtcNow.AddHours(1), ["profile.read"]), profileAuthorization: authorization);
        // Locations/mirror mechanics only; decision 乙 refusals are covered in ScmSingleCallsignTests.
        var relay = new ScmDisplayRelayFake { EnforceRuleB = false };
        using var relayWire = new DisplayOnlyTransport(relay);
        host.ConfigurePrivacyWriter(new PrivacyRelayWriter(uri, relayWire));
        var dispatcher = new GameIdSettingsDispatcher(host, () => (host.GameplayTimeContext, host.Generation));
        var owner = host.CurrentContext!; var generation = host.Generation;
        Task<BridgeDispatchBatch> Send(string name, object payload) => dispatcher.DispatchAsync(
            BridgeEnvelope.Request(name, "handle-privacy", generation, payload, owner), default);
        Task<BridgeDispatchBatch> Request(bool save, int mask = 4) => save
            ? Send("gameIdVisibility.save", new { schemaVersion = 1, expectedRevision = relay.Revision, identityStamp = relay.Stamp, locations = mask })
            : Send("gameIdVisibility.read", new { schemaVersion = 1 });
        string Mirror(BridgeDispatchBatch batch) => batch.Response.Payload.GetProperty("mirror").GetString()!;

        var read = await Request(false);
        Check(read.Response.Error is null && read.Response.Payload.GetProperty("locations").GetInt32() == 15 &&
            read.Response.Payload.EnumerateObject().Count() == 7 && Mirror(read) == "synced" && relay.Imports == 0,
            "decision 乙: an SCM account that never set anything shows everywhere; nothing to import");
        var saved = await Request(true);
        Check(saved.Response.Error is null && relay.Revision == 1 && relay.Locations == 4 &&
            transport.Locations == 4 && Mirror(saved) == "synced", "save writes the Relay, then mirrors Hong Kong");
        var patches = transport.Patches;
        await Request(false);
        Check(transport.Patches == patches, "a read never writes Hong Kong");
        foreach (var mode in new[] { "denied", "wrong-subject", "missing-scope" })
        {
            authorization.Mode = mode;
            patches = transport.Patches;
            var partial = await Request(true, mode == "denied" ? 0 : 4 ^ 8);
            // A grant for another account ends the operation (client review R1): sign in again.
            Check((mode == "wrong-subject"
                    ? partial.Response.Error?.Code == "account.reauthorization_required"
                    : partial.Response.Error is null && Mirror(partial) == "pending") && transport.Patches == patches,
                "Relay saved, Hong Kong grant refused shows pending (or asks to sign in again) without a PATCH: " + mode);
        }
        authorization.Mode = "granted";
        // Simplified rule (user 11-16): a retry never makes Hong Kong more public (12 would reveal bit 8
        // over Hong Kong's 4); only the user's own save does, in that same request.
        var hkBefore = transport.Locations;
        var retried = await Send("gameIdVisibility.retrySync", new { schemaVersion = 1 });
        Check(retried.Response.Error is null && Mirror(retried) == "pending" && transport.Locations == hkBefore,
            "retry does not reveal on Hong Kong");
        var savedAgain = await Request(true, relay.Locations);
        Check(savedAgain.Response.Error is null && Mirror(savedAgain) == "synced" && transport.Locations == relay.Locations,
            "saving again pushes the Relay value to Hong Kong");
        transport.Mode = "lost";
        patches = transport.Patches;
        var lost = await Request(true, 2);
        Check(lost.Response.Error is null && transport.Patches == patches + 1 && transport.Locations == 2 && Mirror(lost) == "synced",
            "lost Hong Kong reply is confirmed by a read, never a second PATCH");
        transport.Mode = "conflict";
        var cas = await Request(true, 4);
        Check(cas.Response.Error is null && relay.Locations == 4 && Mirror(cas) == "pending",
            "Hong Kong CAS conflict keeps the Relay save and reports pending");
        transport.Mode = "invalid-public";
        var invalid = await Request(true, 8);
        Check(invalid.Response.Error is null && Mirror(invalid) == "pending",
            "an invalid Hong Kong response is never read as in step");
        transport.Mode = "down";
        var down = await Request(true, 1);
        Check(down.Response.Error is null && relay.Locations == 1 && Mirror(down) == "pending",
            "Hong Kong outage keeps the Relay save and reports pending");
        transport.Mode = "ok";
        relay.Mode = "conflict";
        Check((await Request(true, 2)).Response.Error?.Code == "gameId.conflict", "stale Relay draft stays a conflict");
        relay.Mode = "ok";
        transport.Mode = "unverified";
        var unverified = await Request(true, 8);
        Check(unverified.Response.Error is null && Mirror(unverified) == "synced",
            "unverified Hong Kong stays hidden, which is the safe state");
        transport.Mode = "ok";
        relay.Mode = "down";
        Check((await Request(false)).Response.Error is not null, "Relay outage has no Hong Kong fallback");
        relay.Mode = "ok";
        await host.LogoutAsync(owner, default);
        var calls = transport.Calls + relay.Reads + relay.Writes;
        Check((await Request(true, 2)).Response.Error is not null && transport.Calls + relay.Reads + relay.Writes == calls,
            "stale owner cannot write");
    }

    private sealed class DisplayOnlyTransport(ScmDisplayRelayFake relay) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Check(ScmDisplayRelayFake.Handles(request), "only display settings reach the Relay here");
            return relay.SendAsync(request, token);
        }
    }

    private sealed class ScmHandlePrivacyTransport : HttpMessageHandler
    {
        internal int Calls, Patches, Locations = 15;
        internal long Revision;
        internal string Mode = "ok";
        internal bool HoldRead;
        internal bool HoldWrite;
        internal TaskCompletionSource ReadEntered = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal TaskCompletionSource ReleaseRead = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal TaskCompletionSource WriteEntered = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal TaskCompletionSource ReleaseWrite = new(TaskCreationOptions.RunContinuationsAsynchronously);
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Calls++;
            if (HoldRead && request.Method == HttpMethod.Get)
            {
                ReadEntered.TrySetResult();
                await ReleaseRead.Task.WaitAsync(token);
            }
            Check(request.RequestUri!.AbsolutePath == "/app-api/starbridge/v1/handle-privacy", "Java-only scoped endpoint");
            if (Mode == "down") return new(HttpStatusCode.ServiceUnavailable);
            if (request.Method == HttpMethod.Patch)
            {
                if (HoldWrite)
                {
                    WriteEntered.TrySetResult();
                    await ReleaseWrite.Task.WaitAsync(token);
                }
                Patches++;
                Check(request.Headers.Authorization?.Parameter == "synthetic-write-token", "one-time write authorization");
                using var body = System.Text.Json.JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
                Check(body.RootElement.EnumerateObject().Count() == 3 && !body.RootElement.TryGetProperty("subject", out _), "no caller-selected identity");
                if (Mode == "conflict") return new(HttpStatusCode.Conflict);
                Check(body.RootElement.GetProperty("expectedRevision").GetInt64() == Revision, "expected version forwarded");
                Locations = body.RootElement.GetProperty("locations").GetInt32(); Revision++;
                if (Mode == "lost") throw new HttpRequestException("synthetic lost response");
            }
            else Check(request.Method == HttpMethod.Get && request.Headers.Authorization?.Parameter == "synthetic-read-token", "read credentials retained");
            return new(HttpStatusCode.OK) { Content = JsonContent.Create(new { schemaVersion = 1, revision = Revision,
                locations = Mode == "unverified" ? 0 : Mode == "invalid-public" ? 15 : Locations,
                canConfigure = Mode is not ("unverified" or "invalid-public"), identityStamp = new string('a', 64) }) };
        }
    }
}
