using System.Net;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StarBridge.Core.TrustSafety;
using StarBridge.HostRuntime.Account;
namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    private sealed record OfficialShipReportContext(string AccountScope, string RequestId, string TargetRef, string ShipRef);
    private static string OfficialReportKey(string scope, string requestId) => Convert.ToHexString(SHA256.HashData(
        Encoding.UTF8.GetBytes("StarBridge.OfficialFleet.ShipImage.Report.v1\n" + scope + "\n" + requestId)))[..32].ToLowerInvariant();
    private static object OfficialReportReceipt(OfficialShipReportContext context, ShipReportResult result) => new
    {
        schemaVersion = 1,
        targetRef = context.TargetRef,
        shipRef = context.ShipRef,
        requestId = context.RequestId,
        status = result.Status,
        error = result.Error
    };

    internal async Task<object> ReportOfficialShipImageAsync(string bearer, JsonElement body, string accountScope,
        Action current, TimeProvider clock, CancellationToken token)
    {
        Validate(body, "targetRef", "shipRef", "version", "requestId", "reason", "details");
        var reference = Text(body, "targetRef", 32); var shipRef = Text(body, "shipRef", 32); var requestId = Text(body, "requestId", 32);
        var version = Text(body, "version", 64); var reason = Text(body, "reason", 32).Trim().ToLowerInvariant(); var details = Text(body, "details", 1000, true).Trim();
        if (!LowerHex(reference, 32) || !LowerHex(shipRef, 32) || !LowerHex(requestId, 32) || !ShipHash(version) || !ReportReasons.IsSupported(reason)) throw Invalid();
        var context = new OfficialShipReportContext(accountScope, requestId, reference, shipRef);
        var key = OfficialReportKey(accountScope, requestId);
        var fingerprint = Convert.ToHexString(SHA256.HashData(JsonSerializer.SerializeToUtf8Bytes(new { reference, shipRef, version, reason, details })));
        if (!await _write.WaitAsync(0, token)) return OfficialReportReceipt(context, new("rejected", "busy"));
        var sent = false;
        try
        {
            current(); token.ThrowIfCancellationRequested();
            if (_shipReportAttempts.TryGetValue(key, out var prior))
                return OfficialReportReceipt(context, prior.Official != context || prior.Fingerprint != fingerprint ? new("rejected", "intentConflict") : prior.Result);
            var bound = LookupOfficialShipImage(body, accountScope, clock, report: true);
            if (bound.Version != version) return OfficialReportReceipt(context, new("rejected", "mediaChanged"));
            foreach (var old in _shipReportAttempts.Where(p => p.Value.Result.Status != "unknown" && p.Value.CreatedAt < clock.GetUtcNow().AddMinutes(-10)).ToArray())
                _shipReportAttempts.TryRemove(old.Key, out _);
            if (_shipReportAttempts.Count >= 2048) return OfficialReportReceipt(context, new("rejected", "refreshRequired"));
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token); deadline.CancelAfter(TimeSpan.FromSeconds(12));
            using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(_origin, "/api/official-fleets/ship-images/report"))
            { Content = JsonContent.Create(new { schemaVersion = 1, sourceRef = bound.SourceRef, shipId = bound.ShipId, version, reason, details, clientRequestId = key }) };
            request.Headers.Authorization = new("Bearer", bearer);
            current(); deadline.Token.ThrowIfCancellationRequested();
            _shipReportAttempts[key] = new(fingerprint, new("unknown", "outcomeUnknown"), clock.GetUtcNow(), context); sent = true;
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
            current(); deadline.Token.ThrowIfCancellationRequested();
            ShipReportResult result;
            if (response.StatusCode == HttpStatusCode.OK)
            {
                var root = await ReadOfficialHangarJson(response, deadline.Token, 4096);
                if (root.ValueKind != JsonValueKind.Object || !root.EnumerateObject().Select(p => p.Name).Order(StringComparer.Ordinal).SequenceEqual(new[] { "schemaVersion", "reportId", "status" }.Order(StringComparer.Ordinal)) ||
                    Number(root, "schemaVersion", 1, 1) != 1 || !LowerHex(Text(root, "reportId", 32), 32) || Text(root, "status", 32) is not ("submitted" or "already_submitted")) throw Invalid();
                result = new("accepted");
            }
            else result = response.StatusCode switch
            {
                HttpStatusCode.BadRequest => new("rejected", "dataInvalid"),
                HttpStatusCode.Unauthorized => new("rejected", "identityUnavailable"),
                HttpStatusCode.Forbidden => new("rejected", "notAllowed"),
                HttpStatusCode.NotFound => new("rejected", "refreshRequired"),
                HttpStatusCode.Conflict => new("rejected", "mediaChanged"),
                HttpStatusCode.TooManyRequests => new("rejected", "rateLimited"),
                _ => new("unknown", "outcomeUnknown")
            };
            current(); deadline.Token.ThrowIfCancellationRequested();
            _shipReportAttempts[key] = new(fingerprint, result, clock.GetUtcNow(), context);
            return OfficialReportReceipt(context, result);
        }
        catch (Exception error) when (error is HttpRequestException or IOException or OperationCanceledException or JsonException or InvalidOperationException or
            KeyNotFoundException or FormatException or OverflowException or AccountBridgeHostException or StarBridge.NativeBridge.BridgeStaleGenerationException)
        { return OfficialReportReceipt(context, new(sent ? "unknown" : "rejected", sent ? "outcomeUnknown" : "refreshRequired")); }
        finally { _write.Release(); }
    }

    internal async Task<object> ReadOfficialShipImageReportStatusAsync(string bearer, JsonElement body, string accountScope, Action current, CancellationToken token)
    {
        Validate(body, "requestId"); var requestId = Text(body, "requestId", 32);
        if (!LowerHex(requestId, 32)) throw Invalid();
        var key = OfficialReportKey(accountScope, requestId);
        current(); token.ThrowIfCancellationRequested();
        if (!_shipReportAttempts.TryGetValue(key, out var attempt) || attempt.Official is not { } context || context.AccountScope != accountScope || context.RequestId != requestId)
            throw new AccountBridgeHostException("communities.refreshRequired");
        try
        {
            // Only a previously recorded local attempt reaches this authenticated
            // reporter-only maintenance endpoint. No old target/G1 resolution.
            var root = await WorkspaceJson(bearer, "/api/official-fleets/ship-images/report-status?clientRequestId=" + key, token, 4096);
            current(); token.ThrowIfCancellationRequested();
            if (root.ValueKind != JsonValueKind.Object || !root.EnumerateObject().Select(p => p.Name).Order(StringComparer.Ordinal).SequenceEqual(new[] { "schemaVersion", "clientRequestId", "status" }.Order(StringComparer.Ordinal)) ||
                Number(root, "schemaVersion", 1, 1) != 1 || Text(root, "clientRequestId", 32) != key) throw Invalid();
            var result = Text(root, "status", 16) switch { "accepted" => new ShipReportResult("accepted"), "unknown" => new("unknown", "outcomeUnknown"), _ => throw Invalid() };
            current(); _shipReportAttempts[key] = attempt with { Result = result };
            return OfficialReportReceipt(context, result);
        }
        catch (Exception error) when (error is HttpRequestException or IOException or OperationCanceledException or JsonException or InvalidOperationException or
            KeyNotFoundException or FormatException or AccountBridgeHostException or StarBridge.NativeBridge.BridgeStaleGenerationException)
        { return OfficialReportReceipt(context, new("unknown", "outcomeUnknown")); }
    }
}
