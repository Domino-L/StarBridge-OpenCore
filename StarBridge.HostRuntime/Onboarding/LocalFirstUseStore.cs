using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace StarBridge.HostRuntime.Onboarding;

// Separate device-local tree; never opens/moves account-owned or legacy files.
// DPAPI is user protection, not a security boundary against that same OS user.
internal sealed class LocalFirstUseStore(string root, TimeProvider? time = null)
{
    private readonly string _directory = Path.Combine(Path.GetFullPath(root), "local-first-use-v1");
    private readonly TimeProvider _time = time ?? TimeProvider.System;
    private string StatePath => Path.Combine(_directory, "state.bin");
    private const int MaximumBytes = 128 * 1024;
    private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("StarBridge.local-first-use.v1");
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    { PropertyNameCaseInsensitive = false, UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow, MaxDepth = 12 };
    private sealed record Document([property: JsonRequired] int SchemaVersion,
        [property: JsonRequired] LocalFirstUseSnapshot Value);

    internal LocalFirstUseSnapshot Read()
    {
        try
        {
            Safe(StatePath);
            FileStream file;
            try { file = new(StatePath, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete); }
            catch (FileNotFoundException) { return LocalFirstUseSnapshot.Empty; }
            catch (DirectoryNotFoundException) { return LocalFirstUseSnapshot.Empty; }
            using var source = file;
            if (source.Length is <= 0 or > MaximumBytes) throw new InvalidDataException();
            var encrypted = new byte[(int)source.Length]; source.ReadExactly(encrypted);
            if (source.ReadByte() != -1) throw new InvalidDataException();
            var clear = ProtectedData.Unprotect(encrypted, Entropy, DataProtectionScope.CurrentUser);
            try
            {
                if (clear.Length is <= 0 or > MaximumBytes) throw new InvalidDataException();
                using var json = JsonDocument.Parse(clear, new JsonDocumentOptions { MaxDepth = 12 });
                Unique(json.RootElement);
                var data = JsonSerializer.Deserialize<Document>(clear, Json);
                if (data is null || data.SchemaVersion != 3 || data.Value is null) throw new InvalidDataException();
                LocalFirstUseValidation.Check(data.Value);
                return data.Value;
            }
            finally { CryptographicOperations.ZeroMemory(clear); }
        }
        catch (Exception error) when (StorageError(error) || error is LocalFirstUseException)
        { throw new LocalFirstUseException("firstUse.read_failed"); }
    }

    internal LocalFirstUseSnapshot ConfirmIdentity(long revision, string operationId,
        LocalIdentityProof proof, Func<bool> evidenceCurrent)
    {
        if (!proof.Valid(_time.GetUtcNow())) throw new LocalFirstUseException("firstUse.evidence_required");
        return Write(revision, operationId, evidenceCurrent, old =>
        {
            var source = old.Sources.SingleOrDefault(s => s.SourceKey == proof.SourceKey);
            if (old.Sources.Count != 0 && (source is null || old.SelectedSourceKey != source.SourceKey))
                throw new LocalFirstUseException("firstUse.source_changed");
            if (source is { NeedsFreshGameEvidence: true } &&
                (proof.Origin != "freshSession" || source.Baseline is null ||
                    proof.BaselineKey != LocalGameEvidenceValidation.Key(source.Baseline)))
                throw new LocalFirstUseException("firstUse.evidence_required");
            var existing = old.Profiles.SingleOrDefault(p =>
                p.Handle.Equals(proof.Handle, StringComparison.OrdinalIgnoreCase));
            var profile = existing ?? new LocalDeviceProfile(Guid.NewGuid().ToString("N"), proof.Handle, _time.GetUtcNow());
            return old with {
                Profiles = existing is null ? [.. old.Profiles, profile] : old.Profiles,
                ActiveProfileId = profile.Id,
                // Source confirmation and clearing the sticky gate commit together.
                Sources = source is null ? old.Sources : old.Sources.Select(s => s.SourceKey == source.SourceKey
                    ? s with { NeedsFreshGameEvidence = false, Baseline = null, ConfirmedProfileId = profile.Id,
                        ConfirmedObservedAt = proof.ObservedAt, ConfirmedOrigin = proof.Origin } : s).ToArray(),
                // Switching identity discards only stale *UI* progress, not any profile data.
                Progress = old.ActiveProfileId == profile.Id ? old.Progress : null
            };
        });
    }

