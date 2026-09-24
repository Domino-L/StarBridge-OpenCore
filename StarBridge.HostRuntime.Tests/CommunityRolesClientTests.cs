using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;

internal static class CommunityRolesClientTests
{
    internal static async Task Verify()
    {
        await TransportAndReceipts();
        await LateReadAndWrite();
        ValidateDrafts();
    }

    private static async Task TransportAndReceipts()
    {
        var writes = 0;
        var reads = 0;
        var mode = "ok";
        JsonElement outgoing = default;
        using var handler = new Handler(async request =>
        {
            Check(request.Headers.Authorization?.Parameter == "test-bearer", "uses only current supplied bearer");
            if (request.RequestUri!.AbsolutePath == "/api/fleets/directory") return Reply(Directory());
            if (request.Method == HttpMethod.Get)
            {
                reads++;
                Check(request.RequestUri.PathAndQuery == "/api/fleets/roles?code=A", "read uses resolved target, never caller URL");
                if (mode == "forbidden") return new(HttpStatusCode.Forbidden);
                var source = Projection();
                if (mode == "wrong-code") source["code"] = "B";
                if (mode == "duplicate") source["roles"]!.AsArray().Add(source["roles"]![0]!.DeepClone());
                if (mode == "no-rights") source["access"]!["canEditRoles"] = false;
                if (mode == "large") source["unused"] = new string('x', 256 * 1024);
                return Reply(source);
            }
            writes++;
            Check(request.RequestUri.PathAndQuery == "/api/fleets/info?projection=roles", "existing WPF targeted write");
            outgoing = await request.Content!.ReadFromJsonAsync<JsonElement>();
            if (mode == "lost") throw new HttpRequestException("test connection lost");
            if (mode == "conflict") return new(HttpStatusCode.Conflict);
            if (mode == "unauthorized") return new(HttpStatusCode.Unauthorized);
            if (mode == "denied") return new(HttpStatusCode.Forbidden);
            if (mode == "invalid") return new(HttpStatusCode.BadRequest);
            if (mode == "missing") return new(HttpStatusCode.NotFound);
            if (mode == "server-error") return new(HttpStatusCode.InternalServerError);
            if (mode == "oversize") return Reply(new { schemaVersion = 1, status = "accepted", profileRevision = 8, unused = new string('x', 5000) });
            return Reply(new { schemaVersion = 1, status = "accepted", profileRevision = mode == "old-revision" ? 7 : 8 });
        });
        using var client = new CommunityClient(new Uri("https://community.invalid"), handler);
        var directory = await client.ReadAsync("test-bearer", new("mine", "", null, null), "A:1", default);
        var query = JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = directory.Items[0].TargetRef });
        async Task<JsonElement> Read() => JsonSerializer.SerializeToElement(await client.ReadRolesAsync("test-bearer", query, "A:1", Current, default));
        var snapshot = await Read();
        Check(!snapshot.GetRawText().Contains("do-not-forward") && !snapshot.GetProperty("access").GetProperty("canAssignMembers").GetBoolean(),
            "only bounded role projection crosses Bridge; definition editor need not be owner");
        Check(snapshot.GetProperty("roles")[2].GetProperty("permissions")[1].GetString() == "future.preserved", "hidden permission IDs retained");
        var command = Command(snapshot);
        var accepted = await client.SaveRolesAsync("test-bearer", command, "A:1", Current, default);
        Check(accepted.Status == "accepted" && accepted.ProfileRevision == 8 && writes == 1, "storage receipt accepted");
        Check(outgoing.EnumerateObject().Count() == 4 && outgoing.GetProperty("fleetCode").GetString() == "A" &&
            outgoing.GetProperty("expectedProfileRevision").GetInt64() == 7 && outgoing.GetProperty("updatedSections")[0].GetString() == "role-groups",
            "scope and version come from Host draft, no unrelated profile fields overwritten");
        Check(!outgoing.GetRawText().Contains("memberCount") && outgoing.GetProperty("roleGroups")[0].GetProperty("isSystem").GetBoolean(),
            "system identity is host-owned; counts never submitted");
        Check(await client.SaveRolesAsync("test-bearer", command, "A:1", Current, default) == accepted && writes == 1, "same intent returns receipt without replay");
        var changed = JsonNode.Parse(command.GetRawText())!;
        changed["roles"]![2]!["displayName"] = "Changed";
        Check((await client.SaveRolesAsync("test-bearer", Element(changed), "A:1", Current, default)).Error == "requestChanged" && writes == 1,
            "request ID cannot be reused with changed definitions");
        Check((await client.SaveRolesAsync("test-bearer", command, "B:1", Current, default)).Status == "rejected" && writes == 1, "account scope cannot reuse draft or receipt");

        var deletedSystem = JsonNode.Parse(Command(snapshot).GetRawText())!;
        deletedSystem["roles"]!.AsArray().RemoveAt(0);
        Check((await client.SaveRolesAsync("test-bearer", Element(deletedSystem), "A:1", Current, default)).Error == "invalidDraft" && writes == 1, "system seats cannot be removed");
        var ownerOverride = JsonNode.Parse(Command(snapshot).GetRawText())!;
        ownerOverride["roles"]![0]!["permissions"] = new JsonArray("members.remove");
        ownerOverride["roles"]![0]!["isEnabled"] = false;
        await client.SaveRolesAsync("test-bearer", Element(ownerOverride), "A:1", Current, default);
        Check(outgoing.GetProperty("roleGroups")[0].GetProperty("isEnabled").GetBoolean() &&
            outgoing.GetProperty("roleGroups")[0].GetProperty("permissions")[0].GetString() == "fleet.profile.edit", "owner grant is immutable");

        foreach (var pair in new[] { ("conflict", "conflict"), ("unauthorized", "identityUnavailable"), ("denied", "notAllowed"),
            ("invalid", "invalidDraft"), ("missing", "refreshRequired") })
        {
            mode = pair.Item1;
            var before = writes;
            var receipt = await client.SaveRolesAsync("test-bearer", Command(snapshot), "A:1", Current, default);
            Check(receipt.Status == "rejected" && receipt.Error == pair.Item2 && writes == before + 1, "HTTP error mapped without retry: " + mode);
        }
        foreach (var failure in new[] { "lost", "server-error", "oversize", "old-revision" })
        {
            mode = failure;
            var before = writes;
            var intent = Command(snapshot, confirm: true);
            var receipt = await client.SaveRolesAsync("test-bearer", intent, "A:1", Current, default);
            Check(receipt.Status == "unknown" && receipt.ProfileRevision is null && writes == before + 1, "unverified result is unknown: " + mode);
            Check((await client.SaveRolesAsync("test-bearer", intent, "A:1", Current, default)).Status == "unknown" && writes == before + 1,
                "same uncertain intent never replays");
            Check((await client.SaveRolesAsync("test-bearer", Command(snapshot), "A:1", Current, default)).Status == "unknown" && writes == before + 1,
                "new ID alone cannot bypass uncertain operation protection");
        }
        mode = "ok";
        snapshot = await Read();
        var writesBeforeRead = writes;
        Check((await client.SaveRolesAsync("test-bearer", Command(snapshot), "A:1", Current, default)).Status == "unknown" && writes == writesBeforeRead,
            "new edit reference at same revision cannot hide uncertain write");
        Check((await client.SaveRolesAsync("test-bearer", Command(snapshot, confirm: true), "A:1", Current, default)).Status == "accepted", "explicit uncertain retry allowed, version still checked");
        foreach (var pair in new[] { ("forbidden", "communities.notAllowed"), ("no-rights", "communities.notAllowed"),
            ("wrong-code", "communities.dataInvalid"), ("duplicate", "communities.dataInvalid"), ("large", "communities.dataInvalid") })
        {
            mode = pair.Item1;
            await Error(async () => await Read(), pair.Item2);
        }
        mode = "ok";
        var beforeRead = reads;
        await Error(() => client.ReadRolesAsync("test-bearer", query, "B:1", Current, default), "communities.refreshRequired");
        Check(reads == beforeRead, "cross-account read rejected before HTTP");
        client.InvalidateRolesEdits();
        var editQuery = JsonSerializer.SerializeToElement(new { schemaVersion = 1, editRef = snapshot.GetProperty("editRef").GetString() });
        await Error(() => client.ReadRolesAsync("test-bearer", editQuery, "A:1", Current, default), "communities.refreshRequired");
        Check((await client.SaveRolesAsync("test-bearer", Command(snapshot), "A:1", Current, default)).Status == "rejected", "invalidation clears editing authority");
    }

    private static async Task LateReadAndWrite()
    {
        var ready = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var pauseRead = false;
        var current = true;
        var writes = 0;
        void CheckCurrent() { if (!current) throw new AccountBridgeHostException("account.stale_generation"); }
        using var handler = new Handler(async request =>
        {
            if (request.RequestUri!.AbsolutePath == "/api/fleets/directory") return Reply(Directory());
            if (request.Method == HttpMethod.Get && !pauseRead) return Reply(Projection());
            if (request.Method == HttpMethod.Post) writes++;
            ready.SetResult();
            await release.Task;
            return request.Method == HttpMethod.Get ? Reply(Projection()) : Reply(new { schemaVersion = 1, status = "accepted", profileRevision = 8 });
        });
        using var client = new CommunityClient(new Uri("https://community.invalid"), handler);
        var directory = await client.ReadAsync("test-bearer", new("mine", "", null, null), "A:1", default);
        var query = JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = directory.Items[0].TargetRef });
        pauseRead = true;
        var lateRead = client.ReadRolesAsync("test-bearer", query, "A:1", Current, default);
        await ready.Task.WaitAsync(TimeSpan.FromSeconds(5));
        client.InvalidateRolesEdits();
        release.SetResult();
        await Error(() => lateRead, "communities.identityUnavailable");
        pauseRead = false;
        ready = new(TaskCreationOptions.RunContinuationsAsynchronously);
        release = new(TaskCreationOptions.RunContinuationsAsynchronously);
        var snapshot = JsonSerializer.SerializeToElement(await client.ReadRolesAsync("test-bearer", query, "A:1", CheckCurrent, default));
        var pending = client.SaveRolesAsync("test-bearer", Command(snapshot), "A:1", CheckCurrent, default);
        await ready.Task.WaitAsync(TimeSpan.FromSeconds(5));
        try
        {
            Check((await client.SaveRolesAsync("test-bearer", Command(snapshot), "A:1", CheckCurrent, default)).Error == "busy" && writes == 1,
                "shared write gate prevents concurrent role submission");
            current = false;
            client.InvalidateRolesEdits();
        }
        finally { release.SetResult(); }
        var receipt = await pending;
        Check(receipt.Status == "unknown" && receipt.ProfileRevision is null, "late save cannot report success for new account");
    }

    private static void ValidateDrafts()
    {
        var snapshot = Element(new { editRef = new string('a', 32), roles = Projection()["roles"] });
        CommunityClient.ValidateRolesSave(Command(snapshot));
        foreach (var field in new[] { "fleetCode", "expectedProfileRevision", "updatedSections", "url" })
        {
            var body = JsonNode.Parse(Command(snapshot).GetRawText())!;
            body[field] = "forbidden";
            InvalidDraft(Element(body));
        }
        foreach (var field in new[] { "isSystem", "memberCount", "createdAt", "accountId" })
        {
            var body = JsonNode.Parse(Command(snapshot).GetRawText())!;
            body["roles"]![0]![field] = "forbidden";
            InvalidDraft(Element(body));
        }
        var duplicate = JsonNode.Parse(Command(snapshot).GetRawText())!;
        duplicate["roles"]!.AsArray().Add(duplicate["roles"]![0]!.DeepClone());
        InvalidDraft(Element(duplicate));
        foreach (var field in new[] { "key", "displayName", "description", "color", "permissions" })
        {
            var body = JsonNode.Parse(Command(snapshot).GetRawText())!;
            body["roles"]![0]![field] = null;
            InvalidDraft(Element(body));
        }
    }

    private static void InvalidDraft(JsonElement body)
    {
        try { CommunityClient.ValidateRolesSave(body); throw new InvalidOperationException("Invalid draft accepted"); }
        catch (AccountBridgeHostException e) when (e.Code == "communities.dataInvalid") { }
    }
    private static JsonElement Command(JsonElement snapshot, bool confirm = false) => Element(new
    {
        schemaVersion = 1, requestId = Guid.NewGuid().ToString("N"), editRef = snapshot.GetProperty("editRef").GetString(),
        roles = snapshot.GetProperty("roles").EnumerateArray().Select(row => row.EnumerateObject()
            .Where(p => p.Name is "key" or "displayName" or "description" or "color" or "sortOrder" or "isEnabled" or "permissions")
            .ToDictionary(p => p.Name, p => p.Value.Clone())).ToArray(), confirmUncertainRetry = confirm
    });
    private static JsonNode Projection() => JsonSerializer.SerializeToNode(new
    {
        schemaVersion = 1, membershipModelVersion = 2, code = "A", name = "Organization A", profileRevision = 7,
        access = new { canEditRoles = true, canAssignMembers = false }, internalOnly = "do-not-forward",
        roles = new[] { "fleet_commander", "fleet_deputy_commander", "custom_navigation" }.Select((key, index) => new
        {
            key, displayName = key, description = "", color = "#7755FF", sortOrder = index,
            isSystem = index < 2, isEnabled = true, memberCount = 1,
            permissions = new[] { "fleet.profile.edit", "future.preserved" },
            createdAt = "2026-09-01T00:00:00Z", updatedAt = "2026-09-07T00:00:00Z", privateMemberIds = "do-not-forward"
        }).ToArray()
    })!;
    internal static object Directory() => new
    {
        schemaVersion = 1, membershipModelVersion = 2, view = "mine", query = "", next = (string?)null,
        items = new[] { new { code = "A", name = "Organization A", description = "", language = "", activeTime = "", memberCount = 1,
            relationship = "owner", joinMode = "direct", actions = Array.Empty<string>() } }
    };
    private static void Current() { }
    private static JsonElement Element(object value) => JsonSerializer.SerializeToElement(value);
    private static HttpResponseMessage Reply(object body) => new(HttpStatusCode.OK) { Content = JsonContent.Create(body) };
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
    private static async Task Error(Func<Task<object>> action, string code)
    {
        try { await action(); throw new InvalidOperationException("Expected " + code); }
        catch (AccountBridgeHostException e) when (e.Code == code) { }
    }
    private sealed class Handler(Func<HttpRequestMessage, Task<HttpResponseMessage>> send) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => send(request);
    }
}
