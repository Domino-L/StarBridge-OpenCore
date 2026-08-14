using System.Windows;
using System.Windows.Controls;

namespace StarBridge.Desktop.Controls;

public enum DirectoryRegion
{
    List,
    Sidebar
}

/// <summary>
/// Shared list-sidebar layout used by Bridge directory surfaces.
///
/// Pages own their content and row structure. This panel owns the horizontal
/// relationship between the scan surface and its contextual sidebar, so every
/// consumer keeps one spacing and responsive-width contract without assuming
/// what the sidebar contains.
/// </summary>
public sealed class DirectorySplitPanel : Grid
{
    public static readonly DependencyProperty ListWidthProperty =
        DependencyProperty.Register(
            nameof(ListWidth),
            typeof(GridLength),
            typeof(DirectorySplitPanel),
            new FrameworkPropertyMetadata(
                new GridLength(2.05, GridUnitType.Star),
                FrameworkPropertyMetadataOptions.AffectsMeasure,
                OnLayoutPropertyChanged));

    public static readonly DependencyProperty SidebarWidthProperty =
        DependencyProperty.Register(
            nameof(SidebarWidth),
            typeof(GridLength),
            typeof(DirectorySplitPanel),
            new FrameworkPropertyMetadata(
                new GridLength(1, GridUnitType.Star),
                FrameworkPropertyMetadataOptions.AffectsMeasure,
                OnLayoutPropertyChanged));

    public static readonly DependencyProperty SidebarMinWidthProperty =
        DependencyProperty.Register(
            nameof(SidebarMinWidth),
            typeof(double),
            typeof(DirectorySplitPanel),
            new FrameworkPropertyMetadata(
                320d,
                FrameworkPropertyMetadataOptions.AffectsMeasure,
                OnLayoutPropertyChanged),
            value => (double)value >= 0);

    public static readonly DependencyProperty GapProperty =
        DependencyProperty.Register(
            nameof(Gap),
            typeof(double),
            typeof(DirectorySplitPanel),
            new FrameworkPropertyMetadata(
                14d,
                FrameworkPropertyMetadataOptions.AffectsMeasure,
                OnLayoutPropertyChanged),
            value => (double)value >= 0);

    public static readonly DependencyProperty RegionProperty =
        DependencyProperty.RegisterAttached(
            "Region",
            typeof(DirectoryRegion),
            typeof(DirectorySplitPanel),
            new FrameworkPropertyMetadata(DirectoryRegion.List, OnRegionChanged));

    public GridLength ListWidth
    {
        get => (GridLength)GetValue(ListWidthProperty);
        set => SetValue(ListWidthProperty, value);
    }

    public GridLength SidebarWidth
    {
        get => (GridLength)GetValue(SidebarWidthProperty);
        set => SetValue(SidebarWidthProperty, value);
    }

    public double SidebarMinWidth
    {
        get => (double)GetValue(SidebarMinWidthProperty);
        set => SetValue(SidebarMinWidthProperty, value);
    }

    public double Gap
    {
        get => (double)GetValue(GapProperty);
        set => SetValue(GapProperty, value);
    }

    public static void SetRegion(DependencyObject element, DirectoryRegion value) =>
        element.SetValue(RegionProperty, value);

    public static DirectoryRegion GetRegion(DependencyObject element) =>
        (DirectoryRegion)element.GetValue(RegionProperty);

    protected override void OnInitialized(EventArgs e)
    {
        base.OnInitialized(e);
        RebuildColumns();
        ApplyRegions();
    }

    protected override void OnVisualChildrenChanged(DependencyObject visualAdded, DependencyObject visualRemoved)
    {
        base.OnVisualChildrenChanged(visualAdded, visualRemoved);
        if (visualAdded is UIElement element)
        {
            ApplyRegion(element);
        }
    }

    private static void OnLayoutPropertyChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        if (d is DirectorySplitPanel panel)
        {
            panel.RebuildColumns();
        }
    }

    private static void OnRegionChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        if (d is UIElement element)
        {
            ApplyRegion(element);
        }
    }

    private static void ApplyRegion(UIElement element)
    {
        SetColumn(element, GetRegion(element) == DirectoryRegion.Sidebar ? 2 : 0);
    }

    private void ApplyRegions()
    {
        foreach (UIElement child in Children)
        {
            ApplyRegion(child);
        }
    }

    private void RebuildColumns()
    {
        ColumnDefinitions.Clear();
        ColumnDefinitions.Add(new ColumnDefinition { Width = ListWidth });
        ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(Gap) });
        ColumnDefinitions.Add(new ColumnDefinition
        {
            Width = SidebarWidth,
            MinWidth = SidebarMinWidth
        });
    }
}
