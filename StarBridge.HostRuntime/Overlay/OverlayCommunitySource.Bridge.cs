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
            _revision++; // An older roster response must not restore the old name.
            _catalog = _catalog.Select(row => row.Code == code ? row with { Name = name } : row).ToArray();
            if (_content?.Code == code) _content = _content with { Name = name };
        }
    }
    internal string Mode { get { lock (_sync) { CheckScope(); return _scope.Owner is null ? "unavailable" : _choice.Mode; } } }

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
                if (!force && _choiceStore is not null && _catalogAt != default && _now() - _catalogAt < TimeSpan.FromSeconds(30)) return _catalog;
                catalogRevision = _catalogRevision;
            }
            var targets = await _reader.ReadTargetsAsync(scope.Owner!, token).ConfigureAwait(false);
            lock (_sync)
            {
                CheckScope();
                if (_disposed || scope != _scope) throw new OperationCanceledException();
                if (catalogRevision != _catalogRevision) return _catalog;
                _catalog = targets.ToArray(); _catalogAt = _now();
                if (_content is not null && !_catalog.Any(x => x.Code == _content.Code)) _content = null;
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
            BridgeEnvelopeValidator.ValidateWireShape(request);
            BridgeEnvelopeValidator.RequireCurrentVersion(request);
            var scope = _owner();
            if (_disposed || scope.Owner is null || request.AccountContext != scope.Owner ||
                request.SessionGeneration != scope.Generation || request.MessageType != BridgeMessageTypes.Request)
                return Error(request, "identityUnavailable");
            var body = request.Payload;
            var write = request.Name == SelectRequest;
            var focus = request.Name == FocusRequest;
            string[] allowed = write ? ["schemaVersion", "revision", "mode", "code"] : focus ? ["schemaVersion", "code"] : ["schemaVersion"];
            var names = body.EnumerateObject().Select(x => x.Name).ToArray();
            if (request.Name is not (ReadRequest or SelectRequest or FocusRequest) || body.GetProperty("schemaVersion").GetInt32() != 1 ||
                (write ? names.Length is < 3 or > 4 : names.Length != (focus ? 2 : 1)) || names.Distinct().Count() != names.Length || names.Except(allowed).Any())
                return Error(request, "invalidRequest");
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token, _stop.Token);
            deadline.CancelAfter(TimeSpan.FromSeconds(20));
            await _choiceGate.WaitAsync(deadline.Token); entered = true;
            // Local automatic/room choices remain writable even if directory reads fail.
            // A specific organization always needs a fresh authorization check.
            var selectingCommunity = write && body.GetProperty("mode").GetString() == "community";
            var catalogFailed = false;
            if (!write || selectingCommunity)
            {
                try { await CatalogAsync(scope, selectingCommunity, deadline.Token).ConfigureAwait(false); }
                catch (Exception e) when (!write && !token.IsCancellationRequested && !_stop.IsCancellationRequested &&
                    e is Account.AccountBridgeHostException or OperationCanceledException)
                { catalogFailed = true; }
            }
            lock (_sync)
            {
                CheckScope();
                if (_disposed || scope != _scope) return Error(request, "identityUnavailable");
                if (_choiceFailed) return Error(request, "storage_unavailable");
                if (focus)
                {
                    var code = body.GetProperty("code").GetString();
                    if (!OverlaySceneChoiceStore.Valid("community", code)) return Error(request, "invalidRequest");
                    if (catalogFailed || !_catalog.Any(x => x.Code == code)) return Error(request, "targetUnavailable");
                    if (_pageCode != code)
                    {
                        _pageCode = code;
                        // Navigation is transient, never a persisted manual choice.
                        // Manual scenes and their in-flight reads remain untouched.
                        if (_choice.Mode == "auto")
                        {
                            _revision++;
                            _content = null;
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
                    _choice = saved; _explicitCode = code; _revision++; _content = null;
                    if (_lastDemand is not null && _wake.CurrentCount == 0) _wake.Release();
                }
                var content = Read();
                var room = _room();
                var actual = _choice.Mode == "room" ? room is null ? null : "room" :
                    _choice.Mode == "auto" && room is not null ? "room" : content is not null ? "org:" + content.Code : null;
                var status = actual is not null ? "ready" : catalogFailed || _catalogAt == default ? "unavailable" : _choice.Mode == "auto" && _catalog.Count == 0 ? "local" :
                    _choice.Mode == "room" || _choice.Mode == "community" && !_catalog.Any(x => x.Code == _choice.Code)
                        ? "unavailable" : _lastDemand is null || _now() - _lastDemand > TimeSpan.FromSeconds(20) ? "standby" : "loading";
                return new(BridgeEnvelope.Response(request, new { schemaVersion = 1, revision = _choice.Revision,
                    mode = _choice.Mode, code = _choice.Code, actualId = actual, status,
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
