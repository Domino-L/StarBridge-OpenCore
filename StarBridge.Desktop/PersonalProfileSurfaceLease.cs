using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using MediaBrushes = System.Windows.Media.Brushes;
using MediaColor = System.Windows.Media.Color;
using Panel = System.Windows.Controls.Panel;
using WpfHorizontalAlignment = System.Windows.HorizontalAlignment;

namespace StarBridge.Desktop;

/// <summary>
/// Temporarily moves the live personal-profile surface from the main window into
/// an in-game tool window, then restores every element to its original parent.
/// </summary>
internal sealed class PersonalProfileSurfaceLease : IDisposable
{
    private readonly TabItem _sourceTab;
    private readonly ContentControl _destination;
    private readonly object _profileSurface;
    private readonly object _sourcePlaceholder;
    private readonly Grid _host;
    private readonly Action? _released;
    private readonly List<OverlayPlacement> _overlayPlacements;
    private bool _disposed;

    private PersonalProfileSurfaceLease(
        TabItem sourceTab,
        ContentControl destination,
        object profileSurface,
        object sourcePlaceholder,
        Grid host,
        List<OverlayPlacement> overlayPlacements,
        Action? released)
    {
        _sourceTab = sourceTab;
        _destination = destination;
        _profileSurface = profileSurface;
        _sourcePlaceholder = sourcePlaceholder;
        _host = host;
        _overlayPlacements = overlayPlacements;
        _released = released;
    }

    internal static PersonalProfileSurfaceLease Attach(
        TabItem sourceTab,
        ContentControl destination,
        IEnumerable<FrameworkElement> overlays,
        Action? released = null)
    {
        ArgumentNullException.ThrowIfNull(sourceTab);
        ArgumentNullException.ThrowIfNull(destination);
        ArgumentNullException.ThrowIfNull(overlays);

        if (sourceTab.Content is not UIElement profileSurface)
        {
            throw new InvalidOperationException("个人资料页面当前无法移动到游戏浮层。");
        }

        var placeholder = CreateSourcePlaceholder();
        var host = new Grid
        {
            Background = MediaBrushes.Transparent,
            ClipToBounds = true
        };
        var placements = new List<OverlayPlacement>();

        sourceTab.Content = placeholder;
        host.Children.Add(profileSurface);
        Panel.SetZIndex(profileSurface, 0);

        try
        {
            var zIndex = 100;
            foreach (var overlay in overlays.Distinct())
            {
                if (VisualTreeHelper.GetParent(overlay) is not Panel parent)
                {
                    continue;
                }

                var index = parent.Children.IndexOf(overlay);
                placements.Add(new OverlayPlacement(overlay, parent, index));
                parent.Children.Remove(overlay);
                host.Children.Add(overlay);
                Panel.SetZIndex(overlay, zIndex++);
            }

            destination.Content = host;
            return new PersonalProfileSurfaceLease(
                sourceTab,
                destination,
                profileSurface,
                placeholder,
                host,
                placements,
                released);
        }
        catch
        {
            foreach (var placement in placements.AsEnumerable().Reverse())
            {
                host.Children.Remove(placement.Element);
                placement.Parent.Children.Insert(
                    Math.Clamp(placement.Index, 0, placement.Parent.Children.Count),
                    placement.Element);
            }

            host.Children.Remove(profileSurface);
            sourceTab.Content = profileSurface;
            throw;
        }
    }

    public void Dispose()
    {
        if (_disposed)
        {
            return;
        }

        _disposed = true;
        if (ReferenceEquals(_destination.Content, _host))
        {
            _destination.Content = null;
        }

        foreach (var placement in _overlayPlacements.AsEnumerable().Reverse())
        {
            _host.Children.Remove(placement.Element);
            placement.Parent.Children.Insert(
                Math.Clamp(placement.Index, 0, placement.Parent.Children.Count),
                placement.Element);
        }

        _host.Children.Remove((UIElement)_profileSurface);
        if (ReferenceEquals(_sourceTab.Content, _sourcePlaceholder))
        {
            _sourceTab.Content = _profileSurface;
        }

        _released?.Invoke();
    }

    private static Grid CreateSourcePlaceholder()
    {
        var message = new TextBlock
        {
            Text = "个人资料已在游戏浮层中打开",
            HorizontalAlignment = WpfHorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            Foreground = new SolidColorBrush(MediaColor.FromRgb(121, 165, 188)),
            FontSize = 13
        };
        return new Grid
        {
            Background = MediaBrushes.Transparent,
            Children = { message }
        };
    }

    private sealed record OverlayPlacement(
        FrameworkElement Element,
        Panel Parent,
        int Index);
}
