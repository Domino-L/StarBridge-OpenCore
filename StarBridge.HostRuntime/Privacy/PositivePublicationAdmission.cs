namespace StarBridge.HostRuntime.Privacy;

// Lock order: publication _gate -> positive admission -> store file lock.
// Store-only commits take admission -> file lock, then release BOTH before
// waking/awaiting publication. Never wait for _gate while holding admission.
// Writers hold admission from final revalidation through HTTP completion;
// directory reads, OAuth refresh and retries acquire a new lease separately.
internal sealed class PositivePublicationAdmission
{
    private readonly SemaphoreSlim _gate = new(1, 1);
    internal TimeSpan WaitTimeout { get; set; } = TimeSpan.FromSeconds(20);
    internal async Task<IDisposable> EnterAsync(CancellationToken token)
    {
        if (!await _gate.WaitAsync(WaitTimeout, token).ConfigureAwait(false))
            throw new TimeoutException("Positive publication admission timed out.");
        return new Lease(_gate);
    }
    private sealed class Lease(SemaphoreSlim gate) : IDisposable
    {
        private SemaphoreSlim? _gate = gate;
        public void Dispose() => Interlocked.Exchange(ref _gate, null)?.Release();
    }
}
