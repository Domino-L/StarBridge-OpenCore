using System.Globalization;
using System.Text.Json;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Hangar;

public sealed partial class LocalHangarStore
{
    // These fields belong only to this local instance. Catalog matching and
    // community publication must continue to use Title, never Nickname/Notes.
    public LocalHangarSnapshot SavePersonalData(BridgeAccountContext owner, long expectedRevision,
        string operationId, string shipId, string? nickname, string? notes, Func<bool>? canCommit = null)
    {
        var storage = StorageOwner(owner);
        bool Current() => (canCommit?.Invoke() ?? true) && StorageOwner(owner) == storage;
        _ = OwnerHash(storage);
        nickname = string.IsNullOrWhiteSpace(nickname) ? null : nickname.Trim();
        notes = string.IsNullOrWhiteSpace(notes) ? null : notes.Replace("\r\n", "\n").Replace('\r', '\n').Trim();
        if (expectedRevision < 0 || expectedRevision == long.MaxValue || !ValidText(operationId, 256) ||
            !ValidText(shipId, 128) || !ValidPersonalData(nickname, notes))
            throw new LocalHangarStoreException("hangar.invalid_personal_data", "Invalid local ship details.");
        var requestHash = Hash(JsonSerializer.SerializeToUtf8Bytes(new { kind = "personal-data-v1", shipId, nickname, notes }));
        _ = PreparePersonalData(ReadFile(storage));
        try
        {
            CheckDirectory();
            var path = GetPath(storage);
            CheckFile(path + ".lock");
            using var writeLock = new FileStream(path + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
            var current = ReadFile(storage);
            var next = PreparePersonalData(current);
            CheckCanCommit(Current);
            if (ReferenceEquals(current, next)) return next.Snapshot;
            var bytes = JsonSerializer.SerializeToUtf8Bytes(new Envelope(1, OwnerHash(storage), next, Integrity(OwnerHash(storage), next)), Json);
            if (bytes.Length > MaximumBytes) throw new InvalidDataException("Inventory limit exceeded.");
            Commit(path, bytes, true, Current);
            return next.Snapshot;
        }
        catch (Exception error) when (IsStorageError(error))
        { throw new LocalHangarStoreException("hangar.storage_write_failed", "The local ship details could not be saved safely.", error); }

        SavedFile PreparePersonalData(SavedFile? current)
        {
            if (current is null) throw new LocalHangarStoreException("hangar.ship_unavailable", "Ship unavailable.");
            if (current.Snapshot.OperationId == operationId)
            {
                if (current.ExpectedRevision == expectedRevision && current.RequestHash == requestHash) return current;
                throw new LocalHangarStoreException("hangar.revision_conflict", "Operation already used.");
            }
            if (current.Snapshot.Revision != expectedRevision)
                throw new LocalHangarStoreException("hangar.revision_conflict", "Inventory changed.");
            if (current.Snapshot.Ships.Concat(current.Snapshot.FormerShips ?? []).Count(s => s.Id == shipId) != 1)
                throw new LocalHangarStoreException("hangar.ship_unavailable", "Ship unavailable.");
            var now = DateTimeOffset.UtcNow;
            if (current.Snapshot.SavedAt > now) now = current.Snapshot.SavedAt.Value;
            return new(current.Snapshot with {
                Revision = expectedRevision + 1, OperationId = operationId, SavedAt = now,
                InventorySavedAt = current.Snapshot.InventorySavedAt ?? current.Snapshot.SavedAt,
                Ships = current.Snapshot.Ships.Select(Update).ToArray(),
                FormerShips = current.Snapshot.FormerShips?.Select(Update).ToArray()
            }, expectedRevision, requestHash);
        }
        LocalHangarShip Update(LocalHangarShip ship) => ship.Id == shipId ? ship with { Nickname = nickname, Notes = notes } : ship;
    }

    private static bool ValidPersonalData(string? nickname, string? notes) =>
        (nickname is null || nickname.Length <= 2048 && !string.IsNullOrWhiteSpace(nickname) &&
            ValidCharacters(nickname) && StringInfo.ParseCombiningCharacters(nickname).Length <= 64) &&
        (notes is null || notes.Length <= 16000 && !string.IsNullOrWhiteSpace(notes) &&
            ValidCharacters(notes.Replace("\n", "").Replace("\r", "").Replace("\t", "")) &&
            StringInfo.ParseCombiningCharacters(notes).Length <= 2000);
}
