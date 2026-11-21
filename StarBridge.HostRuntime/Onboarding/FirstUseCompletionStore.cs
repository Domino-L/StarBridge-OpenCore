using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace StarBridge.HostRuntime.Onboarding;

// A historical display receipt. Never an identity, recording or publication grant.
internal sealed record FirstUseCompletion(
    [property: JsonRequired] long Revision,
    [property: JsonRequired] string OperationId,
    [property: JsonRequired] DateTimeOffset CompletedAt,
    [property: JsonRequired] string Mode,
    [property: JsonRequired] string? ProfileId,
    [property: JsonRequired] string? SourceKey,
    bool LogDeferred = false,
    // Read from the receipt file itself: written by a checked save whose
    // after-commit check has not passed. Never part of the deferred payload.
    [property: JsonIgnore] bool Unconfirmed = false);

internal sealed class FirstUseCompletionStore(string root)
{
    private readonly string _directory = Path.Combine(Path.GetFullPath(root), "first-use-completion-v1");
    private readonly string _deferredDirectory = Path.Combine(Path.GetFullPath(root), "first-use-completion-deferred-v1");
    private string StatePath => Path.Combine(_directory, "state.bin");
    private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("StarBridge.first-use-completion.v1");
    private static readonly byte[] DeferredEntropy = Encoding.UTF8.GetBytes("StarBridge.first-use-completion-deferred.v1");
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    { UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow, PropertyNameCaseInsensitive = false, MaxDepth = 4 };
    // Keep the ordinary payload byte-for-byte equivalent to 0.7.2.1 before DPAPI.
    private sealed record LegacyValue([property: JsonRequired] long Revision,
        [property: JsonRequired] string OperationId, [property: JsonRequired] DateTimeOffset CompletedAt,
        [property: JsonRequired] string Mode, [property: JsonRequired] string ProfileId,
        [property: JsonRequired] string SourceKey);
    private sealed record Document([property: JsonRequired] int SchemaVersion,
        [property: JsonRequired] LegacyValue Value);
    private sealed record DeferredDocument([property: JsonRequired] int SchemaVersion,
        [property: JsonRequired] FirstUseCompletion Value);
    // The only other receipt form: the same value marked `"confirmed": false`,
    // written by a checked save (one with `afterCommit`) before that check
    // passed. Only a receipt in the 0.7.2.1 form above counts as confirmed, so
    // whoever reads this one, at any time and in any process, sees it as
    // unconfirmed, whatever happens to other files.
    private sealed record UnconfirmedDocument([property: JsonRequired] int SchemaVersion,
        [property: JsonRequired] LegacyValue Value, [property: JsonRequired] bool Confirmed);

    internal FirstUseCompletion? Read()
    {
        var value = ReadFile(StatePath, false) ?? ReadFile(Path.Combine(_deferredDirectory, "state.bin"), true);
        ReadProbe?.Invoke(value);
        return value;
    }

    private static FirstUseCompletion? ReadFile(string path, bool deferred)
    {
        try
        {
            Safe(path);
            FileStream stream;
            try { stream = new(path, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete); }
            catch (FileNotFoundException) { return null; }
            catch (DirectoryNotFoundException) { return null; }
            byte[] encrypted;
            using (var file = stream)
            {
                if (file.Length is <= 0 or > 8192) throw new InvalidDataException();
                encrypted = new byte[(int)file.Length]; file.ReadExactly(encrypted);
                if (file.ReadByte() != -1) throw new InvalidDataException();
            }
            return Parse(encrypted, deferred);
        }
        catch (Exception error) when (StorageError(error))
        { throw new LocalFirstUseException("firstUse.completion_read_failed"); }
    }

