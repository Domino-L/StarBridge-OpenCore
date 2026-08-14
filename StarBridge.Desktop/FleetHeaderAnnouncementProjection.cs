namespace StarBridge.Desktop;

internal sealed record FleetHeaderAnnouncementPresentation(
    string TitleText,
    string ContentSuffix,
    string AccessibleText);

internal static class FleetHeaderAnnouncementProjection
{
    internal static FleetHeaderAnnouncementPresentation Project(
        string? title,
        string? content,
        bool useChinese)
    {
        var normalizedTitle = NormalizeInline(title);
        if (normalizedTitle.Length == 0)
        {
            var emptyText = useChinese
                ? "暂无公告 · 点击查看"
                : "No bulletin · Open center";
            return new(emptyText, "", emptyText);
        }

        var normalizedContent = NormalizeInline(content);
        if (normalizedContent.Length == 0)
        {
            return new(normalizedTitle, "", normalizedTitle);
        }

        return new(
            normalizedTitle,
            $" · {normalizedContent}",
            string.Join(Environment.NewLine, normalizedTitle, normalizedContent));
    }

    private static string NormalizeInline(string? value) =>
        string.Join(
            " ",
            (value ?? "").Split(
                [' ', '\t', '\r', '\n'],
                StringSplitOptions.RemoveEmptyEntries));
}
