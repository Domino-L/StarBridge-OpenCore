using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Notifications;

public sealed partial class NotificationSettingsBridgeDispatcher
{
    private readonly NotificationPolicyStore _policies = new(dataRoot);
    private long _policyEpoch;
    internal AnnouncementNotificationObserver CreateAnnouncementObserver() => new(new(dataRoot), _rallyTime, ReadPolicies);
    internal NotificationPolicySnapshot ReadPolicies(BridgeAccountContext owner) { lock (_gate) return _policies.Read(owner); }
    internal NotificationPolicySnapshot SavePolicies(BridgeAccountContext owner, long revision, string operation,
        NotificationPolicyRule[] rules, Func<bool> current, bool extended = false)
    {
        lock (_gate) {
            ObjectDisposedException.ThrowIf(_disposed, this);
            var result = _policies.Save(owner, revision, operation, rules, current, extended);
            Interlocked.Increment(ref _policyEpoch);
            Interlocked.Increment(ref _directEpoch);
            InvalidateReminder();
            PublishDirectUnread(null, reset: true);
            return result;
        }
    }
    internal async ValueTask PresentCommunityAsync(CommunityNotificationNotice incoming, CancellationToken token)
    {
        DesktopNotification notice;
        lock (_gate) {
            if (_disposed || token.IsCancellationRequested || !incoming.IsCurrent()) return;
            try {
                var source = incoming.Source;
                if (string.IsNullOrWhiteSpace(source.PolicyKey)) return;
                var official = source.SourceKind == OrganizationNotificationSourceKind.OfficialFleet;
                if (!Enum.IsDefined(source.SourceKind) || official != NotificationPolicyStore.IsOfficialFleetKey(source.PolicyKey) ||
                    official && (source.ManagementAvailable || source.Tasks.Length != 0 || source.JoinedAt != null)) return;
                var policies = _policies.Read(incoming.Owner);
                var admittedAt = _rallyTime.GetUtcNow();
                var zone = NotificationOrganizationPolicy.LocalZone(_rallyTime);
                if (!NotificationOrganizationPolicy.AllowsCard(policies.Rule(source.PolicyKey), incoming.Kind, incoming.OccurredAt, admittedAt, zone)) return;
                var settings = Read();
                var management = incoming.Kind == NotificationEventKind.OrganizationManagement;
                var announcement = incoming.Kind == NotificationEventKind.OrganizationAnnouncement;
                if (!settings.WindowsEnabled || desktop == null || !CanNotifySocial(announcement ? "announcement" : management ? "management" : "chat")) return;
                if (announcement ? source.Announcements == null || source.AnnouncementSource == null :
                    management ? !source.ManagementAvailable : incoming.Kind != NotificationEventKind.OrganizationChat || !source.ChatAvailable) return;
                var epoch = Interlocked.Read(ref _directEpoch);
                var policyEpoch = Interlocked.Read(ref _policyEpoch);
                bool Current() => !_disposed && epoch == Interlocked.Read(ref _directEpoch) &&
                    policyEpoch == Interlocked.Read(ref _policyEpoch) && incoming.IsCurrent() &&
                    NotificationOrganizationPolicy.Current(_policies, incoming.Owner, source.PolicyKey, incoming.Kind,
                        policies.SuppressionRevision(source.PolicyKey), admittedAt, zone, _rallyTime, card: true);
                var id = Guid.NewGuid();
                notice = CreateDesktop(id, false, 0, 0, settings, Current) with {
                    RevalidateBeforePresent = announcement ? incoming.Revalidate : null,
                    Community = new(settings.Preview == "hiddenDetails" ? "" : source.Name,
                        settings.Preview == "fullContent" && !management && !announcement ? source.Chat?.Callsign ?? "" : "",
                        settings.Preview == "fullContent" && !management && !announcement ? source.Chat?.Text ?? "" : "", management, source.SourceKind, announcement,
                        announcement ? Math.Clamp(incoming.AnnouncementSummaryCount, 0, 100) : 0),
                    // Announcements redeem a current page reference only after
                    // another authorized read; other events retain their route.
                    Activated = activationEvent == null ? null : () => Activate(id, Current,
                        announcement ? official ? "officialFleetAnnouncements" : "communityAnnouncements" : official ? "officialFleet" : "communities",
                        announcement ? incoming.ReauthorizeActivation : null, announcement ? source.AnnouncementSource : null)
                };
            } catch (Exception e) when (e is IOException or InvalidDataException or UnauthorizedAccessException or System.Text.Json.JsonException or
                Settings.ApplicationPreferencesException) { return; }
        }
        if (notice.IsCurrent()) await desktop!.TryPresentDetailedAsync(notice, token).ConfigureAwait(false);
    }
}
