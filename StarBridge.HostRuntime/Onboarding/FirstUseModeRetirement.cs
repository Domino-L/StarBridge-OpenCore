using System.Diagnostics;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace StarBridge.HostRuntime.Onboarding;

// Private process identity and retirement facts; never an account ID, token,
// credential path, UI payload, identity proof or onboarding completion receipt.
internal sealed record FirstUseRetirementOwner([property: JsonRequired] int ProcessId,
    [property: JsonRequired] DateTimeOffset StartedAt)
{
    internal static FirstUseRetirementOwner Capture()
    {
        using var process = Process.GetCurrentProcess();
        return new(Environment.ProcessId, process.StartTime.ToUniversalTime());
    }
    internal string ReadExit()
    {
        try
        {
            using var process = Process.GetProcessById(ProcessId);
            if (process.HasExited) return "exited";
            // PID reuse does not revive the old owner. An inaccessible start time
            // is unknown, never evidence of exit.
            var started = new DateTimeOffset(process.StartTime.ToUniversalTime());
            return started == StartedAt ? "running" : "exited";
        }
        catch (ArgumentException) { return "exited"; }
        catch (InvalidOperationException) { return "unknown"; }
        catch (System.ComponentModel.Win32Exception) { return "unknown"; }
        catch (NotSupportedException) { return "unknown"; }
    }
}
internal sealed record FirstUseRetirementReceipt(
    [property: JsonRequired] long PendingRevision,
    [property: JsonRequired] string PendingOperationId,
    [property: JsonRequired] DateTimeOffset PendingSavedAt,
    [property: JsonRequired] DateTimeOffset SavedAt,
    [property: JsonRequired] FirstUseRetirementOwner Owner,
    [property: JsonRequired] long SignedOutGeneration,
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
    private string RetirementPath => Path.Combine(_directory, "retirement.bin");
    private static readonly byte[] RetirementEntropy = Encoding.UTF8.GetBytes("StarBridge.first-use-retirement.v1");
    private sealed record RetirementDocument([property: JsonRequired] int SchemaVersion,
        [property: JsonRequired] FirstUseRetirementReceipt Value);

    internal FirstUseRetirementReceipt? ReadRetirement()
    {
        try
        {
            Safe(RetirementPath);
            FileStream file;
            try { file = new(RetirementPath, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete); }
            catch (FileNotFoundException) { return null; }
            catch (DirectoryNotFoundException) { return null; }
            using var source = file;
            if (source.Length is <= 0 or > MaximumBytes) throw new InvalidDataException();
            var encrypted = new byte[(int)source.Length]; source.ReadExactly(encrypted);
            if (source.ReadByte() != -1) throw new InvalidDataException();
            var clear = ProtectedData.Unprotect(encrypted, RetirementEntropy, DataProtectionScope.CurrentUser);
            try
            {
                if (clear.Length is <= 0 or > MaximumBytes) throw new InvalidDataException();
                using var json = JsonDocument.Parse(clear, new JsonDocumentOptions { MaxDepth = 4 });
                Unique(json.RootElement);
                var document = JsonSerializer.Deserialize<RetirementDocument>(clear, Json);
                if (document is null || document.SchemaVersion != 1 || document.Value is null) throw new InvalidDataException();
                ValidateRetirement(document.Value);
                return document.Value;
            }
            finally { CryptographicOperations.ZeroMemory(clear); }
        }
        catch (Exception error) when (StorageError(error))
        { throw new LocalFirstUseException("firstUse.mode_receipt_read_failed"); }
    }

    // Only called after the real account lifecycle returns all four stop facts.
    // Final owner guards must still prove those facts at the actual commit.
    internal void SaveRetirement(FirstUseModeChoice pending, LocalAccountStopObservation stopped, Func<bool> current)
    {
        if (pending.Phase != "localPending" || stopped is not { State: "sessionStopped", RequestsDrained: true,
                PublicationStopped: true, SessionLoopsStopped: true, BusinessBackgroundStopped: true })
            throw new LocalFirstUseException("firstUse.mode_receipt_required");
        string? temporary = null;
        try
        {
            var receipt = new FirstUseRetirementReceipt(pending.Revision, pending.OperationId!, pending.SavedAt!.Value,
                _time.GetUtcNow(), FirstUseRetirementOwner.Capture(), stopped.Generation, true, true, true, true);
            ValidateRetirement(receipt);
            Safe(RetirementPath); Safe(RetirementPath + ".lock");
            if (!current() || Read() != pending) throw new LocalFirstUseException("firstUse.context_changed");
            Directory.CreateDirectory(_directory);
            using var lease = new FileStream(RetirementPath + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
            // Do not overwrite an unreadable or malformed earlier receipt.
            var old = ReadRetirement();
            var clear = JsonSerializer.SerializeToUtf8Bytes(new RetirementDocument(1, receipt), Json);
            byte[] encrypted;
            try { encrypted = ProtectedData.Protect(clear, RetirementEntropy, DataProtectionScope.CurrentUser); }
            finally { CryptographicOperations.ZeroMemory(clear); }
            if (encrypted.Length > MaximumBytes) throw new InvalidDataException();
            temporary = Path.Combine(_directory, Guid.NewGuid().ToString("N") + ".retirement.tmp");
            using (var file = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write,
                FileShare.None, 4096, FileOptions.WriteThrough))
            { file.Write(encrypted); file.Flush(true); }
            Safe(RetirementPath); Safe(temporary);
            if (!current() || Read() != pending || ReadRetirement() != old)
                throw new LocalFirstUseException("firstUse.context_changed");
            if (!current()) throw new LocalFirstUseException("firstUse.context_changed");
            if (old is null) File.Move(temporary, RetirementPath);
            else File.Replace(temporary, RetirementPath, null);
        }
        catch (Exception error) when (StorageError(error))
        { throw new LocalFirstUseException("firstUse.mode_receipt_write_failed"); }
        finally
        {
            if (temporary is not null)
                try { File.Delete(temporary); } catch (Exception error) when (StorageError(error)) { }
        }
    }
    private void ValidateRetirement(FirstUseRetirementReceipt value)
    {
        if (value.PendingRevision <= 0 || value.PendingRevision >= long.MaxValue ||
            !LocalFirstUseValidation.Id(value.PendingOperationId) || value.SignedOutGeneration < 0 ||
            value.Owner is null || value.Owner.ProcessId <= 0 || value.Owner.StartedAt.Offset != TimeSpan.Zero ||
            value.Owner.StartedAt < DateTimeOffset.UnixEpoch || value.Owner.StartedAt > value.SavedAt ||
            value.PendingSavedAt.Offset != TimeSpan.Zero || value.PendingSavedAt < DateTimeOffset.UnixEpoch ||
            value.SavedAt.Offset != TimeSpan.Zero || value.SavedAt < value.PendingSavedAt || value.SavedAt > _time.GetUtcNow() ||
            !value.RequestsDrained || !value.PublicationStopped || !value.SessionLoopsStopped || !value.BusinessBackgroundStopped)
            throw new InvalidDataException();
    }
}
