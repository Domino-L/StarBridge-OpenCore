using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.Core.Profiles;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

// All HTTP is handled in memory. These checks never use a configured service or token vault.
internal static class VisitorFleetAffiliationTests
{
    private static readonly JsonSerializerOptions Web = new(JsonSerializerDefaults.Web);
    private static void Check(bool value, string label)
    {
        if (!value) throw new Exception("Visitor affiliation: " + label);
    }

    internal static async Task Run()
    {
        foreach (var status in new string?[] { "shown", "none", "unavailable", null, "hidden", "future-value" })
        {
            var body = Page();
            body["fleetAffiliationStatus"] = status;
            var page = JsonSerializer.Deserialize<PersonalProfileDocumentContract>(JsonSerializer.Serialize(body, Web), Web)!;
            Check(page.FleetAffiliationStatus == (status is "shown" or "none" ? status : "unavailable"),
                "full document accepts status and safely handles null/unknown");
        }
        var old = JsonSerializer.Deserialize<PersonalProfileDocumentContract>(JsonSerializer.Serialize(Page(), Web), Web)!;
        Check(old.FleetAffiliationStatus == "unavailable", "old document with no status is unavailable");

        foreach (bool legacy in new[] { false, true })
        {
            var headerBody = Header(legacy);
            var oldHeader = PersonalProfilePublicHeader.Parse(BridgePayload.From(headerBody), legacy ? "fixture-legacy" : null);
            Check(oldHeader.FleetAffiliationStatus == "hidden", "restricted header without status is hidden");
            headerBody["fleetAffiliationStatus"] = "hidden";
            var header = PersonalProfilePublicHeader.Parse(BridgePayload.From(headerBody), legacy ? "fixture-legacy" : null);
            var bridge = BridgePayload.From(header.ToBridge());
            Check(bridge.GetProperty("fleetAffiliationStatus").GetString() == "hidden", "restricted status reaches bridge");
            Check(bridge.GetProperty("publicHeader").TryGetProperty("callSign", out _) &&
                bridge.GetProperty("publicHeader").EnumerateObject().All(p =>
                    new[] { "avatarAssetId", "callSign", "tradeWindow" }.Contains(p.Name)), "public header data whitelist is unchanged");
            foreach (var invalid in new object?[] { "shown", "none", "unavailable", null, 1 })
            {
                headerBody["fleetAffiliationStatus"] = invalid;
                RejectHeader(headerBody, legacy, "non-hidden status in restricted response");
            }
            headerBody["fleetAffiliationStatus"] = "hidden";
            headerBody["fleetAffiliation"] = new { fleetName = "leak" };
            RejectHeader(headerBody, legacy, "organization data at root");
            headerBody.Remove("fleetAffiliation");
            headerBody["publicHeader"] = new { callsign = "Target", fleetAffiliation = new { fleetCode = "leak" } };
            RejectHeader(headerBody, legacy, "organization data in header");
        }
        var duplicate = "{\"schemaVersion\":1,\"restricted\":true,\"visibility\":\"private\",\"publicHeader\":{\"callsign\":\"Target\"}," +
            "\"fleetAffiliationStatus\":\"hidden\",\"fleetAffiliationStatus\":\"hidden\"}";
        using (var json = JsonDocument.Parse(duplicate))
        {
            try { PersonalProfilePublicHeader.Parse(json.RootElement, null); throw new Exception("duplicate status accepted"); }
            catch (JsonException) { }
        }

        foreach (bool legacy in new[] { false, true })
        {
            using var transport = new Transport(legacy);
            var http = new ScmHttpClient(transport);
            var endpoint = new Uri("http://127.0.0.1:9/app-api/starbridge/v1/personal-profile");
            var client = new OAuthPkceClient(http, new EmptyVault(), new ScmOAuthOptions(
                "fixture", endpoint, endpoint, endpoint, "fixture", "fixture", "profile.read", "/callback"));
            var session = new ScmOAuthSession("fixture", "viewer", "Viewer", "synthetic",
                DateTimeOffset.UtcNow.AddHours(1), ["profile.read"]);
            async Task<ScmPersonalProfileResult> Read() => legacy
                ? await client.LoadLegacyMemberVisitorPersonalProfileAsync(session, "fixture-legacy", default)
                : await client.LoadVisitorPersonalProfileAsync(session, "scm-v1:" + new string('a', 64), default);
            foreach (var status in new[] { "shown", "none", "unavailable" })
            {
                var page = Page(); page["fleetAffiliationStatus"] = status;
                transport.Body = legacy ? new { schemaVersion = 1, legacyAccountId = "fixture-legacy", profile = page } : page;
                Check((await Read()).Profile.FleetAffiliationStatus == status, "both visitor routes preserve status");
            }
            transport.Body = legacy ? new { schemaVersion = 1, legacyAccountId = "fixture-legacy", profile = Page() } : Page();
            Check((await Read()).Profile.FleetAffiliationStatus == "unavailable", "both routes default old page");
            var header = Header(legacy); header["fleetAffiliationStatus"] = "hidden"; transport.Body = header;
            Check((await Read()).Restricted?.FleetAffiliationStatus == "hidden", "both routes parse hidden");
            header.Remove("fleetAffiliationStatus");
            Check((await Read()).Restricted?.FleetAffiliationStatus == "hidden", "both routes treat a header without status as hidden");
            Check(transport.Calls == 6, "reads add no fallback request or alternate route");
        }
    }

