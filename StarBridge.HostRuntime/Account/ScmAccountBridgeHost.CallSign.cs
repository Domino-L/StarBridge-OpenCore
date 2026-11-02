using System.Net;
using System.Text.Json;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    private string? _scmDisplayCallSign;

    private static string? ValidDisplayCallSign(string? value) => value is { Length: > 0 and <= 32 } &&
        value == value.Trim() && !value.Any(char.IsControl) ? value : null;

    public async Task<object> UpdateCallSignAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token)
    {
        if (payload.ValueKind != JsonValueKind.Object || payload.EnumerateObject().Count() != 3 ||
            !payload.TryGetProperty("schemaVersion", out var schema) || !schema.TryGetInt32(out var version) || version != 1 ||
            !payload.TryGetProperty("callSign", out var name) || name.ValueKind != JsonValueKind.String ||
            !payload.TryGetProperty("expectedCallSign", out var expected) || expected.ValueKind != JsonValueKind.String ||
            ValidDisplayCallSign(name.GetString()) is not { } callSign || ValidDisplayCallSign(expected.GetString()) is not { } expectedCallSign)
            throw new AccountBridgeHostException("account.callsign_invalid");
        await _mutationGate.WaitAsync(token);
        var writeAttempted = false;
        try
        {
            var owner = RequireSession(context);
            var generation = Generation;
            void Current()
            {
                token.ThrowIfCancellationRequested();
                RequireSameSession(owner, RequireSession(context));
                if (_disposed || Generation != generation) throw new AccountBridgeHostException("account.reauthorization_required");
            }
            if (!owner.Capabilities.Contains("profile.read", StringComparer.Ordinal))
                throw new ScmApiForbiddenException("Call sign preflight requires profile.read.");
            var before = await GetPersonalProfileAsync(context, token);
            Current();
            if (before.Identity.Callsign != callSign)
            {
                // A draft may not overwrite a name changed by another device since the editor read it.
                if (before.Identity.Callsign != expectedCallSign) throw new AccountBridgeHostException("account.callsign_conflict");
                var grant = await _profileAuthorization.AuthorizeProfileWriteAsync(RequireSession(context), token);
                RequireSameSession(owner, grant);
                Current();
                writeAttempted = true;
                await _oauth.UpdatePersonalProfileCallSignAsync(grant, before.Revision, callSign, token);
                Current();
                // Confirm against the normal read authority, not just the mutation response.
                var confirmed = await GetPersonalProfileAsync(context, token);
                Current();
                if (confirmed.PublicId != before.PublicId ||
                    confirmed.Revision < before.Revision + 1 || confirmed.Identity.Callsign != callSign)
                    throw new AccountBridgeHostException("account.callsign_unconfirmed");
            }
            _scmDisplayCallSign = callSign;
            return new { schemaVersion = 1, callSign };
        }
        catch (AccountBridgeHostException e) when (writeAttempted && PersonalProfileReadFailures.IsReadFailure(e.Code))
        { throw new AccountBridgeHostException("account.callsign_unconfirmed"); }
        catch (ScmApiForbiddenException) { throw new AccountBridgeHostException(writeAttempted ? "account.callsign_unconfirmed" : AccountBridgeStableErrors.PersonalProfileWriteForbidden); }
        catch (ScmApiAuthenticationException) { throw new AccountBridgeHostException(writeAttempted ? "account.callsign_unconfirmed" : AccountBridgeStableErrors.ReauthorizationRequired); }
        catch (OAuthAuthorizationDeniedException) { throw new OperationCanceledException("Call sign authorization was cancelled."); }
        catch (HttpRequestException e) when (e.StatusCode == HttpStatusCode.Conflict)
        { throw new AccountBridgeHostException("account.callsign_conflict"); }
        catch (OperationCanceledException) when (writeAttempted)
        { throw new AccountBridgeHostException("account.callsign_unconfirmed"); }
        catch (Exception e) when (e is HttpRequestException or IOException or InvalidOperationException)
        { throw new AccountBridgeHostException(writeAttempted ? "account.callsign_unconfirmed" : "account.callsign_unavailable"); }
        finally { if (!_disposed) _mutationGate.Release(); }
    }
}
