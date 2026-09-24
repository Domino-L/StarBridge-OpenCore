namespace StarBridge.Desktop;

using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

internal sealed record FleetStateCacheEntry(
    int SchemaVersion,
    string StateJson,
    DateTimeOffset? CachedAtUtc);

internal static class FleetStateCacheStore
{
    private const int CurrentSchemaVersion = 1;
    private const string DirectoryName = "fleet-state";
    private static readonly JsonSerializerOptions Options = new(JsonSerializerDefaults.Web)
    {
        WriteIndented = true
    };

    internal static FleetStateCacheEntry? LoadAccount(string accountNamespace) =>
        Load(AccountPath(accountNamespace));

    internal static FleetStateCacheEntry? LoadLegacy(string? legacyAccountId) =>
        Load(LegacyPath(legacyAccountId));

    internal static void SaveAccount(
        string accountNamespace,
        string stateJson,
        DateTimeOffset? cachedAtUtc)
    {
        var path = AccountPath(accountNamespace) ??
                   throw new ArgumentException("A full account cache namespace is required.", nameof(accountNamespace));
        Save(path, new FleetStateCacheEntry(CurrentSchemaVersion, stateJson, cachedAtUtc));
    }

    internal static bool StageLegacy(
        string? legacyAccountId,
        string? stateJson,
        DateTimeOffset? cachedAtUtc)
    {
        var path = LegacyPath(legacyAccountId);
        if (path is null || string.IsNullOrWhiteSpace(stateJson))
        {
            return false;
        }

        var existing = Load(path);
        if (existing is null ||
            existing.CachedAtUtc is null ||
            cachedAtUtc is not null && cachedAtUtc > existing.CachedAtUtc)
        {
            Save(path, new FleetStateCacheEntry(CurrentSchemaVersion, stateJson, cachedAtUtc));
        }

        return true;
    }

    internal static void PromoteLegacy(string legacyAccountId, string accountNamespace)
    {
        var source = LegacyPath(legacyAccountId);
        var destination = AccountPath(accountNamespace);
        if (source is null || destination is null || !File.Exists(source))
        {
            return;
        }

        Directory.CreateDirectory(Path.GetDirectoryName(destination)!);
        if (File.Exists(destination))
        {
            File.Delete(source);
            return;
        }

        File.Move(source, destination);
    }

    private static FleetStateCacheEntry? Load(string? path)
    {
        if (path is null || !File.Exists(path))
        {
            return null;
        }

        try
        {
            var entry = JsonSerializer.Deserialize<FleetStateCacheEntry>(File.ReadAllText(path), Options);
            return entry is { SchemaVersion: CurrentSchemaVersion } &&
                   !string.IsNullOrWhiteSpace(entry.StateJson)
                ? entry
                : null;
        }
        catch
        {
            return null;
        }
    }

    private static void Save(string path, FleetStateCacheEntry entry)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var temporary = path + ".tmp";
        File.WriteAllText(temporary, JsonSerializer.Serialize(entry, Options));
        File.Move(temporary, path, overwrite: true);
    }

    private static string? AccountPath(string? accountNamespace)
    {
        const string prefix = "account:";
        if (string.IsNullOrWhiteSpace(accountNamespace) ||
            !accountNamespace.StartsWith(prefix, StringComparison.Ordinal) ||
            !IsSha256(accountNamespace[prefix.Length..]))
        {
            return null;
        }

        return Path.Combine(
            DesktopStorageRoot.CurrentRoot,
            DirectoryName,
            $"account-{accountNamespace[prefix.Length..]}.json");
    }

    private static string? LegacyPath(string? legacyAccountId)
    {
        if (string.IsNullOrWhiteSpace(legacyAccountId))
        {
            return null;
        }

        var normalized = legacyAccountId.Trim().ToUpperInvariant();
        var hash = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(normalized)))
            .ToLowerInvariant();
        return Path.Combine(
            DesktopStorageRoot.CurrentRoot,
            DirectoryName,
            $"legacy-{hash}.json");
    }

    private static bool IsSha256(string value) =>
        value.Length == 64 && value.All(character =>
            character is >= '0' and <= '9' or >= 'a' and <= 'f');
}
