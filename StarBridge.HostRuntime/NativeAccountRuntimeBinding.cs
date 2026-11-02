using StarBridge.HostRuntime.Lifecycle;
using StarBridge.HostRuntime.Notifications;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime;

// Native callbacks and the account pipe share one installed owner. A callback
// keeps that exact owner/lease through actual exit; a stale callback never looks
// up another owner at completion or relabels its result with a newer generation.
public sealed partial class NativeAccountRuntimeBinding : IBridgeRequestDispatcher, IAsyncDisposable
{
    private readonly object _gate = new();
    private readonly AccountBridgeRuntime _root;
    private Slot _current;
    private Task<PreparedNativeCallbacks?>? _preparation;
    private AccountBridgeRuntime.PreparedFirstUseBusinessOwner? _pending;
    private bool _disposed;

    internal sealed class Slot(AccountBridgeRuntime owner, AccountBridgeRuntime.FirstUseBusinessInstallation? installation = null)
    {
        internal AccountBridgeRuntime Owner { get; } = owner;
        internal AsyncWorkRetirement Work { get; } = new();
        internal Action<BridgeEnvelope>? Handler;
        internal AccountBridgeRuntime.FirstUseBusinessInstallation? Installation { get; } = installation;
        internal InstalledNativeCallbacks? Receipt;
        internal bool Active => Installation is null || Installation.IsActive && Receipt?.HasTransactionAuthority == true;
        internal IBridgeRequestDispatcher Dispatcher => Installation is null ? Owner : Installation;
        internal void Subscribe()
        {
            if (Installation is null) Owner.EventReady += Handler;
            else Installation.EventReady += Handler;
        }
        internal void Unsubscribe()
        {
            if (Installation is null) Owner.EventReady -= Handler;
            else Installation.EventReady -= Handler;
        }
    }

    public NativeAccountRuntimeBinding(AccountBridgeRuntime owner)
    {
        ArgumentNullException.ThrowIfNull(owner);
        _root = owner;
        _current = new(owner);
        var slot = _current;
        slot.Handler = envelope => Publish(slot, envelope);
        slot.Subscribe();
    }

    public event Action<BridgeEnvelope>? EventReady;
    public long Generation => Read(owner => _root.FirstUseMode?.ControlGeneration ?? owner.Generation, -1L);

    private (Slot Slot, AsyncWorkRetirement.Lease? Lease) Enter(CancellationToken token)
    {
        lock (_gate) return (_current, _disposed || !_current.Active ? null : _current.Work.Enter(token));
    }
    private bool Current(Slot slot, AsyncWorkRetirement.Lease work)
    {
        lock (_gate) return !_disposed && ReferenceEquals(_current, slot) && slot.Active && work.IsCurrent;
    }

    public T Read<T>(Func<AccountBridgeRuntime, T> read, T unavailable)
    {
        ArgumentNullException.ThrowIfNull(read);
        var (slot, admitted) = Enter(default); using var work = admitted;
        if (work is null) return unavailable;
        var generation = slot.Owner.Generation;
        var result = read(slot.Owner);
        return Current(slot, work) && slot.Owner.Generation == generation ? result : unavailable;
    }

    public async Task<T> ReadAsync<T>(Func<AccountBridgeRuntime, CancellationToken, Task<T>> read,
        CancellationToken token = default)
    {
        ArgumentNullException.ThrowIfNull(read);
        var (slot, admitted) = Enter(token); using var work = admitted;
        if (work is null) throw new OperationCanceledException("Native account callbacks have stopped.");
        var generation = slot.Owner.Generation;
        var result = await read(slot.Owner, work.Token).ConfigureAwait(false);
        if (!Current(slot, work) || slot.Owner.Generation != generation)
            throw new OperationCanceledException("Native account callback ownership has changed.");
        return result;
    }

    public Task RunAsync(Func<AccountBridgeRuntime, CancellationToken, Task> run, CancellationToken token = default) =>
        ReadAsync(async (owner, cancellation) => { await run(owner, cancellation).ConfigureAwait(false); return 0; }, token);

