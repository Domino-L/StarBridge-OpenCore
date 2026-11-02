using StarBridge.Core.Hangar;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Hangar;

public sealed partial class LocalHangarStore
{
    internal Func<BridgeAccountContext, BridgeAccountContext>? ResolveOwner { get; set; }

    private BridgeAccountContext StorageOwner(BridgeAccountContext authentication)
    {
        try { return ResolveOwner?.Invoke(authentication) ?? authentication; }
        catch (Privacy.LocalPrivacyException error)
        { throw new LocalHangarStoreException("hangar.account_changed", "Business ownership is not verified.", error); }
    }

    public LocalHangarSnapshot Read(BridgeAccountContext owner)
    {
        var storage = StorageOwner(owner);
        try
        {
            var result = ReadCore(storage);
            CheckCanCommit(() => StorageOwner(owner) == storage);
            return result;
        }
        catch (LocalHangarStoreException error) when (error.Code == "hangar.storage_busy")
        {
            CheckCanCommit(() => StorageOwner(owner) == storage);
            throw;
        }
    }

    public LocalHangarSnapshot Save(BridgeAccountContext owner, long expectedRevision, string operationId,
        IReadOnlyList<CollectedHangarShip> observations, bool partial, bool confirmEmpty, Func<bool>? canCommit = null,
        IReadOnlyList<string>? removedShipIds = null)
    {
        var storage = StorageOwner(owner);
        bool Current() => (canCommit?.Invoke() ?? true) && StorageOwner(owner) == storage;
        return SaveCore(storage, expectedRevision, operationId, observations, partial, confirmEmpty, Current, removedShipIds);
    }

    internal LocalHangarSnapshot SaveCustomImage(BridgeAccountContext owner, long expectedRevision,
        string operationId, string shipId, string? preparedImageData, Func<bool>? canCommit = null)
    {
        var storage = StorageOwner(owner);
        bool Current() => (canCommit?.Invoke() ?? true) && StorageOwner(owner) == storage;
        return SaveCustomImageCore(storage, expectedRevision, operationId, shipId, preparedImageData, Current);
    }

    internal string? ReadCustomImage(BridgeAccountContext owner, long revision, string shipId)
    {
        var storage = StorageOwner(owner);
        var result = ReadCustomImageCore(storage, revision, shipId);
        CheckCanCommit(() => StorageOwner(owner) == storage);
        return result;
    }
}
