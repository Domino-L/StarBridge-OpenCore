using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

internal static partial class LegacyPasswordLoginTests
{
    internal static async Task EntitlementLifecycle()
    {
        using var transport = new Transport { Body = Transport.Valid.TrimEnd('}') + ",\"entitlements\":[\"test-grant\"]}" };
        using var client = new LegacyPasswordLoginClient(new Uri("https://example.invalid/"), new Store(), transport);
        using var host = CreateHost(client);
        await host.LoginLegacyAsync(BridgePayload.From(new { schemaVersion = 1, email = "old@example.invalid", password = "short" }), 0, default);
        Check(host.CurrentOverlayEntitlements.SequenceEqual(new[] { "test-grant" }), "login publishes authoritative legacy grants");
        transport.Body = Transport.Valid.TrimEnd('}') + ",\"entitlements\":[\"redeemed-grant\"]}";
        var result = await host.RedeemLegacyEntitlementsAsync(host.CurrentContext!, "test-code", default);
        Check(result.Outcome == "redeemed" && host.CurrentOverlayEntitlements.SequenceEqual(new[] { "redeemed-grant" }), "redeem replaces grants");
        using var dispatcher = new AccountBridgeDispatcher(host);
        var response = await dispatcher.DispatchAsync(BridgeEnvelope.Request("account.redeemLegacyEntitlements", "redeem-test", host.Generation,
            new { schemaVersion = 1, code = "test-code" }, host.CurrentContext));
        Check(response.Response.Payload.GetProperty("outcome").GetString() == "redeemed" && response.Response.Payload.EnumerateObject().Count() == 2,
            "Bridge returns only schema and outcome, no credentials or raw grants");
        await host.LogoutAsync(host.CurrentContext!, default);
        Check(host.CurrentOverlayEntitlements.Count == 0, "logout clears grants");
        using var scm = CreateHost(client, new ScmOAuthSession("scm", "subject", "test", "token", DateTimeOffset.UtcNow.AddMinutes(10), []));
        var calls = transport.Calls;
        Check((await scm.RedeemLegacyEntitlementsAsync(scm.CurrentContext!, "test-code", default)).Outcome == "unsupported" && transport.Calls == calls,
            "SCM cannot send legacy redemption");
    }
    internal static async Task GameplayResetTransport()
    {
        var transport = new Transport();
        using var client = new LegacyPasswordLoginClient(new Uri("https://example.invalid/"), new Store(), transport);
        using var host = CreateHost(client);
        await host.LoginLegacyAsync(BridgePayload.From(new { schemaVersion = 1, email = "old@example.invalid", password = "synthetic" }), 0, default);
        var context = host.CurrentContext!;
        var state = new StarBridge.Core.Profiles.GameplayTimeResetState(1, 3, null, null, 400, 0, null,
            ObservedAt: DateTimeOffset.UtcNow);
        transport.Body = JsonSerializer.Serialize(state, new JsonSerializerOptions(JsonSerializerDefaults.Web));
        Check((await host.ReadAsync(context, default)).Revision == 3 && transport.Authorized, "uses existing legacy bearer");
        var request = new StarBridge.Core.Profiles.GameplayTimeResetRequest(1, 3, Guid.NewGuid().ToString("N"));
        var receipt = state with { Revision = 4, LastOperationId = request.OperationId, LastExpectedRevision = 3, PlayTimeSeconds = 0 };
        transport.Body = JsonSerializer.Serialize(new StarBridge.Core.Profiles.GameplayTimeResetResult("completed", receipt), new JsonSerializerOptions(JsonSerializerDefaults.Web));
        Check((await host.ResetAsync(context, request, default)).Outcome == "completed", "matched reset receipt accepted");
        foreach (var status in new[] { HttpStatusCode.Unauthorized, HttpStatusCode.NotFound, HttpStatusCode.ServiceUnavailable })
        {
            transport.Status = status;
            var before = transport.Calls;
            try { await host.ResetAsync(context, request, default); throw new Exception("Expected transport failure"); }
            catch (HttpRequestException) { }
            Check(transport.Calls == before + 1, "failed write is never retried");
        }
        transport.Status = HttpStatusCode.OK;
        foreach (var body in new[] { "{\"schemaVersion\":1}", "{\"schemaVersion\":1,\"schemaVersion\":1}", new string('x', 8193) })
        {
            transport.Body = body;
            var failed = false;
            try { await host.ReadAsync(context, default); }
            catch (Exception e) when (e is JsonException or InvalidOperationException or ArgumentException) { failed = true; }
            Check(failed, "invalid or excessive response is rejected");
        }
        var calls = transport.Calls;
        using var scm = CreateHost(client, new ScmOAuthSession("scm-development", "synthetic", "Synthetic",
            "synthetic-bearer", DateTimeOffset.UtcNow.AddMinutes(5), []));
        transport.Body = JsonSerializer.Serialize(state, new JsonSerializerOptions(JsonSerializerDefaults.Web));
        Check((await scm.ReadAsync(scm.CurrentContext!, default)).Revision == 3 && transport.Bearer == "synthetic-bearer",
            "SCM uses its own bearer for the WPF S2 statistics domain");
        Check(transport.Calls == calls + 1, "SCM performs one Relay request without credential exchange");
        calls = transport.Calls;
        try { await scm.ReadAsync(context, default); throw new Exception("Wrong owner must fail"); }
        catch (StarBridge.HostRuntime.Presence.GameplayTimeException) { }
        Check(transport.Calls == calls, "wrong owner rejected before transport");
        var update = new StarBridge.Core.Profiles.PersonalProfileGameplayStatisticsUpdateRequestContract(
            false, 600, 0, 0, ExpectedGameplayRevision: 4, ResetOperationId: request.OperationId);
        transport.Body = JsonSerializer.Serialize(new {
            schemaVersion = 1, isGameplayStatisticsPublic = false,
            gameplayStatistics = new { playTimeSeconds = 600, downedCount = 0, deathCount = 0,
                historicalPlayTimeSeconds = 0, historicalSessionCount = 0,
                historicalIncompleteSessionCount = 0, historyImportedAt = (DateTimeOffset?)null }
        });
        Check(await host.PublishGameplayStatisticsAsync(context, update, default), "legacy upload acknowledges exact snapshot");
        Check(transport.Upload?.ExpectedGameplayRevision == 4 && transport.Upload.ResetOperationId == request.OperationId,
            "upload carries revision and reset epoch receipt");
        Check(await scm.PublishGameplayStatisticsAsync(scm.CurrentContext!, update, default) && transport.Bearer == "synthetic-bearer",
            "SCM upload uses its existing Relay bearer");
        calls = transport.Calls;
        try { await host.PublishGameplayStatisticsAsync(context, update with { ExpectedGameplayRevision = null }, default); throw new Exception("Expected rejection"); }
        catch (ArgumentException) { }
        Check(transport.Calls == calls, "unversioned Flutter upload never reaches transport");
        transport.Status = HttpStatusCode.Conflict;
        Check(!await host.PublishGameplayStatisticsAsync(context, update, default) && transport.Calls == calls + 1,
            "conflict does not replay snapshot");
        foreach (var status in new[] { HttpStatusCode.Unauthorized, HttpStatusCode.ServiceUnavailable })
        {
            transport.Status = status;
            calls = transport.Calls;
            try { await host.PublishGameplayStatisticsAsync(context, update, default); throw new Exception("Expected failure"); }
            catch (HttpRequestException) { }
            Check(transport.Calls == calls + 1, "failed upload does not refresh and replay");
        }
        transport.Status = HttpStatusCode.OK;
        transport.Body = transport.Body.Replace("\"playTimeSeconds\":600", "\"playTimeSeconds\":0");
        try { await host.PublishGameplayStatisticsAsync(context, update, default); throw new Exception("Expected mismatched acknowledgement"); }
        catch (JsonException) { }
        Console.WriteLine("PASS gameplay reset S2 transport, response bounds, no replay and SCM/legacy owner boundary");
    }
    internal static async Task Verify()
    {
        var transport = new Transport();
        var store = new Store();
        using var client = new LegacyPasswordLoginClient(new Uri("http://127.0.0.1:5058/"), store, transport);
        using var host = CreateHost(client);
        using var runtime = new AccountBridgeRuntime(host);
        var fields = BridgePayload.From(new { schemaVersion = 1, email = " old@example.invalid ", password = " short " });
        var request = BridgeEnvelope.Request("account.loginLegacy", "legacy-login", 0, fields);
        var response = await runtime.DispatchAsync(request);
        Check(Outcome(response) == "verified", "legacy credentials verified");
        foreach (var name in new[] { "recentlyPlayed.privacyRead", "recentlyPlayed.privacyWrite" })
        {
            var privacyRequest = BridgeEnvelope.Request(name, "recent-privacy-route", host.Generation,
                BridgePayload.From(new { schemaVersion = 1 })) with { AccountContext = host.CurrentContext };
            var privacyResponse = await runtime.DispatchAsync(privacyRequest);
            Check(privacyResponse.Response.Error?.Code != BridgeErrorCodes.CapabilityUnavailable,
                "Recently played privacy must reach the account dispatcher, including validated writes");
        }
        Check((await host.GetCurrentAsync(default)).State == "legacySignedIn", "WPF parity: successful legacy login establishes a visible legacy session");
        Check(host.SupportsConcurrentReads, "restored legacy session enables the audited independent read lane");
        Check((await host.GetCurrentAsync(default)).DisplayName == "Old Commander", "legacy header uses the WPF callsign");
        Check((await host.GetCurrentAsync(default)).MaskedAccount == "o****@example.invalid", "legacy account label follows S2 masking");
        Check(AccountDisplayLabel.Mask("commander@example.invalid") == "comm****@example.invalid", "long email local part is masked");
        Check(AccountDisplayLabel.Mask(null) is null, "missing account label stays unknown");
        Check(transport.Calls == 1 && transport.Path == "/api/auth/login" && !transport.Authorized, "WPF anonymous login only");
        Check(transport.Email == "old@example.invalid" && transport.Password == " short ", "existing short passwords allowed and not trimmed");
        Check(store.Saves == 1 && store.Value!.AccountId == "legacy-synthetic" && store.Value.AuthToken == "synthetic-token", "reuses protected-store contract");
        Check(host.CurrentContext?.Authority.StartsWith("starbridge-relay-") == true && host.HangarIdentity?.Identity.Status == StarBridge.Core.Identity.ScmGameIdentityStatus.Unknown && host.Generation == 1 && response.Events.Count == 1, "legacy identity is separate from SCM and does not fabricate verified game identity");
        request = request with { SessionGeneration = host.Generation };
        Check(response.Response.Payload.EnumerateObject().Select(p => p.Name).Order().SequenceEqual(new[] { "outcome", "retryAfterSeconds", "schemaVersion" }), "no token, email or private account data projected");
        var stored = store.Value;
        transport.Status = HttpStatusCode.Unauthorized;
        Check(Outcome(await runtime.DispatchAsync(request)) == "rejected" && ReferenceEquals(store.Value, stored), "password failure preserves existing credential");
        transport.Status = HttpStatusCode.TooManyRequests;
        var limited = await runtime.DispatchAsync(request);
        Check(Outcome(limited) == "throttled" && limited.Response.Payload.GetProperty("retryAfterSeconds").GetInt32() == 95, "WPF Retry-After preserved");
        transport.Status = HttpStatusCode.OK;
        foreach (var body in new[] { "{}", "[]", "{\"token\":\"private\",\"accountId\":null}", "<private failure>", new string('x', 2 * 1024 * 1024 + 1) })
        {
            transport.Body = body;
            Check(Outcome(await runtime.DispatchAsync(request)) == "unavailable" && store.Saves == 1, "unconfirmed result does not replace saved credentials");
        }
        transport.Body = Transport.Valid;
        store.Fail = true;
        Check(Outcome(await runtime.DispatchAsync(request)) == "storageUnavailable" && store.Value == stored, "cannot claim saved when protected persistence fails");
        store.Fail = false;
        var calls = transport.Calls;
        Check((await runtime.DispatchAsync(request with { SessionGeneration = 9 })).Response.Status == BridgeResponseStatuses.Error && transport.Calls == calls, "stale login rejected before HTTP");
        Check((await runtime.DispatchAsync(request with { AccountContext = new("test", "synthetic", "subject") })).Response.Status == BridgeResponseStatuses.Error && transport.Calls == calls, "SCM contextual login rejected");
        using var duplicate = JsonDocument.Parse("{\"schemaVersion\":1,\"email\":\"old@example.invalid\",\"password\":\"one\",\"password\":\"two\"}");
        Check((await runtime.DispatchAsync(request with { Payload = duplicate.RootElement })).Response.Status == BridgeResponseStatuses.Error && transport.Calls == calls, "ambiguous payload rejected");
        var blank = request with { Payload = BridgePayload.From(new { schemaVersion = 1, email = "", password = "secret" }) };
        Check(Outcome(await runtime.DispatchAsync(blank)) == "invalidInput" && transport.Calls == calls, "invalid input cannot hit server");

        transport.Pending = true;
        using var cancellation = new CancellationTokenSource();
        var pending = runtime.DispatchAsync(request, cancellation.Token);
        await transport.Started.Task;
        cancellation.Cancel();
        Check((await pending).Response.Status == BridgeResponseStatuses.Cancelled && store.Saves == 1, "cancel prevents persistence even when server ignores cancellation");
        transport.Pending = false;
        Check(Outcome(await runtime.DispatchAsync(request)) == "verified" && store.Saves == 2, "explicit retry after cancel works");
        var legacyContext = host.CurrentContext!;
        try { await host.GetProfileAsync(legacyContext, default); throw new Exception("Legacy identity granted SCM profile access"); }
        catch (AccountBridgeHostException) { }
        await host.LogoutAsync(legacyContext, default);
        Check(host.CurrentContext is null && (await host.GetCurrentAsync(default)).State == "signedOut", "legacy logout removes visible session");
        Check(!host.SupportsConcurrentReads, "logout disables the independent read lane before another restore");

        // A live SCM account must use the separate explicit-link flow, never be silently replaced.
        using var signedIn = CreateHost(client, new ScmOAuthSession("scm-development", "synthetic", "Synthetic",
            "synthetic-bearer", DateTimeOffset.UtcNow.AddMinutes(5), []));
        Check(((LegacyPasswordLoginResult)await signedIn.LoginLegacyAsync(fields, 0, default)).Outcome == "sessionChanged", "signed-in SCM is not overwritten");

        using var closingTransport = new Transport { Pending = true };
        var closingStore = new Store();
        using var closingClient = new LegacyPasswordLoginClient(new Uri("https://example.invalid/"), closingStore, closingTransport);
        var closingHost = CreateHost(closingClient);
        var late = closingHost.LoginLegacyAsync(fields, 0, default);
        await closingTransport.Started.Task;
        closingHost.Dispose();
        try { await late; throw new Exception("Late close accepted"); } catch (OperationCanceledException) { }
        Check(closingStore.Saves == 0, "Host close cannot save late successful response");
        try { using var unsafeClient = new LegacyPasswordLoginClient(new Uri("http://example.invalid/"), store); throw new Exception("unsafe login endpoint"); }
        catch (ArgumentException) { }
        await VerifyRestoration();
        await VerifyRelayReads();
        await VerifyPlayerActivity();
        await VerifyCommunityReads();
        await VerifyLegacyIdentity();
        await VerifyLegacyPersonalProfile();
    }

