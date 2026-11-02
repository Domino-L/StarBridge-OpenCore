using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text.Json;
using StarBridge.Core.Organizations;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    private sealed record OfficialRoleBridgeIntent(string SourceRef, string EditRef, string RequestId, string Action,
        string? RoleRef, OfficialRoleMetadataValue Metadata, IReadOnlyList<OrganizationCapabilityPermission>? Permissions);
    private sealed record OfficialRoleWriteResult(string Status, string? Error = null, long? Revision = null);
    private static string OfficialRoleBridgeFingerprint(OfficialRoleBridgeIntent intent) => Convert.ToHexString(SHA256.HashData(
        JsonSerializer.SerializeToUtf8Bytes(new
        {
            Domain = "StarBridge.OfficialRole.BridgeIntent.v1",
            intent.SourceRef,
            intent.EditRef,
            intent.Action,
            intent.RoleRef,
            intent.Metadata,
            intent.Permissions
        }, AnnouncementJson))).ToLowerInvariant();

    internal async Task<object> ManageOfficialRoleTemplatesAsync(string bearer, JsonElement body, string accountKey,
        string accountScope, Action current, CancellationToken token)
    {
        var intent = ParseOfficialRoleBridgeIntent(body);
        object Receipt(OfficialRoleWriteResult result) => JsonSerializer.SerializeToElement(new
        {
            schemaVersion = 1,
            intent.SourceRef,
            intent.EditRef,
            intent.RequestId,
            intent.Action,
            status = result.Status,
            error = result.Error,
            revision = result.Revision
        }, new JsonSerializerOptions(JsonSerializerDefaults.Web));
        if (!await _write.WaitAsync(0, token)) return Receipt(new("rejected", "busy"));
        var started = false;
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token); deadline.CancelAfter(TimeSpan.FromSeconds(12));
        try
        {
            var result = await _announcementJournal.Value.RunAsync(accountKey, _origin, async journal =>
            {
                current(); deadline.Token.ThrowIfCancellationRequested();
                var bridgeHash = OfficialRoleBridgeFingerprint(intent);
                if (journal.FindRole(intent.RequestId) is { } prior)
                {
                    started = prior.Phase is "sendStarted" or "unknown" or "accepted";
                    return prior.BridgeFingerprint == bridgeHash ? OfficialRoleResult(prior) : new OfficialRoleWriteResult("rejected", "intentConflict");
                }
                if (!_officialRolePages.TryGetValue(intent.EditRef, out var edit) || edit.AccountScope != accountScope ||
                    edit.SourceRef != intent.SourceRef || edit.Expires <= _targetClock.GetUtcNow()) return new OfficialRoleWriteResult("rejected", "refreshRequired");
                OfficialRole? role = null;
                if (intent.Action == "metadata" && (intent.RoleRef is null || !edit.Rows.TryGetValue(intent.RoleRef, out role)))
                    return new OfficialRoleWriteResult("rejected", "rolesChanged");
                var operation = AnnouncementAttemptJournal.RoleOperationId(accountKey, _origin, intent.RequestId);
                var command = new OfficialRoleJournalIntent(intent.SourceRef, edit.ScopeKey, edit.AuthorityBinding, intent.Action,
                    edit.PolicyRevision, role?.Key ?? "bridge-role:" + operation, role?.PermissionVersion, role?.MetadataRevision, intent.Metadata, intent.Permissions);
                var record = new OfficialRoleJournalRecord(intent.RequestId, operation, command, AnnouncementAttemptJournal.RoleFingerprint(command),
                    bridgeHash, _targetClock.GetUtcNow(), "prepared");
                await journal.SaveRoleAsync(record);
                OfficialRolePage fresh;
                try { fresh = await FetchOfficialRoleTemplatesAsync(bearer, intent.SourceRef, accountScope, edit.Offset, edit.PolicyRevision, current, deadline.Token); }
                catch (Exception error) when (OfficialAnnouncementFailure(error))
                {
                    RetireOfficialRolePages(accountScope, intent.SourceRef);
                    current(); deadline.Token.ThrowIfCancellationRequested();
                    record = record with { Phase = "rejected", Error = "refreshRequired" };
                    await journal.SaveRoleAsync(record); return OfficialRoleResult(record);
                }
                current(); deadline.Token.ThrowIfCancellationRequested();
                bool EditCurrent() => _officialRolePages.TryGetValue(intent.EditRef, out var active) && active == edit;
                var freshRole = role is null ? null : fresh.Rows.Values.SingleOrDefault(r => r.Key == role.Key);
                if (!EditCurrent() || fresh.ScopeKey != edit.ScopeKey || fresh.AuthorityBinding != edit.AuthorityBinding ||
                    fresh.PolicyRevision != edit.PolicyRevision || role is not null && !OfficialRoleEqual(role, freshRole))
                {
                    RetireOfficialRolePages(accountScope, intent.SourceRef);
                    record = record with { Phase = "rejected", Error = "rolesChanged" };
                    await journal.SaveRoleAsync(record); return OfficialRoleResult(record);
                }
                var permission = Text(fresh.Access.GetProperty(intent.Action == "create" ? "create" : "updateMetadata"), "state", 16);
                if (permission == "allowed" && intent.Permissions is not null)
                {
                    foreach (var right in intent.Permissions.Where(right => right.CanUse))
                    {
                        var decision = fresh.CreationCapabilities.EnumerateArray().Single(value => Text(value, "capability", 64) == right.Capability);
                        var state = Text(decision, "state", 16);
                        if (state != "allowed") { permission = state; break; }
                    }
                }
                if (permission != "allowed")
                {
                    RetireOfficialRolePages(accountScope, intent.SourceRef);
                    record = record with { Phase = "rejected", Error = permission == "denied" ? "notAllowed" : "unavailable" };
                    await journal.SaveRoleAsync(record); return OfficialRoleResult(record);
                }
                using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(_origin,
                    intent.Action == "create" ? "/api/official-fleets/governance/roles/create" : "/api/official-fleets/governance/roles/metadata"))
                { Content = JsonContent.Create(OfficialRoleCommand(record)) };
                request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
                record = record with { Phase = "sendStarted" };
                await journal.SaveRoleAsync(record);
                started = true; // Durable before the only possible positive HTTP call, including an OAuth callback retry.
                current(); deadline.Token.ThrowIfCancellationRequested();
                if (!EditCurrent()) throw new AccountBridgeHostException("communities.refreshRequired");
                using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
                current(); deadline.Token.ThrowIfCancellationRequested();
                var outcome = await DecodeOfficialRoleWriteAsync(response, record, deadline.Token);
                current(); deadline.Token.ThrowIfCancellationRequested();
                var saved = outcome.Status switch
                {
                    "accepted" => record with { Phase = "accepted", Receipt = new(command.PolicyRevision + 1, command.PolicyRevision + 1) },
                    "rejected" => record with { Phase = "rejected", Error = outcome.Error },
                    _ => record with { Phase = "unknown", Error = "outcomeUnknown" }
                };
                await journal.SaveRoleAsync(saved);
                RetireOfficialRolePages(accountScope, intent.SourceRef);
                return OfficialRoleResult(saved);
            }, current, deadline.Token);
            current(); deadline.Token.ThrowIfCancellationRequested(); return Receipt(result);
        }
        catch (Exception error) when (OfficialAnnouncementFailure(error))
        { return Receipt(new(started ? "unknown" : "rejected", started ? "outcomeUnknown" : "localRecoveryUnavailable")); }
        finally { _write.Release(); }
    }
    private static bool OfficialRoleEqual(OfficialRole left, OfficialRole? right) => right is not null && left.Key == right.Key &&
        left.PermissionVersion == right.PermissionVersion && left.MetadataRevision == right.MetadataRevision && left.Enabled == right.Enabled &&
        left.Metadata == right.Metadata && left.Permissions.SequenceEqual(right.Permissions);
    private static OfficialRoleWriteResult OfficialRoleResult(OfficialRoleJournalRecord row) => row.Phase switch
    {
        "accepted" when row.Receipt is { } receipt => new("accepted", Revision: receipt.PolicyRevision),
        "accepted" => throw new InvalidDataException("Missing role receipt."),
        "rejected" => new("rejected", row.Error),
        _ => new("unknown", "outcomeUnknown")
    };
    private static Dictionary<string, object?> OfficialRoleCommand(OfficialRoleJournalRecord row)
    {
        var intent = row.Intent;
        var body = new Dictionary<string, object?>
        {
            ["schemaVersion"] = 1,
            ["sourceRef"] = intent.SourceRef,
            ["operationId"] = row.OperationId,
            ["expectedPolicyRevision"] = intent.PolicyRevision,
            ["roleKey"] = intent.RoleKey,
            ["displayName"] = intent.Metadata.DisplayName,
            ["description"] = intent.Metadata.Description,
            ["color"] = intent.Metadata.Color,
            ["sortOrder"] = intent.Metadata.SortOrder
        };
        if (intent.Action == "create") body["permissions"] = intent.Permissions;
        else { body["expectedMetadataRevision"] = intent.ExpectedMetadataRevision; body["expectedPermissionVersion"] = intent.ExpectedPermissionVersion; }
        return body;
    }
    private static async Task<OfficialRoleWriteResult> DecodeOfficialRoleWriteAsync(HttpResponseMessage response, OfficialRoleJournalRecord row, CancellationToken token)
    {
        try
        {
            var root = await ReadOfficialHangarJson(response, token, 4096);
            if (response.StatusCode == HttpStatusCode.OK)
            {
                RequireOfficialAnnouncementObject(root, "schemaVersion", "state", "operationId", "policyRevision", "auditSequence");
                if (Number(root, "schemaVersion", 1, 1) != 1 || Text(root, "operationId", 128) != row.OperationId ||
                    Text(root, "state", 32) is not ("accepted" or "duplicate") || row.Intent.PolicyRevision == long.MaxValue ||
                    OfficialAnnouncementRevision(root, "policyRevision") != row.Intent.PolicyRevision + 1 ||
                    OfficialAnnouncementRevision(root, "auditSequence") != row.Intent.PolicyRevision + 1) throw Invalid();
                return new("accepted", Revision: row.Intent.PolicyRevision + 1);
            }
            RequireOfficialAnnouncementObject(root, "schemaVersion", "state", "operationId");
            if (Number(root, "schemaVersion", 1, 1) != 1 || Text(root, "operationId", 128) != row.OperationId) throw Invalid();
            return ((int)response.StatusCode, Text(root, "state", 32)) switch
            {
                (400, "invalid") => new("rejected", "dataInvalid"),
                (403, "notAllowed") => new("rejected", "notAllowed"),
                (409, "conflict") => new("rejected", "rolesChanged"),
                (503, "storageLimitReached") => new("rejected", "unavailable"),
                _ => new("unknown", "outcomeUnknown")
            };
        }
        catch (Exception error) when (OfficialAnnouncementFailure(error)) { return new("unknown", "outcomeUnknown"); }
    }
    private static OfficialRoleBridgeIntent ParseOfficialRoleBridgeIntent(JsonElement body)
    {
        Validate(body, "sourceRef", "editRef", "requestId", "action", "roleRef", "metadata", "permissions");
        var source = Text(body, "sourceRef", 64); var edit = Text(body, "editRef", 32);
        var request = Text(body, "requestId", 32); var action = Text(body, "action", 16);
        if (!OfficialAnnouncementSource(source) || !LowerHex(edit, 32) || !LowerHex(request, 32) || action is not ("create" or "metadata")) throw Invalid();
        RequireOfficialAnnouncementObject(body, action == "create"
            ? ["schemaVersion", "sourceRef", "editRef", "requestId", "action", "metadata", "permissions"]
            : ["schemaVersion", "sourceRef", "editRef", "requestId", "action", "metadata", "roleRef"]);
        var role = action == "metadata" ? Text(body, "roleRef", 32) : null;
        if (role is not null && !LowerHex(role, 32)) throw Invalid();
        return new(source, edit, request, action, role, ParseOfficialRoleMetadata(body.GetProperty("metadata")),
            action == "create" ? ParseOfficialRolePermissions(body.GetProperty("permissions")) : null);
    }
}