    // These events retain the original dispatcher's sequence source. A stale
    // captured generation is rejected, not stamped as a current account event.
    private BridgeEnvelope NativeEvent(long generation, object payload,
        Func<AccountBridgeRuntime, long, object, BridgeEnvelope> create) =>
        Read(owner => generation == owner.Generation ? create(owner, generation, payload) : null, (BridgeEnvelope?)null)
        ?? throw new OperationCanceledException("Native account event ownership has changed.");
    public BridgeEnvelope NotificationActivation(long generation, object payload) =>
        NativeEvent(generation, payload, (owner, value, body) => owner.NotificationActivation(value, body));
    public BridgeEnvelope SocialNotification(long generation, object payload) =>
        NativeEvent(generation, payload, (owner, value, body) => owner.SocialNotification(value, body));
    public BridgeEnvelope HostEvent(long generation, string name, object payload) =>
        NativeEvent(generation, payload, (owner, value, body) => owner.HostEvent(value, name, body));
    public BridgeEnvelope MenuHotkeyIntent(long generation, object payload) =>
        NativeEvent(generation, payload, (owner, value, body) => owner.MenuHotkeyIntent(value, body));
    public BridgeEnvelope UpdateProgress(long generation, object payload) =>
        NativeEvent(generation, payload, (owner, value, body) => owner.UpdateProgress(value, body));

    public IBridgeRequestDispatcher CreateNotificationPolicyDispatcher(NotificationSettingsBridgeDispatcher notifications) =>
        new NotificationPolicyBridgeDispatcher(notifications, this,
            () => Read(owner => owner.NativeNotificationOwner, (Context: (BridgeAccountContext?)null, Generation: -1L)));