    private static async Task VerifyLegacyPersonalProfile()
    {
        using var transport = new Transport();
        using var client = new LegacyPasswordLoginClient(new Uri("https://example.invalid/"), new Store(), transport);
        using var host = CreateHost(client);
        await host.LoginLegacyAsync(BridgePayload.From(new { schemaVersion = 1, email = "old@example.invalid", password = "short" }), 0, default);
        var owner = host.CurrentContext!;
        var document = new StarBridge.Core.Profiles.PersonalProfileDocumentContract(
            3, owner.Subject, true, 7, DateTimeOffset.UtcNow,
            new("Commander", "Commander_One"),
            StarBridge.Core.Profiles.PersonalProfileContentContract.Empty with { Introduction = "Existing profile" },
            new("Fleet", "TEST", null, "Member", "blue"), new([]), new(3600, 0, 0, DateTimeOffset.UtcNow));
        transport.Body = JsonSerializer.Serialize(document, new JsonSerializerOptions(JsonSerializerDefaults.Web));
        var profile = await host.GetPersonalProfileAsync(owner, default);
        Check(profile.Revision == 7 && profile.Content.Introduction == "Existing profile" && profile.GameplayStatistics?.PlayTimeSeconds == 3600,
            "S2 reads existing Relay profile and statistics without SCM");
        Check(transport.Path == "/api/profile/me" && transport.Authorized && transport.DirectoryReads == 1,
            "only authenticated own-profile and existing directory GETs are used");
        Check(profile.FleetAffiliation?.Kind == "community" && profile.FleetAffiliation.LogoImageData is not null,
            "S2 affiliation uses matching organization logo");
        transport.Body = JsonSerializer.Serialize(document with { PublicId = "another-owner" }, new JsonSerializerOptions(JsonSerializerDefaults.Web));
        try { await host.GetPersonalProfileAsync(owner, default); throw new Exception("Cross-owner profile accepted"); }
        catch (AccountBridgeHostException) { }
        transport.Status = HttpStatusCode.Gone;
        try { await host.GetPersonalProfileAsync(owner, default); throw new Exception("Retired route accepted"); }
        catch (AccountBridgeHostException) { }
        Check(host.CurrentContext == owner, "profile outage does not log out the legacy account");
        transport.Status = HttpStatusCode.OK;
        transport.Body = JsonSerializer.Serialize(document, new JsonSerializerOptions(JsonSerializerDefaults.Web));
        transport.Pending = true;
        using var cancelled = new CancellationTokenSource();
        var pending = host.GetPersonalProfileAsync(owner, cancelled.Token);
        await transport.Started.Task;
        cancelled.Cancel();
        try { await pending; throw new Exception("Cancelled profile accepted"); }
        catch (OperationCanceledException) { }
        var calls = transport.Calls;
        await host.LogoutAsync(owner, default);
        try { await host.GetPersonalProfileAsync(owner, default); throw new Exception("Signed-out profile accepted"); }
        catch (AccountBridgeHostException) { }
        Check(transport.Calls == calls, "signed-out read cannot contact Relay");
    }

