using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime;

public sealed partial class NativeAccountRuntimeBinding
{
    private RootOfflineCallbacks? _rootOffline;

    internal bool OwnsRoot(AccountBridgeRuntime root) => !_disposed && ReferenceEquals(root, _root);
    public IBridgeRequestDispatcher? CreateModeDispatcher() => _disposed || _root.FirstUseMode is not { } mode
        ? null : new Onboarding.FirstUseModeBridgeDispatcher(mode, this);

    internal RootOfflineCallbacks? CaptureRootOnlineCallbacks(AccountBridgeRuntime root, long generation)
    {
        lock (_gate)
        {
            if (_disposed || !ReferenceEquals(root, _root) || !ReferenceEquals(_current.Owner, root) ||
                _current.Installation is not null || _current.Work.IsClosed || _pending is not null ||
                _rootOffline is not null || root.NativeNotificationOwner.Context is not { } context ||
                !root.CanPreserveRootSession(generation, context)) return null;
            return new(this, _current, generation, context);
        }
    }

    // This immutable provenance covers one ordinary Native slot, not an online
    // installation or a mode receipt. Only its own physical drain may restore it.
    internal sealed class RootOfflineCallbacks
    {
        private readonly NativeAccountRuntimeBinding _binding;
        private readonly Slot _slot;
        private readonly object _exitGate = new();
        private Task? _exit;
        internal long Generation { get; }
        internal BridgeAccountContext Context { get; }
        internal AccountBridgeRuntime Root => _binding._root;
        internal RootOfflineCallbacks(NativeAccountRuntimeBinding binding, Slot slot, long generation,
            BridgeAccountContext context)
        { _binding = binding; _slot = slot; Generation = generation; Context = context; }
        internal bool IsLive => !_binding._disposed && ReferenceEquals(_binding._current, _slot) &&
            !_slot.Work.IsClosed && _binding._pending is null &&
            (_binding._rootOffline is null || ReferenceEquals(_binding._rootOffline, this)) &&
            Root.CanPreserveRootSession(Generation, Context);
        internal bool HasExited => _exit is { IsCompletedSuccessfully: true } && _slot.Work.IsClosed;

        internal Task DrainAsync()
        {
            TaskCompletionSource completion;
            lock (_exitGate)
            {
                if (_exit is not null) return _exit;
                completion = new(TaskCreationOptions.RunContinuationsAsynchronously);
                _exit = completion.Task;
            }
            _ = CompleteAsync(completion);
            return completion.Task;
        }
        private async Task CompleteAsync(TaskCompletionSource completion)
        {
            try
            {
                lock (_binding._gate)
                {
                    // A total Close can already have sealed this exact slot.
                    // Consume its original physical drain, not live permission
                    // to install or acknowledge a now obsolete identity.
                    if (!ReferenceEquals(_binding._current, _slot) || _binding._pending is not null ||
                        _binding._rootOffline is not null && !ReferenceEquals(_binding._rootOffline, this))
                        throw new Onboarding.LocalFirstUseException("firstUse.context_changed");
                    _binding._rootOffline = this;
                }
                await CloseSlot(_slot).ConfigureAwait(false);
                completion.TrySetResult();
            }
            catch (Exception error) { completion.TrySetException(error); }
        }
        internal bool RestoreLocal(long epoch)
        {
            lock (_binding._gate)
            {
                if (_binding._disposed || !HasExited || !ReferenceEquals(_binding._current, _slot) ||
                    !ReferenceEquals(_binding._rootOffline, this) || !Root.HasPreservedRootSessionExit(Generation, Context) ||
                    !Root.HasCurrentFirstUseLocalSources(epoch)) return false;
                var restored = new Slot(Root);
                restored.Handler = envelope => _binding.Publish(restored, envelope);
                restored.Subscribe();
                _binding._current = restored;
                _binding._rootOffline = null;
                return true;
            }
        }
    }
}
