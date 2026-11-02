using System.Security.Cryptography;
using System.Text.Json;
using System.Reflection;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Images;
using StarBridge.NativeBridge;

internal static class RemoteImageCacheBridgeTests
{
    internal static async Task Run()
    {
        await Roundtrip();
        await PublicationAndScope();
        await BoundsAndExpiry();
        await Cleanup();
        await Retirement();
    }
    private static async Task Roundtrip()
    {
        await using var f = new Fixture();
        var first = f.Create();
        var token = await f.Open(first, "full-body");
        var bytes = new byte[4 * 1024 * 1024];
        Random.Shared.NextBytes(bytes);
        await f.Upload(first, token, bytes);
        Require((await f.Call(first, "commit", new { cacheToken = token })).Payload.GetProperty("status").GetString() == "stored", "full 4 MiB commit succeeds");
        var reopened = f.Create();
        var response = await f.Call(reopened, "open", new { key = Key("full-body"), kind = "ship" });
        token = response.Payload.GetProperty("cacheToken").GetString()!;
        Require(response.Payload.GetProperty("status").GetString() == "ready" && response.Payload.GetProperty("length").GetInt32() == bytes.Length,
            "new bridge reads persisted full body metadata");
        using var reconstructed = new MemoryStream();
        for (var offset = 0; offset < bytes.Length;)
        {
            var chunk = (await f.Call(reopened, "read", new { cacheToken = token, offset })).Payload;
            var data = Convert.FromBase64String(chunk.GetProperty("chunk").GetString()!);
            reconstructed.Write(data);
            offset = chunk.GetProperty("nextOffset").GetInt32();
            Require(chunk.GetProperty("done").GetBoolean() == (offset == bytes.Length), "chunk completion has exact offset");
        }
        Require(reconstructed.ToArray().SequenceEqual(bytes) && f.MaximumFrameBytes <= BridgeProtocol.MaximumFrameBytes,
            "actual BridgeWireCodec roundtrips full 4 MiB through frames below 1 MiB");
        await f.Call(reopened, "close", new { cacheToken = token });
        Console.WriteLine("PASS chunked full-body persistence and actual wire codec");
    }
    private static async Task PublicationAndScope()
    {
        await using var f = new Fixture();
        var a = f.Create(); var b = f.Create();
        var late = await f.Open(a, "rejected");
        var rejecting = await f.Open(b, "rejected");
        await f.Call(b, "reject", new { cacheToken = rejecting });
        await f.Upload(a, late, [1, 2, 3]);
        Require((await f.Call(a, "commit", new { cacheToken = late })).Payload.GetProperty("status").GetString() == "superseded",
            "late chunked commit cannot cross a rejection");
        var changed = await f.Open(a, "changed-owner");
        f.Generation++;
        Require((await f.Call(a, "beginWrite", f.Metadata(changed, [1]))).Status != BridgeResponseStatuses.Ok,
            "new generation retires an old token");
        var offlineKey = await f.Open(b, "offline-control");
        await f.Upload(b, offlineKey, [4, 5, 6]);
        await f.Call(b, "commit", new { cacheToken = offlineKey });
        f.Store.Pin(f.Owner, 123, () => true);
        f.OfflineRevision = 123;
        var offline = await f.Call(b, "open", new { key = Key("offline-control"), kind = "ship" });
        var offlineToken = offline.Payload.GetProperty("cacheToken").GetString()!;
        Require(offline.Payload.GetProperty("status").GetString() == "ready" &&
            (await f.Call(b, "beginWrite", f.Metadata(offlineToken, [7]))).Status != BridgeResponseStatuses.Ok,
            "exact offline scope displays persisted bytes and refuses upload");
        f.Alive = false;
        Require((await f.Call(b, "read", new { cacheToken = offlineToken, offset = 0 })).Status != BridgeResponseStatuses.Ok,
            "retired original owner cannot read an acquired body");
        Console.WriteLine("PASS chunk publication, generation and read-only offline scope");
    }
    private static async Task BoundsAndExpiry()
    {
        await using var f = new Fixture();
        var bridge = f.Create();
        var token = await f.Open(bridge, "offset");
        await f.Call(bridge, "beginWrite", f.Metadata(token, [1, 2, 3]));
        Require((await f.Call(bridge, "append", new { cacheToken = token, offset = 1, chunk = "AQID" })).Status != BridgeResponseStatuses.Ok,
            "upload rejects holes and out-of-order bytes");
        Require((await f.Call(bridge, "commit", new { cacheToken = token })).Status != BridgeResponseStatuses.Ok,
            "incomplete upload cannot publish");
        for (var i = 0; i < 64; i++) await f.Open(bridge, "bounded-" + i);
        Require((await f.Call(bridge, "open", new { key = Key("overflow"), kind = "ship" })).Error?.Code == "imageCache.busy",
            "logical receipts are bounded");
        f.Clock.Advance(TimeSpan.FromSeconds(31));
        Require((await f.Call(bridge, "open", new { key = Key("after-expiry"), kind = "ship" })).Status == BridgeResponseStatuses.Ok,
            "monotonic expiry recovers receipt capacity");
        Console.WriteLine("PASS offsets, incomplete bodies, bounded receipts and expiry");
    }
    private static async Task Retirement()
    {
        await using var f = new Fixture();
        using var entered = new ManualResetEventSlim();
        using var release = new ManualResetEventSlim();
        var bridge = new RemoteImageCacheBridge(f.Store, () => new(f.Owner, null, 7, () =>
        {
            entered.Set();
            if (!release.Wait(5000)) throw new TimeoutException("Synthetic callback was not released.");
            return true;
        }));
        var pending = bridge.DispatchAsync(BridgeEnvelope.Request("imageCache.open", "synthetic-drain", 7,
            new { schemaVersion = 1, key = Key("drain"), kind = "ship" })).AsTask();
        Require(entered.Wait(3000), "actual bridge work reaches the held owner callback");
        try
        {
            var retirement = bridge.RetireAsync();
            Require(!retirement.IsCompleted, "retirement waits for admitted physical work");
            release.Set();
            var response = await pending;
            await retirement;
            Require(response.Response.Status != BridgeResponseStatuses.Ok, "retired work cannot publish a cache token");
        }
        finally { release.Set(); await bridge.DisposeAsync(); }
        Console.WriteLine("PASS bridge retirement joins admitted work");
    }
    private static async Task Cleanup()
    {
        await using var f = new Fixture();
        var bridge = f.Create();
        var token = await f.Open(bridge, "maintenance");
        await f.Upload(bridge, token, [1, 2, 3]);
        await f.Call(bridge, "commit", new { cacheToken = token });
        token = await f.Open(bridge, "maintenance");
        var lateWriter = await f.Open(bridge, "late-maintenance");
        Require(StarBridge.HostRuntime.Support.ImageCacheMaintenance.Clear(f.Root) == 1,
            "original maintenance entry removes persisted regenerable body");
        Require((await f.Call(bridge, "read", new { cacheToken = token, offset = 0 })).Status != BridgeResponseStatuses.Ok,
            "already acquired body cannot escape after cleanup");
        Require((await f.Call(bridge, "beginWrite", f.Metadata(lateWriter, [7]))).Status != BridgeResponseStatuses.Ok,
            "pre-cleanup token cannot start a later upload");
        Console.WriteLine("PASS cleanup fences acquired bytes and pending writes");
    }
    private sealed class Fixture : IAsyncDisposable
    {
        internal readonly string Root = Path.Combine(Path.GetTempPath(), "StarBridge-image-wire-" + Guid.NewGuid().ToString("N"));
        internal readonly BridgeAccountContext Owner = new("synthetic", "synthetic-authority", "synthetic-wire-pilot");
        internal readonly Clock Clock = new();
        internal readonly OfflineAccountStore Store;
        internal bool Alive = true;
        internal long Generation = 7;
        internal long? OfflineRevision;
        internal int MaximumFrameBytes;
        private readonly List<RemoteImageCacheBridge> _clients = [];
        internal Fixture() { Directory.CreateDirectory(Root); Store = new(Root); Store.Observe(Owner, "Synthetic Wire Pilot", () => true); }
        internal RemoteImageCacheBridge Create()
        {
            var bridge = new RemoteImageCacheBridge(new(Root), () =>
            {
                var generation = Generation; var revision = OfflineRevision;
                return Alive ? new(revision is null ? Owner : null, revision, generation,
                    () => Alive && Generation == generation && OfflineRevision == revision) : null;
            }, Clock);
            _clients.Add(bridge);
            return bridge;
        }
        internal async Task<BridgeEnvelope> Call(RemoteImageCacheBridge bridge, string operation, object payload)
        {
            var fields = JsonSerializer.SerializeToElement(payload, BridgeProtocol.JsonOptions).EnumerateObject()
                .ToDictionary(row => row.Name, row => (object?)row.Value, StringComparer.Ordinal);
            fields.Add("schemaVersion", 1);
            var request = BridgeEnvelope.Request("imageCache." + operation, Guid.NewGuid().ToString("N"), Generation, fields);
            var result = await bridge.DispatchAsync(await Wire(request));
            return await Wire(result.Response);
        }
        private async Task<BridgeEnvelope> Wire(BridgeEnvelope envelope)
        {
            // The codec is intentionally internal to NativeBridge. Exercise
            // its actual stream framing without broadening product visibility.
            var codec = typeof(BridgeEnvelope).Assembly.GetType("StarBridge.NativeBridge.BridgeWireCodec", throwOnError: true)!;
            using var stream = new MemoryStream();
            var write = (ValueTask)codec.GetMethod("WriteFrameAsync", BindingFlags.NonPublic | BindingFlags.Static)!
                .Invoke(null, [stream, envelope, CancellationToken.None])!;
            await write;
            MaximumFrameBytes = Math.Max(MaximumFrameBytes, checked((int)stream.Length - sizeof(int)));
            stream.Position = 0;
            var read = (ValueTask<BridgeEnvelope?>)codec.GetMethod("ReadFrameAsync", BindingFlags.NonPublic | BindingFlags.Static)!
                .Invoke(null, [stream, CancellationToken.None])!;
            return await read ?? throw new InvalidDataException("Actual wire codec returned no frame.");
        }
        internal async Task<string> Open(RemoteImageCacheBridge bridge, string resource) =>
            (await Call(bridge, "open", new { key = Key(resource), kind = "ship" })).Payload.GetProperty("cacheToken").GetString()!;
        internal object Metadata(string token, byte[] bytes)
        {
            var now = DateTimeOffset.UtcNow;
            return new { cacheToken = token, length = bytes.Length, sha256 = Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant(),
                storedAtMs = now.ToUnixTimeMilliseconds(), freshUntilMs = now.AddMinutes(2).ToUnixTimeMilliseconds(),
                maxAgeSeconds = 120, noCache = false, mustRevalidate = false, etag = "\"fixture\"", validatorTarget = Key("target") };
        }
        internal async Task Upload(RemoteImageCacheBridge bridge, string token, byte[] bytes)
        {
            Require((await Call(bridge, "beginWrite", Metadata(token, bytes))).Status == BridgeResponseStatuses.Ok, "begin bounded upload");
            for (var offset = 0; offset < bytes.Length; offset += 256 * 1024)
                Require((await Call(bridge, "append", new { cacheToken = token, offset,
                    chunk = Convert.ToBase64String(bytes, offset, Math.Min(256 * 1024, bytes.Length - offset)) })).Status == BridgeResponseStatuses.Ok,
                    "append exact bounded chunk");
        }
        public async ValueTask DisposeAsync()
        {
            foreach (var client in _clients) await client.DisposeAsync();
            if (!Path.GetFullPath(Root).StartsWith(Path.GetFullPath(Path.GetTempPath()), StringComparison.OrdinalIgnoreCase)) throw new IOException();
            Directory.Delete(Root, recursive: true);
        }
    }
    private sealed class Clock : TimeProvider
    {
        private long _ticks;
        public override long TimestampFrequency => 1000;
        public override long GetTimestamp() => _ticks;
        internal void Advance(TimeSpan elapsed) => _ticks += (long)elapsed.TotalMilliseconds;
    }
    private static string Key(string text) => Convert.ToHexString(SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(text))).ToLowerInvariant();
    private static void Require(bool condition, string message)
    { if (!condition) throw new InvalidOperationException("FAIL " + message); }
}
