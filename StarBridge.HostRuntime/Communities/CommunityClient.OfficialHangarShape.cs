using System.Diagnostics;
using System.Text.Json;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Communities;

internal sealed partial class CommunityClient
{
    // Mirrors organization_hangar_sharing.dart parseOfficial/Page.parse and
    // organization_ship_image_features.dart. See the mapping in HostRuntime.Tests.
    // This probe returns the very same object; neither validation nor logging
    // is allowed to change the original projection or its exceptions.
    internal object ObserveOfficialHangarShape(object response)
    {
        var started = Stopwatch.GetTimestamp();
        var code = "unclassified";
        // Use the actual wire conversion, including camelCase/null omission;
        // inspecting a default serialization could diagnose a different shape.
        try { code = OfficialHangarShape(BridgePayload.From(response)); }
        catch { /* Includes string decoding and serialization failures. */ }
        try { ReadDiagnostic?.Invoke("official-hangar-shape", code, null, (long)Stopwatch.GetElapsedTime(started).TotalMilliseconds); }
        catch { /* Local journal failures cannot change the response. */ }
        return response;
    }

    private static string OfficialHangarShape(JsonElement row)
    {
        if (row.ValueKind != JsonValueKind.Object) return "draft-invalid";
        var images = row.TryGetProperty("imageFeatures", out var features);
        var fields = new[] { "schemaVersion", "editRef", "sourceRef", "state", "strategy", "inventoryState", "canGrant",
            "canPublish", "canReduce", "selectionKnown", "selectedCount", "maximumSelected", "selectedRefs", "scopes", "scopeRef", "page" };
        if (!ShapeFields(row, images ? fields.Concat(["imageFeatures", "imageCount", "canClearImages"]).ToArray() : fields)) return "draft-fields-invalid";
        if (!ShapeNumber(row.GetProperty("schemaVersion"), 1)) return "schema-invalid";
        var edit = row.GetProperty("editRef");
        if (!ShapeRef(edit)) return "edit-ref-invalid";
        var source = row.GetProperty("sourceRef");
        var canAct = row.GetProperty("canGrant").ValueKind == JsonValueKind.True || row.GetProperty("canReduce").ValueKind == JsonValueKind.True;
        if (canAct && source.ValueKind == JsonValueKind.String && source.GetString() == "") return "scope-missing";
        if (source.ValueKind != JsonValueKind.Null && !ShapeSource(source)) return "source-ref-invalid";
        if (!ShapeChoice(row.GetProperty("state"), "available", "selectionRequired", "stale", "unavailable", "forbidden")) return "state-invalid";
        var strategy = row.GetProperty("strategy");
        if (strategy.ValueKind != JsonValueKind.Null && !ShapeChoice(strategy, "notShared", "organizationPool", "operationOnly")) return "strategy-invalid";
        var inventory = row.GetProperty("inventoryState");
        if (!ShapeChoice(inventory, "complete", "missing", "partial", "unavailable")) return "inventory-state-invalid";
        if (!ShapeNumber(row.GetProperty("maximumSelected"), 10000)) return "maximum-selected-invalid";
        if (!ShapeInt(row.GetProperty("selectedCount"), 0, 10000, out var count)) return "selected-count-invalid";
        var selected = row.GetProperty("selectedRefs");
        if (selected.ValueKind != JsonValueKind.Array || selected.GetArrayLength() > 10000 || selected.EnumerateArray().Any(r => !ShapeRef(r))) return "selected-refs-invalid";
        if (selected.EnumerateArray().Select(r => r.GetString()).Distinct(StringComparer.Ordinal).Count() != selected.GetArrayLength()) return "selected-refs-duplicate";
        var scopes = row.GetProperty("scopes");
        if (scopes.ValueKind != JsonValueKind.Array || scopes.GetArrayLength() > 101) return "scopes-invalid";
        var scope = row.GetProperty("scopeRef");
        if (canAct && scope.ValueKind == JsonValueKind.String && scope.GetString() == "") return "scope-missing";
        if (scope.ValueKind != JsonValueKind.Null && !ShapeRef(scope)) return "scope-ref-invalid";
        if (new[] { "canGrant", "canPublish", "canReduce", "selectionKnown" }.Any(key => !ShapeBool(row.GetProperty(key)))) return "flags-invalid";
        var grant = row.GetProperty("canGrant").GetBoolean();
        var publish = row.GetProperty("canPublish").GetBoolean();
        var reduce = row.GetProperty("canReduce").GetBoolean();
        var known = row.GetProperty("selectionKnown").GetBoolean();
        var imageCount = 0;
        var imageReduce = false;
        if (images)
        {
            if (!ShapeFields(features, ["protocolVersion", "read", "upload", "report", "reduce"]) ||
                !ShapeNumber(features.GetProperty("protocolVersion"), 1) ||
                new[] { "read", "upload", "report", "reduce" }.Any(key => !ShapeBool(features.GetProperty(key)))) return "image-features-invalid";
            imageReduce = features.GetProperty("reduce").GetBoolean();
            if (!ShapeInt(row.GetProperty("imageCount"), 0, 10000, out imageCount)) return "image-count-invalid";
            var clear = row.GetProperty("canClearImages");
            if (!ShapeBool(clear) || clear.GetBoolean() && (!reduce || !imageReduce || imageCount == 0)) return "clear-images-invalid";
        }
        if (publish && (!grant || inventory.GetString() != "complete")) return "publish-without-complete";
        if ((grant || reduce) && (scope.ValueKind == JsonValueKind.Null || source.ValueKind == JsonValueKind.Null)) return "scope-missing";
        if (known && selected.GetArrayLength() != count) return "selected-count-mismatch";
        if (!known && selected.GetArrayLength() != 0) return "selection-unknown-with-refs";
        if (strategy.GetString() != "organizationPool" && count != 0) return "selected-without-pool";
        var seen = new HashSet<string>(StringComparer.Ordinal);
        foreach (var entry in scopes.EnumerateArray())
        {
            if (entry.ValueKind != JsonValueKind.Object) return "scope-row-invalid";
            if (!ShapeFields(entry, ["scopeRef", "name", "isCurrent"])) return "scope-fields-invalid";
            var reference = entry.GetProperty("scopeRef");
            if (!ShapeRef(reference)) return "scope-ref-invalid";
            if (!seen.Add(reference.GetString()!)) return "scope-ref-duplicate";
            if (ShapeLabel(entry.GetProperty("name"), 10) != "ok") return "scope-name-invalid";
            if (!ShapeBool(entry.GetProperty("isCurrent"))) return "scope-current-invalid";
        }
        if (scope.ValueKind != JsonValueKind.Null && !seen.Contains(scope.GetString()!)) return "scope-not-found";
        var page = row.GetProperty("page");
        var pageCode = OfficialHangarPageShape(page);
        if (pageCode != "ok") return pageCode;
        if (page.GetProperty("editRef").GetString() != edit.GetString()) return "page-edit-mismatch";
        return page.GetProperty("offset").GetInt32() != 0 ? "page-offset-not-zero" : "ok";
    }