    private static async Task VerifyLegacyIdentity()
    {
        var bytes = new byte[300_000];
        Convert.FromBase64String("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=").CopyTo(bytes, 0);
        var avatar = Convert.ToBase64String(bytes);
        Check(StarBridge.HostRuntime.PartyRooms.RoomAvatarProjection.Normalize(avatar) is null,
            "account avatar compatibility must not enlarge the room-list media budget");
        Check(StarBridge.HostRuntime.PartyRooms.RoomAvatarProjection.Normalize(Convert.ToBase64String(new byte[512 * 1024 + 1]), 512 * 1024) is null,
            "account avatar remains bounded by WPF size policy");
        using var transport = new Transport { Body = Transport.Valid.TrimEnd('}') +
            ",\"gameName\":\"Commander_One\",\"identityBindingRequired\":false,\"identityBindingConfirmedAt\":\"2026-09-10T00:00:00Z\",\"avatarImageData\":\"" + avatar + "\"}" };
        using var client = new LegacyPasswordLoginClient(new Uri("https://example.invalid/"), new Store(), transport);
        using var host = CreateHost(client);
        await host.LoginLegacyAsync(BridgePayload.From(new { schemaVersion = 1, email = "old@example.invalid", password = "short" }), 0, default);
        Check(host.HangarIdentity?.Identity.CanonicalHandle == "commander_one", "legacy confirmed RSI identity comes from Relay AuthResponse");
        Check((await host.GetCurrentAsync(default)).AvatarImageData == "data:image/png;base64," + avatar,
            "legacy custom avatar bytes survive login projection without a preset substitution");
        var policy = await host.GetGameIdentityPolicyAsync(host.CurrentContext!, default);
        Check(policy.State == "awaitingGameIdentity", "bound legacy handle without local game observation cannot grant sensitive network writes");
        await host.LogoutAsync(host.CurrentContext!, default);
        Check((await host.GetCurrentAsync(default)).AvatarImageData is null, "logout clears the prior account photo");
    }

