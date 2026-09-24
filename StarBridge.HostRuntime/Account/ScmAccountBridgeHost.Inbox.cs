namespace StarBridge.HostRuntime.Account;

using System.Text.Json;
using StarBridge.NativeBridge;

internal sealed partial class ScmAccountBridgeHost
{
    private sealed record InboxLease(BridgeAccountContext Owner, long Generation, DateTimeOffset Expires, Dictionary<string, string> Ids);
    private InboxLease? _inboxLease;

    public async Task<object> ReadNotificationInboxAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token)
    {
        AccountSafetyRequest.Read(payload);
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
        var ids = new Dictionary<string, string>();
        var items = result.Result.Items.Where(x => x.ActionTarget != "friend_chat")
            .OrderByDescending(x => x.CreatedAt).Select(x => {
                var reference = Guid.NewGuid().ToString("N");
                ids.Add(reference, x.NotificationId);
                return new { reference, x.Category, x.Priority, x.Title, x.Body, x.CreatedAt,
                    read = x.ReadAt is not null, x.ActionTarget, x.ActionLabel, x.IsAvailable, x.GroupCount };
            }).ToArray();
        _inboxLease = new(context, generation, DateTimeOffset.UtcNow.AddMinutes(10), ids);
        return new { schemaVersion = 1, items, unreadCount = items.Count(x => !x.read), result.Result.UpdatedAt };
    }

    public async Task<object> MarkNotificationInboxReadAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token)
    {
        if (payload.ValueKind != JsonValueKind.Object || payload.EnumerateObject().Count() != 2 ||
            !payload.TryGetProperty("schemaVersion", out var schema) || schema.GetInt32() != 1 ||
            !payload.TryGetProperty("references", out var rows) || rows.ValueKind != JsonValueKind.Array ||
            rows.GetArrayLength() is < 1 or > 5000)
            throw new AccountBridgeHostException("notificationInbox.invalid_request");
        var lease = _inboxLease;
        var session = RequireRelaySession(context);
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
        await client.MarkInboxReadAsync(session.AccessToken, refs.Select(x => lease!.Ids[x]).ToArray(), Current, token);
        Current();
        return new { schemaVersion = 1, confirmed = true };
    }
}
