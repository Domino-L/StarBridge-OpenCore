using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    internal sealed record AdmissionIntent(string RequestId, string TargetRef, string Action,
        string? EntryRef, int ExpiresInDays, int MaxUses, bool ConfirmUncertainRetry);
    private sealed record AdmissionAttempt(AdmissionIntent Intent, CommunityCommand Result);
    private readonly Dictionary<string, AdmissionAttempt> _admissionAttempts = new();
    private readonly HashSet<string> _admissionUncertain = new(StringComparer.Ordinal);

    internal static AdmissionIntent ParseAdmissionIntent(JsonElement body)
    {
        try
        {
            Validate(body, "requestId", "targetRef", "action", "entryRef", "expiresInDays", "maxUses", "confirmUncertainRetry");
            string Reference(string key)
            {
                var value = Text(body, key, 32);
                return value.Length == 32 && value.All(c => c is >= 'a' and <= 'f' or >= '0' and <= '9') ? value : throw Invalid();
            }
            var action = Text(body, "action", 24);
            if (action is not ("approve" or "decline" or "generateInvite" or "revokeInvite")) throw Invalid();
            var generate = action == "generateInvite";
            if (generate && body.TryGetProperty("entryRef", out _) || !generate &&
                new[] { "expiresInDays", "maxUses" }.Any(key => body.TryGetProperty(key, out _))) throw Invalid();
            return new(Reference("requestId"), Reference("targetRef"), action, generate ? null : Reference("entryRef"),
                generate ? Number(body, "expiresInDays", 1, 30) : 0,
                generate ? Number(body, "maxUses", 0, 50) : 0,
                body.TryGetProperty("confirmUncertainRetry", out var retry) && retry.GetBoolean());
        }
        catch (Exception error) when (error is InvalidOperationException or KeyNotFoundException or FormatException)
        { throw Invalid(); }
    }

    internal async Task<CommunityCommand> ManageAdmissionsAsync(string bearer, JsonElement body, string scope,
        Action current, CancellationToken token, bool wpfS2 = false)
    {
        if (wpfS2) return await ManageWpfS2AdmissionsAsync(bearer, body, scope, current, token);
        var intent = ParseAdmissionIntent(body);
        var epoch = Interlocked.Read(ref _inviteEpoch);
        if (!await _write.WaitAsync(0, token)) return new("rejected", "busy");
        var requestKey = scope + "\0" + intent.RequestId;
        string? operationKey = null;
        var sent = false;
        CommunityCommand Finish(CommunityCommand result)
        {
            lock (_inviteGate)
            {
                if (epoch == _inviteEpoch)
                {
                    _admissionAttempts[requestKey] = new(intent, result);
                    if (sent && operationKey is not null)
                    {
                        if (result.Status == "unknown") _admissionUncertain.Add(operationKey);
                        else _admissionUncertain.Remove(operationKey);
                    }
                }
            }
            return result;
        }
        try
        {
            current();
            lock (_inviteGate)
            {
                if (epoch != _inviteEpoch) return new("rejected", "identityUnavailable");
                if (_admissionAttempts.TryGetValue(requestKey, out var prior))
                    return prior.Intent == intent ? prior.Result : new("rejected", "requestChanged");
                if (_admissionAttempts.Count >= 256) return new("rejected", "refreshRequired");
            }
            var target = Resolve(intent.TargetRef, scope, allowWpfS2: wpfS2);
            var section = intent.Action is "approve" or "decline" ? "applications" : "invites";
            AdmissionTarget? entry = null;
            if (intent.EntryRef is not null && (!_admissionTargets.TryGetValue(intent.EntryRef, out entry) ||
                entry.Code != target.Code || entry.Scope != scope || entry.Kind != section || entry.Expires <= DateTimeOffset.UtcNow))
                return Finish(new("rejected", "refreshRequired"));
            operationKey = scope + "\0" + target.Code + "\0" + section + "\0" + (entry?.Id ?? "generate");
            lock (_inviteGate)
            {
                // A fresh request ID alone is not consent to repeat an uncertain write.
                if (_admissionUncertain.Contains(operationKey) && !intent.ConfirmUncertainRetry)
                    return Finish(new("unknown", "outcomeUnknown"));
            }
            var page = JsonSerializer.SerializeToElement(await ReadAdmissionsAsync(bearer,
                JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = intent.TargetRef, section, offset = entry?.Offset ?? 0 }),
                scope, current, token, wpfS2));
            current();
            var access = page.GetProperty("access");
            if (section == "applications" && !access.GetProperty("canDecideApplications").GetBoolean() ||
                intent.Action == "generateInvite" && !access.GetProperty("canCreateInvite").GetBoolean())
                return Finish(new("rejected", "notAllowed"));
            if (entry is not null)
            {
                var found = false;
                foreach (var row in page.GetProperty("items").EnumerateArray())
                {
                    if (!_admissionTargets.TryGetValue(row.GetProperty("entryRef").GetString()!, out var fresh) || fresh.Id != entry.Id) continue;
                    found = true;
                    if (intent.Action == "revokeInvite" && (!row.GetProperty("canRevoke").GetBoolean() || row.GetProperty("status").GetString() != "Active"))
                        return Finish(new("rejected", "notAllowed"));
                }
                // Paging may have moved since the UI was read. Require a fresh selection,
                // never substitute the row now occupying the old position.
                if (!found) return Finish(new("rejected", "refreshRequired"));
            }
            var path = intent.Action switch
            {
                "generateInvite" => "/api/fleets/invites",
                "revokeInvite" => "/api/fleets/invites/revoke",
                _ => "/api/fleets/applications/decide"
            };
            object payload = intent.Action switch
            {
                "generateInvite" => new { FleetCode = target.Code, intent.ExpiresInDays, intent.MaxUses, AcceptMode = "Direct", Purpose = "code" },
                "revokeInvite" => new { FleetCode = target.Code, InviteId = entry!.Id },
                _ => new { FleetCode = target.Code, ApplicationId = entry!.Id, Approve = intent.Action == "approve" }
            };
            using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(_origin, path)) { Content = JsonContent.Create(payload) };
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
            deadline.CancelAfter(TimeSpan.FromSeconds(12));
            current();
            token.ThrowIfCancellationRequested();
            lock (_inviteGate)
            {
                if (epoch != _inviteEpoch) return new("rejected", "identityUnavailable");
                sent = true;
                Finish(new("unknown", "outcomeUnknown"));
            }
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
            current();
            // These exact WPF endpoints return 200 only after SaveAsync completes.
            // Do not deserialize or forward their unrestricted bulk snapshot. The UI
            // refreshes the narrow admissions projection separately, including the code.
            return Finish(response.StatusCode switch
            {
                HttpStatusCode.OK => new("accepted"),
                HttpStatusCode.BadRequest or HttpStatusCode.NotFound or HttpStatusCode.Conflict => new("rejected", "refreshRequired"),
                HttpStatusCode.Forbidden => new("rejected", "notAllowed"),
                HttpStatusCode.Unauthorized => new("rejected", "identityUnavailable"),
                _ => new("unknown", "outcomeUnknown")
            });
        }
        catch (Exception error) when (error is HttpRequestException or IOException or OperationCanceledException or
            AccountBridgeHostException or StarBridge.NativeBridge.BridgeStaleGenerationException or JsonException or
            InvalidOperationException or KeyNotFoundException or FormatException)
        {
            var reason = error is AccountBridgeHostException bridge ? bridge.Code.Replace("communities.", "", StringComparison.Ordinal) : "refreshRequired";
            return Finish(new(sent ? "unknown" : "rejected", sent ? "outcomeUnknown" : reason));
        }
        finally { _write.Release(); }
    }
}
