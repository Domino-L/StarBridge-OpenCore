namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    internal void ClearDownloadableImageReadCaches() => _communities?.ClearDownloadableImageReadCaches();
}
