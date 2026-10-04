namespace StarBridge.HostRuntime.Overlay;

using System.Text.Json;
using StarBridge.Core.Overlay;

/// <summary>Local v2 preset. Source policy is independent of the retired CSV scene slot.</summary>
internal sealed record OverlayPresetDocument(
    OverlayDisplaySettings Settings,
    IReadOnlyList<InformationOverlayLayoutItem> Layout,
    OverlayPresetSources Sources,
    bool RecoveredDefaults = false)
{
    internal string Serialize()
    {
        var settings = new Dictionary<string, object?>(OverlayWorkspaceWireProjection.Settings(Settings));
        settings.Remove("scenePreference");
        return JsonSerializer.Serialize(new
        {
            schemaVersion = 2,
            recoveredDefaults = RecoveredDefaults,
            settings,
            layout = OverlayWorkspaceStore.ValidateLayout(Layout).Select(OverlayWorkspaceWireProjection.Layout),
            sources = JsonSerializer.Deserialize<JsonElement>(OverlayPresetSourcesCodec.Serialize(Sources))
        });
    }

    internal static OverlayPresetDocument Parse(string payload)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(payload) || payload.Length > 128 * 1024)
                throw new FormatException();
            using var document = JsonDocument.Parse(payload, new JsonDocumentOptions { MaxDepth = 12 });
            var root = document.RootElement;
            Exact(root, ["schemaVersion", "recoveredDefaults", "settings", "layout", "sources"]);
            if (root.GetProperty("schemaVersion").GetInt32() != 2) throw new FormatException();
            var fields = OverlayWorkspaceWireProjection.Settings(OverlayDisplaySettings.Default).Keys
                .Where(key => key != "scenePreference").ToArray();
            var settingsNode = root.GetProperty("settings");
            Exact(settingsNode, fields, allowMissing: true);
            var settings = OverlayWorkspaceWireProjection.Settings(OverlayDisplaySettings.Default)
                .ToDictionary(pair => pair.Key, pair => JsonSerializer.SerializeToElement(pair.Value));
            foreach (var property in settingsNode.EnumerateObject()) settings[property.Name] = property.Value.Clone();
            var sources = OverlayPresetSourcesCodec.Parse(root.GetProperty("sources").GetRawText());
            // Adapter for old runtime consumers; the retired field is never persisted in this document.
            settings["scenePreference"] = JsonSerializer.SerializeToElement(
                sources.Binding.Mode == OverlaySourceMode.Room ? "PartyRoom" : "Auto");
            return new(
                OverlayWorkspaceWireProjection.ParseSettings(JsonSerializer.SerializeToElement(settings)),
                OverlayWorkspaceStore.ValidateLayout(OverlayWorkspaceWireProjection.ParseLayout(root.GetProperty("layout"))),
                sources,
                root.GetProperty("recoveredDefaults").GetBoolean() || settingsNode.EnumerateObject().Count() != fields.Length);
        }
        catch (Exception exception) when (exception is JsonException or FormatException or InvalidOperationException
            or ArgumentException or OverflowException or OverlaySettingsException)
        {
            // A legacy fallback here could resurrect a removed policy.
            throw new OverlaySettingsException("overlay.workspace_invalid_preset", false, exception);
        }
    }

    private static void Exact(JsonElement node, IReadOnlyCollection<string> fields, bool allowMissing = false)
    {
        if (node.ValueKind != JsonValueKind.Object) throw new FormatException();
        var actual = new HashSet<string>(StringComparer.Ordinal);
        foreach (var property in node.EnumerateObject())
            if (!actual.Add(property.Name)) throw new FormatException();
        if (allowMissing ? !actual.IsSubsetOf(fields) : !actual.SetEquals(fields)) throw new FormatException();
    }
}
