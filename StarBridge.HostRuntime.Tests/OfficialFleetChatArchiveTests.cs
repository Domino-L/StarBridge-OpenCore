using System.Net;
using System.Net.Http.Json;
using System.Diagnostics;
using System.Runtime.Versioning;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Chat;
using StarBridge.HostRuntime.Communities;
using StarBridge.HostRuntime.Friends;
using StarBridge.NativeBridge;

[SupportedOSPlatform("windows")]
internal static class OfficialFleetChatArchiveTests
{
    private static readonly JsonSerializerOptions Web = new(JsonSerializerDefaults.Web);

    // ChatHistoryArchive has one process-owned store. Keep a suite's existing
    // store/root untouched instead of replacing or reflecting into that owner.
    internal static async Task RunIsolated()
    {
        var start = new ProcessStartInfo("dotnet") { UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardOutput = true, RedirectStandardError = true };
        foreach (var argument in new[] { "exec", typeof(OfficialFleetChatArchiveTests).Assembly.Location,
            "--official-chat-archive-p0", "all" }) start.ArgumentList.Add(argument);
        using var worker = Process.Start(start) ?? throw new InvalidOperationException("P0 worker unavailable");
        var output = worker.StandardOutput.ReadToEndAsync(); var error = worker.StandardError.ReadToEndAsync();
        await worker.WaitForExitAsync().WaitAsync(TimeSpan.FromSeconds(30));
        Console.Write(await output); Console.Error.Write(await error);
        Check(worker.ExitCode == 0, "isolated P0 worker preserves any existing suite archive root");
    }

    internal static async Task Run(string mode = "all")
    {
        if (!OperatingSystem.IsWindows()) throw new PlatformNotSupportedException("P0 requires actual Windows DPAPI, never a stub or skip.");
        if (mode is not ("all" or "read" or "append")) throw new ArgumentException(nameof(mode));
        using var fixture = new Fixture();
        if (mode is "all" or "read") await ReadExisting(fixture);
        if (mode is "all" or "append") await Append(fixture);
        await CommunityAndPrivateControls(fixture);
        Console.WriteLine("PASS P0 uses actual Host dispatch, original archive owner and Windows DPAPI; no account-file migration or live network");
    }

    private static async Task ReadExisting(Fixture fixture)
    {
        var now = DateTimeOffset.UtcNow.AddMinutes(-1);
        var old = new LocalChatLine[] {
            new(1, "old-scm-display-fixture", "retained content one", now, false, true),
            new(2, "expired-bridge-display-fixture", "retained content two", now.AddSeconds(1), true, false)
        };
        await fixture.Store.Run(fixture.Account, "organization:OFFICIALFLEET:7", old);
        var path = fixture.File("organization:OFFICIALFLEET:7");
        var before = await File.ReadAllBytesAsync(path);
        Check(!Encoding.UTF8.GetString(before).Contains(old[0].Name), "real DPAPI archive is encrypted at rest");
        Check((await fixture.Store.Run(fixture.Account, "organization:OFFICIALFLEET:7")).SequenceEqual(old), "same original owner decrypts the seeded old record");
        var calls = fixture.Handler.Calls;
        var read = await fixture.Dispatch(new { schemaVersion = 1, sourceRef = "officialFleet:7", action = "chat",
            targetRef = fixture.Target, after = 0, before = 0, localHistory = "read" });
        var after = await File.ReadAllBytesAsync(path);
        Console.WriteLine("P0_DPAPI_READ_HASH " + JsonSerializer.Serialize(new { path,
            beforeSha256 = Convert.ToHexString(SHA256.HashData(before)), afterSha256 = Convert.ToHexString(SHA256.HashData(after)) }));
        Check(before.SequenceEqual(after), "actual official localHistory read leaves original encrypted file bytes/hash unchanged");
        Check(fixture.Handler.Calls == calls, "official localHistory dispatch performs no author lookup or HTTP");
        var rows = ReadRows(read);
        Check(rows.Select(row => row with { Name = "" }).SequenceEqual(old.Select(row => row with { Name = "" })),
            "official history preserves content, time, order, self and attachment booleans");
        Check(rows.All(row => row.Name == ""), "official old SCM/expired Bridge names are neutral at the actual dispatcher boundary");
        Check((await fixture.Store.Run(fixture.Account, "organization:OFFICIALFLEET:7")).SequenceEqual(old), "read projection does not overwrite old names in storage");
        var denied = await fixture.Dispatcher.DispatchAsync(BridgeEnvelope.Request("officialFleet.communication", Guid.NewGuid().ToString("N"), 1,
            new { schemaVersion = 1, sourceRef = "officialFleet:8", action = "chat", targetRef = fixture.Target,
                after = 0, before = 0, localHistory = "read" }, fixture.Owner));
        Check(denied.Response.Status != "ok" && fixture.Handler.Calls == calls, "cross-source archive request remains rejected before IO");
        Console.WriteLine("PASS P0 old official archive read: DPAPI original hash unchanged, names neutral, no network or authority fields");
    }

