using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;

internal static class CommunityWorkspaceClientTests
{
    internal static async Task Verify()
    {
        var calls = 0;
        var state = "ok";
        string? mediaQuery = null;
        using var handler = new Handler(request =>
        {
            calls++;
            Check(request.Method == HttpMethod.Get && request.Headers.Authorization?.Parameter == "test-bearer", "read-only supplied bearer");
            var path = request.RequestUri!.AbsolutePath;
            if (path == "/api/fleets/directory") return new(HttpStatusCode.OK) { Content = JsonContent.Create(new
            {
                schemaVersion = 1, membershipModelVersion = 2, view = "mine", query = "", next = (string?)null,
                items = new[] { "A", "B" }.Select(code => new { code, name = "Organization " + code, description = "", language = "", activeTime = "",
                    memberCount = 1, relationship = "member", joinMode = "direct", actions = new[] { "leave" }, logoImageData = (string?)null })
            }) };
            if (state == "forbidden") return new(HttpStatusCode.Forbidden);
            if (path == "/api/fleets/media")
            {
                mediaQuery = Uri.UnescapeDataString(request.RequestUri.Query);
                return new(HttpStatusCode.OK) { Content = JsonContent.Create(new
                {
                    schemaVersion = 1, kind = "avatar", memberId = "account:member-one", version = new string('a', 64), mimeType = "image/png",
                    totalBytes = 1, offset = 0, next = (int?)null, data = state == "bad-media" ? "!" : "AQ=="
                }) };
            }
            Check(path == "/api/fleets/workspace", "never requests legacy bulk snapshots");
            var payload = Workspace();
            if (state == "main-menu") payload["members"]![0]!["hasServerSession"] = false;
            if (state == "invalid-session") payload["members"]![0]!["hasServerSession"] = "false";
            if (state == "central-zone") payload["timeZoneId"] = "Central America Standard Time";
            if (state == "unknown-zone") payload["timeZoneId"] = "unknown-test-zone";
            if (state == "different-member") payload["members"]![0]!["memberId"] = "account:member-two";
            if (state == "wrong-code") payload["code"] = "B";
            if (state == "wrong-page") payload["next"] = 20;
            if (state == "invalid-color") payload["members"]![0]!["roleColor"] = "bogus";
            if (state == "missing") payload.AsObject().Remove("access");
            if (state == "legacy-access") payload["access"]!.AsObject().Remove("canViewLogs");
            if (state == "invalid-log-access") payload["access"]!["canViewLogs"] = "true";
            if (state == "big") payload["description"] = new string('x', 1000000);
            return new(HttpStatusCode.OK) { Content = JsonContent.Create(payload) };
        });
        using var client = new CommunityClient(new Uri("https://community.invalid"), handler);
        var directory = await client.ReadAsync("test-bearer", new("mine", "", null, null), "one", default);
        var a = directory.Items[0].TargetRef;
        var b = directory.Items[1].TargetRef;
        var query = JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = a, query = "", offset = 0 });
        var response = JsonSerializer.SerializeToElement(await client.ReadWorkspaceAsync("test-bearer", query, "one", default));
        var member = response.GetProperty("members")[0];
        var memberRef = member.GetProperty("memberRef").GetString()!;
        Check(member.GetProperty("hasServerSession").ValueKind == JsonValueKind.Null, "absent session stays unknown, not false");
        state = "main-menu";
        var mainMenu = JsonSerializer.SerializeToElement(await client.ReadWorkspaceAsync("test-bearer", query, "one", default));
        Check(!mainMenu.GetProperty("members")[0].GetProperty("hasServerSession").GetBoolean(), "explicit no-server state survives the bridge");
        state = "ok";
        Check(memberRef.Length == 32 && member.GetProperty("gameName").GetString() == "", "opaque member ref does not reconstruct hidden game IDs");
        Check(!response.GetRawText().Contains("account:member-one") && !response.GetRawText().Contains("private-administration-data"), "whitelist excludes source identities and extra admin fields");
        Check(response.GetProperty("access").GetProperty("canEditLogo").GetBoolean() &&
            !response.GetProperty("access").GetProperty("canEditProfile").GetBoolean(), "logo-only editor entry preserves authoritative permission");
        Check(response.GetProperty("access").GetProperty("canViewLogs").GetBoolean(), "log entry preserves the server's explicit permission");
        state = "legacy-access";
        Check(response.GetProperty("timeZoneStandardOffsetMinutes").GetInt32() == 0, "UTC display offset");
        state = "central-zone";
        var zone = JsonSerializer.SerializeToElement(await client.ReadWorkspaceAsync("test-bearer", query, "one", default));
        Check(zone.GetProperty("timeZoneStandardOffsetMinutes").GetInt32() == -360 &&
            !zone.GetProperty("timeZoneUsesDaylightSaving").GetBoolean(), "Central America retains UTC minus six without DST");
        state = "unknown-zone";
        zone = JsonSerializer.SerializeToElement(await client.ReadWorkspaceAsync("test-bearer", query, "one", default));
        Check(!zone.TryGetProperty("timeZoneStandardOffsetMinutes", out _), "unknown zone does not invent an offset or reject the workspace");
        state = "legacy-access";
        var legacy = JsonSerializer.SerializeToElement(await client.ReadWorkspaceAsync("test-bearer", query, "one", default));
        Check(legacy.GetProperty("members")[0].GetProperty("memberRef").GetString() == memberRef,
            "validated rereads reuse the same scoped member reference for incremental avatar caching");
        Check(!legacy.GetProperty("access").GetProperty("canViewLogs").GetBoolean(), "missing legacy permission does not grant log access");
        state = "ok";
        var media = JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = a, kind = "avatar", memberRef, offset = 0 });
        var chunk = JsonSerializer.SerializeToElement(await client.ReadMediaAsync("test-bearer", media, "one", default));
        Check(chunk.GetProperty("memberRef").GetString() == memberRef && !chunk.GetRawText().Contains("account:member-one") &&
            mediaQuery!.Contains("memberId=account:member-one"), "member reference resolves only inside the Host");
        state = "different-member";
        var otherMember = JsonSerializer.SerializeToElement(await client.ReadWorkspaceAsync("test-bearer", query, "one", default));
        Check(otherMember.GetProperty("members")[0].GetProperty("memberRef").GetString() != memberRef,
            "different identities with the same callsign never share an avatar reference");
        state = "ok";
        var otherDirectory = await client.ReadAsync("test-bearer", new("mine", "", null, null), "two", default);
        var otherQuery = JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = otherDirectory.Items[0].TargetRef, query = "", offset = 0 });
        var otherScope = JsonSerializer.SerializeToElement(await client.ReadWorkspaceAsync("test-bearer", otherQuery, "two", default));
        Check(otherScope.GetProperty("members")[0].GetProperty("memberRef").GetString() != memberRef,
            "the same member in another account generation never reuses a reference");
        var before = calls;
        await Error(() => client.ReadWorkspaceAsync("test-bearer", query, "two", default), "communities.refreshRequired");
        await Error(() => client.ReadMediaAsync("test-bearer", JsonSerializer.SerializeToElement(new
            { schemaVersion = 1, targetRef = b, kind = "avatar", memberRef, offset = 0 }), "one", default), "communities.refreshRequired");
        await Error(() => client.ReadMediaAsync("test-bearer", JsonSerializer.SerializeToElement(new
            { schemaVersion = 1, targetRef = a, kind = "avatar", memberId = "account:member-one", offset = 0 }), "one", default), "communities.dataInvalid");
        Check(before == calls, "wrong account, wrong organization and injected raw identity never make HTTP requests");
        foreach (var failure in new[] { "wrong-code", "wrong-page", "invalid-color", "missing", "big", "invalid-log-access", "invalid-session" })
        {
            state = failure;
            await Error(() => client.ReadWorkspaceAsync("test-bearer", query, "one", default), "communities.dataInvalid");
        }
        state = "bad-media";
        await Error(() => client.ReadMediaAsync("test-bearer", media, "one", default), "communities.dataInvalid");
        state = "forbidden";
        await Error(() => client.ReadWorkspaceAsync("test-bearer", query, "one", default), "communities.notAllowed");
    }

    internal static JsonNode Workspace() => JsonSerializer.SerializeToNode(new
    {
        schemaVersion = 1, membershipModelVersion = 2, code = "A", name = "Organization A", description = "private contact details",
        tags = "探索", language = "English", activeTime = "22:00–02:00", timeZoneId = "UTC", websiteUrl = (string?)null,
        activityWindows = new[] { new { days = new[] { "mon" }, startTime = "22:00", endTime = "02:00", endsNextDay = true } },
        activeSystemIds = new[] { "stanton" }, externalContacts = new[] { new { platform = "contact", value = "private group" } },
        hasLogo = true, hasBanner = false, query = "", offset = 0, next = (int?)null, totalCount = 1, matchedCount = 1,
        fetchedAt = DateTimeOffset.UtcNow,
        access = new { isOwner = false, canEditProfile = false, canReviewApplications = false, canRemoveMembers = false, canCreateInvite = false, canManageAnnouncements = false, canEditLogo = true, canEditBanner = false, canViewLogs = true },
        members = new[] { new { memberId = "account:member-one", gameName = "", callsign = "Visible callsign", roleTitle = "成员", roleColor = "#00FF00",
            isSelf = false, isOwner = false, online = false, hasAvatar = true, liveStatus = "Offline", ship = "Unknown", location = "Unknown",
            locationConfidence = "None", serverRegion = (string?)null, serverShard = (string?)null, lastUpdated = (string?)null, joinedAt = (string?)null,
            arrivalPendingConfirmation = false, arrivalTargetCode = (string?)null } },
        administration = "private-administration-data"
    })!;
    private static async Task Error(Func<Task<object>> read, string code)
    {
        try { await read(); throw new InvalidOperationException("Expected " + code); }
        catch (AccountBridgeHostException e) when (e.Code == code) { }
    }
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
    private sealed class Handler(Func<HttpRequestMessage, HttpResponseMessage> read) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) => Task.FromResult(read(request));
    }
}