    public async ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(request);
        Slot slot; AsyncWorkRetirement.Lease? admitted;
        try { (slot, admitted) = Enter(cancellationToken); }
        catch (OperationCanceledException) { return new(BridgeEnvelope.CancelledResponse(request), []); }
        using var work = admitted;
        if (work is null) return new(BridgeEnvelope.CancelledResponse(request), []);
        try
        {
            var result = await slot.Dispatcher.DispatchAsync(request, work.Token).ConfigureAwait(false);
            // Login/restore may legitimately advance this same owner's generation.
            // The original account dispatcher owns that check; slot identity and
            // actual exit admission, not a copied generation, fence pipe replies.
            return Current(slot, work) ? result : new(BridgeEnvelope.CancelledResponse(request), []);
        }
        catch (OperationCanceledException) { return new(BridgeEnvelope.CancelledResponse(request), []); }
    }

    private void Publish(Slot slot, BridgeEnvelope envelope)
    {
        AsyncWorkRetirement.Lease? admitted;
        lock (_gate)
        {
            if (_disposed || !ReferenceEquals(_current, slot) || !slot.Active) return;
            admitted = slot.Work.Enter(default);
        }
        using var work = admitted;
        if (work is null || envelope.SessionGeneration != slot.Owner.Generation || !Current(slot, work)) return;
        EventReady?.Invoke(envelope);
    }

    private Task CloseCallbacks()
    {
        Slot slot;
        lock (_gate) slot = _current;
        return slot.Receipt?.RetireAsync() ?? CloseSlot(slot);
    }
    private static Task CloseSlot(Slot slot)
    {
        var drained = slot.Work.Close();
        slot.Unsubscribe();
        return drained;
    }

    // This receipt covers only these actual Native callback/event/pipe leases.
    // It is not an online installation, sampler exit, business activation or
    // onboarding completion receipt. No bridge command or public setter exists.
    internal Task<PreparedNativeCallbacks?> PrepareHandoffAsync(AccountBridgeRuntime.PreparedFirstUseBusinessOwner prepared,
        CancellationToken token = default)
    {
        ArgumentNullException.ThrowIfNull(prepared);
        token.ThrowIfCancellationRequested();
        Task<PreparedNativeCallbacks?> pending;
        TaskCompletionSource<PreparedNativeCallbacks?> completion;
        Slot slot;
        lock (_gate)
        {
            if (_disposed || _rootOffline is not null || _root.FirstUseMode?.OwnsBusinessPreparation(prepared) != true)
                return Task.FromResult<PreparedNativeCallbacks?>(null);
            if (_preparation is not null)
                return ReferenceEquals(_pending, prepared) ? _preparation.WaitAsync(token) : Task.FromResult<PreparedNativeCallbacks?>(null);
            _pending = prepared;
            slot = _current;
            completion = new(TaskCreationOptions.RunContinuationsAsynchronously);
            pending = _preparation = completion.Task;
        }
        // Reserve the one physical drain under the lock, but run cancellation
        // outside it. Native cancellation callbacks may synchronously ask a
        // different thread to read this binding; that thread must not deadlock.
        _ = CompletePreparationAsync(prepared, slot, completion);
        return pending.WaitAsync(token);
    }

    private async Task CompletePreparationAsync(AccountBridgeRuntime.PreparedFirstUseBusinessOwner prepared,
        Slot slot, TaskCompletionSource<PreparedNativeCallbacks?> completion)
    {
        try { completion.TrySetResult(await PrepareCoreAsync(prepared, slot).ConfigureAwait(false)); }
        catch (Exception error) { completion.TrySetException(error); }
    }

    private async Task<PreparedNativeCallbacks?> PrepareCoreAsync(AccountBridgeRuntime.PreparedFirstUseBusinessOwner prepared, Slot slot)
    {
        var drained = CloseCallbacks();
        await drained.ConfigureAwait(false);
        var result = PreparedNativeCallbacks.Create(this, slot, prepared, drained);
        return result;
    }

    internal sealed class PreparedNativeCallbacks
    {
        private readonly NativeAccountRuntimeBinding _binding;
        private readonly Slot _slot;
        private readonly AccountBridgeRuntime.PreparedFirstUseBusinessOwner _prepared;
        private readonly Task _drained;
        private PreparedNativeCallbacks(NativeAccountRuntimeBinding binding, Slot slot,
            AccountBridgeRuntime.PreparedFirstUseBusinessOwner prepared, Task drained)
        { _binding = binding; _slot = slot; _prepared = prepared; _drained = drained; }
        internal AccountBridgeRuntime Root => _binding._root;
        internal bool HasExitedSuccessfully => _slot.Work.IsClosed && _drained.IsCompletedSuccessfully;
        internal bool OwnsOriginalStoppedSlot(AccountBridgeRuntime.PreparedFirstUseBusinessOwner original)
        {
            lock (_binding._gate) return !_binding._disposed && ReferenceEquals(_prepared, original) &&
                ReferenceEquals(_binding._pending, original) && ReferenceEquals(_binding._current, _slot) &&
                _binding._preparation is { IsCompletedSuccessfully: true } preparation &&
                ReferenceEquals(preparation.Result, this) && HasExitedSuccessfully;
        }
        internal Task<bool> RestoreLocalAsync(AccountBridgeRuntime.PreparedFirstUseBusinessOwner original, long epoch) =>
            ReferenceEquals(_prepared, original) ? _binding.RestoreLocalCallbacksAsync(original, epoch) : Task.FromResult(false);
        internal static PreparedNativeCallbacks? Create(NativeAccountRuntimeBinding binding, Slot slot,
            AccountBridgeRuntime.PreparedFirstUseBusinessOwner prepared, Task drained)
        {
            var result = new PreparedNativeCallbacks(binding, slot, prepared, drained);
            return result.IsCurrent ? result : null;
        }
        internal bool IsCurrent
        {
            get
            {
                lock (_binding._gate) return !_binding._disposed && ReferenceEquals(_binding._current, _slot) &&
                    ReferenceEquals(_binding._pending, _prepared) && _slot.Work.IsClosed && _drained.IsCompletedSuccessfully &&
                    _binding._root.FirstUseMode?.OwnsBusinessPreparation(_prepared) == true;
            }
        }
        internal bool Authorizes(AccountBridgeRuntime.PreparedFirstUseBusinessOwner prepared, Task localSourcesExit) =>
            ReferenceEquals(_prepared, prepared) && IsCurrent &&
            _binding._root.OwnsSuccessfulFirstUseSourcesExit(localSourcesExit);

        internal bool AuthorizesActivated(NativeAccountRuntimeBinding binding,
            AccountBridgeRuntime.PreparedFirstUseBusinessOwner prepared, Task sources) =>
            ReferenceEquals(_binding, binding) && ReferenceEquals(_prepared, prepared) &&
            ReferenceEquals(binding._current, _slot) && ReferenceEquals(binding._pending, prepared) &&
            binding._preparation is { IsCompletedSuccessfully: true } preparation && ReferenceEquals(preparation.Result, this) &&
            _slot.Work.IsClosed && _drained.IsCompletedSuccessfully &&
            binding._root.OwnsSuccessfulFirstUseSourcesExit(sources) &&
            binding._root.FirstUseMode?.OwnsActivatedBusinessPreparation(prepared) == true;
    }

    public Task<bool> StopPrivacyPublicationAsync(CancellationToken token = default)
    {
        Slot slot; lock (_gate) slot = _current;
        return slot.Owner.StopPrivacyPublicationAsync(token);
    }
    // Native composition drains before synchronous Composite/device disposal.
    // Closing callback admission does not itself dispose the account or claim
    // that publication, session loops or a business handoff have completed.
    public Task DrainCallbacksAsync() => CloseCallbacks();
}