    internal LocalFirstUseSnapshot SelectSource(long revision, string operationId,
        string logPath, string version, Func<bool> current)
    {
        var path = LocalGameEvidenceValidation.SelectionPath(logPath, version);
        return Write(revision, operationId, current, old =>
        {
            var source = old.Sources.SingleOrDefault(s => s.LogPath.Equals(path, StringComparison.OrdinalIgnoreCase));
            source ??= new(Guid.NewGuid().ToString("N"), path, version, false, null, null, null, null);
            return old with {
                Sources = old.Sources.Any(s => s.SourceKey == source.SourceKey) ? old.Sources : [.. old.Sources, source],
                SelectedSourceKey = source.SourceKey,
                // Selecting a version is not confirmation of its current Handle.
                ActiveProfileId = old.SelectedSourceKey == source.SourceKey ? old.ActiveProfileId : null,
                Progress = old.SelectedSourceKey == source.SourceKey ? old.Progress : null
            };
        });
    }

    internal LocalFirstUseSnapshot RequireFreshGameEvidence(long revision, string operationId,
        string sourceKey, LocalGameEvidenceBaseline? baseline, Func<bool> current, string? replacingBaselineKey = null) =>
        Write(revision, operationId, current, old =>
        {
            var source = old.Sources.SingleOrDefault(s => s.SourceKey == sourceKey);
            if (source is null || old.SelectedSourceKey != sourceKey) throw new LocalFirstUseException("firstUse.source_changed");
            if (baseline is not null && !LocalGameEvidenceValidation.Baseline(baseline, _time.GetUtcNow()))
                throw new LocalFirstUseException("firstUse.evidence_required");
            // Ordinary refresh cannot move a live baseline past evidence already received.
            if (source.Baseline is { } previous &&
                (replacingBaselineKey != LocalGameEvidenceValidation.Key(previous) ||
                    baseline is null || baseline.CapturedAt < previous.CapturedAt))
                throw new LocalFirstUseException("firstUse.evidence_required");
            return old with {
                Sources = old.Sources.Select(s => s.SourceKey == sourceKey ? s with {
                    NeedsFreshGameEvidence = true, Baseline = baseline, ConfirmedProfileId = null,
                    ConfirmedObservedAt = null, ConfirmedOrigin = null
                } : s).ToArray(),
                // Local profiles stay intact; this source no longer authorizes active recording.
                ActiveProfileId = null,
                Progress = null
            };
        });

    internal LocalFirstUseSnapshot InvalidateSourceIdentity(long revision, string operationId,
        string sourceKey, Func<bool> current) => Write(revision, operationId, current, old =>
        {
            if (old.SelectedSourceKey != sourceKey) throw new LocalFirstUseException("firstUse.source_changed");
            return old with {
                Sources = old.Sources.Select(s => s.SourceKey == sourceKey ? s with {
                    ConfirmedProfileId = null, ConfirmedObservedAt = null, ConfirmedOrigin = null
                } : s).ToArray(),
                ActiveProfileId = null, Progress = null
            };
        });

    internal LocalFirstUseSnapshot SetListening(long revision, string operationId, string sourceKey,
        bool enabled, Func<bool> current) => Write(revision, operationId, current, old =>
        {
            var source = old.Sources.SingleOrDefault(s => s.SourceKey == sourceKey);
            if (source is null || old.SelectedSourceKey != sourceKey) throw new LocalFirstUseException("firstUse.source_changed");
            if (enabled && (source.NeedsFreshGameEvidence || source.ConfirmedProfileId is null ||
                old.ActiveProfileId != source.ConfirmedProfileId)) throw new LocalFirstUseException("firstUse.evidence_required");
            return old with { Sources = old.Sources.Select(s => s.SourceKey == sourceKey
                ? s with { ListeningEnabled = enabled } : s).ToArray() };
        });

    internal LocalFirstUseSnapshot SaveProgress(long revision, string operationId,
        LocalFirstUseProgress progress, Func<bool> current) =>
        Write(revision, operationId, current, old => old with { Progress = progress });

