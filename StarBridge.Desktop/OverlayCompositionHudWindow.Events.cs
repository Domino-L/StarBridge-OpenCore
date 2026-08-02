using Vortice.Direct2D1;

namespace StarBridge.Desktop;

internal sealed partial class OverlayCompositionHudWindow
{
    private void DrawEventNotifications(ID2D1RenderTarget target, OverlayCompositionFrameState state)
    {
        if (state.LagrangeWeaveStyle)
        {
            DrawLagrangeEventNotifications(target, state);
            return;
        }

        var rect = state.EventRect;
        var y = (float)rect.Y;
        foreach (var row in state.EventRows)
        {
            var contentWidth = Math.Max(1, (float)rect.Width - 86);
            var titleHeight = MeasureWrappedTextHeight(row.Title, _eventTitleFormat, contentWidth, 34, 15);
            var detailHeight = MeasureWrappedTextHeight(row.Detail, _eventDetailFormat, contentWidth, 48, 14);
            var itemHeight = Math.Max(64, 10 + titleHeight + 6 + detailHeight + 10);
            var fade = Math.Clamp(row.Opacity, 0, 1);
            var x = (float)rect.X + row.SlideOffsetX;
            var backgroundAlpha = state.Opacity * state.EventStyle.BackgroundOpacity * fade;
            var textAlpha = state.Opacity * state.EventStyle.TextOpacity * fade;
            var chromeAlpha = state.Opacity * fade;
            FillRect(target, x, y, (float)rect.Width, itemHeight, state.Palette.PanelBackground, backgroundAlpha);
            DrawRectangle(target, x, y, (float)rect.Width, itemHeight, state.Palette.PanelBorder, chromeAlpha, 1);
            FillRect(target, x + 12, y + 12, 4, itemHeight - 24, row.AccentColor, chromeAlpha * 0.9f);
            DrawWrappedText(target, row.Title, _eventTitleFormat, x + 28, y + 8, contentWidth, 34, row.AccentColor, textAlpha);
            DrawWrappedText(target, row.Detail, _eventDetailFormat, x + 28, y + 10 + titleHeight + 6, contentWidth, 48, state.Palette.Text, textAlpha);
            DrawText(target, row.Timestamp, _mutedRightFormat, x + (float)rect.Width - 58, y + 8, 46, 16, state.Palette.Muted, textAlpha);
            y += itemHeight + 8;
        }
    }

    private static bool IsPartySceneLabel(string value) =>
        value.Contains("房间", StringComparison.OrdinalIgnoreCase) ||
        value.Contains("PARTY", StringComparison.OrdinalIgnoreCase);
}
