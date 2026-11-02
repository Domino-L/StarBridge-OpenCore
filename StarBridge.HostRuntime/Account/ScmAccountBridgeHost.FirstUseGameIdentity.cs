using System.Text.Json;
using StarBridge.Core.Identity;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Onboarding;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    internal async Task<object> FirstUseGameIdentityAsync(string command, JsonElement payload,
        Func<bool> current, CancellationToken token)
    {
        var (gameName, contact) = ValidateGameIdentityPayload(command, payload);
        var operation = new object();
        ScmOAuthSession owner;
        long generation;
        await _mutationGate.WaitAsync(token).ConfigureAwait(false);
        try
        {
            RequireFirstUseGameIdentityContext(current);
            var session = Volatile.Read(ref _session);
            if (FirstUseSignInState != "identityCheckRequired" || session is null)
                return command == GameIdentityBridge.OpenProfile ? new { schemaVersion = 1, opened = false }
                    : GameIdentityOutcome("unavailable");
            owner = session; generation = Generation;
            if (owner.AuthoritativeGameIdentity.Status == ScmGameIdentityStatus.Verified)
                return command == GameIdentityBridge.OpenProfile ? new { schemaVersion = 1, opened = false }
                    : GameIdentityOutcome("alreadyVerified");
            if (owner.AuthoritativeGameIdentity.Status is not (ScmGameIdentityStatus.Unverified or
                ScmGameIdentityStatus.ReverifyRequired or ScmGameIdentityStatus.Revoked))
                return command == GameIdentityBridge.OpenProfile ? new { schemaVersion = 1, opened = false }
                    : GameIdentityOutcome("unavailable");
            if (_gameIdentityOperation is not null && _gameIdentityOperationGeneration == generation)
                throw new LocalFirstUseException("firstUse.operation_in_progress");
            if (command != GameIdentityBridge.OpenProfile &&
                !owner.Capabilities.Contains("game_identity.verify", StringComparer.Ordinal))
                return GameIdentityOutcome("reauthorizationRequired");
            _gameIdentityOperation = operation; _gameIdentityOperationGeneration = generation;
        }
        finally { _mutationGate.Release(); }

        var active = owner;
        void RequireOwner()
        {
            RequireFirstUseGameIdentityContext(current);
            if (Generation != generation || !ReferenceEquals(Volatile.Read(ref _session), active) ||
                _freshSignInPending || _reauthorizationRequired || _credentialTemporarilyUnavailable)
                throw new LocalFirstUseException("firstUse.context_changed");
        }
        void Adopt(ScmOAuthSession candidate)
        {
            _mutationGate.WaitAsync(token).GetAwaiter().GetResult();
            try
            {
                RequireOwner(); token.ThrowIfCancellationRequested();
                RequireSameSession(owner, candidate);
                if (!_oauth.IsFreshFirstUseSessionCurrent(candidate))
                    throw new LocalFirstUseException("firstUse.context_changed");
                // Identity metadata only, same original owner and generation.
                Volatile.Write(ref _session, candidate); active = candidate;
                if (candidate.AuthoritativeGameIdentity.Status != ScmGameIdentityStatus.Verified &&
                    !candidate.Capabilities.Contains("game_identity.verify", StringComparer.Ordinal))
                    throw new ScmApiForbiddenException("SCM game identity permission is unavailable.");
            }
            finally { _mutationGate.Release(); }
        }
        async Task<ScmOAuthSession> ReadIdentity(ScmOAuthSession session, CancellationToken ct,
            Action<ScmOAuthSession>? ready)
        {
            RequireOwner();
            var read = await _oauth.RefreshFirstUseIdentityAsync(session, ct).ConfigureAwait(false);
            ct.ThrowIfCancellationRequested(); ready?.Invoke(read); return read;
        }
        try
        {
            object response;
            try
            {
                RequireOwner(); token.ThrowIfCancellationRequested();
                if (command == GameIdentityBridge.OpenProfile)
                    response = new { schemaVersion = 1, opened = _oauth.OpenGameIdentityProfile() };
                else if (command == GameIdentityBridge.RequestCode)
                {
                    var code = await _oauth.GetFirstUseGameIdentityCodeAsync(owner, gameName!, token).ConfigureAwait(false);
                    response = !code.Available ? GameIdentityOutcome("unavailable") : !code.Success ? GameIdentityRejection(code.Message)
                        : string.IsNullOrWhiteSpace(code.VerificationCode) || code.ExpireTime <= 0 ? GameIdentityOutcome("unavailable")
                        : new { schemaVersion = 1, outcome = "issued", verificationCode = code.VerificationCode, expiresInSeconds = code.ExpireTime };
                }
                else
                {
                    var attempt = await new ScmGameIdentityVerificationCoordinator(_oauth, ReadIdentity,
                        _oauth.VerifyFirstUseGameIdentityAsync).VerifyAsync(owner, gameName!, contact!, token, Adopt).ConfigureAwait(false);
                    response = attempt.Accepted && attempt.ActiveSession.AuthoritativeGameIdentity is
                        { Status: ScmGameIdentityStatus.Verified, CanonicalHandle: { } handle }
                        ? new { schemaVersion = 1, outcome = "verified", authoritativeHandle = attempt.ActiveSession.GameIdentityHandle ?? handle }
                        : attempt.Accepted || attempt.OutcomeUnknown ? GameIdentityOutcome("outcomeUnknown") : GameIdentityRejection(attempt.Message);
                }
            }
            catch (ScmApiForbiddenException) { response = GameIdentityOutcome("reauthorizationRequired"); }
            catch (ScmApiAuthenticationException) { response = GameIdentityOutcome("reauthorizationRequired"); }
            catch (OperationCanceledException) when (!token.IsCancellationRequested)
            { response = GameIdentityOutcome(command == GameIdentityBridge.Verify ? "outcomeUnknown" : "unavailable"); }
            catch (Exception error) when (error is HttpRequestException or IOException or InvalidOperationException or JsonException)
            { response = GameIdentityOutcome(command == GameIdentityBridge.Verify ? "outcomeUnknown" : "unavailable"); }
            await _mutationGate.WaitAsync(token).ConfigureAwait(false);
            try { RequireOwner(); token.ThrowIfCancellationRequested(); return response; }
            finally { _mutationGate.Release(); }
        }
        finally
        {
            if (!_disposed)
            {
                await _mutationGate.WaitAsync().ConfigureAwait(false);
                try { if (ReferenceEquals(_gameIdentityOperation, operation)) _gameIdentityOperation = null; }
                finally { _mutationGate.Release(); }
            }
            // No installed account event, participation wakeup or publication.
        }
    }

    private void RequireFirstUseGameIdentityContext(Func<bool> current)
    {
        if (_disposed || !current() || !IsFirstUseAuthenticationCandidate || _localModeSessionLoopsStopped)
            throw new LocalFirstUseException("firstUse.context_changed");
    }
}
