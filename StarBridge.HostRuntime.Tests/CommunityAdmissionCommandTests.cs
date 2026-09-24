using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;

internal static class CommunityAdmissionCommandTests
{
    internal static async Task Verify()
    {
        foreach (var action in new[] { "approve", "decline", "generateInvite", "revokeInvite" })
        {
            using var handler = new Handler();
            using var client = new CommunityClient(new Uri("https://community.invalid"), handler);
            var target = (await client.ReadAsync("bearer", new("mine", "", null, null), "account:1", default)).Items.Single().TargetRef;
            var section = action is "approve" or "decline" ? "applications" : "invites";
            async Task<string> Entry() => JsonSerializer.SerializeToElement(await client.ReadAdmissionsAsync("bearer",
                JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = target, section, offset = 0 }), "account:1", () => { }, default))
                .GetProperty("items")[0].GetProperty("entryRef").GetString()!;
            var entry = await Entry();
            var body = Body(action, target, entry);
            Task<CommunityCommand> Send(JsonElement data, string scope = "account:1", Action? current = null) =>
                client.ManageAdmissionsAsync("bearer", data, scope, current ?? (() => { }), default);
            Check((await Send(body, "other")).Status == "rejected" && handler.Writes == 0, "foreign account cannot resolve target");
            handler.Denied = true;
            Check((await Send(Body(action, target, entry))).Error == "notAllowed" && handler.Writes == 0, "fresh permission loss rejects before POST");
            handler.Denied = false;
            if (action != "generateInvite")
            {
                handler.Missing = true;
                Check((await Send(Body(action, target, entry))).Error == "refreshRequired" && handler.Writes == 0, "removed or moved row is never substituted");
                handler.Missing = false;
            }
            var receipt = await Send(body);
            Check(receipt.Status == "accepted" && handler.Writes == 1, action + " sends exactly one write");
            Check((await Send(body)) == receipt && handler.Writes == 1, "same intent reuses receipt");
            var changed = JsonSerializer.Deserialize<Dictionary<string, object?>>(body)!;
            changed["confirmUncertainRetry"] = true;
            Check((await Send(JsonSerializer.SerializeToElement(changed))).Error == "requestChanged" && handler.Writes == 1, "same ID cannot change intent");
            Check(!JsonSerializer.Serialize(receipt).Contains("secret"), "bulk server snapshot never crosses bridge");
            Check(handler.LastBody!.Value.GetProperty("fleetCode").GetString() == "A", "Host resolves organization rather than caller code");
            if (action == "generateInvite")
                Check(handler.LastBody.Value.GetProperty("maxUses").GetInt32() == 1 && handler.LastBody.Value.GetProperty("purpose").GetString() == "code", "WPF invite defaults and code policy");
            else if (section == "applications")
                Check(handler.LastBody.Value.GetProperty("approve").GetBoolean() == (action == "approve") && handler.LastBody.Value.GetProperty("applicationId").GetString() == "server-app", "decision resolves exact application");
            else Check(handler.LastBody.Value.GetProperty("inviteId").GetString() == "server-invite", "revoke resolves exact invite");

