namespace StarBridge.HostRuntime.Lifecycle;

// Device HTTP remains outside account ownership, but not outside connection
// mode. One original epoch owns admission, cancellation and physical exit.
// Authentication during an explicit pending-online review does not use this
// device gate and never grants general device-network admission.
public sealed class DeviceNetworkAdmission
{
    internal static DeviceNetworkAdmission Unavailable { get; } = new(() => false);
    private readonly Func<bool> _allowed;
    private readonly object _gate = new();
    private AsyncWorkRetirement _epoch = new();
    private TaskCompletionSource? _pause;
    private bool _paused;
    private volatile bool _retired;
    internal DeviceNetworkAdmission(Func<bool> allowed) => _allowed = allowed;

    private bool Allowed()
    { try { return _allowed(); } catch { return false; } }

    public Lease? Enter(CancellationToken token = default)
    {
        token.ThrowIfCancellationRequested();
        lock (_gate)
        {
            if (_retired || !Allowed()) return null;
            if (_paused)
            {
                // Only actual mode readback plus the old physical exit may
                // create another epoch; a resume/login intention is not enough.
                if (_pause?.Task.IsCompletedSuccessfully != true) return null;
                _epoch = new(); _pause = null; _paused = false;
            }
            var work = _epoch.Enter(token);
            return work is null ? null : new(this, work, _epoch);
        }
    }
    internal Task PauseAsync()
    {
        TaskCompletionSource completion;
        AsyncWorkRetirement epoch;
        lock (_gate)
        {
            if (_pause is not null) return _pause.Task;
            _paused = true; epoch = _epoch;
            completion = new(TaskCreationOptions.RunContinuationsAsynchronously);
            _pause = completion;
        }
        _ = Drain(epoch, completion); // Cancellation callbacks never run under _gate.
        return completion.Task;
    }
    private static async Task Drain(AsyncWorkRetirement epoch, TaskCompletionSource completion)
    {
        try { await epoch.Close().ConfigureAwait(false); completion.TrySetResult(); }
        catch (Exception error) { completion.TrySetException(error); }
    }
    internal Task RetireAsync()
    {
        lock (_gate) _retired = true;
        return PauseAsync();
    }
    public sealed class Lease : IDisposable
    {
        private readonly DeviceNetworkAdmission _owner;
        private readonly AsyncWorkRetirement.Lease _work;
        private int _disposed;
        internal Lease(DeviceNetworkAdmission owner, AsyncWorkRetirement.Lease work, object epoch)
        { _owner = owner; _work = work; Epoch = epoch; }
        // Opaque identity of the admission epoch, shared by its successive leases.
        internal object Epoch { get; }
        public CancellationToken Token => _work.Token;
        public bool IsCurrent => Volatile.Read(ref _disposed) == 0 && _work.IsCurrent && !_owner._retired && _owner.Allowed();
        public void RequireCurrent() { if (!IsCurrent) throw new OperationCanceledException(Token); }
        public void Dispose() { if (Interlocked.Exchange(ref _disposed, 1) == 0) _work.Dispose(); }
    }
}
