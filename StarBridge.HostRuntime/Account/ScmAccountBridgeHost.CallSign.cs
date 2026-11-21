using System.Net;
using System.Text.Json;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Privacy;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    private string? _scmDisplayCallSign;

    // Reading: any name the SCM profile already holds (up to 32 characters).
    private static string? ValidDisplayCallSign(string? value) => value is { Length: > 0 and <= 32 } &&
        value == value.Trim() && !value.Any(char.IsControl) ? value : null;

    // Writing (11-15 decision 甲): one callsign for SCM accounts, legacy rules (trim,
    // CJK counts 2, at most 10). The profile editor never clears it; the settings card can.
    private static string? ValidEditCallSign(string? value)
    {
        if (value is null || value != value.Trim() || value.Length == 0) return null;
        try { return PrivacyRelayWriter.NormalizeDisplayCallsign(value); }
        catch (AccountBridgeHostException) { return null; }
    }

    public async Task<object> UpdateCallSignAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token)
    {
        if (payload.ValueKind != JsonValueKind.Object || payload.EnumerateObject().Count() != 3 ||
            !payload.TryGetProperty("schemaVersion", out var schema) || !schema.TryGetInt32(out var version) || version != 1 ||
            !payload.TryGetProperty("callSign", out var name) || name.ValueKind != JsonValueKind.String ||
            !payload.TryGetProperty("expectedCallSign", out var expected) || expected.ValueKind != JsonValueKind.String ||
            ValidEditCallSign(name.GetString()) is not { } callSign || expected.GetString() is not { Length: > 0 and <= 32 } expectedCallSign ||
            expectedCallSign != expectedCallSign.Trim() || expectedCallSign.Any(char.IsControl))
            throw new AccountBridgeHostException("account.callsign_invalid");
        var generation = Generation;
        // Stale-draft check before anything is written: another device's rename since
        // the editor read must not reach the Relay and then fail on Hong Kong.
        var current = (await GetPersonalProfileAsync(context, token)).Identity.Callsign;
        if (_disposed || Generation != generation) throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        if (current != expectedCallSign && current != callSign) throw new AccountBridgeHostException("account.callsign_conflict");
        // The Relay keeps the same single callsign: write it first, so the
        // StarBridge pages never lag behind the SCM profile name.
        await SaveRelayCallSignIfChangedAsync(context, generation, callSign, token);
        var confirmed = await SyncHkCallSignAsync(context, generation, callSign, expectedCallSign, token);
        // A confirmed non-empty name ends any pending "restore default" for this account.
        if (_restorePending is { } pending && pending.Owner == context) _restorePending = null;
        return new { schemaVersion = 1, callSign = confirmed };
    }

    private async Task SaveRelayCallSignIfChangedAsync(BridgeAccountContext context, long generation, string? callSign, CancellationToken token)
    {
        // Legacy accounts keep their own profile route; without a Relay writer there is nothing to sync.
        if (_session is null || _privacyWriter is null) return;
        try
        {
            var current = await WithEventSessionAsync(context, generation, false,
                (writer, bearer, _, ct) => writer.ReadDisplayAsync(bearer, ct), token);
            // A first rename must not skip the one-time import of an explicit Hong Kong hide
            // (review P1): every first Relay write goes through the same check.
            current = await ImportExplicitHkHideAsync(context, generation, current, token);
            if (current.Callsign == callSign) return;
            var saved = await WithEventSessionAsync(context, generation, false,
                (writer, bearer, ensure, ct) => writer.SaveDisplayCallsignAsync(bearer, current.Revision, current.IdentityStamp,
                    callSign, ensure, ct), token);
            ForgetDisplayMirror(context);
            _ = saved;
        }
        catch (AccountBridgeHostException e) when (e.Code is "gameId.relay_outdated")
        {
            // Before r49 the Relay has no SCM callsign; the SCM profile name still saves.
        }
        catch (AccountBridgeHostException e) when (e.Code is "gameId.conflict")
        { throw new AccountBridgeHostException("account.callsign_conflict"); }
        catch (AccountBridgeHostException e) when (e.Code is "callsign.invalid")
        { throw new AccountBridgeHostException("account.callsign_invalid"); }
        catch (AccountBridgeHostException e) when (e.Code.StartsWith("gameId.", StringComparison.Ordinal) ||
            e.Code.StartsWith("events.", StringComparison.Ordinal))
        { throw new AccountBridgeHostException("account.callsign_unavailable", retryable: e.Retryable); }
    }

    /// <summary>Writes the SCM profile callsign (Hong Kong). <paramref name="callSign"/>
    /// null restores the SCM default name; <paramref name="expectedCallSign"/> null skips
    /// the stale-draft check (Relay-led sync). Returns the confirmed profile name.</summary>
    private async Task<string> SyncHkCallSignAsync(BridgeAccountContext context, long generation, string? callSign,
        string? expectedCallSign, CancellationToken token)
    {
        await _mutationGate.WaitAsync(token);
        var writeAttempted = false;
        try
        {
            // The generation is the one the whole operation started with, checked again
            // after the lock and before every write.
            if (_disposed || Generation != generation) throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
            var owner = RequireSession(context);
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
            if (callSign is null || before.Identity.Callsign != callSign)
            {
                // A draft may not overwrite a name changed by another device since the editor read it.
                if (expectedCallSign is not null && before.Identity.Callsign != expectedCallSign)
                    throw new AccountBridgeHostException("account.callsign_conflict");
                var grant = await _profileAuthorization.AuthorizeProfileWriteAsync(RequireSession(context), token);
                RequireSameSession(owner, grant);
                Current();
                writeAttempted = true;
                OAuthPkceClient.PersonalProfileCallSignResult written;
                try { written = await _oauth.UpdatePersonalProfileCallSignAsync(grant, before.Revision, callSign ?? "", token); }
                catch (HttpRequestException e) when (callSign is null && e.StatusCode == HttpStatusCode.BadRequest)
                {
                    // Hong Kong before swap 7 does not accept "restore default" yet.
                    throw new AccountBridgeHostException("account.callsign_restore_pending");
                }
                Current();
                // Confirm against the normal read authority, not just the mutation response.
                var confirmed = await GetPersonalProfileAsync(context, token);
                Current();
                if (confirmed.PublicId != before.PublicId || confirmed.Revision < before.Revision + 1 ||
                    callSign is not null && confirmed.Identity.Callsign != callSign ||
                    callSign is null && confirmed.Identity.Callsign != written.CallSign)
                    throw new AccountBridgeHostException("account.callsign_unconfirmed");
                _scmDisplayCallSign = confirmed.Identity.Callsign;
                return confirmed.Identity.Callsign;
            }
            _scmDisplayCallSign = callSign;
            return callSign;
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
