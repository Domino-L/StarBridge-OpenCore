using StarBridge.HostRuntime.Overlay;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    internal string? OverlayPreferenceKey(string memberRef, string scope) =>
        _memberTargets.TryGetValue(memberRef, out var member) && member.Scope == scope && member.Expires > DateTimeOffset.UtcNow
            ? OverlayMemberIdentity.FromAccountId(member.MemberId) : null;
    // Called only after a current, authenticated joined-directory read. Resolving
    // an address is not permission to render; the workspace is read again.
    internal OverlayCommunityTarget OverlayTarget(string reference, string scope)
    {
        var target = ResolveForRead(reference, scope, allowWpfS2: true);
        return new(target.Code, target.Name, reference);
    }
}
