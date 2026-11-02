using System.Runtime.InteropServices;
using StarBridge.HostRuntime.Overlay;

namespace StarBridge.OverlayRuntime.Windows;

/// Native composition reader. Only the launching client's window registered
/// by its native pipe bridge for THIS Host may supply physical client bounds.
/// No foreground/title/MainWindowHandle heuristic or renderer-supplied handle.
public sealed class WindowsOverlayPreviewRegisteredClient(int clientProcessId, int hostProcessId, Func<bool>? isCurrent = null)
{
    private const string LeaseProperty = "StarBridge.NativeHostBridge.PrimaryLease";
    private const string ServerProperty = "StarBridge.NativeHostBridge.ServerPid";
    private const string EpochProperty = "StarBridge.NativeHostBridge.ConnectionEpoch";
    public Func<OverlayPreviewClientViewport?>? Capture()
    {
        if (Resolve() is null) return null;
        var lease = Registered();
        var token = GetProp(lease.Window, LeaseProperty);
        var epoch = GetProp(lease.Window, EpochProperty);
        if (lease.Window == IntPtr.Zero || token == IntPtr.Zero || epoch == IntPtr.Zero) return null;
        bool Matches() => lease == Registered() && token == GetProp(lease.Window, LeaseProperty) &&
            epoch == GetProp(lease.Window, EpochProperty);
        return () =>
        {
            if (!Matches()) return null;
            var viewport = Resolve();
            // Disconnect/reconnect may race the physical bounds read itself.
            // A stable new Resolve result must never revive this older lease.
            return Matches() ? viewport : null;
        };
    }
    public OverlayPreviewClientViewport? Resolve()
    {
        try
        {
            if (clientProcessId <= 0 || hostProcessId != Environment.ProcessId ||
                isCurrent?.Invoke() == false) return null;
            var lease = Registered();
            if (lease.Window == IntPtr.Zero) return null;
            var token = GetProp(lease.Window, LeaseProperty);
            var epoch = GetProp(lease.Window, EpochProperty);
            var reader = new StarBridge.Desktop.OverlayPreviewClientViewportResolver(Registered);
            var result = reader.Resolve();
            return token != IntPtr.Zero && epoch != IntPtr.Zero && token == GetProp(lease.Window, LeaseProperty) &&
                epoch == GetProp(lease.Window, EpochProperty) &&
                lease == Registered() && isCurrent?.Invoke() != false ? result : null;
        }
        catch { return null; } // Missing registration never falls back to an auxiliary window.
    }
    private (IntPtr Window, int ClientProcessId, bool IsCurrent) Registered()
    {
        if (isCurrent?.Invoke() == false) return (IntPtr.Zero, clientProcessId, false);
        IntPtr window = IntPtr.Zero;
        var count = 0;
        EnumCallback callback = (candidate, _) =>
        {
            GetWindowThreadProcessId(candidate, out var pid);
            if (pid == clientProcessId && GetAncestor(candidate, 2) == candidate &&
                GetProp(candidate, ServerProperty).ToInt64() == hostProcessId &&
                GetProp(candidate, LeaseProperty) != IntPtr.Zero && GetProp(candidate, EpochProperty) != IntPtr.Zero)
            { window = candidate; count++; }
            return true;
        };
        if (!EnumWindows(callback, IntPtr.Zero) || count != 1) window = IntPtr.Zero;
        return (window, clientProcessId, window != IntPtr.Zero);
    }
    private delegate bool EnumCallback(IntPtr window, IntPtr state);
    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumCallback callback, IntPtr state);
    [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "GetPropW")] private static extern IntPtr GetProp(IntPtr window, string name);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out uint pid);
    [DllImport("user32.dll")] private static extern IntPtr GetAncestor(IntPtr window, uint flags);
}
