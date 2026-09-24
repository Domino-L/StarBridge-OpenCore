using System.Net;
using System.Text.Json;

namespace StarBridge.HostRuntime.Updates;

public sealed record FlutterUpdateCheck(string Status, FlutterUpdateManifest? Available = null);
internal sealed record FlutterUpdateArtifact(string Stage, string Archive, FlutterUpdateManifest Manifest);

/// <summary>Host-owned check/download/stage boundary. No installation or process launch side effects.</summary>
public sealed class FlutterUpdateRuntime : IApplicationUpdateSource
{
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
        { UnmappedMemberHandling = System.Text.Json.Serialization.JsonUnmappedMemberHandling.Disallow };
    private readonly Uri? _manifestUri;
    private readonly FlutterUpdateTarget _target;
    private readonly FlutterUpdateManifestVerifier _verifier;
    private readonly HttpClient _http;
    private readonly SemaphoreSlim _gate = new(1, 1);
    private FlutterUpdateManifest? _available;
    private bool _disposed;
    private FlutterUpdateArtifact? _preparedArtifact;

    internal FlutterUpdateArtifact RequirePreparedArtifact(string stage)
    {
        ObjectDisposedException.ThrowIf(_disposed, this);
        var artifact = _preparedArtifact;
        if (artifact is null || artifact.Stage != stage) throw new InvalidOperationException("Unknown prepared artifact.");
        return artifact;
    }

    public FlutterUpdateRuntime(Uri? manifestUri, FlutterUpdateTarget target,
        FlutterUpdateManifestVerifier verifier)
        : this(manifestUri, target, verifier, new HttpClientHandler { AllowAutoRedirect = false }) { }

    internal FlutterUpdateRuntime(Uri? manifestUri, FlutterUpdateTarget target,
        FlutterUpdateManifestVerifier verifier, HttpMessageHandler handler)
    {
        _manifestUri = manifestUri is null ? null : FlutterUpdateManifestVerifier.RequireHttps(manifestUri.AbsoluteUri);
        _target = target;
        _verifier = verifier;
        _http = new HttpClient(handler) { Timeout = TimeSpan.FromMinutes(10) };
    }

    public async Task<FlutterUpdateCheck> CheckAsync(CancellationToken cancellation = default)
    {
        await _gate.WaitAsync(cancellation);
        try
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            _available = null;
            if (_manifestUri is null) return new("channel-unconfigured");
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
            timeout.CancelAfter(TimeSpan.FromSeconds(30));
            using var response = await GetAsync(_manifestUri, timeout.Token);
            using var output = new MemoryStream();
            await CopyBoundedAsync(response, output, 65536, exactSize: false, timeout.Token);
            output.Position = 0;
            var manifest = await JsonSerializer.DeserializeAsync<FlutterUpdateManifest>(output, Json, timeout.Token)
                ?? throw new InvalidDataException("Update manifest is missing.");
            if (!_verifier.Verify(manifest, _target, DateTimeOffset.UtcNow)) return new("up-to-date");
            _available = manifest;
            return new("available", manifest);
        }
        finally { _gate.Release(); }
    }

    async Task<ApplicationUpdateCheck> IApplicationUpdateSource.CheckForUpdateAsync(CancellationToken cancellation)
    {
        var result = await CheckAsync(cancellation);
        return new(result.Status, result.Available?.Version, result.Available?.Notes);
    }

    // Only the manifest already checked by this instance can be staged. Bridge callers
    // must not submit paths, URLs, keys or a replacement manifest as an update command.
    public async Task<string> StageAsync(string ownedStagingRoot, CancellationToken cancellation = default,
        string? expectedVersion = null)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
        timeout.CancelAfter(TimeSpan.FromMinutes(10));
        cancellation = timeout.Token;
        await _gate.WaitAsync(cancellation);
        try
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            var manifest = _available ?? throw new InvalidOperationException("Check for an update first.");
            _preparedArtifact = null;
            if (expectedVersion is not null && manifest.Version != expectedVersion)
                throw new InvalidOperationException("The confirmed update offer changed.");
            if (!_verifier.Verify(manifest, _target, DateTimeOffset.UtcNow)) throw new InvalidDataException();
            if (!Path.IsPathFullyQualified(ownedStagingRoot) || !Directory.Exists(ownedStagingRoot))
                throw new IOException("Owned staging directory is unavailable.");
            for (var directory = new DirectoryInfo(ownedStagingRoot); directory is not null; directory = directory.Parent)
                if ((directory.Attributes & FileAttributes.ReparsePoint) != 0) throw new IOException("Redirected staging root.");
            var package = Path.Combine(ownedStagingRoot, "flutter-download-" + Guid.NewGuid().ToString("N") + ".zip");
            using var response = await GetAsync(new Uri(manifest.PackageUrl), cancellation);
            using (var output = new FileStream(package, FileMode.CreateNew, FileAccess.Write, FileShare.None,
                81920, FileOptions.Asynchronous))
                await CopyBoundedAsync(response, output, manifest.PackageBytes, exactSize: true, cancellation);
            var stage = await Task.Run(() => FlutterUpdateStager.Prepare(package, ownedStagingRoot,
                manifest, _verifier, _target, DateTimeOffset.UtcNow, cancellation), cancellation);
            cancellation.ThrowIfCancellationRequested();
            _preparedArtifact = new(stage, package, manifest);
            return stage;
        }
        finally { _gate.Release(); }
    }

    private async Task<HttpResponseMessage> GetAsync(Uri uri, CancellationToken cancellation)
    {
        var response = await _http.GetAsync(uri, HttpCompletionOption.ResponseHeadersRead, cancellation);
        if (response.StatusCode != HttpStatusCode.OK)
        {
            response.Dispose();
            throw new HttpRequestException("Update endpoint did not return a direct successful HTTPS response.");
        }
        return response;
    }

    private static async Task CopyBoundedAsync(HttpResponseMessage response, Stream output, long limit,
        bool exactSize, CancellationToken cancellation)
    {
        if (response.Content.Headers.ContentLength is long size &&
            (size > limit || (exactSize && size != limit))) throw new InvalidDataException("Invalid update download size.");
        using var input = await response.Content.ReadAsStreamAsync(cancellation);
        var buffer = new byte[81920];
        long total = 0;
        int count;
        while ((count = await input.ReadAsync(buffer, cancellation)) > 0)
        {
            total += count;
            if (total > limit) throw new InvalidDataException("Update download exceeds its limit.");
            await output.WriteAsync(buffer.AsMemory(0, count), cancellation);
        }
        if (exactSize && total != limit) throw new InvalidDataException("Incomplete update download.");
    }

    public void Dispose() { _disposed = true; _http.Dispose(); }
}
