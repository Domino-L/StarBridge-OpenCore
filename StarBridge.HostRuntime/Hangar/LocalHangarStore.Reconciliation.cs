using StarBridge.Core.Hangar;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Hangar;

/// <summary>Display-only local IDs; opaque pledge identifiers never leave Host.</summary>
public sealed record LocalHangarRemovalGroup(string GroupId, int RequiredCount, IReadOnlyList<string> ShipIds);

public sealed partial class LocalHangarStore
{
    public IReadOnlyList<LocalHangarRemovalGroup> PreviewRemovals(BridgeAccountContext owner, long expectedRevision,
        IReadOnlyList<CollectedHangarShip> observations, bool partial)
    {
        var current = Read(owner);
        if (expectedRevision != current.Revision)
            throw new LocalHangarStoreException("hangar.revision_conflict", "Read the current inventory before reviewing removals.");
        return RemovalGroups(current, observations, partial);
    }

    private static IReadOnlyList<LocalHangarRemovalGroup> RemovalGroups(LocalHangarSnapshot current,
        IReadOnlyList<CollectedHangarShip> observations, bool partial)
    {
        if (partial) return [];
        var counts = observations.GroupBy(s => MatchKey(s.PledgeKey, s.Title, s.Liner)).ToDictionary(g => g.Key, g => g.Count());
        return current.Ships.GroupBy(s => MatchKey(s.PledgeKey, s.Title, s.Liner))
            // If none remain, there is no choice: the whole group left. Single
            // instances also have an unambiguous transition, as before.
            .Where(g => g.Count() > 1 && counts.GetValueOrDefault(g.Key) > 0 && counts[g.Key] < g.Count())
            .Select(g => new LocalHangarRemovalGroup(g.First().Id, g.Count() - counts[g.Key],
                Array.AsReadOnly(g.Select(s => s.Id).ToArray()))).ToArray();
    }
}
