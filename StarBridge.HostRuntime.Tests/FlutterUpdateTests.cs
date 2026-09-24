using System.IO.Compression;
using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StarBridge.HostRuntime.Updates;

internal static class FlutterUpdateTests
{
    private static readonly FlutterUpdateTarget Target = new("win-x64", "preview", "0.6.6");
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    internal static async Task Verify()
    {
        using var key = RSA.Create(2048);
        var verifier = new FlutterUpdateManifestVerifier(new Dictionary<string, string> { ["isolated-test"] = key.ToXmlString(false) });
        var bytes = Package();
        var manifest = Sign(key, Manifest(bytes));
        if (!verifier.Verify(manifest, Target, DateTimeOffset.UtcNow)) throw new Exception("New update missed.");
        foreach (var invalid in new[] {
            manifest with { ClientKind = "wpf" }, manifest with { SchemaVersion = 0 },
            manifest with { Architecture = "win-arm64" }, manifest with { Channel = "stable" },
            manifest with { PackageFormat = "installer" }, manifest with { Notes = "tampered" },
            manifest with { SignatureKeyId = "unknown" }, manifest with { Signature = "invalid" },
            manifest with { PackageUrl = "http://example.invalid/package.zip" },
            manifest with { PackageUrl = "https://user:password@example.invalid/package.zip" },
            manifest with { PackageBytes = 0 }, manifest with { PublishedAt = DateTimeOffset.UtcNow.AddDays(1) }
        }) Reject(() => verifier.Verify(invalid, Target, DateTimeOffset.UtcNow));
        var old = Sign(key, manifest with { Version = "0.6.5" });
        if (verifier.Verify(old, Target, DateTimeOffset.UtcNow)) throw new Exception("Downgrade accepted.");
        var equal = Sign(key, manifest with { Version = "0.6.6.0" });
        if (verifier.Verify(equal, Target, DateTimeOffset.UtcNow))
            throw new Exception("Three-part and zero-revision versions must not trigger a reinstall.");

        var root = Path.Combine(Path.GetTempPath(), "starbridge-flutter-update-test-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var archive = Path.Combine(root, "package.zip");
            File.WriteAllBytes(archive, bytes);
            var stage = FlutterUpdateStager.Prepare(archive, root, manifest, verifier, Target, DateTimeOffset.UtcNow);
            if (File.ReadAllText(Path.Combine(stage, "starbridge_flutter.exe")) != "isolated-not-an-executable")
                throw new Exception("Package not staged.");
            // All fixtures are inert text, never executed. No installation path is supplied.
            foreach (var bad in new[] { Package("../escape"), Package("data/../../escape"), Package("C:/escape"),
                Package("data/file:stream"), Package("CON.txt"), Package("data/file."),
                Package("FLUTTER_WINDOWS.DLL"), Package("data"), Package(identityKind: "wpf"),
                Package(omitRuntime: true), Package("linked", symlink: true) })
            {
                File.WriteAllBytes(archive, bad);
                var badManifest = Sign(key, Manifest(bad));
                Reject(() => FlutterUpdateStager.Prepare(archive, root, badManifest, verifier, Target, DateTimeOffset.UtcNow));
            }
            File.WriteAllBytes(archive, bytes.Concat(new byte[] { 1 }).ToArray());
            Reject(() => FlutterUpdateStager.Prepare(archive, root, manifest, verifier, Target, DateTimeOffset.UtcNow));
            var transport = new FixtureHandler(manifest, bytes);
            using var runtime = new FlutterUpdateRuntime(new Uri("https://example.invalid/manifest"), Target, verifier, transport);
            var check = await runtime.CheckAsync();
            if (check.Status != "available") throw new Exception("Runtime did not find signed fixture.");
            await RejectAsync(() => runtime.StageAsync(root, expectedVersion: "9.9.9"));
            var runtimeStage = await runtime.StageAsync(root);
            if (!File.Exists(Path.Combine(runtimeStage, FlutterUpdateStager.IdentityFile))) throw new Exception("Runtime stage missing.");
            transport.PackageOverride = bytes[..^1];
            await RejectAsync(() => runtime.StageAsync(root));
            transport.PackageOverride = bytes.Concat(new byte[] { 1 }).ToArray();
            await RejectAsync(() => runtime.StageAsync(root));
            transport.PackageOverride = bytes.Select((value, index) => index == 1 ? (byte)(value ^ 1) : value).ToArray();
            await RejectAsync(() => runtime.StageAsync(root));
            transport.PackageOverride = null;
            transport.ManifestOverride = new string('x', 65537);
            await RejectAsync(() => runtime.CheckAsync());
            transport.ManifestOverride = "{\"version\":\"0.6.7\",\"packageUrl\":\"https://example.invalid/wpf.zip\"}";
            await RejectAsync(() => runtime.CheckAsync());
            transport.ManifestOverride = JsonSerializer.Serialize(manifest, Json)[..^1] + ",\"publicKey\":\"attacker\"}";
            await RejectAsync(() => runtime.CheckAsync());
            transport.ManifestOverride = null;
            transport.Redirect = true;
            await RejectAsync(() => runtime.CheckAsync());
            await RejectAsync(() => runtime.StageAsync(root)); // Failed check invalidates earlier offer.
            using var unconfigured = new FlutterUpdateRuntime(null, Target, verifier, new FixtureHandler(manifest, bytes));
            if ((await unconfigured.CheckAsync()).Status != "channel-unconfigured") throw new Exception("Missing channel misreported.");
            await RejectAsync(() => unconfigured.StageAsync(root));
            try { await unconfigured.CheckAsync(new CancellationToken(true)); throw new Exception("Cancellation ignored."); }
            catch (OperationCanceledException) { }
        }
        finally { Directory.Delete(root, recursive: true); } // Exact dedicated test fixture only.
    }

