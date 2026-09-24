using System.IO;

namespace StarBridge.Desktop;

/// <summary>Best-effort native diagnostics without constructing the retired application.</summary>
internal static class DesktopRuntimeDiagnostics
{
    internal static void WriteCrashLog(Exception exception) =>
        Append("desktop-crash.log", $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss}]\n{exception}\n\n");

    internal static void WriteDiagnosticLog(string message) =>
        Append("desktop-overlay-diagnostics.log", $"[{DateTime.Now:yyyy-MM-dd HH:mm:ss.fff}] {message}{Environment.NewLine}");

    private static void Append(string fileName, string text)
    {
        try
        {
            var directory = StarBridge.HostRuntime.HostDataRoot.BootstrapDirectory;
#if DEBUG
            var debugRoot = Environment.GetEnvironmentVariable("STARBRIDGE_DEBUG_DATA_ROOT");
            if (!string.IsNullOrWhiteSpace(debugRoot))
                directory = Path.TrimEndingDirectorySeparator(Path.GetFullPath(Environment.ExpandEnvironmentVariables(debugRoot.Trim())));
#endif
            Directory.CreateDirectory(directory);
            File.AppendAllText(Path.Combine(directory, fileName), text);
        }
        catch
        {
            // Diagnostics must never become another runtime failure.
        }
    }
}
