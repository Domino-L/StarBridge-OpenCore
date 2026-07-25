namespace StarBridge.Desktop;

using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

public sealed record IdentityBindingLocalModeSettings(string[] AccountIds)
{
    public static IdentityBindingLocalModeSettings Empty { get; } = new([]);

    public bool IsEnabled(string? accountId)
    {
        var normalized = NormalizeAccountId(accountId);
        return normalized is not null &&
               AccountIds.Any(candidate =>
                   candidate.Equals(normalized, StringComparison.OrdinalIgnoreCase));
    }

    public IdentityBindingLocalModeSettings WithAccount(string? accountId, bool enabled)
    {
        var normalized = NormalizeAccountId(accountId);
        if (normalized is null)
        {
            return Normalize();
        }

        var accounts = new HashSet<string>(
            Normalize().AccountIds,
            StringComparer.OrdinalIgnoreCase);
        if (enabled)
        {
            accounts.Add(normalized);
        }
        else
        {
            accounts.Remove(normalized);
        }

        return new IdentityBindingLocalModeSettings(
            accounts.OrderBy(value => value, StringComparer.OrdinalIgnoreCase).ToArray());
    }

    public string Serialize() => JsonSerializer.Serialize(Normalize());

    public static IdentityBindingLocalModeSettings Parse(string? payload)
    {
        if (string.IsNullOrWhiteSpace(payload))
        {
            return Empty;
        }

        try
        {
            return (JsonSerializer.Deserialize<IdentityBindingLocalModeSettings>(payload) ?? Empty)
                .Normalize();
        }
        catch (JsonException)
        {
            return Empty;
        }
    }

    private IdentityBindingLocalModeSettings Normalize() =>
        new((AccountIds ?? [])
            .Select(NormalizeAccountId)
            .Where(value => value is not null)
            .Select(value => value!)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .OrderBy(value => value, StringComparer.OrdinalIgnoreCase)
            .ToArray());

    private static string? NormalizeAccountId(string? value) =>
        string.IsNullOrWhiteSpace(value) ? null : value.Trim();
}

public static class IdentityBindingLocalModeAccountKey
{
    public static string[] BuildCandidates(string? accountId, string? accountName)
    {
        var candidates = new List<string>(2);
        if (!string.IsNullOrWhiteSpace(accountId))
        {
            candidates.Add($"id:{accountId.Trim()}");
        }

        if (!string.IsNullOrWhiteSpace(accountName))
        {
            var normalizedName = accountName.Trim().ToUpperInvariant();
            var digest = Convert.ToHexString(
                SHA256.HashData(Encoding.UTF8.GetBytes(normalizedName))).ToLowerInvariant();
            candidates.Add($"account:{digest[..24]}");
        }

        return candidates
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
    }
}

internal static class IdentityBindingLocalModeSettingsStore
{
    private static readonly string SettingsPath = Path.Combine(
        DesktopAppConfig.ConfigDirectory,
        "identity-binding.local-mode");
    private static readonly string FallbackSettingsPath = Path.Combine(
        AppContext.BaseDirectory,
        "config",
        "identity-binding.local-mode");

    public static IdentityBindingLocalModeSettings Load()
    {
        return IdentityBindingLocalModeSettings.Parse(
            ReadOptionalText(SettingsPath) ?? ReadOptionalText(FallbackSettingsPath));
    }

    public static void Save(IdentityBindingLocalModeSettings settings)
    {
        var payload = settings.Serialize();
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(SettingsPath)!);
            File.WriteAllText(SettingsPath, payload);
            return;
        }
        catch
        {
            Directory.CreateDirectory(Path.GetDirectoryName(FallbackSettingsPath)!);
            File.WriteAllText(FallbackSettingsPath, payload);
        }
    }

    private static string? ReadOptionalText(string path)
    {
        try
        {
            return File.Exists(path) ? File.ReadAllText(path) : null;
        }
        catch
        {
            return null;
        }
    }
}
