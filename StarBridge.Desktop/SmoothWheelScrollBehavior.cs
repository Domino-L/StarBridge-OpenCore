using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using WpfComboBox = System.Windows.Controls.ComboBox;

namespace StarBridge.Desktop;

/// <summary>
/// Gives ordinary WPF scroll surfaces interruptible, frame-synchronized wheel motion.
/// Specialized chat surfaces keep their own history-aware viewport controller.
/// </summary>
public static class SmoothWheelScrollBehavior
{
    private const double WheelDistance = 52;
    private const double ScrollResponse = 18;
    private const double CompletionTolerance = 0.3;
    private static readonly ConditionalWeakTable<ScrollViewer, ScrollState> States = new();
    private static readonly ConditionalWeakTable<WpfComboBox, DropDownBackgroundGuard> DropDownGuards = new();

    public static readonly DependencyProperty IsEnabledProperty = DependencyProperty.RegisterAttached(
        "IsEnabled",
        typeof(bool),
        typeof(SmoothWheelScrollBehavior),
        new PropertyMetadata(false, OnIsEnabledChanged));

    public static readonly DependencyProperty StopsWheelPropagationProperty = DependencyProperty.RegisterAttached(
        "StopsWheelPropagation",
        typeof(bool),
        typeof(SmoothWheelScrollBehavior),
        new PropertyMetadata(false));

    public static readonly DependencyProperty GuardsBackgroundWhileDropDownOpenProperty = DependencyProperty.RegisterAttached(
        "GuardsBackgroundWhileDropDownOpen",
        typeof(bool),
        typeof(SmoothWheelScrollBehavior),
        new PropertyMetadata(false, OnGuardsBackgroundWhileDropDownOpenChanged));

    public static bool GetIsEnabled(DependencyObject element) =>
        (bool)element.GetValue(IsEnabledProperty);

    public static void SetIsEnabled(DependencyObject element, bool value) =>
        element.SetValue(IsEnabledProperty, value);

    public static bool GetStopsWheelPropagation(DependencyObject element) =>
        (bool)element.GetValue(StopsWheelPropagationProperty);

    public static void SetStopsWheelPropagation(DependencyObject element, bool value) =>
        element.SetValue(StopsWheelPropagationProperty, value);

    public static bool GetGuardsBackgroundWhileDropDownOpen(DependencyObject element) =>
        (bool)element.GetValue(GuardsBackgroundWhileDropDownOpenProperty);

    public static void SetGuardsBackgroundWhileDropDownOpen(DependencyObject element, bool value) =>
        element.SetValue(GuardsBackgroundWhileDropDownOpenProperty, value);

    public static void SetVerticalBounds(ScrollViewer viewer, double minimum, double maximum)
    {
        ArgumentNullException.ThrowIfNull(viewer);
        if (States.TryGetValue(viewer, out var state))
        {
            state.SetVerticalBounds(minimum, maximum);
        }
    }

    public static void ClearVerticalBounds(ScrollViewer viewer)
    {
        ArgumentNullException.ThrowIfNull(viewer);
        if (States.TryGetValue(viewer, out var state))
        {
            state.ClearVerticalBounds();
        }
    }

    private static void OnIsEnabledChanged(DependencyObject dependencyObject, DependencyPropertyChangedEventArgs e)
    {
        if (dependencyObject is not ScrollViewer viewer)
        {
            return;
        }

        if (e.NewValue is true)
        {
            States.GetValue(viewer, static target => new ScrollState(target)).Attach();
            return;
        }

        if (States.TryGetValue(viewer, out var state))
        {
            state.Detach();
            States.Remove(viewer);
        }
    }

