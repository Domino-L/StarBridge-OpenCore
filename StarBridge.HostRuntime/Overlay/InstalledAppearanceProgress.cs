namespace StarBridge.HostRuntime.Overlay;

/// <summary>Process-local installed appearance progress, never preset data or
/// use eligibility. AccountEpoch is an opaque reference token, not an account ID;
/// a changed token invalidates former admission. Null usage is unknown, not zero.</summary>
public sealed record InstalledAppearanceProgressSnapshot(
    object? AccountEpoch, long? ConfirmedUsageMs, string SyncState);

/// <summary>Nonblocking Host-owned seam. Read does not start accounting/network.
/// Only a normal native owner may Observe eligible visible use; preview/render
/// ticks must not call it. The installed Adapter supplies acquisition policy and
/// authenticated reporting. Native detaches Changed but does not own disposal.</summary>
public interface IInstalledAppearanceProgress
{
    InstalledAppearanceProgressSnapshot Read();
    // Explicit foreground collection query, not accounting or lease creation.
    // Implementations keep pending reports intact and isolate account changes.
    ValueTask RefreshAsync(CancellationToken cancellationToken = default) => ValueTask.CompletedTask;
    void Observe(bool eligibleNormalUse);
    event Action? Changed;
}
