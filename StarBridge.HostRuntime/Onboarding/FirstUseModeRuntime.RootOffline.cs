namespace StarBridge.HostRuntime.Onboarding;

internal sealed partial class FirstUseModeRuntime
{
    private volatile RootOfflineTransition? _rootOffline;

    // Ordinary startup has no OnlineCommit. Consume its exact Native root slot
    // instead, never fabricate a staged installation or use strict sign-out.
    internal Task<FirstUseModeObservation> ApplyRootOfflineAsync(long revision, string operationId,
        long generation, NativeAccountRuntimeBinding native, CancellationToken token = default)
    {
        ArgumentNullException.ThrowIfNull(native);
        token.ThrowIfCancellationRequested();
        if (revision < 0 || !LocalFirstUseValidation.Id(operationId))
            throw new LocalFirstUseException("firstUse.invalid_request");
        if (_rootOffline is { } original)
        {
            if (original.Online.Revision != revision || original.OperationId != operationId ||
                original.Callbacks.Generation != generation || !ReferenceEquals(original.Native, native))
                throw new LocalFirstUseException("firstUse.context_changed");
            return Observe(original.Completion.Task, token);
        }
        if (!_writer.Wait(0)) throw new LocalFirstUseException("firstUse.operation_in_progress");
        RootOfflineTransition transition;
        try
        {
            var online = _accepted;
            if (_closed || _changing || deviceOnly || online is null || online.Phase is not ("unchosen" or "online") ||
                online.Revision != revision || online.OperationId == operationId || store.Read() != online ||
                _onlineCommit is not null || _candidateStart is not null || _stop is not null ||
                native.CaptureRootOnlineCallbacks(account, generation) is not { } callbacks)
                throw new LocalFirstUseException("firstUse.context_changed");
            lock (_onlineCommitGate)
            {
                if (_closed || _rootOffline is not null || !callbacks.IsLive)
                    throw new LocalFirstUseException("firstUse.context_changed");
                transition = new(this, online, operationId, native, callbacks, Interlocked.Increment(ref _epoch));
                _rootOffline = transition; _changing = true;
            }
        }
        catch { _writer.Release(); throw; }
        _ = CompleteRootOfflineAsync(transition);
        return Observe(transition.Completion.Task, token);
    }

    internal sealed class RootOfflineTransition(FirstUseModeRuntime mode, FirstUseModeChoice online,
        string operationId, NativeAccountRuntimeBinding native,
        NativeAccountRuntimeBinding.RootOfflineCallbacks callbacks, long epoch)
    {
        internal readonly FirstUseModeChoice Online = online;
        internal readonly string OperationId = operationId;
        internal readonly NativeAccountRuntimeBinding Native = native;
        internal readonly NativeAccountRuntimeBinding.RootOfflineCallbacks Callbacks = callbacks;
        internal readonly long Epoch = epoch;
        internal readonly TaskCompletionSource<FirstUseModeObservation> Completion = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal volatile FirstUseModeChoice? Pending, Completed;
        internal volatile bool LocalRestored;
        internal bool OwnsTransition => !mode._closed && ReferenceEquals(mode._rootOffline, this) &&
            Interlocked.Read(ref mode._epoch) == Epoch && mode._onlineCommit is null;
        internal bool BeginCurrent() => OwnsTransition && mode._accepted == Online &&
            mode.ModeStore.Read() == Online && Callbacks.IsLive;
        internal bool HasPhysicalExit => Callbacks.HasExited &&
            Callbacks.Root.HasPreservedRootSessionExit(Callbacks.Generation, Callbacks.Context);
        internal bool CompleteCurrent() => OwnsTransition && Pending is { } pending &&
            mode._accepted == pending && mode.ModeStore.Read() == pending && HasPhysicalExit;
        internal void WriteAndAdopt(FirstUseModeChoice next, Action write)
        {
            lock (mode._onlineCommitGate)
            {
                if (!OwnsTransition || (next.Phase == "offlinePending" ? !Callbacks.IsLive : !HasPhysicalExit))
                    throw new LocalFirstUseException("firstUse.context_changed");
                write();
                if (next.Phase == "offlinePending") Pending = next;
                else Completed = next;
                Volatile.Write(ref mode._accepted, next);
            }
        }
    }

    private async Task CompleteRootOfflineAsync(RootOfflineTransition transition)
    {
        await Task.Yield();
        FirstUseModeObservation result = new("recoveryRequired", transition.Online.Revision);
        bool retryUnwritten = false;
        try
        {
            var retainedCredential = account.ReadRetainedCredentialVersion(
                transition.Callbacks.Context, transition.Callbacks.Generation);
            store.BeginRootOffline(transition);
            result = new("recoveryRequired", transition.Pending!.Revision);
            var deviceExit = DeviceNetwork.PauseAsync();
            var accountExit = ExitRootOnlineAsync(transition);
            await Task.WhenAll(deviceExit, accountExit).ConfigureAwait(false);
            if (!await accountExit.ConfigureAwait(false) || !transition.CompleteCurrent()) return;
            store.CompleteRootOffline(transition);
            account.PinOfflineAccount(transition.Callbacks.Context, transition.Completed!.Revision,
                () => transition.OwnsTransition && transition.HasPhysicalExit && store.Read() == transition.Completed,
                retainedCredential);
            if (!await account.RestoreFirstUseLocalSourcesAsync(account.RetireFirstUseLocalSourcesAsync(), transition.Epoch).ConfigureAwait(false) ||
                !transition.Callbacks.RestoreLocal(transition.Epoch) || !transition.OwnsTransition ||
                store.Read() != transition.Completed) return;
            transition.LocalRestored = true;
            result = new("offline", transition.Completed!.Revision, "local", true);
        }
        catch
        {
            if (transition.Pending is null)
            {
                FirstUseModeChoice? observed = null;
                try { observed = store.Read(); } catch { }
                retryUnwritten = !_closed && observed == transition.Online && _accepted == transition.Online && transition.Callbacks.IsLive;
                if (!retryUnwritten)
                    try { await ExitRootOnlineAsync(transition).ConfigureAwait(false); } catch { }
            }
            result = new("recoveryRequired", _accepted?.Revision ?? transition.Online.Revision);
        }
        finally
        {
            if (retryUnwritten)
            {
                bool released = false;
                lock (_onlineCommitGate)
                    if (!_closed && ReferenceEquals(_rootOffline, transition) && transition.Pending is null &&
                        _accepted == transition.Online && transition.Callbacks.IsLive)
                    { _rootOffline = null; released = true; }
                // Close may have won after unwritten readback. Only releasing
                // this exact reservation under the same gate can leave online
                // intact; otherwise Close owns the original physical exit too.
                if (!released)
                    try { await ExitRootOnlineAsync(transition).ConfigureAwait(false); } catch { }
            }
            _changing = false; _writer.Release(); transition.Completion.TrySetResult(result);
        }
    }

    private async Task<bool> ExitRootOnlineAsync(RootOfflineTransition transition)
    {
        // Start Native drain before closing root admission. Every sibling's
        // original task remains owned even when another one faults.
        var callbacks = transition.Callbacks.DrainAsync();
        var online = account.StopRootOnlinePreservingSessionAsync(transition.Callbacks);
        var sources = account.RetireFirstUseLocalSourcesAsync();
        await Task.WhenAll(callbacks, online, sources).ConfigureAwait(false);
        return online.Result && transition.HasPhysicalExit;
    }

    private bool RootOfflineReady(FirstUseModeChoice choice) =>
        _rootOffline is { LocalRestored: true } root && root.Completed == choice && root.HasPhysicalExit;
}
