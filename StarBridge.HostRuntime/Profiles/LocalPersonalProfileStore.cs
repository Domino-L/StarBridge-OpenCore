using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;
using StarBridge.NativeBridge;
using StarBridge.Core.Profiles;

namespace StarBridge.HostRuntime.Profiles;

public sealed record LocalProfileLayout(string Id, int Span, bool IsVisible, int Position,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] IReadOnlyList<string>? FavoriteShipIds = null);
public sealed record LocalProfileContent(string CallSign, string Introduction, int AvatarStyle,
    string WallpaperId, IReadOnlyList<LocalProfileLayout> Modules, IReadOnlyList<string>? FavoriteShipIds,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] LocalProfilePlayStyle? PlayStyle = null,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] LocalProfileSchedule? Schedule = null,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingDefault)] bool PreserveEmptyFields = false,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] IReadOnlyList<PersonalProfileShowcaseContract>? Showcases = null,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] IReadOnlyList<string>? AchievementShowcase = null,
    // 0.7.3 main role (user 11-05): one of PlayStyle.Roles. Kept only in the sidefile; on a save
    // null keeps the saved one and "" clears it.
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? MainRole = null,
    // Explicit defaults from the editor or the matching field state file.
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] IReadOnlyDictionary<string, bool>? FieldStates = null);
public sealed record LocalProfileSnapshot(long Revision, DateTimeOffset? SavedAt, string? OperationId, LocalProfileContent? Content);
public sealed class LocalProfileException(string code) : Exception(code) { public string Code { get; } = code; }

