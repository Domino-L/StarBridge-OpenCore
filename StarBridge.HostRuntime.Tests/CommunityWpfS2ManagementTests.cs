using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;

internal static class CommunityWpfS2ManagementTests
{
    private const string Pixel = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aM7sAAAAASUVORK5CYII=";

    internal static async Task Verify()
    {
        var posts = new List<string>();
        var identityReads = 0;
        var identityCode = "A";
        Action? beforeIdentityResponse = null;
        var fleet = JsonSerializer.SerializeToNode(Fleet())!.AsObject();
        using var handler = new Handler(request =>
        {
            Check(request.Headers.Authorization?.Parameter == "fixture", "only current bearer is used");
            var path = request.RequestUri!.AbsolutePath;
            if (request.Method == HttpMethod.Post)
            {
                posts.Add(path);
                var body = JsonNode.Parse(request.Content!.ReadAsStringAsync().GetAwaiter().GetResult())!;
                if (path == "/api/fleets/applications/decide") fleet["applications"] = new JsonArray();
                if (path == "/api/fleets/invites/revoke")
                    foreach (var row in fleet["invites"]!.AsArray())
                        if (row!["id"]!.GetValue<string>() == body["inviteId"]!.GetValue<string>()) row["status"] = "Revoked";
                if (path == "/api/fleets/invites")
                    fleet["invites"]!.AsArray().Add(JsonSerializer.SerializeToNode(new
                    {
                        id = "new-invite", code = "NEW-CODE", createdBy = "Owner", createdByAccount = "owner-id",
                        createdAt = DateTimeOffset.UtcNow, expiresAt = DateTimeOffset.UtcNow.AddDays(7),
                        maxUses = 1, usedCount = 0, status = "Active", acceptMode = "Direct"
                    }));
                return Json(fleet);
            }
            if (path == "/api/fleets/membership") return Json(new { fleetCode = "A" });
            if (path == "/api/fleets") return Json(new[] { fleet });
            if (path == "/api/auth/session") return Json(new { accountId = "owner-id", userName = "owner-login", gameName = "Owner" });
            if (path == "/api/fleets/admissions/applicant")
            {
                identityReads++;
                Check(request.RequestUri.Query.Contains("applicationId=application-private-id"), "Host resolves the stored application ID only");
                beforeIdentityResponse?.Invoke();
                return Json(new { schemaVersion = 1, code = identityCode, applicationId = "application-private-id", accountId = "stable-applicant-id" });
            }
            return new(HttpStatusCode.NotFound);
        });
        using var client = new CommunityClient(new Uri("https://fixture.invalid"), handler);
        var mine = await client.ReadWpfS2Async("fixture", new("mine", "", null, null), "scope", "owner-id", default);
        var targetRef = mine.Items.Single().TargetRef;
        var workspace = Element(await client.ReadWorkspaceAsync("fixture", Element(new
            { schemaVersion = 1, targetRef, query = "", offset = 0 }), "scope", default));
        Check(workspace.GetProperty("access").GetProperty("canReviewApplications").GetBoolean() &&
              workspace.GetProperty("access").GetProperty("canCreateInvite").GetBoolean(),
            "legacy owner receives only verified management capabilities");

        var applications = await Read("applications");
        var application = applications.GetProperty("items")[0];
        Check(application.GetProperty("gameName").GetString() == "申请者" &&
              application.GetProperty("hasAvatar").GetBoolean(), "pending application is projected from the S2 snapshot");
        Check(!applications.GetRawText().Contains("application-private-id") &&
              !applications.GetRawText().Contains("applicant-account"), "server and account identifiers stay inside Host");
        var entryRef = application.GetProperty("entryRef").GetString()!;
        var identity = await client.ResolveApplicantIdentityAsync("fixture", targetRef, entryRef, "scope", "owner-id", () => { }, default);
        Check(identity == "stable-applicant-id" && identityReads == 1, "applicant reference resolves through authorized server identity");
        await Error(async () => await client.ResolveApplicantIdentityAsync("fixture", targetRef, entryRef, "other", "owner-id", () => { }, default),
            "communities.refreshRequired");
        await Error(async () => await client.ResolveApplicantIdentityAsync("fixture", targetRef, entryRef, "scope", "other-viewer", () => { }, default),
            "profile.visitor_unavailable");
        Check(identityReads == 1, "foreign scope and viewer are rejected before transport");
        identityCode = "B";
        try
        {
            await client.ResolveApplicantIdentityAsync("fixture", targetRef, entryRef, "scope", "owner-id", () => { }, default);
            throw new InvalidOperationException("mismatched organization response accepted");
        }
        catch (AccountBridgeHostException) { }
        identityCode = "A";
        var accountCurrent = true;
        beforeIdentityResponse = () => accountCurrent = false;
        await Error(async () => await client.ResolveApplicantIdentityAsync("fixture", targetRef, entryRef, "scope", "owner-id",
            () => { if (!accountCurrent) throw new AccountBridgeHostException("identityUnavailable"); }, default), "identityUnavailable");
        beforeIdentityResponse = () => client.InvalidateInvitePreviews();
        await Error(async () => await client.ResolveApplicantIdentityAsync("fixture", targetRef, entryRef, "scope", "owner-id", () => { }, default),
            "communities.refreshRequired");
        beforeIdentityResponse = null;
        applications = await Read("applications");
        application = applications.GetProperty("items")[0];
        var avatar = Element(await client.ReadMediaAsync("fixture", Element(new
        {
            schemaVersion = 1, targetRef, kind = "applicant",
            memberRef = application.GetProperty("entryRef").GetString(), offset = 0
        }), "scope", default));
        Check(avatar.GetProperty("data").GetString() == Pixel.Split(',')[1], "applicant avatar reuses the original snapshot bytes");

        var approve = await client.ManageAdmissionsAsync("fixture", Intent(targetRef, "approve",
            application.GetProperty("entryRef").GetString()), "scope", () => { }, default, wpfS2: true);
        Check(approve.Status == "accepted" && posts.SequenceEqual(new[] { "/api/fleets/applications/decide" }),
            "approval reuses the original WPF endpoint once");

        var invites = await Read("invites");
        var invite = invites.GetProperty("items")[0];
        Check(invites.GetProperty("currentInviteAvailable").GetBoolean() &&
              invites.GetProperty("currentInvite").GetProperty("code").GetString() == "VISIBLE-CODE" &&
              invite.GetProperty("canRevoke").GetBoolean(), "current owner invitation remains manageable");
        var revoke = await client.ManageAdmissionsAsync("fixture", Intent(targetRef, "revokeInvite",
            invite.GetProperty("entryRef").GetString()), "scope", () => { }, default, wpfS2: true);
        Check(revoke.Status == "accepted" && posts.Last() == "/api/fleets/invites/revoke", "revoke uses the original endpoint");

        var generate = await client.ManageAdmissionsAsync("fixture", Element(new
        {
            schemaVersion = 1, requestId = Guid.NewGuid().ToString("N"), targetRef,
            action = "generateInvite", expiresInDays = 7, maxUses = 1, confirmUncertainRetry = false
        }), "scope", () => { }, default, wpfS2: true);
        Check(generate.Status == "accepted" && posts.TakeLast(2).SequenceEqual(new[] { "/api/fleets/invites/revoke", "/api/fleets/invites" }),
            "generation revokes the former current code before using the original endpoint");

        var readsBefore = handler.Reads;
        await Error(() => client.ReadAdmissionsAsync("fixture", Query(targetRef, "applications"), "other", () => { }, default, wpfS2: true),
            "communities.refreshRequired");
        Check(handler.Reads == readsBefore, "cross-account reference is rejected before transport");

        async Task<JsonElement> Read(string section) => Element(await client.ReadAdmissionsAsync(
            "fixture", Query(targetRef, section), "scope", () => { }, default, wpfS2: true));
    }