            handler.Mode = "lost";
            var uncertainBody = Body(action, target, entry);
            Check((await Send(uncertainBody)).Status == "unknown" && handler.Writes == 2, "lost response is never claimed rejected");
            Check((await Send(uncertainBody)).Status == "unknown" && handler.Writes == 2, "lost reply replay does not resend");
            Check((await Send(Body(action, target, entry))).Status == "unknown" && handler.Writes == 2, "new ID alone does not repeat uncertain operation");
            handler.Mode = "ok";
            Check((await Send(Body(action, target, entry, true))).Status == "accepted" && handler.Writes == 3, "explicit new confirmation rechecks permission and can retry");
            handler.Mode = "403";
            Check((await Send(Body(action, target, entry))).Error == "notAllowed", "server remains final authority after preflight");
            handler.Mode = "500";
            Check((await Send(Body(action, target, entry))).Status == "unknown", "server failure may follow a committed mutation");
            client.InvalidateInvitePreviews();
            if (action != "generateInvite")
                Check((await Send(Body(action, target, entry))).Error == "refreshRequired", "invalidation removes stale row capabilities");
        }
        await VerifyConcurrentAndLate();
        await VerifyCurrentInviteOutsidePage();
        foreach (var changes in new[] {
            new Dictionary<string, object?> { ["maxUses"] = 51 },
            new Dictionary<string, object?> { ["expiresInDays"] = 0 },
            new Dictionary<string, object?> { ["fleetCode"] = "B" },
            new Dictionary<string, object?> { ["requestId"] = "raw" },
            new Dictionary<string, object?> { ["entryRef"] = new string('a', 32) },
            new Dictionary<string, object?> { ["confirmUncertainRetry"] = "true" } })
        {
            var fields = JsonSerializer.Deserialize<Dictionary<string, object?>>(Body("generateInvite", new string('a', 32), "unused"))!;
            foreach (var change in changes) fields[change.Key] = change.Value;
            try { CommunityClient.ParseAdmissionIntent(JsonSerializer.SerializeToElement(fields)); throw new InvalidOperationException("Invalid intent accepted"); }
            catch (AccountBridgeHostException error) when (error.Code == "communities.dataInvalid") { }
        }
    }

    private static async Task VerifyConcurrentAndLate()
    {
        using var handler = new Handler { Mode = "hold" };
        using var client = new CommunityClient(new Uri("https://community.invalid"), handler);
        var target = (await client.ReadAsync("bearer", new("mine", "", null, null), "account:1", default)).Items.Single().TargetRef;
        var active = true;
        void Current() { if (!active) throw new AccountBridgeHostException("communities.identityUnavailable"); }
        var first = client.ManageAdmissionsAsync("bearer", Body("generateInvite", target, "unused"), "account:1", Current, default);
        await handler.Entered.Task;
        Check((await client.ManageAdmissionsAsync("bearer", Body("generateInvite", target, "unused"), "account:1", Current, default)).Error == "busy", "parallel click shares write gate");
        active = false;
        client.InvalidateInvitePreviews();
        handler.Release.SetResult();
        Check((await first).Status == "unknown" && handler.Writes == 1, "late reply cannot be accepted into changed account");
    }
    private static async Task VerifyCurrentInviteOutsidePage()
    {
        using var handler = new Handler { Mode = "own-off-page" };
        using var client = new CommunityClient(new Uri("https://community.invalid"), handler);
        var target = (await client.ReadAsync("bearer", new("mine", "", null, null), "account:1", default)).Items.Single().TargetRef;
        var page = JsonSerializer.SerializeToElement(await client.ReadAdmissionsAsync("bearer",
            JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = target, section = "invites", offset = 0 }), "account:1", () => { }, default));
        var reference = page.GetProperty("currentInvite").GetProperty("entryRef").GetString()!;
        Check(page.GetProperty("items").GetArrayLength() == 20, "current code is independent of first page");
        var result = await client.ManageAdmissionsAsync("bearer", Body("revokeInvite", target, reference), "account:1", () => { }, default);
        Check(result.Status == "accepted" && handler.LastReadOffset == 20 && handler.Writes == 1 &&
            handler.LastBody!.Value.GetProperty("inviteId").GetString() == "server-invite", "revoke preflight follows actual current-code page and exact server ID");
    }
    private static JsonElement Body(string action, string target, string entry, bool retry = false)
    {
        var fields = new Dictionary<string, object?> { ["schemaVersion"] = 1, ["requestId"] = Guid.NewGuid().ToString("N"),
            ["targetRef"] = target, ["action"] = action, ["confirmUncertainRetry"] = retry };
        if (action == "generateInvite") { fields["expiresInDays"] = 7; fields["maxUses"] = 1; }
        else fields["entryRef"] = entry;
        return JsonSerializer.SerializeToElement(fields);
    }
    private sealed class Handler : HttpMessageHandler
    {
        internal bool Denied, Missing;
        internal string Mode = "ok";
        internal int Writes;
        internal int LastReadOffset;
        internal JsonElement? LastBody;
        internal readonly TaskCompletionSource Entered = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource Release = new(TaskCreationOptions.RunContinuationsAsynchronously);
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Check(request.Headers.Authorization?.Parameter == "bearer", "bearer preserved");
            var path = request.RequestUri!.AbsolutePath;
            if (request.Method == HttpMethod.Post)
            {
                Writes++;
                Check(path is "/api/fleets/applications/decide" or "/api/fleets/invites" or "/api/fleets/invites/revoke", "only existing WPF writes");
                LastBody = JsonSerializer.Deserialize<JsonElement>(await request.Content!.ReadAsStringAsync(token));
                if (Mode == "lost") throw new HttpRequestException("Lost after sending");
                if (Mode == "hold") { Entered.SetResult(); await Release.Task; }
                if (int.TryParse(Mode, out var status)) return new((HttpStatusCode)status);
                return Reply(new { privateSnapshot = "secret", arbitrary = new string('x', 1000000) });
            }
            if (path == "/api/fleets/directory") return Reply(new {
                schemaVersion = 1, membershipModelVersion = 2, view = "mine", query = "", next = (string?)null,
                items = new[] { new { code = "A", name = "Organization A", description = "", language = "", activeTime = "", memberCount = 1,
                    relationship = "owner", joinMode = "direct", actions = Array.Empty<string>() } } });
            Check(path == "/api/fleets/admissions", "preflight uses narrow page");
            var section = request.RequestUri.Query.Contains("section=applications") ? "applications" : "invites";
            var body = new { schemaVersion = 1, membershipModelVersion = 2, code = "A", section, offset = 0, next = (int?)null,
                totalCount = Missing ? 0 : 1,
                applications = section == "applications" && !Missing ? new object[] { new { applicationId = "server-app", gameName = "Applicant", callsign = "Call", message = "Hello", status = "Pending", createdAt = (string?)null, hasAvatar = false } } : [],
                invites = section == "invites" && !Missing ? new object[] { new { inviteId = "server-invite", code = "CODE", createdBy = "Owner", createdAt = (string?)null, expiresAt = (string?)null, maxUses = 1, usedCount = 0, status = "Active", isOwn = true, canRevoke = !Denied } } : [],
                access = new { canReadApplications = true, canDecideApplications = !Denied, canReadInvites = true, canCreateInvite = !Denied, canSendInvitationCard = true }, fetchedAt = DateTimeOffset.UtcNow };
            if (Mode != "own-off-page") return Reply(body);
            LastReadOffset = request.RequestUri.Query.Contains("offset=20") ? 20 : 0;
            var projected = JsonSerializer.SerializeToNode(body)!;
            var own = projected["invites"]![0]!.DeepClone();
            projected["currentInvite"] = own;
            projected["currentInviteOffset"] = 20;
            projected["totalCount"] = 21;
            projected["offset"] = LastReadOffset;
            projected["next"] = LastReadOffset == 0 ? JsonValue.Create(20) : null;
            if (LastReadOffset == 0) projected["invites"] = new JsonArray(Enumerable.Range(0, 20).Select(index => {
                var other = own.DeepClone();
                other["inviteId"] = "other-" + index;
                other["isOwn"] = false;
                return other;
            }).ToArray());
            return Reply(projected);
        }
        private static HttpResponseMessage Reply(object body) => new(HttpStatusCode.OK) { Content = JsonContent.Create(body) };
    }
    private static void Check(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
}
