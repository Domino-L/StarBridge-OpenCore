using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;
using StarBridge.Core.Presence;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Privacy;

/// <summary>
/// Account-scoped local choices and Host-confirmed consent metadata. No legacy
/// promotion, remote writer or publication-policy fallback is reachable here.
/// </summary>
public sealed class LocalPrivacyStore(string root)
{
    internal PositivePublicationAdmission PositiveAdmission { get; } = new();
    internal Func<BridgeAccountContext, BridgeAccountContext>? ResolveOwner { get; set; }
    private string ResolvedHash(BridgeAccountContext owner) => OwnerHash(ResolveOwner?.Invoke(owner) ?? owner);
    private readonly string _directory = Path.Combine(Path.GetFullPath(root), "privacy-local-v1");
    private const int MaximumBytes = 192 * 1024;
    internal static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        PropertyNameCaseInsensitive = false,
        UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow,
        MaxDepth = 10
    };
    private sealed record SavedFile(int SchemaVersion, string OwnerHash, LocalPrivacySnapshot Snapshot, string Integrity,
        [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] int? ConsentVersion = null,
        [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingDefault)] bool PublicationPaused = false);

    public LocalPrivacySnapshot Read(BridgeAccountContext owner) => ReadFile(owner)?.Snapshot ?? new(0, null, null, null);

    internal bool HasPublicationConsent(BridgeAccountContext owner) => ReadFile(owner)?.ConsentVersion == 1;
    internal bool IsPublicationPaused(BridgeAccountContext owner) => ReadFile(owner)?.PublicationPaused == true;
    internal bool IsPublicationRevoked(BridgeAccountContext owner) => ReadFile(owner)?.ConsentVersion == 0;

    // null = not asked; 0 = declined/revoked; 1 = confirmed. A refusal is a
    // completed choice, never permission to publish or a reason to ask again.
    internal bool NeedsFirstChoice(BridgeAccountContext owner) => ReadFile(owner) is null &&
        !File.Exists(Path.Combine(root, "desktop.config")) &&
        !File.Exists(Path.Combine(root, "onboarding.complete")) &&
        !File.Exists(Path.Combine(root, "onboarding-introduction.read"));

    private SavedFile? ReadFile(BridgeAccountContext owner)
    {
        var hash = ResolvedHash(owner);
        try
        {
            if (!CheckPath(_directory, true) || !CheckPath(PathFor(hash), false))
            {
                if (ResolvedHash(owner) != hash) throw new LocalPrivacyException("privacy_local.account_changed");
                return null;
            }
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
                file.Integrity != Integrity(hash, file.Snapshot, file.ConsentVersion, file.PublicationPaused) || file.Snapshot.Revision <= 0 ||
                file.Snapshot.SavedAt is null || file.Snapshot.SavedAt < DateTimeOffset.UnixEpoch ||
                !Guid.TryParseExact(file.Snapshot.OperationId, "N", out _) || file.Snapshot.Settings is null)
                throw new IOException();
            if (ResolvedHash(owner) != hash) throw new LocalPrivacyException("privacy_local.account_changed");
            return file with { Snapshot = file.Snapshot with { Settings = file.Snapshot.Settings.ValidatedCopy() } };
        }
        catch (LocalPrivacyOwnerUnavailableException) { throw; }
        catch (IOException e) when ((e.HResult & 0xffff) is 32 or 33)
        { throw new LocalPrivacyReadUnavailableException(); }
        catch (Exception e) when (StorageError(e) || e is LocalPrivacyException)
        { throw new LocalPrivacyException("privacy_local.read_failed"); }
    }

    public LocalPrivacySnapshot Save(BridgeAccountContext owner, long expectedRevision, string operationId,
        LocalPrivacySettings settings, Func<bool> canCommit, CancellationToken cancellation = default)
        => SaveAsync(owner, expectedRevision, operationId, settings, canCommit, cancellation).GetAwaiter().GetResult();

    public Task<LocalPrivacySnapshot> SaveAsync(BridgeAccountContext owner, long expectedRevision, string operationId,
        LocalPrivacySettings settings, Func<bool> canCommit, CancellationToken cancellation = default)
        => SaveCoreAsync(owner, expectedRevision, operationId, () =>
        {
            if (settings is null) throw new LocalPrivacyException("privacy_local.invalid_request");
            var copy = settings.ValidatedCopy();
            return _ => copy;
        }, canCommit, cancellation);

    internal LocalPrivacySnapshot SaveMerged(BridgeAccountContext owner, long expectedRevision, string operationId,
        Func<LocalPrivacySnapshot, LocalPrivacySettings> merge, Func<bool> canCommit, CancellationToken cancellation = default)
        => SaveMergedAsync(owner, expectedRevision, operationId, merge, canCommit, cancellation).GetAwaiter().GetResult();

    // Whatever a save retains from the saved file is taken from the revision it
    // replaces, under the write lock, and never from an earlier lease-free read.
    internal Task<LocalPrivacySnapshot> SaveMergedAsync(BridgeAccountContext owner, long expectedRevision, string operationId,
        Func<LocalPrivacySnapshot, LocalPrivacySettings> merge, Func<bool> canCommit, CancellationToken cancellation = default)
        => SaveCoreAsync(owner, expectedRevision, operationId, () => merge, canCommit, cancellation);

    private async Task<LocalPrivacySnapshot> SaveCoreAsync(BridgeAccountContext owner, long expectedRevision, string operationId,
        Func<Func<LocalPrivacySnapshot, LocalPrivacySettings>> prepare, Func<bool> canCommit, CancellationToken cancellation)
    {
        using var admission = await PositiveAdmission.EnterAsync(cancellation).ConfigureAwait(false);
        var hash = ResolvedHash(owner);
        var originalCanCommit = canCommit;
        canCommit = () => !cancellation.IsCancellationRequested && originalCanCommit() && ResolvedHash(owner) == hash;
        if (expectedRevision < 0 || expectedRevision == long.MaxValue ||
            !Guid.TryParseExact(operationId, "N", out _)) throw new LocalPrivacyException("privacy_local.invalid_request");
        var merge = prepare();
        if (!canCommit()) throw new LocalPrivacyException("privacy_local.account_changed");
        var current = Read(owner);
        var settings = merge(current).ValidatedCopy();
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
            settings = merge(current).ValidatedCopy();
            CheckRevision(current, expectedRevision, operationId, settings);
            if (!canCommit()) throw new LocalPrivacyException("privacy_local.account_changed");
            if (current.OperationId == operationId) return current;
            var next = new LocalPrivacySnapshot(expectedRevision + 1, DateTimeOffset.UtcNow, operationId, settings);
            // Turning sharing off revokes remembered consent even if it is turned
            // back on before the publication timer observes the disabled revision.
            var consent = settings.PublicationEnabled ? ReadFile(owner)?.ConsentVersion : 0;
            var paused = ReadFile(owner)?.PublicationPaused == true;
            var bytes = JsonSerializer.SerializeToUtf8Bytes(new SavedFile(1, hash, next, Integrity(hash, next, consent, paused), consent, paused), Json);
            if (bytes.Length > MaximumBytes) throw new LocalPrivacyException("privacy_local.invalid_request");
            temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
            { stream.Write(bytes); stream.Flush(true); }
            CheckPath(_directory, true);
            CheckPath(path, false);
            if (!canCommit()) throw new LocalPrivacyException("privacy_local.account_changed");
            if (current.Revision == 0) File.Move(temporary, path);
            else if (!StoreFileCommit.ReplaceIfUnchanged(temporary, path, CommitStillAllowed(path, canCommit), MaximumBytes, "Local privacy commit did not complete."))
                throw new LocalPrivacyException(canCommit() ? "privacy_local.conflict" : "privacy_local.account_changed");
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
    // Uses the same lock and atomic replacement; existing policy revisions stay
    // unchanged. Only a pause or an actual withdrawal obligation creates a
    // minimal, disabled policy when no saved policy exists.
    internal void SetPublicationConsent(BridgeAccountContext owner, long revision, bool enabled, Func<bool> canCommit,
        CancellationToken cancellation = default)
        => SetPublicationConsentAsync(owner, revision, enabled, canCommit, cancellation).GetAwaiter().GetResult();

    internal Task SetPublicationConsentAsync(BridgeAccountContext owner, long revision, bool enabled, Func<bool> canCommit,
        CancellationToken cancellation = default, bool withdrawalRequired = false)
        => SetPublicationMetadataAsync(owner, revision, enabled, false, canCommit, cancellation, withdrawalRequired);

    internal void SetPublicationPaused(BridgeAccountContext owner, long revision, bool paused, Func<bool> canCommit)
        => SetPublicationPausedAsync(owner, revision, paused, canCommit).GetAwaiter().GetResult();

    internal Task SetPublicationPausedAsync(BridgeAccountContext owner, long revision, bool paused, Func<bool> canCommit,
        CancellationToken cancellation = default)
        => SetPublicationMetadataAsync(owner, revision, null, paused, canCommit, cancellation);

    private async Task SetPublicationMetadataAsync(BridgeAccountContext owner, long revision, bool? enabled, bool paused,
        Func<bool> canCommit, CancellationToken cancellation, bool withdrawalRequired = false)
    {
        using var admission = await PositiveAdmission.EnterAsync(cancellation).ConfigureAwait(false);
        var hash = ResolvedHash(owner);
        var originalCanCommit = canCommit;
        canCommit = () => !cancellation.IsCancellationRequested && originalCanCommit() && ResolvedHash(owner) == hash;
        string? temporary = null;
        try
        {
            if (!canCommit()) throw new LocalPrivacyException("privacy_local.account_changed");
            var file = ReadFile(owner);
            if ((file?.Snapshot.Revision ?? 0) != revision ||
                enabled == true && file?.Snapshot.Settings?.PublicationEnabled != true)
                throw new LocalPrivacyException("privacy_local.conflict");
            // A fresh stop with no consent or withdrawal obligation is read-only,
            // just like clearing a nonexistent pause. Validate revision first.
            // The publisher admits room-only pauses only after definite invisible
            // observation and confirmed membership/actual renewal activity.
            if (file is null && !paused && !withdrawalRequired) return;
            CheckPath(_directory, true);
            Directory.CreateDirectory(_directory);
            var path = PathFor(hash);
            CheckPath(path + ".lock", false);
            using var writeLock = new FileStream(path + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
            file = ReadFile(owner);
            if ((file?.Snapshot.Revision ?? 0) != revision ||
                enabled == true && file?.Snapshot.Settings?.PublicationEnabled != true)
                throw new LocalPrivacyException("privacy_local.conflict");
            var creating = file is null;
            if (file is null)
            {
                // No editor defaults, consent, or positive sharing scopes are
                // inferred from a room pause or a withdrawal obligation.
                var snapshot = new LocalPrivacySnapshot(1, DateTimeOffset.UtcNow, Guid.NewGuid().ToString("N"),
                    new(false, new(PlayerSharedStateFields.None, false, false, []),
                        new(PlayerSharedStateFields.None, false)));
                file = new(1, hash, snapshot, Integrity(hash, snapshot, null));
            }
            int? consent = enabled is null ? file.ConsentVersion : enabled.Value ? 1 : 0;
            // Revocation must not silently resume a durable room-only pause.
            if (enabled == false) paused |= file.PublicationPaused;
            if (file.ConsentVersion == consent && file.PublicationPaused == paused) return;
            var next = file with { ConsentVersion = consent, PublicationPaused = paused,
                Integrity = Integrity(hash, file.Snapshot, consent, paused) };
            var bytes = JsonSerializer.SerializeToUtf8Bytes(next, Json);
            if (bytes.Length > MaximumBytes) throw new LocalPrivacyException("privacy_local.write_failed");
            temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
            { stream.Write(bytes); stream.Flush(true); }
            CheckPath(_directory, true);
            CheckPath(path, false);
            if (!canCommit()) throw new LocalPrivacyException("privacy_local.account_changed");
            if (creating) File.Move(temporary, path);
            else if (!StoreFileCommit.ReplaceIfUnchanged(temporary, path, CommitStillAllowed(path, canCommit), MaximumBytes, "Local privacy commit did not complete."))
                throw new LocalPrivacyException(canCommit() ? "privacy_local.conflict" : "privacy_local.account_changed");
        }
        catch (Exception e) when (StorageError(e)) { throw new LocalPrivacyException("privacy_local.write_failed"); }
        finally
        {
            if (temporary is not null)
                try { File.Delete(temporary); } catch (Exception e) when (StorageError(e)) { }
        }
    }

    // A wait for a reader may outlast the checks made before the commit.
    private Func<bool> CommitStillAllowed(string path, Func<bool> canCommit) => () =>
    {
        CheckPath(_directory, true);
        CheckPath(path, false);
        return canCommit();
    };

    private static void CheckRevision(LocalPrivacySnapshot current, long expected, string operation, LocalPrivacySettings settings)
    {
        if (IsCommittedOperation(current, expected, operation, settings)) return;
        if (current.OperationId == operation || current.Revision != expected)
            throw new LocalPrivacyException("privacy_local.conflict");
    }

    internal static bool IsCommittedOperation(LocalPrivacySnapshot current, long expected, string operation, LocalPrivacySettings settings) =>
        expected >= 0 && expected < long.MaxValue && Guid.TryParseExact(operation, "N", out _) &&
        current.OperationId == operation && current.Revision == expected + 1 &&
        JsonSerializer.Serialize(current.Settings, Json) == JsonSerializer.Serialize(settings, Json);

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
    private static string Integrity(string owner, LocalPrivacySnapshot snapshot, int? consent, bool paused = false) => paused
        ? Hash(JsonSerializer.SerializeToUtf8Bytes(new { schemaVersion = 1, owner, snapshot, consentVersion = consent, publicationPaused = true }, Json))
        : consent is null
        ? Hash(JsonSerializer.SerializeToUtf8Bytes(new { schemaVersion = 1, owner, snapshot }, Json))
        : Hash(JsonSerializer.SerializeToUtf8Bytes(new { schemaVersion = 1, owner, snapshot, consentVersion = consent }, Json));
    private string PathFor(string hash) => Path.Combine(_directory, hash + ".json");
    private static bool StorageError(Exception e) => e is IOException or UnauthorizedAccessException or JsonException or
        System.Security.SecurityException or ArgumentException or NotSupportedException;
}

