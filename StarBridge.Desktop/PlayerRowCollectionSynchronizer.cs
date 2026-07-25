using System.Collections.ObjectModel;

namespace StarBridge.Desktop;

internal static class PlayerRowCollectionSynchronizer
{
    public static int Synchronize(
        ObservableCollection<PlayerRow> target,
        IReadOnlyList<PlayerRow> source)
    {
        var changes = 0;
        for (var index = 0; index < source.Count; index++)
        {
            var next = source[index];
            if (index < target.Count && HasSameIdentity(target[index], next))
            {
                if (!target[index].Equals(next))
                {
                    target[index] = next;
                    changes++;
                }

                continue;
            }

            var existingIndex = FindIdentity(target, next, index + 1);
            if (existingIndex >= 0)
            {
                target.Move(existingIndex, index);
                changes++;
                if (!target[index].Equals(next))
                {
                    target[index] = next;
                    changes++;
                }

                continue;
            }

            target.Insert(index, next);
            changes++;
        }

        while (target.Count > source.Count)
        {
            target.RemoveAt(target.Count - 1);
            changes++;
        }

        return changes;
    }

    private static int FindIdentity(
        ObservableCollection<PlayerRow> rows,
        PlayerRow candidate,
        int startIndex)
    {
        for (var index = Math.Max(0, startIndex); index < rows.Count; index++)
        {
            if (HasSameIdentity(rows[index], candidate))
            {
                return index;
            }
        }

        return -1;
    }

    private static bool HasSameIdentity(PlayerRow left, PlayerRow right)
    {
        if (!string.IsNullOrWhiteSpace(left.AccountId) &&
            !string.IsNullOrWhiteSpace(right.AccountId))
        {
            return left.AccountId.Equals(right.AccountId, StringComparison.OrdinalIgnoreCase);
        }

        return left.Name.Equals(right.Name, StringComparison.OrdinalIgnoreCase);
    }
}
