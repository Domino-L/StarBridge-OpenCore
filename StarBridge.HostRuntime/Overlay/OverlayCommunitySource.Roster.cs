using System.Text.Json;
using StarBridge.Core.Overlay;
using StarBridge.NativeBridge;
namespace StarBridge.HostRuntime.Overlay;

internal sealed partial class OverlayCommunitySource
{
    internal InformationOverlayRosterPreferences RosterPreferences
    { get { lock (_sync) { CheckScope(); return _scope.Owner is null || _choiceFailed ? InformationOverlayRosterPreferences.Empty : _choice.Roster; } } }

    private sealed record EditorRoster(OverlayCommunitySource Source,
        (BridgeAccountContext? Owner, long Generation) Scope, long Revision, long CatalogRevision,
        OverlayCommunityTarget Target, InformationOverlayCommunityContent Content);

    // Called under this source's lock, both after the await and when building rows.
    private InformationOverlayCommunityContent? CurrentEditorRoster(EditorRoster? read) =>
        read is not null && ReferenceEquals(read.Source, this) && Current(read.Scope, read.Revision) &&
        _catalogRevision == read.CatalogRevision && read.Content.Code == read.Target.Code &&
        _catalog.Any(target => target.Code == read.Target.Code && target.Reference == read.Target.Reference) &&
        (!_isFleetSession || !_fleetNotMember && (_fleetReference is null || _fleetReference == read.Target.Reference))
            ? read.Content : null;

    private (string Key, string Name)[] RosterCandidates(EditorRoster? editorRoster = null)
    {
        // Module sources: offer the people the member module can actually show,
        // not the legacy account-level selection (which may hold no roster at all).
        if (ModuleMembersTarget() is { } target)
        {
            if (target.Room) return _room()?.Members.Where(m => m.PreferenceKey is not null)
                .Select(m => (m.PreferenceKey!, m.Callsign)).DistinctBy(m => m.Item1).ToArray() ?? [];
            if (target.Code is null)
            {
                if (_fleetSource is not { } fleet) return [];
                lock (fleet._sync)
                {
                    var fleetRoster = fleet.Read() ?? fleet.CurrentEditorRoster(editorRoster);
                    return fleetRoster?.Members.Where(m => m.PreferenceKey is not null)
                        .Select(m => (m.PreferenceKey!, m.Callsign)).DistinctBy(m => m.Item1).ToArray() ?? [];
                }
            }
            var roster = FreshModuleRoster(target.Code) ??
                (editorRoster?.Target.Code == target.Code ? CurrentEditorRoster(editorRoster) : null);
            return roster?.Members.Where(m => m.PreferenceKey is not null)
                .Select(m => (m.PreferenceKey!, m.Callsign)).DistinctBy(m => m.Item1).ToArray() ?? [];
        }
        var room = _room();
        if (_choice.Mode is "auto" or "room" && room is not null)
            return room.Members.Where(m => m.PreferenceKey is not null)
                .Select(m => (m.PreferenceKey!, m.Callsign)).DistinctBy(m => m.Item1).ToArray();
        if (_choice.Mode == "room") return [];
        return ReadForDisplay()?.Members.Where(m => m.PreferenceKey is not null)
            .Select(m => (m.PreferenceKey!, m.Callsign)).DistinctBy(m => m.Item1).ToArray() ?? [];
    }

