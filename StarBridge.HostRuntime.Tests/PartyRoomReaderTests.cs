using System.Net;
using System.Text;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.PartyRooms;
using StarBridge.NativeBridge;

internal static class PartyRoomReaderTests
{
    internal static async Task Commands()
    {
        var methods = new List<string>();
        using var reader = new PartyRoomReader(new Uri("https://relay.example.test/"), new Handler(request => {
            methods.Add(request.Method.Method);
            if (request.Method == HttpMethod.Get)
                return new(HttpStatusCode.OK) { Content = new ByteArrayContent(Wire(null, Room("one"))) };
            Check(request.RequestUri!.AbsolutePath == "/api/party-rooms/join", "Fixed command endpoint.");
            var body = request.Content!.ReadAsStringAsync().GetAwaiter().GetResult();
            Check(!body.Contains("bearer") && !body.Contains("accountId") && body.Contains("memberState"), "Identity comes from bearer, not UI.");
            return new(HttpStatusCode.OK) { Content = new StringContent("{\"status\":\"pending\",\"error\":null}") };
        }));
        var payload = JsonSerializer.SerializeToElement(new { schemaVersion = 1, operation = "join", data = new { roomId = "one", password = "" } });
        var pending = await reader.ExecuteAsync("test-bearer", payload, default);
        Check(pending.Status == "pending" && pending.Directory!.CurrentRoomId is null, "Application is not membership.");
        Check(methods.SequenceEqual(new[] { "POST", "GET" }), "One command followed by authoritative read.");
        var invalid = JsonSerializer.SerializeToElement(new { schemaVersion = 1, operation = "join", data = new { roomId = "one", password = "", accountId = "spoofed" } });
        try { await reader.ExecuteAsync("test-bearer", invalid, default); throw new Exception("Unsafe command accepted."); }
        catch (AccountBridgeHostException error) { Check(error.Code == "party_rooms.data_invalid" && methods.Count == 2, "Reject unknown fields before HTTP."); }
        var posts = 0;
        using var failed = new PartyRoomReader(new Uri("https://relay.example.test/"), new Handler(_ => {
            posts++; throw new HttpRequestException("private transport error");
        }));
        try { await failed.ExecuteAsync("test-bearer", payload, default); throw new Exception("Unknown outcome hidden."); }
        catch (AccountBridgeHostException error) { Check(error.Code == "party_rooms.outcome_unknown" && posts == 1, "Never replay uncertain writes."); }
        using var refreshFailed = new PartyRoomReader(new Uri("https://relay.example.test/"), new Handler(request =>
            request.Method == HttpMethod.Post ? new(HttpStatusCode.OK) { Content = new StringContent("{\"status\":\"joined\"}") }
            : new(HttpStatusCode.ServiceUnavailable)));
        var accepted = await refreshFailed.ExecuteAsync("test-bearer", payload, default);
        Check(accepted.Status == "joined" && accepted.Error == "refreshRequired" && accepted.Directory is null, "Accepted write and failed read are distinct.");
    }

