using System.Net;
using System.Net.Http.Json;
using StarBridge.Core.Profiles;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.PartyRooms;
using StarBridge.Core.PartyRooms;
using StarBridge.NativeBridge;

internal static partial class LegacyPasswordLoginTests
{
    private static async Task ScmVisitorProfileRead()
    {
        using var transport = new ScmVisitorTransport();
        var uri = new Uri("http://127.0.0.1:9/");
        var oauth = new OAuthPkceClient(new ScmHttpClient(transport), new ScmBackgroundVault(),
            new ScmOAuthOptions("synthetic", uri, uri, uri, "synthetic", "synthetic", "openid profile.read", "/callback"));
        var session = new ScmOAuthSession("synthetic", "viewer", "Pilot", "synthetic-read-token",
            DateTimeOffset.UtcNow.AddHours(1), ["profile.read"]);
        var target = "scm-v1:" + new string('a', 64);
        var result = await oauth.LoadVisitorPersonalProfileAsync(session, target, default);
        Check(result.Profile.Identity.Callsign == "Visitor" && !result.Profile.IsPublic,
            "SCM server-authorized friend/main-fleet content remains visible without being public");
        Check(result.ActiveSession.Subject == session.Subject, "reading another profile never changes logged-in owner");
        transport.RichLayout = true;
        var rich = await oauth.LoadVisitorPersonalProfileAsync(session, target, default);
        Check(rich.Profile.Content.Modules.Length == 4,
            "authorized visitor transport must not truncate the server's rich layout");
        Check(rich.Profile.Content.Modules[3].Id == "favorite-ships-2" &&
            !rich.Profile.Content.Modules[3].IsVisible && rich.Profile.Hangar is null &&
            rich.Profile.Presentation is null && rich.Profile.Identity.GameId == "",
            "rich visitor layout preserves hidden cards without adding assets, edit metadata or Handle");
        transport.RichLayout = false;
        var fullLayout = Enumerable.Range(1, 64).Select(index =>
            new PersonalProfileModuleContract("favorite-ships-" + index, 1, false, index - 1,
                FavoriteShipIds: [index.ToString("x32")])).ToArray();
        transport.LayoutOverride = fullLayout;
        var full = await oauth.LoadVisitorPersonalProfileAsync(session, target, default);
        Check(full.Profile.Content.Modules.Length == 64 &&
            full.Profile.Content.Modules[63].FavoriteShipIds!.Single() == 64.ToString("x32"),
            "all bounded hidden visitor module selections survive transport");
        foreach (var invalidLayout in new PersonalProfileModuleContract[][] {
            [.. fullLayout, new("favorite-ships-65", 1, false, 64)],
            [new("unsupported", 1, true, 0)],
            [new("favorite-ships", 1, true, 0), new("favorite-ships", 1, false, 1)],
            [new("favorite-ships", 1, true, 0, FavoriteShipIds: ["invalid"])],
            [new("favorite-ships", 1, true, 0, FavoriteShipIds: [1.ToString("x32")]),
             new("favorite-ships-2", 1, false, 1, FavoriteShipIds: [1.ToString("x32")])],
            [new("hangar-summary", 1, true, 0, FavoriteShipIds: [1.ToString("x32")])],
            [new("favorite-ships", 1, false, 0, FavoriteShipIds: [1.ToString("x32"), 2.ToString("x32")])]
        })
        {
            transport.LayoutOverride = invalidLayout;
            var before = transport.Calls;
            try { await oauth.LoadVisitorPersonalProfileAsync(session, target, default); throw new Exception("invalid visitor layout accepted"); }
            catch (ScmApiProtocolException) { }
            Check(transport.Calls == before + 1, "invalid visitor layout is rejected without fallback or replay");
        }
        transport.LayoutOverride = null;
        foreach (var invalid in new[] { "legacy-id", "scm-v1:" + new string('A', 64), target + "/other" })
        {
            var before = transport.Calls;
            try { await oauth.LoadVisitorPersonalProfileAsync(session, invalid, default); throw new Exception("invalid target accepted"); }
            catch (ArgumentException) { }
            Check(transport.Calls == before, "invalid visitor target cannot reach HTTP");
        }
        transport.WrongTarget = true;
        try { await oauth.LoadVisitorPersonalProfileAsync(session, target, default); throw new Exception("wrong target accepted"); }
        catch (ScmApiProtocolException) { }
        transport.WrongTarget = false;
        transport.Status = HttpStatusCode.NotFound;
        try { await oauth.LoadVisitorPersonalProfileAsync(session, target, default); throw new Exception("private profile accepted"); }
        catch (HttpRequestException e) when (e.StatusCode == HttpStatusCode.NotFound) { }
        transport.Status = HttpStatusCode.ServiceUnavailable;
        var calls = transport.Calls;
        try { await oauth.LoadVisitorPersonalProfileAsync(session, target, default); throw new Exception("outage accepted"); }
        catch (ScmApiUnavailableException) { }
        Check(transport.Calls == calls + 1, "Java outage must not trigger legacy fallback or replay");
        await ScmRoomVisitorPipeline();
        await ScmFriendVisitorPipeline();
        await ScmCommunityVisitorPipeline();
    }

