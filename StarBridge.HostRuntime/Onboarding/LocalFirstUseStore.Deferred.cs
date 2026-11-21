using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace StarBridge.HostRuntime.Onboarding;

internal sealed partial class LocalFirstUseStore
{
    private readonly string _deferredDirectory = Path.Combine(Path.GetFullPath(root), "local-first-use-deferred-v1");
    private static readonly byte[] DeferredEntropy = Encoding.UTF8.GetBytes("StarBridge.local-first-use-deferred.v1");

    // Same declaration and serialization order as 9156873f's snapshot, including
    // schemaVersion=3. Incompatible UI progress and unselected retained sources
    // belong only to the extension; never invent a selected source or identity.
    private sealed record LegacySnapshot(
        [property: JsonRequired] long Revision,
        [property: JsonRequired] string? OperationId,
        [property: JsonRequired] DateTimeOffset? SavedAt,
        [property: JsonRequired] IReadOnlyList<LocalDeviceProfile> Profiles,
        [property: JsonRequired] string? ActiveProfileId,
        [property: JsonRequired] LocalFirstUseProgress? Progress)
    {
        [JsonRequired] public IReadOnlyList<LocalFirstUseSource> Sources { get; init; } = [];
        [JsonRequired] public string? SelectedSourceKey { get; init; }
        internal LocalFirstUseSnapshot Current() => new(Revision, OperationId, SavedAt, Profiles, ActiveProfileId, Progress)
        { Sources = Sources, SelectedSourceKey = SelectedSourceKey };
        internal static LegacySnapshot From(LocalFirstUseSnapshot value) => new(value.Revision, value.OperationId,
            value.SavedAt, value.Profiles, value.ActiveProfileId,
            value.LogDeferred && value.Progress is { ProfileId: null, Step: "local" or "summary" }
                ? new("log", "local", null, null, null) : value.Progress)
        { Sources = value.LogDeferred ? [] : value.Sources, SelectedSourceKey = value.SelectedSourceKey };
    }

    private sealed record DeferredDocument(
        [property: JsonRequired] int SchemaVersion,
        [property: JsonRequired] string MainHash,
        [property: JsonRequired] bool LogDeferred,
        [property: JsonRequired] bool? DeferredStatisticsAllowed,
        [property: JsonRequired] LocalFirstUseProgress? Progress,
        [property: JsonRequired] IReadOnlyList<LocalFirstUseSource> Sources)
    {
        public bool LogSetupPending { get; init; }
    }

    private LocalFirstUseSnapshot ReadDeferred(LocalFirstUseSnapshot main, byte[] mainBytes)
        => ReadDeferredFile(main, mainBytes, "state.bin") ??
            ReadDeferredFile(main, mainBytes, "pending.bin") ?? main;

