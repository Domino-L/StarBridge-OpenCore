namespace StarBridge.HostRuntime.Account;

// Existing account mutations remain exclusive. Independent sharing work uses
// the bounded read lane; a pending mutation closes admission to new work.
internal sealed class AccountMutationGate(Action? onExclusiveEntered = null) : IDisposable
{
    private readonly AccountDispatchGate _gate = new();
    private IAsyncDisposable? _exclusive;

    internal ValueTask<IAsyncDisposable> EnterSharedAsync(CancellationToken token) => _gate.EnterAsync(true, token);
    internal async Task WaitAsync(CancellationToken token = default)
    {
        _exclusive = await _gate.EnterAsync(false, token).ConfigureAwait(false);
        Entered();
    }
    internal Task<bool> WaitAsync(int milliseconds, CancellationToken token) =>
        WaitAsync(TimeSpan.FromMilliseconds(milliseconds), token);
    internal async Task<bool> WaitAsync(TimeSpan timeout, CancellationToken token)
    {
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
        var entering = _gate.EnterAsync(false, deadline.Token);
        if (!entering.IsCompletedSuccessfully) deadline.CancelAfter(timeout);
        try
        {
            _exclusive = await entering.ConfigureAwait(false);
            Entered();
            return true;
        }
        catch (OperationCanceledException) when (!token.IsCancellationRequested) { return false; }
    }
    private void Entered()
    {
        // Recovery owns the exclusive lease before any caller snapshots a
        // session. A failed callback must not strand the mutation barrier.
        try { onExclusiveEntered?.Invoke(); }
        catch { Release(); throw; }
    }
    internal void Release() => Interlocked.Exchange(ref _exclusive, null)?.DisposeAsync().GetAwaiter().GetResult();
    public void Dispose() => _gate.Dispose();
}
