using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;

internal static class CommunityLogsClientTests
{
    internal static async Task Verify()
    {
        var calls = 0;
        var writes = 0;
        var mode = "ok";
        var payload = Page();
        string? lastQuery = null;
        using var handler = new Handler(async request =>
        {
            calls++;
            Check(request.Headers.Authorization?.Parameter == "synthetic-bearer", "only current bearer used");
            var path = request.RequestUri!.AbsolutePath;
            if (path == "/api/fleets/directory") return Json(new
            {
                schemaVersion = 1, membershipModelVersion = 2, view = "mine", query = "", next = (string?)null,
                items = new[] { "A", "B" }.Select(code => new { code, name = code, description = "", language = "", activeTime = "",
                    memberCount = 1, relationship = "owner", joinMode = "direct", actions = Array.Empty<string>(), logoImageData = (string?)null })
            });
            if (path == "/api/fleets/logs")
            {
                Check(request.Method == HttpMethod.Get, "logs read remains GET");
                lastQuery = request.RequestUri.Query;
                if (mode == "forbidden") return new(HttpStatusCode.Forbidden);
                if (mode == "unauthorized") return new(HttpStatusCode.Unauthorized);
                if (mode == "missing") return new(HttpStatusCode.NotFound);
                if (mode == "offline") throw new HttpRequestException();
                return Json(payload);
            }
            Check(path == "/api/fleets/logs/delete" && request.Method == HttpMethod.Post, "only effective delete route used");
            writes++;
            var body = JsonNode.Parse(await request.Content!.ReadAsStringAsync())!;
            Check(body["fleetCode"]!.GetValue<string>() == "A" && body["logId"]!.GetValue<string>() == "server-log-id" &&
                request.RequestUri.Query == "?projection=logs&version=" + new string('a', 64), "server identity and version resolved inside Host");
            if (mode == "lost") throw new IOException();
            if (mode == "conflict") return new(HttpStatusCode.Conflict);
            if (mode == "forbidden") return new(HttpStatusCode.Forbidden);
            if (mode == "unauthorized") return new(HttpStatusCode.Unauthorized);
            if (mode == "invalid-receipt") return Json(new { schemaVersion = 1, status = "accepted", eventLog = "unexpected" });
            if (mode == "large-receipt") return new(HttpStatusCode.OK) { Content = new StringContent(new string('x', 1025)) };
            return Json(new { schemaVersion = 1, status = "accepted" });
        });
        using var client = new CommunityClient(new Uri("https://community.invalid"), handler);
        var directory = await client.ReadAsync("synthetic-bearer", new("mine", "", null, null), "account-a", default);
        var a = directory.Items[0].TargetRef;
        var b = directory.Items[1].TargetRef;
        JsonElement Query(string target, string type = "All", string query = "", int offset = 0) =>
            JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = target, type, query, offset });
        async Task<JsonElement> Read() => JsonSerializer.SerializeToElement(await client.ReadLogsAsync("synthetic-bearer", Query(a), "account-a", default));
        JsonElement DeleteBody(string target, string logRef) => JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = target, logRef });
        async Task<JsonElement> Delete(string target, string logRef, Action? current = null) =>
            JsonSerializer.SerializeToElement(await client.DeleteLogAsync("synthetic-bearer", DeleteBody(target, logRef), "account-a", current ?? (() => { }), default), new JsonSerializerOptions(JsonSerializerDefaults.Web));
        string Ref(JsonElement page) => page.GetProperty("items")[0].GetProperty("logRef").GetString()!;
        var page = await Read();
        var logRef = Ref(page);
        Check(logRef.Length == 32 && !page.GetRawText().Contains("server-log-id") && !page.GetRawText().Contains(new string('a', 64)) &&
            !page.GetRawText().Contains("private-extra"), "projection exposes no source IDs, versions or undeclared fields");
        Check(page.GetProperty("items")[0].GetProperty("occurrenceCount").GetInt32() == 3 &&
            page.GetProperty("items")[0].GetProperty("timestamp").ValueKind == JsonValueKind.Null, "unknown history and repeated count preserved");
        var before = calls;
        await Error(() => client.ReadLogsAsync("synthetic-bearer", Query(a), "account-b", default), "communities.refreshRequired");
        await Error(() => client.ReadLogsAsync("synthetic-bearer", Query(a, "任务"), "account-a", default), "communities.dataInvalid");
        await Error(() => client.ReadLogsAsync("synthetic-bearer", Query(a, query: "bad\0"), "account-a", default), "communities.dataInvalid");
        Check((await Delete(b, logRef)).GetProperty("status").GetString() == "rejected" && calls == before, "wrong account, organization and invalid query never reach network");
        Check((await Delete(a, logRef)).GetProperty("status").GetString() == "accepted" && writes == 1, "valid deletion accepted once");
        Check((await Delete(a, logRef)).GetProperty("status").GetString() == "rejected" && writes == 1, "same displayed reference cannot replay");

        foreach (var mutation in new Action<JsonNode>[]
        {
            p => p["code"] = "B", p => p["schemaVersion"] = 2, p => p["membershipModelVersion"] = 1,
            p => p["query"] = "mismatch", p => p["type"] = "成员", p => p["offset"] = 1,
            p => p["next"] = 20, p => p["matchedCount"] = 2, p => p["totalCount"] = 0,
            p => p["items"]![0]!["version"] = "bad", p => p["items"]![0]!["occurrenceCount"] = 0,
            p => p["items"]![0]!["detail"] = "bad\0", p => p["items"]![0]!["title"] = new string('x', 8193),
            p => p["items"]![0]!["timestamp"] = "not-a-date",
            p => p["items"]![0]!["timestamp"] = "2026-09-07T00:00:00Z",
            p => p["fetchedAt"] = null,
            p => { p["items"]!.AsArray().Add(p["items"]![0]!.DeepClone()); p["totalCount"] = 2; p["matchedCount"] = 2; }
        })
        {
            payload = Page(); mutation(payload);
            await Error(() => client.ReadLogsAsync("synthetic-bearer", Query(a), "account-a", default), "communities.dataInvalid");
        }
        payload = Page(); payload["type"] = "成员"; payload["query"] = "a&b +中文"; payload["items"]![0]!["type"] = "成员";
        await client.ReadLogsAsync("synthetic-bearer", Query(a, "成员", " a&b +中文 "), "account-a", default);
        Check(lastQuery!.Contains("q=a%26b%20%2B") && lastQuery.Contains("type="), "query encoded as data, not extra parameters");
        payload = Page(); payload["offset"] = 20; payload["totalCount"] = 21; payload["matchedCount"] = 21;
        var tail = JsonSerializer.SerializeToElement(await client.ReadLogsAsync("synthetic-bearer", Query(a, offset: 20), "account-a", default));
        Check(tail.GetProperty("offset").GetInt32() == 20 && tail.GetProperty("next").ValueKind == JsonValueKind.Null, "last partial page valid");
        payload = Page(); payload["items"] = new JsonArray(); payload["matchedCount"] = 0; payload["totalCount"] = 0;
        Check((await Read()).GetProperty("items").GetArrayLength() == 0, "empty logs distinct from errors");
        payload = Page(); logRef = Ref(await Read()); payload["canDelete"] = false;
        page = await Read(); before = writes;
        Check((await Delete(a, logRef)).GetProperty("status").GetString() == "rejected" &&
            (await Delete(a, Ref(page))).GetProperty("status").GetString() == "rejected" && writes == before, "read-only refresh revokes old delete references");
        payload = Page();
        foreach (var failure in new[] { "lost", "invalid-receipt", "large-receipt", "conflict", "forbidden", "unauthorized" })
        {
            mode = "ok"; logRef = Ref(await Read()); mode = failure;
            var result = await Delete(a, logRef);
            Check(result.GetProperty("status").GetString() == (failure is "conflict" or "forbidden" or "unauthorized" ? "rejected" : "unknown"), "honest command outcome: " + failure);
            before = writes; await Delete(a, logRef); Check(writes == before, "failure never silently replays: " + failure);
        }
        foreach (var (failure, error) in new[] { ("forbidden", "communities.notAllowed"), ("unauthorized", "communities.identityUnavailable"),
                     ("missing", "communities.notFound"), ("offline", "communities.unavailable") })
        { mode = failure; await Error(() => client.ReadLogsAsync("synthetic-bearer", Query(a), "account-a", default), error); }
        mode = "ok"; logRef = Ref(await Read()); before = writes;
        Check((await Delete(a, logRef, () => throw new AccountBridgeHostException("communities.identityUnavailable"))).GetProperty("status").GetString() == "rejected" && writes == before,
            "session lost before send performs no write");
    }
    private static JsonNode Page() => JsonSerializer.SerializeToNode(new
    {
        schemaVersion = 1, membershipModelVersion = 2, code = "A", name = "Organization A", canDelete = true,
        type = "All", query = "", offset = 0, next = (int?)null, totalCount = 1, matchedCount = 1, fetchedAt = "2026-09-07T00:00:00Z",
        items = new[] { new { id = "server-log-id", version = new string('a', 64), timestamp = (string?)null, endTimestamp = (string?)null,
            type = "成员", title = "成员加入", detail = "Visible detail", occurrenceCount = 3 } }, extra = "private-extra"
    })!;
    private static HttpResponseMessage Json(object value) => new(HttpStatusCode.OK) { Content = JsonContent.Create(value) };
    private static async Task Error(Func<Task<object>> read, string code)
    {
        try { await read(); throw new InvalidOperationException("Expected " + code); }
        catch (AccountBridgeHostException e) when (e.Code == code) { }
    }
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
    private sealed class Handler(Func<HttpRequestMessage, Task<HttpResponseMessage>> read) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) => read(request);
    }
}
