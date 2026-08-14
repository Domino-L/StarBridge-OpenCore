using System.IO;
using System.Reflection;
using System.Text.Json;

namespace StarBridge.Desktop;

internal sealed record AppReleaseHistoryEntry(
    string Version,
    string PublishedOn,
    string Title,
    string Summary,
    IReadOnlyList<string> Highlights);

internal sealed record AppReleaseHistoryDocument(
    int SchemaVersion,
    string CurrentVersion,
    IReadOnlyList<AppReleaseHistoryEntry> Entries);

internal static class AppReleaseHistoryCatalog
{
    internal const string ResourceName = "StarBridge.ReleaseNotes.catalog.json";

    internal static IReadOnlyList<AppReleaseHistoryEntry> Entries { get; } = Load().Entries;

    internal static AppReleaseHistoryDocument Load()
    {
        var assembly = Assembly.GetExecutingAssembly();
        using var stream = assembly.GetManifestResourceStream(ResourceName)
            ?? throw new InvalidDataException($"Embedded release history was not found: {ResourceName}");
        var document = JsonSerializer.Deserialize<AppReleaseHistoryDocument>(
            stream,
            new JsonSerializerOptions { PropertyNameCaseInsensitive = true })
            ?? throw new InvalidDataException("Embedded release history is empty or invalid.");

        Validate(document, AppVersionIdentity.GetCurrentVersion());
        return document;
    }

    internal static void Validate(AppReleaseHistoryDocument document, string expectedCurrentVersion)
    {
        ArgumentNullException.ThrowIfNull(document);
        ArgumentException.ThrowIfNullOrWhiteSpace(expectedCurrentVersion);

        if (document.SchemaVersion != 1)
        {
            throw new InvalidDataException($"Unsupported release-history schema: {document.SchemaVersion}");
        }

        if (!string.Equals(document.CurrentVersion, expectedCurrentVersion, StringComparison.Ordinal))
        {
            throw new InvalidDataException(
                $"Release history current version '{document.CurrentVersion}' does not match the application version '{expectedCurrentVersion}'.");
        }

        if (document.Entries is null || document.Entries.Count == 0)
        {
            throw new InvalidDataException("Release history must contain at least one entry.");
        }

        if (!string.Equals(document.Entries[0].Version, document.CurrentVersion, StringComparison.Ordinal))
        {
            throw new InvalidDataException("The newest release-history entry must match currentVersion.");
        }

        var duplicateVersion = document.Entries
            .GroupBy(entry => entry.Version, StringComparer.Ordinal)
            .FirstOrDefault(group => group.Count() > 1)?.Key;
        if (duplicateVersion is not null)
        {
            throw new InvalidDataException($"Release history contains duplicate version '{duplicateVersion}'.");
        }

        foreach (var entry in document.Entries)
        {
            if (!Version.TryParse(entry.Version, out _) ||
                !DateOnly.TryParseExact(entry.PublishedOn, "yyyy-MM-dd", out _) ||
                string.IsNullOrWhiteSpace(entry.Title) ||
                string.IsNullOrWhiteSpace(entry.Summary) ||
                entry.Highlights is null ||
                entry.Highlights.Count == 0 ||
                entry.Highlights.Any(string.IsNullOrWhiteSpace))
            {
                throw new InvalidDataException($"Release history entry '{entry.Version}' is incomplete.");
            }
        }
    }
}
