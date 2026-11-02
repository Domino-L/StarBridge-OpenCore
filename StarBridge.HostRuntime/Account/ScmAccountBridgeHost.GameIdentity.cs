using System.Text.Json;
using StarBridge.Core.Identity;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal static class GameIdentityBridge
{
    internal const string Capability = "account.gameIdentity.v1";
    internal const string RequestCode = "account.gameIdentity.requestCode";
    internal const string Verify = "account.gameIdentity.verify";
    internal const string OpenProfile = "account.gameIdentity.openRsiProfile";
    internal static bool IsRequest(string name) => name is RequestCode or Verify or OpenProfile;
}

internal sealed partial class ScmAccountBridgeHost
{
    internal event Action<long>? GameIdentityChanged;
    private object? _gameIdentityOperation;
    private long _gameIdentityOperationGeneration = -1;
    internal bool HasGameIdentityBridge => !_disposed && _session is not null && _legacySession is null &&
        !_reauthorizationRequired && !_credentialTemporarilyUnavailable && !_localModeSessionLoopsStopped &&
        !IsBusinessStartupDeferred;

    internal async Task<object> GameIdentityAsync(BridgeAccountContext context, long generation,
        string command, JsonElement payload, CancellationToken token)
    {
        var (gameName, contact) = ValidateGameIdentityPayload(command, payload);
        ScmOAuthSession owner;
        var operation = new object();
        await _mutationGate.WaitAsync(token).ConfigureAwait(false);
        try
        {
            RequireGameIdentityOwner(context, generation);
            owner = RequireSession(context);
            if (command != GameIdentityBridge.OpenProfile)
            {
                if (owner.AuthoritativeGameIdentity.Status == ScmGameIdentityStatus.Verified)
                    return GameIdentityOutcome("alreadyVerified");
                if (!owner.Capabilities.Contains("game_identity.verify", StringComparer.Ordinal))
                    return GameIdentityOutcome("reauthorizationRequired");
                if (_gameIdentityOperation is not null && _gameIdentityOperationGeneration == generation)
                    throw new AccountBridgeHostException(AccountBridgeStableErrors.OperationInProgress);
                _gameIdentityOperation = operation;
                _gameIdentityOperationGeneration = generation;
            }
        }
        finally { _mutationGate.Release(); }
        if (command == GameIdentityBridge.OpenProfile)
            return new { schemaVersion = 1, opened = _oauth.OpenGameIdentityProfile() };

        var active = owner;
        // OAuth invokes this after committing a refresh, before resource IO.
        // Adopt even if caller cancellation arrives after that commit. This
        // short lease never encloses a network request or a browser operation.
        void Adopt(ScmOAuthSession candidate)
        {
            if (_disposed) throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
            _mutationGate.WaitAsync().GetAwaiter().GetResult();
            try
            {
                RequireGameIdentityOwner(context, generation);
                RequireSameSession(owner, candidate);
                RequireSameSession(owner, RequireSession(context));
                CommitSharingSession(new RelayRequestSession(active), new RelayRequestSession(candidate));
                active = candidate;
                if (candidate.AuthoritativeGameIdentity.Status != ScmGameIdentityStatus.Verified &&
                    !candidate.Capabilities.Contains("game_identity.verify", StringComparer.Ordinal))
                    throw new ScmApiForbiddenException("SCM game identity permission is unavailable.");
            }
            finally { _mutationGate.Release(); }
        }

        try
        {
            object response;
            ScmGameIdentitySnapshot? verifiedIdentity = null;
            try
            {
                if (command == GameIdentityBridge.RequestCode)
                {
                    var code = await _oauth.GetGameIdentityVerificationCodeAsync(owner, gameName!, token, Adopt).ConfigureAwait(false);
                    response = !code.Available ? GameIdentityOutcome("unavailable")
                        : !code.Success ? GameIdentityRejection(code.Message)
                        : string.IsNullOrWhiteSpace(code.VerificationCode) || code.ExpireTime <= 0 ? GameIdentityOutcome("unavailable")
                        : new { schemaVersion = 1, outcome = "issued", verificationCode = code.VerificationCode, expiresInSeconds = code.ExpireTime };
                }
                else
                {
                    var attempt = await new ScmGameIdentityVerificationCoordinator(_oauth).VerifyAsync(
                        owner, gameName!, contact!, token, Adopt).ConfigureAwait(false);
                    response = attempt.Accepted && attempt.ActiveSession.AuthoritativeGameIdentity is
                        { Status: ScmGameIdentityStatus.Verified, CanonicalHandle: { } handle }
                        ? new { schemaVersion = 1, outcome = "verified", authoritativeHandle = attempt.ActiveSession.GameIdentityHandle ?? handle }
                        : attempt.Accepted || attempt.OutcomeUnknown ? GameIdentityOutcome("outcomeUnknown")
                        : GameIdentityRejection(attempt.Message);
                    if (attempt.Accepted) verifiedIdentity = attempt.ActiveSession.AuthoritativeGameIdentity;
                }
            }
            catch (ScmApiForbiddenException) { response = GameIdentityOutcome("reauthorizationRequired"); }
            catch (ScmApiAuthenticationException) { response = GameIdentityOutcome("reauthorizationRequired"); }
            catch (OperationCanceledException) when (!token.IsCancellationRequested)
            { response = GameIdentityOutcome(command == GameIdentityBridge.Verify ? "outcomeUnknown" : "unavailable"); }
            catch (Exception error) when (error is HttpRequestException or IOException or InvalidOperationException or JsonException)
            { response = GameIdentityOutcome(command == GameIdentityBridge.Verify ? "outcomeUnknown" : "unavailable"); }

            if (_disposed) throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
            await _mutationGate.WaitAsync().ConfigureAwait(false);
            try
            {
                RequireGameIdentityOwner(context, generation);
                RequireSameSession(owner, RequireSession(context));
                token.ThrowIfCancellationRequested();
                if (verifiedIdentity is not null && _session!.AuthoritativeGameIdentity != verifiedIdentity)
                    return GameIdentityOutcome("outcomeUnknown");
                return response;
            }
            finally { _mutationGate.Release(); }
        }
        finally
        {
            var identityChanged = false;
            if (!_disposed)
            {
                await _mutationGate.WaitAsync().ConfigureAwait(false);
                try
                {
                    if (ReferenceEquals(_gameIdentityOperation, operation)) _gameIdentityOperation = null;
                    if (!_disposed && Generation == generation && CurrentContext == context &&
                        _session is { } current && current.AuthoritativeGameIdentity != owner.AuthoritativeGameIdentity)
                    {
                        _participationNextCheck = default;
                        identityChanged = true;
                    }
                }
                finally { _mutationGate.Release(); }
            }
            // Identity metadata keeps the account generation and its leases.
            // Subscribers may re-read the committed state, so notify outside the gate.
            if (identityChanged)
            {
                WakeParticipantLoop();
                GameIdentityChanged?.Invoke(generation);
            }
        }
    }

