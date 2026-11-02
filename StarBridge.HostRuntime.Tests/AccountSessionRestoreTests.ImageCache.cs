using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Onboarding;
using StarBridge.HostRuntime.Presence;
using StarBridge.NativeBridge;

internal static partial class AccountSessionRestoreTests
{
    internal static async Task ImageCacheRuntimeContracts()
    {
        var failures = new List<string>();
        await Run("ordinary authenticated Native/composite path exposes local image cache", Online);
        await Run("completed offline and cold offline preserve exact display resources without network", Offline);
        await Run("disk snapshot cannot restore or authenticate an unchecked account", Unchecked);
        await Run("original long HTTP max-age survives the actual route while local freshness stays capped", LongMaxAge);
        if (failures.Count != 0) throw new InvalidOperationException(string.Join(Environment.NewLine, failures));

        async Task Run(string name, Func<Task> test)
        {
            try { await test(); Console.WriteLine("PASS " + name); }
            catch (Exception error) { failures.Add("FAIL " + name + ": " + error.Message); Console.WriteLine(failures[^1]); }
        }
    }
    private static async Task Online()
    {
        await using var f = new ImageCacheFixture();
        await f.Authenticate();
        var requests = f.Transport.Requests;
        var response = await f.Call("open", new { key = ImageKey("online"), kind = "ship" });
        ImageRequire(response.Status == "ok" && response.Payload.GetProperty("status").GetString() == "miss",
            "original composite/Native path must open an image receipt under the confirmed owner");
        ImageRequire(AccountBridgeRuntime.AdvertisedCapabilities.Contains("imageCache.resources.v1"), "actual account capability advertises implemented resource protocol");
        var token = response.Payload.GetProperty("cacheToken").GetString()!;
        var now = DateTimeOffset.UtcNow;
        await f.Call("beginWrite", new { cacheToken = token, length = 3, sha256 = ImageDigest([1, 2, 3]),
            storedAtMs = now.ToUnixTimeMilliseconds(), freshUntilMs = now.AddMinutes(2).ToUnixTimeMilliseconds(),
            maxAgeSeconds = 120, noCache = false, mustRevalidate = false, etag = "\"fixture\"", validatorTarget = ImageKey("target") });
        ImageRequire((await f.Call("append", new { cacheToken = token, offset = 0, chunk = "AQID" })).Status == "ok", "actual route accepts bounded image bytes");
        ImageRequire((await f.Call("commit", new { cacheToken = token })).Payload.GetProperty("status").GetString() == "stored", "actual route persists the completed body");
        response = await f.Call("open", new { key = ImageKey("online"), kind = "ship" });
        token = response.Payload.GetProperty("cacheToken").GetString()!;
        var read = await f.Call("read", new { cacheToken = token, offset = 0 });
        ImageRequire(Convert.FromBase64String(read.Payload.GetProperty("chunk").GetString()!).SequenceEqual(new byte[] { 1, 2, 3 }) &&
            read.AccountContext is null && f.Transport.Requests == requests, "local cache route preserves bytes without HTTP or exporting an account context");
        ImageRequire((await f.Call("open", new { key = ImageKey("online"), kind = "ship", subject = "synthetic-other" })).Status != "ok",
            "caller cannot choose a disk owner");
        var stale = await f.Router.DispatchAsync(BridgeEnvelope.Request("imageCache.open", Guid.NewGuid().ToString("N"), f.Native.Generation + 1,
            new { schemaVersion = 1, key = ImageKey("online"), kind = "ship" }));
        ImageRequire(stale.Response.Status != "ok", "caller cannot promote its resource generation");
    }
    private static async Task LongMaxAge()
    {
        await using var f = new ImageCacheFixture();
        await f.Authenticate();
        var key = ImageKey("long-lived");
        var token = (await f.Call("open", new { key, kind = "ship" })).Payload.GetProperty("cacheToken").GetString()!;
        var now = DateTimeOffset.UtcNow;
        var begin = await f.Call("beginWrite", new { cacheToken = token, length = 3, sha256 = ImageDigest([1, 2, 3]),
            storedAtMs = now.ToUnixTimeMilliseconds(), freshUntilMs = now.AddMinutes(5).ToUnixTimeMilliseconds(),
            maxAgeSeconds = 3600, noCache = false, mustRevalidate = false, etag = "\"long\"", validatorTarget = ImageKey("target") });
        ImageRequire(begin.Status == "ok", "a 3600 s origin max-age is valid metadata, not an invalid request: " + begin.Status + " " + begin.Error?.Code);
        await f.Call("append", new { cacheToken = token, offset = 0, chunk = "AQID" });
        ImageRequire((await f.Call("commit", new { cacheToken = token })).Payload.GetProperty("status").GetString() == "stored",
            "long max-age metadata is persisted");
        var reopened = await f.Call("open", new { key, kind = "ship" });
        ImageRequire(reopened.Payload.GetProperty("maxAgeSeconds").GetInt32() == 3600,
            "a later 304 without Cache-Control must inherit the original 3600 s");
        ImageRequire(reopened.Payload.GetProperty("freshUntilMs").GetInt64() - reopened.Payload.GetProperty("storedAtMs").GetInt64() <= 300_000,
            "local freshness stays capped at five minutes");
        var second = (await f.Call("open", new { key = ImageKey("too-fresh"), kind = "ship" })).Payload.GetProperty("cacheToken").GetString()!;
        var tooFresh = await f.Call("beginWrite", new { cacheToken = second, length = 3, sha256 = ImageDigest([1, 2, 3]),
            storedAtMs = now.ToUnixTimeMilliseconds(), freshUntilMs = now.AddMinutes(10).ToUnixTimeMilliseconds(),
            maxAgeSeconds = 3600, noCache = false, mustRevalidate = false, etag = "\"long\"", validatorTarget = ImageKey("target") });
        ImageRequire(tooFresh.Status != "ok" && tooFresh.Error?.Code == "imageCache.invalid_request",
            "local freshness beyond five minutes is rejected as a request error, never a commit exception");
    }
    private static async Task Offline()
    {
        await using var f = new ImageCacheFixture();
        await f.Authenticate();
        var store = new OfflineAccountStore(f.Root);
        var lease = store.CaptureRemoteImageRead(f.Owner, null, "ship", () => true)!;
        var now = DateTimeOffset.UtcNow;
        ImageRequire(store.PublishRemoteImage(lease, new(ImageKey("offline"), [4, 5, 6], now, now.AddMinutes(2), 120,
            false, false, "\"fixture\"", ImageKey("target")), () => true), "confirmed online control seeds real protected image bytes");
        var mode = f.Runtime.FirstUseMode!;
        var transition = await mode.ApplyRootOfflineAsync(mode.Current.Revision, Guid.NewGuid().ToString("N"), f.Runtime.Generation, f.Native);
        ImageRequire(transition.State == "offline" && store.ReadRetainedOwner(transition.Revision, () => true) == f.Owner,
            "original mode transaction must finish and bind the actual synthetic Windows vault before cache assertions");
        var traffic = f.Transport.Requests;
        var vaultBytes = File.ReadAllBytes(f.VaultPath);
        await Check(f.Router, f.Native.Generation);
        using var cold = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root,
            _ => throw new InvalidOperationException("Cold offline resource read cannot construct an online owner."));
        await using var coldNative = new NativeAccountRuntimeBinding(cold);
        using var coldRouter = new CompositeBridgeDispatcher(new ImageUnsupported(), coldNative, new ImageUnsupported());
        await Check(coldRouter, coldNative.Generation);
        ImageRequire(traffic == f.Transport.Requests && vaultBytes.SequenceEqual(File.ReadAllBytes(f.VaultPath)),
            "warm/cold reads neither contact the network nor refresh/delete stored credentials");
        var tokenReply = await CacheCall(coldRouter, coldNative.Generation, "open", new { key = ImageKey("offline"), kind = "ship" });
        var token = tokenReply.Payload.GetProperty("cacheToken").GetString()!;
        f.Vault.SaveRefreshToken(f.Options.AuthorityId + ":synthetic-cold-owner", "synthetic-replaced-refresh");
        ImageRequire((await CacheCall(coldRouter, coldNative.Generation, "read", new { cacheToken = token, offset = 0 })).Status != "ok",
            "replacement of original retained credentials retires an acquired body");

