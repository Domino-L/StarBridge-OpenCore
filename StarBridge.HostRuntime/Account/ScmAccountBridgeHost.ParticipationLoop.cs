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
        _participantIdentity = null;
        lock (_participantLoopGate) {
            if (_participantLoopCancellation is not null)
                _participantLoopStopCompletion = Task.WhenAll(_participantLoopStopCompletion, ParticipantLoopCompletion);
            _participantLoopCancellation?.Cancel();
            _participantLoopCancellation = null;
        }
    }

    // Renewal is read-only work of an already-consumed admission. A temporary
    // missing binding still blocks business leases and positive publications,
    // but must not remove the only background path able to repair that binding.
    private StarBridge.NativeBridge.BridgeAccountContext? ParticipantLoopOwner =>
        _businessStartupDeferred
            ? _firstUseBusinessAdmission?.CanRenewLocalDataOwner == true ? CurrentContext : null
            : GameplayTimeContext;

    private void EnsureParticipantLoop()
    {
        lock (_participantLoopGate) {
            if (IsBusinessStartupDeferred && _firstUseBusinessAdmission?.CanRenewLocalDataOwner != true)
            {
                Support.IdentityGateJournal.Changed("owner-ensure", "code=skipped-deferred");
                return;
            }
            if (!_participantLoopEnabled || _disposed || _localModeSessionLoopsStopped || _session is null || ParticipantLoopOwner is not { } owner ||
                _participantLoopCancellation is not null) return;
            var generation = Generation;
            var cancellation = new CancellationTokenSource();
            _participantLoopCancellation = cancellation;
            ParticipantLoopCompletion = Task.Run(async () => {
                var token = cancellation.Token;
                var firstRound = true;
                var stoppedBy = "None";
                try {
                    while (!token.IsCancellationRequested && !_disposed && generation == Generation && ParticipantLoopOwner == owner) {
                        // Taken before enrolling, so a wake during this round is not lost.
                        Task wake;
                        lock (_participantLoopGate) wake = _participantLoopWake.Task;
                        await EnsureLocalDataOwnerAsync(token, force: firstRound && _businessStartupDeferred).ConfigureAwait(false);
                        firstRound = false;
                        try { await EnsureParticipantEnrollmentAsync(token, waitForMutation: true).ConfigureAwait(false); }
                        catch (OperationCanceledException) when (token.IsCancellationRequested) { throw; }
                        catch (Exception error)
                        {
                            Support.IdentityGateJournal.Event("participant-loop",
                                $"code=enrollment-unavailable exception={Support.IdentityGateJournal.Type(error)}");
                        }
                        await Task.WhenAny(Task.Delay(_participantLoopInterval, ParticipantClock, token), wake).ConfigureAwait(false);
                        token.ThrowIfCancellationRequested();
                    }
                }
                catch (OperationCanceledException error) when (token.IsCancellationRequested) { stoppedBy = Support.IdentityGateJournal.Type(error); }
                catch (ObjectDisposedException error) when (_disposed) { stoppedBy = Support.IdentityGateJournal.Type(error); }
                catch (Exception error)
                {
                    stoppedBy = Support.IdentityGateJournal.Type(error);
                }
                finally {
                    Support.IdentityGateJournal.Event("participant-loop", $"code=loop-stopped exception={stoppedBy}");
                    lock (_participantLoopGate) {
                        var owned = ReferenceEquals(_participantLoopCancellation, cancellation);
                        if (owned) _participantLoopCancellation = null;
                        // Only this loop may repair its slot. An explicit stop
                        // already detached it and must never be undone here.
                        if (owned && !token.IsCancellationRequested) EnsureParticipantLoop();
                        cancellation.Dispose();
                    }
                }
            });
        }
    }
}
