using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;

internal static class CommunityChatSendTests
{
    internal static async Task Verify()
    {
        var mode = "ok";
        var posted = new List<JsonElement>();
        JsonElement? history = null;
        var historySelf = true;
        var historyText = "hello\nworld";
        using var handler = new Handler(async request =>
        {
            Check(request.Headers.Authorization?.Parameter == "fixture-bearer", "current bearer only");
            var path = request.RequestUri!.AbsolutePath;
            if (path == "/api/fleets/directory") return Json(new
            {
                schemaVersion = 1, membershipModelVersion = 2, view = "mine", query = "", next = (string?)null,
                items = new[] { "A", "B" }.Select(code => new { code, name = code, description = "", language = "", activeTime = "",
                    memberCount = 2, relationship = "member", joinMode = "direct", actions = new[] { "leave" }, logoImageData = (string?)null }),
            });
            if (request.Method == HttpMethod.Get)
            {
                if (path.EndsWith("channels")) return Json(new { totalUnread = 0,
                    channels = new[] { new { type = "fleet", channelId = "fleet:A", unreadCount = 0, canSend = true } } });
                Check(history is not null && path.EndsWith("messages"), "only known history route");
                return Json(new { schemaVersion = 1, channelId = "fleet:A", latestSequence = 20, oldestSequence = 20,
                    hasOlder = false, canSend = true, serverTime = "2026-09-08T00:00:00Z", messages = new[] { new {
                        sequence = 20, messageId = history!.Value.GetProperty("clientMessageId").GetString(), senderAccountId = "private-sender",
                        senderCallsign = "Example", senderGameId = "", senderRoleTitle = "成员", senderRoleColor = "#29AFFF",
                        text = historyText, createdAt = "2026-09-08T00:00:00Z", isSelf = historySelf, hasAvatar = false, hasAttachment = false,
                    } } });
            }
            Check(path == "/api/fleets/chat/messages" && request.Method == HttpMethod.Post, "exact live POST route");
            using var body = JsonDocument.Parse(await request.Content!.ReadAsStringAsync());
            posted.Add(body.RootElement.Clone());
            if (mode == "lost") throw new HttpRequestException("fixture disconnected");
            if (mode.StartsWith("status-")) return new((HttpStatusCode)int.Parse(mode[7..]));
            if (mode == "malformed") return new(HttpStatusCode.OK) { Content = new StringContent("{") };
            if (mode == "oversized") return new(HttpStatusCode.OK) { Content = new StringContent(new string('x', 2 * 1024 * 1024 + 1)) };
            var sent = body.RootElement;
            var response = JsonSerializer.SerializeToNode(new {
                status = "sent", error = (string?)null, message = new {
                    sequence = 12, messageId = sent.GetProperty("clientMessageId").GetString(), channelId = sent.GetProperty("channelId").GetString(),
                    text = sent.GetProperty("text").GetString(), attachment = sent.GetProperty("attachment").Clone(),
                    senderAccountId = "private-sender", senderAvatarImageData = "private-extra-never-export",
                }
            })!;
            switch (mode)
            {
                case "wrong-id": response["message"]!["messageId"] = "other"; break;
                case "wrong-channel": response["message"]!["channelId"] = "fleet:B"; break;
                case "wrong-text": response["message"]!["text"] = "different"; break;
                case "wrong-attachment": response["message"]!["attachment"] = null; break;
                case "wrong-sequence": response["message"]!["sequence"] = 0; break;
                case "wrong-status": response["status"] = "accepted"; break;
            }
            return Json(response);
        });
        using var client = new CommunityClient(new Uri("https://community.invalid"), handler);
        var directory = await client.ReadAsync("fixture-bearer", new("mine", "", null, null), "scope", default);
        var a = directory.Items[0].TargetRef; var b = directory.Items[1].TargetRef;
        JsonElement Body(string target, string id, string text = "hello\nworld", object? attachment = null) =>
            JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = target, requestId = id, text, attachment });
        async Task<JsonElement> Send(JsonElement body, string scope = "scope", Action? current = null) =>
            JsonSerializer.SerializeToElement(await client.SendChatAsync("fixture-bearer", body, scope, current ?? (() => {}), default));
        string Id() => Guid.NewGuid().ToString("N");
        var id = Id();
        var bodyA = Body(a, id, " hello\nworld ");
        var sent = await Send(bodyA);
        Check(sent.GetProperty("status").GetString() == "accepted" && sent.GetProperty("sequence").GetInt64() == 12, "correlated accepted receipt");
        Check(sent.GetProperty("requestId").GetString() == id && !sent.GetRawText().Contains("private-"), "receipt excludes raw sender/avatars");
        Check(posted[0].GetProperty("text").GetString() == "hello\nworld" && posted[0].GetProperty("fleetCode").GetString() == "A", "WPF normalization and scoped target");
        Check((await Send(bodyA)).GetProperty("status").GetString() == "accepted" && posted.Count == 1, "duplicate click never reposts");
        Check((await Send(Body(a, id, "changed"))).GetProperty("error").GetString() == "intentConflict" && posted.Count == 1, "request id binds original intention");
        await Send(Body(b, id));
        Check(posted[1].GetProperty("fleetCode").GetString() == "B" && posted[0].GetProperty("clientMessageId").GetString() != posted[1].GetProperty("clientMessageId").GetString(), "same UI nonce across orgs remains separate");
        var attachment = new { kind = "overlay_preset", title = "Fixture", summary = "Shared fixture",
            overlayPresetPackage = "{\"version\":1,\"name\":\"Fixture\",\"settings\":\"{}\",\"layout\":\"{}\"}" };
        Check((await Send(Body(a, Id(), "", attachment))).GetProperty("status").GetString() == "accepted", "attachment-only existing WPF message supported");
        foreach (var failure in new[] { "lost", "malformed", "oversized", "wrong-id", "wrong-channel", "wrong-text", "wrong-sequence", "wrong-status", "status-500", "status-302", "wrong-attachment" })
        {
            mode = failure;
            var attempt = Body(a, Id(), attachment: failure == "wrong-attachment" ? attachment : null);
            var count = posted.Count;
            var result = await Send(attempt);
            Check(result.GetProperty("status").GetString() == "unknown" && result.GetProperty("sequence").ValueKind == JsonValueKind.Null, "unknown not false acceptance: " + failure);
            await Send(attempt);
            Check(posted.Count == count + 1, "unknown cannot silently repost: " + failure);
        }
        foreach (var (status, error) in new[] { (400,"dataInvalid"), (401,"identityUnavailable"), (403,"notAllowed"), (404,"refreshRequired"), (409,"intentConflict"), (429,"rateLimited") })
        {
            mode = "status-" + status;
            var result = await Send(Body(a, Id()));
            Check(result.GetProperty("status").GetString() == "rejected" && result.GetProperty("error").GetString() == error, "server rejection: " + status);
        }
        mode = "lost";
        var lostId = Id();
        var lost = Body(a, lostId);
        await Send(lost);
        history = posted.Last();
        async Task<JsonElement> Read() => JsonSerializer.SerializeToElement(await client.ReadChatAsync("fixture-bearer",
            JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = a, after = 0, before = 0 }), "scope", () => {}, default));
        historySelf = false;
        Check((await Read()).GetProperty("messages")[0].GetProperty("localRequestId").ValueKind == JsonValueKind.Null, "other author cannot reconcile send");
        historySelf = true; historyText = "wrong";
        Check((await Read()).GetProperty("messages")[0].GetProperty("localRequestId").ValueKind == JsonValueKind.Null, "changed text cannot reconcile send");
        historyText = "hello\nworld";
        var recovered = await Read();
        Check(recovered.GetProperty("messages")[0].GetProperty("localRequestId").GetString() == lostId, "own actual history resolves lost receipt");
        var postCount = posted.Count;
        var confirmed = await Send(lost);
        Check(confirmed.GetProperty("status").GetString() == "accepted" && confirmed.GetProperty("sequence").GetInt64() == 20 && posted.Count == postCount, "reconciled receipt returned without POST");
        Check((await Send(Body(a, Id()), "other-account")).GetProperty("status").GetString() == "rejected" && posted.Count == postCount, "account scoped target checked before send");
        var checks = 0;
        mode = "ok";
        Check((await Send(Body(a, Id()), current: () => { if (++checks == 3) throw new AccountBridgeHostException("communities.identityUnavailable"); })).GetProperty("status").GetString() == "unknown", "changed account after POST never accepted");
        foreach (var invalid in new[] { Body(a, Id(), ""), Body(a, Id(), new string('x',1001)), Body(a, "not-a-reference"),
            JsonSerializer.SerializeToElement(new { schemaVersion=1, targetRef=a, requestId=Id() }),
            Body(a, Id(), attachment: new { kind="overlay_preset", title="Fixture" }),
            Body(a, Id(), attachment: new { kind="fleet_invitation",title="Fixture",summary="Fixture",overlayPresetPackage=attachment.overlayPresetPackage }) })
        {
            var count = posted.Count;
            try { await Send(invalid); throw new InvalidOperationException("Expected invalid payload"); }
            catch (AccountBridgeHostException e) when (e.Code == "communities.dataInvalid") {}
            Check(posted.Count == count, "invalid payload never posted");
        }
    }
    private static HttpResponseMessage Json(object value) => new(HttpStatusCode.OK) { Content = JsonContent.Create(value) };
    private static void Check(bool condition, string label) { if (!condition) throw new InvalidOperationException(label); }
    private sealed class Handler(Func<HttpRequestMessage, Task<HttpResponseMessage>> run) : HttpMessageHandler
    { protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => run(request); }
}
