namespace StarBridge.Core.Chat;

public sealed record SequenceHistoryPage<T>(
    T[] Items,
    long LatestSequence,
    long OldestSequence,
    bool HasOlder);

/// <summary>
/// Defines the shared sequence-cursor semantics for every persisted chat surface.
/// </summary>
public static class SequenceHistoryPager
{
    public const int DefaultPageSize = 50;
    public const int MaximumPageSize = 200;

    public static SequenceHistoryPage<T> Page<T>(
        IEnumerable<T>? source,
        Func<T, long> sequenceSelector,
        long afterSequence = 0,
        long beforeSequence = 0,
        int limit = DefaultPageSize)
    {
        ArgumentNullException.ThrowIfNull(sequenceSelector);

        var ordered = (source ?? [])
            .OrderBy(sequenceSelector)
            .ToArray();
        var pageSize = Math.Clamp(limit, 1, MaximumPageSize);
        var after = Math.Max(0, afterSequence);
        var before = Math.Max(0, beforeSequence);

        T[] items;
        if (before > 0)
        {
            items = ordered
                .Where(item => sequenceSelector(item) < before)
                .TakeLast(pageSize)
                .ToArray();
        }
        else if (after > 0)
        {
            items = ordered
                .Where(item => sequenceSelector(item) > after)
                .Take(pageSize)
                .ToArray();
        }
        else
        {
            items = ordered.TakeLast(pageSize).ToArray();
        }

        var latestSequence = ordered.Length == 0
            ? after
            : Math.Max(after, sequenceSelector(ordered[^1]));
        var oldestSequence = items.Length == 0 ? 0 : sequenceSelector(items[0]);
        var hasOlder = oldestSequence > 0 && ordered.Any(item => sequenceSelector(item) < oldestSequence);
        return new SequenceHistoryPage<T>(items, latestSequence, oldestSequence, hasOlder);
    }
}
