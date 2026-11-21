using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Lifecycle;
using StarBridge.HostRuntime.Updates;
using StarBridge.HostRuntime.Support;
using StarBridge.NativeBridge;

internal static class FlutterUpdateHeroTests
{
    internal static async Task Verify()
    {
        var previousRoot = HostDataRoot.CurrentRoot;
        var root = Path.Combine(Environment.CurrentDirectory, ".codex-build", "hero-tests", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        HostDataRoot.UsePreparedRoot(root);
        try
        {
            await FlutterUpdateHeroMirrorTests.Verify();
            var cases = new (string, Func<Task>)[] {
                ("chunk bytes, PNG/JPEG, memory cache", ChunkAndCache),
                ("signed notes eligibility without image HTTP", Ineligible),
                ("integrity, size, redirects, file headers", InvalidDownloads),
                ("fixed manifest authority", FixedAddress),
                ("strict Bridge fields, offsets, source capabilities", BridgeGuards),
                ("serialized downloads and explicit retry", SerializedDownloads),
                ("cancelled download holds network lease until physical exit", CancelAndDrain),
                ("cancelled A leaves B free to download", IndependentCancellation),
                ("cancelled semaphore waiter leaves active download alone", CancelledWaiter),
                ("new offer waits for old transfer without caching stale bytes", ChangedOfferDuringDownload),
                ("hero does not block check or prepare", HeroDoesNotBlock),
                ("prepare does not block hero", PrepareDoesNotBlock),
                ("changed, withdrawn and failed checks invalidate cache", Invalidation),
                ("generation and offline admission", SessionAndNetwork),
                ("hero follows automatic device or manual terms admission", TermsAdmission)
            };
            var passed = 0;
            foreach (var (name, run) in cases)
            {
                await run().WaitAsync(TimeSpan.FromSeconds(15));
                passed++;
                Console.WriteLine("PASS update hero: " + name);
            }
            Console.WriteLine($"Update hero: {passed} passed, 0 failed");
        }
        finally
        {
            HostDataRoot.UsePreparedRoot(previousRoot);
            Directory.Delete(root, recursive: true);
        }
    }

    private static byte[] Picture(int length = 600000, bool png = false)
    {
        var bytes = new byte[length];
        new Random(42).NextBytes(bytes);
        (png ? new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 } : new byte[] { 255, 216, 255 }).CopyTo(bytes, 0);
        return bytes;
    }
    private static string Hash(byte[] bytes) => Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
    private static string Line(byte[] bytes) => $"主图校验 sha256={Hash(bytes)} bytes={bytes.Length}";
    private static void Require(bool value, string message) { if (!value) throw new Exception(message); }
    private static TaskCompletionSource Gate() => new(TaskCreationOptions.RunContinuationsAsynchronously);

    private static async Task ChunkAndCache()
    {
        foreach (var png in new[] { false, true })
        {
            using var f = new Fixture(Picture(png: png));
            await f.Check();
            using var output = new MemoryStream();
            for (var offset = 0; ;)
            {
                var response = await f.Read(offset: offset);
                Require(response.Status == "ok", "Valid hero unavailable.");
                var p = response.Payload;
                Require(p.EnumerateObject().Count() == 9 && p.GetProperty("schemaVersion").GetInt32() == 1 &&
                    p.GetProperty("version").GetString() == f.Version && p.GetProperty("offset").GetInt32() == offset &&
                    p.GetProperty("mediaType").GetString() == (png ? "image/png" : "image/jpeg") &&
                    p.GetProperty("length").GetInt32() == f.Bytes.Length && p.GetProperty("sha256").GetString() == Hash(f.Bytes), "Hero wire contract changed.");
                var chunk = Convert.FromBase64String(p.GetProperty("chunk").GetString()!);
                Require(chunk.Length <= 256 * 1024 && JsonSerializer.SerializeToUtf8Bytes(response).Length < 1024 * 1024, "Bridge frame too large.");
                output.Write(chunk);
                offset = p.GetProperty("nextOffset").GetInt32();
                if (p.GetProperty("done").GetBoolean()) break;
            }
            Require(output.ToArray().SequenceEqual(f.Bytes), "Chunk reassembly changed image.");
            Require((await f.Read(offset: f.Bytes.Length)).Payload.GetProperty("chunk").GetString() == "", "EOF offset invalid.");
            await f.Check();
            Require((await f.Read()).Status == "ok" && f.Handler.HeroRequests == 1, "Same signed version downloaded again.");
        }
    }

