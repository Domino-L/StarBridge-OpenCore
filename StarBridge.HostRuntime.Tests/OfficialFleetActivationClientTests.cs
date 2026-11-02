using System.Net;
using System.Reflection;
using System.Runtime.Versioning;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Communities;
using StarBridge.NativeBridge;

internal static class OfficialFleetActivationClientTests
{
    private const string Source = "officialFleet:7";
    private const string Activate = "officialFleet.governance.activate";
    private const string Revoke = "officialFleet.governance.revokeActivation";
    private static JsonElement Command => JsonSerializer.SerializeToElement(new
        { schemaVersion = 1, sourceRef = Source, operationId = "intent-1", expectedPolicyRevision = 2 });

    internal static async Task RunAsync()
    {
        await ContextAndMappings();
        if (OperatingSystem.IsWindows()) await RuntimeCases();
    }

    private static async Task ContextAndMappings()
    {
        using var relay = new Relay();
        using var client = new CommunityClient(new Uri("https://governance.invalid/"), relay);
        async Task<JsonElement> Context() => (JsonElement)await client.ReadOfficialGovernanceContextAsync("synthetic", JsonSerializer.SerializeToElement(new
            { schemaVersion = 1, sourceRef = Source, include = new[] { "role" } }), () => { }, default);
        foreach (var role in new string?[] { null, "leader", "admin", "editor", "member" })
        {
            relay.Body = ContextWire(role);
            var row = await Context();
            Check(relay.RoleHeader && (role is null ? !row.TryGetProperty("role", out _) : row.GetProperty("role").GetString() == role),
                "role header and optional role projection: " + (role ?? "old relay"));
        }
        var stale = JsonNode.Parse(ContextWire("member"))!;
        stale["membershipUpdatedAt"] = "2026-10-20T00:00:00Z";
        stale["capabilities"]![0]!["state"] = "unavailable";
        stale["capabilities"]![0]!["reason"] = "membershipEvidenceStale";
        relay.Body = stale.ToJsonString();
        var projected = await Context();
        Check(projected.GetProperty("membershipUpdatedAt").GetString() == "2026-10-20T00:00:00Z" &&
            projected.GetProperty("capabilities")[0].GetProperty("reason").GetString() == "membershipEvidenceStale", "context stale reason and timestamp");
        relay.Status = HttpStatusCode.ServiceUnavailable;
        relay.Body = "{\"schemaVersion\":1,\"state\":\"membershipEvidenceStale\",\"membershipUpdatedAt\":\"2026-10-20T00:00:00Z\"}";
        try { await Context(); throw new InvalidOperationException("Expected stale diagnostic"); }
        catch (AccountBridgeHostException error) when (error.Code == "membershipEvidenceStale")
        { Check(error.MembershipUpdatedAt == "2026-10-20T00:00:00Z", "stale HTTP error retains timestamp"); }

        var outcomes = new[] { (200, "accepted", "accepted"), (200, "duplicate", "duplicate"), (400, "invalid", "invalid"),
            (401, "identityUnavailable", "identityUnavailable"), (403, "notAllowed", "notAllowed"), (409, "conflict", "conflict"),
            (503, "unavailable", "unavailable"), (503, "storageLimitReached", "storageLimitReached"), (202, "operationOutcomeUnknown", "outcomeUnknown") };
        foreach (var activate in new[] { true, false })
        foreach (var (status, state, expected) in outcomes)
        {
            relay.Status = (HttpStatusCode)status;
            relay.Body = JsonSerializer.Serialize(new { schemaVersion = 1, state, operationId = "intent-1", policyRevision = 3, auditSequence = 8 });
            var row = (JsonElement)await client.WriteGovernanceActivationAsync("synthetic", Command, activate, () => { }, default);
            Check(row.GetProperty("state").GetString() == expected && row.GetProperty("policyRevision").GetInt64() == 3 &&
                row.GetProperty("operationId").GetString() == "intent-1" && relay.Request == Command.GetRawText() &&
                relay.Path == "/api/official-fleets/governance/activation/" + (activate ? "activate" : "revoke"),
                (activate ? "activate" : "revoke") + " HTTP/state mapping: " + state);
        }
        foreach (var (status, body, expected) in new[] {
            (401, "", "identityUnavailable"), (403, "{}", "notAllowed"), (409, "{}", "conflict"), (400, "{}", "invalid"),
            (503, "{}", "unavailable"), (404, "{}", "unavailable"), (500, "{}", "outcomeUnknown"),
            (200, "{}", "outcomeUnknown"), (200, "{\"schemaVersion\":1,\"state\":\"accepted\"}", "outcomeUnknown"),
            (200, "{\"schemaVersion\":1,\"state\":\"unavailable\"}", "outcomeUnknown"),
            (202, "{}", "outcomeUnknown"), (503, "{\"schemaVersion\":1,\"state\":\"storageLimitReached\"}", "storageLimitReached") })
        {
            relay.Status = (HttpStatusCode)status; relay.Body = body;
            var row = (JsonElement)await client.WriteGovernanceActivationAsync("synthetic", Command, true, () => { }, default);
            Check(row.GetProperty("state").GetString() == expected && !row.TryGetProperty("policyRevision", out _), "early or malformed response " + status + " => " + expected);
        }
        relay.Failure = new HttpRequestException("Synthetic loss");
        var before = relay.Calls;
        var lost = (JsonElement)await client.WriteGovernanceActivationAsync("synthetic", Command, true, () => { }, default);
        Check(lost.GetProperty("state").GetString() == "outcomeUnknown" && relay.Calls == before + 1, "lost response never auto-retries");
        relay.Failure = new OperationCanceledException("Synthetic timeout");
        var timeout = (JsonElement)await client.WriteGovernanceActivationAsync("synthetic", Command, false, () => { }, default);
        Check(timeout.GetProperty("state").GetString() == "outcomeUnknown", "post-send timeout preserves uncertain outcome");
        relay.Failure = null;
        before = relay.Calls;
        var invalid = new List<string> { "{}", "null", Command.GetRawText().Replace("\"schemaVersion\":1", "\"schemaVersion\":2"),
            Command.GetRawText().Replace("\"expectedPolicyRevision\":2", "\"expectedPolicyRevision\":-1"),
            Command.GetRawText().Replace("\"expectedPolicyRevision\":2", "\"expectedPolicyRevision\":2.5"),
            Command.GetRawText().Replace("\"expectedPolicyRevision\":2", "\"expectedPolicyRevision\":9223372036854775808"),
            Command.GetRawText().Replace("officialFleet:7", "officialFleet:0") };
        foreach (var operation in new[] { "", " padded", "trailing ", "a\nb", new string('x', 129) })
        { var row = JsonNode.Parse(Command.GetRawText())!; row["operationId"] = operation; invalid.Add(row.ToJsonString()); }
        invalid.Add(Command.GetRawText()[..^1] + ",\"subject\":\"injected\"}");
        invalid.Add(Command.GetRawText()[..^1] + ",\"schemaVersion\":1}");
        invalid.Add(Command.GetRawText()[..^1] + new string(' ', 2048) + "}");
        foreach (var raw in invalid)
        {
            using var doc = JsonDocument.Parse(raw);
            try { await client.WriteGovernanceActivationAsync("synthetic", doc.RootElement, true, () => { }, default); throw new InvalidOperationException("Invalid body sent"); }
            catch (AccountBridgeHostException error) when (error.Code == "communities.dataInvalid") { }
        }
        Check(relay.Calls == before, "invalid, duplicate, unknown, missing and oversized payload fields never reach relay");
    }