    private static async Task ScmCommunityVisitorPipeline()
    {
        using var profile = new ScmVisitorTransport();
        using var directoryTransport = new ScmVisitorCommunityTransport();
        using var communities = new StarBridge.HostRuntime.Communities.CommunityClient(new Uri("https://example.invalid/"), directoryTransport);
        var uri = new Uri("http://127.0.0.1:9/");
        var oauth = new OAuthPkceClient(new ScmHttpClient(profile), new ScmBackgroundVault(),
            new ScmOAuthOptions("synthetic", uri, uri, uri, "synthetic", "synthetic", "openid profile.read", "/callback"));
        using var host = new ScmAccountBridgeHost(oauth, new ScmProfileCacheStore(), "integration", () => null,
            initialSession: new ScmOAuthSession("synthetic", "viewer", "Pilot", "synthetic-read-token",
                DateTimeOffset.UtcNow.AddHours(1), ["profile.read"]), communities: communities);
        using var dispatcher = new AccountBridgeDispatcher(host);
        var owner = host.CurrentContext!; var generation = host.Generation;
        var directory = (StarBridge.HostRuntime.Communities.CommunityPage)await host.ReadCommunitiesAsync(owner,
            BridgePayload.From(new { schemaVersion = 1, view = "mine", query = "" }), default);
        var target = directory.Items.Single().TargetRef;
        async Task<string> Member() {
            var workspace = BridgePayload.From(await host.ReadCommunityWorkspaceAsync(owner,
                BridgePayload.From(new { schemaVersion = 1, targetRef = target, query = "", offset = 0 }), default));
            return workspace.GetProperty("members")[0].GetProperty("memberRef").GetString()!;
        }
        var member = await Member();
        Task<AccountBridgeDispatchResult> Read(string name, object payload) => dispatcher.DispatchAsync(BridgeEnvelope.Request(
            name, Guid.NewGuid().ToString("N"), generation, payload, owner), default);
        var result = await Read("communities.memberPersonalProfile", new { schemaVersion = 1, targetRef = target, memberRef = member });
        Check(result.Response.Error is null, "SCM dedicated community visitor route reaches Java: " + result.Response.Error?.Code);
        result = await Read("users.profile", new { schemaVersion = 1, source = "community", reference = member, contextRef = target });
        Check(result.Response.Error is null && !result.Response.Payload.GetProperty("editable").GetBoolean(),
            "SCM shared avatar route reads the same community member");
        var calls = profile.Calls;
        var relayCalls = directoryTransport.Calls;
        foreach (var operation in new[] { "users.profile", "users.social" })
        {
            result = await Read(operation, new { schemaVersion = 1, source = "communityApplicant", reference = member, contextRef = target });
            Check(result.Response.Error?.Code == "communities.refreshRequired" && calls == profile.Calls &&
                relayCalls == directoryTransport.Calls,
                "member refs cannot be substituted for scoped applicant refs");
        }
        result = await Read("communities.memberPersonalProfile", new { schemaVersion = 1, targetRef = target, memberRef = member, publicId = "injected" });
        Check(result.Response.Error is not null && calls == profile.Calls, "SCM member route rejects identity injection before HTTP");
        directoryTransport.Historical = true;
        member = await Member();
        result = await Read("users.profile", new { schemaVersion = 1, source = "community", reference = member, contextRef = target });
        Check(result.Response.Error is null && profile.Calls == calls + 1,
            "historical member profile uses the Java-owned active-binding resolver, never a guessed SCM ID");
        result = await Read("communities.memberPersonalProfile", new { schemaVersion = 1, targetRef = target, memberRef = member });
        Check(result.Response.Error is null, "dedicated community profile entry shares historical identity resolution");
        foreach (var status in new[] { HttpStatusCode.NotFound, HttpStatusCode.Forbidden, HttpStatusCode.ServiceUnavailable })
        {
            profile.LegacyStatus = status;
            calls = profile.Calls; relayCalls = directoryTransport.Calls;
            result = await Read("users.profile", new { schemaVersion = 1, source = "community", reference = member, contextRef = target });
            Check(result.Response.Error?.Code == (status == HttpStatusCode.NotFound
                    ? "profile.visitor_not_visible" : "profile.visitor_identity_unavailable") &&
                profile.Calls == calls + 1 && relayCalls == directoryTransport.Calls,
                "historical private or unavailable Java target cannot trigger a Relay profile fallback");
        }
        profile.LegacyRouteMissing = true;
        result = await Read("users.profile", new { schemaVersion = 1, source = "community", reference = member, contextRef = target });
        Check(result.Response.Error?.Code == "profile.visitor_identity_unavailable", "missing Java route is not evidence of a private profile");
        profile.LegacyRouteMissing = false; profile.LegacyStatus = HttpStatusCode.OK;
        profile.WrongLegacyId = true;
        result = await Read("users.profile", new { schemaVersion = 1, source = "community", reference = member, contextRef = target });
        Check(result.Response.Error?.Code == "profile.visitor_identity_unavailable", "another historical member's profile cannot be substituted");
        profile.WrongLegacyId = false;
        directoryTransport.Historical = false;
        var admissions = BridgePayload.From(await host.ReadCommunityAdmissionsAsync(owner, BridgePayload.From(new {
            schemaVersion = 1, targetRef = target, section = "applications", offset = 0 }), default));
        var entry = admissions.GetProperty("items")[0].GetProperty("entryRef").GetString()!;
        Check(!admissions.GetRawText().Contains("fixture-application"), "application server IDs stay behind Bridge");
        Task<AccountBridgeDispatchResult> Applicant() => Read("users.profile", new {
            schemaVersion = 1, source = "communityApplicant", reference = entry, contextRef = target });
        result = await Applicant();
        Check(result.Response.Error is null && !result.Response.Payload.GetProperty("editable").GetBoolean(),
            "SCM applicant scoped reference reaches Java visitor policy: " + result.Response.Error?.Code);
        calls = profile.Calls;
        foreach (var status in new[] { HttpStatusCode.NotFound, HttpStatusCode.Forbidden, HttpStatusCode.ServiceUnavailable })
        {
            directoryTransport.ApplicantStatus = status;
            result = await Applicant();
            Check(result.Response.Error is not null && profile.Calls == calls && !result.Response.Payload.GetRawText().Contains("Visitor"),
                "withdrawn, revoked or unavailable applicant identity never reuses profile data");
        }
        directoryTransport.ApplicantStatus = HttpStatusCode.OK;
        directoryTransport.Historical = true;
        Check((await Applicant()).Response.Error?.Code == "profile.visitor_unavailable" && profile.Calls == calls,
            "legacy applicant cannot silently become SCM target");
        directoryTransport.Historical = false;
        profile.Pending = true;
        var pending = Applicant();
        await profile.Started.Task.WaitAsync(TimeSpan.FromSeconds(5));
        directoryTransport.ApplicantStatus = HttpStatusCode.Forbidden;
        profile.Release.TrySetResult(true);
        result = await pending;
        Check(result.Response.Error is not null && !result.Response.Payload.GetRawText().Contains("Visitor"),
            "revoking review permission during Java profile load discards the late body");
        directoryTransport.ApplicantStatus = HttpStatusCode.OK;
        profile.Started = new(TaskCreationOptions.RunContinuationsAsynchronously);
        profile.Release = new(TaskCreationOptions.RunContinuationsAsynchronously);
        pending = Applicant();
        await profile.Started.Task.WaitAsync(TimeSpan.FromSeconds(5));
        await host.LogoutAsync(owner, default);
        profile.Release.TrySetResult(true);
        Check((await pending).Response.Error is not null, "late applicant profile cannot survive logout");
    }

