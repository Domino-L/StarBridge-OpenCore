using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    private async Task<CommunityCommand> ManageWpfS2AdmissionsAsync(string bearer, JsonElement body, string scope,
        Action current, CancellationToken token)
    {
        var intent = ParseAdmissionIntent(body);
        var epoch = Interlocked.Read(ref _inviteEpoch);
        var key = scope + "\0wpf\0" + intent.RequestId;
        if (!await _write.WaitAsync(0, token)) return new("rejected", "busy");
        var sent = false;
        string? operation = null;
        try
        {
            current();
            lock (_inviteGate)
            {
                if (_admissionAttempts.TryGetValue(key, out var prior)) return prior.Intent == intent ? prior.Result : new("rejected", "requestChanged");
                if (_admissionAttempts.Count >= 256) return new("rejected", "refreshRequired");
            }
            var target = Resolve(intent.TargetRef, scope, allowWpfS2: true);
            var section = intent.Action is "approve" or "decline" ? "applications" : "invites";
            AdmissionTarget? entry = null;
            if (intent.EntryRef is not null && (!_admissionTargets.TryGetValue(intent.EntryRef, out entry) ||
                entry.Scope != scope || entry.Code != target.Code || entry.Kind != section || entry.Expires <= _targetClock.GetUtcNow()))
                return new("rejected", "refreshRequired");
            operation = scope + "\0wpf\0" + target.Code + "\0" + (entry?.Id ?? "generate");
            lock (_inviteGate)
            {
                // S2 has no request-receipt lookup. A confirmation checkbox cannot make replay safe.
                if (_admissionUncertain.Contains(operation)) return new("unknown", "outcomeUnknown");
            }
            var page = JsonSerializer.SerializeToElement(await ReadWpfS2AdmissionsAsync(bearer,
                JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = intent.TargetRef, section, offset = entry?.Offset ?? 0 }),
                scope, current, token));
            if (entry is not null)
            {
                var selected = page.GetProperty("items").EnumerateArray().SingleOrDefault(row =>
                    _admissionTargets.TryGetValue(Text(row, "entryRef", 32), out var fresh) && fresh.Id == entry.Id);
                if (selected.ValueKind == JsonValueKind.Undefined) return new("rejected", "refreshRequired");
                if (intent.Action == "revokeInvite" && !WpfFlag(selected, "canRevoke")) return new("rejected", "notAllowed");
            }
            else if (!WpfFlag(page.GetProperty("access"), "canCreateInvite")) return new("rejected", "notAllowed");

            var fleet = await WpfGovernanceFleet(bearer, target, current, token);
            var priorIds = WpfS2InvitationRows(fleet).Select(row => Text(row, "id", 128)).ToHashSet(StringComparer.OrdinalIgnoreCase);
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
            deadline.CancelAfter(TimeSpan.FromSeconds(20));
            if (intent.Action == "generateInvite" && page.GetProperty("currentInvite").ValueKind == JsonValueKind.Object)
            {
                var currentInvite = page.GetProperty("currentInvite");
                if (!_admissionTargets.TryGetValue(Text(currentInvite, "entryRef", 32), out var own)) throw Invalid();
                var revoked = await Post("/api/fleets/invites/revoke", new { fleetCode = target.Code, inviteId = own.Id });
                if (revoked.Error is not null) return Finish(revoked.Error);
                if (WpfS2InvitationRows(revoked.Fleet).Any(row => Text(row, "id", 128) == own.Id && WpfS2InviteStatus(row, _targetClock.GetUtcNow()) == "Active")) throw Invalid();
            }
            var path = intent.Action switch { "generateInvite" => "/api/fleets/invites", "revokeInvite" => "/api/fleets/invites/revoke", _ => "/api/fleets/applications/decide" };
            object payload = intent.Action switch
            {
                "generateInvite" => new { fleetCode = target.Code, intent.ExpiresInDays, intent.MaxUses, acceptMode = "Direct" },
                "revokeInvite" => new { fleetCode = target.Code, inviteId = entry!.Id },
                _ => new { fleetCode = target.Code, applicationId = entry!.Id, approve = intent.Action == "approve" }
            };
            var receipt = await Post(path, payload);
            if (receipt.Error is not null) return Finish(receipt.Error);
            if (intent.Action == "generateInvite")
            {
                var candidates = WpfS2InvitationRows(receipt.Fleet).Where(row => !priorIds.Contains(Text(row, "id", 128)) &&
                    WpfS2InviteStatus(row, _targetClock.GetUtcNow()) == "Active" &&
                    Number(row, "maxUses", 0, 50) == intent.MaxUses && Number(row, "usedCount", 0, 50) == 0 &&
                    WpfText(row, "acceptMode", 32).Equals("Direct", StringComparison.OrdinalIgnoreCase)).ToArray();
                if (candidates.Length != 1 || string.IsNullOrWhiteSpace(Text(candidates[0], "code", 128))) throw Invalid();
            }
            else if (intent.Action == "revokeInvite")
            {
                if (WpfS2InvitationRows(receipt.Fleet).Any(row => Text(row, "id", 128) == entry!.Id &&
                    WpfS2InviteStatus(row, _targetClock.GetUtcNow()) == "Active")) throw Invalid();
            }
            else if (WpfS2OptionalRows(receipt.Fleet, "applications", 10000).Any(row => Text(row, "id", 128) == entry!.Id &&
                (string.IsNullOrWhiteSpace(WpfText(row, "status", 16)) || WpfText(row, "status", 16).Equals("Pending", StringComparison.OrdinalIgnoreCase)))) throw Invalid();
            current();
            deadline.Token.ThrowIfCancellationRequested();
            return Finish(new("accepted"));

            async Task<(JsonElement Fleet, CommunityCommand? Error)> Post(string route, object value)
            {
                using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(_origin, route))
                    { Content = JsonContent.Create(value, value.GetType()) };
                request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
                current();
                deadline.Token.ThrowIfCancellationRequested();
                lock (_inviteGate)
                {
                    if (epoch != _inviteEpoch) throw new AccountBridgeHostException("communities.identityUnavailable");
                    _admissionUncertain.Add(operation);
                    _admissionAttempts[key] = new(intent, new("unknown", "outcomeUnknown"));
                    sent = true;
                }
                using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
                current();
                if (!response.IsSuccessStatusCode) return (default, response.StatusCode switch
                {
                    HttpStatusCode.BadRequest or HttpStatusCode.NotFound or HttpStatusCode.Conflict => new("rejected", "refreshRequired"),
                    HttpStatusCode.Forbidden => new("rejected", "notAllowed"), HttpStatusCode.Unauthorized => new("rejected", "identityUnavailable"),
                    _ => new("unknown", "outcomeUnknown")
                });
                using var document = await ReadBoundedJsonAsync(response, 8 * 1024 * 1024, deadline.Token);
                if (!Text(document.RootElement, "code", 256).Equals(target.Code, StringComparison.OrdinalIgnoreCase)) throw Invalid();
                return (document.RootElement.Clone(), null);
            }
        }
        catch (Exception error) when (error is HttpRequestException or IOException or OperationCanceledException or JsonException or
            InvalidOperationException or KeyNotFoundException or FormatException or OverflowException or AccountBridgeHostException or
            StarBridge.NativeBridge.BridgeStaleGenerationException)
        { return Finish(new(sent ? "unknown" : "rejected", sent ? "outcomeUnknown" : "refreshRequired")); }
        finally { _write.Release(); }

        CommunityCommand Finish(CommunityCommand result)
        {
            lock (_inviteGate)
            {
                if (epoch != _inviteEpoch) return new(sent ? "unknown" : "rejected", sent ? "outcomeUnknown" : "identityUnavailable");
                _admissionAttempts[key] = new(intent, result);
                if (operation is not null && result.Status != "unknown") _admissionUncertain.Remove(operation);
                return result;
            }
        }
    }
}
