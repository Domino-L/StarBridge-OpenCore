using StarBridge.HostRuntime.Privacy;
using StarBridge.HostRuntime.Auth;
using System.Net;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal interface IGameIdSettingsRemote
{
    Task<object> ReadGameIdAsync(BridgeAccountContext owner, long generation, CancellationToken token);
    Task<object> SaveGameIdAsync(BridgeAccountContext owner, long generation, long revision, string stamp, int locations, CancellationToken token);
    Task<object> SaveDisplayCallsignAsync(BridgeAccountContext owner, long generation, long revision, string stamp, string? callsign, CancellationToken token);
    Task<object> RetryDisplaySyncAsync(BridgeAccountContext owner, long generation, bool automatic, CancellationToken token);
    /// <summary>Counts Hong Kong confirming a callsign write from these settings (save or retry). The account
    /// name shown in the top bar is read from Hong Kong, so a change here means it must be read again.</summary>
    long HkCallsignConfirmations => 0;
}

/// <summary>SCM settings view (11-15 decision 甲): the Relay is the authority for the one
/// callsign and the game ID locations; Hong Kong is kept in step. Mirror is "synced",
/// "pending" (retry available), "restorePending" (Hong Kong cannot restore the default
/// name yet) or "unknown" (could not check this time).</summary>
internal sealed record ScmGameIdSettingsView(int SchemaVersion, long Revision, int Locations, bool CanConfigure,
    string IdentityStamp,
    // The bridge drops nulls by default; the Flutter card tells SCM from legacy accounts by the
    // presence of this key, so "no callsign yet" must still be written as null.
    [property: System.Text.Json.Serialization.JsonIgnore(Condition = System.Text.Json.Serialization.JsonIgnoreCondition.Never)] string? Callsign,
    string Mirror);

internal sealed partial class ScmAccountBridgeHost : IGameIdSettingsRemote
{
    private CancellationTokenSource? _handlePrivacyRead;
    // Hong Kong check per owner/generation/Relay revision/stamp: which half is out of step.
    private (BridgeAccountContext Owner, long Generation, long Revision, string Stamp, bool LocationsOk, bool CallsignOk)? _displayMirror;
    // A cleared callsign whose Hong Kong restore has not been confirmed yet. Kept apart
    // from the revision so a later locations-only save cannot clear it.
    private (BridgeAccountContext Owner, long Generation)? _restorePending;
    // Hong Kong before swap 7 answers 400 to "restore default": automatic retries wait.
    private (BridgeAccountContext Owner, long Generation, DateTimeOffset Until)? _restoreUnsupported;
    private long _hkCallsignConfirmations;
    public long HkCallsignConfirmations => Interlocked.Read(ref _hkCallsignConfirmations);

    public async Task<object> ReadGameIdAsync(BridgeAccountContext owner, long generation, CancellationToken token)
    {
        if (_session is null)
            return await WithEventSessionAsync(owner, generation, false, (writer, bearer, _, ct) => writer.ReadGameIdAsync(bearer, ct), token);
        var relay = await ReadRelayDisplayAsync(owner, generation, token);
        return View(relay, await DisplayMirrorAsync(owner, generation, relay, token));
    }

    public async Task<object> SaveGameIdAsync(BridgeAccountContext owner, long generation, long revision, string stamp, int locations, CancellationToken token)
    {
        if (_session is null)
            return await WithEventSessionAsync(owner, generation, false, (writer, bearer, current, ct) => writer.SaveGameIdAsync(bearer, revision, stamp, locations, current, ct), token);
        await EnsureImportedBeforeFirstWriteAsync(owner, generation, revision, token);
        // Review R9 P1: the Hong Kong state when this save starts is the only baseline a reveal may
        // overwrite. If another device writes Hong Kong meanwhile (e.g. a later hide), the reveal is
        // skipped and the card shows pending. Unreadable now means no reveal in this request.
        GameIdSettingsSnapshot? hkAtStart = null;
        try { hkAtStart = await ScmHandlePrivacyAsync(owner, generation, null, token); }
        catch (Exception error) when (!EndsDisplayOperation(error, generation, token)) { }
        var saved = await WithEventSessionAsync(owner, generation, false,
            (writer, bearer, current, ct) => writer.SaveDisplayLocationsAsync(bearer, revision, stamp, locations, current, ct), token);
        return View(saved, await PushDisplayToHkAsync(owner, generation, saved, locations: true, callsign: false, token,
            userSave: true, hkAtStart: hkAtStart));
    }

