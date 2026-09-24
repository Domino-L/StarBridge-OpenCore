using System.Net;
using StarBridge.HostRuntime.Account;
using StarBridge.NativeBridge;

internal static partial class LegacyPasswordLoginTests
{
    internal static async Task ProfileVisibility()
    {
        var transport = new Transport();
        using var client = new LegacyPasswordLoginClient(new Uri("https://example.invalid/"), new Store(), transport);
        using var host = CreateHost(client);
        await host.LoginLegacyAsync(BridgePayload.From(new { schemaVersion = 1, email = "old@example.invalid", password = "synthetic" }), 0, default);
        using var dispatcher = new AccountBridgeDispatcher(host);
        foreach (var value in new[] { "public", "friendsFleetAndOrganizations", "friendsOnly", "private" })
        {
            transport.Body = "{\"schemaVersion\":1,\"revision\":2,\"visibility\":\"" + value + "\"}";
            var read = await dispatcher.DispatchAsync(BridgeEnvelope.Request("personalProfile.readVisibility", "read", host.Generation,
                new { schemaVersion = 1 }, host.CurrentContext));
            Check(read.Response.Payload.GetProperty("visibility").GetString() == value, "read authoritative visibility");
            var before = transport.Calls;
            var saved = await dispatcher.DispatchAsync(BridgeEnvelope.Request("personalProfile.saveVisibility", "save", host.Generation,
                new { schemaVersion = 1, expectedRevision = 1, visibility = value }, host.CurrentContext));
            Check(saved.Response.Payload.GetProperty("visibility").GetString() == value && transport.Calls == before + 1 && transport.Authorized,
                "single bounded write with existing credential");
        }
        transport.Status = HttpStatusCode.Conflict;
        var calls = transport.Calls;
        var failed = await dispatcher.DispatchAsync(BridgeEnvelope.Request("personalProfile.saveVisibility", "conflict", host.Generation,
            new { schemaVersion = 1, expectedRevision = 1, visibility = "private" }, host.CurrentContext));
        Check(failed.Response.Error is not null && transport.Calls == calls + 1, "conflict not retried or reported successful");
        var context = host.CurrentContext;
        var generation = host.Generation;
        await host.LogoutAsync(context!, default);
        calls = transport.Calls;
        failed = await dispatcher.DispatchAsync(BridgeEnvelope.Request("personalProfile.saveVisibility", "stale", generation,
            new { schemaVersion = 1, expectedRevision = 1, visibility = "public" }, context));
        Check(failed.Response.Error is not null && transport.Calls == calls, "old account cannot publish");
    }
}