    // The binding the member module follows, resolved like the display resolver
    // but without leases. Null outside module mode or when it shows only local data.
    private (bool Room, string? Code)? ModuleMembersTarget()
    {
        if (!UsesModuleSources() || _moduleDemand() is not { Sources: { } preset } demand || _scope.Owner is not { } owner) return null;
        var key = OverlaySceneChoiceStore.Hash(owner);
        var module = preset.Modules.GetValueOrDefault(OverlaySourceModule.Members, OverlaySourceBinding.Follow);
        var binding = module.Mode != OverlaySourceMode.None ? module
            : demand.TemporarySource?.ForScope(key, _scope.Generation)
              ?? (preset.Binding.Mode != OverlaySourceMode.None ? preset.Binding : _choice.Mode switch
              {
                  "auto" => OverlaySourceBinding.Automatic,
                  "room" => new(OverlaySourceMode.Room),
                  "fleet" => new(OverlaySourceMode.Fleet),
                  "community" => new(OverlaySourceMode.Community, _choice.Code, key),
                  _ => null
              });
        switch (binding?.Mode)
        {
            case OverlaySourceMode.Fleet:
                return (false, null);
            case OverlaySourceMode.Room:
                return (true, null);
            case OverlaySourceMode.Community when binding.OwnerKey == key && binding.CommunityCode is { } code:
                return (false, code);
            case OverlaySourceMode.Auto when _room() is not null:
                return (true, null);
            case OverlaySourceMode.Auto when _pageFleet:
                return (false, null);
            case OverlaySourceMode.Auto when _focusedModuleCommunity is { } focused:
                return (false, focused);
            default:
                return null;
        }
    }

    private InformationOverlayCommunityContent? FreshModuleRoster(string code)
    {
        if (_moduleSessions.TryGetValue(code, out var session)) return session.Source.Read();
        if (!WantsFleet && Read() is { } selected && selected.Code == code) return selected;
        return _workspaceRosters.TryGetValue(code, out var roster) && _now() < roster.AcceptedAt.AddSeconds(40) ? roster.Content : null;
    }

