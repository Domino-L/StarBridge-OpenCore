using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    internal static string ValidateGovernanceActivation(JsonElement body)
    {
        try
        {
            Validate(body, "sourceRef", "operationId", "expectedPolicyRevision");
            if (body.EnumerateObject().Count() != 4 || Encoding.UTF8.GetByteCount(body.GetRawText()) > 2048) throw Invalid();
            var source = Text(body, "sourceRef", 64);
            var operation = Text(body, "operationId", 128);
            if (!OfficialAnnouncementSource(source) || operation.Length == 0 || operation.Trim() != operation) throw Invalid();
            _ = OfficialAnnouncementRevision(body, "expectedPolicyRevision");
            return source;
        }
        catch (Exception error) when (error is JsonException or InvalidOperationException or KeyNotFoundException or FormatException or OverflowException)
        { throw Invalid(); }
    }

    internal async Task<object> WriteGovernanceActivationAsync(string bearer, JsonElement body, bool activate,
        Action current, CancellationToken token, Action<string, int?>? diagnostic = null)
    {
        var started = System.Diagnostics.Stopwatch.GetTimestamp();
        var code = "data-invalid";
        int? status = null;
        void Observe(string value, int? httpStatus) { code = value; status = httpStatus ?? status; }
        try { return await WriteGovernanceActivationCoreAsync(bearer, body, activate, current, token, Observe); }
        finally
        {
            try
            {
                if (diagnostic is not null) diagnostic(code, status);
                else ReadDiagnostic?.Invoke("official-governance-activation", code, status,
                    (long)System.Diagnostics.Stopwatch.GetElapsedTime(started).TotalMilliseconds);
            }
            catch { /* Preserve the original outcome, including uncertain writes. */ }
        }
    }

    private async Task<object> WriteGovernanceActivationCoreAsync(string bearer, JsonElement body, bool activate,
        Action current, CancellationToken token, Action<string, int?> observe)
    {
        var source = ValidateGovernanceActivation(body);
        var operation = Text(body, "operationId", 128);
        object Outcome(string state, long? revision = null, long? audit = null)
        {
            var row = new Dictionary<string, object?> { ["schemaVersion"] = 1, ["sourceRef"] = source,
                ["operationId"] = operation, ["state"] = state };
            if (revision.HasValue) row["policyRevision"] = revision.Value;
            if (audit.HasValue) row["auditSequence"] = audit.Value;
            return JsonSerializer.SerializeToElement(row);
        }
        using var request = new HttpRequestMessage(HttpMethod.Post,
            new Uri(_origin, "/api/official-fleets/governance/activation/" + (activate ? "activate" : "revoke")))
        { Content = new StringContent(body.GetRawText(), Encoding.UTF8, "application/json") };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
        observe("not-sent", null);
        current(); token.ThrowIfCancellationRequested();
        try
        {
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
            observe("unclassified", (int)response.StatusCode);
            current();
            var fallback = response.StatusCode switch
            {
                HttpStatusCode.BadRequest => "invalid",
                HttpStatusCode.Unauthorized => "identityUnavailable",
                HttpStatusCode.Forbidden => "notAllowed",
                HttpStatusCode.Conflict => "conflict",
                HttpStatusCode.NotFound or HttpStatusCode.MethodNotAllowed or HttpStatusCode.ServiceUnavailable => "unavailable",
                _ => "outcomeUnknown"
            };
            JsonElement row;
            try
            {
                row = await ReadOfficialHangarJson(response, token, 4096);
                try
                {
                    var value = row.ValueKind == JsonValueKind.Object &&
                        (row.TryGetProperty("state", out var state) || row.TryGetProperty("code", out state)) &&
                        state.ValueKind == JsonValueKind.String ? state.GetString() : null;
                    observe(value is "accepted" or "duplicate" or "invalid" or "identityUnavailable" or "notAllowed" or
                        "conflict" or "unavailable" or "storageLimitReached" or "operationOutcomeUnknown"
                        ? value : "unclassified", (int)response.StatusCode);
                }
                catch { observe("unclassified", (int)response.StatusCode); }
            }
            catch (Exception error) when (error is JsonException or AccountBridgeHostException) { current(); return Outcome(fallback); }
            current();
            try
            {
                var keys = row.EnumerateObject().Select(p => p.Name).ToArray();
                if (keys.Distinct(StringComparer.Ordinal).Count() != keys.Length ||
                    keys.Any(k => k is not ("schemaVersion" or "state" or "operationId" or "policyRevision" or "auditSequence")) ||
                    Number(row, "schemaVersion", 1, 1) != 1) return Outcome(fallback);
                var state = Text(row, "state", 32);
                if (row.TryGetProperty("operationId", out _) && Text(row, "operationId", 128) != operation) return Outcome("outcomeUnknown");
                var mapped = (response.StatusCode, state) switch
                {
                    (HttpStatusCode.OK, "accepted" or "duplicate") => state,
                    (HttpStatusCode.BadRequest, "invalid") => state,
                    (HttpStatusCode.Unauthorized, "identityUnavailable") => state,
                    (HttpStatusCode.Forbidden, "notAllowed") => state,
                    (HttpStatusCode.Conflict, "conflict") => state,
                    (HttpStatusCode.ServiceUnavailable, "unavailable" or "storageLimitReached") => state,
                    (HttpStatusCode.Accepted, "operationOutcomeUnknown") => "outcomeUnknown",
                    _ => fallback
                };
                long? revision = row.TryGetProperty("policyRevision", out _) ? OfficialAnnouncementRevision(row, "policyRevision") : null;
                long? audit = row.TryGetProperty("auditSequence", out _) ? OfficialAnnouncementRevision(row, "auditSequence") : null;
                if (mapped is "accepted" or "duplicate" && (revision is null || audit is null || !row.TryGetProperty("operationId", out _)))
                    return Outcome("outcomeUnknown");
                return Outcome(mapped, revision, audit);
            }
            catch (Exception error) when (error is JsonException or AccountBridgeHostException or InvalidOperationException or KeyNotFoundException or FormatException or OverflowException)
            { return Outcome(fallback); }
        }
        catch (Exception error) when (error is HttpRequestException or IOException or OperationCanceledException)
        {
            observe(error is OperationCanceledException ? "timeout" : "transient", null);
            current(); // Account retirement is still a stale request, never an outcome for the new owner.
            return Outcome("outcomeUnknown");
        }
    }
}
