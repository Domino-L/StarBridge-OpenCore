using StarBridge.HostRuntime.Support;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime;

public sealed partial class AccountBridgeRuntime
{
    private LocalMissionRecords? _localMissionRecords;
    private MissionRecordsRuntime? _missionRecords;
    private bool MissionRecordsLocalMode => _localBusinessRetired || FirstUseBusinessUnavailable || _firstUseCandidate ||
        RetainsFirstUseSession || _host is Account.EnvironmentLockedAccountBridgeHost;

    private void ConfigureMissionRecords(string dataRoot)
    {
        _localMissionRecords = new(dataRoot);
        _missionRecords = new(_localMissionRecords, GameplayOwner, MissionImportUnavailableReason,
            GameplayHandle, () => _gameLog?.BoundLivePathForHistory);
        _gameLog?.ConfigureMissionRecords(_localMissionRecords);
    }
    private string? MissionImportUnavailableReason()
    {
        if (MissionRecordsLocalMode) return "localMode";
        if (GameplayOwner().Context is null) return "signedOut";
        if (GameplayHandle() is null || !GameRecordingIdentityReady) return "identityUnverified";
        return _gameplayTime?.MissionImportConsentAllowed == true ? null : "consentMissing";
    }

    private Task<BridgeDispatchBatch> DispatchMissionRecordsAsync(BridgeEnvelope request, CancellationToken token)
    {
        try { token.ThrowIfCancellationRequested(); MissionRecordsRuntime.ValidateRequest(request); }
        catch (OperationCanceledException) { return Task.FromResult(new BridgeDispatchBatch(BridgeEnvelope.CancelledResponse(request), [])); }
        catch (Exception) { return Task.FromResult(MissionRecordsRuntime.Error(request, "invalidRequest")); }
        var owner = GameplayOwner();
        if (_disposed || request.SessionGeneration != owner.Generation || request.AccountContext != owner.Context)
            return Task.FromResult(MissionRecordsRuntime.Error(request, "accountChanged"));
        var reason = MissionImportUnavailableReason() ?? "signedOut";
        if (_missionRecords is not null && !MissionRecordsLocalMode)
            return _missionRecords.DispatchAsync(request, token);
        // Cold local/first-use graphs do not construct an account record store.
        return Task.FromResult(request.Name == "missionRecords.summary"
            ? new BridgeDispatchBatch(BridgeEnvelope.Response(request, new { schemaVersion = 1,
                groups = Array.Empty<LocalMissionGroup>(), total = 0, importAvailable = false, importUnavailableReason = reason }), [])
            : MissionRecordsRuntime.Error(request, "unavailable", reason));
    }
}
