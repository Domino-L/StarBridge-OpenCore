using System.Buffers.Binary;
using System.Text.Json;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Hangar;

public sealed partial class LocalHangarStore
{
    private const string ImageReferencePrefix = "image-v1:";
    private const string PngDataPrefix = "data:image/png;base64,";
    private const int MaximumLocalImageBytes = 512 * 1024;

    /// <summary>Accepts only an image prepared by the native picker, never a caller-supplied path.</summary>
    private LocalHangarSnapshot SaveCustomImageCore(BridgeAccountContext owner, long expectedRevision,
        string operationId, string shipId, string? preparedImageData, Func<bool>? canCommit = null)
    {
        _ = OwnerHash(owner);
        if (expectedRevision < 0 || expectedRevision == long.MaxValue || !ValidText(operationId, 256) || !ValidText(shipId, 128))
            throw new LocalHangarStoreException("hangar.invalid_request", "Invalid image save request.");
        byte[]? image = null;
        if (preparedImageData is not null)
        {
            if (!preparedImageData.StartsWith(PngDataPrefix, StringComparison.Ordinal) || preparedImageData.Length > 700000)
                throw new LocalHangarStoreException("hangar.image_invalid", "Invalid prepared image.");
            try { image = Convert.FromBase64String(preparedImageData[PngDataPrefix.Length..]); }
            catch (FormatException) { throw new LocalHangarStoreException("hangar.image_invalid", "Invalid prepared image."); }
            if (!ValidPng(image)) throw new LocalHangarStoreException("hangar.image_invalid", "Invalid prepared image.");
        }
        var imageHash = image is null ? null : Hash(image);
        var reference = imageHash is null ? null : ImageReferencePrefix + imageHash;
        var requestHash = Hash(JsonSerializer.SerializeToUtf8Bytes(new { kind = "custom-image-v1", shipId, reference }));
        _ = PrepareImage(ReadFile(owner));
        try
        {
            CheckDirectory();
            Directory.CreateDirectory(_directory);
            var path = GetPath(owner);
            CheckFile(path + ".lock");
            using var writeLock = new FileStream(path + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
            var current = ReadFile(owner);
            var next = PrepareImage(current);
            CheckCanCommit(canCommit);
            if (ReferenceEquals(current, next)) return next.Snapshot;
            if (image is not null)
            {
                var imagePath = ImagePath(owner, imageHash!);
                if (CheckFile(imagePath))
                {
                    if (Hash(ReadImageFile(imagePath)) != imageHash) throw new InvalidDataException("Image checksum mismatch.");
                }
                else Commit(imagePath, image, false, canCommit);
            }
            var bytes = JsonSerializer.SerializeToUtf8Bytes(new Envelope(1, OwnerHash(owner), next, Integrity(OwnerHash(owner), next)), Json);
            if (bytes.Length > MaximumBytes) throw new InvalidDataException("Inventory limit exceeded.");
            Commit(path, bytes, true, canCommit);
            return next.Snapshot;
        }
        catch (Exception error) when (IsStorageError(error))
        { throw new LocalHangarStoreException("hangar.storage_write_failed", "The image could not be saved safely.", error); }

        SavedFile PrepareImage(SavedFile? current)
        {
            if (current is null) throw new LocalHangarStoreException("hangar.image_ship_unavailable", "Ship unavailable.");
            if (current.Snapshot.OperationId == operationId)
            {
                if (current.ExpectedRevision == expectedRevision && current.RequestHash == requestHash) return current;
                throw new LocalHangarStoreException("hangar.revision_conflict", "Operation already used.");
            }
            if (current.Snapshot.Revision != expectedRevision)
                throw new LocalHangarStoreException("hangar.revision_conflict", "Inventory changed.");
            if (current.Snapshot.Ships.Count(s => s.Id == shipId) != 1)
                throw new LocalHangarStoreException("hangar.image_ship_unavailable", "Ship unavailable.");
            var now = DateTimeOffset.UtcNow;
            if (current.Snapshot.SavedAt > now) now = current.Snapshot.SavedAt.Value;
            var next = current.Snapshot with { Revision = expectedRevision + 1, OperationId = operationId, SavedAt = now,
                InventorySavedAt = current.Snapshot.InventorySavedAt ?? current.Snapshot.SavedAt,
                Ships = current.Snapshot.Ships.Select(ship => ship.Id == shipId
                    ? ship with { CustomImagePath = reference, CustomImageCrop = null } : ship).ToArray() };
            return new(next, expectedRevision, requestHash);
        }
    }

    private string? ReadCustomImageCore(BridgeAccountContext owner, long revision, string shipId)
    {
        var snapshot = ReadCore(owner);
        if (snapshot.Revision != revision) throw new LocalHangarStoreException("hangar.revision_conflict", "Inventory changed.");
        var ship = snapshot.Ships.Concat(snapshot.FormerShips ?? []).SingleOrDefault(s => s.Id == shipId);
        if (ship is null) throw new LocalHangarStoreException("hangar.image_ship_unavailable", "Ship unavailable.");
        // Older arbitrary paths are preserved as metadata but are never opened by this API.
        if (ship.CustomImagePath is not { } reference || !reference.StartsWith(ImageReferencePrefix, StringComparison.Ordinal)) return null;
        var hash = reference[ImageReferencePrefix.Length..];
        if (!IsHash(hash)) throw new LocalHangarStoreException("hangar.image_invalid", "Invalid image reference.");
        try
        {
            if (!CheckDirectory()) throw new IOException("Image storage missing.");
            var bytes = ReadImageFile(ImagePath(owner, hash));
            if (Hash(bytes) != hash || !ValidPng(bytes)) throw new InvalidDataException("Invalid saved image.");
            return PngDataPrefix + Convert.ToBase64String(bytes);
        }
        catch (Exception error) when (IsStorageError(error))
        { throw new LocalHangarStoreException("hangar.image_read_failed", "Saved image could not be read safely.", error); }
    }
    private string ImagePath(BridgeAccountContext owner, string hash) => Path.Combine(_directory, OwnerHash(owner) + "." + hash + ".png");
    private static byte[] ReadImageFile(string path)
    {
        if (!CheckFile(path)) throw new IOException("Image missing.");
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        if (stream.Length is <= 0 or > MaximumLocalImageBytes) throw new InvalidDataException("Image size invalid.");
        var bytes = new byte[(int)stream.Length]; stream.ReadExactly(bytes);
        if (stream.ReadByte() != -1) throw new InvalidDataException("Image changed.");
        return bytes;
    }
    private static bool ValidPng(byte[] bytes)
    {
        if (bytes.Length is < 33 or > MaximumLocalImageBytes ||
            !bytes.AsSpan(0, 8).SequenceEqual(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 }) ||
            BinaryPrimitives.ReadUInt32BigEndian(bytes.AsSpan(8, 4)) != 13 || !bytes.AsSpan(12, 4).SequenceEqual("IHDR"u8)) return false;
        var width = BinaryPrimitives.ReadUInt32BigEndian(bytes.AsSpan(16, 4));
        var height = BinaryPrimitives.ReadUInt32BigEndian(bytes.AsSpan(20, 4));
        return width is > 0 and <= 4096 && height is > 0 and <= 4096 && (long)width * height <= 16_000_000;
    }
}
