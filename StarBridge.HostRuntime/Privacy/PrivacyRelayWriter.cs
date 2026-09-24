using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Privacy;

/// <summary>S2 active route only. No redirect, fallback, link creation or stored bearer.</summary>
internal sealed partial class PrivacyRelayWriter : IDisposable
{
    private readonly HttpClient _http;
    private readonly Uri _players, _membership, _communityTargets, _scopedPlayers, _communityMembers, _eventSettings;
    internal PrivacyRelayWriter(Uri origin, HttpMessageHandler? handler = null)
    {
        if (!origin.IsAbsoluteUri || origin.UserInfo.Length > 0 || origin.Query.Length > 0 || origin.Fragment.Length > 0 ||
            (origin.Scheme != "https" && !(origin.Scheme == "http" && origin.IsLoopback)))
            throw new ArgumentException("Trusted HTTPS or loopback origin required.");
        _players = new Uri(origin, "/api/players/realtime");
        _eventSettings = new Uri(origin, "/api/privacy/events");
        _communityMembers = new Uri(origin, "/api/privacy/community-members/read");
        _membership = new Uri(origin, "/api/fleets/membership");
        _communityTargets = new Uri(origin, "/api/privacy/community-scopes");
        _scopedPlayers = new Uri(origin, "/api/players/realtime-scoped");
        _http = new(handler ?? new HttpClientHandler { AllowAutoRedirect = false }) { Timeout = TimeSpan.FromSeconds(12) };
    }
    internal async Task SendAsync(string bearer, JsonElement payload, CancellationToken token)
    {
        if (payload.TryGetProperty("communities", out _))
        {
            await SendCommunitiesAsync(bearer, payload, token);
            return;
        }
        if (payload.GetProperty("online").GetBoolean())
        {
            // Legacy realtime audiences depend on the legacy membership, not the
            // SCM official-fleet page. Never invent a fleet or write its directory.
            using var membershipRequest = Request(HttpMethod.Get, _membership, bearer);
            using var membershipResponse = await _http.SendAsync(membershipRequest, HttpCompletionOption.ResponseHeadersRead, token);
            RequireSuccess(membershipResponse);
            using var membership = await ReadAsync(membershipResponse, token);
            var code = membership.RootElement.GetProperty("fleetCode");
            if (code.ValueKind is not (JsonValueKind.Null or JsonValueKind.String)) throw Invalid();
            var fleet = code.GetString();
            if (fleet is not null && (fleet.Length > 256 || fleet.Any(char.IsControl))) throw Invalid();
            var body = System.Text.Json.Nodes.JsonNode.Parse(payload.GetRawText())!.AsObject();
            body["fleet"] = string.IsNullOrWhiteSpace(fleet) ? "No Fleet" : fleet;
            payload = JsonSerializer.SerializeToElement(body);
        }
        // Retired references may survive in signed local files, never in a grant.
        var retired = System.Text.Json.Nodes.JsonNode.Parse(payload.GetRawText())!.AsObject();
        retired["fleetVisibilityGroupIds"] = new System.Text.Json.Nodes.JsonArray();
        retired["roomVisibilityGroupIds"] = new System.Text.Json.Nodes.JsonArray();
        payload = JsonSerializer.SerializeToElement(retired);
        using var request = Request(HttpMethod.Post, _players, bearer);
        request.Content = JsonContent.Create(payload);
        using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
        RequireSuccess(response);
        if (!response.Headers.TryGetValues("X-StarBridge-Realtime-Version", out var versions) ||
            !versions.SequenceEqual(new[] { "1" })) throw Invalid();
        using var result = await ReadAsync(response, token);
        ValidateReceipt(result.RootElement, payload);
    }
    private static void ValidateReceipt(JsonElement root, JsonElement payload)
    {
        // A 200 alone is insufficient: an older server dropping dual-axis fields
        // cannot be advertised as having applied privacy. Never log this body.
        foreach (var key in new[] { "name", "online", "ship", "location", "liveStatus", "visibilityScope",
            "roomVisibilityScope", "fleetSharedStateFields", "roomSharedStateFields", "fleetAdministratorsCanView",
            "fleetMembersCanView", "roomMembersCanView", "friendsCanViewPresence",
            "fleetVisibilityGroupIds", "roomVisibilityGroupIds" })
        {
            if (!root.TryGetProperty(key, out var value) || !Equal(value, payload.GetProperty(key)))
                throw Invalid();
        }
        foreach (var key in new[] { "serverShard", "serverRegion" })
        {
            var expected = payload.GetProperty(key);
            if (!root.TryGetProperty(key, out var value)) { if (expected.ValueKind != JsonValueKind.Null) throw Invalid(); }
            else if (!Equal(value, expected)) throw Invalid();
        }
    }
    private static bool Equal(JsonElement a, JsonElement b) => a.ValueKind == b.ValueKind &&
        (a.ValueKind == JsonValueKind.Array
            ? a.EnumerateArray().Select(v => v.ToString()).OrderBy(v => v, StringComparer.Ordinal)
                .SequenceEqual(b.EnumerateArray().Select(v => v.ToString()).OrderBy(v => v, StringComparer.Ordinal))
            : a.ToString() == b.ToString());
    private static HttpRequestMessage Request(HttpMethod method, Uri uri, string bearer)
    {
        var request = new HttpRequestMessage(method, uri);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
        return request;
    }
    private static void RequireSuccess(HttpResponseMessage response)
    {
        if (response.IsSuccessStatusCode) return;
        throw new AccountBridgeHostException(response.StatusCode switch {
            HttpStatusCode.Unauthorized => "privacy_publication.identity_unavailable",
            HttpStatusCode.Forbidden => "privacy_publication.forbidden",
            HttpStatusCode.Conflict or HttpStatusCode.PreconditionRequired => "privacy_publication.identity_required",
            HttpStatusCode.Gone => "privacy_publication.route_retired",
            HttpStatusCode.RequestTimeout or HttpStatusCode.TooManyRequests or
                HttpStatusCode.InternalServerError or HttpStatusCode.BadGateway or
                HttpStatusCode.ServiceUnavailable or HttpStatusCode.GatewayTimeout => "privacy_publication.temporarily_unavailable",
            _ => "privacy_publication.unavailable"
        });
    }
    private static async Task<JsonDocument> ReadAsync(HttpResponseMessage response, CancellationToken token)
    {
        const int maximum = 2 * 1024 * 1024;
        if (response.Content.Headers.ContentLength > maximum) throw Invalid();
        using var input = await response.Content.ReadAsStreamAsync(token);
        using var output = new MemoryStream();
        var buffer = new byte[8192];
        int count;
        while ((count = await input.ReadAsync(buffer, token)) != 0)
        { if (output.Length + count > maximum) throw Invalid(); output.Write(buffer, 0, count); }
        var doc = JsonDocument.Parse(output.ToArray(), new JsonDocumentOptions { MaxDepth = 32 });
        try { LocalPrivacyStore.RejectDuplicates(doc.RootElement); return doc; }
        catch { doc.Dispose(); throw; }
    }
    private static AccountBridgeHostException Invalid() => new("privacy_publication.response_invalid");
    public void Dispose() => _http.Dispose();
}
