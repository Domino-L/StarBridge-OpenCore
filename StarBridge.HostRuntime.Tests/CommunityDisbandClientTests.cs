using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;

internal static class CommunityDisbandClientTests
{
    internal static async Task Verify()
    {
        var mode = "ok";
        var reads = 0;
        var writes = 0;
        string? lastPassword = null;
        using var handler = new Handler(async request =>
        {
            Check(request.Headers.Authorization?.Parameter == "test-bearer", "uses the supplied SCM bearer");
            if (request.RequestUri!.AbsolutePath == "/api/fleets/directory") return Json(new
            {
                schemaVersion = 1, membershipModelVersion = 2, view = "mine", query = "", next = (string?)null,
                items = new[] { "A", "B" }.Select(code => new { code, name = "Organization " + code, description = "", language = "",
                    activeTime = "", memberCount = 2, relationship = "member", joinMode = "direct", actions = new[] { "leave" }, logoImageData = (string?)null })
            });
            if (request.Method == HttpMethod.Get)
            {
                reads++;
                Check(request.RequestUri.AbsolutePath == "/api/fleets/disband-preview", "only bounded confirmation read");
                var payload = JsonSerializer.SerializeToNode(new
                {
                    schemaVersion = 1, code = "A", name = "Organization A", memberCount = 2,
                    version = new string('a', 64), canDisband = true, credentialMode = "legacyPassword",
                    passwordHash = "must-not-cross-bridge"
                })!;
                switch (mode)
                {
                    case "wrong-code": payload["code"] = "B"; break;
                    case "wrong-authority": payload["credentialMode"] = "scmPassword"; break;
                    case "bad-version": payload["version"] = "abc"; break;
                    case "bad-name": payload["name"] = "\nprivate"; break;
                    case "bad-count": payload["memberCount"] = -1; break;
                    case "bad-permission": payload["canDisband"] = "true"; break;
                    case "missing": payload.AsObject().Remove("memberCount"); break;
                    case "big": payload["extra"] = new string('x', 17000); break;
                    case "denied": payload["canDisband"] = false; break;
                }
                return Json(payload);
            }
            writes++;
            Check(request.RequestUri.AbsolutePath == "/api/fleets/disband" &&
                request.RequestUri.Query == "?projection=disband&version=" + new string('a', 64), "scoped version never falls back to unconfirmed route");
            var body = await request.Content!.ReadFromJsonAsync<JsonElement>();
            Check(body.EnumerateObject().Count() == 2 && body.GetProperty("fleetCode").GetString() == "A", "narrow command contains only its resolved target and credential");
            lastPassword = body.GetProperty("password").GetString();
            return mode switch
            {
                "lost" => throw new HttpRequestException("simulated lost reply"),
                "unauthorized" => new(HttpStatusCode.Unauthorized),
                "wrong-password" => new(HttpStatusCode.BadRequest),
                "forbidden" => new(HttpStatusCode.Forbidden),
                "conflict" => new(HttpStatusCode.Conflict),
                "missing-target" => new(HttpStatusCode.NotFound),
                "server-error" => new(HttpStatusCode.InternalServerError),
                "bad-receipt" => Json(new { disbanded = true }),
                "big-receipt" => Json(new { schemaVersion = 1, status = "accepted", extra = new string('x', 2000) }),
                _ => Json(new { schemaVersion = 1, status = "accepted" })
            };
        });
        using var client = new CommunityClient(new Uri("https://community.invalid"), handler);
        var directory = await client.ReadAsync("test-bearer", new("mine", "", null, null), "scope", default);
        var a = directory.Items[0].TargetRef;
        var b = directory.Items[1].TargetRef;
        JsonElement ReadBody(string target) => JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = target });
        JsonElement WriteBody(string reference, string target, string password = "  fixture-password  ") =>
            JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = target, confirmationRef = reference, password });
        async Task<JsonElement> Read(Action? current = null) => JsonSerializer.SerializeToElement(
            await client.ReadDisbandAsync("test-bearer", ReadBody(a), "scope", current ?? (() => { }), default));
        async Task<CommunityCommand> Write(JsonElement body, string scope = "scope", Action? current = null) =>
            (CommunityCommand)await client.DisbandAsync("test-bearer", body, scope, current ?? (() => { }), default);
        var preview = await Read();
        Check(preview.GetProperty("memberCount").GetInt32() == 2 && preview.GetProperty("targetRef").GetString() == a &&
            !preview.GetRawText().Contains("must-not-cross-bridge") && !preview.TryGetProperty("version", out _), "UI receives whitelist, not hash or version");
        var confirmation = preview.GetProperty("confirmationRef").GetString()!;
        Check((await Write(WriteBody(confirmation, b))).Status == "rejected" && writes == 0, "cross-organization ref never writes");
        await Error(() => Write(WriteBody(confirmation, a), "other"), "communities.refreshRequired");
        var deniedCurrent = await Write(WriteBody(confirmation, a), current: () => throw new AccountBridgeHostException("communities.identityUnavailable"));
        Check(deniedCurrent.Status == "rejected" && writes == 0, "invalidated account never sends");
        Check((await Write(WriteBody(confirmation, a))).Status == "accepted" && lastPassword == "  fixture-password  ", "credential is preserved exactly for its one explicit attempt");
        Check((await Write(WriteBody(confirmation, a))).Status == "rejected" && writes == 1, "double click never replays");
        foreach (var failure in new[] { "wrong-code", "wrong-authority", "bad-version", "bad-name", "bad-count", "bad-permission", "missing", "big" })
        {
            mode = failure;
            await Error(async () => await Read(), "communities.dataInvalid");
        }
        mode = "denied";
        confirmation = (await Read()).GetProperty("confirmationRef").GetString()!;
        Check((await Write(WriteBody(confirmation, a))).Status == "rejected" && writes == 1, "read-only response produces no usable confirmation");
        mode = "ok";
        var old = (await Read()).GetProperty("confirmationRef").GetString()!;
        await Read();
        Check((await Write(WriteBody(old, a))).Status == "rejected" && writes == 1, "fresh preview revokes earlier confirmation");
        foreach (var failure in new[] { "lost", "unauthorized", "wrong-password", "forbidden", "conflict", "missing-target", "server-error", "bad-receipt", "big-receipt" })
        {
            mode = "ok";
            confirmation = (await Read()).GetProperty("confirmationRef").GetString()!;
            mode = failure;
            var before = writes;
            var answer = await Write(WriteBody(confirmation, a));
            var uncertain = failure is "lost" or "server-error" or "bad-receipt" or "big-receipt";
            Check(answer.Status == (uncertain ? "unknown" : "rejected"), "correct outcome for " + failure);
            if (failure == "wrong-password") Check(answer.Error == "passwordInvalid", "incorrect legacy password is actionable");
            await Write(WriteBody(confirmation, a));
            Check(writes == before + 1, "no automatic re-send after " + failure);
        }
        foreach (var password in new[] { "", "   ", new string('x', 4097) })
            await Error(() => Write(WriteBody(confirmation, a, password)), "communities.dataInvalid");
        var beforeReads = reads;
        await Error(() => client.ReadDisbandAsync("test-bearer", JsonSerializer.SerializeToElement(new { schemaVersion = 1, code = "A" }), "scope", () => { }, default), "communities.dataInvalid");
        Check(reads == beforeReads, "raw code injection does not reach HTTP");
    }
    private static HttpResponseMessage Json(object value) => new(HttpStatusCode.OK) { Content = JsonContent.Create(value) };
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
    private static async Task Error(Func<Task> action, string code)
    {
        try { await action(); throw new InvalidOperationException("Expected " + code); }
        catch (AccountBridgeHostException e) when (e.Code == code) { }
    }
    private sealed class Handler(Func<HttpRequestMessage, Task<HttpResponseMessage>> action) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => action(request);
    }
}
