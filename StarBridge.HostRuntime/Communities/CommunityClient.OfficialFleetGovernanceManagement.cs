using System.Globalization;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.Core.Organizations;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    private const string GovernancePath = "/api/official-fleets/governance/";

    internal Task<object> OfficialGovernanceManagementAsync(string bearer, JsonElement body, string action,
        Action current, CancellationToken token) => GuardWorkspace(async () =>
    {
        var write = action is "writeRankPolicy" or "updateRolePermissions" or "assignRole" or "revokeRole";
        var receipt = action == "readGovernanceOutcome";
        string route;
        string? source = null;
        if (write)
        {
            route = ValidateGovernanceWrite(body, action);
            source = Text(body, "sourceRef", 64);
        }
        else if (receipt)
        {
            RequireOfficialAnnouncementObject(body, "schemaVersion", "scopeKey", "operationId");
            if (Number(body, "schemaVersion", 1, 1) != 1 || !LowerHex(Text(body, "scopeKey", 64), 64)) throw Invalid();
            _ = OfficialRoleText(body, "operationId", 128);
            route = "receipt-query";
        }
        else
        {
            route = action switch { "readRankPolicy" => "ranks", "readMemberRoles" => "roles/member",
                "readGovernanceAudit" => "audit", _ => throw Invalid() };
            string[] fields = action == "readMemberRoles" ? ["schemaVersion", "sourceRef", "targetSubject"] :
                action == "readGovernanceAudit" ? ["schemaVersion", "sourceRef", "offset"] : ["schemaVersion", "sourceRef"];
            if (body.TryGetProperty("expectedPolicyRevision", out _) && action == "readGovernanceAudit") fields = [.. fields, "expectedPolicyRevision"];
            RequireOfficialAnnouncementObject(body, fields);
            if (Number(body, "schemaVersion", 1, 1) != 1) throw Invalid();
            source = Text(body, "sourceRef", 64);
            if (!OfficialAnnouncementSource(source)) throw Invalid();
            route += "?sourceRef=" + Uri.EscapeDataString(source);
            if (action == "readMemberRoles")
            {
                var subject = Text(body, "targetSubject", 71);
                if (!GovernanceSubject(subject)) throw Invalid();
                route += "&targetSubject=" + Uri.EscapeDataString(subject);
            }
            if (action == "readGovernanceAudit")
            {
                var offset = Number(body, "offset", 0, 8192);
                if (offset % 20 != 0 || offset > 0 && !body.TryGetProperty("expectedPolicyRevision", out _)) throw Invalid();
                route += "&offset=" + offset.ToString(CultureInfo.InvariantCulture);
                if (body.TryGetProperty("expectedPolicyRevision", out _)) route += "&expectedPolicyRevision=" +
                    OfficialAnnouncementRevision(body, "expectedPolicyRevision").ToString(CultureInfo.InvariantCulture);
            }
        }
        using var request = new HttpRequestMessage(write || receipt ? HttpMethod.Post : HttpMethod.Get, new Uri(_origin, GovernancePath + route));
        if (write || receipt) request.Content = JsonContent.Create(body);
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
        var locked = false; var started = false;
        try
        {
            if (write)
            {
                locked = await _write.WaitAsync(0, token);
                if (!locked) throw new AccountBridgeHostException("communities.busy");
            }
            current(); token.ThrowIfCancellationRequested();
            started = write;
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
            current(); token.ThrowIfCancellationRequested();
            var row = await ReadOfficialHangarJson(response, token, 256 * 1024);
            current(); token.ThrowIfCancellationRequested();
            if (write)
            {
                ValidateGovernanceWriteResult(row, response.StatusCode, body);
                return (object)row.Clone();
            }
            if (response.StatusCode != HttpStatusCode.OK) throw new AccountBridgeHostException(response.StatusCode switch
            {
                HttpStatusCode.Unauthorized => "communities.identityUnavailable", HttpStatusCode.Forbidden => "communities.notAllowed",
                HttpStatusCode.NotFound => "communities.upgradeRequired", HttpStatusCode.Conflict => "communities.refreshRequired",
                _ => "communities.unavailable"
            });
            ValidateGovernanceRead(row, action, source, body);
            return (object)row.Clone();
        }
        catch (Exception error) when (write && started && OfficialAnnouncementFailure(error))
        {
            // A transport/shape failure after send is never a safe negative or an automatic retry.
            current(); token.ThrowIfCancellationRequested();
            return (object)JsonSerializer.SerializeToElement(new { schemaVersion = 1, state = "operationOutcomeUnknown",
                operationId = Text(body, "operationId", 128) });
        }
        finally { if (locked) _write.Release(); }
    });

    internal static string ValidateGovernanceWrite(JsonElement body, string action)
    {
        string[] extra = action switch
        {
            "writeRankPolicy" => ["rows"],
            "updateRolePermissions" => ["roleKey", "expectedPermissionVersion", "enabled", "permissions"],
            "assignRole" => ["targetSubject", "expectedTargetMembershipEpoch", "roleKey", "expectedRolePermissionVersion", "parts"],
            "revokeRole" => ["grantId", "expectedGrantVersion"], _ => throw Invalid()
        };
        RequireOfficialAnnouncementObject(body, ["schemaVersion", "sourceRef", "operationId", "expectedPolicyRevision", .. extra]);
        if (Number(body, "schemaVersion", 1, 1) != 1 || !OfficialAnnouncementSource(Text(body, "sourceRef", 64))) throw Invalid();
        _ = OfficialRoleText(body, "operationId", 128); _ = OfficialAnnouncementRevision(body, "expectedPolicyRevision");
        switch (action)
        {
            case "writeRankPolicy": ValidateGovernanceRanks(body); return "ranks/update";
            case "updateRolePermissions":
                _ = OfficialRoleText(body, "roleKey", 256); _ = Number(body, "expectedPermissionVersion", 1, int.MaxValue);
                _ = OfficialRoleFlag(body.GetProperty("enabled")); _ = ParseOfficialRolePermissions(body.GetProperty("permissions"));
                return "roles/permissions";
            case "revokeRole":
                _ = OfficialRoleText(body, "grantId", 256);
                if (OfficialAnnouncementRevision(body, "expectedGrantVersion") < 1) throw Invalid();
                return "roles/revoke";
            default:
                if (!GovernanceSubject(Text(body, "targetSubject", 71))) throw Invalid();
                _ = OfficialRoleText(body, "expectedTargetMembershipEpoch", 128); _ = OfficialRoleText(body, "roleKey", 256);
                _ = Number(body, "expectedRolePermissionVersion", 1, int.MaxValue);
                var parts = Rows(body, "parts", OrganizationCapabilityCatalog.Implemented.Count).ToArray();
                if (parts.Length == 0) throw Invalid();
                var ids = new HashSet<string>(StringComparer.Ordinal); var capabilities = new HashSet<string>(StringComparer.Ordinal);
                foreach (var part in parts)
                {
                    string[] fields = ["grantId", "ceiling", "rootActivationId", "expectedRootVersion"];
                    if (part.TryGetProperty("expiresAt", out var expires))
                    {
                        fields = [.. fields, "expiresAt"];
                        if (expires.ValueKind != JsonValueKind.String || !expires.TryGetDateTimeOffset(out var time) || time.Offset != TimeSpan.Zero) throw Invalid();
                    }
                    RequireOfficialAnnouncementObject(part, fields);
                    if (!ids.Add(OfficialRoleText(part, "grantId", 256)) || OfficialAnnouncementRevision(part, "expectedRootVersion") < 1) throw Invalid();
                    _ = OfficialRoleText(part, "rootActivationId", 256);
                    var rights = ParseOfficialRolePermissions(part.GetProperty("ceiling"));
                    if (rights.Count == 0 || rights.Any(p => !p.CanUse || !capabilities.Add(p.Capability))) throw Invalid();
                }
                return "roles/assign";
        }
    }
    private static bool GovernanceSubject(string subject) => subject.Length == 71 && subject.StartsWith("scm-v1:", StringComparison.Ordinal) &&
        LowerHex(subject[7..], 64);
    private static void ValidateGovernanceRanks(JsonElement body)
    {
        var rows = Rows(body, "rows", 4).ToArray(); var seen = new HashSet<int>();
        foreach (var row in rows)
        {
            RequireOfficialAnnouncementObject(row, "rankValue", "announcements", "rally", "audit");
            if (!seen.Add(Number(row, "rankValue", 2, 5))) throw Invalid();
            foreach (var key in new[] { "announcements", "rally", "audit" }) _ = OfficialRoleFlag(row.GetProperty(key));
        }
        if (seen.Count != 4) throw Invalid();
    }
    private static void ValidateGovernanceWriteResult(JsonElement row, HttpStatusCode status, JsonElement intent)
    {
        var success = status == HttpStatusCode.OK;
        RequireOfficialAnnouncementObject(row, success ? ["schemaVersion", "state", "operationId", "policyRevision", "auditSequence"] :
            ["schemaVersion", "state", "operationId"]);
        if (Number(row, "schemaVersion", 1, 1) != 1 || Text(row, "operationId", 128) != Text(intent, "operationId", 128)) throw Invalid();
        var state = Text(row, "state", 32);
        if (success)
        {
            var expected = OfficialAnnouncementRevision(intent, "expectedPolicyRevision");
            if (expected == long.MaxValue || state is not ("accepted" or "duplicate") || OfficialAnnouncementRevision(row, "policyRevision") != expected + 1 ||
                OfficialAnnouncementRevision(row, "auditSequence") != expected + 1) throw Invalid();
        }
        else if (((int)status, state) is not ((400, "invalid") or (403, "notAllowed") or (409, "conflict") or
            (503, "unavailable") or (503, "storageLimitReached") or (202, "operationOutcomeUnknown"))) throw Invalid();
    }
    private static void ValidateGovernanceRead(JsonElement row, string action, string? source, JsonElement request)
    {
        if (action == "readGovernanceOutcome")
        {
            RequireOfficialAnnouncementObject(row, "schemaVersion", "state", "operationId", "kind", "expectedRevision", "resultRevision", "auditSequence", "timelineRevision");
            if (Number(row, "schemaVersion", 1, 1) != 1 || Text(row, "state", 16) != "found" ||
                Text(row, "operationId", 128) != Text(request, "operationId", 128)) throw Invalid();
            _ = OfficialRoleText(row, "kind", 64);
            var expected = OfficialAnnouncementRevision(row, "expectedRevision");
            if (expected == long.MaxValue || OfficialAnnouncementRevision(row, "resultRevision") != expected + 1 ||
                OfficialAnnouncementRevision(row, "auditSequence") != expected + 1) throw Invalid();
            if (row.GetProperty("timelineRevision").ValueKind != JsonValueKind.Null) _ = OfficialAnnouncementRevision(row, "timelineRevision");
            return;
        }
        string[] common = ["schemaVersion", "state", "sourceRef", "policyRevision"];
        if (action == "readRankPolicy")
        {
            RequireOfficialAnnouncementObject(row, [.. common, "scopeKey", "write", "rows"]);
            if (!LowerHex(Text(row, "scopeKey", 64), 64)) throw Invalid();
            ValidateOfficialRoleDecision(row.GetProperty("write")); ValidateGovernanceRanks(row);
        }
        else if (action == "readMemberRoles")
        {
            RequireOfficialAnnouncementObject(row, [.. common, "targetSubject", "membershipEpoch", "rootActivationId", "rootActivationVersion", "grants"]);
            if (Text(row, "targetSubject", 71) != Text(request, "targetSubject", 71)) throw Invalid();
            _ = OfficialRoleText(row, "membershipEpoch", 128); _ = OfficialRoleText(row, "rootActivationId", 256);
            if (OfficialAnnouncementRevision(row, "rootActivationVersion") < 1) throw Invalid();
            var ids = new HashSet<string>(StringComparer.Ordinal);
            foreach (var grant in Rows(row, "grants", 8192))
            {
                RequireOfficialAnnouncementObject(grant, "grantId", "version", "roleKey", "permissionVersion", "revoked");
                if (!ids.Add(OfficialRoleText(grant, "grantId", 256)) || OfficialAnnouncementRevision(grant, "version") < 1) throw Invalid();
                _ = OfficialRoleText(grant, "roleKey", 256); _ = Number(grant, "permissionVersion", 1, int.MaxValue); _ = OfficialRoleFlag(grant.GetProperty("revoked"));
            }
        }
        else
        {
            string[] fields = [.. common, "offset", "totalCount", "items"];
            if (row.TryGetProperty("nextOffset", out _)) fields = [.. fields, "nextOffset"];
            RequireOfficialAnnouncementObject(row, fields);
            var offset = Number(row, "offset", 0, 8192); var total = Number(row, "totalCount", 0, 8192);
            var rows = Rows(row, "items", 20).ToArray();
            if (offset != Number(request, "offset", 0, 8192) || offset > total || rows.Length != Math.Min(20, total - offset)) throw Invalid();
            int? next = row.TryGetProperty("nextOffset", out var raw) && raw.ValueKind != JsonValueKind.Null ? Number(row, "nextOffset", 0, 8192) : null;
            if (next != (offset + rows.Length < total ? (int?)(offset + rows.Length) : null)) throw Invalid();
            foreach (var item in rows)
            {
                RequireOfficialAnnouncementObject(item, "kind", "occurredAtUtc", "actorDisplay", "targetDisplay");
                _ = OfficialRoleText(item, "kind", 64); _ = OfficialRoleText(item, "actorDisplay", 128); _ = OfficialRoleText(item, "targetDisplay", 128);
                if (item.GetProperty("occurredAtUtc").ValueKind != JsonValueKind.String || !item.GetProperty("occurredAtUtc").TryGetDateTimeOffset(out var time) || time.Offset != TimeSpan.Zero) throw Invalid();
            }
        }
        if (Number(row, "schemaVersion", 1, 1) != 1 || Text(row, "state", 16) != "available" || Text(row, "sourceRef", 64) != source) throw Invalid();
        var revision = OfficialAnnouncementRevision(row, "policyRevision");
        if (request.TryGetProperty("expectedPolicyRevision", out _) && OfficialAnnouncementRevision(request, "expectedPolicyRevision") != revision) throw Invalid();
    }
}