    internal static async Task CommandValidation()
    {
        var calls = 0;
        var draft = new Dictionary<string, object?> {
            ["title"] = "测试房间", ["goal"] = "", ["capacity"] = 4, ["isPublic"] = true,
            ["eligibility"] = "everyone", ["admissionMode"] = "direct", ["passwordEnabled"] = true,
            ["password"] = "test-only", ["voiceRequirement"] = "recommended", ["language"] = "zh",
            ["recruitmentDurationMinutes"] = 240, ["autoDisbandHours"] = 6,
            ["gameplayTagNodeIds"] = new[] { "support_cargo_escort" }, ["contextTagIds"] = Array.Empty<string>()
        };
        using var reader = new PartyRoomReader(new Uri("https://relay.example.test/"), new Handler(request => {
            calls++;
            if (request.Method == HttpMethod.Get)
                return new(HttpStatusCode.OK) { Content = new ByteArrayContent(Wire("one", Room("one"))) };
            Check(request.RequestUri!.AbsolutePath == "/api/party-rooms", "Fixed create endpoint.");
            Check(request.Headers.Authorization?.Parameter == "test-bearer", "Current bearer on write.");
            using var body = JsonDocument.Parse(request.Content!.ReadAsStringAsync().GetAwaiter().GetResult());
            Check(body.RootElement.GetProperty("tagCatalogVersion").GetInt32() == 3, "WPF catalog version accompanies create.");
            Check(body.RootElement.GetProperty("hostState").ValueKind == JsonValueKind.Null, "Do not fabricate host presence.");
            return new(HttpStatusCode.OK) { Content = new StringContent("{\"status\":\"joined\"}") };
        }));
        JsonElement Payload() => JsonSerializer.SerializeToElement(new { schemaVersion = 1, operation = "create", data = draft });
        Check((await reader.ExecuteAsync("test-bearer", Payload(), default)).Directory!.CurrentRoomId == "one", "Create uses authoritative membership.");
        foreach (var invalid in new (string Key, object? Value)[] {
            ("capacity", 17), ("title", "x"), ("password", "123"), ("autoDisbandHours", 5),
            ("recruitmentDurationMinutes", 361), ("language", "any"),
            ("gameplayTagNodeIds", new[] { "unknown" }), ("gameplayTagNodeIds", Array.Empty<string>()),
            ("gameplayTagNodeIds", new[] { "support", "support_cargo_escort" }) })
        {
            var saved = draft[invalid.Key]; draft[invalid.Key] = invalid.Value;
            try { await reader.ExecuteAsync("test-bearer", Payload(), default); throw new Exception("Invalid draft sent."); }
            catch (AccountBridgeHostException error) { Check(error.Code == "party_rooms.data_invalid" && calls == 2, "Invalid draft stays local."); }
            draft[invalid.Key] = saved;
        }
        var join = JsonSerializer.SerializeToElement(new { schemaVersion = 1, operation = "join", data = new { roomId = "one", password = "" } });
        foreach (var content in new[] { "{}", "{\"status\":\"closed\"}", new string('x', 2 * 1024 * 1024 + 1) })
        {
            var sends = 0;
            using var malformed = new PartyRoomReader(new Uri("https://relay.example.test/"), new Handler(_ => {
                sends++; return new(HttpStatusCode.OK) { Content = new StringContent(content) };
            }));
            try { await malformed.ExecuteAsync("test-bearer", join, default); throw new Exception("Malformed write response accepted."); }
            catch (AccountBridgeHostException error) { Check(error.Code == "party_rooms.outcome_unknown" && sends == 1, "Malformed response blocks replay."); }
        }
        foreach (var status in new[] { HttpStatusCode.Unauthorized, HttpStatusCode.Forbidden })
        {
            var sends = 0;
            using var denied = new PartyRoomReader(new Uri("https://relay.example.test/"), new Handler(_ => {
                sends++; return new(status) { Content = new StringContent("private") };
            }));
            try { await denied.ExecuteAsync("test-bearer", join, default); throw new Exception("Denied write accepted."); }
            catch (AccountBridgeHostException error) { Check(sends == 1 && error.Code == (status == HttpStatusCode.Unauthorized ? "party_rooms.identity_unavailable" : "party_rooms.forbidden"), "No auth replay or private error disclosure."); }
        }
    }

    internal static Task Projection()
    {
        var directory = PartyRoomReader.Parse(Wire(null, Room("one"), Room("two")));
        Check(directory.Rooms.Length == 2 && directory.CurrentRoomId is null, "Directory membership must be explicit.");
        var wire = BridgePayload.From(directory);
        Check(wire.GetProperty("currentRoomId").ValueKind == JsonValueKind.Null, "Bridge must preserve explicit null membership.");
        var text = wire.GetRawText();
        Check(!text.Contains("private-") && !text.Contains("roomCode") && !text.Contains("accountId"), "No private identifiers cross the bridge.");
        Check(directory.Rooms[0].Members[0].GameId == "Citizen_CN", "Handle casing must survive.");
        Check(directory.Rooms[0].LeaderServerRegion == "US", "Only the host's broad region is projected for discovery.");
        Check(directory.Rooms[0].Tags.Select(tag => tag.Text).SequenceEqual(new[] {
            "救援与支援 · 护航安保 · 货运护航", "新手友好" }), "Reuse WPF paths, legacy aliases and context labels; deduplicate and omit unknown IDs.");
        var current = PartyRoomReader.Parse(Wire("two", Room("one"), Room("two")));
        Check(current.Rooms.Length == 1 && current.Rooms[0].RoomId == "two", "Joined users cannot browse other rooms.");
        Check(current.Rooms.Single().RoomCode == "private-code", "Room code is available only for the authoritative current room.");
        Check(directory.Rooms.All(room => room.RoomCode is null), "Discovery never leaks room codes.");
        Check(PartyRoomReader.Parse(Wire(null)).Rooms.Length == 0, "Explicit empty is valid.");
        var sample = Encoding.UTF8.GetString(Wire(null, Room("one")));
        foreach (var pair in new[] { ("pub_euc1_00000000_001", "EU"), ("pub_apse2_00000000_001", "AU"),
            ("pub_apse1_00000000_001", "ASIA"), ("美服", "US"), ("未进入游戏", ""), ("", "") })
        {
            var mapped = PartyRoomReader.Parse(Encoding.UTF8.GetBytes(sample.Replace("pub_use1b_00000000_001", pair.Item1)));
            Check(mapped.Rooms[0].LeaderServerRegion == pair.Item2, "WPF region vocabulary and unknown states stay consistent.");
            Check(mapped.Rooms[0].Members.Single().ServerRegion == pair.Item2, "Member banners receive the same broad region, never a shard code.");
        }
        var noHost = PartyRoomReader.Parse(Encoding.UTF8.GetBytes(sample.Replace("\"isHost\":true", "\"isHost\":false")));
        Check(noHost.Rooms[0].LeaderServerRegion == "", "Never substitute another member's server for the leader.");
        return Task.CompletedTask;
    }