/// <summary>Explicit account-scoped presentation saves, with no legacy-file or remote writes.</summary>
public sealed partial class LocalPersonalProfileStore(string root)
{
    internal Func<BridgeAccountContext, BridgeAccountContext>? ResolveOwner { get; set; }
    private string ResolvedHash(BridgeAccountContext owner)
    {
        try { return OwnerHash(ResolveOwner?.Invoke(owner) ?? owner); }
        catch (Privacy.LocalPrivacyException) { throw new LocalProfileException("profile_local.account_changed"); }
    }
    internal string ImportJournalDirectory => Path.Combine(Path.GetFullPath(root), "personal-profile-import-v1");
    private readonly string _directory = Path.Combine(Path.GetFullPath(root), "personal-profile-local-v1");
    private const int MaximumBytes = 64 * 1024;
    internal static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        PropertyNameCaseInsensitive = false, UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow, MaxDepth = 12
    };
    private sealed record SavedFile(int SchemaVersion, string OwnerHash, LocalProfileSnapshot Snapshot, string Integrity);

    public LocalProfileSnapshot Read(BridgeAccountContext owner)
        => Read(owner, out _, out _, out _);

    private LocalProfileSnapshot Read(BridgeAccountContext owner, out (bool Readable, string? OperationId) showcase,
        out bool hasInlineShowcases, out string[]? explicitlyEmpty)
    {
        showcase = default;
        hasInlineShowcases = false;
        explicitlyEmpty = null;
        var hash = ResolvedHash(owner);
        try
        {
            if (!CheckPath(_directory, true) || !CheckPath(PathFor(hash), false))
            {
                if (ResolvedHash(owner) != hash) throw new LocalProfileException("profile_local.account_changed");
                return new(0, null, null, null);
            }
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
            // Build 61 stored the additive fields inline. Keep accepting its exact
            // checksum; only a later explicit save converts it to the old disk shape.
            hasInlineShowcases = file.Snapshot.Content is { Showcases: not null } or { AchievementShowcase: not null };
            var snapshot = ReadShowcases(hash, file.Snapshot, out showcase);
            explicitlyEmpty = ReadFieldStates(hash, snapshot);
            if (ResolvedHash(owner) != hash) throw new LocalProfileException("profile_local.account_changed");
            return snapshot with { Content = snapshot.Content! with {
                FieldStates = explicitlyEmpty is { Length: > 0 }
                    ? explicitlyEmpty.ToDictionary(field => field, _ => true, StringComparer.Ordinal) : null
            } };
        }
        catch (Exception e) when (StorageError(e) || e is LocalProfileException)
        { throw new LocalProfileException("profile_local.read_failed"); }
    }

    public LocalProfileSnapshot Save(BridgeAccountContext owner, long expectedRevision, string operationId,
        LocalProfileContent content, Func<bool> canCommit)
        => SaveCore(owner, expectedRevision, operationId, content, canCommit, false);

    internal LocalProfileSnapshot SaveImported(BridgeAccountContext owner, long expectedRevision, string operationId,
        LocalProfileContent content, Func<bool> canCommit, bool hasJournalShowcases = true)
        => SaveCore(owner, expectedRevision, operationId, content, canCommit, true, hasJournalShowcases);

    private LocalProfileSnapshot SaveCore(BridgeAccountContext owner, long expectedRevision, string operationId,
        LocalProfileContent content, Func<bool> canCommit, bool selectedImport, bool hasJournalShowcases = true)
    {
        var hash = ResolvedHash(owner);
        var originalCanCommit = canCommit;
        canCommit = () => originalCanCommit() && ResolvedHash(owner) == hash;
        Validate(content);
        if (content.FieldStates?.Any(field => !field.Value || !IsExplicitDefault(content, field.Key)) == true)
            throw new LocalProfileException("profile_local.invalid_request");
        if (expectedRevision < 0 || expectedRevision == long.MaxValue || !Guid.TryParseExact(operationId, "N", out _))
            throw new LocalProfileException("profile_local.invalid_request");
        content = content with {
            Modules = content.Modules.Select(m => m with { FavoriteShipIds = m.FavoriteShipIds?.ToArray() }).ToArray(),
            FavoriteShipIds = content.FavoriteShipIds?.ToArray(),
            Showcases = content.Showcases?.ToArray(), AchievementShowcase = content.AchievementShowcase?.ToArray(),
            FieldStates = content.FieldStates?.ToDictionary(field => field.Key, field => field.Value, StringComparer.Ordinal),
            PlayStyle = content.PlayStyle?.Copy(), Schedule = content.Schedule?.Copy()
        };
        var requestedContent = content;
        var fields = ExplicitlyEmpty(requestedContent);
        var current = Read(owner, out var showcase, out var hasInlineShowcases, out _);
        content = PreserveShowcases(requestedContent, current.Content);
        CheckRevision(current, expectedRevision, operationId, content, showcase.OperationId, hasInlineShowcases);
        try
        {
            CheckPath(_directory, true);
            Directory.CreateDirectory(_directory);
            var path = PathFor(hash);
            CheckPath(path + ".lock", false);
            using var writeLock = new FileStream(path + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
            current = Read(owner, out showcase, out hasInlineShowcases, out var savedFields);
            content = PreserveShowcases(requestedContent, current.Content);
            CheckRevision(current, expectedRevision, operationId, content, showcase.OperationId, hasInlineShowcases);
            if (!selectedImport) LocalProfileCollaborationPolicy.ValidateEdit(content.PlayStyle, current.Content?.PlayStyle);
            if (!canCommit()) throw new LocalProfileException("profile_local.account_changed");
            if (hasInlineShowcases)
            {
                // Preserve the already committed operation before starting this
                // save. A failed split must never discard inline values or [].
                MigrateInline(hash, current, canCommit);
                current = Read(owner, out showcase, out hasInlineShowcases, out savedFields);
                content = PreserveShowcases(requestedContent, current.Content);
                CheckRevision(current, expectedRevision, operationId, content, showcase.OperationId, hasInlineShowcases);
                if (!canCommit()) throw new LocalProfileException("profile_local.account_changed");
            }
            // An import can recover the main fields even when neither showcase copy is readable.
            var writeShowcases = hasJournalShowcases || showcase.Readable;
            if (current.OperationId == operationId)
            {
                if (!selectedImport && savedFields is not null && !savedFields.SequenceEqual(fields, StringComparer.Ordinal))
                    throw new LocalProfileException("profile_local.conflict");
                // Repair incomplete side writes under the same lock, keeping
                // the revision, timestamp and main bytes already committed.
                if (writeShowcases && showcase.OperationId != operationId)
                    WriteAtomic(SidePath(hash), ShowcaseBytes(hash, operationId, content), canCommit);
                if (savedFields is null)
                    WriteAtomic(FieldStatePath(hash), FieldStateBytes(hash, operationId, fields), canCommit);
                else
                    content = content with { FieldStates = current.Content!.FieldStates };
                return current with { Content = content };
            }
            var next = new LocalProfileSnapshot(expectedRevision + 1, DateTimeOffset.UtcNow, operationId, content);
            var disk = MainSnapshot(next);
            var bytes = JsonSerializer.SerializeToUtf8Bytes(new MainFile(1, hash, disk, MainIntegrity(hash, disk)), Json);
            if (bytes.Length > MaximumBytes) throw new LocalProfileException("profile_local.invalid_request");
            var sideBytes = writeShowcases ? ShowcaseBytes(hash, operationId, content) : null;
            WriteAtomic(path, bytes, canCommit);
            if (sideBytes is not null) WriteAtomic(SidePath(hash), sideBytes, canCommit);
            WriteAtomic(FieldStatePath(hash), FieldStateBytes(hash, operationId, fields), canCommit);
            return next;
        }
        catch (Exception e) when (StorageError(e)) { throw new LocalProfileException("profile_local.write_failed"); }
    }

    // Missing additive fields are an old-client edit, while [] explicitly clears.
    // Merge again under the write lock, before revision/idempotency checks.
    private static LocalProfileContent PreserveShowcases(LocalProfileContent requested, LocalProfileContent? current) =>
        requested with {
            Showcases = (requested.Showcases ?? current?.Showcases)?.ToArray(),
            AchievementShowcase = (requested.AchievementShowcase ?? current?.AchievementShowcase)?.ToArray(),
            MainRole = KeptMainRole(requested.MainRole switch { null => current?.MainRole, "" => null, var role => role },
                requested.PlayStyle)
        };

    /// <summary>A main role survives only while it is still one of the roles.</summary>
    internal static string? KeptMainRole(string? role, LocalProfilePlayStyle? style) =>
        role is not null && style?.Roles?.Contains(role, StringComparer.Ordinal) == true ? role : null;

    internal static void Validate(LocalProfileContent? content)
    {
        LocalProfileCollaborationPolicy.Validate(content?.PlayStyle, content?.Schedule);
        LocalProfileModulePolicy.Validate(content);
        if (content is null || string.IsNullOrWhiteSpace(content.CallSign) || content.CallSign.Length > 32 ||
            content.CallSign.Any(char.IsControl) || content.Introduction is null || content.Introduction.Length > 500 ||
            content.Introduction.Any(c => char.IsControl(c) && c is not ('\r' or '\n' or '\t')) ||
            content.AvatarStyle is < 0 or > 3 || string.IsNullOrWhiteSpace(content.WallpaperId) ||
            content.WallpaperId.Length > 100 || content.WallpaperId.Any(c => !char.IsAsciiLetterOrDigit(c) && c != '-') ||
            content.Modules is null ||
            content.MainRole is { } role && (role.Length > 80 || role.Any(char.IsControl) ||
                role.Length > 0 && content.PlayStyle?.Roles?.Contains(role, StringComparer.Ordinal) != true))
            throw new LocalProfileException("profile_local.invalid_request");
    }

    private static void CheckRevision(LocalProfileSnapshot current, long expected, string operation,
        LocalProfileContent content, string? showcaseOperationId, bool hasInlineShowcases)
    {
        if (IsCommittedSave(current, expected, operation, content, showcaseOperationId, hasInlineShowcases)) return;
        if (current.OperationId == operation || current.Revision != expected)
            throw new LocalProfileException("profile_local.conflict");
    }
    internal bool IsCommittedImport(BridgeAccountContext owner, long expected, string operation, LocalProfileContent? content)
    {
        var current = Read(owner, out var showcase, out var hasInlineShowcases, out _);
        return content is not null &&
            IsCommittedSave(current, expected, operation, PreserveShowcases(content, current.Content),
                showcase.OperationId, hasInlineShowcases);
    }

    private static bool IsCommittedSave(LocalProfileSnapshot current, long expected, string operation,
        LocalProfileContent content, string? showcaseOperationId, bool hasInlineShowcases) =>
        current.OperationId == operation && current.Revision == expected + 1 &&
        // Build 61 committed inline fields with main. Otherwise compare only
        // the committed main until its corresponding showcase write finishes.
        (hasInlineShowcases || showcaseOperationId == operation
            ? JsonSerializer.Serialize(current.Content! with { FieldStates = null }, Json) ==
                JsonSerializer.Serialize(content with { FieldStates = null }, Json)
            : MainContentFor(current.Content) is { } main &&
                JsonSerializer.Serialize(main, Json) == JsonSerializer.Serialize(MainContentFor(content), Json));
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
        // Check ancestors too, including a missing destination below a linked root.
        for (var parent = Path.GetDirectoryName(path); parent is not null; parent = Path.GetDirectoryName(parent))
        {
            try { if (File.GetAttributes(parent).HasFlag(FileAttributes.ReparsePoint)) throw new IOException(); }
            catch (FileNotFoundException) { }
            catch (DirectoryNotFoundException) { }
        }
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