    private static async Task VerifyRelayReads()
    {
        using var login = new LegacyPasswordLoginClient(new Uri("https://example.invalid/"), new Store(), new Transport());
        using var relay = new Transport { Body = "{\"refreshedAt\":\"2026-09-10T00:00:00Z\",\"friends\":[],\"incomingRequests\":[],\"outgoingRequests\":[],\"blockedUsers\":[]}" };
        using var friends = new StarBridge.HostRuntime.Friends.FriendsReader(new Uri("https://example.invalid/"), relay);
        using var host = CreateHost(login, friends: friends);
        await host.LoginLegacyAsync(BridgePayload.From(new { schemaVersion = 1, email = "old@example.invalid", password = "short" }), 0, default);
        var view = await host.ReadFriendsAsync(host.CurrentContext!, BridgePayload.From(new { schemaVersion = 1 }), default);
        Check(view.Friends.Length == 0 && relay.Calls == 1 && relay.Authorized, "WPF S2: old account reads Relay friends without an SCM session");
        Check(host.GameplayTimeContext == host.CurrentContext && host.HangarIdentity?.Account == host.CurrentContext,
            "local profile, privacy and hangar share the authenticated legacy owner without SCM");
        try { await host.ReadFriendsAsync(host.CurrentContext! with { Subject = "other" }, BridgePayload.From(new { schemaVersion = 1 }), default); throw new Exception("wrong owner allowed"); }
        catch (AccountBridgeHostException) { }
        Check(relay.Calls == 1, "cross-account read rejected before Relay");
        relay.Status = HttpStatusCode.Forbidden;
        try { await host.ReadFriendsAsync(host.CurrentContext!, BridgePayload.From(new { schemaVersion = 1 }), default); throw new Exception("Relay refusal ignored"); }
        catch (AccountBridgeHostException e) { Check(e.Code == "friends.forbidden", "Relay remains permission authority"); }
        Check(relay.Calls == 2 && (await host.GetCurrentAsync(default)).State == "legacySignedIn", "no SCM fallback or replay after Relay refusal");
    }

    internal static async Task VerifyPlayerActivity()
    {
        using var login = new LegacyPasswordLoginClient(new Uri("https://example.invalid/"), new Store(), new Transport());
        using var relay = new ActivityTransport();
        using var friends = new StarBridge.HostRuntime.Friends.FriendsReader(new Uri("https://example.invalid/"), relay);
        using var host = CreateHost(login, friends: friends);
        await host.LoginLegacyAsync(BridgePayload.From(new { schemaVersion = 1, email = "old@example.invalid", password = "short" }), 0, default);
        var context = host.CurrentContext!;
        var observations = new List<StarBridge.HostRuntime.Notifications.PlayerActivityObservation>();
        host.PlayerActivityObserved = observations.Add;
        host.ShouldObservePlayerActivity = () => true;
        var request = BridgePayload.From(new { schemaVersion = 1 });
        var old = host.ReadFriendsAsync(context, request, default);
        await relay.Started.Task;
        await host.ReadFriendsAsync(context, request, default);
        Check(observations.Count == 1 && observations[0].Members.Single().Presence == "inGame", "newest real read reaches enabled observer");
        relay.Old.TrySetResult();
        await old;
        Check(observations.Count == 1, "late old complete read cannot reverse newer activity state");
        var current = observations.Single();
        Check(current.IsCurrent() && current.IsComplete && current.Members.Single().MemberKey.Length == 64 &&
            !current.Members.Single().MemberKey.Contains("private-account"), "observation exposes only scoped opaque identities");
        await host.ReadFriendsAsync(context, request, default);
        Check(!current.IsCurrent() && observations.Count == 2 && observations[^1].IsCurrent(),
            "a newer complete source invalidates queued delivery from the previous membership snapshot");
        current = observations[^1];
        host.ShouldObservePlayerActivity = () => false;
        await host.ReadFriendsAsync(context, request, default);
        Check(!relay.LastIncludedPresence && observations.Count == 2 && !current.IsCurrent(), "disabled activity stops presence collection and invalidates prior delivery");
        host.ShouldObservePlayerActivity = () => true;
        await host.LogoutAsync(context, default);
        Check(!current.IsCurrent(), "logout invalidates outstanding activity delivery");
    }