    private static void RejectHeader(object body, bool legacy, string label)
    {
        try { PersonalProfilePublicHeader.Parse(BridgePayload.From(body), legacy ? "fixture-legacy" : null); }
        catch (JsonException) { return; }
        throw new Exception("Visitor affiliation accepted " + label);
    }

    private static Dictionary<string, object?> Page() => new()
    {
        ["schemaVersion"] = 3, ["publicId"] = "fixture-public-id", ["isPublic"] = true,
        ["visibility"] = "public", ["revision"] = 7, ["updatedAt"] = DateTimeOffset.UnixEpoch,
        ["identity"] = new { callsign = "Target", gameId = "" }, ["content"] = PersonalProfileContentContract.Empty,
        ["fleetAffiliation"] = null, ["hangar"] = null
    };

    private static Dictionary<string, object?> Header(bool legacy)
    {
        var result = new Dictionary<string, object?>
        {
            ["schemaVersion"] = 1, ["restricted"] = true, ["visibility"] = "private",
            ["publicHeader"] = new { callsign = "Target", tradeWindow = (object?)null }
        };
        if (legacy) result["legacyAccountId"] = "fixture-legacy";
        return result;
    }

    private sealed class Transport(bool legacy) : HttpMessageHandler
    {
        internal object Body = Page();
        internal int Calls;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Calls++;
            Check(request.RequestUri!.IsLoopback && request.RequestUri.Port == 9, "synthetic endpoint only");
            Check(request.Method == (legacy ? HttpMethod.Post : HttpMethod.Get), "existing route method");
            Check(Uri.UnescapeDataString(request.RequestUri.AbsolutePath).EndsWith(legacy ? "/visitor-legacy" : "/visitor/scm-v1:" + new string('a', 64)),
                "existing route path");
            var response = new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(Body, options: Web) };
            if (!legacy) response.Headers.Add("X-StarBridge-Profile-Subject", "scm-v1:" + new string('a', 64));
            return Task.FromResult(response);
        }
    }

    private sealed class EmptyVault : ITokenVault
    {
        public void SaveRefreshToken(string key, string value) => throw new InvalidOperationException("No vault writes");
        public string? LoadRefreshToken(string key) => null;
        public string? LoadActiveAccountKey() => null;
        public void DeleteRefreshToken(string key) => throw new InvalidOperationException("No vault writes");
    }
}
