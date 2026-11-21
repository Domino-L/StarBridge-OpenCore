using System.Net;
using System.Security.Cryptography;
using System.Text.RegularExpressions;

namespace StarBridge.HostRuntime.Updates;

public sealed partial class FlutterInstallerUpdateSource
{
    internal const int HeroChunkBytes = 256 * 1024;
    private const int MaximumHeroBytes = 3 * 1024 * 1024;
    private const int MaximumHeroOrigins = 3;
    // 3 x 8s fits inside Flutter's 35s whole-image budget, with 11s for Bridge chunks/hash.
    private static readonly TimeSpan HeroOriginTimeout = TimeSpan.FromSeconds(8);
    private static readonly Regex HeroLine = new(
        @"\A主图校验 sha256=([0-9a-f]{64}) bytes=([1-9][0-9]{0,7})\z", RegexOptions.CultureInvariant);
    private readonly object _heroGate = new();
    private readonly SemaphoreSlim _heroDownload = new(1, 1);
    private HeroImage? _heroCache;
    private Uri[] _heroOrigins = [];

    private sealed record HeroImage(string MediaType, string Sha256, byte[] Bytes);
    internal sealed record HeroChunk(string Version, string MediaType, string Sha256,
        int Length, int Offset, int NextOffset, string Chunk, bool Done);
    private enum ManifestProtocol { V1, V2 }

    // A recheck of the same signed offer retains its memory cache. A changed,
    // failed or withdrawn offer invalidates it, including any in-flight result.
    private void SetAvailable(Manifest? manifest, Uri? verifiedManifestUri = null, ManifestProtocol? protocol = null)
    {
        // Only compile-time manifest inputs may supply an authority. Neither signed
        // downloadUrls/notes nor response headers can expand this allowlist.
        // v1 authorizes only its verified origin, even when v2 mirrors are configured.
        var fallback = protocol == ManifestProtocol.V2
            ? FlutterUpdateMirror.Order(_manifestMirrors, _domestic).Select(m => new Uri(m.Url))
                .Concat(_hasV1 ? new[] { _uri } : Array.Empty<Uri>())
            : Array.Empty<Uri>();
        var origins = manifest is null || verifiedManifestUri is null || protocol is null ? [] :
            new[] { verifiedManifestUri }.Concat(fallback)
                .Select(uri => new Uri(uri.GetLeftPart(UriPartial.Authority)))
                .Distinct().Take(MaximumHeroOrigins).ToArray();
        lock (_heroGate)
        {
            if (_available == manifest && _heroOrigins.SequenceEqual(origins)) return;
            _available = manifest;
            _heroOrigins = origins;
            _heroCache = null;
        }
    }

    private static (string Hash, int Length)? HeroDescriptor(Manifest manifest)
    {
        if (manifest.Version.Split('.').Length != 3) return null;
        var lines = manifest.Notes.Replace("\r\n", "\n", StringComparison.Ordinal).Split('\n');
        var last = lines.Length - 1;
        while (last >= 0 && lines[last].Length == 0) last--;
        if (last < 0) return null;
        var match = HeroLine.Match(lines[last]);
        if (!match.Success || lines.Take(last).Any(line => HeroLine.IsMatch(line)) ||
            !int.TryParse(match.Groups[2].Value, out var length) ||
            length > MaximumHeroBytes) return null;
        return (match.Groups[1].Value, length);
    }

    internal async Task<HeroChunk?> ReadHeroAsync(string version, int offset, CancellationToken cancellation = default)
    {
        Manifest manifest;
        Uri[] origins;
        (string Hash, int Length) descriptor;
        lock (_heroGate)
        {
            if (_available is not { } current || current.Version != version ||
                HeroDescriptor(current) is not { } valid || offset < 0 || offset > valid.Length ||
                (offset != valid.Length && offset % HeroChunkBytes != 0)) return null;
            manifest = current;
            origins = _heroOrigins;
            descriptor = valid;
        }
        // Each request owns its transfer and cancellation. Keep its dispatcher
        // network lease alive until HTTP and stream disposal have physically exited.
        await _heroDownload.WaitAsync(cancellation).ConfigureAwait(false);
        try
        {
            HeroImage? image;
            lock (_heroGate)
            {
                if (!ReferenceEquals(_available, manifest)) return null;
                image = _heroCache;
            }
            if (image is null)
            {
                foreach (var origin in origins)
                {
                    cancellation.ThrowIfCancellationRequested();
                    lock (_heroGate) { if (!ReferenceEquals(_available, manifest)) return null; }
                    image = await DownloadHeroAsync(manifest, origin, descriptor.Hash, descriptor.Length, cancellation).ConfigureAwait(false);
                    if (image is not null) break;
                }
            }
            cancellation.ThrowIfCancellationRequested();
            lock (_heroGate)
            {
                if (image is null || !ReferenceEquals(_available, manifest)) return null;
                var count = Math.Min(HeroChunkBytes, image.Bytes.Length - offset);
                return new(version, image.MediaType, image.Sha256, image.Bytes.Length, offset, offset + count,
                    Convert.ToBase64String(image.Bytes, offset, count), offset + count == image.Bytes.Length);
            }
        }
        finally { _heroDownload.Release(); }
    }

    private async Task<HeroImage?> DownloadHeroAsync(Manifest manifest, Uri origin, string hash, int length, CancellationToken cancellation)
    {
        try
        {
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
            timeout.CancelAfter(HeroOriginTimeout);
            var token = timeout.Token;
            var uri = new Uri(origin, "/downloads/update-art/" + hash + ".jpg");
            using var response = await _http.GetAsync(uri, HttpCompletionOption.ResponseHeadersRead, token).ConfigureAwait(false);
            if (response.StatusCode != HttpStatusCode.OK ||
                response.Content.Headers.ContentLength is long declared && declared != length) return null;
            using var input = await response.Content.ReadAsStreamAsync(token).ConfigureAwait(false);
            var bytes = new byte[length];
            var received = 0;
            while (received < length)
            {
                var read = await input.ReadAsync(bytes.AsMemory(received), token).ConfigureAwait(false);
                if (read == 0) return null;
                received += read;
            }
            if (await input.ReadAsync(new byte[1], token).ConfigureAwait(false) != 0 ||
                !CryptographicOperations.FixedTimeEquals(SHA256.HashData(bytes), Convert.FromHexString(hash))) return null;
            var mediaType = bytes.AsSpan().StartsWith(new byte[] { 0xff, 0xd8, 0xff }) ? "image/jpeg" :
                bytes.AsSpan().StartsWith(new byte[] { 0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a }) ? "image/png" : null;
            if (mediaType is null) return null;
            token.ThrowIfCancellationRequested();
            var image = new HeroImage(mediaType, hash, bytes);
            lock (_heroGate)
            {
                if (!ReferenceEquals(_available, manifest)) return null;
                return _heroCache = image;
            }
        }
        catch { return null; } // No untrusted address, hash or transport detail crosses Bridge.
    }
}
