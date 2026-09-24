using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;

internal static class CommunityOwnershipTransferClientTests
{
    internal static Task Verify() => VerifyIntent(false);
    internal static Task VerifyExit() => VerifyIntent(true);
    private static async Task VerifyIntent(bool leaveAfterTransfer)
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
                var path = leaveAfterTransfer ? "/api/fleets/ownership-exit" : "/api/fleets/ownership-transfer";
                Check(Uri.UnescapeDataString(request.RequestUri.PathAndQuery) == path + "?code=A&memberId=account:member-one", "resolve member and organization before preview");
                if (mode == "forbidden") return new(HttpStatusCode.Forbidden);
                var payload = JsonSerializer.SerializeToNode(new
                {
                    schemaVersion = 1, code = "A", memberId = "account:member-one", version = version.ToString("x64"),
                    gameName = "", callsign = "Visible callsign", roleTitle = "成员", formerOwnerRoleTitle = "副负责人", canTransfer = mode != "protected",
                    leaveAfterTransfer, privateField = "do-not-forward"
                })!;
                if (mode == "wrong-member") payload["memberId"] = "account:other";
                if (mode == "wrong-code") payload["code"] = "B";
                if (mode == "wrong-version") payload["version"] = "invalid";
                if (mode == "missing-role") payload.AsObject().Remove("formerOwnerRoleTitle");
                if (mode == "wrong-role") payload["formerOwnerRoleTitle"] = 42;
                if (mode == "long-role") payload["formerOwnerRoleTitle"] = new string('x', 513);
                if (mode == "wrong-flag") payload["canTransfer"] = "true";
                if (mode == "wrong-intent") payload["leaveAfterTransfer"] = !leaveAfterTransfer;
                if (mode == "invalid-intent") payload["leaveAfterTransfer"] = "true";
                if (mode == "missing-intent") payload.AsObject().Remove("leaveAfterTransfer");
                if (mode == "large") payload["privateField"] = new string('x', 16 * 1024);
                if (mode == "late-read") invalidate!();
                return Reply(payload);
            }
            writes++;
            var writePath = leaveAfterTransfer ? "/api/fleets/leave?projection=ownership-exit" : "/api/fleets/transfer-commander?projection=ownership-transfer";
            Check(Uri.UnescapeDataString(request.RequestUri.PathAndQuery).StartsWith(
                writePath + "&memberId=account:member-one&version=", StringComparison.Ordinal), "scoped versioned ownership endpoint");
            var outgoing = await request.Content!.ReadFromJsonAsync<JsonElement>();
            Check(outgoing.EnumerateObject().Count() == (leaveAfterTransfer ? 1 : 2) && outgoing.GetProperty("fleetCode").GetString() == "A" &&
                (leaveAfterTransfer || outgoing.GetProperty("targetGameName").GetString() == ""), "body cannot redirect by name or supply UID");
            if (pending is not null) return await pending.Task;
            if (mode == "lost") throw new HttpRequestException("test lost response");
            if (mode == "conflict") return new(HttpStatusCode.Conflict);
            if (mode == "denied") return new(HttpStatusCode.Forbidden);
            if (mode == "missing") return new(HttpStatusCode.NotFound);
            if (mode == "invalid") return new(HttpStatusCode.BadRequest);
            if (mode == "unauthorized") return new(HttpStatusCode.Unauthorized);
            if (mode == "empty") return new(HttpStatusCode.NoContent);
            if (mode == "bad-receipt") return Reply(new { schemaVersion = 2, status = "accepted" });
            if (mode == "contradictory-receipt") return Reply(new { schemaVersion = 1, status = "accepted", error = "notAllowed" });
            if (mode == "large-receipt") return Reply(new { schemaVersion = 1, status = "accepted", privateField = new string('x', 5000) });
            return Reply(new { schemaVersion = 1, status = "accepted" });
        });
        using var client = new CommunityClient(new Uri("https://community.invalid"), handler);
        invalidate = client.InvalidateOwnershipTransferEdits;
        var directory = await client.ReadAsync("test-bearer", new("mine", "", null, null), "A:1", default);
        var targetRef = directory.Items[0].TargetRef;
        var workspace = Element(await client.ReadWorkspaceAsync("test-bearer",
            Element(new { schemaVersion = 1, targetRef, query = "", offset = 0 }), "A:1", default));
        var memberRef = workspace.GetProperty("members")[0].GetProperty("memberRef").GetString();
        var query = Element(new { schemaVersion = 1, targetRef, memberRef });
        async Task<JsonElement> Read() => Element(await client.ReadOwnershipTransferAsync("test-bearer", query, "A:1", Current, default, leaveAfterTransfer));
        Task<CommunityCommand> Transfer(JsonElement body, string scope = "A:1") => client.TransferOwnershipAsync("test-bearer", body, scope, Current, default, leaveAfterTransfer);
        var snapshot = await Read();
        Check(!snapshot.GetRawText().Contains("account:member-one") && !snapshot.GetRawText().Contains("do-not-forward") &&
            !snapshot.TryGetProperty("version", out _), "private identity and version stay in Host");
        Check(snapshot.GetProperty("formerOwnerRoleTitle").GetString() == "副负责人", "actual post-transfer role is projected");
        await Error(() => client.ReadOwnershipTransferAsync("test-bearer", query, "B:1", Current, default), "communities.refreshRequired");
        await Error(() => client.ReadOwnershipTransferAsync("test-bearer", Element(new { schemaVersion = 1, targetRef, memberRef,
            editRef = snapshot.GetProperty("editRef").GetString() }), "A:1", Current, default), "communities.dataInvalid");
        var refreshed = Element(await client.ReadOwnershipTransferAsync("test-bearer", Element(new { schemaVersion = 1,
            editRef = snapshot.GetProperty("editRef").GetString() }), "A:1", Current, default, leaveAfterTransfer));
        Check(refreshed.GetProperty("memberRef").GetString() == memberRef && writes == 0, "reread preserves target without writing");
        var command = Command(snapshot);
        Check((await client.TransferOwnershipAsync("test-bearer", command, "A:1", Current, default, !leaveAfterTransfer)).Error == "invalidDraft" && writes == 0,
            "read reference cannot switch between transfer and departure");
        await Error(() => client.ReadOwnershipTransferAsync("test-bearer", Element(new { schemaVersion = 1,
            editRef = snapshot.GetProperty("editRef").GetString() }), "A:1", Current, default, !leaveAfterTransfer), "communities.dataInvalid");
        var receipt = await Transfer(command);
        Check(receipt.Status == "accepted" && writes == 1 && await Transfer(command) == receipt && writes == 1, "accepted receipt deduplicated");
        Check((await client.TransferOwnershipAsync("test-bearer", command, "A:1", Current, default, !leaveAfterTransfer)).Error == "requestChanged" && writes == 1,
            "cached receipt cannot authorize a different operation");
        var changed = JsonNode.Parse(command.GetRawText())!;
        changed["confirmUncertainRetry"] = true;
        Check((await Transfer(Element(changed))).Error == "requestChanged", "same request id cannot change intent");
        Check((await Transfer(command, "B:1")).Status == "rejected" && writes == 1, "references account scoped");
        foreach (var field in new[] { "memberId", "accountId", "targetGameName", "fleetCode", "version", "roleKey" })
        {
            var forged = JsonNode.Parse(Command(snapshot).GetRawText())!;
            forged[field] = "forged";
            try { CommunityClient.ValidateOwnershipTransfer(Element(forged)); throw new InvalidOperationException("unexpected field accepted: " + field); }
            catch (AccountBridgeHostException) { }
        }
        foreach (var invalid in new[] { "wrong-member", "wrong-code", "wrong-version", "large", "missing-role", "wrong-role", "long-role", "wrong-flag", "wrong-intent", "invalid-intent" })
        {
            mode = invalid;
            await Error(() => client.ReadOwnershipTransferAsync("test-bearer", query, "A:1", Current, default, leaveAfterTransfer), "communities.dataInvalid");
        }
        mode = "missing-intent";
        if (leaveAfterTransfer)
            await Error(() => client.ReadOwnershipTransferAsync("test-bearer", query, "A:1", Current, default, true), "communities.dataInvalid");
        else await Read(); // Previous retaining-transfer services did not publish an intent flag.
        mode = "protected";
        snapshot = await Read();
        Check((await Transfer(Command(snapshot))).Error == "notAllowed" && writes == 1, "no write for protected member");
        foreach (var failure in new[] { "conflict", "denied", "invalid", "missing", "unauthorized", "lost", "empty", "bad-receipt", "large-receipt", "contradictory-receipt" })
        {
            mode = "ok"; version++;
            snapshot = await Read();
            mode = failure;
            var before = writes;
            command = Command(snapshot);
            receipt = await Transfer(command);
            Check(receipt.Status == (failure is "lost" or "empty" or "bad-receipt" or "large-receipt" or "contradictory-receipt" ? "unknown" : "rejected"), "correct result for " + failure);
            Check(await Transfer(command) == receipt && writes == before + 1, "no automatic duplicate for " + failure);
            if (receipt.Status == "unknown")
                Check((await Transfer(Command(snapshot))).Status == "unknown" && writes == before + 1, "new request cannot bypass uncertainty");
        }
        mode = "ok";
        snapshot = await Read();
        var beforeRetry = writes;
        Check((await Transfer(Command(snapshot))).Status == "unknown" && writes == beforeRetry, "new preview of same version still needs explicit retry");
        mode = "denied";
        Check((await Transfer(Command(snapshot, confirm: true))).Status == "unknown", "rejected retry cannot disprove prior uncertain transfer");
        mode = "ok";
        Check((await Transfer(Command(snapshot, confirm: true))).Status == "accepted", "explicit retry uses server version guard");
        pending = new(TaskCreationOptions.RunContinuationsAsynchronously);
        version++;
        snapshot = await Read();
        var saving = Transfer(Command(snapshot));
        Check((await Transfer(Command(snapshot))).Error == "busy", "shared organization write gate");
        invalidate();
        pending.SetResult(Reply(new { schemaVersion = 1, status = "accepted" }));
        Check((await saving).Status == "unknown", "late response cannot confirm after account change");
        pending = null;
        await Error(() => client.ReadOwnershipTransferAsync("test-bearer", Element(new { schemaVersion = 1, editRef = snapshot.GetProperty("editRef").GetString() }), "A:1", Current, default), "communities.refreshRequired");
        mode = "late-read";
        await Error(() => client.ReadOwnershipTransferAsync("test-bearer", query, "A:1", Current, default, leaveAfterTransfer), "communities.identityUnavailable");
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
