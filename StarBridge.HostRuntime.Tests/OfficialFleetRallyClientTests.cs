using System.Net;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;

/// Main-fleet rally bridge: strict request shapes, the invisible viewer is
/// read with online=0, and only the counts-only projection reaches Flutter.
internal static class OfficialFleetRallyClientTests
{
    private const string Source = "officialFleet:7";
    private static readonly string RallyId = new('a', 32);
    private static readonly DateTimeOffset Started = new(2026, 10, 21, 20, 0, 0, TimeSpan.Zero);

    internal static async Task RunAsync()
    {
        var handler = new Relay();
        using var client = new CommunityClient(new Uri("https://rally.invalid/"), handler, TimeProvider.System);
        Task<JsonElement> Call(object body) => Run(client, body);

        handler.Body = State(null, Rally());
        foreach (var isSelf in new[] { true, false })
        {
            var wire = JsonNode.Parse(State(null, Rally()))!;
            wire["rally"]!["starter"] = new JsonObject { ["displayName"] = "Leader A", ["isSelf"] = isSelf };
            handler.Body = wire.ToJsonString();
            var projected = await Call(new { schemaVersion = 1, action = "read", sourceRef = Source, online = false, include = new[] { "starter" } });
            var starter = projected.GetProperty("rally").GetProperty("starter");
            Check(starter.GetProperty("displayName").GetString() == "Leader A" && starter.GetProperty("isSelf").GetBoolean() == isSelf && handler.StarterHeader,
                "Host opts in and projects starter display fields");
        }
        handler.Body = State(null, Rally());
        var read = await Call(new { schemaVersion = 1, action = "read", sourceRef = Source, online = true });
        Check(handler.Method == "GET" && handler.Path == "/api/official-fleets/rally?sourceRef=officialFleet%3A7&online=1" &&
            handler.Bearer == "token", "Read asks the relay with the bearer and online=1");
        var rally = read.GetProperty("rally");
        Check(rally.GetProperty("coming").GetInt32() == 9 && rally.GetProperty("pending").GetInt32() == 25 &&
            rally.GetProperty("state").GetString() == "active" && rally.GetProperty("response").ValueKind == JsonValueKind.Null &&
            read.GetProperty("onlineCount").GetInt32() == 37, "Counts are projected as-is");
        await Call(new { schemaVersion = 1, action = "read", sourceRef = Source, online = false });
        Check(handler.Path!.EndsWith("&online=0", StringComparison.Ordinal), "An invisible viewer reads with online=0");

        handler.Body = State(null, null);
        Check((await Call(new { schemaVersion = 1, action = "read", sourceRef = Source, online = true })).GetProperty("rally").ValueKind ==
            JsonValueKind.Null, "No rally reads as null");

        handler.Body = JsonSerializer.Serialize(new { schemaVersion = 1, sourceRef = Source, canStart = true, onlineCount = 37,
            remainingThisHour = 2, durations = new[] { 15, 30, 60 }, maximumText = 40 });
        var eligibility = await Call(new { schemaVersion = 1, action = "eligibility", sourceRef = Source });
        Check(handler.Path == "/api/official-fleets/rally/eligibility?sourceRef=officialFleet%3A7" &&
            eligibility.GetProperty("canStart").GetBoolean() && eligibility.GetProperty("remainingThisHour").GetInt32() == 2,
            "Eligibility is read separately");

        handler.Body = State("started", Rally());
        var operation = Guid.NewGuid().ToString("N");
        await Call(new { schemaVersion = 1, action = "start", sourceRef = Source, operationId = operation, text = " 新巴贝奇集合 ", minutes = 30 });
        var sent = JsonNode.Parse(handler.Request!)!.AsObject();
        Check(handler.Method == "POST" && handler.Path == "/api/official-fleets/rally/start" &&
            sent["text"]!.GetValue<string>() == "新巴贝奇集合" && sent["operationId"]!.GetValue<string>() == operation &&
            sent["minutes"]!.GetValue<int>() == 30 && sent.Count == 5, "Start posts a trimmed, minimal command");

        handler.Body = State("accepted", Rally(response: "coming"));
        await Call(new { schemaVersion = 1, action = "respond", sourceRef = Source, rallyId = RallyId, response = "coming" });
        Check(handler.Path == "/api/official-fleets/rally/respond" && JsonNode.Parse(handler.Request!)!["response"]!.GetValue<string>() == "coming",
            "Respond posts the answer");
        handler.Body = State("ended", Rally(state: "ended"));
        await Call(new { schemaVersion = 1, action = "end", sourceRef = Source, rallyId = RallyId });
        Check(handler.Path == "/api/official-fleets/rally/end", "End posts the rally id");

        handler.Calls = 0;
        foreach (var bad in new object[] {
            new { schemaVersion = 1, action = "read", sourceRef = Source },
            new { schemaVersion = 1, action = "read", sourceRef = "officialFleet:x", online = true },
            new { schemaVersion = 2, action = "read", sourceRef = Source, online = true },
            new { schemaVersion = 1, action = "delete", sourceRef = Source },
            new { schemaVersion = 1, action = "start", sourceRef = Source, operationId = operation, text = "", minutes = 30 },
            new { schemaVersion = 1, action = "start", sourceRef = Source, operationId = operation, text = new string('长', 41), minutes = 30 },
            new { schemaVersion = 1, action = "start", sourceRef = Source, operationId = operation, text = "集合", minutes = 20 },
            new { schemaVersion = 1, action = "start", sourceRef = Source, operationId = "op", text = "集合", minutes = 30 },
            new { schemaVersion = 1, action = "respond", sourceRef = Source, rallyId = RallyId, response = "maybe" },
            new { schemaVersion = 1, action = "end", sourceRef = Source, rallyId = RallyId, extra = 1 } })
            await Fails(() => Call(bad), "communities.dataInvalid");
        Check(handler.Calls == 0, "Malformed requests never reach the relay");

        foreach (var (status, code) in new[] { (HttpStatusCode.Unauthorized, "communities.identityUnavailable"),
            (HttpStatusCode.Forbidden, "communities.notAllowed"), (HttpStatusCode.NotFound, "communities.upgradeRequired"),
            (HttpStatusCode.Conflict, "officialFleet.rallyConflict"), (HttpStatusCode.TooManyRequests, "officialFleet.rallyRateLimited"),
            (HttpStatusCode.ServiceUnavailable, "communities.unavailable") })
        {
            handler.Status = status;
            await Fails(() => Call(new { schemaVersion = 1, action = "start", sourceRef = Source, operationId = operation, text = "集合", minutes = 30 }), code);
        }
        handler.Status = HttpStatusCode.OK;

        foreach (var (name, body) in new[] {
            ("other source", State(null, Rally()).Replace(Source, "officialFleet:8")),
            ("member names", JsonNode.Parse(State(null, Rally()))!.AsObject().Also(o => o["rally"]!["responders"] = "Ann")),
            ("bad state", State(null, Rally(state: "open"))),
            ("bad answer", State(null, Rally(response: "maybe"))),
            ("bad expiry", JsonNode.Parse(State(null, Rally()))!.AsObject().Also(o => o["rally"]!["expiresAt"] = Started.AddMinutes(31))),
            ("negative", State(null, Rally()).Replace("\"coming\":9", "\"coming\":-1")),
            ("read outcome", State("started", Rally())),
            ("missing rally", State("started", null)) })
        {
            handler.Body = body;
            var action = name is "read outcome" ? "read" : name == "missing rally" ? "start" : "read";
            object request = action == "read" ? new { schemaVersion = 1, action, sourceRef = Source, online = true }
                : new { schemaVersion = 1, action, sourceRef = Source, operationId = operation, text = "集合", minutes = 30 };
            await Fails(() => Call(request), "communities.dataInvalid");
        }
        Console.WriteLine("PASS official fleet rally bridge: strict shapes, online flag, counts-only projection, stable errors");
    }

