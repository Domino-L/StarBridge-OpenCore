namespace StarBridge.HostRuntime.Account;

/// <summary>
/// A small read lane behind an exclusive mutation barrier. A waiting writer
/// holds admission so new reads cannot indefinitely delay login/logout/writes.
/// </summary>
internal sealed class AccountDispatchGate : IDisposable
{
    private readonly SemaphoreSlim _admission = new(1, 1);
    private readonly SemaphoreSlim _resource = new(1, 1);
    private readonly SemaphoreSlim _readerState = new(1, 1);
    private readonly SemaphoreSlim _readSlots = new(4, 4);
    private int _readers;

    internal async ValueTask<IAsyncDisposable> EnterAsync(bool read, CancellationToken token)
    {
        if (!read)
        {
            await _admission.WaitAsync(token);
            try { await _resource.WaitAsync(token); }
            finally { _admission.Release(); }
            return new Lease(this, false);
        }

        await _readSlots.WaitAsync(token);
        try
        {
            await _admission.WaitAsync(token);
            try
            {
                await _readerState.WaitAsync(token);
                try
                {
                    if (_readers == 0) await _resource.WaitAsync(token);
                    _readers++;
                }
                finally { _readerState.Release(); }
            }
            finally { _admission.Release(); }
            return new Lease(this, true);
        }
        catch { _readSlots.Release(); throw; }
    }

    private async ValueTask ExitAsync(bool read)
    {
        if (!read) { _resource.Release(); return; }
        await _readerState.WaitAsync();
        try { if (--_readers == 0) _resource.Release(); }
        finally { _readerState.Release(); _readSlots.Release(); }
    }

    private sealed class Lease(AccountDispatchGate gate, bool read) : IAsyncDisposable
    {
        private AccountDispatchGate? _gate = gate;
        public ValueTask DisposeAsync() => Interlocked.Exchange(ref _gate, null)?.ExitAsync(read) ?? ValueTask.CompletedTask;
    }

    // The pipe owner drains all request workers before disposing its dispatcher.
    public void Dispose()
    {
        _admission.Dispose();
        _resource.Dispose();
        _readerState.Dispose();
        _readSlots.Dispose();
    }
}
