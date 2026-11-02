namespace StarBridge.Desktop.Tests;

internal static class NotificationEnvironmentPolicyTests
{
    internal static void RunAll()
    {
        foreach (var state in new[] { 2, 3, 5, 6, 7 })
        foreach (var game in new[] { "running", "notRunning" }) {
            if (DesktopNotificationEnvironment.EvaluateExecHangarSuppression(state, game, () => "",
                () => "do-not-disturb", () => "foreground-fullscreen") != "")
                throw new Exception("Hangar game/DND exception must permit compact cards and audio on active desktops");
            if (DesktopNotificationEnvironment.EvaluateExecHangarSuppression(state, game, () => "inactive-desktop",
                () => "do-not-disturb", () => "") != "inactive-desktop")
                throw new Exception("Hangar exception must retain locked-desktop safety");
            foreach (var mode in new[] { "notification-mode-unavailable", "notification-mode-unsupported" })
                if (DesktopNotificationEnvironment.EvaluateExecHangarSuppression(state, game, () => "", () => mode, () => "") != mode)
                    throw new Exception("Unknown notification environment cannot grant hangar delivery");
            if (DesktopNotificationEnvironment.EvaluateExecHangarSuppression(state, game, () => "",
                () => "do-not-disturb", () => "foreground-unavailable") != "foreground-unavailable")
                throw new Exception("Compact hangar still requires a known foreground desktop");
        }
        foreach (var state in new[] { 0, 1, 4, 8, -1 })
            if (DesktopNotificationEnvironment.EvaluateExecHangarSuppression(state, "running", () => "",
                () => "do-not-disturb", () => "") == "")
                throw new Exception("Hangar does not bypass presentation, inactive or unknown shell states");
        foreach (var game in new[] { "unknown", "", "future-state" })
            if (DesktopNotificationEnvironment.EvaluateExecHangarSuppression(5, game, () => "", () => "do-not-disturb", () => "") == "")
                throw new Exception("Unknown game observations cannot grant hangar delivery");
        foreach (var mode in new[] { "", "do-not-disturb" }) {
            if (!DesktopNotificationEnvironment.CompactExecHangar("running", mode) ||
                DesktopNotificationEnvironment.CompactExecHangar("notRunning", mode) != (mode == "do-not-disturb"))
                throw new Exception("Only game/DND uses compact hangar; ordinary desktop keeps full detail");
        }
        if (DesktopNotificationEnvironment.EvaluateExecHangarSuppression(5, "notRunning", () => "", () => "", () => "foreground-fullscreen") != "foreground-fullscreen")
            throw new Exception("Hangar exception must not allow full cards over unrelated immersive apps");
        if (DesktopNotificationEnvironment.EvaluateExecHangarSuppression(3, "running", () => "", () => "", () => "foreground-fullscreen") != "")
            throw new Exception("Known running game must receive the compact hangar reminder");
        foreach (var state in new[] { 2, 3, 5, 6, 7 })
        {
            if (!DesktopNotificationEnvironment.AchievementDesktopAllowed(state, () => ""))
                throw new Exception("Achievement celebration must survive DND/fullscreen/quiet mode on an active desktop");
            if (DesktopNotificationEnvironment.AchievementDesktopAllowed(state, () => "secure-or-inactive-desktop"))
                throw new Exception("Achievement celebration cannot bypass a locked/secure desktop");
        }
        foreach (var state in new[] { 0, 1, 4, 8, -1 })
            if (DesktopNotificationEnvironment.AchievementDesktopAllowed(state, () => ""))
                throw new Exception("Unknown, unavailable and presentation desktops defer achievement celebration");
        foreach (var state in new[] { 2, 3, 5, 7 })
            if (DesktopNotificationEnvironment.EvaluateActivitySuppression(state, true, () => "", () => "", () => "foreground-fullscreen") != "")
                throw new Exception("An authorized player activity must not be blocked again solely because the game is foreground/fullscreen");
        foreach (var state in new[] { 2, 3, 5, 7 }) {
            if (DesktopNotificationEnvironment.EvaluateActivitySuppression(state, false, () => "", () => "", () => "foreground-fullscreen") == "")
                throw new Exception("Activity exemption must not grant permission over unrelated fullscreen apps");
            if (DesktopNotificationEnvironment.EvaluateActivitySuppression(state, true, () => "inactive-desktop", () => "", () => "") != "inactive-desktop" ||
                DesktopNotificationEnvironment.EvaluateActivitySuppression(state, true, () => "", () => "do-not-disturb", () => "") != "do-not-disturb")
                throw new Exception("Game activity must preserve desktop and Windows quiet protection");
        }
        foreach (var state in new[] { 0, 1, 4, 6, 8, -1 })
            if (DesktopNotificationEnvironment.EvaluateActivitySuppression(state, true, () => "", () => "", () => "") == "")
                throw new Exception("Game activity cannot bypass explicit presentation, quiet time or unknown shell state");
        foreach (var surface in new[] { "Progman", "WorkerW", "Shell_TrayWnd", "Shell_SecondaryTrayWnd" })
            if (!DesktopNotificationEnvironment.IsDesktopSurface(surface)) throw new Exception("Desktop surface misclassified");
        if (DesktopNotificationEnvironment.IsDesktopSurface("SDL_app")) throw new Exception("App must not be treated as desktop");
        foreach (var x in new[] { 0, -2560 }) {
            var monitor = new System.Drawing.Rectangle(x, 0, 2560, 1440);
            if (DesktopNotificationEnvironment.ForegroundBoundsReason(monitor, monitor) != "foreground-fullscreen")
                throw new Exception("Physical fullscreen bounds must suppress cards on either monitor");
            if (DesktopNotificationEnvironment.ForegroundBoundsReason(new(x, 0, 2560, 1392), monitor) != "")
                throw new Exception("Work-area maximized window is not fullscreen");
            if (DesktopNotificationEnvironment.ForegroundBoundsReason(default, monitor) != "foreground-unavailable")
                throw new Exception("Invalid bounds cannot grant visual permission");
        }
        foreach (var game in new[] { "running", "notRunning" }) {
            if (!StarBridge.NativeHost.WindowsNotificationActivity.SocialSoundAllowed(true, true, game))
                throw new Exception("Enabled private/friend sound must survive a known running game: " + game);
            if (StarBridge.NativeHost.WindowsNotificationActivity.SocialSoundAllowed(false, true, game) ||
                StarBridge.NativeHost.WindowsNotificationActivity.SocialSoundAllowed(true, false, game))
                throw new Exception("Game sound permission must not bypass system or foreground safety");
        }
        foreach (var game in new[] { "unknown", "", "future-state" })
            if (StarBridge.NativeHost.WindowsNotificationActivity.SocialSoundAllowed(true, true, game))
                throw new Exception("Unknown game state must not grant social sound permission");
        foreach (var state in new[] { 2, 3, 5, 7 }) {
            var sound = DesktopNotificationEnvironment.EvaluateSuppression(state, true, () => "", () => "");
            if (sound != "") throw new Exception($"Enabled social sound must survive full-screen shell state {state}: {sound}");
            foreach (var reason in new[] { "do-not-disturb", "notification-mode-unavailable", "notification-mode-unsupported" })
                if (DesktopNotificationEnvironment.EvaluateSuppression(state, true, () => "", () => reason) != (state == 5 ? reason : ""))
                    throw new Exception("Full-screen social audio is independent of visual mode; ordinary desktop still honors it");
            if (DesktopNotificationEnvironment.EvaluateSuppression(state, true, () => "inactive-desktop", () => "") != "inactive-desktop")
                throw new Exception("Full-screen sound must not bypass desktop safety");
            var visual = DesktopNotificationEnvironment.EvaluateSuppression(state, false, () => "", () => "", () => "");
            if ((visual == "") != (state is 2 or 5)) throw new Exception("Ordinary minimized desktop Busy must not alone suppress a card: " + visual);
        }
        foreach (var state in new[] { 2, 5 }) {
            foreach (var reason in new[] { "foreground-fullscreen", "foreground-unavailable" })
                if (DesktopNotificationEnvironment.EvaluateSuppression(state, false, () => "", () => "", () => reason) != reason)
                    throw new Exception("Visual must verify foreground even when shell accepts notifications");
            foreach (var reason in new[] { "do-not-disturb", "notification-mode-unavailable" })
                if (DesktopNotificationEnvironment.EvaluateSuppression(state, false, () => "", () => reason, () => "") != reason)
                    throw new Exception("Busy override must preserve notification mode");
            if (DesktopNotificationEnvironment.EvaluateSuppression(state, false, () => "inactive-desktop", () => "", () => "") != "inactive-desktop")
                throw new Exception("Busy override must preserve locked desktop gate");
        }
        foreach (var state in new[] { 0, 1, 4, 6, 8, -1 })
            if (DesktopNotificationEnvironment.EvaluateSuppression(state, true,
                () => throw new Exception("Blocked state passed desktop gate"), () => "") == "")
                throw new Exception("Explicit quiet/presentation/unknown states must remain blocked");
    }
}
