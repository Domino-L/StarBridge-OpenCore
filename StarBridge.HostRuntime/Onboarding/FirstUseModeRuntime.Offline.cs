namespace StarBridge.HostRuntime.Onboarding;

internal sealed partial class FirstUseModeRuntime
{
    private volatile OfflineTransition? _offline;

    // Explicit offline selection, never a presence override or account logout.
    // One original transition owns the durable intent, physical online exit and
    // reconstruction. Cancelling a UI observer cannot abandon any of that work.
    internal Task<FirstUseModeObservation> ApplyOfflineAsync(long revision, string operationId,
        long accountGeneration, CancellationToken token = default)
    {
        token.ThrowIfCancellationRequested();
        if (revision < 0 || !LocalFirstUseValidation.Id(operationId))
            throw new LocalFirstUseException("firstUse.invalid_request");
        var existing = _offline;
        if (existing is not null)
        {
            if (existing.Online.Revision != revision || existing.OperationId != operationId ||
                existing.AccountGeneration != accountGeneration)
                throw new LocalFirstUseException("firstUse.context_changed");
            return Observe(existing.Completion.Task, token);
        }
        if (!_writer.Wait(0)) throw new LocalFirstUseException("firstUse.operation_in_progress");
        OfflineTransition transition;
        try
        {
            var online = _accepted;
            var committed = _onlineCommit;
            if (_closed || _changing || online is not { Phase: "online" } || online.Revision != revision ||
                online.OperationId == operationId || store.Read() != online ||
                committed?.Committed != online || !committed.Completion.Task.IsCompletedSuccessfully ||
                committed.Graph.Installation.Owner.Generation != accountGeneration || !committed.Graph.IsLive)
                throw new LocalFirstUseException("firstUse.context_changed");
            lock (_onlineCommitGate)
            {
                if (_closed || _offline is not null || !ReferenceEquals(_onlineCommit, committed))
                    throw new LocalFirstUseException("firstUse.context_changed");
                transition = new(this, committed, online, operationId, accountGeneration,
                    Interlocked.Increment(ref _epoch));
                _offline = transition; _changing = true;
            }
        }
        catch { _writer.Release(); throw; }
        _ = CompleteOfflineAsync(transition);
        return Observe(transition.Completion.Task, token);
    }

    internal sealed class OfflineTransition(FirstUseModeRuntime mode, OnlineCommit original,
        FirstUseModeChoice online, string operationId, long accountGeneration, long epoch)
    {
        internal readonly OnlineCommit Original = original;
        internal readonly FirstUseModeChoice Online = online;
        internal readonly string OperationId = operationId;
        internal readonly long AccountGeneration = accountGeneration, Epoch = epoch;
        internal readonly TaskCompletionSource<FirstUseModeObservation> Completion = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal volatile FirstUseModeChoice? Pending, Completed;
        internal volatile bool LocalRestored;

        internal bool OwnsTransition => !mode._closed && ReferenceEquals(mode._offline, this) &&
            ReferenceEquals(mode._onlineCommit, Original) && Interlocked.Read(ref mode._epoch) == Epoch;
        internal bool BeginCurrent() => OwnsTransition && mode._accepted == Online &&
            mode.ModeStore.Read() == Online && Original.Graph.IsLive &&
            Original.Graph.Installation.Owner.Generation == AccountGeneration;
        internal bool HasPhysicalExit => Original.Graph.Installation.Owner.HasPreservedFirstUseSessionExit &&
            Original.Graph.HasNativeExit;
        internal bool CompleteCurrent() => OwnsTransition && Pending is { } pending &&
            mode._accepted == pending && mode.ModeStore.Read() == pending && HasPhysicalExit;

        internal void WriteAndAdopt(FirstUseModeChoice next, Action write)
        {
            lock (mode._onlineCommitGate)
            {
                // All IO/clock/provenance checks were performed by the store.
                // Close shares only this final rename/adoption gate.
                if (!OwnsTransition || (next.Phase == "offlinePending" ? !Original.Graph.IsLive : !HasPhysicalExit))
                    throw new LocalFirstUseException("firstUse.context_changed");
                write();
                if (next.Phase == "offlinePending") Pending = next;
                else Completed = next;
                Volatile.Write(ref mode._accepted, next);
            }
        }
    }

