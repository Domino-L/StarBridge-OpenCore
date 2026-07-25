using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;

namespace StarBridge.Desktop;

internal static class WindowsFullscreenTaskbar
{
    private static readonly Guid TaskbarListClassId = new("56FDF344-FD6D-11D0-958A-006097C9A090");

    public static void SetFullscreen(Window window, bool fullscreen)
    {
        if (!OperatingSystem.IsWindows())
        {
            return;
        }

        var handle = new WindowInteropHelper(window).Handle;
        if (handle == IntPtr.Zero)
        {
            return;
        }

        ITaskbarList2? taskbar = null;
        try
        {
            var taskbarType = Type.GetTypeFromCLSID(TaskbarListClassId, throwOnError: true);
            taskbar = Activator.CreateInstance(taskbarType!) as ITaskbarList2;
            if (taskbar is not null)
            {
                Marshal.ThrowExceptionForHR(taskbar.HrInit());
                Marshal.ThrowExceptionForHR(taskbar.MarkFullscreenWindow(handle, fullscreen));
            }
        }
        catch (COMException)
        {
            // The editor remains usable if Explorer or the taskbar is unavailable.
        }
        catch (InvalidCastException)
        {
            // Older or replacement shells may not expose ITaskbarList2.
        }
        finally
        {
            if (taskbar is not null && Marshal.IsComObject(taskbar))
            {
                Marshal.FinalReleaseComObject(taskbar);
            }
        }
    }

    [ComImport]
    [Guid("602D4995-B13A-429B-A66E-1935E44F4317")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface ITaskbarList2
    {
        [PreserveSig]
        int HrInit();

        [PreserveSig]
        int AddTab(IntPtr windowHandle);

        [PreserveSig]
        int DeleteTab(IntPtr windowHandle);

        [PreserveSig]
        int ActivateTab(IntPtr windowHandle);

        [PreserveSig]
        int SetActiveAlt(IntPtr windowHandle);

        [PreserveSig]
        int MarkFullscreenWindow(
            IntPtr windowHandle,
            [MarshalAs(UnmanagedType.Bool)] bool fullscreen);
    }
}
