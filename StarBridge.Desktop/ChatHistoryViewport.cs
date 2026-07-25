using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;

namespace StarBridge.Desktop;

public readonly record struct ChatScrollAnchor(double ExtentHeight, double VerticalOffset);

/// <summary>
/// Hides WPF scroll anchoring details from every chat surface.
/// </summary>
public static class ChatHistoryViewport
{
    private const double EdgeTolerance = 24;
    private const double HistoryPrefetchDistance = 180;
    private const double WheelScrollDistance = 36;
    private const double MaximumPendingDistance = 108;
    private const double ScrollResponse = 34;
    private static readonly ConditionalWeakTable<System.Windows.Controls.ListBox, SmoothScrollState> SmoothScrollStates = new();

    public static ScrollViewer? Find(DependencyObject? root)
    {
        if (root is null)
        {
            return null;
        }

        if (root is ScrollViewer viewer)
        {
            return viewer;
        }

        for (var index = 0; index < VisualTreeHelper.GetChildrenCount(root); index++)
        {
            if (Find(VisualTreeHelper.GetChild(root, index)) is { } child)
            {
                return child;
            }
        }

        return null;
    }

    public static bool IsNearTop(ScrollViewer viewer) => viewer.VerticalOffset <= EdgeTolerance;

    public static bool IsNearBottom(ScrollViewer viewer) =>
        viewer.ScrollableHeight - viewer.VerticalOffset <= EdgeTolerance;

    public static bool ShouldLoadOlder(ScrollViewer viewer) =>
        viewer.VerticalOffset <= HistoryPrefetchDistance;

    public static void EnableSmoothScrolling(System.Windows.Controls.ListBox list)
    {
        ArgumentNullException.ThrowIfNull(list);
        if (SmoothScrollStates.TryGetValue(list, out _))
        {
            return;
        }

        var state = new SmoothScrollState(list);
        SmoothScrollStates.Add(list, state);
        list.PreviewMouseWheel += state.OnPreviewMouseWheel;
        list.PreviewMouseDown += state.OnPreviewMouseDown;
    }

    public static ChatScrollAnchor Capture(System.Windows.Controls.ListBox list)
    {
        list.UpdateLayout();
        var viewer = Find(list);
        return viewer is null
            ? default
            : new ChatScrollAnchor(viewer.ExtentHeight, viewer.VerticalOffset);
    }

    public static void RestoreAfterPrepend(System.Windows.Controls.ListBox list, ChatScrollAnchor anchor)
    {
        list.UpdateLayout();
        if (Find(list) is not { } viewer)
        {
            return;
        }

        var addedExtent = Math.Max(0, viewer.ExtentHeight - anchor.ExtentHeight);
        viewer.ScrollToVerticalOffset(anchor.VerticalOffset + addedExtent);
        if (SmoothScrollStates.TryGetValue(list, out var state))
        {
            state.AdjustTargetAfterPrepend(addedExtent);
        }
    }

    public static void ScrollToLatest(System.Windows.Controls.ListBox list)
    {
        list.UpdateLayout();
        Find(list)?.ScrollToEnd();
        ResetTargetAfterExternalScroll(list);
    }

    private static void ResetTargetAfterExternalScroll(System.Windows.Controls.ListBox list)
    {
        if (SmoothScrollStates.TryGetValue(list, out var state))
        {
            state.ResetTargetAfterExternalScroll();
        }
    }

    private sealed class SmoothScrollState(System.Windows.Controls.ListBox list)
    {
        private ScrollViewer? _viewer;
        private double _targetOffset;
        private TimeSpan _lastRenderingTime;
        private bool _isRendering;

        public void OnPreviewMouseWheel(object sender, MouseWheelEventArgs e)
        {
            _viewer = Find(list);
            if (_viewer is null || _viewer.ScrollableHeight <= 0)
            {
                return;
            }

            var wheelSteps = e.Delta / 120d;
            if (Math.Abs(wheelSteps) < double.Epsilon)
            {
                return;
            }

            if (!_isRendering)
            {
                _targetOffset = _viewer.VerticalOffset;
            }

            var currentOffset = _viewer.VerticalOffset;
            var inputDistance = -wheelSteps * WheelScrollDistance;
            var pendingDistance = _targetOffset - currentOffset;
            if (Math.Abs(pendingDistance) > 0.35 && Math.Sign(inputDistance) != Math.Sign(pendingDistance))
            {
                _targetOffset = currentOffset;
            }

            _targetOffset = Math.Clamp(
                _targetOffset + inputDistance,
                Math.Max(0, currentOffset - MaximumPendingDistance),
                Math.Min(_viewer.ScrollableHeight, currentOffset + MaximumPendingDistance));
            e.Handled = true;

            if (!SystemParameters.ClientAreaAnimation)
            {
                _viewer.ScrollToVerticalOffset(_targetOffset);
                ResetTargetAfterExternalScroll();
                return;
            }

            if (_isRendering)
            {
                return;
            }

            _isRendering = true;
            _lastRenderingTime = default;
            CompositionTarget.Rendering += OnRendering;
        }

        public void OnPreviewMouseDown(object sender, MouseButtonEventArgs e) =>
            ResetTargetAfterExternalScroll();

        public void ResetTargetAfterExternalScroll()
        {
            StopRendering();
            _viewer = Find(list);
            _targetOffset = _viewer?.VerticalOffset ?? 0;
        }

        public void AdjustTargetAfterPrepend(double addedExtent)
        {
            _viewer = Find(list);
            if (_viewer is null)
            {
                return;
            }

            _targetOffset = _isRendering
                ? Math.Clamp(_targetOffset + addedExtent, 0, _viewer.ScrollableHeight)
                : _viewer.VerticalOffset;
        }

        private void OnRendering(object? sender, EventArgs e)
        {
            if (_viewer is null || !list.IsVisible)
            {
                ResetTargetAfterExternalScroll();
                return;
            }

            var renderingTime = e is RenderingEventArgs renderingArgs
                ? renderingArgs.RenderingTime
                : TimeSpan.Zero;
            var elapsedSeconds = _lastRenderingTime == default || renderingTime <= _lastRenderingTime
                ? 1d / 60d
                : Math.Min(0.05, (renderingTime - _lastRenderingTime).TotalSeconds);
            _lastRenderingTime = renderingTime;

            _targetOffset = Math.Clamp(_targetOffset, 0, _viewer.ScrollableHeight);
            var remaining = _targetOffset - _viewer.VerticalOffset;
            if (Math.Abs(remaining) <= 0.35)
            {
                _viewer.ScrollToVerticalOffset(_targetOffset);
                StopRendering();
                return;
            }

            var interpolation = 1 - Math.Exp(-ScrollResponse * elapsedSeconds);
            _viewer.ScrollToVerticalOffset(_viewer.VerticalOffset + remaining * interpolation);
        }

        private void StopRendering()
        {
            if (!_isRendering)
            {
                return;
            }

            CompositionTarget.Rendering -= OnRendering;
            _isRendering = false;
            _lastRenderingTime = default;
        }
    }
}