    internal static async Task Management()
    {
        byte[] Directory(bool host = true, bool application = true) {
            var node = System.Text.Json.Nodes.JsonNode.Parse(Wire("one", Room("one")))!;
            var room = node["rooms"]![0]!;
            room["viewerIsHost"] = host;
            room["pendingApplications"] = JsonSerializer.SerializeToNode(application ? new[] {
                new { applicationId = "application-1", callsign = "申请者", gameId = "Mixed_Case", createdAt = "2026-09-06T12:00:00Z", accountId = "private-account", avatarImageData = "private-avatar" }
            } : []);
            return Encoding.UTF8.GetBytes(node.ToJsonString());
        }
        var projection = PartyRoomReader.Parse(Directory());
        Check(projection.Rooms.Single().PendingApplications.Single().GameId == "Mixed_Case", "Application Handle case preserved.");
        var json = BridgePayload.From(projection).GetRawText();
        Check(!json.Contains("private-account") && !json.Contains("private-avatar"), "No internal identity or image data in applications.");
        Check(PartyRoomReader.Parse(Directory(false)).Rooms.Single().PendingApplications.Length == 0, "Non-host never receives pending applications.");
        var discovery = Encoding.UTF8.GetString(Directory()).Replace("\"currentRoomId\":\"one\"", "\"currentRoomId\":null");
        Check(PartyRoomReader.Parse(Encoding.UTF8.GetBytes(discovery)).Rooms.Single().PendingApplications.Length == 0, "Discovery cannot leak applications even with host flag.");
        foreach (var approve in new[] { true, false })
        {
            var methods = new List<string>();
            using var reader = new PartyRoomReader(new Uri("https://relay.example.test/"), new Handler(request => {
                methods.Add(request.Method.Method);
                if (request.Method == HttpMethod.Get) return new(HttpStatusCode.OK) { Content = new ByteArrayContent(Directory()) };
                Check(request.RequestUri!.AbsolutePath == "/api/party-rooms/applications/decision", "Fixed application endpoint.");
                return new(HttpStatusCode.OK) { Content = JsonContent(approve ? "joined" : "rejected") };
            }));
            var result = await reader.ExecuteAsync("test-bearer", JsonSerializer.SerializeToElement(new {
                schemaVersion = 1, operation = "decide", data = new { roomId = "one", applicationId = "application-1", approve }
            }), default);
            Check(result.Status == (approve ? "approved" : "declined") && result.Error is null, "Declining is successful handling, not failed join.");
            Check(methods.SequenceEqual(new[] { "GET", "POST", "GET" }), "Check role then write once and refresh authoritative state.");
        }
        foreach (var host in new[] { true, false })
        {
            var sends = 0;
            using var reader = new PartyRoomReader(new Uri("https://relay.example.test/"), new Handler(request => {
                Check(request.Method == HttpMethod.Get, "Stale role/application cannot write."); sends++;
                return new(HttpStatusCode.OK) { Content = new ByteArrayContent(Directory(host, false)) };
            }));
            var result = await reader.ExecuteAsync("test-bearer", JsonSerializer.SerializeToElement(new {
                schemaVersion = 1, operation = "decide", data = new { roomId = "one", applicationId = "application-1", approve = true }
            }), default);
            Check(result.Status == "rejected" && result.Error == (host ? "applicationGone" : "notHost") && sends == 1, "Stale role and stale application are explicit.");
        }
        foreach (var mode in new[] { "keep", "remove", "replace" })
        {
            var methods = new List<string>();
            using var reader = new PartyRoomReader(new Uri("https://relay.example.test/"), new Handler(request => {
                methods.Add(request.Method.Method);
                if (request.Method == HttpMethod.Get) return new(HttpStatusCode.OK) { Content = new ByteArrayContent(Directory()) };
                Check(request.RequestUri!.AbsolutePath == "/api/party-rooms/update", "Fixed update endpoint.");
                using var body = JsonDocument.Parse(request.Content!.ReadAsStringAsync().GetAwaiter().GetResult());
                Check(body.RootElement.GetProperty("passwordMode").GetString() == mode, "Explicit password mode preserved.");
                Check(body.RootElement.GetProperty("password").GetString() == (mode == "replace" ? "new-test-password" : null), "No old password read or accidental replacement.");
                return new(HttpStatusCode.OK) { Content = JsonContent("updated") };
            }));
            var result = await reader.ExecuteAsync("test-bearer", JsonSerializer.SerializeToElement(new {
                schemaVersion = 1, operation = "update", data = new { roomId = "one", title = "更新名称", goal = "", capacity = 6,
                    isPublic = true, eligibility = "everyone", admissionMode = "approval", passwordMode = mode,
                    password = mode == "replace" ? "new-test-password" : "", voiceRequirement = "recommended", language = "zh",
                    autoDisbandHours = 6, recruitmentDurationMinutes = (int?)null,
                    gameplayTagNodeIds = new[] { "support_cargo_escort" }, contextTagIds = Array.Empty<string>() }
            }), default);
            Check(result.Status == "updated" && methods.SequenceEqual(new[] { "GET", "POST", "GET" }), "Settings update re-reads membership and never retries.");
        }
        using var close = new PartyRoomReader(new Uri("https://relay.example.test/"), new Handler(request =>
            request.Method == HttpMethod.Get ? new(HttpStatusCode.OK) { Content = new ByteArrayContent(Directory()) }
            : request.RequestUri!.AbsolutePath == "/api/party-rooms/close" ? new(HttpStatusCode.OK) { Content = JsonContent("closed") }
            : throw new Exception("Unexpected close route.")));
        Check((await close.ExecuteAsync("test-bearer", JsonSerializer.SerializeToElement(new {
            schemaVersion = 1, operation = "close", data = new { roomId = "one" }
        }), default)).Status == "closed", "Host close follows dedicated endpoint.");
        var closePayload = JsonSerializer.SerializeToElement(new {
            schemaVersion = 1, operation = "close", data = new { roomId = "one" }
        });
        var preflightCalls = 0;
        using var unavailable = new PartyRoomReader(new Uri("https://relay.example.test/"), new Handler(request => {
            preflightCalls++;
            Check(request.Method == HttpMethod.Get, "Failed preflight must not dispatch a write.");
            return new(HttpStatusCode.ServiceUnavailable);
        }));
        try { await unavailable.ExecuteAsync("test-bearer", closePayload, default); throw new Exception("Failed preflight hidden."); }
        catch (AccountBridgeHostException error) { Check(error.Code == "party_rooms.command_unavailable" && preflightCalls == 1, "Read failure is safely retryable before dispatch."); }
        var refreshCalls = 0;
        var writes = 0;
        using var lostRefresh = new PartyRoomReader(new Uri("https://relay.example.test/"), new Handler(request => {
            if (request.Method == HttpMethod.Post) { writes++; return new(HttpStatusCode.OK) { Content = JsonContent("closed") }; }
            return ++refreshCalls == 1 ? new(HttpStatusCode.OK) { Content = new ByteArrayContent(Directory()) }
                : new(HttpStatusCode.ServiceUnavailable);
        }));
        var closedWithoutRefresh = await lostRefresh.ExecuteAsync("test-bearer", closePayload, default);
        Check(closedWithoutRefresh.Status == "closed" && closedWithoutRefresh.Error == "refreshRequired" && writes == 1,
            "Successful disband is not replayed when authoritative refresh fails.");
    }

