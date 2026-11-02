using System.Net;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.PartyRooms;
using StarBridge.NativeBridge;

internal static class PartyRoomKeepaliveTests
{
    internal static async Task Transport()
    {
        const string membershipToken = "0123456789abcdef0123456789abcdef";
        var wire = JsonNode.Parse(PartyRoomReaderTests.Wire("one", PartyRoomReaderTests.Room("one")))!;
        wire["supportsMembershipKeepalive"] = true;
        wire["viewerMembershipToken"] = membershipToken;
        RoomDirectoryView Parse() => PartyRoomReader.Parse(Encoding.UTF8.GetBytes(wire.ToJsonString()));
        var directory = Parse();
        Check(directory.ViewerMembershipToken == membershipToken, "host retains exact membership token");
        Check(!BridgePayload.From(directory).GetRawText().Contains(membershipToken, StringComparison.Ordinal), "membership token never crosses bridge");
        var calls = 0;
        var status = HttpStatusCode.NoContent;
        using var reader = new PartyRoomReader(new Uri("https://relay.example.test"), new Handler(async request =>
        {
            calls++;
            Check(request.RequestUri!.AbsolutePath == "/api/party-rooms/keepalive" && request.Method == HttpMethod.Post,
                "explicit endpoint, not GET side effects");
            Check(request.Headers.Authorization?.Parameter == "synthetic-bearer", "current authenticated transport");
            using var body = JsonDocument.Parse(await request.Content!.ReadAsStringAsync());
            Check(body.RootElement.EnumerateObject().Count() == 2 &&
                body.RootElement.GetProperty("roomId").GetString() == "one" &&
                body.RootElement.GetProperty("membershipToken").GetString() == membershipToken, "no telemetry or supplied identity");
            return new(status);
        }));
        Check(await reader.KeepaliveAsync("synthetic-bearer", directory, default), "204 confirms renewal");
        status = HttpStatusCode.Conflict;
        Check(!await reader.KeepaliveAsync("synthetic-bearer", directory, default), "lost membership is not renewed");
        foreach (var (response, code) in new[] { (HttpStatusCode.Unauthorized, "party_rooms.identity_unavailable"),
            (HttpStatusCode.Forbidden, "party_rooms.forbidden"), (HttpStatusCode.ServiceUnavailable, "party_rooms.keepalive_unavailable") })
        {
            status = response;
            try { await reader.KeepaliveAsync("synthetic-bearer", directory, default); throw new Exception("Expected keepalive rejection"); }
            catch (AccountBridgeHostException error) { Check(error.Code == code, "typed failure; no auth fallback/replay"); }
        }
        var before = calls;
        Check(!await reader.KeepaliveAsync("synthetic-bearer", directory with { SupportsMembershipKeepalive = false }, default), "old servers not probed");
        Check(!await reader.KeepaliveAsync("synthetic-bearer", directory with { CurrentRoomId = null }, default), "no membership no write");
        Check(calls == before, "unsupported and departed states cause zero HTTP writes");
        wire["viewerMembershipToken"] = "invalid";
        try { Parse(); throw new Exception("Invalid token accepted"); }
        catch (AccountBridgeHostException) { }
        Console.WriteLine("PASS room keepalive transport: private token, capability, exact payload, membership and typed failures");
    }

    private sealed class Handler(Func<HttpRequestMessage, Task<HttpResponseMessage>> send) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) => send(request);
    }
    private static void Check(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }
}
