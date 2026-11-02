using System.Net;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Communities;
using StarBridge.NativeBridge;

internal static partial class OfficialFleetPreviewAuthorTests
{
    private const string Source = "officialFleet:7", Code = "OFFICIALFLEET:7";
    private static readonly string Subject = "scm-v1:" + new string('a', 64);
    private static readonly string Version = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(
        "StarBridge.OfficialFleet.CommunicationAuthor.v1\n" + JsonSerializer.Serialize(new string?[] { "Preview fixture", null })))).ToLowerInvariant();

    internal static async Task Run()
    {
        Check(AccountBridgeRuntime.AdvertisedCapabilities.Contains("officialFleet.communication.previewAuthors"), "new capability advertised");
        foreach (var variant in new object?[] { true, false, null, "true", 1, new object() })
        {
            using var f = new Fixture(); f.Handler.Preview = variant;
            var open = await f.Open();
            Check(open.GetProperty("previewAuthorsAvailable").GetBoolean() == (variant is true), "only explicit relay true enables preview");
        }
        using (var old = new Fixture())
        {
            old.Handler.OldRelay = true;
            Check(!(await old.Open()).GetProperty("previewAuthorsAvailable").GetBoolean(), "new Host accepts old relay with no optional fields");
            var legacy = await old.Success(new { schemaVersion = 1, sourceRef = Source, action = "chat", targetRef = old.Target, after = 0, before = 0 });
            Check(legacy.GetProperty("messages").GetArrayLength() == 1, "new Host ordinary chat remains usable with old relay");
        }
        using var fixture = new Fixture();
        await fixture.Open();
        var readBefore = SnapshotArchive();
        var first = await fixture.Success(fixture.Renewal());
        Check(SnapshotArchive() == readBefore, "first preview creates no archive");
        Check(fixture.Handler.Requests.Count == 2 && fixture.Handler.Requests[1].Path == "/api/official-fleets/chat/messages/read-preview",
            "open then renewal sends exactly one read and no channels request");
        var sent = fixture.Handler.Requests[1].Body;
        Check(!sent.TryGetProperty("purpose", out _) && sent.GetProperty("limit").GetInt32() == 8 &&
            sent.GetProperty("after").GetInt64() == 0 && sent.GetProperty("observedMessages").GetArrayLength() == 0,
            "latest preview uses requested limit without purpose");
        foreach (var field in new[] { "schemaVersion", "targetRef", "latestSequence", "oldestSequence", "hasOlder", "messages", "authorUpdates", "authorRefreshRequired", "authorIdentitySchemaVersion" })
            Check(first.TryGetProperty(field, out _), "chat response field " + field);
        Check(first.GetProperty("unreadCount").GetInt32() == 0 && !first.GetProperty("canSend").GetBoolean(), "unread/send values explicitly unobserved");
        var message = first.GetProperty("messages")[0];
        var reference = message.GetProperty("messageRef").GetString()!;
        var sender = message.GetProperty("senderRef").GetString();
        Check(message.GetProperty("senderCallsign").GetString() == "Preview fixture", "current proof projects author");
        var ordinary = await fixture.Success(new { schemaVersion = 1, sourceRef = Source, action = "chat", targetRef = fixture.Target,
            after = 0, before = 0, authorIdentitySchemaVersion = 1, observeMessageRefs = new[] { reference } });
        Check(ordinary.GetProperty("messages")[0].GetProperty("messageRef").GetString() == reference &&
            ordinary.GetProperty("messages")[0].GetProperty("senderRef").GetString() == sender, "ordinary chat reuses preview message and sender references");
        Check(fixture.Handler.Requests.Last().Path == "/api/official-fleets/chat/messages/read", "ordinary author read keeps original route");
        var normalRead = fixture.Handler.Requests.Last().Body;
        Check(!normalRead.TryGetProperty("purpose", out _), "ordinary author read keeps old request wire shape");
        Check(ordinary.GetProperty("unreadCount").GetInt32() == 3 && ordinary.GetProperty("canSend").GetBoolean(), "ordinary chat still reads real channel state");
        readBefore = SnapshotArchive();
        var calls = fixture.Handler.Requests.Count;
        var renewed = await fixture.Success(fixture.Renewal(1, new[] { reference }));
        Check(fixture.Handler.Requests.Count == calls + 1 && fixture.Handler.Requests.Last().Path == "/api/official-fleets/chat/messages/read-preview" &&
            !fixture.Handler.Requests.Last().Body.TryGetProperty("purpose", out _) && renewed.GetProperty("messages").GetArrayLength() == 0,
            "incremental renewal has only one read");
        var update = renewed.GetProperty("authorUpdates")[0];
        Check(update.GetProperty("messageRef").GetString() == reference && update.GetProperty("senderRef").GetString() == sender &&
            update.GetProperty("recordState").GetString() == "found", "empty page renews ordinary chat addresses");
        Check(SnapshotArchive() == readBefore && fixture.Handler.Unread == 3, "renewal leaves actual archive bytes and read state unchanged");

        foreach (var mutation in new (string Key, object? Value)[] {
            ("after", -1), ("after", long.MaxValue), ("after", "0"), ("limit", 0), ("limit", 9), ("limit", 1.5),
            ("observeMessageRefs", new[] { reference, reference }), ("observeMessageRefs", new[] { "bad" }),
            ("observeMessageRefs", new[] { new string('A', 32) }), ("observeMessageRefs", Enumerable.Range(0, 9).Select(i => i.ToString("x32")).ToArray()),
            ("observeMessageRefs", new object[] { 1 }), ("before", 0), ("localHistory", "clear"), ("authorIdentitySchemaVersion", 1),
            ("sourceRef", "officialFleet:8"), ("targetRef", new string('0', 32)) })
        {
            var body = JsonSerializer.SerializeToNode(fixture.Renewal())!.AsObject();
            body[mutation.Key] = JsonSerializer.SerializeToNode(mutation.Value);
            calls = fixture.Handler.Requests.Count;
            var invalid = await fixture.Dispatch(body);
            Check(invalid.Status != "ok" && fixture.Handler.Requests.Count == calls, "invalid renewal rejected before IO: " + mutation.Key);
        }
        foreach (var key in new[] { "after", "limit", "observeMessageRefs" })
        {
            var body = JsonSerializer.SerializeToNode(fixture.Renewal())!.AsObject(); body.Remove(key);
            calls = fixture.Handler.Requests.Count;
            Check((await fixture.Dispatch(body)).Status != "ok" && fixture.Handler.Requests.Count == calls, "required renewal field " + key);
        }
        foreach (var mapping in new[] { (503, "communities.unavailable"), (403, "communities.notAllowed"),
            (401, "communities.identityUnavailable"), (404, "communities.refreshRequired"), (409, "communities.announcementsChanged") })
        {
            fixture.Handler.Status = (HttpStatusCode)mapping.Item1;
            var failure = await fixture.Dispatch(fixture.Renewal());
            Check(failure.Error?.Code == mapping.Item2, "existing error mapping for " + mapping.Item1 + ": " + failure.Error?.Code);
            if (mapping.Item1 == 503) Check(failure.Error?.Retryable == true, "disabled preview uses retryable temporary unavailable");
        }
        fixture.Handler.Status = HttpStatusCode.OK;
        fixture.Handler.BadProof = true;
        var neutral = await fixture.Success(fixture.Renewal());
        Check(neutral.GetProperty("messages")[0].GetProperty("authorIdentityState").GetString() == "unavailable", "invalid author proof remains neutral");
        fixture.Handler.BadProof = false;
        var pending = await fixture.Host.OfficialFleetCommunicationAsync(fixture.Owner, JsonSerializer.SerializeToElement(fixture.Renewal()), default);
        fixture.Handler.Clock.Now += TimeSpan.FromSeconds(6);
        Check(JsonSerializer.SerializeToElement(pending).GetProperty("messages")[0].GetProperty("senderCallsign").GetString() == "", "expiry at final publication still redacts proof");

        using var stale = new Fixture(); await stale.Open(); stale.Handler.Hold = true;
        var held = stale.Host.OfficialFleetCommunicationAsync(stale.Owner, JsonSerializer.SerializeToElement(stale.Renewal()), default);
        await stale.Handler.Started.Task.WaitAsync(TimeSpan.FromSeconds(3));
        stale.Host.Dispose(); stale.Handler.Release.SetResult();
        var denied = false;
        try { await held; } catch (Exception error) when (error is AccountBridgeHostException or BridgeStaleGenerationException or OperationCanceledException) { denied = true; }
        Check(denied, "account generation change rejects late renewal publication");
    }

    private static string SnapshotArchive()
    {
        // Host test runtimeconfig guarantees this is a synthetic TEMP root, never product data.
        var root = Path.Combine(HostDataRoot.CurrentRoot, "chat-history");
        return !Directory.Exists(root) ? "" : string.Join(";", Directory.GetFiles(root, "*", SearchOption.AllDirectories)
            .OrderBy(path => path).Select(path => path + ":" + Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path)))));
    }
    private static void Check(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
    private sealed class Clock : TimeProvider
    {
        internal DateTimeOffset Now = DateTimeOffset.UtcNow;
        public override DateTimeOffset GetUtcNow() => Now;
    }
    private sealed class Fixture : IDisposable
    {
        internal readonly Handler Handler = new();
        internal readonly CommunityClient Client;
        internal readonly ScmAccountBridgeHost Host;
        internal readonly AccountBridgeDispatcher Dispatcher;
        internal readonly BridgeAccountContext Owner;
        internal string Target = "";
        internal Fixture()
        {
            Client = new(new("https://relay.example.test/"), Handler, Handler.Clock);
            var options = new ScmOAuthOptions("fixture-scm", new("http://127.0.0.1:3000/"), new("http://127.0.0.1:18080/"),
                new("http://127.0.0.1:18082/"), "starbridge-desktop", "starbridge-api", "organizations.read", "/oauth/callback");
            var session = new ScmOAuthSession("fixture-scm", "fixture-owner-" + Guid.NewGuid().ToString("N"), "Synthetic", "synthetic-access", DateTimeOffset.UtcNow.AddHours(1), ["organizations.read"]);
            Host = new(new OAuthPkceClient(new ScmHttpClient(Handler), new Vault(), options), new ScmProfileCacheStore(Path.GetTempPath()),
                "fixture", () => null, initialSession: session, initialGeneration: 1, communities: Client);
            Dispatcher = new(Host); Owner = Host.CurrentContext!;
        }
        internal async Task<JsonElement> Open()
        {
            var response = await Success(new { schemaVersion = 1, sourceRef = Source, action = "open" });
            Target = response.GetProperty("targetRef").GetString()!; return response;
        }
        internal object Renewal(long after = 0, string[]? observed = null) => new
            { schemaVersion = 1, sourceRef = Source, action = "chatAuthorRenewal", targetRef = Target, after, limit = 8, observeMessageRefs = observed ?? [] };
        internal async Task<BridgeEnvelope> Dispatch(object body) => (await Dispatcher.DispatchAsync(BridgeEnvelope.Request(
            "officialFleet.communication", Guid.NewGuid().ToString("N"), 1, body, Owner))).Response;
        internal async Task<JsonElement> Success(object body)
        {
            var response = await Dispatch(body); Check(response.Status == "ok", "actual Host dispatch: " + response.Error?.Code); return response.Payload;
        }
        public void Dispose() { Dispatcher.Dispose(); Host.Dispose(); Client.Dispose(); Handler.Dispose(); }
    }
    private sealed class Vault : ITokenVault
    {
        public void SaveRefreshToken(string a, string b) => throw new InvalidOperationException("No credential writes");
        public string? LoadRefreshToken(string a) => null;
        public string? LoadActiveAccountKey() => null;
        public void DeleteRefreshToken(string a) => throw new InvalidOperationException("No credential deletion");
    }
    private sealed class Handler : HttpMessageHandler
    {
        internal readonly Clock Clock = new();
        internal readonly List<(string Path, JsonElement Body)> Requests = new();
        internal object? Preview = true;
        internal bool OldRelay, BadProof, Hold, HideChatAuthors;
        internal int Unread = 3;
        internal HttpStatusCode Status = HttpStatusCode.OK;
        internal string FailureBody = "{\"reason\":\"previewAuthorsDisabled\"}";
        internal string? EchoMessageId;
        internal readonly TaskCompletionSource Started = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource Release = new(TaskCreationOptions.RunContinuationsAsynchronously);
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            var path = request.RequestUri!.AbsolutePath;
            var body = request.Content is null ? default : JsonSerializer.Deserialize<JsonElement>(await request.Content.ReadAsStringAsync(token));
            Requests.Add((path, body));
            if (path == "/api/official-fleets/context")
            {
                var context = JsonSerializer.SerializeToNode(new { schemaVersion = 1, sourceRef = Source, fleetCode = Code, name = "Fixture",
                    announcementsAvailable = true, chatAvailable = true, canSend = true, readReceiptsAvailable = true, canManageAnnouncements = false })!.AsObject();
                if (!OldRelay && !HideChatAuthors) context["authorIdentitySchemaVersion"] = 1;
                if (!OldRelay && Preview is not null) context["previewAuthorsAvailable"] = JsonSerializer.SerializeToNode(Preview);
                return Json(context);
            }
            if (path == "/api/official-fleets/chat/channels") return Json(new { totalUnread = Unread,
                channels = new[] { new { channelId = "fleet:" + Code, type = "fleet", unreadCount = Unread, canSend = true } } });
            if (path == "/api/official-fleets/chat/messages" && request.Method == HttpMethod.Post)
            {
                EchoMessageId = body.GetProperty("clientMessageId").GetString();
                throw new HttpRequestException("Synthetic lost send response");
            }
            object Message() => new { sequence = 1, messageId = EchoMessageId ?? "preview-fixture", senderAccountId = Subject, senderCallsign = "", senderGameId = "",
                senderRoleTitle = "", senderRoleColor = "#9DAAB3", text = "synthetic content", createdAt = Clock.Now.ToString("O"),
                isSelf = EchoMessageId is not null, hasAvatar = false, avatarVersion = (string?)null, hasAttachment = false };
            object Page(bool empty = false) => new { schemaVersion = 1, channelId = "fleet:" + Code, latestSequence = 1,
                oldestSequence = empty ? 0 : 1, hasOlder = false, canSend = true, serverTime = Clock.Now.ToString("O"), messages = empty ? [] : new[] { Message() } };
            if (path == "/api/official-fleets/chat/messages") return Json(Page());
            if (path is not ("/api/official-fleets/chat/messages/read" or "/api/official-fleets/chat/messages/read-preview"))
                throw new InvalidOperationException("Unexpected synthetic route " + path);
            if (Hold) { Started.TrySetResult(); await Release.Task.WaitAsync(token); }
            if (Status != HttpStatusCode.OK) return new(Status) { Content = new StringContent(FailureBody, Encoding.UTF8, "application/json") };
            var observed = body.GetProperty("observedMessages").EnumerateArray().Select(row => new
                { messageId = row.GetProperty("messageId").GetString(), sequence = row.GetProperty("sequence").GetInt64(), recordState = "found", senderAccountId = Subject }).ToArray();
            return Json(new { schemaVersion = 2, sourceRef = Source, page = Page(body.GetProperty("after").GetInt64() > 0), observedMessages = observed,
                identities = new[] { new { businessSubjectId = Subject, state = "visible", callsign = "Preview fixture", hasAvatar = false,
                    identityVersion = BadProof ? new string('0', 64) : Version, identityObservedAtUtc = Clock.Now, identityValidUntilUtc = Clock.Now.AddSeconds(5) } },
                authorRefreshRequired = false });
        }
        private static HttpResponseMessage Json(object body) => new(HttpStatusCode.OK) { Content = JsonContent.Create(body) };
    }
}