    [SupportedOSPlatform("windows")]
    private static async Task RuntimeCases()
    {
        using var relay = new Relay { Body = ContextWire(null) };
        using var native = new Native(relay);
        using var lifecycle = new HostBridgeDispatcher("synthetic-host", () => native.Host.Generation, ["host.lifecycle"],
            additionalCapabilities: () => native.Runtime.OfficialFleetRealtimeCapabilities);
        async Task<string[]> Capabilities()
        {
            var response = await lifecycle.DispatchAsync(BridgeEnvelope.Request("host.ready", Guid.NewGuid().ToString("N"), native.Host.Generation, new { }));
            return response.Response.Payload.GetProperty("hostCapabilities").EnumerateArray().Select(x => x.GetString()!).ToArray();
        }
        Check(!(await Capabilities()).Contains(Activate) && !AccountBridgeRuntime.AdvertisedCapabilities.Contains(Activate) &&
            !AccountBridgeRuntime.AdvertisedCapabilities.Contains(Revoke), "no static activation or revocation claim before relay observation");
        foreach (var name in new[] { Activate, Revoke })
        {
            var before = relay.Calls;
            var unobserved = await native.Call(name);
            Check(unobserved.Response.Error?.Code == "communities.upgradeRequired" && relay.Calls == before,
                "dispatcher accepts but blocks unobserved " + name);
        }
        await native.Context();
        Check(!(await Capabilities()).Contains(Activate), "old relay cannot advertise activation");
        var blocked = await native.Call(Activate);
        Check(blocked.Response.Error?.Code == "communities.upgradeRequired", "old relay activation is blocked before POST");
        relay.Body = ContextWire("leader");
        var legacyContext = await native.Context();
        Check(legacyContext.Response.Payload.EnumerateObject().Count() == 5 && !legacyContext.Response.Payload.TryGetProperty("role", out _),
            "runtime legacy context hides role without losing relay observation");
        Check((await Capabilities()).Contains(Activate) && (await Capabilities()).Contains(Revoke), "observed relay activates dynamic ready capabilities");
        foreach (var name in new[] { Activate, Revoke })
        {
            relay.Body = "{\"schemaVersion\":1,\"state\":\"accepted\",\"operationId\":\"intent-1\",\"policyRevision\":3,\"auditSequence\":8}";
            var response = await native.Call(name);
            Check(response.Response.Status == "ok" && response.Response.Payload.GetProperty("state").GetString() == "accepted", "actual dispatcher routes " + name);
        }
        relay.Body = ContextWire("member");
        var extendedContext = await native.Context(includeRole: true);
        Check(extendedContext.Response.Status == "ok" && extendedContext.Response.Payload.GetProperty("role").GetString() == "member",
            "actual dispatcher accepts include role");
        relay.Body = ContextWire(null);
        await native.Context();
        foreach (var name in new[] { Activate, Revoke })
        {
            var before = relay.Calls;
            Check((await native.Call(name)).Response.Error?.Code == "communities.upgradeRequired" && relay.Calls == before,
                "old relay observation retires support for " + name);
        }
        relay.Body = ContextWire("leader");
        await native.Context();
        relay.Status = HttpStatusCode.ServiceUnavailable;
        relay.Body = "{\"schemaVersion\":1,\"state\":\"membershipEvidenceStale\",\"membershipUpdatedAt\":\"2026-10-20T00:00:00Z\"}";
        var stale = await native.Context();
        Check(stale.Response.Error?.Code == "membershipEvidenceStale" && stale.Response.Payload.GetProperty("membershipUpdatedAt").GetString() == "2026-10-20T00:00:00Z",
            "actual bridge stale error carries the optional update timestamp");
        Check(!(await Capabilities()).Contains(Activate), "failed context retires relay support observation");

        foreach (var name in new[] { Activate, Revoke, "officialFleet.readGovernanceContext" })
        {
            using var held = new Relay { Body = ContextWire("leader") };
            using var owner = new Native(held);
            await owner.Context();
            var oldGeneration = owner.Host.Generation; var oldAccount = owner.Host.CurrentContext;
            held.Body = name.EndsWith("Context", StringComparison.Ordinal) ? ContextWire("leader") :
                "{\"schemaVersion\":1,\"state\":\"accepted\",\"operationId\":\"intent-1\",\"policyRevision\":3,\"auditSequence\":8}";
            held.Hold = true;
            var pending = name.EndsWith("Context", StringComparison.Ordinal) ? owner.Context() : owner.Call(name);
            await held.Arrived.Task.WaitAsync(TimeSpan.FromSeconds(5));
            owner.SwitchAccount();
            held.Release.TrySetResult();
            var late = await pending;
            Check(late.Response.Status != "ok" && late.Response.Payload.EnumerateObject().Count() == 0 &&
                owner.Runtime.OfficialFleetRealtimeCapabilities.Count == 0, "account switch fences late " + name + " and capabilities");
            var count = held.Calls;
            var old = await owner.Runtime.DispatchAsync(BridgeEnvelope.Request(Activate, Guid.NewGuid().ToString("N"), oldGeneration, Command, oldAccount));
            Check(old.Response.Status != "ok" && held.Calls == count, "stale generation cannot send another mutation");
        }
    }