    private static async Task Append(Fixture fixture)
    {
        var read = await fixture.Dispatch(new { schemaVersion = 1, sourceRef = "officialFleet:7", action = "chat",
            targetRef = fixture.Target, after = 0, before = 0 });
        var messages = read.GetProperty("messages").EnumerateArray().ToArray();
        Check(messages.Length == 2 && messages.All(message =>
                message.GetProperty("senderCallsign").GetString() == "" &&
                message.GetProperty("senderGameId").GetString() == "" &&
                message.GetProperty("senderRoleTitle").GetString() == "" &&
                !message.GetProperty("hasAvatar").GetBoolean() &&
                (!message.TryGetProperty("avatarVersion", out var avatarVersion) ||
                    avatarVersion.ValueKind == JsonValueKind.Null)),
            "official chat without identity opt-in keeps raw SCM sender identity neutral");
        var stored = await fixture.Store.Run(fixture.Account, "organization:OFFICIALFLEET:7");
        var appended = stored.Where(row => row.Sequence is 3 or 4).ToArray();
        Check(appended.Length == 2 && appended[0].Text == "current content 3" && appended[1].Self,
            "actual Host page appends both original messages to the same archive owner");
        Check(appended.All(row => row.Name == ""), "official append never persists current Bridge/SCM display names");
        var raw = JsonSerializer.SerializeToElement(stored, Web);
        Check(raw.EnumerateArray().All(row => row.EnumerateObject().Select(property => property.Name).Order().SequenceEqual(
            new[] { "sequence", "name", "text", "time", "self", "attachment" }.Order())),
            "archive retains only the original six display fields: no avatar, credential, BID, target, grant, receipt or action refs");
        var path = fixture.File("organization:OFFICIALFLEET:7");
        var bytes = await File.ReadAllBytesAsync(path);
        Check(!Encoding.UTF8.GetString(bytes).Contains("current content"), "actual appended archive uses Windows DPAPI encryption");
        var calls = fixture.Handler.Calls;
        var local = await fixture.Dispatch(new { schemaVersion = 1, sourceRef = "officialFleet:7", action = "chat",
            targetRef = fixture.Target, after = 0, before = 0, localHistory = "read" });
        Check(ReadRows(local).All(row => row.Name == "") && fixture.Handler.Calls == calls,
            "new official offline view also stays neutral without identity fetch or name reverse lookup");
        Console.WriteLine("PASS P0 official append: neutral durable names, original content fields, encrypted original store");
    }

