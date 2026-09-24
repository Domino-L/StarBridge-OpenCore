using System.Net;
using System.Net.Http.Json;
using StarBridge.HostRuntime.Communities;
using StarBridge.HostRuntime.Notifications;

internal static class CommunityNotificationTests
{
    internal static async Task Run()
    {
        foreach (var kind in Enum.GetValues<NotificationEventKind>()) {
            Check(NotificationSourcePolicy.Allows(NotificationSourceMode.Normal, kind), "Normal includes every known event.");
            Check(!NotificationSourcePolicy.Allows(NotificationSourceMode.DoNotDisturb, kind), "DND blocks every event.");
            Check(NotificationSourcePolicy.Allows(NotificationSourceMode.ImportantOnly, kind) ==
                (kind is NotificationEventKind.DirectMessage or NotificationEventKind.RoomInvitation or NotificationEventKind.JoinRequest or NotificationEventKind.OrganizationManagement),
                "Important includes all private messages but no group chat or presence.");
        }
        Check(!NotificationSourcePolicy.Allows((NotificationSourceMode)99, NotificationEventKind.DirectMessage), "Unknown policy fails closed.");
        var origin = DateTimeOffset.UtcNow;
        var observer = new CommunityNotificationObserver();
        CommunityNotificationFeed Feed(int tick, string key = "source", long sequence = 1, bool manage = true,
            bool chat = true, bool incoming = true, string task = "first") => new(origin.AddSeconds(tick), [
                new(key, "Fixture", origin.AddDays(-1), chat,
                    new(sequence, 1, incoming, origin.AddSeconds(tick), origin.AddSeconds(tick), "Fixture", "Not retained"),
                    manage, [new(task, origin.AddSeconds(tick))])]);
        Check(observer.Observe("owner", 1, Feed(0)).Count == 0, "First snapshot quiet.");
        Check(observer.Observe("owner", 1, Feed(1, sequence: 2, task: "second")).Count == 2, "Fresh chat and management are distinct candidates.");
        Check(observer.Observe("owner", 1, Feed(2, sequence: 2, task: "second")).Count == 0, "No duplicate replay.");
        Check(observer.Observe("owner", 1, Feed(3, sequence: 3, incoming: false, manage: false)).Count == 0, "Own messages and revoked management suppressed.");
        Check(observer.Observe("owner", 1, Feed(4, sequence: 3, task: "third")).Count == 0, "Permission regrant establishes quiet baseline.");
        Check(observer.Observe("owner", 1, Feed(5, key: "rejoined", sequence: 99, task: "new")).Count == 0, "Membership incarnation change is quiet.");
        Check(observer.Observe("other", 2, Feed(6, sequence: 100)).Count == 0, "Account boundary is quiet.");
        Check(observer.Observe("other", 2, Feed(50, sequence: 101)).Count == 0, "Reconnect gap is quiet.");
        Check(observer.Observe("other", 2, Feed(51, sequence: 102, chat: false)).Count == 0, "Failed source quiet.");
        Check(observer.Observe("other", 2, Feed(52, sequence: 103)).Count == 0, "Source recovery quiet.");
        Check(observer.Observe("other", 2, new(origin.AddSeconds(53), [])).Count == 0, "Departure clears the source baseline.");
        Check(observer.Observe("other", 2, Feed(54, sequence: 104)).Count == 0, "A removed source cannot resurrect its old baseline.");
        observer.Reset();
        CommunityNotificationFeed Pair(int tick, bool firstChat, long sequence) => new(origin.AddSeconds(tick), [
            Feed(tick, key: "one", sequence: sequence, chat: firstChat).Sources[0],
            Feed(tick, key: "two", sequence: sequence).Sources[0]
        ]);
        observer.Observe("owner", 3, Pair(0, true, 1));
        var independent = observer.Observe("owner", 3, Pair(1, false, 2));
        Check(independent.Count == 1 && independent[0].SourceKey == "two", "One failed organization does not mute another source.");
        await Reader(origin);
    }

