using System.Security.Cryptography;
using System.Text.Json;
using System.Text.Json.Serialization;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Presence;

internal sealed class VisitorGameplayTimeReceiptStore(string root)
{
    private const string Scope = "gameplay-time-hk-v1";
    private readonly string _directory = Path.Combine(Path.GetFullPath(root), Scope);
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        PropertyNameCaseInsensitive = false,
        UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow,
    };
    private sealed record Receipt([property: JsonRequired] long Seconds, [property: JsonRequired] long? SourceRevision,
        [property: JsonRequired] string AccountScope);

    internal VisitorGameplayTime? Read(BridgeAccountContext owner)
    {
        var scope = AccountScope(owner);
        var directory = Path.Combine(_directory, scope);
        var path = Path.Combine(directory, "last-success.json");
        try
        {
            if (!SafeExisting(_directory, true) || !SafeExisting(directory, true) || !SafeExisting(path, false)) return null;
            using var stream = File.OpenRead(path);
            if (stream.Length > 1024 || JsonSerializer.Deserialize<Receipt>(stream, Json) is not { } receipt ||
                receipt.AccountScope != scope) return null;
            var value = new VisitorGameplayTime(receipt.Seconds, receipt.SourceRevision);
            return value.IsValid ? value : null;
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException) { return null; }
    }

    internal void Save(BridgeAccountContext owner, VisitorGameplayTime value)
    {
        var scope = AccountScope(owner);
        var directory = Path.Combine(_directory, scope);
        if (!SafeExisting(_directory, true)) Directory.CreateDirectory(_directory);
        if (!SafeExisting(directory, true)) Directory.CreateDirectory(directory);
        var path = Path.Combine(directory, "last-success.json");
        _ = SafeExisting(path, false);
        var temporary = Path.Combine(directory, Guid.NewGuid().ToString("N") + ".tmp");
        try
        {
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            {
                JsonSerializer.Serialize(stream, new Receipt(value.Seconds, value.SourceRevision, scope), Json);
                stream.Flush(flushToDisk: true);
            }
            File.Move(temporary, path, overwrite: true);
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }

    private static string AccountScope(BridgeAccountContext owner) =>
        Convert.ToHexString(SHA256.HashData(JsonSerializer.SerializeToUtf8Bytes(
            new[] { Scope, owner.Environment, owner.Authority, owner.Subject })));

    private static bool SafeExisting(string path, bool directory)
    {
        FileAttributes attributes;
        try { attributes = File.GetAttributes(path); }
        catch (FileNotFoundException) { return false; }
        catch (DirectoryNotFoundException) { return false; }
        if (attributes.HasFlag(FileAttributes.ReparsePoint) || attributes.HasFlag(FileAttributes.Directory) != directory)
            throw new IOException("Unexpected gameplay receipt path type.");
        return true;
    }
}
