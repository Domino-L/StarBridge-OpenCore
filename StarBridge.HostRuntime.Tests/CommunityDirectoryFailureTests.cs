using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;
using StarBridge.NativeBridge;

internal static class CommunityDirectoryFailureTests
{
    internal static async Task Classify()
    {
        foreach (var legacy in new[] { false, true })
        foreach (var (fault, code, retryable) in new[] {
            ("503", "communities.readTransient", true), ("429", "communities.readTransient", true),
            ("408", "communities.readTransient", true), ("network", "communities.readTransient", true),
            ("stream", "communities.readTransient", true), ("403", "communities.notAllowed", false),
            ("400", "communities.unavailable", false), ("invalid", "communities.dataInvalid", false),
            ("invalid-stream", "communities.dataInvalid", false)
        }) {
            using var handler = new Handler { Fault = fault };
            using var client = new CommunityClient(new Uri("https://communities.invalid/"), handler);
            try {
                if (legacy) await client.ReadWpfS2Async("synthetic-access", new("mine", "", null, null), "owner:1", "synthetic-viewer", default);
                else await client.ReadAsync("synthetic-access", new("mine", "", null, null), "owner:1", default);
                throw new InvalidOperationException("Failed directory read was accepted.");
            }
            catch (AccountBridgeHostException error) {
                Require(error.Code == code && error.Retryable == retryable,
                    $"Directory classification legacy={legacy} fault={fault}: expected {code}/{retryable}, got {error.Code}/{error.Retryable}");
            }
        }
        foreach (var legacy in new[] { false, true }) {
            using var handler = new Handler { Fault = "caller-cancelled" };
            using var client = new CommunityClient(new Uri("https://communities.invalid/"), handler);
            using var cancellation = new CancellationTokenSource();
            handler.Caller = cancellation;
            try {
                if (legacy) await client.ReadWpfS2Async("synthetic-access", new("mine", "", null, null), "owner:1", "synthetic-viewer", cancellation.Token);
                else await client.ReadAsync("synthetic-access", new("mine", "", null, null), "owner:1", cancellation.Token);
                throw new InvalidOperationException("Caller cancellation became successful data.");
            }
            catch (OperationCanceledException) { Require(cancellation.IsCancellationRequested, "Caller cancellation remains cancellation."); }
        }
    }

    internal static Task ActualRuntime() => RuntimeCore(null);
    internal static async Task<string> Wire()
    {
        var messages = new Dictionary<string, BridgeEnvelope>();
        await RuntimeCore((name, response) => messages.Add(name, response));
        return JsonSerializer.Serialize(messages, BridgeProtocol.JsonOptions);
    }

    private static async Task RuntimeCore(Action<string, BridgeEnvelope>? observe)
    {
        using var handler = new Handler();
        using var client = new CommunityClient(new Uri("https://communities.invalid/"), handler);
        using var f = new LocalAccountStopTests.Fixture(sampling: true, communities: client);
        await using var native = new NativeAccountRuntimeBinding(f.Runtime);
        var owner = f.Host.CurrentContext!;
        var generation = f.Host.Generation;
        var root = (await native.DispatchAsync(BridgeEnvelope.Request("account.getCurrent", Op(), generation, new { schemaVersion = 1 }))).Response;
        Require(root.Status == "ok" && root.AccountContext == owner, "Actual fresh root owner precedes the directory.");
        observe?.Invoke("root", root);
        async Task<BridgeEnvelope> Read() => (await native.DispatchAsync(BridgeEnvelope.Request("communities.read", Op(), generation,
            new { schemaVersion = 1, view = "mine", query = "" }, owner))).Response;
        var live = await Read();
        Require(live.Status == "ok", "An actual authorized success precedes failure injection.");
        observe?.Invoke("live", live);
        foreach (var (label, fault, expected) in new[] {
            ("outage", "503", "communities.readTransient"), ("forbidden", "403", "communities.notAllowed"),
            ("unknown", "400", "communities.unavailable"), ("invalid", "invalid", "communities.dataInvalid"),
            ("rateLimited", "429", "communities.readTransient")
        }) {
            handler.Fault = fault;
            var failed = await Read();
            Require(failed.Status == "error" && failed.Error?.Code == expected, "Actual runtime must preserve directory failure category: " + label);
            Require(f.Host.CurrentContext == owner && f.Host.Generation == generation && !f.Vault.Deleted,
                "A field-scoped denial or outage must not sign out the root owner.");
            observe?.Invoke(label, failed);
        }
        handler.Fault = "none";
        var recovered = await Read();
        Require(recovered.Status == "ok", "Explicit fresh retry obtains new live directory grants.");
        observe?.Invoke("recovered", recovered);
    }

    private static string Op() => Guid.NewGuid().ToString("N");
    private static void Require(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
    private sealed class Handler : HttpMessageHandler
    {
        internal string Fault = "none";
        internal CancellationTokenSource? Caller;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Require(request.Method == HttpMethod.Get, "Directory recovery never writes or replays a mutation.");
            if (Fault == "caller-cancelled") { Caller!.Cancel(); token.ThrowIfCancellationRequested(); }
            if (Fault == "network") throw new HttpRequestException("Synthetic directory transport outage");
            if (Fault is "stream" or "invalid-stream")
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StreamContent(new BrokenStream(Fault == "invalid-stream")) });
            if (int.TryParse(Fault, out var status)) return Task.FromResult(new HttpResponseMessage((HttpStatusCode)status));
            if (Fault == "invalid") return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent("{") });
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(new {
                schemaVersion = 1, membershipModelVersion = 2, view = "mine", query = "", next = (string?)null,
                items = new[] { new { code = "SYNTHETIC-ORG", name = "Directory before failure", description = "Synthetic directory description",
                    language = "en", activeTime = "weekends", memberCount = 2, relationship = "member", joinMode = "inviteOnly",
                    actions = new[] { "leave" }, logoImageData = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=" } }
            }) });
        }
    }
    private sealed class BrokenStream(bool invalid) : MemoryStream
    {
        public override ValueTask<int> ReadAsync(Memory<byte> buffer, CancellationToken token = default) =>
            ValueTask.FromException<int>(invalid ? new InvalidDataException("Synthetic invalid data") : new IOException("Synthetic stream outage"));
    }
}
