using System.Net;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StarBridge.HostRuntime.Updates;

internal static class FlutterUpdateHeroMirrorTests
{
    private static readonly Uri V1 = new("https://legacy.example.invalid/v1.json");
    private static readonly FlutterUpdateMirror[] Mirrors = [
        new("jp", "https://jp.example.invalid/v2.json"),
        new("hk", "https://hk.example.invalid/v2.json")];
    private static readonly byte[] Image = [255, 216, 255, 1, 2, 3];
    private static readonly string Hash = Convert.ToHexString(SHA256.HashData(Image)).ToLowerInvariant();

    internal static async Task Verify()
    {
        await HongKongFirst();
        Console.WriteLine("PASS hero mirror: verified Hong Kong manifest wins over regional preference and body hosts");
        foreach (var failure in new[] { "network", "404", "redirect", "length", "hash", "header", "short", "overflow" })
        {
            await Fallback(failure);
            Console.WriteLine("PASS hero mirror: Hong Kong to Japan after " + failure);
        }
        await V1Only();
        Console.WriteLine("PASS hero mirror: v1-only authority and silent failure");
        await V1Fallback();
        Console.WriteLine("PASS hero mirror: verified v1 never requests a v2 hero host");
        await TimedFallback();
        Console.WriteLine("PASS hero mirror: real first-host timeout leaves a slow second host its full budget");
        await Recheck();
        Console.WriteLine("PASS hero mirror: v2 cache retention, changed origin and failed-check invalidation");
        await Cancel();
        Console.WriteLine("PASS hero mirror: cancellation does not start another host");
        Console.WriteLine("Hero mirrors: 14 passed, 0 skipped, 0 failed");
    }

    private static async Task HongKongFirst()
    {
        using var f = new Fixture();
        await f.Check();
        Require(await f.Source.ReadHeroAsync("0.7.4", 0) is not null, "valid hero unavailable");
        Require(f.Transport.Images.Select(u => u.Host).SequenceEqual(new[] { "hk.example.invalid" }), "verified authority lost");
        Require(f.Transport.Images[0].AbsolutePath == "/downloads/update-art/" + Hash + ".jpg", "unsafe image path");
        Require(!f.Transport.SentCredentials, "image request sent credentials");
    }

    private static async Task Fallback(string failure)
    {
        using var f = new Fixture();
        if (failure == "header") f.Bytes = [0, 1, 2, 3, 4, 5];
        f.Transport.Hero = uri => uri.Host.StartsWith("hk", StringComparison.Ordinal) ? failure switch {
            "network" => throw new HttpRequestException(),
            "404" => new(HttpStatusCode.NotFound),
            "redirect" => Redirect(),
            "length" => Ok(new byte[2]),
            "hash" => Ok(new byte[Image.Length]),
            "header" => Ok(f.Bytes),
            "short" => Unknown(f.Bytes[..^1]),
            _ => Unknown(f.Bytes.Concat(new byte[] { 9 }).ToArray())
        } : Ok(f.Bytes);
        await f.Check();
        var chunk = await f.Source.ReadHeroAsync("0.7.4", 0);
        Require((chunk is not null) == (failure != "header"), "integrity fallback result");
        var expected = failure == "header"
            ? new[] { "hk.example.invalid", "jp.example.invalid", "legacy.example.invalid" }
            : new[] { "hk.example.invalid", "jp.example.invalid" };
        Require(f.Transport.Images.Select(u => u.Host).SequenceEqual(expected), "compiled host fallback order");
    }

    private static async Task V1Only()
    {
        using var f = new Fixture(v1Only: true);
        await f.Check();
        Require(await f.Source.ReadHeroAsync("0.7.4", 0) is not null, "v1 hero");
        Require(f.Transport.Images.Single().Host == V1.Host, "v1 used body authority");
        using var unavailable = new Fixture(v1Only: true);
        unavailable.Transport.Hero = _ => new(HttpStatusCode.NotFound);
        await unavailable.Check();
        Require(await unavailable.Source.ReadHeroAsync("0.7.4", 0) is null && unavailable.Transport.Images.Count == 1,
            "v1 failure must stay silent with no extra host");
    }

