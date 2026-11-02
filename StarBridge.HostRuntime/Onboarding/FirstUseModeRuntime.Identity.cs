using StarBridge.Core.Identity;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Onboarding;

// Display-only facts. No account key, profile ID, token, filesystem path or
// authorization flag enters this view. Confirmation is only a handoff precondition.
internal sealed record FirstUseOnlineIdentityObservation(string State, string? LocalHandle = null,
    string? AuthoritativeHandle = null, string? AccountDisplayName = null, string? ConfirmationKey = null);

internal sealed partial class FirstUseModeRuntime
{
    private readonly SemaphoreSlim _identityGate = new(1, 1);
    private readonly TimeProvider _identityTime = time ?? TimeProvider.System;
    private volatile IdentityReview? _issuedIdentity, _confirmedIdentity;
    internal sealed record LocalIdentityScope(LocalFirstUseSource Source, LocalDeviceProfile Profile);
    private sealed record IdentityScope(FirstUseModeChoice Pending, AccountBridgeRuntime Candidate, LocalIdentityScope? Local, bool AccountOnly);
    private sealed record IdentityReview(string Key, IdentityScope Scope, FirstUseScmIdentityFacts Facts,
        DateTimeOffset CreatedAt, DateTimeOffset ExpiresAt);

    // Side-effect-free projection: no identity refresh, key issuance, restore or
    // confirmation. A polling client must not consume an already issued review.
    internal FirstUseOnlineIdentityObservation CurrentOnlineIdentity(long revision)
    {
        if (HasInstalledOnlineAccount) return CurrentInstalledIdentity(revision);
        try
        {
            var (state, scope) = CaptureIdentityScope(revision);
            if (scope is null)
                return new(state == "signInRequired" && _candidateStart is null &&
                    store.ReadOnlineOrigin()?.CandidateStarted == true ? "recoveryRequired" : state);
            if (_handoffPreparing || _preparedOnline is { IsCurrent: true }) return new("operationInProgress", scope.Local?.Profile.Handle);
            if (scope.Candidate.FirstUseAuthenticationSealed) return new("operationInProgress", scope.Local?.Profile.Handle);
            if (_confirmedIdentity is { } confirmed && IsReviewCurrent(confirmed))
                return View(ConfirmedState(confirmed.Scope), confirmed.Scope, confirmed.Facts);
            if (_issuedIdentity is { } issued && IsReviewCurrent(issued))
                return View(ReviewState(issued.Scope), issued.Scope, issued.Facts) with { ConfirmationKey = issued.Key };
            return new(scope.Candidate.RequiresFirstUseGameIdentityReauthorization(OnlineIntent(scope.Pending))
                ? "reauthorizationRequired" : scope.Candidate.FirstUseSignInState(OnlineIntent(scope.Pending)), scope.Local?.Profile.Handle);
        }
        catch (LocalFirstUseException) { return new("unavailable"); }
    }

    internal async Task<FirstUseOnlineIdentityObservation> ReadOnlineIdentityAsync(long revision,
        CancellationToken token = default)
    {
        if (HasInstalledOnlineAccount) return await ReviewInstalledIdentityAsync(revision, null, token).ConfigureAwait(false);
        if (revision < 0) throw new LocalFirstUseException("firstUse.invalid_request");
        if (!await _identityGate.WaitAsync(0, token).ConfigureAwait(false))
            throw new LocalFirstUseException("firstUse.operation_in_progress");
        try
        {
            if (_candidateStart is { IsCompletedSuccessfully: true } start && start.Result.FirstUseAuthenticationSealed)
                return CurrentOnlineIdentity(revision);
            _issuedIdentity = null; _confirmedIdentity = null;
            var (state, scope) = CaptureIdentityScope(revision);
            if (scope is null) return new(state);
            return await ReviewIdentityCoreAsync(scope, token).ConfigureAwait(false);
        }
        catch (LocalFirstUseException) { return new("unavailable"); }
        finally { _identityGate.Release(); }
    }

