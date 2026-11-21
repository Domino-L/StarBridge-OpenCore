using System.Globalization;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace StarBridge.HostRuntime.Updates;

// Separate wire/signature domain: the shipped nine-field v1 contract stays unchanged.
internal sealed record FlutterInstallerManifestV2(string ClientKind, string Platform, string PackageKind,
    string Version, FlutterUpdateMirror[] DownloadUrls, long DownloadBytes, string DownloadSha256,
    string Notes, string SignatureKeyId, string Signature)
{
    internal static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        PropertyNameCaseInsensitive = false,
        UnmappedMemberHandling = System.Text.Json.Serialization.JsonUnmappedMemberHandling.Disallow
    };

    internal static FlutterInstallerManifestV2 Read(JsonElement root)
    {
        RequireProperties(root, 10);
        if (!root.TryGetProperty("downloadUrls", out var urls) || urls.ValueKind != JsonValueKind.Array)
            throw new InvalidDataException("manifest-invalid");
        foreach (var item in urls.EnumerateArray()) RequireProperties(item, 2);
        return root.Deserialize<FlutterInstallerManifestV2>(Json) ?? throw new InvalidDataException("manifest-invalid");
    }

    private static void RequireProperties(JsonElement root, int count)
    {
        if (root.ValueKind != JsonValueKind.Object) throw new InvalidDataException("manifest-invalid");
        var names = root.EnumerateObject().Select(p => p.Name).ToArray();
        if (names.Length != count || names.Distinct(StringComparer.Ordinal).Count() != count)
            throw new InvalidDataException("manifest-invalid");
    }

    internal Version Verify(string platform, IReadOnlyDictionary<string, string> keys)
    {
        FlutterUpdateMirror.Validate(DownloadUrls);
        if (ClientKind != "flutter" || Platform != platform || PackageKind != "inno-setup" ||
            DownloadBytes is <= 0 or > FlutterUpdateManifestVerifier.MaximumPackageBytes ||
            Notes is null || Notes.Length > 16384 || SignatureKeyId is null || !keys.TryGetValue(SignatureKeyId, out var key) ||
            DownloadSha256 is null || DownloadSha256.Length != 64 || DownloadSha256.Any(c => !Uri.IsHexDigit(c)) ||
            string.IsNullOrEmpty(Signature) || Signature.Length > 2048) throw new InvalidDataException("manifest-invalid");
        var version = ApplicationUpdateVersion.Parse(Version);
        byte[] signature;
        try { signature = Convert.FromBase64String(Signature); }
        catch (FormatException) { throw new InvalidDataException("manifest-signature-invalid"); }
        using var rsa = RSA.Create();
        rsa.FromXmlString(key);
        if (rsa.KeySize < 2048 || !rsa.VerifyData(Encoding.UTF8.GetBytes(BuildPayload()), signature,
            HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1)) throw new InvalidDataException("manifest-signature-invalid");
        return version;
    }

    // Count plus region/URL pairs preserves order and prevents ambiguous list framing.
    internal string BuildPayload() => string.Join('\n', new[] {
        "starbridge-flutter-installer-manifest-v2", ClientKind, Platform, PackageKind, Version,
        DownloadBytes.ToString(CultureInfo.InvariantCulture), DownloadSha256.ToLowerInvariant(),
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(Notes))).ToLowerInvariant(),
        DownloadUrls.Length.ToString(CultureInfo.InvariantCulture)
    }.Concat(DownloadUrls.SelectMany(m => new[] { m.Region, m.Url })));

    // Only common installer fields; never used for v1 signature verification.
    internal FlutterInstallerUpdateSource.Manifest Common => new(ClientKind, Platform, PackageKind, Version,
        DownloadUrls[0].Url, DownloadSha256, Notes, SignatureKeyId, Signature);
}

internal sealed record FlutterUpdateMirror(string Region, string Url)
{
    internal static void Validate(FlutterUpdateMirror[]? mirrors)
    {
        if (mirrors is null || mirrors.Length is < 1 or > 4) throw new InvalidDataException("mirror-list-invalid");
        var unique = new HashSet<Uri>();
        foreach (var mirror in mirrors)
        {
            if (mirror is null || mirror.Region is not ("jp" or "hk") || mirror.Url is null ||
                mirror.Url.Any(char.IsControl)) throw new InvalidDataException("mirror-list-invalid");
            var uri = FlutterUpdateManifestVerifier.RequireHttps(mirror.Url);
            if (uri.IsLoopback || !unique.Add(uri)) throw new InvalidDataException("mirror-list-invalid");
        }
    }

    // Metadata is a single string: jp|https://...;hk|https://... (literal delimiters forbidden in URLs).
    internal static FlutterUpdateMirror[] ParseMetadata(string? value)
    {
        if (string.IsNullOrEmpty(value)) return [];
        try
        {
            var mirrors = value.Split(';').Select(entry => {
                var parts = entry.Split('|');
                if (parts.Length != 2) throw new InvalidDataException();
                return new FlutterUpdateMirror(parts[0], parts[1]);
            }).ToArray();
            Validate(mirrors);
            return mirrors;
        }
        catch (Exception e) when (e is InvalidDataException or ArgumentException or UriFormatException) { return []; }
    }

    internal static FlutterUpdateMirror[] Order(FlutterUpdateMirror[] mirrors, bool? domestic) =>
        domestic is null ? mirrors.ToArray() : mirrors.OrderBy(m => m.Region == (domestic.Value ? "hk" : "jp") ? 0 : 1).ToArray();
}