    private static async Task V1Fallback()
    {
        using var f = new Fixture();
        f.Transport.FailV2 = true;
        f.Transport.Hero = uri => uri.Host == V1.Host ? new(HttpStatusCode.NotFound) : Ok(f.Bytes);
        await f.Check();
        Require(await f.Source.ReadHeroAsync("0.7.4", 0) is null, "v1 failure must retain the bundled hero");
        Require(f.Transport.Images.Select(u => u.Host).SequenceEqual(new[] { V1.Host }), "v1 requested a v2 hero host");
    }

    private static async Task TimedFallback()
    {
        using var f = new Fixture();
        // The same decodable PNG used by the Flutter Bridge/display regression.
        f.Bytes = Convert.FromBase64String(
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==");
        var firstTimedOut = false;
        f.Transport.SlowHero = async (uri, token) => {
            if (uri.Host == "hk.example.invalid")
            {
                try { await Task.Delay(Timeout.InfiniteTimeSpan, token); }
                catch (OperationCanceledException) when (token.IsCancellationRequested) { firstTimedOut = true; throw; }
                throw new Exception("First host completed without its timeout.");
            }
            Require(firstTimedOut, "second host started before real timeout");
            // Real elapsed time and the production cancellation token, no injected failure/clock.
            await Task.Delay(TimeSpan.FromSeconds(7), token);
            return Ok(f.Bytes);
        };
        await f.Check();
        var elapsed = System.Diagnostics.Stopwatch.StartNew();
        var chunk = await f.Source.ReadHeroAsync("0.7.4", 0).WaitAsync(TimeSpan.FromSeconds(24));
        Require(chunk is not null && chunk.MediaType == "image/png" &&
            Convert.FromBase64String(chunk.Chunk).SequenceEqual(f.Bytes), "slow second hero lost");
        Require(firstTimedOut && elapsed.Elapsed >= TimeSpan.FromSeconds(15), "real per-host timeout not exercised");
        Require(f.Transport.Images.Select(u => u.Host).SequenceEqual(new[] { "hk.example.invalid", "jp.example.invalid" }),
            "timed fallback host order");
    }

    private static async Task Recheck()
    {
        using var f = new Fixture();
        await f.Check();
        Require(await f.Source.ReadHeroAsync("0.7.4", 0) is not null, "initial image");
        await f.Check();
        Require(await f.Source.ReadHeroAsync("0.7.4", 0) is not null && f.Transport.Images.Count == 1, "same v2 cache lost");
        f.Transport.PreferHongKong = false;
        await f.Check();
        Require(await f.Source.ReadHeroAsync("0.7.4", 0) is not null && f.Transport.Images.Last().Host == "jp.example.invalid",
            "changed verified origin kept stale cache");
        f.Transport.FailAll = true;
        try { await f.Check(); throw new Exception("failed check accepted"); }
        catch (HttpRequestException) { }
        Require(await f.Source.ReadHeroAsync("0.7.4", 0) is null, "failed v2 check retained cache");
    }

    private static async Task Cancel()
    {
        using var f = new Fixture();
        using var cancellation = new CancellationTokenSource();
        f.Transport.Hero = _ => { cancellation.Cancel(); throw new HttpRequestException(); };
        await f.Check();
        try { await f.Source.ReadHeroAsync("0.7.4", 0, cancellation.Token); throw new Exception("cancellation ignored"); }
        catch (OperationCanceledException) { }
        Require(f.Transport.Images.Count == 1, "cancelled request retried another host");
    }

    private static HttpResponseMessage Ok(byte[] bytes) => new(HttpStatusCode.OK) { Content = new ByteArrayContent(bytes) };
    private static HttpResponseMessage Unknown(byte[] bytes) => new(HttpStatusCode.OK) { Content = new UnknownContent(bytes) };
    private static HttpResponseMessage Redirect()
    {
        var response = new HttpResponseMessage(HttpStatusCode.Redirect);
        response.Headers.Location = new Uri("https://body.example.invalid/redirect.jpg");
        return response;
    }
    private static void Require(bool value, string message) { if (!value) throw new Exception(message); }

    private sealed class Fixture : IDisposable
    {
        private readonly RSA _rsa = RSA.Create(2048);
        internal byte[] Bytes = Image;
        internal readonly Transport Transport;
        internal readonly FlutterInstallerUpdateSource Source;
        internal Fixture(bool v1Only = false)
        {
            Transport = new Transport { Manifest = Manifest };
            Transport.Hero = _ => Ok(Bytes);
            var keys = new Dictionary<string, string> { ["fixture"] = _rsa.ToXmlString(false) };
            Source = v1Only ? new(V1, "windows-x64", "0.7.3", keys, Transport) :
                new(V1, Mirrors, "windows-x64", "0.7.3", keys, Transport, () => false, _ => { });
        }
        private string Sign(string payload) => Convert.ToBase64String(_rsa.SignData(Encoding.UTF8.GetBytes(payload),
            HashAlgorithmName.SHA256, RSASignaturePadding.Pkcs1));
        private string Manifest(bool v1)
        {
            var hash = Convert.ToHexString(SHA256.HashData(Bytes)).ToLowerInvariant();
            var notes = "Hero https://body.example.invalid/evil.jpg\n主图校验 sha256=" + hash + " bytes=" + Bytes.Length;
            const string bodyUrl = "https://body.example.invalid/setup.exe";
            object signed;
            if (v1)
            {
                var m = new FlutterInstallerUpdateSource.Manifest("flutter", "windows-x64", "inno-setup", "0.7.4", bodyUrl,
                    hash, notes, "fixture", "");
                signed = m with { Signature = Sign(FlutterInstallerUpdateSource.BuildPayload(m)) };
            }
            else
            {
                var m = new FlutterInstallerManifestV2("flutter", "windows-x64", "inno-setup", "0.7.4",
                    [new("jp", bodyUrl)], Bytes.Length, hash, notes, "fixture", "");
                signed = m with { Signature = Sign(m.BuildPayload()) };
            }
            return JsonSerializer.Serialize(signed, new JsonSerializerOptions(JsonSerializerDefaults.Web));
        }
        internal async Task Check() => Require((await Source.CheckForUpdateAsync()).Status == "available", "manifest check failed");
        public void Dispose() { Source.Dispose(); _rsa.Dispose(); }
    }

    private sealed class Transport : HttpMessageHandler
    {
        internal Func<bool, string> Manifest = null!;
        internal Func<Uri, HttpResponseMessage> Hero = null!;
        internal Func<Uri, CancellationToken, Task<HttpResponseMessage>>? SlowHero;
        internal bool PreferHongKong = true, FailV2, FailAll, SentCredentials;
        internal readonly List<Uri> Images = [];
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            var uri = request.RequestUri!;
            SentCredentials |= request.Headers.Authorization is not null || request.Headers.Contains("Cookie");
            if (uri.AbsolutePath.Contains("/update-art/", StringComparison.Ordinal))
            {
                Images.Add(uri);
                return SlowHero is null ? Task.FromResult(Hero(uri)) : SlowHero(uri, token);
            }
            if (FailAll || uri.AbsolutePath == "/v2.json" && (FailV2 || PreferHongKong && uri.Host.StartsWith("jp", StringComparison.Ordinal)))
                throw new HttpRequestException();
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(Manifest(uri == V1)) });
        }
    }

    private sealed class UnknownContent(byte[] bytes) : HttpContent
    {
        protected override Task SerializeToStreamAsync(Stream stream, TransportContext? context) => stream.WriteAsync(bytes).AsTask();
        protected override bool TryComputeLength(out long length) { length = 0; return false; }
        protected override Task<Stream> CreateContentReadStreamAsync() => Task.FromResult<Stream>(new MemoryStream(bytes, writable: false));
    }
}
