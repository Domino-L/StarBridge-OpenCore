using StarBridge.HostRuntime.Overlay;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    // Called only after a current, authenticated joined-directory read. Resolving
    // an address is not permission to render; the workspace is read again.
    internal OverlayCommunityTarget OverlayTarget(string reference, string scope)
    {
        var target = ResolveForRead(reference, scope, allowWpfS2: true);
        return new(target.Code, target.Name, reference);
    }
}
