namespace StarBridge.NativeHost;

using System.Runtime.InteropServices;
using StarBridge.HostRuntime.Presence;

internal sealed class WindowsNotificationActivity(int parentProcessId)
{
    private readonly LocalGamePresenceReader _game = new();
    internal StarBridge.HostRuntime.Notifications.PlayerActivityEnvironment ReadPlayerActivity(
        StarBridge.HostRuntime.Support.IRuntimeOverlayStatusReader? overlay)
    {
        try {
            var foreground = GetForegroundWindow();
            if (foreground == IntPtr.Zero || GetWindowThreadProcessId(foreground, out var id) == 0)
                return new(false, false, false, false);
            var game = _game.Read().State;
            if (game == "unknown") return new(false, id != parentProcessId, false, false);
            if (game == "notRunning") return new(true, id != parentProcessId, false, false);
            if (overlay is null) return new(false, id != parentProcessId, true, false);
            var status = ReadOverlayBounded(overlay);
            return new(status.WindowState is "open" or "closed", id != parentProcessId, true, status.WindowState == "open");
        } catch { return new(false, false, false, false); }
    }
    internal static StarBridge.HostRuntime.Support.RuntimeOverlayStatus ReadOverlayBounded(
        StarBridge.HostRuntime.Support.IRuntimeOverlayStatusReader reader)
    {
        using var deadline = new CancellationTokenSource(TimeSpan.FromMilliseconds(200));
        return reader.ReadStatusAsync(deadline.Token).AsTask().WaitAsync(deadline.Token).GetAwaiter().GetResult();
    }
    internal bool CanNotify()
    {
        if (!StarBridge.OverlayRuntime.Windows.WindowsInformationOverlayRuntimeFactory.SystemAllowsNotifications()) return false;
        var foreground = GetForegroundWindow();
        if (foreground == IntPtr.Zero) return false;
        if (GetWindowThreadProcessId(foreground, out var processId) == 0 || processId == parentProcessId) return false;
        // Unknown game state is quiet too; sound must not compete with the overlay.
        return _game.Read().State == "notRunning";
    }
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
}
