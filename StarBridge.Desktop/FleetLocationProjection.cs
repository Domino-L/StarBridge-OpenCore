namespace StarBridge.Desktop;

using StarBridge.Core.Presence;

internal readonly record struct FleetLocationValue(string Key, string DisplayName);

/// <summary>
/// Owns the single normalization and display seam for fleet-presence locations.
/// Consumers compare <see cref="FleetLocationValue.Key"/> and render its display
/// name; presentation prefixes never become part of the grouping identity.
/// </summary>
internal static class FleetLocationProjection
{
    private static readonly string[] PresentationPrefixes =
    [
        "地点：",
        "地点:",
        "位置：",
        "位置:",
        "Location:",
        "可能在：",
        "可能在:",
        "可能离开：",
        "可能离开:"
    ];

    internal static FleetLocationValue? Resolve(PlayerRow player, string? language)
    {
        ArgumentNullException.ThrowIfNull(player);
        if (player.SharedPresence != PlayerPresenceKind.InGame)
        {
            return null;
        }

        var raw = !string.IsNullOrWhiteSpace(player.SharedLocation)
            ? player.SharedLocation
            : !string.IsNullOrWhiteSpace(player.RawLocation)
                ? player.RawLocation
                : player.Location;
        return Resolve(raw, language);
    }

    internal static FleetLocationValue? Resolve(string? raw, string? language)
    {
        var normalized = NormalizeKey(raw);
        if (normalized is null)
        {
            return null;
        }

        var displayName = LocationNameLocalizer.DisplayName(
            normalized,
            language?.Equals("zh", StringComparison.OrdinalIgnoreCase) == true ? "zh" : "en");
        return PlayerSessionStatePresentation.HasRecognizedValue(displayName)
            ? new FleetLocationValue(normalized, displayName.Trim())
            : null;
    }

    internal static string? NormalizeKey(string? raw)
    {
        if (!PlayerSessionStatePresentation.HasRecognizedValue(raw))
        {
            return null;
        }

        var value = raw!.Trim();
        foreach (var prefix in PresentationPrefixes)
        {
            if (value.StartsWith(prefix, StringComparison.OrdinalIgnoreCase))
            {
                value = value[prefix.Length..].Trim();
                break;
            }
        }

        var normalized = LocationNameLocalizer.NormalizeLocation(value).Trim();
        return PlayerSessionStatePresentation.HasRecognizedValue(normalized)
            ? normalized
            : null;
    }
}
