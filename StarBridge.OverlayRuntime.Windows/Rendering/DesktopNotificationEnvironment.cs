namespace StarBridge.Desktop;

using System.Runtime.InteropServices;
using System.Text;
using Windows.Foundation.Metadata;
using Windows.UI.Notifications;

/// <summary>Read-only OS guards. An absent/new/failed state is never permission to interrupt.</summary>
public static class DesktopNotificationEnvironment
{
    public static string UserReason(string? reason) => reason switch {
        "do-not-disturb" => "doNotDisturb",
        "shell-suppressed-2" => "systemBusy",
        "shell-suppressed-3" or "shell-suppressed-4" or "shell-suppressed-7" => "fullScreen",
        "foreground-fullscreen" => "fullScreen",
        "foreground-unavailable" => "environmentUnknown",
        "shell-suppressed-1" or "secure-or-inactive-desktop" or "input-desktop-unavailable" => "inactiveDesktop",
        "shell-suppressed-6" => "quietTime",
        "notification-mode-unsupported" => "unsupported",
        "game-active-or-unknown" => "gameActiveOrUnknown",
        "main-window-active-or-unknown" => "appActiveOrUnknown",
        _ => "unavailable"
    };
    public static string SuppressionReason() => ReadSuppressionReason(false);
    public static string SocialSoundSuppressionReason() => ReadSuppressionReason(true);
    internal static string PlayerActivitySuppressionReason() => ReadSuppressionReason(false, true);
    internal static string EvaluateActivitySuppression(int state, bool gameForeground,
        Func<string> desktopReason, Func<string> notificationModeReason, Func<string> foregroundReason)
    {
        if (!gameForeground) return EvaluateSuppression(state, false, desktopReason, notificationModeReason, foregroundReason);
        // The activity producer already revalidates the user's background/reduce
        // choices. Only a verified game foreground gets this visual exception.
        if (state is not (2 or 3 or 5 or 7)) return "shell-suppressed-" + state;
        var inactive = desktopReason();
        return inactive.Length != 0 ? inactive : notificationModeReason();
    }
    private static string ReadSuppressionReason(bool allowFullscreenSound, bool playerActivity = false)
    {
        try
        {
            if (SHQueryUserNotificationState(out var state) != 0) return "shell-state-unavailable";
            if (playerActivity) return EvaluateActivitySuppression(state, StarCitizenProcessProbe.IsForeground(),
                ReadDesktopReason, ReadNotificationModeReason, ReadForegroundVisualReason);
            return EvaluateSuppression(state, allowFullscreenSound, ReadDesktopReason, ReadNotificationModeReason,
                ReadForegroundVisualReason);
        }
        catch { return "system-state-unavailable"; }
    }

    internal static string EvaluateSuppression(int state, bool allowFullscreenSound,
        Func<string> desktopReason, Func<string> notificationModeReason, Func<string>? foregroundReason = null)
    {
        // Windows can switch the toast notification mode to PriorityOnly while
        // a full-screen app is foreground. That visual mode must not mute an
        // explicitly enabled private/friend sound. A locked or inactive desktop,
        // explicit presentation state, quiet time and unknown shell state still
        // block audio. Outside full-screen, respect the notification mode.
        var immersiveSocialSound = allowFullscreenSound && state is 2 or 3 or 7;
        if (state != 5 && !(state == 2 && !allowFullscreenSound) && !immersiveSocialSound)
            return "shell-suppressed-" + state;
        var inactive = desktopReason();
        if (inactive.Length != 0) return inactive;
        if (immersiveSocialSound) return "";
        var mode = notificationModeReason();
        if (mode.Length != 0) return mode;
        // Busy is advisory: normal minimization can produce it on an idle desktop.
        // Production callers additionally verify the actual foreground window.
        return allowFullscreenSound ? "" : foregroundReason?.Invoke() ?? "foreground-unavailable";
    }

