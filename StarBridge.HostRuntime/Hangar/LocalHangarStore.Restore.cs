using System.Text.Json;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Hangar;

public sealed partial class LocalHangarStore
{
    /// <summary>
    /// Writes the account copy into an account that has never saved a local hangar (revision 0). A local
    /// hangar that already exists is never replaced. Returns null when nothing was written for that reason.
    /// The file format is the normal hangar-local-v1 envelope, so older clients read it unchanged.
    /// </summary>
    public LocalHangarSnapshot? RestoreFromArchive(BridgeAccountContext owner, HangarArchive.Document archive,
        string operationId, Func<bool>? canCommit = null)
    {
        var storage = StorageOwner(owner);
        bool Current() => (canCommit?.Invoke() ?? true) && StorageOwner(owner) == storage;
        _ = OwnerHash(storage);
        if (!ValidText(operationId, 256) || archive is null || archive.SchemaVersion != HangarArchive.SchemaVersion ||
            archive.Ships is null || archive.Ships.Count > MaximumShips || archive.FormerShips?.Count > MaximumShips)
            throw new LocalHangarStoreException("hangar.archive_invalid", "The account hangar copy is not usable.");
        if (ReadFile(storage) is not null) return null;
        try
        {
            CheckDirectory();
            Directory.CreateDirectory(_directory);
            var path = GetPath(storage);
            CheckFile(path + ".lock");
            using var writeLock = new FileStream(path + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
            if (ReadFile(storage) is not null) return null;
            var now = DateTimeOffset.UtcNow;
            var ships = archive.Ships.Select(HangarArchive.ToLocal).ToArray();
            var former = archive.FormerShips?.Select(HangarArchive.ToLocal).ToArray();
            var latest = ships.Concat(former ?? []).Select(s => s.RemovedAt ?? s.AddedAt).DefaultIfEmpty(now).Max();
            if (latest > now) now = latest;
            var inventory = archive.InventorySavedAt is { } saved && saved <= now ? saved.ToUniversalTime() : now;
            var snapshot = new LocalHangarSnapshot(1, now, operationId, ships, archive.Partial && ships.Length > 0,
                former is { Length: > 0 } ? former : null, inventory);
            var requestHash = Hash(JsonSerializer.SerializeToUtf8Bytes(new { kind = "archive-restore-v1", operationId }));
            var next = new SavedFile(snapshot, 0, requestHash);
            ValidateFile(next);
            CheckCanCommit(Current);
            var bytes = JsonSerializer.SerializeToUtf8Bytes(new Envelope(1, OwnerHash(storage), next, Integrity(OwnerHash(storage), next)), Json);
            if (bytes.Length > MaximumBytes) throw new InvalidDataException("Inventory limit exceeded.");
            Commit(path, bytes, false, Current);
            return snapshot;
        }
        catch (InvalidDataException error)
        { throw new LocalHangarStoreException("hangar.archive_invalid", "The account hangar copy is not usable.", error); }
        catch (Exception error) when (IsStorageError(error))
        { throw new LocalHangarStoreException("hangar.storage_write_failed", "The local hangar could not be saved safely.", error); }
    }
}
