namespace StarBridge.OverlayRuntime.Windows;

using System.Drawing;
using StarBridge.HostRuntime.Tools;

public static class ExecHangarGameOverlayPlacement
{
    public static Rectangle ForGame(Rectangle client, uint dpi, string position, double contentWidth = ExecHangarGameOverlayCard.CardWidth)
    {
        if (client.Width <= 0 || client.Height <= 0 || !ExecHangarGameOverlay.Positions.Contains(position) ||
            !double.IsFinite(contentWidth) || contentWidth < 1 || contentWidth > 400)
            throw new ArgumentException("Invalid game placement.");
        var scale = Math.Clamp(dpi / 96d, .5, 4);
        var margin = Math.Min((int)Math.Round(16 * scale), Math.Min(client.Width, client.Height) / 4);
        var availableWidth = Math.Max(1, client.Width - margin * 2);
        var availableHeight = Math.Max(1, client.Height - margin * 2);
        var width = Math.Min(availableWidth, (int)Math.Ceiling(contentWidth * scale));
        var height = Math.Min(availableHeight, (int)Math.Ceiling(ExecHangarGameOverlayCard.CardHeight * scale));
        var x = position.EndsWith("Left", StringComparison.Ordinal) ? client.Left + margin
            : position.EndsWith("Right", StringComparison.Ordinal) ? client.Right - margin - width
            : client.Left + (client.Width - width) / 2;
        var y = position.StartsWith("top", StringComparison.Ordinal) ? client.Top + margin : client.Bottom - margin - height;
        return new(x, y, width, height);
    }
}
