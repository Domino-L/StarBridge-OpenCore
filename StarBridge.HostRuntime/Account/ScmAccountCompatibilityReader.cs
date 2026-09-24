namespace StarBridge.HostRuntime.Account;

using StarBridge.HostRuntime.Auth;
using System.Net;
using System.Net.Http;

internal interface IAccountCompatibilityCoordinator
{
    Task<AccountBridgeCompatibilityProjection> ReadAsync(
        ScmOAuthSession session,
        CancellationToken cancellationToken);

    Task<AccountBridgeCompatibilityProjection> LinkExistingAsync(
        ScmOAuthSession session,
        LegacyIdentityLinkPasswordCredential? credential,
        CancellationToken cancellationToken);

    Task<AccountBridgeCompatibilityProjection> CreateCompatibilityIdentityAsync(
        ScmOAuthSession session,
        CancellationToken cancellationToken);
}

/// <summary>
/// Translates SCM's legacy identity-link contract and the local one-time
/// migration credential into a small, non-secret product projection.
/// </summary>
internal sealed class ScmAccountCompatibilityCoordinator(
    IdentityLinkCoordinator linkCoordinator,
    IIdentityLinkClient identityLinks,
    ILegacyMigrationCredentialStore migrationCredentials) : IAccountCompatibilityCoordinator
{
    public async Task<AccountBridgeCompatibilityProjection> ReadAsync(
        ScmOAuthSession session,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(session);
        var link = await identityLinks.ResolveAsync(session, cancellationToken)
            .ConfigureAwait(false);
        var hasStoredCredential = migrationCredentials.Load() is not null;
        if (link is null)
        {
            return new AccountBridgeCompatibilityProjection(
                IdentityState: "unlinked",
                RelayState: "notApplicable",
                StoredLegacyCredentialAvailable: hasStoredCredential,
                LegacyFeaturesAvailable: false,
                AvailableActions: ["linkExistingAccount", "createCompatibilityIdentity"],
                LegacyAccountId: null);
        }

        if (link.Status.Equals("ACTIVE", StringComparison.OrdinalIgnoreCase) &&
            !string.IsNullOrWhiteSpace(link.LegacyAccountId))
        {
            return new AccountBridgeCompatibilityProjection(
                IdentityState: "linked",
                RelayState: "notEstablished",
                StoredLegacyCredentialAvailable: false,
                LegacyFeaturesAvailable: false,
                AvailableActions: [],
                LegacyAccountId: link.LegacyAccountId.Trim());
        }

        return new AccountBridgeCompatibilityProjection(
            IdentityState: "unknown",
            RelayState: "unknown",
            StoredLegacyCredentialAvailable: hasStoredCredential,
            LegacyFeaturesAvailable: false,
            AvailableActions: ["retry"],
            LegacyAccountId: null);
    }

    public async Task<AccountBridgeCompatibilityProjection> LinkExistingAsync(
        ScmOAuthSession session,
        LegacyIdentityLinkPasswordCredential? credential,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(session);
        try
        {
            var result = await linkCoordinator.EnsureLinkedAsync(
                    session,
                    cancellationToken,
                    requestPasswordCredential: credential is null
                        ? null
                        : _ => Task.FromResult<LegacyIdentityLinkPasswordCredential?>(credential),
                    useStoredCredential: credential is null)
                .ConfigureAwait(false);
            switch (result.Outcome)
            {
                case IdentityLinkOutcome.AlreadyLinked:
                case IdentityLinkOutcome.Linked:
                    return await ReadAsync(session, cancellationToken).ConfigureAwait(false);
                case IdentityLinkOutcome.NoLegacyCredential:
                    throw new AccountBridgeHostException(
                        AccountBridgeStableErrors.LegacyCredentialsRequired);
                case IdentityLinkOutcome.Conflict:
                    throw new AccountBridgeHostException(
                        AccountBridgeStableErrors.CompatibilityConflict);
                case IdentityLinkOutcome.ExistingLinkMismatch:
                    throw new AccountBridgeHostException(
                        AccountBridgeStableErrors.CompatibilityExistingLinkMismatch);
                default:
                    throw new AccountBridgeHostException(
                        AccountBridgeStableErrors.CompatibilityWriteUnavailable,
                        retryable: true);
            }
        }
        catch (HttpRequestException exception)
            when (exception.StatusCode == HttpStatusCode.Unauthorized)
        {
            throw new AccountBridgeHostException(
                AccountBridgeStableErrors.LegacyCredentialsRejected);
        }
    }

    public async Task<AccountBridgeCompatibilityProjection> CreateCompatibilityIdentityAsync(
        ScmOAuthSession session,
        CancellationToken cancellationToken)
    {
        ArgumentNullException.ThrowIfNull(session);
        var result = await linkCoordinator
            .ProvisionCompatibilityAccountAsync(session, cancellationToken)
            .ConfigureAwait(false);
        switch (result.Outcome)
        {
            case IdentityLinkOutcome.AlreadyLinked:
            case IdentityLinkOutcome.Linked:
                return await ReadAsync(session, cancellationToken).ConfigureAwait(false);
            case IdentityLinkOutcome.Conflict:
                throw new AccountBridgeHostException(
                    AccountBridgeStableErrors.CompatibilityConflict);
            default:
                throw new AccountBridgeHostException(
                    AccountBridgeStableErrors.CompatibilityWriteUnavailable,
                    retryable: true);
        }
    }
}