    private static FlutterUpdateManifest Manifest(byte[] bytes) => new(1, "flutter", "win-x64", "preview",
        "portable-zip", "0.6.7", "https://example.invalid/package.zip", bytes.Length,
        Convert.ToHexString(SHA256.HashData(bytes)), DateTimeOffset.UtcNow.AddMinutes(-1), "Test only", "isolated-test", "");
    private static FlutterUpdateManifest Sign(RSA key, FlutterUpdateManifest manifest) => manifest with {
        Signature = Convert.ToBase64String(key.SignData(Encoding.UTF8.GetBytes(FlutterUpdateManifestVerifier.BuildPayload(manifest)),
            HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1)) };
    private static byte[] Package(string? extra = null, string identityKind = "flutter", bool omitRuntime = false, bool symlink = false)
    {
        using var output = new MemoryStream();
        using (var archive = new ZipArchive(output, ZipArchiveMode.Create, leaveOpen: true))
        {
            Add(archive, FlutterUpdateStager.IdentityFile, JsonSerializer.Serialize(new FlutterPackageIdentity(1,
                identityKind, "win-x64", "preview", "0.6.7", "starbridge_flutter.exe"), Json));
            foreach (var required in FlutterUpdateStager.RequiredFiles)
                if (!omitRuntime || required != "native_host/StarBridge.NativeHost.exe")
                    Add(archive, required, "isolated-not-an-executable");
            if (extra is not null)
            {
                var entry = Add(archive, extra, "rejected");
                if (symlink) entry.ExternalAttributes = unchecked((int)0xA1FF0000);
            }
        }
        return output.ToArray();
    }
    private static ZipArchiveEntry Add(ZipArchive archive, string path, string text)
    {
        var entry = archive.CreateEntry(path);
        using var writer = new StreamWriter(entry.Open());
        writer.Write(text);
        return entry;
    }
    private static void Reject(Action action)
    {
        try { action(); }
        catch (Exception error) when (error is InvalidDataException or JsonException or CryptographicException) { return; }
        throw new Exception("Unsafe update accepted.");
    }
    private static async Task RejectAsync(Func<Task> action)
    {
        try { await action(); }
        catch (Exception error) when (error is HttpRequestException or InvalidOperationException or InvalidDataException or JsonException) { return; }
        throw new Exception("Unsafe runtime action accepted.");
    }
    private sealed class FixtureHandler(FlutterUpdateManifest manifest, byte[] package) : HttpMessageHandler
    {
        public bool Redirect;
        public string? ManifestOverride;
        public byte[]? PackageOverride;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) =>
            Task.FromResult(new HttpResponseMessage(Redirect ? HttpStatusCode.Redirect : HttpStatusCode.OK) {
                Content = request.RequestUri!.AbsolutePath == "/manifest"
                    ? new StringContent(ManifestOverride ?? JsonSerializer.Serialize(manifest, Json), Encoding.UTF8, "application/json")
                    : new ByteArrayContent(PackageOverride ?? package) });
    }
}