    public async Task<object> SaveDisplayCallsignAsync(BridgeAccountContext owner, long generation, long revision, string stamp,
        string? callsign, CancellationToken token)
    {
        if (_session is null) throw new AccountBridgeHostException("gameId.unsupported");
        var normalized = PrivacyRelayWriter.NormalizeDisplayCallsign(callsign);
        await EnsureImportedBeforeFirstWriteAsync(owner, generation, revision, token);
        var saved = await WithEventSessionAsync(owner, generation, false,
            (writer, bearer, current, ct) => writer.SaveDisplayCallsignAsync(bearer, revision, stamp, normalized, current, ct), token);
        // An explicit clear always asks Hong Kong to restore the default name.
        if (saved.Callsign is null) _restorePending = (owner, generation);
        return View(saved, await PushDisplayToHkAsync(owner, generation, saved, locations: false, callsign: true, token, userAction: true));
    }

    // Retries only the halves that are actually out of step.
    public async Task<object> RetryDisplaySyncAsync(BridgeAccountContext owner, long generation, bool automatic, CancellationToken token)
    {
        if (_session is null) throw new AccountBridgeHostException("gameId.unsupported");
        var relay = await ReadRelayDisplayAsync(owner, generation, token);
        var check = await CheckHkMirrorAsync(owner, generation, relay, token);
        return View(relay, await PushDisplayToHkAsync(owner, generation, relay,
            locations: check is not { LocationsOk: true }, callsign: check is not { CallsignOk: true }, token, userAction: !automatic));
    }

    // Settings reads yield to privacy publication, like the event-sharing reads.
    private async Task<ScmDisplaySettings> ReadRelayDisplayAsync(BridgeAccountContext owner, long generation, CancellationToken token)
    {
        ScmDisplaySettings relay;
        try
        {
            relay = await WithEventSessionAsync(owner, generation, false, (writer, bearer, _, ct) => writer.ReadDisplayAsync(bearer, ct),
                token, yieldableRead: true);
        }
        catch (AccountBridgeHostException error) when (error.Code == "events.temporarily_unavailable")
        { throw new AccountBridgeHostException("gameId.unavailable", retryable: true); }
        return await ImportExplicitHkHideAsync(owner, generation, relay, token);
    }

    // Decision 乙: an account that never set anything on the Relay now defaults to
    // "show". A hide the user explicitly saved on Hong Kong (the earlier settings page
    // wrote there) is imported once, before any mirror push could overwrite it.
    private async Task<ScmDisplaySettings> ImportExplicitHkHideAsync(BridgeAccountContext owner, long generation,
        ScmDisplaySettings relay, CancellationToken token)
    {
        if (relay.Revision != 0) return relay;
        GameIdSettingsSnapshot hk;
        try { hk = await ScmHandlePrivacyAsync(owner, generation, null, token); }
        catch (Exception error) when (!EndsDisplayOperation(error, generation, token))
        {
            // Unknown import state (review P1): never let the Relay's "show" default become the
            // basis of a first write or a mirror push; the card shows "unavailable" and retries.
            throw new AccountBridgeHostException("gameId.unavailable", retryable: true);
        }
        if (hk.Revision == 0 || !hk.CanConfigure || hk.Locations == 15 || hk.Locations == relay.Locations) return relay;
        try
        {
            var imported = await WithEventSessionAsync(owner, generation, false,
                (writer, bearer, current, ct) => writer.SaveDisplayLocationsAsync(bearer, relay.Revision, relay.IdentityStamp,
                    hk.Locations, current, ct, importExplicit: true), token);
            ForgetDisplayMirror(owner);
            return imported;
        }
        catch (AccountBridgeHostException error) when (error.Code is "gameId.conflict")
        {
            // Another device imported (or wrote) first: read again. A Relay still without a row
            // cannot be trusted to carry the hide (review R2 P1): stop rather than offer "show".
            var reread = await WithEventSessionAsync(owner, generation, false, (writer, bearer, _, ct) => writer.ReadDisplayAsync(bearer, ct), token);
            if (reread.Revision == 0) throw new AccountBridgeHostException("gameId.unavailable", retryable: true);
            return reread;
        }
    }

