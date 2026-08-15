namespace StarBridge.Desktop;

public static class OverlayEventShipPresentation
{
    public static string FormatShipChange(string displayName, string ship, bool zh)
    {
        var localizedShip = zh
            ? ShipDisplayNamePresentation.ResolveChinese(
                ship,
                ShipDisplayNamePresentation.UnknownShip)
            : ShipNameLocalizer.DisplayName(
                ShipNameLocalizer.ResolveCode(ship),
                "en");

        return zh
            ? $"{displayName} 切换飞船：{localizedShip}"
            : $"{displayName} switched ship: {localizedShip}";
    }
}
