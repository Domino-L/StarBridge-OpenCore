namespace StarBridge.HostRuntime.Overlay;

using System.Text.Json;
using StarBridge.Core.Overlay;

// Overlay v2 (0.7.3). The earlier one-time switch to the visor (11-06) is gone: v2 keeps its own
// files in V2Folder and starts from defaults, where the visor is the default look, so no saved
// preset is switched, no marker or backup is written for it, and the earlier overlay files are
// never read, written or deleted (0.7.2.1 keeps working on them after a rollback).
//
// The one-time line "浮层升级到新版，设置已恢复默认" shows when the earlier overlay files exist
// (only their presence is checked, never their content) and the v2 folder has no notice marker yet.
// Dismissing it writes that marker inside the v2 folder.
//
// Kept from the earlier overlay (user, 11-07: "保留"): the four game-linked choices (open with the game, open when
// the game comes to the front, close when it goes to the back, focus the game when the overlay opens). Until v2
// writes anything, they are read from the earlier overlay.settings (read only, never changed) and shown on every
// preset v2 has not saved yet. The first v2 write stores them in the v2 folder (CarriedFile); from then on the
// earlier file is never read again. A missing or damaged earlier file gives the defaults.
//
// v2 defaults (user, 11-07: "建议默认关闭安静显示"): the visor look, calm display off (the setting stays; the user
// can turn it on), and the four kept choices. They apply to presets v2 has not saved and to new or reset presets.
//
// The visor sidecar helpers below stay for presets written by 0.7.3 test builds before the reset;
// v2 documents never hold the visor fields or the "Visor" skin (0.7.2.1 rejects both).
internal sealed partial class OverlayWorkspaceStore
{
    /// <summary>In the v2 folder: the settings page has shown the upgrade line.</summary>
    internal const string V2NoticeFile = "overlay.v2-notice.json";

    /// <summary>In the v2 folder: the game-linked choices copied once from the earlier overlay.settings.</summary>
    internal const string CarriedFile = "overlay.v2-carried.json";

    private sealed record CarriedChoices(int SchemaVersion, bool AutoOpenOverlayOnGameStart, bool AutoOpenOverlayOnGameForeground,
        bool AutoCloseOverlayOnGameBackground, bool AutoFocusGameWindowOnOpen);

    /// <summary>Files whose presence means this user had saved the earlier overlay.</summary>
    private static readonly string[] LegacyOverlayFiles =
        ["overlay.settings", "overlay.layout", "overlay.presets", "overlay.active-preset"];

    private static readonly JsonSerializerOptions MarkerJson = new(JsonSerializerDefaults.Web);

    /// <summary>Per-preset visor part of a v2 document; see <see cref="OverlayPresetDocument"/>.</summary>
    private const string VisorSidecar = "visor.json";

    /// <summary>Writes a v2 document that 0.7.2.1 still reads, plus its visor sidecar, in the same transaction.</summary>
    private static void AddPresetDocument(IDictionary<string, string> writes, string id, OverlayPresetDocument document,
        bool visor = true)
    {
        var payload = document.Serialize();
        writes[PresetFile(id, "workspace.json")] = payload;
        // Moving an older client's CSV to v2 writes no sidecar: that preset was not written by 0.7.3.
        if (visor) writes[PresetFile(id, VisorSidecar)] = document.SerializeVisor(payload);
    }

    /// <summary>
    /// A settings CSV 0.7.3 or later wrote: it carries the reserved visor column 80. An older client
    /// rewrites the CSV without it.
    /// </summary>
    private static bool WrittenSince073(string? settingsCsv)
    {
        if (settingsCsv is null) return false;
        var parts = settingsCsv.Split(',', StringSplitOptions.TrimEntries);
        return parts.Length > 80 && parts[80] == "Visor";
    }

    private static string? ReadVisorSidecar(string root, string id, bool primary, IDictionary<string, string> observed)
    {
        var name = PresetFile(id, VisorSidecar);
        var path = Path.Combine(root, name);
        if (!File.Exists(path) || new FileInfo(path).Length > 4 * 1024) return null;
        var payload = File.ReadAllText(path, System.Text.Encoding.UTF8);
        observed[$"{(primary ? "primary" : "fallback")}/{name}"] = payload;
        return payload;
    }

    /// <summary>True in v2 storage when the earlier overlay files exist and the upgrade line was not shown yet.</summary>
    private bool UpgradeNoticePending()
    {
        if (!V2Mode) return false;
        if (File.Exists(Path.Combine(_dataRoot, V2NoticeFile))) return false;
        return LegacyOverlayFiles.Any(name => File.Exists(Path.Combine(_sharedRoot, name)));
    }

