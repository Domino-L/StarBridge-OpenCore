using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;

internal static class CommunityAdmissionsClientTests
{
    internal static async Task Verify()
    {
        using var handler = new Handler();
        using var client = new CommunityClient(new Uri("https://community.invalid"), handler);
        var directory = await client.ReadAsync("bearer", new("mine", "", null, null), "account:1", default);
        var target = directory.Items.Single().TargetRef;
        JsonElement Body(string section = "applications") => JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = target, section, offset = 0 });
        async Task<JsonElement> Read(string section = "applications", Action? current = null) => JsonSerializer.SerializeToElement(
            await client.ReadAdmissionsAsync("bearer", Body(section), "account:1", current ?? (() => { }), default));
        var apps = await Read();
        var entry = apps.GetProperty("items")[0];
        var reference = entry.GetProperty("entryRef").GetString()!;
        Check(reference.Length == 32 && entry.GetProperty("message").GetString() == "Joining\nmessage", "opaque application references and multiline messages");
        Check(!apps.GetRawText().Contains("server-app-id") && !apps.GetRawText().Contains("secret-owner"), "raw IDs and unexpected account data never cross Bridge");
        var calls = handler.Calls;
        await Error(() => client.ReadAdmissionsAsync("bearer", Body(), "account:2", () => { }, default), "communities.refreshRequired");
        Check(handler.Calls == calls, "cross-account target fails before network request");
        var invites = await Read("invites");
        Check(invites.GetProperty("items")[0].GetProperty("code").GetString() == "VISIBLE-CODE", "authorized invite code is available for copying");
        Check(!invites.GetProperty("currentInviteAvailable").GetBoolean(), "old server response cannot assert there is no current invite");
        foreach (var mode in new[] { "current-on-page", "current-off-page", "current-none" })
        {
            handler.Mode = mode;
            var result = await Read("invites");
            Check(result.GetProperty("currentInviteAvailable").GetBoolean(), "current-invite capability is explicit");
            var own = result.GetProperty("currentInvite");
            if (mode == "current-none") Check(own.ValueKind == JsonValueKind.Null, "confirmed missing invite stays null");
            else {
                Check(own.GetProperty("code").GetString() == "VISIBLE-CODE" && !own.GetRawText().Contains("server-invite-id"), "own code uses opaque reference");
                Check(result.GetProperty("items").GetArrayLength() == (mode == "current-off-page" ? 20 : 1), "extra own code does not expand bounded page");
                if (mode == "current-on-page") Check(own.GetProperty("entryRef").GetString() == result.GetProperty("items")[0].GetProperty("entryRef").GetString(), "same row reuses reference");
            }
        }
        foreach (var mode in new[] { "current-not-own", "current-bad-offset", "current-conflict" }) {
            handler.Mode = mode;
            await Error(async () => await Read("invites"), "communities.dataInvalid");
        }
        handler.Mode = "ok";
        JsonElement Media(string entryRef) => JsonSerializer.SerializeToElement(new {
            schemaVersion = 1, targetRef = target, kind = "applicant", memberRef = entryRef, offset = 0 });
        var media = JsonSerializer.SerializeToElement(await client.ReadMediaAsync("bearer", Media(reference), "account:1", default));
        Check(media.GetProperty("memberRef").GetString() == reference && !media.GetRawText().Contains("server-app-id"), "avatar result retains only scoped reference");
        await Error(() => client.ReadMediaAsync("bearer", Media(invites.GetProperty("items")[0].GetProperty("entryRef").GetString()!), "account:1", default), "communities.refreshRequired");
        client.InvalidateInvitePreviews();
        await Error(() => client.ReadMediaAsync("bearer", Media(reference), "account:1", default), "communities.refreshRequired");
        foreach (var mode in new[] { "wrong-code", "wrong-section", "wrong-next", "denied-flags", "extra-section", "duplicate", "too-many", "bad-status", "bad-json", "huge" })
        {
            handler.Mode = mode;
            await Error(async () => await Read(), "communities.dataInvalid");
        }
        foreach (var (mode, error) in new[] { ("403", "notAllowed"), ("401", "identityUnavailable"), ("500", "unavailable") })
        {
            handler.Mode = mode;
            await Error(async () => await Read(), "communities." + error);
        }
        handler.Mode = "hold";
        var active = true;
        var pending = Read(current: () => { if (!active) throw new AccountBridgeHostException("communities.identityUnavailable"); });
        await handler.Entered.Task;
        active = false;
        client.InvalidateInvitePreviews();
        handler.Release.SetResult();
        await Error(async () => await pending, "communities.identityUnavailable");
        Check(handler.Writes == 0, "management read capability never issues mutations");
    }

    private sealed class Handler : HttpMessageHandler
    {
        internal string Mode = "ok";
        internal int Calls, Writes;
        internal readonly TaskCompletionSource Entered = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource Release = new(TaskCreationOptions.RunContinuationsAsynchronously);
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Calls++;
            if (request.Method != HttpMethod.Get) Writes++;
            Check(request.Headers.Authorization?.Parameter == "bearer", "only supplied SCM bearer is used");
            if (request.RequestUri!.AbsolutePath == "/api/fleets/directory") return Reply(new {
                schemaVersion = 1, membershipModelVersion = 2, view = "mine", query = "", next = (string?)null,
                items = new[] { new { code = "A", name = "Organization A", description = "", language = "", activeTime = "", memberCount = 1,
                    relationship = "owner", joinMode = "direct", actions = Array.Empty<string>() } } });
            if (request.RequestUri.AbsolutePath == "/api/fleets/media")
            {
                Check(request.RequestUri.Query.Contains("kind=applicant") && request.RequestUri.Query.Contains("memberId=server-app-id"), "avatar target resolved by Host");
                return Reply(new { schemaVersion = 1, kind = "applicant", memberId = "server-app-id", version = new string('a', 64),
                    mimeType = "image/png", totalBytes = 3, offset = 0, next = (int?)null, data = "AAAA" });
            }
            Check(request.RequestUri.AbsolutePath == "/api/fleets/admissions" && request.RequestUri.Query.Contains("code=A"), "only narrow target-scoped route");
            if (Mode == "hold") { Entered.SetResult(); await Release.Task; }
            if (int.TryParse(Mode, out var status)) return new((HttpStatusCode)status);
            if (Mode is "bad-json" or "huge") return new(HttpStatusCode.OK) { Content = new StringContent(Mode == "bad-json" ? "{" : new string('x', 1000000)) };
            var section = request.RequestUri.Query.Contains("section=invites") ? "invites" : "applications";
            object application = new { applicationId = "server-app-id", gameName = "Applicant", callsign = "Callsign", message = "Joining\nmessage",
                status = Mode == "bad-status" ? "Accepted" : "Pending", createdAt = DateTimeOffset.UtcNow, hasAvatar = true, privateAccount = "secret-owner" };
            object invitation = new { inviteId = "server-invite-id", code = "VISIBLE-CODE", createdBy = "Owner", createdAt = DateTimeOffset.UtcNow,
                expiresAt = DateTimeOffset.UtcNow.AddDays(1), maxUses = 3, usedCount = 0, status = "Active", isOwn = true, canRevoke = true };
            var body = new {
                schemaVersion = 1, membershipModelVersion = 2, code = Mode == "wrong-code" ? "B" : "A",
                section = Mode == "wrong-section" ? "invites" : section, offset = 0,
                next = Mode == "wrong-next" ? 20 : (int?)null, totalCount = Mode == "duplicate" ? 2 : 1,
                applications = section == "applications" ? Enumerable.Repeat(application, Mode == "duplicate" ? 2 : Mode == "too-many" ? 21 : 1).ToArray() : Array.Empty<object>(),
                invites = section == "invites" || Mode == "extra-section" ? new[] { invitation } : Array.Empty<object>(),
                access = new { canReadApplications = Mode != "denied-flags", canDecideApplications = true,
                    canReadInvites = true, canCreateInvite = true, canSendInvitationCard = true }, fetchedAt = DateTimeOffset.UtcNow };
            if (!Mode.StartsWith("current-", StringComparison.Ordinal)) return Reply(body);
            var projected = JsonSerializer.SerializeToNode(body)!;
            var ownNode = JsonSerializer.SerializeToNode(invitation)!;
            projected["currentInvite"] = Mode == "current-none" ? null : ownNode;
            projected["currentInviteOffset"] = Mode == "current-none" ? null : JsonValue.Create(0);
            if (Mode == "current-off-page") {
                projected["invites"] = new JsonArray(Enumerable.Range(0, 20).Select(index => {
                    var row = ownNode.DeepClone();
                    row["inviteId"] = "other-" + index;
                    row["isOwn"] = false;
                    return row;
                }).ToArray());
                projected["totalCount"] = 21;
                projected["next"] = 20;
                projected["currentInviteOffset"] = 20;
            }
            if (Mode == "current-not-own") ownNode["isOwn"] = false;
            if (Mode == "current-bad-offset") projected["currentInviteOffset"] = 3;
            if (Mode == "current-conflict") ownNode["code"] = "CONFLICT";
            return Reply(projected);
        }
        private static HttpResponseMessage Reply(object body) => new(HttpStatusCode.OK) { Content = JsonContent.Create(body) };
    }
    private static async Task Error(Func<Task<object>> run, string expected)
    {
        try { await run(); throw new InvalidOperationException("Expected " + expected); }
        catch (AccountBridgeHostException e) when (e.Code == expected) { }
    }
    private static void Check(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
}
