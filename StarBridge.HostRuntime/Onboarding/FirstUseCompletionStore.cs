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
    [property: JsonRequired] string ProfileId,
    [property: JsonRequired] string SourceKey);

internal sealed class FirstUseCompletionStore(string root)
{
    private readonly string _directory = Path.Combine(Path.GetFullPath(root), "first-use-completion-v1");
    private string StatePath => Path.Combine(_directory, "state.bin");
    private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("StarBridge.first-use-completion.v1");
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    { UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow, PropertyNameCaseInsensitive = false, MaxDepth = 4 };
    private sealed record Document([property: JsonRequired] int SchemaVersion,
        [property: JsonRequired] FirstUseCompletion Value);

    internal FirstUseCompletion? Read()
    {
        try
        {
            Safe(StatePath);
            FileStream stream;
            try { stream = new(StatePath, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete); }
            catch (FileNotFoundException) { return null; }
            catch (DirectoryNotFoundException) { return null; }
            using var file = stream;
            if (file.Length is <= 0 or > 8192) throw new InvalidDataException();
            var encrypted = new byte[(int)file.Length]; file.ReadExactly(encrypted);
            if (file.ReadByte() != -1) throw new InvalidDataException();
            var clear = ProtectedData.Unprotect(encrypted, Entropy, DataProtectionScope.CurrentUser);
            try
            {
                if (clear.Length is <= 0 or > 8192) throw new InvalidDataException();
                using var parsed = JsonDocument.Parse(clear, new JsonDocumentOptions { MaxDepth = 4 });
                Unique(parsed.RootElement);
                var document = JsonSerializer.Deserialize<Document>(clear, Json);
                if (document is not { SchemaVersion: 1, Value: not null }) throw new InvalidDataException();
                Validate(document.Value);
                return document.Value;
            }
            finally { CryptographicOperations.ZeroMemory(clear); }
        }
        catch (Exception error) when (StorageError(error))
        { throw new LocalFirstUseException("firstUse.completion_read_failed"); }
    }

    // The product completion owner must revalidate the installed mode, identity
    // and domain choices in current(). This persistence method grants none of them.
    internal FirstUseCompletion Save(FirstUseCompletion? expected, string operationId, string mode,
        string profileId, string sourceKey, Func<bool> current)
    {
        var value = new FirstUseCompletion((expected?.Revision ?? 0) + 1, operationId,
            DateTimeOffset.UtcNow, mode, profileId, sourceKey);
        try { Validate(value); }
        catch (InvalidDataException) { throw new LocalFirstUseException("firstUse.invalid_request"); }
        string? temporary = null;
        try
        {
            Safe(StatePath); Safe(StatePath + ".lock");
            if (!current()) throw new LocalFirstUseException("firstUse.context_changed");
            Directory.CreateDirectory(_directory);
            using var lease = new FileStream(StatePath + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
            if (Read() != expected || expected?.OperationId == operationId)
                throw new LocalFirstUseException("firstUse.revision_conflict");
            var clear = JsonSerializer.SerializeToUtf8Bytes(new Document(1, value), Json);
            byte[] encrypted;
            try { encrypted = ProtectedData.Protect(clear, Entropy, DataProtectionScope.CurrentUser); }
            finally { CryptographicOperations.ZeroMemory(clear); }
            temporary = Path.Combine(_directory, Guid.NewGuid().ToString("N") + ".tmp");
            using (var file = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
            { file.Write(encrypted); file.Flush(true); }
            Safe(StatePath); Safe(temporary);
            if (!current()) throw new LocalFirstUseException("firstUse.context_changed");
            if (Read() != expected) throw new LocalFirstUseException("firstUse.revision_conflict");
            if (!current()) throw new LocalFirstUseException("firstUse.context_changed");
            if (expected is null) File.Move(temporary, StatePath);
            else if (!StoreFileCommit.ReplaceIfUnchanged(temporary, StatePath, () => { Safe(StatePath); return current(); }, 8192, "First-use completion commit did not complete."))
                throw new LocalFirstUseException(current() ? "firstUse.revision_conflict" : "firstUse.context_changed");
            return value;
        }
        catch (Exception error) when (StorageError(error))
        { throw new LocalFirstUseException("firstUse.completion_write_failed"); }
        finally
        {
            if (temporary is not null) try { File.Delete(temporary); } catch (Exception error) when (StorageError(error)) { }
        }
    }

    private static void Validate(FirstUseCompletion value)
    {
        if (value.Revision <= 0 || value.Revision >= long.MaxValue || !LocalFirstUseValidation.Id(value.OperationId) ||
            value.CompletedAt.Offset != TimeSpan.Zero || value.CompletedAt < DateTimeOffset.UnixEpoch ||
            value.CompletedAt > DateTimeOffset.UtcNow || value.Mode is not ("local" or "online") ||
            !LocalFirstUseValidation.Id(value.ProfileId) || !LocalFirstUseValidation.Token(value.SourceKey))
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
