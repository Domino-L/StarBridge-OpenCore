using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime;

public sealed partial class AccountBridgeRuntime
{
    /// <summary>Retire only Native read-side organization image copies. The
    /// diagnostics owner clears protected files separately through its root.</summary>
    public void ClearDownloadableImageReadCaches()
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        if (_host is ScmAccountBridgeHost scm) scm.ClearDownloadableImageReadCaches();
    }
}