    // Review R2 P1: a settings save based on a revision-0 snapshot runs the same one-time
    // import first. If the import moved the Relay, the card's draft is stale: refresh it.
    private async Task EnsureImportedBeforeFirstWriteAsync(BridgeAccountContext owner, long generation, long revision, CancellationToken token)
    {
        if (revision != 0) return;
        var relay = await WithEventSessionAsync(owner, generation, false, (writer, bearer, _, ct) => writer.ReadDisplayAsync(bearer, ct), token);
        var checkedRelay = await ImportExplicitHkHideAsync(owner, generation, relay, token);
        if (checkedRelay.Revision != revision) throw new AccountBridgeHostException("gameId.conflict");
    }

    private static ScmGameIdSettingsView View(ScmDisplaySettings relay, string mirror) =>
        new(1, relay.Revision, relay.Locations, relay.CanConfigure, relay.IdentityStamp, relay.Callsign, mirror);

    private void ForgetDisplayMirror(BridgeAccountContext owner)
    {
        if (_displayMirror is { } cached && cached.Owner == owner) _displayMirror = null;
    }

    private bool RestorePending(BridgeAccountContext owner, long generation) =>
        _restorePending is { } pending && pending.Owner == owner && pending.Generation == generation;

    // Account changes, stale generations and caller cancellation end the whole
    // operation; they are never recorded as an ordinary "not in sync yet". The caller
    // token is checked unconditionally because lower layers may wrap the cancellation.
    private bool EndsDisplayOperation(Exception error, long generation, CancellationToken token) =>
        token.IsCancellationRequested ||
        error is BridgeStaleGenerationException ||
        error is AccountBridgeHostException { Code: "gameId.account_changed" or AccountBridgeStableErrors.ReauthorizationRequired } ||
        _disposed || Generation != generation;

    private string State(BridgeAccountContext owner, long generation, (bool LocationsOk, bool CallsignOk)? check)
    {
        if (RestorePending(owner, generation)) return "restorePending";
        if (check is not { } value) return "unknown";
        return value.LocationsOk && value.CallsignOk ? "synced" : "pending";
    }

    // Hong Kong is checked once per Relay revision and identity stamp (not on every 15-second poll).
    private async Task<string> DisplayMirrorAsync(BridgeAccountContext owner, long generation, ScmDisplaySettings relay, CancellationToken token)
    {
        if (_displayMirror is { } cached && cached.Owner == owner && cached.Generation == generation &&
            cached.Revision == relay.Revision && cached.Stamp == relay.IdentityStamp)
            return State(owner, generation, (cached.LocationsOk, cached.CallsignOk));
        return State(owner, generation, await CheckHkMirrorAsync(owner, generation, relay, token));
    }

    // A Relay callsign of null cannot be compared with the SCM default name: it is in
    // step unless a restore is pending in this session (known limitation after restart).
    private async Task<(bool LocationsOk, bool CallsignOk)?> CheckHkMirrorAsync(BridgeAccountContext owner, long generation,
        ScmDisplaySettings relay, CancellationToken token)
    {
        try
        {
            var hk = await ScmHandlePrivacyAsync(owner, generation, null, token);
            var locationsOk = HkLocationsMatch(hk, relay.Locations);
            var callsignOk = relay.Callsign is null
                ? !RestorePending(owner, generation)
                : (await GetPersonalProfileAsync(owner, token)).Identity.Callsign == relay.Callsign;
            if (_disposed || Generation != generation) throw new AccountBridgeHostException("gameId.account_changed");
            // Both sides read back the same non-empty name (another device may have
            // finished it): any pending restore for this account is over.
            if (relay.Callsign is not null && callsignOk && RestorePending(owner, generation))
            {
                _restorePending = null;
                _restoreUnsupported = null;
            }
            _displayMirror = (owner, generation, relay.Revision, relay.IdentityStamp, locationsOk, callsignOk);
            return (locationsOk, callsignOk);
        }
        catch (Exception error) when (!EndsDisplayOperation(error, generation, token))
        {
            return null; // "unknown", not cached: the next poll checks again.
        }
    }

    // An unverified Hong Kong identity cannot disclose anything; hidden there is the safe state.
    private static bool HkLocationsMatch(GameIdSettingsSnapshot hk, int desired) =>
        hk.Locations == desired || !hk.CanConfigure && hk.Locations == 0;

