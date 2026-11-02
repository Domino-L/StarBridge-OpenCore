namespace StarBridge.HostRuntime.Onboarding;

internal sealed partial class FirstUseModeRuntime
{
    internal bool HasColdOnlinePending => !_closed && deviceOnly && account.IsDeviceOnlyFirstUseStopped &&
        _candidateStart is null && _onlineCommit is null && _accepted is { Phase: "onlinePending" } pending &&
        store.ReadOnlineOrigin() is { CandidateStarted: true } origin && origin.IsFor(pending);

    // Explicit display/mode recovery, not cancellation of an unknown credential.
    // The original PID/start time must have exited. The current device-only root
    // has no online consumers; the opaque vault remains untouched and no account
    // is restored. A future online command obtains new live identity authority.
    internal async Task<FirstUseModeObservation> RecoverColdOnlineAsync(long revision, string operationId,
        CancellationToken token = default)
    {
        if (revision < 0 || !LocalFirstUseValidation.Id(operationId)) throw new LocalFirstUseException("firstUse.invalid_request");
        if (!await _writer.WaitAsync(0, token).ConfigureAwait(false)) throw new LocalFirstUseException("firstUse.operation_in_progress");
        try
        {
            var pending = _accepted;
            var origin = store.ReadOnlineOrigin();
            if (!HasColdOnlinePending || pending is null || pending.Revision != revision || pending.OperationId == operationId ||
                store.Read() != pending || origin?.IsFor(pending) != true || !LocalMode().Active)
                throw new LocalFirstUseException("firstUse.context_changed");
            if (origin.Owner.ReadExit() != "exited") return new("recoveryRequired", pending.Revision, "local", true);
            token.ThrowIfCancellationRequested();
            _accepted = store.ReturnFromOnline(pending, operationId, () => !_closed && !token.IsCancellationRequested &&
                deviceOnly && account.IsDeviceOnlyFirstUseStopped && _candidateStart is null && _onlineCommit is null &&
                _accepted == pending && store.ReadOnlineOrigin() == origin && origin.Owner.ReadExit() == "exited" && LocalMode().Active);
            _issuedIdentity = null; _confirmedIdentity = null; _preparedOnline = null;
            if (_accepted.Phase == "offline" && origin.Local.Phase == "offline")
                account.ReturnOfflineAccount(origin.Local.Revision, _accepted.Revision,
                    () => !_closed && store.Read() == _accepted && LocalMode().Active);
            return Current;
        }
        finally { _writer.Release(); }
    }
}
