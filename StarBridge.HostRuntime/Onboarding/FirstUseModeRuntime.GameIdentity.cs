using System.Text.Json;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Onboarding;

internal sealed partial class FirstUseModeRuntime
{
    // Account-only restoration also checks SCM verification. Once THIS candidate
    // explicitly verifies a game Handle, keep any local Handle mismatch visible
    // instead of falling back to account-only review, even on a rejected write.
    // The marker belongs only to this revision/generation, not durable permission.
    private long _gameIdentityReviewRevision = -1, _gameIdentityReviewGeneration = -1;
    private bool HasExplicitGameIdentityReview(IdentityScope scope) =>
        _gameIdentityReviewRevision == scope.Pending.Revision && _gameIdentityReviewGeneration == scope.Candidate.Generation;

    internal async Task<object> FirstUseGameIdentityAsync(long revision, string command, JsonElement payload,
        Func<bool> wireCurrent, CancellationToken token)
    {
        object Unavailable() => command == GameIdentityBridge.OpenProfile
            ? new { schemaVersion = 1, opened = false } : new { schemaVersion = 1, outcome = "unavailable" };
        if (Current.Revision != revision) throw new LocalFirstUseException("firstUse.context_changed");
        if (!HasAuthenticatedOnlineCandidate) return Unavailable();
        if (!await _identityGate.WaitAsync(0, token).ConfigureAwait(false))
            throw new LocalFirstUseException("firstUse.operation_in_progress");
        try
        {
            var pending = _accepted;
            if (_closed || _changing || !wireCurrent() || Current.Revision != revision)
                throw new LocalFirstUseException("firstUse.context_changed");
            if (pending is not { Phase: "onlinePending" } || !LocalMode().Active || _candidateCancel is not null ||
                _candidateStart is not { IsCompletedSuccessfully: true } start) return Unavailable();
            // This operation verifies the authenticated candidate independently of
            // a local profile. Local Handle matching stays in the existing review.
            var scope = new IdentityScope(pending, start.Result, null, true);
            bool CurrentOwner() => wireCurrent() && !scope.Candidate.FirstUseAuthenticationSealed && IsIdentityScopeCurrent(scope);
            if (!CurrentOwner()) return Unavailable();
            _issuedIdentity = null; _confirmedIdentity = null;
            if (command != GameIdentityBridge.OpenProfile)
            {
                _gameIdentityReviewRevision = pending.Revision;
                _gameIdentityReviewGeneration = scope.Candidate.Generation;
            }
            return await scope.Candidate.FirstUseGameIdentityAsync(OnlineIntent(pending), command, payload,
                CurrentOwner, token).ConfigureAwait(false);
        }
        finally { _identityGate.Release(); }
    }
}
