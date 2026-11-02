using System.Text.Json;
using StarBridge.HostRuntime.Communities;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Hangar;

/// <summary>Native image draft only. Selection/cropping never saves or publishes an image.</summary>
internal sealed class HangarImageDraftBridge(ICommunityLogoPicker picker,
    Func<(BridgeAccountContext? Context, long Generation)> owner,
    Func<BridgeAccountContext, LocalHangarSnapshot> inventory, LocalHangarStore? store = null) : IDisposable
{
    internal static readonly string[] Requests = ["hangarImage.pick", "hangarImage.crop", "hangarImage.clear", "hangarImage.save", "hangarImage.read", "hangarImage.restore"];
    private readonly SemaphoreSlim _gate = new(1, 1);
    private readonly object _sync = new();
    private CancellationTokenSource _scope = new();
    private Draft? _draft;
    private bool _disposed;
    private sealed record Draft(BridgeAccountContext Owner, long Generation, long Revision,
        LocalHangarShip Ship, string SourceRef, string Reference, string? ImageData);
    internal sealed record PreparedImage(LocalHangarShip Ship, long Revision, string ImageData);

    internal async ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken token = default)
    {
        var entered = false;
        try
        {
            BridgeEnvelopeValidator.ValidateWireShape(request);
            BridgeEnvelopeValidator.RequireCurrentVersion(request);
            var current = owner();
            if (request.MessageType != BridgeMessageTypes.Request || current.Context is null ||
                request.AccountContext != current.Context || request.SessionGeneration != current.Generation)
                return Error(request, "hangar.account_changed");
            var body = request.Payload;
            string[] fields = request.Name switch {
                "hangarImage.pick" => ["schemaVersion", "shipId", "expectedRevision"],
                "hangarImage.crop" => ["schemaVersion", "draftRef", "x", "y", "size"],
                "hangarImage.save" => ["schemaVersion", "draftRef"],
                "hangarImage.read" => ["schemaVersion", "shipId", "expectedRevision"],
                "hangarImage.restore" => ["schemaVersion", "shipId", "expectedRevision"],
                "hangarImage.clear" => ["schemaVersion"], _ => [] };
            var names = body.EnumerateObject().Select(p => p.Name).ToArray();
            if (fields.Length == 0 || body.GetRawText().Length > 2048 || names.Length != fields.Length ||
                names.Distinct().Count() != names.Length || names.Except(fields).Any() || body.GetProperty("schemaVersion").GetInt32() != 1)
                return Error(request, "hangar.invalid_request");
            CancellationToken scope;
            lock (_sync) { if (_disposed) return Error(request, "hangar.account_changed"); scope = _scope.Token; }
            using var linked = CancellationTokenSource.CreateLinkedTokenSource(token, scope);
            entered = await _gate.WaitAsync(0, linked.Token);
            if (!entered) return Error(request, "hangar.image_busy");
            if (request.Name == "hangarImage.read")
            {
                RequireCurrent(current.Context, current.Generation, linked.Token);
                if (store is null) return Error(request, BridgeErrorCodes.CapabilityUnavailable);
                var data = store.ReadCustomImage(current.Context, body.GetProperty("expectedRevision").GetInt64(), body.GetProperty("shipId").GetString() ?? "");
                RequireCurrent(current.Context, current.Generation, linked.Token);
                return Ok(request, new { schemaVersion = 1, status = data is null ? "none" : "ready", imageData = data });
            }
            if (request.Name == "hangarImage.pick")
            {
                var revision = body.GetProperty("expectedRevision").GetInt64();
                var shipId = body.GetProperty("shipId").GetString();
                var ship = RequireShip(current.Context, revision, shipId);
                lock (_sync) { RequireCurrent(current.Context, current.Generation, linked.Token); _draft = null; picker.Clear(); }
                var source = await picker.PickAsync(linked.Token);
                lock (_sync)
                {
                    RequireCurrent(current.Context, current.Generation, linked.Token);
                    if (source is null) return Ok(request, new { schemaVersion = 1, status = "cancelled" });
                    if (!Guid.TryParseExact(source.SourceRef, "N", out _) || !ValidImage(source.PreviewImageData) || source.Width <= 0 || source.Height <= 0)
                        throw new InvalidDataException();
                    if (RequireShip(current.Context, revision, shipId) != ship) throw new LocalHangarStoreException("hangar.revision_conflict", "Inventory changed.");
                    var reference = Guid.NewGuid().ToString("N");
                    _draft = new(current.Context, current.Generation, revision, ship, source.SourceRef, reference, null);
                    return Ok(request, new { schemaVersion = 1, status = "selected", draftRef = reference,
                        previewImageData = source.PreviewImageData, width = source.Width, height = source.Height });
                }
            }
            lock (_sync)
            {
                RequireCurrent(current.Context, current.Generation, linked.Token);
                if (request.Name == "hangarImage.clear")
                { _draft = null; picker.Clear(); return Ok(request, new { schemaVersion = 1, status = "cleared" }); }
                if (request.Name == "hangarImage.restore")
                {
                    if (store is null) return Error(request, BridgeErrorCodes.CapabilityUnavailable);
                    var restored = store.SaveCustomImage(current.Context, body.GetProperty("expectedRevision").GetInt64(),
                        "restore:" + request.CorrelationId, body.GetProperty("shipId").GetString() ?? "", null,
                        () => !_disposed && !linked.IsCancellationRequested && owner() == current);
                    _draft = null; picker.Clear();
                    return Ok(request, new { schemaVersion = 1, status = "restored", revision = restored.Revision });
                }
                var draft = RequireDraft(current.Context, current.Generation, body.GetProperty("draftRef").GetString());
                if (request.Name == "hangarImage.save")
                {
                    if (store is null) return Error(request, BridgeErrorCodes.CapabilityUnavailable);
                    if (draft.ImageData is null) return Error(request, "hangar.image_not_prepared");
                    var saved = store.SaveCustomImage(current.Context, draft.Revision, draft.Reference, draft.Ship.Id, draft.ImageData,
                        () => !_disposed && !linked.IsCancellationRequested && owner() == current);
                    _draft = null; picker.Clear();
                    return Ok(request, new { schemaVersion = 1, status = "saved", revision = saved.Revision });
                }
                var x = body.GetProperty("x").GetDouble(); var y = body.GetProperty("y").GetDouble(); var size = body.GetProperty("size").GetDouble();
                if (!double.IsFinite(x) || !double.IsFinite(y) || !double.IsFinite(size) || x is < 0 or > 1 || y is < 0 or > 1 || size is < .2 or > 1)
                    throw new InvalidDataException();
                var data = picker.Crop(draft.SourceRef, x, y, size);
                if (!ValidImage(data)) throw new InvalidDataException();
                RequireCurrent(current.Context, current.Generation, linked.Token);
                _draft = draft with { ImageData = data };
                return Ok(request, new { schemaVersion = 1, status = "prepared", draftRef = draft.Reference, previewImageData = data });
            }
        }
        catch (OperationCanceledException) { return new(BridgeEnvelope.CancelledResponse(request), []); }
        catch (LocalHangarStoreException error) { return Error(request, error.Code); }
        catch (Exception error) when (error is BridgeProtocolException or ArgumentException or InvalidOperationException or IOException or
            UnauthorizedAccessException or JsonException or KeyNotFoundException or FormatException or OverflowException)
        { return Error(request, "hangar.image_invalid"); }
        finally { if (entered) _gate.Release(); }
    }

    // Only a future explicit save action may consume this; Flutter cannot supply encoded bytes or paths.
    internal PreparedImage TakePrepared(BridgeAccountContext context, long generation, string reference)
    {
        lock (_sync)
        {
            RequireCurrent(context, generation, default);
            var draft = RequireDraft(context, generation, reference);
            if (draft.ImageData is null) throw new LocalHangarStoreException("hangar.image_not_prepared", "Image needs confirmation.");
            RequireCurrent(context, generation, default);
            _draft = null; picker.Clear();
            return new(draft.Ship, draft.Revision, draft.ImageData);
        }
    }
    private Draft RequireDraft(BridgeAccountContext context, long generation, string? reference)
    {
        var draft = _draft;
        if (draft is null || draft.Owner != context || draft.Generation != generation || draft.Reference != reference)
            throw new LocalHangarStoreException("hangar.image_draft_expired", "Image selection expired.");
        if (RequireShip(context, draft.Revision, draft.Ship.Id) != draft.Ship)
            throw new LocalHangarStoreException("hangar.revision_conflict", "Inventory changed.");
        return draft;
    }
    private LocalHangarShip RequireShip(BridgeAccountContext context, long revision, string? id)
    {
        var snapshot = inventory(context);
        if (revision < 0 || snapshot.Revision != revision)
            throw new LocalHangarStoreException("hangar.revision_conflict", "Inventory changed.");
        var matches = snapshot.Ships.Where(ship => ship.Id == id).Take(2).ToArray();
        if (matches.Length != 1) throw new LocalHangarStoreException("hangar.image_ship_unavailable", "Ship unavailable.");
        return matches[0];
    }
    private void RequireCurrent(BridgeAccountContext context, long generation, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        if (_disposed || owner() != (context, generation))
            throw new LocalHangarStoreException("hangar.account_changed", "Account changed.");
    }
    private static bool ValidImage(string data) => data is { Length: > 22 and <= 700000 } && data.StartsWith("data:image/png;base64,", StringComparison.Ordinal);
    private static BridgeDispatchBatch Ok(BridgeEnvelope request, object value) => new(BridgeEnvelope.Response(request, value), []);
    private static BridgeDispatchBatch Error(BridgeEnvelope request, string code) => new(BridgeEnvelope.ErrorResponse(request, new(code, "Hangar image request failed.")), []);
    internal void Invalidate()
    {
        lock (_sync)
        {
            if (_disposed) return;
            var previous = _scope; _scope = new(); _draft = null;
            previous.Cancel(); picker.Clear();
        }
    }
    public void Dispose()
    {
        lock (_sync) { if (_disposed) return; Invalidate(); _disposed = true; _scope.Cancel(); picker.Dispose(); }
    }
}
