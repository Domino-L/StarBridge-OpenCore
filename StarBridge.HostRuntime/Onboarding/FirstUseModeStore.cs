using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace StarBridge.HostRuntime.Onboarding;

// Mode intent is not UI progress, identity, consent, or an onboarding completion.
internal sealed record FirstUseModeChoice(
    [property: JsonRequired] long Revision,
    [property: JsonRequired] string? OperationId,
    [property: JsonRequired] DateTimeOffset? SavedAt,
    [property: JsonRequired] string Phase)
{
    internal static FirstUseModeChoice Unchosen => new(0, null, null, "unchosen");
    internal bool BlocksAutomaticAccountStartup => Phase is not ("unchosen" or "online");
}

internal sealed partial class FirstUseModeStore(string root, TimeProvider? time = null)
{
    private readonly string _directory = Path.Combine(Path.GetFullPath(root), "first-use-mode-v1");
    private readonly TimeProvider _time = time ?? TimeProvider.System;
    private string StatePath => Path.Combine(_directory, "state.bin");
    private const int MaximumBytes = 8192;
    private volatile bool _unwrittenOriginalOwner;
    private volatile string? _ownedTemporary;
    private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("StarBridge.first-use-mode.v1");
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    { PropertyNameCaseInsensitive = false, UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow, MaxDepth = 4 };
    private sealed record Document([property: JsonRequired] int SchemaVersion,
        [property: JsonRequired] FirstUseModeChoice Value);

    internal FirstUseModeChoice Read() => ReadCore(_unwrittenOriginalOwner, _ownedTemporary);

    // Only the original runtime that actually observed no tree may retain its
    // no-choice observation across a failed initial write. A cold runtime must
    // always perform the strict read, even if it finds only a leftover lock.
    internal FirstUseModeChoice ReadForInitialization()
    {
        var value = ReadCore(false, null);
        _unwrittenOriginalOwner = value == FirstUseModeChoice.Unchosen;
        return value;
    }

    private FirstUseModeChoice ReadCore(bool freshWriter, string? ownedTemporary)
    {
        try
        {
            Safe(StatePath);
            FileStream file;
            try { file = new(StatePath, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete); }
            catch (FileNotFoundException) { return Missing(freshWriter, ownedTemporary); }
            catch (DirectoryNotFoundException) { return Missing(freshWriter, ownedTemporary); }
            using var source = file;
            if (source.Length is <= 0 or > MaximumBytes) throw new InvalidDataException();
            var encrypted = new byte[(int)source.Length]; source.ReadExactly(encrypted);
            if (source.ReadByte() != -1) throw new InvalidDataException();
            var clear = ProtectedData.Unprotect(encrypted, Entropy, DataProtectionScope.CurrentUser);
            try
            {
                if (clear.Length is <= 0 or > MaximumBytes) throw new InvalidDataException();
                using var json = JsonDocument.Parse(clear, new JsonDocumentOptions { MaxDepth = 4 });
                Unique(json.RootElement);
                var data = JsonSerializer.Deserialize<Document>(clear, Json);
                if (data is null || data.SchemaVersion != 1 || data.Value is null) throw new InvalidDataException();
                Validate(data.Value);
                _unwrittenOriginalOwner = false;
                return data.Value;
            }
            finally { CryptographicOperations.ZeroMemory(clear); }
        }
        catch (Exception error) when (StorageError(error))
        { throw new LocalFirstUseException("firstUse.mode_read_failed"); }
    }

