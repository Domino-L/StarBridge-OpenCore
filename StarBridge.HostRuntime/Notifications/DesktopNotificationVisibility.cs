namespace StarBridge.HostRuntime.Notifications;

/// Native environment rule only. Player-specific game/overlay privacy is revalidated
/// by its IsCurrent callback; actual foreground/fullscreen is verified by the native OS guard.
public static class DesktopNotificationVisibility
{
    public static string LocalGateReason(string systemReason, bool? appForeground, string gameState)
    {
        if (systemReason.Length != 0) return systemReason;
        if (appForeground is null) return "appActiveOrUnknown";
        if (appForeground.Value) return "appForeground";
        return gameState switch {
            "notRunning" or "running" => "",
            _ => "gameActiveOrUnknown"
        };
    }
    public static string SuppressionReason(DesktopNotification notice, string gameState, bool? appForeground)
    {
        // Process existence cannot distinguish foreground gameplay from an idle
        // desktop with the game in the background. Native OS/foreground guards
        // run before this policy; an uncertain process observation still blocks.
        if (notice.Activity is null && gameState is not ("notRunning" or "running"))
            return "game-active-or-unknown";
        if (!notice.Test && notice.BackgroundOnly && appForeground != false) return "main-window-active-or-unknown";
        return "";
    }
}
