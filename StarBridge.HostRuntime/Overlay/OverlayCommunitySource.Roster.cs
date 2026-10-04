using System.Text.Json;
using StarBridge.NativeBridge;
namespace StarBridge.HostRuntime.Overlay;

internal sealed partial class OverlayCommunitySource
{
    internal InformationOverlayRosterPreferences RosterPreferences
    { get { lock (_sync) { CheckScope(); return _scope.Owner is null || _choiceFailed ? InformationOverlayRosterPreferences.Empty : _choice.Roster; } } }

    private (string Key, string Name)[] RosterCandidates()
    {
        var room = _room();
        if (_choice.Mode is "auto" or "room" && room is not null)
            return room.Members.Where(m => m.PreferenceKey is not null)
                .Select(m => (m.PreferenceKey!, m.Callsign)).DistinctBy(m => m.Item1).ToArray();
        if (_choice.Mode == "room") return [];
        return ReadForDisplay()?.Members.Where(m => m.PreferenceKey is not null)
            .Select(m => (m.PreferenceKey!, m.Callsign)).DistinctBy(m => m.Item1).ToArray() ?? [];
    }

    internal async ValueTask<BridgeDispatchBatch> DispatchRosterAsync(BridgeEnvelope request, CancellationToken token)
    {
        await _choiceGate.WaitAsync(token);
        try
        {
            BridgeEnvelopeValidator.ValidateWireShape(request);
            BridgeEnvelopeValidator.RequireCurrentVersion(request);
            lock (_sync)
            {
                CheckScope();
                var scope = _scope;
                if (_disposed || scope.Owner is null || request.AccountContext != scope.Owner ||
                    request.SessionGeneration != scope.Generation || request.MessageType != BridgeMessageTypes.Request)
                    return Error(request, "identityUnavailable");
                if (_choiceFailed) return Error(request, "storage_unavailable");
                var body = request.Payload;
                if (request.Name is not ("overlayRoster.read" or "overlayRoster.update")) return Error(request, "invalidRequest");
                var write = request.Name == "overlayRoster.update";
                string[] allowed = write ? ["schemaVersion", "revision", "key", "mode"] : ["schemaVersion"];
                var names = body.EnumerateObject().Select(p => p.Name).ToArray();
                if (names.Length != allowed.Length || names.Distinct().Count() != names.Length || names.Except(allowed).Any() ||
                    body.GetProperty("schemaVersion").GetInt32() != 1) return Error(request, "invalidRequest");
                var rows = RosterCandidates();
                if (write)
                {
                    var key = body.GetProperty("key").GetString();
                    var mode = body.GetProperty("mode").GetString();
                    if (key is null || !rows.Any(row => row.Key == key) || mode is not ("auto" or "pin" or "exclude"))
                        return Error(request, "targetUnavailable");
                    if (body.GetProperty("revision").GetInt64() != _choice.Revision) return Error(request, "conflict");
                    var prefs = _choice.Roster;
                    var pinned = prefs.Pinned.Where(id => id != key).ToList();
                    var excluded = prefs.Excluded.Where(id => id != key).ToList();
                    if (mode == "pin") pinned.Add(key);
                    if (mode == "exclude") excluded.Add(key);
                    if (pinned.Count + excluded.Count > 1000) return Error(request, "invalidRequest");
                    _choice = _choiceStore?.Save(scope.Owner, _choice.Revision, _choice.Mode, _choice.Code,
                        () => !_disposed && _owner() == scope, new(pinned.ToArray(), excluded.ToArray()))
                        ?? throw new IOException("Roster store unavailable.");
                }
                return new(BridgeEnvelope.Response(request, new { schemaVersion = 1, revision = _choice.Revision,
                    rows = rows.Select(row => new { key = row.Key, name = row.Name,
                        mode = _choice.Roster.Excluded.Contains(row.Key) ? "exclude" : _choice.Roster.Pinned.Contains(row.Key) ? "pin" : "auto" }).ToArray() }), []);
            }
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { return Error(request, "storage_unavailable"); }
        catch (Exception e) when (e is JsonException or InvalidOperationException or KeyNotFoundException or FormatException or OverflowException)
        { return Error(request, "invalidRequest"); }
        finally { _choiceGate.Release(); }
    }
}