    // When the member module's organization roster has lapsed (HUD closed, game
    // not running), read it once for this editor. The result only lists names;
    // it is not stored and grants no display lease.
    private async Task<EditorRoster?> ReadEditorRosterAsync(BridgeEnvelope request, CancellationToken token)
    {
        (BridgeAccountContext? Owner, long Generation) scope;
        string? code;
        bool fleetRequested;
        lock (_sync)
        {
            CheckScope();
            scope = _scope;
            fleetRequested = ModuleMembersTarget() is { Room: false, Code: null } && _fleetSource?.Read() is null;
            code = ModuleMembersTarget() is { Room: false, Code: { } target } && FreshModuleRoster(target) is null ? target : null;
        }
        // Only for the current account and session; the request is fully validated afterwards.
        if (code is null && !fleetRequested || scope.Owner is null || request.AccountContext != scope.Owner ||
            request.SessionGeneration != scope.Generation) return null;
        try
        {
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token, _stop.Token);
            deadline.CancelAfter(TimeSpan.FromSeconds(10));
            var source = fleetRequested ? _fleetSource : this;
            return source is null ? null : await source.ReadEditorRosterFromSourceAsync(scope,
                fleetRequested ? FleetId : code!, deadline.Token).ConfigureAwait(false);
        }
        catch (Exception error) when (error is OperationCanceledException or IOException or InvalidDataException or HttpRequestException ||
                                      IsTransientReadFailure(error) || error is Account.AccountBridgeHostException)
        { return null; }
    }

    private async Task<EditorRoster?> ReadEditorRosterFromSourceAsync(
        (BridgeAccountContext? Owner, long Generation) scope, string code, CancellationToken token)
    {
        var target = (await CatalogAsync(scope, false, token).ConfigureAwait(false)).SingleOrDefault(t => t.Code == code);
        if (target is null) return null;
        long revision, catalogRevision;
        lock (_sync)
        {
            CheckScope();
            if (_disposed || _scope != scope || !_catalog.Contains(target)) return null;
            revision = _revision; catalogRevision = _catalogRevision;
        }
        var roster = await _reader.ReadRosterAsync(scope.Owner!, target, token).ConfigureAwait(false);
        token.ThrowIfCancellationRequested();
        lock (_sync)
        {
            var read = new EditorRoster(this, scope, revision, catalogRevision, target, roster);
            return CurrentEditorRoster(read) is null ? null : read;
        }
    }

    internal async ValueTask<BridgeDispatchBatch> DispatchRosterAsync(BridgeEnvelope request, CancellationToken token)
    {
        await _choiceGate.WaitAsync(token);
        try
        {
            var editorRoster = request.Name is "overlayRoster.read" or "overlayRoster.update"
                ? await ReadEditorRosterAsync(request, token).ConfigureAwait(false) : null;
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
                var names = body.EnumerateObject().Select(p => p.Name).ToArray();
                // An update either sets one member's mode or the module display options.
                var displayWrite = write && names.Contains("display");
                string[] allowed = !write ? ["schemaVersion"]
                    : displayWrite ? ["schemaVersion", "revision", "display"]
                    : ["schemaVersion", "revision", "key", "mode"];
                if (names.Length != allowed.Length || names.Distinct().Count() != names.Length || names.Except(allowed).Any() ||
                    body.GetProperty("schemaVersion").GetInt32() != 1) return Error(request, "invalidRequest");
                var rows = RosterCandidates(editorRoster);
                if (displayWrite)
                {
                    if (!TryReadDisplay(body.GetProperty("display"), out var overflow, out var rowLimit, out var interval))
                        return Error(request, "invalidRequest");
                    if (body.GetProperty("revision").GetInt64() != _choice.Revision) return Error(request, "conflict");
                    _choice = _choiceStore?.Save(scope.Owner, _choice.Revision, _choice.Mode, _choice.Code,
                        () => !_disposed && _owner() == scope,
                        _choice.Roster with { Overflow = overflow, RowLimit = rowLimit, RotationIntervalSeconds = interval })
                        ?? throw new IOException("Roster store unavailable.");
                }
                else if (write)
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
                        () => !_disposed && _owner() == scope, prefs with { Pinned = pinned.ToArray(), Excluded = excluded.ToArray() })
                        ?? throw new IOException("Roster store unavailable.");
                }
                var roster = _choice.Roster;
                return new(BridgeEnvelope.Response(request, new { schemaVersion = 1, revision = _choice.Revision,
                    rows = rows.Select(row => new { key = row.Key, name = row.Name,
                        mode = roster.Excluded.Contains(row.Key) ? "exclude" : roster.Pinned.Contains(row.Key) ? "pin" : "auto" }).ToArray(),
                    display = new { overflow = roster.EffectiveOverflow, rowLimit = roster.RowLimit,
                        rotationIntervalSeconds = roster.EffectiveRotationIntervalSeconds } }), []);
            }
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { return Error(request, "storage_unavailable"); }
        catch (Exception e) when (e is JsonException or InvalidOperationException or KeyNotFoundException or FormatException or OverflowException)
        { return Error(request, "invalidRequest"); }
        finally { _choiceGate.Release(); }
    }

    // Exactly {overflow, rowLimit, rotationIntervalSeconds}; defaults are stored as their "unset" values.
    private static bool TryReadDisplay(JsonElement display, out string? overflow, out int rowLimit, out int interval)
    {
        overflow = null; rowLimit = 0; interval = 0;
        if (display.ValueKind != JsonValueKind.Object) return false;
        var names = display.EnumerateObject().Select(p => p.Name).ToArray();
        string[] expected = ["overflow", "rowLimit", "rotationIntervalSeconds"];
        if (names.Length != expected.Length || names.Except(expected).Any() || names.Distinct().Count() != names.Length) return false;
        var mode = display.GetProperty("overflow").GetString();
        overflow = mode switch { "summary" => null, "rotate" or "truncate" => mode, _ => "invalid" };
        rowLimit = display.GetProperty("rowLimit").GetInt32();
        var seconds = display.GetProperty("rotationIntervalSeconds").GetInt32();
        interval = seconds == InformationOverlayRosterPreferences.DefaultRotationIntervalSeconds ? 0 : seconds;
        return InformationOverlayRosterPreferences.ValidDisplay(overflow, rowLimit, interval);
    }
}
