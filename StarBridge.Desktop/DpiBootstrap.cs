using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using WinForms = System.Windows.Forms;

namespace StarBridge.Desktop;

internal static class DpiBootstrap
{
    private static readonly IntPtr PerMonitorV2Context = new(-4);

    internal static bool SetHighDpiModeAccepted { get; private set; }

    internal static bool IsPerMonitorV2 { get; private set; }

    internal static string Diagnostic { get; private set; } = "DPI bootstrap has not run.";

    [ModuleInitializer]
    internal static void Initialize()
    {
        // WPF's generated entry point constructs App before user startup code
        // runs. Configure the process before that entry point so WPF, WinForms,
        // WebView2 and DirectComposition all inherit one DPI policy.
        try
        {
            SetHighDpiModeAccepted =
                WinForms.Application.SetHighDpiMode(WinForms.HighDpiMode.PerMonitorV2);
            var currentContext = GetThreadDpiAwarenessContext();
            IsPerMonitorV2 = currentContext != IntPtr.Zero &&
                             AreDpiAwarenessContextsEqual(currentContext, PerMonitorV2Context);
            Diagnostic =
                $"requestAccepted={SetHighDpiModeAccepted}; effectivePerMonitorV2={IsPerMonitorV2}";

        }
        catch (Exception ex)
        {
            SetHighDpiModeAccepted = false;
            IsPerMonitorV2 = false;
            Diagnostic = $"bootstrapException={ex.GetType().Name}: {ex.Message}";
        }
    }

    [DllImport("user32.dll")]
    private static extern IntPtr GetThreadDpiAwarenessContext();

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool AreDpiAwarenessContextsEqual(IntPtr first, IntPtr second);
}
