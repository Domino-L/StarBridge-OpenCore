namespace StarBridge.HostRuntime.Updates;

// A local preflight failure, not an untrusted download/parser message.
// Only the fixed code crosses the bridge; no paths or raw exception details.
internal sealed class InstalledUpdateVersionMismatchException() : IOException("Registered version does not match.")
{
    internal const string Code = "applicationUpdates.installationVersionMismatch";

    internal static void RequireMatch(string? binaryVersion, string registeredVersion)
    {
        if (ApplicationUpdateVersion.ParseInstalled(binaryVersion) != ApplicationUpdateVersion.Parse(registeredVersion))
            throw new InstalledUpdateVersionMismatchException();
    }
}
