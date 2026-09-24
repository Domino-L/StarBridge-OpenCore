namespace StarBridge.HostRuntime.Account;

using StarBridge.Core.Profiles;
using StarBridge.NativeBridge;

/// <summary>
/// Fail-closed account adapter used before an external SCM environment is
/// approved for the unfinished Flutter client. It never opens a browser,
/// restores credentials, or performs network I/O.
/// </summary>
internal sealed class EnvironmentLockedAccountBridgeHost : IAccountBridgeHost
{
    internal EnvironmentLockedAccountBridgeHost(string environment)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(environment);
    }

    public long Generation => 0;

    public BridgeAccountContext? CurrentContext => null;

    public event Action<long>? AccountChanged
    {
        add { }
        remove { }
    }

    public Task<AccountBridgeSessionProjection> GetCurrentAsync(
        CancellationToken cancellationToken) => Task.FromResult(
            new AccountBridgeSessionProjection(
                "signedOut",
                Generation,
                null,
                null,
                null));

    public Task<AccountBridgeSessionProjection> LoginAsync(
        CancellationToken cancellationToken) => Blocked<AccountBridgeSessionProjection>();

    public Task CancelLoginAsync() => Task.CompletedTask;

    public Task LogoutAsync(
        BridgeAccountContext context,
        CancellationToken cancellationToken) => Blocked();

    public Task<AccountBridgeProfileProjection> GetProfileAsync(
        BridgeAccountContext context,
        CancellationToken cancellationToken) => Blocked<AccountBridgeProfileProjection>();

    public Task<PersonalProfileDocumentContract> GetPersonalProfileAsync(
        BridgeAccountContext context,
        CancellationToken cancellationToken) => Blocked<PersonalProfileDocumentContract>();

    public Task<PersonalProfileDocumentContract> UpdatePersonalProfileAsync(
        BridgeAccountContext context,
        PersonalProfilePresentationUpdateContract update,
        CancellationToken cancellationToken) => Blocked<PersonalProfileDocumentContract>();

    public Task<AccountBridgeOfficialFleetProjection> GetOfficialFleetAsync(
        BridgeAccountContext context,
        CancellationToken cancellationToken) => Blocked<AccountBridgeOfficialFleetProjection>();

    public Task<AccountBridgeCompatibilityProjection> GetCompatibilityStateAsync(
        BridgeAccountContext context,
        CancellationToken cancellationToken) => Blocked<AccountBridgeCompatibilityProjection>();

    public Task<AccountBridgeCompatibilityProjection> LinkLegacyAccountAsync(
        BridgeAccountContext context,
        AccountBridgeLegacyCredential? credential,
        CancellationToken cancellationToken) => Blocked<AccountBridgeCompatibilityProjection>();

    public Task<AccountBridgeCompatibilityProjection> CreateCompatibilityIdentityAsync(
        BridgeAccountContext context,
        CancellationToken cancellationToken) => Blocked<AccountBridgeCompatibilityProjection>();

    public Task<AccountBridgeProfileProjection> PatchPreferencesAsync(
        BridgeAccountContext context,
        AccountBridgePreferencePatch patch,
        CancellationToken cancellationToken) => Blocked<AccountBridgeProfileProjection>();

    public Task<bool> ClearProfileCacheAsync(
        BridgeAccountContext context,
        CancellationToken cancellationToken) => Blocked<bool>();

    public Task<AccountBridgeIdentityProjection> GetGameIdentityPolicyAsync(
        BridgeAccountContext context,
        CancellationToken cancellationToken) => Blocked<AccountBridgeIdentityProjection>();

    private Task Blocked() => Task.FromException(CreateException());

    private Task<T> Blocked<T>() => Task.FromException<T>(CreateException());

    private AccountBridgeHostException CreateException() => new(
        AccountBridgeStableErrors.EnvironmentNotEnabled,
        retryable: false);
}