    private static async Task Ineligible()
    {
        using var f = new Fixture(Picture(80));
        foreach (var (version, notes) in new[] {
            ("0.7.4", "no hero"), ("0.7.4", Line(f.Bytes) + "\n" + Line(f.Bytes)),
            ("0.7.4", Line(f.Bytes) + "\nMore release notes"),
            ("0.7.4", Line(f.Bytes).Replace("sha256=", "SHA256=")),
            ("0.7.4", Line(f.Bytes) + " "), ("0.7.4", " " + Line(f.Bytes)),
            ("0.7.4", Line(f.Bytes) + "\r"),
            ("0.7.4", $"主图校验 sha256={Hash(f.Bytes)} bytes=0"),
            ("0.7.4", $"主图校验 sha256={Hash(f.Bytes)} bytes=080"),
            ("0.7.4", $"主图校验 sha256={Hash(f.Bytes)} bytes=3145729"),
            ("0.7.4.1", Line(f.Bytes)) })
        {
            f.Version = version; f.Notes = notes;
            await f.Check();
            Unavailable(await f.Read());
            Require(f.Handler.HeroRequests == 0, "Ineligible notes caused image HTTP.");
        }
        f.Version = "0.7.4"; f.Notes = "Release notes\r\n" + Line(f.Bytes) + "\r\n\r\n";
        await f.Check();
        Require((await f.Read()).Status == "ok", "CRLF or trailing empty lines rejected.");
    }

    private static async Task InvalidDownloads()
    {
        var bytes = Picture(80);
        foreach (var bad in new[] { "hash", "header-length", "short", "redirect", "header", "overflow", "transport" })
        {
            using var f = new Fixture(bytes);
            if (bad == "header") f.Bytes = new byte[80]; // Correct signed hash, invalid magic bytes.
            if (bad == "hash") f.Notes = $"主图校验 sha256={new string('a', 64)} bytes=80";
            f.Handler.Hero = _ =>
            {
                if (bad == "transport") throw new HttpRequestException("untrusted detail");
                var payload = bad == "short" ? bytes[..^1] : bad == "overflow" ? bytes.Concat(new byte[] { 7 }).ToArray() : f.Bytes;
                var content = new UnknownLengthContent(payload);
                if (bad == "header-length") content.Headers.ContentLength = 79;
                return Task.FromResult(new HttpResponseMessage(bad == "redirect" ? HttpStatusCode.Redirect : HttpStatusCode.OK) { Content = content });
            };
            await f.Check();
            Unavailable(await f.Read());
            Require(f.Handler.HeroRequests == 1, "Host retried failed hero automatically.");
            Require((await f.Bridge.DispatchAsync(f.Request(FlutterUpdateBridgeDispatcher.RequestName, new { schemaVersion = 1 }))).Response.Status == "ok", "Hero failure broke check.");
            var prepared = await f.Bridge.DispatchAsync(f.Request(FlutterUpdateBridgeDispatcher.PrepareRequestName, new { schemaVersion = 1, version = f.Version }));
            Require(prepared.Response.Status == "ok", "Hero failure broke prepare.");
        }
    }

