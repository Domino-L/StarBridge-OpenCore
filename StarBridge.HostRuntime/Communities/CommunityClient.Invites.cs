using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Communities;

internal sealed record CommunityInviteView(string PreviewRef, string Name, string Code, string Commander,
    int MemberCount, string JoinPolicy, DateTimeOffset? ExpiresAt, int RemainingUses, bool AlreadyMember)
{
    public int SchemaVersion => 1;
    public string AcceptMode => "direct";
    public bool MembershipConflict { get; init; }
}

internal sealed partial class CommunityClient
{
    private sealed record InvitePreview(string InviteCode, string Code, string Scope, string TargetRef, DateTimeOffset Expires, bool WpfS2);
    private sealed record InviteAttempt(string PreviewRef, CommunityCommand Result);
    private readonly object _inviteGate = new();
    private readonly Dictionary<string, InvitePreview> _invitePreviews = new();
    private readonly Dictionary<string, InviteAttempt> _inviteAttempts = new();
    private readonly Dictionary<string, CommunityCommand> _inviteOutcomes = new();
    private long _inviteEpoch;

    internal void InvalidateInvitePreviews()
    {
        lock (_inviteGate)
        {
            _inviteEpoch++;
            _invitePreviews.Clear();
            _inviteAttempts.Clear();
            _inviteOutcomes.Clear();
            _admissionTargets.Clear();
            _admissionAttempts.Clear();
            _admissionUncertain.Clear();
        }
    }

    internal static string ParseInvitePreview(JsonElement body)
    {
        Validate(body, "inviteCode");
        var code = Text(body, "inviteCode", 128).Replace(" ", "", StringComparison.Ordinal).Trim().ToUpperInvariant();
        return code.Length > 0 ? code : throw Invalid();
    }

    internal static (string RequestId, string PreviewRef) ParseInviteAcceptance(JsonElement body)
    {
        Validate(body, "requestId", "previewRef");
        string Reference(string key)
        {
            var value = Text(body, key, 32);
            return value.Length == 32 && value.All(c => c is >= 'a' and <= 'f' or >= '0' and <= '9') ? value : throw Invalid();
        }
        return (Reference("requestId"), Reference("previewRef"));
    }

    internal Task<object> PreviewInviteAsync(string bearer, JsonElement body, string scope, Action current, CancellationToken token, bool wpfS2 = false) =>
        GuardWorkspace(async () =>
        {
            var code = ParseInvitePreview(body);
            var epoch = Interlocked.Read(ref _inviteEpoch);
            current();
            var root = await InvitePreviewJson(bearer, code, token);
            current();
            var fleetCode = Text(root, "fleetCode", 256);
            var name = Text(root, "fleetName", 512);
            var commander = Text(root, "commander", 512);
            var joinPolicy = Text(root, "joinPolicy", 32);
            var members = Number(root, "totalMembers", 0, int.MaxValue);
            var remaining = Number(root, "remainingUses", -1, int.MaxValue);
            var expires = root.GetProperty("expiresAt").GetDateTimeOffset();
            if (fleetCode.Length == 0 || name.Length == 0 || Text(root, "acceptMode", 16) != "Direct" ||
                remaining == 0 || expires != default && expires <= DateTimeOffset.UtcNow) throw new AccountBridgeHostException("communities.inviteInvalid");
            var targetRef = Guid.NewGuid().ToString("N");
            lock (_inviteGate)
            {
                if (epoch != _inviteEpoch) throw new AccountBridgeHostException("communities.identityUnavailable");
                if (!wpfS2) _targets[targetRef] = new(fleetCode, scope, DateTimeOffset.UtcNow.AddMinutes(5));
            }
            var mine = await ReadInviteMembership(bearer, fleetCode, targetRef, scope, wpfS2, token);
            current();
            lock (_inviteGate)
            {
                if (epoch != _inviteEpoch) throw new AccountBridgeHostException("communities.identityUnavailable");
                foreach (var item in _invitePreviews.Where(row => row.Value.Expires <= DateTimeOffset.UtcNow).ToArray())
                    _invitePreviews.Remove(item.Key);
                if (_invitePreviews.Count >= 128) throw new AccountBridgeHostException("communities.refreshRequired");
                var reference = Guid.NewGuid().ToString("N");
                var lifetime = DateTimeOffset.UtcNow.AddMinutes(5);
                _invitePreviews[reference] = new(code, fleetCode, scope, targetRef,
                    expires != default && expires < lifetime ? expires : lifetime, wpfS2);
                return new CommunityInviteView(reference, name, fleetCode, commander, members, joinPolicy,
                    expires == default ? null : expires, remaining, mine.Joined) { MembershipConflict = mine.Conflict };
            }
        });

    private async Task<(bool Joined, bool Conflict)> ReadInviteMembership(string bearer, string code,
        string reference, string scope, bool wpfS2, CancellationToken token)
    {
        if (wpfS2)
        {
            // Same authenticated S2 membership/snapshot reader as the joined list.
            // An invitation may name an unlisted organization: discovery filters
            // must not decide whether the current account is already a member.
            var fleets = await WpfS2Membership(bearer, token);
            var joined = fleets.Any(row => Text(row, "code", 256).Equals(code, StringComparison.OrdinalIgnoreCase));
            return (joined, !joined && fleets.Length != 0);
        }
        var mine = await ReadAsync(bearer, new("mine", "", null, reference), scope, token);
        return (mine.Items.Any(row => row.Relationship is "member" or "owner"), false);
    }