    // The absent tree is the existing-user/no-choice case. An existing tree
    // without its state is unknown, not permission to restore authentication.
    // Only a writer that observed the tree absent before creating it may read
    // its own initial lock/temp as an empty state. This receipt is not persisted.
    private FirstUseModeChoice Missing(bool freshWriter, string? ownedTemporary)
    {
        Safe(_directory);
        try
        {
            var attributes = File.GetAttributes(_directory);
            if (!attributes.HasFlag(FileAttributes.Directory)) throw new InvalidDataException();
        }
        catch (FileNotFoundException) { return AbsentTree(freshWriter); }
        catch (DirectoryNotFoundException) { return AbsentTree(freshWriter); }
        if (!freshWriter || Directory.EnumerateFileSystemEntries(_directory).Any(path =>
            !string.Equals(path, StatePath + ".lock", StringComparison.OrdinalIgnoreCase) &&
            !string.Equals(path, ownedTemporary, StringComparison.OrdinalIgnoreCase)))
            throw new InvalidDataException();
        return FirstUseModeChoice.Unchosen;
    }

    // The caller must first persist localPending, then obtain actual retirement
    // receipts before local. A saved choice alone never acknowledges that work.
    internal FirstUseModeChoice Save(long revision, string operationId, string phase, Func<bool> current)
        => SaveCore(revision, operationId, phase, current);

    internal FirstUseModeChoice CompleteOnline(FirstUseModeRuntime.OnlineCommit commit) =>
        SaveCore(commit.Pending.Revision, commit.OperationId, "online", commit.IsCurrent,
            finalCommit: commit.WriteAndAdopt);

    internal FirstUseModeChoice BeginOffline(FirstUseModeRuntime.OfflineTransition transition) =>
        SaveCore(transition.Online.Revision, transition.OperationId, "offlinePending", transition.BeginCurrent,
            finalCommit: transition.WriteAndAdopt);

    internal FirstUseModeChoice CompleteOffline(FirstUseModeRuntime.OfflineTransition transition) =>
        SaveCore(transition.Pending!.Revision, Guid.NewGuid().ToString("N"), "offline", transition.CompleteCurrent,
            finalCommit: transition.WriteAndAdopt);

    internal FirstUseModeChoice BeginRootOffline(FirstUseModeRuntime.RootOfflineTransition transition) =>
        SaveCore(transition.Online.Revision, transition.OperationId, "offlinePending", transition.BeginCurrent,
            finalCommit: transition.WriteAndAdopt, ordinaryOffline: true);

    internal FirstUseModeChoice CompleteRootOffline(FirstUseModeRuntime.RootOfflineTransition transition) =>
        SaveCore(transition.Pending!.Revision, Guid.NewGuid().ToString("N"), "offline", transition.CompleteCurrent,
            finalCommit: transition.WriteAndAdopt);