    private static StringContent JsonContent(string status) => new(JsonSerializer.Serialize(new { status }));

    internal static Task InvalidData()
    {
        foreach (var bytes in new[] {
            Encoding.UTF8.GetBytes("{}"), Encoding.UTF8.GetBytes("not json"),
            Wire("missing", Room("one")), Wire(null, Room("one"), Room("one")),
            Wire(null, Room("one", 17)), Wire(null, Room("one", 1)),
            Encoding.UTF8.GetBytes("{\"rooms\":[],\"serverTime\":\"2026-09-05T12:00:00Z\"}") })
        {
            try { PartyRoomReader.Parse(bytes); throw new Exception("Invalid room data accepted."); }
            catch (AccountBridgeHostException error) { Check(error.Code == "party_rooms.data_invalid", "Stable invalid-data error."); }
        }
        return Task.CompletedTask;
    }

    internal static async Task HttpBoundary()
    {
        var calls = 0;
        using var reader = new PartyRoomReader(new Uri("https://relay.example.test/"), new Handler(request => {
            calls++;
            Check(request.Method == HttpMethod.Get && request.RequestUri!.AbsolutePath == "/api/party-rooms", "Read endpoint only.");
            Check(request.Headers.Authorization?.ToString() == "Bearer test-bearer", "SCM bearer attached per request.");
            return new(HttpStatusCode.OK) { Content = new ByteArrayContent(Wire(null, Room("one"))) };
        }));
        Check((await reader.ReadAsync("test-bearer", default)).Rooms.Length == 1 && calls == 1, "One read, no writes.");
        foreach (var pair in new[] {
            (HttpStatusCode.Unauthorized, "party_rooms.identity_unavailable"),
            (HttpStatusCode.Forbidden, "party_rooms.forbidden"),
            (HttpStatusCode.Redirect, "party_rooms.read_unavailable"),
            (HttpStatusCode.ServiceUnavailable, "party_rooms.read_unavailable") })
        {
            using var failing = new PartyRoomReader(new Uri("https://relay.example.test/"), new Handler(_ =>
                new(pair.Item1) { Content = new StringContent("private-error-body") }));
            try { await failing.ReadAsync("test-bearer", default); throw new Exception("Failure accepted."); }
            catch (AccountBridgeHostException error) { Check(error.Code == pair.Item2 && !error.Message.Contains("private"), "Stable safe error."); }
        }
        using var oversized = new PartyRoomReader(new Uri("http://127.0.0.1:8080"), new Handler(_ =>
            new(HttpStatusCode.OK) { Content = new ByteArrayContent(new byte[2 * 1024 * 1024 + 1]) }));
        try { await oversized.ReadAsync("test-bearer", default); throw new Exception("Oversized response accepted."); }
        catch (AccountBridgeHostException error) { Check(error.Code == "party_rooms.data_invalid", "Response bound."); }
        foreach (var url in new[] { "http://relay.example.test", "https://user:pass" + "@example.test", "https://example.test/?token=bad" })
        {
            try { using var rejected = new PartyRoomReader(new Uri(url)); throw new Exception("Unsafe origin accepted."); }
            catch (ArgumentException) { }
        }
    }

