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

    internal static bool HasSameIdentity(PlayerRow left, PlayerRow right)
    {
        if (!string.IsNullOrWhiteSpace(left.AccountId) &&
            !string.IsNullOrWhiteSpace(right.AccountId))
        {
            return left.AccountId.Equals(right.AccountId, StringComparison.OrdinalIgnoreCase);
        }

        return left.Name.Equals(right.Name, StringComparison.OrdinalIgnoreCase);
    }
}

internal static class FleetMemberRosterOrderPolicy
{
    public static IReadOnlyList<PlayerRow> OrderForDisplay(IReadOnlyList<PlayerRow> source) =>
        source
            .Select((row, index) => new IndexedRow(row, index))
            .OrderBy(item => PresenceRank(item.Row.SharedPresence))
            .ThenBy(item => item.Row.IsFleetCommander ? 0 : 1)
            .ThenBy(item => item.Row.HasFleetPosition ? 0 : 1)
            .ThenBy(item => item.Index)
            .Select(item => item.Row)
            .ToArray();

    public static IReadOnlyList<PlayerRow> PreserveDisplayOrder(
        IReadOnlyList<PlayerRow> current,
        IReadOnlyList<PlayerRow> updated)
    {
        var remaining = updated.ToList();
        var preserved = new List<PlayerRow>(updated.Count);

        foreach (var currentRow in current)
        {
            var matchIndex = remaining.FindIndex(candidate =>
                PlayerRowCollectionSynchronizer.HasSameIdentity(currentRow, candidate));
            if (matchIndex < 0)
            {
                continue;
            }

            preserved.Add(remaining[matchIndex]);
            remaining.RemoveAt(matchIndex);
        }

        preserved.AddRange(remaining);
        return preserved;
    }

    private static int PresenceRank(StarBridge.Core.Presence.PlayerPresenceKind presence) => presence switch
    {
        StarBridge.Core.Presence.PlayerPresenceKind.InGame => 0,
        StarBridge.Core.Presence.PlayerPresenceKind.AppOnline or
            StarBridge.Core.Presence.PlayerPresenceKind.Away => 1,
        _ => 2
    };

    private readonly record struct IndexedRow(PlayerRow Row, int Index);
}
