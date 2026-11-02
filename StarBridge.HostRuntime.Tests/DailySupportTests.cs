using System.Net;
using System.Net.Http.Json;
using System.Text;
using System.Reflection;
using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.NativeBridge;

internal static class DailySupportTests
{
    internal static async Task Verify()
    {
        void Check(bool condition, string name) { if (!condition) throw new Exception(name); Console.WriteLine("PASS " + name); }
        var bytes = Encoding.UTF8.GetBytes("""
            {"schemaVersion":1,"outcome":"granted","receipt":{"id":"test","localDay":"2026-10-09","entitlement":"overlay.skin.night-shadow","expiresAt":"2026-10-10T00:00:00Z"},"temporaryEntitlements":[{"entitlement":"overlay.skin.night-shadow","expiresAt":"2026-10-10T00:00:00Z"}]}
            """);
        Check(DailySupportClient.Parse(bytes).Outcome == "granted", "valid server receipt");
        foreach (var malformed in new[] {
            "{\"schemaVersion\":1,\"outcome\":\"granted\",\"temporaryEntitlements\":[]}",
            "{\"schemaVersion\":1,\"outcome\":\"ready\",\"temporaryEntitlements\":[{}]}",
            "{\"schemaVersion\":2,\"outcome\":\"ready\",\"temporaryEntitlements\":[]}" })
        {
            try { DailySupportClient.Parse(Encoding.UTF8.GetBytes(malformed)); throw new Exception("Malformed receipt accepted"); }
            catch (AccountBridgeHostException) { }
        }
        Console.WriteLine("PASS malformed/missing grants fail closed");
        var handler = new CaptureHandler(bytes);
        using var client = new DailySupportClient(new Uri("https://relay.invalid/"), handler);
        await client.SendAsync("synthetic-token", 60, CancellationToken.None);
        Check(handler.Calls == 1 && handler.Method == HttpMethod.Post && handler.Body == "{\"utcOffsetMinutes\":60}", "POST sends only offset, never owner or entitlement");
        await client.SendAsync("synthetic-token", null, CancellationToken.None);
        Check(handler.Calls == 2 && handler.Method == HttpMethod.Get && handler.Body == null, "readback is GET");
        handler.Status = HttpStatusCode.ServiceUnavailable;
        try { await client.SendAsync("synthetic-token", 60, CancellationToken.None); throw new Exception("503 accepted"); }
        catch (AccountBridgeHostException) { }
        Check(handler.Calls == 3, "uncertain POST never replayed");
        try { using var insecure = new DailySupportClient(new Uri("http://remote.invalid")); throw new Exception("insecure origin accepted"); }
        catch (ArgumentException) { Console.WriteLine("PASS HTTPS required"); }
        await VerifyComposition();
    }

    private static async Task VerifyComposition()
    {
        var host = DispatchProxy.Create<IAccountBridgeHost, SupportHost>();
        var probe = (SupportHost)(object)host;
        using var runtime = new AccountBridgeRuntime(host);
        using var composite = new CompositeBridgeDispatcher(runtime, runtime, runtime);
        foreach (var claim in new[] { false, true })
        {
            var name = claim ? "account.supportClaim" : "account.supportRead";
            if (!AccountBridgeRuntime.AdvertisedCapabilities.Contains(name))
                throw new Exception("Sponsor capability is not advertised.");
            var request = BridgeEnvelope.Request(name, Guid.NewGuid().ToString("N"), 1,
                claim ? new { schemaVersion = 1, utcOffsetMinutes = 60 } : (object)new { schemaVersion = 1 },
                SupportHost.Owner);
            var result = await composite.DispatchAsync(request);
            if (result.Response.Status != BridgeResponseStatuses.Ok)
                throw new Exception($"Advertised sponsor command {name} blocked by real composition: {result.Response.Error?.Code}");
            if (probe.LastClaim != claim || probe.Calls != (claim ? 2 : 1) ||
                result.Response.Payload.GetProperty("schemaVersion").GetInt32() != 1 ||
                result.Response.Payload.GetProperty("outcome").GetString() != (claim ? "granted" : "ready"))
                throw new Exception("Sponsor owner or camel-case receipt did not cross composition exactly once.");
            var stale = await composite.DispatchAsync(request with { SessionGeneration = 0 });
            var wrongOwner = await composite.DispatchAsync(request with { AccountContext = SupportHost.Owner with { Subject = "other" } });
            if (stale.Response.Status != BridgeResponseStatuses.Error || wrongOwner.Response.Status != BridgeResponseStatuses.Error ||
                probe.Calls != (claim ? 2 : 1)) throw new Exception("Sponsor request bypassed account isolation.");
        }
        var unknown = await composite.DispatchAsync(BridgeEnvelope.Request("account.supportUnknown", "unknown", 1,
            new { schemaVersion = 1 }, SupportHost.Owner));
        if (unknown.Response.Error?.Code != BridgeErrorCodes.CapabilityUnavailable || probe.Calls != 2)
            throw new Exception("Unknown sponsor command became available.");
        Console.WriteLine("PASS sponsor read/claim cross real composite and allowlist; wire receipt, ownership and generation preserved");
    }

    public class SupportHost : DispatchProxy
    {
        internal static readonly BridgeAccountContext Owner = new("test", "synthetic", "support-owner");
        internal int Calls;
        internal bool LastClaim;
        protected override object? Invoke(MethodInfo? method, object?[]? args)
        {
            switch (method!.Name)
            {
                case "get_Generation": return 1L;
                case "get_CurrentContext": return Owner;
                case "get_SupportsConcurrentReads": return false;
                case "add_AccountChanged":
                case "remove_AccountChanged": return null;
                case "DailySupportAsync":
                    if (!Equals(args![0], Owner)) throw new Exception("Unexpected owner.");
                    var payload = (JsonElement)args[1]!;
                    LastClaim = (bool)args[2]!;
                    if (payload.EnumerateObject().Count() != (LastClaim ? 2 : 1)) throw new Exception("Unexpected payload.");
                    Calls++;
                    return Task.FromResult<object>(new DailySupportView(1, LastClaim ? "granted" : "ready",
                        LastClaim ? new("synthetic-receipt", "2026-10-12", "overlay.skin.night-shadow",
                            DateTimeOffset.Parse("2026-10-13T00:00:00Z")) : null, []));
                default: throw new NotSupportedException(method.Name);
            }
        }
    }
    private sealed class CaptureHandler(byte[] body) : HttpMessageHandler
    {
        internal int Calls;
        internal HttpMethod? Method;
        internal string? Body;
        internal HttpStatusCode Status = HttpStatusCode.OK;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Calls++; Method = request.Method; Body = request.Content is null ? null : await request.Content.ReadAsStringAsync(token);
            if (request.Headers.Authorization?.Parameter != "synthetic-token" || request.RequestUri!.AbsolutePath != "/api/support/daily")
                throw new Exception("Wrong authenticated transport");
            return new(Status) { Content = new ByteArrayContent(body) };
        }
    }
}
