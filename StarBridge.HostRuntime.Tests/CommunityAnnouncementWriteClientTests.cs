using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;

internal static class CommunityAnnouncementWriteClientTests
{
    internal static async Task Verify()
    {
        var mode = "ok";
        var posted = new List<JsonElement>();
        TaskCompletionSource? hold = null;
        using var handler = new Handler(async request =>
        {
            Check(request.Headers.Authorization?.Parameter == "fixture-bearer", "current bearer required");
            var path = request.RequestUri!.AbsolutePath;
            if (path == "/api/fleets/directory") return Json(new { schemaVersion = 1, membershipModelVersion = 2, view = "mine", query = "",
                next = (string?)null, items = new[] { "A", "B" }.Select(code => new { code, name = code, description = "",
                    language = "", activeTime = "", memberCount = 2, relationship = "member", joinMode = "direct", actions = new[] { "leave" },
                    logoImageData = (string?)null }) });
            if (request.Method == HttpMethod.Get)
            {
                Check(path == "/api/fleets/announcements", "existing announcement read route");
                object Person() => new { accountId = "author-private-id", callsign = "Author", gameId = "", roleTitle = "成员",
                    roleColor = "#29AAFF", avatarImageData = (string?)null };
                object Entry(string id, string state) => new { authorHasAvatar = false, lastEditorHasAvatar = false, announcement = new {
                    id, fleetCode = "A", title = "Before", content = "Body", state, revision = 3, author = Person(), lastEditor = Person(),
                    publishedAt = "2026-09-07T00:00:00Z", updatedAt = "2026-09-08T00:00:00Z", archivedAt = (string?)null, withdrawnAt = (string?)null } };
                // Management authority is checked at POST, not trusted from a stale page flag.
                return Json(new { schemaVersion = 1, membershipModelVersion = 2, fleetCode = "A", revision = 10, canManage = false,
                    current = Entry("actual-id", "Published"), history = new[] { Entry("old-id", "Archived") }, offset = 0, next = (int?)null,
                    totalHistoryCount = 1, refreshedAt = "2026-09-08T00:00:00Z" });
            }
            Check(request.Method == HttpMethod.Post && request.RequestUri.Query == "?view=client"
                && new[] { "publish", "edit", "withdraw" }.Any(action => path == "/api/fleets/announcements/" + action), "bounded live write route only");
            using var body = JsonDocument.Parse(await request.Content!.ReadAsStringAsync());
            var command = body.RootElement.Clone();
            posted.Add(command);
            if (hold is not null) await hold.Task;
            if (mode == "lost") throw new HttpRequestException("fixture lost reply");
            if (mode.StartsWith("status-")) return new((HttpStatusCode)int.Parse(mode[7..]));
            if (mode == "malformed") return new(HttpStatusCode.OK) { Content = new StringContent("{") };
            if (mode == "oversized") return new(HttpStatusCode.OK) { Content = new StringContent(new string('x', 16385)) };
            if (mode == "duplicate-json") return new(HttpStatusCode.OK) { Content = new StringContent("{\"status\":\"published\",\"status\":\"edited\"}") };
            var operation = path.Split('/').Last();
            var node = JsonSerializer.SerializeToNode(new { schemaVersion = 1, membershipModelVersion = 2,
                status = mode == "duplicate" ? "duplicate" : operation == "publish" ? "published" : operation == "edit" ? "edited" : "withdrawn",
                announcementId = operation == "publish" ? "new-private-id" : command.GetProperty("announcementId").GetString(),
                revision = 11, privateExtra = "never-export" })!;
            switch (mode)
            {
                case "wrong-id": node["announcementId"] = "different-id"; break;
                case "blank-id": node["announcementId"] = " "; break;
                case "wrong-status": node["status"] = "saved"; break;
                case "wrong-schema": node["schemaVersion"] = 2; break;
                case "wrong-membership": node["membershipModelVersion"] = 1; break;
                case "old-revision": node["revision"] = 10; break;
                case "zero-revision": node["revision"] = 0; break;
                case "error-success": node["error"] = "failure"; break;
            }
            return Json(node);
        });
        using var client = new CommunityClient(new Uri("https://community.invalid"), handler);
        var directory = await client.ReadAsync("fixture-bearer", new("mine", "", null, null), "scope", default);
        var a = directory.Items[0].TargetRef; var b = directory.Items[1].TargetRef;
        var page = JsonSerializer.SerializeToElement(await client.ReadAnnouncementsAsync("fixture-bearer",
            JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = a, offset = 0 }), "scope", () => {}, default));
        var active = page.GetProperty("current").GetProperty("announcementRef").GetString();
        var old = page.GetProperty("history")[0].GetProperty("announcementRef").GetString();
        string Id() => Guid.NewGuid().ToString("N");
        JsonElement Body(string action = "publish", string? id = null, string? target = null, string? announcement = null,
            string title = " Title ", string content = " Body\r\ntext ") => JsonSerializer.SerializeToElement(new {
                schemaVersion = 1, targetRef = target ?? a, requestId = id ?? Id(), action,
                announcementRef = announcement ?? (action == "publish" ? null : active),
                title = action == "withdraw" ? null : title, content = action == "withdraw" ? null : content });
        async Task<JsonElement> Send(JsonElement body, string scope = "scope", Action? current = null) => JsonSerializer.SerializeToElement(
            await client.ManageAnnouncementsAsync("fixture-bearer", body, scope, current ?? (() => {}), default));
        var id = Id(); var publish = Body(id: id);
        var receipt = await Send(publish);
        Check(receipt.GetProperty("status").GetString() == "accepted" && receipt.GetProperty("revision").GetInt64() == 11
            && receipt.GetProperty("requestId").GetString() == id && receipt.GetProperty("action").GetString() == "publish", "correlated narrow receipt");
        Check(!receipt.ToString().Contains("private") && !receipt.ToString().Contains("never-export") && !receipt.ToString().Contains("fleetCode"), "server identifiers and extras remain native");
        Check(posted[0].GetProperty("title").GetString() == "Title" && posted[0].GetProperty("content").GetString() == "Body\ntext", "WPF normalization preserved");
        Check((await Send(publish)).GetProperty("status").GetString() == "accepted" && posted.Count == 1, "double delivery only one POST");
        Check((await Send(Body(id: id, content: "different"))).GetProperty("error").GetString() == "intentConflict" && posted.Count == 1, "key binds original content");
        Check((await Send(Body("edit", id: id))).GetProperty("error").GetString() == "intentConflict" && posted.Count == 1, "key binds action");
        await Send(Body(id: id, target: b));
        Check(posted[1].GetProperty("fleetCode").GetString() == "B"
            && posted[0].GetProperty("clientRequestId").GetString() != posted[1].GetProperty("clientRequestId").GetString(), "multi-organization nonce is scoped");
        foreach (var action in new[] { "edit", "withdraw" })
        {
            Check((await Send(Body(action))).GetProperty("status").GetString() == "accepted", action + " accepted");
            Check(posted.Last().GetProperty("announcementId").GetString() == "actual-id"
                && posted.Last().GetProperty("expectedRevision").GetInt32() == 3, "original target and version supplied by Host");
        }
        var before = posted.Count;
        Check((await Send(Body("edit", target: b))).GetProperty("error").GetString() == "refreshRequired", "cross organization reference rejected");
        Check((await Send(Body("edit", announcement: old))).GetProperty("error").GetString() == "announcementsChanged", "history is not editable");
        Check((await Send(Body(), "another-account")).GetProperty("status").GetString() == "rejected", "account scope rejected");
        Check(posted.Count == before, "invalid scope and history never POST");
        foreach (var failure in new[] { "lost", "malformed", "oversized", "duplicate-json", "wrong-id", "blank-id", "wrong-status",
                     "wrong-schema", "wrong-membership", "old-revision", "zero-revision", "error-success", "status-500", "status-302" })
        {
            mode = failure;
            var attempt = Body("edit"); before = posted.Count;
            Check((await Send(attempt)).GetProperty("status").GetString() == "unknown", failure + " is not success");
            Check((await Send(attempt)).GetProperty("status").GetString() == "unknown" && posted.Count == before + 1, failure + " is never replayed");
        }
        foreach (var (status, error) in new[] { (400,"dataInvalid"), (401,"identityUnavailable"), (403,"notAllowed"),
                     (404,"refreshRequired"), (409,"announcementsChanged"), (429,"rateLimited") })
        {
            mode = "status-" + status;
            var denied = await Send(Body("edit"));
            Check(denied.GetProperty("status").GetString() == "rejected" && denied.GetProperty("error").GetString() == error, "actual authority/status " + status);
        }
        mode = "duplicate";
        Check((await Send(Body("edit"))).GetProperty("status").GetString() == "accepted", "original server receipt duplicate accepted");
        mode = "ok";
        foreach (var invalid in new[] { Body(title: ""), Body(title: new string('x',49)), Body(content: new string('x',1201)),
                     Body(title: "hello\nworld"), Body(content: "x\0y"), Body(id: "bad"), Body(action: "delete"), Body(announcement: active),
                     JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = a, requestId = Id(), action = "edit", announcementRef = active,
                         title = "Title", content = "", expectedRevision = 3 }) })
        {
            before = posted.Count;
            try { await Send(invalid); throw new InvalidOperationException("Expected invalid intent"); }
            catch (AccountBridgeHostException e) when (e.Code == "communities.dataInvalid") { }
            Check(posted.Count == before, "malformed intention fails before POST");
        }
        var checks = 0; var stale = Body();
        Check((await Send(stale, current: () => { if (++checks == 3) throw new AccountBridgeHostException("communities.identityUnavailable"); }))
            .GetProperty("status").GetString() == "unknown", "late account change cannot accept a receipt");
        before = posted.Count;
        await Send(stale);
        Check(posted.Count == before, "late result not replayed");
        hold = new(TaskCreationOptions.RunContinuationsAsynchronously);
        var pending = Send(Body());
        while (posted.Count == before) await Task.Yield();
        Check((await Send(Body())).GetProperty("error").GetString() == "busy", "concurrent command uses existing write gate");
        hold.SetResult();
        Check((await pending).GetProperty("status").GetString() == "accepted", "first write completes once");
    }
    private static HttpResponseMessage Json(object value) => new(HttpStatusCode.OK) { Content = JsonContent.Create(value) };
    private static void Check(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
    private sealed class Handler(Func<HttpRequestMessage, Task<HttpResponseMessage>> run) : HttpMessageHandler
    { protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => run(request); }
}