    private static async Task CommunityAndPrivateControls(Fixture fixture)
    {
        var directory = await fixture.Client.ReadAsync("synthetic-access", new("mine", "", null, null), "community-scope", default);
        var reference = directory.Items.Single().TargetRef;
        await fixture.Client.ReadChatAsync("synthetic-access", JsonSerializer.SerializeToElement(new { schemaVersion = 1,
            targetRef = reference, after = 0, before = 0 }), "community-scope", () => { }, default, fixture.Account);
        var stored = await fixture.Store.Run(fixture.Account, "organization:A");
        Check(stored.Length == 2 && stored.All(row => row.Name == "dynamic-bridge-or-scm-name-fixture"), "ordinary community append keeps existing sender names");
        var community = JsonSerializer.SerializeToElement(await fixture.Client.ReadChatAsync("synthetic-access", JsonSerializer.SerializeToElement(new {
            schemaVersion = 1, targetRef = reference, after = 0, before = 0, localHistory = "read" }), "community-scope", () => { }, default, fixture.Account), Web);
        Check(ReadRows(community).SequenceEqual(stored), "ordinary community read keeps original archive display semantics");

        using var privateHandler = new PrivateHandler();
        using var friends = new FriendsReader(new("https://private.example.test/"), privateHandler);
        var conversations = (ConversationsView)await friends.ReadChatAsync("synthetic-access", JsonSerializer.SerializeToElement(new { schemaVersion = 1 }), default, "private-scope");
        var privateRef = conversations.Conversations.Single().TargetRef;
        var privateRows = new LocalChatLine[] { new(1, "unchanged-private-name-fixture", "private retained content", DateTimeOffset.UtcNow.AddMinutes(-1), false, false) };
        await fixture.Store.Run(fixture.Account, "private:synthetic-peer", privateRows);
        var privateResult = JsonSerializer.SerializeToElement(await friends.ReadChatAsync("synthetic-access", JsonSerializer.SerializeToElement(new {
            schemaVersion = 1, targetRef = privateRef, localHistory = "read" }), default, "private-scope", fixture.Account), Web);
        Check(ReadRows(privateResult).SequenceEqual(privateRows) && privateHandler.Calls == 1,
            "actual private reader default retains names and reads its existing local owner without network");
        Console.WriteLine("PASS P0 positive controls: community append/read and actual private reader retain original names");
    }

