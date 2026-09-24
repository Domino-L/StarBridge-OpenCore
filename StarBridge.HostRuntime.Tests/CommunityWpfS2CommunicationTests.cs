using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Security.Cryptography;
using System.Text;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;

internal static class CommunityWpfS2CommunicationTests
{
    internal static async Task Verify()
    {
        await VerifyMultipleMemberships();
        var calls = 0;
        var forbidden = false;
        var receiptLost = false;
        long revision = 30;
        using var handler = new Handler(request =>
        {
            calls++;
            Check(request.Headers.Authorization?.Parameter == "test-token", "Authenticated requests only");
            if (forbidden) return new(HttpStatusCode.Forbidden);
            var path = request.RequestUri!.AbsolutePath;
            if (request.Method == HttpMethod.Post)
            {
                Check(path == "/api/fleets/chat/read", "Only existing WPF read receipt may write");
                using var body = JsonDocument.Parse(request.Content!.ReadAsStringAsync().GetAwaiter().GetResult());
                Check(body.RootElement.GetProperty("fleetCode").GetString() == "A" && body.RootElement.GetProperty("throughSequence").GetInt64() == 11,
                    "Receipt uses previously fetched message, never an arbitrary sequence");
                if (receiptLost) throw new HttpRequestException("fixture response lost");
                return Json(new { channelId = "fleet:A", readThroughSequence = 11 });
            }
            Check(request.Method == HttpMethod.Get, "No unrelated mutations");
            var query = Uri.UnescapeDataString(request.RequestUri.Query);
            Check(!query.Contains("projection=") && !query.Contains("view="), "S2 uses the existing WPF contract, not new server projections");
            if (path == "/api/fleets/membership") return Json(new { fleetCode = "A", fleetCodes = new[] { "A" } });
            if (path == "/api/fleets") return Json(new[] { new { code = "A", name = "Fixture", totalMembers = 2, logoImageData = Pixel } });
            Check(query.Contains("fleetCode=A"), "Only selected organization");
            if (path == "/api/fleets/chat/channels") return Json(new { totalUnread = 2,
                channels = new[] { new { channelId = "fleet:A", type = "fleet", unreadCount = 2, canSend = true } } });
            if (path == "/api/fleets/chat/messages")
            {
                long Parameter(string key, long fallback = 0) => query.TrimStart('?').Split('&').FirstOrDefault(p => p.StartsWith(key + "=")) is { } match ? long.Parse(match[(key.Length + 1)..]) : fallback;
                var after = Parameter("after"); var before = Parameter("before"); var limit = (int)Parameter("limit", 50);
                var eligible = Enumerable.Range(1, 60).Where(i => i > after && (before == 0 || i < before));
                var rows = (after > 0 ? eligible.Take(limit) : eligible.TakeLast(limit)).ToArray();
                return Json(new { channelId = "fleet:A", latestSequence = 60, oldestSequence = rows.FirstOrDefault(),
                    hasOlder = rows.Length > 0 && rows[0] > 1, serverTime = Time, canSend = true,
                    messages = rows.Select(i => new { sequence = i, messageId = "msg-" + i, channelId = "fleet:A",
                        senderAccountId = i % 2 == 0 ? "self-id" : "other-id", senderCallsign = "Visible", senderGameId = "VisibleGame",
                        senderRoleTitle = "成员", senderRoleColor = "#47AAEE", text = "Original\nmessage", createdAt = Time,
                        senderAvatarImageData = Pixel, attachment = (object?)null, secret = "must-not-export" }) });
            }
            if (path == "/api/fleets/announcements") return Json(new { fleetCode = "A", revision, canManage = true,
                refreshedAt = Time, current = Announcement("current", false),
                history = Enumerable.Range(0, 21).Select(i => Announcement("history-" + i.ToString("D2"), true)) });
            return new(HttpStatusCode.NotFound);
        });
        using var client = new CommunityClient(new Uri("https://relay.invalid"), handler);
        var mine = await client.ReadWpfS2Async("test-token", new("mine", "", null, null), "scope", "self-id", default);
        var target = mine.Items.Single().TargetRef;
        Check(client.CachedSharingLogo("scope", "A") == mine.Items.Single().LogoImageData &&
            client.CachedSharingLogo("scope", "A") is not null,
            "Sharing reuses the authorized organization logo");
        Check(client.CachedSharingLogo("other-scope", "A") is null,
            "Sharing logos cannot cross account scopes");
        JsonElement Chat(long after = 0, long before = 0) => Body(new { schemaVersion = 1, targetRef = target, after, before });
        var chat = Body(await client.ReadChatAsync("test-token", Chat(), "scope", () => { }, default));
        Check(chat.GetProperty("messages").GetArrayLength() == 50 && chat.GetProperty("hasOlder").GetBoolean(), "S2 latest history paginates 50 messages");
        Check(!chat.GetRawText().Contains("self-id") && !chat.GetRawText().Contains("must-not-export"), "Private raw identities and extras stay in Host");
        Check(chat.GetProperty("canSend").GetBoolean(), "Sending follows the authenticated S2 server capability");
        Check(chat.GetProperty("messages")[1].GetProperty("isSelf").GetBoolean(), "Self comes from authenticated account identity");
        var avatarVersion = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(Pixel))).ToLowerInvariant();
        Check(chat.GetProperty("messages").EnumerateArray().All(m => m.GetProperty("avatarVersion").GetString() == avatarVersion),
            "Avatar content version is stable across messages without exporting image data in metadata");
        Check(!chat.GetRawText().Contains("base64"), "Chat metadata does not repeat avatar bytes per message");
        var older = Body(await client.ReadChatAsync("test-token", Chat(before: 11), "scope", () => { }, default));
        Check(older.GetProperty("messages").GetArrayLength() == 10 && !older.GetProperty("hasOlder").GetBoolean(), "Earlier history uses the existing cursor");
        Check(older.GetProperty("messages")[0].GetProperty("senderRef").GetString() ==
            chat.GetProperty("messages")[0].GetProperty("senderRef").GetString(), "Same sender reference survives history pagination for scoped avatar reuse");
        var messageRef = chat.GetProperty("messages")[0].GetProperty("messageRef").GetString();
        var detail = Body(await client.ReadChatDetailAsync("test-token", Body(new { schemaVersion = 1, targetRef = target, messageRef, offset = 0 }), "scope", () => { }, default));
        using var decoded = JsonDocument.Parse(Convert.FromBase64String(detail.GetProperty("data").GetString()!));
        Check(decoded.RootElement.GetProperty("avatarImageData").GetString() == Pixel, "Original chat author image survives");
        var receiptBody = Body(new { schemaVersion = 1, targetRef = target, messageRef });
        var receipt = Body(await client.MarkChatReadAsync("test-token", receiptBody, "scope", () => { }, default));
        Check(receipt.GetProperty("status").GetString() == "accepted", "S2 visible-message receipt uses the WPF endpoint");
        receiptLost = true;
        var beforeLost = calls;
        receipt = Body(await client.MarkChatReadAsync("test-token", receiptBody, "scope", () => { }, default));
        Check(receipt.GetProperty("status").GetString() == "unknown" && calls == beforeLost + 1, "Lost receipt never auto-replays or claims success");
        JsonElement Page(int offset = 0, long? expectedRevision = null) => Body(new { schemaVersion = 1, targetRef = target, offset, expectedRevision });
        var announcements = Body(await client.ReadAnnouncementsAsync("test-token", Page(), "scope", () => { }, default));
        Check(announcements.GetProperty("history").GetArrayLength() == 20 && announcements.GetProperty("next").GetInt32() == 20, "Announcement history paginates without requiring new server projection");
        Check(announcements.GetProperty("current").GetProperty("content").GetString() == "Original\nannouncement", "Full announcement body preserved");
        Check(!announcements.GetRawText().Contains("author-id") && !announcements.GetRawText().Contains("base64"), "List hides raw identities and transports images separately");
        var last = Body(await client.ReadAnnouncementsAsync("test-token", Page(20, 30), "scope", () => { }, default));
        Check(last.GetProperty("history").GetArrayLength() == 1 && last.GetProperty("next").ValueKind == JsonValueKind.Null, "Final history page");
        var announcementRef = announcements.GetProperty("current").GetProperty("announcementRef").GetString();
        var image = Body(await client.ReadAnnouncementDetailAsync("test-token", Body(new { schemaVersion = 1, targetRef = target, announcementRef, offset = 0 }), "scope", () => { }, default));
        using var authors = JsonDocument.Parse(Convert.FromBase64String(image.GetProperty("data").GetString()!));
        Check(authors.RootElement.GetProperty("authorAvatarImageData").GetString() == Pixel, "Original announcement author avatar");
        revision++;
        await Error(() => client.ReadAnnouncementsAsync("test-token", Page(20, 30), "scope", () => { }, default), "communities.announcementsChanged");
        var previous = calls;
        await Error(() => client.ReadChatAsync("test-token", Chat(), "other-scope", () => { }, default), "communities.refreshRequired");
        Check(calls == previous, "Cross-account rejection before HTTP");
        forbidden = true;
        await Error(() => client.ReadAnnouncementsAsync("test-token", Page(), "scope", () => { }, default), "communities.notAllowed");
        Check(calls == previous + 1, "No fallback or retry to alternate routes after membership rejection");
    }
    private static async Task VerifyMultipleMemberships()
    {
        object membership = new { fleetCode = (string?)null, fleetCodes = new[] { "A", "B" } };
        using var client = new CommunityClient(new Uri("https://fixture.invalid"), new Handler(request =>
        {
            Check(request.Method == HttpMethod.Get, "Membership reads never publish state");
            return request.RequestUri!.AbsolutePath switch
            {
                "/api/fleets/membership" => Json(membership),
                "/api/fleets" => Json(new[] {
                    new { code = "A", name = "First", totalMembers = 1 },
                    new { code = "B", name = "Second", totalMembers = 1 } }),
                _ => new(HttpStatusCode.NotFound)
            };
        }));
        async Task<CommunityPage> Read() => await client.ReadWpfS2Async("fixture", new("mine", "", null, null), "scope", "viewer", default);
        Check((await Read()).Items.Length == 2, "All memberships survive a cleared sharing context");
        membership = new { fleetCode = "A", fleetCodes = new[] { "A", "B" } };
        Check((await Read()).Items.Length == 2, "Sharing context does not truncate memberships");
        membership = new { fleetCode = "A", fleetCodes = Array.Empty<string>() };
        Check((await Read()).Items.Length == 0, "Empty authoritative membership ignores stale sharing context");
        membership = new { fleetCode = "A" };
        Check((await Read()).Items.Length == 1, "Original S2 response remains supported");
        membership = new { fleetCode = "A", fleetCodes = new[] { "A", "a" } };
        await Error(async () => await Read(), "communities.dataInvalid");
        membership = new { fleetCode = "A", fleetCodes = new[] { "A", "missing" } };
        await Error(async () => await Read(), "communities.dataInvalid");
    }
    private const string Time = "2026-09-10T00:00:00Z";
    private const string Pixel = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aM7sAAAAASUVORK5CYII=";
    private static object Announcement(string id, bool archived) => new { id, fleetCode = "A", title = "Title", content = "Original\nannouncement",
        state = archived ? "Archived" : "Published", revision = 2, publishedAt = Time, updatedAt = Time,
        archivedAt = archived ? Time : null, withdrawnAt = (string?)null, author = Author(), lastEditor = Author() };
    private static object Author() => new { accountId = "author-id", callsign = "Author", gameId = "Game", roleTitle = "成员", roleColor = "#47AAEE", avatarImageData = Pixel };
    private static JsonElement Body(object value) => JsonSerializer.SerializeToElement(value);
    private static HttpResponseMessage Json(object value) => new(HttpStatusCode.OK) { Content = JsonContent.Create(value) };
    private static void Check(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
    private static async Task Error(Func<Task<object>> read, string code)
    {
        try { await read(); throw new InvalidOperationException("Expected " + code); }
        catch (AccountBridgeHostException e) when (e.Code == code) { }
    }
    private sealed class Handler(Func<HttpRequestMessage, HttpResponseMessage> send) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => Task.FromResult(send(request));
    }
}
