using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Onboarding;

internal sealed partial class FirstUseModeRuntime
{
    private sealed record InstalledReview(string Key, OnlineCommit? Commit, AccountBridgeRuntime Owner,
        FirstUseModeChoice Mode, LocalIdentityScope Local, FirstUseScmIdentityFacts Facts, DateTimeOffset ExpiresAt);
    private volatile InstalledReview? _installedReview, _installedBinding;
    internal FirstUseCompletionStore? ColdCompletionHistory { private get; set; }

    internal bool HasInstalledOnlineAccount
    {
        get
        {
            try
            {
                if (_closed || _changing || _candidateCancel is not null || _accepted?.Phase != "online" || store.Read() != _accepted) return false;
                return _onlineCommit is { IsCancellation: false, Committed: not null } commit
                    ? commit.Committed == _accepted && commit.Graph.IsLive
                    : _onlineCommit is null && !deviceOnly && account.HasColdFirstUseAccount;
            }
            catch { return false; }
        }
    }

    internal bool AllowsLocalIdentitySetup => LocalMode().Active || HasInstalledOnlineAccount;
    private bool InstalledGameIdentityAllowed
    {
        get
        {
            try
            {
                if (InstalledIdentityBound) return true;
                // An activated, identity-bearing installation may finish its
                // original commit. Account-only preparation never qualifies.
                return !_closed && _candidateCancel is null && _accepted is { Phase: "onlinePending" } pending &&
                    store.Read() == pending && _confirmedIdentity is { Scope.AccountOnly: false, Scope.Local: not null } confirmed &&
                    confirmed.Scope.Pending == pending && CaptureLocalIdentity() == confirmed.Scope.Local &&
                    confirmed.Scope.Candidate.InstalledFirstUseIdentityCurrent(confirmed.Facts) &&
                    Assess(confirmed.Facts, confirmed.Scope.Local.Profile.Handle) == "match";
            }
            catch { return false; }
        }
    }
    private bool BindingCurrent(InstalledReview value) => HasInstalledOnlineAccount &&
        ReferenceEquals(_onlineCommit, value.Commit) && _accepted == value.Mode &&
        CaptureLocalIdentity() is { } local && local.Profile == value.Local.Profile &&
        local.Source with { ListeningEnabled = value.Local.Source.ListeningEnabled } == value.Local.Source &&
        value.Owner.InstalledFirstUseIdentityCurrent(value.Facts) &&
        Assess(value.Facts, value.Local.Profile.Handle) == "match";
    private bool InstalledIdentityBound
    {
        get
        {
            string reason;
            try { reason = BindInstalledIdentity(); }
            catch { reason = "exception"; }
            FirstUseIdentityDiagnostics.Note(reason);
            return reason == "bound";
        }
    }

    // Serializes receipt writers (backfill and explicit confirmation). Readers
    // take no lock, so a sign-in or gate read never waits on a receipt write.
    // Both writers save with an after-commit check, so each new receipt is
    // written in its unconfirmed form and turned confirmed only after that
    // check passed. A reader decides from the one receipt it read: it never
    // binds a receipt whose commit has not finished, and a receipt left by a
    // failed rollback stays unconfirmed on disk, across restarts, until an
    // explicit confirmation saves a confirmed one.
    private readonly object _coldBindingGate = new();

    // History only avoids repeating an already acknowledged setup. Authority
    // still requires THIS restored session, selected local identity, live vault
    // lineage and fresh verified identity match. Returns a reason code only.
    private string BindInstalledIdentity()
    {
        if (_installedBinding is { } bound) return BindingCurrent(bound) ? "bound" : "binding-stale";
        if (!HasInstalledOnlineAccount) return "no-online-account";
        if (_onlineCommit is not null) return "no-history";
        if (CaptureLocalIdentity() is not { } local) return "no-local-identity:" + LocalIdentityGap();
        var history = ColdCompletionHistory?.Read();
        if (history is null)
        {
            if (ColdCompletionHistory is null || !ReturningAtStartup) return "no-history";
            if (account.CurrentColdFirstUseFacts() is not { } current) return "no-facts";
            if (Assess(current, local.Profile.Handle) is var assessed && assessed != "match") return "assess-" + assessed;
            // Only the session restored at startup, with its original credential,
            // stands for the setup this user already finished. After a sign-in or
            // account change the user confirms explicitly instead.
            if (!account.IsRestoredColdFirstUseSession(current)) return "not-restored-session";
            // Setup was finished before this device kept a completion receipt
            // (the store arrived in 0.7.2.1). The same checks a receipt would be
            // checked against pass now, so record it once and bind.
            if (!BackfillCompletion(local, current)) return "no-history";
            history = ColdCompletionHistory.Read();
        }
        if (history is { Unconfirmed: true }) return "history-uncertain";
        if (history is not { Mode: "online" }) return "history-mode-mismatch";
        if (history.ProfileId != local.Profile.Id) return "history-profile-mismatch";
        if (history.SourceKey != local.Source.SourceKey) return "history-source-mismatch";
        if (account.CurrentColdFirstUseFacts() is not { } facts) return "no-facts";
        if (Assess(facts, local.Profile.Handle) is var assessment && assessment != "match") return "assess-" + assessment;
        var value = new InstalledReview(Guid.NewGuid().ToString("N"), null, account, _accepted!, local, facts, DateTimeOffset.MaxValue);
        if (!BindingCurrent(value)) return "binding-stale";
        _installedBinding = value;
        return "bound";
    }

