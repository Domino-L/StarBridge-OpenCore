using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Privacy;

internal sealed record OfficialRealtimeCellWire(string State, string? Value, string? Confidence);
internal sealed record OfficialRealtimeMemberWire(string OwnerBusinessSubjectId, string Presence,
    OfficialRealtimeCellWire Server, OfficialRealtimeCellWire Ship, OfficialRealtimeCellWire Location,
    bool ArrivalPending, string? ArrivalTargetCode, string? ServerRegion = null,
    bool? HasServerSession = null, string? LocationHiddenReason = null);
internal sealed partial class PrivacyRelayWriter
{
    internal async Task<IReadOnlyDictionary<string,OfficialRealtimeMemberWire>> ReadOfficialRuntimeAsync(
        string bearer, string sourceRef, IReadOnlyList<string> subjects, CancellationToken token, Action current)
    {
        if (subjects.Count > 100 || subjects.Distinct(StringComparer.Ordinal).Count() != subjects.Count) throw Invalid();
        using var request = Request(HttpMethod.Post, OfficialUri("read"), bearer);
        request.Content = JsonContent.Create(new { schemaVersion = 4, sourceRef, ownerBusinessSubjectIds = subjects });
        current();
        AccountReadTiming.Checkpoint(MemberReadCheckpoint.Relay);
        OfficialMemberReadObservation.Sending();
        using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
        OfficialMemberReadObservation.Response(response.StatusCode);
        RequireSuccess(response); using var document = await ReadAsync(response, token);
        current();
        AccountReadTiming.Checkpoint(MemberReadCheckpoint.Relay);
        var root = document.RootElement;
        try {
            if (root.EnumerateObject().Count() != 7 || root.GetProperty("schemaVersion").GetInt32() != 4 || root.GetProperty("sourceRef").GetString() != sourceRef ||
                root.GetProperty("coverage").GetString() != "requestedOwners" || root.GetProperty("requestedOwnerCount").GetInt32() != subjects.Count ||
                root.GetProperty("members").GetArrayLength() != subjects.Count ||
                !root.GetProperty("supportedFilters").EnumerateArray().Select(x => x.GetString()).SequenceEqual(new[] { "all" })) throw Invalid();
            var capabilities = root.GetProperty("runtimeCapabilities");
            if (capabilities.EnumerateObject().Count() != 6 || new[] { "presence", "server", "ship", "location" }.Any(k => !capabilities.GetProperty(k).GetBoolean()) ||
                capabilities.GetProperty("onlineCount").GetBoolean() || capabilities.GetProperty("inGameCount").GetBoolean()) throw Invalid();
            var result = new Dictionary<string,OfficialRealtimeMemberWire>(StringComparer.Ordinal);
            foreach (var raw in root.GetProperty("members").EnumerateArray()) {
                if (raw.EnumerateObject().Count() != 10) throw Invalid();
                var member = raw.Deserialize<OfficialRealtimeMemberWire>(LocalPrivacyStore.Json);
                if (member is null || !subjects.Contains(member.OwnerBusinessSubjectId, StringComparer.Ordinal) ||
                    member.Presence is not ("offline" or "online" or "away" or "inGame") || !result.TryAdd(member.OwnerBusinessSubjectId, member)) throw Invalid();
                foreach (var cell in new[] { member.Server, member.Ship, member.Location }) {
                    if (cell is null || cell.State is not ("value" or "unknown" or "notShared" or "notInGame") ||
                        (cell.State == "value" ? string.IsNullOrWhiteSpace(cell.Value) || cell.Value.Length > 512 || cell.Value.Any(char.IsControl) : cell.Value is not null)) throw Invalid();
                }
                bool Bounded(string? value, int max) => value is null || value.Length <= max && !value.Any(char.IsControl);
                if (!Bounded(member.ServerRegion, 32) || !Bounded(member.ArrivalTargetCode, 512) ||
                    member.LocationHiddenReason is not (null or "lowConfidence") ||
                    member.Server.State == "notShared" && (member.ServerRegion is not null || member.HasServerSession is not null) ||
                    member.Location.State == "notShared" && (member.ArrivalPending || member.ArrivalTargetCode is not null || member.LocationHiddenReason is not null)) throw Invalid();
                if (member.Presence != "inGame" && (member.Server.State != "notInGame" || member.Ship.State != "notInGame" ||
                    member.Location.State != "notInGame" || member.ArrivalPending || member.ArrivalTargetCode is not null ||
                    member.ServerRegion is not null || member.HasServerSession is not null || member.LocationHiddenReason is not null)) throw Invalid();
            }
            return result;
        } catch (Exception error) when (error is JsonException or InvalidOperationException or KeyNotFoundException or FormatException) { throw Invalid(); }
    }
}