    private async Task<JsonElement> InvitePreviewJson(string bearer, string code, CancellationToken token)
    {
        using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(_origin, "/api/fleets/invites/preview"))
            { Content = JsonContent.Create(new { InviteCode = code }) };
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
        deadline.CancelAfter(TimeSpan.FromSeconds(12));
        using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
        if (response.StatusCode == HttpStatusCode.NotFound) throw new AccountBridgeHostException("communities.inviteInvalid");
        if (response.StatusCode == HttpStatusCode.Unauthorized) throw new AccountBridgeHostException("communities.identityUnavailable");
        if (response.StatusCode == HttpStatusCode.Forbidden) throw new AccountBridgeHostException("communities.notAllowed");
        if (!response.IsSuccessStatusCode) throw new AccountBridgeHostException("communities.unavailable", true);
        using var input = await response.Content.ReadAsStreamAsync(deadline.Token);
        using var buffer = new MemoryStream();
        var chunk = new byte[4096]; int count;
        while ((count = await input.ReadAsync(chunk, deadline.Token)) > 0)
        {
            if (buffer.Length + count > 16 * 1024) throw Invalid();
            buffer.Write(chunk, 0, count);
        }
        using var json = JsonDocument.Parse(buffer.ToArray());
        return json.RootElement.Clone();
    }

    internal async Task<CommunityCommand> AcceptInviteAsync(string bearer, JsonElement body, string scope,
        Action current, CancellationToken token)
    {
        var (requestId, previewRef) = ParseInviteAcceptance(body);
        var epoch = Interlocked.Read(ref _inviteEpoch);
        var requestKey = scope + "\0" + requestId;
        if (!await _write.WaitAsync(0, token)) return new("rejected", "busy");
        bool sent = false;
        string? outcomeKey = null;
        CommunityCommand Finish(CommunityCommand result)
        {
            lock (_inviteGate)
            {
                if (epoch == _inviteEpoch)
                {
                    _inviteAttempts[requestKey] = new(previewRef, result);
                    if (sent && outcomeKey is not null)
                    {
                        // Definitive refusal did not admit anyone. A new explicit
                        // intent may retry after permission/state recovery.
                        if (result.Status == "rejected") _inviteOutcomes.Remove(outcomeKey);
                        else _inviteOutcomes[outcomeKey] = result;
                    }
                }
            }
            return result;
        }
        try
        {
            current();
            InvitePreview preview;
            lock (_inviteGate)
            {
                if (epoch != _inviteEpoch) return new("rejected", "identityUnavailable");
                if (_inviteAttempts.TryGetValue(requestKey, out var previous))
                    return previous.PreviewRef == previewRef ? previous.Result : new("rejected", "requestChanged");
                if (_inviteAttempts.Count >= 256) return new("rejected", "refreshRequired");
                if (!_invitePreviews.TryGetValue(previewRef, out preview!) || preview.Scope != scope || preview.Expires <= DateTimeOffset.UtcNow)
                    return new("rejected", "refreshRequired");
            }
            outcomeKey = scope + "\0" + preview.InviteCode;
            // Membership is checked before any consumption, including reconciliation
            // after a lost reply. Modern multi-membership remains independent;
            // S2 retains its original single-membership guard, never auto-leaving.
            var mine = await ReadInviteMembership(bearer, preview.Code, preview.TargetRef, scope, preview.WpfS2, token);
            current();
            if (mine.Joined) return Finish(new("accepted"));
            if (mine.Conflict) return Finish(new("rejected", "membershipConflict"));
            lock (_inviteGate)
            {
                if (epoch != _inviteEpoch) return new("rejected", "identityUnavailable");
                if (_inviteOutcomes.TryGetValue(outcomeKey, out var previous))
                    return Finish(previous.Status == "accepted" ? new("rejected", "refreshRequired") : previous);
            }
            using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(_origin, "/api/fleets/invites/accept"))
                { Content = JsonContent.Create(new { InviteCode = preview.InviteCode }) };
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
            if (!response.IsSuccessStatusCode) return Finish(response.StatusCode switch
            {
                HttpStatusCode.NotFound => new("rejected", "inviteInvalid"),
                HttpStatusCode.BadRequest or HttpStatusCode.Conflict => new("rejected", "refreshRequired"),
                HttpStatusCode.Forbidden => new("rejected", "notAllowed"),
                HttpStatusCode.Unauthorized => new("rejected", "identityUnavailable"),
                _ => new("unknown", "outcomeUnknown")
            });
            // Do not materialize the legacy bulk organization response. Confirm through
            // the bounded, viewer-filtered membership directory instead.
            var joined = await ReadInviteMembership(bearer, preview.Code, preview.TargetRef, scope, preview.WpfS2, deadline.Token);
            current();
            return Finish(joined.Joined
                ? new("accepted") : new("unknown", "outcomeUnknown"));
        }
        catch (Exception error) when (error is HttpRequestException or IOException or OperationCanceledException or
            AccountBridgeHostException or StarBridge.NativeBridge.BridgeStaleGenerationException or JsonException or
            InvalidOperationException or KeyNotFoundException or FormatException)
        { return Finish(new(sent ? "unknown" : "rejected", sent ? "outcomeUnknown" : "refreshRequired")); }
        finally { _write.Release(); }
    }
}
