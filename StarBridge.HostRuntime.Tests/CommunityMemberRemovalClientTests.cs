using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;

internal static class CommunityMemberRemovalClientTests
{
    internal static async Task Verify()
    {
        var mode = "ok";
        var version = 1;
        var writes = 0;
        Action? invalidate = null;
        TaskCompletionSource<HttpResponseMessage>? pending = null;
        using var handler = new Handler(async request =>
        {
            Check(request.Headers.Authorization?.Parameter == "test-bearer", "only current bearer");
            if (request.RequestUri!.AbsolutePath == "/api/fleets/directory") return Reply(CommunityRolesClientTests.Directory());
            if (request.RequestUri.AbsolutePath == "/api/fleets/workspace") return Reply(CommunityWorkspaceClientTests.Workspace());
            if (request.Method == HttpMethod.Get)
            {
                Check(Uri.UnescapeDataString(request.RequestUri.PathAndQuery) == "/api/fleets/member-removal?code=A&memberId=account:member-one", "resolve member and organization before preview");
                if (mode == "forbidden") return new(HttpStatusCode.Forbidden);
                var payload = JsonSerializer.SerializeToNode(new
                {
                    schemaVersion = 1, code = "A", memberId = "account:member-one", version = version.ToString("x64"),
                    gameName = "", callsign = "Visible callsign", roleTitle = "成员", canRemove = mode != "protected",
                    privateField = "do-not-forward"
                })!;
                if (mode == "wrong-member") payload["memberId"] = "account:other";
                if (mode == "wrong-code") payload["code"] = "B";
                if (mode == "wrong-version") payload["version"] = "invalid";
                if (mode == "large") payload["privateField"] = new string('x', 16 * 1024);
                if (mode == "late-read") invalidate!();
                return Reply(payload);
            }
            writes++;
            Check(Uri.UnescapeDataString(request.RequestUri.PathAndQuery).StartsWith(
                "/api/fleets/members/remove?projection=member-removal&memberId=account:member-one&version=", StringComparison.Ordinal), "scoped versioned removal endpoint");
            var outgoing = await request.Content!.ReadFromJsonAsync<JsonElement>();
            Check(outgoing.EnumerateObject().Count() == 2 && outgoing.GetProperty("fleetCode").GetString() == "A" &&
                outgoing.GetProperty("targetGameName").GetString() == "", "body cannot redirect by name or supply UID");
            if (pending is not null) return await pending.Task;
            if (mode == "lost") throw new HttpRequestException("test lost response");
            if (mode == "conflict") return new(HttpStatusCode.Conflict);
            if (mode == "denied") return new(HttpStatusCode.Forbidden);
            if (mode == "missing") return new(HttpStatusCode.NotFound);
            if (mode == "invalid") return new(HttpStatusCode.BadRequest);
            if (mode == "unauthorized") return new(HttpStatusCode.Unauthorized);
            if (mode == "empty") return new(HttpStatusCode.NoContent);
            if (mode == "bad-receipt") return Reply(new { schemaVersion = 2, status = "accepted" });
            if (mode == "large-receipt") return Reply(new { schemaVersion = 1, status = "accepted", privateField = new string('x', 5000) });
            return Reply(new { schemaVersion = 1, status = "accepted" });
        });
        using var client = new CommunityClient(new Uri("https://community.invalid"), handler);
        invalidate = client.InvalidateMemberRemovalEdits;
        var directory = await client.ReadAsync("test-bearer", new("mine", "", null, null), "A:1", default);
        var targetRef = directory.Items[0].TargetRef;
        var workspace = Element(await client.ReadWorkspaceAsync("test-bearer",
            Element(new { schemaVersion = 1, targetRef, query = "", offset = 0 }), "A:1", default));
        var memberRef = workspace.GetProperty("members")[0].GetProperty("memberRef").GetString();
        var query = Element(new { schemaVersion = 1, targetRef, memberRef });
        async Task<JsonElement> Read() => Element(await client.ReadMemberRemovalAsync("test-bearer", query, "A:1", Current, default));
        Task<CommunityCommand> Remove(JsonElement body, string scope = "A:1") => client.RemoveMemberAsync("test-bearer", body, scope, Current, default);
        var snapshot = await Read();
        Check(!snapshot.GetRawText().Contains("account:member-one") && !snapshot.GetRawText().Contains("do-not-forward") &&
            !snapshot.TryGetProperty("version", out _), "private identity and version stay in Host");
        var command = Command(snapshot);
        var receipt = await Remove(command);
        Check(receipt.Status == "accepted" && writes == 1 && await Remove(command) == receipt && writes == 1, "accepted receipt deduplicated");
        var changed = JsonNode.Parse(command.GetRawText())!;
        changed["confirmUncertainRetry"] = true;
        Check((await Remove(Element(changed))).Error == "requestChanged", "same request id cannot change intent");
        Check((await Remove(command, "B:1")).Status == "rejected" && writes == 1, "references account scoped");
        foreach (var field in new[] { "memberId", "accountId", "targetGameName", "fleetCode", "version", "roleKey" })
        {
            var forged = JsonNode.Parse(Command(snapshot).GetRawText())!;
            forged[field] = "forged";
            try { CommunityClient.ValidateMemberRemoval(Element(forged)); throw new InvalidOperationException("unexpected field accepted: " + field); }
            catch (AccountBridgeHostException) { }
        }
        foreach (var invalid in new[] { "wrong-member", "wrong-code", "wrong-version", "large" })
        {
            mode = invalid;
            await Error(() => client.ReadMemberRemovalAsync("test-bearer", query, "A:1", Current, default), "communities.dataInvalid");
        }
        mode = "protected";
        snapshot = await Read();
        Check((await Remove(Command(snapshot))).Error == "notAllowed" && writes == 1, "no write for protected member");
        foreach (var failure in new[] { "conflict", "denied", "invalid", "missing", "unauthorized", "lost", "empty", "bad-receipt", "large-receipt" })
        {
            mode = "ok"; version++;
            snapshot = await Read();
            mode = failure;
            var before = writes;
            command = Command(snapshot);
            receipt = await Remove(command);
            Check(receipt.Status == (failure is "lost" or "empty" or "bad-receipt" or "large-receipt" ? "unknown" : "rejected"), "correct result for " + failure);
            Check(await Remove(command) == receipt && writes == before + 1, "no automatic duplicate for " + failure);
            if (receipt.Status == "unknown")
                Check((await Remove(Command(snapshot))).Status == "unknown" && writes == before + 1, "new request cannot bypass uncertainty");
        }
        mode = "ok";
        snapshot = await Read();
        var beforeRetry = writes;
        Check((await Remove(Command(snapshot))).Status == "unknown" && writes == beforeRetry, "new preview of same version still needs explicit retry");
        Check((await Remove(Command(snapshot, confirm: true))).Status == "accepted", "explicit retry uses server version guard");
        pending = new(TaskCreationOptions.RunContinuationsAsynchronously);
        version++;
        snapshot = await Read();
        var saving = Remove(Command(snapshot));
        Check((await Remove(Command(snapshot))).Error == "busy", "shared organization write gate");
        invalidate();
        pending.SetResult(Reply(new { schemaVersion = 1, status = "accepted" }));
        Check((await saving).Status == "unknown", "late response cannot confirm after account change");
        pending = null;
        await Error(() => client.ReadMemberRemovalAsync("test-bearer", Element(new { schemaVersion = 1, editRef = snapshot.GetProperty("editRef").GetString() }), "A:1", Current, default), "communities.refreshRequired");
        mode = "late-read";
        await Error(() => client.ReadMemberRemovalAsync("test-bearer", query, "A:1", Current, default), "communities.identityUnavailable");
    }
    private static JsonElement Command(JsonElement snapshot, bool confirm = false) => Element(new
    {
        schemaVersion = 1, requestId = Guid.NewGuid().ToString("N"), editRef = snapshot.GetProperty("editRef").GetString(), confirmUncertainRetry = confirm
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
