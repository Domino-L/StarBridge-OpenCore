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
                new { schemaVersion = 1, count }), announcements: notifications.CreateAnnouncementObserver());
        _communityNotifications.ObserveAccount();
        _host.AccountChanged += InvalidateCommunityNotifications;
        if (_host is Account.ScmAccountBridgeHost source) {
            source.NotificationMembershipChanged += InvalidateOrganizationNotifications;
            source.FleetMembershipObserved += ObserveNotificationOfficialMembership;
            source.CommunityDirectoryObserved += ConfirmNotificationCommunityDirectory;
            source.CommunityRosterRevoked += RevokeNotificationCommunity;
        }
        if (!_firstUseCandidate) _communityNotifications.Start();
        return true;
    }
    private void ConfirmNotificationCommunityDirectory(StarBridge.NativeBridge.BridgeAccountContext owner, long generation,
        long sequence, DateTimeOffset startedAt, IReadOnlyList<Overlay.InformationOverlayCommunityContent> rosters)
    {
        if (!_disposed) _communityNotifications?.ConfirmCommunityDirectory(owner, generation, rosters.Select(row => row.Code));
    }
    private void RevokeNotificationCommunity(StarBridge.NativeBridge.BridgeAccountContext owner, long generation, long sequence, string code)
    {
        if (!_disposed) _communityNotifications?.RevokeCommunity(owner, generation, code);
    }
    private void InvalidateCommunityNotifications(long _) {
        if (_disposed) return;
        _communityNotifications?.ObserveAccount();
        _communityNotifications?.Invalidate();
    }
    private void ObserveNotificationOfficialMembership(StarBridge.NativeBridge.BridgeAccountContext owner, long generation, string? source)
    {
        if (!_disposed) _communityNotifications?.ObserveOfficialMembership(owner, generation, source);
    }
    private void InvalidateOrganizationNotifications(StarBridge.NativeBridge.BridgeAccountContext owner, long generation)
    {
        if (!_disposed && GameplayOwner() == (owner, generation)) _communityNotifications?.Invalidate();
    }
}