    private sealed class ActivityTransport : HttpMessageHandler
    {
        internal readonly TaskCompletionSource Started = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource Old = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal int Calls;
        internal bool LastIncludedPresence;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            var number = Interlocked.Increment(ref Calls);
            LastIncludedPresence = request.RequestUri!.Query == "?includePresence=true";
            if (number == 1) { Started.TrySetResult(); await Old.Task; }
            var user = new { accountId = "private-account", callsign = "Pilot", gameId = "", relationshipState = "friend",
                avatarImageData = (string?)null, presence = number == 1 ? "Offline" : "InGame", lastUpdated = DateTimeOffset.UtcNow };
            return new(HttpStatusCode.OK) { Content = new ByteArrayContent(FriendsReaderTests.Directory(user)) };
        }
    }

    private static async Task VerifyCommunityReads()
    {
        using var loginTransport = new Transport
        {
            Body = Transport.Valid.TrimEnd('}') +
                ",\"gameName\":\"Commander_One\",\"identityBindingRequired\":false,\"identityBindingConfirmedAt\":\"2026-09-10T00:00:00Z\"}"
        };
        using var login = new LegacyPasswordLoginClient(new Uri("https://example.invalid/"), new Store(), loginTransport);
        using var relay = new CommunityTransport();
        using var friends = new StarBridge.HostRuntime.Friends.FriendsReader(new Uri("https://example.invalid/"), relay);
        var invitationRoot = Directory.CreateTempSubdirectory("starbridge-legacy-host-invitation-").FullName;
        using var communities = new StarBridge.HostRuntime.Communities.CommunityClient(new Uri("https://example.invalid/"), relay,
            invitationJournal: new StarBridge.HostRuntime.Communities.InvitationOutboxJournal(invitationRoot));
        using var host = CreateHost(login, friends: friends, communities: communities);
        await host.LoginLegacyAsync(BridgePayload.From(new { schemaVersion = 1, email = "old@example.invalid", password = "short" }), 0, default);
        var owner = host.CurrentContext!;
        var query = BridgePayload.From(new { schemaVersion = 1, view = "mine", query = "" });
        var view = (StarBridge.HostRuntime.Communities.CommunityPage)await host.ReadCommunitiesAsync(owner, query, default);
        Check(view.Items.Length == 1 && relay.Calls == 2, "S2 Host selects WPF membership reads without probing SCM or new directory");
        var workspace = JsonSerializer.SerializeToElement(await host.ReadCommunityWorkspaceAsync(owner,
            BridgePayload.From(new { schemaVersion = 1, targetRef = view.Items[0].TargetRef, query = "", offset = 0 }), default));
        Check(workspace.GetProperty("members").GetArrayLength() == 0 && relay.Calls == 4, "S2 Host carries the old target through workspace routing");
        var discovery = (StarBridge.HostRuntime.Communities.CommunityPage)await host.ReadCommunitiesAsync(owner,
            BridgePayload.From(new { schemaVersion = 1, view = "discover", query = "", filters = "{\"sort\":\"name\"}" }), default);
        Check(discovery.Items.Length == 1 && relay.Calls == 7, "Host routes S2 discovery and filters through old sources");
        var invite = (StarBridge.HostRuntime.Communities.CommunityInviteView)await host.PreviewCommunityInviteAsync(owner,
            BridgePayload.From(new { schemaVersion = 1, inviteCode = "FIXTURE-INVITE" }), default);
        Check(invite.MembershipConflict && !invite.AlreadyMember && relay.Calls == 10, "Real S2 account dispatch selects existing membership for invitation preview");
        var admission = (StarBridge.HostRuntime.Communities.CommunityCommand)await host.AcceptCommunityInviteAsync(owner,
            BridgePayload.From(new { schemaVersion = 1, requestId = Guid.NewGuid().ToString("N"), previewRef = invite.PreviewRef }), default);
        Check(admission.Error == "membershipConflict" && relay.Calls == 12, "S2 account dispatch cannot replace its existing membership");
        relay.LeaveEnabled = true;
        var leaveView = (StarBridge.HostRuntime.Communities.CommunityPage)await host.ReadCommunitiesAsync(owner, query, default);
        Check(leaveView.Items.Single().Actions.SequenceEqual(new[] { "leave" }), "S2 Host exposes ordinary exit using authenticated ownership");
        var leaving = (StarBridge.HostRuntime.Communities.CommunityCommand)await host.ExecuteCommunityAsync(owner,
            BridgePayload.From(new { schemaVersion = 1, action = "leave", targetRef = leaveView.Items[0].TargetRef }), default);
        Check(leaving.Status == "accepted" && relay.LeaveWrites == 1, "Existing account dispatcher routes confirmed ordinary exit without SCM");
        var creation = (StarBridge.HostRuntime.Communities.CommunityCreationResult)await host.CreateCommunityAsync(owner,
            BridgePayload.From(new
            {
                schemaVersion = 1,
                requestId = Guid.NewGuid().ToString("N"),
                draft = new
                {
                    schemaVersion = 1,
                    name = "New Organization",
                    code = "NEWORG",
                    description = "",
                    joinPolicy = "Open",
                    tagIds = new[] { "combat_pvp" },
                    activeSystemIds = new[] { "stanton" },
                    activeFrom = "19:00",
                    activeTo = "22:00",
                    timeZoneId = "UTC"
                }
            }), default);
        Check(creation.Status == "accepted" && creation.Organization?.Relationship == "owner" && relay.CreateWrites == 1,
            "Legacy account dispatcher selects the WPF snapshot create adapter and confirms ownership");
        var profile = JsonSerializer.SerializeToElement(await host.ReadCommunityProfileAsync(owner,
            BridgePayload.From(new { schemaVersion = 1, targetRef = creation.Organization!.TargetRef }), default));
        var profileSave = (StarBridge.HostRuntime.Communities.CommunityProfileSaveResult)await host.SaveCommunityProfileAsync(owner,
            BridgePayload.From(new
            {
                schemaVersion = 1,
                requestId = Guid.NewGuid().ToString("N"),
                editRef = profile.GetProperty("editRef").GetString(),
                changes = new { description = "Updated organization" }
            }), default);
        Check(profileSave.Status == "accepted" && profileSave.ProfileRevision == 2 && relay.ProfileWrites == 1,
            "Legacy account dispatcher selects the original WPF profile update adapter");
        var conversations = (StarBridge.HostRuntime.Friends.ConversationsView)await host.ReadDirectMessagesAsync(owner,
            BridgePayload.From(new { schemaVersion = 1 }), default);
        var invitationPreview = (StarBridge.HostRuntime.Communities.InvitationTargetPreview)await host.PreviewCommunityInviteSendAsync(owner,
            BridgePayload.From(new
            {
                schemaVersion = 1,
                organizationRef = creation.Organization!.TargetRef,
                channel = "private",
                destinationRef = conversations.Conversations.Single().TargetRef
            }), default);
        Check(invitationPreview.CanSend && invitationPreview.EligibleRecipients == 1,
            "Legacy account dispatcher previews invitations from the WPF roster and policy");
        var invitation = (StarBridge.HostRuntime.Communities.InvitationSendProgress)await host.SendCommunityInviteAsync(owner,
            BridgePayload.From(new
            {
                schemaVersion = 1,
                operationId = Guid.NewGuid().ToString("N"),
                organizationRef = creation.Organization.TargetRef,
                channel = "private",
                destinationRef = conversations.Conversations.Single().TargetRef,
                maxUses = 1,
                action = "advance"
            }), default);
        Check(invitation.Status == "sent" && relay.InviteWrites == 1 && relay.InvitationMessageWrites == 1 && relay.OriginalInviteWireShape,
            "Legacy account dispatcher selects original WPF invite generation and direct-message routes");
        var callsBeforeLogout = relay.Calls;
        await host.LogoutAsync(owner, default);
        try { await host.ReadCommunitiesAsync(owner, query, default); throw new Exception("signed-out organization read allowed"); }
        catch (AccountBridgeHostException) { }
        Check(relay.Calls == callsBeforeLogout, "logout rejects organization read before transport");
    }

    private sealed class CommunityTransport : HttpMessageHandler
    {
        internal int Calls;
        internal int LeaveWrites;
        internal int CreateWrites;
        internal int InviteWrites;
        internal int InvitationMessageWrites;
        internal int ProfileWrites;
        internal bool LeaveEnabled;
        internal bool Created;
        internal bool InviteCreated;
        internal bool OriginalInviteWireShape = true;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Calls++;
            Check((request.Method == HttpMethod.Get || request.Method == HttpMethod.Post &&
                (request.RequestUri!.AbsolutePath == "/api/fleets/invites/preview" ||
                 LeaveEnabled && request.RequestUri!.AbsolutePath == "/api/fleets/leave" ||
                 LeaveEnabled && request.RequestUri!.AbsolutePath == "/api/fleets" ||
                 request.RequestUri!.AbsolutePath == "/api/fleets/invites" ||
                 request.RequestUri!.AbsolutePath == "/api/fleets/info" ||
                 request.RequestUri!.AbsolutePath == "/api/friends/chat/messages")) &&
                request.Headers.Authorization?.Parameter == "synthetic-token", "S2 supplied legacy credential and only scoped test routes");
            if (request.RequestUri!.AbsolutePath == "/api/fleets/leave") LeaveWrites++;
            if (request.Method == HttpMethod.Post && request.RequestUri.AbsolutePath == "/api/fleets")
            {
                CreateWrites++;
                using var posted = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
                Check(posted.RootElement.GetProperty("code").GetString() == "NEWORG" &&
                      posted.RootElement.GetProperty("commander").GetString() == "Old Commander (Commander_One)",
                    "Legacy Host projects the verified WPF identity into the original snapshot");
                Created = true;
                return new HttpResponseMessage(HttpStatusCode.OK)
                {
                    Content = new StringContent(CreatedFleet)
                };
            }
            if (request.Method == HttpMethod.Post && request.RequestUri.AbsolutePath == "/api/fleets/invites")
            {
                InviteWrites++;
                using var posted = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
                OriginalInviteWireShape &= request.RequestUri.Query.Length == 0 &&
                    !posted.RootElement.TryGetProperty("clientRequestId", out _) &&
                    !posted.RootElement.TryGetProperty("clientRequestedAt", out _);
                InviteCreated = true;
                return new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(CreatedFleetWithInvite()) };
            }
            if (request.Method == HttpMethod.Post && request.RequestUri.AbsolutePath == "/api/fleets/info")
            {
                ProfileWrites++;
                using var posted = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
                Check(request.RequestUri.Query.Length == 0 &&
                      posted.RootElement.GetProperty("fleetCode").GetString() == "NEWORG" &&
                      posted.RootElement.GetProperty("expectedProfileRevision").GetInt64() == 1,
                    "Legacy Host keeps the original WPF profile update contract");
                return new HttpResponseMessage(HttpStatusCode.OK)
                {
                    Content = new StringContent(CreatedFleet
                        .Replace("\"description\":\"\"", "\"description\":\"Updated organization\"", StringComparison.Ordinal)
                        .Replace("\"profileRevision\":1", "\"profileRevision\":2", StringComparison.Ordinal))
                };
            }
            if (request.Method == HttpMethod.Post && request.RequestUri.AbsolutePath == "/api/friends/chat/messages")
            {
                InvitationMessageWrites++;
                using var posted = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
                OriginalInviteWireShape &= request.RequestUri.Query.Length == 0 &&
                    !posted.RootElement.TryGetProperty("clientRequestedAt", out _) &&
                    !posted.RootElement.TryGetProperty("confirmOnly", out _);
                var requestId = posted.RootElement.GetProperty("clientMessageId").GetString();
                var attachment = posted.RootElement.GetProperty("attachment").Clone();
                return new HttpResponseMessage(HttpStatusCode.OK)
                {
                    Content = JsonContent.Create(new { message = new { messageId = requestId, sequence = 1,
                        createdAt = DateTimeOffset.UtcNow, senderAccountId = "legacy-synthetic",
                        recipientAccountId = "recipient-id", text = "", attachment } })
                };
            }
            var body = request.RequestUri!.AbsolutePath switch
            {
                "/api/fleets/membership" => Created ? "{\"fleetCode\":\"NEWORG\"}" : LeaveWrites == 0 ? "{\"fleetCode\":\"A\"}" : "{\"fleetCode\":null}",
                "/api/fleets/applications/mine" => "[]",
                "/api/fleets" => Created
                    ? "[" + (InviteCreated ? CreatedFleetWithInvite() : CreatedFleet) + "]"
                    : LeaveEnabled
                    ? "[{\"code\":\"A\",\"name\":\"Existing organization\",\"totalMembers\":1,\"ownerAccount\":\"other-user\",\"members\":[{\"accountId\":\"legacy-synthetic\"}]}]"
                    : "[{\"code\":\"A\",\"name\":\"Existing organization\",\"totalMembers\":0,\"members\":[]}]",
                "/api/auth/session" => "{\"accountId\":\"legacy-synthetic\",\"userName\":\"self-user\"}",
                "/api/fleets/leave" => "{\"status\":\"left\"}",
                "/api/fleets/invites/preview" => JsonSerializer.Serialize(new { fleetCode = "B", fleetName = "Invite organization", commander = "Owner", joinPolicy = "Invite", totalMembers = 2, expiresAt = DateTimeOffset.UtcNow.AddHours(1), remainingUses = 3, acceptMode = "Direct" }),
                "/api/friends/chat/conversations" => JsonSerializer.Serialize(new { totalUnread = 0, serverTime = DateTimeOffset.UtcNow,
                    conversations = new[] { new { user = new { accountId = "recipient-id", callsign = "Recipient", gameId = "Recipient" },
                        unreadCount = 0, lastMessagePreview = "", lastMessageAt = DateTimeOffset.UtcNow, conversationState = "friend" } } }),
                _ => throw new Exception("Unexpected route")
            };
            return new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(body) };
        }

        private const string CreatedFleet = "{\"code\":\"NEWORG\",\"name\":\"New Organization\",\"totalMembers\":1,\"ownerAccount\":\"self-user\",\"members\":[{\"accountId\":\"legacy-synthetic\"}],\"memberPermissions\":[],\"description\":\"\",\"language\":\"zh-CN\",\"activeTime\":\"19:00 - 22:00\",\"type\":\"PVP\",\"activeSystemIds\":[\"stanton\"],\"logoImageData\":null,\"profileRevision\":1,\"fleetInvitationCardPolicy\":\"all_members\",\"invites\":[]}";
        private static string CreatedFleetWithInvite() => JsonSerializer.Serialize(new
        {
            code = "NEWORG", name = "New Organization", totalMembers = 1, ownerAccount = "self-user",
            members = new[] { new { accountId = "legacy-synthetic" } }, description = "", language = "zh-CN",
            activeTime = "19:00 - 22:00", type = "PVP", activeSystemIds = new[] { "stanton" },
            logoImageData = (string?)null, fleetInvitationCardPolicy = "all_members",
            invites = new[] { new { id = new string('a', 32), code = "INVITE-HOST", createdBy = "Old Commander",
                createdAt = DateTimeOffset.UtcNow, expiresAt = DateTimeOffset.UtcNow.AddDays(7), maxUses = 1,
                usedCount = 0, status = "Active", acceptMode = "Direct", createdByAccount = "self-user" } }
        });
    }

    private static async Task VerifyRestoration()
    {
        var migration = new Store();
        var active = new Store();
        using (var transport = new Transport())
        using (var client = new LegacyPasswordLoginClient(new Uri("https://example.invalid/"), migration, transport, active))
        using (var host = CreateHost(client))
        {
            await host.LoginLegacyAsync(BridgePayload.From(new { schemaVersion = 1, email = "old@example.invalid", password = "short" }), host.Generation, default);
            Check(active.Value is not null && migration.Reads == 0, "persist active session without reading migration data");
        }
        using var restoreTransport = new Transport();
        using var restoreClient = new LegacyPasswordLoginClient(new Uri("https://example.invalid/"), migration, restoreTransport, active);
        var scmVault = new Vault { ForbidRead = true };
        using var restored = CreateHost(restoreClient, vault: scmVault);
        Check((await restored.GetCurrentAsync(default)).State == "legacySignedIn" && restoreTransport.Path == "/api/auth/session" && restoreTransport.Authorized, "restore validates WPF session endpoint");
        Check(scmVault.Reads == 0, "selected legacy account restoration never reads or contacts SCM");
        await restored.LogoutAsync(restored.CurrentContext!, default);
        Check(active.Value is null && migration.Value is not null, "logout deletes only active credential, not migration source");
        var preservedMigration = migration.Value;
        using (var signedOutTransport = new Transport())
        using (var signedOutClient = new LegacyPasswordLoginClient(new Uri("https://example.invalid/"), migration, signedOutTransport, active))
        using (var signedOut = CreateHost(signedOutClient))
        {
            Check((await signedOut.GetCurrentAsync(default)).State == "signedOut" && active.Value is null,
                "reopening after logout stays signed out despite preserved WPF credential");
            Check(signedOutTransport.Calls == 0 && migration.Reads == 0 && migration.Value == preservedMigration,
                "signed-out startup neither reads nor sends nor changes the WPF credential");
            await signedOut.LoginLegacyAsync(BridgePayload.From(new { schemaVersion = 1, email = "old@example.invalid", password = "short" }), signedOut.Generation, default);
            Check((await signedOut.GetCurrentAsync(default)).State == "legacySignedIn" && active.Value is not null,
                "explicit old-account login works again without SCM linking");
            Check(migration.Reads == 0, "explicit login does not import saved WPF credentials");
        }
        using var unavailableTransport = new Transport { Status = HttpStatusCode.ServiceUnavailable };
        using var unavailableClient = new LegacyPasswordLoginClient(new Uri("https://example.invalid/"), migration,
            unavailableTransport, active);
        using var unavailable = CreateHost(unavailableClient);
        Check((await unavailable.GetCurrentAsync(default)).State == "legacyUnavailable" && active.Value is not null, "outage retains credential without claiming a live session");
        var generation = unavailable.Generation;
        Check((await unavailable.GetCurrentAsync(default)).State == "legacyUnavailable" && unavailable.Generation == generation, "unchanged outage does not churn account generation");
        unavailableTransport.Status = HttpStatusCode.OK;
        unavailableTransport.Body = "[]";
        Check((await unavailable.GetCurrentAsync(default)).State == "legacyUnavailable" && active.Value is not null, "malformed restore response preserves credential");
        unavailableTransport.Body = Transport.Valid.TrimEnd('}') + ",\"avatarImageData\":\"" + new string('x', 20000) + "\"}";
        var events = 0;
        unavailable.AccountChanged += _ => events++;
        Check((await unavailable.GetCurrentAsync(default)).State == "legacySignedIn" && unavailable.Generation == generation + 1 && events == 1,
            "network recovery with WPF avatar-sized response publishes a single live-session transition");
        using var rejectedClient = new LegacyPasswordLoginClient(new Uri("https://example.invalid/"), migration,
            new Transport { Status = HttpStatusCode.Unauthorized }, active);
        using var rejected = CreateHost(rejectedClient);
        Check((await rejected.GetCurrentAsync(default)).State == "signedOut" && active.Value is null, "expired session clears active credential");
    }

    private static ScmAccountBridgeHost CreateHost(LegacyPasswordLoginClient client, ScmOAuthSession? session = null,
        StarBridge.HostRuntime.Friends.FriendsReader? friends = null, Vault? vault = null,
        StarBridge.HostRuntime.Communities.CommunityClient? communities = null) =>
        new(new OAuthPkceClient(new ScmHttpClient(), vault ?? new Vault(), ScmOAuthOptions.CreateDefault()), new ScmProfileCacheStore(), "development", () => null,
            initialSession: session, legacyPasswordLogin: client, friends: friends, communities: communities);
    private static string? Outcome(BridgeDispatchBatch result) => result.Response.Payload.TryGetProperty("outcome", out var value) ? value.GetString() : null;
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
    private sealed class Store : ILegacyMigrationCredentialStore
    {
        internal int Saves;
        internal int Reads;
        internal bool Fail;
        internal LegacyMigrationCredential? Value;
        public void Save(LegacyMigrationCredential value) { if (Fail) throw new IOException("synthetic"); Saves++; Value = value; }
        public LegacyMigrationCredential? Load() { Reads++; return Value; }
        public void Delete() { Value = null; }
    }
    private sealed class Transport : HttpMessageHandler
    {
        internal const string Valid = "{\"accountId\":\"legacy-synthetic\",\"email\":\"old@example.invalid\",\"token\":\"synthetic-token\",\"callsign\":\"Old Commander\"}";
        internal HttpStatusCode Status = HttpStatusCode.OK;
        internal string Body = Valid;
        internal string? Path, Email, Password;
        internal bool Authorized, Pending;
        internal string? Bearer;
        internal StarBridge.Core.Profiles.PersonalProfileGameplayStatisticsUpdateRequestContract? Upload;
        internal int Calls;
        internal int DirectoryReads;
        internal string DirectoryLogo = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=";
        internal TaskCompletionSource Started = new(TaskCreationOptions.RunContinuationsAsynchronously);
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            if (request.RequestUri!.AbsolutePath == "/api/profile/me/gameplay-statistics")
            {
                Calls++; Bearer = request.Headers.Authorization?.Parameter;
                Check(request.Method == HttpMethod.Put && request.RequestUri.Query.Length == 0, "owner-scoped PUT only");
                Upload = JsonSerializer.Deserialize<StarBridge.Core.Profiles.PersonalProfileGameplayStatisticsUpdateRequestContract>(
                    await request.Content!.ReadAsStringAsync(token), new JsonSerializerOptions(JsonSerializerDefaults.Web));
                return new(Status) { Content = new StringContent(Body) };
            }
            if (request.RequestUri!.AbsolutePath is "/api/profile/me/gameplay-time-reset" or "/api/profile/me/visibility")
            {
                Calls++; Authorized = request.Headers.Authorization?.Scheme == "Bearer";
                Bearer = request.Headers.Authorization?.Parameter;
                Check(request.RequestUri.Query.Length == 0, "reset target comes only from authenticated session");
                return new(Status) { Content = new StringContent(Body) };
            }
            if (request.RequestUri!.AbsolutePath == "/api/fleets")
            {
                DirectoryReads++;
                return new(HttpStatusCode.OK) { Content = JsonContent.Create(new[] { new { code = "TEST", logoImageData = DirectoryLogo } }) };
            }
            Calls++; Path = request.RequestUri!.AbsolutePath; Authorized = request.Headers.Authorization is not null;
            if (request.Content is not null && Path != "/api/auth/entitlements/redeem")
            {
                using var json = JsonDocument.Parse(await request.Content.ReadAsStringAsync(token));
                Email = json.RootElement.GetProperty("email").GetString(); Password = json.RootElement.GetProperty("password").GetString();
            }
            if (Pending)
            {
                Started.TrySetResult();
                var ended = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
                using var registration = token.Register(() => ended.TrySetResult());
                await ended.Task; // Deliberately returns success after cancellation.
            }
            var response = new HttpResponseMessage(Status) { Content = new StringContent(Body) };
            if (Status == HttpStatusCode.TooManyRequests) response.Headers.RetryAfter = new RetryConditionHeaderValue(TimeSpan.FromSeconds(95));
            return response;
        }
    }
    private sealed class Vault : ITokenVault
    {
        internal bool ForbidRead;
        internal int Reads;
        public void SaveRefreshToken(string a, string b) => throw new Exception("Legacy login cannot save SCM token");
        public string? LoadRefreshToken(string a) => null;
        public string? LoadActiveAccountKey() { Reads++; if (ForbidRead) throw new Exception("SCM access is forbidden in this legacy restoration test"); return null; }
        public void DeleteRefreshToken(string a) => throw new Exception("Legacy login cannot delete SCM token");
    }
}
