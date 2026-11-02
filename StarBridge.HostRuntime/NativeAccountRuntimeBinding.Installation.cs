namespace StarBridge.HostRuntime;

public sealed partial class NativeAccountRuntimeBinding
{
    internal InstalledNativeCallbacks? InstallBusiness(AccountBridgeRuntime.FirstUseBusinessInstallation installation)
    {
        ArgumentNullException.ThrowIfNull(installation);
        return installation.AttachNativeCallbacks(this);
    }

    // Called only under the original installation gate, always before our gate.
    // Control/device dispatchers remain on the retained root, outside this slot.
    internal InstalledNativeCallbacks? InstallCore(AccountBridgeRuntime.FirstUseBusinessInstallation installation,
        PreparedNativeCallbacks callbacks, AccountBridgeRuntime.PreparedFirstUseBusinessOwner prepared, Task sources)
    {
        lock (_gate)
        {
            if (_disposed || !installation.IsActive || !callbacks.AuthorizesActivated(this, prepared, sources)) return null;
            var installed = new Slot(installation.Owner, installation);
            var receipt = new InstalledNativeCallbacks(this, installed, prepared);
            installed.Receipt = receipt;
            installed.Handler = envelope => Publish(installed, envelope);
            installed.Subscribe();
            _current = installed;
            // Real Native admission can precede the durable mode commit. Even
            // cancellation before that commit cannot rewind the pipe's epoch.
            _root.FirstUseMode?.ObserveNativeControlGeneration(installed.Owner.Generation);
            return receipt;
        }
    }

    internal sealed class InstalledNativeCallbacks(NativeAccountRuntimeBinding binding, Slot slot,
        AccountBridgeRuntime.PreparedFirstUseBusinessOwner prepared)
    {
        private Task? _exit;
        internal AccountBridgeRuntime Root => binding._root;
        internal bool HasOriginalSlotProof(AccountBridgeRuntime.FirstUseBusinessInstallation installation)
        {
            lock (binding._gate) return !binding._disposed && ReferenceEquals(binding._current, slot) &&
                ReferenceEquals(slot.Receipt, this) && ReferenceEquals(slot.Installation, installation);
        }
        // No Slot.Active/mode callback: final commit and mode qualification must
        // not recurse, or acquire a mode lock while holding the binding gate.
        internal bool HasLiveSlotProof(AccountBridgeRuntime.FirstUseBusinessInstallation installation)
        {
            lock (binding._gate) return !binding._disposed && ReferenceEquals(binding._current, slot) &&
                ReferenceEquals(slot.Receipt, this) && ReferenceEquals(slot.Installation, installation) &&
                !slot.Work.IsClosed && installation.IsActive;
        }
        internal Task<bool> RestoreLocalAsync(AccountBridgeRuntime.PreparedFirstUseBusinessOwner original, long epoch) =>
            ReferenceEquals(prepared, original) ? binding.RestoreLocalCallbacksAsync(original, epoch) : Task.FromResult(false);
        internal bool HasTransactionAuthority => binding._root.FirstUseMode?.OwnsActivatedBusinessPreparation(prepared) == true;
        internal bool IsFor(NativeAccountRuntimeBinding candidate) => ReferenceEquals(binding, candidate);
        internal bool IsCurrent
        {
            get
            {
                lock (binding._gate) return !binding._disposed && ReferenceEquals(binding._current, slot) &&
                    ReferenceEquals(slot.Receipt, this) && slot.Active && !slot.Work.IsClosed;
            }
        }
        internal bool HasExitedSuccessfully => Volatile.Read(ref _exit)?.IsCompletedSuccessfully == true;
        // Exact captured slot only: late retirement cannot close a recovered
        // local slot. AsyncWorkRetirement owns the one physical drain task.
        internal Task RetireAsync()
        {
            var exit = CloseSlot(slot);
            Interlocked.CompareExchange(ref _exit, exit, null);
            return exit;
        }
    }
}
