using System.Collections.Concurrent;
using System.Globalization;
using System.Net;
using System.Net.Http.Headers;
using System.Text.Json;
using StarBridge.Core.Organizations;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    private const string OfficialRoleTemplatesPath = "/api/official-fleets/governance/roles/templates";
    private sealed record OfficialRole(string Key, int PermissionVersion, long MetadataRevision, bool Enabled,
        IReadOnlyList<OrganizationCapabilityPermission> Permissions, OfficialRoleMetadataValue? Metadata);
    private sealed record OfficialRolePage(string AccountScope, string SourceRef, string ScopeKey, string AuthorityBinding,
        long PolicyRevision, int Offset, int TotalCount, int? NextOffset, JsonElement Access, JsonElement CreationCapabilities,
        IReadOnlyDictionary<string, OfficialRole> Rows, DateTimeOffset Expires);
    private readonly ConcurrentDictionary<string, OfficialRolePage> _officialRolePages = new(StringComparer.Ordinal);
    private long _officialRolePageEpoch;

    internal Task<object> ReadOfficialRoleTemplatesAsync(string bearer, JsonElement body, string accountScope,
        Action current, CancellationToken token) => GuardWorkspace(async () =>
    {
        Validate(body, "sourceRef", "pageRef", "include");
        var includePolicy = OfficialFleetProjectionRequested(body, "policyV2");
        var source = Text(body, "sourceRef", 64); var continuation = Optional(body, "pageRef", 32);
        if (!OfficialAnnouncementSource(source) || continuation is not null && !LowerHex(continuation, 32)) throw Invalid();
        OfficialRolePage? previous = null;
        if (continuation is not null && (!_officialRolePages.TryGetValue(continuation, out previous) ||
            previous.AccountScope != accountScope || previous.SourceRef != source || previous.NextOffset is null ||
            previous.Expires <= _targetClock.GetUtcNow())) throw new AccountBridgeHostException("communities.refreshRequired");
        var epoch = continuation is null ? Interlocked.Increment(ref _officialRolePageEpoch) : Interlocked.Read(ref _officialRolePageEpoch);
        if (continuation is null) RetireOfficialRolePages(accountScope, source);
        OfficialRolePage page;
        try
        {
            page = await FetchOfficialRoleTemplatesAsync(bearer, source, accountScope, previous?.NextOffset ?? 0,
                previous?.PolicyRevision, current, token);
        }
        catch { RetireOfficialRolePages(accountScope, source); throw; }
        if (previous is not null && (previous.ScopeKey != page.ScopeKey || previous.AuthorityBinding != page.AuthorityBinding ||
            previous.PolicyRevision != page.PolicyRevision))
        {
            RetireOfficialRolePages(accountScope, source);
            throw new AccountBridgeHostException("communities.refreshRequired");
        }
        current(); token.ThrowIfCancellationRequested();
        if (epoch != Interlocked.Read(ref _officialRolePageEpoch) || _officialRolePages.Count >= 128)
            throw new AccountBridgeHostException("communities.refreshRequired");
        var reference = Guid.NewGuid().ToString("N");
        if (!_officialRolePages.TryAdd(reference, page)) throw Invalid();
        try
        {
            current(); token.ThrowIfCancellationRequested();
            if (epoch != Interlocked.Read(ref _officialRolePageEpoch)) throw new AccountBridgeHostException("communities.refreshRequired");
            var projection = JsonSerializer.SerializeToElement(new
            {
                schemaVersion = 1,
                state = "available",
                sourceRef = source,
                editRef = reference,
                revision = page.PolicyRevision,
                offset = page.Offset,
                totalCount = page.TotalCount,
                nextPageRef = page.NextOffset.HasValue ? reference : null,
                access = page.Access,
                creationCapabilities = includePolicy ? page.CreationCapabilities.EnumerateArray().ToArray() :
                    page.CreationCapabilities.EnumerateArray().Where(value =>
                        OrganizationCapabilityCatalog.Legacy.Contains(Text(value, "capability", 64), StringComparer.Ordinal)).ToArray(),
                roles = page.Rows.Select(pair =>
                {
                    var fields = new Dictionary<string, object?>
                    {
                        ["roleRef"] = pair.Key, ["enabled"] = pair.Value.Enabled,
                        ["permissions"] = pair.Value.Permissions, ["metadata"] = pair.Value.Metadata
                    };
                    if (includePolicy)
                    {
                        fields["roleKey"] = pair.Value.Key;
                        fields["permissionVersion"] = pair.Value.PermissionVersion;
                        fields["metadataRevision"] = pair.Value.MetadataRevision;
                    }
                    return fields;
                }).ToArray()
            }, new JsonSerializerOptions(JsonSerializerDefaults.Web));
            current(); token.ThrowIfCancellationRequested();
            return (object)projection;
        }
        catch { _officialRolePages.TryRemove(reference, out _); throw; }
    });

    private async Task<OfficialRolePage> FetchOfficialRoleTemplatesAsync(string bearer, string source, string accountScope,
        int offset, long? expected, Action current, CancellationToken token)
    {
        var path = OfficialRoleTemplatesPath + "?sourceRef=" + Uri.EscapeDataString(source) + "&offset=" + offset.ToString(CultureInfo.InvariantCulture);
        if (expected.HasValue) path += "&expectedPolicyRevision=" + expected.Value.ToString(CultureInfo.InvariantCulture);
        using var request = new HttpRequestMessage(HttpMethod.Get, new Uri(_origin, path));
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
        request.Headers.Add("X-StarBridge-Governance-Capabilities", "2");
        current(); token.ThrowIfCancellationRequested();
        using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
        current(); token.ThrowIfCancellationRequested();
        if (response.StatusCode != HttpStatusCode.OK) throw new AccountBridgeHostException(response.StatusCode switch
        {
            HttpStatusCode.Unauthorized => "communities.identityUnavailable",
            HttpStatusCode.Forbidden => "communities.notAllowed",
            HttpStatusCode.Conflict => "communities.refreshRequired",
            HttpStatusCode.NotFound => "communities.upgradeRequired",
            _ => "communities.unavailable"
        });
        var row = await ReadOfficialHangarJson(response, token, 256 * 1024);
        RequireOfficialAnnouncementObject(row, "schemaVersion", "state", "sourceRef", "scopeKey", "authorityBinding", "policyRevision",
            "offset", "totalCount", "nextOffset", "access", "creationCapabilities", "roles");
        if (Number(row, "schemaVersion", 1, 1) != 1 || Text(row, "state", 16) != "available" ||
            Text(row, "sourceRef", 64) != source || Number(row, "offset", 0, 8192) != offset) throw Invalid();
        var scope = Text(row, "scopeKey", 64); var binding = Text(row, "authorityBinding", 64);
        if (!LowerHex(scope, 64) || !LowerHex(binding, 64)) throw Invalid();
        var policy = OfficialAnnouncementRevision(row, "policyRevision");
        if (expected.HasValue && expected.Value != policy) throw Invalid();
        var total = Number(row, "totalCount", 0, 8192); var values = Rows(row, "roles", 20).ToArray();
        if (offset > total || values.Length != Math.Min(20, total - offset)) throw Invalid();
        int? next = row.GetProperty("nextOffset").ValueKind == JsonValueKind.Null ? null : Number(row, "nextOffset", 0, 8192);
        int? expectedNext = offset + values.Length < total ? offset + values.Length : null;
        if (next != expectedNext) throw Invalid();
        var access = row.GetProperty("access"); RequireOfficialAnnouncementObject(access, "read", "create", "updateMetadata");
        foreach (var name in new[] { "read", "create", "updateMetadata" }) ValidateOfficialRoleDecision(access.GetProperty(name));
        if (Text(access.GetProperty("read"), "state", 16) != "allowed") throw Invalid();
        var capabilities = Rows(row, "creationCapabilities", OrganizationCapabilityCatalog.Implemented.Count).ToArray(); var seenCapabilities = new HashSet<string>(StringComparer.Ordinal);
        foreach (var value in capabilities)
        {
            RequireOfficialAnnouncementObject(value, "capability", "state", "reason");
            var capability = Text(value, "capability", 64);
            if (!OrganizationCapabilityCatalog.IsSupported(capability) || !seenCapabilities.Add(capability)) throw Invalid();
            ValidateOfficialRoleDecision(value, withCapability: true);
        }
        if (!seenCapabilities.SetEquals(OrganizationCapabilityCatalog.Implemented) && !seenCapabilities.SetEquals(OrganizationCapabilityCatalog.Legacy)) throw Invalid();
        var roles = new Dictionary<string, OfficialRole>(StringComparer.Ordinal); var keys = new HashSet<string>(StringComparer.Ordinal);
        foreach (var value in values)
        {
            RequireOfficialAnnouncementObject(value, "roleKey", "permissionVersion", "metadataRevision", "enabled", "permissions", "metadata");
            var key = OfficialRoleText(value, "roleKey", 256);
            if (!keys.Add(key)) throw Invalid();
            var version = Number(value, "permissionVersion", 1, int.MaxValue);
            var revision = OfficialAnnouncementRevision(value, "metadataRevision");
            var metadata = value.GetProperty("metadata").ValueKind == JsonValueKind.Null ? null : ParseOfficialRoleMetadata(value.GetProperty("metadata"));
            roles.Add(Guid.NewGuid().ToString("N"), new(key, version, revision, OfficialRoleFlag(value.GetProperty("enabled")),
                ParseOfficialRolePermissions(value.GetProperty("permissions")), metadata));
        }
        current(); token.ThrowIfCancellationRequested();
        return new(accountScope, source, scope, binding, policy, offset, total, next, access.Clone(), row.GetProperty("creationCapabilities").Clone(),
            roles, _targetClock.GetUtcNow().AddMinutes(5));
    }

    private static void ValidateOfficialRoleDecision(JsonElement value, bool withCapability = false)
    {
        if (!withCapability) RequireOfficialAnnouncementObject(value, "state", "reason");
        var state = Text(value, "state", 16); var reason = Text(value, "reason", 128);
        if (state is not ("allowed" or "denied" or "unavailable") || reason.Length == 0 ||
            reason.Any(c => !(char.IsAsciiLetterOrDigit(c) || c == '_'))) throw Invalid();
    }
    private static OfficialRoleMetadataValue ParseOfficialRoleMetadata(JsonElement value)
    {
        RequireOfficialAnnouncementObject(value, "displayName", "description", "color", "sortOrder");
        return new(OfficialRoleText(value, "displayName", 64), Text(value, "description", 1024, true),
            OfficialRoleText(value, "color", 32), Number(value, "sortOrder", int.MinValue, int.MaxValue));
    }
    private static string OfficialRoleText(JsonElement value, string key, int limit)
    {
        var text = Text(value, key, limit);
        return !string.IsNullOrWhiteSpace(text) && text == text.Trim() ? text : throw Invalid();
    }
    private static bool OfficialRoleFlag(JsonElement value) => value.ValueKind switch
    {
        JsonValueKind.True => true,
        JsonValueKind.False => false,
        _ => throw Invalid()
    };
    private static IReadOnlyList<OrganizationCapabilityPermission> ParseOfficialRolePermissions(JsonElement value)
    {
        if (value.ValueKind != JsonValueKind.Array || value.GetArrayLength() > OrganizationCapabilityCatalog.Implemented.Count) throw Invalid();
        var seen = new HashSet<string>(StringComparer.Ordinal); var rows = new List<OrganizationCapabilityPermission>();
        foreach (var row in value.EnumerateArray())
        {
            RequireOfficialAnnouncementObject(row, "capability", "canUse", "canDelegate");
            var key = Text(row, "capability", 64); var use = OfficialRoleFlag(row.GetProperty("canUse")); var grant = OfficialRoleFlag(row.GetProperty("canDelegate"));
            if (!OrganizationCapabilityCatalog.IsSupported(key) || !seen.Add(key) || grant && !use) throw Invalid();
            rows.Add(new(key, use, grant));
        }
        return Array.AsReadOnly(rows.OrderBy(row => row.Capability, StringComparer.Ordinal).ToArray());
    }
    private void RetireOfficialRolePages(string accountScope, string source)
    {
        foreach (var pair in _officialRolePages.Where(pair => pair.Value.AccountScope == accountScope && pair.Value.SourceRef == source ||
            pair.Value.Expires <= _targetClock.GetUtcNow()).ToArray()) _officialRolePages.TryRemove(pair.Key, out _);
    }
    private void DisposeOfficialRolePages() { Interlocked.Increment(ref _officialRolePageEpoch); _officialRolePages.Clear(); }
}
