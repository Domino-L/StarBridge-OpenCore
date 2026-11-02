using StarBridge.HostRuntime.Notifications;

namespace StarBridge.HostRuntime.Communities;

// Internal notification input. No account ids, command references, attachments
// or read-receipt handles leave the existing authenticated reader.
internal sealed record CommunityNotificationFeed(DateTimeOffset ReceivedAt, CommunityNotificationSource[] Sources,
    bool CommunitiesConfirmed = true)
{
    internal bool IsBounded => Sources.Length <= 65 &&
        Sources.Count(row => row.SourceKind == OrganizationNotificationSourceKind.Community) <= 64 &&
        Sources.Count(row => row.SourceKind == OrganizationNotificationSourceKind.OfficialFleet) <= 1 &&
        Sources.Select(row => row.SourceKey).Distinct(StringComparer.Ordinal).Count() == Sources.Length &&
        Sources.All(row => Enum.IsDefined(row.SourceKind) && row.Tasks.Length <= 10000 &&
            (row.SourceKind != OrganizationNotificationSourceKind.OfficialFleet ||
                row.JoinedAt is null && !row.ManagementAvailable && row.Tasks.Length == 0));
}
internal sealed record CommunityNotificationSource(
    string SourceKey, string Name, DateTimeOffset? JoinedAt,
    bool ChatAvailable, CommunityNotificationChat? Chat,
    bool ManagementAvailable, CommunityNotificationTask[] Tasks, string PolicyKey = "", bool ManagementConfirmed = true,
    OrganizationNotificationSourceKind SourceKind = OrganizationNotificationSourceKind.Community);
internal sealed record CommunityNotificationChat(
    long Sequence, int Unread, bool Incoming, DateTimeOffset ServerTime,
    DateTimeOffset? CreatedAt, string Callsign, string Text);
internal sealed record CommunityNotificationTask(string Key, DateTimeOffset CreatedAt);
