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
            try
            {
                // History only avoids repeating an already acknowledged setup.
                // Authority still requires THIS restored session, selected local
                // identity, live vault lineage and fresh verified identity match.
                if (_installedBinding is null && _onlineCommit is null && HasInstalledOnlineAccount &&
                    CaptureLocalIdentity() is { } local && ColdCompletionHistory?.Read() is { Mode: "online" } previous &&
                    previous.ProfileId == local.Profile.Id && previous.SourceKey == local.Source.SourceKey &&
                    account.CurrentColdFirstUseFacts() is { } facts && Assess(facts, local.Profile.Handle) == "match")
                    _installedBinding = new(Guid.NewGuid().ToString("N"), null, account, _accepted!, local, facts, DateTimeOffset.MaxValue);
                return _installedBinding is { } value && BindingCurrent(value);
            }
            catch { return false; }
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
