using StarBridge.HostRuntime.Chat;
using System.Text;
using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Friends;
using StarBridge.HostRuntime.Account;

internal static class LocalChatHistoryTests
{
    internal static async Task Verify()
    {
        var root = Path.GetFullPath(Path.Combine(Path.GetTempPath(), "StarBridge-chat-test-" + Guid.NewGuid().ToString("N")));
        var now = DateTimeOffset.UtcNow;
        var store = new LocalChatHistory(root, () => now);
        await store.Run("fixture-account", "private:fixture-peer", [
            new(1, "Fixture", "expired message", now.AddDays(-91), false, false),
            new(2, "Fixture", "synthetic private history", now.AddDays(-1), false, false)]);
        var reopened = new LocalChatHistory(root, () => now);
        var rows = await reopened.Run("fixture-account", "private:fixture-peer");
        Require(rows.Length == 1 && rows[0].Sequence == 2, "restart and ninety day retention");
        var file = Directory.GetFiles(root, "*.dat", SearchOption.AllDirectories).Single();
        Require(!Encoding.UTF8.GetString(await File.ReadAllBytesAsync(file)).Contains("synthetic private history"), "encrypted at rest");
        Require((await reopened.Run("other-account", "private:fixture-peer")).Length == 0, "account isolation");
        Require((await reopened.Run("fixture-account", "organization:fixture-peer")).Length == 0, "channel isolation");
        await reopened.Run("fixture-account", "private:fixture-peer", [new(2, "Fixture", "updated", now, false, false)]);
        Require((await reopened.Run("fixture-account", "private:fixture-peer")).Length == 1, "deduplicate sequence");
        now = now.AddDays(91);
        Require((await reopened.Run("fixture-account", "private:fixture-peer")).Length == 0, "expired content not served");
        await reopened.Run("fixture-account", "private:fixture-peer", [new(3, "Fixture", "clear me", now, false, false)]);
        await reopened.Run("fixture-account", "private:fixture-peer", clear: true);
        Require((await reopened.Run("fixture-account", "private:fixture-peer")).Length == 0, "explicit clear");
        var previousRoot = HostDataRoot.CurrentRoot;
        HostDataRoot.UsePreparedRoot(root);
        try { await BridgeRead(); }
        finally { HostDataRoot.UsePreparedRoot(previousRoot); }
        // Only the freshly-created synthetic test directory may be removed.
        if (root.StartsWith(Path.GetFullPath(Path.GetTempPath()), StringComparison.OrdinalIgnoreCase) &&
            Path.GetFileName(root).StartsWith("StarBridge-chat-test-", StringComparison.Ordinal)) Directory.Delete(root, true);
        Console.WriteLine("PASS encrypted local chat restart, account/channel isolation, 90-day expiry, deduplication and clear");
    }
    private static void Require(bool ok, string detail) { if (!ok) throw new Exception(detail); }
    private sealed class Handler : HttpMessageHandler
    {
        internal int Reads;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Reads++;
            object body = request.RequestUri!.AbsolutePath.EndsWith("conversations")
                ? new { conversations = new[] { new { user = new { accountId = "synthetic-peer", callsign = "Fixture", gameId = "Fixture" },
                    lastMessagePreview = "fixture", lastMessageAt = DateTimeOffset.UtcNow, unreadCount = 0, conversationState = "friend" } }, totalUnread = 0, serverTime = DateTimeOffset.UtcNow }
                : new { targetAccountId = "synthetic-peer", messages = new[] { new { sequence = 1, messageId = "fixture-message", senderAccountId = "synthetic-peer",
                    recipientAccountId = "synthetic-viewer", text = "persisted fixture", createdAt = DateTimeOffset.UtcNow } },
                    latestSequence = 1, oldestSequence = 1, hasOlder = false, canSend = true, conversationState = "friend" };
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(body) });
        }
    }
    private static async Task BridgeRead()
    {
        var handler = new Handler();
        using var reader = new FriendsReader(new Uri("https://fixture.invalid"), handler);
        var directory = (ConversationsView)await reader.ReadChatAsync("fixture-token", JsonSerializer.SerializeToElement(new { schemaVersion = 1 }), default, "scope");
        var reference = directory.Conversations.Single().TargetRef;
        await reader.ReadChatAsync("fixture-token", JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = reference }), default, "scope", "fixture-account");
        var count = handler.Reads;
        var payload = JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = reference, localHistory = "read" });
        var local = JsonSerializer.SerializeToElement(await reader.ReadChatAsync("fixture-token", payload, default, "scope", "fixture-account"), new JsonSerializerOptions(JsonSerializerDefaults.Web));
        Require(local.GetProperty("rows")[0].GetProperty("text").GetString() == "persisted fixture" && handler.Reads == count, "local read uses no network");
        Require(!local.TryGetProperty("canSend", out _) && !local.GetRawText().Contains("fixture-message"), "archive has no command authority");
        try { await reader.ReadChatAsync("fixture-token", payload, default, "other-scope", "fixture-account"); throw new Exception("scope escaped"); }
        catch (AccountBridgeHostException) { }
        await reader.ReadChatAsync("fixture-token", JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = reference, localHistory = "clear" }), default, "scope", "fixture-account");
        Require(handler.Reads == count, "clear never deletes remote messages");
    }
}
