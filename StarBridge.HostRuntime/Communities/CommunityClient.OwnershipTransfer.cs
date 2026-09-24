using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    private sealed record OwnershipTransferEdit(string Scope, string Code, string MemberId, string TargetRef,
        string MemberRef, string Version, bool CanTransfer, DateTimeOffset Expires, bool LeaveAfterTransfer);
    private sealed record OwnershipTransferAttempt(string Hash, CommunityCommand Result);
    private readonly object _ownershipTransferGate = new();
    private readonly Dictionary<string, OwnershipTransferEdit> _ownershipTransferEdits = new();
    private readonly Dictionary<string, OwnershipTransferAttempt> _ownershipTransferAttempts = new();
    private readonly HashSet<string> _ownershipTransferUncertain = new();
    private long _ownershipTransferEpoch;

    internal void InvalidateOwnershipTransferEdits()
    {
        lock (_ownershipTransferGate) { _ownershipTransferEpoch++; _ownershipTransferEdits.Clear(); }
    }

    internal Task<object> ReadOwnershipTransferAsync(string bearer, JsonElement body, string scope, Action current,
        CancellationToken token, bool leaveAfterTransfer = false) => GuardWorkspace(async () =>
    {
        Validate(body, "targetRef", "memberRef", "editRef");
        current();
        long epoch;
        OwnershipTransferEdit? previous;
        var editRef = Optional(body, "editRef", 32);
        lock (_ownershipTransferGate)
        {
            epoch = _ownershipTransferEpoch;
            previous = editRef is null ? null : ResolveOwnershipTransferEdit(editRef, scope);
            if (previous is not null && previous.LeaveAfterTransfer != leaveAfterTransfer) throw Invalid();
        }
        if (editRef is not null && (body.TryGetProperty("targetRef", out _) || body.TryGetProperty("memberRef", out _))) throw Invalid();
        var targetRef = previous?.TargetRef ?? Text(body, "targetRef", 32);
        var memberRef = previous?.MemberRef ?? Text(body, "memberRef", 32);
        string code, memberId;
        if (previous is null)
        {
            var target = Resolve(targetRef, scope);
            if (!_memberTargets.TryGetValue(memberRef, out var member) || member.Code != target.Code ||
                member.Scope != scope || member.Expires <= DateTimeOffset.UtcNow)
                throw new AccountBridgeHostException("communities.refreshRequired");
            code = target.Code;
            memberId = member.MemberId;
        }
        else { code = previous.Code; memberId = previous.MemberId; }
        var readPath = leaveAfterTransfer ? "/api/fleets/ownership-exit?code=" : "/api/fleets/ownership-transfer?code=";
        var root = await WorkspaceJson(bearer, readPath + Uri.EscapeDataString(code) +
            "&memberId=" + Uri.EscapeDataString(memberId), token);
        if (Encoding.UTF8.GetByteCount(root.GetRawText()) > 16 * 1024 || Number(root, "schemaVersion", 1, 1) != 1 ||
            root.EnumerateObject().Select(property => property.Name).Distinct().Count() != root.EnumerateObject().Count() ||
            Text(root, "code", 256) != code || Text(root, "memberId", 512) != memberId) throw Invalid();
        var version = Text(root, "version", 64);
        if (version.Length != 64 || version.Any(c => !char.IsAsciiHexDigit(c))) throw Invalid();
        var canTransfer = root.GetProperty("canTransfer").GetBoolean();
        if (root.TryGetProperty("leaveAfterTransfer", out var intent)
            ? intent.GetBoolean() != leaveAfterTransfer : leaveAfterTransfer) throw Invalid();
        var fields = Strings(root, ("gameName", 512), ("callsign", 512), ("roleTitle", 512), ("formerOwnerRoleTitle", 512));
        current();
        token.ThrowIfCancellationRequested();
        lock (_ownershipTransferGate)
        {
            if (epoch != _ownershipTransferEpoch) throw new AccountBridgeHostException("communities.identityUnavailable");
            foreach (var expired in _ownershipTransferEdits.Where(pair => pair.Value.Expires <= DateTimeOffset.UtcNow).ToArray())
                _ownershipTransferEdits.Remove(expired.Key);
            if (_ownershipTransferEdits.Count >= 128) throw new AccountBridgeHostException("communities.refreshRequired");
            var nextRef = Guid.NewGuid().ToString("N");
            _ownershipTransferEdits[nextRef] = new(scope, code, memberId, targetRef, memberRef, version, canTransfer, DateTimeOffset.UtcNow.AddMinutes(15), leaveAfterTransfer);
            fields["schemaVersion"] = 1;
            fields["targetRef"] = targetRef;
            fields["memberRef"] = memberRef;
            fields["editRef"] = nextRef;
            fields["canTransfer"] = canTransfer;
            fields["leaveAfterTransfer"] = leaveAfterTransfer;
            return fields;
        }
    });

    private OwnershipTransferEdit ResolveOwnershipTransferEdit(string reference, string scope) =>
        _ownershipTransferEdits.TryGetValue(reference, out var edit) && edit.Scope == scope && edit.Expires > DateTimeOffset.UtcNow
            ? edit : throw new AccountBridgeHostException("communities.refreshRequired");

    internal static void ValidateOwnershipTransfer(JsonElement body)
    {
        Validate(body, "requestId", "editRef", "confirmUncertainRetry");
        try
        {
            foreach (var key in new[] { "requestId", "editRef" })
            {
                var value = Text(body, key, 32);
                if (value.Length != 32 || value.Any(c => c is not (>= 'a' and <= 'f' or >= '0' and <= '9'))) throw Invalid();
            }
            if (body.TryGetProperty("confirmUncertainRetry", out var confirm)) confirm.GetBoolean();
        }
        catch (Exception e) when (e is JsonException or InvalidOperationException or KeyNotFoundException or FormatException or OverflowException)
        { throw Invalid(); }
    }

    internal async Task<CommunityCommand> TransferOwnershipAsync(string bearer, JsonElement body, string scope,
        Action current, CancellationToken token, bool leaveAfterTransfer = false)
    {
        ValidateOwnershipTransfer(body);
        var key = scope + "\0" + Text(body, "requestId", 32);
        var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(leaveAfterTransfer + "\0" + body.GetRawText())));
        if (!await _write.WaitAsync(0, token)) return new("rejected", "busy");
        var sent = false;
        var wasUncertain = false;
        try
        {
            current();
            OwnershipTransferEdit edit;
            long epoch;
            string operation;
            lock (_ownershipTransferGate)
            {
                epoch = _ownershipTransferEpoch;
                if (_ownershipTransferAttempts.TryGetValue(key, out var prior))
                    return prior.Hash == hash ? prior.Result : new("rejected", "requestChanged");
                if (_ownershipTransferAttempts.Count >= 256) return new("rejected", "refreshRequired");
                edit = ResolveOwnershipTransferEdit(Text(body, "editRef", 32), scope);
                if (edit.LeaveAfterTransfer != leaveAfterTransfer) return new("rejected", "invalidDraft");
                operation = scope + "\0" + edit.Code + "\0" + edit.MemberId + "\0" + edit.Version + "\0" + leaveAfterTransfer;
                wasUncertain = _ownershipTransferUncertain.Contains(operation);
                if (wasUncertain && !(body.TryGetProperty("confirmUncertainRetry", out var confirm) && confirm.GetBoolean()))
                    return new("unknown", "outcomeUnknown");
            }
            if (!edit.CanTransfer) return new("rejected", "notAllowed");
            var writePath = leaveAfterTransfer ? "/api/fleets/leave?projection=ownership-exit&memberId=" :
                "/api/fleets/transfer-commander?projection=ownership-transfer&memberId=";
            using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(_origin,
                writePath + Uri.EscapeDataString(edit.MemberId) +
                "&version=" + Uri.EscapeDataString(edit.Version)))
            {
                Content = leaveAfterTransfer ? JsonContent.Create(new { fleetCode = edit.Code }) :
                    JsonContent.Create(new { fleetCode = edit.Code, targetGameName = "" })
            };
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
            deadline.CancelAfter(TimeSpan.FromSeconds(12));
            current();
            token.ThrowIfCancellationRequested();
            lock (_ownershipTransferGate)
            {
                if (epoch != _ownershipTransferEpoch) throw new AccountBridgeHostException("communities.identityUnavailable");
                _ownershipTransferAttempts[key] = new(hash, new("unknown", "outcomeUnknown"));
                _ownershipTransferUncertain.Add(operation);
            }
            sent = true;
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
            current();
            CommunityCommand receipt;
            if (response.StatusCode != HttpStatusCode.OK)
                receipt = response.StatusCode switch
                {
                    HttpStatusCode.Conflict => new("rejected", "conflict"),
                    HttpStatusCode.BadRequest => new("rejected", "invalidDraft"),
                    HttpStatusCode.Forbidden => new("rejected", "notAllowed"),
                    HttpStatusCode.NotFound => new("rejected", "refreshRequired"),
                    HttpStatusCode.Unauthorized => new("rejected", "identityUnavailable"),
                    _ => new("unknown", "outcomeUnknown")
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
                using var json = JsonDocument.Parse(buffer.ToArray());
                if (json.RootElement.EnumerateObject().Count() != 2 || Number(json.RootElement, "schemaVersion", 1, 1) != 1 ||
                    Text(json.RootElement, "status", 16) != "accepted") throw Invalid();
                receipt = new("accepted");
            }
            // A rejected retry does not prove that the earlier timed-out transfer was not applied.
            if (wasUncertain && receipt.Status == "rejected") receipt = new("unknown", "outcomeUnknown");
            current();
            lock (_ownershipTransferGate)
            {
                if (epoch != _ownershipTransferEpoch) throw new AccountBridgeHostException("communities.identityUnavailable");
                _ownershipTransferAttempts[key] = new(hash, receipt);
                if (receipt.Status == "accepted" || receipt.Status == "rejected" && !wasUncertain) _ownershipTransferUncertain.Remove(operation);
            }
            return receipt;
        }
        catch (Exception e) when (e is HttpRequestException or IOException or OperationCanceledException or AccountBridgeHostException or
            StarBridge.NativeBridge.BridgeStaleGenerationException or JsonException or InvalidOperationException or KeyNotFoundException or FormatException or OverflowException)
        { return new(sent ? "unknown" : "rejected", sent ? "outcomeUnknown" : "refreshRequired"); }
        finally { _write.Release(); }
    }
}
