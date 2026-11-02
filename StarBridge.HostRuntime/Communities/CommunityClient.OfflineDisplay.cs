using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    internal IReadOnlyList<OfflineOrganizationObservation> ObserveDirectoryDisplay(CommunityPage page, string scope) =>
        page.Items.Select(row => {
            var target = ResolveForRead(row.TargetRef, scope, allowWpfS2: true);
            return new OfflineOrganizationObservation(target.Code, row.Name, row.LogoImageData, row.LogoDeferred);
        }).ToArray();

    internal (string Code, string Image)? ObserveDirectoryLogo(string reference, string scope, string version)
    {
        var target = ResolveForRead(reference, scope, allowWpfS2: true);
        var image = CachedSharingLogo(scope, target.Code);
        if (image is null) return null;
        var comma = image.IndexOf(',');
        var hash = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(Convert.FromBase64String(image[(comma + 1)..])));
        return string.Equals(hash, version, StringComparison.OrdinalIgnoreCase) ? (target.Code, image) : null;
    }
}
