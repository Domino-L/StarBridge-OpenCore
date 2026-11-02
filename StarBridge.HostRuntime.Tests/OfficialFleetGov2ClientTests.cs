using System.Net;
using System.Net.Http.Json;
using System.Reflection;
using System.Runtime.Loader;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.Core.Organizations;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;

internal static class OfficialFleetGov2ClientTests
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    internal static async Task RunAsync()
    {
        await Templates();
        await WaitCompatibility();
        await WaitOverallDeadline();
    }
    private static JsonElement Body(bool expanded = false) => JsonSerializer.SerializeToElement(expanded
        ? (object)new { schemaVersion = 1, sourceRef = "officialFleet:7", include = new[] { "policyV2" } }
        : new { schemaVersion = 1, sourceRef = "officialFleet:7" });

    private static async Task Templates()
    {
        using var handler = new TemplatesHandler();
        using var client = new CommunityClient(new("https://synthetic.example.test/"), handler);
        var actual = (JsonElement)await client.ReadOfficialRoleTemplatesAsync("synthetic", Body(), "scope", () => { }, default);
        Check(actual.GetProperty("creationCapabilities").GetArrayLength() == 3 &&
            !actual.GetProperty("roles")[0].TryGetProperty("roleKey", out _), "default template projection retains three capabilities and legacy row fields");
        // Run the real r17 binary in its own dependency context, using only this fake handler.
        // The optional path is supplied by the local verification runner; CI may use the frozen fixture below.
        var path = Environment.GetEnvironmentVariable("STARBRIDGE_GOV2_R17_HOST_DLL");
        var expected = JsonNode.Parse(R17Fixture)!;
        if (!string.IsNullOrEmpty(path))
        {
            var loader = new R17LoadContext(Path.GetDirectoryName(path)!);
            try
            {
                var type = loader.LoadFromAssemblyPath(Path.GetFullPath(path)).GetType("StarBridge.HostRuntime.Communities.CommunityClient", true)!;
                var ctor = type.GetConstructors(BindingFlags.Instance | BindingFlags.NonPublic).Single();
                var arguments = ctor.GetParameters().Select(p => p.HasDefaultValue ? p.DefaultValue : null).ToArray();
                arguments[0] = new Uri("https://synthetic.example.test/"); arguments[1] = new TemplatesHandler();
                using var old = (IDisposable)ctor.Invoke(arguments);
                var task = (Task<object>)type.GetMethod("ReadOfficialRoleTemplatesAsync", BindingFlags.Instance | BindingFlags.NonPublic)!
                    .Invoke(old, ["synthetic", Body(), "scope", (Action)(() => { }), CancellationToken.None])!;
                expected = Normalize((JsonElement)await task);
                Check(JsonNode.DeepEquals(expected, JsonNode.Parse(R17Fixture)), "real r17 serialized result matches the frozen normalized fixture");
            }
            finally { loader.Unload(); }
        }
        Check(JsonNode.DeepEquals(Normalize(actual), expected), "current serialized default template result equals r17 (only opaque references normalized)");
        var expanded = (JsonElement)await client.ReadOfficialRoleTemplatesAsync("synthetic", Body(true), "scope", () => { }, default);
        Check(expanded.GetProperty("creationCapabilities").GetArrayLength() == 4 &&
            expanded.GetProperty("roles")[0].GetProperty("permissionVersion").GetInt32() == 1 &&
            expanded.GetProperty("roles")[0].GetProperty("roleKey").GetString() == "legacy",
            "include policyV2 returns the fourth creation capability and bound policy fields");
        // Real Bridge encoding must preserve the same JSON shape, including null metadata and nextPageRef.
        var request = StarBridge.NativeBridge.BridgeEnvelope.Request("officialFleet.readRoleTemplates", "shape", 1, Body());
        var response = StarBridge.NativeBridge.BridgeEnvelope.Response(request, actual);
        var codec = typeof(StarBridge.NativeBridge.BridgeEnvelope).Assembly.GetType("StarBridge.NativeBridge.BridgeWireCodec")!;
        var wire = (byte[])codec.GetMethod("Encode", BindingFlags.NonPublic | BindingFlags.Static)!.Invoke(null, [response])!;
        using var frame = JsonDocument.Parse(wire);
        Check(JsonNode.DeepEquals(Normalize(frame.RootElement.GetProperty("payload")), expected), "actual Bridge frame retains the r17 default template shape");
        Check(AccountBridgeRuntime.AdvertisedCapabilities.Contains("officialFleet.wait"), "official wait remains advertised");
    }
    private static JsonNode Normalize(JsonElement value)
    {
        var node = JsonNode.Parse(value.GetRawText())!;
        node["editRef"] = "opaque";
        foreach (var row in node["roles"]!.AsArray()) row!["roleRef"] = "opaque";
        return node;
    }
    private sealed class R17LoadContext(string directory) : AssemblyLoadContext("GOV2-r17", isCollectible: true)
    {
        protected override Assembly? Load(AssemblyName name)
        {
            // Resolve r17 domain dependencies before falling back to the current
            // process; mixing its reader with the new four-capability Core is invalid.
            var path = Path.Combine(directory, name.Name + ".dll");
            return name.Name?.StartsWith("StarBridge.", StringComparison.Ordinal) == true && File.Exists(path)
                ? LoadFromAssemblyPath(path) : null;
        }
    }
    private const string R17Fixture = """
        {"schemaVersion":1,"state":"available","sourceRef":"officialFleet:7","editRef":"opaque","revision":1,"offset":0,"totalCount":1,"nextPageRef":null,
        "access":{"read":{"state":"allowed","reason":"currentMember"},"create":{"state":"allowed","reason":"explicitRootDelegation"},"updateMetadata":{"state":"allowed","reason":"explicitRootDelegation"}},
        "creationCapabilities":[{"capability":"announcements.manage","state":"allowed","reason":"explicitRootDelegation"},{"capability":"audit.view","state":"allowed","reason":"explicitRootDelegation"},{"capability":"organization.roles.manage","state":"allowed","reason":"explicitRootDelegation"}],
        "roles":[{"roleRef":"opaque","enabled":true,"permissions":[{"capability":"audit.view","canUse":true,"canDelegate":false}],"metadata":null}]}
        """;
    private sealed class TemplatesHandler : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            var expanded = request.Headers.Contains("X-StarBridge-Governance-Capabilities");
            var capabilities = expanded ? OrganizationCapabilityCatalog.Implemented : OrganizationCapabilityCatalog.Legacy;
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(new
            {
                schemaVersion = 1, state = "available", sourceRef = "officialFleet:7", scopeKey = new string('a', 64), authorityBinding = new string('b', 64),
                policyRevision = 1, offset = 0, totalCount = 1, nextOffset = (int?)null,
                access = new { read = new { state = "allowed", reason = "currentMember" },
                    create = new { state = "allowed", reason = "explicitRootDelegation" }, updateMetadata = new { state = "allowed", reason = "explicitRootDelegation" } },
                creationCapabilities = capabilities.Select(capability => new { capability, state = "allowed", reason = "explicitRootDelegation" }),
                roles = new[] { new { roleKey = "legacy", permissionVersion = 1, metadataRevision = 1, enabled = true,
                    permissions = new[] { new { capability = "audit.view", canUse = true, canDelegate = false } }, metadata = (object?)null } }
            }, options: Json) });
        }
    }
    private static async Task WaitCompatibility()
    {
        var body = JsonSerializer.SerializeToElement(new { schemaVersion = 1, sourceRef = "officialFleet:7", instance = "", version = -1 });
        using var handler = new WaitHandler();
        using var client = new CommunityClient(new("https://synthetic.example.test/"), handler);
        var session = new CommunityClient.OfficialActivityWaitSession();
        await client.WaitOfficialActivityAsync("synthetic", body, () => { }, default, session);
        Check(handler.Seconds.SequenceEqual(new[] { 25 }), "new session sends 25 seconds");
        handler.Seconds.Clear(); handler.Status = HttpStatusCode.BadRequest;
        await client.WaitOfficialActivityAsync("synthetic", body, () => { }, default, session);
        Check(handler.Seconds.SequenceEqual(new[] { 25, 8 }), "400 on 25 retries exactly once with 8");
        handler.Seconds.Clear();
        await client.WaitOfficialActivityAsync("synthetic", body, () => { }, default, session);
        Check(handler.Seconds.SequenceEqual(new[] { 8 }), "old relay duration is remembered for the session");
        handler.Seconds.Clear(); handler.Status = HttpStatusCode.OK;
        await client.WaitOfficialActivityAsync("synthetic", body, () => { }, default, new());
        Check(handler.Seconds.SequenceEqual(new[] { 25 }), "new session probes 25 again");
        foreach (var status in new[] { HttpStatusCode.Forbidden, HttpStatusCode.Unauthorized, HttpStatusCode.ServiceUnavailable })
        {
            handler.Status = status; handler.Seconds.Clear();
            try { await client.WaitOfficialActivityAsync("synthetic", body, () => { }, default, new()); throw new Exception("expected denial"); }
            catch (AccountBridgeHostException) { }
            Check(handler.Seconds.SequenceEqual(new[] { 25 }), "no legacy retry on " + status);
        }
        handler.Status = HttpStatusCode.BadRequest; handler.RejectEight = true; handler.Seconds.Clear();
        try { await client.WaitOfficialActivityAsync("synthetic", body, () => { }, default, new()); throw new Exception("expected rejection"); }
        catch (AccountBridgeHostException) { }
        Check(handler.Seconds.SequenceEqual(new[] { 25, 8 }), "second 400 terminates without retry loop");
    }
    private static async Task WaitOverallDeadline()
    {
        var body = JsonSerializer.SerializeToElement(new { schemaVersion = 1, sourceRef = "officialFleet:7", instance = "", version = -1 });
        using var handler = new LateRejectionHandler();
        using var client = new CommunityClient(new("https://synthetic.example.test/"), handler);
        var clock = System.Diagnostics.Stopwatch.StartNew();
        try
        {
            await client.WaitOfficialActivityAsync("synthetic", body, () => { }, default, new(), TimeSpan.FromSeconds(1));
            throw new Exception("expected the wait to run out");
        }
        catch (OperationCanceledException) { }
        Check(handler.Requests == 2 && clock.Elapsed < TimeSpan.FromMilliseconds(1500),
            "a late 400 does not restart the whole wait's deadline");
        using var spent = new LateRejectionHandler();
        using var spentClient = new CommunityClient(new("https://synthetic.example.test/"), spent);
        try
        {
            await spentClient.WaitOfficialActivityAsync("synthetic", body, () => { }, default, new(), TimeSpan.Zero);
            throw new Exception("expected a spent wait to be refused");
        }
        catch (AccountBridgeHostException error) when (error.Code == "communities.unavailable") { }
        Check(spent.Requests == 0, "a wait with no time left sends nothing");
    }
    private sealed class LateRejectionHandler : HttpMessageHandler
    {
        internal int Requests;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            if (Interlocked.Increment(ref Requests) == 1)
            {
                await Task.Delay(700, token);
                return new(HttpStatusCode.BadRequest);
            }
            await Task.Delay(Timeout.Infinite, token);
            throw new InvalidOperationException();
        }
    }
    private sealed class WaitHandler : HttpMessageHandler
    {
        internal readonly List<int> Seconds = [];
        internal HttpStatusCode Status = HttpStatusCode.OK;
        internal bool RejectEight;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            var seconds = int.Parse(request.RequestUri!.Query.Split("waitSeconds=")[1]); Seconds.Add(seconds);
            var status = seconds == 8 && !RejectEight ? HttpStatusCode.OK : Status;
            return Task.FromResult(new HttpResponseMessage(status) { Content = JsonContent.Create(new
                { sourceRef = "officialFleet:7", instanceId = new string('a', 32), version = 1, serverTime = DateTimeOffset.UtcNow }) });
        }
    }
    private static void Check(bool condition, string message)
    { if (!condition) throw new InvalidOperationException(message); Console.WriteLine("PASS GOV2 Host: " + message); }
}
