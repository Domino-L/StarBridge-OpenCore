using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Chat;

internal static partial class OfficialFleetPreviewAuthorTests
{
    private static JsonObject ChatRenewal(Fixture fixture, long after = 0, string[]? observed = null, int limit = 50)
    {
        var body = JsonSerializer.SerializeToNode(fixture.Renewal(after, observed))!.AsObject();
        body["surface"] = "chat"; body["limit"] = limit; return body;
    }

    internal static async Task ChatRenewalContract()
    {
        Check(AccountBridgeRuntime.AdvertisedCapabilities.Contains("officialFleet.communication.chatAuthorRenewal"), "chat renewal capability");
        using var fixture = new Fixture(); await fixture.Open();
        foreach (var surface in new[] { "missing", "preview", "chat" })
        {
            var query = JsonSerializer.SerializeToNode(fixture.Renewal())!.AsObject();
            if (surface != "missing") query["surface"] = surface;
            var calls = fixture.Handler.Requests.Count;
            var result = await fixture.Success(query);
            Check(fixture.Handler.Requests.Count == calls + 1 && fixture.Handler.Requests.Last().Path ==
                "/api/official-fleets/chat/messages/" + (surface == "chat" ? "read" : "read-preview"), "surface routes single read: " + surface);
            Check(result.GetProperty("unreadCount").GetInt32() == 0 && !result.GetProperty("canSend").GetBoolean(), "renewal leaves channel state unobserved");
        }
        var first = await fixture.Success(ChatRenewal(fixture));
        var message = first.GetProperty("messages")[0]; var reference = message.GetProperty("messageRef").GetString()!;
        Check(first.GetProperty("authorIdentitySchemaVersion").GetInt32() == 1 && message.GetProperty("senderCallsign").GetString() == "Preview fixture", "chat current author proof");
        // Renew addresses beyond their original five-minute detail lease, through the same validator.
        fixture.Handler.Clock.Now += TimeSpan.FromMinutes(6);
        var renewed = await fixture.Success(ChatRenewal(fixture, 1, [reference]));
        var update = renewed.GetProperty("authorUpdates")[0];
        Check(renewed.GetProperty("messages").GetArrayLength() == 0 && update.GetProperty("messageRef").GetString() == reference &&
            update.GetProperty("senderRef").GetString() == message.GetProperty("senderRef").GetString() && update.GetProperty("recordState").GetString() == "found",
            "chat renews retained message and sender references");
        fixture.Handler.Clock.Now = DateTimeOffset.UtcNow;
        foreach (var limit in new[] { 1, 50 }) await fixture.Success(ChatRenewal(fixture, limit: limit));
        var fifty = Enumerable.Range(0, 50).Select(i => i.ToString("x32")).ToArray();
        await fixture.Success(ChatRenewal(fixture, observed: fifty));
        foreach (var mutation in new (string Key, object? Value)[] {
            ("surface", null), ("surface", "CHAT"), ("surface", " chat"), ("surface", "other"), ("surface", 1), ("surface", true), ("surface", new object()),
            ("limit", 0), ("limit", 51), ("limit", 1.5), ("after", -1), ("after", long.MaxValue),
            ("observeMessageRefs", new[] { reference, reference }), ("observeMessageRefs", new[] { "bad" }),
            ("observeMessageRefs", new object[] { 1 }), ("observeMessageRefs", Enumerable.Range(0, 51).Select(i => i.ToString("x32")).ToArray()),
            ("before", 0), ("localHistory", "clear"), ("authorIdentitySchemaVersion", 1), ("sourceRef", "officialFleet:8") })
        {
            var query = ChatRenewal(fixture); query[mutation.Key] = JsonSerializer.SerializeToNode(mutation.Value);
            var calls = fixture.Handler.Requests.Count; var failure = await fixture.Dispatch(query);
            Check(failure.Error?.Code == (mutation.Key == "sourceRef" ? "communities.refreshRequired" : "communities.dataInvalid") &&
                fixture.Handler.Requests.Count == calls, "chat input rejected before IO: " + mutation.Key + "/" + failure.Error?.Code);
        }
        fixture.Handler.BadProof = true;
        var neutral = await fixture.Success(ChatRenewal(fixture));
        Check(neutral.GetProperty("messages")[0].GetProperty("authorIdentityState").GetString() == "unavailable", "chat proof validation stays fail closed");
        fixture.Handler.BadProof = false;
        var pending = await fixture.Host.OfficialFleetCommunicationAsync(fixture.Owner, JsonSerializer.SerializeToElement(ChatRenewal(fixture)), default);
        fixture.Handler.Clock.Now += TimeSpan.FromSeconds(6);
        Check(JsonSerializer.SerializeToElement(pending).GetProperty("messages")[0].GetProperty("senderCallsign").GetString() == "Preview fixture", "chat publication carries lapsed display observation to Flutter");

        using var old = new Fixture(); old.Handler.Preview = null; await old.Open();
        var compatible = await old.Success(ChatRenewal(old));
        Check(compatible.GetProperty("messages").GetArrayLength() == 1 && old.Handler.Requests.Last().Path.EndsWith("/read"),
            "new client plus old author-capable relay needs no new relay route or preview field");
        using var legacy = new Fixture(); legacy.Handler.OldRelay = true; await legacy.Open();
        var ordinary = await legacy.Success(new { schemaVersion = 1, sourceRef = Source, action = "chat", targetRef = legacy.Target, after = 0, before = 0 });
        Check(!ordinary.TryGetProperty("authorIdentitySchemaVersion", out _) && ordinary.GetProperty("messages").GetArrayLength() == 1,
            "new client plus pre-author relay retains ordinary content");
        using var independent = new Fixture(); independent.Handler.HideChatAuthors = true;
        var opened = await independent.Open();
        Check(opened.GetProperty("authorIdentitySchemaVersion").GetInt32() == 0 && opened.GetProperty("previewAuthorsAvailable").GetBoolean(),
            "chat schema downgrade preserves independent preview advertisement");
        var previewRead = await independent.Success(independent.Renewal());
        Check(previewRead.GetProperty("authorIdentitySchemaVersion").GetInt32() == 1 &&
            previewRead.GetProperty("messages")[0].GetProperty("senderCallsign").GetString() == "Preview fixture" &&
            independent.Handler.Requests.Last().Path.EndsWith("/read-preview"), "preview still renews after opening with chat brake active");
        var previousCalls = independent.Handler.Requests.Count;
        Check((await independent.Dispatch(ChatRenewal(independent))).Error?.Code == "communities.dataInvalid" &&
            independent.Handler.Requests.Count == previousCalls, "preview support does not grant chat author capability");
        Check((await independent.Dispatch(OrdinaryChat(independent))).Error?.Code == "communities.dataInvalid" &&
            independent.Handler.Requests.Count == previousCalls, "preview support does not grant ordinary chat author opt-in");
    }

