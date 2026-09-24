using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Privacy;

/// <summary>
/// Account-scoped local choices and Host-confirmed consent metadata. No legacy
/// promotion, remote writer or publication-policy fallback is reachable here.
/// </summary>
public sealed class LocalPrivacyStore(string root)
{
    private readonly string _directory = Path.Combine(Path.GetFullPath(root), "privacy-local-v1");
    private const int MaximumBytes = 192 * 1024;
    internal static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        PropertyNameCaseInsensitive = false,
        UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow,
        MaxDepth = 10
    };
    private sealed record SavedFile(int SchemaVersion, string OwnerHash, LocalPrivacySnapshot Snapshot, string Integrity,
        [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] int? ConsentVersion = null);

    public LocalPrivacySnapshot Read(BridgeAccountContext owner) => ReadFile(owner)?.Snapshot ?? new(0, null, null, null);

    internal bool HasPublicationConsent(BridgeAccountContext owner) => ReadFile(owner)?.ConsentVersion == 1;

    // null = not asked; 0 = declined/revoked; 1 = confirmed. A refusal is a
    // completed choice, never permission to publish or a reason to ask again.
    internal bool NeedsFirstChoice(BridgeAccountContext owner) => ReadFile(owner) is null &&
        !File.Exists(Path.Combine(root, "desktop.config")) &&
        !File.Exists(Path.Combine(root, "onboarding.complete")) &&
        !File.Exists(Path.Combine(root, "onboarding-introduction.read"));

    private SavedFile? ReadFile(BridgeAccountContext owner)
    {
        var hash = OwnerHash(owner);
        try
        {
            if (!CheckPath(_directory, true) || !CheckPath(PathFor(hash), false)) return null;
            using var stream = new FileStream(PathFor(hash), FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete);
            if (stream.Length is <= 0 or > MaximumBytes) throw new IOException();
            var bytes = new byte[(int)stream.Length];
            stream.ReadExactly(bytes);
            if (stream.ReadByte() != -1) throw new IOException();
            using var doc = JsonDocument.Parse(bytes, new JsonDocumentOptions { MaxDepth = 10 });
            RejectDuplicates(doc.RootElement);
            var file = JsonSerializer.Deserialize<SavedFile>(bytes, Json);
            if (file is null || file.SchemaVersion != 1 || file.OwnerHash != hash || file.Snapshot is null ||
                file.ConsentVersion is not (null or 0 or 1) ||
                file.Integrity != Integrity(hash, file.Snapshot, file.ConsentVersion) || file.Snapshot.Revision <= 0 ||
                file.Snapshot.SavedAt is null || file.Snapshot.SavedAt < DateTimeOffset.UnixEpoch ||
                !Guid.TryParseExact(file.Snapshot.OperationId, "N", out _) || file.Snapshot.Settings is null)
                throw new IOException();
            return file with { Snapshot = file.Snapshot with { Settings = file.Snapshot.Settings.ValidatedCopy() } };
        }
        catch (Exception e) when (StorageError(e) || e is LocalPrivacyException)
        { throw new LocalPrivacyException("privacy_local.read_failed"); }
    }

    public LocalPrivacySnapshot Save(BridgeAccountContext owner, long expectedRevision, string operationId,
        LocalPrivacySettings settings, Func<bool> canCommit)
    {
        var hash = OwnerHash(owner);
        if (settings is null || expectedRevision < 0 || expectedRevision == long.MaxValue ||
            !Guid.TryParseExact(operationId, "N", out _)) throw new LocalPrivacyException("privacy_local.invalid_request");
        settings = settings.ValidatedCopy();
        if (!canCommit()) throw new LocalPrivacyException("privacy_local.account_changed");
        var current = Read(owner);
        CheckRevision(current, expectedRevision, operationId, settings);
        string? temporary = null;
        try
        {
            CheckPath(_directory, true);
            Directory.CreateDirectory(_directory);
            var path = PathFor(hash);
            CheckPath(path + ".lock", false);
            using var writeLock = new FileStream(path + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
            current = Read(owner);
            CheckRevision(current, expectedRevision, operationId, settings);
            if (!canCommit()) throw new LocalPrivacyException("privacy_local.account_changed");
            if (current.OperationId == operationId) return current;
            var next = new LocalPrivacySnapshot(expectedRevision + 1, DateTimeOffset.UtcNow, operationId, settings);
            // Turning sharing off revokes remembered consent even if it is turned
            // back on before the publication timer observes the disabled revision.
            var consent = settings.PublicationEnabled ? ReadFile(owner)?.ConsentVersion : 0;
            var bytes = JsonSerializer.SerializeToUtf8Bytes(new SavedFile(1, hash, next, Integrity(hash, next, consent), consent), Json);
            if (bytes.Length > MaximumBytes) throw new LocalPrivacyException("privacy_local.invalid_request");
            temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
            { stream.Write(bytes); stream.Flush(true); }
            CheckPath(_directory, true);
            CheckPath(path, false);
            if (!canCommit()) throw new LocalPrivacyException("privacy_local.account_changed");
            if (current.Revision > 0) File.Replace(temporary, path, null);
            else File.Move(temporary, path);
            return next;
        }
        catch (Exception e) when (StorageError(e)) { throw new LocalPrivacyException("privacy_local.write_failed"); }
        finally
        {
            if (temporary is not null)
                try { File.Delete(temporary); } catch (Exception e) when (StorageError(e)) { }
        }
    }

    // Host-only consent metadata, not an editor field or a second settings store.
    // Uses the same lock and atomic replacement; the policy revision is unchanged.
    internal void SetPublicationConsent(BridgeAccountContext owner, long revision, bool enabled, Func<bool> canCommit)
    {
        var hash = OwnerHash(owner);
        string? temporary = null;
        try
        {
            if (!canCommit()) throw new LocalPrivacyException("privacy_local.account_changed");
            var file = ReadFile(owner);
            if (file is null && !enabled) return;
            if (file is null || file.Snapshot.Revision != revision || enabled && file.Snapshot.Settings?.PublicationEnabled != true)
                throw new LocalPrivacyException("privacy_local.conflict");
            CheckPath(_directory, true);
            var path = PathFor(hash);
            CheckPath(path + ".lock", false);
            using var writeLock = new FileStream(path + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
            file = ReadFile(owner);
            if (file is null || file.Snapshot.Revision != revision) throw new LocalPrivacyException("privacy_local.conflict");
            int? consent = enabled ? 1 : 0;
            if (file.ConsentVersion == consent) return;
            var next = file with { ConsentVersion = consent, Integrity = Integrity(hash, file.Snapshot, consent) };
            var bytes = JsonSerializer.SerializeToUtf8Bytes(next, Json);
            if (bytes.Length > MaximumBytes) throw new LocalPrivacyException("privacy_local.write_failed");
            temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
            { stream.Write(bytes); stream.Flush(true); }
            CheckPath(_directory, true);
            CheckPath(path, false);
            if (!canCommit()) throw new LocalPrivacyException("privacy_local.account_changed");
            File.Replace(temporary, path, null);
        }
        catch (Exception e) when (StorageError(e)) { throw new LocalPrivacyException("privacy_local.write_failed"); }
        finally
        {
            if (temporary is not null)
                try { File.Delete(temporary); } catch (Exception e) when (StorageError(e)) { }
        }
    }

    private static void CheckRevision(LocalPrivacySnapshot current, long expected, string operation, LocalPrivacySettings settings)
    {
        if (current.OperationId == operation && current.Revision == expected + 1 &&
            JsonSerializer.Serialize(current.Settings, Json) == JsonSerializer.Serialize(settings, Json)) return;
        if (current.OperationId == operation || current.Revision != expected)
            throw new LocalPrivacyException("privacy_local.conflict");
    }

    internal static void RejectDuplicates(JsonElement value)
    {
        if (value.ValueKind == JsonValueKind.Object)
        {
            var names = new HashSet<string>(StringComparer.Ordinal);
            foreach (var property in value.EnumerateObject())
            { if (!names.Add(property.Name)) throw new JsonException(); RejectDuplicates(property.Value); }
        }
        else if (value.ValueKind == JsonValueKind.Array)
            foreach (var item in value.EnumerateArray()) RejectDuplicates(item);
    }

    private static bool CheckPath(string path, bool directory)
    {
        FileAttributes attributes;
        try { attributes = File.GetAttributes(path); }
        catch (FileNotFoundException) { return false; }
        catch (DirectoryNotFoundException) { return false; }
        if ((attributes & FileAttributes.ReparsePoint) != 0 || attributes.HasFlag(FileAttributes.Directory) != directory)
            throw new IOException();
        return true;
    }
    private static string OwnerHash(BridgeAccountContext owner)
    {
        if (owner is null || !owner.IsComplete || new[] { owner.Environment, owner.Authority, owner.Subject }
            .Any(v => v.Length > 2048 || v.Any(char.IsControl))) throw new LocalPrivacyException("privacy_local.account_changed");
        return Hash(JsonSerializer.SerializeToUtf8Bytes(new[] { owner.Environment, owner.Authority, owner.Subject }));
    }
    private static string Hash(byte[] bytes) => Convert.ToHexString(SHA256.HashData(bytes));
    private static string Integrity(string owner, LocalPrivacySnapshot snapshot, int? consent) => consent is null
        ? Hash(JsonSerializer.SerializeToUtf8Bytes(new { schemaVersion = 1, owner, snapshot }, Json))
        : Hash(JsonSerializer.SerializeToUtf8Bytes(new { schemaVersion = 1, owner, snapshot, consentVersion = consent }, Json));
    private string PathFor(string hash) => Path.Combine(_directory, hash + ".json");
    private static bool StorageError(Exception e) => e is IOException or UnauthorizedAccessException or JsonException or
        System.Security.SecurityException or ArgumentException or NotSupportedException;
}