    private bool V2Mode => !string.Equals(_dataRoot, _sharedRoot, StringComparison.OrdinalIgnoreCase);

    /// <summary>
    /// The kept choices: from the v2 folder once copied, else (v2 has written nothing yet) from the earlier
    /// overlay.settings, read only. Null outside v2 storage.
    /// </summary>
    private CarriedChoices? ReadCarried()
    {
        if (!V2Mode) return null;
        var copied = Path.Combine(_dataRoot, CarriedFile);
        if (File.Exists(copied))
        {
            try
            {
                return new FileInfo(copied).Length <= 4 * 1024
                    ? JsonSerializer.Deserialize<CarriedChoices>(File.ReadAllText(copied, System.Text.Encoding.UTF8), MarkerJson) ?? Defaults()
                    : Defaults();
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException) { return Defaults(); }
        }
        var earlier = Path.Combine(_sharedRoot, SettingsFile);
        try
        {
            if (!File.Exists(earlier) || new FileInfo(earlier).Length > 64 * 1024) return Defaults();
            var old = OverlayDisplaySettings.Parse(File.ReadAllText(earlier, System.Text.Encoding.UTF8));
            return new CarriedChoices(1, old.AutoOpenOverlayOnGameStart, old.AutoOpenOverlayOnGameForeground,
                old.AutoCloseOverlayOnGameBackground, old.AutoFocusGameWindowOnOpen);
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or FormatException or ArgumentException)
        {
            return Defaults();
        }

        static CarriedChoices Defaults()
        {
            var value = OverlayDisplaySettings.Default;
            return new CarriedChoices(1, value.AutoOpenOverlayOnGameStart, value.AutoOpenOverlayOnGameForeground,
                value.AutoCloseOverlayOnGameBackground, value.AutoFocusGameWindowOnOpen);
        }
    }

    /// <summary>A new or reset preset: the shipped defaults, plus in v2 the visor look, calm display off and the kept choices.</summary>
    private OverlayDisplaySettings PresetDefaults(string presetId)
    {
        var settings = InformationOverlayDefaults.CreateSettings(presetId);
        var carried = ReadCarried();
        return carried is null ? settings : V2Defaults(settings, carried) with { Skin = OverlaySkin.Visor, RequestedSkin = OverlaySkin.Visor };
    }

    private static OverlayDisplaySettings V2Defaults(OverlayDisplaySettings settings, CarriedChoices carried) => settings with
    {
        AutoOpenOverlayOnGameStart = carried.AutoOpenOverlayOnGameStart,
        AutoOpenOverlayOnGameForeground = carried.AutoOpenOverlayOnGameForeground,
        AutoCloseOverlayOnGameBackground = carried.AutoCloseOverlayOnGameBackground,
        AutoFocusGameWindowOnOpen = carried.AutoFocusGameWindowOnOpen,
        CalmDisplay = OverlayCalmDisplay.Off
    };

    /// <summary>The v2 defaults on a preset v2 has not saved yet; a preset saved in v2 keeps what it saved.</summary>
    private OverlayDisplaySettings Carry(OverlayDisplaySettings settings, CarriedChoices? carried, string presetId, bool isActive)
    {
        if (carried is null) return settings;
        var saved = File.Exists(Path.Combine(_dataRoot, PresetFile(presetId, "settings"))) ||
            File.Exists(Path.Combine(_dataRoot, PresetFile(presetId, "workspace.json"))) ||
            isActive && File.Exists(Path.Combine(_dataRoot, SettingsFile));
        return saved ? settings : V2Defaults(settings, carried);
    }

    /// <summary>With the first v2 write, the kept choices are stored in the v2 folder; the earlier file is not read again.</summary>
    private void AddCarriedWrite(IDictionary<string, string> writes)
    {
        if (!V2Mode || File.Exists(Path.Combine(_dataRoot, CarriedFile)) || writes.ContainsKey(CarriedFile)) return;
        writes[CarriedFile] = JsonSerializer.Serialize(ReadCarried(), MarkerJson);
    }

    /// <summary>The settings page showed the one-time line; it does not come back.</summary>
    internal void DismissVisorNotice()
    {
        lock (StorageGate)
        {
            try
            {
                if (!UpgradeNoticePending()) return;
                var writes = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
                {
                    [V2NoticeFile] = JsonSerializer.Serialize(new { schemaVersion = 1, shownAtUtc = DateTimeOffset.UtcNow }, MarkerJson)
                };
                AddCarriedWrite(writes);
                ApplyFileTransaction(writes, new HashSet<string>());
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException)
            {
                throw new OverlaySettingsException("overlay.workspace_write_failed", true, error);
            }
        }
    }
}
