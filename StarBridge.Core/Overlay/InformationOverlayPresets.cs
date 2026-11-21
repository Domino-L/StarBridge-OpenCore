namespace StarBridge.Core.Overlay;

using System.Text.Json;
using System.Text.RegularExpressions;

public sealed record InformationOverlayPresetEntry(string Id, string Name);

public static class InformationOverlayPresetCodec
{
    public const string DefaultPresetId = "preset1";

    /// <summary>
    /// The earlier client's built-in layouts (combat, compact, command and the custom slot), retired in 0.7.3 (user,
    /// 11-10: "3套预设布局只是之前遗留下来的废弃代码"): there is one default layout. A preset under one of these names
    /// that the user saved stays as their own preset; one never saved is dropped (OverlayWorkspaceStore).
    /// </summary>
    public static readonly IReadOnlySet<string> RetiredBuiltInIds =
        new HashSet<string>(["combat", "compact", "command", "custom"], StringComparer.OrdinalIgnoreCase);

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
    // Fields 74–79 turn calm display on for new installs; older files parse as Unset.
    private const string DefaultSettingsPayload =
        "0,CallsignAndGameName,1,1,1,1.00,1,1,0,1,Default,0,0,Simple,0,#FFFFFF,52.48,1.57,1,1,BridgeTerminal,1,1,120,1,Right,5.03,0.254,1,Auto,0,Default,AllFleet,0.456,2047,3,0,Slow,0;0;0;0;0;0;0;0;0;0;0,1,3.1,12.12,0,Default,Strong,0,0,0,60,3,Auto,1,FullScreenBarrage,Right,4,12,1,1,1,0,16,UpperMiddle,Standard,1,Strong,1,0,5,All,1,0.15,0,Default,1,On,10,0,0,Relevant,," +
        // 0.7.3 m102 (11-18 user): the visor fields, with the members 12 rows high ("12 人"); the rest as before
        "Visor,Medium,0,-1,-1,15,1,1,1,364,554";

    public const string DefaultLayoutPayload =
        "Notice,0.34,0,0.32,0.055,Center,Top,0,1,0.08;" +
        "Squads,0,0.4211,0.1327,0.1042,Left,Middle,0,1,0.08;" +
        "Members,0,0.5253,0.1327,0.1557,Right,Middle,0,1,0.08;" +
        "Chat,0,0.681,0.1327,0.1069,Center,Bottom,0,1,0.15";

    public static OverlayDisplaySettings DefaultSettings { get; } =
        OverlayDisplaySettings.Parse(DefaultSettingsPayload);

    /// <summary>
    /// The overall opacity each preset shipped with before 0.7.3, when the setting never took effect (the overlay was
    /// always drawn full): the retired compact layout 0.78, the retired command layout 0.9, every other preset 0.85.
    /// </summary>
    public static double LegacyDefaultOpacity(string? presetId) => InformationOverlayPresetCodec.SanitizeId(presetId) switch
    {
        "compact" => 0.78,
        "command" => 0.9,
        _ => 0.85,
    };

    /// <summary>
    /// The one-time move when the overall opacity starts to take effect (user, 11-10: "默认改成 100%", nobody's overlay may
    /// turn fainter): a preset still at its old default moves to full; any other saved value was chosen and is kept.
    /// The store runs this once per data root and then keeps what is saved, so a value chosen later stays.
    /// </summary>
    public static OverlayDisplaySettings MigrateLegacyOpacity(string? presetId, OverlayDisplaySettings settings) =>
        Math.Abs(settings.Opacity - LegacyDefaultOpacity(presetId)) < 0.005 ? settings with { Opacity = 1.0 } : settings;

    /// <summary>The default preset's settings; any other preset with nothing saved starts from the plain defaults.</summary>
    public static OverlayDisplaySettings CreateSettings(string? presetId) =>
        InformationOverlayPresetCodec.SanitizeId(presetId) == InformationOverlayPresetCodec.DefaultPresetId
            ? DefaultSettings
            : OverlayDisplaySettings.Default;

    /// <summary>One default layout for every preset (the earlier built-in layouts are retired, 0.7.3).</summary>
    /// <summary>
    /// 0.7.3 (11-13 user, "背景可以"): a block's background opacity is the plate's real opacity (100% = solid). Before, 100%
    /// drew only a faint plate (the decoration colour at 13%), so a value saved before is read once at 15% of itself and
    /// looks as it did.
    /// </summary>
    public const double LegacyBackgroundScale = 0.15;

    public static double ScaleLegacyBackground(double value) =>
        Math.Round(InformationOverlayLayoutItem.NormalizeBackgroundOpacity(value) * LegacyBackgroundScale, 2);

    public static OverlayDisplaySettings ScaleLegacyBackground(OverlayDisplaySettings settings) =>
        settings with { EventNotificationBackgroundOpacity = ScaleLegacyBackground(settings.EventNotificationBackgroundOpacity) };

    public static IReadOnlyList<InformationOverlayLayoutItem> ScaleLegacyBackground(IEnumerable<InformationOverlayLayoutItem> layout) =>
        layout.Select(item => new InformationOverlayLayoutItem(item.Key, item.X, item.Y, item.Width, item.Height,
            item.HorizontalAnchor, item.VerticalAnchor, item.IsLocked, item.TextOpacity,
            ScaleLegacyBackground(item.BackgroundOpacity), item.DecorationOpacity)).ToArray();

    public static IReadOnlyList<InformationOverlayLayoutItem> CreateLayout(string? presetId) =>
        InformationOverlayLayoutItem.ParseMany(DefaultLayoutPayload).ToArray();
}
