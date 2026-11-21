namespace StarBridge.HostRuntime.Onboarding;

internal sealed partial class FirstUseModeRuntime
{
    // The guide's explicit local selection may finish the SAME stopped physical
    // transition after a transient storage/reconstruction failure. It never
    // repeats installation, constructs an account or treats an unknown exit as
    // completed. Cold recovery retains its original PID/receipt checks.
    internal async Task<FirstUseModeObservation> RecoverLocalSelectionAsync(long revision, string operationId,
        NativeAccountRuntimeBinding native, CancellationToken token)
    {
        if (_onlineCommit is null && _offline is null && _rootOffline is null)
            return deviceOnly
                ? await RecoverLocalAsync(revision, operationId, token).ConfigureAwait(false)
                : await ApplyLocalAsync(revision, operationId, account.Generation, token).ConfigureAwait(false);
        if (revision < 0 || !LocalFirstUseValidation.Id(operationId) || !native.OwnsRoot(account))
            throw new LocalFirstUseException("firstUse.invalid_request");
        if (!await _writer.WaitAsync(0, token).ConfigureAwait(false))
            throw new LocalFirstUseException("firstUse.operation_in_progress");
        try
        {
            if (_closed || _changing || _accepted is not { } accepted || accepted.Revision != revision ||
                accepted.OperationId == operationId || store.Read() != accepted)
                throw new LocalFirstUseException("firstUse.context_changed");
            token.ThrowIfCancellationRequested();
            _changing = true;
            if (_rootOffline is { LocalRestored: false } root)
            {
                if (!root.Completion.Task.IsCompletedSuccessfully || !root.OwnsTransition || !root.HasPhysicalExit ||
                    (root.Completed ?? root.Pending) != accepted) return new("recoveryRequired", revision);
                if (root.Completed is null) store.CompleteRootOffline(root);
                var local = root.Completed!;
                if (!account.HasCurrentFirstUseLocalSources(root.Epoch) &&
                    !await account.RestoreFirstUseLocalSourcesAsync(account.RetireFirstUseLocalSourcesAsync(), root.Epoch).ConfigureAwait(false))
                    return new("recoveryRequired", local.Revision);
                if (!NativeLocal() && !root.Callbacks.RestoreLocal(root.Epoch) || !root.OwnsTransition || store.Read() != local)
                    return new("recoveryRequired", local.Revision);
                root.LocalRestored = true;
                return new("offline", local.Revision, "local", true);
            }
            if (_offline is { LocalRestored: false } offline)
            {
                if (!offline.Completion.Task.IsCompletedSuccessfully || !offline.OwnsTransition || !offline.HasPhysicalExit ||
                    (offline.Completed ?? offline.Pending) != accepted) return new("recoveryRequired", revision);
                if (offline.Completed is null) store.CompleteOffline(offline);
                var local = offline.Completed!;
                if (!account.HasCurrentFirstUseLocalSources(offline.Epoch) &&
                    !await account.RestoreFirstUseLocalSourcesAsync(offline.Original.Graph.Sources, offline.Epoch).ConfigureAwait(false))
                    return new("recoveryRequired", local.Revision);
                if (!NativeLocal() && !await offline.Original.Graph.RestoreNativeAsync(offline.Epoch).ConfigureAwait(false) ||
                    !offline.OwnsTransition || store.Read() != local) return new("recoveryRequired", local.Revision);
                offline.LocalRestored = true;
                return new("offline", local.Revision, "local", true);
            }
            if (_onlineCommit is { Committed: null, LocalRestored: false } commit)
            {
                if (!commit.Completion.Task.IsCompletedSuccessfully || commit.Epoch != Interlocked.Read(ref _epoch) ||
                    !HasOriginalRecoveryExit(commit) || (commit.ReturnedLocal ?? commit.Pending) != accepted ||
                    store.ReadOnlineOrigin() != commit.Origin) return new("recoveryRequired", revision);
                return await RestoreAfterOnlineWriteFailureAsync(commit).ConfigureAwait(false);
            }
            return new("recoveryRequired", revision);
        }
        finally { _changing = false; _writer.Release(); }

        bool NativeLocal() => native.Read(owner => ReferenceEquals(owner, account), false);
    }
}