    internal static string ReadForegroundVisualReason()
    {
        var window = GetForegroundWindow();
        if (window == IntPtr.Zero) return "foreground-unavailable";
        var name = new StringBuilder(128);
        if (GetClassName(window, name, name.Capacity) == 0) return "foreground-unavailable";
        // Desktop/taskbar surfaces cover the monitor but are not immersive apps.
        if (IsDesktopSurface(name.ToString())) return "";
        if (DwmGetWindowAttribute(window, 9, out var bounds, Marshal.SizeOf<Rect>()) != 0)
            return "foreground-unavailable";
        var info = new MonitorInfo { Size = Marshal.SizeOf<MonitorInfo>() };
        if (!GetMonitorInfo(MonitorFromWindow(window, 2), ref info)) return "foreground-unavailable";
        return ForegroundBoundsReason(
            System.Drawing.Rectangle.FromLTRB(bounds.Left, bounds.Top, bounds.Right, bounds.Bottom),
            System.Drawing.Rectangle.FromLTRB(info.Monitor.Left, info.Monitor.Top, info.Monitor.Right, info.Monitor.Bottom));
    }

    internal static bool IsDesktopSurface(string name) =>
        name is "Progman" or "WorkerW" or "Shell_TrayWnd" or "Shell_SecondaryTrayWnd";

    internal static string ForegroundBoundsReason(System.Drawing.Rectangle bounds, System.Drawing.Rectangle monitor)
    {
        if (bounds.Width <= 0 || bounds.Height <= 0 || monitor.Width <= 0 || monitor.Height <= 0)
            return "foreground-unavailable";
        return bounds.Left <= monitor.Left && bounds.Top <= monitor.Top &&
            bounds.Right >= monitor.Right && bounds.Bottom >= monitor.Bottom ? "foreground-fullscreen" : "";
    }

    private static string ReadDesktopReason()
    {
            var desktop = OpenInputDesktop(0, false, 1);
            if (desktop == IntPtr.Zero) return "input-desktop-unavailable";
            try
            {
                var name = new StringBuilder(256);
                if (!GetUserObjectInformation(desktop, 2, name, 512, out _) || name.ToString() != "Default")
                    return "secure-or-inactive-desktop";
            }
            finally { CloseDesktop(desktop); }
            return "";
    }

    internal static string ReadNotificationModeReason()
    {
        try {
            if (!ApiInformation.IsPropertyPresent("Windows.UI.Notifications.ToastNotificationManagerForUser", "NotificationMode"))
                return "notification-mode-unsupported";
            // SDK 22621 is retained for the existing client. Query the public v15 WinRT interface
            // when present instead of using undocumented WNF/registry guesses on older Windows.
            var manager = ToastNotificationManager.GetDefault();
            var native = ((WinRT.IWinRTObject)manager).NativeObject;
            var iid = new Guid("3EFCB176-6CC1-56DC-973B-251F7AACB1C5");
            if (Marshal.QueryInterface(native.ThisPtr, ref iid, out var modeInterface) != 0)
                return "notification-mode-unavailable";
            try
            {
                var vtable = Marshal.ReadIntPtr(modeInterface);
                var getter = Marshal.GetDelegateForFunctionPointer<GetMode>(Marshal.ReadIntPtr(vtable, 6 * IntPtr.Size));
                if (getter(modeInterface, out var mode) != 0) return "notification-mode-unavailable";
                return mode == 0 ? "" : "do-not-disturb";
            }
            finally { Marshal.Release(modeInterface); GC.KeepAlive(manager); }
        }
        catch { return "notification-mode-unavailable"; }
    }

    [UnmanagedFunctionPointer(CallingConvention.StdCall)] private delegate int GetMode(IntPtr self, out int mode);
    [StructLayout(LayoutKind.Sequential)] private struct Rect { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] private struct MonitorInfo { public int Size; public Rect Monitor, Work; public uint Flags; }
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetClassName(IntPtr window, StringBuilder name, int count);
    [DllImport("dwmapi.dll")] private static extern int DwmGetWindowAttribute(IntPtr window, int attribute, out Rect bounds, int size);
    [DllImport("user32.dll")] private static extern IntPtr MonitorFromWindow(IntPtr window, uint flags);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern bool GetMonitorInfo(IntPtr monitor, ref MonitorInfo info);
    [DllImport("shell32.dll")] private static extern int SHQueryUserNotificationState(out int state);
    [DllImport("user32.dll", SetLastError = true)] private static extern IntPtr OpenInputDesktop(uint flags, bool inherit, uint access);
    [DllImport("user32.dll")] private static extern bool CloseDesktop(IntPtr desktop);
    [DllImport("user32.dll", EntryPoint = "GetUserObjectInformationW", CharSet = CharSet.Unicode)]
    private static extern bool GetUserObjectInformation(IntPtr handle, int index, StringBuilder value, uint size, out uint needed);
}
