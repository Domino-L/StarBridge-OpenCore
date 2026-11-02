using StarBridge.HostRuntime.Notifications;

namespace StarBridge.HostRuntime;

public sealed partial class AccountBridgeRuntime
{
    private CommunityNotificationRuntime? _communityNotifications;
    internal (StarBridge.NativeBridge.BridgeAccountContext? Context, long Generation) NativeNotificationOwner => GameplayOwner();
    public IBridgeRequestDispatcher CreateNotificationPolicyDispatcher(NotificationSettingsBridgeDispatcher notifications) =>
        new NotificationPolicyBridgeDispatcher(notifications, this, () => _disposed ? (null, Generation) : GameplayOwner());
    public bool ConfigureCommunityNotifications(NotificationSettingsBridgeDispatcher notifications,
        NotificationAudioBridgeDispatcher? audio = null)
    {
        using var configuration = EnterAccountBusinessConfiguration();
        if (configuration is null) return false;
        if (_communityNotifications != null) throw new InvalidOperationException("Organization notifications already configured.");
        if (_host is not ICommunityNotificationReader reader) return false;
        _communityNotifications = new(reader, () => _disposed ? (null, Generation) : GameplayOwner(), async (notice, token) => {
            if (!token.IsCancellationRequested) audio?.TryPlayCommunity(notice);
            await notifications.PresentCommunityAsync(notice, token);
        }, pendingManagement: (generation, count) =>
            _dispatcher.PublishDomainEvent("notificationSettings.pendingManagement", generation,
                new { schemaVersion = 1, count }));
        _host.AccountChanged += InvalidateCommunityNotifications;
        if (!_firstUseCandidate) _communityNotifications.Start();
        return true;
    }
    private void InvalidateCommunityNotifications(long _) => _communityNotifications?.Invalidate();
}
