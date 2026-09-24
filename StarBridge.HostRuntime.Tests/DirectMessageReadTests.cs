using System.Net;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Friends;

internal static class DirectMessageReadTests
{
    private static readonly DateTimeOffset Now = DateTimeOffset.Parse("2026-09-06T12:00:00Z");
    private static JsonElement Payload(object value) => JsonSerializer.SerializeToElement(value);
    private static object Directory() => new { conversations = new[] { new { user = new { accountId = "target-private", callsign = "示例", gameId = "Example", avatarImageData = (string?)null },
        lastMessagePreview = "历史\n预览", lastMessageAt = Now, unreadCount = 2, conversationState = "request_incoming" } }, totalUnread = 2, serverTime = Now };
    private static object History(int first, int last, long latest = 60, string target = "target-private", bool duplicate = false) => new {
        targetAccountId = target, messages = Enumerable.Range(first, last - first + 1).Select(n => new {
            sequence = n, messageId = duplicate ? "duplicate" : $"message-{n}", senderAccountId = n % 2 == 0 ? "viewer-private" : target,
            recipientAccountId = n % 2 == 0 ? target : "viewer-private", text = "消息\n内容", createdAt = Now,
            attachment = n == first ? new { kind = "overlay_preset", overlayPresetPackage = "private-package" } : null }),
        latestSequence = latest, oldestSequence = first, hasOlder = first > 1, canSend = false, conversationState = "request_incoming"
    };
    private sealed class Handler(Func<HttpRequestMessage, HttpResponseMessage> send) : HttpMessageHandler
    { protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => Task.FromResult(send(request)); }
    private static HttpResponseMessage Ok(object body) => new(HttpStatusCode.OK) { Content = new StringContent(JsonSerializer.Serialize(body)) };
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
    internal static async Task Paging()
    {
        await NotificationMetadata();
        await Receipts();
        await OpenFriend();
        await InvitationCards();
        var paths = new List<string>();
        using var reader = new FriendsReader(new Uri("https://relay.example.test"), new Handler(request => {
            Check(request.Method == HttpMethod.Get && request.Headers.Authorization?.Parameter == "token", "Only scoped reads");
            var path = request.RequestUri!.PathAndQuery; paths.Add(path);
            if (path.Contains("conversations")) { Check(path.EndsWith("includePresence=false"), "No presence"); return Ok(Directory()); }
            Check(path.Contains("targetAccountId=target-private") && path.EndsWith("limit=50"), "Resolved target, bounded page");
            return Ok(path.Contains("before=11") ? History(1, 10) : path.Contains("after=60") ? History(61, 62, 62) : History(11, 60));
        }));
        var directory = (ConversationsView)await reader.ReadChatAsync("token", Payload(new { schemaVersion = 1 }), default, "a:1");
        var reference = directory.Conversations.Single().TargetRef;
        Check(!JsonSerializer.Serialize(directory).Contains("target-private") && directory.TotalUnread == 2, "Opaque directory and unread preserved");
        Check(directory.Conversations[0].LatestSequence == null && directory.Conversations[0].LastMessageIncoming == null,
            "Old contracts remain readable without guessing notification metadata.");
        var page = (DirectHistoryView)await reader.ReadChatAsync("token", Payload(new { schemaVersion = 1, targetRef = reference }), default, "a:1");
        Check(page.Messages.Length == 50 && page.HasOlder && page.OldestSequence == 11 && !page.CanSend, "Initial page/request state");
        var serialized = JsonSerializer.Serialize(page);
        Check(!serialized.Contains("viewer-private") && !serialized.Contains("private-package") && !serialized.Contains("target-private"), "No account IDs or executable attachment");
        Check(page.Messages[0].Incoming && !page.Messages[1].Incoming, "Sender direction preserved");
        var refreshed = (ConversationsView)await reader.ReadChatAsync("token", Payload(new { schemaVersion = 1 }), default, "a:1");
        Check(refreshed.Conversations.Single().TargetRef == reference,
            "Background directory refresh preserves an open conversation reference and its paging cursors.");
        var older = (DirectHistoryView)await reader.ReadChatAsync("token", Payload(new { schemaVersion = 1, targetRef = reference, before = 11 }), default, "a:1");
        Check(older.Messages.Length == 10 && !older.HasOlder, "Before paging");
        var newer = (DirectHistoryView)await reader.ReadChatAsync("token", Payload(new { schemaVersion = 1, targetRef = reference, after = 60 }), default, "a:1");
        Check(newer.Messages.Length == 2 && paths.Count == 5, "After paging without read receipts");
    }
    internal static async Task NotificationMetadata()
    {
        foreach (var sender in new[] { "target-private", "viewer-private" }) {
            using var reader = new FriendsReader(new Uri("https://relay.example.test"), new Handler(_ => Ok(new {
                conversations = new[] { new { user = new { accountId = "target-private", callsign = "Fixture", gameId = "Fixture" },
                    lastMessagePreview = "fixture", lastMessageAt = Now, unreadCount = 1, conversationState = "friend",
                    latestSequence = 42L, lastSenderAccountId = sender } }, totalUnread = 1, serverTime = Now,
            })));
            var directory = (ConversationsView)await reader.ReadChatAsync("token", Payload(new { schemaVersion = 1 }), default, "fixture:1");
            var row = directory.Conversations.Single();
            Check(row.LatestSequence == 42 && row.LastMessageIncoming == (sender == "target-private"), "Preserve validated sequence and incoming direction.");
            var wire = JsonSerializer.Serialize(directory);
            Check(!wire.Contains("target-private") && !wire.Contains("viewer-private"), "Notification metadata never exposes raw account IDs.");
        }
    }