    // Online-return receipts are private to this module. The ordinary writer
    // cannot turn an arbitrary onlinePending choice into a completed local mode.
    private FirstUseModeChoice SaveCore(long revision, string operationId, string phase, Func<bool> current,
        Action<FirstUseModeChoice>? beforeCommit = null, bool returningFromOnline = false,
        Action<FirstUseModeChoice, Action>? finalCommit = null, bool ordinaryOffline = false)
    {
        if (revision < 0 || revision >= long.MaxValue - 1 || !LocalFirstUseValidation.Id(operationId) ||
            phase is not ("localPending" or "local" or "onlinePending" or "online" or "offlinePending" or "offline"))
            throw new LocalFirstUseException("firstUse.invalid_request");
        // Impossible receipt-less requests must not leave a directory/lock that
        // a later cold read correctly considers ambiguous prior-use evidence.
        if ((phase is "online" or "offlinePending") && finalCommit is null ||
            phase == "offline" && finalCommit is null && !returningFromOnline ||
            phase == "local" && revision == 0)
        {
            if (!current()) throw new LocalFirstUseException("firstUse.context_changed");
            var previous = Read();
            if (previous.Revision != revision || previous.OperationId == operationId)
                throw new LocalFirstUseException("firstUse.revision_conflict");
            throw new LocalFirstUseException("firstUse.mode_receipt_required");
        }
        string? temporary = null;
        try
        {
            Safe(StatePath); Safe(StatePath + ".lock");
            if (!current()) throw new LocalFirstUseException("firstUse.context_changed");
            if (!_unwrittenOriginalOwner && !Directory.Exists(_directory))
            {
                _ = ReadCore(false, null); // Reject a lost tree with prior-use evidence.
                _unwrittenOriginalOwner = true;
            }
            var freshWriter = _unwrittenOriginalOwner;
            Directory.CreateDirectory(_directory);
            Safe(StatePath + ".lock");
            using var lease = new FileStream(StatePath + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
            var old = ReadCore(freshWriter, null);
            if (old.Revision != revision || old.OperationId == operationId)
                throw new LocalFirstUseException("firstUse.revision_conflict");
            if (phase == "local" && old.Phase != "localPending" && !(returningFromOnline && old.Phase == "onlinePending") ||
                phase == "online" && (old.Phase != "onlinePending" || finalCommit is null) ||
                phase == "offlinePending" && (!(old.Phase == "online" || ordinaryOffline && old.Phase == "unchosen") || finalCommit is null) ||
                phase == "offline" && !(returningFromOnline && old.Phase == "onlinePending" &&
                    ReadOnlineOrigin() is { Local.Phase: "offline" } origin && origin.IsFor(old)) &&
                    (old.Phase != "offlinePending" || finalCommit is null))
                throw new LocalFirstUseException("firstUse.mode_receipt_required");
            EnsurePresence(); // Fail closed after a crash or later whole-tree loss.
            var next = new FirstUseModeChoice(revision + 1, operationId, _time.GetUtcNow(), phase);
            Validate(next);
            var clear = JsonSerializer.SerializeToUtf8Bytes(new Document(1, next), Json);
            byte[] encrypted;
            try { encrypted = ProtectedData.Protect(clear, Entropy, DataProtectionScope.CurrentUser); }
            finally { CryptographicOperations.ZeroMemory(clear); }
            if (encrypted.Length > MaximumBytes) throw new InvalidDataException();
            temporary = Path.Combine(_directory, Guid.NewGuid().ToString("N") + ".tmp");
            _ownedTemporary = temporary;
            using (var file = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write,
                FileShare.None, 4096, FileOptions.WriteThrough))
            { file.Write(encrypted); file.Flush(true); }
            Safe(StatePath); Safe(temporary);
            beforeCommit?.Invoke(next);
            if (!current()) throw new LocalFirstUseException("firstUse.context_changed");
            if (ReadCore(freshWriter, temporary) != old) throw new LocalFirstUseException("firstUse.revision_conflict");
            if (!current()) throw new LocalFirstUseException("firstUse.context_changed");
            void Write()
            {
                if (old.Revision == 0) File.Move(temporary, StatePath);
                else File.Replace(temporary, StatePath, null);
                _unwrittenOriginalOwner = false;
            }
            if (finalCommit is null) Write();
            else finalCommit(next, Write);
            return next;
        }
        catch (Exception error) when (StorageError(error))
        { throw new LocalFirstUseException("firstUse.mode_write_failed"); }
        finally
        {
            if (_ownedTemporary == temporary) _ownedTemporary = null;
            if (temporary is not null)
                try { File.Delete(temporary); } catch (Exception error) when (StorageError(error)) { }
        }
    }

    private void Validate(FirstUseModeChoice value)
    {
        if (value.Revision <= 0 || value.Revision >= long.MaxValue || !LocalFirstUseValidation.Id(value.OperationId) ||
            value.SavedAt is null || value.SavedAt.Value.Offset != TimeSpan.Zero ||
            value.SavedAt < DateTimeOffset.UnixEpoch || value.SavedAt > _time.GetUtcNow() ||
            value.Phase is not ("localPending" or "local" or "onlinePending" or "online" or "offlinePending" or "offline"))
            throw new InvalidDataException();
    }
    private static bool StorageError(Exception error) => error is IOException or InvalidDataException or UnauthorizedAccessException or
        CryptographicException or JsonException or NotSupportedException or System.Security.SecurityException;
    private static void Safe(string path)
    {
        for (var current = Path.GetFullPath(path); current is not null; current = Path.GetDirectoryName(current))
        {
            FileAttributes attributes;
            try { attributes = File.GetAttributes(current); }
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
