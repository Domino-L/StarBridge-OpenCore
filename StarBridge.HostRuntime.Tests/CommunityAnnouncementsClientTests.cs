using System.Net;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;

internal static class CommunityAnnouncementsClientTests
{
    internal static async Task Verify()
    {
        var mode = "ok";
        var calls = 0;
        var image = new byte[400 * 1024];
        new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 }.CopyTo(image, 0);
        var avatar = "data:image/png;base64," + Convert.ToBase64String(image);
        object Author(bool detail, bool legacy = false) => new { accountId = legacy ? "legacy" : "hidden-account-id", callsign = "Author",
            gameId = "VisibleGameId", roleTitle = "成员", roleColor = "#47AAEE", avatarImageData = detail ? avatar : null,
            secret = "must-not-export" };
        object Entry(string id, bool detail, bool archived = false) => new { authorHasAvatar = true, lastEditorHasAvatar = true,
            announcement = new { id, fleetCode = "A", title = "Announcement", content = "Body\ntext", revision = 2,
                state = archived ? "Archived" : "Published", publishedAt = "2026-09-07T00:00:00Z", updatedAt = "2026-09-08T00:00:00Z",
                archivedAt = archived ? "2026-09-08T00:00:00Z" : null, withdrawnAt = (string?)null,
                author = Author(detail), lastEditor = Author(detail) } };
        using var handler = new Handler(request =>
        {
            calls++;
            Check(request.Method == HttpMethod.Get && request.Headers.Authorization?.Parameter == "test-bearer", "only authorized GET requests");
            var path = request.RequestUri!.AbsolutePath;
            var query = Uri.UnescapeDataString(request.RequestUri.Query);
            if (path == "/api/fleets/directory") return Json(new { schemaVersion = 1, membershipModelVersion = 2, view = "mine", query = "",
                next = (string?)null, items = new[] { "A", "B" }.Select(code => new { code, name = "Organization " + code, description = "",
                    language = "", activeTime = "", memberCount = 2, relationship = "member", joinMode = "direct", actions = new[] { "leave" },
                    logoImageData = (string?)null }) });
            Check(path == "/api/fleets/announcements" && query.Contains("fleetCode=A"), "one existing route and resolved organization only");
            if (mode.StartsWith("status-")) return new((HttpStatusCode)int.Parse(mode[7..]));
            if (mode == "lost") throw new HttpRequestException("disconnected");
            if (mode == "duplicate-json") return new(HttpStatusCode.OK) { Content = new StringContent("{\"schemaVersion\":1,\"schemaVersion\":2}") };
            if (query.Contains("view=detail"))
            {
                Check(query.Contains("announcementId=actual-id") && query.Contains("expectedRevision=30"), "detail is pinned to the previously read record/version");
                var node = JsonSerializer.SerializeToNode(new { schemaVersion = 1, membershipModelVersion = 2, fleetCode = "A", revision = 30L,
                    canManage = mode != "revoked", refreshedAt = "2026-09-08T00:00:00Z", entry = Entry("actual-id", true) })!;
                switch (mode)
                {
                    case "detail-other": node["entry"]!["announcement"]!["id"] = "another-id"; break;
                    case "detail-metadata": node["entry"]!["announcement"]!["title"] = "Replaced title"; break;
                    case "detail-author": node["entry"]!["announcement"]!["author"]!["accountId"] = "another-person"; break;
                    case "avatar-lied": node["entry"]!["authorHasAvatar"] = false; break;
                    case "bad-avatar": node["entry"]!["announcement"]!["author"]!["avatarImageData"] = "data:image/png;base64,YmFk"; break;
                    case "bare-avatar": node["entry"]!["announcement"]!["author"]!["avatarImageData"] = Convert.ToBase64String(image); break;
                    case "changed-avatar": node["entry"]!["announcement"]!["author"]!["avatarImageData"] = "data:image/png;base64," + Convert.ToBase64String(image[..^1]); break;
                }
                return Json(node);
            }
            Check(query.Contains("view=client"), "page opts into bounded projection");
            var offset = query.Contains("offset=20") ? 20 : 0;
            if (offset > 0) Check(query.Contains("expectedRevision=30"), "next page requires snapshot revision");
            var page = JsonSerializer.SerializeToNode(new { schemaVersion = 1, membershipModelVersion = 2, fleetCode = "A", revision = 30L,
                canManage = true, current = Entry("actual-id", false), history = Enumerable.Range(offset, offset == 0 ? 20 : 1).Select(i => Entry("history-" + i.ToString("D2"), false, true)),
                offset, next = offset == 0 ? (int?)20 : null, totalHistoryCount = 21, refreshedAt = "2026-09-08T00:00:00Z", secret = "must-not-export" })!;
            switch (mode)
            {
                case "wrong-code": page["fleetCode"] = "B"; break;
                case "wrong-schema": page["schemaVersion"] = 2; break;
                case "wrong-membership": page["membershipModelVersion"] = 1; break;
                case "bad-count": page["totalHistoryCount"] = 19; break;
                case "bad-next": page["next"] = 19; break;
                case "bad-state": page["current"]!["announcement"]!["state"] = "Withdrawn"; break;
                case "bad-history": page["history"]![0]!["announcement"]!["state"] = "Published"; break;
                case "duplicate-id": page["history"]![0]!["announcement"]!["id"] = "actual-id"; break;
                case "bad-order": page["history"]![1]!["announcement"]!["id"] = "history-00"; break;
                case "inline-avatar": page["current"]!["announcement"]!["author"]!["avatarImageData"] = avatar; break;
                case "bad-color": page["current"]!["announcement"]!["author"]!["roleColor"] = "red"; break;
                case "bad-time": page["current"]!["announcement"]!["updatedAt"] = "unknown"; break;
                case "too-large": page["extra"] = new string('x', 500000); break;
                case "legacy": page["current"]!["announcement"]!["author"]!["accountId"] = "legacy"; break;
                case "empty": page["current"] = null; page["history"] = new JsonArray(); page["totalHistoryCount"] = 0; page["next"] = null; page["revision"] = 0; break;
            }
            return Json(page);
        });
        var clock = new TargetClock();
        using var client = new CommunityClient(new Uri("https://community.invalid"), handler, clock);
        var directory = await client.ReadAsync("test-bearer", new("mine", "", null, null), "scope", default);
        var a = directory.Items[0].TargetRef;
        var b = directory.Items[1].TargetRef;
        JsonElement Body(int offset = 0, long? revision = null) => JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = a, offset, expectedRevision = revision });
        async Task<JsonElement> Read(JsonElement? body = null, string scope = "scope", Action? current = null) => JsonSerializer.SerializeToElement(
            await client.ReadAnnouncementsAsync("test-bearer", body ?? Body(), scope, current ?? (() => { }), default));
        var first = await Read();
        var announcementRef = first.GetProperty("current").GetProperty("announcementRef").GetString()!;
        Check(first.GetProperty("history").GetArrayLength() == 20 && first.GetProperty("current").GetProperty("author").GetProperty("memberRef").GetString()!.Length == 32,
            "current and bounded history carry scoped avatar-menu references");
        Check(!first.ToString().Contains("hidden-account-id") && !first.ToString().Contains("actual-id")
            && !first.ToString().Contains("must-not-export") && !first.ToString().Contains("fleetCode"), "private ids and server extras never cross bridge");
        Check((await Read()).GetProperty("current").GetProperty("announcementRef").GetString() == announcementRef, "unchanged records keep stable short-lived references");
        Check((await Read(Body(20, 30))).GetProperty("history").GetArrayLength() == 1, "remaining history page");
        var before = calls;
        await Reject(() => Read(Body(20)), "communities.dataInvalid");
        await Reject(() => Read(scope: "other-account"), "communities.refreshRequired");
        Check(calls == before, "invalid scope or paging fails before HTTP");
        JsonElement DetailBody(int offset = 0, string? version = null, string? targetRef = null) => JsonSerializer.SerializeToElement(new
            { schemaVersion = 1, targetRef = targetRef ?? a, announcementRef, offset, version });
        async Task<JsonElement> Detail(JsonElement? body = null, Action? current = null) => JsonSerializer.SerializeToElement(
            await client.ReadAnnouncementDetailAsync("test-bearer", body ?? DetailBody(), "scope", current ?? (() => { }), default));
        before = calls;
        await Reject(() => Detail(DetailBody(targetRef: b)), "communities.refreshRequired");
        await Reject(() => Detail(DetailBody(1)), "communities.dataInvalid");
        Check(calls == before, "cross-organization references never reach service");
        var chunks = new List<byte>();
        string? hash = null;
        int? nextOffset = 0;
        do
        {
            var chunk = await Detail(DetailBody(nextOffset!.Value, hash));
            Check(chunk.GetProperty("targetRef").GetString() == a && chunk.GetProperty("announcementRef").GetString() == announcementRef
                && chunk.GetProperty("offset").GetInt32() == nextOffset, "chunk identity and cursor preserved");
            hash ??= chunk.GetProperty("version").GetString();
            Check(chunk.GetProperty("version").GetString() == hash, "one stable content hash across chunks");
            var bytes = Convert.FromBase64String(chunk.GetProperty("data").GetString()!);
            Check(bytes.Length <= 192 * 1024, "bounded chunk");
            chunks.AddRange(bytes);
            nextOffset = chunk.GetProperty("next").ValueKind == JsonValueKind.Null ? null : chunk.GetProperty("next").GetInt32();
        } while (nextOffset is not null);
        Check(Convert.ToHexString(SHA256.HashData(chunks.ToArray())).ToLowerInvariant() == hash, "whole detail integrity");
        using (var payload = JsonDocument.Parse(chunks.ToArray()))
            Check(payload.RootElement.EnumerateObject().Count() == 2 && payload.RootElement.GetProperty("authorAvatarImageData").GetString() == avatar,
                "detail contains only original avatars, no hidden identity");
        mode = "bare-avatar";
        Check((await Detail()).GetProperty("version").GetString() == hash, "legacy raw base64 normalizes to the same actual image");
        mode = "changed-avatar";
        await Reject(() => Detail(DetailBody(192 * 1024, hash)), "communities.announcementsChanged");
        foreach (var failure in new[] { "detail-other", "detail-metadata", "detail-author" })
        { mode = failure; await Reject(() => Detail(), "communities.announcementsChanged"); }
        foreach (var failure in new[] { "avatar-lied", "bad-avatar" })
        { mode = failure; await Reject(() => Detail(), "communities.dataInvalid"); }
        mode = "revoked";
        Check(!(await Detail()).GetProperty("canManage").GetBoolean(), "detail does not cache old manage permission");
        foreach (var (status, error) in new[] { (401, "identityUnavailable"), (403, "notAllowed"), (404, "notFound"), (409, "announcementsChanged"), (503, "unavailable") })
        { mode = "status-" + status; await Reject(() => Detail(), "communities." + error); }
        foreach (var failure in new[] { "wrong-code", "wrong-schema", "wrong-membership", "bad-count", "bad-next", "bad-state", "bad-history",
            "duplicate-id", "bad-order", "inline-avatar", "bad-color", "bad-time", "too-large", "duplicate-json" })
        { mode = failure; await Reject(() => Read(), "communities.dataInvalid"); }
        mode = "legacy";
        Check((await Read()).GetProperty("current").GetProperty("author").GetProperty("memberRef").ValueKind == JsonValueKind.Null,
            "historical placeholder does not impersonate an account menu");
        mode = "empty";
        Check((await Read()).GetProperty("current").ValueKind == JsonValueKind.Null, "confirmed empty remains empty");
        mode = "ok";
        var checks = 0;
        await Reject(() => Read(current: () => { if (++checks == 2) throw new AccountBridgeHostException("stale"); }), "stale");
        checks = 0;
        await Reject(() => Detail(current: () => { if (++checks == 2) throw new AccountBridgeHostException("stale"); }), "stale");
        clock.Advance(TimeSpan.FromMinutes(4));
        await Read();
        clock.Advance(TimeSpan.FromMinutes(4));
        await Read();
        Check(calls > 0, "successful authorized reads preserve an active target beyond five minutes");
        before = calls;
        await Reject(() => Detail(DetailBody(targetRef: b)), "communities.refreshRequired");
        Check(calls == before, "reading one organization does not renew another organization");
        clock.Advance(TimeSpan.FromMinutes(4));
        mode = "status-503";
        await Reject(() => Read(), "communities.unavailable");
        clock.Advance(TimeSpan.FromMinutes(2));
        before = calls;
        mode = "ok";
        await Read();
        Check(calls > before, "expired page recovers only through fresh authorized transport");
    }
    private static async Task Reject(Func<Task<JsonElement>> action, string code)
    {
        try { await action(); throw new InvalidOperationException("Expected " + code); }
        catch (AccountBridgeHostException e) { Check(e.Code == code, "Expected " + code + ", got " + e.Code); }
    }
    private static HttpResponseMessage Json(object body) => new(HttpStatusCode.OK) { Content = JsonContent.Create(body) };
    private static void Check(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
    private sealed class Handler(Func<HttpRequestMessage, HttpResponseMessage> respond) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => Task.FromResult(respond(request));
    }
    private sealed class TargetClock : TimeProvider
    {
        private DateTimeOffset _now = DateTimeOffset.UtcNow;
        public override DateTimeOffset GetUtcNow() => _now;
        public void Advance(TimeSpan duration) => _now += duration;
    }
}
