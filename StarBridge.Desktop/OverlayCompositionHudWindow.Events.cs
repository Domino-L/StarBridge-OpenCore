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
        var contentWidth = Math.Max(1, (float)rect.Width - 86);
        var layouts = state.EventRows.Select(row =>
        {
            var titleHeight = MeasureWrappedTextHeight(row.Title, _eventTitleFormat, contentWidth, 34, 15);
            var detailHeight = MeasureWrappedTextHeight(row.Detail, _eventDetailFormat, contentWidth, 48, 14);
            return (TitleHeight: titleHeight, Height: Math.Max(64, 10 + titleHeight + 6 + detailHeight + 10));
        }).ToArray();
        var stack = OverlayEventStackLayout.Arrange(state.EventRows.Select((row, index) =>
            new OverlayEventStackLayout.Row(layouts[index].Height, row.MotionProgress, row.IsEntering, row.IsExiting)).ToArray(), 8);
        for (var index = 0; index < state.EventRows.Count; index++)
        {
            var row = state.EventRows[index];
            var titleHeight = layouts[index].TitleHeight;
            var itemHeight = layouts[index].Height;
            var y = (float)rect.Y + stack.Slots[index].Top + stack.Slots[index].OffsetY;
            var fade = Math.Clamp(row.Opacity, 0, 1);
            var x = (float)rect.X + row.SlideOffsetX;
            var backgroundAlpha = state.Opacity * state.EventStyle.BackgroundOpacity * fade;
            var textAlpha = state.Opacity * state.EventStyle.TextOpacity * fade;
            var chromeAlpha = state.Opacity * state.EventStyle.DecorationOpacity * fade;
            FillRect(target, x, y, (float)rect.Width, itemHeight, state.Palette.PanelBackground, backgroundAlpha);
            DrawRectangle(target, x, y, (float)rect.Width, itemHeight, state.Palette.PanelBorder, chromeAlpha, 1);
            FillRect(target, x + 12, y + 12, 4, itemHeight - 24, state.Palette.Title, chromeAlpha * 0.9f);
            DrawWrappedText(target, row.Title, _eventTitleFormat, x + 28, y + 8, contentWidth, 34, state.Palette.Title, textAlpha);
            DrawWrappedText(target, row.Detail, _eventDetailFormat, x + 28, y + 10 + titleHeight + 6, contentWidth, 48, state.Palette.Text, textAlpha);
            DrawText(target, row.Timestamp, _mutedRightFormat, x + (float)rect.Width - 58, y + 8, 46, 16, state.Palette.Muted, textAlpha);
        }
    }

    private static bool IsPartySceneLabel(string value) =>
        value.Contains("房间", StringComparison.OrdinalIgnoreCase) ||
        value.Contains("PARTY", StringComparison.OrdinalIgnoreCase);
}
