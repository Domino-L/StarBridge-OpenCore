using Vortice.Direct2D1;
using Vortice.DirectWrite;

namespace StarBridge.Desktop;

internal sealed partial class OverlayCompositionHudWindow
{
    private bool DrawModuleEmptyMessage(ID2D1RenderTarget target, string? message, float x, float y,
        float width, float height, OverlayCompositionFrameState state, double opacity)
    {
        if (message is null) return false;
        if (width > 0 && height > 0)
            DrawWrappedText(target, message, _mutedFormat, x, y, width, Math.Min(48, height), state.Palette.Muted, opacity);
        return true;
    }

    // Reuses each skin's title/body typography and palette. Reserve a bounded
    // header slot rather than appending to semantic titles or overlapping meta.
    private void DrawSourceHeader(ID2D1RenderTarget target, string title, string? source,
        IDWriteTextFormat? titleFormat, float x, float y, float width,
        OverlayCompositionFrameState state, double opacity)
    {
        if (string.IsNullOrWhiteSpace(source))
        {
            DrawText(target, title, titleFormat, x, y, width, 22, state.Palette.Title, opacity);
            return;
        }
        var labelWidth = Math.Min(Math.Max(1, width * 0.46f), MeasureTextWidth(source, _mutedFormat) + 12);
        var titleWidth = Math.Max(1, width - labelWidth - 8);
        var labelX = x + titleWidth + 8;
        DrawText(target, title, titleFormat, x, y, titleWidth, 22, state.Palette.Title, opacity);
        DrawRectangle(target, labelX, y + 2, labelWidth, 18, state.Palette.Muted, opacity * 0.6, 1);
        DrawText(target, source, _mutedFormat, labelX + 6, y + 3, Math.Max(1, labelWidth - 12), 16,
            state.Palette.Muted, opacity);
    }
}
