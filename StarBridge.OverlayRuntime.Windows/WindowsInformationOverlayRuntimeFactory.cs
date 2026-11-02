namespace StarBridge.OverlayRuntime.Windows;

using StarBridge.HostRuntime.Overlay;
using StarBridge.HostRuntime.Presence;

/// <summary>
/// Windows platform boundary for the native information overlay. The headless
/// Host depends only on the runtime contract and asks this platform plug-in for
/// the Windows implementation.
/// </summary>
public static class WindowsInformationOverlayRuntimeFactory
{
    public static StarBridge.HostRuntime.Overlay.GameStartupSession ReadGameStartupSession()
    {
        try
        {
            var ids = new HashSet<int>();
            foreach (var name in new[] { "StarCitizen", "StarCitizen_LIVE", "StarCitizen_PTUR", "StarCitizen_EPTU", "StarCitizen_HOTFIX", "StarCitizen_TECH-PREVIEW" })
                foreach (var process in System.Diagnostics.Process.GetProcessesByName(name))
                    using (process) ids.Add(process.Id);
            return ids.Count == 0 ? new("notRunning") : ids.Count == 1 ? new("running", ids.Single()) : new("unknown");
        }
        catch { return new("unknown"); }
    }
    public static StarBridge.HostRuntime.Notifications.IDesktopNotificationSink CreateDesktopNotifications(int parentProcessId) =>
        new StarBridge.Desktop.NativeDesktopNotificationRuntime(parentProcessId);

    public static bool SystemAllowsNotifications() => StarBridge.Desktop.DesktopNotificationEnvironment.SuppressionReason().Length == 0;
    public static string SystemNotificationSuppressionReason()
    {
        var reason = StarBridge.Desktop.DesktopNotificationEnvironment.SuppressionReason();
        return reason.Length == 0 ? "" : StarBridge.Desktop.DesktopNotificationEnvironment.UserReason(reason);
    }
    public static bool SystemAllowsSocialSound() => StarBridge.Desktop.DesktopNotificationEnvironment.SocialSoundSuppressionReason().Length == 0;
    public static string SystemTradeSuppressionReason() =>
        StarBridge.Desktop.DesktopNotificationEnvironment.TradeSuppressionReason();
    public static bool SystemAllowsExecHangar(string gameState) =>
        StarBridge.Desktop.DesktopNotificationEnvironment.ExecHangarSuppressionReason(gameState).Length == 0;
    public static IInformationOverlayRuntime Create(
        Func<GameLogSessionSnapshot> sessionProvider,
        Func<IReadOnlyList<string>>? entitlementProvider = null,
        Func<InformationOverlayRoomContent?>? roomProvider = null,
        Func<InformationOverlayCommunityContent?>? communityProvider = null,
        Func<string?>? sceneModeProvider = null,
        Func<string?>? languageProvider = null,
        Func<InformationOverlayRosterPreferences>? rosterPreferences = null,
        Func<LocalGamePresenceSnapshot>? localPresenceProvider = null,
        Func<CancellationToken, Task>? prepareCommunity = null,
        Func<InformationOverlayRuntimeWorkspace, InformationOverlayModuleReadResult>? moduleProvider = null,
        string? installedAppearanceDataRoot = null,
        IInstalledAppearanceProgress? installedAppearanceProgress = null,
        IInformationOverlayLocalSource? localSource = null) =>
        new StarBridge.Desktop.NativeInformationOverlayRuntime(
            sessionProvider,
            entitlementProvider,
            roomProvider,
            communityProvider,
            sceneModeProvider,
            languageProvider,
            rosterPreferences,
            localPresenceProvider,
            prepareCommunity,
            moduleProvider,
            installedAppearanceDataRoot,
            installedAppearanceProgress,
            localSource);
}
