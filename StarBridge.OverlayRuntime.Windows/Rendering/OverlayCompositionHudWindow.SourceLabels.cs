using System.Globalization;
using Vortice.Direct2D1;
using Vortice.DirectWrite;

namespace StarBridge.Desktop;

internal sealed partial class OverlayCompositionHudWindow
{
    // The one accent every appearance uses for a module with its own source.
    private static readonly HudColor SourceOwnAccent = HudColor.FromRgb(245, 181, 68);
    private const float SourceLabelGap = 6;
    private const float SourceLabelMinimumWidth = 28;
    private readonly Dictionary<(string Text, int Width), string> _sourceLabelFitCache = [];
    private readonly Dictionary<(IDWriteTextFormat Format, string Title, string Label), float> _sourceLabelBaselines = [];

    // A status headline on one line; the reason and the switch hint only on the
    // module chosen to explain this problem. Unavailable reads amber, syncing reads
    // as ordinary text. Uses the skin's event typography and palette.
    private bool DrawModuleEmptyMessage(ID2D1RenderTarget target, OverlayModuleEmptyState? message, float x, float y,
        float width, float height, OverlayCompositionFrameState state, double opacity)
    {
        if (message is null) return false;
        if (width <= 0 || height <= 0) return true;
        var bottom = y + height;
        var headlineHeight = Math.Min(height, MeasureWrappedTextHeight(message.Headline, _eventTitleFormat, width, 34, 16));
        DrawWrappedText(target, message.Headline, _eventTitleFormat, x, y, width, headlineHeight,
            message.Kind == OverlayModuleEmptyKind.Syncing ? state.Palette.Text : SourceOwnAccent, opacity);
        if (!message.Expanded) return true;
        var cursor = y + headlineHeight + 3;
        foreach (var (text, color) in new[] { (message.Detail, state.Palette.Muted), (message.Hint, state.Palette.Title) })
        {
            if (string.IsNullOrWhiteSpace(text) || bottom - cursor < 12) continue;
            var lineHeight = Math.Min(bottom - cursor, MeasureWrappedTextHeight(text, _eventDetailFormat, width, 32, 15));
            DrawWrappedText(target, text, _eventDetailFormat, x, cursor, width, lineHeight, color, opacity);
            cursor += lineHeight + 2;
        }
        return true;
    }

    // The one title helper for every public appearance: the skin's own title,
    // then a smaller trailing "· source" in the skin's muted colour (amber when
    // the module has its own source). Nothing else in the header changes.
    private void DrawSourceHeader(ID2D1RenderTarget target, string title, string? source, bool own,
        IDWriteTextFormat? titleFormat, float x, float y, float width,
        OverlayCompositionFrameState state, double opacity, HudColor? titleColor = null)
    {
        DrawText(target, title, titleFormat, x, y, width, 22, titleColor ?? state.Palette.Title, opacity);
        if (string.IsNullOrWhiteSpace(source)) return;
        var labelX = x + Math.Min(width, MeasureTextWidth(title, titleFormat)) + SourceLabelGap;
        var labelWidth = x + width - labelX;
        if (labelWidth < SourceLabelMinimumWidth) return;
        var label = FitSourceLabel(SourceLabelText(source), labelWidth);
        if (label.Length == 0) return;
        DrawText(target, label, _sourceLabelFormat, labelX, y + SourceLabelOffset(title, titleFormat, label),
            labelWidth, 22, own ? SourceOwnAccent : state.Palette.Muted, opacity);
    }

    private void ResetSourceLabelCaches()
    {
        _sourceLabelFitCache.Clear();
        _sourceLabelBaselines.Clear();
    }

    // Sits the label on the title's baseline, whatever the skin's title size or
    // vertical alignment (panel titles are centred, event titles top-aligned).
    private float SourceLabelOffset(string title, IDWriteTextFormat? titleFormat, string label)
    {
        if (_writeFactory is null || titleFormat is null || _sourceLabelFormat is null) return 1;
        var key = (titleFormat, title, label);
        if (_sourceLabelBaselines.TryGetValue(key, out var offset)) return offset;
        offset = Baseline(title, titleFormat) - Baseline(label, _sourceLabelFormat);
        if (_sourceLabelBaselines.Count >= 64) _sourceLabelBaselines.Clear();
        _sourceLabelBaselines[key] = offset;
        return offset;
    }

    private float Baseline(string text, IDWriteTextFormat format)
    {
        using var layout = _writeFactory!.CreateTextLayout(text, format, 4096, 22);
        var lines = new LineMetrics[2];
        layout.GetLineMetrics(lines, out var count);
        return layout.Metrics.Top + (count > 0 ? lines[0].Baseline : 0);
    }

    private static string SourceLabelText(string source) => "· " + source;

    // Header space a source label wants, for layouts that share the title row.
    private float SourceLabelSpace(string? source) => string.IsNullOrWhiteSpace(source) ? 0
        : MeasureTextWidth(SourceLabelText(source), _sourceLabelFormat, 48) + SourceLabelGap + 8;

    // Trims by whole text elements with an ellipsis; cached per label and width.
    private string FitSourceLabel(string text, float width)
    {
        var key = (text, (int)width);
        if (_sourceLabelFitCache.TryGetValue(key, out var fitted)) return fitted;
        fitted = text;
        if (MeasureSourceLabel(text) > width)
        {
            var stops = StringInfo.ParseCombiningCharacters(text);
            var low = 0;
            var high = stops.Length - 1;
            while (low < high)
            {
                var mid = (low + high + 1) / 2;
                if (MeasureSourceLabel(text[..stops[mid]].TrimEnd() + "…") <= width) low = mid;
                else high = mid - 1;
            }
            // "· " alone says nothing; draw no label rather than a bare dot.
            fitted = low < 3 ? "" : text[..stops[low]].TrimEnd() + "…";
        }
        if (_sourceLabelFitCache.Count >= 64) _sourceLabelFitCache.Clear();
        _sourceLabelFitCache[key] = fitted;
        return fitted;
    }

    private float MeasureSourceLabel(string text)
    {
        if (_writeFactory is null || _sourceLabelFormat is null) return text.Length * 7f;
        using var layout = _writeFactory.CreateTextLayout(text, _sourceLabelFormat, 4096, 64);
        return layout.Metrics.WidthIncludingTrailingWhitespace;
    }
}