    private static void OnGuardsBackgroundWhileDropDownOpenChanged(
        DependencyObject dependencyObject,
        DependencyPropertyChangedEventArgs e)
    {
        if (dependencyObject is not WpfComboBox comboBox)
        {
            return;
        }

        if (e.NewValue is true)
        {
            DropDownGuards.GetValue(comboBox, static target => new DropDownBackgroundGuard(target)).Attach();
            return;
        }

        if (DropDownGuards.TryGetValue(comboBox, out var guard))
        {
            guard.Detach();
            DropDownGuards.Remove(comboBox);
        }
    }

    private sealed class ScrollState(ScrollViewer viewer)
    {
        private readonly WheelDirectionBounceGuard _directionGuard = new();
        private double _targetOffset;
        private TimeSpan _lastRenderingTime;
        private bool _isAttached;
        private bool _isRendering;
        private double _minimumOffset;
        private double _maximumOffset = double.PositiveInfinity;

        public void Attach()
        {
            if (_isAttached)
            {
                return;
            }

            _isAttached = true;
            _targetOffset = viewer.VerticalOffset;
            viewer.PreviewMouseWheel += OnPreviewMouseWheel;
            viewer.PreviewMouseDown += OnPreviewMouseDown;
            viewer.PreviewKeyDown += OnPreviewKeyDown;
            viewer.Unloaded += OnUnloaded;
        }

        public void Detach()
        {
            if (!_isAttached)
            {
                return;
            }

            StopRendering(resetTarget: false);
            viewer.PreviewMouseWheel -= OnPreviewMouseWheel;
            viewer.PreviewMouseDown -= OnPreviewMouseDown;
            viewer.PreviewKeyDown -= OnPreviewKeyDown;
            viewer.Unloaded -= OnUnloaded;
            _isAttached = false;
        }

        public void SetVerticalBounds(double minimum, double maximum)
        {
            minimum = Math.Max(0, minimum);
            maximum = Math.Max(minimum, maximum);
            _minimumOffset = minimum;
            _maximumOffset = maximum;
            StopRendering(resetTarget: false);
            _targetOffset = ClampToVerticalBounds(viewer.VerticalOffset);
        }

        public void ClearVerticalBounds()
        {
            _minimumOffset = 0;
            _maximumOffset = double.PositiveInfinity;
            StopRendering(resetTarget: false);
            _targetOffset = viewer.VerticalOffset;
        }

        private void OnPreviewMouseWheel(object sender, MouseWheelEventArgs e)
        {
            if (e.Handled)
            {
                return;
            }

            var route = FindScrollRoute(e.OriginalSource as DependencyObject, e.Delta);
            if (route.IsBlocked)
            {
                e.Handled = true;
                return;
            }

            if (route.Target is not { } target || !ReferenceEquals(target, viewer))
            {
                return;
            }

            var wheelSteps = e.Delta / 120d;
            if (Math.Abs(wheelSteps) < double.Epsilon)
            {
                return;
            }

            var inputDisposition = _directionGuard.Evaluate(
                e.Delta,
                Environment.TickCount64,
                _isRendering,
                IsAtVerticalBoundary(viewer));
            if (inputDisposition == WheelInputDisposition.Brake)
            {
                e.Handled = true;
                StopRendering(resetTarget: true);
                return;
            }

            if (!_isRendering)
            {
                _targetOffset = viewer.VerticalOffset;
            }

            var currentOffset = viewer.VerticalOffset;
            var inputDistance = -wheelSteps * ResolveWheelDistance(viewer);
            var pendingDistance = _targetOffset - currentOffset;
            if (Math.Abs(pendingDistance) > CompletionTolerance &&
                Math.Sign(inputDistance) != Math.Sign(pendingDistance))
            {
                _targetOffset = currentOffset;
            }

            var maximumPendingDistance = Math.Clamp(viewer.ViewportHeight * 0.55, 120, 300);
            _targetOffset = ClampToVerticalBounds(Math.Clamp(
                _targetOffset + inputDistance,
                currentOffset - maximumPendingDistance,
                currentOffset + maximumPendingDistance));
            e.Handled = true;

            if (!SystemParameters.ClientAreaAnimation)
            {
                viewer.ScrollToVerticalOffset(_targetOffset);
                StopRendering(resetTarget: true);
                return;
            }

            StartRendering();
        }

