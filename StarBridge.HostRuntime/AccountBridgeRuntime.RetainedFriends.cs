using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime;

public sealed partial class AccountBridgeRuntime
{
    private object ReadRetainedFriends(BridgeEnvelope request, string readId,
        BridgeAccountContext owner, Func<bool> current)
    {
        var body = request.Payload;
        var paged = body.TryGetProperty("pagedResponse", out var enabled) && enabled.GetBoolean();
        var offset = body.TryGetProperty("offset", out var skip) ? skip.GetInt32() : 0;
        if ((!paged && (body.TryGetProperty("snapshotId", out _) || body.TryGetProperty("offset", out _))) || offset < 0)
            throw new AccountBridgeHostException("offlineAccount.invalid_request");
        if (paged && body.TryGetProperty("snapshotId", out var snapshot))
        {
            if (snapshot.GetString() is not { } id || !Guid.TryParseExact(id, "N", out _))
                throw new AccountBridgeHostException("offlineAccount.invalid_request");
            // ResolveRetainedRead already validated this exact readId again for
            // this request. The snapshot ID supplies neither identity nor login.
            var page = _friendPages.ReadCached(id, offset, owner, request.SessionGeneration, "retained:" + readId);
            if (!current()) throw new AccountBridgeHostException("offlineAccount.context_changed");
            return new { schemaVersion = 1, page.Directory, page.CachedAtUtc };
        }
        if (offset != 0) throw new AccountBridgeHostException("offlineAccount.invalid_request");
        var pageRevision = Volatile.Read(ref _friendPageRevision);
        var data = _offlineAccount?.ReadSelectedFriends(owner, current)
            ?? throw new AccountBridgeHostException("offlineAccount.unavailable");
        if (!paged) return new { schemaVersion = 1, data.Directory, data.CachedAtUtc };
        var version = data.Version;
        var storageOwner = data.StorageOwner;
        var epoch = data.Epoch;
        bool ScopeCurrent() => !_disposed && !_requestRetirement.IsClosed &&
            pageRevision == Volatile.Read(ref _friendPageRevision) &&
            ResolveRetainedRead(readId, request, CancellationToken.None) is { } access &&
            access.Owner == owner && access.Current();
        bool SnapshotCurrent()
        {
            try { return _offlineAccount?.IsSelectedFriendsVersionCurrent(owner, storageOwner, version, epoch, ScopeCurrent) == true; }
            catch (Exception error) when (CacheFailure(error)) { return false; }
        }
        var directory = _friendPages.Open(JsonSerializer.SerializeToElement(data.Directory, BridgeProtocol.JsonOptions),
            owner, request.SessionGeneration, "retained:" + readId, SnapshotCurrent, data.CachedAtUtc);
        if (!current() || !SnapshotCurrent()) throw new AccountBridgeHostException("offlineAccount.context_changed");
        return new { schemaVersion = 1, directory, data.CachedAtUtc };
    }
}
