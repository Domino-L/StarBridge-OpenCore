using StarBridge.HostRuntime.Onboarding;

namespace StarBridge.HostRuntime;

public sealed partial class AccountBridgeRuntime
{
    internal FirstUseBusinessInstallation.OnlineGraph? CaptureInstalledFirstUseGraph(FirstUseModeRuntime mode,
        PreparedFirstUseOnlineCandidate candidate) => _firstUseInstallation?.CaptureRecoveryGraph(mode, candidate);

    internal sealed partial class FirstUseBusinessInstallation
    {
        // Capture provenance once, under the same gate that registers the Native
        // receipt. Live validation never takes this gate from inside mode/Native.
        internal OnlineGraph? CaptureOnlineGraph(FirstUseModeRuntime mode,
            PreparedFirstUseOnlineCandidate candidate)
        {
            lock (_gate)
            {
                if (!IsActive || !_prepared.IsFor(candidate) || _native is not { } native ||
                    !ReferenceEquals(native.Root.FirstUseMode, mode) ||
                    !native.Root.OwnsSuccessfulFirstUseSourcesExit(_sources) ||
                    !native.HasLiveSlotProof(this)) return null;
                return new(this, _prepared, native, _sources);
            }
        }

        // Recovery consumes immutable original provenance even if credential
        // replacement or retirement revoked live business authority. It never
        // grants activation/online commit and still requires actual exits later.
        internal OnlineGraph? CaptureRecoveryGraph(FirstUseModeRuntime mode, PreparedFirstUseOnlineCandidate candidate)
        {
            lock (_gate)
            {
                if (!_prepared.IsFor(candidate) || !ReferenceEquals(_callbacks.Root.FirstUseMode, mode) ||
                    !_callbacks.Root.OwnsSuccessfulFirstUseSourcesExit(_sources)) return null;
                if (_native is { } native)
                    return native.HasOriginalSlotProof(this) ? new(this, _prepared, native, _sources) : null;
                return _callbacks.OwnsOriginalStoppedSlot(_prepared) ? new(this, _prepared, null, _sources, _callbacks) : null;
            }
        }

        internal sealed record OnlineGraph(FirstUseBusinessInstallation Installation,
            PreparedFirstUseBusinessOwner Prepared, NativeAccountRuntimeBinding.InstalledNativeCallbacks? Native,
            Task Sources, NativeAccountRuntimeBinding.PreparedNativeCallbacks? Uninstalled = null)
        {
            internal AccountBridgeRuntime Root => Native?.Root ?? Uninstalled!.Root;
            internal bool IsLive => Native is not null && Installation.IsActive && Native.HasLiveSlotProof(Installation);
            internal bool HasNativeExit => Native?.HasExitedSuccessfully ?? Uninstalled?.HasExitedSuccessfully == true;
            internal Task<bool> RestoreNativeAsync(long epoch) => Native?.RestoreLocalAsync(Prepared, epoch) ??
                Uninstalled!.RestoreLocalAsync(Prepared, epoch);
        }
    }
}
