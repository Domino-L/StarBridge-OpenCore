namespace StarBridge.HostRuntime;

public sealed partial class AccountBridgeRuntime
{
    private readonly object _publicationExitGate = new();
    private Task? _publicationExit;
    private readonly object _firstUseGraphExitGate = new();
    private Task? _firstUseGraphExit;

    private Task RetirePublicationOwnersAsync()
    {
        TaskCompletionSource completion;
        lock (_publicationExitGate)
        {
            if (_publicationExit is not null) return _publicationExit;
            completion = new(TaskCreationOptions.RunContinuationsAsynchronously);
            _publicationExit = completion.Task;
        }
        _ = CompleteRetirementAsync(completion, () => Task.WhenAll(
            Begin(() => _privacyPublication?.RetireAsync() ?? Task.CompletedTask),
            Begin(() => _friendSharing?.RetireAsync() ?? Task.CompletedTask),
            Begin(() => _eventSharing?.RetireAsync() ?? Task.CompletedTask)));
        return completion.Task;
    }

    // Called only after actual account stops, withdrawals and loop exit. Unlike
    // local mode's account-slot retirement, a discarded candidate retains no
    // device sampler; the entire original dormant/partly-started graph must exit.
    private Task RetireStoppedFirstUseBusinessGraphAsync()
    {
        TaskCompletionSource completion;
        lock (_firstUseGraphExitGate)
        {
            if (_firstUseGraphExit is not null) return _firstUseGraphExit;
            if (!_firstUseCandidate || !IsLocalAccountStopped(Generation) ||
                _localBackgroundRetirement?.IsCompletedSuccessfully != true ||
                _publicationExit?.IsCompletedSuccessfully != true)
                throw new Onboarding.LocalFirstUseException("firstUse.context_changed");
            completion = new(TaskCreationOptions.RunContinuationsAsynchronously);
            _firstUseGraphExit = completion.Task;
        }
        _ = CompleteRetirementAsync(completion, () => Task.WhenAll(
            Begin(() => _gameLog?.RetireAsync() ?? Task.CompletedTask),
            Begin(() => _gameplayTime?.RetireAsync() ?? Task.CompletedTask),
            Begin(() => _achievements?.RetireAsync() ?? Task.CompletedTask),
            Begin(RetirePublicationOwnersAsync)));
        return completion.Task;
    }
    private static Task Begin(Func<Task> retire)
    { try { return retire(); } catch (Exception error) { return Task.FromException(error); } }
    private static async Task CompleteRetirementAsync(TaskCompletionSource completion, Func<Task> retire)
    {
        try { await retire().ConfigureAwait(false); completion.TrySetResult(); }
        catch (Exception error) { completion.TrySetException(error); }
    }
}
