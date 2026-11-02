namespace StarBridge.HostRuntime.Overlay;

using System.Text.Json;
using StarBridge.Core.Overlay;
using StarBridge.NativeBridge;

public sealed partial class OverlayBridgeDispatcher
{
    private string[] BoundedLivePreviewIds()
    {
        if (_runtime is not IInformationOverlayAppearancePreviewRuntime preview ||
            _runtime is not IInformationOverlayAppearanceCatalog catalog) return [];
        var ids = preview.GetLivePreviewAppearanceIds();
        if (ids.Count > 8 || ids.Distinct(StringComparer.Ordinal).Count() != ids.Count ||
            ids.Any(id => string.IsNullOrEmpty(id) || id.Length > 64 || id.Any(c => !char.IsAsciiLetterOrDigit(c) && c != '_' && c != '-'))) return [];
        var profiles = catalog.GetAppearances();
        return ids.Where(id => profiles.Any(p => p.Id == id && (p.IsPreviewAvailable ?? p.IsReleased))).ToArray();
    }

    private async Task<BridgeEnvelope> OpenAppearancePreviewAsync(BridgeEnvelope request, CancellationToken cancellationToken)
    {
        RejectUnknown(request.Payload, "schemaVersion", "appearanceId", "appearanceOptions", "reduceMotion");
        if (!request.Payload.TryGetProperty("appearanceId", out var id) || id.ValueKind != JsonValueKind.String ||
            !request.Payload.TryGetProperty("appearanceOptions", out var values))
            throw new BridgeProtocolException(BridgeErrorCodes.InvalidEnvelope, "Invalid appearance preview.");
        OverlayAppearanceOptions options;
        try { options = OverlayAppearanceOptions.Parse(values.GetRawText()); }
        catch (FormatException) { throw new BridgeProtocolException(BridgeErrorCodes.InvalidEnvelope, "Invalid appearance preview options."); }
        var appearance = id.GetString()!;
        if (!BoundedLivePreviewIds().Contains(appearance, StringComparer.Ordinal) ||
            _runtime is not IInformationOverlayAppearancePreviewRuntime preview)
            throw new BridgeProtocolException(BridgeErrorCodes.CapabilityUnavailable, "Appearance preview is unavailable.");
        var reduced = request.Payload.TryGetProperty("reduceMotion", out var motion);
        if (reduced && motion.ValueKind is not (JsonValueKind.True or JsonValueKind.False))
            throw new BridgeProtocolException(BridgeErrorCodes.InvalidEnvelope, "Invalid appearance preview motion.");
        var session = await preview.OpenAppearancePreviewAsync(appearance, options, reduced && motion.GetBoolean(), cancellationToken);
        if (session is null || !Guid.TryParseExact(session, "N", out _))
            throw new OverlaySettingsException("overlay.appearance_preview_unavailable", true);
        if (request.SessionGeneration != _generation() || cancellationToken.IsCancellationRequested)
        {
            await preview.CloseAppearancePreviewAsync(session, CancellationToken.None);
            cancellationToken.ThrowIfCancellationRequested();
            throw new BridgeStaleGenerationException(request.SessionGeneration, _generation());
        }
        return BridgeEnvelope.Response(request, new { schemaVersion = 1, sessionId = session }, preserveRequestAccountContext: false);
    }

    private async Task<BridgeEnvelope> CloseAppearancePreviewAsync(BridgeEnvelope request, CancellationToken cancellationToken)
    {
        RejectUnknown(request.Payload, "schemaVersion", "sessionId");
        if (!request.Payload.TryGetProperty("sessionId", out var id) || id.ValueKind != JsonValueKind.String ||
            !Guid.TryParseExact(id.GetString(), "N", out _))
            throw new BridgeProtocolException(BridgeErrorCodes.InvalidEnvelope, "Invalid appearance preview session.");
        if (_runtime is IInformationOverlayAppearancePreviewRuntime preview)
            await preview.CloseAppearancePreviewAsync(id.GetString()!, cancellationToken);
        return BridgeEnvelope.Response(request, new { schemaVersion = 1, closed = true }, preserveRequestAccountContext: false);
    }
}
