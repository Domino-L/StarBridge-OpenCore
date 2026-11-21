using System.Net;
using System.Reflection;
using System.Reflection.Emit;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Updates;

internal static class FlutterUpdateMirrorTests
{
    private static readonly Uri V1 = new("https://jp.example.invalid/v1.json");
    private static readonly FlutterUpdateMirror[] Manifests = [
        new("jp", "https://jp.example.invalid/v2.json"), new("hk", "https://hk.example.invalid/v2.json")];
    private static readonly FlutterUpdateMirror[] Downloads = [
        new("jp", "https://jp.example.invalid/setup.exe"), new("hk", "https://hk.example.invalid/setup.exe")];
    private static readonly byte[] Bytes = Encoding.UTF8.GetBytes("inert mirror test package, never executed");
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);

    internal static async Task Verify()
    {
        using var rsa = RSA.Create(2048);
        var keys = new Dictionary<string, string> { ["fixture"] = rsa.ToXmlString(false) };
        // Literal payload is independent of the production serializer/payload builder.
        FlutterInstallerManifestV2 Sign(FlutterInstallerManifestV2 value) => value with {
            Signature = Convert.ToBase64String(rsa.SignData(Encoding.UTF8.GetBytes(string.Join('\n', new[] {
                "starbridge-flutter-installer-manifest-v2", value.ClientKind, value.Platform, value.PackageKind,
                value.Version, value.DownloadBytes.ToString(System.Globalization.CultureInfo.InvariantCulture),
                value.DownloadSha256.ToLowerInvariant(),
                Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value.Notes))).ToLowerInvariant(),
                value.DownloadUrls.Length.ToString(System.Globalization.CultureInfo.InvariantCulture)
            }.Concat(value.DownloadUrls.SelectMany(m => new[] { m.Region, m.Url })))), HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1))
        };
        var valid = Sign(new("flutter", "windows-x64", "inno-setup", "0.7.3", Downloads, Bytes.Length,
            Convert.ToHexString(SHA256.HashData(Bytes)), "镜像更新", "fixture", ""));
        var validJson = JsonSerializer.Serialize(valid, Json);
        using (var document = JsonDocument.Parse(validJson)) {
            var parsed = FlutterInstallerManifestV2.Read(document.RootElement);
            Require(parsed.Verify("windows-x64", keys) == new Version("0.7.3.0"), "v2 independent signature");
            var handoff = InstalledUpdateWindowsOperations.VerifySignedManifest(document.RootElement, keys);
            Require(handoff.Bytes == Bytes.Length && handoff.Manifest.Version == "0.7.3", "helper v2 re-verification");
        }
        using (var otherRsa = RSA.Create(2048)) {
            var rotatedKeys = new Dictionary<string, string>(keys) { ["rotated"] = otherRsa.ToXmlString(false) };
            var rotated = valid with { SignatureKeyId = "rotated" };
            rotated = rotated with { Signature = Convert.ToBase64String(otherRsa.SignData(Encoding.UTF8.GetBytes(rotated.BuildPayload()), HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1)) };
            Require(rotated.Verify("windows-x64", rotatedKeys) == new Version("0.7.3.0"), "second trust root");
        }
        foreach (var bad in new[] {
            valid with { Notes = "tampered" }, valid with { Version = "0.7.4" }, valid with { DownloadBytes = Bytes.Length + 1 },
            valid with { DownloadUrls = Downloads.Reverse().ToArray() },
            valid with { DownloadUrls = [Downloads[0] with { Region = "hk" }, Downloads[1]] },
            valid with { SignatureKeyId = "unknown" }, valid with { Signature = "invalid" },
            Sign(valid with { ClientKind = "wpf" }), Sign(valid with { Platform = "windows-arm64" }),
            Sign(valid with { PackageKind = "zip" }), Sign(valid with { Version = "0.7.3+1" }),
            Sign(valid with { DownloadSha256 = new string('z', 64) }), Sign(valid with { DownloadBytes = 0 }),
            Sign(valid with { DownloadBytes = FlutterUpdateManifestVerifier.MaximumPackageBytes + 1 }),
            Sign(valid with { DownloadUrls = [] }), Sign(valid with { DownloadUrls = Enumerable.Repeat(Downloads[0], 5).ToArray() }),
            Sign(valid with { DownloadUrls = [Downloads[0], Downloads[0]] }),
            Sign(valid with { DownloadUrls = [new("bad", Downloads[0].Url)] }),
            Sign(valid with { DownloadUrls = [new("jp", "http://example.invalid/setup.exe")] }),
            Sign(valid with { DownloadUrls = [new("jp", "https://localhost/setup.exe")] }),
            Sign(valid with { DownloadUrls = [new("jp", "https://127.0.0.1/setup.exe")] }),
            Sign(valid with { DownloadUrls = [new("jp", "https://[::1]/setup.exe")] }),
            Sign(valid with { DownloadUrls = [new("jp", "https://example.invalid/setup.exe#fragment")] })
        }) Reject(() => bad.Verify("windows-x64", keys), "invalid v2 accepted");
        foreach (var count in new[] { 1, 4 }) {
            var list = Enumerable.Range(0, count).Select(i => new FlutterUpdateMirror("jp", $"https://example.invalid/{i}.exe")).ToArray();
            Require(Sign(valid with { DownloadUrls = list }).Verify("windows-x64", keys) == new Version("0.7.3.0"), "valid list boundary");
        }
        foreach (var badJson in new[] {
            "null", "[]", "{}", validJson[..^1] + ",\"extra\":1}",
            validJson[..^1] + ",\"version\":\"0.7.3\"}",
            validJson.Replace("\"region\":\"jp\"", "\"region\":\"jp\",\"region\":\"hk\""),
            validJson.Replace("\"region\":\"jp\"", "\"region\":\"jp\",\"extra\":1"),
            validJson.Replace("\"downloadBytes\":", "\"DownloadBytes\":"),
            validJson.Replace("\"downloadUrls\":[", "\"downloadUrls\":[null,")
        }) Reject(() => { using var d = JsonDocument.Parse(badJson); FlutterInstallerManifestV2.Read(d.RootElement).Verify("windows-x64", keys); }, "invalid JSON accepted");
        Console.WriteLine("PASS mirror v2 strict schema, ordered independent signature, bounds and helper handoff");

        var v1 = new FlutterInstallerUpdateSource.Manifest("flutter", "windows-x64", "inno-setup", "0.7.3",
            Downloads[0].Url, valid.DownloadSha256, "legacy", "fixture", "");
        v1 = v1 with { Signature = Convert.ToBase64String(rsa.SignData(Encoding.UTF8.GetBytes(string.Join('\n',
            "starbridge-flutter-installer-manifest-v1", v1.ClientKind, v1.Platform, v1.PackageKind, v1.Version,
            v1.DownloadUrl, v1.DownloadSha256.ToLowerInvariant(), Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(v1.Notes))).ToLowerInvariant())),
            HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1)) };
        var v1Json = JsonSerializer.Serialize(v1, Json);
        using (var transport = new Handler()) {
            transport.Manifest = _ => new StringContent(v1Json);
            using var source = new FlutterInstallerUpdateSource(V1, "windows-x64", "0.7.2.1", keys, transport);
            Require((await source.CheckForUpdateAsync()).Status == "available", "0.7.2.1 to 0.7.3 v1 upgrade");
            transport.Manifest = _ => new StringContent(v1Json[..^1] + ",\"downloadUrls\":[]}");
            await RejectAsync(() => source.CheckForUpdateAsync(), "v1 accepted v2 field");
        }
        Console.WriteLine("PASS mirror v1 0.7.2.1 upgrade and extra-field rejection");

        foreach (var region in new bool?[] { true, false, null }) {
            using var transport = new Handler { Manifest = _ => new StringContent(validJson) };
            var observations = new List<string>();
            using var source = Source(transport, region, observations);
            Require((await source.CheckForUpdateAsync()).Status == "available", "region check");
            var preferred = region == true ? "hk" : "jp";
            Require(transport.Requests.Single().Host.StartsWith(preferred), "manifest region ordering");
            var root = NewRoot();
            try {
                string file;
                using (var artifact = await source.DownloadAsync(root, "0.7.3", Publisher)) {
                    file = artifact.Path;
                    Require(artifact.SignedManifest is FlutterInstallerManifestV2, "lost signed v2 at handoff");
                }
                File.Delete(file);
                Require(transport.Requests.Last().Host.StartsWith(preferred), "download region ordering");
                Require(observations.SequenceEqual(new[] { "manifest=1 result=verified", "download=1 result=verified" }), "fixed index diagnostics");
            } finally { Directory.Delete(root); }
        }
        Require(FlutterUpdateMirror.Order(Downloads.Reverse().ToArray(), null)[0].Region == "hk", "unknown must retain compiled order");
        foreach (var firstBad in new[] { "transport", "signature", "redirect", "oversized" }) {
            using var transport = new Handler {
                Manifest = uri => uri.Host.StartsWith("jp") ? firstBad switch {
                    "transport" => throw new HttpRequestException(), "signature" => new StringContent(validJson.Replace("镜像更新", "tampered")),
                    "redirect" => throw new HttpRequestException(), _ => new StringContent(new string('x', 65537))
                } : new StringContent(validJson)
            };
            // JSON's default encoder escapes Chinese, so tamper a literal signature field instead.
            if (firstBad == "signature") transport.Manifest = uri => new StringContent(uri.Host.StartsWith("jp") ? validJson.Replace("0.7.3", "0.7.4") : validJson);
            var observations = new List<string>();
            using var source = Source(transport, null, observations);
            Require((await source.CheckForUpdateAsync()).Status == "available" && transport.Requests.Count == 2, "second manifest not attempted");
            Require(observations.Count == 2 && observations[1] == "manifest=2 result=verified", "manifest retry diagnostics");
        }
        foreach (var failure in new[] { "transport", "signature" }) {
            using var transport = new Handler { Manifest = uri => uri == V1 ? new StringContent(v1Json) :
                failure == "transport" ? throw new HttpRequestException() : new StringContent(validJson.Replace("0.7.3", "0.7.4")) };
            using var source = Source(transport, null, []);
            Require((await source.CheckForUpdateAsync()).Status == "available" && transport.Requests.Last() == V1 && transport.Requests.Count == 3, "v1 fallback");
        }
        using (var transport = new Handler { Manifest = _ => throw new HttpRequestException() }) {
            using var source = new FlutterInstallerUpdateSource(null, Manifests, "windows-x64", "0.7.2.1", keys, transport, diagnostic: _ => { });
            await RejectAsync(() => source.CheckForUpdateAsync(), "all manifests failed silently");
            try { await source.CheckForUpdateAsync(); throw new Exception("network exhaustion not reported"); }
            catch (HttpRequestException) { }
        }
        using (var transport = new Handler { Manifest = _ => new StringContent(validJson.Replace("0.7.3", "0.7.4")) }) {
            using var source = new FlutterInstallerUpdateSource(null, Manifests, "windows-x64", "0.7.2.1", keys, transport, diagnostic: _ => { });
            try { await source.CheckForUpdateAsync(); throw new Exception("verification exhaustion not reported"); }
            catch (InvalidDataException) { }
        }
        using (var transport = new Handler { Manifest = uri => uri == V1 ? new StringContent(v1Json) : uri.Host.StartsWith("jp")
            ? new StringContent(JsonSerializer.Serialize(Sign(valid with { Version = "0.7.2" }), Json)) : throw new HttpRequestException() }) {
            using var source = Source(transport, null, []);
            Require((await source.CheckForUpdateAsync()).Status == "available" && transport.Requests.Last() == V1 && transport.Requests.Count == 3,
                "an older mirror plus a failed mirror must still ask v1");
        }
        using (var transport = new Handler { Manifest = _ => new StringContent(JsonSerializer.Serialize(Sign(valid with { Version = "0.7.2" }), Json)) }) {
            using var source = Source(transport, null, []);
            Require((await source.CheckForUpdateAsync()).Status == "up-to-date" && transport.Requests.Count == 2, "every mirror older means up to date, without v1");
        }
        using (var transport = new Handler { Manifest = uri => uri.Host.StartsWith("jp")
            ? new StringContent(JsonSerializer.Serialize(Sign(valid with { Version = "0.7.2" }), Json)) : new StringContent(validJson) }) {
            var observations = new List<string>();
            using var source = Source(transport, null, observations);
            Require((await source.CheckForUpdateAsync()).Status == "available" && transport.Requests.Count == 2, "a lagging first mirror must not hide a newer release");
            Require(observations.SequenceEqual(new[] { "manifest=1 result=verified-not-newer", "manifest=2 result=verified" }), "lagging mirror diagnostics");
        }
        Console.WriteLine("PASS mirror domestic, overseas, unknown order; manifest retry, lagging mirrors and v1 fallback");

        foreach (var failure in new[] { "http", "transport", "partial", "size", "hash", "signature", "publisher" }) {
            var root = NewRoot();
            try {
                var observations = new List<string>();
                var calls = 0;
                using var transport = new Handler { Manifest = _ => new StringContent(validJson) };
                transport.Package = uri => {
                    Require(!Directory.EnumerateFiles(root).Any(), "previous attempt residue before next request");
                    if (!uri.Host.StartsWith("jp")) return new ByteArrayContent(Bytes);
                    return failure switch {
                        "http" => throw new HttpRequestException(), "transport" => throw new HttpRequestException(),
                        "partial" => new StreamContent(new FailingStream(Bytes)),
                        "size" => new ByteArrayContent(Bytes[..^1]),
                        "hash" => new ByteArrayContent(Bytes.Select(b => (byte)(b ^ 1)).ToArray()),
                        _ => new ByteArrayContent(Bytes)
                    };
                };
                using var source = Source(transport, null, observations);
                await source.CheckForUpdateAsync();
                Task VerifyPublisher(string path, string version, CancellationToken token) {
                    calls++;
                    if (calls == 1 && failure is "signature" or "publisher") throw new InvalidDataException("synthetic rejection");
                    return Publisher(path, version, token);
                }
                string file;
                using (var artifact = await source.DownloadAsync(root, "0.7.3", VerifyPublisher)) file = artifact.Path;
                Require(transport.Requests.Count == 3 && Directory.GetFiles(root).SequenceEqual(new[] { file }), "download retry/cleanup");
                Require(calls == (failure is "signature" or "publisher" ? 2 : 1), "unverified content reached publisher");
                var reason = failure switch { "http" or "transport" => "download-failed", "partial" => "download-verification-failed",
                    "size" => "download-size-mismatch", "hash" => "download-hash-mismatch", _ => "publisher-verification-failed" };
                Require(observations.Contains("download=1 result=" + reason) && observations.Last() == "download=2 result=verified", "fixed download reason");
                File.Delete(file);
            } finally { Directory.Delete(root); }
        }
        {
            var root = NewRoot();
            try {
                using var transport = new Handler { Manifest = _ => new StringContent(validJson), Package = _ => new ByteArrayContent(Bytes.Select(b => (byte)(b ^ 1)).ToArray()) };
                using var source = Source(transport, null, []);
                await source.CheckForUpdateAsync();
                await RejectAsync(() => source.DownloadAsync(root, "0.7.3", Publisher), "all downloads failed silently");
                Require(!Directory.GetFiles(root).Any() && transport.Requests.Count == 3, "exhaustion residue");
            } finally { Directory.Delete(root); }
        }
        {
            var root = NewRoot();
            try {
                using var transport = new Handler { Manifest = _ => new StringContent(validJson) };
                var observations = new List<string>();
                using var source = Source(transport, null, observations);
                await source.CheckForUpdateAsync();
                using var cancelled = new CancellationTokenSource();
                await RejectAsync(() => source.DownloadAsync(root, "0.7.3", Publisher,
                    p => { if (p.ReceivedBytes > 0) cancelled.Cancel(); }, cancelled.Token), "download cancel ignored");
                Require(transport.Requests.Count == 2 && !Directory.GetFiles(root).Any(), "cancel retried or left residue");
            } finally { Directory.Delete(root); }
        }
        {
            var root = NewRoot();
            FileStream? blocker = null;
            try {
                using var transport = new Handler { Manifest = _ => new StringContent(validJson) };
                var observations = new List<string>();
                using var source = Source(transport, null, observations);
                await source.CheckForUpdateAsync();
                var failedClosed = false;
                try {
                    using var unexpected = await source.DownloadAsync(root, "0.7.3", (file, _, _) => {
                        blocker = new FileStream(file, FileMode.Open, FileAccess.Read, FileShare.Read);
                        throw new InvalidDataException("injected publisher rejection with deletion blocked");
                    });
                } catch (InvalidOperationException error) when (error.Message == "download-cleanup-failed") { failedClosed = true; }
                Require(failedClosed && transport.Requests.Count == 2 && observations.Last() == "download=1 result=download-cleanup-failed",
                    "cleanup failure must stop retries with a fixed reason");
            } finally {
                blocker?.Dispose();
                foreach (var file in Directory.GetFiles(root)) File.Delete(file);
                Directory.Delete(root);
            }
        }
        {
            var root = NewRoot();
            try {
                using var transport = new Handler { Manifest = _ => new StringContent(validJson), Package = _ => new UnknownLengthContent(Bytes) };
                using var source = Source(transport, null, []);
                await source.CheckForUpdateAsync();
                string file;
                using (var artifact = await source.DownloadAsync(root, "0.7.3", Publisher)) file = artifact.Path;
                File.Delete(file);
                transport.Manifest = uri => uri == V1 ? new StringContent(v1Json) : throw new HttpRequestException();
                Require((await source.CheckForUpdateAsync()).Status == "available", "v1 fallback after v2 offer");
                using (var artifact = await source.DownloadAsync(root, "0.7.3", Publisher)) {
                    file = artifact.Path;
                    Require(artifact.SignedManifest is FlutterInstallerUpdateSource.Manifest, "stale v2 retained after v1 fallback");
                }
                File.Delete(file);
            } finally { Directory.Delete(root); }
        }
        using (var transport = new Handler { Manifest = _ => throw new OperationCanceledException() }) {
            using var source = Source(transport, null, []);
            await RejectAsync(() => source.CheckForUpdateAsync(new CancellationToken(true)), "cancel ignored");
            Require(transport.Requests.Count == 0, "cancelled operation retried");
        }
        Console.WriteLine("PASS mirror download transport, partial stream, size, hash, signature/publisher retry and residue cleanup");
        await MetadataAndCache();
        return;

        FlutterInstallerUpdateSource Source(Handler handler, bool? region, List<string> events) =>
            new(V1, Manifests, "windows-x64", "0.7.2.1", keys, handler, () => region, events.Add);
    }

    private static async Task MetadataAndCache()
    {
        const string encoded = "jp|https://jp.example.invalid/v2.json;hk|https://hk.example.invalid/v2.json";
        Require(FlutterUpdateMirror.ParseMetadata(encoded).Select(m => m.Region).SequenceEqual(new[] { "jp", "hk" }), "metadata order");
        foreach (var invalid in new string?[] { null, "", " ", "{}", encoded + ";", "jp|http://example.invalid/x",
            "cn|https://example.invalid/x", "jp|https://localhost/x", "jp|https://[::1]/x", "jp|https://example.invalid/x#f",
            "jp|https://example.invalid/x|extra", "jp|https://example.invalid/x;jp|https://example.invalid/x" })
            Require(FlutterUpdateMirror.ParseMetadata(invalid).Length == 0, "malformed metadata accepted");
        foreach (var metadata in new[] { Array.Empty<string>(), new[] { "malformed" }, new[] { encoded, encoded } }) {
            var assembly = AssemblyBuilder.DefineDynamicAssembly(new AssemblyName("MirrorFixture" + Guid.NewGuid().ToString("N")), AssemblyBuilderAccess.Run);
            foreach (var value in metadata) assembly.SetCustomAttribute(new CustomAttributeBuilder(
                typeof(AssemblyMetadataAttribute).GetConstructor([typeof(string), typeof(string)])!, [FlutterReleaseUpdateSource.MetadataKeyV2, value]));
            using var source = FlutterReleaseUpdateSource.FromRelease(assembly, "0.7.2.1", "windows-x64");
            Require((await source.CheckForUpdateAsync()).Status == "channel-unconfigured", "bad v2 did not become unconfigured v1");
            assembly.SetCustomAttribute(new CustomAttributeBuilder(typeof(AssemblyMetadataAttribute).GetConstructor([typeof(string), typeof(string)])!,
                [FlutterReleaseUpdateSource.MetadataKey, "http://example.invalid/v1"]));
            using var fallback = FlutterReleaseUpdateSource.FromRelease(assembly, "0.7.2.1", "windows-x64");
            Require((await fallback.CheckForUpdateAsync()).Status == "configuration-invalid", "bad v2 did not retain v1 behavior");
        }
        var envName = FlutterReleaseUpdateSource.MetadataKeyV2;
        var old = Environment.GetEnvironmentVariable(envName);
        try {
            Environment.SetEnvironmentVariable(envName, "hk|https://injected.example.invalid/v2.json");
            var assembly = AssemblyBuilder.DefineDynamicAssembly(new AssemblyName("NoMirrorFixture"), AssemblyBuilderAccess.Run);
            using var source = FlutterReleaseUpdateSource.FromRelease(assembly, "0.7.2.1", "windows-x64");
            Require((await source.CheckForUpdateAsync()).Status == "channel-unconfigured", "environment supplied URL");
            Require(FlutterUpdateMirror.ParseMetadata(encoded)[0].Region == "jp", "environment reordered metadata");
        } finally { Environment.SetEnvironmentVariable(envName, old); }
        var root = NewRoot();
        try {
            var path = Path.Combine(root, "scm-region-cache.json");
            var now = DateTimeOffset.UtcNow;
            Require(ScmRegionRouter.ReadCachedClassification(path, now) is null, "missing region cache");
            foreach (var region in new bool?[] { true, false, null }) {
                WriteCache(now, 4, region);
                Require(ScmRegionRouter.ReadCachedClassification(path, now) == region, "existing SCM classification");
            }
            foreach (var time in new[] { now.AddDays(-2), now.AddMinutes(1) }) {
                WriteCache(time, 4, true);
                Require(ScmRegionRouter.ReadCachedClassification(path, now) is null, "stale/future cache used");
            }
            WriteCache(now, 3, true);
            Require(ScmRegionRouter.ReadCachedClassification(path, now) is null, "unsupported cache schema");
            File.WriteAllText(path, "broken", Encoding.UTF8);
            Require(ScmRegionRouter.ReadCachedClassification(path, now) is null, "malformed cache");
            File.Delete(path);
            void WriteCache(DateTimeOffset time, int schema, bool? domestic) => File.WriteAllText(path,
                JsonSerializer.Serialize(new { ApiBaseUri = "https://ignored.example.invalid/", ResourceBaseUri = "https://ignored.example.invalid/",
                    ResolvedAt = time, WebSocketBaseUri = "https://ignored.example.invalid/", SchemaVersion = schema, IsCN = domestic }), Encoding.UTF8);
        } finally { Directory.Delete(root); }
        Console.WriteLine("PASS mirror compiled metadata validation, environment isolation and read-only SCM cache");
    }

    private static string NewRoot() {
        var root = Path.Combine(Path.GetTempPath(), "starbridge-mirror-test-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root); return root;
    }
    private static Task Publisher(string path, string version, CancellationToken token) {
        Require(version == "0.7.3" && File.ReadAllBytes(path).SequenceEqual(Bytes), "publisher input");
        token.ThrowIfCancellationRequested(); return Task.CompletedTask;
    }
    private static void Require(bool value, string message) { if (!value) throw new Exception(message); }
    private static void Reject(Action action, string message) {
        try { action(); } catch (Exception e) when (e is InvalidDataException or JsonException or CryptographicException or ArgumentException) { return; }
        throw new Exception(message);
    }
    private static async Task RejectAsync(Func<Task> action, string message) {
        try { await action(); } catch (Exception e) when (e is InvalidDataException or JsonException or HttpRequestException or OperationCanceledException) { return; }
        throw new Exception(message);
    }
    private sealed class Handler : HttpMessageHandler {
        internal readonly List<Uri> Requests = [];
        internal Func<Uri, HttpContent> Manifest = _ => throw new Exception("unexpected manifest");
        internal Func<Uri, HttpContent> Package = _ => new ByteArrayContent(Bytes);
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) {
            token.ThrowIfCancellationRequested();
            Require(request.Method == HttpMethod.Get && request.Headers.Authorization is null && !request.Headers.Contains("Cookie"), "unexpected request data");
            var uri = request.RequestUri!;
            Requests.Add(uri);
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = uri.AbsolutePath.EndsWith(".json") ? Manifest(uri) : Package(uri) });
        }
    }
    private sealed class UnknownLengthContent(byte[] bytes) : HttpContent {
        protected override bool TryComputeLength(out long length) { length = 0; return false; }
        protected override Task SerializeToStreamAsync(Stream stream, TransportContext? context) => stream.WriteAsync(bytes).AsTask();
    }
    private sealed class FailingStream(byte[] bytes) : MemoryStream(bytes) {
        private bool _read;
        public override ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken token = default) {
            if (_read) throw new IOException("injected partial transfer");
            _read = true; return base.ReadAsync(buffer[..Math.Min(buffer.Length, 5)], token);
        }
    }
}