using System.Net;
using StarBridge.HostRuntime.Account;
using StarBridge.NativeBridge;

internal static partial class LegacyPasswordLoginTests
{
    internal static async Task HangarMigrationBridge()
    {
        using var transport = new RetiredHangarTransport();
        using var client = new LegacyPasswordLoginClient(new Uri("https://example.invalid/"), new Store(), transport);
        using var host = CreateHost(client);
        await host.LoginLegacyAsync(BridgePayload.From(new { schemaVersion = 1, email = "old@example.invalid", password = "short" }), 0, default);
        using var dispatcher = new AccountBridgeDispatcher(host);
        foreach (var name in new[] { "hangar.migrationRead", "hangar.migrationSelectLocal", "hangar.migrationConfirmLocal",
            "hangar.migrationReadLocal", "hangar.migrationClearLocal", "hangar.migrationCompare" })
        {
            var response = await dispatcher.DispatchAsync(BridgeEnvelope.Request(name, Guid.NewGuid().ToString("N"),
                host.Generation, new { schemaVersion = 1 }, host.CurrentContext));
            Check(response.Response.Error is not null, "retired hangar migration must not dispatch");
        }
        Check(transport.Requests == 1, "retired migration must not fetch server hangar");
        Console.WriteLine("PASS retired hangar migration routes reject requests without reading inventory");
    }

    private sealed class RetiredHangarTransport : HttpMessageHandler
    {
        internal int Requests;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Requests++;
            Check(request.RequestUri!.AbsolutePath == "/api/auth/login", "only login is expected");
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(Transport.Valid) });
        }
    }
}
