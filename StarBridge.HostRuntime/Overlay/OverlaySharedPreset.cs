namespace StarBridge.HostRuntime.Overlay;

using System.Globalization;
using System.Text.Json;
using StarBridge.Core.Chat;
using StarBridge.Core.Overlay;

// WPF v1 settings/layout package. It contains no account, hotkey or entitlement data.
internal sealed record OverlaySharedPreset(int Version, string Name, string Settings, string Layout,
    JsonElement? Sources = null, bool RemovedOrganizationBindings = false)
{
    internal static OverlaySharedPreset Parse(string? payload)
    {
        try
        {
            if (payload is null || payload.Length is < 16 or > ChatAttachmentPolicy.MaximumPresetPackageLength)
                throw Invalid();
            using var json = JsonDocument.Parse(payload);
            var fields = json.RootElement.EnumerateObject().ToArray();
            var package = JsonSerializer.Deserialize<OverlaySharedPreset>(payload,
                new JsonSerializerOptions { PropertyNameCaseInsensitive = true }) ?? throw Invalid();
            var expected = package.Version == 2
                ? new[] { "version", "name", "settings", "layout", "sources", "removedorganizationbindings" }
                : new[] { "version", "name", "settings", "layout" };
            if (fields.Length != expected.Length || fields.Select(p => p.Name.ToLowerInvariant()).Distinct().Count() != expected.Length ||
                fields.Any(p => !expected.Contains(p.Name.ToLowerInvariant()))) throw Invalid();
            var name = InformationOverlayPresetCodec.CleanName(package.Name);
            if (package.Version is not (1 or 2) || name is null || string.IsNullOrWhiteSpace(package.Settings) ||
                string.IsNullOrWhiteSpace(package.Layout)) throw Invalid();
            var settings = package.Settings.Split(',', StringSplitOptions.TrimEntries);
            if (settings.Length < 5 || settings.Length > 128 ||
                settings[0] is not ("0" or "1") || settings.Skip(2).Take(3).Any(s => s is not ("0" or "1")) ||
                !Enum.TryParse<OverlayMemberNameMode>(settings[1], out var mode) || !Enum.IsDefined(mode) ||
                settings.Any(s => s.Contains('\n') || s.Contains('\r') ||
                    (double.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out var n) && !double.IsFinite(n))))
                throw Invalid();
            var rows = package.Layout.Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
            var keys = new HashSet<string>(StringComparer.Ordinal);
            foreach (var row in rows)
            {
                var parts = row.Split(',', StringSplitOptions.TrimEntries);
                if (parts.Length is < 5 or > 11 || !keys.Add(parts[0]) ||
                    parts[0] is not ("Notice" or "Squads" or "Members" or "Chat" or "Mission") ||
                    parts.Skip(1).Take(4).Concat(parts.Skip(8)).Any(s =>
                        !double.TryParse(s, NumberStyles.Float, CultureInfo.InvariantCulture, out var n) || !double.IsFinite(n)))
                    throw Invalid();
            }
            if (!keys.Any(k => k != "Mission")) throw Invalid();
            // Legacy packages may lack later modules/fields. Use the same safe defaults as WPF.
            var parsed = InformationOverlayLayoutItem.ParseMany(package.Layout).ToDictionary(i => i.Key);
            var layout = InformationOverlayDefaults.CreateLayout(InformationOverlayPresetCodec.DefaultPresetId)
                .Select(item => parsed.GetValueOrDefault(item.Key, item));
            OverlaySourceExport? transfer = package.Version == 2
                ? OverlayPresetSourcesCodec.ForTransfer(OverlayPresetSourcesCodec.Parse(package.Sources?.GetRawText() ?? "")) : null;
            return new(package.Version, name, OverlayDisplaySettings.Parse(package.Settings).Serialize(),
                InformationOverlayLayoutItem.SerializeMany(layout),
                transfer is null ? null : JsonSerializer.Deserialize<JsonElement>(OverlayPresetSourcesCodec.Serialize(transfer.Sources)),
                package.RemovedOrganizationBindings || transfer?.RemovedOrganizationBindings == true);
        }
        catch (Exception error) when (error is JsonException or InvalidOperationException or ArgumentException or FormatException)
        {
            throw Invalid();
        }
    }

    // Preserve the exact four-field v1 format for WPF and old relay deployments.
    internal string Serialize() => Version == 1
        ? JsonSerializer.Serialize(new { Version, Name, Settings, Layout }) : JsonSerializer.Serialize(this);
    private static OverlaySettingsException Invalid() => new("overlay.shared_preset_invalid");
}
