using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace StarBridge.HostRuntime.Updates;

/// <summary>Checks the existing signed Flutter Inno installer contract. Never executes it,
/// follows redirects, sends account credentials, or falls back to WPF/portable manifests.</summary>
public sealed partial class FlutterInstallerUpdateSource : IApplicationUpdateSource
{
    internal sealed record Manifest(string ClientKind, string Platform, string PackageKind,
        string Version, string DownloadUrl, string DownloadSha256, string Notes,
        string SignatureKeyId, string Signature);

    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    {
        PropertyNameCaseInsensitive = false,
        UnmappedMemberHandling = System.Text.Json.Serialization.JsonUnmappedMemberHandling.Disallow
    };
    private readonly Uri _uri;
    private readonly string _platform;
    private readonly Version _current;
    private readonly IReadOnlyDictionary<string, string> _keys;
    private readonly HttpClient _http;
    private readonly SemaphoreSlim _operation = new(1, 1);
    private Manifest? _available;

    public FlutterInstallerUpdateSource(Uri uri, string platform, string currentVersion,
        IReadOnlyDictionary<string, string> trustedKeys)
        : this(uri, platform, currentVersion, trustedKeys,
            new HttpClientHandler { AllowAutoRedirect = false, UseCookies = false }) { }

    internal FlutterInstallerUpdateSource(Uri uri, string platform, string currentVersion,
        IReadOnlyDictionary<string, string> trustedKeys, HttpMessageHandler transport)
    {
        _uri = FlutterUpdateManifestVerifier.RequireHttps(uri.AbsoluteUri);
        if (platform != "windows-x64") throw new InvalidDataException("Unsupported installer target.");
        _platform = platform;
        _current = ApplicationUpdateVersion.ParseInstalled(currentVersion);
        _keys = new Dictionary<string, string>(trustedKeys, StringComparer.Ordinal);
        _http = new HttpClient(transport) { Timeout = Timeout.InfiniteTimeSpan };
    }

    public async Task<ApplicationUpdateCheck> CheckForUpdateAsync(CancellationToken cancellation = default)
    {
        if (!await _operation.WaitAsync(0, cancellation)) throw new InvalidOperationException("Update operation is in progress.");
        try { return await CheckCoreAsync(cancellation); }
        finally { _operation.Release(); }
    }

    private async Task<ApplicationUpdateCheck> CheckCoreAsync(CancellationToken cancellation)
    {
        _available = null;
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
        timeout.CancelAfter(TimeSpan.FromSeconds(30));
        try
        {
            using var response = await _http.GetAsync(_uri, HttpCompletionOption.ResponseHeadersRead, timeout.Token);
            if (response.StatusCode != HttpStatusCode.OK)
            {
                if ((int)response.StatusCode >= 500 || response.StatusCode is HttpStatusCode.RequestTimeout or HttpStatusCode.TooManyRequests)
                    throw new HttpRequestException("Update service is temporarily unavailable.");
                return new("channel-unavailable");
            }
            if (response.Content.Headers.ContentLength is > 65536) throw new InvalidDataException();
            using var input = await response.Content.ReadAsStreamAsync(timeout.Token);
            using var output = new MemoryStream();
            var buffer = new byte[8192];
            int read;
            while ((read = await input.ReadAsync(buffer, timeout.Token)) > 0)
            {
                if (output.Length + read > 65536) throw new InvalidDataException();
                output.Write(buffer, 0, read);
            }
            // Reject duplicate names before deserialization (last-wins JSON is ambiguous).
            using var document = JsonDocument.Parse(output.ToArray());
            if (document.RootElement.ValueKind != JsonValueKind.Object) throw new InvalidDataException();
            var names = document.RootElement.EnumerateObject().Select(p => p.Name).ToArray();
            if (names.Length != 9 || names.Distinct(StringComparer.Ordinal).Count() != 9) throw new InvalidDataException();
            var manifest = document.RootElement.Deserialize<Manifest>(Json) ?? throw new InvalidDataException();
            var candidate = Verify(manifest);
            cancellation.ThrowIfCancellationRequested();
            if (candidate > _current) _available = manifest;
            return candidate > _current ? new("available", manifest.Version, manifest.Notes) : new("up-to-date");
        }
        catch (OperationCanceledException) when (!cancellation.IsCancellationRequested)
        {
            throw new HttpRequestException("Update check timed out.");
        }
    }

    private Version Verify(Manifest manifest) => VerifyManifest(manifest, _platform, _keys);

    internal static Version VerifyManifest(Manifest manifest, string platform, IReadOnlyDictionary<string, string> keys)
    {
        if (manifest.ClientKind != "flutter" || manifest.Platform != platform || manifest.PackageKind != "inno-setup" ||
            manifest.Notes is null || manifest.Notes.Length > 16384 ||
            manifest.SignatureKeyId is null || !keys.TryGetValue(manifest.SignatureKeyId, out var publicKey) ||
            manifest.DownloadSha256 is null || manifest.DownloadSha256.Length != 64 ||
            manifest.DownloadSha256.Any(c => !Uri.IsHexDigit(c)) ||
            string.IsNullOrEmpty(manifest.Signature) || manifest.Signature.Length > 2048 ||
            string.IsNullOrEmpty(manifest.DownloadUrl)) throw new InvalidDataException("Invalid installer manifest.");
        var version = ApplicationUpdateVersion.Parse(manifest.Version);
        FlutterUpdateManifestVerifier.RequireHttps(manifest.DownloadUrl);
        byte[] signature;
        try { signature = Convert.FromBase64String(manifest.Signature); }
        catch (FormatException error) { throw new InvalidDataException("Invalid installer signature.", error); }
        using var rsa = RSA.Create();
        rsa.FromXmlString(publicKey);
        if (rsa.KeySize < 2048 || !rsa.VerifyData(Encoding.UTF8.GetBytes(BuildPayload(manifest)), signature,
            HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1)) throw new InvalidDataException("Untrusted installer manifest.");
        return version;
    }

    internal static string BuildPayload(Manifest manifest) => string.Join('\n',
        "starbridge-flutter-installer-manifest-v1", manifest.ClientKind, manifest.Platform, manifest.PackageKind,
        manifest.Version, manifest.DownloadUrl, manifest.DownloadSha256.ToLowerInvariant(),
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(manifest.Notes))).ToLowerInvariant());

    public void Dispose() => _http.Dispose();
}
