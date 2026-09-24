using System.Diagnostics;
using System.Runtime.InteropServices;

namespace StarBridge.Desktop;

internal static class StarCitizenProcessProbe
{
    private static readonly string[] ProcessNames =
    [
        "StarCitizen",
        "StarCitizen_LIVE",
        "StarCitizen_PTUR",
        "StarCitizen_EPTU",
        "StarCitizen_TECH-PREVIEW"
    ];

    public static bool IsRunning() => TryGetStart(out _);

    public static bool TryGetStart(out DateTimeOffset? startedAtUtc)
    {
        startedAtUtc = null;
        var found = false;
        foreach (var processName in ProcessNames)
        {
            Process[] processes;
            try
            {
                processes = Process.GetProcessesByName(processName);
            }
            catch
            {
                continue;
            }

            foreach (var process in processes)
            {
                using (process)
                {
                    try
                    {
                        if (process.HasExited)
                        {
                            continue;
                        }

                        found = true;
                        var processStart = new DateTimeOffset(process.StartTime.ToUniversalTime(), TimeSpan.Zero);
                        if (startedAtUtc is null || processStart < startedAtUtc)
                        {
                            startedAtUtc = processStart;
                        }
                    }
                    catch
                    {
                        // Process existence is enough when its start time is inaccessible.
                        found = true;
                    }
                }
            }
        }

        return found;
    }

    public static bool IsForeground()
    {
        var foregroundHandle = GetForegroundWindow();
        return foregroundHandle != IntPtr.Zero && IsGameWindow(foregroundHandle);
    }

    public static IntPtr FindMainWindow()
    {
        foreach (var processName in ProcessNames)
        {
            Process[] processes;
            try
            {
                processes = Process.GetProcessesByName(processName);
            }
            catch
            {
                continue;
            }

            foreach (var process in processes)
            {
                using (process)
                {
                    var handle = process.MainWindowHandle;
                    if (handle != IntPtr.Zero)
                    {
                        return handle;
                    }
                }
            }
        }

        return IntPtr.Zero;
    }

    private static bool IsGameWindow(IntPtr handle)
    {
        _ = GetWindowThreadProcessId(handle, out var processId);
        if (processId == 0)
        {
            return false;
        }

        try
        {
            using var process = Process.GetProcessById((int)processId);
            return ProcessNames.Any(processName =>
                process.ProcessName.Equals(processName, StringComparison.OrdinalIgnoreCase));
        }
        catch
        {
            return false;
        }
    }

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr handle, out uint processId);
}