    private static LocalChatLine[] ReadRows(JsonElement root)
    {
        Check(root.GetProperty("schemaVersion").GetInt32() == 1 && (!root.TryGetProperty("error", out var error) || error.ValueKind == JsonValueKind.Null),
            "unchanged local history shape and successful original owner");
        return root.GetProperty("rows").Deserialize<LocalChatLine[]>(Web)!;
    }
    private static void Check(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); Console.WriteLine("PASS " + message); }

    private sealed class Fixture : IDisposable
    {
        private readonly string _previousRoot = HostDataRoot.CurrentRoot;
        internal readonly Handler Handler = new();
        internal readonly string Root;
        internal readonly CommunityClient Client;
        internal readonly ScmAccountBridgeHost Host;
        internal readonly AccountBridgeDispatcher Dispatcher;
        internal readonly BridgeAccountContext Owner;
        internal readonly LocalChatHistory Store;
        internal readonly string Account;
        internal readonly string Target;
        internal Fixture()
        {
            Root = Path.Combine(Path.GetTempPath(), "StarBridge-P0-official-archive-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(Root); HostDataRoot.UsePreparedRoot(Root); Store = new LocalChatHistory();
            Client = new(new("https://relay.example.test/"), Handler);
            var options = new ScmOAuthOptions("fixture-scm", new("http://127.0.0.1:3000/"), new("http://127.0.0.1:18080/"),
                new("http://127.0.0.1:18082/"), "starbridge-desktop", "starbridge-api", "organizations.read", "/oauth/callback");
            var session = new ScmOAuthSession("fixture-scm", "fixture-owner", "Synthetic", "synthetic-access", DateTimeOffset.UtcNow.AddHours(1), ["organizations.read"]);
            Host = new(new OAuthPkceClient(new ScmHttpClient(Handler), new Vault(), options), new ScmProfileCacheStore(Root), "fixture", () => null,
                initialSession: session, initialGeneration: 1, communities: Client);
            Dispatcher = new(Host); Owner = Host.CurrentContext!; Account = JsonSerializer.Serialize(Owner);
            Target = Dispatch(new { schemaVersion = 1, sourceRef = "officialFleet:7", action = "open" }).GetAwaiter().GetResult().GetProperty("targetRef").GetString()!;
            Console.WriteLine("P0_DPAPI_FIXTURE_ROOT " + Root);
        }
        internal async Task<JsonElement> Dispatch(object body)
        {
            var response = (await Dispatcher.DispatchAsync(BridgeEnvelope.Request("officialFleet.communication", Guid.NewGuid().ToString("N"), 1, body, Owner))).Response;
            Check(response.Status == "ok", "actual official communication Host dispatcher accepts current synthetic scope");
            return response.Payload;
        }
        internal string File(string key) => Path.Combine(Root, "chat-history", Hash(Account), Hash(key) + ".dat");
        private static string Hash(string value) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value)));
        public void Dispose() { Dispatcher.Dispose(); Host.Dispose(); Client.Dispose(); Handler.Dispose(); HostDataRoot.UsePreparedRoot(_previousRoot); }
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
        internal int Calls;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Calls++; var path = request.RequestUri!.AbsolutePath;
            Check(request.Method == HttpMethod.Get && request.Headers.Authorization?.Parameter == "synthetic-access", "fixture uses supplied bearer and GET only");
            if (path == "/api/official-fleets/context") return Json(new { schemaVersion = 1, sourceRef = "officialFleet:7", fleetCode = "OFFICIALFLEET:7",
                name = "Fixture", announcementsAvailable = true, chatAvailable = true, canSend = false, readReceiptsAvailable = false, canManageAnnouncements = false });
            if (path == "/api/fleets/directory") return Json(new { schemaVersion = 1, membershipModelVersion = 2, view = "mine", query = "", next = (string?)null,
                items = new[] { new { code = "A", name = "Community fixture", description = "", language = "", activeTime = "", memberCount = 2,
                    relationship = "member", joinMode = "direct", actions = new[] { "leave" }, logoImageData = (string?)null } } });
            var code = path.StartsWith("/api/official-fleets/", StringComparison.Ordinal) ? "OFFICIALFLEET:7" : "A";
            var channel = "fleet:" + code;
            if (path.EndsWith("/chat/channels", StringComparison.Ordinal)) return Json(new { totalUnread = 2,
                channels = new[] { new { channelId = channel, type = "fleet", unreadCount = 2, latestSequence = 4, canSend = false } } });
            if (path.EndsWith("/chat/messages", StringComparison.Ordinal)) return Json(new { schemaVersion = 1, channelId = channel, latestSequence = 4,
                oldestSequence = 3, hasOlder = true, canSend = false, serverTime = DateTimeOffset.UtcNow,
                messages = new[] { 3, 4 }.Select(sequence => new { sequence, messageId = "synthetic-message-" + sequence, senderAccountId = "scm-v1:" + new string('a', 64),
                    senderCallsign = "dynamic-bridge-or-scm-name-fixture", senderGameId = "sensitive-game-id-fixture", senderRoleTitle = "Role", senderRoleColor = "#9DAAB3",
                    text = "current content " + sequence, createdAt = DateTimeOffset.UtcNow.AddMinutes(-1), isSelf = sequence == 4,
                    hasAvatar = true, avatarVersion = new string('b', 64), hasAttachment = false }) });
            throw new InvalidOperationException("Unexpected network route: " + path);
        }
    }
    private sealed class PrivateHandler : HttpMessageHandler
    {
        internal int Calls;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Calls++; Check(request.RequestUri!.AbsolutePath.EndsWith("conversations", StringComparison.Ordinal), "private fixture only opens current conversation");
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(new { conversations = new[] {
                new { user = new { accountId = "synthetic-peer", callsign = "Private peer", gameId = "" }, lastMessagePreview = "", lastMessageAt = DateTimeOffset.UtcNow,
                    unreadCount = 0, conversationState = "friend" } }, totalUnread = 0, serverTime = DateTimeOffset.UtcNow }) });
        }
    }
    private static Task<HttpResponseMessage> Json(object body) => Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(body) });
}
