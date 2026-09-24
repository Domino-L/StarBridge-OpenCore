using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;

internal static class CommunityMemberRoleClientTests
{
    internal static async Task Verify()
    {
        var mode = "ok";
        var version = 1;
        var writes = 0;
        Action? invalidate = null;
        TaskCompletionSource<HttpResponseMessage>? pending = null;
        JsonElement outgoing = default;
        using var handler = new Handler(async request =>
        {
            Check(request.Headers.Authorization?.Parameter == "test-bearer", "current bearer only");
            if (request.RequestUri!.AbsolutePath == "/api/fleets/directory") return Reply(CommunityRolesClientTests.Directory());
            if (request.RequestUri.AbsolutePath == "/api/fleets/workspace") return Reply(CommunityWorkspaceClientTests.Workspace());
            if (request.Method == HttpMethod.Get)
            {
                Check(Uri.UnescapeDataString(request.RequestUri.PathAndQuery) == "/api/fleets/member-role?code=A&memberId=account:member-one", "resolved target goes to the narrow member endpoint");
                if (mode == "forbidden") return new(HttpStatusCode.Forbidden);
                var payload = JsonSerializer.SerializeToNode(new
                {
                    schemaVersion = 1, code = "A", memberId = "account:member-one", version = version.ToString("x64"),
                    gameName = "", callsign = "Visible callsign", roleTitle = "成员", roleKey = "", canAssign = mode != "protected",
                    roles = new[] { new { key = "custom_navigation", displayName = "导航", color = "#9B7CFA" } },
                    privateField = "do-not-forward"
                })!;
                if (mode == "wrong-member") payload["memberId"] = "account:other";
                if (mode == "wrong-version") payload["version"] = "invalid";
                if (mode == "duplicate") payload["roles"]!.AsArray().Add(payload["roles"]![0]!.DeepClone());
                if (mode == "owner-option") payload["roles"]![0]!["key"] = "fleet_commander";
                if (mode == "large") payload["privateField"] = new string('x', 256 * 1024);
                if (mode == "late-read") invalidate!();
                return Reply(payload);
            }
            writes++;
            Check(Uri.UnescapeDataString(request.RequestUri.PathAndQuery).StartsWith(
                "/api/fleets/permissions?projection=member-role&memberId=account:member-one&version=", StringComparison.Ordinal), "save reuses the WPF permissions endpoint");
            outgoing = await request.Content!.ReadFromJsonAsync<JsonElement>();
            if (pending is not null) return await pending.Task;
            if (mode == "lost") throw new HttpRequestException("test lost response");
            if (mode == "late-write") invalidate!();
            if (mode == "conflict") return new(HttpStatusCode.Conflict);
            if (mode == "denied") return new(HttpStatusCode.Forbidden);
            if (mode == "invalid") return new(HttpStatusCode.BadRequest);
            if (mode == "missing") return new(HttpStatusCode.NotFound);
            if (mode == "unauthorized") return new(HttpStatusCode.Unauthorized);
            if (mode == "empty") return new(HttpStatusCode.NoContent);
            if (mode == "bad-receipt") return Reply(new { schemaVersion = 2, status = "accepted" });
            if (mode == "large-receipt") return Reply(new { schemaVersion = 1, status = "accepted", privateField = new string('x', 5000) });
            return Reply(new { schemaVersion = 1, status = "accepted" });
        });
        using var client = new CommunityClient(new Uri("https://community.invalid"), handler);
        invalidate = client.InvalidateMemberRoleEdits;
        var directory = await client.ReadAsync("test-bearer", new("mine", "", null, null), "A:1", default);
        var targetRef = directory.Items[0].TargetRef;
        var workspace = JsonSerializer.SerializeToElement(await client.ReadWorkspaceAsync("test-bearer",
            Element(new { schemaVersion = 1, targetRef, query = "", offset = 0 }), "A:1", default));
        var memberRef = workspace.GetProperty("members")[0].GetProperty("memberRef").GetString();
        var query = Element(new { schemaVersion = 1, targetRef, memberRef });
        async Task<JsonElement> Read() => JsonSerializer.SerializeToElement(await client.ReadMemberRoleAsync("test-bearer", query, "A:1", Current, default));
        Task<CommunityCommand> Save(JsonElement body, string scope = "A:1") => client.SaveMemberRoleAsync("test-bearer", body, scope, Current, default);
        var snapshot = await Read();
        Check(!snapshot.GetRawText().Contains("account:member-one") && !snapshot.GetRawText().Contains("do-not-forward") &&
            !snapshot.TryGetProperty("version", out _), "only safe fields and opaque references cross Bridge");
        var command = Command(snapshot);
        var receipt = await Save(command);
        Check(receipt.Status == "accepted" && writes == 1, "valid receipt accepted");
        Check(outgoing.GetProperty("fleetCode").GetString() == "A" && outgoing.GetProperty("permission").GetProperty("roleGroupKey").GetString() == "custom_navigation" &&
            !outgoing.GetProperty("permission").TryGetProperty("accountId", out _), "caller cannot supply member identity or rights");
        Check(await Save(command) == receipt && writes == 1, "same request does not resend");
        var changed = JsonNode.Parse(command.GetRawText())!;
        changed["roleKey"] = "";
        Check((await Save(Element(changed))).Error == "requestChanged" && writes == 1, "request ID pins exact intent");
        Check((await Save(command, "B:1")).Status == "rejected" && writes == 1, "cross account reference rejected");
        var forged = JsonNode.Parse(Command(snapshot).GetRawText())!;
        forged["accountId"] = "other";
        try { CommunityClient.ValidateMemberRoleSave(Element(forged)); throw new InvalidOperationException("forged target accepted"); }
        catch (AccountBridgeHostException) { }
        forged.AsObject().Remove("accountId");
        forged["roleKey"] = "fleet_commander";
        Check((await Save(Element(forged))).Error == "invalidDraft" && writes == 1, "owner role cannot be submitted");

        foreach (var invalid in new[] { "wrong-member", "wrong-version", "duplicate", "owner-option", "large" })
        {
            mode = invalid;
            await Error(() => client.ReadMemberRoleAsync("test-bearer", query, "A:1", Current, default), "communities.dataInvalid");
        }
        mode = "protected";
        snapshot = await Read();
        Check((await Save(Command(snapshot))).Error == "notAllowed" && writes == 1, "protected member is read-only");
        foreach (var failure in new[] { "conflict", "denied", "invalid", "missing", "unauthorized", "lost", "empty", "bad-receipt", "large-receipt" })
        {
            mode = "ok"; version++;
            snapshot = await Read();
            mode = failure;
            var before = writes;
            command = Command(snapshot);
            receipt = await Save(command);
            Check(receipt.Status == (failure is "lost" or "empty" or "bad-receipt" or "large-receipt" ? "unknown" : "rejected"), "accurate outcome for " + failure);
            Check(await Save(command) == receipt && writes == before + 1, "receipt replay never resends " + failure);
            if (receipt.Status == "unknown")
                Check((await Save(Command(snapshot))).Status == "unknown" && writes == before + 1, "new request ID does not bypass uncertainty");
        }
        mode = "ok";
        snapshot = await Read();
        var uncertainWrites = writes;
        Check((await Save(Command(snapshot))).Status == "unknown" && writes == uncertainWrites, "fresh edit reference cannot bypass same-version uncertainty");
        Check((await Save(Command(snapshot, confirm: true))).Status == "accepted", "explicit uncertain retry permitted with server version guard");

        pending = new(TaskCreationOptions.RunContinuationsAsynchronously);
        version++;
        snapshot = await Read();
        var saving = Save(Command(snapshot));
        Check((await Save(Command(snapshot))).Error == "busy", "shared write gate serializes member writes");
        invalidate();
        pending.SetResult(Reply(new { schemaVersion = 1, status = "accepted" }));
        Check((await saving).Status == "unknown", "late response cannot become success after invalidation");
        pending = null;
        await Error(() => client.ReadMemberRoleAsync("test-bearer", Element(new { schemaVersion = 1, editRef = snapshot.GetProperty("editRef").GetString() }), "A:1", Current, default), "communities.refreshRequired");
        mode = "late-read";
        await Error(() => client.ReadMemberRoleAsync("test-bearer", query, "A:1", Current, default), "communities.identityUnavailable");
    }
    private static JsonElement Command(JsonElement snapshot, bool confirm = false) => Element(new
    {
        schemaVersion = 1, requestId = Guid.NewGuid().ToString("N"), editRef = snapshot.GetProperty("editRef").GetString(),
        roleKey = "custom_navigation", confirmUncertainRetry = confirm
    });
    private static JsonElement Element(object value) => JsonSerializer.SerializeToElement(value);
    private static HttpResponseMessage Reply(object body) => new(HttpStatusCode.OK) { Content = JsonContent.Create(body) };
    private static void Current() { }
    private static void Check(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
    private static async Task Error(Func<Task<object>> read, string code)
    {
        try { await read(); throw new InvalidOperationException("Expected " + code); }
        catch (AccountBridgeHostException e) when (e.Code == code) { }
    }
    private sealed class Handler(Func<HttpRequestMessage, Task<HttpResponseMessage>> send) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => send(request);
    }
}
