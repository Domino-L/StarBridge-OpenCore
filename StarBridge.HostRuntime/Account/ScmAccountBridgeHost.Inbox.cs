namespace StarBridge.HostRuntime.Account;

using System.Text.Json;
using System.Net.Http;
using StarBridge.HostRuntime.Auth;
using StarBridge.Core.TrustSafety;
using StarBridge.NativeBridge;

internal sealed partial class ScmAccountBridgeHost
{
    private sealed record InboxLease(BridgeAccountContext Owner, long Generation, DateTimeOffset Expires, Dictionary<string, string> Ids);
    private InboxLease? _inboxLease;

    private static bool InboxScmFailure(Exception e) => e is HttpRequestException or
        OperationCanceledException or ScmApiProtocolException or JsonException or
        AccountBridgeHostException;

    public async Task<object> ReadNotificationInboxAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token)
    {
        var allowScmCache = AccountSafetyRequest.InboxRead(payload);
        if (_reauthorizationRequired || _credentialTemporarilyUnavailable)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        var session = RequireRelaySession(context);
        var generation = Generation;
        var client = _accountSafety ?? throw new AccountBridgeHostException("notificationInbox.unavailable");
        var result = await SendRelayRequestAsync(session, (active, ct) => client.ReadInboxAsync(active.AccessToken, ct), token);
        token.ThrowIfCancellationRequested();
        if (_disposed || generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
        RequireSameRelaySession(RequireRelaySession(context), result.ActiveSession);
        _session = result.ActiveSession.Scm;
        bool Current() => !_disposed && generation == Generation && CurrentContext == context &&
            !_reauthorizationRequired && !_credentialTemporarilyUnavailable;
        NotificationItemContract[] scmItems = [];
        if (result.ActiveSession.Scm is { } scm && scm.Capabilities.Contains("profile.read", StringComparer.Ordinal))
        {
            try { scmItems = await ReadScmInboxPageAsync(scm, Current, allowScmCache, token); }
            catch (Exception e) when (InboxScmFailure(e) && !token.IsCancellationRequested) { }
        }
        token.ThrowIfCancellationRequested();
        if (!Current()) throw new BridgeStaleGenerationException(generation, Generation);
        RequireSameRelaySession(RequireRelaySession(context), result.ActiveSession);
        var ids = new Dictionary<string, string>();
        var items = result.Result.Items.Concat(scmItems).Where(x => x.ActionTarget != "friend_chat")
            .OrderByDescending(x => x.CreatedAt).Select(x => {
                var reference = Guid.NewGuid().ToString("N");
                ids.Add(reference, x.NotificationId);
                var eventKey = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(
                    System.Text.Encoding.UTF8.GetBytes(JsonSerializer.Serialize(context) + "\n" + x.NotificationId))).ToLowerInvariant();
                return new { reference, eventKey, x.Category, x.Priority, x.Title, x.Body, x.CreatedAt,
                    read = x.ReadAt is not null, x.ActionTarget, x.ActionLabel, x.IsAvailable, x.GroupCount };
            }).ToArray();
        _inboxLease = new(context, generation, DateTimeOffset.UtcNow.AddMinutes(10), ids);
        return new { schemaVersion = 1, items, unreadCount = items.Count(x => !x.read), result.Result.UpdatedAt,
            scmPushHealthy = InboxPushHealthy };
    }

    public async Task<object> MarkNotificationInboxReadAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token)
    {
        if (payload.ValueKind != JsonValueKind.Object || payload.EnumerateObject().Count() != 2 ||
            !payload.TryGetProperty("schemaVersion", out var schema) || schema.GetInt32() != 1 ||
            !payload.TryGetProperty("references", out var rows) || rows.ValueKind != JsonValueKind.Array ||
            rows.GetArrayLength() is < 1 or > 5000)
            throw new AccountBridgeHostException("notificationInbox.invalid_request");
        var lease = _inboxLease;
        var session = await ReadDirectRelaySessionAsync(context, token).ConfigureAwait(false);
        void Current() {
            token.ThrowIfCancellationRequested();
            if (_reauthorizationRequired || _credentialTemporarilyUnavailable)
                throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
            if (_disposed || lease is null || lease.Owner != context || lease.Generation != Generation ||
                lease.Expires <= DateTimeOffset.UtcNow || !ReferenceEquals(lease, _inboxLease))
                throw new AccountBridgeHostException("notificationInbox.stale");
            RequireSameRelaySession(RequireRelaySession(context), session);
        }
        Current();
        var refs = rows.EnumerateArray().Select(x => x.GetString() ?? "").ToArray();
        if (refs.Distinct().Count() != refs.Length || refs.Any(x => !lease!.Ids.ContainsKey(x)))
            throw new AccountBridgeHostException("notificationInbox.invalid_request");
        var client = _accountSafety ?? throw new AccountBridgeHostException("notificationInbox.unavailable");
        var sources = refs.Select(x => lease!.Ids[x]).ToArray();
        var relayIds = sources.Where(x => !x.StartsWith("scm:", StringComparison.Ordinal)).ToArray();
        var anyConfirmed = false;
        try
        {
            if (relayIds.Length > 0)
            {
                await client.MarkInboxReadAsync(session.AccessToken, relayIds, Current, token);
                anyConfirmed = true;
            }
            foreach (var source in sources.Where(x => x.StartsWith("scm:", StringComparison.Ordinal)))
            {
                Current();
                if (session.Scm is not { } scm || !scm.Capabilities.Contains("profile.write", StringComparer.Ordinal))
                    return new { schemaVersion = 1, confirmed = false };
                try
                {
                    var result = await _oauth.MarketplaceNoticesAsync(scm, BridgePayload.From(new {
                        schemaVersion = 1, operation = "read",
                        id = long.Parse(source.AsSpan(4), System.Globalization.CultureInfo.InvariantCulture)
                    }), () => { Current(); return true; }, token, _realtimeGate, onReadConfirmed: () => anyConfirmed = true);
                    var confirmed = BridgePayload.From(result.Data).GetProperty("confirmed").GetBoolean();
                    anyConfirmed |= confirmed;
                    Current();
                    RequireSameSession(scm, result.ActiveSession);
                    _session = result.ActiveSession;
                    if (!confirmed) return new { schemaVersion = 1, confirmed = false };
                }
                catch (Exception e) when (InboxScmFailure(e) && !token.IsCancellationRequested)
                {
                    Current();
                    return new { schemaVersion = 1, confirmed = false };
                }
            }
            Current();
            return new { schemaVersion = 1, confirmed = true };
        }
        finally
        {
            // A successful prefix is permanent, even when a later write fails or the caller exits.
            // The single event wakes the existing readers; its revision forbids healthy-cache reuse.
            if (anyConfirmed) ObserveInboxReadChanged(lease!.Generation);
        }
    }
}
