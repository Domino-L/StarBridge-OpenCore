using System.Text.Json;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Hangar;

public sealed partial class LocalHangarStore
{
    // Bookmarks belong to individual saved ships, not personal-profile favorites.
    public LocalHangarSnapshot SetFavorite(BridgeAccountContext owner, long expectedRevision,
        string operationId, string shipId, bool favorite, Func<bool>? canCommit = null)
    {
        var storage = StorageOwner(owner);
        bool Current() => (canCommit?.Invoke() ?? true) && StorageOwner(owner) == storage;
        _ = OwnerHash(storage);
        if (expectedRevision < 0 || expectedRevision == long.MaxValue || !ValidText(operationId, 256) || !ValidText(shipId, 128))
            throw new LocalHangarStoreException("hangar.invalid_request", "Invalid bookmark request.");
        var requestHash = Hash(JsonSerializer.SerializeToUtf8Bytes(new { kind = "favorite-v1", shipId, favorite }));
        _ = PrepareFavorite(ReadFile(storage));
        try
        {
            CheckDirectory();
            var path = GetPath(storage);
            CheckFile(path + ".lock");
            using var writeLock = new FileStream(path + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
            var current = ReadFile(storage);
            var next = PrepareFavorite(current);
            CheckCanCommit(Current);
            if (ReferenceEquals(current, next)) return next.Snapshot;
            var bytes = JsonSerializer.SerializeToUtf8Bytes(new Envelope(1, OwnerHash(storage), next, Integrity(OwnerHash(storage), next)), Json);
            if (bytes.Length > MaximumBytes) throw new InvalidDataException("Inventory limit exceeded.");
            Commit(path, bytes, true, Current);
            return next.Snapshot;
        }
        catch (Exception error) when (IsStorageError(error))
        { throw new LocalHangarStoreException("hangar.storage_write_failed", "The bookmark could not be saved safely.", error); }

        SavedFile PrepareFavorite(SavedFile? current)
        {
            if (current is null) throw new LocalHangarStoreException("hangar.favorite_ship_unavailable", "Ship unavailable.");
            if (current.Snapshot.OperationId == operationId)
            {
                if (current.ExpectedRevision == expectedRevision && current.RequestHash == requestHash) return current;
                throw new LocalHangarStoreException("hangar.revision_conflict", "Operation already used.");
            }
            if (current.Snapshot.Revision != expectedRevision)
                throw new LocalHangarStoreException("hangar.revision_conflict", "Inventory changed.");
            if (current.Snapshot.Ships.Concat(current.Snapshot.FormerShips ?? []).Count(s => s.Id == shipId) != 1)
                throw new LocalHangarStoreException("hangar.favorite_ship_unavailable", "Ship unavailable.");
            var now = DateTimeOffset.UtcNow;
            if (current.Snapshot.SavedAt > now) now = current.Snapshot.SavedAt.Value;
            var snapshot = current.Snapshot with
            {
                Revision = expectedRevision + 1, OperationId = operationId, SavedAt = now,
                InventorySavedAt = current.Snapshot.InventorySavedAt ?? current.Snapshot.SavedAt,
                Ships = current.Snapshot.Ships.Select(Update).ToArray(),
                FormerShips = current.Snapshot.FormerShips?.Select(Update).ToArray()
            };
            return new(snapshot, expectedRevision, requestHash);
        }
        LocalHangarShip Update(LocalHangarShip ship) => ship.Id == shipId ? ship with { IsFavorite = favorite } : ship;
    }
}
