namespace StarBridge.Core.Ships;

/// <summary>Exact local catalog presentation, not server classification or scheduling policy.</summary>
public static class ShipCatalogIconKey
{
    public static string? Resolve(string role, string tags, string? size)
    {
        if (size is not ("small" or "medium" or "large" or "capital")) return null;
        var parts = role.Split('/').Select(p => p.Trim().ToLowerInvariant()).ToArray();
        var markers = tags.Split(',', ';', '|', ' ').Select(p => p.Trim().ToLowerInvariant());
        // A ground vehicle must never acquire a spacecraft silhouette.
        if (markers.Any(p => p is "vehicle" or "ground") ||
            parts.Any(p => p.Contains("ground", StringComparison.Ordinal) ||
                           p.Contains("vehicle", StringComparison.Ordinal))) return null;
        var category = parts[0] switch
        {
            "combat" => "combat",
            "exploration" => "exploration",
            "industrial" => "industrial",
            "support" => "support",
            "competition" when size != "capital" => "competition",
            "transport" when parts.Skip(1).Any(p => p.Contains("cargo", StringComparison.Ordinal) ||
                                                     p.Contains("freight", StringComparison.Ordinal)) => "logistics",
            _ => null
        };
        return category is null ? null : $"{category}-{size}";
    }
}