    private static string OfficialHangarPageShape(JsonElement page)
    {
        if (page.ValueKind != JsonValueKind.Object) return "page-invalid";
        var fields = new[] { "schemaVersion", "editRef", "offset", "totalOptions", "options" };
        if (!ShapeFields(page, page.TryGetProperty("next", out var next) ? fields.Concat(["next"]).ToArray() : fields)) return "page-fields-invalid";
        if (!ShapeNumber(page.GetProperty("schemaVersion"), 1)) return "schema-invalid";
        if (!ShapeRef(page.GetProperty("editRef"))) return "edit-ref-invalid";
        var rawOffset = page.GetProperty("offset");
        if (rawOffset.ValueKind != JsonValueKind.Number || !rawOffset.TryGetInt64(out var offset64) || offset64 < 0 || offset64 % 100 != 0) return "page-offset-invalid";
        if (!ShapeInt(page.GetProperty("totalOptions"), 0, 20000, out var total) || offset64 > total) return "page-total-invalid";
        var offset = (int)offset64; // Proven <= total <= 20000 above.
        var options = page.GetProperty("options");
        if (options.ValueKind != JsonValueKind.Array) return "options-invalid";
        var length = options.GetArrayLength();
        if (length > 100) return "options-too-many";
        if (length != Math.Clamp(total - offset, 0, 100)) return "page-count-mismatch";
        if (offset + length < total ? !ShapeInt(next, 0, 20000, out var continuation) || continuation != offset + length
            : next.ValueKind is not (JsonValueKind.Null or JsonValueKind.Undefined)) return "page-next-invalid";
        var seen = new HashSet<string>(StringComparer.Ordinal);
        foreach (var option in options.EnumerateArray())
        {
            if (option.ValueKind != JsonValueKind.Object) return "option-invalid";
            if (!ShapeFields(option, ["shipRef", "name", "missing", "grantable"])) return "option-fields-invalid";
            var reference = option.GetProperty("shipRef");
            if (!ShapeRef(reference)) return "ship-ref-invalid";
            if (!seen.Add(reference.GetString()!)) return "ship-ref-duplicate";
            var missing = option.GetProperty("missing");
            var grantable = option.GetProperty("grantable");
            if (!ShapeBool(missing) || !ShapeBool(grantable) || missing.GetBoolean() == grantable.GetBoolean()) return "option-flags-invalid";
            var name = option.GetProperty("name");
            if (name.ValueKind == JsonValueKind.Null)
            {
                if (!missing.GetBoolean()) return "blank-name";
            }
            else
            {
                var code = ShapeLabel(name, 512);
                if (code != "ok") return code;
            }
        }
        return "ok";
    }

