using System.Net;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.PartyRooms;
using StarBridge.NativeBridge;

// Synthetic HTTP fixtures only. No live account, room or service is contacted.
internal static class PartyRoomHostTransferTests
{
    private const string MemberToken = "0123456789abcdef0123456789abcdef";
    private const string OtherToken = "fedcba9876543210fedcba9876543210";

    private static byte[] Directory(bool? supported = true, bool host = true,
        bool joined = true, bool peer = true, bool peerHost = false, string memberToken = MemberToken)
    {
        var wire = JsonNode.Parse(PartyRoomReaderTests.Wire(joined ? "one" : null, PartyRoomReaderTests.Room("one")))!;
        if (supported is not null) wire["supportsHostTransfer"] = supported.Value;
        var room = wire["rooms"]![0]!;
        room["viewerIsHost"] = host;
        if (peer)
        {
            var member = room["members"]![0]!.DeepClone();
            member["isHost"] = peerHost;
            member["accountId"] = "synthetic-peer";
            member["removalToken"] = memberToken;
            room["members"]!.AsArray().Add(member);
        }
        return JsonSerializer.SerializeToUtf8Bytes(wire);
    }

    private static JsonElement Command(object? data = null) => JsonSerializer.SerializeToElement(new {
        schemaVersion = 1, operation = "transferHost", data = data ?? new { roomId = "one", memberToken = MemberToken }
    });

    internal static async Task Authority()
    {
        foreach (var supported in new bool?[] { null, false, true })
        {
            var directory = PartyRoomReader.Parse(Directory(supported));
            Check(directory.SupportsHostTransfer == (supported == true), "Old service must default to unsupported.");
            var projection = BridgePayload.From(directory);
            Check(projection.GetProperty("supportsHostTransfer").GetBoolean() == (supported == true), "Capability survives safe bridge projection.");
            Check(!projection.GetRawText().Contains("synthetic-peer", StringComparison.Ordinal), "Transfer must not expose account identity.");
        }
        var malformedFlag = JsonNode.Parse(Directory())!;
        malformedFlag["supportsHostTransfer"] = "true";
        Check(!PartyRoomReader.Parse(JsonSerializer.SerializeToUtf8Bytes(malformedFlag)).SupportsHostTransfer,
            "Only a boolean true advertises the operation.");
        foreach (var (wire, error) in new[] {
            (Directory(null), "unavailable"), (Directory(false), "unavailable"),
            (Directory(host: false), "notHost"), (Directory(joined: false), "notHost"),
            (Directory(peer: false), "memberGone"), (Directory(peerHost: true), "memberGone"),
            (Directory(memberToken: OtherToken), "memberGone")
        })
        {
            var calls = new List<string>();
            using var reader = new PartyRoomReader(new Uri("https://relay.example.test/"), new Handler(request => {
                calls.Add(request.Method.Method);
                return Ok(wire);
            }));
            var rejected = await reader.ExecuteAsync("synthetic-token", Command(), default);
            Check(rejected.Status == "rejected" && rejected.Error == error, "Fresh authority must reject invalid transfer target.");
            Check(calls.SequenceEqual(new[] { "GET" }), "Authority rejection must not POST.");
        }
        foreach (var status in new[] { HttpStatusCode.Unauthorized, HttpStatusCode.Forbidden, HttpStatusCode.ServiceUnavailable })
        {
            var calls = 0;
            using var reader = new PartyRoomReader(new Uri("https://relay.example.test/"), new Handler(request => {
                Check(request.Method == HttpMethod.Get, "Failed authority must not dispatch a write.");
                calls++;
                return new(status);
            }));
            try { await reader.ExecuteAsync("synthetic-token", Command(), default); throw new Exception("Failed authority accepted."); }
            catch (AccountBridgeHostException) { Check(calls == 1, "Preflight is not retried."); }
        }
        foreach (var data in new object[] {
            new { roomId = "one", memberToken = "bad" },
            new { roomId = "one", memberToken = MemberToken, accountId = "spoofed" },
            new { roomId = "one", memberToken = MemberToken, removalToken = MemberToken },
            new { roomId = "one" }
        })
        {
            var calls = 0;
            using var reader = new PartyRoomReader(new Uri("https://relay.example.test/"), new Handler(_ => { calls++; return Ok(Directory()); }));
            try { await reader.ExecuteAsync("synthetic-token", Command(data), default); throw new Exception("Invalid transfer input accepted."); }
            catch (AccountBridgeHostException error) { Check(error.Code == "party_rooms.data_invalid" && calls == 0, "Validate all fields before HTTP."); }
        }
    }

