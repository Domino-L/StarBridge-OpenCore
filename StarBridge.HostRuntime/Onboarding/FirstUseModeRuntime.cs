namespace StarBridge.HostRuntime.Onboarding;

internal sealed record FirstUseModeObservation(string State, long Revision, string? ActiveMode = null,
    bool PublicationSuspended = false);

// Owns durable mode intent and the actual account retirement handshake. Not an
// onboarding completion receipt: identity, device choices and preview remain separate.
internal sealed partial class FirstUseModeRuntime(FirstUseModeStore store, LocalFirstUseStore identities,
    AccountBridgeRuntime account, bool deviceOnly,
    Func<FirstUseOnlineCandidateIntent, CancellationToken, Task<AccountBridgeRuntime>>? candidateFactory = null,
    TimeProvider? time = null)
{
    private readonly SemaphoreSlim _writer = new(1, 1);
    internal Account.OfflineAccountDisplay? OfflineAccount => Current is { State: "offline" } observed
        ? account.ReadOfflineAccount(observed.Revision) : null;
    internal Hangar.LocalHangarSnapshot? OfflineHangar(long revision) => Current is { State: "offline" } observed &&
        observed.Revision == revision ? account.ReadOfflineHangar(revision) : null;
    internal Profiles.LocalProfileSnapshot? OfflineProfile(long revision) => Current is { State: "offline" } observed &&
        observed.Revision == revision ? account.ReadOfflineProfile(revision) : null;
    internal Account.OfflineAchievementDisplay? OfflineAchievements(long revision) => Current is { State: "offline" } observed &&
        observed.Revision == revision ? account.ReadOfflineAchievements(revision) : null;
    internal Achievements.ScmAchievementCatalog? OfflineScmAchievements(long revision) => Current is { State: "offline" } observed &&
        observed.Revision == revision ? account.ReadOfflineScmAchievements(revision) : null;
    internal Account.OfflinePersonalProfileDisplay? OfflineRemoteProfile(long revision) => Current is { State: "offline" } observed &&
        observed.Revision == revision ? account.ReadOfflineRemoteProfile(revision) : null;
    internal Account.OfflineOrganizationDirectory? OfflineOrganizations(long revision, Func<bool> current) =>
        Current is { State: "offline" } observed && observed.Revision == revision
            ? account.ReadOfflineOrganizations(revision, current) : null;
    private FirstUseModeChoice? _accepted;
    private LocalAccountStopObservation? _stop;
    private long _epoch;
    private volatile bool _changing, _closed;
    // Only an in-process cancellation fence for a read bracketed by full
    // durable Current/credential checks. Never an authorization by itself.
    internal Func<bool> CaptureOfflineReadFence(long revision)
    {
        var epoch = Interlocked.Read(ref _epoch);
        var accepted = Volatile.Read(ref _accepted);
        return () => !_closed && !_changing && accepted is { Phase: "offline" } &&
            accepted.Revision == revision && Volatile.Read(ref _accepted) == accepted &&
            Interlocked.Read(ref _epoch) == epoch;
    }
    internal Lifecycle.DeviceNetworkAdmission DeviceNetwork { get; private set; } = Lifecycle.DeviceNetworkAdmission.Unavailable;

    internal void Initialize()
    {
        try { _accepted = store.ReadForInitialization(); }
        catch (LocalFirstUseException) { _accepted = null; }
        DeviceNetwork = new(() => Current is { State: "online", ActiveMode: "online", PublicationSuspended: false });
    }

    internal (bool Active, long Generation) LocalMode()
    {
        var epoch = Interlocked.Read(ref _epoch);
        if (_closed || _changing) return (false, -1);
        try
        {
            var accepted = Volatile.Read(ref _accepted);
            if (accepted is null || store.Read() != accepted) return (false, -1);
            if (accepted.Phase is "offline" or "offlinePending")
            {
                var offlineReady = accepted.Phase == "offline" && (deviceOnly && account.IsDeviceOnlyFirstUseStopped || RootOfflineReady(accepted) ||
                    _offline is { LocalRestored: true } offline && offline.Completed == accepted && offline.HasPhysicalExit ||
                    _onlineCommit is { LocalRestored: true } resumed && resumed.ReturnedLocal == accepted && HasOriginalRecoveryExit(resumed));
                if (_closed || _changing || epoch != Interlocked.Read(ref _epoch)) return (false, -1);
                return offlineReady ? (true, epoch) : (false, -1);
            }
            if (accepted.Phase == "onlinePending" && store.ReadOnlineOrigin() is { Local.Phase: "offline" } resume && resume.IsFor(accepted))
            {
                if (_onlineCommit is { Committed: null, LocalRestored: false }) return (false, -1);
                var ready = deviceOnly && account.IsDeviceOnlyFirstUseStopped || RootOfflineReady(resume.Local) ||
                    _offline is { LocalRestored: true } previous && previous.Completed == resume.Local && previous.HasPhysicalExit;
                if (_closed || _changing || epoch != Interlocked.Read(ref _epoch)) return (false, -1);
                return ready ? (true, epoch) : (false, -1);
            }
            if (_onlineCommit is { } committed)
            {
                if (committed.Committed == accepted && committed.Graph.IsLive) return (false, epoch);
                if (!committed.LocalRestored) return (false, -1);
            }
            var localIntent = accepted.Phase == "local" || accepted.Phase == "onlinePending" &&
                store.ReadOnlineOrigin()?.IsFor(accepted) == true;
            var local = localIntent && (deviceOnly && account.IsDeviceOnlyFirstUseStopped ||
                _stop is { State: "sessionStopped", RequestsDrained: true, PublicationStopped: true,
                    SessionLoopsStopped: true, BusinessBackgroundStopped: true } stop && account.IsLocalAccountStopped(stop.Generation));
            if (_closed || _changing || epoch != Interlocked.Read(ref _epoch)) return (false, -1);
            return local ? (true, epoch) : !deviceOnly && accepted.Phase is "unchosen" or "online"
                ? (false, epoch) : (false, -1);
        }
        catch { return (false, -1); }
    }

    internal FirstUseModeObservation Current
    {
        get
        {
            var before = Volatile.Read(ref _accepted);
            var mode = LocalMode();
            var accepted = Volatile.Read(ref _accepted);
            if (before != accepted || LocalMode() != mode)
                return new("unavailable", accepted?.Revision ?? 0);
            return mode.Active ? new(accepted!.Phase == "onlinePending" ? "signInRequired" : accepted.Phase == "offline" ? "offline" : "local", accepted.Revision, "local", true) : mode.Generation >= 0
                ? new("online", accepted!.Revision, "online")
                : new(_changing ? "switching" : _onlineCommit is { LocalRestored: false } || _rootOffline is { LocalRestored: false } || accepted?.Phase is "localPending" or "onlinePending" or "offlinePending"
                    ? "recoveryRequired" : "unavailable", accepted?.Revision ?? 0);
        }
    }

    internal async Task<FirstUseModeObservation> ApplyLocalAsync(long revision, string operationId,
        long accountGeneration, CancellationToken token = default)
    {
        if (revision < 0 || !LocalFirstUseValidation.Id(operationId))
            throw new LocalFirstUseException("firstUse.invalid_request");
        if (!await _writer.WaitAsync(0, token).ConfigureAwait(false))
            throw new LocalFirstUseException("firstUse.operation_in_progress");
        try
        {
            var old = store.Read();
            // The committed candidate, not this one-way retired root, owns the
            // next explicit offline transition. Do not stop the wrong account.
            if (_onlineCommit is { Committed: not null })
                throw new LocalFirstUseException("firstUse.context_changed");
            if (_closed || old != _accepted || revision != old.Revision || account.Generation != accountGeneration)
                throw new LocalFirstUseException("firstUse.context_changed");
            if (old.OperationId == operationId) throw new LocalFirstUseException("firstUse.revision_conflict");
            if (LocalMode().Active) return Current;
            if (deviceOnly) return new("recoveryRequired", old.Revision);
            token.ThrowIfCancellationRequested();
            _changing = true; Interlocked.Increment(ref _epoch);
            // Write the intent before irreversible retirement. Cancellation/crash
            // cannot return a later cold start to implicit account restoration.
            if (old.Phase != "localPending")
            {
                try
                {
                    _accepted = store.Save(revision, operationId, "localPending",
                        () => !_closed && !token.IsCancellationRequested && account.Generation == accountGeneration);
                }
                catch { _changing = false; throw; }
            }
            var pending = _accepted!;
            var deviceExit = DeviceNetwork.PauseAsync();
            account.BlockFirstUseAccountRequests();
            var accountExit = account.StopAccountForLocalModeAsync(accountGeneration, token,
                (facts, credential, current) => store.SaveCredentialCheckpoint(pending, facts, credential,
                    () => !_closed && !token.IsCancellationRequested && current()));
            await Task.WhenAll(deviceExit, accountExit).ConfigureAwait(false);
            var stopped = await accountExit.ConfigureAwait(false);
            if (stopped.State != "sessionStopped" || !stopped.RequestsDrained || !stopped.PublicationStopped ||
                !stopped.SessionLoopsStopped || !stopped.BusinessBackgroundStopped)
                return new(stopped.State, pending.Revision);
            _stop = stopped;
            token.ThrowIfCancellationRequested();
            store.SaveRetirement(pending, stopped,
                () => !_closed && !token.IsCancellationRequested && account.IsLocalAccountStopped(stopped.Generation));
            _accepted = store.Save(pending.Revision, Guid.NewGuid().ToString("N"), "local",
                () => !_closed && !token.IsCancellationRequested && account.IsLocalAccountStopped(stopped.Generation));
            return new("local", _accepted.Revision, "local", true);
        }
        finally { _changing = false; _writer.Release(); }
    }

    // Recovery is explicit. Either all original exits were completed, or a
    // separate checkpoint proves all readers/publication exited and authorizes
    // only that credential version's clear after the original process has exited.
    // Earlier partial stops remain pending. No account/OAuth/network is restored.
    internal async Task<FirstUseModeObservation> RecoverLocalAsync(long revision, string operationId,
        CancellationToken token = default)
    {
        if (revision < 0 || !LocalFirstUseValidation.Id(operationId))
            throw new LocalFirstUseException("firstUse.invalid_request");
        if (!await _writer.WaitAsync(0, token).ConfigureAwait(false))
            throw new LocalFirstUseException("firstUse.operation_in_progress");
        try
        {
            var pending = store.Read();
            if (_closed || !deviceOnly || !account.IsDeviceOnlyFirstUseStopped || pending != _accepted ||
                pending.Revision != revision || pending.Phase != "localPending" || pending.OperationId == operationId)
                throw new LocalFirstUseException("firstUse.context_changed");
            var receipt = store.ReadRetirement();
            var checkpoint = store.ReadCredentialCheckpoint();
            if (checkpoint?.IsFor(pending) == true)
            {
                var ownerExit = checkpoint.Owner.ReadExit();
                if (ownerExit != "exited") return new(ownerExit == "running" ? "ownerRunning" : "ownerUnknown", pending.Revision);
                token.ThrowIfCancellationRequested();
                _changing = true; Interlocked.Increment(ref _epoch);
                var vault = store.FindCredentialCheckpointVault(checkpoint);
                if (vault is null) return new("recoveryRequired", pending.Revision);
                bool Current() => !_closed && !token.IsCancellationRequested && account.IsDeviceOnlyFirstUseStopped &&
                    store.Read() == pending && store.ReadCredentialCheckpoint() == checkpoint && checkpoint.Owner.ReadExit() == "exited";
                try
                {
                    if (!vault.TryClearRetirement(checkpoint.Credential, Current, () =>
                        _accepted = store.Save(pending.Revision, operationId, "local", () => Current() && vault.IsRetirementCleared(checkpoint.Credential))))
                        return new("recoveryRequired", pending.Revision);
                }
                catch (Exception error) when (error is System.IO.IOException or System.IO.InvalidDataException or UnauthorizedAccessException or
                    System.Security.Cryptography.CryptographicException or System.Security.SecurityException)
                { throw new LocalFirstUseException("firstUse.mode_receipt_write_failed"); }
                return new("local", _accepted!.Revision, "local", true);
            }
            if (receipt is null || !receipt.IsFor(pending)) return new("recoveryRequired", pending.Revision);
            var exited = receipt.Owner.ReadExit();
            if (exited != "exited") return new(exited == "running" ? "ownerRunning" : "ownerUnknown", pending.Revision);
            token.ThrowIfCancellationRequested();
            _changing = true; Interlocked.Increment(ref _epoch);
            _accepted = store.Save(pending.Revision, operationId, "local", () => !_closed && !token.IsCancellationRequested &&
                account.IsDeviceOnlyFirstUseStopped && store.ReadRetirement() == receipt && receipt.Owner.ReadExit() == "exited");
            return new("local", _accepted.Revision, "local", true);
        }
        finally { _changing = false; _writer.Release(); }
    }

    // Explicit online selection records a pending intent; it does not reuse this
    // one-way retired account runtime or restore its credentials. Composition must
    // obtain a fresh-login candidate and verify actual sign-in before committing.
    internal FirstUseModeObservation RequestOnline(long revision, string operationId)
    {
        if (revision < 0 || !LocalFirstUseValidation.Id(operationId))
            throw new LocalFirstUseException("firstUse.invalid_request");
        if (!_writer.Wait(0)) throw new LocalFirstUseException("firstUse.operation_in_progress");
        try
        {
            if (_closed || _accepted is null || _accepted.Revision != revision || store.Read() != _accepted)
                throw new LocalFirstUseException("firstUse.context_changed");
            if (_accepted.Phase is "unchosen" or "online") return Current;
            // Resume is a distinct retained-session installation, not the old
            // fresh-login path that could overwrite a preserved credential.
            if (_accepted.Phase == "offline") throw new LocalFirstUseException("firstUse.resume_required");
            if (!LocalMode().Active) throw new LocalFirstUseException("firstUse.mode_receipt_required");
            if (_accepted.Phase == "onlinePending") return Current;
            // This is still the same established local source and statistics
            // epoch. Merely requesting a browser login must not retire it.
            _accepted = store.BeginOnline(_accepted, operationId, () => !_closed && LocalMode().Active);
            _issuedIdentity = null; _confirmedIdentity = null;
            _preparedOnline = null;
            _candidateLifetime?.Dispose();
            _candidateStart = null; _candidateCancel = null; _candidateLifetime = null;
            _onlineCommit = null;
            return Current;
        }
        finally { _changing = false; _writer.Release(); }
    }

    internal void Close() { _ = DeviceNetwork.RetireAsync(); _ = CloseOnlineOwner(); }
    internal Task<bool>? CloseOwnedOnlineAsync() => CloseOnlineOwner();
}
