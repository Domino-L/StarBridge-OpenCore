using System.Net;
using System.Security.Cryptography;
using System.Text.Json;

namespace StarBridge.HostRuntime.Updates;

public sealed partial class FlutterInstallerUpdateSource
{
    private FlutterUpdateMirror[] _manifestMirrors = [];
    private FlutterInstallerManifestV2? _availableV2;
    private readonly Func<bool?>? _readRegion;
    private readonly Action<string>? _diagnostic;
    private bool? _domestic;
    private bool _hasV1 = true;

    internal FlutterInstallerUpdateSource(Uri? v1, FlutterUpdateMirror[] mirrors, string platform, string version,
        IReadOnlyDictionary<string, string> keys, HttpMessageHandler handler, Func<bool?>? readRegion = null,
        Action<string>? diagnostic = null)
        : this(v1 ?? new Uri(mirrors[0].Url), platform, version, keys, handler)
    {
        FlutterUpdateMirror.Validate(mirrors);
        _manifestMirrors = mirrors.ToArray();
        _hasV1 = v1 is not null;
        _readRegion = readRegion;
        _diagnostic = diagnostic;
    }

    private void Observe(string kind, int index, string result)
    {
        var message = $"{kind}={index} result={result}";
        if (_diagnostic is not null) _diagnostic(message);
        else Auth.ScmAuthDiagnostics.Write("update-mirrors", "device", "observation", message);
    }

    private async Task<ApplicationUpdateCheck> CheckMirrorsAsync(CancellationToken cancellation)
    {
        _availableV2 = null;
        _domestic = _readRegion?.Invoke();
        var mirrors = FlutterUpdateMirror.Order(_manifestMirrors, _domestic);
        // A valid manifest that is not newer may come from a mirror that lags behind; keep asking the rest.
        var upToDate = false;
        var failed = false;
        var verificationFailed = false;
        for (var i = 0; i < mirrors.Length; i++)
        {
            try
            {
                using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
                timeout.CancelAfter(TimeSpan.FromSeconds(30));
                using var response = await _http.GetAsync(new Uri(mirrors[i].Url), HttpCompletionOption.ResponseHeadersRead, timeout.Token);
                if (response.StatusCode != HttpStatusCode.OK) throw new HttpRequestException();
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
                using var document = JsonDocument.Parse(output.ToArray());
                var manifest = FlutterInstallerManifestV2.Read(document.RootElement);
                var version = manifest.Verify(_platform, _keys);
                cancellation.ThrowIfCancellationRequested();
                if (version <= _current) { Observe("manifest", i + 1, "verified-not-newer"); upToDate = true; continue; }
                _availableV2 = manifest;
                SetAvailable(manifest.Common, new Uri(mirrors[i].Url), ManifestProtocol.V2);
                Observe("manifest", i + 1, "verified");
                return new("available", manifest.Version, manifest.Notes);
            }
            catch (Exception error) when (!cancellation.IsCancellationRequested && error is
                HttpRequestException or OperationCanceledException or InvalidDataException or IOException or JsonException or CryptographicException or ArgumentException)
            {
                failed = true;
                verificationFailed |= error is not (HttpRequestException or OperationCanceledException or IOException);
                Observe("manifest", i + 1, error switch {
                    OperationCanceledException => "manifest-timeout", HttpRequestException => "manifest-download-failed",
                    _ => "manifest-verification-failed" });
            }
        }
        cancellation.ThrowIfCancellationRequested();
        // "Up to date" only when every mirror confirmed it; a failed mirror may hold the newer release, so ask v1.
        if (upToDate && !failed) { SetAvailable(null); return new("up-to-date"); }
        if (!_hasV1)
        {
            if (upToDate) { SetAvailable(null); return new("up-to-date"); }
            // Keep the network/verification distinction the bridge reports to the user.
            throw verificationFailed ? new InvalidDataException("manifest-mirrors-exhausted")
                : new HttpRequestException("manifest-mirrors-exhausted");
        }
        try
        {
            var result = await CheckCoreAsync(cancellation);
            Observe("manifest-v1", 1, result.Status);
            return result;
        }
        catch (Exception e) when (!cancellation.IsCancellationRequested && e is HttpRequestException or InvalidDataException or IOException or JsonException)
        { Observe("manifest-v1", 1, "manifest-failed"); throw; }
    }
}
