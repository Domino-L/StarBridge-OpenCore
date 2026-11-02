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
    internal Action<string, string, int?, long>? CommunityReadDiagnostic { get; set; }
    internal Action<string, string, int?, long>? PublicationDiagnostic { get; set; }
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
        _http = new(handler ?? new HttpClientHandler { AllowAutoRedirect = false }) {
            Timeout = TimeSpan.FromSeconds(12), MaxResponseContentBufferSize = 2 * 1024 * 1024 };
    }
    internal static bool IsCompleteWithdrawal(JsonElement payload) =>
        !payload.GetProperty("online").GetBoolean() &&
        !payload.GetProperty("roomMembersCanView").GetBoolean() && payload.GetProperty("roomSharedStateFields").GetInt32() == 0 &&
        !payload.GetProperty("fleetMembersCanView").GetBoolean() && !payload.GetProperty("fleetAdministratorsCanView").GetBoolean() &&
        payload.GetProperty("fleetSharedStateFields").GetInt32() == 0 && !payload.GetProperty("friendsCanViewPresence").GetBoolean() &&
        (!payload.TryGetProperty("communities", out var scopes) || scopes.ValueKind == JsonValueKind.Array && scopes.GetArrayLength() == 0);

    internal async Task SendAsync(string bearer, JsonElement payload, CancellationToken token, Action? current = null,
        bool allowOfficialPositive = false, PositivePublicationAdmission? admission = null)
    {
        if (payload.TryGetProperty("officialFleet", out _)) {
            await SendOfficialFleetAsync(bearer, payload, token, current, allowOfficialPositive, admission); return;
        }
        if (payload.TryGetProperty("communities", out _))
        {
            await SendCommunitiesAsync(bearer, payload, token, current: current, admission: admission);
            return;
        }
        if (payload.GetProperty("online").GetBoolean())
        {
            // Legacy realtime audiences depend on the legacy membership, not the
            // SCM official-fleet page. Never invent a fleet or write its directory.
            using var membershipRequest = Request(HttpMethod.Get, _membership, bearer);
            using var membershipResponse = await _http.SendAsync(membershipRequest, HttpCompletionOption.ResponseHeadersRead, token);
            RequireSuccess(membershipResponse);
            var fleet = await ObservePublicationReceiptAsync(membershipResponse, async () =>
            {
                using var membership = await ReadAsync(membershipResponse, token);
                var code = membership.RootElement.GetProperty("fleetCode");
                if (code.ValueKind is not (JsonValueKind.Null or JsonValueKind.String)) throw Invalid();
                var value = code.GetString();
                if (value is not null && (value.Length > 256 || value.Any(char.IsControl))) throw Invalid();
                return value;
            }, "publication-membership");
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
        using var response = await SendAdmittedAsync(request, token, current, admission);
        RequireSuccess(response);
        await ObservePublicationReceiptAsync(response, async () =>
        {
            if (!response.Headers.TryGetValues("X-StarBridge-Realtime-Version", out var versions) ||
                !versions.SequenceEqual(new[] { "1" })) throw Invalid();
            using var result = await ReadAsync(response, token);
            ValidateReceipt(result.RootElement, payload);
        });
    }
    private async Task<HttpResponseMessage> SendAdmittedAsync(HttpRequestMessage request, CancellationToken token,
        Action? current, PositivePublicationAdmission? admission)
    {
        using var lease = admission is null ? null : await admission.EnterAsync(token).ConfigureAwait(false);
        token.ThrowIfCancellationRequested();
        current?.Invoke();
        // Keep the lease through response completion, including the body. This
        // scope never waits for publication _gate; membership/OAuth retries are
        // outside it and must re-enter and revalidate before their next write.
        return await _http.SendAsync(request, HttpCompletionOption.ResponseContentRead, token).ConfigureAwait(false);
    }
    private static readonly string[] RequiredReceiptFields = [ "name", "online", "ship", "location", "liveStatus", "visibilityScope",
        "roomVisibilityScope", "fleetSharedStateFields", "roomSharedStateFields", "fleetAdministratorsCanView",
        "fleetMembersCanView", "roomMembersCanView", "friendsCanViewPresence",
        "fleetVisibilityGroupIds", "roomVisibilityGroupIds" ];
    private static readonly string[] OptionalReceiptFields = [ "serverShard", "serverRegion" ];
    private static readonly object ReceiptMismatchKey = new();
    internal static bool IsReceiptField(string? field) => field is not null &&
        (RequiredReceiptFields.Contains(field, StringComparer.Ordinal) || OptionalReceiptFields.Contains(field, StringComparer.Ordinal));

    private static AccountBridgeHostException ReceiptMismatch(string field)
    {
        // Carry only a fixed field name; retain the original exception type/code.
        var error = Invalid();
        error.Data[ReceiptMismatchKey] = field;
        return error;
    }

    private static void ValidateReceipt(JsonElement root, JsonElement payload)
    {
        // A 200 alone is insufficient: an older server dropping dual-axis fields
        // cannot be advertised as having applied privacy. Never log this body.
        foreach (var key in RequiredReceiptFields)
        {
            if (!root.TryGetProperty(key, out var value)) throw ReceiptMismatch(key);
            var expected = payload.GetProperty(key);
            if (!(key == "name" && value.ValueKind == JsonValueKind.String && expected.ValueKind == JsonValueKind.String
                    ? string.Equals(value.GetString(), expected.GetString(), StringComparison.OrdinalIgnoreCase)
                    : Equal(value, expected)))
                throw ReceiptMismatch(key);
        }
        foreach (var key in OptionalReceiptFields)
        {
            var expected = payload.GetProperty(key);
            if (!root.TryGetProperty(key, out var value)) { if (expected.ValueKind != JsonValueKind.Null) throw ReceiptMismatch(key); }
            else if (!Equal(value, expected)) throw ReceiptMismatch(key);
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
        }, httpStatus: response.StatusCode);
    }
    // Temporary loopback diagnostic [DEBUG-community-read]. Only a fixed code
    // whitelist can leave this method; response text and identifiers never do.
    internal async Task RecordPublicationErrorAsync(HttpResponseMessage response, CancellationToken token)
    {
        var diagnostic = PublicationDiagnostic ?? CommunityReadDiagnostic;
        if (diagnostic is null || response.IsSuccessStatusCode) return;
        var code = "unclassified";
        try
        {
            if (response.Content.Headers.ContentLength is null or <= 2048)
            {
                using var budget = CancellationTokenSource.CreateLinkedTokenSource(token);
                budget.CancelAfter(TimeSpan.FromMilliseconds(250));
                using var stream = await response.Content.ReadAsStreamAsync(budget.Token);
                var bytes = new byte[2049];
                var count = 0;
                while (count < bytes.Length)
                {
                    var read = await stream.ReadAsync(bytes.AsMemory(count), budget.Token);
                    if (read == 0) break;
                    count += read;
                }
                if (count <= 2048)
                {
                    using var body = JsonDocument.Parse(bytes.AsMemory(0, count));
                    if (body.RootElement.TryGetProperty("code", out var value) && value.ValueKind == JsonValueKind.String)
                        code = value.GetString() switch {
                            "SCM_BUSINESS_IDENTITY_UNAVAILABLE" => "scm_business_identity_unavailable",
                            "SCM_IDENTITY_UNAVAILABLE" => "scm_identity_unavailable",
                            "LEGACY_ACCOUNT_MISSING" => "legacy_account_missing",
                            _ => "unclassified"
                        };
                }
            }
        }
        catch { /* Diagnostic failure cannot replace the original HTTP error. */ }
        try { diagnostic("publication-http", code, (int)response.StatusCode, 0); }
        catch { /* Diagnostic failure cannot affect publication. */ }
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
