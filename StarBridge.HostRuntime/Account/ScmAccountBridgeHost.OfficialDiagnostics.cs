using StarBridge.HostRuntime.Privacy;
using StarBridge.NativeBridge;
using System.Text.Json;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    internal Action<string, string, int?, long>? OfficialFleetDiagnostic { get; set; }
    private sealed class OfficialMemberDiagnosticState(long generation, BridgeAccountContext owner, string source)
    {
        internal readonly long Generation = generation;
        internal readonly BridgeAccountContext Owner = owner;
        internal readonly string Source = source;
        internal bool Failed;
    }
    // Two bounded active slots. Source switches retire the slot, even when a
    // later request returns to the old source. Nothing here is written to disk.
    private OfficialMemberDiagnosticState? _officialMembersDiagnostic, _officialRuntimeMembersDiagnostic;

    private void RecordOfficialDiagnostic(string stage, string code, int? status, long elapsedMs)
    {
        try { (OfficialFleetDiagnostic ?? _communities?.ReadDiagnostic ?? _privacyWriter?.PublicationDiagnostic)?.Invoke(stage, code, status, elapsedMs); }
        catch { /* Diagnostics cannot change any result or exception. */ }
    }

    private async Task<object> ObserveOfficialAnnouncement(string? stage, Func<Task<object>> read)
    {
        if (stage is null) return await read();
        using var observation = new OfficialAnnouncementReadObservation();
        try { return await read(); }
        catch (Exception error)
        {
            try { observation.Fail(error); }
            catch { /* Keep the original exception, including its type. */ }
            throw;
        }
        finally
        {
            try { RecordOfficialDiagnostic(stage, observation.Code, observation.Status, observation.ElapsedMs); }
            catch { /* Diagnostics cannot change the read. */ }
        }
    }

    private static string? OfficialAnnouncementStage(JsonElement body)
    {
        try
        {
            if (body.ValueKind == JsonValueKind.Object && body.TryGetProperty("action", out var action) &&
                action.ValueKind == JsonValueKind.String)
                return action.GetString() switch
                {
                    "announcements" => "official-announcements",
                    "announcementDetail" => "official-announcement-detail",
                    _ => null
                };
        }
        catch { /* Original request validation owns malformed input. */ }
        return null;
    }

    private async Task<object> ObserveOfficialMembers(string stage, BridgeAccountContext owner, JsonElement payload, Func<Task<object>> read)
    {
        OfficialMemberDiagnosticState? state = null;
        try
        {
            lock (_realtimeGate)
            {
                if (!_disposed && CurrentContext == owner && payload.ValueKind == JsonValueKind.Object &&
                    payload.TryGetProperty("sourceRef", out var source) && source.ValueKind == JsonValueKind.String &&
                    source.GetString() is { Length: > 0 and <= 64 } reference)
                {
                    var slot = stage == "official-members" ? _officialMembersDiagnostic : _officialRuntimeMembersDiagnostic;
                    if (slot is null || slot.Generation != Generation || slot.Owner != owner || slot.Source != reference)
                        slot = new(Generation, owner, reference);
                    if (stage == "official-members") _officialMembersDiagnostic = slot;
                    else _officialRuntimeMembersDiagnostic = slot;
                    state = slot;
                }
            }
        }
        catch { /* Invalid diagnostic keys cannot preempt the original validation. */ }
        using var observation = new OfficialMemberReadObservation();
        try { return await read(); }
        catch (Exception error) { observation.Fail(error); throw; }
        finally
        {
            var failed = observation.Code != "ok";
            var recovered = false;
            lock (_realtimeGate)
            {
                var slot = stage == "official-members" ? _officialMembersDiagnostic : _officialRuntimeMembersDiagnostic;
                if (state is not null && ReferenceEquals(state, slot) && !_disposed &&
                    state.Generation == Generation && state.Owner == CurrentContext)
                {
                    recovered = !failed && state.Failed;
                    state.Failed = failed;
                }
            }
            if (failed || recovered)
                RecordOfficialDiagnostic(stage, observation.Code, observation.Status, observation.ElapsedMs);
        }
    }
}
