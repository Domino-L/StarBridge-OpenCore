using System.Globalization;
using System.Text.Json;
using StarBridge.HostRuntime.Marketplace;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

// Native-only seam: it does not add a Bridge capability or expose an identity.
internal interface IMarketplaceTraderProfileTargets
{
    Task<Func<JsonElement, string?>?> PrepareMarketTraderReferencesAsync(
        BridgeAccountContext context, long generation, CancellationToken token);
}

internal sealed partial class ScmAccountBridgeHost : IMarketplaceTraderProfileTargets
{
    private const int MarketTraderCapacity = 4096;
    private readonly object _marketTraderGate = new();
    private sealed record MarketTraderTarget(long Id, string Row, string Scope, DateTimeOffset Expires);
    private readonly Dictionary<string, MarketTraderTarget> _marketTraderTargets = new(StringComparer.Ordinal);
    private readonly Dictionary<(long Id, string Row, string Scope), string> _marketTraderReferences = new();
    private sealed class MarketTraderViewerLookup(string scope)
    {
        internal string Scope { get; } = scope;
        internal TaskCompletionSource<long> Completion { get; } = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal DateTimeOffset RetryAfter { get; set; }
    }
    private MarketTraderViewerLookup? _marketTraderViewer;
    internal Func<DateTimeOffset> MarketTraderClock { get; init; } = () => DateTimeOffset.UtcNow;

    public async Task<Func<JsonElement, string?>?> PrepareMarketTraderReferencesAsync(
        BridgeAccountContext context, long generation, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        Auth.ScmOAuthSession session;
        var scope = FriendScope(context, generation);
        MarketTraderViewerLookup lookup;
        var start = false;
        lock (_realtimeGate)
        {
            if (!MarketTraderOwnerCurrent(context, generation) || _session is not { } active ||
                !active.Capabilities.Contains("profile.read", StringComparer.Ordinal) ||
                !active.Capabilities.Contains("trade.read", StringComparer.Ordinal)) return null;
            session = active;
            lock (_marketTraderGate)
            {
                var cached = _marketTraderViewer;
                if (cached is null || cached.Scope != scope ||
                    cached.Completion.Task.IsCompleted && cached.RetryAfter <= MarketTraderClock() &&
                    (!cached.Completion.Task.IsCompletedSuccessfully || cached.Completion.Task.Result == 0))
                {
                    _marketTraderViewer = cached = new(scope);
                    start = true;
                    // A cancelled waiter must not leave an unobserved task failure.
                    _ = cached.Completion.Task.ContinueWith(completed => { _ = completed.Exception; }, CancellationToken.None,
                        TaskContinuationOptions.OnlyOnFaulted | TaskContinuationOptions.ExecuteSynchronously, TaskScheduler.Default);
                }
                lookup = cached;
            }
        }
        if (start) _ = CompleteMarketTraderViewerAsync(lookup, session, context, generation);
        // Each caller cancels only its own wait; transport/session recovery has
        // its own bounded deadline and is shared by all callers in this scope.
        var viewer = await lookup.Completion.Task.WaitAsync(token);
        lock (_realtimeGate)
        {
            token.ThrowIfCancellationRequested();
            if (viewer == 0 || !MarketTraderOwnerCurrent(context, generation)) return null;
        }
        return row => RegisterMarketTrader(row, viewer, scope, context, generation);
    }

    private async Task CompleteMarketTraderViewerAsync(MarketTraderViewerLookup lookup,
        Auth.ScmOAuthSession session, BridgeAccountContext context, long generation)
    {
        long viewer = 0;
        Exception? failure = null;
        try
        {
            // Subject is an HMAC, never the numeric SCM member ID. Read only
            // the ID from the already-authorized self trade-profile route.
            var result = await _oauth.LoadMarketTraderViewerAsync(session, CancellationToken.None);
            lock (_realtimeGate)
            {
                if (MarketTraderOwnerCurrent(context, generation))
                {
                    RequireSameSession(session, RequireSession(context));
                    RequireSameSession(session, result.ActiveSession);
                    // Marketplace reads can overlap the ordinary account lane.
                    CommitSharingSession(new(session), new(result.ActiveSession));
                    viewer = result.Result;
                }
            }
        }
        catch (Exception error) when (error is HttpRequestException or IOException or JsonException or
            Auth.ScmApiProtocolException or AccountBridgeHostException or OperationCanceledException)
        { } // Cannot exclude self reliably: preserve quotes without profile actions.
        catch (Exception error) { failure = error; }
        lock (_marketTraderGate)
        {
            // A late old-scope result only completes its own waiters. It never
            // replaces the lookup installed by a new account or generation.
            lookup.RetryAfter = MarketTraderClock().AddSeconds(60);
            if (failure is not null) lookup.Completion.TrySetException(failure);
            else lookup.Completion.TrySetResult(viewer);
        }
    }

    private bool MarketTraderOwnerCurrent(BridgeAccountContext context, long generation) =>
        !_disposed && generation == Generation && context == CurrentContext &&
        !_reauthorizationRequired && !_credentialTemporarilyUnavailable && !_localModeSessionLoopsStopped;

    private string? RegisterMarketTrader(JsonElement row, long viewer, string scope,
        BridgeAccountContext context, long generation)
    {
        var id = ScmMarketplaceReader.At(row, "creatorId").TryGetInt64Safe();
        if (id is not > 0 || id == viewer) return null;
        var orderValue = ScmMarketplaceReader.At(row, "orderNumber");
        var order = orderValue.ValueKind == JsonValueKind.String ? orderValue.GetString()! : "";
        lock (_realtimeGate)
        {
            if (!MarketTraderOwnerCurrent(context, generation)) return null;
            lock (_marketTraderGate)
            {
                var now = MarketTraderClock();
                foreach (var stale in _marketTraderTargets.Where(p => p.Value.Scope != scope || p.Value.Expires <= now)
                             .Select(p => p.Key).ToArray()) RemoveMarketTrader(stale);
                var key = (id.Value, order, scope);
                if (!_marketTraderReferences.TryGetValue(key, out var reference))
                {
                    if (_marketTraderTargets.Count >= MarketTraderCapacity)
                        RemoveMarketTrader(_marketTraderTargets.MinBy(p => p.Value.Expires).Key);
                    reference = Guid.NewGuid().ToString("N");
                    _marketTraderReferences[key] = reference;
                }
                _marketTraderTargets[reference] = new(id.Value, order, scope, now.AddMinutes(30));
                return reference;
            }
        }
    }

    private void RemoveMarketTrader(string reference)
    {
        if (_marketTraderTargets.Remove(reference, out var target))
            _marketTraderReferences.Remove((target.Id, target.Row, target.Scope));
    }

    private string ResolveMarketTrader(string reference, string scope)
    {
        lock (_marketTraderGate)
        {
            if (!_marketTraderTargets.TryGetValue(reference, out var target) || target.Scope != scope ||
                target.Expires <= MarketTraderClock()) throw new AccountBridgeHostException("users.targetChanged");
            return target.Id.ToString(CultureInfo.InvariantCulture);
        }
    }
}
