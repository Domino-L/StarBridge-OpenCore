namespace StarBridge.HostRuntime.Auth;

// Published once startup resolves the actual API route, including preflight fallback.
// Website links do not follow an OAuth-only explicit web override.
internal static class ScmWebsiteRouting
{
    internal static readonly Uri DomesticRoot = new("https://flowcld.xyz/");
    internal static readonly Uri OverseasRoot = new("https://scm.flowcld.com/");
    private static Uri _currentRoot = OverseasRoot;
    internal static Uri CurrentRoot => System.Threading.Volatile.Read(ref _currentRoot);
    internal static bool IsDomestic(ScmRegionRoute? route) =>
        route?.ApiBaseUri.Host.Equals("flowcld.xyz", StringComparison.OrdinalIgnoreCase) == true;
    internal static void SetActive(ScmRegionRoute? route) =>
        System.Threading.Volatile.Write(ref _currentRoot, IsDomestic(route) ? DomesticRoot : OverseasRoot);

    internal static Uri Chat(long peer) => new(CurrentRoot,
        "message?userId=" + peer.ToString(System.Globalization.CultureInfo.InvariantCulture));
}