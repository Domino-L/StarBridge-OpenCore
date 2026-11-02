using StarBridge.NativeBridge;
using StarBridge.HostRuntime.Auth;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    // 0.7.2 G9: the SCM trade-chat socket runs for the whole signed-in session (user decision
    // 2026-10-21, "一直保持，并且需要无延迟同步"). Each push already carries the message, projected
    // without SCM member ids, and goes straight to Flutter as "marketplace.chatPushed".
    internal event Action<long, object>? MarketplaceChatPushed;
    internal event Action<BridgeAccountContext, long, Notifications.TradeNotificationEvent>? MarketplaceNoticePushed;

    internal bool AllowsTradeNotification(bool chat)
    {
        var session = _session;
        return session is not null && GameplayTimeContext is not null &&
            session.Capabilities.Contains(chat ? "trade.read" : "profile.read", StringComparer.Ordinal) &&
            (!chat || session.Capabilities.Contains("trade.write", StringComparer.Ordinal));
    }

    private ScmChatConnection EnsureTradeChat(BridgeAccountContext owner, long generation)
    {
        var session = RequireSession(owner);
        if (!session.Capabilities.Contains("trade.write", StringComparer.Ordinal))
            throw new AccountBridgeHostException("marketplace.reauthorize_required");
        bool IsCurrent() => !_disposed && Generation == generation && CurrentContext == owner && !_localModeSessionLoopsStopped;
        return _oauth.StartChat(OAuthPkceClient.ChatOwner(session), async token =>
        {
            // Same discipline as the presence ticket: one credential mutation at a time.
            await _mutationGate.WaitAsync(token).ConfigureAwait(false);
            try
            {
                if (!IsCurrent()) throw new OperationCanceledException(token);
                var current = RequireSession(owner);
                var (ticket, active) = await _oauth.IssueChatTicketAsync(current, token).ConfigureAwait(false);
                lock (_realtimeGate)
                {
                    if (!IsCurrent()) throw new OperationCanceledException(token);
                    RequireSameSession(current, active);
                    _session = active;
                }
                return ticket;
            }
            finally { _mutationGate.Release(); }
        }, payload =>
        {
            if (IsCurrent()) MarketplaceChatPushed?.Invoke(generation, payload);
        });
    }

    private void StartTradeChatWithRealtime(ScmOAuthSession session, BridgeAccountContext owner, long generation)
    {
        if (!session.Capabilities.Contains("trade.write", StringComparer.Ordinal)) return;
        try { EnsureTradeChat(owner, generation); }
        catch (AccountBridgeHostException) { }
    }
}
