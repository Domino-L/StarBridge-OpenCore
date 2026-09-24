using System.Net;
using System.Text;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.PartyRooms;
using StarBridge.NativeBridge;

internal static class PartyRoomChatTests
{
    internal static async Task Attachments()
    {
        var package = new StarBridge.HostRuntime.Overlay.OverlaySharedPreset(1, "测试", "0,CallsignAndGameName,0,0,0", "Chat,0,0,0.2,0.2").Serialize();
        var card = new StarBridge.Core.Chat.ChatAttachmentContract("overlay_preset", "测试", "预设", package);
        JsonElement Command(object attachment) => JsonSerializer.SerializeToElement(new { schemaVersion = 1, operation = "chatSend", data = new { roomId = "one", text = "", attachment } });
        var posts = 0;
        using var reader = new PartyRoomReader(new Uri("https://relay.example.test"), new Handler(request => {
            if (request.Method == HttpMethod.Get) return Ok(PartyRoomReaderTests.Wire("one", PartyRoomReaderTests.Room("one")));
            posts++;
            using var body = JsonDocument.Parse(request.Content!.ReadAsStringAsync().GetAwaiter().GetResult());
            Check(body.RootElement.GetProperty("attachment").GetProperty("overlayPresetPackage").GetString() == package, "WPF package preserved on wire.");
            throw new HttpRequestException("unknown");
        }));
        foreach (var invalid in new[] { card with { Kind = "fleet_invitation", FleetInviteCode = "ABC123" },
            card with { OverlayPresetPackage = "{}" }, card with { OverlayPresetPackage = package.Replace("Chat,0", "Chat,NaN") } }) {
            try { await reader.ExecuteAsync("test-bearer", Command(invalid), default); throw new Exception("Invalid attachment sent."); }
            catch (AccountBridgeHostException e) { Check(e.Code == "party_rooms.data_invalid" && posts == 0, "Invalid/unsupported cards never POST."); }
        }
        try { await reader.ExecuteAsync("test-bearer", Command(card), default); throw new Exception("Expected uncertain send."); }
        catch (AccountBridgeHostException e) { Check(e.Code == "party_rooms.outcome_unknown" && posts == 1, "Attachment-only send, exactly one POST and no replay."); }
    }
    internal static async Task Chat()
    {
        await InvitationReads();
        var calls = new List<string>();
        object Message(long sequence) => new { sequence, messageId = "message-" + sequence, kind = "player", senderCallsign = "呼号",
            senderGameId = "Mixed_CN", text = "消息", createdAt = "2026-09-06T12:00:00Z", senderAccountId = "private-account", senderAvatarImageData = "private-avatar" };
        JsonElement Command(string operation, object data) => JsonSerializer.SerializeToElement(new { schemaVersion = 1, operation, data });
        using var reader = new PartyRoomReader(new Uri("https://relay.example.test"), new Handler(request => {
            calls.Add(request.Method.Method);
            if (request.Method == HttpMethod.Get && request.RequestUri!.AbsolutePath == "/api/party-rooms")
                return Ok(PartyRoomReaderTests.Wire("one", PartyRoomReaderTests.Room("one")));
            if (request.Method == HttpMethod.Get) {
                Check(request.RequestUri!.Query == "?roomId=one&after=2&before=0&limit=50", "Bounded real cursor query.");
                return Ok(JsonSerializer.SerializeToUtf8Bytes(new { messages = new[] { Message(3) }, latestSequence = 6, hasOlder = true, oldestSequence = 3 }));
            }
            using var body = JsonDocument.Parse(request.Content!.ReadAsStringAsync().GetAwaiter().GetResult());
            Check(body.RootElement.GetProperty("text").GetString() == "测试文本", "Plain message text matches draft.");
            Check(!body.RootElement.TryGetProperty("senderAccountId", out _), "Sender is authenticated, never caller-selected.");
            return Ok(JsonSerializer.SerializeToUtf8Bytes(new { message = Message(7) }));
        }));
        var page = await reader.ExecuteAsync("test-bearer", Command("chatRead", new { roomId = "one", after = 2, before = 0 }), default);
        Check(page.Chat!.Messages.Single().Sequence == 3 && page.Chat.LatestSequence == 6, "Read watermark differs from server high watermark.");
        Check(ScmAccountBridgeHost.ProjectRoomChat(page, "mixed_cn").Chat!.Messages.Single().IsSelf, "Verified Handle identifies self regardless of casing.");
        Check(!ScmAccountBridgeHost.ProjectRoomChat(page, "呼号").Chat!.Messages.Single().IsSelf, "Editable callsign must never identify self.");
        Check(!ScmAccountBridgeHost.ProjectRoomChat(page, "").Chat!.Messages.Single().IsSelf, "Missing identity is not self.");
        var system = page with { Chat = page.Chat with { Messages = [page.Chat.Messages[0] with { Kind = "system" }] } };
        Check(!ScmAccountBridgeHost.ProjectRoomChat(system, "mixed_cn").Chat!.Messages.Single().IsSelf, "System events are not player bubbles.");
        Check(!BridgePayload.From(page).GetRawText().Contains("private-"), "Chat strips internal sender IDs and raw avatar data.");
        var sent = await reader.ExecuteAsync("test-bearer", Command("chatSend", new { roomId = "one", text = "测试文本" }), default);
        Check(ScmAccountBridgeHost.ProjectRoomChat(sent, "").Message!.IsSelf, "Authenticated send acknowledgement belongs to this viewer.");
        Check(sent.Status == "sent" && sent.Message!.Sequence == 7 && calls.SequenceEqual(new[] { "GET", "GET", "GET", "POST" }), "Check membership before private reads and one message write.");
        foreach (var invalid in new[] {
            Command("chatSend", new { roomId = "one", text = new string('x', 301) }),
            Command("chatSend", new { roomId = "one", text = "   " }),
            Command("chatSend", new { roomId = "one", text = "hello", senderAccountId = "forged" }),
            Command("chatRead", new { roomId = "one", after = 2, before = 3 }) }) {
            try { await reader.ExecuteAsync("test-bearer", invalid, default); throw new Exception("Invalid chat request accepted."); }
            catch (AccountBridgeHostException error) { Check(error.Code == "party_rooms.data_invalid" && calls.Count == 4, "Invalid fields never send HTTP."); }
        }
        var posts = 0;
        using var failing = new PartyRoomReader(new Uri("https://relay.example.test"), new Handler(request => {
            if (request.Method == HttpMethod.Get) return Ok(PartyRoomReaderTests.Wire("one", PartyRoomReaderTests.Room("one")));
            posts++; throw new HttpRequestException("private transport failure");
        }));
        try { await failing.ExecuteAsync("test-bearer", Command("chatSend", new { roomId = "one", text = "hello" }), default); throw new Exception("Uncertain send hidden."); }
        catch (AccountBridgeHostException error) { Check(error.Code == "party_rooms.outcome_unknown" && posts == 1, "Uncertain send is never replayed."); }
        using var left = new PartyRoomReader(new Uri("https://relay.example.test"), new Handler(request => {
            Check(request.Method == HttpMethod.Get, "Former member cannot write.");
            return Ok(PartyRoomReaderTests.Wire(null, PartyRoomReaderTests.Room("one")));
        }));
        Check((await left.ExecuteAsync("test-bearer", Command("chatSend", new { roomId = "one", text = "hello" }), default)).Error == "notMember", "Membership required.");
        Check((await left.ExecuteAsync("test-bearer", Command("chatRead", new { roomId = "one", after = 0, before = 0 }), default)).Error == "notMember", "Former members cannot fetch private history.");
        using var preflight = new PartyRoomReader(new Uri("https://relay.example.test"), new Handler(request => {
            Check(request.Method == HttpMethod.Get, "Failed preflight must not write.");
            return new HttpResponseMessage(HttpStatusCode.ServiceUnavailable);
        }));
        try { await preflight.ExecuteAsync("test-bearer", Command("chatSend", new { roomId = "one", text = "hello" }), default); throw new Exception("Preflight failure hidden."); }
        catch (AccountBridgeHostException error) { Check(error.Code == "party_rooms.command_unavailable", "Failed preflight is not an uncertain write."); }
    }
    private static async Task InvitationReads()
    {
        foreach (var member in new[] { true, false }) {
            var historyReads = 0;
            using var reader = new PartyRoomReader(new Uri("https://relay.example.test"), new Handler(request => {
                Check(request.Method == HttpMethod.Get, "Invitation history never creates or accepts a code.");
                if (request.RequestUri!.AbsolutePath == "/api/party-rooms")
                    return Ok(PartyRoomReaderTests.Wire(member ? "one" : null, PartyRoomReaderTests.Room("one")));
                historyReads++;
                return Ok(JsonSerializer.SerializeToUtf8Bytes(new {
                    messages = new[] { new { sequence = 1, messageId = "invite-card", kind = "player", senderCallsign = "成员", senderGameId = "Member",
                        text = "", createdAt = "2026-09-06T12:00:00Z", senderAccountId = "private-account",
                        attachment = new { kind = "fleet_invitation", title = "组织邀请", summary = "查看详情", fleetInviteCode = "ABCDEF12",
                            expiresAt = "2020-01-01T00:00:00Z", overlayPresetPackage = "private-package", roomId = "private-room" }
                    } }, latestSequence = 1, oldestSequence = 1, hasOlder = false
                }));
            }));
            var result = await reader.ExecuteAsync("test-bearer", JsonSerializer.SerializeToElement(new {
                schemaVersion = 1, operation = "chatRead", data = new { roomId = "one", after = 0, before = 0 }
            }), default);
            Check(historyReads == (member ? 1 : 0), "Membership is checked before accessing invitation history.");
            if (!member) { Check(result.Error == "notMember", "Former members cannot fetch private cards."); continue; }
            var attachment = result.Chat!.Messages.Single().Attachment;
            Check(attachment is { Kind: "fleet_invitation", FleetInviteCode: "ABCDEF12", Title: "组织邀请", Summary: "查看详情" } &&
                attachment.ExpiresAt == DateTimeOffset.Parse("2020-01-01T00:00:00Z"), "Existing WPF card and historical expiry survive projection.");
            Check(!BridgePayload.From(result).GetRawText().Contains("private-"), "Only normalized invitation fields leave Host.");
        }
    }
    private static HttpResponseMessage Ok(byte[] bytes) => new(HttpStatusCode.OK) { Content = new ByteArrayContent(bytes) };
    private static void Check(bool value, string reason) { if (!value) throw new Exception(reason); }
    private sealed class Handler(Func<HttpRequestMessage, HttpResponseMessage> send) : HttpMessageHandler {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => Task.FromResult(send(request));
    }
}
