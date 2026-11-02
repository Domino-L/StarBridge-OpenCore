using System.Text.Json;
using System.Net;
using System.Net.Http.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.NativeBridge;

internal static partial class PersonalProfileReadFailureTests
{
    internal static async Task UnexpectedHostFailure()
    {
        var response = (await UnknownFailureScenario()).Fault;
        var wire = JsonSerializer.Serialize(response, BridgeProtocol.JsonOptions);
        if (response.Error?.Code != "bridge.host_error" || response.Error.Retryable ||
            response.Status != BridgeResponseStatuses.Error || wire.Contains("private-internal-fault", StringComparison.Ordinal))
            throw new InvalidOperationException($"Unknown Host fault became {response.Error?.Code}/{response.Error?.Retryable}");
    }

    internal static async Task<string> UnknownFailureWire()
    {
        var scenario = await UnknownFailureScenario();
        return JsonSerializer.Serialize(new { success = scenario.Success, fault = scenario.Fault }, BridgeProtocol.JsonOptions);
    }

    private static async Task<(BridgeEnvelope Success, BridgeEnvelope Fault)> UnknownFailureScenario()
    {
        var fail = false;
        using var transport = new Handler((_, _) => fail
            ? throw new FormatException("private-internal-fault")
            : Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) {
                Content = JsonContent.Create(Document with { Identity = new("Synthetic pilot", "Synthetic_Pilot") }) }));
        using var host = CreateScm(transport);
        using var dispatcher = new AccountBridgeDispatcher(host);
        var generation = host.Generation;
        var success = await dispatcher.DispatchAsync(BridgeEnvelope.Request("personalProfile.getSelf", "success-profile-wire",
            generation, new { schemaVersion = 1 }, host.CurrentContext));
        if (success.Response.Status != BridgeResponseStatuses.Ok) throw new InvalidOperationException("Valid baseline did not load");
        fail = true;
        var result = await dispatcher.DispatchAsync(BridgeEnvelope.Request("personalProfile.getSelf", "fault-profile-wire",
            generation, new { schemaVersion = 1 }, host.CurrentContext));
        if (result.Events.Count != 0 || host.Generation != generation)
            throw new InvalidOperationException("Unknown fault acknowledged a mutation or retired an unrelated account");
        return (success.Response, result.Response);
    }
}
