using StarBridge.HostRuntime.Friends;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    internal void RequireFriendsPageContext(BridgeAccountContext context)
    {
        if (_disposed || _reauthorizationRequired || _credentialTemporarilyUnavailable)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        _ = RequireRelaySession(context);
    }
    internal event Func<BridgeAccountContext, long, bool, CancellationToken, Task<OfflineFriendsReadLease?>>? FriendsReadStarting;
    internal event Action<OfflineFriendsReadLease, long, OfflineFriendsReadOutcome, FriendsView?>? FriendsReadFinished;

    private void FinishFriendsDisplay(OfflineFriendsReadLease? lease, long generation,
        OfflineFriendsReadOutcome outcome, FriendsView? result)
    {
        if (lease is null) return;
        try { FriendsReadFinished?.Invoke(lease, generation, outcome, result); }
        finally { lease.Dispose(); }
    }
}
