namespace StarBridge.HostRuntime.Account;

using StarBridge.NativeBridge;

internal sealed partial class ScmAccountBridgeHost : IAccountBridgeStagedProfileReader
{
    public AccountBridgeProfileProjection? ReadProfileDisplayCache(BridgeAccountContext context, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        var generation = Generation;
        lock (_realtimeGate)
        {
            RequireAccountProfileReadOwner(context, generation);
            var memory = _profileReadSnapshot;
            var cached = memory?.Owner == context && memory.Generation == generation
                ? memory.Profile : _profileReadCacheSuppressed ? null : _profileCache.Load(CurrentRoute());
            token.ThrowIfCancellationRequested();
            RequireAccountProfileReadOwner(context, generation);
            return cached is null ? null : ProjectProfile(cached.ToOfflineProfile(), "cache", cached.CachedAtUtc, []);
        }
    }

    public Task<AccountBridgeProfileProjection> GetProfileDisplayDataAsync(BridgeAccountContext context, CancellationToken token) =>
        GetProfileCoreAsync(context, token, includeDirectory: false);

    public async Task<IReadOnlyList<AccountBridgeTimeZone>> GetProfileTimeZoneDirectoryAsync(BridgeAccountContext context, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        var generation = Generation;
        lock (_realtimeGate) RequireAccountProfileReadOwner(context, generation);
        // Existing public endpoint does not add an Authorization header and
        // cannot refresh credentials. It must not hold the private account queue.
        var directory = await LoadDirectoryAsync(token, strictFailures: true);
        token.ThrowIfCancellationRequested();
        lock (_realtimeGate) RequireAccountProfileReadOwner(context, generation);
        return directory;
    }
}
