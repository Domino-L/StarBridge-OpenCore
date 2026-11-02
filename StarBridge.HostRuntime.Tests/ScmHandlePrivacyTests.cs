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
        using var transport = new ScmHandlePrivacyTransport { HoldRead = true };
        var uri = new Uri("http://127.0.0.1:9/");
        var oauth = new OAuthPkceClient(new ScmHttpClient(transport), new ScmVisitorVault(),
            new ScmOAuthOptions("synthetic", uri, uri, uri, "synthetic", "synthetic", "openid profile.read", "/callback"));
        using var host = new ScmAccountBridgeHost(oauth, new ScmProfileCacheStore(), "integration", () => null,
            initialSession: new ScmOAuthSession("synthetic", "owner", "Pilot", "synthetic-read-token",
                DateTimeOffset.UtcNow.AddHours(1), ["profile.read"], GameIdentityVerified: true, GameIdentityHandle: "Pilot"),
            profileAuthorization: new ScmVisibilityAuthorization());
        using var wire = new QueueProbeTransport { HoldDirectory = communityRead };
        host.ConfigurePrivacyWriter(new PrivacyRelayWriter(uri, wire));
        var owner = host.CurrentContext!;
        Task read = communityRead ? host.ReadCommunitySharingTargetsAsync(owner, host.Generation, default) :
            host.ReadGameIdAsync(owner, host.Generation, default);
        await (communityRead ? wire.DirectoryEntered.Task : transport.ReadEntered.Task).WaitAsync(TimeSpan.FromSeconds(2));
        wire.HoldDirectory = false;
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
        var save = host.SaveGameIdAsync(owner, host.Generation, 0, new string('a', 64), 0, default);
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
        internal readonly TaskCompletionSource DirectoryEntered = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource ReleaseDirectory = new(TaskCreationOptions.RunContinuationsAsynchronously);
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
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
        using var transport = new ScmHandlePrivacyTransport();
        var uri = new Uri("http://127.0.0.1:9/");
        var oauth = new OAuthPkceClient(new ScmHttpClient(transport), new ScmVisitorVault(),
            new ScmOAuthOptions("synthetic", uri, uri, uri, "synthetic", "synthetic", "openid profile.read", "/callback"));
        var authorization = new ScmVisibilityAuthorization();
        using var host = new ScmAccountBridgeHost(oauth, new ScmProfileCacheStore(), "integration", () => null,
            initialSession: new ScmOAuthSession("synthetic", "owner", "Pilot", "synthetic-read-token",
                DateTimeOffset.UtcNow.AddHours(1), ["profile.read"]), profileAuthorization: authorization);
        var dispatcher = new GameIdSettingsDispatcher(host, () => (host.GameplayTimeContext, host.Generation));
        var owner = host.CurrentContext!; var generation = host.Generation;
        Task<BridgeDispatchBatch> Request(bool save, long revision = 0, int mask = 4) => dispatcher.DispatchAsync(
            BridgeEnvelope.Request(save ? "gameIdVisibility.save" : "gameIdVisibility.read", "handle-privacy", generation,
                save ? (object)new { schemaVersion = 1, expectedRevision = revision, identityStamp = new string('a', 64), locations = mask }
                    : new { schemaVersion = 1 }, owner), default);
        var read = await Request(false);
        Check(read.Response.Error is null && read.Response.Payload.GetProperty("locations").GetInt32() == 0,
            "SCM defaults hidden through Java without any legacy adapter");
        var saved = await Request(true);
        Check(saved.Response.Error is null && saved.Response.Payload.GetProperty("revision").GetInt64() == 1,
            "SCM privacy save uses authorized dedicated Java PATCH");
        await Request(false); // Transport checks that write grant did not replace read credentials.
        foreach (var mode in new[] { "denied", "wrong-subject", "missing-scope" })
        {
            authorization.Mode = mode;
            int before = transport.Calls;
            Check((await Request(true, 1)).Response.Error is not null && before == transport.Calls,
                "invalid grant cannot contact privacy endpoint: " + mode);
        }
        authorization.Mode = "granted";
        transport.Mode = "lost";
        int patches = transport.Patches;
        saved = await Request(true, 1, 0);
        Check(saved.Response.Error is null && transport.Patches == patches + 1 &&
            saved.Response.Payload.GetProperty("locations").GetInt32() == 0, "lost reply confirmed by GET without replay");
        transport.Mode = "conflict";
        Check((await Request(true, 2)).Response.Error?.Code == "gameId.conflict", "CAS conflict stays conflict");
        transport.Mode = "unverified";
        read = await Request(false);
        Check(read.Response.Error is null && !read.Response.Payload.GetProperty("canConfigure").GetBoolean() &&
            read.Response.Payload.GetProperty("locations").GetInt32() == 0, "unverified SCM is hidden, not legacy public");
        transport.Mode = "invalid-public";
        Check((await Request(false)).Response.Error is not null, "unverified public response rejected");
        transport.Mode = "down";
        var count = transport.Calls;
        Check((await Request(false)).Response.Error is not null && transport.Calls == count + 1, "outage has no legacy fallback");
        transport.Mode = "ok";
        await host.LogoutAsync(owner, default);
        count = transport.Calls;
        Check((await Request(true, 2)).Response.Error is not null && transport.Calls == count, "stale owner cannot write");
    }

    private sealed class ScmHandlePrivacyTransport : HttpMessageHandler
    {
        internal int Calls, Patches, Locations;
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
