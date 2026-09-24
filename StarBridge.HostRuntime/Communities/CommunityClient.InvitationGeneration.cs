using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Communities;

internal sealed record InvitationGenerationIntent(string TargetRef, string RequestId, DateTimeOffset RequestedAt, int MaxUses);
internal sealed record InvitationGenerationResult(string Status, string? Error = null,
    string? InviteId = null, string? Code = null, DateTimeOffset? ExpiresAt = null);

internal sealed partial class CommunityClient
{
    // Internal step for the shared private/room send workflow, not a raw-code Bridge capability.
    // The coordinator must retain this immutable intent until the generation outcome is reconciled.
    internal async Task<InvitationGenerationResult> GenerateInvitationCardAsync(string bearer, InvitationGenerationIntent intent,
        string scope, Action current, CancellationToken token)
    {
        static bool Reference(string text) => text.Length == 32 && text.All(c => c is >= '0' and <= '9' or >= 'a' and <= 'f');
        if (!Reference(intent.TargetRef) || !Reference(intent.RequestId) || intent.MaxUses is < 1 or > 50)
            return new("rejected", "dataInvalid");
        if (!await _write.WaitAsync(0, token)) return new("rejected", "busy");
        var epoch = Interlocked.Read(ref _inviteEpoch);
        var sent = false;
        try
        {
            current();
            var target = Resolve(intent.TargetRef, scope);
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
            deadline.CancelAfter(TimeSpan.FromSeconds(12));
            var access = await WorkspaceJson(bearer,
                $"/api/fleets/admissions?code={Uri.EscapeDataString(target.Code)}&section=access&offset=0", deadline.Token, 16 * 1024);
            current();
            if (Number(access, "schemaVersion", 1, 1) != 1 || Number(access, "membershipModelVersion", 2, 2) != 2
                || Text(access, "code", 256) != target.Code || Text(access, "section", 16) != "access") throw Invalid();
            // An older Relay can ignore new POST fields. Never attempt replayable generation without positive support.
            if (!access.TryGetProperty("inviteGenerationVersion", out var version) || version.GetInt32() != 1)
                return new("rejected", "unavailable");
            if (!access.GetProperty("access").GetProperty("canSendInvitationCard").GetBoolean())
                return new("rejected", "notAllowed");
            using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(_origin, "/api/fleets/invites?view=client"))
            {
                Content = JsonContent.Create(new { FleetCode = target.Code, ExpiresInDays = 7, intent.MaxUses,
                    AcceptMode = "Direct", Purpose = "card", ClientRequestId = intent.RequestId, ClientRequestedAt = intent.RequestedAt })
            };
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
            lock (_inviteGate)
            {
                current();
                deadline.Token.ThrowIfCancellationRequested();
                if (epoch != _inviteEpoch) return new("rejected", "identityUnavailable");
                sent = true;
            }
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
            current();
            if (epoch != Interlocked.Read(ref _inviteEpoch)) return new("unknown", "outcomeUnknown");
            if (response.StatusCode != HttpStatusCode.OK) return response.StatusCode switch
            {
                HttpStatusCode.Unauthorized => new("rejected", "identityUnavailable"),
                HttpStatusCode.Forbidden => new("rejected", "notAllowed"),
                HttpStatusCode.BadRequest => new("rejected", "dataInvalid"),
                HttpStatusCode.NotFound or HttpStatusCode.Conflict => new("rejected", "refreshRequired"),
                _ => new("unknown", "outcomeUnknown")
            };
            using var stream = await response.Content.ReadAsStreamAsync(deadline.Token);
            using var buffer = new MemoryStream();
            var chunk = new byte[1024];
            int count;
            while ((count = await stream.ReadAsync(chunk, deadline.Token)) > 0)
            {
                if (buffer.Length + count > 4096) throw Invalid();
                buffer.Write(chunk, 0, count);
            }
            using var document = JsonDocument.Parse(buffer.ToArray());
            var root = document.RootElement;
            if (root.EnumerateObject().Select(field => field.Name).Distinct().Count() != root.EnumerateObject().Count()
                || root.EnumerateObject().Any(field => field.Name is not ("schemaVersion" or "status" or "requestId" or "inviteId" or "code" or "expiresAt"))
                || Number(root, "schemaVersion", 1, 1) != 1 || Text(root, "requestId", 32) != intent.RequestId) throw Invalid();
            var status = Text(root, "status", 16);
            var id = Optional(root, "inviteId", 32);
            var code = Optional(root, "code", 40);
            DateTimeOffset? expires = root.TryGetProperty("expiresAt", out var expiration) && expiration.ValueKind != JsonValueKind.Null
                ? expiration.GetDateTimeOffset() : null;
            deadline.Token.ThrowIfCancellationRequested(); current();
            if (epoch != Interlocked.Read(ref _inviteEpoch)) return new("unknown", "outcomeUnknown");
            if (status == "unavailable" && id is null && code is null && expires is null) return new("rejected", "inviteInvalid");
            if (status != "accepted" || id is null || !Reference(id) || string.IsNullOrWhiteSpace(code) || code.Length < 6
                || expires is null || expires <= DateTimeOffset.UtcNow) throw Invalid();
            return new("accepted", InviteId: id, Code: code, ExpiresAt: expires);
        }
        catch (Exception error) when (error is HttpRequestException or IOException or OperationCanceledException or JsonException
            or AccountBridgeHostException or StarBridge.NativeBridge.BridgeStaleGenerationException or InvalidOperationException or KeyNotFoundException or FormatException)
        { return new(sent ? "unknown" : "rejected", sent ? "outcomeUnknown" : "refreshRequired"); }
        finally { _write.Release(); }
    }
}
