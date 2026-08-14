namespace StarBridge.Desktop;

internal static class InGameSnapshotItemIdentity
{
    internal static T[] PreserveEqualInstances<T>(
        IEnumerable<T>? currentItems,
        IReadOnlyList<T> incomingItems)
        where T : class
    {
        ArgumentNullException.ThrowIfNull(incomingItems);

        var current = currentItems?.ToArray() ?? [];
        if (current.Length == 0)
        {
            return incomingItems.Count == 0 ? [] : incomingItems.ToArray();
        }

        var available = new Dictionary<T, Queue<T>>();
        foreach (var item in current)
        {
            if (!available.TryGetValue(item, out var matches))
            {
                matches = new Queue<T>();
                available.Add(item, matches);
            }

            matches.Enqueue(item);
        }

        var resolved = new T[incomingItems.Count];
        for (var index = 0; index < incomingItems.Count; index++)
        {
            var incoming = incomingItems[index];
            resolved[index] = available.TryGetValue(incoming, out var matches) &&
                              matches.Count > 0
                ? matches.Dequeue()
                : incoming;
        }

        if (currentItems is T[] currentArray && currentArray.Length == resolved.Length)
        {
            var unchanged = true;
            for (var index = 0; index < currentArray.Length; index++)
            {
                if (!ReferenceEquals(currentArray[index], resolved[index]))
                {
                    unchanged = false;
                    break;
                }
            }

            if (unchanged)
            {
                return currentArray;
            }
        }

        return resolved;
    }
}