    private async Task<string> PushDisplayToHkAsync(BridgeAccountContext owner, long generation, ScmDisplaySettings relay,
        bool locations, bool callsign, CancellationToken token, bool userAction = false, bool userSave = false,
        GameIdSettingsSnapshot? hkAtStart = null)
    {
        var failed = false;
        // A Relay without a row (revision 0) has nothing authoritative to push: any explicit
        // Hong Kong hide must come in through the import, never be overwritten (review R3 P1).
        if (locations && relay.Revision != 0)
        {
            try
            {
                var hk = await ScmHandlePrivacyAsync(owner, generation, null, token);
                // Simplified rule (user 11-16): Hong Kong may become more public only inside the
                // request where the user saved these locations on this device. Reads, retries,
                // automatic retries and callsign saves only ever hide more; nothing is kept for later.
                var reveals = (relay.Locations & ~hk.Locations) != 0;
                if (userSave)
                {
                    // Review R13 P1: a refused write leaves Hong Kong's revision where it was (its identity can
                    // change and come back between our read and write). Read once more and write again, never
                    // more public than Hong Kong shows then; a refused reveal still ends as pending.
                    async Task WriteOwnAsync(HandlePrivacyWrite write)
                    {
                        try { await ScmHandlePrivacyAsync(owner, generation, write, token); }
                        catch (AccountBridgeHostException conflict) when (conflict.Code == "gameId.conflict")
                        {
                            var again = await ScmHandlePrivacyAsync(owner, generation, null, token);
                            var barrier = (relay.Locations & ~again.Locations) == 0 ? relay.Locations : again.Locations;
                            await ScmHandlePrivacyAsync(owner, generation, new(again.Revision, again.IdentityStamp, barrier), token);
                            if (barrier != relay.Locations) throw;
                        }
                    }

                    // Reviews R10-R12 P1s: the user's own save always writes Hong Kong (once more after a refusal), so
                    // Hong Kong's revision moves and any older in-flight reveal (from another device)
                    // fails Hong Kong's revision check: the latest choice always wins. This holds while
                    // Hong Kong briefly cannot be configured too.
                    if (!reveals)
                        await WriteOwnAsync(new(hk.Revision, hk.IdentityStamp, relay.Locations));
                    // A reveal: only while Hong Kong is still exactly as it was when this save started, and
                    // written against that baseline so Hong Kong refuses it if anything wrote in between (R9 P1).
                    else if (hkAtStart is { } start && start.Revision == hk.Revision &&
                        start.IdentityStamp == hk.IdentityStamp && start.Locations == hk.Locations)
                        await WriteOwnAsync(new(start.Revision, start.IdentityStamp, relay.Locations));
                    // Not allowed to reveal: write what Hong Kong already shows, only to move its revision.
                    else
                        await WriteOwnAsync(new(hk.Revision, hk.IdentityStamp, hk.Locations));
                }
                // Reads, retries, automatic retries and callsign saves only ever hide more (simplified rule, user 11-16).
                else if (!reveals && !HkLocationsMatch(hk, relay.Locations))
                    await ScmHandlePrivacyAsync(owner, generation, new(hk.Revision, hk.IdentityStamp, relay.Locations), token);
            }
            catch (Exception error) when (!EndsDisplayOperation(error, generation, token)) { failed = true; }
        }
        // A null Relay callsign is only pushed (as "restore default") when a restore is
        // actually pending; a locations mismatch alone never rewrites the profile name.
        var cooling = _restoreUnsupported is { } wait && wait.Owner == owner && wait.Generation == generation &&
            DateTimeOffset.UtcNow < wait.Until;
        var restore = relay.Callsign is null && RestorePending(owner, generation) && (userAction || !cooling);
        if (callsign && (relay.Callsign is not null || restore))
        {
            try
            {
                await SyncHkCallSignAsync(owner, generation, relay.Callsign, expectedCallSign: null, token);
                Interlocked.Increment(ref _hkCallsignConfirmations);
                if (_restorePending is { } pending && pending.Owner == owner) _restorePending = null;
                _restoreUnsupported = null;
            }
            catch (AccountBridgeHostException error) when (error.Code == "account.callsign_restore_pending")
            { _restoreUnsupported = (owner, generation, DateTimeOffset.UtcNow.AddMinutes(30)); }
            catch (Exception error) when (!EndsDisplayOperation(error, generation, token)) { failed = true; }
        }
        // Report the state of both halves (read back from Hong Kong), not just the one written now.
        var state = State(owner, generation, await CheckHkMirrorAsync(owner, generation, relay, token));
        return failed && state is "synced" or "unknown" ? "pending" : state;
    }

