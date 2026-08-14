namespace StarBridge.Desktop;

internal sealed record FleetHeaderExternalContactEntry(
    string Platform,
    string Value,
    string DisplayText);

internal sealed record FleetHeaderExternalContactPresentation(
    bool IsVisible,
    string InlineText,
    string AccessibleText,
    IReadOnlyList<FleetHeaderExternalContactEntry> Entries);

internal static class FleetHeaderExternalContactProjection
{
    private const int MaximumContactCount = 5;

    internal static FleetHeaderExternalContactPresentation Project(
        bool hasFleet,
        IEnumerable<FleetExternalContactRow> contacts,
        bool useChinese)
    {
        ArgumentNullException.ThrowIfNull(contacts);

        if (!hasFleet)
        {
            return new(false, "", "", []);
        }

        var separator = useChinese ? "：" : ": ";
        var entries = contacts
            .Where(contact =>
                !string.IsNullOrWhiteSpace(contact.Platform) &&
                !string.IsNullOrWhiteSpace(contact.Value))
            .Take(MaximumContactCount)
            .Select(contact =>
            {
                var platform = contact.Platform.Trim();
                var value = contact.Value.Trim();
                return new FleetHeaderExternalContactEntry(
                    platform,
                    value,
                    $"{platform}{separator}{value}");
            })
            .ToArray();

        if (entries.Length == 0)
        {
            var emptyText = useChinese ? "未设置" : "Not configured";
            return new(true, emptyText, emptyText, []);
        }

        return new(
            true,
            string.Join(" · ", entries.Select(entry => entry.DisplayText)),
            string.Join(Environment.NewLine, entries.Select(entry => entry.DisplayText)),
            entries);
    }
}
