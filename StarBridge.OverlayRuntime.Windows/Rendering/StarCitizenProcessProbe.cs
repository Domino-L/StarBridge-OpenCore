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

    // Names only, so no handle to the game is opened.
    public static bool IsRunning() => StarBridge.HostRuntime.Presence.ProcessSnapshotNames.Any(IsGameImageName);

    internal static bool IsGameImageName(string imageName) =>
        ProcessNames.Any(processName => processName.Equals(
            System.IO.Path.GetFileNameWithoutExtension(imageName), StringComparison.OrdinalIgnoreCase));

    // Reads the start time through a process handle: for the old WPF client only, never a
    // release path (the input safety gate holds this).
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

    internal static bool TryCaptureForeground(out IntPtr handle, out uint processId)
    {
        handle = GetForegroundWindow();
        processId = 0;
        if (handle == IntPtr.Zero || !IsGameWindow(handle)) return false;
        _ = GetWindowThreadProcessId(handle, out processId);
        return processId != 0 && handle == GetForegroundWindow();
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

        return StarBridge.HostRuntime.Presence.ProcessSnapshotNames.FindForeground(processId) is { } imageName &&
            IsGameImageName(imageName);
    }

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    private static extern uint GetWindowThreadProcessId(IntPtr handle, out uint processId);
}
