using System.Net;
using System.Reflection;
using System.Text.Json;
using StarBridge.HostRuntime.Friends;
using StarBridge.HostRuntime.Realtime;

internal static class DirectMessageRealtimeHintTests
{
    internal static async Task Verify()
    {
        using var reader = new FriendsReader(new Uri("https://relay.invalid/"), new LocalHandler(), realtime: true);
        var client = reader.RealtimeClient!;
        var rows = (ConversationsView)await reader.ReadChatAsync("fixture", JsonSerializer.SerializeToElement(new { schemaVersion = 1 }), default, "scope");
        Set(client, "_state", RelayRealtimeClient.State.Connected);
        Set(client, "_bearer", "fixture");
        Check(!client.DirectMessagesPushHealthy, "connection alone does not prove DM support");
        var initial = await Wait(reader);
        var instance = initial.GetProperty("instance").GetString()!;
        var version = initial.GetProperty("version").GetInt64();
        Apply(client, 1, "peer", "a", 7);
        var hints = await Wait(reader, instance, version);
        Check(hints.GetProperty("directMessagesPushHealthy").GetBoolean(), "known peer proves DM support");
        Check(hints.GetProperty("directMessagesOnly").GetBoolean(), "DM invalidation stays directed");
        var targets = hints.GetProperty("directMessageTargets").EnumerateArray().Select(v => v.GetString()).ToArray();
        Check(targets.SequenceEqual(new[] { rows.Conversations[0].TargetRef }), "only matching issued conversation wakes");
        Check(!targets.Contains(rows.Conversations[1].TargetRef), "another conversation does not wake");
        Check(!hints.ToString().Contains("peer") && !hints.ToString().Contains("message"), "bridge contains no peer identity or content");
        var current = Cursor(client);
        Apply(client, 1, "peer", "a", 7);
        Apply(client, 2, "peer", "a", 7);
        Apply(client, 3, "peer", "b", 6);
        Apply(client, 4, "peer", "a", 8);
        Check(Cursor(client) == current, "duplicate and out-of-order hints are coalesced");
        Apply(client, 5, "unknown", "x", 1);
        Apply(client, 6, "unknown", "y", 2);
        Apply(client, 7, "another-unknown", "z", 3);
        var unknown = await Wait(reader, instance, current);
        Check(Cursor(client) == current + 1 && unknown.GetProperty("directMessageTargets").GetArrayLength() == 0,
            "unknown conversations cause one directory check per connection and no history wake");
        client.Stop();
        Set(client, "_state", RelayRealtimeClient.State.Connected);
        Set(client, "_bearer", "other-fixture");
        var other = await Wait(reader, bearer: "other-fixture");
        Apply(client, 1, "peer", "late-other-owner", 99);
        var foreign = await Wait(reader, other.GetProperty("instance").GetString()!, 0, "other-fixture");
        Check(foreign.GetProperty("directMessageTargets").GetArrayLength() == 0 && !client.DirectMessagesPushHealthy,
            "another account's retained capabilities cannot wake or prove health");
        client.Stop();
        Set(client, "_bearer", "fixture");
        Set(client, "_state", RelayRealtimeClient.State.Connected);
        client.Apply(JsonSerializer.SerializeToElement(new object[] {
            new { seq = 1, type = "dm.message.created", data = new { } },
            new { seq = 2, type = "dm.message.created", data = new { conversation = "peer", message = new { id = "a", sequence = 0 } } },
            new { type = "dm.message.created" }, new { seq = "invalid", type = "dm.message.created" }
        }));
        Check(!client.DirectMessagesPushHealthy, "malformed/legacy shapes keep fallback");
        client.Stop();
        await client.TryWaitAsync("old-fixture", false, "", -1, TimeSpan.Zero, default);
        var old = ((CancellationTokenSource)Field("_loop").GetValue(client)!).Token;
        await client.TryWaitAsync("new-fixture", false, "", -1, TimeSpan.Zero, default);
        var before = Cursor(client);
        try { client.Apply(Events(20, "peer", "late", 100), old); throw new Exception("old stream accepted"); }
        catch (OperationCanceledException) { }
        Check(old.IsCancellationRequested && Cursor(client) == before && !client.DirectMessagesPushHealthy,
            "late old-connection event after switching account cannot change new account");
        client.Stop();
        await DirectMessageGatewayRecoveryTests.Verify();
        Console.WriteLine("PASS DM hints: matching conversation/account, one unknown recheck, dedup, legacy shapes and late old stream");
    }

    internal static async Task<JsonElement> Wait(FriendsReader reader, string instance = "", long version = -1, string bearer = "fixture") =>
        JsonSerializer.SerializeToElement(await reader.WaitActivityAsync(bearer,
            JsonSerializer.SerializeToElement(new { schemaVersion = 1, instance, version }), default));
    private static void Apply(RelayRealtimeClient client, long seq, string peer, string id, long sequence) => client.Apply(Events(seq, peer, id, sequence));
    private static JsonElement Events(long seq, string peer, string id, long sequence) => JsonSerializer.SerializeToElement(new[] {
        new { seq, type = "dm.message.created", data = new { conversation = peer, message = new { id, sequence } } } });
    private static FieldInfo Field(string name) => typeof(RelayRealtimeClient).GetField(name, BindingFlags.Instance | BindingFlags.NonPublic)!;
    private static void Set(RelayRealtimeClient client, string name, object value) => Field(name).SetValue(client, value);
    private static long Cursor(RelayRealtimeClient client) => (long)Field("_socialVersion").GetValue(client)!;
    private static void Check(bool value, string reason) { if (!value) throw new Exception(reason); }
    private sealed class LocalHandler : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            if (request.RequestUri!.AbsolutePath.EndsWith("ticket")) return Task.FromResult(new HttpResponseMessage(HttpStatusCode.NotFound));
            var body = request.RequestUri.AbsolutePath.EndsWith("conversations")
                ? JsonSerializer.Serialize(new { conversations = new[] { "peer", "different-peer" }.Select(id => new {
                    user = new { accountId = id, callsign = "Fixture", gameId = "" }, lastMessagePreview = "",
                    lastMessageAt = DateTimeOffset.UtcNow, unreadCount = 0, conversationState = "friend" }), totalUnread = 0, serverTime = DateTimeOffset.UtcNow })
                : "{\"instanceId\":\"00000000000000000000000000000001\",\"version\":0}";
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(body) });
        }
    }
}
