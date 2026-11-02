using StarBridge.Core.Profiles;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    // This only suppresses display retention after a hard read failure; it
    // never grants account authority. A confirmed fresh persistence re-enables it.
    private bool _profileReadCacheSuppressed;
    private sealed record AccountProfileReadSnapshot(BridgeAccountContext Owner, long Generation,
        ScmCachedProfileContract Profile);
    private AccountProfileReadSnapshot? _profileReadSnapshot;

    private void RequireAccountProfileReadOwner(BridgeAccountContext context, long generation)
    {
        if (_disposed || Generation != generation || _credentialTemporarilyUnavailable || _reauthorizationRequired)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        _ = RequireSession(context);
    }

    private void InvalidateAccountProfileCache(AccountRouteIdentity route)
    {
        _profileReadCacheSuppressed = true;
        _profileReadSnapshot = null;
        try { _profileCache.Clear(route); }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException)
        {
            ReportAccountProfileCacheFailure("invalidate", error);
        }
    }

    private static void ReportAccountProfileCacheFailure(string operation, Exception error) =>
        ScmAuthDiagnostics.Write("account-profile-cache", operation, "failed", $"exceptionType={error.GetType().Name}");
}
