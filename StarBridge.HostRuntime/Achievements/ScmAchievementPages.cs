namespace StarBridge.HostRuntime.Achievements;

internal static class ScmAchievementPages
{
    // Max-sized Chinese conditions still fit the existing 1 MiB Bridge frame.
    internal const int Size = 16;
    internal static object Read(ScmAchievementCatalog catalog, int offset, string? snapshotId, bool cached)
    {
        catalog.Validate();
        var id = catalog.ReadAtUtc.ToUniversalTime().ToString("O");
        if (offset < 0 || offset > catalog.Items.Length || offset % Size != 0 ||
            (snapshotId is not null && snapshotId != id) || (offset != 0 && snapshotId is null))
            throw new InvalidOperationException("SCM achievement snapshot changed.");
        var items = catalog.Items.Skip(offset).Take(Size).ToArray();
        return new { schemaVersion = 1, catalog.ReadAtUtc, snapshotId = id, total = catalog.Items.Length,
            offset, nextOffset = offset + items.Length < catalog.Items.Length ? (int?)(offset + items.Length) : null,
            cachedAtUtc = cached ? (DateTimeOffset?)catalog.ReadAtUtc : null, items };
    }
}