    internal async Task<FirstUseOnlineIdentityObservation> ConfirmOnlineIdentityAsync(long revision, string confirmationKey,
        CancellationToken token = default)
    {
        if (HasInstalledOnlineAccount) return await ReviewInstalledIdentityAsync(revision, confirmationKey, token).ConfigureAwait(false);
        if (revision < 0 || !LocalFirstUseValidation.Id(confirmationKey))
            throw new LocalFirstUseException("firstUse.invalid_request");
        if (!await _identityGate.WaitAsync(0, token).ConfigureAwait(false))
            throw new LocalFirstUseException("firstUse.operation_in_progress");
        try
        {
            if (_candidateStart is { IsCompletedSuccessfully: true } start && start.Result.FirstUseAuthenticationSealed)
                return CurrentOnlineIdentity(revision);
            var issued = _issuedIdentity; _issuedIdentity = null; _confirmedIdentity = null;
            if (issued is null || issued.Key != confirmationKey || issued.Scope.Pending.Revision != revision ||
                !IsIdentityScopeCurrent(issued.Scope)) throw new LocalFirstUseException("firstUse.context_changed");
            if (!WithinReview(issued)) return new("reviewExpired");
            // An actual readback is required. Login's snapshot or a cached policy
            // cannot prove that verification has not been revoked since review.
            var read = await issued.Scope.Candidate.ReadFirstUseIdentityAsync(OnlineIntent(issued.Scope.Pending), token).ConfigureAwait(false);
            token.ThrowIfCancellationRequested();
            if (!IsIdentityScopeCurrent(issued.Scope) || !WithinReview(issued)) return new("contextChanged");
            if (read.Facts is not { } current || read.State != "observed") return View(read.State, issued.Scope);
            var assessed = AssessScope(current, issued.Scope);
            if (assessed != "match") return View(assessed, issued.Scope, current);
            if (issued.Facts.Context != current.Context || issued.Facts.Generation != current.Generation ||
                issued.Facts.Session.AuthoritativeGameIdentity.CanonicalHandle != current.Session.AuthoritativeGameIdentity.CanonicalHandle ||
                issued.Facts.Session.DisplayName != current.Session.DisplayName)
                return IssueReview(issued.Scope, current); // Changed review is not implicit acceptance.
            var confirmed = issued with { Facts = current };
            if (!IsReviewCurrent(confirmed)) return new("contextChanged");
            _confirmedIdentity = confirmed;
            return View(ConfirmedState(issued.Scope), issued.Scope, current);
        }
        finally { _identityGate.Release(); }
    }

    // Live Native-only precondition. No persistence and no generic permission
    // boolean: composition still needs unique owner/generation installation and
    // separate consent/ownership decisions before actual business activation.
    internal bool HasConfirmedOnlineIdentity(long revision)
    {
        if (HasInstalledOnlineAccount) return revision == _accepted?.Revision && HasInstalledOnlineForCompletion;
        var confirmed = _confirmedIdentity;
        return confirmed is not null && !confirmed.Scope.AccountOnly && confirmed.Scope.Pending.Revision == revision && IsReviewCurrent(confirmed);
    }

    internal bool HasConfirmedOnlineAccount(long revision) => _confirmedIdentity is { } confirmed &&
        confirmed.Scope.Pending.Revision == revision && IsReviewCurrent(confirmed);

    private async Task<FirstUseOnlineIdentityObservation> ReviewIdentityCoreAsync(IdentityScope scope, CancellationToken token)
    {
        var read = await scope.Candidate.ReadFirstUseIdentityAsync(OnlineIntent(scope.Pending), token).ConfigureAwait(false);
        token.ThrowIfCancellationRequested();
        if (!IsIdentityScopeCurrent(scope)) return new("contextChanged");
        if (read.Facts is not { } facts || read.State != "observed") return View(read.State, scope);
        var assessed = AssessScope(facts, scope);
        // Retained account-only restoration does not require a local Handle,
        // but still requires verified SCM authority before entering online.
        // Explicit game verification keeps its stricter local identity review.
        if (assessed != "match" && !HasExplicitGameIdentityReview(scope) &&
            OnlineIntent(scope.Pending).RetainSession && scope.Candidate.RetainsFirstUseSession)
        {
            scope = scope with { AccountOnly = true };
            assessed = AssessScope(facts, scope);
        }
        return assessed == "match" ? IssueReview(scope, facts) : View(assessed, scope, facts);
    }

    private FirstUseOnlineIdentityObservation IssueReview(IdentityScope scope, FirstUseScmIdentityFacts facts)
    {
        var now = _identityTime.GetUtcNow();
        var issued = new IdentityReview(Guid.NewGuid().ToString("N"), scope, facts, now, now.AddMinutes(2));
        if (!IsReviewCurrent(issued)) return new("contextChanged");
        _issuedIdentity = issued;
        return View(ReviewState(scope), scope, facts) with { ConfirmationKey = issued.Key };
    }