    // The final check and file commit run inside the same gate that Close and
    // every mode transition use, so neither can land between them. A sign-in or
    // account change does not take that gate; it publishes a new generation,
    // which the store's after-commit check sees, and the receipt is put back.
    private Action<Action> ReceiptCommitGate(FirstUseModeChoice? mode) => commit =>
    {
        lock (_onlineCommitGate)
        {
            if (_closed || _changing || _accepted != mode || _onlineCommit is not null || _candidateCancel is not null)
                throw new LocalFirstUseException("firstUse.context_changed");
            commit();
        }
    };

    private static bool ReceiptMatches(FirstUseCompletion? receipt, LocalIdentityScope local) =>
        receipt is { Mode: "online", LogDeferred: false } && receipt.ProfileId == local.Profile.Id &&
        receipt.SourceKey == local.Source.SourceKey;

    // Writes a completion receipt only while every binding check still holds,
    // rechecked inside the commit gate and again once the file is in place.
    // Never replaces a receipt. Any failure is a failure: a receipt that can
    // still be read afterwards stays uncertain, never taken as success.
    private bool BackfillCompletion(LocalIdentityScope local, FirstUseScmIdentityFacts facts)
    {
        var history = ColdCompletionHistory!;
        var mode = _accepted;
        lock (_coldBindingGate)
        {
            bool Current() => !_closed && !_changing && _accepted == mode && _onlineCommit is null && HasInstalledOnlineAccount &&
                CaptureLocalIdentity() == local && account.IsRestoredColdFirstUseSession(facts) &&
                Assess(facts, local.Profile.Handle) == "match";
            try
            {
                if (history.Read() is not null) return true;
                if (!Current()) return false;
                history.Save(null, Guid.NewGuid().ToString("N"), "online", local.Profile.Id, local.Source.SourceKey, Current,
                    commitGate: ReceiptCommitGate(mode), afterCommit: Current);
                FirstUseIdentityDiagnostics.Note("history-backfilled");
                return true;
            }
            catch (LocalFirstUseException) { return false; }
        }
    }

    // An explicit installed-identity confirmation on a missing receipt (a
    // returning user), a changed profile, log source or an older local-mode
    // receipt records the receipt first. The binding is published only after
    // the saved receipt is read back confirmed; a failed save keeps the gate
    // closed, and a receipt it may have left behind stays uncertain.
    // A receipt that cannot be read is recovered the same way: only this
    // explicit confirmation replaces it (never the automatic backfill), and
    // only after the same checked save the binding is published.
    private bool RecordConfirmedCompletion(InstalledReview value)
    {
        var history = ColdCompletionHistory;
        if (history is null) return true;
        lock (_coldBindingGate)
        {
            try
            {
                FirstUseCompletion? previous = null;
                var unreadable = false;
                try { previous = history.Read(); }
                catch (LocalFirstUseException error) when (error.Code == "firstUse.completion_read_failed") { unreadable = true; }
                catch (InvalidDataException) { unreadable = true; }
                // A user still inside first-use setup finishes it there; only a
                // returning user's missing receipt is created here.
                if (previous is null && !unreadable && !ReturningAtStartup) return true;
                // A matching receipt left uncertain by a failed rollback is saved
                // again, so the next process finds a confirmed one.
                if (ReceiptMatches(previous, value.Local) && !previous!.Unconfirmed) return true;
                bool Current() => !_closed && !_changing && BindingCurrent(value);
                if (!Current()) return false;
                history.Save(previous, Guid.NewGuid().ToString("N"), "online", value.Local.Profile.Id, value.Local.Source.SourceKey, Current,
                    commitGate: ReceiptCommitGate(value.Mode), afterCommit: Current, replaceUnreadable: unreadable);
                if (history.Read() is not { } saved || !ReceiptMatches(saved, value.Local) || saved.Unconfirmed)
                    throw new LocalFirstUseException("firstUse.completion_write_failed");
                FirstUseIdentityDiagnostics.Note(unreadable ? "history-recovered" : "history-updated");
                return true;
            }
            catch (LocalFirstUseException)
            {
                FirstUseIdentityDiagnostics.Note("history-update-failed");
                return false;
            }
        }
    }

