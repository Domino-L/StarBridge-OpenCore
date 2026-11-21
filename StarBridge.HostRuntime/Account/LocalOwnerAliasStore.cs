using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

/// <summary>
/// "This SCM identity keeps using that legacy owner's local files" (account plan item 8,
/// owner-alias-073/DESIGN.md). One small file in the data root; the business files
/// themselves are never moved, copied or deleted. Entries are only added: an SCM
/// identity that already has an alias never gets a different one.
/// </summary>
internal sealed class LocalOwnerAliasStore
{
    internal const string FileName = "local-owner-aliases.bin";
    // Same protection as the legacy credential (LegacyMigrationCredentialStore) and
    // OfflineAccountStore.ProtectedFiles: Windows DPAPI, current user, own entropy.
    private static readonly byte[] Entropy = System.Text.Encoding.UTF8.GetBytes("StarBridge.LocalOwnerAlias.v1");
    internal const int MaximumEntries = 16;
    private const int MaximumBytes = 64 * 1024;
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        PropertyNameCaseInsensitive = false,
        UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow,
        MaxDepth = 8
    };

    internal enum RecordResult { Written, AlreadyRecorded, Conflict, Full, Failed }

    private sealed record Target(string Environment, string Authority, string Subject)
    {
        internal BridgeAccountContext Context => new(Environment, Authority, Subject);
    }
    private sealed record Entry(string Key, Target Target, DateTimeOffset RecordedAt, string Integrity);
    private sealed record SavedFile(int SchemaVersion, Entry[] Aliases);

    private readonly string _root;
    private readonly string _path;
    private readonly TimeProvider _time;
    private readonly object _gate = new();
    private Dictionary<string, Entry> _entries = new(StringComparer.Ordinal);
    private bool _loaded;

    internal LocalOwnerAliasStore(string root, TimeProvider? time = null)
    {
        _root = Path.GetFullPath(root);
        _path = Path.Combine(_root, FileName);
        _time = time ?? TimeProvider.System;
    }

    internal string FilePath => _path;

    internal bool TryGet(BridgeAccountContext authentication, out BridgeAccountContext target)
    {
        target = null!;
        if (!Valid(authentication)) return false;
        lock (_gate)
        {
            EnsureLoaded();
            if (!_entries.TryGetValue(Key(authentication), out var found)) return false;
            target = found.Target.Context;
            return true;
        }
    }

    internal RecordResult Record(BridgeAccountContext authentication, BridgeAccountContext target)
    {
        if (!Valid(authentication) || !Valid(target) || authentication == target ||
            authentication.Environment != target.Environment) return RecordResult.Failed;
        lock (_gate)
        {
            // The whole read-add-replace runs under a lock file, so a second Host process
            // on the same data root (CX-OWNER-ALIAS-073-R #1) can neither drop this entry
            // nor record a different target for the same SCM identity at the same time.
            FileStream fileLock;
            try { fileLock = AcquireFileLock(); }
            catch (Exception error) when (StorageError(error))
            {
                Support.IdentityGateJournal.Event("owner-alias", $"code=lock-unavailable exception={Support.IdentityGateJournal.Type(error)}");
                return RecordResult.Failed;
            }
            using (fileLock)
                return RecordLocked(authentication, target);
        }
    }

    private RecordResult RecordLocked(BridgeAccountContext authentication, BridgeAccountContext target)
    {
        // Always reread under the lock: another owner on the same data root may have
        // added an entry since this instance loaded; never write over it.
        try { _entries = Read(); _loaded = true; }
        catch (Exception error) when (Corrupt(error))
        {
            // #3: a file that went bad after this instance loaded is set aside like
            // one found bad at load. This call carries the two agreeing sources, so
            // it rebuilds from empty; nothing else is trusted from the bad file.
            Support.IdentityGateJournal.Event("owner-alias", $"code=corrupt exception={Support.IdentityGateJournal.Type(error)}");
            if (!SetAside()) return RecordResult.Failed;
            _entries = new(StringComparer.Ordinal);
            _loaded = true;
        }
        catch (Exception error) when (StorageError(error))
        {
            Support.IdentityGateJournal.Event("owner-alias", $"code=refresh-failed exception={Support.IdentityGateJournal.Type(error)}");
            return RecordResult.Failed;
        }
        var key = Key(authentication);
        if (_entries.TryGetValue(key, out var existing))
            return existing.Target.Context == target ? RecordResult.AlreadyRecorded : RecordResult.Conflict;
        if (_entries.Count >= MaximumEntries) return RecordResult.Full;
        var at = _time.GetUtcNow();
        var stored = new Target(target.Environment, target.Authority, target.Subject);
        var next = new Dictionary<string, Entry>(_entries, StringComparer.Ordinal)
        {
            [key] = new(key, stored, at, Integrity(key, stored, at))
        };
        try { Write(next.Values.ToArray()); }
        catch (Exception error) when (StorageError(error))
        {
            Support.IdentityGateJournal.Event("owner-alias", $"code=write-failed exception={Support.IdentityGateJournal.Type(error)}");
            return RecordResult.Failed;
        }
        _entries = next;
        Support.IdentityGateJournal.Event("owner-alias", "code=written");
        return RecordResult.Written;
    }

    private void EnsureLoaded()
    {
        if (_loaded) return;
        try
        {
            _entries = Read();
            _loaded = true;
        }
        catch (Exception error) when (Corrupt(error))
        {
            // Kept for inspection, never deleted. A fresh alias needs the same two
            // agreeing sources again, so rebuilding cannot point at the wrong owner.
            Support.IdentityGateJournal.Event("owner-alias", $"code=corrupt exception={Support.IdentityGateJournal.Type(error)}");
            _entries = new(StringComparer.Ordinal);
            _loaded = SetAsideIfStillCorrupt();
        }
        catch (Exception error) when (StorageError(error))
        {
            // Busy or unreadable: no alias this time, try again on the next lookup.
            Support.IdentityGateJournal.Event("owner-alias", $"code=read-unavailable exception={Support.IdentityGateJournal.Type(error)}");
            _entries = new(StringComparer.Ordinal);
        }
    }

    private Dictionary<string, Entry> Read()
    {
        var result = new Dictionary<string, Entry>(StringComparer.Ordinal);
        SafeTree();
        if (!Exists(_path)) return result;
        byte[] bytes;
        using (var stream = new FileStream(_path, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete))
        {
            if (stream.Length is <= 0 or > MaximumBytes) throw new InvalidDataException();
            var encrypted = new byte[(int)stream.Length];
            stream.ReadExactly(encrypted);
            if (stream.ReadByte() != -1) throw new InvalidDataException();
            bytes = ProtectedData.Unprotect(encrypted, Entropy, DataProtectionScope.CurrentUser);
        }
        var file = JsonSerializer.Deserialize<SavedFile>(bytes, Json);
        if (file is null || file.SchemaVersion != 1 || file.Aliases is null || file.Aliases.Length > MaximumEntries)
            throw new InvalidDataException();
        foreach (var entry in file.Aliases)
        {
            if (entry?.Target is null || entry.Key is not { Length: 64 } || !Valid(entry.Target.Context) ||
                entry.Integrity != Integrity(entry.Key, entry.Target, entry.RecordedAt) ||
                !result.TryAdd(entry.Key, entry)) throw new InvalidDataException();
        }
        return result;
    }

    private void Write(Entry[] entries)
    {
        SafeTree();
        Exists(_path); // Rejects a junction, link or directory under the alias name.
        var clear = JsonSerializer.SerializeToUtf8Bytes(new SavedFile(1, entries), Json);
        byte[] bytes;
        try { bytes = ProtectedData.Protect(clear, Entropy, DataProtectionScope.CurrentUser); }
        finally { CryptographicOperations.ZeroMemory(clear); }
        var temporary = _path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        try
        {
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None,
                4096, FileOptions.WriteThrough))
            {
                stream.Write(bytes);
                stream.Flush(true);
            }
            File.Move(temporary, _path, overwrite: true);
        }
        finally
        {
            // Only this call's own temporary file; nothing else is ever removed.
            if (File.Exists(temporary)) File.Delete(temporary);
        }
    }

    // A lookup that finds a bad file only sets it aside under the lock and only if it is
    // still bad there: another Host may have just replaced it with a good one.
    private bool SetAsideIfStillCorrupt()
    {
        try
        {
            using var fileLock = AcquireFileLock();
            try { _entries = Read(); return true; }
            catch (Exception error) when (Corrupt(error)) { return SetAside(); }
        }
        catch (Exception error) when (StorageError(error))
        {
            Support.IdentityGateJournal.Event("owner-alias", $"code=set-aside-failed exception={Support.IdentityGateJournal.Type(error)}");
            _entries = new(StringComparer.Ordinal);
            return false;
        }
    }

    private const int LockAttempts = 40;

    private FileStream AcquireFileLock()
    {
        SafeTree();
        if (!Directory.Exists(_root)) throw new IOException("Unexpected data root.");
        var path = _path + ".lock";
        Exists(path); // Rejects a junction, link or directory under the lock name.
        for (var attempt = 1; ; attempt++)
        {
            try { return new FileStream(path, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None); }
            catch (IOException error) when (attempt < LockAttempts && (error.HResult & 0xFFFF) is 32 or 33)
            {
                Thread.Sleep(25); // Another Host holds the lock for one short read-add-replace.
            }
        }
    }

    // #2: the data root and every directory above it, as FirstUseModeStore.Safe does for
    // its own tree; reads, writes, the lock and set-aside never pass through a link.
    private void SafeTree()
    {
        for (var current = _root; current is not null; current = Path.GetDirectoryName(current))
        {
            FileAttributes attributes;
            try { attributes = File.GetAttributes(current); }
            catch (FileNotFoundException) { continue; }
            catch (DirectoryNotFoundException) { continue; }
            if ((attributes & FileAttributes.ReparsePoint) != 0) throw new IOException("Unexpected path type.");
        }
    }

    private static bool Corrupt(Exception error) => error is InvalidDataException or JsonException or CryptographicException;

    private bool SetAside()
    {
        try
        {
            SafeTree();
            if (!Exists(_path)) return true;
            var stamp = _time.GetUtcNow().ToString("yyyyMMdd'T'HHmmss'Z'", System.Globalization.CultureInfo.InvariantCulture);
            File.Move(_path, Path.Combine(_root, $"local-owner-aliases.corrupt-{stamp}-{Guid.NewGuid():N}.bin"));
            return true;
        }
        catch (Exception error) when (StorageError(error))
        {
            Support.IdentityGateJournal.Event("owner-alias", $"code=set-aside-failed exception={Support.IdentityGateJournal.Type(error)}");
            return false;
        }
    }

    private static bool Exists(string path)
    {
        FileAttributes attributes;
        try { attributes = File.GetAttributes(path); }
        catch (FileNotFoundException) { return false; }
        catch (DirectoryNotFoundException) { return false; }
        if ((attributes & FileAttributes.ReparsePoint) != 0 || attributes.HasFlag(FileAttributes.Directory))
            throw new IOException("Unexpected path type.");
        return true;
    }

    private static bool Valid(BridgeAccountContext? context) => context is not null && context.IsComplete &&
        new[] { context.Environment, context.Authority, context.Subject }.All(v => v.Length <= 2048 && !v.Any(char.IsControl));

    internal static string Key(BridgeAccountContext authentication) => Hash(JsonSerializer.SerializeToUtf8Bytes(
        new[] { "owner-alias-v1", authentication.Environment, authentication.Authority, authentication.Subject }));

    private static string Integrity(string key, Target target, DateTimeOffset at) => Hash(JsonSerializer.SerializeToUtf8Bytes(
        new { schemaVersion = 1, key, target.Environment, target.Authority, target.Subject, at = at.ToUnixTimeMilliseconds() }));

    private static string Hash(byte[] bytes) => Convert.ToHexString(SHA256.HashData(bytes));

    private static bool StorageError(Exception error) => error is IOException or UnauthorizedAccessException or
        NotSupportedException or System.Security.SecurityException;
}