    private static async Task FixedAddress()
    {
        using var f = new Fixture(Picture(80));
        f.Notes = "https://other.invalid/hero.jpg\r\n" + Line(f.Bytes);
        f.DownloadUrl = "https://installer.invalid/installer.exe";
        await f.Check();
        Require((await f.Read()).Status == "ok", "Hero with unrelated text failed.");
        Require(f.Handler.HeroUri == new Uri($"https://updates.example.invalid:8443/downloads/update-art/{Hash(f.Bytes)}.jpg"), "Address came from Notes or installer URL.");
        Require(!f.Handler.SentCredentials, "Hero sent account headers.");
    }

    private static async Task BridgeGuards()
    {
        using var f = new Fixture(Picture(80));
        await f.Check();
        foreach (var payload in new object[] {
            new { schemaVersion = 1, version = f.Version }, new { version = f.Version, offset = 0 },
            new { schemaVersion = 1, offset = 0 }, new { schemaVersion = 1, version = f.Version, offset = 0, extra = true },
            new { schemaVersion = 2, version = f.Version, offset = 0 }, new { schemaVersion = 1, version = 7, offset = 0 },
            new { schemaVersion = 1, version = f.Version, offset = -1 }, new { schemaVersion = 1, version = f.Version, offset = 1 },
            new { schemaVersion = 1, version = f.Version, offset = 81 }, new { schemaVersion = 1, version = f.Version, offset = 1.5 },
            new { schemaVersion = 1, version = f.Version, offset = "0" }, new { schemaVersion = 1, version = f.Version, offset = long.MaxValue },
            new { schemaVersion = 1, version = "0.7.3", offset = 0 } })
            Require((await f.Bridge.DispatchAsync(f.Request(FlutterUpdateBridgeDispatcher.HeroReadRequestName, payload))).Response.Status == "error", "Malformed hero request accepted.");
        var duplicate = JsonSerializer.Deserialize<JsonElement>("{\"schemaVersion\":1,\"version\":\"0.7.4\",\"version\":\"0.7.4\"}");
        Unavailable((await f.Bridge.DispatchAsync(f.Request(FlutterUpdateBridgeDispatcher.HeroReadRequestName, duplicate))).Response);
        Require(f.Handler.HeroRequests == 0, "Invalid Bridge request caused HTTP.");
        Require(FlutterUpdateBridgeDispatcher.SourceCapabilities(f.Source).SequenceEqual(new[] { FlutterUpdateBridgeDispatcher.HeroReadRequestName }) &&
            FlutterUpdateBridgeDispatcher.SourceCapabilities(null).Count == 0 && FlutterUpdateBridgeDispatcher.SourceCapabilities(new OtherSource()).Count == 0, "Installer capability declaration wrong.");
        using var empty = new FlutterUpdateBridgeDispatcher(null, () => "0.7.0", () => 1);
        using var other = new FlutterUpdateBridgeDispatcher(new OtherSource(), () => "0.7.0", () => 1);
        Unavailable((await empty.DispatchAsync(f.HeroRequest())).Response);
        Unavailable((await other.DispatchAsync(f.HeroRequest())).Response);
        using var composite = new CompositeBridgeDispatcher(new RejectRoute(), new RejectRoute(), new RejectRoute(), updates: f.Bridge);
        Require((await composite.DispatchAsync(f.HeroRequest())).Response.Status == "ok", "Composite hero route missing.");
    }

