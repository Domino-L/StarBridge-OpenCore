namespace StarBridge.Desktop;

public static class FleetPassiveRefreshPolicy
{
    public static IReadOnlyList<T> PreserveVisibleOrder<T>(
        IEnumerable<T> refreshedItems,
        IReadOnlyList<string> visibleKeys,
        Func<T, string?> keySelector)
    {
        var rankByKey = visibleKeys
            .Select((key, index) => (Key: key?.Trim(), Index: index))
            .Where(entry => !string.IsNullOrWhiteSpace(entry.Key))
            .GroupBy(entry => entry.Key!, StringComparer.OrdinalIgnoreCase)
            .ToDictionary(group => group.Key, group => group.First().Index, StringComparer.OrdinalIgnoreCase);

        return refreshedItems
            .Select((item, index) =>
            {
                var key = keySelector(item)?.Trim();
                return (
                    Item: item,
                    OriginalIndex: index,
                    PreservedRank: !string.IsNullOrWhiteSpace(key) && rankByKey.TryGetValue(key, out var rank)
                        ? rank
                        : int.MaxValue);
            })
            .OrderBy(entry => entry.PreservedRank)
            .ThenBy(entry => entry.OriginalIndex)
            .Select(entry => entry.Item)
            .ToArray();
    }

    public static bool ShouldMerge(
        string? incomingFleetCode,
        DateTimeOffset incomingUpdatedAt,
        string? currentFleetCode,
        DateTimeOffset currentUpdatedAt)
    {
        if (!string.Equals(
                incomingFleetCode?.Trim(),
                currentFleetCode?.Trim(),
                StringComparison.OrdinalIgnoreCase))
        {
            return true;
        }

        return incomingUpdatedAt > currentUpdatedAt;
    }
}
