using StarBridge.HostRuntime.Privacy;
using StarBridge.HostRuntime.Auth;
using System.Net;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal interface IGameIdSettingsRemote
{
    Task<GameIdSettingsSnapshot> ReadGameIdAsync(BridgeAccountContext owner, long generation, CancellationToken token);
    Task<GameIdSettingsSnapshot> SaveGameIdAsync(BridgeAccountContext owner, long generation, long revision, string stamp, int locations, CancellationToken token);
}
internal sealed partial class ScmAccountBridgeHost : IGameIdSettingsRemote
{
    private CancellationTokenSource? _handlePrivacyRead;
    public Task<GameIdSettingsSnapshot> ReadGameIdAsync(BridgeAccountContext owner, long generation, CancellationToken token) =>
        _session is not null ? ScmHandlePrivacyAsync(owner, generation, null, token) :
        WithEventSessionAsync(owner, generation, false, (writer, bearer, _, ct) => writer.ReadGameIdAsync(bearer, ct), token);
    public Task<GameIdSettingsSnapshot> SaveGameIdAsync(BridgeAccountContext owner, long generation, long revision, string stamp, int locations, CancellationToken token) =>
        _session is not null ? ScmHandlePrivacyAsync(owner, generation, new(revision, stamp, locations), token) :
        WithEventSessionAsync(owner, generation, false, (writer, bearer, current, ct) => writer.SaveGameIdAsync(bearer, revision, stamp, locations, current, ct), token);

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