    private static object Fleet() => new
    {
        code = "A", name = "多语言组织", ownerAccount = "owner-id", description = "", type = "自由", language = "any",
        activeTime = "19:00 - 22:00", totalMembers = 1, inviteCodeCreationPolicy = "commander",
        fleetInvitationCardPolicy = "commander", logoImageData = (string?)null, bannerImageData = (string?)null,
        activeSystemIds = Array.Empty<string>(), externalContacts = Array.Empty<object>(), activityWindows = Array.Empty<object>(),
        roleGroups = Array.Empty<object>(), memberPermissions = Array.Empty<object>(),
        members = new[] { new { accountId = "owner-id", gameName = "Owner", callsign = "Owner", roleTitle = "负责人",
            online = true, liveStatus = "AppOnline", ship = (string?)null, location = (string?)null,
            lastUpdated = DateTimeOffset.UtcNow, joinedAt = DateTimeOffset.UtcNow, arrivalPendingConfirmation = false,
            arrivalTargetCode = (string?)null, avatarImageData = (string?)null } },
        applications = new[] { new { id = "application-private-id", applicantGameName = "申请者", applicantCallsign = "Pilot",
            applicantAccount = "applicant-account", message = "希望加入", status = "Pending",
            createdAt = DateTimeOffset.UtcNow, avatarImageData = Pixel } },
        invites = Enumerable.Range(0, 21).Select(index => new
        {
            id = "invite-private-id-" + index,
            code = index == 20 ? "VISIBLE-CODE" : "OTHER-" + index,
            createdBy = index == 20 ? "Owner" : "Manager",
            createdByAccount = index == 20 ? "owner-login" : "manager-id",
            createdAt = DateTimeOffset.UtcNow.AddMinutes(-index),
            expiresAt = DateTimeOffset.UtcNow.AddDays(7),
            maxUses = 1, usedCount = 0, status = "Active", acceptMode = "Direct"
        }).ToArray()
    };

    private static JsonElement Query(string targetRef, string section) => Element(new
        { schemaVersion = 1, targetRef, section, offset = 0 });
    private static JsonElement Intent(string targetRef, string action, string? entryRef) => Element(new
        { schemaVersion = 1, requestId = Guid.NewGuid().ToString("N"), targetRef, action, entryRef, confirmUncertainRetry = false });
    private static JsonElement Element(object value) => JsonSerializer.SerializeToElement(value);
    private static HttpResponseMessage Json(object value) => new(HttpStatusCode.OK) { Content = JsonContent.Create(value) };
    private static void Check(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
    private static async Task Error(Func<Task<object>> action, string expected)
    {
        try { await action(); throw new InvalidOperationException("Expected " + expected); }
        catch (AccountBridgeHostException error) when (error.Code == expected) { }
    }
    private sealed class Handler(Func<HttpRequestMessage, HttpResponseMessage> send) : HttpMessageHandler
    {
        internal int Reads;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            if (request.Method == HttpMethod.Get) Reads++;
            return Task.FromResult(send(request));
        }
    }
}
