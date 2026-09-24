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
    public static IInformationOverlayRuntime Create(
        Func<GameLogSessionSnapshot> sessionProvider,
        Func<IReadOnlyList<string>>? entitlementProvider = null,
        Func<InformationOverlayRoomContent?>? roomProvider = null,
        Func<InformationOverlayCommunityContent?>? communityProvider = null,
        Func<string?>? sceneModeProvider = null,
        Func<string?>? languageProvider = null) =>
        new StarBridge.Desktop.NativeInformationOverlayRuntime(
            sessionProvider,
            entitlementProvider,
            roomProvider,
            communityProvider,
            sceneModeProvider,
            languageProvider);
}
