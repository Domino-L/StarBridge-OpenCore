namespace StarBridge.HostRuntime.Overlay;

using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StarBridge.Core.Overlay;

/// <summary>Local v2 preset. Source policy is independent of the retired CSV scene slot.</summary>
/// <remarks>
/// 0.7.3 visor: the v2 document stays exactly what 0.7.2.1 reads (it rejects unknown settings
/// fields and unknown skin names), so the visor fields are left out of it and a visor skin is
/// written there as the standard one. The visor part lives in a sidecar
/// (<c>overlay.&lt;id&gt;.visor.json</c>) that names the hash of the document it was written with;
/// a document an older client rewrote no longer matches, so the stale sidecar is ignored.
/// </remarks>
internal sealed record OverlayPresetDocument(
    OverlayDisplaySettings Settings,
    IReadOnlyList<InformationOverlayLayoutItem> Layout,
    OverlayPresetSources Sources,
    bool RecoveredDefaults = false)
{
    /// <summary>Settings fields 0.7.2.1 does not know; they are kept in the visor sidecar.</summary>
    internal static readonly IReadOnlySet<string> VisorFields = new HashSet<string>(
        ["visorSize", "visorHolidayGold", "visorBadgeX", "visorBadgeY", "visorTilt", "visorChatPlate",
         "visorMembersAutoWidth", "visorMembersAutoHeight", "visorMembersWidth", "visorMembersHeight",
         "visorEventsAutoWidth", "visorChatAutoWidth", "visorEventsWidth", "visorChatWidth", "visorViewingDistance", "visorEventsX"],
        StringComparer.Ordinal);

    /// <summary>True when a matching visor sidecar was read: 0.7.3 or later wrote this preset.</summary>
    internal bool WrittenWithVisor { get; init; }

    internal string Serialize()
    {
        var settings = new Dictionary<string, object?>(OverlayWorkspaceWireProjection.Settings(Settings));
        settings.Remove("scenePreference");
        foreach (var field in VisorFields) settings.Remove(field);
        if (Settings.Skin == OverlaySkin.Visor) settings["skin"] = nameof(OverlaySkin.Default);
        if (Settings.RequestedSkin == OverlaySkin.Visor) settings["requestedSkin"] = nameof(OverlaySkin.Default);
        return JsonSerializer.Serialize(new
        {
            schemaVersion = 2,
            recoveredDefaults = RecoveredDefaults,
            settings,
            layout = OverlayWorkspaceStore.ValidateLayout(Layout).Select(OverlayWorkspaceWireProjection.Layout),
            sources = JsonSerializer.Deserialize<JsonElement>(OverlayPresetSourcesCodec.Serialize(Sources))
        });
    }

    /// <summary>The visor sidecar for <paramref name="document"/> (the text <see cref="Serialize"/> returned).</summary>
    internal string SerializeVisor(string document) => JsonSerializer.Serialize(new
    {
        schemaVersion = 1,
        document = Hash(document),
        skin = Settings.Skin.ToString(),
        requestedSkin = Settings.RequestedSkin.ToString(),
        visorSize = Settings.VisorSize.ToString(),
        visorHolidayGold = Settings.VisorHolidayGold,
        visorBadgeX = OverlayDisplaySettings.NormalizeVisorBadge(Settings.VisorBadgeX),
        visorBadgeY = OverlayDisplaySettings.NormalizeVisorBadge(Settings.VisorBadgeY),
        visorTilt = OverlayDisplaySettings.NormalizeVisorTilt(Settings.VisorTilt),
        visorChatPlate = Settings.VisorChatPlate,
        visorMembersAutoWidth = Settings.VisorMembersAutoWidth,
        visorMembersAutoHeight = Settings.VisorMembersAutoHeight,
        visorMembersWidth = OverlayDisplaySettings.NormalizeVisorMembersWidth(Settings.VisorMembersWidth),
        visorMembersHeight = OverlayDisplaySettings.NormalizeVisorMembersHeight(Settings.VisorMembersHeight),
        visorEventsAutoWidth = Settings.VisorEventsAutoWidth,
        visorChatAutoWidth = Settings.VisorChatAutoWidth,
        visorEventsWidth = OverlayDisplaySettings.NormalizeVisorMembersWidth(Settings.VisorEventsWidth),
        visorChatWidth = OverlayDisplaySettings.NormalizeVisorMembersWidth(Settings.VisorChatWidth),
        visorViewingDistance = OverlayDisplaySettings.NormalizeVisorViewingDistance(Settings.VisorViewingDistance),
        visorEventsX = OverlayDisplaySettings.NormalizeVisorBadge(Settings.VisorEventsX)
    });

    internal static OverlayPresetDocument Parse(string payload, string? visor = null)
    {
        OverlayPresetDocument parsed;
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
            // The visor fields are optional here (they live in the sidecar), so their absence is not a recovery.
            var baseFields = fields.Count(field => !VisorFields.Contains(field));
            parsed = new(
                OverlayWorkspaceWireProjection.ParseSettings(JsonSerializer.SerializeToElement(settings)),
                OverlayWorkspaceStore.ValidateLayout(OverlayWorkspaceWireProjection.ParseLayout(root.GetProperty("layout"))),
                sources,
                root.GetProperty("recoveredDefaults").GetBoolean() ||
                settingsNode.EnumerateObject().Count(property => !VisorFields.Contains(property.Name)) != baseFields);
        }
        catch (Exception exception) when (exception is JsonException or FormatException or InvalidOperationException
            or ArgumentException or OverflowException or OverlaySettingsException)
        {
            // A legacy fallback here could resurrect a removed policy.
            throw new OverlaySettingsException("overlay.workspace_invalid_preset", false, exception);
        }
        return visor is null ? parsed : WithVisor(parsed, payload, visor);
    }

    /// <summary>
    /// Applies a sidecar written together with this exact document. A damaged or stale sidecar is
    /// ignored (the preset keeps what the document says) rather than blocking the preset.
    /// </summary>
    private static OverlayPresetDocument WithVisor(OverlayPresetDocument parsed, string payload, string visor)
    {
        try
        {
            if (visor.Length > 4 * 1024) return parsed;
            using var document = JsonDocument.Parse(visor, new JsonDocumentOptions { MaxDepth = 4 });
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object || root.GetProperty("schemaVersion").GetInt32() != 1 ||
                root.GetProperty("document").GetString() != Hash(payload))
                return parsed;
            var settings = parsed.Settings with
            {
                Skin = Enum.Parse<OverlaySkin>(root.GetProperty("skin").GetString()!),
                RequestedSkin = Enum.Parse<OverlaySkin>(root.GetProperty("requestedSkin").GetString()!),
                VisorSize = Enum.Parse<OverlayVisorSize>(root.GetProperty("visorSize").GetString()!),
                VisorHolidayGold = root.GetProperty("visorHolidayGold").GetBoolean(),
                VisorBadgeX = OverlayDisplaySettings.NormalizeVisorBadge(root.GetProperty("visorBadgeX").GetDouble()),
                VisorBadgeY = OverlayDisplaySettings.NormalizeVisorBadge(root.GetProperty("visorBadgeY").GetDouble()),
                // Added 11-07 (later 0.7.3 builds): missing, or of the wrong type, each reads its default on its own,
                // without dropping the rest of the sidecar.
                VisorTilt = OverlayDisplaySettings.NormalizeVisorTilt(OptionalNumber(root, "visorTilt", OverlayDisplaySettings.DefaultVisorTilt)),
                VisorChatPlate = OptionalBool(root, "visorChatPlate", true),
                VisorMembersAutoWidth = OptionalBool(root, "visorMembersAutoWidth", true),
                VisorMembersAutoHeight = OptionalBool(root, "visorMembersAutoHeight", true),
                VisorMembersWidth = OverlayDisplaySettings.NormalizeVisorMembersWidth(
                    OptionalNumber(root, "visorMembersWidth", OverlayDisplaySettings.DefaultVisorMembersWidth)),
                VisorMembersHeight = OverlayDisplaySettings.NormalizeVisorMembersHeight(
                    OptionalNumber(root, "visorMembersHeight", OverlayDisplaySettings.DefaultVisorMembersHeight)),
                VisorEventsAutoWidth = OptionalBool(root, "visorEventsAutoWidth", true),
                VisorChatAutoWidth = OptionalBool(root, "visorChatAutoWidth", true),
                VisorEventsWidth = OverlayDisplaySettings.NormalizeVisorMembersWidth(
                    OptionalNumber(root, "visorEventsWidth", OverlayDisplaySettings.DefaultVisorMembersWidth)),
                VisorChatWidth = OverlayDisplaySettings.NormalizeVisorMembersWidth(
                    OptionalNumber(root, "visorChatWidth", OverlayDisplaySettings.DefaultVisorMembersWidth)),
                // added 11-11: an older sidecar reads the distance the visor always had
                VisorViewingDistance = OverlayDisplaySettings.NormalizeVisorViewingDistance(
                    OptionalNumber(root, "visorViewingDistance", OverlayDisplaySettings.DefaultVisorViewingDistance)),
                // added 11-12: an older sidecar keeps the events at the screen edge
                VisorEventsX = OverlayDisplaySettings.NormalizeVisorBadge(
                    OptionalNumber(root, "visorEventsX", OverlayDisplaySettings.UnsetVisorBadge))
            };
            if (!Enum.IsDefined(settings.Skin) || !Enum.IsDefined(settings.RequestedSkin) || !Enum.IsDefined(settings.VisorSize))
                return parsed;
            return parsed with { Settings = settings, WrittenWithVisor = true };
        }
        catch (Exception exception) when (exception is JsonException or FormatException or InvalidOperationException
            or ArgumentException or KeyNotFoundException or OverflowException)
        {
            return parsed;
        }
    }

    private static bool OptionalBool(JsonElement root, string name, bool fallback) =>
        root.TryGetProperty(name, out var value) && value.ValueKind is JsonValueKind.True or JsonValueKind.False ? value.GetBoolean() : fallback;

    private static double OptionalNumber(JsonElement root, string name, double fallback) =>
        root.TryGetProperty(name, out var value) && value.ValueKind == JsonValueKind.Number && value.TryGetDouble(out var number) ? number : fallback;

    private static string Hash(string payload) =>
        Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(payload))).ToLowerInvariant();

    private static void Exact(JsonElement node, IReadOnlyCollection<string> fields, bool allowMissing = false)
    {
        if (node.ValueKind != JsonValueKind.Object) throw new FormatException();
        var actual = new HashSet<string>(StringComparer.Ordinal);
        foreach (var property in node.EnumerateObject())
            if (!actual.Add(property.Name)) throw new FormatException();
        if (allowMissing ? !actual.IsSubsetOf(fields) : !actual.SetEquals(fields)) throw new FormatException();
    }
}
