namespace StarBridge.Desktop;

public static class OverlayEventShipPresentation
{
    public static string ShipName(string ship, bool zh) => zh
        ? ShipDisplayNamePresentation.ResolveChinese(
            ship,
            ShipDisplayNamePresentation.UnknownShip)
        : ShipNameLocalizer.DisplayName(
            ShipNameLocalizer.ResolveCode(ship),
            "en");

    public static string FormatShipChange(string displayName, string ship, bool zh)
    {
        var localizedShip = ShipName(ship, zh);

        return zh
            ? $"{displayName} 切换飞船：{localizedShip}"
            : $"{displayName} switched ship: {localizedShip}";
    }
}
