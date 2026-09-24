namespace StarBridge.HostRuntime.Notifications;

/// Native environment rule only. Player-specific game/overlay privacy is revalidated
/// by its IsCurrent callback; ordinary message cards retain the previous rule.
public static class DesktopNotificationVisibility
{
    public static string SuppressionReason(DesktopNotification notice, string gameState, bool? appForeground)
    {
        if (notice.Activity is null && gameState != "notRunning") return "game-active-or-unknown";
        if (!notice.Test && notice.BackgroundOnly && appForeground != false) return "main-window-active-or-unknown";
        return "";
    }
}
