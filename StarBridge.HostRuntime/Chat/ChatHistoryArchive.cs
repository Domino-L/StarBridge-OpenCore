using System.Text.Json;

namespace StarBridge.HostRuntime.Chat;

internal static class ChatHistoryArchive
{
    private static readonly LocalChatHistory Store = new();
    internal static async Task<object> Read(string account, string key, string operation, bool neutralNames = false)
    {
        if (operation is not ("read" or "clear")) throw new InvalidDataException();
        try
        {
            var rows = await Store.Run(account, key, clear: operation == "clear");
            // Official author identity is a fresh viewer-scoped projection, never archive authority.
            if (neutralNames) rows = rows.Select(row => row with { Name = "" }).ToArray();
            return new { schemaVersion = 1, rows, error = (string?)null };
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or System.Security.Cryptography.CryptographicException or JsonException)
        { return new { schemaVersion = 1, rows = Array.Empty<LocalChatLine>(), error = "localHistoryUnavailable" }; }
    }
    internal static async Task<bool> Save(string? account, string key, LocalChatLine[] lines)
    {
        if (account is null) return true; // Test adapters do not touch real local data.
        try { await Store.Run(account, key, lines); return true; }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or System.Security.Cryptography.CryptographicException or JsonException)
        { return false; }
    }
}
