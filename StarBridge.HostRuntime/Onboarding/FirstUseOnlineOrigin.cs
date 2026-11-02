using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace StarBridge.HostRuntime.Onboarding;

// Proves where this exact pending intent came from, not an authenticated account
// or permission grant. A started candidate cannot be cancelled on a cold process
// merely because its old owner has exited: its credential version is then unknown.
internal sealed record FirstUseOnlineOrigin(
    [property: JsonRequired] FirstUseModeChoice Local,
    [property: JsonRequired] FirstUseModeChoice Pending,
    [property: JsonRequired] bool CandidateStarted,
    [property: JsonRequired] FirstUseRetirementOwner Owner)
{
    internal bool IsFor(FirstUseModeChoice choice) => Pending == choice;
}

internal sealed partial class FirstUseModeStore
{
    private string OnlineOriginPath => Path.Combine(_directory, "online-origin.bin");
    private static readonly byte[] OnlineOriginEntropy = Encoding.UTF8.GetBytes("StarBridge.first-use-online-origin.v1");
    private sealed record OnlineOriginDocument([property: JsonRequired] int SchemaVersion,
        [property: JsonRequired] FirstUseOnlineOrigin Value);

    internal FirstUseOnlineOrigin? ReadOnlineOrigin()
    {
        try
        {
            Safe(OnlineOriginPath);
            FileStream file;
            try { file = new(OnlineOriginPath, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete); }
            catch (FileNotFoundException) { return null; }
            catch (DirectoryNotFoundException) { return null; }
            using var source = file;
            if (source.Length is <= 0 or > MaximumBytes) throw new InvalidDataException();
            var encrypted = new byte[(int)source.Length]; source.ReadExactly(encrypted);
            if (source.ReadByte() != -1) throw new InvalidDataException();
            var clear = ProtectedData.Unprotect(encrypted, OnlineOriginEntropy, DataProtectionScope.CurrentUser);
            try
            {
                if (clear.Length is <= 0 or > MaximumBytes) throw new InvalidDataException();
                using var json = JsonDocument.Parse(clear, new JsonDocumentOptions { MaxDepth = 4 });
                Unique(json.RootElement);
                var document = JsonSerializer.Deserialize<OnlineOriginDocument>(clear, Json);
                if (document is null || document.SchemaVersion != 1 || document.Value is null) throw new InvalidDataException();
                ValidateOnlineOrigin(document.Value);
                return document.Value;
            }
            finally { CryptographicOperations.ZeroMemory(clear); }
        }
        catch (Exception error) when (StorageError(error))
        { throw new LocalFirstUseException("firstUse.mode_receipt_read_failed"); }
    }

    internal FirstUseModeChoice BeginOnline(FirstUseModeChoice local, string operationId, Func<bool> current)
        => BeginOnlineCore(local, operationId, current, retainSession: false);

    internal FirstUseModeChoice BeginResume(FirstUseModeChoice offline, string operationId, Func<bool> current)
        => BeginOnlineCore(offline, operationId, current, retainSession: true);

    private FirstUseModeChoice BeginOnlineCore(FirstUseModeChoice local, string operationId, Func<bool> current,
        bool retainSession)
    {
        if (local.Phase != (retainSession ? "offline" : "local")) throw new LocalFirstUseException("firstUse.mode_receipt_required");
        return SaveCore(local.Revision, operationId, "onlinePending", () => current() && Read() == local,
            pending => WriteOnlineOrigin(new(local, pending, false, FirstUseRetirementOwner.Capture()),
                () => current() && Read() == local));
    }

    // Persist before invoking the auth-only factory. Every origin write shares
    // the actual mode writer lease, including creation and return-to-local.
    internal void MarkOnlineCandidateStarted(FirstUseModeChoice pending, Func<bool> current)
    {
        try
        {
            Safe(StatePath + ".lock");
            using var lease = new FileStream(StatePath + ".lock", FileMode.Open, FileAccess.ReadWrite, FileShare.None);
            var origin = ReadOnlineOrigin();
            if (!current() || Read() != pending || origin?.IsFor(pending) != true || origin.CandidateStarted)
                throw new LocalFirstUseException("firstUse.context_changed");
            WriteOnlineOrigin(origin with { CandidateStarted = true, Owner = FirstUseRetirementOwner.Capture() },
                () => current() && Read() == pending && ReadOnlineOrigin() == origin);
        }
        catch (Exception error) when (StorageError(error))
        { throw new LocalFirstUseException("firstUse.mode_receipt_write_failed"); }
    }

    internal FirstUseModeChoice ReturnFromOnline(FirstUseModeChoice pending, string operationId, Func<bool> current) =>
        SaveCore(pending.Revision, operationId, ReadOnlineOrigin()?.Local.Phase == "offline" ? "offline" : "local", () => current() && Read() == pending &&
            ReadOnlineOrigin()?.IsFor(pending) == true, returningFromOnline: true);

    private void WriteOnlineOrigin(FirstUseOnlineOrigin value, Func<bool> current)
    {
        string? temporary = null;
        try
        {
            ValidateOnlineOrigin(value);
            Safe(OnlineOriginPath);
            var old = ReadOnlineOrigin(); // Preserve malformed/unknown earlier data.
            if (!current()) throw new LocalFirstUseException("firstUse.context_changed");
            var clear = JsonSerializer.SerializeToUtf8Bytes(new OnlineOriginDocument(1, value), Json);
            byte[] encrypted;
            try { encrypted = ProtectedData.Protect(clear, OnlineOriginEntropy, DataProtectionScope.CurrentUser); }
            finally { CryptographicOperations.ZeroMemory(clear); }
            if (encrypted.Length > MaximumBytes) throw new InvalidDataException();
            temporary = Path.Combine(_directory, Guid.NewGuid().ToString("N") + ".online.tmp");
            using (var output = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None,
                4096, FileOptions.WriteThrough)) { output.Write(encrypted); output.Flush(true); }
            Safe(OnlineOriginPath); Safe(temporary);
            if (!current() || ReadOnlineOrigin() != old) throw new LocalFirstUseException("firstUse.context_changed");
            if (old is null) File.Move(temporary, OnlineOriginPath);
            else File.Replace(temporary, OnlineOriginPath, null);
        }
        catch (Exception error) when (StorageError(error))
        { throw new LocalFirstUseException("firstUse.mode_receipt_write_failed"); }
        finally
        {
            if (temporary is not null)
                try { File.Delete(temporary); } catch (Exception error) when (StorageError(error)) { }
        }
    }

    private void ValidateOnlineOrigin(FirstUseOnlineOrigin value)
    {
        if (value.Local is null || value.Pending is null || value.Owner is null) throw new InvalidDataException();
        Validate(value.Local); Validate(value.Pending);
        if (value.Local.Phase is not ("local" or "offline") || value.Pending.Phase != "onlinePending" ||
            value.Pending.Revision != value.Local.Revision + 1 || value.Pending.OperationId == value.Local.OperationId ||
            value.Pending.SavedAt < value.Local.SavedAt || value.Owner.ProcessId <= 0 ||
            value.Owner.StartedAt.Offset != TimeSpan.Zero || value.Owner.StartedAt < DateTimeOffset.UnixEpoch ||
            value.Owner.StartedAt > _time.GetUtcNow()) throw new InvalidDataException();
    }
}
