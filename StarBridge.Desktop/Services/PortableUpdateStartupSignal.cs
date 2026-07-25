using System.IO;
using System.Text;
using System.Windows;

namespace StarBridge.Desktop;

internal static class PortableUpdateStartupSignal
{
    internal const string ReadyMarkerEnvironmentVariable = "STARBRIDGE_UPDATE_READY_MARKER";

    public static void Attach(Window window)
    {
        var markerPath = Environment.GetEnvironmentVariable(ReadyMarkerEnvironmentVariable);
        if (string.IsNullOrWhiteSpace(markerPath))
        {
            return;
        }

        EventHandler? rendered = null;
        rendered = (_, _) =>
        {
            window.ContentRendered -= rendered;
            TryWriteReadyMarker(markerPath);
        };
        window.ContentRendered += rendered;
    }

    private static void TryWriteReadyMarker(string markerPath)
    {
        try
        {
            Directory.CreateDirectory(Path.GetDirectoryName(markerPath) ?? Path.GetTempPath());
            File.WriteAllText(
                markerPath,
                DateTimeOffset.UtcNow.ToString("O"),
                new UTF8Encoding(encoderShouldEmitUTF8Identifier: false));
        }
        catch
        {
            // Readiness reporting must never prevent the updated app from starting.
        }
        finally
        {
            Environment.SetEnvironmentVariable(ReadyMarkerEnvironmentVariable, null);
        }
    }
}
