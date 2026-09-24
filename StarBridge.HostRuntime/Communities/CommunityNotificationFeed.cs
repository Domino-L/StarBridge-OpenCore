namespace StarBridge.HostRuntime.Communities;

// Internal notification input. No account ids, command references, attachments
// or read-receipt handles leave the existing authenticated reader.
internal sealed record CommunityNotificationFeed(DateTimeOffset ReceivedAt, CommunityNotificationSource[] Sources);
internal sealed record CommunityNotificationSource(
    string SourceKey, string Name, DateTimeOffset JoinedAt,
    bool ChatAvailable, CommunityNotificationChat? Chat,
    bool ManagementAvailable, CommunityNotificationTask[] Tasks, string PolicyKey = "");
internal sealed record CommunityNotificationChat(
    long Sequence, int Unread, bool Incoming, DateTimeOffset ServerTime,
    DateTimeOffset? CreatedAt, string Callsign, string Text);
internal sealed record CommunityNotificationTask(string Key, DateTimeOffset CreatedAt);
