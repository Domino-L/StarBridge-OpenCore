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
    public static StarBridge.HostRuntime.Notifications.IDesktopNotificationSink CreateDesktopNotifications(int parentProcessId) =>
        new StarBridge.Desktop.NativeDesktopNotificationRuntime(parentProcessId);

    public static bool SystemAllowsNotifications() => StarBridge.Desktop.DesktopNotificationEnvironment.SuppressionReason().Length == 0;
    public static string SystemNotificationSuppressionReason()
    {
        var reason = StarBridge.Desktop.DesktopNotificationEnvironment.SuppressionReason();
        return reason.Length == 0 ? "" : StarBridge.Desktop.DesktopNotificationEnvironment.UserReason(reason);
    }
    public static bool SystemAllowsSocialSound() => StarBridge.Desktop.DesktopNotificationEnvironment.SocialSoundSuppressionReason().Length == 0;
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
        Func<InformationOverlayRuntimeWorkspace, InformationOverlayModuleReadResult>? moduleProvider = null) =>
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
            moduleProvider);
}