        static async Task Check(CompositeBridgeDispatcher router, long generation)
        {
            var result = await CacheCall(router, generation, "open", new { key = ImageKey("offline"), kind = "ship" });
            ImageRequire(result.Status == "ok" && result.Payload.GetProperty("status").GetString() == "ready",
                "completed original offline scope must read local image bytes through the actual dispatcher");
            var token = result.Payload.GetProperty("cacheToken").GetString()!;
            var read = await CacheCall(router, generation, "read", new { cacheToken = token, offset = 0 });
            ImageRequire(Convert.FromBase64String(read.Payload.GetProperty("chunk").GetString()!).SequenceEqual(new byte[] { 4, 5, 6 }) &&
                read.AccountContext is null, "offline response carries display bytes without account authority");
            ImageRequire((await CacheCall(router, generation, "reject", new { cacheToken = token })).Status != "ok", "offline display receipt cannot mutate image eligibility");
            var account = await router.DispatchAsync(BridgeEnvelope.Request("account.getCurrent", Guid.NewGuid().ToString("N"), generation));
            ImageRequire(account.Response.Error?.Code == "account.local_mode", "resource access cannot reopen the retired account network lane");
        }
    }
    private static async Task Unchecked()
    {
        await using var f = new ImageCacheFixture();
        new OfflineAccountStore(f.Root).Observe(f.Owner, "Synthetic Cached Name", () => true);
        var result = await f.Call("open", new { key = ImageKey("unchecked"), kind = "ship" });
        ImageRequire(result.Status != "ok" && f.Host.CurrentContext is null && f.Transport.Requests == 0,
            "unchecked cached account does not authenticate, restore OAuth or make network requests");
    }
    private sealed class ImageCacheFixture : IAsyncDisposable
    {
        internal readonly string Root;
        internal readonly string VaultPath;
        internal readonly WindowsTokenVault Vault;
        internal readonly ScmOAuthOptions Options;
        internal readonly ColdContentHandler Transport;
        internal readonly ScmAccountBridgeHost Host;
        internal readonly AccountBridgeRuntime Runtime;
        internal readonly NativeAccountRuntimeBinding Native;
        internal readonly CompositeBridgeDispatcher Router;
        internal readonly BridgeAccountContext Owner;
        private readonly string _previousRoot;
        private readonly bool _preserveRoot;
        internal ImageCacheFixture(string? sharedRoot = null)
        {
            _preserveRoot = sharedRoot is not null;
            Root = sharedRoot ?? Path.Combine(Path.GetTempPath(), "StarBridge-image-runtime-" + Guid.NewGuid().ToString("N"));
            if (sharedRoot is not null && (Path.GetDirectoryName(Path.GetFullPath(Root)) != Path.TrimEndingDirectorySeparator(Path.GetFullPath(Path.GetTempPath())) ||
                !System.Text.RegularExpressions.Regex.IsMatch(Path.GetFileName(Root), "^StarBridge-image-runtime-[0-9a-f]{32}$") ||
                Directory.Exists(Root) && (File.GetAttributes(Root) & FileAttributes.ReparsePoint) != 0))
                throw new IOException("Worker requires an isolated synthetic temporary root.");
            Directory.CreateDirectory(Root);
            _previousRoot = HostDataRoot.CurrentRoot; HostDataRoot.UsePreparedRoot(Root);
            var local = new LocalFirstUseStore(Root);
            if (local.Read().SelectedSourceKey is null)
            {
                var source = local.SelectSource(0, Guid.NewGuid().ToString("N"), Path.Combine(Root, "install", "LIVE", "Game.log"), "LIVE", () => true);
                local.ConfirmIdentity(source.Revision, Guid.NewGuid().ToString("N"), new(source.SelectedSourceKey!, Guid.NewGuid().ToString("N"),
                    "Pilot-Example", DateTimeOffset.UtcNow, "history", true, false), () => true);
            }
            var settings = CreateEnvironmentSettings(); Options = ScmOAuthOptions.Create(settings);
            VaultPath = Path.Combine(Root, "scm-token-vault.json"); Vault = new(VaultPath);
            Vault.SaveRefreshToken(Options.AuthorityId + ":synthetic-cold-owner", "synthetic-cold-refresh");
            Owner = new(settings.EnvironmentName, Options.AuthorityId, "synthetic-cold-owner");
            Transport = new(Options, "none");
            Host = new(new OAuthPkceClient(new ScmHttpClient(Transport), Vault, Options),
                new ScmProfileCacheStore(Path.Combine(Root, "profile")), settings.EnvironmentName, () => null);
            Runtime = new(Host, gameplayTime: new GameplayTimeStore(Root), gameLog: new GameLogSettingsStore(Root));
            Runtime.InitializeOfflineAccount(Root);
            Native = new(Runtime); Router = new(new ImageUnsupported(), Native, new ImageUnsupported());
        }
        internal async Task Authenticate()
        {
            var current = await ReadCurrent(Runtime, "synthetic-image-seed");
            ImageRequire(current.Response.Status == "ok" && Host.CurrentContext == Owner &&
                new OfflineAccountStore(Root).ReadSelectedDisplay(Owner, () => true) is not null, "actual authenticated root control persists original display owner");
            var configured = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(Root, _ => Task.FromResult(Runtime));
            ImageRequire(ReferenceEquals(configured, Runtime) && Runtime.FirstUseMode is not null,
                "fixture attaches mode to the original authenticated root");
        }
        internal Task<BridgeEnvelope> Call(string operation, object payload) => CacheCall(Router, Native.Generation, operation, payload);
        public async ValueTask DisposeAsync()
        {
            Transport.Release.TrySetResult();
            Router.Dispose();
            await Native.DisposeAsync(); Runtime.Dispose(); Transport.Dispose();
            HostDataRoot.UsePreparedRoot(_previousRoot);
            if (!Path.GetFullPath(Root).StartsWith(Path.GetFullPath(Path.GetTempPath()), StringComparison.OrdinalIgnoreCase)) throw new IOException();
            if (!_preserveRoot) Directory.Delete(Root, recursive: true);
        }
    }
    private sealed class ImageUnsupported : IBridgeRequestDispatcher
    {
        public event Action<BridgeEnvelope>? EventReady { add { } remove { } }
        public ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken cancellationToken = default) =>
            ValueTask.FromResult(new BridgeDispatchBatch(BridgeEnvelope.ErrorResponse(request, new("synthetic.unsupported", "Unsupported test route.")), []));
        public void Dispose() { }
    }
    private static async Task<BridgeEnvelope> CacheCall(IBridgeRequestDispatcher router, long generation, string operation, object payload)
    {
        var fields = JsonSerializer.SerializeToElement(payload, BridgeProtocol.JsonOptions).EnumerateObject()
            .ToDictionary(row => row.Name, row => (object?)row.Value, StringComparer.Ordinal);
        fields.Add("schemaVersion", 1);
        return (await router.DispatchAsync(BridgeEnvelope.Request("imageCache." + operation, Guid.NewGuid().ToString("N"), generation, fields))).Response;
    }
    private static string ImageKey(string value) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value))).ToLowerInvariant();
    private static string ImageDigest(byte[] value) => Convert.ToHexString(SHA256.HashData(value)).ToLowerInvariant();
    private static void ImageRequire(bool value, string name) { if (!value) throw new InvalidOperationException(name); }
}
