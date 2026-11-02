namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    private readonly object _participantLoopGate = new();
    private bool _participantLoopEnabled;
    private CancellationTokenSource? _participantLoopCancellation;
    private TimeSpan _participantLoopInterval = TimeSpan.FromMinutes(1);
    internal Task ParticipantLoopCompletion { get; private set; } = Task.CompletedTask;
    private Task _participantLoopStopCompletion = Task.CompletedTask;
    private TaskCompletionSource _participantLoopWake = new(TaskCreationOptions.RunContinuationsAsynchronously);

    // Ends the current wait. The loop still applies all its own owner checks.
    private void WakeParticipantLoop()
    {
        TaskCompletionSource woken;
        lock (_participantLoopGate) {
            woken = _participantLoopWake;
            _participantLoopWake = new(TaskCreationOptions.RunContinuationsAsynchronously);
        }
        woken.TrySetResult();
    }

    internal void EnableParticipantSynchronization(TimeSpan? interval = null)
    {
        lock (_participantLoopGate) {
            if (interval is { } value) {
                if (value <= TimeSpan.Zero) throw new ArgumentOutOfRangeException(nameof(interval));
                _participantLoopInterval = value;
            }
            _participantLoopEnabled = true;
            EnsureParticipantLoop();
        }
    }

    private void StopParticipantLoop()
    {
        lock (_participantLoopGate) {
            if (_participantLoopCancellation is not null)
                _participantLoopStopCompletion = Task.WhenAll(_participantLoopStopCompletion, ParticipantLoopCompletion);
            _participantLoopCancellation?.Cancel();
            _participantLoopCancellation = null;
        }
    }

    private void EnsureParticipantLoop()
    {
        lock (_participantLoopGate) {
            if (IsBusinessStartupDeferred || !_participantLoopEnabled || _disposed || _localModeSessionLoopsStopped || _session is null || GameplayTimeContext is not { } owner ||
                _participantLoopCancellation is not null) return;
            var generation = Generation;
            var cancellation = new CancellationTokenSource();
            _participantLoopCancellation = cancellation;
            ParticipantLoopCompletion = Task.Run(async () => {
                var token = cancellation.Token;
                try {
                    while (!token.IsCancellationRequested && !_disposed && generation == Generation && GameplayTimeContext == owner) {
                        // Taken before enrolling, so a wake during this round is not lost.
                        Task wake;
                        lock (_participantLoopGate) wake = _participantLoopWake.Task;
                        await EnsureLocalDataOwnerAsync(token).ConfigureAwait(false);
                        await EnsureParticipantEnrollmentAsync(token, waitForMutation: true).ConfigureAwait(false);
                        await Task.WhenAny(Task.Delay(_participantLoopInterval, token), wake).ConfigureAwait(false);
                        token.ThrowIfCancellationRequested();
                    }
                }
                catch (OperationCanceledException) when (token.IsCancellationRequested) { }
                catch (ObjectDisposedException) when (_disposed) { }
                finally {
                    lock (_participantLoopGate) {
                        if (ReferenceEquals(_participantLoopCancellation, cancellation)) _participantLoopCancellation = null;
                        cancellation.Dispose();
                    }
                }
            });
        }
    }
}