    private LocalFirstUseSnapshot? ReadDeferredFile(LocalFirstUseSnapshot main, byte[] mainBytes, string name)
    {
        try
        {
            var path = Path.Combine(_deferredDirectory, name);
            Safe(path);
            byte[] bytes;
            using (var file = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete))
            {
                if (file.Length is <= 0 or > MaximumBytes) throw new InvalidDataException();
                bytes = new byte[(int)file.Length]; file.ReadExactly(bytes);
                if (file.ReadByte() != -1) throw new InvalidDataException();
            }
            var clear = ProtectedData.Unprotect(bytes, DeferredEntropy, DataProtectionScope.CurrentUser);
            try
            {
                if (clear.Length is <= 0 or > MaximumBytes) throw new InvalidDataException();
                using var json = JsonDocument.Parse(clear, new JsonDocumentOptions { MaxDepth = 12 });
                Unique(json.RootElement);
                var extension = JsonSerializer.Deserialize<DeferredDocument>(clear, Json);
                if (extension is not { SchemaVersion: 1 } ||
                    extension.MainHash != Convert.ToHexString(SHA256.HashData(mainBytes))) return null;
                var value = main with { LogDeferred = extension.LogDeferred,
                    DeferredStatisticsAllowed = extension.DeferredStatisticsAllowed,
                    Progress = extension.Progress, Sources = extension.Sources,
                    LogSetupPending = extension.LogSetupPending };
                LocalFirstUseValidation.Check(value);
                return value;
            }
            finally { CryptographicOperations.ZeroMemory(clear); }
        }
        // An obsolete/absent/damaged optional extension never makes a valid old
        // main file unreadable and cannot authorize recording or deferred setup.
        catch (Exception error) when (StorageError(error) || error is LocalFirstUseException) { return null; }
    }

    private void WriteDeferred(LocalFirstUseSnapshot value, byte[] mainBytes, Func<bool> current)
    {
        // Every write replaces the extension, including clearing its choice.
        // No deletion is needed and any older extension is bound to other bytes.
        var path = Path.Combine(_deferredDirectory, "pending.bin");
        Safe(path);
        var clear = JsonSerializer.SerializeToUtf8Bytes(new DeferredDocument(1,
            Convert.ToHexString(SHA256.HashData(mainBytes)), value.LogDeferred,
            value.DeferredStatisticsAllowed, value.Progress, value.Sources)
            { LogSetupPending = value.LogSetupPending }, Json);
        byte[] encrypted;
        try
        {
            if (clear.Length > MaximumBytes) throw new InvalidDataException();
            encrypted = ProtectedData.Protect(clear, DeferredEntropy, DataProtectionScope.CurrentUser);
        }
        finally { CryptographicOperations.ZeroMemory(clear); }
        if (encrypted.Length > MaximumBytes) throw new InvalidDataException();
        Directory.CreateDirectory(_deferredDirectory);
        var temporary = Path.Combine(_deferredDirectory, Guid.NewGuid().ToString("N") + ".tmp");
        try
        {
            using (var file = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None,
                4096, FileOptions.WriteThrough)) { file.Write(encrypted); file.Flush(true); }
            Safe(path); Safe(temporary);
            if (!current()) throw new LocalFirstUseException("firstUse.context_changed");
            if (!File.Exists(path)) File.Move(temporary, path);
            else if (!StoreFileCommit.ReplaceIfUnchanged(temporary, path,
                () => { Safe(path); return current(); }, MaximumBytes, "Deferred progress commit did not complete."))
                throw new LocalFirstUseException("firstUse.write_failed");
        }
        finally { try { File.Delete(temporary); } catch (Exception error) when (StorageError(error)) { } }
    }

    private void CommitDeferred()
    {
        var pending = Path.Combine(_deferredDirectory, "pending.bin");
        var path = Path.Combine(_deferredDirectory, "state.bin");
        Safe(pending); Safe(path);
        // Reads also recognize pending.bin by exact hash, so a crash on either
        // side of this rename preserves a matching extension without replay.
        if (!File.Exists(path)) File.Move(pending, path);
        else if (!StoreFileCommit.ReplaceIfUnchanged(pending, path,
            () => { Safe(pending); Safe(path); return true; }, MaximumBytes,
            "Deferred progress promotion did not complete."))
            throw new LocalFirstUseException("firstUse.write_failed");
    }

    private void StabilizeDeferred(LocalFirstUseSnapshot main)
    {
        // If a previous process exited after committing main but before the
        // final extension rename, preserve that matching extension before the
        // next write stages another pending version. A failed next write must
        // leave the previous choice intact.
        if (main.Revision == 0) return;
        Safe(StatePath);
        using var file = new FileStream(StatePath, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete);
        if (file.Length is <= 0 or > MaximumBytes) throw new InvalidDataException();
        var bytes = new byte[(int)file.Length]; file.ReadExactly(bytes);
        if (file.ReadByte() != -1) throw new InvalidDataException();
        if (ReadDeferredFile(main, bytes, "state.bin") is null && ReadDeferredFile(main, bytes, "pending.bin") is not null)
            CommitDeferred();
    }
}
