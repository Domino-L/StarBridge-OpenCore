using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Profiles;

public sealed record LocalProfileLayout(string Id, int Span, bool IsVisible, int Position,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] IReadOnlyList<string>? FavoriteShipIds = null);
public sealed record LocalProfileContent(string CallSign, string Introduction, int AvatarStyle,
    string WallpaperId, IReadOnlyList<LocalProfileLayout> Modules, IReadOnlyList<string>? FavoriteShipIds,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] LocalProfilePlayStyle? PlayStyle = null,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] LocalProfileSchedule? Schedule = null,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingDefault)] bool PreserveEmptyFields = false);
public sealed record LocalProfileSnapshot(long Revision, DateTimeOffset? SavedAt, string? OperationId, LocalProfileContent? Content);
public sealed class LocalProfileException(string code) : Exception(code) { public string Code { get; } = code; }

/// <summary>Explicit account-scoped presentation saves, with no legacy-file or remote writes.</summary>
public sealed class LocalPersonalProfileStore(string root)
{
    private readonly string _directory = Path.Combine(Path.GetFullPath(root), "personal-profile-local-v1");
    private const int MaximumBytes = 64 * 1024;
    internal static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        PropertyNameCaseInsensitive = false, UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow, MaxDepth = 12
    };
    private sealed record SavedFile(int SchemaVersion, string OwnerHash, LocalProfileSnapshot Snapshot, string Integrity);

    public LocalProfileSnapshot Read(BridgeAccountContext owner)
    {
        var hash = OwnerHash(owner);
        try
        {
            if (!CheckPath(_directory, true) || !CheckPath(PathFor(hash), false)) return new(0, null, null, null);
            using var stream = new FileStream(PathFor(hash), FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete);
            if (stream.Length is <= 0 or > MaximumBytes) throw new IOException();
            var bytes = new byte[(int)stream.Length];
            stream.ReadExactly(bytes);
            if (stream.ReadByte() != -1) throw new IOException();
            using var doc = JsonDocument.Parse(bytes, new JsonDocumentOptions { MaxDepth = 12 });
            RejectDuplicates(doc.RootElement);
            var file = JsonSerializer.Deserialize<SavedFile>(bytes, Json);
            if (file is null || file.SchemaVersion != 1 || file.OwnerHash != hash || file.Snapshot is null ||
                file.Integrity != Integrity(hash, file.Snapshot) || file.Snapshot.Revision <= 0 ||
                file.Snapshot.SavedAt is null || file.Snapshot.SavedAt < DateTimeOffset.UnixEpoch ||
                !Guid.TryParseExact(file.Snapshot.OperationId, "N", out _)) throw new IOException();
            Validate(file.Snapshot.Content);
            return file.Snapshot;
        }
        catch (Exception e) when (StorageError(e) || e is LocalProfileException)
        { throw new LocalProfileException("profile_local.read_failed"); }
    }

    public LocalProfileSnapshot Save(BridgeAccountContext owner, long expectedRevision, string operationId,
        LocalProfileContent content, Func<bool> canCommit)
    {
        var hash = OwnerHash(owner);
        Validate(content);
        if (expectedRevision < 0 || expectedRevision == long.MaxValue || !Guid.TryParseExact(operationId, "N", out _))
            throw new LocalProfileException("profile_local.invalid_request");
        content = content with {
            Modules = content.Modules.Select(m => m with { FavoriteShipIds = m.FavoriteShipIds?.ToArray() }).ToArray(),
            FavoriteShipIds = content.FavoriteShipIds?.ToArray(),
            PlayStyle = content.PlayStyle?.Copy(), Schedule = content.Schedule?.Copy()
        };
        var current = Read(owner);
        CheckRevision(current, expectedRevision, operationId, content);
        string? temporary = null;
        try
        {
            CheckPath(_directory, true);
            Directory.CreateDirectory(_directory);
            var path = PathFor(hash);
            CheckPath(path + ".lock", false);
            using var writeLock = new FileStream(path + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
            current = Read(owner);
            CheckRevision(current, expectedRevision, operationId, content);
            if (!canCommit()) throw new LocalProfileException("profile_local.account_changed");
            if (current.OperationId == operationId) return current;
            var next = new LocalProfileSnapshot(expectedRevision + 1, DateTimeOffset.UtcNow, operationId, content);
            var bytes = JsonSerializer.SerializeToUtf8Bytes(new SavedFile(1, hash, next, Integrity(hash, next)), Json);
            if (bytes.Length > MaximumBytes) throw new LocalProfileException("profile_local.invalid_request");
            temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
            { stream.Write(bytes); stream.Flush(true); }
            CheckPath(_directory, true);
            CheckPath(path, false);
            if (!canCommit()) throw new LocalProfileException("profile_local.account_changed");
            if (current.Revision > 0) File.Replace(temporary, path, null);
            else File.Move(temporary, path);
            return next;
        }
        catch (Exception e) when (StorageError(e)) { throw new LocalProfileException("profile_local.write_failed"); }
        finally
        {
            if (temporary is not null)
                try { File.Delete(temporary); } catch (Exception e) when (StorageError(e)) { }
        }
    }

    internal static void Validate(LocalProfileContent? content)
    {
        LocalProfileCollaborationPolicy.Validate(content?.PlayStyle, content?.Schedule);
        LocalProfileModulePolicy.Validate(content);
        if (content is null || string.IsNullOrWhiteSpace(content.CallSign) || content.CallSign.Length > 32 ||
            content.CallSign.Any(char.IsControl) || content.Introduction is null || content.Introduction.Length > 500 ||
            content.Introduction.Any(c => char.IsControl(c) && c is not ('\r' or '\n' or '\t')) ||
            content.AvatarStyle is < 0 or > 3 || string.IsNullOrWhiteSpace(content.WallpaperId) ||
            content.WallpaperId.Length > 100 || content.WallpaperId.Any(c => !char.IsAsciiLetterOrDigit(c) && c != '-') ||
            content.Modules is null)
            throw new LocalProfileException("profile_local.invalid_request");
    }
    private static void CheckRevision(LocalProfileSnapshot current, long expected, string operation, LocalProfileContent content)
    {
        if (current.OperationId == operation && current.Revision == expected + 1 &&
            JsonSerializer.Serialize(current.Content, Json) == JsonSerializer.Serialize(content, Json)) return;
        if (current.OperationId == operation || current.Revision != expected)
            throw new LocalProfileException("profile_local.conflict");
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
            .Any(v => v.Length > 2048 || v.Any(char.IsControl))) throw new LocalProfileException("profile_local.account_changed");
        return Hash(JsonSerializer.SerializeToUtf8Bytes(new[] { owner.Environment, owner.Authority, owner.Subject }));
    }
    private static string Hash(byte[] data) => Convert.ToHexString(SHA256.HashData(data));
    private static string Integrity(string owner, LocalProfileSnapshot snapshot) =>
        Hash(JsonSerializer.SerializeToUtf8Bytes(new { schemaVersion = 1, owner, snapshot }, Json));
    private string PathFor(string hash) => Path.Combine(_directory, hash + ".json");
    private static bool StorageError(Exception e) => e is IOException or UnauthorizedAccessException or JsonException or
        System.Security.SecurityException or ArgumentException or NotSupportedException;
}
