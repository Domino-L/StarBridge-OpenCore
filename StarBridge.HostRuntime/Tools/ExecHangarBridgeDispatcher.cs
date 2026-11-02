using System.Text.Json;
using StarBridge.Core.Tools;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Tools;

public sealed class ExecHangarBridgeDispatcher(ExecHangarRuntime runtime, Func<long> generation,
    ExecHangarGameOverlay? gameOverlay = null) : IBridgeRequestDispatcher
{
    public static IReadOnlyList<string> Capabilities { get; } = ["execHangar.read", "execHangar.refresh", "execHangar.save",
        "execHangar.start", "execHangar.continuous", "execHangar.stop", "execHangar.extend", "execHangar.addHour", "execHangar.restore", "execHangar.preview", "execHangar.test",
        "execHangar.gameOverlay.read", "execHangar.gameOverlay.pin", "execHangar.gameOverlay.unpin"];
    public event Action<BridgeEnvelope>? EventReady { add { } remove { } }
    public async ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken cancellationToken = default)
    {
        try {
            BridgeEnvelopeValidator.ValidateWireShape(request); BridgeEnvelopeValidator.RequireCurrentVersion(request);
            if (request.SessionGeneration != generation()) return Error(request, "stale_generation");
            if (request.MessageType != "request" || request.AccountContext != null || !Capabilities.Contains(request.Name))
                return Error(request, "invalid_request");
            if (request.Name.StartsWith("execHangar.gameOverlay.", StringComparison.Ordinal))
            {
                var pin = request.Name == "execHangar.gameOverlay.pin";
                var overlayFields = request.Payload.EnumerateObject().Select(p => p.Name).ToArray();
                string[] allowed = pin ? ["schemaVersion", "position"] : ["schemaVersion"];
                if (overlayFields.Length != allowed.Length || overlayFields.Distinct().Count() != allowed.Length ||
                    overlayFields.Except(allowed).Any() || request.Payload.GetProperty("schemaVersion").GetInt32() != 1)
                    return Error(request, "invalid_request");
                if (gameOverlay is null) return Error(request, "unavailable");
                var position = pin ? request.Payload.GetProperty("position").GetString() : null;
                if (pin && (position is null || !ExecHangarGameOverlay.Positions.Contains(position))) return Error(request, "invalid_request");
                cancellationToken.ThrowIfCancellationRequested();
                var state = request.Name == "execHangar.gameOverlay.read" ? gameOverlay.Read()
                    : gameOverlay.Change(position, () => !cancellationToken.IsCancellationRequested && request.SessionGeneration == generation());
                if (request.SessionGeneration != generation()) { gameOverlay.Read(); return Error(request, "stale_generation"); }
                return new(BridgeEnvelope.Response(request, state, preserveRequestAccountContext: false), []);
            }
            var save = request.Name == "execHangar.save";
            var preview = request.Name == "execHangar.preview";
            var command = request.Name is "execHangar.start" or "execHangar.continuous" or "execHangar.stop" or "execHangar.extend" or "execHangar.addHour" or "execHangar.restore";
            string[] fields = save ? ["schemaVersion", "expectedRevision", "enabled", "onOpen", "beforeOpen", "beforeOpenMinutes", "beforeChange", "beforeChangeMinutes",
                "beforeClose", "beforeCloseMinutes", "onClose"] : preview
                ? ["schemaVersion", "durationMinutes", "onlyNext", "enabled", "onOpen", "beforeOpen", "beforeOpenMinutes", "beforeChange", "beforeChangeMinutes", "beforeClose", "beforeCloseMinutes", "onClose"] : request.Name == "execHangar.start"
                ? ["schemaVersion", "expectedRevision", "durationMinutes", "onlyNext"] : command ? ["schemaVersion", "expectedRevision"] : ["schemaVersion"];
            var body = request.Payload; var names = body.EnumerateObject().Select(p => p.Name).ToArray();
            if ((save || preview) && names.Contains("leaveWarning")) fields = [.. fields, "leaveWarning"];
            if ((save || preview) && names.Contains("autoDuringGame")) fields = [.. fields, "autoDuringGame"];
            if (names.Length != fields.Length || names.Distinct().Count() != fields.Length || names.Except(fields).Any() ||
                body.GetProperty("schemaVersion").GetInt32() != 1) return Error(request, "invalid_request");
            ExecHangarReminders Rules() => new(body.GetProperty("enabled").GetBoolean(),
                body.GetProperty("onOpen").GetBoolean(), body.GetProperty("beforeOpen").GetBoolean(),
                body.GetProperty("beforeOpenMinutes").GetInt32(), body.GetProperty("beforeChange").GetBoolean(),
                body.GetProperty("beforeChangeMinutes").GetInt32(), body.GetProperty("beforeClose").GetBoolean(),
                body.GetProperty("beforeCloseMinutes").GetInt32(), body.GetProperty("onClose").GetBoolean(),
                body.TryGetProperty("leaveWarning", out var leave) && leave.GetBoolean(),
                body.TryGetProperty("autoDuringGame", out var auto) && auto.GetBoolean());
            var snapshot = preview ? await runtime.PreviewAsync(Rules(), body.GetProperty("durationMinutes").GetInt32(), body.GetProperty("onlyNext").GetBoolean(), cancellationToken)
                : request.Name == "execHangar.test" ? await runtime.TestAsync(() => request.SessionGeneration == generation(), cancellationToken)
                : save ? await runtime.SaveAsync(Rules(), body.GetProperty("expectedRevision").GetInt32(),
                () => request.SessionGeneration == generation(), cancellationToken)
                : command ? await runtime.MonitorAsync(request.Name[11..], body.GetProperty("expectedRevision").GetInt32(),
                    request.Name == "execHangar.start" ? body.GetProperty("durationMinutes").GetInt32() : 0,
                    request.Name == "execHangar.start" && body.GetProperty("onlyNext").GetBoolean(),
                    () => request.SessionGeneration == generation(), cancellationToken)
                : await runtime.ReadAsync(request.Name == "execHangar.refresh", cancellationToken);
            if (request.SessionGeneration != generation()) return Error(request, "stale_generation");
            return new(BridgeEnvelope.Response(request, snapshot, preserveRequestAccountContext: false), []);
        } catch (ExecHangarConflictException) { return Error(request, "conflict"); }
        catch (OperationCanceledException) { return new(BridgeEnvelope.CancelledResponse(request), []); }
        catch (BridgeProtocolException e) { return new(BridgeEnvelope.ErrorResponse(request, new(e.Code, "Hangar request rejected.")), []); }
        catch (Exception e) when (e is JsonException or ArgumentException or InvalidOperationException or KeyNotFoundException or OverflowException) { return Error(request, "invalid_request"); }
        catch { return Error(request, "unavailable"); }
    }
    private static BridgeDispatchBatch Error(BridgeEnvelope request, string code) => new(
        BridgeEnvelope.ErrorResponse(request, new("execHangar." + code, "Hangar tool unavailable.", true)), []);
    public void Dispose() { } // Runtime belongs to the Host lifecycle.
}