    private static bool ShapeFields(JsonElement row, string[] keys) => row.ValueKind == JsonValueKind.Object &&
        row.EnumerateObject().Count() == keys.Length && keys.All(key => row.TryGetProperty(key, out _));
    private static bool ShapeBool(JsonElement value) => value.ValueKind is JsonValueKind.True or JsonValueKind.False;
    private static bool ShapeInt(JsonElement value, int min, int max, out int number)
    {
        number = 0;
        return value.ValueKind == JsonValueKind.Number && value.TryGetInt32(out number) && number >= min && number <= max;
    }
    // Dart uses numeric equality for schema/protocol/maximum constants (1.0 == 1).
    private static bool ShapeNumber(JsonElement value, int number) => value.ValueKind == JsonValueKind.Number && value.TryGetDecimal(out var actual) && actual == number;
    private static bool ShapeRef(JsonElement value) => value.ValueKind == JsonValueKind.String &&
        value.GetString() is { Length: 32 } text && text.All(c => c is >= 'a' and <= 'f' or >= '0' and <= '9');
    private static bool ShapeSource(JsonElement value)
    {
        if (value.ValueKind != JsonValueKind.String || value.GetString() is not { } text || !text.StartsWith("officialFleet:", StringComparison.Ordinal)) return false;
        var id = text.AsSpan("officialFleet:".Length);
        return id.Length is >= 1 and <= 19 && id[0] is >= '1' and <= '9' && id.ToArray().All(c => c is >= '0' and <= '9');
    }
    private static bool ShapeChoice(JsonElement value, params string[] choices) => value.ValueKind == JsonValueKind.String && choices.Contains(value.GetString(), StringComparer.Ordinal);
    private static string ShapeLabel(JsonElement value, int max)
    {
        if (value.ValueKind != JsonValueKind.String) return "name-invalid";
        var text = value.GetString()!;
        // Whitespace-only labels are an intentional extra diagnostic requested
        // by OS-8; Flutter _label currently only rejects the empty string.
        if (string.IsNullOrWhiteSpace(text)) return "blank-name";
        if (text.Length > max) return "name-too-long";
        return text.Any(c => c <= '\x1f' || c == '\x7f') ? "name-control-char" : "ok";
    }
}
