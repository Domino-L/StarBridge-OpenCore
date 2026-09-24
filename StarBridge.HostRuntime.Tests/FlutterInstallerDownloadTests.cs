using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StarBridge.HostRuntime.Updates;

internal static class FlutterInstallerDownloadTests
{
    internal static async Task Verify()
    {
        using var rsa = RSA.Create(2048);
        var bytes = Encoding.UTF8.GetBytes("inert fixture, never executed");
        var manifest = new FlutterInstallerUpdateSource.Manifest("flutter", "windows-x64", "inno-setup",
            "0.7.1", "https://example.invalid/installer.exe", Convert.ToHexString(SHA256.HashData(bytes)), "fixture", "fixture", "");
        manifest = manifest with { Signature = Convert.ToBase64String(rsa.SignData(
            Encoding.UTF8.GetBytes(FlutterInstallerUpdateSource.BuildPayload(manifest)), HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1)) };
        var handler = new DownloadHandler(JsonSerializer.Serialize(manifest, new JsonSerializerOptions(JsonSerializerDefaults.Web)), bytes);
        using var source = new FlutterInstallerUpdateSource(new Uri("https://example.invalid/manifest.json"), "windows-x64", "0.7.0+1",
            new Dictionary<string, string> { ["fixture"] = rsa.ToXmlString(false) }, handler);
        var root = Path.Combine(Path.GetTempPath(), "starbridge-installer-download-test-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        var untouched = Path.Combine(root, "unrelated.txt");
        File.WriteAllText(untouched, "keep");
        try
        {
            var publisherCalls = 0;
            Task Publisher(string file, string version, CancellationToken token)
            {
                publisherCalls++;
                Require(version == "0.7.1" && File.ReadAllBytes(file).SequenceEqual(bytes), "Unverified file reached publisher boundary.");
                try { using var writer = new FileStream(file, FileMode.Open, FileAccess.Write, FileShare.ReadWrite); throw new Exception("Verified artifact was writable."); }
                catch (IOException) { }
                return Task.CompletedTask;
            }
            await Reject(() => source.DownloadAsync(root, "0.7.1", Publisher));
            Require(handler.Downloads == 0, "Download without checked offer.");
            Require((await source.CheckForUpdateAsync()).Status == "available", "Build suffix prevented update check.");
            await Reject(() => source.DownloadAsync(root, "0.7.2", Publisher));
            Require(handler.Downloads == 0, "Unconfirmed version downloaded.");
            var progress = new List<FlutterUpdateProgress>();
            string downloaded;
            using (var artifact = await source.DownloadAsync(root, "0.7.1", Publisher, progress.Add))
            {
                downloaded = artifact.Path;
                Require(artifact.Version == "0.7.1" && publisherCalls == 1 && File.ReadAllBytes(downloaded).SequenceEqual(bytes), "Download did not complete.");
                Require(progress.First().Phase == "downloading" && progress.Last().Phase == "verified" &&
                    progress.Last().ReceivedBytes == bytes.Length && progress.Any(p => p.Phase == "verifying"), "Progress is inaccurate.");
            }
            File.Delete(downloaded); // Exact file created by this fixture.
            handler.UnknownLength = true;
            using (var artifact = await source.DownloadAsync(root, "0.7.1", Publisher, progress.Add)) downloaded = artifact.Path;
            Require(progress.Last().TotalBytes is null, "Unknown size fabricated a total.");
            File.Delete(downloaded);
            handler.UnknownLength = false;

            foreach (var bad in new[] { bytes[..^1], Array.Empty<byte>(), bytes.Concat(new byte[] { 1 }).ToArray(),
                bytes.Select(b => (byte)(b ^ 1)).ToArray() })
            {
                handler.Bytes = bad;
                var previous = publisherCalls;
                await Reject(() => source.DownloadAsync(root, "0.7.1", Publisher));
                Require(publisherCalls == previous, "Invalid hash reached publisher verifier.");
                RequireClean();
            }
            handler.Bytes = bytes;
            foreach (var declared in new long[] { bytes.Length + 1, bytes.Length - 1, 0, FlutterUpdateManifestVerifier.MaximumPackageBytes + 1 })
            {
                handler.DeclaredLength = declared;
                await Reject(() => source.DownloadAsync(root, "0.7.1", Publisher));
                RequireClean();
            }
            handler.DeclaredLength = null;
            handler.DownloadStatus = HttpStatusCode.Redirect;
            await Reject(() => source.DownloadAsync(root, "0.7.1", Publisher));
            RequireClean();
            handler.DownloadStatus = HttpStatusCode.OK;
            using (var cancelled = new CancellationTokenSource())
            {
                await Reject(() => source.DownloadAsync(root, "0.7.1", Publisher,
                    p => { if (p.ReceivedBytes > 0) cancelled.Cancel(); }, cancelled.Token));
                RequireClean();
            }
            await Reject(() => source.DownloadAsync(root, "0.7.1", (_, _, _) => throw new InvalidDataException("Publisher mismatch")));
            RequireClean();
            // A progress callback uses the real gate to prove a check cannot
            // replace the offer while this download is in flight.
            var concurrentRejected = false;
            using (var artifact = await source.DownloadAsync(root, "0.7.1", Publisher, p =>
            {
                if (p.ReceivedBytes != 0) return;
                try { source.CheckForUpdateAsync().GetAwaiter().GetResult(); }
                catch (InvalidOperationException) { concurrentRejected = true; }
            })) downloaded = artifact.Path;
            File.Delete(downloaded);
            Require(concurrentRejected, "Check replaced an in-flight offer.");
            handler.ManifestStatus = HttpStatusCode.NotFound;
            await source.CheckForUpdateAsync();
            var before = handler.Downloads;
            await Reject(() => source.DownloadAsync(root, "0.7.1", Publisher));
            Require(handler.Downloads == before, "Old offer survived a failed check.");
            RequireClean();
            // Real OS verification rejects the inert unsigned fixture without executing it.
            if (OperatingSystem.IsWindows())
                await Reject(() => FlutterInstallerPublisherVerifier.VerifyAsync(untouched, "0.7.1", CancellationToken.None));

            void RequireClean() => Require(Directory.GetFiles(root).Length == 1 && File.ReadAllText(untouched) == "keep",
                "Failed download remained or unrelated data was changed.");
        }
        finally { Directory.Delete(root, recursive: true); } // Only newly-created TEMP test root.
    }

    private static void Require(bool condition, string message) { if (!condition) throw new Exception(message); }
    private static async Task Reject(Func<Task> action)
    {
        try { await action(); }
        catch (Exception error) when (error is IOException or InvalidDataException or InvalidOperationException or HttpRequestException or OperationCanceledException) { return; }
        throw new Exception("Unsafe or cancelled installer download was accepted.");
    }
    private sealed class DownloadHandler(string manifest, byte[] bytes) : HttpMessageHandler
    {
        internal byte[] Bytes = bytes;
        internal long? DeclaredLength;
        internal bool UnknownLength;
        internal int Downloads;
        internal HttpStatusCode ManifestStatus = HttpStatusCode.OK, DownloadStatus = HttpStatusCode.OK;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            token.ThrowIfCancellationRequested();
            if (request.Headers.Authorization is not null || request.Headers.Contains("Cookie")) throw new Exception("Credentials sent to updater.");
            if (request.RequestUri!.AbsolutePath == "/manifest.json")
                return Task.FromResult(new HttpResponseMessage(ManifestStatus) { Content = new StringContent(manifest) });
            Require(request.RequestUri.AbsolutePath == "/installer.exe", "Unexpected URL.");
            Downloads++;
            HttpContent content = UnknownLength ? new UnknownSizeContent(Bytes) : new ByteArrayContent(Bytes);
            if (DeclaredLength is long length) content.Headers.ContentLength = length;
            return Task.FromResult(new HttpResponseMessage(DownloadStatus) { Content = content });
        }
    }
    private sealed class UnknownSizeContent(byte[] bytes) : ByteArrayContent(bytes)
    {
        protected override bool TryComputeLength(out long length) { length = 0; return false; }
    }
}