    private FirstUseOnlineIdentityObservation CurrentInstalledIdentity(long revision)
    {
        if (revision != _accepted?.Revision || !HasInstalledOnlineAccount) return new("contextChanged");
        _ = InstalledIdentityBound;
        if (_installedBinding is { } bound && BindingCurrent(bound))
            return InstalledView("boundOnlineIdentity", bound);
        if (_installedReview is { } issued && _identityTime.GetUtcNow() < issued.ExpiresAt && BindingCurrent(issued))
            return InstalledView("installedReviewRequired", issued) with { ConfirmationKey = issued.Key };
        return new(CaptureLocalIdentity() is null ? "needsLocalIdentity" : "identityCheckRequired");
    }

    private async Task<FirstUseOnlineIdentityObservation> ReviewInstalledIdentityAsync(long revision, string? key, CancellationToken token)
    {
        if (revision < 0 || key is not null && !LocalFirstUseValidation.Id(key))
            throw new LocalFirstUseException("firstUse.invalid_request");
        if (!await _identityGate.WaitAsync(0, token).ConfigureAwait(false))
            throw new LocalFirstUseException("firstUse.operation_in_progress");
        try
        {
            var issued = _installedReview; _installedReview = null;
            if (!HasInstalledOnlineAccount || _accepted?.Revision != revision)
                return new("contextChanged");
            var commit = _onlineCommit;
            var installedMode = _accepted!;
            var owner = commit?.Graph.Installation.Owner ?? account;
            var local = CaptureLocalIdentity();
            if (local is null) return new("needsLocalIdentity");
            if (key is not null && (issued is null || issued.Key != key || !BindingCurrent(issued) ||
                _identityTime.GetUtcNow() >= issued.ExpiresAt)) return new("contextChanged");
            var result = await owner.ReadInstalledFirstUseIdentityAsync(token).ConfigureAwait(false);
            token.ThrowIfCancellationRequested();
            if (!HasInstalledOnlineAccount || _accepted != installedMode || !ReferenceEquals(_onlineCommit, commit) || CaptureLocalIdentity() != local)
                return new("contextChanged");
            if (result is not { State: "observed", Facts: not null }) return new(result.State);
            var assessment = Assess(result.Facts, local.Profile.Handle);
            var next = new InstalledReview(Guid.NewGuid().ToString("N"), commit, owner, installedMode, local, result.Facts, _identityTime.GetUtcNow().AddMinutes(2));
            if (assessment != "match") { _installedBinding = null; return InstalledView(assessment, next); }
            if (!BindingCurrent(next)) return new("contextChanged");
            if (key is null && InstalledIdentityBound)
            {
                _installedBinding = next;
                return InstalledView("boundOnlineIdentity", next);
            }
            if (key is not null && issued!.Facts.Context == next.Facts.Context && issued.Facts.Generation == next.Facts.Generation &&
                issued.Facts.Session.AuthoritativeGameIdentity == next.Facts.Session.AuthoritativeGameIdentity &&
                issued.Facts.Session.DisplayName == next.Facts.Session.DisplayName && _identityTime.GetUtcNow() < issued.ExpiresAt)
            {
                if (commit is null && !RecordConfirmedCompletion(next))
                {
                    // Recording stays closed. The same review can be confirmed
                    // again once the data folder is writable.
                    _installedReview = next;
                    throw new LocalFirstUseException("firstUse.completion_write_failed");
                }
                _installedBinding = next;
                return InstalledView("boundOnlineIdentity", next);
            }
            _installedReview = next;
            return InstalledView("installedReviewRequired", next) with { ConfirmationKey = next.Key };
        }
        finally { _identityGate.Release(); }
    }

    private static FirstUseOnlineIdentityObservation InstalledView(string state, InstalledReview value) =>
        new(state, value.Local.Profile.Handle, value.Facts.Session.AuthoritativeGameIdentity.Handle ??
            value.Facts.Session.AuthoritativeGameIdentity.NormalizedHandle, value.Facts.Session.DisplayName);
}
