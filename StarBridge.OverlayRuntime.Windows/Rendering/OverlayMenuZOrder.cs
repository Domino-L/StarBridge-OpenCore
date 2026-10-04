using System.Runtime.InteropServices;

namespace StarBridge.Desktop;

// Event-driven stacking boundary. The owner supplies an already validated menu
// HWND. HWND reuse and menu closure must never redirect this to another process.
internal sealed class OverlayMenuZOrder
{
    private nint _above;
    private uint _process;
    internal void Set(nint above)
    {
        GetWindowThreadProcessId(above, out _process);
        Interlocked.Exchange(ref _above, above);
    }

    private nint Above()
    {
        var above = Interlocked.CompareExchange(ref _above, 0, 0);
        GetWindowThreadProcessId(above, out var process);
        return above != 0 && IsWindow(above) && IsWindowVisible(above) && process == _process ? above : 0;
    }

    internal void Apply(nint handle)
    {
        var above = Above();
        if (handle != 0 && above != 0)
            SetWindowPos(handle, above, 0, 0, 0, 0, 0x0001 | 0x0002 | 0x0010);
    }

    internal void Constrain(int message, nint position)
    {
        if (message != 0x0046 || position == 0) return; // WM_WINDOWPOSCHANGING
        var above = Above();
        if (above == 0) return;
        var value = Marshal.PtrToStructure<WindowPosition>(position);
        if ((value.Flags & 0x0004) != 0) return; // SWP_NOZORDER
        value.InsertAfter = above;
        value.Flags |= 0x0010; // Never activate the passive HUD.
        Marshal.StructureToPtr(value, position, false);
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct WindowPosition
    {
        public nint Window, InsertAfter;
        public int X, Y, Width, Height;
        public uint Flags;
    }
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(nint window, out uint process);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool IsWindow(nint window);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool IsWindowVisible(nint window);
    [DllImport("user32.dll")] [return: MarshalAs(UnmanagedType.Bool)] private static extern bool SetWindowPos(nint window, nint after, int x, int y, int width, int height, uint flags);
}
