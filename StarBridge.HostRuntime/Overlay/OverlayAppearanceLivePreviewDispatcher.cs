using System.Text.Json;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Overlay;

/// <summary>Owns finite native preview requests behind one capability. Can be
/// composed with the existing overlay dispatcher without account/UI dependencies.</summary>
public sealed class OverlayAppearanceLivePreviewDispatcher : IBridgeRequestDispatcher
{
    public const string Capability = "overlay.appearanceLivePreview";
    public const string Open = Capability + ".open", Update = Capability + ".update", Close = Capability + ".close";
    public const string Protect = Capability + ".protect";
    public const string Playback = Capability + ".playback";
    public const string Renew = Capability + ".renew";
    private readonly IInformationOverlayLivePreviewRuntime _runtime;
    private readonly Func<long> _generation;
    private readonly Func<(string? OwnerKey, long Generation)> _scope;
    private readonly Func<OverlayPreviewClientViewport?>? _clientViewport;
    private readonly Func<Func<OverlayPreviewClientViewport?>?>? _captureClientViewport;
    private readonly SemaphoreSlim _gate = new(1, 1);
    private volatile bool _disposed;
    public OverlayAppearanceLivePreviewDispatcher(IInformationOverlayLivePreviewRuntime runtime, Func<long> generation,
        Func<(string? OwnerKey, long Generation)>? scope = null,
        Func<OverlayPreviewClientViewport?>? clientViewport = null,
        Func<Func<OverlayPreviewClientViewport?>?>? captureClientViewport = null)
    {
        _runtime = runtime; _generation = generation; _scope = scope ?? (() => (null, generation()));
        _clientViewport = clientViewport;
        _captureClientViewport = captureClientViewport;
    }
    public event Action<BridgeEnvelope>? EventReady { add { } remove { } }
    public async ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken cancellationToken = default)
    {
        await _gate.WaitAsync(cancellationToken);
        try
        {
            BridgeEnvelopeValidator.ValidateWireShape(request);
            BridgeEnvelopeValidator.RequireCurrentVersion(request);
            if (_disposed || request.MessageType != BridgeMessageTypes.Request || request.AccountContext is not null ||
                request.Payload.ValueKind != JsonValueKind.Object || !request.Payload.TryGetProperty("schemaVersion", out var schema) ||
                !schema.TryGetInt32(out var version) || version != 1 || request.SessionGeneration != _generation())
                throw new FormatException("Invalid preview request.");
            object response;
            switch (request.Name)
            {
                case Open:
                    InformationOverlayLivePreviewDraft.Exact(request.Payload, "schemaVersion", "frame");
                    var draft = InformationOverlayLivePreviewDraft.Parse(request.Payload.GetProperty("frame"));
                    RequireInstalled(draft.AppearanceId);
                    var owner = _scope(); var generation = request.SessionGeneration;
                    var viewportLease = _captureClientViewport is null ? _clientViewport : _captureClientViewport();
                    if (_captureClientViewport is not null && viewportLease is null)
                        throw new OverlaySettingsException("overlay.appearance_preview_unavailable", true);
                    var scope = new InformationOverlayLivePreviewScope(generation,
                        () => !_disposed && _generation() == generation && _scope() == owner, viewportLease);
                    if (scope.HasClientViewport && scope.CurrentClientViewport() is not { IsValid: true })
                        throw new OverlaySettingsException("overlay.appearance_preview_unavailable", true);
                    var session = await _runtime.OpenLiveAppearancePreviewAsync(draft, scope, cancellationToken);
                    if (session is null || !Guid.TryParseExact(session, "N", out _))
                        throw new OverlaySettingsException("overlay.appearance_preview_unavailable", true);
                    if (!scope.IsCurrent() || cancellationToken.IsCancellationRequested)
                    {
                        await _runtime.CloseLiveAppearancePreviewAsync(session, CancellationToken.None);
                        cancellationToken.ThrowIfCancellationRequested();
                        throw new FormatException("Preview owner changed.");
                    }
                    object[] initialPlacements;
                    try {
                        initialPlacements = await ReadPlacements(session, 0, cancellationToken);
                        if (!scope.IsCurrent()) throw new FormatException("Preview owner changed.");
                    } catch {
                        await _runtime.CloseLiveAppearancePreviewAsync(session, CancellationToken.None);
                        throw;
                    }
                    response = new { schemaVersion = 1, sessionId = session, placementStates = initialPlacements };
                    break;
                case Update:
                    InformationOverlayLivePreviewDraft.Exact(request.Payload, "schemaVersion", "sessionId", "revision", "frame");
                    var updateId = Session(request.Payload);
                    if (!request.Payload.GetProperty("revision").TryGetInt64(out var revision) || revision is < 1 or > 9007199254740991)
                        throw new FormatException("Invalid preview revision.");
                    var next = InformationOverlayLivePreviewDraft.Parse(request.Payload.GetProperty("frame"));
                    RequireInstalled(next.AppearanceId);
                    var updateOwner = _scope();
                    var applied = await _runtime.UpdateLiveAppearancePreviewAsync(updateId, revision, next, cancellationToken);
                    if (request.SessionGeneration != _generation() || _scope() != updateOwner || cancellationToken.IsCancellationRequested)
                    {
                        await _runtime.CloseLiveAppearancePreviewAsync(updateId, CancellationToken.None);
                        cancellationToken.ThrowIfCancellationRequested();
                        throw new FormatException("Preview owner changed.");
                    }
                    if (applied != revision) throw new OverlaySettingsException("overlay.appearance_preview_unavailable", true);
                    object[] placements;
                    try {
                        placements = await ReadPlacements(updateId, revision, cancellationToken);
                    } catch (OperationCanceledException) {
                        // Native may have already applied this draft before the
                        // read was cancelled. Release only its captured session;
                        // the cancelled token must not suppress cleanup itself.
                        await _runtime.CloseLiveAppearancePreviewAsync(updateId, CancellationToken.None);
                        throw;
                    }
                    if (request.SessionGeneration != _generation() || _scope() != updateOwner || cancellationToken.IsCancellationRequested)
                    {
                        await _runtime.CloseLiveAppearancePreviewAsync(updateId, CancellationToken.None);
                        cancellationToken.ThrowIfCancellationRequested();
                        throw new FormatException("Preview owner changed.");
                    }
                    response = new { schemaVersion = 1, revision = applied.Value, placementStates = placements };
                    break;
                case Renew:
                    InformationOverlayLivePreviewDraft.Exact(request.Payload, "schemaVersion", "sessionId", "revision");
                    var renewId = Session(request.Payload);
                    if (!request.Payload.GetProperty("revision").TryGetInt64(out var renewRevision) ||
                        renewRevision is < 1 or > 9007199254740991)
                        throw new FormatException("Invalid preview renewal revision.");
                    var renewOwner = _scope();
                    var renewed = await _runtime.RenewLiveAppearancePreviewAsync(renewId, renewRevision, cancellationToken);
                    if (request.SessionGeneration != _generation() || _scope() != renewOwner || cancellationToken.IsCancellationRequested)
                    {
                        await _runtime.CloseLiveAppearancePreviewAsync(renewId, CancellationToken.None);
                        cancellationToken.ThrowIfCancellationRequested();
                        throw new FormatException("Preview owner changed.");
                    }
                    if (renewed != renewRevision) throw new OverlaySettingsException("overlay.appearance_preview_unavailable", true);
                    response = new { schemaVersion = 1, revision = renewed.Value };
                    break;
                case Close:
                    InformationOverlayLivePreviewDraft.Exact(request.Payload, "schemaVersion", "sessionId");
                    await _runtime.CloseLiveAppearancePreviewAsync(Session(request.Payload), cancellationToken);
                    response = new { schemaVersion = 1, closed = true };
                    break;
                case Protect:
                    InformationOverlayLivePreviewDraft.Exact(request.Payload, "schemaVersion", "sessionId", "revision", "areas");
                    var protectionId = Session(request.Payload);
                    if (!request.Payload.GetProperty("revision").TryGetInt64(out var protectionRevision) ||
                        protectionRevision is < 1 or > 9007199254740991)
                        throw new FormatException("Invalid control revision.");
                    var areaValue = request.Payload.GetProperty("areas");
                    if (areaValue.ValueKind != JsonValueKind.Array || areaValue.GetArrayLength() > 16)
                        throw new FormatException("Invalid control areas.");
                    var areas = areaValue.EnumerateArray().Select(item =>
                    {
                        InformationOverlayLivePreviewDraft.Exact(item, "x", "y", "width", "height");
                        var area = new OverlayPreviewControlArea(item.GetProperty("x").GetDouble(), item.GetProperty("y").GetDouble(),
                            item.GetProperty("width").GetDouble(), item.GetProperty("height").GetDouble());
                        if (!area.IsValid) throw new FormatException("Invalid control area.");
                        return area;
                    }).ToArray();
                    var client = _clientViewport?.Invoke();
                    if (_runtime is not IInformationOverlayLivePreviewControls controls || client is not { IsValid: true } viewport)
                        throw new OverlaySettingsException("overlay.appearance_preview_unavailable", true);
                    var protectionOwner = _scope();
                    var protectedRevision = await controls.ProtectLivePreviewControlsAsync(protectionId, protectionRevision,
                        viewport, areas, cancellationToken);
                    if (request.SessionGeneration != _generation() || _scope() != protectionOwner ||
                        cancellationToken.IsCancellationRequested)
                    {
                        await _runtime.CloseLiveAppearancePreviewAsync(protectionId, CancellationToken.None);
                        cancellationToken.ThrowIfCancellationRequested();
                        throw new FormatException("Preview owner changed.");
                    }
                    if (protectedRevision != protectionRevision) throw new OverlaySettingsException("overlay.appearance_preview_unavailable", true);
                    response = new { schemaVersion = 1, revision = protectedRevision.Value };
                    break;
                case Playback:
                    InformationOverlayLivePreviewDraft.Exact(request.Payload, "schemaVersion", "sessionId", "revision", "action");
                    var playbackId = Session(request.Payload);
                    if (!request.Payload.GetProperty("revision").TryGetInt64(out var playbackRevision) ||
                        playbackRevision is < 1 or > 9007199254740991 ||
                        request.Payload.GetProperty("action").ValueKind != JsonValueKind.String ||
                        !Enum.TryParse<OverlayAppearancePreviewPlayback>(request.Payload.GetProperty("action").GetString(), false, out var action) ||
                        !Enum.IsDefined(action) || action.ToString() != request.Payload.GetProperty("action").GetString())
                        throw new FormatException("Invalid playback intent.");
                    if (_runtime is not IInformationOverlayLivePreviewPlayback playback)
                        throw new OverlaySettingsException("overlay.appearance_preview_unavailable", true);
                    var playbackOwner = _scope();
                    var receipt = await playback.PlayLivePreviewAsync(playbackId, playbackRevision, action, cancellationToken);
                    if (request.SessionGeneration != _generation() || _scope() != playbackOwner || cancellationToken.IsCancellationRequested)
                    {
                        await _runtime.CloseLiveAppearancePreviewAsync(playbackId, CancellationToken.None);
                        cancellationToken.ThrowIfCancellationRequested();
                        throw new FormatException("Preview owner changed.");
                    }
                    if (receipt is not { } played || played.Revision != playbackRevision)
                        throw new OverlaySettingsException("overlay.appearance_preview_unavailable", true);
                    response = new { schemaVersion = 1, revision = played.Revision, accepted = played.Accepted };
                    break;
                default: throw new OverlaySettingsException("overlay.appearance_preview_unavailable");
            }
            return new(BridgeEnvelope.Response(request, response, preserveRequestAccountContext: false), []);
        }
        catch (OperationCanceledException) { return new(BridgeEnvelope.CancelledResponse(request with { AccountContext = null }), []); }
        catch (OverlaySettingsException error) { return Error(request, error.Code, error.Retryable); }
        catch (Exception error) when (error is FormatException or JsonException or InvalidOperationException or KeyNotFoundException or BridgeProtocolException)
        { return Error(request, BridgeErrorCodes.InvalidEnvelope, false); }
        catch { return Error(request, "overlay.appearance_preview_unavailable", true); }
        finally { _gate.Release(); }
    }
    private void RequireInstalled(string appearanceId)
    {
        var ids = _runtime.GetLiveAppearancePreviewIds();
        if (ids.Count > 8 || ids.Distinct(StringComparer.Ordinal).Count() != ids.Count || !ids.Contains(appearanceId, StringComparer.Ordinal))
            throw new OverlaySettingsException("overlay.appearance_preview_unavailable");
    }
    private async ValueTask<object[]> ReadPlacements(string id, long revision, CancellationToken cancellationToken)
    {
        var states = await _runtime.ReadLivePreviewPlacementStatesAsync(id, revision, cancellationToken);
        cancellationToken.ThrowIfCancellationRequested();
        if (states is null || states.Count > 12 || states.Select(s => s.SlotId).Distinct(StringComparer.Ordinal).Count() != states.Count ||
            states.Any(s => string.IsNullOrEmpty(s.SlotId) || s.SlotId.Length > 64 ||
                s.SlotId.Any(c => !char.IsAsciiLetterOrDigit(c) && c is not ('_' or '-')) ||
                s.Reason is not ("placed" or "invalid" or "module-hidden" or "module-space" or "joined-edge" or
                    "screen-edge" or "neighbor-module" or "decoration-overlap" or "interaction-space" or "observation-only")))
            throw new FormatException("Invalid placement feedback.");
        return states.Select(s => (object)new { slotId = s.SlotId, reason = s.Reason }).ToArray();
    }
    private static string Session(JsonElement payload)
    {
        var id = payload.GetProperty("sessionId");
        if (id.ValueKind != JsonValueKind.String || !Guid.TryParseExact(id.GetString(), "N", out _))
            throw new FormatException("Invalid preview session.");
        return id.GetString()!;
    }
    private static BridgeDispatchBatch Error(BridgeEnvelope request, string code, bool retryable) => new(
        BridgeEnvelope.ErrorResponse(request with { AccountContext = null }, new(code, "Appearance preview failed.", retryable)), []);
    public void Dispose() => _disposed = true;
}
