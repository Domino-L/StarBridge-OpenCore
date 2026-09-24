using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Communities;

internal static class CommunityWpfS2WriteTests
{
    internal static async Task Verify()
    {
        var posts = 0;
        var mode = "ok";
        var canManage = true;
        var revision = 1;
        var recordRevision = 1;
        var withdrawn = false;
        var title = "Original";
        var content = "Original body";
        const string time = "2026-09-10T00:00:00Z";
        object Author() => new { accountId = "self", callsign = "Owner", gameId = "Game", roleTitle = "负责人", roleColor = "#47AAEE", avatarImageData = (string?)null };
        object Record() => new { id = "announcement", fleetCode = "A", title, content,
            state = withdrawn ? "Withdrawn" : "Published", revision = recordRevision, publishedAt = time, updatedAt = time,
            withdrawnAt = withdrawn ? time : null, archivedAt = (string?)null, author = Author(), lastEditor = Author() };
        object Timeline() => new { fleetCode = "A", revision, canManage, refreshedAt = time,
            current = withdrawn ? null : Record(), history = withdrawn ? new[] { Record() } : Array.Empty<object>() };
        using var handler = new Handler(request =>
        {
            Check(request.Headers.Authorization?.Parameter == "fixture", "Authenticated only");
            Check(!request.RequestUri!.Query.Contains("view="), "Never use new projection on S2");
            var path = request.RequestUri.AbsolutePath;
            if (request.Method == HttpMethod.Get)
            {
                if (path == "/api/fleets/membership") return Json(new { fleetCode = "A" });
                if (path == "/api/fleets") return Json(new[] { new { code = "A", name = "Fixture", totalMembers = 1 } });
                if (path == "/api/fleets/announcements") return Json(Timeline());
                throw new InvalidOperationException("Unexpected GET");
            }
            posts++;
            Check(request.Method == HttpMethod.Post, "Only WPF posts");
            using var document = JsonDocument.Parse(request.Content!.ReadAsStringAsync().GetAwaiter().GetResult());
            var body = document.RootElement;
            Check(body.GetProperty("fleetCode").GetString() == "A", "Selected fleet only");
            if (mode == "lost") throw new HttpRequestException("fixture lost response");
            if (mode == "forbidden") return new(HttpStatusCode.Forbidden);
            if (mode == "conflict") return new(HttpStatusCode.Conflict);
            if (path == "/api/fleets/chat/messages")
                return Json(new { status = (string?)null, message = new { sequence = 1,
                    messageId = body.GetProperty("clientMessageId").GetString(), channelId = "fleet:A",
                    senderAccountId = mode == "wrong-sender" ? "other" : "self", text = body.GetProperty("text").GetString(),
                    attachment = (object?)null } });
            var action = path.Split('/').Last();
            Check(action is "publish" or "edit" or "withdraw", "Existing announcement mutation only");
            if (action != "publish") Check(body.GetProperty("expectedRevision").GetInt32() == recordRevision, "Original record concurrency token");
            revision++; recordRevision++;
            if (action == "withdraw") withdrawn = true;
            else { withdrawn = false; title = body.GetProperty("title").GetString()!; content = body.GetProperty("content").GetString()!; }
            var result = JsonSerializer.SerializeToNode(new { status = action == "publish" ? "published" : action == "edit" ? "edited" : "withdrawn", timeline = Timeline() })!;
            switch (mode)
            {
                case "wrong-fleet": result["timeline"]!["fleetCode"] = "B"; break;
                case "wrong-editor": result["timeline"]!["current"]!["lastEditor"]!["accountId"] = "other"; break;
                case "wrong-content": result["timeline"]!["current"]!["content"] = "Different"; break;
                case "wrong-status": result["status"] = "saved"; break;
                case "stale-timeline": result["timeline"]!["revision"] = 0; break;
                case "malformed": return new(HttpStatusCode.OK) { Content = new StringContent("{") };
            }
            return Json(result);
        });
        using var client = new CommunityClient(new Uri("https://fixture.invalid"), handler);
        var mine = await client.ReadWpfS2Async("fixture", new("mine", "", null, null), "scope", "self", default);
        var target = mine.Items.Single().TargetRef;
        JsonElement Send(string id, string text = "Hello") => Body(new { schemaVersion = 1, targetRef = target, requestId = id, text });
        async Task<JsonElement> Chat(JsonElement body, string scope = "scope") => Body(await client.SendChatAsync("fixture", body, scope, () => { }, default));
        var send = Send(new string('a', 32));
        Status(await Chat(send), "accepted");
        var count = posts;
        Status(await Chat(send), "accepted"); Check(posts == count, "No duplicate chat POST");
        Status(await Chat(Send(new string('a', 32), "Different")), "rejected");
        mode = "lost"; send = Send(new string('b', 32));
        Status(await Chat(send), "unknown"); count = posts;
        Status(await Chat(send), "unknown"); Check(posts == count, "Uncertain chat never replayed");
        mode = "wrong-sender"; Status(await Chat(Send(new string('c', 32))), "unknown");
        mode = "forbidden"; Status(await Chat(Send(new string('d', 32))), "rejected");
        count = posts; Status(await Chat(Send(new string('e', 32)), "other-scope"), "rejected"); Check(posts == count, "No cross-account POST");
        mode = "ok";
        async Task<string> Reference()
        {
            var page = Body(await client.ReadAnnouncementsAsync("fixture", Body(new { schemaVersion = 1, targetRef = target, offset = 0 }), "scope", () => { }, default));
            Check(page.GetProperty("canManage").GetBoolean() == canManage, "Management uses server permission");
            return page.GetProperty("current").GetProperty("announcementRef").GetString()!;
        }
        JsonElement Intent(string id, string action, string? reference = null) => Body(new { schemaVersion = 1, targetRef = target, requestId = id, action,
            announcementRef = reference, title = action == "withdraw" ? null : "New title", content = action == "withdraw" ? null : "New\nbody" });
        async Task<JsonElement> Write(JsonElement body) => Body(await client.ManageAnnouncementsAsync("fixture", body, "scope", () => { }, default));
        var publish = Intent(new string('1', 32), "publish");
        Status(await Write(publish), "accepted"); count = posts;
        Status(await Write(publish), "accepted"); Check(posts == count, "No duplicate announcement POST");
        var reference = await Reference();
        Status(await Write(Intent(new string('2', 32), "edit", reference)), "accepted");
        count = posts;
        Status(await Write(Intent(new string('3', 32), "edit", reference)), "rejected"); Check(posts == count, "Stale record stopped before POST");
        reference = await Reference();
        canManage = false; count = posts;
        Status(await Write(Intent(new string('4', 32), "withdraw", reference)), "rejected"); Check(posts == count, "Permission loss stopped before POST");
        canManage = true; mode = "conflict";
        Status(await Write(Intent(new string('5', 32), "edit", reference)), "rejected");
        mode = "lost"; var lost = Intent(new string('6', 32), "withdraw", reference);
        Status(await Write(lost), "unknown"); count = posts;
        Status(await Write(lost), "unknown"); Check(posts == count, "Uncertain announcement never replayed");
        mode = "ok"; Status(await Write(Intent(new string('7', 32), "withdraw", reference)), "accepted");
        foreach (var invalid in new[] { "wrong-fleet", "wrong-editor", "wrong-content", "wrong-status", "stale-timeline", "malformed" })
        {
            mode = invalid;
            var intent = Intent(Guid.NewGuid().ToString("N"), "publish");
            Status(await Write(intent), "unknown"); count = posts;
            Status(await Write(intent), "unknown"); Check(posts == count, "Invalid receipt never permits automatic replay");
        }
    }
    private static JsonElement Body(object value) => JsonSerializer.SerializeToElement(value);
    private static HttpResponseMessage Json(object value) => new(HttpStatusCode.OK) { Content = JsonContent.Create(value) };
    private static void Status(JsonElement result, string expected) => Check(result.GetProperty("status").GetString() == expected, "Expected " + expected + ": " + result);
    private static void Check(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
    private sealed class Handler(Func<HttpRequestMessage, HttpResponseMessage> send) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => Task.FromResult(send(request));
    }
}
