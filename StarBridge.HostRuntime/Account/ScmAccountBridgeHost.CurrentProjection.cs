namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost : IAccountBridgeCurrentProjection
{
    private static readonly TimeSpan CurrentProjectionWindow = TimeSpan.FromSeconds(30);
    private sealed record FullCurrent(AccountBridgeSessionProjection Projection, long At);
    private FullCurrent? _lastFullCurrent;

    // DL-129: answer a repeated current read without the serialized SCM lane
    // only while a recent full read already did every side effect (restore,
    // local-owner check, enrollment, loop starts, display observation), the
    // local owner is still fresh and nothing in the projection has changed.
    // Anything else returns null and takes the ordinary queue.
    public AccountBridgeSessionProjection? TryProjectCurrent()
        => TryProjectCurrent(out _);

    internal AccountBridgeSessionProjection? TryProjectCurrent(out CurrentProjectionReason reason)
    {
        reason = CurrentProjectionReason.none;
        var last = Volatile.Read(ref _lastFullCurrent);
        if (last is null) { reason = CurrentProjectionReason.noLastFull; return null; }
        if (_disposed) { reason = CurrentProjectionReason.hostDisposed; return null; }
        if (_businessStartupDeferred) { reason = CurrentProjectionReason.businessStartupDeferred; return null; }
        if (!_restoreAttempted) { reason = CurrentProjectionReason.restoreNotAttempted; return null; }
        if (_reauthorizationRequired) { reason = CurrentProjectionReason.reauthRequired; return null; }
        if (_credentialTemporarilyUnavailable) { reason = CurrentProjectionReason.credentialTemporary; return null; }
        if (_legacyRestoreUnavailable) { reason = CurrentProjectionReason.legacyUnavailable; return null; }
        if (!Volatile.Read(ref _participantLoopEnabled)) { reason = CurrentProjectionReason.participantLoopOff; return null; }
        var age = LocalDataOwnerClock.GetElapsedTime(last.At);
        if (age < TimeSpan.Zero) { reason = CurrentProjectionReason.ageNegative; return null; }
        if (age >= CurrentProjectionWindow) { reason = CurrentProjectionReason.ageExpired; return null; }
        if (_session is not null && _compatibilityReader is not null)
        {
            var binding = Volatile.Read(ref _localOwnerBinding);
            if (CurrentContext is not { } context) { reason = CurrentProjectionReason.ownerContextMissing; return null; }
            if (binding is null) { reason = CurrentProjectionReason.ownerBindingMissing; return null; }
            if (binding.Authentication != context) { reason = CurrentProjectionReason.ownerAuthenticationChanged; return null; }
            if (binding.Generation != Generation) { reason = CurrentProjectionReason.ownerGenerationChanged; return null; }
            if (!LocalOwnerFresh(binding, TimeSpan.FromMinutes(1))) { reason = CurrentProjectionReason.ownerStale; return null; }
        }
        var projection = ProjectCurrent();
        if (projection == last.Projection) return projection;
        reason = CurrentProjectionReason.projectionChanged;
        return null;
    }
}
