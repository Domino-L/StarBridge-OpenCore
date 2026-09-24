namespace StarBridge.HostRuntime;

using System.IO;

/// <summary>
/// Resolves the one product data root without depending on WPF. The legacy
/// Desktop migration UI may prepare and publish a root during transition; the
/// final Native Host resolves the same locator directly.
/// </summary>
public static class HostDataRoot
{
    private static string? _currentRoot;

    public static string BootstrapDirectory { get; } = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "StarBridge");

    public static string CurrentRoot =>
        _currentRoot ??= ResolveConfiguredRoot(BootstrapDirectory);

    public static void UsePreparedRoot(string root)
    {
        if (string.IsNullOrWhiteSpace(root))
        {
            throw new ArgumentException("Product data root is required.", nameof(root));
        }

        _currentRoot = Path.TrimEndingDirectorySeparator(Path.GetFullPath(
            Environment.ExpandEnvironmentVariables(root.Trim())));
    }

    private static string ResolveConfiguredRoot(string bootstrapDirectory)
    {
#if DEBUG
        var debugRoot = Environment.GetEnvironmentVariable("STARBRIDGE_DEBUG_DATA_ROOT");
        if (!string.IsNullOrWhiteSpace(debugRoot))
        {
            return Path.TrimEndingDirectorySeparator(Path.GetFullPath(debugRoot));
        }
#endif

        return Storage.StorageRootLocator.Read(bootstrapDirectory);
    }
}
