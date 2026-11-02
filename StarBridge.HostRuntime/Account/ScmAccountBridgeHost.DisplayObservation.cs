namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    // Native-only cache observation after real restore and local-owner checking.
    // No authority, progress event or extra Bridge response is published here.
    internal event Action<AccountBridgeSessionProjection, CancellationToken>? AccountDisplayObserved;
}
