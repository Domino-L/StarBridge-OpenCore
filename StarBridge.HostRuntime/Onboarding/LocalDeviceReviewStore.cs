using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace StarBridge.HostRuntime.Onboarding;

// Only an explicit review of shared device choices. No identity, statistics
// consent, functional Native readiness, online permission or completion grant.
internal sealed record LocalDeviceReview(
    [property: JsonRequired] long Revision,
    [property: JsonRequired] string? OperationId,
    [property: JsonRequired] DateTimeOffset? SavedAt,
    [property: JsonRequired] string? Fingerprint)
{
    internal static LocalDeviceReview Empty => new(0, null, null, null);
}

internal sealed class LocalDeviceReviewStore(string root)
{
    private readonly string _directory = Path.Combine(Path.GetFullPath(root), "first-use-device-review-v1");
    private string PathName => Path.Combine(_directory, "state.bin");
    private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("StarBridge.first-use-device-review.v1");
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    { UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow, PropertyNameCaseInsensitive = false, MaxDepth = 4 };
    private sealed record Document([property: JsonRequired] int SchemaVersion,
        [property: JsonRequired] LocalDeviceReview Value);
    internal LocalDeviceReview Read()
    {
        try
        {
            Safe(PathName);
            FileStream source;
            try { source = new(PathName, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete); }
            catch (FileNotFoundException) { return LocalDeviceReview.Empty; }
            catch (DirectoryNotFoundException) { return LocalDeviceReview.Empty; }
            using var file = source;
            if (file.Length is <= 0 or > 8192) throw new InvalidDataException();
            var encrypted = new byte[(int)file.Length]; file.ReadExactly(encrypted);
            if (file.ReadByte() != -1) throw new InvalidDataException();
            var clear = ProtectedData.Unprotect(encrypted, Entropy, DataProtectionScope.CurrentUser);
            try
            {
                if (clear.Length is <= 0 or > 8192) throw new InvalidDataException();
                using var json = JsonDocument.Parse(clear, new JsonDocumentOptions { MaxDepth = 4 });
                Unique(json.RootElement);
                var document = JsonSerializer.Deserialize<Document>(clear, Json);
                if (document is not { SchemaVersion: 1, Value: not null }) throw new InvalidDataException();
                Validate(document.Value); return document.Value;
            }
            finally { CryptographicOperations.ZeroMemory(clear); }
        }
        catch (Exception error) when (StorageError(error))
        { throw new LocalFirstUseException("firstUse.device_review_read_failed"); }
    }
    internal LocalDeviceReview Save(LocalDeviceReview expected, string operationId, string fingerprint, Func<bool> current)
    {
        if (expected.Revision < 0 || expected.Revision >= long.MaxValue - 1 ||
            !LocalFirstUseValidation.Id(operationId) || !Hash(fingerprint))
            throw new LocalFirstUseException("firstUse.invalid_request");
        string? temporary = null;
        try
        {
            Safe(PathName); Safe(PathName + ".lock");
            if (!current()) throw new LocalFirstUseException("firstUse.context_changed");
            Directory.CreateDirectory(_directory);
            using var lease = new FileStream(PathName + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
            var old = Read();
            if (old != expected || old.OperationId == operationId) throw new LocalFirstUseException("firstUse.revision_conflict");
            var next = new LocalDeviceReview(old.Revision + 1, operationId, DateTimeOffset.UtcNow, fingerprint);
            Validate(next);
            var clear = JsonSerializer.SerializeToUtf8Bytes(new Document(1, next), Json);
            byte[] encrypted;
            try { encrypted = ProtectedData.Protect(clear, Entropy, DataProtectionScope.CurrentUser); }
            finally { CryptographicOperations.ZeroMemory(clear); }
            temporary = Path.Combine(_directory, Guid.NewGuid().ToString("N") + ".tmp");
            using (var file = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
            { file.Write(encrypted); file.Flush(true); }
            Safe(PathName); Safe(temporary);
            if (!current()) throw new LocalFirstUseException("firstUse.context_changed");
            if (Read() != old) throw new LocalFirstUseException("firstUse.revision_conflict");
            if (!current()) throw new LocalFirstUseException("firstUse.context_changed");
            if (old.Revision == 0) File.Move(temporary, PathName); else File.Replace(temporary, PathName, null);
            return next;
        }
        catch (Exception error) when (StorageError(error))
        { throw new LocalFirstUseException("firstUse.device_review_write_failed"); }
        finally
        {
            if (temporary is not null) try { File.Delete(temporary); } catch (Exception error) when (StorageError(error)) { }
        }
    }
    private static bool Hash(string? value) => value is { Length: 64 } && value.All(c => c is >= '0' and <= '9' or >= 'A' and <= 'F');
    private static void Validate(LocalDeviceReview value)
    {
        if (value.Revision <= 0 || value.Revision >= long.MaxValue || !LocalFirstUseValidation.Id(value.OperationId) ||
            value.SavedAt is null || value.SavedAt.Value.Offset != TimeSpan.Zero ||
            value.SavedAt < DateTimeOffset.UnixEpoch || value.SavedAt > DateTimeOffset.UtcNow || !Hash(value.Fingerprint))
            throw new InvalidDataException();
    }
    private static bool StorageError(Exception error) => error is IOException or InvalidDataException or UnauthorizedAccessException or
        CryptographicException or JsonException or NotSupportedException or System.Security.SecurityException;
    private static void Safe(string path)
    {
        for (var node = Path.GetFullPath(path); node is not null; node = Path.GetDirectoryName(node))
        {
            FileAttributes attributes;
            try { attributes = File.GetAttributes(node); }
            catch (FileNotFoundException) { continue; }
            catch (DirectoryNotFoundException) { continue; }
            if (attributes.HasFlag(FileAttributes.ReparsePoint)) throw new IOException();
        }
    }
    private static void Unique(JsonElement value)
    {
        if (value.ValueKind != JsonValueKind.Object) return;
        var names = new HashSet<string>(StringComparer.Ordinal);
        foreach (var field in value.EnumerateObject())
        { if (!names.Add(field.Name)) throw new JsonException(); Unique(field.Value); }
    }
}
