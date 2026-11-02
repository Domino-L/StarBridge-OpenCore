using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Overlay;

namespace StarBridge.HostRuntime.Tests;

internal static class InstalledAppearanceProgressBoundaryTests
{
    internal static void Verify()
    {
        var assembly = typeof(AccountBridgeRuntime).Assembly;
        if (assembly.GetReferencedAssemblies().Any(reference =>
                reference.Name?.Contains("PrivateAppearances", StringComparison.Ordinal) == true) ||
            assembly.GetTypes().Any(type =>
                type.FullName?.Contains("Haji", StringComparison.Ordinal) == true))
            throw new InvalidOperationException("Public Host imported a private appearance implementation.");

        using var runtime = AccountBridgeRuntime.CreateIsolatedSandboxShell();
        if (runtime.CreateInstalledAppearanceProgress() is not null ||
            runtime.CreateInstalledAppearanceProgress() is not null)
            throw new InvalidOperationException("Sandbox created an installed progress owner.");
        runtime.Dispose();
        try
        {
            runtime.CreateInstalledAppearanceProgress();
            throw new InvalidOperationException("Disposed Host created a progress owner.");
        }
        catch (ObjectDisposedException) { }

        var unknown = new InstalledAppearanceProgressSnapshot(null, null, "unavailable");
        if (unknown.AccountEpoch is not null || unknown.ConfirmedUsageMs is not null)
            throw new InvalidOperationException("Unknown progress became a confirmed zero or an account.");
        Console.WriteLine("PASS public installed progress seam: no private implementation, inert sandbox, disposed guard, unknown remains nullable.");
    }
}
