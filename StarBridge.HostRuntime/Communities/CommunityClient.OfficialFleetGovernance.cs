using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;
using StarBridge.Core.Organizations;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    internal Task<object> ReadOfficialGovernanceContextAsync(string bearer, JsonElement body,
        Action current, CancellationToken token, Action? roleSupportObserved = null) => GuardWorkspace(async () =>
    {
        Validate(body, "sourceRef", "include");
        bool Includes(string name)
        {
            if (!body.TryGetProperty("include", out var include)) return false;
            if (include.ValueKind != JsonValueKind.Array) throw Invalid();
            var values = include.EnumerateArray().Select(v => v.ValueKind == JsonValueKind.String ? v.GetString() : null).ToArray();
            if (values.Any(v => v is not ("role" or "capabilitiesV2")) || values.Distinct(StringComparer.Ordinal).Count() != values.Length) throw Invalid();
            return values.Contains(name, StringComparer.Ordinal);
        }
        var includeRole = Includes("role"); var includeCapabilities = Includes("capabilitiesV2");
        var sourceRef = Text(body, "sourceRef", 64);
        if (!OfficialAnnouncementSource(sourceRef)) throw Invalid();
        using var request = new HttpRequestMessage(HttpMethod.Get,
            new Uri(_origin, "/api/official-fleets/governance/context?sourceRef=" + Uri.EscapeDataString(sourceRef)));
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
        request.Headers.Add("X-StarBridge-Governance-Role", "1");
        request.Headers.Add("X-StarBridge-Governance-Capabilities", "2");
        current(); token.ThrowIfCancellationRequested();
        using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
        current(); token.ThrowIfCancellationRequested();
        if (response.StatusCode == HttpStatusCode.ServiceUnavailable)
        {
            JsonElement failure;
            try { failure = await ReadOfficialHangarJson(response, token, 4096); }
            catch (Exception error) when (error is JsonException or AccountBridgeHostException)
            { throw new AccountBridgeHostException("communities.unavailable"); }
            current(); token.ThrowIfCancellationRequested();
            if (failure.ValueKind == JsonValueKind.Object && failure.TryGetProperty("state", out var reason) &&
                reason.ValueKind == JsonValueKind.String && reason.GetString() == OrganizationRankAuthority.StaleReason)
                throw new AccountBridgeHostException(OrganizationRankAuthority.StaleReason,
                    membershipUpdatedAt: GovernanceUpdatedAt(failure));
        }
        if (response.StatusCode != HttpStatusCode.OK) throw new AccountBridgeHostException(response.StatusCode switch
        {
            HttpStatusCode.Unauthorized => "communities.identityUnavailable",
            HttpStatusCode.Forbidden => "communities.notAllowed",
            HttpStatusCode.NotFound => "communities.upgradeRequired",
            _ => "communities.unavailable"
        });
        var row = await ReadOfficialHangarJson(response, token, 16 * 1024);
        var hasRole = row.TryGetProperty("role", out _);
        string[] fields = hasRole
            ? ["schemaVersion", "sourceRef", "scopeKey", "policyRevision", "capabilities", "rootAuthority", "role"]
            : ["schemaVersion", "sourceRef", "scopeKey", "policyRevision", "capabilities", "rootAuthority"];
        var updatedAt = GovernanceUpdatedAt(row);
        if (row.TryGetProperty("membershipUpdatedAt", out _)) fields = [.. fields, "membershipUpdatedAt"];
        RequireOfficialAnnouncementObject(row, fields);
        var role = hasRole ? Text(row, "role", 16) : null;
        if (role is not (null or "leader" or "admin" or "editor" or "member")) throw Invalid();
        if (Number(row, "schemaVersion", 1, 1) != 1 || Text(row, "sourceRef", 64) != sourceRef ||
            !LowerHex(Text(row, "scopeKey", 64), 64)) throw Invalid();
        var policyRevision = OfficialAnnouncementRevision(row, "policyRevision");
        static bool State(string state) => state is "allowed" or "denied" or "unavailable";
        object Decision(JsonElement value, string key)
        {
            RequireOfficialAnnouncementObject(value, key, "state", "reason");
            var state = Text(value, "state", 16); var reason = Text(value, "reason", 128);
            if (!State(state) || string.IsNullOrEmpty(reason) || reason.Any(c => !(char.IsAsciiLetterOrDigit(c) || c == '_')))
                throw Invalid();
            return key == "capability"
                ? new { capability = Text(value, key, 64), state, reason }
                : (object)new { action = Text(value, key, 16), state, reason };
        }
        var capabilities = Rows(row, "capabilities", OrganizationCapabilityCatalog.Implemented.Count).ToArray();
        var names = capabilities.Select(v => Text(v, "capability", 64)).ToArray();
        var expectedNames = capabilities.Length == OrganizationCapabilityCatalog.Legacy.Count ? OrganizationCapabilityCatalog.Legacy : OrganizationCapabilityCatalog.Implemented;
        if (names.Distinct(StringComparer.Ordinal).Count() != expectedNames.Count ||
            !names.OrderBy(v => v, StringComparer.Ordinal).SequenceEqual(expectedNames.OrderBy(v => v, StringComparer.Ordinal))) throw Invalid();
        var allCapabilities = capabilities.Select(v => Decision(v, "capability")).ToArray();
        var projectedCapabilities = includeCapabilities ? allCapabilities : capabilities.Where(v =>
            OrganizationCapabilityCatalog.Legacy.Contains(Text(v, "capability", 64), StringComparer.Ordinal)).Select(v => Decision(v, "capability")).ToArray();
        var root = row.GetProperty("rootAuthority");
        RequireOfficialAnnouncementObject(root, "providerState", "controls");
        var providerState = Text(root, "providerState", 16);
        if (providerState is not ("unconfigured" or "unavailable" or "observed")) throw Invalid();
        var controls = Rows(root, "controls", 3).ToArray();
        var actions = controls.Select(v => Text(v, "action", 16)).ToArray();
        if (controls.Length != 3 || actions.Distinct(StringComparer.Ordinal).Count() != 3 ||
            !actions.OrderBy(v => v, StringComparer.Ordinal).SequenceEqual(new[] { "activate", "delegate", "recover" })) throw Invalid();
        var projectedControls = controls.Select(v => Decision(v, "action")).ToArray();
        current(); token.ThrowIfCancellationRequested();
        // ScopeKey is only a private maintenance correlation; this read grants no action or editing reference.
        var values = new Dictionary<string, object?>
        {
            ["schemaVersion"] = 1, ["sourceRef"] = sourceRef, ["policyRevision"] = policyRevision,
            ["capabilities"] = projectedCapabilities,
            ["rootAuthority"] = new { providerState, controls = projectedControls }
        };
        if (includeRole && hasRole) values["role"] = role;
        if (includeRole && updatedAt is not null) values["membershipUpdatedAt"] = updatedAt;
        var projection = JsonSerializer.SerializeToElement(values);
        current(); token.ThrowIfCancellationRequested();
        // Relay support is observed independently of Flutter's requested projection.
        // The account owner commits this observation only after its session checks.
        if (hasRole) roleSupportObserved?.Invoke();
        return (object)projection;
    });

    private static string? GovernanceUpdatedAt(JsonElement row)
    {
        if (!row.TryGetProperty("membershipUpdatedAt", out var value)) return null;
        if (value.ValueKind != JsonValueKind.String || !value.TryGetDateTimeOffset(out _)) throw Invalid();
        return value.GetString();
    }

    private static bool OfficialFleetProjectionRequested(JsonElement body, string known)
    {
        if (!body.TryGetProperty("include", out var include)) return false;
        if (include.ValueKind != JsonValueKind.Array) throw Invalid();
        var requested = false;
        foreach (var value in include.EnumerateArray())
        {
            if (requested || value.ValueKind != JsonValueKind.String || value.GetString() != known) throw Invalid();
            requested = true;
        }
        return requested;
    }
}
