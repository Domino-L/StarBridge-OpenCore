using System.IO;
using System.Text.Json;

namespace StarBridge.HostRuntime.Auth;

// 2026-10-21: an advisory, credential-free note beside the vault that the
// stored sign-in was rejected and retired, so a later start can ask the user to
// sign in again instead of showing a plain sign-out. It never grants, restores
// or selects anything; losing it only loses the explanation.
public sealed partial class WindowsTokenVault
{
    private const int SessionExpirySchema = 1;

    private string SessionExpiryPath =>
        Path.Combine(Path.GetDirectoryName(Path.GetFullPath(_vaultPath))!, "scm-session-expired.v1.json");

    internal void MarkSessionExpired(string authority)
    {
        try
        {
            var path = SessionExpiryPath;
            CheckPath(path);
            File.WriteAllText(path, JsonSerializer.Serialize(new
            {
                schemaVersion = SessionExpirySchema,
                authority,
                rejectedAtUtc = DateTimeOffset.UtcNow
            }));
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
    }

    internal bool IsSessionExpired(string authority)
    {
        try
        {
            var path = SessionExpiryPath;
            CheckPath(path);
            if (!File.Exists(path) || new FileInfo(path).Length > 4096) return false;
            using var document = JsonDocument.Parse(File.ReadAllText(path));
            var root = document.RootElement;
            return root.TryGetProperty("schemaVersion", out var schema) && schema.ValueKind == JsonValueKind.Number &&
                schema.GetInt32() == SessionExpirySchema &&
                root.TryGetProperty("authority", out var value) && value.ValueKind == JsonValueKind.String &&
                string.Equals(value.GetString(), authority, StringComparison.Ordinal);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException or FormatException)
        {
            return false;
        }
    }

    internal void ClearSessionExpired()
    {
        try
        {
            var path = SessionExpiryPath;
            CheckPath(path);
            if (File.Exists(path)) File.Delete(path);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
    }
}