        private void OnPreviewMouseDown(object sender, MouseButtonEventArgs e) =>
            CancelInteraction();

        private void OnPreviewKeyDown(object sender, System.Windows.Input.KeyEventArgs e) =>
            CancelInteraction();

        private void OnUnloaded(object sender, RoutedEventArgs e) =>
            CancelInteraction();

        private void CancelInteraction()
        {
            _directionGuard.Reset();
            StopRendering(resetTarget: true);
        }

        private void StartRendering()
        {
            if (_isRendering)
            {
                return;
            }

            _isRendering = true;
            _lastRenderingTime = default;
            CompositionTarget.Rendering += OnRendering;
        }

        private void OnRendering(object? sender, EventArgs e)
        {
            if (!viewer.IsVisible || PresentationSource.FromVisual(viewer) is null)
            {
                StopRendering(resetTarget: true);
                return;
            }

            var renderingTime = e is RenderingEventArgs renderingArgs
                ? renderingArgs.RenderingTime
                : TimeSpan.Zero;
            var elapsedSeconds = _lastRenderingTime == default || renderingTime <= _lastRenderingTime
                ? 1d / 60d
                : Math.Min(0.04, (renderingTime - _lastRenderingTime).TotalSeconds);
            _lastRenderingTime = renderingTime;

            _targetOffset = ClampToVerticalBounds(_targetOffset);
            var remaining = _targetOffset - viewer.VerticalOffset;
            if (Math.Abs(remaining) <= CompletionTolerance)
            {
                viewer.ScrollToVerticalOffset(_targetOffset);
                StopRendering(resetTarget: true);
                return;
            }

            var interpolation = 1 - Math.Exp(-ScrollResponse * elapsedSeconds);
            viewer.ScrollToVerticalOffset(viewer.VerticalOffset + remaining * interpolation);
        }

        private void StopRendering(bool resetTarget)
        {
            if (_isRendering)
            {
                CompositionTarget.Rendering -= OnRendering;
                _isRendering = false;
                _lastRenderingTime = default;
            }

            if (resetTarget)
            {
                _targetOffset = viewer.VerticalOffset;
            }
        }

        private double ClampToVerticalBounds(double offset)
        {
            var minimum = Math.Clamp(_minimumOffset, 0, viewer.ScrollableHeight);
            var maximum = Math.Clamp(_maximumOffset, minimum, viewer.ScrollableHeight);
            return Math.Clamp(offset, minimum, maximum);
        }
    }

    private sealed class DropDownBackgroundGuard
    {
        private readonly WpfComboBox _comboBox;
        private readonly MouseWheelEventHandler _windowWheelHandler;
        private Window? _window;
        private bool _isAttached;

        public DropDownBackgroundGuard(WpfComboBox comboBox)
        {
            _comboBox = comboBox;
            _windowWheelHandler = OnWindowPreviewMouseWheel;
        }

        public void Attach()
        {
            if (_isAttached)
            {
                return;
            }

            _isAttached = true;
            _comboBox.DropDownOpened += OnDropDownOpened;
            _comboBox.DropDownClosed += OnDropDownClosed;
            _comboBox.Unloaded += OnUnloaded;

            if (_comboBox.IsDropDownOpen)
            {
                AttachToWindow();
            }
        }

        public void Detach()
        {
            if (!_isAttached)
            {
                return;
            }

            DetachFromWindow();
            _comboBox.DropDownOpened -= OnDropDownOpened;
            _comboBox.DropDownClosed -= OnDropDownClosed;
            _comboBox.Unloaded -= OnUnloaded;
            _isAttached = false;
        }

        private void OnDropDownOpened(object? sender, EventArgs e) =>
            AttachToWindow();

