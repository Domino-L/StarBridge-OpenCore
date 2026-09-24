namespace StarBridge.Core.Overlay;

using System.Text.Json;
using System.Text.RegularExpressions;

public sealed record InformationOverlayPresetEntry(string Id, string Name);

public static class InformationOverlayPresetCodec
{
    public const string DefaultPresetId = "preset1";
    public const string CompactPresetId = "compact";
    public const string CommandPresetId = "command";
    public const string CombatPresetId = "combat";
    public const string CustomPresetId = "custom";

    private sealed record Manifest(List<InformationOverlayPresetEntry> Presets);

    public static string SerializeManifest(IEnumerable<InformationOverlayPresetEntry> entries)
    {
        ArgumentNullException.ThrowIfNull(entries);
        var normalized = new List<InformationOverlayPresetEntry>();
        var ids = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var entry in entries)
        {
            if (entry is null)
            {
                continue;
            }

            var id = SanitizeId(entry.Id);
            var name = CleanName(entry.Name);
            if (name is not null && ids.Add(id))
            {
                normalized.Add(new InformationOverlayPresetEntry(id, name));
            }
        }

        if (normalized.Count == 0)
        {
            throw new ArgumentException("At least one overlay preset is required.", nameof(entries));
        }

        return JsonSerializer.Serialize(new Manifest(normalized));
    }

    public static IReadOnlyList<InformationOverlayPresetEntry> ParseManifest(
        string? serialized,
        out bool recovered)
    {
        recovered = false;
        if (string.IsNullOrWhiteSpace(serialized))
        {
            return [];
        }

        List<InformationOverlayPresetEntry>? entries = null;
        var options = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };
        try
        {
            entries = JsonSerializer.Deserialize<Manifest>(serialized, options)?.Presets;
        }
        catch (JsonException)
        {
            // Older experimental builds may have written a raw list.
        }

        if (entries is null)
        {
            try
            {
                entries = JsonSerializer.Deserialize<List<InformationOverlayPresetEntry>>(serialized, options);
            }
            catch (JsonException)
            {
                recovered = true;
                return [];
            }
        }

        if (entries is null)
        {
            recovered = true;
            return [];
        }

        var result = new List<InformationOverlayPresetEntry>(entries.Count);
        var ids = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var entry in entries)
        {
            if (entry is null)
            {
                recovered = true;
                continue;
            }

            var id = SanitizeId(entry.Id);
            var name = CleanName(entry.Name) ?? "默认预设";
            if (id.Equals(DefaultPresetId, StringComparison.OrdinalIgnoreCase) &&
                (name.Equals("预设1", StringComparison.OrdinalIgnoreCase) ||
                 name.Equals("舰桥标准", StringComparison.OrdinalIgnoreCase)))
            {
                name = "默认预设";
            }

            if (ids.Add(id))
            {
                result.Add(new InformationOverlayPresetEntry(id, name));
            }
        }

        recovered |= result.Count != entries.Count;
        return result;
    }

    public static string SanitizeId(string? value)
    {
        var raw = string.IsNullOrWhiteSpace(value)
            ? DefaultPresetId
            : value.Trim().ToLowerInvariant();
        var safe = Regex.Replace(raw, "[^a-z0-9]+", "-").Trim('-');
        return string.IsNullOrWhiteSpace(safe) ? DefaultPresetId : safe;
    }

    public static string? CleanName(string? value)
    {
        var name = value?.Trim();
        if (string.IsNullOrWhiteSpace(name))
        {
            return null;
        }

        return name.Length > 24 ? name[..24] : name;
    }
}

public static class InformationOverlayDefaults
{
    private const string DefaultSettingsPayload =
        "0,CallsignAndGameName,1,1,1,1.00,1,1,0,1,Default,0,0,Simple,0,#FFFFFF,52.48,1.57,1,1,BridgeTerminal,1,1,120,1,Right,5.03,0.291,1,Auto,0,Default,AllFleet,0.456,2047,3,0,Slow,0;0;0;0;0;0;0;0;0;0;0,1,3.1,12.12,0,Default,Strong,0,0,0,60,3,Auto,1,FullScreenBarrage,Right,4,12,1,1,1,0,16,UpperMiddle,Standard,1,Strong,1,0,5,All";

    public const string DefaultLayoutPayload =
        "Notice,0.34,0,0.32,0.055,Center,Top,0,1,0.5;" +
        "Squads,0,0.4211,0.1327,0.1042,Left,Middle,0,1,0.5;" +
        "Members,0,0.5253,0.1327,0.1557,Right,Middle,0,1,0.5;" +
        "Chat,0,0.681,0.1327,0.1069,Center,Bottom,0,1,1";

    public static OverlayDisplaySettings DefaultSettings { get; } =
        OverlayDisplaySettings.Parse(DefaultSettingsPayload);

    public static OverlayDisplaySettings CreateSettings(string? presetId)
    {
        return NormalizeBuiltInId(presetId) switch
        {
            InformationOverlayPresetCodec.DefaultPresetId => DefaultSettings,
            InformationOverlayPresetCodec.CompactPresetId => OverlayDisplaySettings.Default with
            {
                HideMissionWhenIdle = false,
                HideOfflineMembers = true,
                HideSquadIcons = true,
                Opacity = 0.78,
                ShowNotice = true,
                ShowSquads = true,
                ShowMission = false,
                ShowMembers = true
            },
            InformationOverlayPresetCodec.CommandPresetId => OverlayDisplaySettings.Default with
            {
                HideMissionWhenIdle = false,
                HideOfflineMembers = false,
                HideSquadIcons = false,
                Opacity = 0.9,
                ShowNotice = true,
                ShowSquads = true,
                ShowMission = false,
                ShowMembers = true
            },
            _ => OverlayDisplaySettings.Default
        };
    }

    public static IReadOnlyList<InformationOverlayLayoutItem> CreateLayout(string? presetId)
    {
        var payload = NormalizeBuiltInId(presetId) switch
        {
            InformationOverlayPresetCodec.CompactPresetId =>
                "Notice,0.34,0,0.32,0.055;" +
                "Squads,0.01,0.36,0.13,0.24;" +
                "Members,0.84,0.58,0.15,0.18;" +
                "Chat,0.35,0.78,0.30,0.18",
            InformationOverlayPresetCodec.CommandPresetId =>
                "Notice,0.285,0,0.43,0.075;" +
                "Squads,0.01,0.30,0.18,0.42;" +
                "Members,0.78,0.54,0.21,0.26;" +
                "Chat,0.35,0.75,0.30,0.21",
            _ => DefaultLayoutPayload
        };

        return InformationOverlayLayoutItem.ParseMany(payload).ToArray();
    }

    private static string NormalizeBuiltInId(string? presetId)
    {
        var id = InformationOverlayPresetCodec.SanitizeId(presetId);
        return id switch
        {
            InformationOverlayPresetCodec.DefaultPresetId => id,
            InformationOverlayPresetCodec.CompactPresetId => id,
            InformationOverlayPresetCodec.CommandPresetId => id,
            InformationOverlayPresetCodec.CombatPresetId => id,
            InformationOverlayPresetCodec.CustomPresetId => id,
            _ => InformationOverlayPresetCodec.DefaultPresetId
        };
    }
}
