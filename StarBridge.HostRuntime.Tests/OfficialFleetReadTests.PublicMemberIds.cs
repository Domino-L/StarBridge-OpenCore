using System.Globalization;
using System.Net;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.OfficialFleet;
using StarBridge.NativeBridge;

internal static partial class OfficialFleetReadTests
{
    private const long PublicLargeId = 9007199254740993;
    private const string PublicIdSubject = "scm-v1:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb";

    private static async Task PublicMemberIdCompatibility()
    {
        // Consumer-domain fixtures use the exact number/string forms observed
        // from the production NumberSerializer. These are not a DTO HTTP export.
        foreach (var id in new[] { 1L, 9007199254740990L, 9007199254740991L, 9007199254740992L, PublicLargeId, long.MaxValue })
        foreach (var quoted in new[] { false, true })
        {
            var text = id.ToString(CultureInfo.InvariantCulture);
            using var value = JsonDocument.Parse(quoted ? JsonSerializer.Serialize(text) : text);
            Require(OfficialFleetPublicId.Read(value.RootElement) == id, "Public ID parsing preserves every int64 bit");
            var profile = JsonSerializer.SerializeToElement(new { id = value.RootElement, sid = "ASTER" });
            _ = OfficialFleetReadModel.Profile(profile, "officialFleet:" + text, "ASTER");
        }

        // The public RSI logo (also RSI's default logo) and banner are carried
        // as https URLs only; anything else is dropped, never rewritten.
        const string logo = "https://cdn.robertsspaceindustries.com/static/images/organization/defaults/logo/generic.jpg";
        const string banner = "https://cdn.robertsspaceindustries.com/static/images/organization/defaults/banner/generic.jpg";
        var images = OfficialFleetReadModel.Profile(JsonSerializer.SerializeToElement(
            new { id = 7, sid = "ASTER", image = logo, banner }), "officialFleet:7", "ASTER");
        Require(images.LogoUrl == logo && images.BannerUrl == banner, "Public profile carries the RSI logo and banner");
        var insecure = OfficialFleetReadModel.Profile(JsonSerializer.SerializeToElement(
            new { id = 7, sid = "ASTER", image = "http://example.test/logo.jpg" }), "officialFleet:7", "ASTER");
        Require(insecure.LogoUrl is null, "A non-https logo is dropped");
        var wire = JsonSerializer.SerializeToElement(images, BridgeProtocol.JsonOptions);
        Require(wire.GetProperty("logoUrl").GetString() == logo, "The bridge profile names the logo logoUrl");

        var malformed = new[] {
            "0", "-1", "1.0", "1e0", "9223372036854775808", "null", "true", "[]", "{}",
            "\"\"", "\"0\"", "\"-1\"", "\"+1\"", "\" 1\"", "\"1 \"", "\"01\"", "\"00\"",
            "\"1.0\"", "\"1e0\"", "\"9223372036854775808\"", "\"10000000000000000000\"",
            "\"١\"", "\"１\"", "\"1\\n\"", "\"1\\u0000\"", "\"" + new string('1', 100) + "\""
        };
        foreach (var raw in malformed)
        {
            using var value = JsonDocument.Parse(raw);
            RequirePublicIdInvalid(() => OfficialFleetPublicId.Read(value.RootElement));
            var profile = JsonSerializer.SerializeToElement(new { id = value.RootElement, sid = "ASTER" });
            RequirePublicIdInvalid(() => OfficialFleetReadModel.Profile(profile, "officialFleet:7", "ASTER"));
            await InvalidPublicMemberPage(raw, false);
            await InvalidPublicMemberPage(raw, true);
        }

        foreach (var runtime in new[] { false, true })
        {
            await InvalidPublicMemberPage("101,\"101\"", runtime);
            await InvalidPublicMemberPage("9007199254740993,\"9007199254740993\"", runtime);
        }
        await PublicProfileStringId();
        await PublicMemberEquivalentReferences();
        await RuntimePublicMemberExactLookup();
        Console.WriteLine("PASS public organization IDs retain exact positive int64 compatibility without widening G1");
    }

    private static void RequirePublicIdInvalid(Action action)
    {
        try { action(); }
        catch (AccountBridgeHostException error) when (error.Code == AccountBridgeStableErrors.OfficialFleetDataInvalid) { return; }
        throw new InvalidOperationException("Malformed public IDs must use the existing invalid-data error");
    }

