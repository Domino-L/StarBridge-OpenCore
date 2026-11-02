namespace StarBridge.HostRuntime.Account;

using StarBridge.NativeBridge;

internal sealed partial class AccountBridgeDispatcher
{
    private async Task<BridgeEnvelope> DispatchStagedProfileAsync(BridgeEnvelope request,
        IAccountBridgeStagedProfileReader reader, CancellationToken token)
    {
        RejectUnknownProperties(request.Payload, "schemaVersion");
        if (request.Payload.EnumerateObject().Count() != 1)
            throw new BridgeProtocolException(BridgeErrorCodes.InvalidEnvelope, "Invalid staged profile payload.");
        var owner = RequireCurrentContext(request);
        if (request.Name == AccountBridgeRequestNames.GetProfileTimeZoneDirectory)
            return BridgeEnvelope.Response(request, new { schemaVersion = 1,
                timeZones = await reader.GetProfileTimeZoneDirectoryAsync(owner, token), availableActions = _profileActions });
        var profile = request.Name == AccountBridgeRequestNames.ReadProfileDisplayCache
            ? reader.ReadProfileDisplayCache(owner, token)
            : await reader.GetProfileDisplayDataAsync(owner, token);
        return profile is null ? BridgeEnvelope.Response(request, new {
            schemaVersion = 1, profile = (object?)null, source = "unavailable", cachedAtUtc = (DateTimeOffset?)null,
            preferencesPolicy = new { locales = Array.Empty<string>(), timeZones = Array.Empty<AccountBridgeTimeZone>(),
                availableActions = _profileActions.Where(action => action != AccountBridgeRequestNames.PatchPreferences).ToArray() }
        }) : ToProfileResponse(request, profile, allowPreferenceWrite: false);
    }
}