    private sealed class ScmVisitorCommunityTransport : HttpMessageHandler
    {
        internal bool Historical;
        internal int Calls;
        internal HttpStatusCode ApplicantStatus = HttpStatusCode.OK;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Calls++;
            Check(request.Method == HttpMethod.Get && request.Headers.Authorization?.Parameter == "synthetic-read-token",
                "SCM organization profile navigation is read-only");
            if (request.RequestUri!.AbsolutePath == "/api/fleets/directory")
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(new {
                    schemaVersion = 1, membershipModelVersion = 2, view = "mine", query = "", next = (string?)null,
                    items = new[] { new { code = "A", name = "Fixture", description = "", language = "", activeTime = "",
                        memberCount = 1, relationship = "member", joinMode = "direct", actions = new[] { "leave" }, logoImageData = (string?)null } }
                }) });
            if (request.RequestUri.AbsolutePath == "/api/fleets/admissions")
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(new {
                    schemaVersion = 1, membershipModelVersion = 2, code = "A", section = "applications", offset = 0,
                    next = (int?)null, totalCount = 1, fetchedAt = DateTimeOffset.UtcNow,
                    access = new { canReadApplications = true, canDecideApplications = false, canReadInvites = false,
                        canCreateInvite = false, canSendInvitationCard = false },
                    applications = new[] { new { applicationId = "fixture-application", gameName = "", callsign = "Visitor",
                        message = "", status = "Pending", createdAt = DateTimeOffset.UtcNow, hasAvatar = false } }, invites = Array.Empty<object>()
                }) });
            if (request.RequestUri.AbsolutePath == "/api/fleets/admissions/applicant")
            {
                Check(request.RequestUri.Query == "?code=A&applicationId=fixture-application", "applicant identity uses exact scoped application");
                return Task.FromResult(new HttpResponseMessage(ApplicantStatus) { Content = JsonContent.Create(new {
                    schemaVersion = 1, code = "A", applicationId = "fixture-application",
                    accountId = Historical ? "historical-account" : "scm-v1:" + new string('a', 64)
                }) });
            }
            Check(request.RequestUri.AbsolutePath == "/api/fleets/workspace", "exact modern organization workspace endpoint");
            var workspace = CommunityWorkspaceClientTests.Workspace();
            workspace["members"]![0]!["memberId"] = Historical ? "account:historical-member" : "account:scm-v1:" + new string('a', 64);
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(workspace) });
        }
    }

    private static async Task ScmFriendVisitorPipeline()
    {
        using var profile = new ScmVisitorTransport { AllowFriendIdentity = true };
        using var directoryTransport = new ScmVisitorFriendsTransport();
        using var friends = new StarBridge.HostRuntime.Friends.FriendsReader(new Uri("https://example.invalid/"), directoryTransport);
        var uri = new Uri("http://127.0.0.1:9/");
        var oauth = new OAuthPkceClient(new ScmHttpClient(profile), new ScmBackgroundVault(),
            new ScmOAuthOptions("synthetic", uri, uri, uri, "synthetic", "synthetic", "openid profile.read", "/callback"));
        using var host = new ScmAccountBridgeHost(oauth, new ScmProfileCacheStore(), "integration", () => null,
            initialSession: new ScmOAuthSession("synthetic", "viewer", "Pilot", "synthetic-read-token",
                DateTimeOffset.UtcNow.AddHours(1), ["profile.read"]), friends: friends);
        using var dispatcher = new AccountBridgeDispatcher(host);
        var owner = host.CurrentContext!; var generation = host.Generation;
        var directory = await host.ReadFriendsAsync(owner, BridgePayload.From(new { schemaVersion = 1 }), default);
        var peer = directory.Friends.Single();
        Check(!BridgePayload.From(directory).GetRawText().Contains("scm-v1:"), "friend list hides internal SCM identity");
        Task<AccountBridgeDispatchResult> Read(string source, string reference) => dispatcher.DispatchAsync(BridgeEnvelope.Request(
            "users.profile", Guid.NewGuid().ToString("N"), generation,
            new { schemaVersion = 1, source, reference }, owner), default);
        foreach (var source in new[] { "friend", "conversation" })
        {
            var reference = source == "friend" ? peer.TargetRef! : peer.ChatTargetRef!;
            var result = await Read(source, reference);
            Check(result.Response.Error is null && !result.Response.Payload.GetProperty("editable").GetBoolean(),
                "pure SCM " + source + " opens authorized Java profile: " + result.Response.Error?.Code);
        }
        profile.Status = HttpStatusCode.NotFound;
        var denied = await Read("conversation", peer.ChatTargetRef!);
        Check(denied.Response.Error?.Code == "profile.visitor_not_visible" &&
            !denied.Response.Payload.GetRawText().Contains("Visitor"), "server privacy denial cannot reuse previous profile body");
        profile.Status = HttpStatusCode.OK;
        directoryTransport.DifferentPeer = true;
        await host.ReadFriendsAsync(owner, BridgePayload.From(new { schemaVersion = 1 }), default);
        var calls = profile.Calls;
        Check((await Read("friend", peer.TargetRef!)).Response.Error is null && profile.Calls == calls + 1,
            "retained profile reference still resolves original identity, never the new same-name row");
        profile.Status = HttpStatusCode.NotFound;
        Check((await Read("friend", peer.TargetRef!)).Response.Error?.Code == "profile.visitor_not_visible",
            "retained read reference does not retain previous Java authorization");
        calls = profile.Calls;
        await host.LogoutAsync(owner, default);
        Check((await Read("conversation", peer.ChatTargetRef!)).Response.Error is not null && profile.Calls == calls,
            "old conversation profile reference cannot survive account logout");
        Check(directoryTransport.Writes == 0, "opening a friend profile never writes to Relay");
    }

    private sealed class ScmVisitorFriendsTransport : HttpMessageHandler
    {
        internal bool DifferentPeer;
        internal int Writes;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            if (request.Method != HttpMethod.Get) Writes++;
            Check(request.Headers.Authorization?.Parameter == "synthetic-read-token" && request.RequestUri!.AbsolutePath == "/api/friends",
                "friend directory uses exact Relay path and SCM bearer");
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent(
                FriendsReaderTests.Directory(FriendsReaderTests.User("scm-v1:" + new string(DifferentPeer ? 'b' : 'a', 64)))) });
        }
    }

    internal static Task VisitorProfileWireFixture(string wireBody) => ScmRoomVisitorPipeline(wireBody);

    private static async Task ScmRoomVisitorPipeline(string? wireBody = null)
    {
        using var profile = new ScmVisitorTransport { WireBody = wireBody };
        using var roomTransport = new ScmVisitorRoomTransport();
        using var rooms = new PartyRoomReader(new Uri("https://example.invalid/"), roomTransport);
        var uri = new Uri("http://127.0.0.1:9/");
        var oauth = new OAuthPkceClient(new ScmHttpClient(profile), new ScmBackgroundVault(),
            new ScmOAuthOptions("synthetic", uri, uri, uri, "synthetic", "synthetic", "openid profile.read", "/callback"));
        using var host = new ScmAccountBridgeHost(oauth, new ScmProfileCacheStore(), "integration", () => null,
            initialSession: new ScmOAuthSession("synthetic", "viewer", "Pilot", "synthetic-read-token",
                DateTimeOffset.UtcNow.AddHours(1), ["profile.read"]), partyRooms: rooms);
        using var dispatcher = new AccountBridgeDispatcher(host);
        var owner = host.CurrentContext!;
        var generation = host.Generation;
        var directory = await host.GetPartyRoomsAsync(owner, default);
        var reference = directory.Rooms.Single().Members.Single().UserRef ?? throw new Exception("Room target missing");
        Check(!BridgePayload.From(directory).GetRawText().Contains("scm-v1:"),
            "SCM room gives Flutter opaque references, never the internal subject");
        Task<AccountBridgeDispatchResult> Read(string entry) => dispatcher.DispatchAsync(BridgeEnvelope.Request(
            "users.profile", Guid.NewGuid().ToString("N"), generation,
            new { schemaVersion = 1, source = "room", reference = entry, query = "" }, owner), default);
        var visible = await Read(reference);
        Check(visible.Response.Error is null && !visible.Response.Payload.GetProperty("editable").GetBoolean(),
            "pure SCM room reference reaches Java and read-only visitor projection: " + visible.Response.Error?.Code);
        Check(!visible.Response.Payload.GetRawText().Contains("scm-v1:") &&
            !visible.Response.Payload.GetRawText().Contains("opaque-public-profile"), "Host keeps target IDs private");
        if (wireBody is not null)
        {
            // Only the opt-in synthetic stdin fixture emits the bridge payload.
            Console.Write(visible.Response.Payload.GetRawText());
            return;
        }
        var calls = profile.Calls;
        Check((await Read("scm-v1:" + new string('a', 64))).Response.Error is not null && profile.Calls == calls,
            "raw target ID cannot bypass room reference resolution");
        roomTransport.Locked = true;
        Check((await Read(reference)).Response.Error?.Code == "users.targetChanged" && profile.Calls == calls,
            "withdrawn room preview stops before Java profile access");
        roomTransport.Locked = false;
        directory = await host.GetPartyRoomsAsync(owner, default);
        reference = directory.Rooms.Single().Members.Single().UserRef!;
        profile.Pending = true;
        var pending = Read(reference);
        await profile.Started.Task.WaitAsync(TimeSpan.FromSeconds(5));
        await host.LogoutAsync(owner, default);
        profile.Release.TrySetResult(true);
        Check((await pending).Response.Error is not null, "late SCM profile cannot survive logout/generation change");
    }

    private sealed class ScmVisitorRoomTransport : HttpMessageHandler
    {
        internal bool Locked;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Check(request.Headers.Authorization?.Parameter == "synthetic-read-token", "room reads use SCM bearer only");
            var now = DateTimeOffset.UtcNow;
            var room = new PartyRoomSnapshot("fixture-room", "fixture-code", "scm-v1:" + new string('a', 64),
                "Fixture", "", [], [], 4, true, "everyone", "direct", Locked, "recommended", "zh", null, now.AddHours(1),
                [new("", "Visitor", "", null, true, "应用在线", "", "", "", now)
                    { PublicProfileId = "scm-v1:" + new string('a', 64) }], now, now, 1)
                { CanPreviewMemberProfiles = !Locked };
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
                { Content = JsonContent.Create(new PartyRoomDirectoryResponse([room], null, now)) });
        }
    }

    private sealed class ScmVisitorTransport : HttpMessageHandler
    {
        internal int Calls;
        internal bool AllowFriendIdentity;
        internal bool AllowOwnProfile;
        internal bool WrongTarget;
        internal bool Pending;
        internal bool RichLayout;
        internal PersonalProfileModuleContract[]? LayoutOverride;
        internal string? WireBody;
        internal TaskCompletionSource<bool> Started = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal TaskCompletionSource<bool> Release = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal HttpStatusCode Status = HttpStatusCode.OK;
        internal HttpStatusCode LegacyStatus = HttpStatusCode.OK;
        internal bool WrongLegacyId, LegacyRouteMissing;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            var target = "scm-v1:" + new string('a', 64);
            var path = Uri.UnescapeDataString(request.RequestUri!.AbsolutePath);
            if (AllowOwnProfile && path == "/app-api/starbridge/v1/personal-profile")
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) {
                    Content = new StringContent(WireBody!, System.Text.Encoding.UTF8, "application/json") });
            if (path == "/app-api/starbridge/v1/personal-profile/visitor-legacy")
            {
                Check(request.Method == HttpMethod.Post && request.Headers.Authorization?.Parameter == "synthetic-read-token",
                    "historical visitor is a Java read using the current SCM bearer");
                using var document = System.Text.Json.JsonDocument.Parse(request.Content!.ReadAsStringAsync(token).GetAwaiter().GetResult());
                var input = document.RootElement;
                Check(input.GetProperty("legacyAccountId").GetString() == "historical-member" && input.GetProperty("schemaVersion").GetInt32() == 1,
                    "only the exact scoped roster identity reaches Java");
                Calls++;
                if (LegacyRouteMissing) return Complete(new HttpResponseMessage(HttpStatusCode.NotFound) { Content = new StringContent("<html>Not found</html>") });
                if (LegacyStatus != HttpStatusCode.OK) return Complete(new HttpResponseMessage(LegacyStatus) {
                    Content = JsonContent.Create(new { code = LegacyStatus == HttpStatusCode.NotFound
                        ? "PERSONAL_PROFILE_NOT_AVAILABLE" : "PROFILE_IDENTITY_TEMPORARILY_UNAVAILABLE" }) });
                return Complete(new HttpResponseMessage(LegacyStatus) { Content = JsonContent.Create(new {
                    schemaVersion = 1, legacyAccountId = WrongLegacyId ? "other-historical-member" : "historical-member", profile = new PersonalProfileDocumentContract(
                        3, "opaque-public-profile", false, 7, DateTimeOffset.UtcNow, new("Visitor", ""),
                        PersonalProfileContentContract.Empty, null, Visibility: "friendsAndMainFleet")
                }) });
            }
            if (AllowFriendIdentity && (path == "/app-api/starbridge/v1/participants/" + target + "/friend-identity" ||
                path == "/app-api/starbridge/v1/participants/scm-v1:" + new string('b', 64) + "/friend-identity"))
            {
                Check(request.Method == HttpMethod.Get && request.RequestUri.Query.Length == 0 &&
                    request.Headers.Authorization?.Parameter == "synthetic-read-token", "scoped friend identity GET uses current owner token");
                var id = path.Split('/')[5];
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(new {
                    schemaVersion = 1, businessSubjectId = id, callSign = "Visitor", handle = ""
                }) });
            }
            Calls++;
            Check(request.Method == HttpMethod.Get && Uri.UnescapeDataString(request.RequestUri!.AbsolutePath) ==
                "/app-api/starbridge/v1/personal-profile/visitor/" + target &&
                request.Headers.Authorization?.Parameter == "synthetic-read-token", "Java visitor endpoint and owner token");
            var response = new HttpResponseMessage(Status) { Content = JsonContent.Create(new PersonalProfileDocumentContract(
                3, "opaque-public-profile", false, 7, DateTimeOffset.UtcNow, new("Visitor", ""),
                PersonalProfileContentContract.Empty with {
                    Modules = LayoutOverride ?? (RichLayout ? [new("favorite-ships", 1, true, 0),
                        new("hangar-summary", 1, true, 1), new("skilled-roles", 1, true, 2),
                        new("favorite-ships-2", 1, false, 3)] : [])
                }, null, Visibility: "friendsAndMainFleet")) };
            if (WireBody is not null)
            {
                response.Content.Dispose();
                response.Content = new StringContent(WireBody, System.Text.Encoding.UTF8, "application/json");
            }
            response.Headers.Add("X-StarBridge-Profile-Subject", WrongTarget ? "scm-v1:" + new string('b', 64) : target);
            return Complete(response);
        }
        private async Task<HttpResponseMessage> Complete(HttpResponseMessage response)
        {
            if (Pending) { Started.TrySetResult(true); await Release.Task.WaitAsync(TimeSpan.FromSeconds(10)); }
            return response;
        }
    }
}