    private static async Task InvitationCards()
    {
        foreach (var fault in new[] { "none", "short", "long", "control", "empty", "expiry", "scope" })
        {
            var reads = 0;
            using var reader = new FriendsReader(new Uri("https://relay.example.test"), new Handler(request => {
                Check(request.Method == HttpMethod.Get, "Reading an invitation never creates or accepts one.");
                if (request.RequestUri!.AbsolutePath.EndsWith("conversations")) return Ok(Directory());
                reads++;
                return Ok(new {
                    targetAccountId = "target-private", messages = new[] { new {
                        sequence = 1, messageId = "card", senderAccountId = "target-private", recipientAccountId = "viewer-private",
                        text = "", createdAt = Now,
                        attachment = new { kind = "fleet_invitation", title = fault == "empty" ? "" : "组织邀请 · Alpha",
                            summary = "查看组织详情", fleetInviteCode = fault switch { "short" => "abc", "long" => new string('a', 41), "control" => "ABCD\nEF", _ => "ABCDEF12" },
                            expiresAt = fault == "expiry" ? "bad-time" : Now.ToString("O"),
                            ownerAccountId = "private-owner", overlayPresetPackage = "private-package" }
                    } }, latestSequence = 1, oldestSequence = 1, hasOlder = false, canSend = false, conversationState = "friend"
                });
            }));
            var directory = (ConversationsView)await reader.ReadChatAsync("token", Payload(new { schemaVersion = 1 }), default, "a:1");
            try {
                var page = (DirectHistoryView)await reader.ReadChatAsync("token", Payload(new { schemaVersion = 1, targetRef = directory.Conversations[0].TargetRef }), default, fault == "scope" ? "b:1" : "a:1");
                Check(fault == "none", "Malformed/cross-account card accepted: " + fault);
                var card = page.Messages.Single().CommunityInvitation;
                Check(card is { InviteCode: "ABCDEF12", Title: "组织邀请 · Alpha", Summary: "查看组织详情" } && card.ExpiresAt == Now,
                    "Exact bounded historical invitation metadata preserved, including expired cards.");
                var json = JsonSerializer.Serialize(page);
                Check(!json.Contains("private-owner") && !json.Contains("private-package") && !json.Contains("target-private"), "Unrelated attachment fields and account IDs never escape.");
            } catch (AccountBridgeHostException e) {
                Check(fault != "none" && e.Code == (fault == "scope" ? "directMessages.target_changed" : "directMessages.data_invalid"), "Strict card projection errors.");
            }
            Check(reads == (fault == "scope" ? 0 : 1), "Invalid account scope is rejected before card fetch.");
        }
    }
    private static async Task Receipts()
    {
        foreach (var fault in new[] { "none", "newMessage", "noHistory", "scope", "future", "ackTarget", "ackCursor", "403" }) {
            var posts = 0;
            using var reader = new FriendsReader(new Uri("https://relay.example.test"), new Handler(request => {
                if (request.Method == HttpMethod.Post) {
                    posts++;
                    Check(request.RequestUri!.AbsolutePath == "/api/friends/chat/read", "Existing receipt endpoint only");
                    using var body = JsonDocument.Parse(request.Content!.ReadAsStringAsync().GetAwaiter().GetResult());
                    Check(body.RootElement.GetProperty("targetAccountId").GetString() == "target-private" &&
                        body.RootElement.GetProperty("throughSequence").GetInt64() == 59, "Exact target and viewed cursor");
                    if (fault == "403") return new(HttpStatusCode.Forbidden);
                    return Ok(new { targetAccountId = fault == "ackTarget" ? "other" : "target-private",
                        readThroughSequence = fault == "ackCursor" ? 57 : 59 });
                }
                if (request.RequestUri!.AbsolutePath.EndsWith("conversations")) {
                    if (posts == 0) return Ok(Directory());
                    return Ok(new { conversations = new[] { new { user = new { accountId = "target-private" },
                        unreadCount = fault == "newMessage" ? 1 : 0 } } });
                }
                return Ok(History(11, 60, latest: 100));
            }));
            var directory = (ConversationsView)await reader.ReadChatAsync("token", Payload(new { schemaVersion = 1 }), default, "a:1");
            var reference = directory.Conversations[0].TargetRef;
            if (fault != "noHistory") await reader.ReadChatAsync("token", Payload(new { schemaVersion = 1, targetRef = reference }), default, "a:1");
            try {
                var receipt = await reader.MarkChatReadAsync("token", Payload(new { schemaVersion = 1, targetRef = reference,
                    throughSequence = fault == "future" ? 99 : 59 }), default, fault == "scope" ? "b:1" : "a:1");
                Check(fault is "none" or "newMessage", "Invalid receipt accepted: " + fault);
                Check(receipt.ReadThroughSequence == 59 && receipt.UnreadCount == (fault == "newMessage" ? 1 : 0), "Authoritative count preserves concurrent unread");
                Check(!JsonSerializer.Serialize(receipt).Contains("target-private"), "Receipt has no account identifier");
            } catch (AccountBridgeHostException e) {
                Check(fault is not ("none" or "newMessage") && e.Code.StartsWith("directMessages."), "Unexpected receipt failure");
            }
            Check(posts == (fault is "noHistory" or "scope" or "future" ? 0 : 1), "Invalid cursor/scope never posts");
        }
        foreach (var json in new[] { "{}", "{\"schemaVersion\":1,\"targetAccountId\":\"raw\",\"throughSequence\":1}",
            "{\"schemaVersion\":1,\"targetRef\":\"00000000000000000000000000000001\",\"throughSequence\":0}" }) {
            using var body = JsonDocument.Parse(json);
            try { FriendsReader.ParseChatMarkRead(body.RootElement); throw new Exception("Invalid receipt payload accepted"); }
            catch (AccountBridgeHostException e) { Check(e.Code == "directMessages.invalid_request", "Strict receipt payload"); }
        }
    }
    private static async Task OpenFriend()
    {
        var paths = new List<string>();
        using var reader = new FriendsReader(new Uri("https://relay.example.test"), new Handler(request => {
            paths.Add(request.RequestUri!.AbsolutePath);
            Check(request.Method == HttpMethod.Get, "Opening a friend never sends a message.");
            if (request.RequestUri.AbsolutePath == "/api/friends")
                return new(HttpStatusCode.OK) { Content = new ByteArrayContent(FriendsReaderTests.Directory(FriendsReaderTests.User("target-private"))) };
            if (request.RequestUri.AbsolutePath.EndsWith("conversations")) return Ok(Directory());
            Check(request.RequestUri.Query.Contains("targetAccountId=target-private"), "Exact Host-issued target, not display-name matching.");
            return Ok(History(1, 2));
        }));
        var friend = (await reader.ReadAsync("token", null, default, "scope:1")).Friends.Single();
        Check(friend.ChatTargetRef is not null && friend.ChatTargetRef != friend.TargetRef, "Independent opaque chat reference.");
        foreach (var scope in new[] { "scope:2", "other-account" }) {
            try { await reader.ReadChatAsync("token", Payload(new { schemaVersion = 1, targetRef = friend.ChatTargetRef }), default, scope); throw new Exception("Cross-account friend opened."); }
            catch (AccountBridgeHostException e) { Check(e.Code == "directMessages.target_changed", "Scope guard before network."); }
        }
        var page = (DirectHistoryView)await reader.ReadChatAsync("token", Payload(new { schemaVersion = 1, targetRef = friend.ChatTargetRef }), default, "scope:1");
        Check(page.Messages.Length == 2 && paths.SequenceEqual(new[] { "/api/friends", "/api/friends/chat/messages" }), "Friend opens directly without a prior conversation.");
        var conversations = (ConversationsView)await reader.ReadChatAsync("token", Payload(new { schemaVersion = 1 }), default, "scope:1");
        Check(friend.ConversationKey?.Length == 64 && friend.ConversationKey == conversations.Conversations[0].ConversationKey,
            "Friend and conversation share a non-command correlation key.");
        var otherScope = (ConversationsView)await reader.ReadChatAsync("token", Payload(new { schemaVersion = 1 }), default, "scope:2");
        Check(friend.ConversationKey != otherScope.Conversations[0].ConversationKey, "Unread keys cannot correlate across account generations.");
        var again = (ConversationsView)await reader.ReadChatAsync("token", Payload(new { schemaVersion = 1 }), default, "scope:1");
        Check(friend.ConversationKey == again.Conversations[0].ConversationKey, "Unread keys remain stable on refresh.");
        var tokenRefresh = (ConversationsView)await reader.ReadChatAsync("new-access-token", Payload(new { schemaVersion = 1 }), default, "scope:1");
        Check(friend.ConversationKey == tokenRefresh.Conversations[0].ConversationKey, "Token rotation within the same account generation preserves unread correlation.");
        try { await reader.ReadChatAsync("token", Payload(new { schemaVersion = 1, targetRef = friend.ConversationKey }), default, "scope:1"); throw new Exception("Correlation key accepted as command reference."); }
        catch (AccountBridgeHostException) { }
        await reader.ReadChatAsync("token", Payload(new { schemaVersion = 1, targetRef = friend.ChatTargetRef }), default, "scope:1");
        await reader.ReadAsync("token", null, default, "scope:1");
        try { await reader.ReadChatAsync("token", Payload(new { schemaVersion = 1, targetRef = friend.ChatTargetRef }), default, "scope:1"); throw new Exception("Stale friend ref opened."); }
        catch (AccountBridgeHostException e) { Check(e.Code == "directMessages.target_changed", "Refresh retires old friend references."); }
    }
    internal static async Task Guards()
    {
        foreach (var fault in new[] { "scope", "token", "cursor", "target", "duplicate", "401", "403", "302", "oversize", "removed" }) {
            var calls = 0;
            using var reader = new FriendsReader(new Uri("https://relay.example.test"), new Handler(request => {
                calls++;
                if (request.RequestUri!.AbsolutePath.EndsWith("conversations"))
                    return fault == "removed" && calls > 1
                        ? Ok(new { conversations = Array.Empty<object>(), totalUnread = 0, serverTime = Now })
                        : Ok(Directory());
                if (int.TryParse(fault, out var code)) return new((HttpStatusCode)code) { Content = new StringContent("sensitive server error") };
                if (fault == "oversize") return new(HttpStatusCode.OK) { Content = new StringContent(new string('x', FriendsReader.MaxBytes + 1)) };
                return Ok(History(11, 12, target: fault == "target" ? "other" : "target-private", duplicate: fault == "duplicate"));
            }));
            var directory = (ConversationsView)await reader.ReadChatAsync("token", Payload(new { schemaVersion = 1 }), default, "a:1");
            if (fault == "removed") await reader.ReadChatAsync("token", Payload(new { schemaVersion = 1 }), default, "a:1");
            try {
                await reader.ReadChatAsync(fault == "token" ? "other" : "token", Payload(new { schemaVersion = 1,
                    targetRef = directory.Conversations[0].TargetRef, before = fault == "cursor" ? 999 : 0 }), default, fault == "scope" ? "b:1" : "a:1");
                throw new Exception("Fault accepted: " + fault);
            } catch (AccountBridgeHostException e) { Check(e.Code.StartsWith("directMessages.") && !e.Message.Contains("sensitive"), "Bounded errors"); }
            Check(calls == (fault is "scope" or "token" or "cursor" ? 1 : 2), "Bad reference has no network access");
        }
        foreach (var json in new[] { "{}", "{\"schemaVersion\":1,\"targetAccountId\":\"injected\"}", "{\"schemaVersion\":1,\"before\":2}",
            "{\"schemaVersion\":1,\"schemaVersion\":1}", "{\"schemaVersion\":1,\"targetRef\":\"00000000000000000000000000000001\",\"before\":1,\"after\":2}" }) {
            using var doc = JsonDocument.Parse(json);
            try { FriendsReader.ParseChatRead(doc.RootElement); throw new Exception("Invalid payload accepted"); }
            catch (AccountBridgeHostException e) { Check(e.Code == "directMessages.invalid_request", "Strict read payload"); }
        }
    }
}