    private static async Task Reader(DateTimeOffset now)
    {
        bool member = true, owner = true, brokenChat = false;
        int histories = 0, requests = 0;
        using var handler = new Handler(request => {
            requests++;
            Check(request.Method == HttpMethod.Get, "Notification feed performs no writes or receipts.");
            Check(request.Headers.Authorization?.Parameter == "fixture", "Authenticated source only.");
            var path = request.RequestUri!.AbsolutePath;
            if (path == "/api/fleets/membership") return Json(new { fleetCode = member ? "A" : null, fleetCodes = member ? new[] { "A" } : [] });
            if (path == "/api/fleets") return Json(new[] { new {
                code = "A", name = "Fixture", ownerAccount = owner ? "viewer" : "other",
                members = new[] { new { accountId = "viewer", joinedAt = now.AddDays(-1) } },
                applications = new[] { new { id = "private-application", status = "Pending", createdAt = now, message = "Never projected" } }
            } });
            if (path == "/api/auth/session") return Json(new { accountId = "viewer", userName = "viewer" });
            if (path == "/api/fleets/chat/channels") return brokenChat ? new(HttpStatusCode.ServiceUnavailable) : Json(new {
                totalUnread = 1, channels = new[] { new { channelId = "fleet:A", type = "fleet", unreadCount = 1, canSend = true } }
            });
            if (path == "/api/fleets/chat/messages") {
                histories++;
                Check(request.RequestUri.Query.Contains("limit=1"), "Only newest message, no history sweep.");
                return Json(new { channelId = "fleet:A", latestSequence = 3, oldestSequence = 3, hasOlder = true, canSend = true, serverTime = now,
                    messages = new[] { new { channelId = "fleet:A", sequence = 3, messageId = "private-message", senderAccountId = "other",
                        senderCallsign = "Visible", senderGameId = "Visible", senderRoleTitle = "Member", senderRoleColor = "#47AAEE",
                        text = "Visible message", createdAt = now } } });
            }
            throw new Exception("Unexpected route " + path);
        });
        using var client = new CommunityClient(new Uri("https://relay.invalid"), handler);
        async Task<CommunityNotificationFeed> Read(string scope = "owner-scope") =>
            await client.ReadWpfS2NotificationsAsync("fixture", scope, "viewer", () => { }, default);
        var first = (await Read()).Sources.Single();
        Check(first.Chat is { Sequence: 3, Incoming: true } && first.ManagementAvailable && first.Tasks.Length == 1, "Chat and authorized pending management read.");
        Check(!first.Tasks[0].Key.Contains("private-application") && first.SourceKey.Length == 64, "No raw identifiers in notification projection.");
        Check((await Read()).Sources.Single().SourceKey == first.SourceKey, "Stable within same owner and membership.");
        Check((await Read("other-scope")).Sources.Single().SourceKey != first.SourceKey, "Different owner cannot correlate sources.");
        owner = false; brokenChat = true;
        var revoked = (await Read()).Sources.Single();
        Check(!revoked.ManagementAvailable && revoked.Tasks.Length == 0 && !revoked.ChatAvailable, "Revocation and failed channel do not use stale content.");
        member = false; var before = requests;
        Check((await Read()).Sources.Length == 0 && requests == before + 1, "Departure removes source without fetching chat.");
        var captured = requests;
        try { await client.ReadWpfS2NotificationsAsync("fixture", "scope", "viewer", () => throw new OperationCanceledException(), default); throw new Exception("Expected cancellation"); }
        catch (OperationCanceledException) { }
        Check(requests == captured && histories == 3, "Invalidated reads stop before network.");
    }
    private sealed class Handler(Func<HttpRequestMessage, HttpResponseMessage> send) : HttpMessageHandler {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => Task.FromResult(send(request));
    }
    private static HttpResponseMessage Json(object value) => new(HttpStatusCode.OK) { Content = JsonContent.Create(value) };
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
}
