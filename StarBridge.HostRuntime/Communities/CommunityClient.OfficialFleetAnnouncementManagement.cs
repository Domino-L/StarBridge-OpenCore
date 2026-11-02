using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text.Json;
using StarBridge.Core.FleetAnnouncements;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    private sealed record OfficialAnnouncementIntent(string SourceRef, string EditRef, string RequestId, string Action,
        string? AnnouncementRef, string? Title, string? Content);
    private static string OfficialBridgeFingerprint(OfficialAnnouncementIntent intent) => Convert.ToHexString(SHA256.HashData(
        JsonSerializer.SerializeToUtf8Bytes(new
        {
            Domain = "StarBridge.OfficialAnnouncement.BridgeIntent.v1",
            intent.SourceRef,
            intent.EditRef,
            intent.Action,
            intent.AnnouncementRef,
            intent.Title,
            intent.Content
        }, AnnouncementJson))).ToLowerInvariant();

    internal async Task<object> ManageOfficialAnnouncementsAsync(string bearer, JsonElement body, string accountKey,
        string accountScope, Action current, CancellationToken token)
    {
        var intent = ParseOfficialAnnouncementIntent(body);
        object Receipt(AnnouncementWriteResult result) => new
        {
            schemaVersion = 1,
            intent.SourceRef,
            intent.EditRef,
            intent.RequestId,
            intent.Action,
            status = result.Status,
            error = result.Error,
            revision = result.Revision
        };
        if (!await _write.WaitAsync(0, token)) return Receipt(new("rejected", "busy"));
        var started = false;
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
        deadline.CancelAfter(TimeSpan.FromSeconds(12));
        try
        {
            var result = await _announcementJournal.Value.RunAsync(accountKey, _origin, async journal =>
            {
                current(); deadline.Token.ThrowIfCancellationRequested();
                var bridgeHash = OfficialBridgeFingerprint(intent);
                if (journal.Find(intent.RequestId) is { } prior)
                {
                    started = prior.Phase is "sendStarted" or "unknown" or "accepted";
                    return prior.BridgeFingerprint == bridgeHash ? OfficialAnnouncementResult(prior) : new AnnouncementWriteResult("rejected", "intentConflict");
                }
                if (!_officialAnnouncementEdits.TryGetValue(intent.EditRef, out var edit) || edit.AccountScope != accountScope ||
                    edit.SourceRef != intent.SourceRef || edit.Expires <= _targetClock.GetUtcNow()) return new AnnouncementWriteResult("rejected", "refreshRequired");
                if (intent.Action != "publish" && (edit.Item is null || edit.ItemRef != intent.AnnouncementRef))
                    return new AnnouncementWriteResult("rejected", "announcementsChanged");
                var command = new AnnouncementJournalIntent(intent.SourceRef, edit.ScopeKey, edit.AuthorityBinding, intent.Action,
                    edit.PolicyRevision, edit.TimelineRevision, intent.Action == "publish" ? null : edit.Item?.Id,
                    intent.Action == "publish" ? null : edit.Item?.Revision, intent.Title, intent.Content);
                var record = new AnnouncementJournalRecord(intent.RequestId, AnnouncementAttemptJournal.OperationId(accountKey, _origin, intent.RequestId),
                    command, AnnouncementAttemptJournal.Fingerprint(command), bridgeHash, _targetClock.GetUtcNow(), "prepared");
                await journal.SaveAsync(record);
                OfficialAnnouncementEdit fresh;
                try { fresh = await FetchOfficialAnnouncementEditorAsync(bearer, intent.SourceRef, accountScope, current, deadline.Token); }
                catch (Exception error) when (OfficialAnnouncementFailure(error))
                {
                    _officialAnnouncementEdits.TryRemove(intent.EditRef, out _);
                    current(); deadline.Token.ThrowIfCancellationRequested();
                    record = record with { Phase = "rejected", Error = "refreshRequired" };
                    await journal.SaveAsync(record);
                    return OfficialAnnouncementResult(record);
                }
                current(); deadline.Token.ThrowIfCancellationRequested();
                bool EditCurrent() => _officialAnnouncementEdits.TryGetValue(intent.EditRef, out var active) && active == edit;
                if (!EditCurrent() || fresh.ScopeKey != edit.ScopeKey || fresh.AuthorityBinding != edit.AuthorityBinding ||
                    fresh.PolicyRevision != edit.PolicyRevision || fresh.TimelineRevision != edit.TimelineRevision || fresh.Item != edit.Item)
                {
                    _officialAnnouncementEdits.TryRemove(intent.EditRef, out _);
                    record = record with { Phase = "rejected", Error = "announcementsChanged" };
                    await journal.SaveAsync(record);
                    return OfficialAnnouncementResult(record);
                }
                using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(_origin,
                    "/api/official-fleets/announcements/" + intent.Action))
                { Content = JsonContent.Create(OfficialAnnouncementCommand(record)) };
                request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
                record = record with { Phase = "sendStarted" };
                await journal.SaveAsync(record); // Durable before any positive HTTP starts.
                started = true;
                current(); deadline.Token.ThrowIfCancellationRequested();
                if (!EditCurrent()) throw new AccountBridgeHostException("communities.refreshRequired");
                // Anything after this observation is conservatively uncertain.
                using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
                current(); deadline.Token.ThrowIfCancellationRequested();
                var outcome = await DecodeOfficialAnnouncementWriteAsync(response, record, deadline.Token);
                current(); deadline.Token.ThrowIfCancellationRequested();
                if (outcome.Status == "accepted" && outcome.Revision is null) throw Invalid();
                var saved = outcome.Status switch
                {
                    "accepted" => record with { Phase = "accepted", Receipt = new(command.PolicyRevision + 1, outcome.Revision.GetValueOrDefault(), command.PolicyRevision + 1) },
                    "rejected" => record with { Phase = "rejected", Error = outcome.Error },
                    _ => record with { Phase = "unknown", Error = "outcomeUnknown" }
                };
                await journal.SaveAsync(saved);
                if (saved.Phase == "accepted") _officialAnnouncementEdits.TryRemove(intent.EditRef, out _);
                return OfficialAnnouncementResult(saved);
            }, current, deadline.Token);
            current(); deadline.Token.ThrowIfCancellationRequested();
            return Receipt(result);
        }
        catch (Exception error) when (OfficialAnnouncementFailure(error))
        {
            // Includes ScmApiAuthenticationException (an HttpRequestException):
            // never let OAuth's callback retry perform a second POST.
            return Receipt(new(started ? "unknown" : "rejected", started ? "outcomeUnknown" : "localRecoveryUnavailable"));
        }
        finally { _write.Release(); }
    }

    private static bool OfficialAnnouncementFailure(Exception error) => error is HttpRequestException or IOException or InvalidDataException or
        UnauthorizedAccessException or CryptographicException or OperationCanceledException or JsonException or InvalidOperationException or
        KeyNotFoundException or FormatException or OverflowException or AccountBridgeHostException or StarBridge.NativeBridge.BridgeStaleGenerationException;

    private static AnnouncementWriteResult OfficialAnnouncementResult(AnnouncementJournalRecord row) => row.Phase switch
    {
        "accepted" when row.Receipt is { } receipt => new("accepted", Revision: receipt.TimelineRevision),
        "accepted" => throw new InvalidDataException("Missing confirmed receipt."),
        "rejected" => new("rejected", row.Error),
        _ => new("unknown", "outcomeUnknown")
    };

    private static Dictionary<string, object?> OfficialAnnouncementCommand(AnnouncementJournalRecord row)
    {
        var intent = row.Intent;
        var body = new Dictionary<string, object?>
        {
            ["schemaVersion"] = 1,
            ["sourceRef"] = intent.SourceRef,
            ["operationId"] = row.OperationId,
            ["expectedPolicyRevision"] = intent.PolicyRevision,
            ["expectedTimelineRevision"] = intent.TimelineRevision
        };
        if (intent.Action != "publish") { body["announcementId"] = intent.AnnouncementId; body["expectedItemRevision"] = intent.ItemRevision; }
        if (intent.Action != "withdraw") { body["title"] = intent.Title; body["content"] = intent.Content; }
        return body;
    }

    private static async Task<AnnouncementWriteResult> DecodeOfficialAnnouncementWriteAsync(HttpResponseMessage response,
        AnnouncementJournalRecord row, CancellationToken token)
    {
        try
        {
            var root = await ReadOfficialHangarJson(response, token, 4096);
            if (response.StatusCode == HttpStatusCode.OK)
            {
                RequireOfficialAnnouncementObject(root, "schemaVersion", "state", "operationId", "policyRevision", "timelineRevision", "auditSequence");
                if (Number(root, "schemaVersion", 1, 1) != 1 || Text(root, "operationId", 128) != row.OperationId ||
                    Text(root, "state", 32) is not ("accepted" or "duplicate")) throw Invalid();
                var policy = OfficialAnnouncementRevision(root, "policyRevision");
                var timeline = OfficialAnnouncementRevision(root, "timelineRevision");
                if (row.Intent.PolicyRevision == long.MaxValue || row.Intent.TimelineRevision == long.MaxValue ||
                    policy != row.Intent.PolicyRevision + 1 || timeline != row.Intent.TimelineRevision + 1 ||
                    OfficialAnnouncementRevision(root, "auditSequence") != policy) throw Invalid();
                return new("accepted", Revision: timeline);
            }
            RequireOfficialAnnouncementObject(root, "schemaVersion", "state", "operationId");
            if (Number(root, "schemaVersion", 1, 1) != 1 || Text(root, "operationId", 128) != row.OperationId) throw Invalid();
            // A naked HTTP status, proxy body, unknown reason or malformed acknowledgement
            // cannot prove the original operation did not commit.
            return ((int)response.StatusCode, Text(root, "state", 32)) switch
            {
                (400, "invalid") => new("rejected", "dataInvalid"),
                (403, "notAllowed") => new("rejected", "notAllowed"),
                (409, "conflict") => new("rejected", "announcementsChanged"),
                (503, "storageLimitReached") => new("rejected", "unavailable"),
                _ => new("unknown", "outcomeUnknown")
            };
        }
        catch (Exception error) when (OfficialAnnouncementFailure(error)) { return new("unknown", "outcomeUnknown"); }
    }

    private static OfficialAnnouncementIntent ParseOfficialAnnouncementIntent(JsonElement body)
    {
        Validate(body, "sourceRef", "editRef", "requestId", "action", "announcementRef", "title", "content");
        var source = Text(body, "sourceRef", 64); var edit = Text(body, "editRef", 32);
        var id = Text(body, "requestId", 32); var action = Text(body, "action", 16);
        if (!OfficialAnnouncementSource(source) || !LowerHex(edit, 32) || !LowerHex(id, 32) ||
            action is not ("publish" or "edit" or "withdraw")) throw Invalid();
        var reference = Optional(body, "announcementRef", 32);
        if (action == "publish" && body.TryGetProperty("announcementRef", out _) ||
            action != "publish" && (reference is null || !LowerHex(reference, 32))) throw Invalid();
        if (action == "withdraw")
        {
            if (body.TryGetProperty("title", out _) || body.TryGetProperty("content", out _)) throw Invalid();
            return new(source, edit, id, action, reference, null, null);
        }
        var normalized = FleetAnnouncementPolicy.Normalize(Text(body, "title", 48), Text(body, "content", 1200, true));
        return normalized.Error is null ? new(source, edit, id, action, reference, normalized.Title, normalized.Content) : throw Invalid();
    }
}
