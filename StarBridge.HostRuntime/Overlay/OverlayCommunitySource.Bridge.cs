using System.Text.Json;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Overlay;

internal sealed partial class OverlayCommunitySource
{
    internal const string ReadRequest = "overlayScenes.read";
    internal const string SelectRequest = "overlayScenes.select";
    internal const string FocusRequest = "overlayScenes.focusCommunity";
    private readonly OverlaySceneChoiceStore? _choiceStore;
    private readonly Func<InformationOverlayRoomContent?> _room;
    private readonly SemaphoreSlim _catalogGate = new(1, 1);
    private readonly SemaphoreSlim _choiceGate = new(1, 1);
    private OverlaySceneChoice _choice = new();
    private bool _choiceFailed;
    private DateTimeOffset _choiceRetryAt;
    private IReadOnlyList<OverlayCommunityTarget> _catalog = [];
    private DateTimeOffset _catalogAt;
    private long _catalogRevision;

    internal void Rename(BridgeAccountContext owner, long generation, string code, string name)
    {
        lock (_sync)
        {
            CheckScope();
            if (_disposed || _scope != (owner, generation)) return;
            _catalogRevision++;
            InvalidateRead(); // An older roster response must not restore the old name.
            _catalog = _catalog.Select(row => row.Code == code ? row with { Name = name } : row).ToArray();
            if (_content?.Code == code) _content = _content with { Name = name };
        }
    }
    internal string Mode { get { lock (_sync) { CheckScope(); return _scope.Owner is null ? "unavailable" : _choice.Mode; } } }

    // Display-only name of an organization the account still belongs to, for
    // "X is unreachable". No I/O or grant; a rejected or unread directory names nothing.
    internal string? PeekCommunityName(BridgeAccountContext owner, long generation, string code)
    {
        lock (_sync)
        {
            if (_disposed || _choiceFailed || _scope != (owner, generation) || _owner() != (owner, generation) ||
                _catalogAt == default) return null;
            return _catalog.FirstOrDefault(row => row.Code == code)?.Name;
        }
    }

    private async Task<IReadOnlyList<OverlayCommunityTarget>> CatalogAsync(
        (BridgeAccountContext? Owner, long Generation) scope, bool force, CancellationToken token)
    {
        await _catalogGate.WaitAsync(token).ConfigureAwait(false);
        try
        {
            long catalogRevision;
            lock (_sync)
            {
                CheckScope();
                if (_disposed || scope != _scope) throw new OperationCanceledException();
                if (!force && (_choiceStore is not null || _isFleetSession) && _catalogAt != default && _now() - _catalogAt < TimeSpan.FromSeconds(30)) return _catalog;
                catalogRevision = _catalogRevision;
            }
            var targets = await _reader.ReadTargetsAsync(scope.Owner!, token).ConfigureAwait(false);
            lock (_sync)
            {
                CheckScope();
                if (_disposed || scope != _scope) throw new OperationCanceledException();
                if (catalogRevision != _catalogRevision) return _catalog;
                // A complete newer directory supersedes pending content reads
                // for removed memberships, including driver-only sources.
                if (_catalog.Any(previous => !targets.Any(next => next.Code == previous.Code))) InvalidateRead();
                _catalog = targets.ToArray(); _catalogAt = _now();
                if (_isFleetSession) _fleetNotMember = targets.Count == 0;
                foreach (var code in _workspaceRosters.Keys.Where(code => !_catalog.Any(x => x.Code == code)).ToArray())
                    RevokeWorkspace(code);
                foreach (var code in _moduleAuthorities.Keys.Where(code => !_catalog.Any(x => x.Code == code)).ToArray())
                    RevokeWorkspace(code);
                foreach (var code in _moduleSessions.Keys.Where(code => !_catalog.Any(x => x.Code == code)).ToArray())
                    RemoveModuleSession(code);
                if (_content is not null && !_catalog.Any(x => x.Code == _content.Code)) _content = null;
                DirectoryMembershipConfirmed?.Invoke(scope.Owner!, scope.Generation, _catalog.Select(t => t.Code).ToHashSet(StringComparer.Ordinal));
                return _catalog;
            }
        }
        finally { _catalogGate.Release(); }
    }

