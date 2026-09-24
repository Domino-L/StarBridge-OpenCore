using StarBridge.HostRuntime.Hangar;
using StarBridge.NativeBridge;
using System.Net;

internal static class HangarSandboxTests
{
    public static async Task LiveProbe()
    {
        using var dispatcher = HangarSandboxDispatcher.FromEnvironment(() => 0) ?? throw new Exception("Sandbox not enabled");
        var read = await dispatcher.DispatchAsync(BridgeEnvelope.Request("hangarSandbox.read", "live-a", 0, new { testAccount = "A" }));
        if (read.Response.Status != "ok" || read.Response.Payload.GetProperty("ships").GetArrayLength() != 3)
            throw new Exception("MySQL data did not reach Host");
        var name = read.Response.Payload.GetProperty("ships")[0].GetProperty("presentation").GetProperty("names").GetProperty("zhHans").GetString();
        if (string.IsNullOrWhiteSpace(name)) throw new Exception("Chinese presentation missing");
        var other = await dispatcher.DispatchAsync(BridgeEnvelope.Request("hangarSandbox.read", "live-b", 0, new { testAccount = "B" }));
        if (other.Response.Status != "ok" || other.Response.Payload.GetProperty("revision").GetInt32() != 0)
            throw new Exception("Test account isolation failed");
        Console.WriteLine("PASS|Host-Java-MySQL|3-ships|Chinese-names|A-B-isolation");
    }
    public static async Task GuardsAndProjection()
    {
        using var http = new HttpClient(new Handler());
        using var dispatcher = new HangarSandboxDispatcher(http, new string('a', 64), new string('b', 64), () => 5);
        var read = await dispatcher.DispatchAsync(BridgeEnvelope.Request("hangarSandbox.read", "read", 5, new { testAccount = "A" }));
        if (read.Response.Status != "ok" || read.Response.Payload.GetProperty("ships").GetArrayLength() != 0)
            throw new Exception("Read projection missing");
        var bad = await dispatcher.DispatchAsync(BridgeEnvelope.Request("hangarSandbox.read", "bad", 4, new { testAccount = "A" }));
        if (bad.Response.Status != "error") throw new Exception("Stale request accepted");
        var owner = await dispatcher.DispatchAsync(BridgeEnvelope.Request("hangarSandbox.read", "owner", 5, new { testAccount = "A", owner = "real" }));
        if (owner.Response.Status != "error") throw new Exception("Unknown owner accepted");
    }
    private sealed class Handler : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            if (request.RequestUri?.AbsoluteUri != "http://127.0.0.1:18083/hangar" ||
                request.Headers.Authorization?.Parameter != new string('a', 64)) throw new Exception("Wrong destination");
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) {
                Content = new StringContent("{\"revision\":0,\"savedAt\":null,\"catalogVersion\":null,\"ships\":[]}") });
        }
    }
}
