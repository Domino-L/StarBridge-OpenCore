namespace StarBridge.Desktop;

public static class OverlayEventShipPresentation
{
    public static string FormatShipChange(string displayName, string ship, bool zh)
    {
        var localizedShip = ShipNameLocalizer.DisplayName(
            ShipNameLocalizer.ResolveCode(ship),
            zh ? "zh" : "en");

        return zh
            ? $"{displayName} 切换飞船：{localizedShip}"
            : $"{displayName} switched ship: {localizedShip}";
    }
}
