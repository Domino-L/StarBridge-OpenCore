using System.Text.Json;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    private sealed record SupportSnapshot(BridgeAccountContext Owner, long Generation, DateTimeOffset ObservedAt, DailySupportView View);
    private SupportSnapshot? supportSnapshot;
    private DateTimeOffset supportReadAfter;
    private BridgeAccountContext? supportReadOwner;
    private long supportRevision;
    private int supportReading;

    private IReadOnlyList<string> SupportEntitlements()
    {
        var snapshot = supportSnapshot;
        var now = DateTimeOffset.UtcNow;
        return snapshot is null || snapshot.Generation != Generation || snapshot.Owner != CurrentContext ||
            now - snapshot.ObservedAt > TimeSpan.FromMinutes(2) ? [] : snapshot.View.TemporaryEntitlements
                .Where(g => g.ExpiresAt > now).Select(g => g.Entitlement).Distinct(StringComparer.Ordinal).ToArray();
    }

    private void EnsureSupportRead()
    {
        if (IsBusinessStartupDeferred || _dailySupport is null || _disposed || _reauthorizationRequired || _credentialTemporarilyUnavailable ||
            _legacyRestoreUnavailable || CurrentContext is not { } owner ||
            supportReadAfter > DateTimeOffset.UtcNow && supportReadOwner == owner ||
            Interlocked.CompareExchange(ref supportReading, 1, 0) != 0) return;
        var business = _businessStartupDeferred ? _firstUseBusinessAdmission?.Enter(default) : null;
        if (_businessStartupDeferred && business is null) { Interlocked.Exchange(ref supportReading, 0); return; }
        _ = RefreshAsync(owner);
        async Task RefreshAsync(BridgeAccountContext context)
        {
            var generation = Generation;
            var revision = Interlocked.Read(ref supportRevision);
            try
            {
                var session = await ReadDirectRelaySessionAsync(context, business?.Token ?? CancellationToken.None).ConfigureAwait(false);
                var result = await _dailySupport.SendAsync(session.AccessToken, null, business?.Token ?? CancellationToken.None);
                lock (_loginGate)
                {
                    if (_disposed || generation != Generation || context != CurrentContext || revision != Interlocked.Read(ref supportRevision) ||
                        business is not null && (!business.IsCurrent || _firstUseBusinessAdmission?.IsActive != true)) return;
                    RequireSameRelaySession(RequireRelaySession(context), session);
                    supportSnapshot = new(context, generation, DateTimeOffset.UtcNow, result);
                }
            }
            catch { if (generation == Generation && revision == Interlocked.Read(ref supportRevision)) supportSnapshot = null; }
            finally { business?.Dispose(); supportReadOwner = context; supportReadAfter = DateTimeOffset.UtcNow.AddMinutes(1); Interlocked.Exchange(ref supportReading, 0); }
        }
    }

    public async Task<object> DailySupportAsync(BridgeAccountContext context, JsonElement payload, bool claim, CancellationToken token)
    {
        if (payload.ValueKind != JsonValueKind.Object || payload.EnumerateObject().Count() != (claim ? 2 : 1) ||
            !payload.TryGetProperty("schemaVersion", out var schema) || !schema.TryGetInt32(out var version) || version != 1)
            throw new AccountBridgeHostException("bridge.invalid_envelope");
        int? offset = null;
        if (claim)
        {
            if (!payload.TryGetProperty("utcOffsetMinutes", out var field) || !field.TryGetInt32(out var minutes) || minutes is < -840 or > 840)
                throw new AccountBridgeHostException("bridge.invalid_envelope");
            offset = minutes;
        }
        if (!await _mutationGate.WaitAsync(0, token)) throw new AccountBridgeHostException("support.busy");
        try
        {
            var client = _dailySupport ?? throw new AccountBridgeHostException("support.unavailable");
            var generation = Generation;
            Interlocked.Increment(ref supportRevision);
            var session = RequireRelaySession(context);
            if (_disposed || _reauthorizationRequired || _credentialTemporarilyUnavailable || _legacyRestoreUnavailable)
                throw new AccountBridgeHostException("support.unavailable");
            // Never replay POST through automatic OAuth retries. A timeout is uncertain.
            var result = await client.SendAsync(session.AccessToken, offset, token);
            lock (_loginGate)
            {
                token.ThrowIfCancellationRequested();
                if (_disposed || generation != Generation || context != CurrentContext)
                    throw new BridgeStaleGenerationException(generation, Generation);
                RequireSameRelaySession(RequireRelaySession(context), session);
                supportSnapshot = new(context, generation, DateTimeOffset.UtcNow, result);
            }
            return result;
        }
        finally { if (!_disposed) _mutationGate.Release(); }
    }
}
