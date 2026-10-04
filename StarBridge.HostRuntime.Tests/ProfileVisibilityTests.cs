using System.Net;
using StarBridge.HostRuntime.Account;
using StarBridge.NativeBridge;

internal static partial class LegacyPasswordLoginTests
{
    internal static async Task ProfileVisibility()
    {
        await ProfileBackground();
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

    private static async Task ProfileBackground()
    {
        var transport = new Transport();
        using var client = new LegacyPasswordLoginClient(new Uri("https://example.invalid/"), new Store(), transport);
        using var host = CreateHost(client);
        await host.LoginLegacyAsync(BridgePayload.From(new { schemaVersion = 1, email = "old@example.invalid", password = "synthetic" }), 0, default);
        using var dispatcher = new AccountBridgeDispatcher(host);
        transport.Body = "{\"schemaVersion\":1,\"revision\":2,\"wallpaperId\":\"aurora\"}";
        var read = await dispatcher.DispatchAsync(BridgeEnvelope.Request("personalProfile.readBackground", "background-read", host.Generation,
            new { schemaVersion = 1 }, host.CurrentContext));
        Check(read.Response.Error is null && read.Response.Payload.GetProperty("wallpaperId").GetString() == "aurora", "background read");
        var before = transport.Calls;
        var saved = await dispatcher.DispatchAsync(BridgeEnvelope.Request("personalProfile.saveBackground", "background-save", host.Generation,
            new { schemaVersion = 1, expectedRevision = 1, wallpaperId = "aurora" }, host.CurrentContext));
        Check(saved.Response.Error is null && transport.Calls == before + 1 && transport.Authorized, "background single authenticated write");
        foreach (var payload in new object[] { new { schemaVersion = 1, expectedRevision = 1, wallpaperId = "../bad" },
            new { schemaVersion = 1, expectedRevision = 1, wallpaperId = "aurora", visibility = "public" },
            new { schemaVersion = 1, expectedRevision = -1, wallpaperId = "aurora" } })
        {
            before = transport.Calls;
            var invalid = await dispatcher.DispatchAsync(BridgeEnvelope.Request("personalProfile.saveBackground", "background-invalid", host.Generation, payload, host.CurrentContext));
            Check(invalid.Response.Error is not null && transport.Calls == before, "invalid background never sent");
        }
        transport.Status = HttpStatusCode.Conflict;
        before = transport.Calls;
        var conflict = await dispatcher.DispatchAsync(BridgeEnvelope.Request("personalProfile.saveBackground", "background-conflict", host.Generation,
            new { schemaVersion = 1, expectedRevision = 1, wallpaperId = "aurora" }, host.CurrentContext));
        Check(conflict.Response.Error?.Code == "profile.background_conflict" && transport.Calls == before + 1, "background conflict not retried");
        transport.Status = HttpStatusCode.OK;
        transport.Body = "{\"schemaVersion\":1,\"revision\":2,\"wallpaperId\":\"wrong\"}";
        var wrong = await dispatcher.DispatchAsync(BridgeEnvelope.Request("personalProfile.saveBackground", "background-wrong", host.Generation,
            new { schemaVersion = 1, expectedRevision = 1, wallpaperId = "aurora" }, host.CurrentContext));
        Check(wrong.Response.Error is not null, "mismatched background not success");
        var context = host.CurrentContext;
        var generation = host.Generation;
        await host.LogoutAsync(context!, default);
        before = transport.Calls;
        var stale = await dispatcher.DispatchAsync(BridgeEnvelope.Request("personalProfile.saveBackground", "background-stale", generation,
            new { schemaVersion = 1, expectedRevision = 1, wallpaperId = "aurora" }, context));
        Check(stale.Response.Error is not null && transport.Calls == before, "stale background cannot publish");
    }
}
