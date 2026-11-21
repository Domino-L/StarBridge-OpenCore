using System.Reflection;
using System.Security.Cryptography;
using System.Text;

namespace StarBridge.HostRuntime.Updates;

/// <summary>Release-owned configuration. URL comes from compiled NativeHost metadata,
/// public keys from embedded project assets, never a UI/Relay/environment override.</summary>
public static class FlutterReleaseUpdateSource
{
    public const string MetadataKey = "StarBridgeFlutterInstallerManifestUrl";
    public const string MetadataKeyV2 = "StarBridgeFlutterInstallerManifestUrlsV2";
    public static bool InstallationEnabled(Assembly assembly) => assembly.GetCustomAttributes<AssemblyMetadataAttribute>()
        .Where(a => a.Key == "StarBridgeEnableInstalledUpdates").Select(a => a.Value).SequenceEqual(new[] { "true" });

    public static IApplicationUpdateSource FromRelease(Assembly releaseAssembly, string? currentVersion, string platform,
        string? dataRoot = null)
    {
        var urls = releaseAssembly.GetCustomAttributes<AssemblyMetadataAttribute>()
            .Where(a => a.Key == MetadataKey).Select(a => a.Value).ToArray();
        var v1 = urls.Length == 1 ? urls[0] : urls.Length == 0 ? null : "invalid";
        var v2 = releaseAssembly.GetCustomAttributes<AssemblyMetadataAttribute>()
            .Where(a => a.Key == MetadataKeyV2).Select(a => a.Value).ToArray();
        var mirrors = FlutterUpdateMirror.ParseMetadata(v2.Length == 1 ? v2[0] : null);
        if (mirrors.Length == 0) return Create(v1, currentVersion, platform);
        try
        {
            Uri? fallback = null;
            if (!string.IsNullOrWhiteSpace(v1))
            {
                fallback = FlutterUpdateManifestVerifier.RequireHttps(v1);
                if (fallback.IsLoopback) throw new InvalidDataException();
            }
            return new FlutterInstallerUpdateSource(fallback, mirrors, platform, currentVersion!, ReadTrustedKeys(),
                new HttpClientHandler { AllowAutoRedirect = false, UseCookies = false },
                () => dataRoot is null ? null : Auth.ScmRegionRouter.ReadCachedClassification(
                    Path.Combine(dataRoot, "scm-region-cache.json"), DateTimeOffset.UtcNow));
        }
        catch { return new FixedSource("configuration-invalid"); }
    }

    internal static IApplicationUpdateSource Create(string? url, string? currentVersion, string platform)
    {
        if (string.IsNullOrWhiteSpace(url)) return new FixedSource("channel-unconfigured");
        try
        {
            var uri = FlutterUpdateManifestVerifier.RequireHttps(url);
            if (uri.IsLoopback) throw new InvalidDataException("Release source must not be loopback.");
            return new FlutterInstallerUpdateSource(uri, platform, currentVersion!, ReadTrustedKeys());
        }
        catch { return new FixedSource("configuration-invalid"); }
    }

    internal static IReadOnlyDictionary<string, string> ReadTrustedKeys()
    {
        var keys = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var name in new[] { "update-signing-public.xml", "update-signing-public-v2.xml" })
        {
            using var stream = typeof(FlutterReleaseUpdateSource).Assembly.GetManifestResourceStream("StarBridge.Updates." + name)
                ?? throw new InvalidDataException("Missing release trust root.");
            using var reader = new StreamReader(stream, Encoding.UTF8);
            var xml = reader.ReadToEnd();
            using var rsa = RSA.Create();
            rsa.FromXmlString(xml);
            if (rsa.KeySize < 2048 || xml.Contains("<D>", StringComparison.Ordinal)) throw new InvalidDataException();
            var id = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(xml)))[..16].ToLowerInvariant();
            keys.Add(id, xml);
        }
        return keys;
    }

    private sealed class FixedSource(string status) : IApplicationUpdateSource
    {
        public Task<ApplicationUpdateCheck> CheckForUpdateAsync(CancellationToken cancellation = default)
        {
            cancellation.ThrowIfCancellationRequested();
            return Task.FromResult(new ApplicationUpdateCheck(status));
        }
        public void Dispose() { }
    }
}
