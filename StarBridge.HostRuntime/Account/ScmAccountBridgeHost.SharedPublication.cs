using StarBridge.HostRuntime.Privacy;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    private Func<BridgeAccountContext, long, bool>? _positivePublicationAllowed;
    private Func<BridgeAccountContext, long, bool>? _publicationSuspended;
    private PositivePublicationAdmission? _sharedPublicationAdmission;

    internal void ConfigureSharedPublicationAuthorization(Func<BridgeAccountContext, long, bool> allowed,
        Func<BridgeAccountContext, long, bool> suspended, PositivePublicationAdmission admission)
    {
        _positivePublicationAllowed = allowed;
        _publicationSuspended = suspended;
        _sharedPublicationAdmission = admission;
    }

    private void RequireSharedPublication(BridgeAccountContext owner, long generation)
    {
        if (_positivePublicationAllowed?.Invoke(owner, generation) == false)
            throw new OperationCanceledException("Positive publication admission has closed.");
    }

    private bool RoomPublicationSuspended(BridgeAccountContext owner, long generation) =>
        _publicationSuspended?.Invoke(owner, generation) == true;
}
