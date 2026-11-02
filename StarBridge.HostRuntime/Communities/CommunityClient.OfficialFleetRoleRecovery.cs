using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    internal async Task<object> ReadOfficialRoleTemplateOutcomeAsync(string bearer, JsonElement body, string accountKey,
        Action current, CancellationToken token)
    {
        Validate(body, "kind", "offset", "requestId");
        var kind = Text(body, "kind", 16);
        if (kind is not ("pending" or "query")) throw Invalid();
        RequireOfficialAnnouncementObject(body, kind == "pending" ? ["schemaVersion", "kind", "offset"] : ["schemaVersion", "kind", "requestId"]);
        var offset = kind == "pending" ? Number(body, "offset", 0, 127) : 0;
        var requestId = kind == "query" ? Text(body, "requestId", 32) : "";
        if (offset % 20 != 0 || kind == "query" && !LowerHex(requestId, 32)) throw Invalid();
        if (!await _write.WaitAsync(0, token)) throw new AccountBridgeHostException("communities.busy");
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token); deadline.CancelAfter(TimeSpan.FromSeconds(12));
        try
        {
            return await _announcementJournal.Value.RunAsync<object>(accountKey, _origin, async journal =>
            {
                current(); deadline.Token.ThrowIfCancellationRequested();
                if (kind == "pending")
                {
                    var all = journal.RoleItems.Where(r => r.Phase is "prepared" or "sendStarted" or "unknown")
                        .OrderByDescending(r => r.RequestedAt).ThenBy(r => r.RequestId, StringComparer.Ordinal).ToArray();
                    if (offset > all.Length) throw Invalid();
                    return JsonSerializer.SerializeToElement(new
                    {
                        schemaVersion = 1,
                        kind,
                        offset,
                        totalCount = all.Length,
                        next = offset + 20 < all.Length ? (int?)(offset + 20) : null,
                        items = all.Skip(offset).Take(20).Select(r => new { r.RequestId, r.Intent.SourceRef, r.Intent.Action, r.RequestedAt, status = "unknown" }).ToArray()
                    }, new JsonSerializerOptions(JsonSerializerDefaults.Web));
                }
                var row = journal.FindRole(requestId);
                if (row is null) return new { schemaVersion = 1, kind, requestId, status = "unknown", error = "notFound" };
                object Receipt(OfficialRoleWriteResult result) => JsonSerializer.SerializeToElement(new
                {
                    schemaVersion = 1,
                    kind,
                    requestId,
                    row.Intent.SourceRef,
                    row.Intent.Action,
                    status = result.Status,
                    error = result.Error,
                    revision = result.Revision
                }, new JsonSerializerOptions(JsonSerializerDefaults.Web));
                if (row.Phase is "accepted" or "rejected") return Receipt(OfficialRoleResult(row));
                try
                {
                    using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(_origin, "/api/official-fleets/governance/receipt-query"))
                    { Content = JsonContent.Create(new { schemaVersion = 1, scopeKey = row.Intent.ScopeKey, operationId = row.OperationId }) };
                    request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
                    current(); deadline.Token.ThrowIfCancellationRequested();
                    using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
                    current(); deadline.Token.ThrowIfCancellationRequested();
                    if (response.StatusCode != HttpStatusCode.OK) return Receipt(new("unknown", "outcomeUnknown"));
                    var root = await ReadOfficialHangarJson(response, deadline.Token, 4096);
                    RequireOfficialAnnouncementObject(root, "schemaVersion", "state", "operationId", "kind", "expectedRevision", "resultRevision", "auditSequence", "timelineRevision");
                    if (Number(root, "schemaVersion", 1, 1) != 1 || Text(root, "state", 16) != "found" ||
                        Text(root, "operationId", 128) != row.OperationId || Text(root, "kind", 64) != AnnouncementAttemptJournal.RoleKind(row.Intent.Action) ||
                        OfficialAnnouncementRevision(root, "expectedRevision") != row.Intent.PolicyRevision || row.Intent.PolicyRevision == long.MaxValue ||
                        OfficialAnnouncementRevision(root, "resultRevision") != row.Intent.PolicyRevision + 1 ||
                        OfficialAnnouncementRevision(root, "auditSequence") != row.Intent.PolicyRevision + 1 || root.GetProperty("timelineRevision").ValueKind != JsonValueKind.Null) throw Invalid();
                    var saved = row with { Phase = "accepted", Error = null, Receipt = new(row.Intent.PolicyRevision + 1, row.Intent.PolicyRevision + 1) };
                    current(); deadline.Token.ThrowIfCancellationRequested();
                    await journal.SaveRoleAsync(saved);
                    return Receipt(OfficialRoleResult(saved));
                }
                catch (Exception error) when (OfficialAnnouncementFailure(error)) { return Receipt(new("unknown", "outcomeUnknown")); }
            }, current, deadline.Token);
        }
        catch (Exception error) when (OfficialAnnouncementFailure(error)) { throw new AccountBridgeHostException("communities.localRecoveryUnavailable"); }
        finally { _write.Release(); }
    }
}