    internal static async Task ChatRenewalArchiveAndConfirmation()
    {
        using var fixture = new Fixture(); await fixture.Open();
        var account = JsonSerializer.Serialize(fixture.Owner); var key = "organization:" + Code;
        var store = new LocalChatHistory();
        var send = new { schemaVersion = 1, sourceRef = Source, action = "sendChat", targetRef = fixture.Target,
            requestId = Guid.NewGuid().ToString("N"), text = "synthetic content", attachment = (object?)null };
        Check((await fixture.Success(send)).GetProperty("status").GetString() == "unknown", "lost send needs read confirmation");
        var calls = fixture.Handler.Requests.Count;
        var result = await fixture.Success(ChatRenewal(fixture));
        Check(fixture.Handler.Requests.Count == calls + 1 && !fixture.Handler.Requests.Skip(calls).Any(r => r.Path.EndsWith("/chat/channels") || r.Path.EndsWith("/chat/read")),
            "archive and confirmation add no network calls or read writes");
        Check(result.GetProperty("messages")[0].GetProperty("localRequestId").GetString() == send.requestId, "chat renewal emits matching local send request id");
        calls = fixture.Handler.Requests.Count;
        var receipt = await fixture.Success(send);
        Check(receipt.GetProperty("status").GetString() == "accepted" && receipt.GetProperty("sequence").GetInt64() == 1 && fixture.Handler.Requests.Count == calls,
            "chat renewal confirms uncertain send without POST replay");
        var stored = await store.Run(account, key);
        Check(stored.Length == 1 && stored[0].Text == "synthetic content" && stored[0].Self && stored[0].Name == "", "chat renewal archives content with neutral official name");
        Check(!result.GetProperty("localHistoryUnavailable").GetBoolean() && fixture.Handler.Unread == 3, "archive success preserves unread state");
        var offline = await fixture.Success(new { schemaVersion = 1, sourceRef = Source, action = "chat", targetRef = fixture.Target, after = 0, before = 0, localHistory = "read" });
        Check(offline.GetProperty("rows").GetArrayLength() == 1 && fixture.Handler.Requests.Count == calls, "renewed messages available offline without network");

        // Hold this isolated account's archive open to simulate IO failure without changing permissions.
        var folder = Path.Combine(HostDataRoot.CurrentRoot, "chat-history", Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(account))));
        var path = Path.Combine(folder, Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(key))) + ".dat");
        using var lease = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.None);
        var failedSave = await fixture.Success(ChatRenewal(fixture));
        Check(failedSave.GetProperty("localHistoryUnavailable").GetBoolean() && failedSave.GetProperty("messages").GetArrayLength() == 1,
            "archive IO failure preserves content and same unavailable signal as ordinary chat");
        var ordinaryFailure = await fixture.Success(OrdinaryChat(fixture));
        Check(ordinaryFailure.GetProperty("localHistoryUnavailable").GetBoolean(), "ordinary archive failure signal agrees with renewal");
    }

    private static object OrdinaryChat(Fixture fixture) => new { schemaVersion = 1, sourceRef = Source, action = "chat", targetRef = fixture.Target,
        after = 0, before = 0, authorIdentitySchemaVersion = 1, observeMessageRefs = Array.Empty<string>() };

    internal static async Task ChatAuthorsBrakeFallback()
    {
        using var fixture = new Fixture(); await fixture.Open();
        fixture.Handler.Status = HttpStatusCode.ServiceUnavailable;
        fixture.Handler.FailureBody = "{\"reason\":\"chatAuthorsDisabled\"}";
        var calls = fixture.Handler.Requests.Count;
        var result = await fixture.Success(OrdinaryChat(fixture));
        Check(fixture.Handler.Requests.Skip(calls).Select(r => r.Path).SequenceEqual(new[] {
            "/api/official-fleets/chat/channels", "/api/official-fleets/chat/messages/read", "/api/official-fleets/chat/messages" }), "only exact brake falls back to ordinary GET");
        Check(result.GetProperty("messages")[0].GetProperty("text").GetString() == "synthetic content" &&
            result.GetProperty("unreadCount").GetInt32() == 3 && result.GetProperty("canSend").GetBoolean(), "brake preserves ordinary content and channel fields");
        Check(!result.TryGetProperty("authorIdentitySchemaVersion", out _) && !result.TryGetProperty("authorUpdates", out _) &&
            !result.GetProperty("messages")[0].TryGetProperty("authorIdentityState", out _) && result.GetProperty("messages")[0].GetProperty("senderCallsign").GetString() == "",
            "downgraded response has neutral names and no author extension fields");
        foreach (var query in new object[] { ChatRenewal(fixture), fixture.Renewal() })
        {
            calls = fixture.Handler.Requests.Count; var failure = await fixture.Dispatch(query);
            Check(failure.Error?.Code == "communities.unavailable" && failure.Error.Retryable && fixture.Handler.Requests.Count == calls + 1,
                "renewal brake remains existing retryable error, without content fallback");
        }
        foreach (var body in new[] { "{}", "broken", "{\"reason\":\"other\"}", "{\"reason\":\"previewAuthorsDisabled\"}",
            "{\"reason\":\"chatAuthorsDisabled\",\"reason\":\"other\"}", "{\"reason\":\"chatAuthorsDisabled\",\"padding\":\"" + new string('x', 4096) + "\"}" })
        {
            fixture.Handler.FailureBody = body; calls = fixture.Handler.Requests.Count;
            var failure = await fixture.Dispatch(OrdinaryChat(fixture));
            Check(failure.Error?.Code == "communities.unavailable" && fixture.Handler.Requests.Count == calls + 2 && fixture.Handler.Requests.Last().Path.EndsWith("/read"),
                "other or malformed 503 never falls back");
        }
        fixture.Handler.FailureBody = "{\"reason\":\"chatAuthorsDisabled\"}"; fixture.Handler.Status = HttpStatusCode.BadGateway;
        Check((await fixture.Dispatch(OrdinaryChat(fixture))).Error?.Code == "communities.unavailable", "brake reason without 503 never falls back");
        fixture.Handler.Status = HttpStatusCode.OK;
        Check((await fixture.Success(OrdinaryChat(fixture))).GetProperty("authorIdentitySchemaVersion").GetInt32() == 1, "downgrade affects only one read, no cached author decision");
    }
}
