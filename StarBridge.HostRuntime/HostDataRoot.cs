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
    internal const string IsolatedTestProcessSwitch = "StarBridge.HostDataRoot.IsolatedTestProcess";

    public static string BootstrapDirectory { get; } = ResolveBootstrapDirectory();

    /// <summary>True in test hosts that set the isolation runtimeconfig switch.</summary>
    public static bool IsIsolatedTestProcess =>
        AppContext.TryGetSwitch(IsolatedTestProcessSwitch, out var isolated) && isolated;

    // Test hosts never read the user's locator or write diagnostics into the real
    // bootstrap folder. Known folders ignore %LOCALAPPDATA% overrides (2026-10-29).
    private static string ResolveBootstrapDirectory() => IsIsolatedTestProcess
        ? Path.Combine(Path.GetTempPath(), "StarBridge-HostTests-Bootstrap")
        : Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "StarBridge");

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

    internal static string ResolveConfiguredRoot(string bootstrapDirectory)
    {
#if DEBUG
        var debugRoot = Environment.GetEnvironmentVariable("STARBRIDGE_DEBUG_DATA_ROOT");
        if (!string.IsNullOrWhiteSpace(debugRoot))
        {
            return Path.TrimEndingDirectorySeparator(Path.GetFullPath(debugRoot));
        }
#endif
        // Test hosts set this runtimeconfig switch (the Host test project and every
        // child started from its assembly). They never fall back to the user's
        // configured product root, in Debug or Release (2026-10-21).
        if (IsIsolatedTestProcess)
        {
            return Path.TrimEndingDirectorySeparator(
                Path.Combine(Path.GetTempPath(), "StarBridge-HostTests-DataRoot"));
        }

        return Storage.StorageRootLocator.Read(bootstrapDirectory);
    }
}