    internal static object Room(string id, int capacity = 4) => new {
        roomId = id, roomCode = "private-code", ownerAccountId = "private-owner",
        title = "Test room", goal = "Test goal", capacity, isPublic = true, eligibility = "everyone",
        gameplayTagNodeIds = new[] { "mixed_escort", "support_cargo_escort", "unknown-tag" },
        contextTagIds = new[] { "experience_beginner_friendly", "unknown-context" },
        admissionMode = "approval", passwordRequired = false, voiceRequirement = "recommended", language = "zh",
        expiresAt = "2026-09-06T12:00:00Z", recruitmentClosesAt = (string?)null, viewerIsHost = false,
        members = new[] { new { accountId = "private-member", callsign = "测试呼号", gameId = "Citizen_CN",
            isHost = true, presenceText = "游戏中", locationText = "", shipText = "", shardText = "pub_use1b_00000000_001" } }
    };
    internal static byte[] Wire(string? current, params object[] rooms) =>
        JsonSerializer.SerializeToUtf8Bytes(new { currentRoomId = current, serverTime = "2026-09-05T12:00:00Z", rooms });
    private static void Check(bool condition, string reason) { if (!condition) throw new Exception(reason); }
    private sealed class Handler(Func<HttpRequestMessage, HttpResponseMessage> send) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) =>
            Task.FromResult(send(request));
    }
}