    internal static async Task Confirmation()
    {
        var methods = new List<string>();
        using var reader = new PartyRoomReader(new Uri("https://relay.example.test/"), new Handler(request => {
            methods.Add(request.Method.Method);
            if (request.Method == HttpMethod.Get) return Ok(Directory(host: methods.Count == 1));
            Check(request.RequestUri!.AbsolutePath == "/api/party-rooms/host/transfer", "Transfer uses fixed endpoint.");
            using var body = JsonDocument.Parse(request.Content!.ReadAsStringAsync().GetAwaiter().GetResult());
            Check(body.RootElement.EnumerateObject().Select(p => p.Name).Order().SequenceEqual(new[] { "memberToken", "roomId" }),
                "Only room and opaque membership reference are submitted.");
            Check(body.RootElement.GetProperty("memberToken").GetString() == MemberToken, "Reuse existing membership capability.");
            return Ok("{\"status\":\"hostTransferred\"}");
        }));
        var result = await reader.ExecuteAsync("synthetic-token", Command(), default);
        Check(result.Status == "hostTransferred" && result.Error is null && result.Directory?.Rooms.Single().ViewerIsHost == false,
            "Success returns authoritative refreshed host privileges, not command room data.");
        Check(methods.SequenceEqual(new[] { "GET", "POST", "GET" }), "Exactly one preflight, one write and one readback.");

        var reads = 0;
        var posts = 0;
        using var failedRead = new PartyRoomReader(new Uri("https://relay.example.test/"), new Handler(request => {
            if (request.Method == HttpMethod.Post) { posts++; return Ok("{\"status\":\"hostTransferred\"}"); }
            return ++reads == 1 ? Ok(Directory()) : new(HttpStatusCode.ServiceUnavailable);
        }));
        result = await failedRead.ExecuteAsync("synthetic-token", Command(), default);
        Check(result.Status == "hostTransferred" && result.Error == "refreshRequired" && result.Directory is null,
            "Accepted transfer is not reported rejected when readback fails.");
        Check(posts == 1 && reads == 3, "Only the readback may recover once; never replay transfer.");
    }

    internal static async Task Unknown()
    {
        foreach (var failure in new[] { "transport", "canceled", "wrongStatus", "invalidJson", "serverError", "rejected" })
        {
            var reads = 0;
            var posts = 0;
            using var reader = new PartyRoomReader(new Uri("https://relay.example.test/"), new Handler(request => {
                if (request.Method == HttpMethod.Get) { reads++; return Ok(Directory()); }
                posts++;
                return failure switch {
                    "transport" => throw new HttpRequestException("Synthetic dropped reply"),
                    "canceled" => throw new OperationCanceledException(),
                    "wrongStatus" => Ok("{\"status\":\"updated\"}"),
                    "invalidJson" => Ok("{"),
                    "serverError" => new(HttpStatusCode.ServiceUnavailable),
                    _ => new(HttpStatusCode.Conflict) { Content = new StringContent("{\"error\":\"Synthetic rejection\"}") }
                };
            }));
            try
            {
                var result = await reader.ExecuteAsync("synthetic-token", Command(), default);
                Check(failure == "rejected" && result.Status == "rejected" && result.Error == "rejected", "Only explicit rejection proves failure.");
            }
            catch (AccountBridgeHostException error)
            {
                Check(failure != "rejected" && error.Code == "party_rooms.outcome_unknown", "Unconfirmed write must remain unknown.");
            }
            Check(posts == 1 && reads == 1, "Unknown or rejected operation must not replay or fabricate readback.");
        }
    }

    private static HttpResponseMessage Ok(byte[] data) => new(HttpStatusCode.OK) { Content = new ByteArrayContent(data) };
    private static HttpResponseMessage Ok(string data) => new(HttpStatusCode.OK) { Content = new StringContent(data) };
    private static void Check(bool condition, string reason) { if (!condition) throw new Exception(reason); }
    private sealed class Handler(Func<HttpRequestMessage, HttpResponseMessage> send) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) => Task.FromResult(send(request));
    }
}
