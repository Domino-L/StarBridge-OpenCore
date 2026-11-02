using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    private long _marketplaceRevision;
    private readonly SemaphoreSlim _marketplaceWriteGate = new(1, 1);
    public async Task<object> MarketplaceListingsAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token)
    {
        var generation = Generation;
        RequireAccountProfileReadOwner(context, generation);
        var op = Marketplace.MarketplaceTradePolicy.Text(payload, "operation");
        var write = op is not ("read" or "templates");
        if (write && !await _marketplaceWriteGate.WaitAsync(0, token)) throw new AccountBridgeHostException("marketplace.busy");
        try
        {
            var session = RequireSession(context);
            if (write && !session.Capabilities.Contains("trade.write", StringComparer.Ordinal))
                throw new AccountBridgeHostException("marketplace.reauthorize_required");
            bool Current() => !_disposed && Generation == generation && CurrentContext == context && !_localModeSessionLoopsStopped;
            var result = await _oauth.MarketplaceListingsAsync(session, payload, Current, token);
            lock (_realtimeGate)
            {
                token.ThrowIfCancellationRequested();
                RequireAccountProfileReadOwner(context, generation);
                RequireSameSession(session, result.ActiveSession);
                _session = result.ActiveSession;
            }
            return new { schemaVersion = 1, data = result.Data };
        }
        finally { if (write) _marketplaceWriteGate.Release(); }
    }
    public async Task<object> MarketplaceTradeAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token)
    {
        var generation = Generation;
        RequireAccountProfileReadOwner(context, generation);
        var op = Marketplace.MarketplaceTradePolicy.Text(payload, "operation");
        if (op == "revision") return new { schemaVersion = 1, data = new { revision = Interlocked.Read(ref _marketplaceRevision) } };
        var write = op is not ("list" or "detail");
        if (write && !await _marketplaceWriteGate.WaitAsync(0, token)) throw new AccountBridgeHostException("marketplace.busy");
        try
        {
            var session = RequireSession(context);
            if (write && !session.Capabilities.Contains("trade.write", StringComparer.Ordinal))
                throw new AccountBridgeHostException("marketplace.reauthorize_required");
            bool Current() => !_disposed && Generation == generation && CurrentContext == context && !_localModeSessionLoopsStopped;
            var result = await _oauth.MarketplaceTradeAsync(session, payload, Current, token);
            lock (_realtimeGate)
            {
                token.ThrowIfCancellationRequested();
                RequireAccountProfileReadOwner(context, generation);
                RequireSameSession(session, result.ActiveSession);
                _session = result.ActiveSession;
            }
            if (write) Interlocked.Increment(ref _marketplaceRevision);
            return new { schemaVersion = 1, data = result.Data };
        }
        finally { if (write) _marketplaceWriteGate.Release(); }
    }
    // 0.7.2 G5/G6/G7: received reviews, own reports, own blocklist (read) and unblock (write).
    public async Task<object> MarketplaceRecordsAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token)
    {
        var generation = Generation;
        RequireAccountProfileReadOwner(context, generation);
        var write = Marketplace.MarketplaceTradePolicy.Text(payload, "operation") == "unblock";
        if (write && !await _marketplaceWriteGate.WaitAsync(0, token)) throw new AccountBridgeHostException("marketplace.busy");
        try
        {
            var session = RequireSession(context);
            bool Current() => !_disposed && Generation == generation && CurrentContext == context && !_localModeSessionLoopsStopped;
            var result = await _oauth.MarketplaceRecordsAsync(session, payload, Current, token);
            lock (_realtimeGate)
            {
                token.ThrowIfCancellationRequested();
                RequireAccountProfileReadOwner(context, generation);
                RequireSameSession(session, result.ActiveSession);
                _session = result.ActiveSession;
            }
            return new { schemaVersion = 1, data = result.Data };
        }
        finally { if (write) _marketplaceWriteGate.Release(); }
    }
    // 0.7.2 G9: SCM trade messages. Live pushes: ScmAccountBridgeHost.TradeChat.cs.
    public async Task<object> MarketplaceChatAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token)
    {
        var generation = Generation;
        RequireAccountProfileReadOwner(context, generation);
        var session = RequireSession(context);
        bool Current() => !_disposed && Generation == generation && CurrentContext == context && !_localModeSessionLoopsStopped;
        var result = await _oauth.MarketplaceChatAsync(session, payload, Current, () => EnsureTradeChat(context, generation), token);
        lock (_realtimeGate)
        {
            token.ThrowIfCancellationRequested();
            RequireAccountProfileReadOwner(context, generation);
            RequireSameSession(session, result.ActiveSession);
            _session = result.ActiveSession;
        }
        return new { schemaVersion = 1, data = result.Data };
    }
    // 0.7.2 G1: SCM contracts; writes share the hall write gate and bump the revision.
    public async Task<object> MarketplaceContractsAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token)
    {
        var generation = Generation;
        RequireAccountProfileReadOwner(context, generation);
        var write = System.Text.RegularExpressions.Regex.IsMatch(Marketplace.MarketplaceTradePolicy.Text(payload, "operation") ?? "", "^(create|apply|quit|start|complete|cancel|review|dispute)$");
        if (write && !await _marketplaceWriteGate.WaitAsync(0, token)) throw new AccountBridgeHostException("marketplace.busy");
        try
        {
            var session = RequireSession(context);
            bool Current() => !_disposed && Generation == generation && CurrentContext == context && !_localModeSessionLoopsStopped;
            var result = await _oauth.MarketplaceContractsAsync(session, payload, Current, token);
            lock (_realtimeGate)
            {
                token.ThrowIfCancellationRequested();
                RequireAccountProfileReadOwner(context, generation);
                RequireSameSession(session, result.ActiveSession);
                _session = result.ActiveSession;
            }
            if (write) Interlocked.Increment(ref _marketplaceRevision);
            return new { schemaVersion = 1, data = result.Data };
        }
        finally { if (write) _marketplaceWriteGate.Release(); }
    }
    // 0.7.2 G2: the member's own warehouse, read only.
    public async Task<object> MarketplaceWarehouseAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token)
    {
        var generation = Generation;
        RequireAccountProfileReadOwner(context, generation);
        var session = RequireSession(context);
        bool Current() => !_disposed && Generation == generation && CurrentContext == context && !_localModeSessionLoopsStopped;
        var result = await _oauth.MarketplaceWarehouseAsync(session, payload, Current, token);
        lock (_realtimeGate)
        {
            token.ThrowIfCancellationRequested();
            RequireAccountProfileReadOwner(context, generation);
            RequireSameSession(session, result.ActiveSession);
            _session = result.ActiveSession;
        }
        return new { schemaVersion = 1, data = result.Data };
    }
    // 0.7.2 G8: SCM station messages. Read marks do not take the hall write gate.
    public async Task<object> MarketplaceNoticesAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token)
    {
        long generation;
        Auth.ScmOAuthSession session;
        lock (_realtimeGate)
        {
            generation = Generation;
            RequireAccountProfileReadOwner(context, generation);
            session = RequireSession(context);
        }
        bool Current() => !_disposed && Generation == generation && CurrentContext == context && !_localModeSessionLoopsStopped;
        var readConfirmed = false;
        try
        {
            var result = await _oauth.MarketplaceNoticesAsync(session, payload, Current, token, _realtimeGate,
                onReadConfirmed: () => readConfirmed = true);
            lock (_realtimeGate)
            {
                token.ThrowIfCancellationRequested();
                RequireAccountProfileReadOwner(context, generation);
                RequireSameSession(session, result.ActiveSession);
                _session = result.ActiveSession;
            }
            return new { schemaVersion = 1, data = result.Data };
        }
        finally
        {
            // An explicit SCM success survives caller cancellation. Generation still fences stale
            // sessions; merge normal and cancelled exits into one invalidation without retrying.
            if (readConfirmed) ObserveInboxReadChanged(generation);
        }
    }
    public async Task<object> ReadMarketplaceReputationAsync(BridgeAccountContext context, CancellationToken token)
    {
        var generation = Generation;
        RequireAccountProfileReadOwner(context, generation);
        var session = RequireSession(context);
        var result = await _oauth.ReadMarketplaceReputationAsync(session, token);
        lock (_realtimeGate)
        {
            token.ThrowIfCancellationRequested();
            RequireAccountProfileReadOwner(context, generation);
            RequireSameSession(session, result.ActiveSession);
            _session = result.ActiveSession;
        }
        return new { schemaVersion = 1, readAt = DateTimeOffset.UtcNow, data = new { point = result.Point } };
    }
}