    // Decrypts and validates one receipt's bytes; no file access.
    private static FirstUseCompletion Parse(byte[] encrypted, bool deferred)
    {
        if (encrypted.Length is <= 0 or > 8192) throw new InvalidDataException();
        var clear = ProtectedData.Unprotect(encrypted, deferred ? DeferredEntropy : Entropy, DataProtectionScope.CurrentUser);
        try
        {
            if (clear.Length is <= 0 or > 8192) throw new InvalidDataException();
            using var parsed = JsonDocument.Parse(clear, new JsonDocumentOptions { MaxDepth = 4 });
            Unique(parsed.RootElement);
            FirstUseCompletion value;
            if (deferred)
            {
                var document = JsonSerializer.Deserialize<DeferredDocument>(clear, Json);
                if (document is not { SchemaVersion: 1, Value.LogDeferred: true }) throw new InvalidDataException();
                value = document.Value;
            }
            else if (parsed.RootElement.ValueKind == JsonValueKind.Object && parsed.RootElement.TryGetProperty("confirmed", out _))
            {
                var document = JsonSerializer.Deserialize<UnconfirmedDocument>(clear, Json);
                if (document is not { SchemaVersion: 1, Confirmed: false, Value: not null }) throw new InvalidDataException();
                var old = document.Value;
                value = new(old.Revision, old.OperationId, old.CompletedAt, old.Mode, old.ProfileId, old.SourceKey, Unconfirmed: true);
            }
            else
            {
                var document = JsonSerializer.Deserialize<Document>(clear, Json);
                if (document is not { SchemaVersion: 1, Value: not null }) throw new InvalidDataException();
                var old = document.Value;
                value = new(old.Revision, old.OperationId, old.CompletedAt, old.Mode, old.ProfileId, old.SourceKey);
            }
            Validate(value);
            return value;
        }
        finally { CryptographicOperations.ZeroMemory(clear); }
    }

    // True only when these bytes, read in one piece, are not a receipt.
    private static bool Corrupt(byte[] encrypted, bool deferred)
    {
        try { Parse(encrypted, deferred); return false; }
        catch (Exception error) when (error is CryptographicException or JsonException or InvalidDataException) { return true; }
    }

    // Test seams, never set by product code. CommitProbe runs inside the final
    // commit window, after its last check and before the file is committed;
    // CommittedProbe runs once the file is in place, before `afterCommit`;
    // ReadProbe runs on every Read, after the file was read.
    internal Action? CommitProbe { get; set; }
    internal Action? CommittedProbe { get; set; }
    internal Action<FirstUseCompletion?>? ReadProbe { get; set; }

