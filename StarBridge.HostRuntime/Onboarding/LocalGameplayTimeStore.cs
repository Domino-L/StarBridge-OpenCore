using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using StarBridge.HostRuntime.Presence;

namespace StarBridge.HostRuntime.Onboarding;

internal sealed record LocalGameplayTimeSaved(
    [property: JsonRequired] long Revision,
    [property: JsonRequired] GameplayRecordingConsent Consent,
    [property: JsonRequired] long Seconds,
    [property: JsonRequired] DateTimeOffset? FirstRecordedAt)
{
    internal static LocalGameplayTimeSaved Empty => new(0, GameplayRecordingConsent.Unknown, 0, null);
    // One-time history import marker. Omitted until used, so files without an
    // import keep the original shape. Seconds already include HistoricalSeconds.
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] public DateTimeOffset? HistoryImportedAt { get; init; }
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] public long? HistoricalSeconds { get; init; }
    [JsonIgnore(Condition = JsonIgnoreCondition.WhenWritingNull)] public string? ImportReceipt { get; init; }
}

// Random local profile ID, never a Handle-derived key or BridgeAccountContext.
// Account and legacy statistics are not opened, searched, imported or promoted.
internal sealed class LocalGameplayTimeStore(string root, TimeProvider? time = null)
{
    private readonly string _directory = Path.Combine(Path.GetFullPath(root), "local-gameplay-time-v1");
    private readonly TimeProvider _time = time ?? TimeProvider.System;
    private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("StarBridge.local-gameplay-time.v1");
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web) {
        PropertyNameCaseInsensitive = false, UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow, MaxDepth = 8
    };
    private sealed record Document([property: JsonRequired] int SchemaVersion, [property: JsonRequired] string ProfileId,
        [property: JsonRequired] LocalGameplayTimeSaved Value);
    private string PathFor(string profileId)
    {
        if (!LocalFirstUseValidation.Id(profileId)) throw new LocalFirstUseException("firstUse.profile_changed");
        return Path.Combine(_directory, profileId + ".bin");
    }
    internal LocalGameplayTimeSaved Read(string profileId)
    {
        try
        {
            var path = PathFor(profileId); Safe(path);
            FileStream file;
            try { file = new(path, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete); }
            catch (FileNotFoundException) { return LocalGameplayTimeSaved.Empty; }
            catch (DirectoryNotFoundException) { return LocalGameplayTimeSaved.Empty; }
            using var source = file;
            if (source.Length is <= 0 or > 8192) throw new InvalidDataException();
            var encrypted = new byte[(int)source.Length]; source.ReadExactly(encrypted);
            if (source.ReadByte() != -1) throw new InvalidDataException();
            var clear = ProtectedData.Unprotect(encrypted, Entropy, DataProtectionScope.CurrentUser);
            try
            {
                if (clear.Length is <= 0 or > 8192) throw new InvalidDataException();
                using var json = JsonDocument.Parse(clear, new JsonDocumentOptions { MaxDepth = 8 });
                Unique(json.RootElement);
                var document = JsonSerializer.Deserialize<Document>(clear, Json);
                if (document is null || document.SchemaVersion != 1 || document.ProfileId != profileId || document.Value is null)
                    throw new InvalidDataException();
                Check(document.Value, allowEmpty: false);
                return document.Value;
            }
            finally { CryptographicOperations.ZeroMemory(clear); }
        }
        catch (Exception error) when (StorageError(error)) { throw new LocalFirstUseException("firstUse.statistics_read_failed"); }
    }
    internal Lease Open(string profileId, Func<bool> current)
    {
        try
        {
            var path = PathFor(profileId); Safe(path); Safe(path + ".lock");
            if (!current()) throw new LocalFirstUseException("firstUse.context_changed");
            Directory.CreateDirectory(_directory); Safe(path + ".lock");
            var file = new FileStream(path + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
            try
            {
                if (!current()) throw new LocalFirstUseException("firstUse.context_changed");
                return new(this, profileId, file);
            }
            catch { file.Dispose(); throw; }
        }
        catch (Exception error) when (StorageError(error)) { throw new LocalFirstUseException("firstUse.statistics_write_failed"); }
    }
    internal sealed class Lease(LocalGameplayTimeStore store, string profileId, FileStream writeLock) : IDisposable
    {
        private bool _disposed;
        internal LocalGameplayTimeSaved Save(LocalGameplayTimeSaved previous, LocalGameplayTimeSaved desired, Func<bool> current)
        {
            if (_disposed) throw new LocalFirstUseException("firstUse.statistics_write_failed");
            return store.Save(profileId, previous, desired, current);
        }
        // Explicit user reset (WPF parity): clears live and imported time and the
        // one-time import marker, keeps consent. The replaced file is kept as
        // `<profile>.reset-backup.bin`, encrypted exactly as before.
        internal LocalGameplayTimeSaved Reset(LocalGameplayTimeSaved previous, Func<bool> current)
        {
            if (_disposed) throw new LocalFirstUseException("firstUse.statistics_write_failed");
            return store.Save(profileId, previous, previous with { Seconds = 0, FirstRecordedAt = null,
                HistoryImportedAt = null, HistoricalSeconds = null, ImportReceipt = null }, current, reset: true);
        }
        public void Dispose() { _disposed = true; writeLock.Dispose(); }
    }
    internal string ResetBackupPathFor(string profileId) => Path.Combine(_directory, profileId + ".reset-backup.bin");
    private LocalGameplayTimeSaved Save(string profileId, LocalGameplayTimeSaved previous, LocalGameplayTimeSaved desired, Func<bool> current,
        bool reset = false)
    {
        Check(previous, allowEmpty: true);
        if (reset ? previous.Revision == 0 || desired != previous with { Seconds = 0, FirstRecordedAt = null,
                HistoryImportedAt = null, HistoricalSeconds = null, ImportReceipt = null } :
            previous.Revision >= long.MaxValue - 1 || desired.Consent == GameplayRecordingConsent.Unknown ||
            desired.Seconds < previous.Seconds || previous.FirstRecordedAt is not null && desired.FirstRecordedAt != previous.FirstRecordedAt ||
            previous.HistoryImportedAt is not null && (desired.HistoryImportedAt != previous.HistoryImportedAt ||
                desired.HistoricalSeconds != previous.HistoricalSeconds || desired.ImportReceipt != previous.ImportReceipt))
            throw new LocalFirstUseException("firstUse.invalid_request");
        if (previous.Revision >= long.MaxValue - 1) throw new LocalFirstUseException("firstUse.invalid_request");
        var next = desired with { Revision = previous.Revision + 1 }; Check(next, allowEmpty: false);
        string? temporary = null;
        try
        {
            var path = PathFor(profileId); Safe(path);
            if (!current()) throw new LocalFirstUseException("firstUse.context_changed");
            if (Read(profileId) != previous) throw new LocalFirstUseException("firstUse.revision_conflict");
            var clear = JsonSerializer.SerializeToUtf8Bytes(new Document(1, profileId, next), Json);
            byte[] encrypted;
            try { encrypted = ProtectedData.Protect(clear, Entropy, DataProtectionScope.CurrentUser); }
            finally { CryptographicOperations.ZeroMemory(clear); }
            temporary = Path.Combine(_directory, Guid.NewGuid().ToString("N") + ".tmp");
            using (var file = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
            { file.Write(encrypted); file.Flush(true); }
            Safe(path); Safe(temporary);
            if (!current()) throw new LocalFirstUseException("firstUse.context_changed");
            if (Read(profileId) != previous) throw new LocalFirstUseException("firstUse.revision_conflict");
            if (!current()) throw new LocalFirstUseException("firstUse.context_changed");
            if (previous.Revision == 0) File.Move(temporary, path);
            else
            {
                var backup = reset ? ResetBackupPathFor(profileId) : null;
                if (backup is not null) Safe(backup);
                File.Replace(temporary, path, backup);
            }
            return next;
        }
        catch (Exception error) when (StorageError(error)) { throw new LocalFirstUseException("firstUse.statistics_write_failed"); }
        finally
        {
            if (temporary is not null) try { File.Delete(temporary); } catch (Exception error) when (StorageError(error)) { }
        }
    }
    private void Check(LocalGameplayTimeSaved value, bool allowEmpty)
    {
        if (value.Revision == 0 && allowEmpty && value == LocalGameplayTimeSaved.Empty) return;
        if (value.Revision is <= 0 or long.MaxValue || value.Seconds < 0 || !Enum.IsDefined(value.Consent) ||
            value.Consent == GameplayRecordingConsent.Unknown || value.FirstRecordedAt is { } at &&
                (at.Offset != TimeSpan.Zero || at < DateTimeOffset.UnixEpoch || at > _time.GetUtcNow()) ||
            value.Seconds > 0 && value.FirstRecordedAt is null ||
            (value.HistoryImportedAt is null) != (value.HistoricalSeconds is null) ||
            (value.HistoryImportedAt is null) != (value.ImportReceipt is null) ||
            value.HistoryImportedAt is { } imported && (imported.Offset != TimeSpan.Zero || imported < DateTimeOffset.UnixEpoch ||
                imported > _time.GetUtcNow() || value.HistoricalSeconds < 0 || value.HistoricalSeconds > value.Seconds ||
                !LocalFirstUseValidation.Id(value.ImportReceipt)))
            throw new LocalFirstUseException("firstUse.statistics_read_failed");
    }
    private static bool StorageError(Exception error) => error is IOException or InvalidDataException or UnauthorizedAccessException or CryptographicException or
        JsonException or NotSupportedException or System.Security.SecurityException;
    private static void Safe(string path)
    {
        for (var current = Path.GetFullPath(path); current is not null; current = Path.GetDirectoryName(current))
        {
            FileAttributes attributes;
            try { attributes = File.GetAttributes(current); }
            catch (FileNotFoundException) { continue; } catch (DirectoryNotFoundException) { continue; }
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