        private void OnDropDownClosed(object? sender, EventArgs e) =>
            DetachFromWindow();

        private void OnUnloaded(object sender, RoutedEventArgs e) =>
            DetachFromWindow();

        private void AttachToWindow()
        {
            DetachFromWindow();
            _window = Window.GetWindow(_comboBox);
            _window?.AddHandler(
                Mouse.PreviewMouseWheelEvent,
                _windowWheelHandler,
                handledEventsToo: true);
        }

        private void DetachFromWindow()
        {
            _window?.RemoveHandler(Mouse.PreviewMouseWheelEvent, _windowWheelHandler);
            _window = null;
        }

        private void OnWindowPreviewMouseWheel(object sender, MouseWheelEventArgs e)
        {
            if (e.Handled || !_comboBox.IsDropDownOpen)
            {
                return;
            }

            var pointerSource = Mouse.DirectlyOver as DependencyObject ??
                                e.OriginalSource as DependencyObject;
            var disposition = ResolveOpenDropDownWheelDisposition(
                IsInsideOpenDropDown(_comboBox, pointerSource));
            if (disposition == OpenDropDownWheelDisposition.KeepDropDownOpen)
            {
                return;
            }

            _comboBox.IsDropDownOpen = false;
            e.Handled = true;
        }
    }

    private static double ResolveWheelDistance(ScrollViewer viewer)
    {
        var configuredLines = SystemParameters.WheelScrollLines;
        if (configuredLines < 0)
        {
            return Math.Max(WheelDistance, viewer.ViewportHeight * 0.82);
        }

        return WheelDistance * Math.Max(1d, configuredLines / 3d);
    }

    private static WheelRoute FindScrollRoute(DependencyObject? source, int delta)
    {
        while (source is not null)
        {
            if (source is ScrollViewer viewer)
            {
                var canScroll =
                    viewer.ScrollableHeight > CompletionTolerance &&
                    CanScrollInDirection(viewer, delta);
                switch (ResolveViewerWheelDisposition(
                            canScroll,
                            GetStopsWheelPropagation(viewer)))
                {
                    case ViewerWheelDisposition.Scroll:
                        return new WheelRoute(viewer, IsBlocked: false);
                    case ViewerWheelDisposition.Block:
                        return new WheelRoute(Target: null, IsBlocked: true);
                }
            }

            source = GetParent(source);
        }

        return default;
    }

    private static ViewerWheelDisposition ResolveViewerWheelDisposition(
        bool canScrollInDirection,
        bool stopsWheelPropagation) =>
        canScrollInDirection
            ? ViewerWheelDisposition.Scroll
            : stopsWheelPropagation
                ? ViewerWheelDisposition.Block
                : ViewerWheelDisposition.Continue;

    private static OpenDropDownWheelDisposition ResolveOpenDropDownWheelDisposition(
        bool pointerInsideDropDown) =>
        pointerInsideDropDown
            ? OpenDropDownWheelDisposition.KeepDropDownOpen
            : OpenDropDownWheelDisposition.CloseAndBlockBackground;

    private static bool IsInsideOpenDropDown(WpfComboBox comboBox, DependencyObject? source)
    {
        if (source is null)
        {
            return false;
        }

        comboBox.ApplyTemplate();
        var popup = comboBox.Template.FindName("Popup", comboBox) as Popup ??
                    comboBox.Template.FindName("PART_Popup", comboBox) as Popup;
        var popupRoot = popup?.Child;
        if (popupRoot is null)
        {
            return false;
        }

        while (source is not null)
        {
            if (ReferenceEquals(source, popupRoot))
            {
                return true;
            }

            source = GetParent(source);
        }

        return false;
    }

    private static bool CanScrollInDirection(ScrollViewer viewer, int delta) =>
        delta > 0
            ? viewer.VerticalOffset > CompletionTolerance
            : viewer.VerticalOffset < viewer.ScrollableHeight - CompletionTolerance;