    private (string State, IdentityScope? Scope) CaptureIdentityScope(long revision)
    {
        var pending = _accepted;
        if (_closed || pending is null || pending.Revision != revision || store.Read() != pending || !LocalMode().Active)
            return ("contextChanged", null);
        if (pending.Phase != "onlinePending") return ("notStarted", null);
        var start = _candidateStart;
        if (_candidateCancel is not null) return ("contextChanged", null);
        if (start is null) return ("signInRequired", null);
        if (!start.IsCompleted) return ("authorizing", null);
        if (!start.IsCompletedSuccessfully || !start.Result.IsFirstUseOnlineCandidateFor(OnlineIntent(pending)))
            return ("unavailable", null);
        var local = CaptureLocalIdentity();
        if (local is null && !OnlineIntent(pending).RetainSession) return ("needsLocalIdentity", null);
        var scope = new IdentityScope(pending, start.Result, local, local is null);
        return IsIdentityScopeCurrent(scope) ? ("observed", scope) : ("contextChanged", null);
    }

    private LocalIdentityScope? CaptureLocalIdentity()
    {
        var saved = identities.Read();
        var source = saved.Sources.SingleOrDefault(value => value.SourceKey == saved.SelectedSourceKey);
        var profile = saved.Profiles.SingleOrDefault(value => value.Id == source?.ConfirmedProfileId);
        var now = _identityTime.GetUtcNow();
        return source is not null && profile is not null && saved.ActiveProfileId == profile.Id && !source.NeedsFreshGameEvidence &&
            source.ConfirmedObservedAt is { } observed && observed <= now && profile.ConfirmedAt <= now &&
            LocalFirstUseValidation.Handle(profile.Handle) ? new(source, profile) : null;
    }

    private bool IsIdentityScopeCurrent(IdentityScope scope)
    {
        try
        {
            return !_closed && !_changing && _accepted == scope.Pending && store.Read() == scope.Pending && LocalMode().Active &&
                _candidateCancel is null && _candidateStart is { IsCompletedSuccessfully: true } start &&
                ReferenceEquals(start.Result, scope.Candidate) && scope.Candidate.IsFirstUseOnlineCandidateFor(OnlineIntent(scope.Pending)) &&
                (scope.AccountOnly || CaptureLocalIdentity() == scope.Local);
        }
        catch (LocalFirstUseException) { return false; }
    }
    private bool WithinReview(IdentityReview value)
    {
        var now = _identityTime.GetUtcNow();
        return now >= value.CreatedAt && now < value.ExpiresAt;
    }
    private bool IsReviewCurrent(IdentityReview value) => WithinReview(value) && IsIdentityScopeCurrent(value.Scope) &&
        value.Scope.Candidate.IsFirstUseIdentityCurrent(OnlineIntent(value.Scope.Pending), value.Facts) &&
        AssessScope(value.Facts, value.Scope) == "match";

    private string AssessScope(FirstUseScmIdentityFacts facts, IdentityScope scope) =>
        facts.Session.RequiresFirstUseGameIdentityReauthorization ? "reauthorizationRequired" :
        !scope.AccountOnly && scope.Local is { } local ? Assess(facts, local.Profile.Handle) :
        OnlineIntent(scope.Pending).RetainSession && scope.Candidate.RetainsFirstUseSession &&
        scope.Candidate.IsFirstUseIdentityCurrent(OnlineIntent(scope.Pending), facts) ? Assess(facts, null) : "needsLocalIdentity";
    private static string ReviewState(IdentityScope scope) => scope.AccountOnly ? "accountReviewRequired" : "reviewRequired";
    private static string ConfirmedState(IdentityScope scope) => scope.AccountOnly ? "accountConfirmedForHandoff" : "confirmedForHandoff";

    private static string Assess(FirstUseScmIdentityFacts facts, string? localHandle) =>
        IdentityBindingPolicy.Evaluate(facts.Session.AuthoritativeGameIdentity, localHandle).State switch
        {
            IdentityVerificationState.Verified => "match",
            IdentityVerificationState.Mismatch => "mismatch",
            IdentityVerificationState.BindingRequired => "verificationRequired",
            IdentityVerificationState.VerificationPending => "verificationPending",
            IdentityVerificationState.ReverificationRequired => "reverifyRequired",
            IdentityVerificationState.Revoked => "revoked",
            _ => "unavailable"
        };
    private static FirstUseOnlineIdentityObservation View(string state, IdentityScope scope, FirstUseScmIdentityFacts? facts = null) =>
        new(state, scope.AccountOnly ? null : scope.Local?.Profile.Handle, facts?.Session.AuthoritativeGameIdentity.Handle ??
            facts?.Session.AuthoritativeGameIdentity.NormalizedHandle, facts?.Session.DisplayName);
}