    private static string ContextWire(string? role)
    {
        var row = new JsonObject { ["schemaVersion"] = 1, ["sourceRef"] = Source, ["scopeKey"] = new string('a', 64), ["policyRevision"] = 2,
            ["capabilities"] = new JsonArray(new[] { "announcements.manage", "audit.view", "organization.roles.manage" }.Select(c =>
                (JsonNode)new JsonObject { ["capability"] = c, ["state"] = "denied", ["reason"] = "notGranted" }).ToArray()),
            ["rootAuthority"] = new JsonObject { ["providerState"] = "observed", ["controls"] = new JsonArray(new[] { "activate", "recover", "delegate" }.Select(c =>
                (JsonNode)new JsonObject { ["action"] = c, ["state"] = "denied", ["reason"] = "notGranted" }).ToArray()) } };
        if (role is not null) row["role"] = role;
        return row.ToJsonString();
    }

    [SupportedOSPlatform("windows")]
    private sealed class Native : IDisposable
    {
        internal readonly ScmAccountBridgeHost Host;
        internal readonly AccountBridgeRuntime Runtime;
        private static ScmOAuthSession Session(string subject) => new("synthetic-scm", subject, "Synthetic", "synthetic-bearer", DateTimeOffset.UtcNow.AddHours(1), ["profile.read", "organizations.read"]);
        internal Native(HttpMessageHandler relay)
        {
            var origin = new Uri("https://governance.invalid/");
            var options = new ScmOAuthOptions("synthetic-scm", new("http://127.0.0.1:3000/"), new("http://127.0.0.1:18080/"),
                origin, "starbridge-desktop", "starbridge-api", "profile.read organizations.read", "/oauth/callback");
            Host = new(new OAuthPkceClient(new ScmHttpClient(new RejectOAuth()), new NoVault(), options),
                new ScmProfileCacheStore(Path.Combine(Path.GetTempPath(), "cx-l03-profile-" + Guid.NewGuid().ToString("N"))),
                "fixture", () => null, initialSession: Session("synthetic-a"), initialGeneration: 1, communities: new CommunityClient(origin, relay));
            Runtime = new(Host);
        }
        internal Task<BridgeDispatchBatch> Call(string name) => Runtime.DispatchAsync(BridgeEnvelope.Request(name, Guid.NewGuid().ToString("N"), Host.Generation, Command, Host.CurrentContext)).AsTask();
        internal Task<BridgeDispatchBatch> Context(bool includeRole = false) => Runtime.DispatchAsync(BridgeEnvelope.Request("officialFleet.readGovernanceContext", Guid.NewGuid().ToString("N"), Host.Generation,
            includeRole ? (object)new { schemaVersion = 1, sourceRef = Source, include = new[] { "role" } } :
                new { schemaVersion = 1, sourceRef = Source }, Host.CurrentContext)).AsTask();
        internal void SwitchAccount() => typeof(ScmAccountBridgeHost).GetMethod("PublishSession", BindingFlags.NonPublic | BindingFlags.Instance)!
            .Invoke(Host, [Session("synthetic-b"), false, null, false, null, null, null, null]);
        public void Dispose() { Runtime.Dispose(); Host.Dispose(); }
    }