    private static HttpResponseMessage PublicIdResponse(string body) => new(HttpStatusCode.OK) {
        Content = new StringContent(body, System.Text.Encoding.UTF8, "application/json")
    };

    private static HttpResponseMessage PublicIdPage(string rawIds)
    {
        // Split only the fixed test token list; a string token never contains a comma.
        var ids = rawIds.Split(',');
        var rows = string.Join(",", ids.Select(id => "{\"userId\":" + id + ",\"nickname\":\"SCM source\",\"organizationRank\":\"Member\"}"));
        return PublicIdResponse("{\"code\":0,\"data\":{\"total\":" + ids.Length.ToString(CultureInfo.InvariantCulture) + ",\"list\":[" + rows + "]}}");
    }

    private static async Task InvalidPublicMemberPage(string rawIds, bool runtime)
    {
        using var handler = new Handler();
        var pages = 0;
        var identities = 0;
        handler.Failure = (request, _) => {
            if (request.RequestUri!.AbsolutePath == "/app-api/starbridge/v1/official-fleet/member-identities") identities++;
            if (request.RequestUri.AbsolutePath != "/app-api/member/organization/member/page") return null;
            pages++;
            Require(request.Headers.Authorization is null, "Public malformed-ID reads never receive a resource token");
            return Task.FromResult(PublicIdPage(rawIds));
        };
        using var host = Host(handler);
        host.ConfigureOfficialRealtime(runtime);
        using var dispatcher = new AccountBridgeDispatcher(host);
        var query = JsonSerializer.SerializeToElement(new { schemaVersion = runtime ? 2 : 1, sourceRef = "officialFleet:7",
            search = "", filter = "all", pageNumber = 1, pageSize = 50 });
        var result = (await dispatcher.DispatchAsync(BridgeEnvelope.Request(runtime ? "officialFleet.getRuntimeMembers" : "officialFleet.getMembers",
            "invalid-public-id", host.Generation, query, host.CurrentContext))).Response;
        Require(pages == 1 && identities == 0, "Invalid or equivalent duplicate public IDs fail before any G1 lookup");
        Require(result.Status == "error" && result.Error is { Code: AccountBridgeStableErrors.OfficialFleetDataInvalid, Retryable: false },
            "Malformed public IDs are invalid data, not an empty roster or an unlinked identity");
    }

    private static async Task PublicProfileStringId()
    {
        using var handler = new Handler();
        var reads = 0;
        handler.Failure = (request, _) => {
            if (request.RequestUri!.AbsolutePath != "/app-api/member/organization/get") return null;
            reads++;
            Require(request.Headers.Authorization is null, "Public profile ID compatibility never sends a resource token");
            return Task.FromResult(PublicIdResponse("{\"code\":0,\"data\":{\"id\":\"7\",\"sid\":\"ASTER\",\"membersCount\":1}}"));
        };
        using var host = Host(handler);
        var owner = host.CurrentContext!;
        var combined = await host.GetOfficialFleetAsync(owner, default);
        Require(combined.Fleet is { Profile: not null }, "Original optional public profile accepts a canonical string organization ID");
        _ = await host.GetOfficialFleetIdentityAsync(owner, default);
        var deferred = await host.GetOfficialFleetPublicProfileAsync(owner,
            JsonSerializer.SerializeToElement(new { schemaVersion = 1, sourceRef = "officialFleet:7" }), default);
        Require(deferred.Profile is not null && reads == 2, "Deferred profile shares the same public ID parser and original HTTP owner");
    }

