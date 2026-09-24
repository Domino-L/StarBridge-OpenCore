using System.Globalization;
using System.Security.Cryptography;
using System.Text;

namespace StarBridge.HostRuntime.Updates;

/// <summary>A separate signed payload; legacy WPF manifests are never accepted.</summary>
public sealed record FlutterUpdateManifest(
    int SchemaVersion, string ClientKind, string Architecture, string Channel,
    string PackageFormat, string Version, string PackageUrl, long PackageBytes,
    string PackageSha256, DateTimeOffset PublishedAt, string Notes,
    string SignatureKeyId, string Signature);

public sealed record FlutterUpdateTarget(string Architecture, string Channel, string CurrentVersion);

public sealed class FlutterUpdateManifestVerifier
{
    public const string PayloadVersion = "starbridge-flutter-update-manifest-v1";
    public const long MaximumPackageBytes = 1024L * 1024 * 1024;
    private readonly IReadOnlyDictionary<string, string> _trustedPublicKeys;

    // Trust comes from Host configuration, never from a manifest or a Bridge request.
    // Tests supply ephemeral keys; this does not install a production update channel.
    public FlutterUpdateManifestVerifier(IReadOnlyDictionary<string, string> trustedPublicKeys) =>
        _trustedPublicKeys = new Dictionary<string, string>(trustedPublicKeys, StringComparer.Ordinal);

    public bool Verify(FlutterUpdateManifest manifest, FlutterUpdateTarget target, DateTimeOffset now)
    {
        if (manifest.SchemaVersion != 1 || manifest.ClientKind != "flutter" ||
            manifest.PackageFormat != "portable-zip" ||
            manifest.Architecture is not ("win-x64" or "win-arm64") ||
            manifest.Architecture != target.Architecture || manifest.Channel != target.Channel ||
            manifest.Channel is not ("stable" or "preview") ||
            !Version.TryParse(manifest.Version, out var available) || available.Build < 0 ||
            manifest.PackageBytes is <= 0 or > MaximumPackageBytes ||
            manifest.PublishedAt == default || manifest.PublishedAt > now.AddMinutes(5) ||
            manifest.Notes is null || manifest.Notes.Length > 16384 ||
            manifest.SignatureKeyId is null ||
            !_trustedPublicKeys.TryGetValue(manifest.SignatureKeyId, out var key))
            throw new InvalidDataException("Update identity or manifest is invalid.");

        RequireHttps(manifest.PackageUrl);
        if (manifest.PackageSha256 is null || manifest.PackageSha256.Length != 64 ||
            manifest.PackageSha256.Any(character => !Uri.IsHexDigit(character)) ||
            manifest.Signature is null || manifest.Signature.Length > 2048)
            throw new InvalidDataException("Update integrity metadata is invalid.");
        byte[] signature;
        try { signature = Convert.FromBase64String(manifest.Signature); }
        catch (FormatException error) { throw new InvalidDataException("Update signature is invalid.", error); }
        using var rsa = RSA.Create();
        rsa.FromXmlString(key);
        // Same SHA-256 / RSA PKCS#1 scheme as WPF, but a domain-separated payload
        // binds client, architecture and channel as well as the package hash.
        if (rsa.KeySize < 2048 || !rsa.VerifyData(Encoding.UTF8.GetBytes(BuildPayload(manifest)),
                signature, HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1))
            throw new InvalidDataException("Update signature verification failed.");
        return ApplicationUpdateVersion.Parse(manifest.Version) > ApplicationUpdateVersion.ParseInstalled(target.CurrentVersion);
    }

    public static string BuildPayload(FlutterUpdateManifest value) => string.Join('\n',
        PayloadVersion, value.SchemaVersion.ToString(CultureInfo.InvariantCulture),
        value.ClientKind, value.Architecture, value.Channel, value.PackageFormat, value.Version,
        value.PackageUrl, value.PackageBytes.ToString(CultureInfo.InvariantCulture),
        value.PackageSha256.ToLowerInvariant(),
        value.PublishedAt.ToUnixTimeSeconds().ToString(CultureInfo.InvariantCulture),
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value.Notes))).ToLowerInvariant(),
        value.SignatureKeyId);

    public static Uri RequireHttps(string value)
    {
        if (!Uri.TryCreate(value, UriKind.Absolute, out var uri) || uri.Scheme != Uri.UriSchemeHttps ||
            uri.UserInfo.Length != 0 || uri.Fragment.Length != 0 || value.Contains('\n') || value.Contains('\r'))
            throw new InvalidDataException("Update URL must be HTTPS without credentials or a fragment.");
        return uri;
    }
}
