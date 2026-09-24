using System.Security.Cryptography;
using System.Text.Json;
using StarBridge.HostRuntime.Settings;

namespace StarBridge.HostRuntime.Updates;

internal sealed record WpfMigrationPreferencesResult(string State, string? SourceSha256 = null);

/// <summary>Read-only application preference check, not full data compatibility.
/// The coordinator must hold the storage lease and verify the selected root.
/// No account discovery, promotion, default saves or uninstall authority.</summary>
internal static class WpfMigrationPreferencesCheck
{
    internal static WpfMigrationPreferencesResult Inspect(string root)
    {
        try
        {
            if (!Path.IsPathFullyQualified(root) || root.StartsWith(@"\\", StringComparison.Ordinal))
                return new("unavailable");
            root = Path.TrimEndingDirectorySeparator(Path.GetFullPath(root));
            if (root == Path.GetPathRoot(root)) return new("unavailable");
            for (var part = new DirectoryInfo(root); part is not null; part = part.Parent)
                if ((File.GetAttributes(part.FullName) & FileAttributes.ReparsePoint) != 0)
                    return new("unavailable");
            var modern = Path.Combine(root, "application-preferences.v1.json");
            var legacy = Path.Combine(root, "application-behavior.json");
            using var current = OpenIfPresent(modern);
            using var previous = OpenIfPresent(legacy);
            var source = current ?? previous;
            if (source is null) return new("not-present");
            if (source.Length is <= 0 or > 1024 * 1024) return new("needs-review");
            var bytes = new byte[(int)source.Length];
            source.ReadExactly(bytes);
            using var document = JsonDocument.Parse(bytes);
            if (document.RootElement.ValueKind != JsonValueKind.Object) return new("needs-review");
            var names = new HashSet<string>(current is null ? StringComparer.OrdinalIgnoreCase : StringComparer.Ordinal);
            foreach (var property in document.RootElement.EnumerateObject())
                if (!names.Add(property.Name)) return new("needs-review");
            // Legacy deserialization accepts missing booleans as false. That is
            // useful for runtime fallback, but not proof that saved choices survived.
            var required = current is null
                ? new[] { "LaunchAtStartup", "KeepRunningInBackground", "StartMinimized", "BackgroundHintShown" }
                : new[] { "schemaVersion", "revision", "appearanceMode", "motionPreference",
                    "launchAtStartup", "keepRunningInBackground", "startMinimized",
                    "startupChoiceMade", "closeBehaviorChoiceMade", "backgroundHintShown" };
            if (required.Any(name => !names.Contains(name))) return new("needs-review");
            // Invoke the production reader while its input is held against writes/deletion.
            var read = new ApplicationPreferencesStore(root).Load();
            return read.StorageState == ApplicationPreferencesStorageStates.Ready
                ? new("compatible", Convert.ToHexString(SHA256.HashData(bytes)))
                : new("needs-review");
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException or
            ApplicationPreferencesException or ArgumentException or NotSupportedException or System.Security.SecurityException)
        {
            return new("unavailable");
        }
    }

    private static FileStream? OpenIfPresent(string path)
    {
        try
        {
            if ((File.GetAttributes(path) & (FileAttributes.ReparsePoint | FileAttributes.Directory)) != 0)
                throw new IOException("Preferences are not a regular file.");
            return new(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        }
        catch (FileNotFoundException) { return null; }
    }
}