    private static string Also(this JsonObject value, Action<JsonObject> change) { change(value); return value.ToJsonString(); }

    private static async Task<JsonElement> Run(CommunityClient client, object body) =>
        JsonSerializer.SerializeToElement(await client.OfficialRallyAsync("token", JsonSerializer.SerializeToElement(body), () => { }, default));

    private static object Rally(string state = "active", string? response = null) => new
    {
        rallyId = RallyId, text = "新巴贝奇集合，开打赏船", minutes = 30, startedAt = Started, expiresAt = Started.AddMinutes(30),
        state, coming = 9, cannot = 3, pending = 25, response
    };

    private static string State(string? state, object? rally) =>
        JsonSerializer.Serialize(new { schemaVersion = 1, sourceRef = Source, state, onlineCount = 37, rally });

    private static async Task Fails(Func<Task> action, string code)
    {
        try { await action(); }
        catch (AccountBridgeHostException error) when (error.Code == code) { return; }
        throw new InvalidOperationException("Expected " + code);
    }

    private sealed class Relay : HttpMessageHandler
    {
        internal string Body = "{}";
        internal HttpStatusCode Status = HttpStatusCode.OK;
        internal string? Method, Path, Bearer, Request;
        internal int Calls;
        internal bool StarterHeader;

        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Calls++;
            StarterHeader = request.Headers.TryGetValues("X-StarBridge-Rally-Starter", out var values) && values.Single() == "1";
            Method = request.Method.Method; Path = request.RequestUri!.PathAndQuery; Bearer = request.Headers.Authorization?.Parameter;
            Request = request.Content is null ? null : await request.Content.ReadAsStringAsync(token);
            return new HttpResponseMessage(Status) { Content = new StringContent(Body, Encoding.UTF8, "application/json") };
        }
    }

    private static void Check(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }
}
