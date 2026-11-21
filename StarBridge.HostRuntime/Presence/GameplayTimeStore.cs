using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Presence;

public sealed record GameplayTimeSaved(long Revision, GameplayRecordingConsent Consent, long Seconds,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] bool? ShowOnProfile = null,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] DateTimeOffset? FirstRecordedAt = null,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] DateTimeOffset? HistoryImportedAt = null,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] long? HistoricalSeconds = null,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] string? ImportReceipt = null,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] bool? HistoryConsumed = null,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] GameplayPendingReset? PendingReset = null,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] long? AppliedResetRevision = null,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] GameplayPendingImport? PendingImport = null);
public sealed record GameplayPendingReset(string OperationId, long ExpectedRevision,
    [property: JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] DateTimeOffset? ExpiresAt = null);
public sealed record GameplayPendingImport(StarBridge.Core.Profiles.PersonalProfileGameplayStatisticsUpdateRequestContract Update);
public sealed class GameplayTimeException(string code) : Exception(code)
{
    public string Code { get; } = code;
}

/// <summary>One writer per account for the Host lifetime. No legacy import or remote IO.</summary>
public sealed class GameplayTimeStore(string root)
{
    internal GameplayRecordingConsent InitialConsent(string? verifiedHandle, out bool identityPending) =>
        Onboarding.OnlineGameplayConsent.Read(root, verifiedHandle, out identityPending);
    internal Func<BridgeAccountContext, BridgeAccountContext>? ResolveOwner { get; set; }
    internal GameplayFailureJournal Journal { get; } = new();
    internal VisitorGameplayTimeReceiptStore VisitorReceipts { get; } = new(root);
    private BridgeAccountContext StorageOwner(BridgeAccountContext owner)
    {
        try { return ResolveOwner?.Invoke(owner) ?? owner; }
        catch (Privacy.LocalPrivacyOwnerUnavailableException) { throw; }
        catch (Privacy.LocalPrivacyException) { throw new GameplayTimeException("gameplay.account_changed"); }
    }
    private readonly string _directory = Path.Combine(Path.GetFullPath(root), "gameplay-time-local-v1");
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        PropertyNameCaseInsensitive = false, UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow,
        MaxDepth = 8
    };
    private sealed record FileData(int SchemaVersion, string OwnerHash, GameplayTimeSaved Snapshot, string Integrity);

    public Lease Open(BridgeAccountContext owner)
    {
        var authentication = owner;
        owner = StorageOwner(authentication);
        if (owner is null || !owner.IsComplete ||
            new[] { owner.Environment, owner.Authority, owner.Subject }.Any(v => v.Length > 2048 || v.Any(char.IsControl)))
            throw new GameplayTimeException("gameplay.account_changed");
        var hash = Hash(JsonSerializer.SerializeToUtf8Bytes(new[] { owner.Environment, owner.Authority, owner.Subject }));
        try
        {
            Check(_directory, true);
            Directory.CreateDirectory(_directory);
            var path = Path.Combine(_directory, hash + ".json");
            Check(path + ".lock", false);
            var lease = new Lease(path, hash, new FileStream(path + ".lock", FileMode.OpenOrCreate,
                FileAccess.ReadWrite, FileShare.None)) {
                Journal = Journal,
                EnsureOwnerCurrent = () => {
                    if (StorageOwner(authentication) != owner) throw new GameplayTimeException("gameplay.account_changed");
                }
            };
            try { lease.ValidateOwner(); return lease; }
            catch { lease.Dispose(); throw; }
        }
        catch (Exception e) when (StorageError(e))
        {
            Journal.Record("gameplay-store", $"code=storage_unavailable file={hash[..8]}",
                $"code=storage_unavailable file={hash[..8]} exception={Support.IdentityGateJournal.Type(e)}");
            throw new GameplayTimeException("gameplay.storage_unavailable");
        }
    }

    // A file this version cannot read keeps its bytes: the store never rewrites it.
    // The journal names the first failed check so a newer or foreign writer is visible.
    private sealed class StoreRejected(string reason) : IOException(reason)
    {
        internal string Reason { get; } = reason;
    }
    private static StoreRejected Rejected(string reason) => new(reason);

    private static readonly HashSet<string> FileFields = Names(typeof(FileData));
    private static readonly HashSet<string> SnapshotFields = Names(typeof(GameplayTimeSaved));
    private static HashSet<string> Names(Type type) => type.GetProperties()
        .Select(p => JsonNamingPolicy.CamelCase.ConvertName(p.Name)).ToHashSet(StringComparer.Ordinal);
    private static bool UnknownField(JsonElement root) =>
        root.ValueKind == JsonValueKind.Object &&
        (root.EnumerateObject().Any(p => !FileFields.Contains(p.Name)) ||
         root.TryGetProperty("snapshot", out var snapshot) && snapshot.ValueKind == JsonValueKind.Object &&
         snapshot.EnumerateObject().Any(p => !SnapshotFields.Contains(p.Name)));

    public sealed class Lease : IDisposable
    {
        internal Action? EnsureOwnerCurrent { get; init; }
        internal GameplayFailureJournal? Journal { get; init; }
        internal void ValidateOwner() => EnsureOwnerCurrent?.Invoke();
        private readonly string _path;
        private readonly string _hash;
        private readonly FileStream _lock;
        internal Lease(string path, string hash, FileStream writeLock)
        { _path = path; _hash = hash; _lock = writeLock; }

        public GameplayTimeSaved Read()
        {
            ValidateOwner();
            var result = ReadCore();
            ValidateOwner();
            return result;
        }
        private GameplayTimeSaved ReadCore()
        {
            try
            {
                Check(Path.GetDirectoryName(_path)!, true);
                if (!Check(_path, false)) return new(0, GameplayRecordingConsent.Unknown, 0);
                using var stream = new FileStream(_path, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete);
                if (stream.Length is <= 0 or > 4096) throw Rejected("size");
                var bytes = new byte[(int)stream.Length];
                stream.ReadExactly(bytes);
                if (stream.ReadByte() != -1) throw Rejected("size");
                using var doc = JsonDocument.Parse(bytes);
                try { Profiles.LocalPersonalProfileStore.RejectDuplicates(doc.RootElement); }
                catch (Exception e) when (StorageError(e)) { throw Rejected("duplicate-field"); }
                if (UnknownField(doc.RootElement)) throw Rejected("unknown-field");
                var file = JsonSerializer.Deserialize<FileData>(bytes, Json);
                if (file is null || file.Snapshot is null) throw Rejected("empty");
                if (file.SchemaVersion != 1) throw Rejected("schema");
                if (file.OwnerHash != _hash) throw Rejected("owner");
                if (file.Integrity != Integrity(_hash, file.Snapshot)) throw Rejected("integrity");
                if (InvalidSnapshot(file.Snapshot) is { } reason) throw Rejected(reason);
                return file.Snapshot;
            }
            catch (Exception e) when (StorageError(e))
            {
                // Reason tokens and exception type names only; never contents or paths.
                var line = $"code=read_failed file={FilePrefix} reason=" +
                    (e is StoreRejected rejected ? rejected.Reason : "exception-" + Support.IdentityGateJournal.Type(e));
                Journal?.Record("gameplay-store", line, line);
                throw new GameplayTimeException("gameplay.read_failed");
            }
        }

        internal string FilePrefix => _hash[..8];

        private static string? InvalidSnapshot(GameplayTimeSaved snapshot) =>
            snapshot.Revision <= 0 ? "revision" :
            snapshot.Seconds < 0 ? "seconds" :
            !Enum.IsDefined(snapshot.Consent) ? "consent" :
            snapshot.AppliedResetRevision < 0 ? "reset-revision" :
            snapshot.PendingImport is { } import &&
                (!ValidImport(import) || snapshot.PendingReset is not null) ? "pending-import" :
            snapshot.PendingReset is { } pending &&
                (pending.ExpectedRevision < 0 || !Guid.TryParseExact(pending.OperationId, "N", out _)) ? "pending-reset" :
            snapshot.HistoricalSeconds < 0 || snapshot.HistoricalSeconds > snapshot.Seconds ? "historical-seconds" :
            snapshot.HistoricalSeconds > 0 && snapshot.HistoryImportedAt is null ? "history-date" :
            snapshot.ImportReceipt is { } receipt && (receipt.Length != 32 || !Guid.TryParseExact(receipt, "N", out _) ||
                snapshot.HistoryImportedAt is null) ? "import-receipt" : null;

        public GameplayTimeSaved Save(GameplayTimeSaved previous, GameplayRecordingConsent consent,
            long seconds, Func<bool> canCommit)
            => Save(previous, previous with { Consent = consent, Seconds = seconds }, canCommit);

        public GameplayTimeSaved Save(GameplayTimeSaved previous, GameplayTimeSaved desired, Func<bool> canCommit)
        {
            if (!Enum.IsDefined(desired.Consent) || desired.Seconds < previous.Seconds || previous.Revision == long.MaxValue ||
                (desired.HistoricalSeconds ?? 0) < (previous.HistoricalSeconds ?? 0) ||
                desired.HistoricalSeconds > desired.Seconds ||
                previous.HistoryImportedAt is not null && desired.HistoryImportedAt != previous.HistoryImportedAt ||
                previous.HistoryConsumed == true && desired.HistoryConsumed != true ||
                previous.FirstRecordedAt is not null && desired.FirstRecordedAt != previous.FirstRecordedAt ||
                previous.ImportReceipt is not null && desired.ImportReceipt != previous.ImportReceipt ||
                previous.PendingReset != desired.PendingReset || previous.AppliedResetRevision != desired.AppliedResetRevision ||
                previous.PendingImport != desired.PendingImport)
                throw new GameplayTimeException("gameplay.invalid_request");
            return Commit(previous, desired, canCommit);
        }

        internal GameplayTimeSaved BeginReset(GameplayTimeSaved previous, GameplayPendingReset pending, Func<bool> canCommit)
        {
            if (previous.PendingReset is not null || previous.PendingImport is not null || pending.ExpectedRevision < 0 ||
                !Guid.TryParseExact(pending.OperationId, "N", out _))
                throw new GameplayTimeException("gameplay.invalid_request");
            return Commit(previous, previous with { PendingReset = pending }, canCommit);
        }

        internal GameplayTimeSaved BeginImport(GameplayTimeSaved previous, GameplayPendingImport pending, Func<bool> canCommit)
        {
            if (!ValidImport(pending) || previous.PendingReset is not null || previous.PendingImport is not null ||
                previous.HistoryConsumed == true || previous.HistoryImportedAt is not null ||
                pending.Update.PlayTimeSeconds < previous.Seconds)
                throw new GameplayTimeException("gameplay.invalid_request");
            return Commit(previous, previous with { PendingImport = pending }, canCommit);
        }

        internal GameplayTimeSaved FinishImport(GameplayTimeSaved previous, GameplayPendingImport pending,
            bool confirmed, Func<bool> canCommit)
        {
            if (previous.PendingImport != pending) throw new GameplayTimeException("gameplay.conflict");
            var update = pending.Update;
            return Commit(previous, confirmed ? previous with {
                Seconds = Math.Max(previous.Seconds, update.PlayTimeSeconds),
                HistoryImportedAt = update.HistoryImportedAt, HistoricalSeconds = update.HistoricalPlayTimeSeconds,
                ImportReceipt = update.HistoryImportOperationId, HistoryConsumed = true, PendingImport = null
            } : previous with { PendingImport = null }, canCommit);
        }

        private static bool ValidImport(GameplayPendingImport pending)
        {
            var update = pending.Update;
            return update is not null && update.ExpectedGameplayRevision is >= 0 &&
                Guid.TryParseExact(update.HistoryImportOperationId, "N", out _) && update.HistoryImportedAt is not null &&
                update.HistoricalPlayTimeSeconds > 0 && update.PlayTimeSeconds >= update.HistoricalPlayTimeSeconds &&
                update.HistoricalSessionCount >= 0 && update.HistoricalIncompleteSessionCount >= 0 &&
                update.HistoricalIncompleteSessionCount <= update.HistoricalSessionCount &&
                update.DownedCount == 0 && update.DeathCount == 0 &&
                (update.ResetOperationId is null || Guid.TryParseExact(update.ResetOperationId, "N", out _));
        }

        internal GameplayTimeSaved FinishReset(GameplayTimeSaved previous, GameplayPendingReset pending,
            bool confirmed, Func<bool> canCommit, long? confirmedResetRevision = null)
        {
            if (previous.PendingReset != pending) throw new GameplayTimeException("gameplay.conflict");
            var desired = confirmed ? previous with {
                Seconds = 0, HistoricalSeconds = null, HistoryImportedAt = null, HistoryConsumed = null,
                ImportReceipt = null, FirstRecordedAt = null, PendingReset = null, PendingImport = null,
                AppliedResetRevision = confirmedResetRevision ?? checked(pending.ExpectedRevision + 1)
            } : previous with { PendingReset = null };
            return Commit(previous, desired, canCommit);
        }

        internal GameplayTimeSaved ApplyAccountReset(GameplayTimeSaved previous, long resetRevision, Func<bool> canCommit)
        {
            if (previous.PendingReset is not null || resetRevision <= (previous.AppliedResetRevision ?? 0))
                throw new GameplayTimeException("gameplay.conflict");
            return Commit(previous, previous with {
                Seconds = 0, HistoricalSeconds = null, HistoryImportedAt = null, HistoryConsumed = null,
                ImportReceipt = null, FirstRecordedAt = null, AppliedResetRevision = resetRevision, PendingImport = null
            }, canCommit);
        }

        private GameplayTimeSaved Commit(GameplayTimeSaved previous, GameplayTimeSaved desired, Func<bool> canCommit)
        {
            if (previous.Revision == long.MaxValue) throw new GameplayTimeException("gameplay.invalid_request");
            string? temporary = null;
            try
            {
                if (Read() != previous) throw new GameplayTimeException("gameplay.conflict");
                if (!canCommit()) throw new GameplayTimeException("gameplay.account_changed");
                ValidateOwner();
                var next = desired with { Revision = previous.Revision + 1 };
                var bytes = JsonSerializer.SerializeToUtf8Bytes(new FileData(1, _hash, next, Integrity(_hash, next)), Json);
                temporary = _path + "." + Guid.NewGuid().ToString("N") + ".tmp";
                using (var file = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None,
                    4096, FileOptions.WriteThrough))
                { file.Write(bytes); file.Flush(true); }
                Check(Path.GetDirectoryName(_path)!, true);
                Check(_path, false);
                if (!canCommit()) throw new GameplayTimeException("gameplay.account_changed");
                ValidateOwner();
                if (previous.Revision == 0) File.Move(temporary, _path);
                else File.Replace(temporary, _path, null);
                return next;
            }
            catch (Exception e) when (StorageError(e))
            {
                Journal?.Record("gameplay-store", $"code=write_failed file={FilePrefix}",
                    $"code=write_failed file={FilePrefix} exception={Support.IdentityGateJournal.Type(e)}");
                throw new GameplayTimeException("gameplay.write_failed");
            }
            finally
            {
                if (temporary is not null)
                    try { File.Delete(temporary); } catch (Exception e) when (StorageError(e)) { }
            }
        }
        public void Dispose() => _lock.Dispose();
    }
    private static string Hash(byte[] bytes) => Convert.ToHexString(SHA256.HashData(bytes));
    private static string Integrity(string hash, GameplayTimeSaved snapshot) =>
        Hash(JsonSerializer.SerializeToUtf8Bytes(new { schemaVersion = 1, hash, snapshot }, Json));
    private static bool StorageError(Exception e) => e is IOException or UnauthorizedAccessException or
        JsonException or ArgumentException or NotSupportedException or System.Security.SecurityException;
    private static bool Check(string path, bool directory)
    {
        FileAttributes attributes;
        try { attributes = File.GetAttributes(path); }
        catch (FileNotFoundException) { return false; }
        catch (DirectoryNotFoundException) { return false; }
        if (attributes.HasFlag(FileAttributes.ReparsePoint) || attributes.HasFlag(FileAttributes.Directory) != directory)
            throw new IOException();
        return true;
    }
}
