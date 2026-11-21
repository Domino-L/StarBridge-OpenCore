namespace StarBridge.Desktop;

/// <summary>
/// Display stand-ins for a place or ship that is not known yet. They are shown
/// as they are, but they are never a place or a ship: event rules treat them as
/// no value, so "not known" to "known" is not a move (11-15 user: "还会出现莫名出现
/// 到达地点待确认 确认为当前地点的问题，我一直在现在这个地点连船都没上").
/// </summary>
internal static class OverlayPlaceholderText
{
    internal const string LocationZh = "等待位置确认";
    internal const string LocationEn = "Location pending";
    internal const string ShipZh = "等待舰船确认";
    internal const string ShipEn = "Ship pending";
    internal const string PendingLocationTraditional = "地點待確認";

    private static readonly string[] All =
    [
        LocationZh, LocationEn, ShipZh, ShipEn,
        LocationArrivalPresentation.PendingLocation, PendingLocationTraditional,
    ];

    internal static string Location(bool zh) => zh ? LocationZh : LocationEn;

    internal static string Ship(bool zh) => zh ? ShipZh : ShipEn;

    internal static bool Is(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return false;
        var text = value.Trim();
        return All.Any(placeholder => placeholder.Equals(text, StringComparison.OrdinalIgnoreCase));
    }
}
