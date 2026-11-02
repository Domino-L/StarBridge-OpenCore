using StarBridge.HostRuntime.Communities;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    internal event Func<BridgeAccountContext, long, CancellationToken, Task<OfflineOrganizationReadLease?>>? OrganizationReadStarting;
    internal event Action<OfflineOrganizationReadLease, long, bool>? OrganizationReadFinished;
    internal event Action<OfflineOrganizationReadLease, BridgeAccountContext, long, string?, string?, IReadOnlyList<OfflineOrganizationObservation>, CancellationToken>? OrganizationDisplayObserved;
    internal event Func<BridgeAccountContext, long, CancellationToken, OfflineOrganizationImageRead?>? OrganizationImageReadStarting;
    internal event Action<OfflineOrganizationImageRead, BridgeAccountContext, long, string, string, CancellationToken>? OrganizationLogoObserved;

    private Task<OfflineOrganizationReadLease?> BeginOrganizationDisplayRead(BridgeAccountContext owner, long generation,
        CommunityQuery query, CancellationToken token) =>
        query.View == "mine" && query.Query.Trim().Length == 0 && query.TargetRef is null && query.Filters is null
            ? OrganizationReadStarting?.Invoke(owner, generation, token) ?? Task.FromResult<OfflineOrganizationReadLease?>(null)
            : Task.FromResult<OfflineOrganizationReadLease?>(null);

    private void ObserveOrganizationDisplay(OfflineOrganizationReadLease? lease, BridgeAccountContext owner, long generation, CommunityQuery query,
        object result, CancellationToken token)
    {
        if (lease is null || OrganizationDisplayObserved is null || query.View != "mine" || query.Query.Trim().Length != 0 ||
            query.TargetRef is not null || query.Filters is not null || result is not CommunityPage page ||
            _communities is null || token.IsCancellationRequested || _disposed || owner != CurrentContext || generation != Generation) return;
        try {
            OrganizationDisplayObserved.Invoke(lease, owner, generation, query.After, page.Next,
                _communities.ObserveDirectoryDisplay(page, FriendScope(owner, generation)), token);
        }
        catch (AccountBridgeHostException) { } // A retired presentation reference cannot change the confirmed business result.
    }

    private void ObserveOrganizationLogo(OfflineOrganizationImageRead? imageRead, BridgeAccountContext owner, long generation, System.Text.Json.JsonElement payload,
        object result, CancellationToken token)
    {
        if (imageRead is null || OrganizationLogoObserved is null || _communities is null || token.IsCancellationRequested || _disposed ||
            owner != CurrentContext || generation != Generation || !payload.TryGetProperty("kind", out var kind) ||
            kind.GetString() != "logo" || !payload.TryGetProperty("targetRef", out var reference)) return;
        // Only a complete, validated current image may replace the protected display.
        // A partial new transfer can coexist with an older in-memory sharing logo.
        try {
            var chunk = System.Text.Json.JsonSerializer.SerializeToElement(result, BridgeProtocol.JsonOptions);
            if (chunk.TryGetProperty("next", out var next) && next.ValueKind != System.Text.Json.JsonValueKind.Null) return;
            var version = chunk.GetProperty("version").GetString();
            if (_communities.ObserveDirectoryLogo(reference.GetString()!, FriendScope(owner, generation), version!) is { } logo)
                OrganizationLogoObserved.Invoke(imageRead, owner, generation, logo.Code, logo.Image, token);
        }
        catch (AccountBridgeHostException) { }
    }
}
