namespace StarBridge.Desktop;

using System.Runtime.InteropServices;
using System.Text;
using Windows.Foundation.Metadata;
using Windows.UI.Notifications;

/// <summary>Read-only OS guards. An absent/new/failed state is never permission to interrupt.</summary>
public static class DesktopNotificationEnvironment
{
    internal static string UserReason(string? reason) => reason switch {
        "do-not-disturb" => "doNotDisturb",
        "shell-suppressed-2" => "systemBusy",
        "shell-suppressed-3" or "shell-suppressed-4" or "shell-suppressed-7" => "fullScreen",
        "shell-suppressed-1" or "secure-or-inactive-desktop" or "input-desktop-unavailable" => "inactiveDesktop",
        "shell-suppressed-6" => "quietTime",
        "notification-mode-unsupported" => "unsupported",
        "game-active-or-unknown" => "gameActiveOrUnknown",
        "main-window-active-or-unknown" => "appActiveOrUnknown",
        _ => "unavailable"
    };
    public static string SuppressionReason()
    {
        try
        {
            if (SHQueryUserNotificationState(out var state) != 0) return "shell-state-unavailable";
            if (state != 5) return "shell-suppressed-" + state;
            var desktop = OpenInputDesktop(0, false, 1);
            if (desktop == IntPtr.Zero) return "input-desktop-unavailable";
            try
            {
                var name = new StringBuilder(256);
                if (!GetUserObjectInformation(desktop, 2, name, 512, out _) || name.ToString() != "Default")
                    return "secure-or-inactive-desktop";
            }
            finally { CloseDesktop(desktop); }
            return ReadNotificationModeReason();
        }
        catch { return "system-state-unavailable"; }
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
    [DllImport("shell32.dll")] private static extern int SHQueryUserNotificationState(out int state);
    [DllImport("user32.dll", SetLastError = true)] private static extern IntPtr OpenInputDesktop(uint flags, bool inherit, uint access);
    [DllImport("user32.dll")] private static extern bool CloseDesktop(IntPtr desktop);
    [DllImport("user32.dll", EntryPoint = "GetUserObjectInformationW", CharSet = CharSet.Unicode)]
    private static extern bool GetUserObjectInformation(IntPtr handle, int index, StringBuilder value, uint size, out uint needed);
}
