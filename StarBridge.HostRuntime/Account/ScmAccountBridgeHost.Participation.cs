using StarBridge.HostRuntime.Auth;
using StarBridge.Core.Identity;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    private long _participationAttemptGeneration = -1;
    private long _participationCheckGeneration = -1;
    private DateTimeOffset _participationNextCheck;
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
            if (_disposed || session is null || _credentialTemporarilyUnavailable || _reauthorizationRequired ||
                (_participationCheckGeneration == generation && ParticipantClock.GetUtcNow() < _participationNextCheck)) return;
            _participationCheckGeneration = generation;
            _participationNextCheck = ParticipantClock.GetUtcNow().AddMinutes(1);
            using var budget = CancellationTokenSource.CreateLinkedTokenSource(token);
            budget.CancelAfter(TimeSpan.FromSeconds(5));
            try {
                if (session.AuthoritativeGameIdentity.Status is ScmGameIdentityStatus.Unverified or ScmGameIdentityStatus.Pending) return;
                var identity = await _oauth.LoadBusinessIdentityAsync(session, budget.Token);
                if (_disposed || Generation != generation || _session != session ||
                    business is not null && (!business.IsCurrent || _firstUseBusinessAdmission?.IsActive != true)) return;
                RequireSameSession(session, identity.ActiveSession);
                _session = identity.ActiveSession;
                budget.Token.ThrowIfCancellationRequested();
                if (identity.ActiveSession.AuthoritativeGameIdentity.Status is ScmGameIdentityStatus.Unverified or ScmGameIdentityStatus.Pending) return;
                var refreshOnly = _participationAttemptGeneration == generation;
                _participationAttemptGeneration = generation;
                await _oauth.RegisterParticipantAsync(identity.ActiveSession, identity.BusinessSubjectId, budget.Token, refreshOnly);
            }
            catch (OperationCanceledException) when (token.IsCancellationRequested) {
                if (_participationAttemptGeneration != generation) _participationNextCheck = default;
                throw;
            }
            catch (OperationCanceledException) when (!token.IsCancellationRequested) { }
            catch (Exception error) when (error is HttpRequestException or IOException or InvalidOperationException or System.Text.Json.JsonException) {
                // Discovery availability must not erase an otherwise valid SCM login.
                // Normal business actions retain their explicit self-registration path.
            }
        }
        finally { _mutationGate.Release(); }
    }
}