    private static bool IsAtVerticalBoundary(ScrollViewer viewer) =>
        viewer.VerticalOffset <= CompletionTolerance ||
        viewer.VerticalOffset >= viewer.ScrollableHeight - CompletionTolerance;

    private static DependencyObject? GetParent(DependencyObject source)
    {
        try
        {
            return VisualTreeHelper.GetParent(source) ?? LogicalTreeHelper.GetParent(source);
        }
        catch (InvalidOperationException)
        {
            return LogicalTreeHelper.GetParent(source);
        }
    }

    private readonly record struct WheelRoute(ScrollViewer? Target, bool IsBlocked);
}

internal enum ViewerWheelDisposition
{
    Continue,
    Scroll,
    Block
}

internal enum OpenDropDownWheelDisposition
{
    KeepDropDownOpen,
    CloseAndBlockBackground
}

internal enum WheelInputDisposition
{
    Accept,
    Brake
}

/// <summary>
/// Filters the short, isolated reverse pulses produced by worn mechanical wheels.
/// A genuine reversal remains responsive: the first suspicious pulse brakes the
/// current motion and a confirming pulse is accepted immediately.
/// </summary>
internal sealed class WheelDirectionBounceGuard
{
    internal const long BounceWindowMilliseconds = 55;
    internal const long ReversalConfirmationMilliseconds = 90;

    private int _lastAcceptedDirection;
    private long _lastAcceptedTimestamp;
    private int _pendingReversalDirection;
    private long _pendingReversalTimestamp;

    public WheelInputDisposition Evaluate(
        int delta,
        long timestampMilliseconds,
        bool hasActiveMotion,
        bool isAtBoundary)
    {
        var direction = Math.Sign(delta);
        if (direction == 0)
        {
            return WheelInputDisposition.Accept;
        }

        ExpirePendingReversal(timestampMilliseconds);

        if (_lastAcceptedDirection == 0 || direction == _lastAcceptedDirection)
        {
            Accept(direction, timestampMilliseconds);
            return WheelInputDisposition.Accept;
        }

        if (_pendingReversalDirection == direction &&
            ElapsedSince(timestampMilliseconds, _pendingReversalTimestamp) <= ReversalConfirmationMilliseconds)
        {
            Accept(direction, timestampMilliseconds);
            return WheelInputDisposition.Accept;
        }

        var isRapidReversal = ElapsedSince(timestampMilliseconds, _lastAcceptedTimestamp) <= BounceWindowMilliseconds;
        if (isRapidReversal && (hasActiveMotion || isAtBoundary))
        {
            _pendingReversalDirection = direction;
            _pendingReversalTimestamp = timestampMilliseconds;
            return WheelInputDisposition.Brake;
        }

        Accept(direction, timestampMilliseconds);
        return WheelInputDisposition.Accept;
    }

    public void Reset()
    {
        _lastAcceptedDirection = 0;
        _lastAcceptedTimestamp = 0;
        ClearPendingReversal();
    }

    private void Accept(int direction, long timestampMilliseconds)
    {
        _lastAcceptedDirection = direction;
        _lastAcceptedTimestamp = timestampMilliseconds;
        ClearPendingReversal();
    }

    private void ExpirePendingReversal(long timestampMilliseconds)
    {
        if (_pendingReversalDirection != 0 &&
            ElapsedSince(timestampMilliseconds, _pendingReversalTimestamp) > ReversalConfirmationMilliseconds)
        {
            ClearPendingReversal();
        }
    }

    private void ClearPendingReversal()
    {
        _pendingReversalDirection = 0;
        _pendingReversalTimestamp = 0;
    }

    private static long ElapsedSince(long timestampMilliseconds, long earlierTimestampMilliseconds) =>
        Math.Max(0, timestampMilliseconds - earlierTimestampMilliseconds);
}