    private static async Task SerializedDownloads()
    {
        foreach (var fail in new[] { false, true })
        {
            using var f = new Fixture(Picture(80));
            await f.Check();
            var entered = Gate(); var release = Gate();
            f.Handler.Hero = async token => { entered.TrySetResult(); await release.Task.WaitAsync(token); return new(fail ? HttpStatusCode.BadGateway : HttpStatusCode.OK) { Content = new ByteArrayContent(f.Bytes) }; };
            var first = f.Read(); await entered.Task;
            var second = f.Read();
            Require(f.Handler.HeroRequests == 1, "Concurrent hero requests duplicated HTTP.");
            release.SetResult();
            Require((await first).Status == (fail ? "error" : "ok") && (await second).Status == (fail ? "error" : "ok"), "Serialized request lost result.");
            Require(f.Handler.HeroRequests == (fail ? 2 : 1), "Waiting request did not download after a failed predecessor.");
            f.Handler.Hero = _ => Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent(f.Bytes) });
            Require((await f.Read()).Status == "ok" && f.Handler.HeroRequests == (fail ? 3 : 1), "Explicit retry/cache broken.");
        }
    }

    private static async Task CancelAndDrain()
    {
        await CancelAndDrainTransfer(body: false);
        await CancelAndDrainTransfer(body: true);
    }

    private static async Task CancelAndDrainTransfer(bool body)
    {
        var online = true;
        var network = new DeviceNetworkAdmission(() => online);
        using var f = new Fixture(Picture(80), network);
        await f.Check();
        var entered = Gate(); var cancelled = Gate(); var release = Gate(); var exited = Gate();
        var stream = new HeldHeroStream(f.Bytes, entered, cancelled, release, exited);
        if (body)
            f.Handler.Hero = _ => Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StreamContent(stream) });
        else
            f.Handler.Hero = async token => {
                using var registration = token.Register(() => cancelled.TrySetResult());
                entered.TrySetResult();
                try { await release.Task; token.ThrowIfCancellationRequested(); throw new Exception("Expected cancellation."); }
                finally { exited.TrySetResult(); }
            };
        var pending = f.Read();
        await entered.Task;
        online = false;
        var retired = network.RetireAsync();
        try
        {
            await cancelled.Task;
            await Task.Delay(50); // Allow an incorrectly detached observer to complete.
            Require(!retired.IsCompleted && !pending.IsCompleted && !exited.Task.IsCompleted,
                "Offline drain released network lease before physical transfer exit.");
        }
        finally { release.TrySetResult(); await pending; await retired; }
        Require((await pending).Status == "cancelled", "Offline retirement did not cancel the request.");
        Require(exited.Task.IsCompletedSuccessfully, "Drain completed before transport exited.");
        if (body) Require(stream.Disposed, "Drain completed before response stream disposal.");
        else stream.Dispose();
    }

    private static async Task IndependentCancellation()
    {
        using var f = new Fixture(Picture(80));
        await f.Check();
        using var cancellation = new CancellationTokenSource();
        var entered = Gate(); var cancelled = Gate(); var release = Gate();
        f.Handler.Hero = async token => {
            if (f.Handler.HeroRequests == 1)
            {
                using var registration = token.Register(() => cancelled.TrySetResult());
                entered.TrySetResult();
                await release.Task;
                token.ThrowIfCancellationRequested();
            }
            return new(HttpStatusCode.OK) { Content = new ByteArrayContent(f.Bytes) };
        };
        var first = f.Read(cancellation: cancellation.Token); await entered.Task;
        var second = f.Read();
        cancellation.Cancel();
        try
        {
            await cancelled.Task;
            await Task.Delay(50);
            Require(!first.IsCompleted && !second.IsCompleted && f.Handler.HeroRequests == 1,
                "Cancellation detached the first transfer or started an overlapping download.");
        }
        finally { release.TrySetResult(); await first; await second; }
        Require((await first).Status == "cancelled", "A did not return its own cancellation.");
        Require((await second).Status == "ok" && f.Handler.HeroRequests == 2, "A cancellation cancelled B's download.");
        Require((await f.Read()).Status == "ok" && f.Handler.HeroRequests == 2, "B did not populate cache.");
    }

    private static async Task CancelledWaiter()
    {
        using var f = new Fixture(Picture(80));
        await f.Check();
        var entered = Gate(); var release = Gate();
        f.Handler.Hero = async token => { entered.TrySetResult(); await release.Task.WaitAsync(token); return new(HttpStatusCode.OK) { Content = new ByteArrayContent(f.Bytes) }; };
        var first = f.Read(); await entered.Task;
        using var cancellation = new CancellationTokenSource();
        var second = f.Read(cancellation: cancellation.Token);
        cancellation.Cancel();
        try
        {
            Require((await second.WaitAsync(TimeSpan.FromSeconds(2))).Status == "cancelled", "Waiting request ignored its cancellation.");
            Require(!first.IsCompleted && f.Handler.HeroRequests == 1, "Waiting cancellation affected active transfer.");
        }
        finally { release.TrySetResult(); await first; }
        Require((await first).Status == "ok", "Waiting cancellation broke active request.");
    }

    private static async Task ChangedOfferDuringDownload()
    {
        using var f = new Fixture(Picture(80));
        await f.Check();
        var oldBytes = f.Bytes;
        var entered = Gate(); var release = Gate();
        f.Handler.Hero = async token => {
            var bytes = f.Bytes;
            if (f.Handler.HeroRequests == 1) { entered.TrySetResult(); await release.Task.WaitAsync(token); }
            return new(HttpStatusCode.OK) { Content = new ByteArrayContent(bytes) };
        };
        var first = f.Read(); await entered.Task;
        var oldWaiter = f.Read();
        f.Version = "0.7.5"; f.Bytes = Picture(96); await f.Check();
        var second = f.Read();
        try
        {
            Require(!second.IsCompleted && f.Handler.HeroRequests == 1, "New offer failed immediately or overlapped old download.");
        }
        finally { release.TrySetResult(); await first; await oldWaiter; await second; }
        Unavailable(await first);
        Unavailable(await oldWaiter);
        var image = await second;
        Require(image.Status == "ok" && Convert.FromBase64String(image.Payload.GetProperty("chunk").GetString()!).SequenceEqual(f.Bytes) &&
            f.Handler.HeroUri!.AbsolutePath.EndsWith(Hash(f.Bytes) + ".jpg", StringComparison.Ordinal), "New offer did not download its own image.");
        // Re-offering V1 must fetch again, rather than reuse a completed stale transfer.
        f.Version = "0.7.4"; f.Bytes = oldBytes; await f.Check();
        Require((await f.Read()).Status == "ok" && f.Handler.HeroRequests == 3, "Stale V1 transfer wrote cache.");
    }

    private static async Task HeroDoesNotBlock()
    {
        using var f = new Fixture(Picture(80));
        await f.Check();
        var entered = Gate(); var release = Gate();
        f.Handler.Hero = async token => { entered.SetResult(); await release.Task.WaitAsync(token); return new(HttpStatusCode.OK) { Content = new ByteArrayContent(f.Bytes) }; };
        var hero = f.Read(); await entered.Task;
        await f.Check();
        var prepare = await f.Bridge.DispatchAsync(f.Request(FlutterUpdateBridgeDispatcher.PrepareRequestName, new { schemaVersion = 1, version = f.Version }));
        Require(prepare.Response.Status == "ok" && !hero.IsCompleted, "Hero held update operation semaphore.");
        release.SetResult(); Require((await hero).Status == "ok", "Same-offer check discarded in-flight hero.");
    }

    private static async Task PrepareDoesNotBlock()
    {
        using var f = new Fixture(Picture(80));
        await f.Check();
        var entered = Gate(); var release = Gate();
        f.Handler.Installer = async token => { entered.SetResult(); await release.Task.WaitAsync(token); return new(HttpStatusCode.OK) { Content = new ByteArrayContent(Fixture.InstallerBytes) }; };
        var prepare = f.Bridge.DispatchAsync(f.Request(FlutterUpdateBridgeDispatcher.PrepareRequestName, new { schemaVersion = 1, version = f.Version })).AsTask();
        await entered.Task;
        Require((await f.Read()).Status == "ok" && !prepare.IsCompleted, "Update operation held hero download.");
        release.SetResult(); Require((await prepare).Response.Status == "ok", "Prepare failed after concurrent hero.");
    }

    private static async Task Invalidation()
    {
        using var f = new Fixture(Picture(80));
        await f.Check(); Require((await f.Read()).Status == "ok", "Initial cache failed.");
        f.Version = "0.7.5"; await f.Check();
        Unavailable(await f.Read(version: "0.7.4"));
        Require((await f.Read()).Status == "ok" && f.Handler.HeroRequests == 2, "Changed offer retained old cache.");
        f.Version = "0.7.0"; await f.Source.CheckForUpdateAsync();
        Unavailable(await f.Read(version: "0.7.5"));
        f.Version = "0.7.5"; await f.Check();
        Require((await f.Read()).Status == "ok" && f.Handler.HeroRequests == 3, "Withdrawn cache resurrected.");
        f.Handler.ManifestOverride = "{}";
        var check = (await f.Bridge.DispatchAsync(f.Request(FlutterUpdateBridgeDispatcher.RequestName, new { schemaVersion = 1 }))).Response;
        Require(check.Payload.GetProperty("state").GetString() == "verification-failed", "Bad manifest accepted.");
        Unavailable(await f.Read()); f.Handler.ManifestOverride = null;
        await f.Check();
        var entered = Gate(); var release = Gate();
        f.Handler.Hero = async token => { entered.TrySetResult(); await release.Task.WaitAsync(token); return new(HttpStatusCode.OK) { Content = new ByteArrayContent(f.Bytes) }; };
        var pending = f.Read(); await entered.Task;
        f.Version = "0.7.6"; await f.Check();
        release.SetResult(); Unavailable(await pending);
        Require((await f.Read()).Status == "ok" && f.Handler.HeroRequests == 5, "Stale flight repopulated cache.");
    }

    private static async Task SessionAndNetwork()
    {
        var online = true;
        var network = new DeviceNetworkAdmission(() => online);
        using var f = new Fixture(Picture(80), network);
        await f.Check();
        Unavailable((await f.Bridge.DispatchAsync(f.HeroRequest() with { SessionGeneration = 0 })).Response);
        Require((await f.Bridge.DispatchAsync(f.HeroRequest() with { AccountContext = new("fixture", "fixture", "fixture") })).Response.Status == "error", "Account context accepted.");
        online = false; Unavailable(await f.Read());
        Require(f.Handler.HeroRequests == 0, "Offline hero contacted network.");
        online = true;
        var entered = Gate(); var release = Gate();
        f.Handler.Hero = async token => { entered.TrySetResult(); await release.Task.WaitAsync(token); return new(HttpStatusCode.OK) { Content = new ByteArrayContent(f.Bytes) }; };
        var pending = f.Read(); await entered.Task; f.Generation++;
        release.SetResult(); Unavailable(await pending);
        online = false; Unavailable(await f.Read());
        online = true; Require((await f.Read()).Status == "ok", "Current session cannot read cache.");
        // Epoch cancellation must fence even an otherwise cached read.
        await network.RetireAsync(); Unavailable(await f.Read());
    }

    private static async Task TermsAdmission()
    {
        var root = Path.Combine(HostDataRoot.CurrentRoot, "hero-terms");
        Directory.CreateDirectory(root);
        var terms = new TestBuildNoticeStore(root);
        var online = false;
        var network = new DeviceNetworkAdmission(() => online && terms.IsAcknowledged());
        using var f = new Fixture(Picture(80), network, terms);
        // Establish a verified offer using the existing in-memory transport.
        await f.Check();
        BridgeEnvelope Hero(bool automatic) => f.Request(FlutterUpdateBridgeDispatcher.HeroReadRequestName,
            new { schemaVersion = 1, version = f.Version, offset = 0, automatic });
        async Task Denied(bool automatic)
        {
            var before = f.Handler.HeroRequests;
            Unavailable((await f.Bridge.DispatchAsync(Hero(automatic))).Response);
            Require(f.Handler.HeroRequests == before, "Denied hero contacted transport.");
        }
        foreach (var mode in new[] { false, true })
        {
            online = mode;
            await Denied(false);
            await Denied(true);
        }
        online = false;
        terms.Acknowledge(TestBuildNoticeStore.TermsVersion, "Synthetic terms fixture", () => true);
        await Denied(true);
        foreach (var malformed in new object[] {
            new { schemaVersion = 1, version = f.Version, offset = 0, automatic = "false" },
            JsonSerializer.SerializeToElement(new { schemaVersion = 1, version = f.Version, offset = 0, automatic = (bool?)null }),
            new { schemaVersion = 1, version = f.Version, offset = 0, automatic = false, extra = true } })
        {
            var response = (await f.Bridge.DispatchAsync(f.Request(FlutterUpdateBridgeDispatcher.HeroReadRequestName, malformed))).Response;
            Require(response.Status == "error" && f.Handler.HeroRequests == 0, "Malformed provenance contacted transport.");
        }
        Require((await f.Bridge.DispatchAsync(Hero(false))).Response.Status == "ok" && f.Handler.HeroRequests == 1,
            "Manual local hero must use current terms.");
        await Denied(true); // Cached bytes must still respect automatic admission.
        Require((await f.Read()).Status == "ok", "Omitted automatic remains a manual read.");
        online = true;
        Require((await f.Bridge.DispatchAsync(Hero(true))).Response.Status == "ok", "Online automatic hero unavailable.");
        File.Delete(Path.Combine(root, TestBuildNoticeStore.FileName));
        await Denied(false);
        await Denied(true); // Revoked terms also fence cached bytes.
    }
    private static void Unavailable(BridgeEnvelope response) => Require(response.Status == "error" &&
        JsonSerializer.Serialize(response).Contains("applicationUpdates.unavailable", StringComparison.Ordinal) &&
        !JsonSerializer.Serialize(response).Contains("https://", StringComparison.Ordinal), "Failure leaked detail or wrong error.");

    private sealed class Fixture : IDisposable
    {
        internal static readonly byte[] InstallerBytes = Encoding.ASCII.GetBytes("inert installer fixture");
        private readonly RSA _rsa = RSA.Create(2048);
        internal byte[] Bytes;
        internal string Version = "0.7.4";
        internal string? Notes;
        internal string DownloadUrl = "https://updates.example.invalid:8443/installer.exe";
        internal long Generation = 1;
        internal readonly Handler Handler;
        internal readonly FlutterInstallerUpdateSource Source;
        internal readonly FlutterUpdateBridgeDispatcher Bridge;
        private readonly FlutterUpdateInstallation _installation;
        private readonly List<string> _files = [];
        internal Fixture(byte[] bytes, DeviceNetworkAdmission? network = null, TestBuildNoticeStore? terms = null)
        {
            Bytes = bytes;
            Handler = new Handler { Manifest = ManifestJson };
            Handler.Hero = _ => Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent(Bytes) });
            Source = new(new Uri("https://updates.example.invalid:8443/channel/manifest.json?channel=stable"), "windows-x64", "0.7.0",
                new Dictionary<string, string> { ["fixture"] = _rsa.ToXmlString(false) }, Handler);
            _installation = new FlutterUpdateInstallation(async (version, token) => {
                using var download = await Source.DownloadAsync(HostDataRoot.CurrentRoot, version, (_, _, _) => Task.CompletedTask, cancellation: token);
                _files.Add(download.Path); return download.Path;
            }, (_, _) => throw new Exception("Hero test must never install."));
            Bridge = new(Source, () => "0.7.0", () => Generation, installation: _installation, network: network, terms: terms);
        }
        private string ManifestJson()
        {
            var manifest = new FlutterInstallerUpdateSource.Manifest("flutter", "windows-x64", "inno-setup", Version, DownloadUrl,
                Hash(InstallerBytes), Notes ?? Line(Bytes), "fixture", "");
            manifest = manifest with { Signature = Convert.ToBase64String(_rsa.SignData(Encoding.UTF8.GetBytes(FlutterInstallerUpdateSource.BuildPayload(manifest)), HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1)) };
            return JsonSerializer.Serialize(manifest, new JsonSerializerOptions(JsonSerializerDefaults.Web));
        }
        internal async Task Check() => Require((await Source.CheckForUpdateAsync()).Status == "available", "Fixture check failed.");
        internal BridgeEnvelope Request(string name, object payload) => BridgeEnvelope.Request(name, Guid.NewGuid().ToString("N"), Generation, payload);
        internal BridgeEnvelope HeroRequest(int offset = 0, string? version = null) => Request(FlutterUpdateBridgeDispatcher.HeroReadRequestName,
            new { schemaVersion = 1, version = version ?? Version, offset });
        internal async Task<BridgeEnvelope> Read(int offset = 0, string? version = null, CancellationToken cancellation = default) =>
            (await Bridge.DispatchAsync(HeroRequest(offset, version), cancellation)).Response;
        public void Dispose() { Bridge.Dispose(); _rsa.Dispose(); foreach (var file in _files) File.Delete(file); }
    }

    private sealed class Handler : HttpMessageHandler
    {
        internal Func<string> Manifest = null!;
        internal string? ManifestOverride;
        internal Func<CancellationToken, Task<HttpResponseMessage>> Hero = null!;
        internal Func<CancellationToken, Task<HttpResponseMessage>> Installer = _ => Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new ByteArrayContent(Fixture.InstallerBytes) });
        internal int HeroRequests;
        internal Uri? HeroUri;
        internal bool SentCredentials;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellation)
        {
            SentCredentials |= request.Headers.Authorization is not null || request.Headers.Contains("Cookie");
            if (request.RequestUri!.AbsolutePath == "/channel/manifest.json")
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(ManifestOverride ?? Manifest(), Encoding.UTF8, "application/json") });
            if (request.RequestUri.AbsolutePath == "/installer.exe") return Installer(cancellation);
            Interlocked.Increment(ref HeroRequests); HeroUri = request.RequestUri;
            return Hero(cancellation);
        }
    }
    private sealed class UnknownLengthContent(byte[] bytes) : HttpContent
    {
        protected override Task SerializeToStreamAsync(Stream stream, TransportContext? context) => stream.WriteAsync(bytes).AsTask();
        protected override bool TryComputeLength(out long length) { length = 0; return false; }
        protected override Task<Stream> CreateContentReadStreamAsync() => Task.FromResult<Stream>(new MemoryStream(bytes, writable: false));
    }
    private sealed class HeldHeroStream(byte[] bytes, TaskCompletionSource entered, TaskCompletionSource cancelled,
        TaskCompletionSource release, TaskCompletionSource exited) : MemoryStream(bytes, writable: false)
    {
        internal bool Disposed;
        public override async ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken cancellationToken = default)
        {
            using var registration = cancellationToken.Register(() => cancelled.TrySetResult());
            entered.TrySetResult();
            try
            {
                await release.Task; // A transport that needs time to physically finish cancellation.
                cancellationToken.ThrowIfCancellationRequested();
                return await base.ReadAsync(buffer, cancellationToken);
            }
            finally { exited.TrySetResult(); }
        }
        protected override void Dispose(bool disposing) { Disposed = true; base.Dispose(disposing); }
    }
    private sealed class OtherSource : IApplicationUpdateSource
    {
        public Task<ApplicationUpdateCheck> CheckForUpdateAsync(CancellationToken cancellation = default) => Task.FromResult(new ApplicationUpdateCheck("channel-unconfigured"));
        public void Dispose() { }
    }
    private sealed class RejectRoute : IBridgeRequestDispatcher
    {
        public event Action<BridgeEnvelope>? EventReady { add { } remove { } }
        public ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken cancellationToken = default) => throw new Exception("Wrong route.");
        public void Dispose() { }
    }
}
