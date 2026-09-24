using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Communities;

internal static class CommunityWpfS2ProfileTests
{
    internal static async Task Verify()
    {
        using var handler = new Handler();
        using var client = new CommunityClient(new Uri("https://legacy.invalid"), handler);
        const string scope = "legacy-profile";
        const string viewer = "self";
        var target = (await client.ReadWpfS2Async("legacy", new("mine", "", null, null), scope, viewer, default))
            .Items.Single().TargetRef;
        var read = JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = target });
        var profile = JsonSerializer.SerializeToElement(await client.ReadWpfS2ProfileAsync(
            "legacy", read, scope, viewer, default));
        Check(profile.GetProperty("profileRevision").GetInt64() == 4 &&
              profile.GetProperty("profile").GetProperty("description").GetString() == "Before" &&
              profile.GetProperty("access").GetProperty("canEditProfile").GetBoolean(),
            "S2 profile editor projects the original fleet snapshot and exact permission");

        var editRef = profile.GetProperty("editRef").GetString()!;
        var requestId = Guid.NewGuid().ToString("N");
        var command = JsonSerializer.SerializeToElement(new
        {
            schemaVersion = 1,
            requestId,
            editRef,
            changes = new { description = "After", recruitingEnabled = true }
        });
        var saved = await client.SaveWpfS2ProfileAsync("legacy", command, scope, viewer, () => { }, default);
        Check(saved.Status == "accepted" && saved.ProfileRevision == 5 && handler.Writes == 1,
            "S2 profile save accepts the original full update response");
        Check(handler.OriginalRoute && handler.PreservedUntouchedFields && handler.ExpectedRevision == 4,
            "S2 profile save uses the original route and preserves untouched WPF fields");
        saved = await client.SaveWpfS2ProfileAsync("legacy", command, scope, viewer, () => { }, default);
        Check(saved.Status == "accepted" && handler.Writes == 1, "confirmed S2 profile request is not replayed");
        var changed = JsonSerializer.SerializeToElement(new
        {
            schemaVersion = 1,
            requestId,
            editRef,
            changes = new { description = "Changed intent" }
        });
        saved = await client.SaveWpfS2ProfileAsync("legacy", changed, scope, viewer, () => { }, default);
        Check(saved.Status == "rejected" && saved.Error == "requestChanged" && handler.Writes == 1,
            "S2 profile request id cannot be rebound to another draft");

        profile = JsonSerializer.SerializeToElement(await client.ReadWpfS2ProfileAsync(
            "legacy", read, scope, viewer, default));
        handler.Revision++;
        saved = await client.SaveWpfS2ProfileAsync("legacy", Command(profile, "Stale"), scope, viewer, () => { }, default);
        Check(saved.Status == "rejected" && saved.Error == "conflict" && handler.Writes == 1,
            "S2 profile revision changes are rejected before a write");

        handler.Revision--;
        profile = JsonSerializer.SerializeToElement(await client.ReadWpfS2ProfileAsync(
            "legacy", read, scope, viewer, default));
        handler.Allowed = false;
        saved = await client.SaveWpfS2ProfileAsync("legacy", Command(profile, "Denied"), scope, viewer, () => { }, default);
        Check(saved.Status == "rejected" && saved.Error == "notAllowed" && handler.Writes == 1,
            "S2 profile permission is rechecked before every write");
        handler.Allowed = true;

        profile = JsonSerializer.SerializeToElement(await client.ReadWpfS2ProfileAsync(
            "legacy", read, scope, viewer, default));
        handler.Mode = "lost";
        var uncertain = Command(profile, "Uncertain");
        saved = await client.SaveWpfS2ProfileAsync("legacy", uncertain, scope, viewer, () => { }, default);
        var writes = handler.Writes;
        Check(saved.Status == "unknown", "lost S2 profile response remains unknown");
        saved = await client.SaveWpfS2ProfileAsync("legacy", uncertain, scope, viewer, () => { }, default);
        Check(saved.Status == "unknown" && handler.Writes == writes, "uncertain S2 profile write is never replayed");
    }

    private static JsonElement Command(JsonElement profile, string description) => JsonSerializer.SerializeToElement(new
    {
        schemaVersion = 1,
        requestId = Guid.NewGuid().ToString("N"),
        editRef = profile.GetProperty("editRef").GetString(),
        changes = new { description }
    });

    private sealed class Handler : HttpMessageHandler
    {
        internal int Writes;
        internal long Revision = 4;
        internal long ExpectedRevision;
        internal bool Allowed = true;
        internal string Mode = "ok";
        internal bool OriginalRoute = true;
        internal bool PreservedUntouchedFields = true;

        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Check(request.Headers.Authorization?.Parameter == "legacy", "S2 profile requests retain the legacy bearer");
            var path = request.RequestUri!.AbsolutePath;
            if (request.Method == HttpMethod.Get)
                return path switch
                {
                    "/api/fleets/membership" => Reply(new { fleetCode = "A" }),
                    "/api/fleets" => Reply(new[] { Fleet() }),
                    "/api/auth/session" => Reply(new { accountId = "self", userName = "self-user" }),
                    _ => throw new InvalidOperationException("Unexpected GET " + path)
                };
            Check(path == "/api/fleets/info", "S2 profile writes only the original fleet info route");
            Writes++;
            OriginalRoute &= request.RequestUri.Query.Length == 0;
            using var body = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
            ExpectedRevision = body.RootElement.GetProperty("expectedProfileRevision").GetInt64();
            PreservedUntouchedFields &= body.RootElement.GetProperty("type").GetString() == "PVP" &&
                body.RootElement.GetProperty("activeSystemIds").EnumerateArray().Single().GetString() == "stanton" &&
                body.RootElement.GetProperty("roleGroups").GetArrayLength() == 1 &&
                body.RootElement.GetProperty("updatedSections").EnumerateArray().Select(row => row.GetString())
                    .Order().SequenceEqual(new[] { "description", "profile" });
            Description = body.RootElement.GetProperty("description").GetString()!;
            Revision++;
            if (Mode == "lost") throw new HttpRequestException("lost profile response");
            return Reply(Fleet());
        }

        private string Description = "Before";
        private object Fleet() => new
        {
            name = "Organization", code = "A", commander = "Owner", ownerAccount = "other-owner",
            totalMembers = 2, members = new[] { new { accountId = "self" }, new { accountId = "member" } },
            memberPermissions = new[] { new { accountId = "self", permissionEnabled = Allowed,
                canManageFleetInfo = Allowed, canRemoveMembers = false, canPublishTasks = false, canPublishPlans = false } },
            profileRevision = Revision, description = Description, type = "PVP", activeTime = "19:00 - 22:00",
            joinPolicy = "Open", logoText = "A", logoImageData = (string?)null, bannerImageData = (string?)null,
            emailNotificationsEnabled = true, activityWindows = Array.Empty<object>(), activeDaysDescription = "",
            activityCadence = "Casual", timeZoneId = "UTC", recruitingEnabled = false, recruitingTarget = "",
            recruitingNote = "", roleGroups = new[] { new { id = "base", displayName = "Member" } },
            publicListingEnabled = true, publicMemberScaleMode = "Exact", publicShipScaleMode = "TypeSummary",
            publicProfileEnabled = true, publicShowDescription = true, publicShowTags = true,
            publicShowActiveSystems = true, publicShowActivityTime = true, publicShowExternalContacts = false,
            activeSystemIds = new[] { "stanton" }, language = "zh-CN", websiteUrl = "",
            externalContacts = Array.Empty<object>(), inviteCodeCreationPolicy = "management",
            fleetInvitationCardPolicy = "all_members", invites = Array.Empty<object>()
        };

        private static HttpResponseMessage Reply(object value) =>
            new(HttpStatusCode.OK) { Content = JsonContent.Create(value) };
    }

    private static void Check(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }
}
