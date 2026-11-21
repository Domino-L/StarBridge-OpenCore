using System.Net;
using System.Security.Cryptography;

namespace StarBridge.HostRuntime.Updates;

/// <summary>Retains a non-writable, non-deletable file lease until the next owner
/// acquires it. A verified download is not an installation/exit authorization.</summary>
internal sealed class VerifiedInstallerDownload(string path, FlutterInstallerUpdateSource.Manifest manifest, FileStream lease,
    FlutterInstallerManifestV2? manifestV2 = null) : IDisposable
{
    internal string Path { get; } = path;
    internal string Version => Manifest.Version;
    internal FlutterInstallerUpdateSource.Manifest Manifest { get; } = manifest;
    internal object SignedManifest => (object?)manifestV2 ?? Manifest;
    public void Dispose() => lease.Dispose();
}

public sealed partial class FlutterInstallerUpdateSource
{
    internal Task<VerifiedInstallerDownload> DownloadAsync(string ownedRoot, string expectedVersion,
        Action<FlutterUpdateProgress>? progress = null, CancellationToken cancellation = default) =>
        DownloadAsync(ownedRoot, expectedVersion, FlutterInstallerPublisherVerifier.VerifyAsync, progress, cancellation);

    // Internal until installed-product ownership and helper handoff are complete.
    // No Bridge caller can provide paths, URLs, public keys or publisher decisions.
    internal async Task<VerifiedInstallerDownload> DownloadAsync(string ownedRoot, string expectedVersion,
        Func<string, string, CancellationToken, Task> verifyPublisher,
        Action<FlutterUpdateProgress>? progress = null, CancellationToken cancellation = default)
    {
        ArgumentNullException.ThrowIfNull(verifyPublisher);
        if (!await _operation.WaitAsync(0, cancellation)) throw new InvalidOperationException("Update operation is in progress.");
        try
        {
            var manifest = _available ?? throw new InvalidOperationException("Check for updates first.");
            var version = _availableV2?.Verify(_platform, _keys) ?? Verify(manifest);
            if (manifest.Version != expectedVersion || version <= _current)
                throw new InvalidOperationException("The confirmed update changed.");
            var mirrors = _availableV2 is null ? new[] { new FlutterUpdateMirror("jp", manifest.DownloadUrl) } :
                FlutterUpdateMirror.Order(_availableV2.DownloadUrls, _domestic);
            for (var i = 0; i < mirrors.Length; i++)
            {
                try
                {
                    var result = await DownloadOneAsync(ownedRoot, manifest, mirrors[i].Url, verifyPublisher, progress, cancellation);
                    if (_availableV2 is not null) Observe("download", i + 1, "verified");
                    return result;
                }
                catch (InvalidOperationException error) when (error.Message == "download-cleanup-failed")
                { Observe("download", i + 1, "download-cleanup-failed"); throw; }
                catch (Exception error) when (_availableV2 is not null && !cancellation.IsCancellationRequested &&
                    error is HttpRequestException or InvalidDataException or IOException or OperationCanceledException or CryptographicException)
                {
                    Observe("download", i + 1, error switch {
                        OperationCanceledException => "download-timeout", HttpRequestException => "download-failed",
                        InvalidDataException when error.Message is "download-size-mismatch" or "download-hash-mismatch" or "publisher-verification-failed" => error.Message,
                        _ => "download-verification-failed" });
                }
            }
            cancellation.ThrowIfCancellationRequested();
            throw new InvalidDataException("download-mirrors-exhausted");
        }
        finally { _operation.Release(); }
    }