    // The product completion owner must revalidate the installed mode, identity
    // and domain choices in current(). This persistence method grants none of them.
    // `commitGate`, when given, wraps the final check and file commit (the owner's
    // lifecycle gate). `afterCommit` is checked again once the file is in place;
    // if it fails, the previous receipt is put back and nothing is committed.
    // With `afterCommit` the receipt is first committed in its unconfirmed form
    // and replaced by the confirmed form only after that check passed; if the
    // put-back or that replacement fails, the file still says unconfirmed.
    // `replaceUnreadable` (checked saves only, `expected` null) is the explicit
    // recovery of a damaged receipt: it proceeds only when one bounded read of
    // the store's own receipt does not decrypt or parse, and only while the file
    // still holds exactly those bytes; it keeps them to put back and replaces
    // them like any other checked save.
    internal FirstUseCompletion Save(FirstUseCompletion? expected, string operationId, string mode,
        string? profileId, string? sourceKey, Func<bool> current, bool logDeferred = false,
        Action<Action>? commitGate = null, Func<bool>? afterCommit = null, bool replaceUnreadable = false)
    {
        var value = new FirstUseCompletion((expected?.Revision ?? 0) + 1, operationId,
            DateTimeOffset.UtcNow, mode, profileId, sourceKey, logDeferred);
        try { Validate(value); }
        catch (InvalidDataException) { throw new LocalFirstUseException("firstUse.invalid_request"); }
        // Deferred receipts have no unconfirmed form.
        if (afterCommit is not null && logDeferred) throw new LocalFirstUseException("firstUse.invalid_request");
        if (replaceUnreadable && (afterCommit is null || expected is not null)) throw new LocalFirstUseException("firstUse.invalid_request");
        string? temporary = null;
        var directory = logDeferred ? _deferredDirectory : _directory;
        var statePath = Path.Combine(directory, "state.bin");
        try
        {
            Safe(StatePath); Safe(StatePath + ".lock"); Safe(statePath);
            if (!current()) throw new LocalFirstUseException("firstUse.context_changed");
            Directory.CreateDirectory(_directory);
            using var lease = new FileStream(StatePath + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
            // Recovery reads the receipt that cannot be read once, in one bounded
            // piece, and decides from those bytes alone: only content that does not
            // decrypt or parse counts as damaged. A file that is locked, denied or
            // too large fails the save instead. The same bytes are what is put back
            // and what the file must still hold whenever it is about to be replaced.
            var deferredPath = Path.Combine(_deferredDirectory, "state.bin");
            byte[]? damaged = null;
            var damagedDeferred = false;
            if (replaceUnreadable)
            {
                damaged = Snapshot(StatePath);
                if (damaged is null) { damagedDeferred = true; damaged = Snapshot(deferredPath); }
                if (damaged is null || !Corrupt(damaged, damagedDeferred)) throw new LocalFirstUseException("firstUse.revision_conflict");
            }
            // The ordinary receipt still holds those bytes; or, for a damaged
            // deferred receipt, there is still no ordinary receipt at all.
            bool StillDamaged() => damagedDeferred
                ? Snapshot(StatePath) is null && Same(Snapshot(deferredPath), damaged!)
                : Same(Snapshot(StatePath), damaged!);
            // What this save expects on disk.
            bool AsExpected() => replaceUnreadable ? StillDamaged() : Read() == expected;
            if (!AsExpected() || expected?.OperationId == operationId)
                throw new LocalFirstUseException("firstUse.revision_conflict");
            byte[] Encrypt(bool confirmed)
            {
                LegacyValue Legacy() => new(value.Revision, value.OperationId, value.CompletedAt, value.Mode, value.ProfileId!, value.SourceKey!);
                var clear = logDeferred ? JsonSerializer.SerializeToUtf8Bytes(new DeferredDocument(1, value), Json)
                    : confirmed ? JsonSerializer.SerializeToUtf8Bytes(new Document(1, Legacy()), Json)
                    : JsonSerializer.SerializeToUtf8Bytes(new UnconfirmedDocument(1, Legacy(), false), Json);
                try { return ProtectedData.Protect(clear, logDeferred ? DeferredEntropy : Entropy, DataProtectionScope.CurrentUser); }
                finally { CryptographicOperations.ZeroMemory(clear); }
            }
            var encrypted = Encrypt(afterCommit is null);
            var confirmedBytes = afterCommit is null ? null : Encrypt(true);
            Directory.CreateDirectory(directory);
            temporary = Path.Combine(directory, Guid.NewGuid().ToString("N") + ".tmp");
            using (var file = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
            { file.Write(encrypted); file.Flush(true); }
            Safe(statePath); Safe(temporary);
            if (!current()) throw new LocalFirstUseException("firstUse.context_changed");
            if (!AsExpected()) throw new LocalFirstUseException("firstUse.revision_conflict");
            // A damaged deferred receipt with no ordinary one: the new file is fresh.
            var fresh = replaceUnreadable ? damagedDeferred : expected is null || expected.LogDeferred != logDeferred;
            void Commit()
            {
                if (!current()) throw new LocalFirstUseException("firstUse.context_changed");
                CommitProbe?.Invoke();
                if (replaceUnreadable && !StillDamaged()) throw new LocalFirstUseException("firstUse.revision_conflict");
                // Kept only to put the receipt back if `afterCommit` fails.
                var previous = afterCommit is null || fresh ? null : damaged ?? File.ReadAllBytes(statePath);
                const string unfinished = "First-use completion commit did not complete.";
                // A fresh move never overwrites a file that appeared meanwhile.
                if (fresh) File.Move(temporary, statePath);
                else if (!(replaceUnreadable
                        ? StoreFileCommit.Replace(temporary, statePath, () => { Safe(statePath); return current() && StillDamaged(); }, unfinished)
                        : StoreFileCommit.ReplaceIfUnchanged(temporary, statePath, () => { Safe(statePath); return current(); }, 8192, unfinished)))
                    throw new LocalFirstUseException(current() ? "firstUse.revision_conflict" : "firstUse.context_changed");
                CommittedProbe?.Invoke();
                if (afterCommit is null) return;
                if (!afterCommit())
                {
                    // The previous bytes, confirmed or not, go back as they were.
                    Restore(directory, statePath, previous);
                    throw new LocalFirstUseException("firstUse.context_changed");
                }
                // Still under the lease, so the file is the receipt committed above.
                Replace(directory, statePath, confirmedBytes!);
            }
            if (commitGate is null) Commit();
            else commitGate(Commit);
            return value;
        }
        catch (Exception error) when (StorageError(error))
        { throw new LocalFirstUseException("firstUse.completion_write_failed"); }
        finally
        {
            if (temporary is not null) try { File.Delete(temporary); } catch (Exception error) when (StorageError(error)) { }
        }
    }

    // A damaged receipt is kept up to this size to put back; a larger one is not replaced.
    private const int UnreadableLimit = 64 * 1024;

    // One bounded read of a receipt file, or null when there is none. A file that
    // is locked, denied, too large or still growing throws, failing the save.
    private static byte[]? Snapshot(string path)
    {
        Safe(path);
        FileStream stream;
        try { stream = new(path, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete); }
        catch (FileNotFoundException) { return null; }
        catch (DirectoryNotFoundException) { return null; }
        using var file = stream;
        if (file.Length > UnreadableLimit) throw new IOException();
        var bytes = new byte[(int)file.Length];
        file.ReadExactly(bytes);
        if (file.ReadByte() != -1) throw new IOException();
        return bytes;
    }

    private static bool Same(byte[]? read, byte[] expected) => read is not null && read.AsSpan().SequenceEqual(expected);

    // Undo a commit whose owner changed while it was written: remove a receipt
    // that did not exist before, or put the previous bytes back atomically.
    private static void Restore(string directory, string statePath, byte[]? previous)
    {
        if (previous is null) File.Delete(statePath);
        else Replace(directory, statePath, previous);
    }

    // Atomically replace the receipt file with these bytes.
    private static void Replace(string directory, string statePath, byte[] bytes)
    {
        var temporary = Path.Combine(directory, Guid.NewGuid().ToString("N") + ".tmp");
        try
        {
            using (var file = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
            { file.Write(bytes); file.Flush(true); }
            Safe(statePath); Safe(temporary);
            File.Move(temporary, statePath, overwrite: true);
        }
        finally { try { File.Delete(temporary); } catch (Exception error) when (StorageError(error)) { } }
    }

    private static void Validate(FirstUseCompletion value)
    {
        if (value.Revision <= 0 || value.Revision >= long.MaxValue || !LocalFirstUseValidation.Id(value.OperationId) ||
            value.CompletedAt.Offset != TimeSpan.Zero || value.CompletedAt < DateTimeOffset.UnixEpoch ||
            value.CompletedAt > DateTimeOffset.UtcNow || value.Mode is not ("local" or "online") ||
            (value.LogDeferred
                ? value.Mode != "local" || value.ProfileId is not null || value.SourceKey is not null
                : !LocalFirstUseValidation.Id(value.ProfileId) || !LocalFirstUseValidation.Token(value.SourceKey)))
            throw new InvalidDataException();
    }
    private static bool StorageError(Exception error) => error is IOException or UnauthorizedAccessException or
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
        foreach (var property in value.EnumerateObject())
        { if (!names.Add(property.Name)) throw new JsonException(); Unique(property.Value); }
    }
}