    private void RequireGameIdentityOwner(BridgeAccountContext context, long generation)
    {
        if (generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
        if (!HasGameIdentityBridge || CurrentContext != context)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
    }

    private static object GameIdentityOutcome(string outcome) => new { schemaVersion = 1, outcome };
    private static object GameIdentityRejection(string? message) => new Dictionary<string, object?>
    {
        ["schemaVersion"] = 1, ["outcome"] = "rejected", ["message"] = message is { Length: > 512 } ? message[..512] : message
    };

    internal static (string? GameName, string? Contact) ValidateGameIdentityPayload(string command, JsonElement payload)
    {
        var keys = command switch
        {
            GameIdentityBridge.RequestCode => new[] { "schemaVersion", "gameName" },
            GameIdentityBridge.Verify => ["schemaVersion", "gameName", "contact"],
            GameIdentityBridge.OpenProfile => ["schemaVersion"],
            _ => throw new AccountBridgeHostException(BridgeErrorCodes.CapabilityUnavailable)
        };
        if (payload.ValueKind != JsonValueKind.Object || payload.EnumerateObject().Count() != keys.Length ||
            payload.EnumerateObject().Any(p => !keys.Contains(p.Name, StringComparer.Ordinal)) ||
            keys.Any(key => !payload.TryGetProperty(key, out _)) ||
            !payload.TryGetProperty("schemaVersion", out var schema) || schema.ValueKind != JsonValueKind.Number ||
            !schema.TryGetInt32(out var version) || version != 1)
            throw new AccountBridgeHostException(BridgeErrorCodes.InvalidEnvelope);
        if (command == GameIdentityBridge.OpenProfile) return (null, null);
        var name = payload.GetProperty("gameName");
        if (name.ValueKind != JsonValueKind.String || name.GetString()?.Trim() is not { Length: >= 3 } gameName ||
            !IdentityBindingPolicy.IsValidGameName(gameName))
            throw new AccountBridgeHostException(BridgeErrorCodes.InvalidEnvelope);
        if (command != GameIdentityBridge.Verify) return (gameName, null);
        var contactValue = payload.GetProperty("contact");
        if (contactValue.ValueKind != JsonValueKind.String || contactValue.GetString()?.Trim() is not { Length: >= 7 and <= 256 } contact)
            throw new AccountBridgeHostException(BridgeErrorCodes.InvalidEnvelope);
        return (gameName, contact);
    }
}