    private static async Task PublicMemberEquivalentReferences()
    {
        using var handler = new Handler();
        var quoted = true;
        var lookups = new List<long[]>();
        async Task<HttpResponseMessage> Identity(HttpRequestMessage request, CancellationToken token)
        {
            Require(request.Method == HttpMethod.Post && request.RequestUri!.Port == 18082 &&
                request.Headers.Authorization?.Parameter == "synthetic-access", "G1 retains its authenticated resource owner");
            using var body = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
            var ids = body.RootElement.GetProperty("memberIds").EnumerateArray().Select(id => id.GetInt64()).ToArray();
            Require(ids.SequenceEqual(new[] { PublicLargeId }), "The authenticated G1 request receives the exact int64, never a rounded double");
            lookups.Add(ids);
            return PublicIdResponse(JsonSerializer.Serialize(new { schemaVersion = 1, sourceRef = "officialFleet:7", members = new[] {
                new OfficialFleetMemberIdentity(PublicLargeId, "visible", PublicIdSubject, "Bridge Pilot")
            } }, Json));
        }
        handler.Failure = (request, token) => {
            if (request.RequestUri!.AbsolutePath == "/app-api/member/organization/member/page")
            {
                Require(request.Method == HttpMethod.Get && request.RequestUri.Port == 18080 && request.Headers.Authorization is null,
                    "Compatible public member reads still use public core without the resource token");
                return Task.FromResult(PublicIdPage(quoted ? "\"9007199254740993\"" : "9007199254740993"));
            }
            return request.RequestUri.AbsolutePath == "/app-api/starbridge/v1/official-fleet/member-identities" ? Identity(request, token) : null;
        };
        using var host = Host(handler);
        using var dispatcher = new AccountBridgeDispatcher(host);
        string? reference = null;
        foreach (var useString in new[] { true, false })
        {
            quoted = useString;
            var response = (await dispatcher.DispatchAsync(BridgeEnvelope.Request("officialFleet.getMembers", "equivalent-public-id",
                host.Generation, Query(), host.CurrentContext))).Response;
            Require(response.Status == "ok", "Both public Long forms reach the actual member projection");
            var row = response.Payload.GetProperty("members")[0];
            var current = row.GetProperty("memberRef").GetString()!;
            Require(current.Length == 64 && (reference is null || reference == current) &&
                row.GetProperty("profileTargetRef").GetString() == current && row.GetProperty("callsign").GetString() == "Bridge Pilot",
                "Equivalent number/string IDs resolve one existing G1 identity and the same scoped opaque reference");
            Require(!row.TryGetProperty("userId", out _) && !row.TryGetProperty("memberId", out _) &&
                !response.Payload.GetRawText().Contains(PublicIdSubject, StringComparison.Ordinal) &&
                !response.Payload.GetRawText().Contains("9007199254740993", StringComparison.Ordinal),
                "Raw public IDs and private business subjects do not reach Flutter");
            reference = current;
        }
        Require(lookups.Count == 2, "Each original member read performs its existing identity lookup exactly once");
    }

    private static async Task RuntimePublicMemberExactLookup()
    {
        using var handler = new Handler();
        var reads = 0;
        var lookups = 0;
        async Task<HttpResponseMessage> Identity(HttpRequestMessage request, CancellationToken token)
        {
            using var body = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
            Require(body.RootElement.GetProperty("schemaVersion").GetInt32() == 2 &&
                body.RootElement.GetProperty("memberIds")[0].GetInt64() == PublicLargeId &&
                body.RootElement.GetProperty("memberIds").GetArrayLength() == 1 &&
                request.Headers.GetValues("X-StarBridge-Member-Identity-Version").Single() == "2",
                "Runtime's V2 lookup receives the exact public ID under its unchanged strict protocol");
            lookups++;
            // Deliberately stop at the existing identity authority boundary. This
            // fixture grants no live presence or permissions and configures no Relay.
            return new(HttpStatusCode.ServiceUnavailable) { Content = new StringContent("{}") };
        }
        handler.Failure = (request, token) => {
            if (request.RequestUri!.AbsolutePath == "/app-api/member/organization/member/page")
            {
                reads++;
                Require(request.Headers.Authorization is null, "Runtime public Long reads carry no resource token");
                return Task.FromResult(PublicIdPage(reads == 1 ? "\"9007199254740993\"" : "9007199254740993"));
            }
            return request.RequestUri.AbsolutePath == "/app-api/starbridge/v1/official-fleet/member-identities" ? Identity(request, token) : null;
        };
        using var host = Host(handler);
        host.ConfigureOfficialRealtime(true);
        using var dispatcher = new AccountBridgeDispatcher(host);
        for (var i = 0; i < 2; i++)
        {
            var query = JsonSerializer.SerializeToElement(new { schemaVersion = 2, sourceRef = "officialFleet:7",
                search = "", filter = "all", pageNumber = 1, pageSize = 50 });
            var response = (await dispatcher.DispatchAsync(BridgeEnvelope.Request("officialFleet.getRuntimeMembers", "runtime-public-id",
                host.Generation, query, host.CurrentContext))).Response;
            Require(response.Status == "error" && response.Error?.Code == OfficialFleetMemberIdentity.Unavailable,
                "Exact public ID reaches V2 G1; a real authority failure remains unavailable, not a fabricated runtime row");
        }
        Require(reads == 2 && lookups == 2, "Both runtime public Long forms reach exactly one existing V2 lookup per read");
    }
}
