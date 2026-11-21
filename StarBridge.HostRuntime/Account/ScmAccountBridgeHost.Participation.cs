using StarBridge.HostRuntime.Auth;
using StarBridge.Core.Identity;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    private long _participationAttemptGeneration = -1;
    private long _participationCheckGeneration = -1;
    private DateTimeOffset _participationNextCheck;
    private sealed record ParticipantIdentity(BridgeAccountContext Owner, long Generation, string SubjectId);
    private ParticipantIdentity? _participantIdentity;
    internal TimeProvider ParticipantClock { get; init; } = TimeProvider.System;

    // A session lifecycle step, not a side effect of searching another participant.
    // One registration per authenticated generation. Later refreshes cannot create an identity.
    private async Task EnsureParticipantEnrollmentAsync(CancellationToken token, bool waitForMutation = false)
    {
        if (IsBusinessStartupDeferred) return;
        using var business = _businessStartupDeferred ? _firstUseBusinessAdmission?.Enter(token) : null;
        if (_businessStartupDeferred && business is null) return;
        token = business?.Token ?? token;
        // Background enrollment joins the existing fair writer queue; brief
        // sharing reads must not make it miss every one-minute cycle.
        // Root account reads keep zero-wait admission.
        var mutationWait = waitForMutation ? TimeSpan.FromSeconds(5) : TimeSpan.Zero;
        if (!await _mutationGate.WaitAsync(mutationWait, token)) return;
        try {
            var session = _session;
            var generation = Generation;
            var owner = CurrentContext;
            if (_participantIdentity is { } cached && (cached.Owner != owner || cached.Generation != generation) ||
                session is null || _credentialTemporarilyUnavailable || _reauthorizationRequired ||
                session.AuthoritativeGameIdentity.Status is ScmGameIdentityStatus.Unverified or ScmGameIdentityStatus.Pending)
                _participantIdentity = null;
            if (_disposed || session is null || _credentialTemporarilyUnavailable || _reauthorizationRequired ||
                (_participationCheckGeneration == generation && ParticipantClock.GetUtcNow() < _participationNextCheck)) return;
            _participationCheckGeneration = generation;
            _participationNextCheck = ParticipantClock.GetUtcNow().AddMinutes(1);
            using var budget = CancellationTokenSource.CreateLinkedTokenSource(token);
            budget.CancelAfter(TimeSpan.FromSeconds(5));
            try {
                if (session.AuthoritativeGameIdentity.Status is ScmGameIdentityStatus.Unverified or ScmGameIdentityStatus.Pending) return;
                string subjectId;
                ScmOAuthSession active;
                if (_participantIdentity is { } stable) {
                    subjectId = stable.SubjectId;
                    active = await _oauth.PrepareParticipantSessionAsync(session, budget.Token);
                } else {
                    var identity = await _oauth.LoadBusinessIdentityAsync(session, budget.Token);
                    subjectId = identity.BusinessSubjectId;
                    active = identity.ActiveSession;
                }
                if (_disposed || Generation != generation || _session != session ||
                    business is not null && (!business.IsCurrent || _firstUseBusinessAdmission?.IsActive != true)) {
                    _participantIdentity = null;
                    return;
                }
                RequireSameSession(session, active);
                _session = active;
                budget.Token.ThrowIfCancellationRequested();
                if (active.AuthoritativeGameIdentity.Status is ScmGameIdentityStatus.Unverified or ScmGameIdentityStatus.Pending) {
                    _participantIdentity = null;
                    return;
                }
                var refreshOnly = _participationAttemptGeneration == generation;
                _participationAttemptGeneration = generation;
                await _oauth.RegisterParticipantAsync(active, subjectId, budget.Token, refreshOnly);
                // Only a matching receipt establishes a reusable key. It is
                // navigation data for this lifecycle, never an authorization.
                if (!_disposed && Generation == generation && _session == active && CurrentContext == owner && owner is not null &&
                    (business is null || business.IsCurrent && _firstUseBusinessAdmission?.IsActive == true))
                    _participantIdentity = new(owner, generation, subjectId);
                else _participantIdentity = null;
            }
            catch (OperationCanceledException) when (token.IsCancellationRequested) {
                _participantIdentity = null;
                if (_participationAttemptGeneration != generation) _participationNextCheck = default;
                throw;
            }
            catch (OperationCanceledException) when (!token.IsCancellationRequested) { _participantIdentity = null; }
            catch (Exception error) when (error is HttpRequestException or IOException or InvalidOperationException or System.Text.Json.JsonException) {
                _participantIdentity = null;
                // Discovery availability must not erase an otherwise valid SCM login.
                // Normal business actions retain their explicit self-registration path.
            }
            catch { _participantIdentity = null; throw; }
        }
        finally { _mutationGate.Release(); }
    }
}