    private async Task<VerifiedInstallerDownload> DownloadOneAsync(string ownedRoot, Manifest manifest, string url,
        Func<string, string, CancellationToken, Task> verifyPublisher, Action<FlutterUpdateProgress>? progress,
        CancellationToken cancellation)
    {
        string? file = null;
        var created = false;
        FileStream? lease = null;
        try
        {
            RequirePlainDirectory(ownedRoot);
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellation);
            timeout.CancelAfter(TimeSpan.FromMinutes(10));
            var token = timeout.Token;
            using var response = await _http.GetAsync(new Uri(url), HttpCompletionOption.ResponseHeadersRead, token);
            if (response.StatusCode != HttpStatusCode.OK) throw new HttpRequestException("Installer download did not succeed directly.");
            var total = response.Content.Headers.ContentLength;
            const long maximumBytes = FlutterUpdateManifestVerifier.MaximumPackageBytes;
            if (total is <= 0 or > maximumBytes || _availableV2 is not null && total is not null && total != _availableV2.DownloadBytes)
                throw new InvalidDataException("download-size-mismatch");
            var expectedBytes = _availableV2?.DownloadBytes ?? total;
            RequirePlainDirectory(ownedRoot);
            file = System.IO.Path.Combine(ownedRoot, "installer-" + Guid.NewGuid().ToString("N") + ".exe");
            using var input = await response.Content.ReadAsStreamAsync(token);
            using var hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
            long received = 0;
            progress?.Invoke(new("downloading", 0, total));
            using (var output = new FileStream(file, FileMode.CreateNew, FileAccess.Write, FileShare.Read,
                81920, FileOptions.Asynchronous))
            {
                created = true;
                var buffer = new byte[81920];
                int read;
                while ((read = await input.ReadAsync(buffer, token)) > 0)
                {
                    received += read;
                    if (received > maximumBytes || (expectedBytes is not null && received > expectedBytes)) throw new InvalidDataException("download-size-mismatch");
                    await output.WriteAsync(buffer.AsMemory(0, read), token);
                    hash.AppendData(buffer, 0, read);
                    progress?.Invoke(new("downloading", received, total));
                }
                if (received == 0 || (expectedBytes is not null && received != expectedBytes))
                    throw new InvalidDataException("download-size-mismatch");
                if (!CryptographicOperations.FixedTimeEquals(hash.GetHashAndReset(), Convert.FromHexString(manifest.DownloadSha256)))
                    throw new InvalidDataException("download-hash-mismatch");
                await output.FlushAsync(token);
                output.Flush(flushToDisk: true);
                // Reopen and independently rehash under a read-only lease below;
                // never trust the pathname solely because this writer hashed it.
            }
            RequirePlainDirectory(ownedRoot);
            if ((File.GetAttributes(file) & FileAttributes.ReparsePoint) != 0) throw new InvalidDataException("Redirected installer.");
            lease = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.Read);
            if (lease.Length != received || !CryptographicOperations.FixedTimeEquals(
                await SHA256.HashDataAsync(lease, token), Convert.FromHexString(manifest.DownloadSha256)))
                throw new InvalidDataException("Installer changed after download.");
            progress?.Invoke(new("verifying", received, total));
            try { await verifyPublisher(file, manifest.Version, token); }
            catch (Exception e) when (_availableV2 is not null && e is InvalidDataException or IOException or CryptographicException)
            { throw new InvalidDataException("publisher-verification-failed", e); }
            token.ThrowIfCancellationRequested();
            progress?.Invoke(new("verified", received, total));
            token.ThrowIfCancellationRequested();
            var verified = new VerifiedInstallerDownload(file, manifest, lease, _availableV2);
            lease = null;
            file = null; // Caller retains this one owned artifact, never a user-selected file.
            return verified;
        }
        finally
        {
            lease?.Dispose();
            if (created && file is not null)
            {
                // Delete only the random file created by this attempt, never recurse.
                try { RequirePlainDirectory(ownedRoot); File.Delete(file); }
                catch (Exception e) when (e is IOException or UnauthorizedAccessException) { if (_availableV2 is not null) throw new InvalidOperationException("download-cleanup-failed", e); }
            }
        }
    }

    private static void RequirePlainDirectory(string root)
    {
        if (!System.IO.Path.IsPathFullyQualified(root) || !Directory.Exists(root)) throw new IOException("Update cache unavailable.");
        for (var directory = new DirectoryInfo(root); directory is not null; directory = directory.Parent)
            if ((directory.Attributes & FileAttributes.ReparsePoint) != 0) throw new IOException("Redirected update cache.");
    }
}