    internal async ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken token)
    {
        var entered = false;
        try
        {
            using var work = _retirement.Enter(token);
            if (work is null) return Error(request, "identityUnavailable");
            token = work.Token;
            BridgeEnvelopeValidator.ValidateWireShape(request);
            BridgeEnvelopeValidator.RequireCurrentVersion(request);
            var scope = _owner();
            if (_disposed || scope.Owner is null || request.AccountContext != scope.Owner ||
                request.SessionGeneration != scope.Generation || request.MessageType != BridgeMessageTypes.Request)
                return Error(request, "identityUnavailable");
            var body = request.Payload;
            var write = request.Name == SelectRequest;
            var focusFleet = request.Name == FocusFleetRequest;
            var focus = request.Name == FocusRequest || focusFleet;
            string[] allowed = write ? ["schemaVersion", "revision", "mode", "code"] : focus && !focusFleet ? ["schemaVersion", "code"] : ["schemaVersion"];
            var names = body.EnumerateObject().Select(x => x.Name).ToArray();
            if (request.Name is not (ReadRequest or SelectRequest or FocusRequest or FocusFleetRequest) || body.GetProperty("schemaVersion").GetInt32() != 1 ||
                (write ? names.Length is < 3 or > 4 : names.Length != (focus && !focusFleet ? 2 : 1)) || names.Distinct().Count() != names.Length || names.Except(allowed).Any())
                return Error(request, "invalidRequest");
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token, _stop.Token);
            deadline.CancelAfter(TimeSpan.FromSeconds(20));
            if (request.Name == ReadRequest || focusFleet || write && body.GetProperty("mode").GetString() == "fleet")
                await ProbeFleetAsync(scope, deadline.Token).ConfigureAwait(false);
            // Local automatic/room choices remain writable even if directory reads fail.
            // A specific organization always needs a fresh authorization check.
            var selectingCommunity = write && body.GetProperty("mode").GetString() == "community";
            var catalogFailed = false;
            if (!write || selectingCommunity)
            {
                try { await CatalogAsync(scope, selectingCommunity, deadline.Token).ConfigureAwait(false); }
                catch (Exception e) when (!write && !token.IsCancellationRequested && !_stop.IsCancellationRequested &&
                    e is Account.AccountBridgeHostException or OperationCanceledException or IOException or HttpRequestException)
                { catalogFailed = true; }
            }
            // Network authorization must not hold the local choice/roster gate.
            // Revision and scope are checked again after acquiring it.
            await _choiceGate.WaitAsync(deadline.Token); entered = true;
            lock (_sync)
            {
                CheckScope();
                if (_disposed || scope != _scope) return Error(request, "identityUnavailable");
                if (_choiceFailed) return Error(request, "storage_unavailable");
                if (focusFleet)
                {
                    _focusedModuleCommunity = null;
                    _pageCode = null;
                    _pageFleet = true;
                    if (_choice.Mode == "auto")
                    {
                        InvalidateRead(); _content = null;
                        if (_lastDemand is not null) _fleetSource?.ReadForDisplay();
                        NotifyContentChanged();
                    }
                }
                if (focus && !focusFleet)
                {
                    var code = body.GetProperty("code").GetString();
                    if (!OverlaySceneChoiceStore.Valid("community", code)) return Error(request, "invalidRequest");
                    if (catalogFailed || !_catalog.Any(x => x.Code == code)) return Error(request, "targetUnavailable");
                    _focusedModuleCommunity = code;
                    if (_pageCode != code || _pageFleet)
                    {
                        _pageFleet = false;
                        _fleetSource?.SuspendDisplayDemand();
                        _pageCode = code;
                        // Navigation is transient, never a persisted manual choice.
                        // Manual scenes and their in-flight reads remain untouched.
                        if (_choice.Mode == "auto")
                        {
                            InvalidateRead();
                            _content = null;
                            AdoptWorkspace(code);
                            if (_lastDemand is not null && _wake.CurrentCount == 0) _wake.Release();
                        }
                    }
                }
                if (write)
                {
                    var mode = body.GetProperty("mode").GetString() ?? "";
                    var code = !body.TryGetProperty("code", out var codeNode) || codeNode.ValueKind == JsonValueKind.Null ? null : codeNode.GetString();
                    var revision = body.GetProperty("revision").GetInt64();
                    if (!OverlaySceneChoiceStore.Valid(mode, code)) return Error(request, "invalidRequest");
                    if (mode == "community" && !_catalog.Any(x => x.Code == code)) return Error(request, "targetUnavailable");
                    if (_choice.Revision != revision) return Error(request, "conflict");
                    var saved = _choiceStore?.Save(scope.Owner!, revision, mode, code, () => !_disposed && _owner() == scope)
                        ?? throw new IOException("Source store unavailable.");
                    _choice = saved; _explicitCode = code; InvalidateRead(); _content = null;
                    if (!WantsFleet) _fleetSource?.SuspendDisplayDemand();
                    else if (_lastDemand is not null) _fleetSource?.ReadForDisplay();
                    if (mode == "community") _focusedModuleCommunity = code;
                    AdoptWorkspace();
                    if (_lastDemand is not null && _wake.CurrentCount == 0) _wake.Release();
                }
                var content = Read();
                var room = _room();
                var actual = _choice.Mode == "room" ? room is null ? null : "room" :
                    _choice.Mode == "auto" && room is not null ? "room" : content is not null ? WantsFleet ? "fleet" : "org:" + content.Code : null;
                var status = actual is not null ? "ready" : catalogFailed || _catalogAt == default ? "unavailable" : _choice.Mode == "auto" && _catalog.Count == 0 ? "local" :
                    _choice.Mode == "room" || _choice.Mode == "community" && !_catalog.Any(x => x.Code == _choice.Code)
                        ? "unavailable" : _lastDemand is null || _now() - _lastDemand > TimeSpan.FromSeconds(20) ? "standby" : "loading";
                var selection = ReadSourceSelection();
                if (selection is not null) { actual = selection.ActualId; status = selection.Status; }
                if (WantsFleet && actual is null) status = FleetStatus();
                return new(BridgeEnvelope.Response(request, new { schemaVersion = 1, revision = _choice.Revision,
                    mode = _choice.Mode, code = JsonSerializer.SerializeToElement(_choice.Code), actualId = actual, status,
                    fleet = new { status = FleetStatus(), name = FleetName() },
                    sourceOwnerKey = OverlaySceneChoiceStore.Hash(scope.Owner!),
                    automaticPresetSourceId = ReadPresetTrigger(catalogFailed),
                    presetBindingId = selection?.BindingId, temporarySourceId = selection?.TemporaryId,
                    resolvedSourceIds = selection?.ResolvedSourceIds,
                    organizations = _catalog.Select(x => new { code = x.Code, name = x.Name }).ToArray() }), []);
            }
        }
        catch (OperationCanceledException) { return Error(request, "read_failed"); }
        catch (Account.AccountBridgeHostException) { return Error(request, "read_failed"); }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException) { return Error(request, "storage_unavailable"); }
        catch (Exception e) when (e is JsonException or InvalidOperationException or KeyNotFoundException or FormatException or OverflowException)
        { return Error(request, "invalidRequest"); }
        finally { if (entered) _choiceGate.Release(); }
    }
    private static BridgeDispatchBatch Error(BridgeEnvelope request, string code) => new(
        BridgeEnvelope.ErrorResponse(request, new("overlayScenes." + code, "Overlay source request was not completed.", Retryable: true)), []);
}
