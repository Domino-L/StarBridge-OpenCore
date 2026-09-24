namespace StarBridge.HostRuntime.Account;

using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.LegacyRelay;
using System.Net.Http;

// Reuses the S2 identity-link projection and SCM-bearer Relay lease. Reading
// compatibility never provisions an account or consumes migration credentials.
internal sealed class S2CompatibilityReader(
    IAccountCompatibilityCoordinator coordinator,
    ILegacyRelayAccountPort relay,
    IDisposable? transport = null) : IDisposable
{
    internal static S2CompatibilityReader Create(
        ScmHttpClient http, OAuthPkceClient oauth, ScmRuntimeConfiguration configuration)
    {
        var legacyHttp = new HttpClient { Timeout = TimeSpan.FromSeconds(8) };
        var links = new IdentityLinkClient(http, legacyHttp, configuration.OAuthOptions,
            () => configuration.LegacyRelayBaseUri);
        var credentials = new WindowsLegacyMigrationCredentialStore(configuration.LegacyMigrationCredentialPath);
        return new(new ScmAccountCompatibilityCoordinator(
            new IdentityLinkCoordinator(oauth, links, credentials), links, credentials),
            new LegacyRelayAccountClient(legacyHttp, configuration.LegacyRelayBaseUri), legacyHttp);
    }

    internal async Task<AccountBridgeCompatibilityProjection> ReadAsync(
        ScmOAuthSession session, CancellationToken token)
    {
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
        deadline.CancelAfter(TimeSpan.FromSeconds(10));
        var projection = await coordinator.ReadAsync(session, deadline.Token).ConfigureAwait(false);
        // Only the existing-account proof flow is exposed. Provisioning stays retired.
        projection = projection with
        {
            AvailableActions = projection.IdentityState == "unlinked" ? ["linkExistingAccount"] : [],
            LegacyFeaturesAvailable = false
        };
        if (projection.IdentityState != "linked" || string.IsNullOrWhiteSpace(projection.LegacyAccountId))
        {
            relay.Reset();
            return projection;
        }
        var state = await relay.EstablishAsync(session, projection.LegacyAccountId, deadline.Token)
            .ConfigureAwait(false);
        return projection with
        {
            RelayState = state switch
            {
                LegacyRelayAccessState.Ready => "ready",
                LegacyRelayAccessState.AccountMismatch => "accountMismatch",
                LegacyRelayAccessState.AuthorizationRequired => "authorizationRequired",
                _ => "unavailable"
            },
            LegacyFeaturesAvailable = state == LegacyRelayAccessState.Ready,
            AvailableActions = state == LegacyRelayAccessState.Ready ? [] : ["retry"]
        };
    }

    internal async Task<AccountBridgeCompatibilityProjection> LinkAsync(
        ScmOAuthSession session, LegacyIdentityLinkPasswordCredential credential, CancellationToken token)
    {
        await coordinator.LinkExistingAsync(session, credential, token).ConfigureAwait(false);
        token.ThrowIfCancellationRequested();
        var confirmed = await ReadAsync(session, token).ConfigureAwait(false);
        if (confirmed.IdentityState != "linked")
            throw new AccountBridgeHostException(AccountBridgeStableErrors.CompatibilityWriteUnavailable, true);
        return confirmed;
    }

    internal void Reset() => relay.Reset();
    public void Dispose() { relay.Reset(); (relay as IDisposable)?.Dispose(); transport?.Dispose(); }
}
