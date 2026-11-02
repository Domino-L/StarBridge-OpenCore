namespace StarBridge.HostRuntime;

public sealed partial class AccountBridgeRuntime
{
    private enum FirstUseCandidateExit { Failed, SessionPreserved, SignedOut }
    private readonly object _firstUseCandidateRetirementGate = new();
    private Task<FirstUseCandidateExit>? _firstUseCandidateExit;
    private Task<bool>? _firstUseCandidateRetirement, _firstUseCandidateShutdown;

    internal Task<bool> RetireFirstUseOnlineCandidateAsync() => RetainsFirstUseSession ? Task.FromResult(false) :
        BeginFirstUseCandidateExit(preserveSession: false);

    // Internal physical shutdown prerequisite. Only the eventual mode-owned
    // committed installation or retained-resume cancellation may select it;
    // it is never exposed as an ordinary account/logout bridge command.
    internal Task<bool> ShutdownFirstUseOnlineCandidateAsync() => BeginFirstUseCandidateExit(preserveSession: true);

    internal bool HasPreservedFirstUseSessionExit => Volatile.Read(ref _firstUseCandidateExit) is
        { IsCompletedSuccessfully: true, Result: FirstUseCandidateExit.SessionPreserved };

    private Task<bool> BeginFirstUseCandidateExit(bool preserveSession)
    {
        TaskCompletionSource<FirstUseCandidateExit>? completion = null;
        Task<bool> observation;
        lock (_firstUseCandidateRetirementGate)
        {
            if (_firstUseCandidateExit is null)
            {
                completion = new(TaskCreationOptions.RunContinuationsAsynchronously);
                _firstUseCandidateExit = completion.Task;
            }
            observation = preserveSession
                ? _firstUseCandidateShutdown ??= ObserveFirstUseCandidateExitAsync(_firstUseCandidateExit, true)
                : _firstUseCandidateRetirement ??= ObserveFirstUseCandidateExitAsync(_firstUseCandidateExit, false);
        }
        // Reserve both the physical task and this caller's typed observation
        // before synchronous consumer cancellation can reenter from any thread.
        if (completion is not null) _ = CompleteFirstUseCandidateExitAsync(completion, preserveSession);
        return observation;
    }

    private static async Task<bool> ObserveFirstUseCandidateExitAsync(Task<FirstUseCandidateExit> exit, bool shutdown)
    {
        var result = await exit.ConfigureAwait(false);
        // A keep-session exit can never masquerade as credential deletion or
        // authorize local recovery. A prior sign-out also satisfies shutdown.
        return shutdown ? result != FirstUseCandidateExit.Failed : result == FirstUseCandidateExit.SignedOut;
    }

    private async Task CompleteFirstUseCandidateExitAsync(TaskCompletionSource<FirstUseCandidateExit> completion,
        bool preserveSession)
    {
        try
        {
            var exited = await RetireFirstUseCandidateCoreAsync(preserveSession).ConfigureAwait(false);
            completion.TrySetResult(!exited ? FirstUseCandidateExit.Failed : preserveSession
                ? FirstUseCandidateExit.SessionPreserved : FirstUseCandidateExit.SignedOut);
        }
        catch (OperationCanceledException error) { completion.TrySetCanceled(error.CancellationToken); }
        catch (Exception error) { completion.TrySetException(error); }
    }
}
