namespace StarBridge.Desktop;

public static class FleetSnapshotOrderingPolicy
{
    public static bool ShouldAccept(DateTimeOffset candidateUpdatedAt, DateTimeOffset latestAcceptedUpdatedAt) =>
        candidateUpdatedAt == default ||
        latestAcceptedUpdatedAt == DateTimeOffset.MinValue ||
        candidateUpdatedAt >= latestAcceptedUpdatedAt;
}
