namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    private long _inboxPushGeneration = -1;
    private long _inboxScmRevision;
    private sealed record ScmInboxPage(long Generation, long Revision, DateTimeOffset ReadAt,
        Core.TrustSafety.NotificationItemContract[] Items);
    private ScmInboxPage? _inboxScmPage;
    internal event Action<long, bool>? InboxChanged;
    internal bool InboxPushHealthy => !_disposed && !_reauthorizationRequired && !_credentialTemporarilyUnavailable &&
        Volatile.Read(ref _inboxPushGeneration) == Generation;

    internal bool IsTradeNoticeUnread(Notifications.TradeNotificationEvent notice) =>
        _session is { } session && _oauth.StationNotificationUnread(Auth.OAuthPkceClient.ChatOwner(session), notice);

    // Called only by the current account socket, while holding _realtimeGate.
    private void ObserveInboxPush(bool healthy)
    {
        if (!healthy) Volatile.Write(ref _inboxScmPage, null);
        Interlocked.Increment(ref _inboxScmRevision);
        Volatile.Write(ref _inboxPushGeneration, healthy ? Generation : -1);
        InboxChanged?.Invoke(Generation, healthy);
    }

    private void ObserveInboxReadChanged(long generation)
    {
        lock (_realtimeGate)
        {
            if (_disposed || generation != Generation) return;
            Interlocked.Increment(ref _inboxScmRevision);
            InboxChanged?.Invoke(generation, InboxPushHealthy);
            Interlocked.Increment(ref _marketplaceRevision);
            MarketplaceChanged?.Invoke(generation);
        }
    }

    private async Task<Core.TrustSafety.NotificationItemContract[]> ReadScmInboxPageAsync(
        Auth.ScmOAuthSession session, Func<bool> current, bool allowCache, CancellationToken token)
    {
        var generation = Generation;
        var revision = Interlocked.Read(ref _inboxScmRevision);
        var cached = Volatile.Read(ref _inboxScmPage);
        var age = cached is null ? TimeSpan.MaxValue : DateTimeOffset.UtcNow - cached.ReadAt;
        if (allowCache && InboxPushHealthy && cached?.Generation == generation && cached.Revision == revision &&
            age >= TimeSpan.Zero && age < TimeSpan.FromMinutes(5)) return cached.Items;
        var items = await _oauth.ReadNotificationMessagesAsync(session, current, token, _realtimeGate).ConfigureAwait(false);
        // A push during the read must still force the next read back to REST.
        if (current() && generation == Generation && revision == Interlocked.Read(ref _inboxScmRevision))
            Volatile.Write(ref _inboxScmPage, new(generation, revision, DateTimeOffset.UtcNow, items));
        return items;
    }

    // Polling fallback (hotfix 10-29): a new unread trade station message found by a REST read
    // takes the same path as a live push — same owner/generation fence, same unread check.
    private void OnStationTradeDiscovered(string owner, Notifications.TradeNotificationEvent notice, Func<bool> readStillCurrent)
    {
        lock (_realtimeGate)
        {
            // The read's own predicate pins owner, context and generation; only then is the
            // current generation the one that read belonged to. Lock order: Host gate -> receipt gate.
            if (_disposed || _reauthorizationRequired || _credentialTemporarilyUnavailable ||
                _session is not { } session || Auth.OAuthPkceClient.ChatOwner(session) != owner || !readStillCurrent()) return;
            if (CurrentContext is { } context && IsTradeNoticeUnread(notice))
                MarketplaceNoticePushed?.Invoke(context, Generation, notice);
        }
    }

    private async Task DeliverStationPushAsync(Auth.ScmOAuthSession session, NativeBridge.BridgeAccountContext owner,
        long generation, System.Text.Json.JsonElement row, Func<bool> current)
    {
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(30));
        var notice = await _oauth.ReconcileStationPushAsync(session, row, current, _realtimeGate, timeout.Token).ConfigureAwait(false);
        lock (_realtimeGate)
        {
            if (notice is not null && current() && IsTradeNoticeUnread(notice))
                MarketplaceNoticePushed?.Invoke(owner, generation, notice);
        }
    }
}
