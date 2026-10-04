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
            var game = _game.ReadCurrentState();
            if (game == "unknown") return new(false, id != parentProcessId, false, false);
            if (game == "notRunning") return new(true, id != parentProcessId, false, false);
            if (overlay is null) return new(false, id != parentProcessId, true, false);
            var status = ReadOverlayBounded(overlay);
            return new(status.WindowState is "open" or "closed" or "opening", id != parentProcessId, true, status.WindowState == "open");
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
        return DesktopSuppressionReason().Length == 0;
    }
    internal string DesktopSuppressionReason()
    {
        var systemReason = StarBridge.OverlayRuntime.Windows.WindowsInformationOverlayRuntimeFactory.SystemNotificationSuppressionReason();
        if (systemReason.Length != 0) return systemReason;
        var foreground = GetForegroundWindow();
        bool? appForeground = foreground == IntPtr.Zero || GetWindowThreadProcessId(foreground, out var processId) == 0
            ? null : processId == parentProcessId;
        return StarBridge.HostRuntime.Notifications.DesktopNotificationVisibility.LocalGateReason(
            systemReason, appForeground, _game.ReadCurrentState());
    }
    internal bool CanPlaySocialSound()
    {
        // Foreground chat still has an audible arrival cue when explicitly enabled.
        // Ordinary full-screen apps do not mute an enabled social cue. Keep
        // Windows quiet mode, inactive desktop and unknown game state quiet.
        // A known running game is not itself a reason to mute private/friend
        // cues. Player activity uses a separate, silent desktop-card pipeline.
        if (!StarBridge.OverlayRuntime.Windows.WindowsInformationOverlayRuntimeFactory.SystemAllowsSocialSound()) return false;
        var foreground = GetForegroundWindow();
        return SocialSoundAllowed(true,
            foreground != IntPtr.Zero && GetWindowThreadProcessId(foreground, out _) != 0, _game.ReadCurrentState());
    }
    internal static bool SocialSoundAllowed(bool systemAllows, bool foregroundKnown, string gameState) =>
        systemAllows && foregroundKnown && gameState is "notRunning" or "running";
    internal bool CanNotifyGameIdentity()
    {
        if (!StarBridge.OverlayRuntime.Windows.WindowsInformationOverlayRuntimeFactory.SystemAllowsNotifications()) return false;
        var foreground = GetForegroundWindow();
        if (foreground == IntPtr.Zero || GetWindowThreadProcessId(foreground, out var processId) == 0 ||
            processId == parentProcessId) return false;
        // Identity mismatches arise while the game is running. This typed route
        // permits that known state, never unknown state or OS suppression.
        return _game.ReadCurrentState() is "notRunning" or "running";
    }
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out uint processId);
}
