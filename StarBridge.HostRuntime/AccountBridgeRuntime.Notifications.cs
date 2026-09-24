using StarBridge.HostRuntime.Notifications;

namespace StarBridge.HostRuntime;

public sealed partial class AccountBridgeRuntime
{
    private CommunityNotificationRuntime? _communityNotifications;
    public IBridgeRequestDispatcher CreateNotificationPolicyDispatcher(NotificationSettingsBridgeDispatcher notifications) =>
        new NotificationPolicyBridgeDispatcher(notifications, this, () => _disposed ? (null, Generation) : GameplayOwner());
    public bool ConfigureCommunityNotifications(NotificationSettingsBridgeDispatcher notifications)
    {
        if (_communityNotifications != null) throw new InvalidOperationException("Organization notifications already configured.");
        if (_host is not ICommunityNotificationReader reader) return false;
        _communityNotifications = new(reader, () => _disposed ? (null, Generation) : GameplayOwner(), notifications.PresentCommunityAsync);
        _host.AccountChanged += InvalidateCommunityNotifications;
        _communityNotifications.Start();
        return true;
    }
    private void InvalidateCommunityNotifications(long _) => _communityNotifications?.Invalidate();
}
