using System.Net;
using System.Reflection;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.Core.Organizations;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Communities;
using StarBridge.HostRuntime.OfficialFleet;
using StarBridge.NativeBridge;

internal static class OfficialFleetGovernanceManagementClientTests
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    internal static async Task RunAsync()
    {
        using var handler = new Handler();
        using var client = new CommunityClient(new("https://synthetic.example.test/"), handler);
        using var stream = typeof(OfficialFleetGovernanceManagementClientTests).Assembly.GetManifestResourceStream("Governance.never.relay.json")!;
        using var reader = new StreamReader(stream); handler.Body = await reader.ReadToEndAsync();
        var context = (JsonElement)await client.ReadOfficialGovernanceContextAsync("synthetic", JsonSerializer.SerializeToElement(new
            { schemaVersion = 1, sourceRef = "officialFleet:7" }), () => { }, default);
        using var bridgeStream = typeof(OfficialFleetGovernanceManagementClientTests).Assembly.GetManifestResourceStream("Governance.never.bridge.json")!;
        using var expected = JsonDocument.Parse(bridgeStream);
        Check(JsonNode.DeepEquals(JsonNode.Parse(context.GetRawText()), JsonNode.Parse(expected.RootElement.GetRawText())), "Host reads exact shared relay fixture and emits the shared Flutter fixture");
        var expanded = JsonNode.Parse(handler.Body)!;
        expanded["capabilities"]!.AsArray().Add(new JsonObject { ["capability"] = "rally.manage", ["state"] = "denied", ["reason"] = "notGranted" });
        handler.Body = expanded.ToJsonString();
        context = (JsonElement)await client.ReadOfficialGovernanceContextAsync("synthetic", JsonSerializer.SerializeToElement(new
            { schemaVersion = 1, sourceRef = "officialFleet:7", include = new[] { "capabilitiesV2" } }), () => { }, default);
        Check(context.GetProperty("capabilities").GetArrayLength() == 4, "new Flutter opt-in receives strict expanded capabilities");

        var options = new ScmOAuthOptions("synthetic", new("http://127.0.0.1:3000/"), new("http://127.0.0.1:18080/"),
            new("http://127.0.0.1:18082/"), "starbridge-desktop", "starbridge-api", "profile.read organizations.read", "/oauth/callback");
        using var host = new ScmAccountBridgeHost(new OAuthPkceClient(new ScmHttpClient(new MemberIdentityHandler()), new NoVault(), options),
            new ScmProfileCacheStore(Path.Combine(Path.GetTempPath(), "cx-gov-profile-" + Guid.NewGuid().ToString("N"))), "synthetic", () => null,
            initialSession: new ScmOAuthSession("synthetic", "owner", "Pilot", "synthetic-access", DateTimeOffset.UtcNow.AddHours(1), ["profile.read", "organizations.read"]),
            initialGeneration: 1, communities: client);
        using var runtime = new AccountBridgeRuntime(host);
        object Common(string op) => new { schemaVersion = 1, sourceRef = "officialFleet:7", operationId = op, expectedPolicyRevision = 0 };
        object Add(object body, object extras)
        {
            var value = JsonSerializer.SerializeToNode(body, Json)!.AsObject();
            foreach (var p in JsonSerializer.SerializeToNode(extras, Json)!.AsObject()) value[p.Key] = p.Value?.DeepClone();
            return value;
        }
        var cases = new (string Name, object Body, object Reply)[]
        {
            ("readRankPolicy", new { schemaVersion = 1, sourceRef = "officialFleet:7" }, new { schemaVersion = 1, state = "available",
                sourceRef = "officialFleet:7", scopeKey = new string('0', 64), policyRevision = 0,
                write = new { state = "allowed", reason = "explicitRootDelegation" }, rows = OrganizationRankPermissions.Defaults }),
            ("writeRankPolicy", Add(Common("rank"), new { rows = OrganizationRankPermissions.Defaults }), Success("rank")),
            ("updateRolePermissions", Add(Common("permissions"), new { roleKey = "test", expectedPermissionVersion = 1, enabled = false, permissions = Array.Empty<object>() }), Success("permissions")),
            ("readMemberRoles", new { schemaVersion = 1, sourceRef = "officialFleet:7", targetSubject = "scm-v1:" + new string('0', 64) }, new { schemaVersion = 1,
                state = "available", sourceRef = "officialFleet:7", policyRevision = 0, targetSubject = "scm-v1:" + new string('0', 64),
                membershipEpoch = "epoch", rootActivationId = "activation", rootActivationVersion = 1, grants = Array.Empty<object>() }),
            ("assignRole", Add(Common("assign"), new { targetSubject = "scm-v1:" + new string('0', 64), expectedTargetMembershipEpoch = "epoch", roleKey = "test",
                expectedRolePermissionVersion = 1, parts = new[] { new { grantId = "grant", rootActivationId = "activation", expectedRootVersion = 1,
                    ceiling = new[] { new { capability = "audit.view", canUse = true, canDelegate = false } } } } }), Success("assign")),
            ("revokeRole", Add(Common("revoke"), new { grantId = "grant", expectedGrantVersion = 1 }), Success("revoke")),
            ("readGovernanceAudit", new { schemaVersion = 1, sourceRef = "officialFleet:7", offset = 0 }, new { schemaVersion = 1, state = "available", sourceRef = "officialFleet:7",
                policyRevision = 0, offset = 0, totalCount = 0, items = Array.Empty<object>() }),
            ("readGovernanceOutcome", new { schemaVersion = 1, scopeKey = new string('0', 64), operationId = "rank" }, new { schemaVersion = 1, state = "found",
                operationId = "rank", kind = "ranks.permissions", expectedRevision = 0, resultRevision = 1, auditSequence = 1, timelineRevision = (long?)null })
        };
        var enabled = (HashSet<string>)typeof(AccountBridgeRuntime).GetField("EnabledRequests", BindingFlags.Static | BindingFlags.NonPublic)!.GetValue(null)!;
        foreach (var item in cases)
        {
            var name = "officialFleet." + item.Name;
            handler.Body = JsonSerializer.Serialize(item.Reply, Json); handler.Status = HttpStatusCode.OK;
            var result = await runtime.DispatchAsync(BridgeEnvelope.Request(name, Guid.NewGuid().ToString("N"), host.Generation, item.Body, host.CurrentContext));
            Check(result.Response.Status == "ok", "actual Runtime/dispatcher/SCM Host/client accepts " + name + ": " + result.Response.Error?.Code);
            Check(enabled.Contains(name) && AccountBridgeRuntime.AdvertisedCapabilities.Contains(name), "enabled and advertised " + name);
            var codec = typeof(BridgeEnvelope).Assembly.GetType("StarBridge.NativeBridge.BridgeWireCodec")!;
            var encoded = (byte[])codec.GetMethod("Encode", BindingFlags.Static | BindingFlags.NonPublic)!.Invoke(null, [result.Response])!;
            using var frame = JsonDocument.Parse(encoded);
            if (item.Name == "readGovernanceAudit") Check(!frame.RootElement.GetProperty("payload").TryGetProperty("nextOffset", out _), "actual Bridge serialization omits terminal null key");
            var before = handler.Calls;
            var invalid = JsonSerializer.SerializeToNode(item.Body)!.AsObject(); invalid["forgedAuthority"] = "leader";
            var rejected = await runtime.DispatchAsync(BridgeEnvelope.Request(name, Guid.NewGuid().ToString("N"), host.Generation, invalid, host.CurrentContext));
            Check(rejected.Response.Status != "ok" && handler.Calls == before, "strict unknown fields rejected before HTTP for " + name);
        }
        Check(enabled.Contains("officialFleet.wait") && AccountBridgeRuntime.AdvertisedCapabilities.Contains("officialFleet.wait"), "officialFleet.wait is both enabled and advertised");
        typeof(ScmAccountBridgeHost).GetMethod("RememberFleetProfileTargets", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(host,
            [host.CurrentContext, host.Generation, "officialFleet:7", new Dictionary<long, OfficialFleetMemberIdentity>
                { [42] = new(42, "visible", "scm-v1:" + new string('0', 64), "Synthetic member") }]);
        var reference = (string)typeof(ScmAccountBridgeHost).GetMethod("OfficialFleetMemberReference", BindingFlags.Instance | BindingFlags.NonPublic)!
            .Invoke(host, [host.Generation, "officialFleet:7", 42L])!;
        handler.Body = JsonSerializer.Serialize(cases.Single(c => c.Name == "readMemberRoles").Reply, Json);
        var mapped = await runtime.DispatchAsync(BridgeEnvelope.Request("officialFleet.readMemberRoles", Guid.NewGuid().ToString("N"), host.Generation,
            new { schemaVersion = 1, sourceRef = "officialFleet:7", targetRef = reference }, host.CurrentContext));
        Check(mapped.Response.Status == "ok" && mapped.Response.Payload.GetProperty("targetRef").GetString() == reference &&
            !mapped.Response.Payload.TryGetProperty("targetSubject", out _), "existing opaque fleet member reference resolves afresh and returns no raw subject");
        var assignment = JsonSerializer.SerializeToNode(cases.Single(c => c.Name == "assignRole").Body, Json)!.AsObject();
        assignment.Remove("targetSubject"); assignment["targetRef"] = reference;
        handler.Body = JsonSerializer.Serialize(Success("assign"), Json);
        var assigned = await runtime.DispatchAsync(BridgeEnvelope.Request("officialFleet.assignRole", Guid.NewGuid().ToString("N"), host.Generation, assignment, host.CurrentContext));
        Check(assigned.Response.Status == "ok", "opaque member reference also reaches assignment with fresh registered identity mapping");
        var intent = JsonSerializer.SerializeToElement(Add(Common("rank"), new { rows = OrganizationRankPermissions.Defaults }));
        handler.Status = HttpStatusCode.Conflict;
        handler.Body = "{\"schemaVersion\":1,\"state\":\"conflict\",\"operationId\":\"rank\"}";
        var conflict = (JsonElement)await client.OfficialGovernanceManagementAsync("synthetic", intent, "writeRankPolicy", () => { }, default);
        Check(conflict.GetProperty("state").GetString() == "conflict" && !conflict.TryGetProperty("policyRevision", out _), "real failure shape omits null revisions");
        handler.Status = HttpStatusCode.OK; handler.Body = "{}";
        var unknown = (JsonElement)await client.OfficialGovernanceManagementAsync("synthetic", intent, "writeRankPolicy", () => { }, default);
        Check(unknown.GetProperty("state").GetString() == "operationOutcomeUnknown", "malformed success after send never becomes a safe rejection");
    }
    private static object Success(string op) => new { schemaVersion = 1, state = "accepted", operationId = op, policyRevision = 1, auditSequence = 1 };
    private sealed class Handler : HttpMessageHandler
    {
        internal string Body = "{}"; internal HttpStatusCode Status = HttpStatusCode.OK; internal int Calls;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        { Calls++; return Task.FromResult(new HttpResponseMessage(Status) { Content = new StringContent(Body, Encoding.UTF8, "application/json") }); }
    }
    private sealed class MemberIdentityHandler : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            if (request.RequestUri!.AbsolutePath != "/app-api/starbridge/v1/official-fleet/member-identities") throw new InvalidOperationException("No unexpected OAuth IO allowed");
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(JsonSerializer.Serialize(new
                { schemaVersion = 1, sourceRef = "officialFleet:7", members = new[] { new { memberId = 42, state = "visible",
                    businessSubjectId = "scm-v1:" + new string('0', 64), callsign = "Synthetic member" } } }), Encoding.UTF8, "application/json") });
        }
    }
    private sealed class NoVault : ITokenVault
    {
        public void SaveRefreshToken(string a, string b) => throw new InvalidOperationException("No credential IO");
        public string? LoadRefreshToken(string a) => throw new InvalidOperationException("No credential IO");
        public string? LoadActiveAccountKey() => throw new InvalidOperationException("No credential IO");
        public void DeleteRefreshToken(string a) => throw new InvalidOperationException("No credential IO");
    }
    private static void Check(bool condition, string message)
    { if (!condition) throw new InvalidOperationException(message); Console.WriteLine("PASS governance Host: " + message); }
}
