using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Storage;

// 2026-10-21: Host tests that never prepared a root fell back to the user's
// configured data root and appended synthetic sign-in lines to the real
// scm-auth-diagnostics.log while the user's client was running, even with
// STARBRIDGE_DEBUG_DATA_ROOT set (Release ignores it; another process may not
// carry it). A test process must never resolve the configured product root.
internal static class HostDataRootIsolationTests
{
    internal static void Verify()
    {
        var bootstrap = Path.Combine(Path.GetTempPath(), "StarBridge-root-isolation-" + Guid.NewGuid().ToString("N"));
        var configured = Path.Combine(bootstrap, "configured-product-root");
        Directory.CreateDirectory(configured);
        var debugRoot = Environment.GetEnvironmentVariable("STARBRIDGE_DEBUG_DATA_ROOT");
        try
        {
            StorageRootLocator.Write(bootstrap, configured);
            Environment.SetEnvironmentVariable("STARBRIDGE_DEBUG_DATA_ROOT", null);
            var resolved = HostDataRoot.ResolveConfiguredRoot(bootstrap);
            if (string.Equals(resolved, Path.GetFullPath(configured), StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("A test process resolves the user's configured data root.");
            if (!resolved.StartsWith(Path.TrimEndingDirectorySeparator(Path.GetTempPath()), StringComparison.OrdinalIgnoreCase))
                throw new InvalidOperationException("A test process data root must stay under the temporary directory.");
        }
        finally
        {
            Environment.SetEnvironmentVariable("STARBRIDGE_DEBUG_DATA_ROOT", debugRoot);
            Directory.Delete(bootstrap, recursive: true);
        }
        Console.WriteLine("PASS a Host test process never falls back to the user's configured data root");
    }
}
