using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using StarBridge.HostRuntime.Auth;

namespace StarBridge.HostRuntime.Onboarding;

// Distinct from completed retirement: online readers/publication really exited,
// but stored authorization still needs exact-version clearing. No token, account
// ID or caller-controlled target path is persisted or projected to the UI.
internal sealed record FirstUseCredentialCheckpoint(
    [property: JsonRequired] long PendingRevision,
    [property: JsonRequired] string PendingOperationId,
    [property: JsonRequired] DateTimeOffset PendingSavedAt,
    [property: JsonRequired] DateTimeOffset SavedAt,
    [property: JsonRequired] FirstUseRetirementOwner Owner,
    [property: JsonRequired] long OriginalGeneration,
    [property: JsonRequired] ScmCredentialRetirementStamp Credential,
    [property: JsonRequired] bool RequestsDrained,
    [property: JsonRequired] bool PublicationStopped,
    [property: JsonRequired] bool SessionLoopsStopped,
    [property: JsonRequired] bool BusinessBackgroundStopped)
{
    internal bool IsFor(FirstUseModeChoice pending) => pending.Phase == "localPending" &&
        PendingRevision == pending.Revision && PendingOperationId == pending.OperationId && PendingSavedAt == pending.SavedAt;
}

internal sealed partial class FirstUseModeStore
{
    internal WindowsTokenVault? FindCredentialCheckpointVault(FirstUseCredentialCheckpoint checkpoint)
    {
        var root = Path.GetDirectoryName(_directory)!;
        foreach (var name in new[] { "scm-token-vault.json", "scm-token-vault.development.json", "scm-token-vault.local.json" })
        {
            var vault = new WindowsTokenVault(Path.Combine(root, name));
            if (vault.IsRetirementBoundTo(checkpoint.Credential)) return vault;
        }
        return null;
    }

    private string CredentialCheckpointPath => Path.Combine(_directory, "credential-clear.bin");
    private static readonly byte[] CredentialCheckpointEntropy = Encoding.UTF8.GetBytes("StarBridge.first-use-credential-clear.v1");
    private sealed record CredentialCheckpointDocument([property: JsonRequired] int SchemaVersion,
        [property: JsonRequired] FirstUseCredentialCheckpoint Value);

    internal FirstUseCredentialCheckpoint? ReadCredentialCheckpoint()
    {
        try
        {
            Safe(CredentialCheckpointPath);
            FileStream file;
            try { file = new(CredentialCheckpointPath, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete); }
            catch (FileNotFoundException) { return null; }
            catch (DirectoryNotFoundException) { return null; }
            using var source = file;
            if (source.Length is <= 0 or > MaximumBytes) throw new InvalidDataException();
            var encrypted = new byte[(int)source.Length]; source.ReadExactly(encrypted);
            if (source.ReadByte() != -1) throw new InvalidDataException();
            var clear = ProtectedData.Unprotect(encrypted, CredentialCheckpointEntropy, DataProtectionScope.CurrentUser);
            try
            {
                if (clear.Length is <= 0 or > MaximumBytes) throw new InvalidDataException();
                using var json = JsonDocument.Parse(clear, new JsonDocumentOptions { MaxDepth = 4 });
                Unique(json.RootElement);
                var document = JsonSerializer.Deserialize<CredentialCheckpointDocument>(clear, Json);
                if (document is null || document.SchemaVersion != 1 || document.Value is null) throw new InvalidDataException();
                ValidateCredentialCheckpoint(document.Value);
                return document.Value;
            }
            finally { CryptographicOperations.ZeroMemory(clear); }
        }
        catch (Exception error) when (StorageError(error))
        { throw new LocalFirstUseException("firstUse.mode_receipt_read_failed"); }
    }

    internal void SaveCredentialCheckpoint(FirstUseModeChoice pending, LocalAccountStopObservation stopped,
        ScmCredentialRetirementStamp credential, Func<bool> current)
    {
        if (pending.Phase != "localPending" || stopped is not { State: "credentialClearPending", RequestsDrained: true,
                PublicationStopped: true, SessionLoopsStopped: true, BusinessBackgroundStopped: true })
            throw new LocalFirstUseException("firstUse.mode_receipt_required");
        string? temporary = null;
        try
        {
            var next = new FirstUseCredentialCheckpoint(pending.Revision, pending.OperationId!, pending.SavedAt!.Value,
                _time.GetUtcNow(), FirstUseRetirementOwner.Capture(), stopped.Generation, credential, true, true, true, true);
            ValidateCredentialCheckpoint(next);
            Safe(CredentialCheckpointPath); Safe(CredentialCheckpointPath + ".lock");
            if (!current() || Read() != pending) throw new LocalFirstUseException("firstUse.context_changed");
            Directory.CreateDirectory(_directory);
            Safe(CredentialCheckpointPath + ".lock");
            using var lease = new FileStream(CredentialCheckpointPath + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
            var old = ReadCredentialCheckpoint();
            if (old?.IsFor(pending) == true)
            {
                if (old.Owner != next.Owner || old.OriginalGeneration != next.OriginalGeneration || old.Credential != credential ||
                    !current() || Read() != pending) throw new LocalFirstUseException("firstUse.context_changed");
                return;
            }
            var clear = JsonSerializer.SerializeToUtf8Bytes(new CredentialCheckpointDocument(1, next), Json);
            byte[] encrypted;
            try { encrypted = ProtectedData.Protect(clear, CredentialCheckpointEntropy, DataProtectionScope.CurrentUser); }
            finally { CryptographicOperations.ZeroMemory(clear); }
            if (encrypted.Length > MaximumBytes) throw new InvalidDataException();
            temporary = Path.Combine(_directory, Guid.NewGuid().ToString("N") + ".credential-clear.tmp");
            using (var file = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
            { file.Write(encrypted); file.Flush(true); }
            Safe(CredentialCheckpointPath); Safe(temporary);
            if (!current() || Read() != pending || ReadCredentialCheckpoint() != old || !current())
                throw new LocalFirstUseException("firstUse.context_changed");
            if (old is null) File.Move(temporary, CredentialCheckpointPath);
            else File.Replace(temporary, CredentialCheckpointPath, null);
        }
        catch (Exception error) when (StorageError(error))
        { throw new LocalFirstUseException("firstUse.mode_receipt_write_failed"); }
        finally
        {
            if (temporary is not null)
                try { Safe(temporary); File.Delete(temporary); } catch (Exception error) when (StorageError(error)) { }
        }
    }

    private void ValidateCredentialCheckpoint(FirstUseCredentialCheckpoint value)
    {
        // Reuse strict identity/time/fact validation, not completed receipt
        // storage or its signed-out claim. This is a separate pending stage.
        ValidateRetirement(new(value.PendingRevision, value.PendingOperationId, value.PendingSavedAt, value.SavedAt,
            value.Owner, value.OriginalGeneration, value.RequestsDrained, value.PublicationStopped,
            value.SessionLoopsStopped, value.BusinessBackgroundStopped));
        WindowsTokenVault.ValidateRetirementStamp(value.Credential);
        if (value.Credential.EntriesHash is null) throw new InvalidDataException();
    }
}
