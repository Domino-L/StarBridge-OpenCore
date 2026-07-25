namespace StarBridge.Core.FleetAnnouncements;

public static class FleetAnnouncementStates
{
    public const string Published = "Published";
    public const string Archived = "Archived";
    public const string Withdrawn = "Withdrawn";
}

public sealed record FleetAnnouncementAuthorContract(
    string AccountId,
    string Callsign,
    string GameId,
    string RoleTitle,
    string RoleColor,
    string? AvatarImageData = null);

public sealed record FleetAnnouncementContract(
    string Id,
    string FleetCode,
    string Title,
    string Content,
    string State,
    int Revision,
    DateTimeOffset PublishedAt,
    DateTimeOffset UpdatedAt,
    FleetAnnouncementAuthorContract Author,
    FleetAnnouncementAuthorContract LastEditor,
    DateTimeOffset? ArchivedAt = null,
    DateTimeOffset? WithdrawnAt = null)
{
    public bool IsPublished => State.Equals(FleetAnnouncementStates.Published, StringComparison.OrdinalIgnoreCase);
}

public sealed record FleetAnnouncementTimelineContract(
    string FleetCode,
    FleetAnnouncementContract? Current,
    FleetAnnouncementContract[] History,
    long Revision,
    bool CanManage,
    DateTimeOffset RefreshedAt);

public sealed record FleetAnnouncementPublishRequestContract(
    string FleetCode,
    string? Title,
    string? Content,
    string ClientRequestId);

public sealed record FleetAnnouncementEditRequestContract(
    string FleetCode,
    string AnnouncementId,
    int ExpectedRevision,
    string? Title,
    string? Content,
    string ClientRequestId);

public sealed record FleetAnnouncementWithdrawRequestContract(
    string FleetCode,
    string AnnouncementId,
    int ExpectedRevision,
    string ClientRequestId);

public sealed record FleetAnnouncementMutationResponseContract(
    FleetAnnouncementTimelineContract? Timeline,
    string Status,
    string? Error = null);

public static class FleetAnnouncementPolicy
{
    public const int MaximumTitleLength = 48;
    public const int MaximumContentLength = 1200;
    public const int MaximumRetainedAnnouncements = 100;

    public static (string Title, string Content, string? Error) Normalize(string? title, string? content)
    {
        var normalizedTitle = (title ?? "").Trim();
        var normalizedContent = (content ?? "")
            .Replace("\r\n", "\n", StringComparison.Ordinal)
            .Replace('\r', '\n')
            .Trim();
        if (normalizedTitle.Length == 0)
        {
            return (normalizedTitle, normalizedContent, "请输入公告标题。");
        }

        if (normalizedTitle.Length > MaximumTitleLength)
        {
            return (normalizedTitle, normalizedContent, $"公告标题不能超过 {MaximumTitleLength} 个字符。");
        }

        if (normalizedContent.Length > MaximumContentLength)
        {
            return (normalizedTitle, normalizedContent, $"公告正文不能超过 {MaximumContentLength} 个字符。");
        }

        return (normalizedTitle, normalizedContent, null);
    }

    public static string NormalizeRequestId(string? value) =>
        string.IsNullOrWhiteSpace(value) ? "" : value.Trim();
}
