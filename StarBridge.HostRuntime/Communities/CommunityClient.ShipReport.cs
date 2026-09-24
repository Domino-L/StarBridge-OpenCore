using System.Collections.Concurrent;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StarBridge.Core.TrustSafety;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    private sealed record ShipReportResult(string Status, string? Error = null);
    private sealed record ShipReportAttempt(string Fingerprint, ShipReportResult Result, DateTimeOffset CreatedAt);
    private readonly ConcurrentDictionary<string, ShipReportAttempt> _shipReportAttempts = new();

    internal async Task<object> ReportShipImageAsync(string bearer, JsonElement body, string scope,
        Action current, CancellationToken token)
    {
        string reference, shipRef, version, requestId, reason, details;
        bool checkOnly;
        try
        {
            Validate(body, "targetRef", "shipRef", "version", "requestId", "reason", "details", "checkOnly");
            checkOnly = body.TryGetProperty("checkOnly", out var checking) && checking.GetBoolean();
            reference = Text(body, "targetRef", 32); shipRef = Text(body, "shipRef", 32);
            version = Text(body, "version", 64); requestId = Text(body, "requestId", 32);
            reason = Text(body, "reason", 32).Trim().ToLowerInvariant();
            details = Text(body, "details", 1000, true).Trim();
            if (!LowerHex(reference, 32) || !LowerHex(shipRef, 32) || !LowerHex(requestId, 32) ||
                !ShipHash(version) || !ReportReasons.IsSupported(reason)) throw Invalid();
        }
        catch (Exception e) when (e is JsonException or InvalidOperationException or KeyNotFoundException or FormatException)
        { throw Invalid(); }
        object Receipt(ShipReportResult result) => new { schemaVersion = 1, targetRef = reference,
            shipRef, requestId, status = result.Status, error = result.Error };
        if (!await _write.WaitAsync(0, token)) return Receipt(new("rejected", "busy"));
        var sent = false;
        try
        {
            current(); token.ThrowIfCancellationRequested();
            var target = Resolve(reference, scope);
            if (!_shipTargets.TryGetValue(shipRef, out var ship) || ship.Scope != scope || ship.Code != target.Code ||
                ship.Expires <= DateTimeOffset.UtcNow) return Receipt(new("rejected", "refreshRequired"));
            var key = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(scope + "\0" + target.Code + "\0" + requestId)))[..32].ToLowerInvariant();
            var fingerprint = Convert.ToHexString(SHA256.HashData(JsonSerializer.SerializeToUtf8Bytes(new { ship.Id, version, reason, details })));
            if (_shipReportAttempts.TryGetValue(key, out var prior))
            {
                if (prior.Fingerprint != fingerprint) return Receipt(new("rejected", "intentConflict"));
                if (!checkOnly || prior.Result.Status != "unknown") return Receipt(prior.Result);
                var resolved = await CheckShipReportAsync(bearer, key, current, token);
                current(); token.ThrowIfCancellationRequested();
                _shipReportAttempts[key] = new(fingerprint, resolved, DateTimeOffset.UtcNow);
                return Receipt(resolved);
            }
            if (checkOnly) return Receipt(new("unknown", "outcomeUnknown"));
            foreach (var old in _shipReportAttempts.Where(p => p.Value.Result.Status != "unknown" &&
                         p.Value.CreatedAt < DateTimeOffset.UtcNow.AddMinutes(-10)).ToArray())
                _shipReportAttempts.TryRemove(old.Key, out _);
            if (_shipReportAttempts.Count >= 2048) return Receipt(new("rejected", "refreshRequired"));
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
            deadline.CancelAfter(TimeSpan.FromSeconds(12));
            using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(_origin, "/api/fleets/ships/image/report"))
            { Content = JsonContent.Create(new { code = target.Code, shipId = ship.Id, version, reason, details, clientRequestId = key }) };
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
            current(); deadline.Token.ThrowIfCancellationRequested();
            _shipReportAttempts[key] = new(fingerprint, new("unknown", "outcomeUnknown"), DateTimeOffset.UtcNow);
            sent = true;
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
            current();
            ShipReportResult result;
            if (response.StatusCode != HttpStatusCode.OK)
                result = response.StatusCode switch
                {
                    HttpStatusCode.BadRequest => new("rejected", "dataInvalid"),
                    HttpStatusCode.Unauthorized => new("rejected", "identityUnavailable"),
                    HttpStatusCode.Forbidden => new("rejected", "notAllowed"),
                    HttpStatusCode.NotFound => new("rejected", "refreshRequired"),
                    HttpStatusCode.Conflict => new("rejected", "mediaChanged"),
                    HttpStatusCode.TooManyRequests => new("rejected", "rateLimited"),
                    _ => new("unknown", "outcomeUnknown"),
                };
            else
            {
                using var stream = await response.Content.ReadAsStreamAsync(deadline.Token);
                using var buffer = new MemoryStream();
                var chunk = new byte[4096]; int count;
                while ((count = await stream.ReadAsync(chunk, deadline.Token)) > 0)
                {
                    if (buffer.Length + count > 4096) throw Invalid();
                    buffer.Write(chunk, 0, count);
                }
                using var document = JsonDocument.Parse(buffer.ToArray());
                var root = document.RootElement;
                ShipObject(root);
                if (Number(root, "schemaVersion", 1, 1) != 1 || !LowerHex(Text(root, "reportId", 32), 32) ||
                    Text(root, "status", 32) is not ("submitted" or "already_submitted")) throw Invalid();
                result = new("accepted");
            }
            deadline.Token.ThrowIfCancellationRequested(); current();
            _shipReportAttempts[key] = new(fingerprint, result, DateTimeOffset.UtcNow);
            return Receipt(result);
        }
        catch (Exception e) when (e is HttpRequestException or IOException or OperationCanceledException or JsonException or
            InvalidOperationException or KeyNotFoundException or FormatException or OverflowException or
            AccountBridgeHostException or StarBridge.NativeBridge.BridgeStaleGenerationException)
        { return Receipt(new(sent || checkOnly ? "unknown" : "rejected", sent || checkOnly ? "outcomeUnknown" : "refreshRequired")); }
        finally { _write.Release(); }
    }

    private async Task<ShipReportResult> CheckShipReportAsync(string bearer, string key, Action current, CancellationToken token)
    {
        // Read only. Absence or lookup failure is never permission to replay the POST.
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
        deadline.CancelAfter(TimeSpan.FromSeconds(12));
        current(); deadline.Token.ThrowIfCancellationRequested();
        var row = await WorkspaceJson(bearer, "/api/fleets/ships/image/report-status?clientRequestId=" + key, deadline.Token, 4096);
        current(); deadline.Token.ThrowIfCancellationRequested();
        ShipObject(row);
        if (Number(row, "schemaVersion", 1, 1) != 1 || Text(row, "clientRequestId", 32) != key) throw Invalid();
        return Text(row, "status", 16) switch
        {
            "accepted" => new("accepted"),
            "unknown" => new("unknown", "outcomeUnknown"),
            _ => throw Invalid(),
        };
    }
}