    internal LocalFirstUseSnapshot ForgetProfile(long revision, string operationId,
        string profileId, Func<bool> current)
    {
        if (!LocalFirstUseValidation.Id(profileId)) throw new LocalFirstUseException("firstUse.invalid_request");
        return Write(revision, operationId, current, old =>
        {
            if (!old.Profiles.Any(p => p.Id == profileId)) throw new LocalFirstUseException("firstUse.profile_changed");
            return old with {
                Profiles = old.Profiles.Where(p => p.Id != profileId).ToArray(),
                Sources = old.Sources.Select(s => s.ConfirmedProfileId == profileId
                    ? s with { ConfirmedProfileId = null, ConfirmedObservedAt = null, ConfirmedOrigin = null } : s).ToArray(),
                ActiveProfileId = old.ActiveProfileId == profileId ? null : old.ActiveProfileId,
                Progress = old.Progress?.ProfileId == profileId ? null : old.Progress
            };
        });
    }

    private LocalFirstUseSnapshot Write(long revision, string operationId, Func<bool> current,
        Func<LocalFirstUseSnapshot, LocalFirstUseSnapshot> change)
    {
        if (revision < 0 || revision >= long.MaxValue - 1 || !LocalFirstUseValidation.Id(operationId))
            throw new LocalFirstUseException("firstUse.invalid_request");
        string? temporary = null;
        try
        {
            Safe(StatePath); Safe(StatePath + ".lock");
            if (!current()) throw new LocalFirstUseException("firstUse.context_changed");
            Directory.CreateDirectory(_directory);
            Safe(StatePath + ".lock");
            using var lease = new FileStream(StatePath + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
            var old = Read();
            // No operation-only replay acceptance: stale/reused requests require re-read.
            if (old.Revision != revision || old.OperationId == operationId)
                throw new LocalFirstUseException("firstUse.revision_conflict");
            var next = change(old) with {
                Revision = revision + 1, OperationId = operationId, SavedAt = _time.GetUtcNow()
            };
            LocalFirstUseValidation.Check(next);
            var clear = JsonSerializer.SerializeToUtf8Bytes(new Document(3, next), Json);
            byte[] encrypted;
            try
            {
                if (clear.Length > MaximumBytes) throw new LocalFirstUseException("firstUse.invalid_request");
                encrypted = ProtectedData.Protect(clear, Entropy, DataProtectionScope.CurrentUser);
            }
            finally { CryptographicOperations.ZeroMemory(clear); }
            if (encrypted.Length > MaximumBytes) throw new LocalFirstUseException("firstUse.invalid_request");
            temporary = Path.Combine(_directory, Guid.NewGuid().ToString("N") + ".tmp");
            using (var file = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write,
                FileShare.None, 4096, FileOptions.WriteThrough))
            { file.Write(encrypted); file.Flush(true); }
            Safe(StatePath); Safe(temporary);
            if (!current()) throw new LocalFirstUseException("firstUse.context_changed");
            // CAS and the commit guard are checked under the single writer lease.
            if (Read().Revision != revision) throw new LocalFirstUseException("firstUse.revision_conflict");
            if (!current()) throw new LocalFirstUseException("firstUse.context_changed");
            if (old.Revision == 0) File.Move(temporary, StatePath);
            else if (!StoreFileCommit.ReplaceIfUnchanged(temporary, StatePath, () => { Safe(StatePath); return current(); }, MaximumBytes, "First-use progress commit did not complete."))
                throw new LocalFirstUseException(current() ? "firstUse.revision_conflict" : "firstUse.context_changed");
            return next;
        }
        catch (Exception error) when (StorageError(error))
        { throw new LocalFirstUseException("firstUse.write_failed"); }
        finally
        {
            if (temporary is not null)
                try { File.Delete(temporary); } catch (Exception error) when (StorageError(error)) { }
        }
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
        if (value.ValueKind == JsonValueKind.Object)
        {
            var names = new HashSet<string>(StringComparer.Ordinal);
            foreach (var field in value.EnumerateObject())
            { if (!names.Add(field.Name)) throw new JsonException(); Unique(field.Value); }
        }
        else if (value.ValueKind == JsonValueKind.Array)
            foreach (var item in value.EnumerateArray()) Unique(item);
    }
}
