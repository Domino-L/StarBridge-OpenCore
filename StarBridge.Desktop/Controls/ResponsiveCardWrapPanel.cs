using System.Windows;
using WpfPanel = System.Windows.Controls.Panel;
using WpfRect = System.Windows.Rect;
using WpfSize = System.Windows.Size;

namespace StarBridge.Desktop.Controls;

/// <summary>
/// Arranges directory cards with the single Find Fleet responsive policy.
/// The panel consumes the width assigned by its ScrollViewer; it does not
/// inspect the owning Window or reproduce layout constants.
/// </summary>
public sealed class ResponsiveCardWrapPanel : WpfPanel
{
    protected override WpfSize MeasureOverride(WpfSize availableSize)
    {
        var availableWidth = ResolveAvailableWidth(availableSize.Width);
        var layout = FindFleetDirectoryLayout.ResolveGrid(availableWidth);
        foreach (UIElement child in InternalChildren)
        {
            child.Measure(new WpfSize(layout.ItemWidth, double.PositiveInfinity));
        }

        return new WpfSize(layout.ContentWidth, ResolveContentHeight(layout));
    }

    protected override WpfSize ArrangeOverride(WpfSize finalSize)
    {
        var availableWidth = ResolveAvailableWidth(finalSize.Width);
        var layout = FindFleetDirectoryLayout.ResolveGrid(availableWidth);
        var y = 0d;

        for (var rowStart = 0; rowStart < InternalChildren.Count; rowStart += layout.ColumnCount)
        {
            var rowEnd = Math.Min(rowStart + layout.ColumnCount, InternalChildren.Count);
            var rowHeight = 0d;
            for (var index = rowStart; index < rowEnd; index++)
            {
                rowHeight = Math.Max(rowHeight, InternalChildren[index].DesiredSize.Height);
            }

            for (var index = rowStart; index < rowEnd; index++)
            {
                var column = index - rowStart;
                var x = column * (layout.ItemWidth + FindFleetDirectoryLayout.ItemGap);
                InternalChildren[index].Arrange(new WpfRect(x, y, layout.ItemWidth, rowHeight));
            }

            y += rowHeight;
            if (rowEnd < InternalChildren.Count)
            {
                y += FindFleetDirectoryLayout.ItemGap;
            }
        }

        return finalSize;
    }

    private double ResolveContentHeight(FindFleetGridResolution layout)
    {
        var height = 0d;
        for (var rowStart = 0; rowStart < InternalChildren.Count; rowStart += layout.ColumnCount)
        {
            var rowEnd = Math.Min(rowStart + layout.ColumnCount, InternalChildren.Count);
            var rowHeight = 0d;
            for (var index = rowStart; index < rowEnd; index++)
            {
                rowHeight = Math.Max(rowHeight, InternalChildren[index].DesiredSize.Height);
            }

            height += rowHeight;
            if (rowEnd < InternalChildren.Count)
            {
                height += FindFleetDirectoryLayout.ItemGap;
            }
        }

        return height;
    }

    private double ResolveAvailableWidth(double layoutWidth)
    {
        if (double.IsFinite(layoutWidth) && layoutWidth > 0d)
        {
            return layoutWidth;
        }

        if (double.IsFinite(ActualWidth) && ActualWidth > 0d)
        {
            return ActualWidth;
        }

        return FindFleetDirectoryLayout.MinItemWidth;
    }
}
