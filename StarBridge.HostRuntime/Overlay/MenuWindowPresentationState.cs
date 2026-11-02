using System.Runtime.InteropServices;

namespace StarBridge.HostRuntime.Overlay;

// Presentation observation only, not permission to send messages or play audio.
// Each authenticated primary lease owns a separate instance.
internal sealed class MenuWindowPresentationState(Func<long, bool> windowShown)
{
    private readonly object _gate = new();
    private long _request;
    private int _phase;
    private long _window;

    // The renderer's "closed" acknowledgement is best effort. If it is lost, a
    // stale visible phase would hide the pinned HUD and suppress the shortcut
    // until the next opening, so visibility also requires the real menu HWND.
    internal bool Visible
    {
        get
        {
            long window;
            lock (_gate)
            {
                if (_phase != 2) return false;
                window = _window;
            }
            return windowShown(window);
        }
    }

    internal void Observe(long request, string phase, long window)
    {
        var next = phase switch { "opening" => 1, "visible" when window > 0 => 2, "closed" => 3, _ => 0 };
        if (request <= 0 || next == 0) return;
        lock (_gate)
        {
            if (request < _request || (request == _request && next <= _phase)) return;
            _request = request;
            _phase = next;
            if (next == 2) _window = window;
        }
    }

    internal static bool NativeWindowShown(long window) =>
        !OperatingSystem.IsWindows() || (IsWindow((nint)window) && IsWindowVisible((nint)window));

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindow(nint window);
    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindowVisible(nint window);
}