    private sealed record HandlePrivacyWrite(long Revision, string Stamp, int Locations);

    private async Task<GameIdSettingsSnapshot> ScmHandlePrivacyAsync(BridgeAccountContext owner, long generation,
        HandlePrivacyWrite? write, CancellationToken token)
    {
        IAsyncDisposable? readAdmission = null;
        if (write is null) readAdmission = await _mutationGate.EnterSharedAsync(token).ConfigureAwait(false);
        else await _mutationGate.WaitAsync(token);
        var callerToken = token;
        using var readCancellation = write is null ? CancellationTokenSource.CreateLinkedTokenSource(token) : null;
        if (readCancellation is not null)
        {
            token = readCancellation.Token;
            Interlocked.Exchange(ref _handlePrivacyRead, readCancellation);
        }
        try
        {
            void Current()
            {
                token.ThrowIfCancellationRequested();
                if (_disposed || generation != Generation || GameplayTimeContext != owner)
                    throw new AccountBridgeHostException("gameId.account_changed");
            }
            Current();
            var session = RequireSession(owner);
            async Task<GameIdSettingsSnapshot> Read()
            {
                Current();
                var result = await _oauth.ReadHandlePrivacyAsync(RequireSession(owner), token);
                Current();
                RequireSameSession(session, result.ActiveSession);
                RequireSameSession(session, RequireSession(owner));
                CommitSharingSession(new RelayRequestSession(session), new RelayRequestSession(result.ActiveSession));
                ScmSessionProbeDiagnostics.Snapshot(SessionProbeSnapshot.AcceptedByHost, result.Result);
                return result.Result;
            }
            if (write is null) return await Read();
            if (write.Revision < 0 || write.Revision == long.MaxValue || write.Locations is < 0 or > 15 ||
                write.Stamp is not { Length: 64 } || write.Stamp.Any(c => !char.IsAsciiHexDigit(c)))
                throw new AccountBridgeHostException("gameId.invalid_request");
            var grant = await _profileAuthorization.AuthorizeProfileWriteAsync(session, token);
            Current();
            RequireSameSession(session, grant);
            RequireSameSession(session, RequireSession(owner));
            try
            {
                var saved = await _oauth.SaveHandlePrivacyAsync(grant, write.Revision, write.Stamp, write.Locations, token);
                Current();
                return saved;
            }
            catch (HttpRequestException error) when (error.StatusCode is null or HttpStatusCode.ServiceUnavailable or HttpStatusCode.GatewayTimeout)
            {
                // An ambiguous transport failure gets one readback, never another PATCH.
                var confirmed = await Read();
                if (confirmed.Revision == write.Revision + 1 && confirmed.IdentityStamp == write.Stamp &&
                    confirmed.Locations == write.Locations) return confirmed;
                throw new AccountBridgeHostException("gameId.write_unconfirmed");
            }
        }
        catch (OperationCanceledException) when (readCancellation?.IsCancellationRequested == true && !callerToken.IsCancellationRequested)
        { throw new AccountBridgeHostException("gameId.unavailable", retryable: true); }
        catch (ScmApiForbiddenException) { throw new AccountBridgeHostException(AccountBridgeStableErrors.PersonalProfileWriteForbidden); }
        catch (ScmApiAuthenticationException) { throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired); }
        catch (OAuthAuthorizationDeniedException) { throw new OperationCanceledException("Handle privacy authorization was cancelled."); }
        catch (HttpRequestException error) when (error.StatusCode == HttpStatusCode.Conflict)
        { throw new AccountBridgeHostException("gameId.conflict"); }
        catch (ScmApiProtocolException) { throw new AccountBridgeHostException("gameId.invalid_response"); }
        catch (Exception error) when (error is TimeoutException or IOException)
        { throw new AccountBridgeHostException("gameId.unavailable", retryable: true); }
        finally
        {
            if (readCancellation is not null) Interlocked.CompareExchange(ref _handlePrivacyRead, null, readCancellation);
            if (readAdmission is not null) await readAdmission.DisposeAsync().ConfigureAwait(false);
            else if (!_disposed) _mutationGate.Release();
        }
    }
}