    private async Task CompleteOfflineAsync(OfflineTransition transition)
    {
        await Task.Yield();
        FirstUseModeObservation result = new("recoveryRequired", transition.Online.Revision);
        var retryUnwrittenIntent = false;
        try
        {
            // Persist before closing any online owner: a crash cannot authorize
            // implicit account restore. This path never writes a clear checkpoint.
            store.BeginOffline(transition);
            var retainedAccount = transition.Original.Graph.Installation.Owner.NativeNotificationOwner.Context;
            var retainedCredential = retainedAccount is null ? null :
                transition.Original.Graph.Installation.Owner.ReadRetainedCredentialVersion(retainedAccount, transition.AccountGeneration);
            result = new("recoveryRequired", transition.Pending!.Revision);
            var deviceExit = DeviceNetwork.PauseAsync();
            _issuedIdentity = null; _confirmedIdentity = null; _preparedOnline = null;
            CancelCandidateLifetime();
            var accountExit = transition.Original.Graph.Installation.Owner.ShutdownFirstUseOnlineCandidateAsync();
            await Task.WhenAll(deviceExit, accountExit).ConfigureAwait(false);
            if (!await accountExit.ConfigureAwait(false) ||
                !transition.CompleteCurrent()) return;
            store.CompleteOffline(transition);
            if (retainedAccount is not null)
                account.PinOfflineAccount(retainedAccount, transition.Completed!.Revision,
                    () => transition.OwnsTransition && transition.HasPhysicalExit && store.Read() == transition.Completed,
                    retainedCredential);
            if (!await account.RestoreFirstUseLocalSourcesAsync(transition.Original.Graph.Sources, transition.Epoch).ConfigureAwait(false) ||
                !await transition.Original.Graph.RestoreNativeAsync(transition.Epoch).ConfigureAwait(false) ||
                !transition.OwnsTransition || store.Read() != transition.Completed) return;
            transition.LocalRestored = true;
            result = new("offline", transition.Completed!.Revision, "local", true);
        }
        catch
        {
            if (transition.Pending is null)
            {
                // Only exact readback of the original online choice can prove
                // that the intent did not commit and no online exit began.
                FirstUseModeChoice? observed = null;
                try { observed = store.Read(); } catch { }
                retryUnwrittenIntent = observed == transition.Online && _accepted == transition.Online &&
                    transition.Original.Graph.IsLive;
                if (!retryUnwrittenIntent)
                {
                    _issuedIdentity = null; _confirmedIdentity = null; _preparedOnline = null;
                    CancelCandidateLifetime();
                    // Unknown state is not permission to continue networking.
                    // Preserve external bytes and credentials, but await the
                    // exact original physical graph exit (including faults).
                    try { await transition.Original.Graph.Installation.Owner.ShutdownFirstUseOnlineCandidateAsync().ConfigureAwait(false); }
                    catch { }
                }
            }
            // Never turn a partial exit into sign-out or a local success receipt.
            result = new("recoveryRequired", _accepted?.Revision ?? transition.Online.Revision);
        }
        finally
        {
            if (retryUnwrittenIntent)
                lock (_onlineCommitGate)
                    if (!_closed && ReferenceEquals(_offline, transition) && transition.Pending is null &&
                        _accepted == transition.Online && transition.Original.Graph.IsLive)
                        _offline = null;
            _changing = false; _writer.Release();
            transition.Completion.TrySetResult(result);
        }
    }

    internal bool OwnsPreservedOfflineInstallation(AccountBridgeRuntime.FirstUseBusinessInstallation installation, long epoch) =>
        _offline is { Completed: not null } transition &&
        ReferenceEquals(transition.Original.Graph.Installation, installation) && transition.Epoch == epoch &&
        transition.HasPhysicalExit && AllowsLocalSourceReconstruction(epoch);
}