    private sealed class NoVault : ITokenVault
    {
        public void SaveRefreshToken(string a, string b) => throw new InvalidOperationException("No vault writes");
        public string? LoadRefreshToken(string a) => null;
        public string? LoadActiveAccountKey() => null;
        public void DeleteRefreshToken(string a) => throw new InvalidOperationException("No vault deletes");
    }
    private sealed class RejectOAuth : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => throw new InvalidOperationException("No OAuth IO");
    }
    private sealed class Relay : HttpMessageHandler
    {
        internal string Body = "{}";
        internal HttpStatusCode Status = HttpStatusCode.OK;
        internal string? Request, Path;
        internal int Calls;
        internal bool RoleHeader, Hold;
        internal Exception? Failure;
        internal readonly TaskCompletionSource Arrived = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource Release = new(TaskCreationOptions.RunContinuationsAsynchronously);
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Calls++;
            Request = request.Content is null ? null : await request.Content.ReadAsStringAsync(token);
            Path = request.RequestUri!.PathAndQuery;
            RoleHeader = request.Headers.TryGetValues("X-StarBridge-Governance-Role", out var values) && values.Single() == "1";
            if (Failure is not null) throw Failure;
            var response = new HttpResponseMessage(Status) { Content = new StringContent(Body, Encoding.UTF8, "application/json") };
            if (Hold) { Arrived.TrySetResult(); await Release.Task.WaitAsync(TimeSpan.FromSeconds(5)); }
            return response;
        }
    }
    private static void Check(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
        Console.WriteLine("PASS CX-L03 " + message);
    }
}
