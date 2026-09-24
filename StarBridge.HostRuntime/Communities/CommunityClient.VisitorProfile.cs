using System.Text.Json;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    // Opaque roster references are account/organization scoped. Never use a name
    // or handle to discover a private account or accept a raw client account ID.
    internal string ResolveVisitorProfileTarget(JsonElement body, string scope, string viewerId)
    {
        Validate(body, "targetRef", "memberRef");
        var target = Resolve(Text(body, "targetRef", 32), scope, allowWpfS2: true);
        if (target.WpfS2ViewerId != viewerId)
            throw new AccountBridgeHostException("profile.visitor_unavailable");
        var reference = Text(body, "memberRef", 32);
        if (!_memberTargets.TryGetValue(reference, out var member) || member.Code != target.Code ||
            member.Scope != scope || member.Expires <= DateTimeOffset.UtcNow ||
            !member.MemberId.StartsWith("account:", StringComparison.Ordinal) || member.MemberId.Length is < 16 or > 136)
            throw new AccountBridgeHostException("communities.refreshRequired");
        return member.MemberId["account:".Length..];
    }
}
