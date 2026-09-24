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
    private sealed record MemberRemovalEdit(string Scope, string Code, string MemberId, string TargetRef,
        string MemberRef, string Version, bool CanRemove, DateTimeOffset Expires);
    private sealed record MemberRemovalAttempt(string Hash, CommunityCommand Result);
    private readonly object _memberRemovalGate = new();
    private readonly Dictionary<string, MemberRemovalEdit> _memberRemovalEdits = new();
    private readonly Dictionary<string, MemberRemovalAttempt> _memberRemovalAttempts = new();
    private readonly HashSet<string> _memberRemovalUncertain = new();
    private long _memberRemovalEpoch;

    internal void InvalidateMemberRemovalEdits()
    {
        lock (_memberRemovalGate) { _memberRemovalEpoch++; _memberRemovalEdits.Clear(); }
    }

    internal Task<object> ReadMemberRemovalAsync(string bearer, JsonElement body, string scope, Action current,
        CancellationToken token) => GuardWorkspace(async () =>
    {
        Validate(body, "targetRef", "memberRef", "editRef");
        current();
        long epoch;
        MemberRemovalEdit? previous;
        var editRef = Optional(body, "editRef", 32);
        lock (_memberRemovalGate)
        {
            epoch = _memberRemovalEpoch;
            previous = editRef is null ? null : ResolveMemberRemovalEdit(editRef, scope);
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
        var root = await WorkspaceJson(bearer, "/api/fleets/member-removal?code=" + Uri.EscapeDataString(code) +
            "&memberId=" + Uri.EscapeDataString(memberId), token);
        if (Encoding.UTF8.GetByteCount(root.GetRawText()) > 16 * 1024 || Number(root, "schemaVersion", 1, 1) != 1 ||
            Text(root, "code", 256) != code || Text(root, "memberId", 512) != memberId) throw Invalid();
        var version = Text(root, "version", 64);
        if (version.Length != 64 || version.Any(c => !char.IsAsciiHexDigit(c))) throw Invalid();
        var canRemove = root.GetProperty("canRemove").GetBoolean();
        var fields = Strings(root, ("gameName", 512), ("callsign", 512), ("roleTitle", 512));
        current();
        token.ThrowIfCancellationRequested();
        lock (_memberRemovalGate)
        {
            if (epoch != _memberRemovalEpoch) throw new AccountBridgeHostException("communities.identityUnavailable");
            foreach (var expired in _memberRemovalEdits.Where(pair => pair.Value.Expires <= DateTimeOffset.UtcNow).ToArray())
                _memberRemovalEdits.Remove(expired.Key);
            if (_memberRemovalEdits.Count >= 128) throw new AccountBridgeHostException("communities.refreshRequired");
            var nextRef = Guid.NewGuid().ToString("N");
            _memberRemovalEdits[nextRef] = new(scope, code, memberId, targetRef, memberRef, version, canRemove, DateTimeOffset.UtcNow.AddMinutes(15));
            fields["schemaVersion"] = 1;
            fields["targetRef"] = targetRef;
            fields["memberRef"] = memberRef;
            fields["editRef"] = nextRef;
            fields["canRemove"] = canRemove;
            return fields;
        }
    });

    private MemberRemovalEdit ResolveMemberRemovalEdit(string reference, string scope) =>
        _memberRemovalEdits.TryGetValue(reference, out var edit) && edit.Scope == scope && edit.Expires > DateTimeOffset.UtcNow
            ? edit : throw new AccountBridgeHostException("communities.refreshRequired");

    internal static void ValidateMemberRemoval(JsonElement body)
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

    internal async Task<CommunityCommand> RemoveMemberAsync(string bearer, JsonElement body, string scope,
        Action current, CancellationToken token)
    {
        ValidateMemberRemoval(body);
        var key = scope + "\0" + Text(body, "requestId", 32);
        var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(body.GetRawText())));
        if (!await _write.WaitAsync(0, token)) return new("rejected", "busy");
        var sent = false;
        var wasUncertain = false;
        try
        {
            current();
            MemberRemovalEdit edit;
            long epoch;
            string operation;
            lock (_memberRemovalGate)
            {
                epoch = _memberRemovalEpoch;
                if (_memberRemovalAttempts.TryGetValue(key, out var prior))
                    return prior.Hash == hash ? prior.Result : new("rejected", "requestChanged");
                if (_memberRemovalAttempts.Count >= 256) return new("rejected", "refreshRequired");
                edit = ResolveMemberRemovalEdit(Text(body, "editRef", 32), scope);
                operation = scope + "\0" + edit.Code + "\0" + edit.MemberId + "\0" + edit.Version;
                wasUncertain = _memberRemovalUncertain.Contains(operation);
                if (wasUncertain && !(body.TryGetProperty("confirmUncertainRetry", out var confirm) && confirm.GetBoolean()))
                    return new("unknown", "outcomeUnknown");
            }
            if (!edit.CanRemove) return new("rejected", "notAllowed");
            using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(_origin,
                "/api/fleets/members/remove?projection=member-removal&memberId=" + Uri.EscapeDataString(edit.MemberId) +
                "&version=" + Uri.EscapeDataString(edit.Version)))
            {
                Content = JsonContent.Create(new { fleetCode = edit.Code, targetGameName = "" })
            };
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
            deadline.CancelAfter(TimeSpan.FromSeconds(12));
            current();
            token.ThrowIfCancellationRequested();
            lock (_memberRemovalGate)
            {
                if (epoch != _memberRemovalEpoch) throw new AccountBridgeHostException("communities.identityUnavailable");
                _memberRemovalAttempts[key] = new(hash, new("unknown", "outcomeUnknown"));
                _memberRemovalUncertain.Add(operation);
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
                if (Number(json.RootElement, "schemaVersion", 1, 1) != 1 || Text(json.RootElement, "status", 16) != "accepted") throw Invalid();
                receipt = new("accepted");
            }
            current();
            lock (_memberRemovalGate)
            {
                if (epoch != _memberRemovalEpoch) throw new AccountBridgeHostException("communities.identityUnavailable");
                _memberRemovalAttempts[key] = new(hash, receipt);
                if (receipt.Status == "accepted" || receipt.Status == "rejected" && !wasUncertain) _memberRemovalUncertain.Remove(operation);
            }
            return receipt;
        }
        catch (Exception e) when (e is HttpRequestException or IOException or OperationCanceledException or AccountBridgeHostException or
            StarBridge.NativeBridge.BridgeStaleGenerationException or JsonException or InvalidOperationException or KeyNotFoundException or FormatException or OverflowException)
        { return new(sent ? "unknown" : "rejected", sent ? "outcomeUnknown" : "refreshRequired"); }
        finally { _write.Release(); }
    }
}
