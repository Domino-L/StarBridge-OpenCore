namespace StarBridge.HostRuntime.Overlay;

using System.Text.Json;
using StarBridge.NativeBridge;

public sealed partial class OverlayBridgeDispatcher
{
    private string[] BoundedAppearanceProgressIds()
    {
        if (_runtime is not IInformationOverlayAppearanceProgressCatalog progress ||
            _runtime is not IInformationOverlayAppearanceCatalog catalog) return [];
        var ids = progress.GetAppearanceProgressIds();
        if (ids.Count > 8 || ids.Distinct(StringComparer.Ordinal).Count() != ids.Count ||
            ids.Any(id => string.IsNullOrEmpty(id) || id.Length > 64 || id.Any(c => !char.IsAsciiLetterOrDigit(c) && c is not ('_' or '-')))) return [];
        var profiles = catalog.GetAppearances();
        return ids.Where(id => profiles.Any(profile => profile.Id == id)).ToArray();
    }
    private async ValueTask<BridgeDispatchBatch> DispatchAppearanceProgressAsync(
        BridgeEnvelope request, CancellationToken cancellationToken)
    {
        try
        {
            Validate(request);
            RejectUnknown(request.Payload, "schemaVersion", "appearanceId");
            if (!request.Payload.TryGetProperty("appearanceId", out var id) ||
                id.ValueKind != JsonValueKind.String || id.GetString() is not { Length: > 0 and <= 64 } appearance ||
                _runtime is not IInformationOverlayAppearanceCatalog catalog ||
                !catalog.GetAppearances().Any(profile => profile.Id == appearance) ||
                !BoundedAppearanceProgressIds().Contains(appearance, StringComparer.Ordinal) ||
                _runtime is not IInformationOverlayAppearanceProgressCatalog progress)
                throw new BridgeProtocolException(BridgeErrorCodes.CapabilityUnavailable, "Appearance collection is unavailable.");
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            deadline.CancelAfter(TimeSpan.FromSeconds(6));
            var value = await progress.ReadAppearanceProgressAsync(appearance, deadline.Token).AsTask().WaitAsync(deadline.Token);
            cancellationToken.ThrowIfCancellationRequested();
            if (_disposed || request.SessionGeneration != _generation())
                throw new BridgeStaleGenerationException(request.SessionGeneration, _generation());
            if (value is not { } payload || !ValidAppearanceProgress(payload, appearance))
                throw new BridgeProtocolException(BridgeErrorCodes.CapabilityUnavailable, "Appearance collection is unavailable.");
            return new(BridgeEnvelope.Response(request, payload.Clone(), preserveRequestAccountContext: false), []);
        }
        catch (BridgeProtocolException error) { return Error(request, error.Code); }
        catch (OperationCanceledException) { return new(BridgeEnvelope.CancelledResponse(request), []); }
        catch { return Error(request, "overlay.appearance_progress_unavailable", true); }
    }

    private static bool ValidAppearanceProgress(JsonElement value, string appearance)
    {
        const long max = 9_007_199_254_740_991; // Exact across the Bridge's integer representations.
        static bool Exact(JsonElement obj, params string[] names) => obj.ValueKind == JsonValueKind.Object &&
            obj.EnumerateObject().Count() == names.Length &&
            obj.EnumerateObject().Select(p => p.Name).Distinct(StringComparer.Ordinal).Count() == names.Length &&
            obj.EnumerateObject().All(p => names.Contains(p.Name, StringComparer.Ordinal));
        static bool Label(JsonElement obj) => Exact(obj, "zhCN", "zhTW", "en") &&
            obj.EnumerateObject().All(p => p.Value.ValueKind == JsonValueKind.String && p.Value.GetString() is { Length: > 0 and <= 128 });
        static bool Number(JsonElement obj, out long number) => obj.TryGetInt64(out number) && number >= 0 && number <= max;
        if (System.Text.Encoding.UTF8.GetByteCount(value.GetRawText()) > 12 * 1024 ||
            !Exact(value, "schemaVersion", "appearanceId", "state", "confirmedUsageMs", "items") ||
            !value.GetProperty("schemaVersion").TryGetInt32(out var version) || version != 1 ||
            value.GetProperty("appearanceId").GetString() != appearance ||
            value.GetProperty("state").GetString() is not ("ready" or "signedOut" or "accountSyncPending" or "waitingAcknowledgement" or "anotherSession" or "unavailable" or "authenticationRequired" or "resyncRequired")) return false;
        var usage = value.GetProperty("confirmedUsageMs");
        long? total = usage.ValueKind == JsonValueKind.Null ? null : Number(usage, out var known) ? known : -1;
        if (total < 0 || value.GetProperty("state").GetString() is "signedOut" or "authenticationRequired" && total is not null) return false;
        var items = value.GetProperty("items");
        if (items.ValueKind != JsonValueKind.Array || items.GetArrayLength() is < 1 or > 16) return false;
        var ids = new HashSet<string>(StringComparer.Ordinal);
        foreach (var item in items.EnumerateArray())
        {
            if (!Exact(item, "id", "label", "requiredUsageMs", "remainingMs", "owned") ||
                item.GetProperty("id").ValueKind != JsonValueKind.String || item.GetProperty("id").GetString() is not { Length: > 0 and <= 64 } key ||
                key.Any(c => !char.IsAsciiLetterOrDigit(c) && c is not ('_' or '-')) || !ids.Add(key) ||
                !Label(item.GetProperty("label")) || !Number(item.GetProperty("requiredUsageMs"), out var required) ||
                item.GetProperty("owned").ValueKind is not (JsonValueKind.True or JsonValueKind.False)) return false;
            var owned = required == 0 || total >= required;
            var remaining = required == 0 ? 0L : total is { } time ? Math.Max(0, required - time) : (long?)null;
            var input = item.GetProperty("remainingMs");
            if (item.GetProperty("owned").GetBoolean() != owned ||
                (remaining is null ? input.ValueKind != JsonValueKind.Null : !Number(input, out var number) || number != remaining)) return false;
        }
        return true;
    }
}
