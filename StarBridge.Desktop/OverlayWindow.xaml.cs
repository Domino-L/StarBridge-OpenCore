using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Globalization;
using System.Runtime.CompilerServices;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using StarBridge.Core.Presence;
using Brush = System.Windows.Media.Brush;
using Brushes = System.Windows.Media.Brushes;
using Color = System.Windows.Media.Color;

namespace StarBridge.Desktop;

public partial class OverlayWindow : Window, IOverlayHost
{
    private const int GwlExStyle = -20;
    private const int WmNcHitTest = 0x0084;
    private const int HtTransparent = -1;
    private const int WsExTransparent = 0x00000020;
    private const int WsExLayered = 0x00080000;
    private const int WsExToolWindow = 0x00000080;
    private const int WsExNoActivate = 0x08000000;
    private const int RgnOr = 2;
    private const double SteadyStateRegionPadding = 22;
    private const double SteadyStateRegionDelayMs = OverlayStartupTransitionLayer.DurationMs + 120;

    private readonly IEnumerable<OverlayLayoutItem> _layout;
    private readonly OverlayViewModel _viewModel;
    private OverlayDisplaySettings _settings;
    private OverlayStartupTransitionContext _startupTransitionContext;
    private OverlayCompositionStartupTransitionWindow? _compositionStartupTransition;
    private DispatcherTimer? _steadyStateRegionTimer;
    private DispatcherTimer? _eventNotificationRegionTimer;
    private int _lastEventNotificationPulse;
    private DateTimeOffset _eventNotificationRevealUntilUtc = DateTimeOffset.MinValue;
    private bool _eventNotificationRegionClearedForMotion;
    private bool _startupRevealActive;
    private bool _pendingStartupEventNotificationReveal;

    public OverlayWindow(
        OverlayAuthorizedRoster roster,
        IEnumerable<OverlayChatMessage> chatMessages,
        IEnumerable<OverlayLayoutItem> layout,
        OverlayDisplaySettings settings,
        OverlayRosterSelectionSettings rosterSelectionSettings,
        string language,
        bool hasFleet,
        OverlayCommandState commandState,
        PlayerPresenceKind localPresence,
        string localShard,
        Rect surfaceBounds,
        OverlayStartupTransitionContext startupTransitionContext,
        OverlaySceneContext sceneContext)
    {
        InitializeComponent();
        ApplySurfaceBounds(surfaceBounds);
        _layout = layout;
        _settings = settings;
        _startupTransitionContext = startupTransitionContext;
        _viewModel = new OverlayViewModel(
            roster,
            settings,
            rosterSelectionSettings,
            language,
            hasFleet,
            commandState,
            localPresence,
            localShard,
            sceneContext,
            chatMessages);
        _lastEventNotificationPulse = _viewModel.EventNotificationPulse;
        _viewModel.PropertyChanged += OverlayViewModel_PropertyChanged;
        DataContext = _viewModel;
        if (ShouldPlayStartupTransition(settings))
        {
            PrepareOverlayStartupContent();
        }

        Loaded += (_, _) =>
        {
            ApplyLayout();
            UpdateStartupTransitionTargets();
            var revealTargets = GetPanelTargetRects().ToArray();
            if (OverlayCompositionStartupTransitionWindow.TryStart(
                    this,
                    settings,
                    language,
                    startupTransitionContext,
                    revealTargets,
                    out _compositionStartupTransition))
            {
                StartupTransitionLayer.Stop();
                ClearWindowRegion();
                BeginOverlayStartupReveal();
                ScheduleSteadyStateWindowRegion();
            }
            else if (StartupTransitionLayer.Start(settings, language, startupTransitionContext))
            {
                ClearWindowRegion();
                BeginOverlayStartupReveal();
                ScheduleSteadyStateWindowRegion();
            }
            else
            {
                RestoreOverlayStartupContent();
                ApplySteadyStateWindowRegion();
            }
        };
        SizeChanged += (_, _) =>
        {
            ApplyLayout();
            UpdateStartupTransitionTargets();
            if (!_startupRevealActive)
            {
                ApplySteadyStateWindowRegion();
            }
        };
        EventNotificationPanel.SizeChanged += (_, _) => ApplyEventNotificationLayout();
        Closed += (_, _) =>
        {
            CancelSteadyStateWindowRegionTimer();
            CancelEventNotificationRegionTimer();
            _viewModel.PropertyChanged -= OverlayViewModel_PropertyChanged;
            _compositionStartupTransition?.Dispose();
            _compositionStartupTransition = null;
            StartupTransitionLayer.Stop();
        };
    }

    public void Refresh(
        OverlayAuthorizedRoster roster,
        IEnumerable<OverlayChatMessage> chatMessages,
        OverlayDisplaySettings settings,
        OverlayRosterSelectionSettings rosterSelectionSettings,
        string language,
        bool hasFleet,
        OverlayCommandState commandState,
        PlayerPresenceKind localPresence,
        string localShard,
        Rect surfaceBounds,
        OverlayStartupTransitionContext startupTransitionContext,
        OverlaySceneContext sceneContext)
    {
        ApplySurfaceBounds(surfaceBounds);
        _settings = settings;
        _startupTransitionContext = startupTransitionContext;
        _viewModel.Refresh(
            roster,
            settings,
            rosterSelectionSettings,
            language,
            hasFleet,
            commandState,
            localPresence,
            localShard,
            sceneContext,
            chatMessages);
        StartupTransitionLayer.ApplySettings(settings, startupTransitionContext);
        ApplyLayout();
        if (_viewModel.EventNotificationPulse != _lastEventNotificationPulse)
        {
            _lastEventNotificationPulse = _viewModel.EventNotificationPulse;
            HandleEventNotificationPulse();
        }

        UpdateStartupTransitionTargets();
        if (!settings.EnableStartupTransition)
        {
            CancelSteadyStateWindowRegionTimer();
            _compositionStartupTransition?.Dispose();
            _compositionStartupTransition = null;
            RestoreOverlayStartupContent();
            if (!IsEventNotificationRevealActive())
            {
                ApplySteadyStateWindowRegion();
            }
        }
        else if (!_startupRevealActive && !IsEventNotificationRevealActive())
        {
            ApplySteadyStateWindowRegion();
        }
    }

    public void SetVisible(bool visible)
    {
        if (visible)
        {
            Show();
        }
        else
        {
            Hide();
        }
    }

    public void QueueGameEventNotification(
        OverlayEventNotificationTypes eventType,
        string title,
        string detail,
        bool important,
        bool positive)
    {
        if (!_settings.ShowEventNotifications)
        {
            return;
        }

        _viewModel.QueueGameEventNotification(eventType, title, detail, important, positive);
    }

    public void QueueCommunicationEvent(string title, string detail)
    {
        if (_settings.ShowNotice)
        {
            _viewModel.QueueCommunicationEvent(title, detail);
        }
    }

    public void BeginStartupTransition(int settleDelayMs = 0)
    {
        // WPF owns its startup storyboard; the explicit handoff is used by the DComp host.
    }

    private void ApplySurfaceBounds(Rect bounds)
    {
        if (bounds.Width <= 1 || bounds.Height <= 1)
        {
            bounds = new Rect(
                SystemParameters.VirtualScreenLeft,
                SystemParameters.VirtualScreenTop,
                Math.Max(1, SystemParameters.VirtualScreenWidth),
                Math.Max(1, SystemParameters.VirtualScreenHeight));
        }

        Left = bounds.Left;
        Top = bounds.Top;
        Width = bounds.Width;
        Height = bounds.Height;
    }

    private void OverlayViewModel_PropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName != nameof(OverlayViewModel.EventNotificationVisibility) &&
            e.PropertyName != nameof(OverlayViewModel.EventNotificationPulse) &&
            e.PropertyName != nameof(OverlayViewModel.EventNotificationAnimationFrame))
        {
            return;
        }

        Dispatcher.BeginInvoke(() =>
        {
            var isAnimationFrame = e.PropertyName == nameof(OverlayViewModel.EventNotificationAnimationFrame);
            if (!isAnimationFrame)
            {
                ApplyEventNotificationLayout();
            }

            var pulsed = e.PropertyName == nameof(OverlayViewModel.EventNotificationPulse) &&
                _viewModel.EventNotificationPulse != _lastEventNotificationPulse;
            if (pulsed)
            {
                _lastEventNotificationPulse = _viewModel.EventNotificationPulse;
                HandleEventNotificationPulse();
            }

            if (isAnimationFrame && _viewModel.HasActiveEventNotificationMotion)
            {
                EnsureEventNotificationMotionRegion();
                return;
            }

            if (isAnimationFrame && _eventNotificationRegionClearedForMotion)
            {
                var animationScale = OverlayDisplaySettings.ResolveEventNotificationAnimationScale(_settings.EventNotificationAnimationSpeed);
                ScheduleEventNotificationRegionRestore(190 * animationScale);
                return;
            }

            if (!_startupRevealActive && !pulsed && !IsEventNotificationRevealActive())
            {
                ApplySteadyStateWindowRegion();
            }
        });
    }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        if (PresentationSource.FromVisual(this) is HwndSource source)
        {
            source.AddHook(OverlayWindowProc);
        }

        EnableMouseClickThrough();
    }

    private void OverlayWindow_KeyDown(object sender, System.Windows.Input.KeyEventArgs e)
    {
        if (e.Key == Key.Escape)
        {
            Close();
        }
    }

    private void ApplyLayout()
    {
        var resolvedItems = OverlaySurfaceLayout.ResolveItems(
            _layout,
            ActualWidth,
            ActualHeight);
        ApplyPanel("Notice", NoticePanel, resolvedItems);
        ApplyPanel("Squads", SquadsPanel, resolvedItems);
        ApplyPanel("Members", MembersPanel, resolvedItems);
        ApplyEventNotificationLayout();
    }

    private void ApplyEventNotificationLayout()
    {
        var panelHeight = EventNotificationPanel.ActualHeight > 1 ? EventNotificationPanel.ActualHeight : 132;
        var rect = OverlaySurfaceLayout.ResolveEventNotificationRect(
            ActualWidth,
            ActualHeight,
            _settings.EventNotificationSide,
            _settings.EventNotificationY,
            panelHeight);
        EventNotificationPanel.Width = rect.Width;
        Canvas.SetLeft(EventNotificationPanel, rect.Left);
        Canvas.SetTop(EventNotificationPanel, rect.Top);
    }

    private void BeginEventNotificationSlideIn()
    {
        ApplyEventNotificationLayout();
        EnsureEventNotificationMotionRegion();
        EventNotificationPanel.BeginAnimation(OpacityProperty, null);
        EventNotificationTranslate.BeginAnimation(TranslateTransform.XProperty, null);
        var animationScale = OverlayDisplaySettings.ResolveEventNotificationAnimationScale(_settings.EventNotificationAnimationSpeed);

        EventNotificationPanel.Opacity = 1;
        EventNotificationTranslate.X = 0;
        ScheduleEventNotificationRegionRestore(360 * animationScale);
    }

    private void HandleEventNotificationPulse()
    {
        if (_startupRevealActive)
        {
            DeferStartupEventNotificationReveal();
            return;
        }

        BeginEventNotificationSlideIn();
    }

    private void DeferStartupEventNotificationReveal()
    {
        _pendingStartupEventNotificationReveal = true;
        _viewModel.HoldEventNotificationsForStartupReveal(SteadyStateRegionDelayMs + 750);
        ApplyEventNotificationLayout();
        EventNotificationPanel.BeginAnimation(OpacityProperty, null);
        EventNotificationTranslate.BeginAnimation(TranslateTransform.XProperty, null);
        EventNotificationPanel.Opacity = 0;
        EventNotificationTranslate.X = 0;
    }

    private void ReleaseStartupEventNotificationReveal()
    {
        if (!_pendingStartupEventNotificationReveal)
        {
            return;
        }

        _pendingStartupEventNotificationReveal = false;
        if (_viewModel.EventNotifications.Count == 0)
        {
            EventNotificationPanel.Opacity = 1;
            return;
        }

        _viewModel.ReplayEventNotificationsEnter();
    }

    private bool IsEventNotificationRevealActive()
    {
        return DateTimeOffset.UtcNow < _eventNotificationRevealUntilUtc;
    }

    private void EnsureEventNotificationMotionRegion()
    {
        CancelEventNotificationRegionTimer();
        var animationScale = OverlayDisplaySettings.ResolveEventNotificationAnimationScale(_settings.EventNotificationAnimationSpeed);
        _eventNotificationRevealUntilUtc = DateTimeOffset.UtcNow.AddMilliseconds(260 * animationScale);
        if (_eventNotificationRegionClearedForMotion)
        {
            return;
        }

        _eventNotificationRegionClearedForMotion = true;
        ClearWindowRegion();
    }

    private void ScheduleEventNotificationRegionRestore(double delayMs)
    {
        CancelEventNotificationRegionTimer();
        var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(Math.Max(80, delayMs)) };
        _eventNotificationRegionTimer = timer;
        timer.Tick += (_, _) =>
        {
            timer.Stop();
            if (!ReferenceEquals(_eventNotificationRegionTimer, timer))
            {
                return;
            }

            _eventNotificationRegionTimer = null;
            _eventNotificationRegionClearedForMotion = false;
            if (!_startupRevealActive && !IsEventNotificationRevealActive())
            {
                ApplySteadyStateWindowRegion();
            }
        };
        timer.Start();
    }

    private void CancelEventNotificationRegionTimer()
    {
        _eventNotificationRegionTimer?.Stop();
        _eventNotificationRegionTimer = null;
    }

    private static bool ShouldPlayStartupTransition(OverlayDisplaySettings settings)
    {
        return settings.EnableStartupTransition &&
               settings.StartupTransitionStyle == OverlayStartupTransitionStyle.BridgeTerminal;
    }

    private void PrepareOverlayStartupContent()
    {
        _startupRevealActive = true;
        if (_viewModel.EventNotifications.Count > 0)
        {
            DeferStartupEventNotificationReveal();
        }

        foreach (var element in GetStartupRevealElements())
        {
            element.BeginAnimation(OpacityProperty, null);
            element.Opacity = 0;
            element.RenderTransformOrigin = new System.Windows.Point(0.5, 0.5);
            element.RenderTransform = new TransformGroup
            {
                Children =
                {
                    new ScaleTransform(0.965, 0.965),
                    new TranslateTransform(0, 10)
                }
            };
        }
    }

    private void BeginOverlayStartupReveal()
    {
        if (!_startupRevealActive)
        {
            PrepareOverlayStartupContent();
        }

        var index = 0;
        foreach (var element in GetStartupRevealElements())
        {
            var elementDelay = TimeSpan.FromMilliseconds(GetStartupRevealDelayMs(element, index));
            var duration = TimeSpan.FromMilliseconds(element == CrosshairLayer ? 300 : 360);
            BeginElementReveal(element, elementDelay, duration);
            index++;
        }
    }

    private double GetStartupRevealDelayMs(UIElement element, int index)
    {
        if (element is FrameworkElement frameworkElement)
        {
            var top = Canvas.GetTop(frameworkElement);
            var height = frameworkElement.Height > 0 ? frameworkElement.Height : frameworkElement.ActualHeight;
            if (!double.IsNaN(top) &&
                ActualHeight > 1 &&
                height > 1)
            {
                var normalizedY = Math.Clamp((top + height * 0.45) / ActualHeight, 0, 1);
                return 1580 + normalizedY * 230;
            }
        }

        if (element == CrosshairLayer)
        {
            return 1700;
        }

        return 1760 + index * 24;
    }

    private void BeginElementReveal(UIElement element, TimeSpan delay, TimeSpan duration)
    {
        var easing = new CubicEase { EasingMode = EasingMode.EaseOut };
        var opacityAnimation = new DoubleAnimation(1, duration)
        {
            BeginTime = delay,
            EasingFunction = easing,
            FillBehavior = FillBehavior.HoldEnd
        };
        element.BeginAnimation(OpacityProperty, opacityAnimation);

        if (element.RenderTransform is not TransformGroup group ||
            group.Children.Count < 2 ||
            group.Children[0] is not ScaleTransform scale ||
            group.Children[1] is not TranslateTransform translate)
        {
            return;
        }

        var scaleAnimation = new DoubleAnimation(1, duration)
        {
            BeginTime = delay,
            EasingFunction = easing,
            FillBehavior = FillBehavior.HoldEnd
        };
        scale.BeginAnimation(ScaleTransform.ScaleXProperty, scaleAnimation);
        scale.BeginAnimation(ScaleTransform.ScaleYProperty, scaleAnimation.Clone());

        var translateAnimation = new DoubleAnimation(0, duration)
        {
            BeginTime = delay,
            EasingFunction = easing,
            FillBehavior = FillBehavior.HoldEnd
        };
        translate.BeginAnimation(TranslateTransform.YProperty, translateAnimation);
    }

    private void RestoreOverlayStartupContent()
    {
        _startupRevealActive = false;
        foreach (var element in GetStartupRevealElements())
        {
            element.BeginAnimation(OpacityProperty, null);
            element.Opacity = 1;
            element.RenderTransform = Transform.Identity;
        }

        ReleaseStartupEventNotificationReveal();
    }

    private void ScheduleSteadyStateWindowRegion()
    {
        CancelSteadyStateWindowRegionTimer();
        _startupRevealActive = true;
        var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(SteadyStateRegionDelayMs) };
        _steadyStateRegionTimer = timer;
        timer.Tick += (_, _) =>
        {
            timer.Stop();
            if (!ReferenceEquals(_steadyStateRegionTimer, timer))
            {
                return;
            }

            _steadyStateRegionTimer = null;
            _startupRevealActive = false;
            ApplySteadyStateWindowRegion();
            ReleaseStartupEventNotificationReveal();
        };
        timer.Start();
    }

    private void CancelSteadyStateWindowRegionTimer()
    {
        _steadyStateRegionTimer?.Stop();
        _steadyStateRegionTimer = null;
    }

    private void ClearWindowRegion()
    {
        try
        {
            var handle = new WindowInteropHelper(this).Handle;
            if (handle != IntPtr.Zero)
            {
                SetWindowRgn(handle, IntPtr.Zero, true);
            }
        }
        catch (Exception exception)
        {
            App.WriteCrashLog(exception);
        }
    }

    private void ApplySteadyStateWindowRegion()
    {
        try
        {
            var handle = new WindowInteropHelper(this).Handle;
            if (handle == IntPtr.Zero || ActualWidth <= 1 || ActualHeight <= 1)
            {
                return;
            }

            var transform = PresentationSource.FromVisual(this)?.CompositionTarget?.TransformToDevice ?? Matrix.Identity;
            var rects = GetSteadyStateRegionRects().ToArray();
            if (rects.Length == 0)
            {
                rects = [new Rect(0, 0, 1, 1)];
            }

            var combinedRegion = IntPtr.Zero;
            try
            {
                foreach (var rect in rects)
                {
                    var regionRect = ToDeviceRect(rect, transform);
                    if (regionRect.Right <= regionRect.Left || regionRect.Bottom <= regionRect.Top)
                    {
                        continue;
                    }

                    var rectRegion = CreateRectRgn(regionRect.Left, regionRect.Top, regionRect.Right, regionRect.Bottom);
                    if (rectRegion == IntPtr.Zero)
                    {
                        continue;
                    }

                    if (combinedRegion == IntPtr.Zero)
                    {
                        combinedRegion = rectRegion;
                    }
                    else
                    {
                        CombineRgn(combinedRegion, combinedRegion, rectRegion, RgnOr);
                        DeleteObject(rectRegion);
                    }
                }

                if (combinedRegion != IntPtr.Zero && SetWindowRgn(handle, combinedRegion, true) != 0)
                {
                    combinedRegion = IntPtr.Zero;
                }
            }
            finally
            {
                if (combinedRegion != IntPtr.Zero)
                {
                    DeleteObject(combinedRegion);
                }
            }
        }
        catch (Exception exception)
        {
            App.WriteCrashLog(exception);
        }
    }

    private IEnumerable<Rect> GetSteadyStateRegionRects()
    {
        foreach (var panel in new[] { NoticePanel, SquadsPanel, MembersPanel })
        {
            var rect = GetCanvasElementBounds(panel);
            if (rect is not null)
            {
                yield return InflateAndClamp(rect.Value, SteadyStateRegionPadding);
            }
        }

        var eventNotificationRect = GetCanvasElementBounds(EventNotificationPanel);
        if (eventNotificationRect is not null)
        {
            yield return InflateAndClamp(eventNotificationRect.Value, SteadyStateRegionPadding);
        }

        if (CrosshairLayer.Visibility == Visibility.Visible)
        {
            var size = Math.Clamp(
                _viewModel.CrosshairSize + 18,
                OverlayDisplaySettings.MinCrosshairSize + 16,
                OverlayDisplaySettings.MaxCrosshairSize + 40);
            yield return InflateAndClamp(
                new Rect((ActualWidth - size) / 2, (ActualHeight - size) / 2, size, size),
                0);
        }

    }

    private Rect? GetCanvasElementBounds(FrameworkElement element)
    {
        if (element.Visibility != Visibility.Visible)
        {
            return null;
        }

        var width = element.Width > 1 ? element.Width : element.ActualWidth;
        var height = element.Height > 1 ? element.Height : element.ActualHeight;
        if (width <= 1 || height <= 1)
        {
            return null;
        }

        var left = Canvas.GetLeft(element);
        if (double.IsNaN(left))
        {
            left = 0;
        }

        var top = Canvas.GetTop(element);
        if (double.IsNaN(top))
        {
            var bottom = Canvas.GetBottom(element);
            top = double.IsNaN(bottom) ? 0 : ActualHeight - bottom - height;
        }

        return new Rect(left, top, width, height);
    }

    private Rect InflateAndClamp(Rect rect, double padding)
    {
        rect.Inflate(padding, padding);
        var left = Math.Clamp(rect.Left, 0, Math.Max(0, ActualWidth));
        var top = Math.Clamp(rect.Top, 0, Math.Max(0, ActualHeight));
        var right = Math.Clamp(rect.Right, 0, Math.Max(0, ActualWidth));
        var bottom = Math.Clamp(rect.Bottom, 0, Math.Max(0, ActualHeight));
        return new Rect(left, top, Math.Max(1, right - left), Math.Max(1, bottom - top));
    }

    private static (int Left, int Top, int Right, int Bottom) ToDeviceRect(Rect rect, Matrix transform)
    {
        var topLeft = transform.Transform(rect.TopLeft);
        var bottomRight = transform.Transform(rect.BottomRight);
        return (
            (int)Math.Floor(Math.Min(topLeft.X, bottomRight.X)),
            (int)Math.Floor(Math.Min(topLeft.Y, bottomRight.Y)),
            (int)Math.Ceiling(Math.Max(topLeft.X, bottomRight.X)),
            (int)Math.Ceiling(Math.Max(topLeft.Y, bottomRight.Y)));
    }

    private IEnumerable<UIElement> GetStartupRevealElements()
    {
        yield return NoticePanel;
        yield return SquadsPanel;
        yield return MembersPanel;
        yield return CrosshairLayer;
    }

    private void UpdateStartupTransitionTargets()
    {
        StartupTransitionLayer.SetRevealTargets(GetPanelTargetRects());
    }

    private IEnumerable<Rect> GetPanelTargetRects()
    {
        foreach (var panel in new[] { NoticePanel, SquadsPanel, MembersPanel })
        {
            if (panel.Visibility != Visibility.Visible)
            {
                continue;
            }

            var left = Canvas.GetLeft(panel);
            var top = Canvas.GetTop(panel);
            var width = panel.Width > 0 ? panel.Width : panel.ActualWidth;
            var height = panel.Height > 0 ? panel.Height : panel.ActualHeight;
            if (double.IsNaN(left) ||
                double.IsNaN(top) ||
                width <= 1 ||
                height <= 1)
            {
                continue;
            }

            yield return new Rect(left, top, width, height);
        }
    }

    private void ApplyPanel(
        string key,
        FrameworkElement panel,
        IReadOnlyDictionary<string, Rect> resolvedItems)
    {
        var orderedLayout = _layout.ToList();
        var item = orderedLayout.FirstOrDefault(layoutItem =>
            layoutItem.Key.Equals(key, StringComparison.OrdinalIgnoreCase));
        if (item is null)
        {
            return;
        }

        System.Windows.Controls.Panel.SetZIndex(panel, Math.Max(0, orderedLayout.IndexOf(item)));
        ApplyPanelAppearance(panel, item);
        if (!resolvedItems.TryGetValue(item.Key, out var rect))
        {
            return;
        }
        panel.Width = rect.Width;
        panel.Height = rect.Height;
        Canvas.SetLeft(panel, rect.Left);
        Canvas.SetTop(panel, rect.Top);
        if (key.Equals("Squads", StringComparison.OrdinalIgnoreCase))
        {
            _viewModel.ApplyOverviewPanelLayout(
                _settings.SquadStatusDisplayMode,
                panel.Width,
                panel.Height);
        }
    }

    private void ApplyPanelAppearance(FrameworkElement panel, OverlayLayoutItem item)
    {
        if (panel is Border border)
        {
            border.Background = CloneBrushWithOpacity(_viewModel.PanelBackgroundBrush, item.BackgroundOpacity);
        }

        ApplyTextOpacity(panel, item.TextOpacity);
    }

    private static Brush CloneBrushWithOpacity(Brush source, double opacity)
    {
        var brush = source.CloneCurrentValue();
        brush.Opacity = Math.Clamp(brush.Opacity * OverlayLayoutItem.NormalizeBackgroundOpacity(opacity), 0, 1);
        if (brush.CanFreeze)
        {
            brush.Freeze();
        }

        return brush;
    }

    private static void ApplyTextOpacity(DependencyObject root, double opacity)
    {
        if (root is TextBlock textBlock)
        {
            textBlock.Opacity = OverlayLayoutItem.NormalizeTextOpacity(opacity);
        }

        var childCount = VisualTreeHelper.GetChildrenCount(root);
        for (var index = 0; index < childCount; index++)
        {
            ApplyTextOpacity(VisualTreeHelper.GetChild(root, index), opacity);
        }
    }

    private void EnableMouseClickThrough()
    {
        try
        {
            var handle = new WindowInteropHelper(this).Handle;
            if (handle == IntPtr.Zero)
            {
                return;
            }

            var style = GetWindowLong(handle, GwlExStyle);
            var nextStyle = style | WsExTransparent | WsExLayered | WsExToolWindow | WsExNoActivate;
            SetWindowLong(handle, GwlExStyle, nextStyle);
        }
        catch (Exception exception)
        {
            App.WriteCrashLog(exception);
        }
    }

    private static IntPtr OverlayWindowProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == WmNcHitTest)
        {
            handled = true;
            return new IntPtr(HtTransparent);
        }

        return IntPtr.Zero;
    }

    [DllImport("user32.dll", EntryPoint = "GetWindowLong")]
    private static extern int GetWindowLong(IntPtr handle, int index);

    [DllImport("user32.dll", EntryPoint = "SetWindowLong")]
    private static extern int SetWindowLong(IntPtr handle, int index, int newLong);

    [DllImport("user32.dll")]
    private static extern int SetWindowRgn(IntPtr hWnd, IntPtr hRgn, bool bRedraw);

    [DllImport("gdi32.dll")]
    private static extern IntPtr CreateRectRgn(int nLeftRect, int nTopRect, int nRightRect, int nBottomRect);

    [DllImport("gdi32.dll")]
    private static extern int CombineRgn(IntPtr hRgnDest, IntPtr hRgnSrc1, IntPtr hRgnSrc2, int fnCombineMode);

    [DllImport("gdi32.dll")]
    private static extern bool DeleteObject(IntPtr hObject);
}

public sealed class OverlayViewModel : System.ComponentModel.INotifyPropertyChanged
{
    private const double EventNotificationSlideDistance = 420;
    private const int ChatBarrageLaneCount = 12;
    private const int ChatMessageListHistoryCapacity = 100;
    private static readonly TimeSpan EventNotificationAnimationInterval = TimeSpan.FromMilliseconds(1000.0 / 60.0);
    private static readonly TimeSpan EventNotificationIdleInterval = TimeSpan.FromMilliseconds(120);
    private static readonly TimeSpan LocationEventMergeWindow = TimeSpan.FromSeconds(15);

    private readonly DispatcherTimer _timer = new() { Interval = TimeSpan.FromSeconds(1) };
    private readonly DispatcherTimer _rosterRotationTimer = new();
    private readonly OverlayRosterRotationCursor _rosterRotationCursor = new();
    private readonly DispatcherTimer _eventNotificationTimer = new(DispatcherPriority.Render) { Interval = EventNotificationIdleInterval };
    private readonly Queue<PendingOverlayEventNotification> _pendingEventNotifications = new();
    private readonly Queue<PendingCommunicationEvent> _pendingCommunicationEvents = new();
    private readonly Queue<OverlayChatMessage> _pendingChatMessages = new();
    private readonly Dictionary<string, OverlayGameEventPlayerState> _gameEventPlayerStates = new(StringComparer.OrdinalIgnoreCase);
    private int _noticeSecondsRemaining;
    private int _communicationEventDurationSeconds = 5;
    private string _lastCommandNoticeSignature = "";
    private int _eventNotificationPulse;
    private int _eventNotificationAnimationFrame;
    private int _chatPulse;
    private int _chatAnimationFrame;
    private double _eventNotificationDurationSeconds = 3;
    private int _eventNotificationMaxVisibleCount = OverlayDisplaySettings.Default.EventNotificationMaxVisibleCount;
    private bool _eventNotificationPinImportant = OverlayDisplaySettings.Default.EventNotificationPinImportant;
    private OverlayEventNotificationSide _eventNotificationSide = OverlayDisplaySettings.Default.EventNotificationSide;
    private double _eventNotificationAnimationScale = 1;
    private OverlayEventNotificationDurationOverrides _eventNotificationDurations = OverlayDisplaySettings.Default.EventNotificationDurations;
    private OverlayAnimationFrameRate _animationFrameRate = OverlayDisplaySettings.Default.AnimationFrameRate;
    private string _chatChannelId = "";
    private string _chatSettingsSignature = "";
    private long _chatLastSequence;
    private bool _chatInitialized;
    private OverlayChatDisplayMode _chatDisplayMode = OverlayDisplaySettings.Default.ChatDisplayMode;
    private OverlayChatSide _chatSide = OverlayDisplaySettings.Default.ChatSide;
    private int _chatMaxVisibleCount = OverlayDisplaySettings.Default.ChatMaxVisibleCount;
    private double _chatDurationSeconds = OverlayDisplaySettings.Default.ChatDurationSeconds;
    private double _chatBarrageViewportWidth = 1920;
    private string _chatTitle = "";
    private OverlayDisplaySettings _chatSettings = OverlayDisplaySettings.Default;
    private bool _chatZh = true;
    private bool _eventNotificationConnectionQueued;
    private bool _gameEventSnapshotInitialized;
    private OverlaySceneKind? _gameEventSnapshotSceneKind;
    private string _lastGameEventLocalShard = "";
    private OverlayGameEventFleetState _gameEventFleetState = OverlayGameEventFleetState.Empty;
    private OverlayAuthorizedRoster _authorizedRoster = new([]);
    private OverlayRosterSelectionSettings _rosterSelectionSettings = OverlayRosterSelectionSettings.Default;
    private OverlayDisplaySettings _rosterDisplaySettings = OverlayDisplaySettings.Default;
    private string _rosterLanguage = "zh";
    private string _rosterLocalShard = "";
    private double _memberPanelHeight = 440;
    private string _fleetNoticeTitle = "";
    private string _squadsTitle = "";
    private string _membersTitle = "";
    private string _hotkeyToggleLabel = "";
    private string _fleetNotice = "";
    private Visibility _squadsVisibility = Visibility.Visible;
    private Visibility _membersVisibility = Visibility.Visible;
    private Visibility _squadStatusCompactVisibility = Visibility.Visible;
    private Visibility _squadStatusDetailVisibility = Visibility.Collapsed;
    private Visibility _fleetOverviewVisibility = Visibility.Visible;
    private Visibility _fleetOverviewFocusVisibility = Visibility.Collapsed;
    private Visibility _partyOverviewVisibility = Visibility.Collapsed;
    private Visibility _overviewLocationPlaceholderVisibility = Visibility.Collapsed;
    private Visibility _overviewLocationsHorizontalVisibility = Visibility.Collapsed;
    private Visibility _overviewLocationsVerticalVisibility = Visibility.Collapsed;
    private IReadOnlyList<OverlayOverviewLocationCount> _overviewTopLocations = [];
    private IReadOnlyList<OverlayOverviewLocationCount> _overviewVisibleLocations = [];
    private string _overviewLocationPlaceholder = "";
    private string _overviewLocationPlaceholderMetric = "";
    private double _overviewPanelWidth = OverlayOverviewLocationLayout.HorizontalThreshold;
    private double _overviewPanelHeight = 200;
    private Visibility _memberStatusVisibility = Visibility.Visible;
    private int _memberLocationColumn = 2;
    private int _memberLocationColumnSpan = 1;
    private GridLength _memberNameColumnWidth = new(1, GridUnitType.Star);
    private GridLength _memberStatusColumnWidth = new(OverlayDisplaySettings.MemberStatusColumnPixelWidth);
    private GridLength _memberLocationColumnWidth = new(1, GridUnitType.Star);
    private string _squadStatusPrimaryName = "";
    private string _squadStatusSummary = "";
    private string _squadStatusServerSummary = "";
    private string _squadStatusFocusLine = "";
    private string _squadStatusSecondaryLine = "";
    private Brush _squadStatusBrush = new SolidColorBrush(Color.FromRgb(83, 190, 255));
    private bool _showNotice = true;
    private double _overlayOpacity = 0.85;
    private double _eventNotificationTextOpacity = 1.0;
    private double _eventNotificationBackgroundOpacity = 1.0;
    private Brush _panelBackgroundBrush = new SolidColorBrush(Color.FromArgb(176, 5, 10, 17));
    private Brush _panelBorderBrush = new SolidColorBrush(Color.FromRgb(69, 174, 255));
    private Brush _titleBrush = new SolidColorBrush(Color.FromRgb(83, 190, 255));
    private Brush _textBrush = new SolidColorBrush(Color.FromRgb(235, 247, 255));
    private Brush _mutedBrush = new SolidColorBrush(Color.FromRgb(142, 187, 220));
    private Brush _alertBrush = new SolidColorBrush(Color.FromRgb(255, 240, 0));
    private Brush _iconBackgroundBrush = new SolidColorBrush(Color.FromRgb(4, 16, 28));
    private Brush _onlineBrush = new SolidColorBrush(Color.FromRgb(121, 255, 158));
    private Brush _offlineBrush = new SolidColorBrush(Color.FromRgb(255, 105, 105));
    private Brush _crosshairBrush = new SolidColorBrush(Color.FromRgb(235, 247, 255));
    private Brush _crosshairAlertBrush = new SolidColorBrush(Color.FromRgb(255, 240, 0));
    private Visibility _crosshairVisibility = Visibility.Collapsed;
    private Visibility _simpleCrosshairVisibility = Visibility.Collapsed;
    private Visibility _techCrosshairVisibility = Visibility.Collapsed;
    private double _crosshairSize = 96;
    private double _crosshairOpacity = 0.85;
    private Visibility _crosshairCenterMarkVisibility = Visibility.Visible;
    private double _crosshairOutlineOpacity;
    private double _simpleCrosshairStrokeThickness = 2;
    private double _simpleCrosshairDotSize = 4;
    private double _simpleCrosshairNegativeFar = 10;
    private double _simpleCrosshairNegativeNear = 34;
    private double _simpleCrosshairPositiveNear = 62;
    private double _simpleCrosshairPositiveFar = 86;
    private double _techCrosshairStrokeThickness = 1.6;
    private double _techCrosshairThinStrokeThickness = 1.2;
    private double _techCrosshairCornerStrokeThickness = 1.2;
    private double _techCrosshairMainNegativeFar = 18;
    private double _techCrosshairMainNegativeNear = 48;
    private double _techCrosshairMainPositiveNear = 94;
    private double _techCrosshairMainPositiveFar = 124;
    private double _techCrosshairCenterMarkSize = 12;
    private string _techCrosshairCenterMarkData = "M54,71 L66,71 M76,71 L88,71 M71,54 L71,66 M71,76 L71,88";

    internal OverlayViewModel(
        OverlayAuthorizedRoster roster,
        OverlayDisplaySettings settings,
        OverlayRosterSelectionSettings rosterSelectionSettings,
        string language,
        bool hasFleet,
        OverlayCommandState commandState,
        PlayerPresenceKind localPresence,
        string localShard,
        OverlaySceneContext? sceneContext = null,
        IEnumerable<OverlayChatMessage>? chatMessages = null)
    {
        Refresh(
            roster,
            settings,
            rosterSelectionSettings,
            language,
            hasFleet,
            commandState,
            localPresence,
            localShard,
            sceneContext,
            chatMessages);

        InitializeTimers();
    }

    private void InitializeTimers()
    {
        _rosterRotationTimer.Tick += (_, _) =>
        {
            _rosterRotationCursor.Advance();
            RefreshMembersFromAuthorizedRoster();
        };
        _timer.Tick += (_, _) =>
        {
            if (_noticeSecondsRemaining > 0)
            {
                _noticeSecondsRemaining--;
                OnChanged(nameof(NoticeTimerLabel));
                OnChanged(nameof(NotificationVisibility));
            }

            if (_noticeSecondsRemaining <= 0 && !PromotePendingCommunicationEvent())
            {
                _timer.Stop();
            }
        };
        _eventNotificationTimer.Tick += (_, _) =>
        {
            var now = DateTimeOffset.Now;
            TickEventNotifications(now);
            TickChatMessages(now);
        };
    }

    public event System.ComponentModel.PropertyChangedEventHandler? PropertyChanged;

    public ObservableCollection<OverlaySquadRow> Squads { get; } = [];

    public ObservableCollection<OverlaySquadRow> CompactSquads { get; } = [];

    public ObservableCollection<OverlayMemberRow> Members { get; } = [];

    public ObservableCollection<OverlayEventNotificationRow> EventNotifications { get; } = [];

    public ObservableCollection<OverlayEventNotificationRow> ChatMessages { get; } = [];

    public string FleetNoticeTitle
    {
        get => _fleetNoticeTitle;
        private set => SetProperty(ref _fleetNoticeTitle, value);
    }

    public string SquadsTitle
    {
        get => _squadsTitle;
        private set => SetProperty(ref _squadsTitle, value);
    }

    public string MembersTitle
    {
        get => _membersTitle;
        private set => SetProperty(ref _membersTitle, value);
    }

    public string HotkeyToggleLabel
    {
        get => _hotkeyToggleLabel;
        private set => SetProperty(ref _hotkeyToggleLabel, value);
    }

    public string FleetNotice
    {
        get => _fleetNotice;
        private set => SetProperty(ref _fleetNotice, value);
    }

    public Visibility SquadsVisibility
    {
        get => _squadsVisibility;
        private set => SetProperty(ref _squadsVisibility, value);
    }

    public Visibility MembersVisibility
    {
        get => _membersVisibility;
        private set => SetProperty(ref _membersVisibility, value);
    }

    public Visibility SquadStatusCompactVisibility
    {
        get => _squadStatusCompactVisibility;
        private set => SetProperty(ref _squadStatusCompactVisibility, value);
    }

    public Visibility SquadStatusDetailVisibility
    {
        get => _squadStatusDetailVisibility;
        private set => SetProperty(ref _squadStatusDetailVisibility, value);
    }

    public Visibility FleetOverviewVisibility
    {
        get => _fleetOverviewVisibility;
        private set => SetProperty(ref _fleetOverviewVisibility, value);
    }

    public Visibility PartyOverviewVisibility
    {
        get => _partyOverviewVisibility;
        private set => SetProperty(ref _partyOverviewVisibility, value);
    }

    public Visibility FleetOverviewFocusVisibility
    {
        get => _fleetOverviewFocusVisibility;
        private set => SetProperty(ref _fleetOverviewFocusVisibility, value);
    }

    public Visibility OverviewLocationPlaceholderVisibility
    {
        get => _overviewLocationPlaceholderVisibility;
        private set => SetProperty(ref _overviewLocationPlaceholderVisibility, value);
    }

    public Visibility OverviewLocationsHorizontalVisibility
    {
        get => _overviewLocationsHorizontalVisibility;
        private set => SetProperty(ref _overviewLocationsHorizontalVisibility, value);
    }

    public Visibility OverviewLocationsVerticalVisibility
    {
        get => _overviewLocationsVerticalVisibility;
        private set => SetProperty(ref _overviewLocationsVerticalVisibility, value);
    }

    public IReadOnlyList<OverlayOverviewLocationCount> OverviewTopLocations
    {
        get => _overviewTopLocations;
        private set => SetProperty(ref _overviewTopLocations, value);
    }

    public IReadOnlyList<OverlayOverviewLocationCount> OverviewVisibleLocations
    {
        get => _overviewVisibleLocations;
        private set => SetProperty(ref _overviewVisibleLocations, value);
    }

    public string OverviewLocationPlaceholder
    {
        get => _overviewLocationPlaceholder;
        private set => SetProperty(ref _overviewLocationPlaceholder, value);
    }

    public string OverviewLocationPlaceholderMetric
    {
        get => _overviewLocationPlaceholderMetric;
        private set => SetProperty(ref _overviewLocationPlaceholderMetric, value);
    }

    public string SquadStatusPrimaryName
    {
        get => _squadStatusPrimaryName;
        private set => SetProperty(ref _squadStatusPrimaryName, value);
    }

    public string SquadStatusSummary
    {
        get => _squadStatusSummary;
        private set => SetProperty(ref _squadStatusSummary, value);
    }

    public string SquadStatusServerSummary
    {
        get => _squadStatusServerSummary;
        private set => SetProperty(ref _squadStatusServerSummary, value);
    }

    public string SquadStatusFocusLine
    {
        get => _squadStatusFocusLine;
        private set => SetProperty(ref _squadStatusFocusLine, value);
    }

    public string SquadStatusSecondaryLine
    {
        get => _squadStatusSecondaryLine;
        private set => SetProperty(ref _squadStatusSecondaryLine, value);
    }

    public Brush SquadStatusBrush
    {
        get => _squadStatusBrush;
        private set => SetProperty(ref _squadStatusBrush, value);
    }

    public Visibility MemberStatusVisibility
    {
        get => _memberStatusVisibility;
        private set => SetProperty(ref _memberStatusVisibility, value);
    }

    public int MemberLocationColumn
    {
        get => _memberLocationColumn;
        private set => SetProperty(ref _memberLocationColumn, value);
    }

    public int MemberLocationColumnSpan
    {
        get => _memberLocationColumnSpan;
        private set => SetProperty(ref _memberLocationColumnSpan, value);
    }

    public GridLength MemberNameColumnWidth
    {
        get => _memberNameColumnWidth;
        private set => SetProperty(ref _memberNameColumnWidth, value);
    }

    public GridLength MemberStatusColumnWidth
    {
        get => _memberStatusColumnWidth;
        private set => SetProperty(ref _memberStatusColumnWidth, value);
    }

    public GridLength MemberLocationColumnWidth
    {
        get => _memberLocationColumnWidth;
        private set => SetProperty(ref _memberLocationColumnWidth, value);
    }

    public double OverlayOpacity
    {
        get => _overlayOpacity;
        private set => SetProperty(ref _overlayOpacity, value);
    }

    public double EventNotificationTextOpacity
    {
        get => _eventNotificationTextOpacity;
        private set => SetProperty(ref _eventNotificationTextOpacity, value);
    }

    public double EventNotificationBackgroundOpacity
    {
        get => _eventNotificationBackgroundOpacity;
        private set => SetProperty(ref _eventNotificationBackgroundOpacity, value);
    }

    public Brush PanelBackgroundBrush
    {
        get => _panelBackgroundBrush;
        private set => SetProperty(ref _panelBackgroundBrush, value);
    }

    public Brush PanelBorderBrush
    {
        get => _panelBorderBrush;
        private set => SetProperty(ref _panelBorderBrush, value);
    }

    public Brush TitleBrush
    {
        get => _titleBrush;
        private set => SetProperty(ref _titleBrush, value);
    }

    public Brush TextBrush
    {
        get => _textBrush;
        private set => SetProperty(ref _textBrush, value);
    }

    public Brush MutedBrush
    {
        get => _mutedBrush;
        private set => SetProperty(ref _mutedBrush, value);
    }

    public Brush AlertBrush
    {
        get => _alertBrush;
        private set => SetProperty(ref _alertBrush, value);
    }

    public Brush IconBackgroundBrush
    {
        get => _iconBackgroundBrush;
        private set => SetProperty(ref _iconBackgroundBrush, value);
    }

    public Brush OnlineBrush
    {
        get => _onlineBrush;
        private set => SetProperty(ref _onlineBrush, value);
    }

    public Brush OfflineBrush
    {
        get => _offlineBrush;
        private set => SetProperty(ref _offlineBrush, value);
    }

    public Brush CrosshairBrush
    {
        get => _crosshairBrush;
        private set => SetProperty(ref _crosshairBrush, value);
    }

    public Brush CrosshairAlertBrush
    {
        get => _crosshairAlertBrush;
        private set => SetProperty(ref _crosshairAlertBrush, value);
    }

    public Visibility CrosshairVisibility
    {
        get => _crosshairVisibility;
        private set => SetProperty(ref _crosshairVisibility, value);
    }

    public Visibility SimpleCrosshairVisibility
    {
        get => _simpleCrosshairVisibility;
        private set => SetProperty(ref _simpleCrosshairVisibility, value);
    }

    public Visibility TechCrosshairVisibility
    {
        get => _techCrosshairVisibility;
        private set => SetProperty(ref _techCrosshairVisibility, value);
    }

    public double CrosshairSize
    {
        get => _crosshairSize;
        private set => SetProperty(ref _crosshairSize, value);
    }

    public double CrosshairOpacity
    {
        get => _crosshairOpacity;
        private set => SetProperty(ref _crosshairOpacity, value);
    }

    public Visibility CrosshairCenterMarkVisibility
    {
        get => _crosshairCenterMarkVisibility;
        private set => SetProperty(ref _crosshairCenterMarkVisibility, value);
    }

    public double CrosshairOutlineOpacity
    {
        get => _crosshairOutlineOpacity;
        private set => SetProperty(ref _crosshairOutlineOpacity, value);
    }

    public double SimpleCrosshairStrokeThickness
    {
        get => _simpleCrosshairStrokeThickness;
        private set => SetProperty(ref _simpleCrosshairStrokeThickness, value);
    }

    public double SimpleCrosshairDotSize
    {
        get => _simpleCrosshairDotSize;
        private set => SetProperty(ref _simpleCrosshairDotSize, value);
    }

    public double SimpleCrosshairNegativeFar
    {
        get => _simpleCrosshairNegativeFar;
        private set => SetProperty(ref _simpleCrosshairNegativeFar, value);
    }

    public double SimpleCrosshairNegativeNear
    {
        get => _simpleCrosshairNegativeNear;
        private set => SetProperty(ref _simpleCrosshairNegativeNear, value);
    }

    public double SimpleCrosshairPositiveNear
    {
        get => _simpleCrosshairPositiveNear;
        private set => SetProperty(ref _simpleCrosshairPositiveNear, value);
    }

    public double SimpleCrosshairPositiveFar
    {
        get => _simpleCrosshairPositiveFar;
        private set => SetProperty(ref _simpleCrosshairPositiveFar, value);
    }

    public double TechCrosshairStrokeThickness
    {
        get => _techCrosshairStrokeThickness;
        private set => SetProperty(ref _techCrosshairStrokeThickness, value);
    }

    public double TechCrosshairThinStrokeThickness
    {
        get => _techCrosshairThinStrokeThickness;
        private set => SetProperty(ref _techCrosshairThinStrokeThickness, value);
    }

    public double TechCrosshairCornerStrokeThickness
    {
        get => _techCrosshairCornerStrokeThickness;
        private set => SetProperty(ref _techCrosshairCornerStrokeThickness, value);
    }

    public double TechCrosshairMainNegativeFar
    {
        get => _techCrosshairMainNegativeFar;
        private set => SetProperty(ref _techCrosshairMainNegativeFar, value);
    }

    public double TechCrosshairMainNegativeNear
    {
        get => _techCrosshairMainNegativeNear;
        private set => SetProperty(ref _techCrosshairMainNegativeNear, value);
    }

    public double TechCrosshairMainPositiveNear
    {
        get => _techCrosshairMainPositiveNear;
        private set => SetProperty(ref _techCrosshairMainPositiveNear, value);
    }

    public double TechCrosshairMainPositiveFar
    {
        get => _techCrosshairMainPositiveFar;
        private set => SetProperty(ref _techCrosshairMainPositiveFar, value);
    }

    public double TechCrosshairCenterMarkSize
    {
        get => _techCrosshairCenterMarkSize;
        private set => SetProperty(ref _techCrosshairCenterMarkSize, value);
    }

    public string TechCrosshairCenterMarkData
    {
        get => _techCrosshairCenterMarkData;
        private set => SetProperty(ref _techCrosshairCenterMarkData, value);
    }

    public string NoticeTimerLabel => $"{_noticeSecondsRemaining}s";

    public Visibility NotificationVisibility => _showNotice && _noticeSecondsRemaining > 0
        ? Visibility.Visible
        : Visibility.Collapsed;

    public Visibility EventNotificationVisibility => EventNotifications.Count > 0
        ? Visibility.Visible
        : Visibility.Collapsed;

    public int EventNotificationPulse
    {
        get => _eventNotificationPulse;
        private set => SetProperty(ref _eventNotificationPulse, value);
    }

    public int EventNotificationAnimationFrame
    {
        get => _eventNotificationAnimationFrame;
        private set => SetProperty(ref _eventNotificationAnimationFrame, value);
    }

    public Visibility ChatVisibility => ChatMessages.Count > 0
        ? Visibility.Visible
        : Visibility.Collapsed;

    public string ChatTitle
    {
        get => _chatTitle;
        private set => SetProperty(ref _chatTitle, value);
    }

    public OverlayChatDisplayMode ChatDisplayMode => _chatDisplayMode;

    public OverlayChatSide ChatSide => _chatSide;

    public int ChatPulse
    {
        get => _chatPulse;
        private set => SetProperty(ref _chatPulse, value);
    }

    public int ChatAnimationFrame
    {
        get => _chatAnimationFrame;
        private set => SetProperty(ref _chatAnimationFrame, value);
    }

    public int EventNotificationVisibleLimit => _eventNotificationMaxVisibleCount;

    public int PendingEventNotificationCount => _pendingEventNotifications.Count;

    public bool HasActiveEventNotificationMotion => EventNotifications.Any(notification => notification.IsAnimating);

    public void HoldEventNotificationsForStartupReveal(double minimumHoldMs)
    {
        if (EventNotifications.Count == 0)
        {
            return;
        }

        var holdUntil = DateTimeOffset.Now.AddMilliseconds(Math.Max(0, minimumHoldMs));
        var changed = false;
        foreach (var notification in EventNotifications)
        {
            if (!notification.IsExiting &&
                notification.ExpiresAt < holdUntil)
            {
                notification.ExpiresAt = holdUntil;
                changed = true;
            }
        }

        if (changed)
        {
            RefreshEventNotificationTimer();
        }
    }

    public void ReplayEventNotificationsEnter()
    {
        if (EventNotifications.Count == 0)
        {
            return;
        }

        var now = DateTimeOffset.Now;
        var slideOffset = ResolveEventNotificationSlideOffset();
        var replayed = false;
        foreach (var notification in EventNotifications)
        {
            if (notification.IsExiting)
            {
                continue;
            }

            var expiresAt = now.AddSeconds(ResolveEventNotificationDuration(notification.EventType));
            if (notification.ExpiresAt < expiresAt)
            {
                notification.ExpiresAt = expiresAt;
            }

            if (_animationFrameRate != OverlayAnimationFrameRate.Off)
            {
                notification.BeginEnter(now, slideOffset);
            }
            replayed = true;
        }

        if (!replayed)
        {
            return;
        }

        EventNotificationPulse++;
        OnChanged(nameof(EventNotificationVisibility));
        RefreshEventNotificationTimer();
    }

    internal void Refresh(
        OverlayAuthorizedRoster roster,
        OverlayDisplaySettings settings,
        OverlayRosterSelectionSettings rosterSelectionSettings,
        string language,
        bool hasFleet,
        OverlayCommandState commandState,
        PlayerPresenceKind localPresence,
        string localShard,
        OverlaySceneContext? sceneContext = null,
        IEnumerable<OverlayChatMessage>? chatMessages = null)
    {
        ArgumentNullException.ThrowIfNull(roster);
        _authorizedRoster = roster;
        _rosterSelectionSettings = rosterSelectionSettings.Normalize();
        var effectiveSceneContext = sceneContext ?? OverlaySceneContext.Fleet(settings.ScenePreference);
        _rosterRotationCursor.ApplyContext(_rosterSelectionSettings, effectiveSceneContext.Kind);
        _rosterDisplaySettings = settings;
        _rosterLanguage = language;
        _rosterLocalShard = localShard;

        RefreshCore(
            roster.Members,
            settings,
            language,
            hasFleet,
            commandState,
            localPresence,
            localShard,
            effectiveSceneContext,
            chatMessages);
        RefreshMembersFromAuthorizedRoster();
    }

    public void ApplyMemberViewport(double panelHeight)
    {
        var normalized = double.IsFinite(panelHeight) ? Math.Max(0, panelHeight) : 0;
        if (Math.Abs(_memberPanelHeight - normalized) < 0.5)
        {
            return;
        }

        _memberPanelHeight = normalized;
        RefreshMembersFromAuthorizedRoster();
    }

    private void RefreshCore(
        IEnumerable<PlayerRow> players,
        OverlayDisplaySettings settings,
        string language,
        bool hasFleet,
        OverlayCommandState commandState,
        PlayerPresenceKind localPresence,
        string localShard,
        OverlaySceneContext? sceneContext = null,
        IEnumerable<OverlayChatMessage>? chatMessages = null)
    {
        sceneContext ??= OverlaySceneContext.Fleet(settings.ScenePreference);
        var zh = language.Equals("zh", StringComparison.OrdinalIgnoreCase);
        var playerArray = players.ToArray();
        _showNotice = settings.ShowNotice;
        _communicationEventDurationSeconds = (int)Math.Ceiling(
            OverlayDisplaySettings.NormalizeCommunicationEventDuration(settings.CommunicationEventDurationSeconds));
        if (!_showNotice)
        {
            _pendingCommunicationEvents.Clear();
            _noticeSecondsRemaining = 0;
            _lastCommandNoticeSignature = "";
            _timer.Stop();
            OnChanged(nameof(NotificationVisibility));
        }
        OverlayOpacity = settings.Opacity;
        EventNotificationTextOpacity = OverlayLayoutItem.NormalizeTextOpacity(settings.EventNotificationTextOpacity);
        EventNotificationBackgroundOpacity = OverlayLayoutItem.NormalizeBackgroundOpacity(settings.EventNotificationBackgroundOpacity);
        ApplyTheme(settings.Theme);
        ApplyCrosshairSettings(settings);
        CrosshairVisibility = settings.ShowCrosshair ? Visibility.Visible : Visibility.Collapsed;
        // The retained WPF fallback renders the standard cross only. The active
        // DirectComposition host renders the full crosshair catalog.
        SimpleCrosshairVisibility = settings.ShowCrosshair ? Visibility.Visible : Visibility.Collapsed;
        TechCrosshairVisibility = Visibility.Collapsed;
        SquadsVisibility = settings.ShowSquads ? Visibility.Visible : Visibility.Collapsed;
        MembersVisibility = settings.ShowMembers ? Visibility.Visible : Visibility.Collapsed;
        var hideMemberStatus = settings.EffectiveHideMemberOnlineStatus;
        MemberStatusVisibility = hideMemberStatus ? Visibility.Collapsed : Visibility.Visible;
        MemberLocationColumn = 2;
        MemberLocationColumnSpan = 1;
        var memberNameRatio = OverlayDisplaySettings.NormalizeMemberNameColumnRatio(settings.MemberNameColumnRatio);
        MemberNameColumnWidth = new GridLength(memberNameRatio, GridUnitType.Star);
        MemberStatusColumnWidth = hideMemberStatus ? new GridLength(0) : new GridLength(OverlayDisplaySettings.MemberStatusColumnPixelWidth);
        MemberLocationColumnWidth = new GridLength(1 - memberNameRatio, GridUnitType.Star);

        RefreshSquads(
            playerArray,
            settings,
            zh,
            hasFleet,
            localPresence,
            localShard,
            sceneContext);
        RefreshGameEventNotifications(playerArray, settings, zh, hasFleet, localShard, sceneContext);
        RefreshChatMessages(chatMessages ?? [], settings, zh, sceneContext);

        var nextNoticeTitle = string.IsNullOrWhiteSpace(commandState.NoticeTitle)
            ? zh ? "舰队接入" : "FLEET LINK"
            : commandState.NoticeTitle!;
        var nextNoticeText = string.IsNullOrWhiteSpace(commandState.NoticeText)
            ? hasFleet
                ? zh ? "已接入舰队频道，等待指挥同步" : "Fleet channel linked. Awaiting command sync."
                : zh ? "无组织。请先加入或创建组织。" : "No organization. Join or create an organization first."
            : commandState.NoticeText!;

        var nextNoticeSignature = $"{nextNoticeTitle}\n{nextNoticeText}";
        if (_showNotice && !nextNoticeSignature.Equals(_lastCommandNoticeSignature, StringComparison.Ordinal))
        {
            _lastCommandNoticeSignature = nextNoticeSignature;
            QueueCommunicationEvent(nextNoticeTitle, nextNoticeText);
        }

        SquadsTitle = sceneContext.Kind == OverlaySceneKind.PartyRoom
            ? zh ? "房间概况" : "PARTY OVERVIEW"
            : zh ? "舰队总览" : "FLEET OVERVIEW";
        MembersTitle = sceneContext.Kind == OverlaySceneKind.PartyRoom
            ? zh ? "房间成员" : "PARTY MEMBERS"
            : zh ? "成员状态" : "FLEET MEMBERS";
        HotkeyToggleLabel = zh ? "热键切换" : "HOTKEY TOGGLE";
        OnChanged(nameof(NotificationVisibility));
    }

    private void RefreshMembersFromAuthorizedRoster()
    {
        Members.Clear();
        var zh = _rosterLanguage.Equals("zh", StringComparison.OrdinalIgnoreCase);
        var source = _rosterDisplaySettings.HideSelfMember
            ? new OverlayAuthorizedRoster(_authorizedRoster.Members.Where(player => !player.IsSelf))
            : _authorizedRoster;
        var projection = OverlayRosterPlanner.Project(
            source,
            _rosterSelectionSettings,
            new OverlayRosterViewport(
                _memberPanelHeight,
                _rosterLocalShard,
                null,
                _rosterRotationCursor.Page));
        var shouldRotate =
            _rosterSelectionSettings.OverflowMode == OverlayRosterOverflowMode.Rotate &&
            projection.HiddenOnlineCount + projection.HiddenOfflineCount > 0;
        _rosterRotationTimer.Interval = TimeSpan.FromSeconds(
            _rosterSelectionSettings.RotationIntervalSeconds);
        if (shouldRotate)
        {
            _rosterRotationTimer.Start();
        }
        else
        {
            _rosterRotationTimer.Stop();
        }

        foreach (var player in source.Resolve(projection))
        {
            var online = PlayerPresence.IsOnline(player.SharedPresence);
            Members.Add(new OverlayMemberRow(
                FormatMemberName(player, _rosterDisplaySettings.MemberNameMode),
                player.SharedPresenceText,
                player.SharedShipDisplayText,
                player.SharedLocationDisplayText,
                online ? StatusPalette.SuccessBrush : StatusPalette.DisabledBrush));
        }

        if (projection.ShowOverflowSummary)
        {
            var hiddenTotal = projection.HiddenOnlineCount + projection.HiddenOfflineCount;
            var summary = projection.HiddenOfflineCount > 0
                ? zh
                    ? $"另有 {hiddenTotal} 人（{projection.HiddenOnlineCount} 在线 / {projection.HiddenOfflineCount} 离线）"
                    : $"{hiddenTotal} more ({projection.HiddenOnlineCount} online / {projection.HiddenOfflineCount} offline)"
                : zh
                    ? $"另有 {projection.HiddenOnlineCount} 人在线"
                    : $"{projection.HiddenOnlineCount} more online";
            Members.Add(new OverlayMemberRow(summary, "", "", "", MutedBrush));
        }

        if (Members.Count == 0)
        {
            Members.Add(new OverlayMemberRow(
                zh ? "暂无可显示成员" : "No visible members",
                "",
                "",
                "",
                MutedBrush));
        }

        // DirectComposition observes the view model rather than the collection.
        // Notify once after the closed-set projection is rebuilt so viewport changes
        // and rotation ticks both publish a new render frame.
        OnChanged(nameof(Members));
    }

    public void QueueCommunicationEvent(string title, string detail)
    {
        if (!_showNotice || string.IsNullOrWhiteSpace(title))
        {
            return;
        }

        var pending = new PendingCommunicationEvent(title.Trim(), detail?.Trim() ?? "");
        if ((_noticeSecondsRemaining > 0 &&
             FleetNoticeTitle.Equals(pending.Title, StringComparison.Ordinal) &&
             FleetNotice.Equals(pending.Detail, StringComparison.Ordinal)) ||
            _pendingCommunicationEvents.Contains(pending))
        {
            return;
        }

        if (_noticeSecondsRemaining > 0)
        {
            while (_pendingCommunicationEvents.Count >= 20)
            {
                _pendingCommunicationEvents.Dequeue();
            }

            _pendingCommunicationEvents.Enqueue(pending);
            return;
        }

        ShowCommunicationEvent(pending);
    }

    private void ShowCommunicationEvent(PendingCommunicationEvent communicationEvent)
    {
        FleetNoticeTitle = communicationEvent.Title;
        FleetNotice = communicationEvent.Detail;
        _noticeSecondsRemaining = _communicationEventDurationSeconds;
        _timer.Start();
        OnChanged(nameof(NoticeTimerLabel));
        OnChanged(nameof(NotificationVisibility));
    }

    private bool PromotePendingCommunicationEvent()
    {
        if (_pendingCommunicationEvents.Count == 0)
        {
            OnChanged(nameof(NotificationVisibility));
            return false;
        }

        ShowCommunicationEvent(_pendingCommunicationEvents.Dequeue());
        return true;
    }

    private void RefreshChatMessages(
        IEnumerable<OverlayChatMessage> messages,
        OverlayDisplaySettings settings,
        bool zh,
        OverlaySceneContext sceneContext)
    {
        var channelId = sceneContext.ChatChannelId ??
                        (sceneContext.Kind == OverlaySceneKind.PartyRoom ? sceneContext.RoomId : "") ??
                        "";
        var enabled = settings.ShowChat && !string.IsNullOrWhiteSpace(channelId);
        var nextSignature = string.Join(
            '|',
            OverlayDisplaySettings.NormalizeChatDisplayMode(settings.ChatDisplayMode),
            settings.ChatSide,
            settings.ChatMaxVisibleCount,
            settings.ChatDurationSeconds.ToString("0.##", CultureInfo.InvariantCulture),
            settings.ChatShowSender,
            settings.ChatShowTimestamp,
            settings.ChatShowSystemMessages,
            settings.ChatHideSelfMessages,
            settings.ChatBarrageFontSize.ToString("0.##", CultureInfo.InvariantCulture),
            settings.ChatBarrageRegion,
            settings.ChatBarrageDensity,
            settings.ChatBarrageAvoidCenter,
            settings.ChatTextEdgeStrength);
        var resetBaseline = !_chatInitialized ||
                            !_chatChannelId.Equals(channelId, StringComparison.OrdinalIgnoreCase) ||
                            !_chatSettingsSignature.Equals(nextSignature, StringComparison.Ordinal);

        _chatDisplayMode = OverlayDisplaySettings.NormalizeChatDisplayMode(settings.ChatDisplayMode);
        _chatSide = settings.ChatSide;
        _chatMaxVisibleCount = OverlayDisplaySettings.ResolveChatBarrageCapacity(settings.ChatBarrageDensity);
        _chatDurationSeconds = OverlayDisplaySettings.NormalizeChatDuration(settings.ChatDurationSeconds);
        _chatSettings = settings;
        _chatZh = zh;
        ChatTitle = sceneContext.Kind == OverlaySceneKind.PartyRoom
            ? zh ? "房间通讯" : "PARTY COMMS"
            : string.IsNullOrWhiteSpace(sceneContext.ChatChannelTitle)
                ? zh ? "组织通讯" : "ORGANIZATION COMMS"
                : sceneContext.ChatChannelTitle;
        OnChanged(nameof(ChatDisplayMode));
        OnChanged(nameof(ChatSide));

        if (!enabled)
        {
            ResetChatState();
            return;
        }

        var allMessages = messages
            .Where(message => message.ChannelId.Equals(channelId, StringComparison.OrdinalIgnoreCase))
            .OrderBy(message => message.Sequence)
            .ToArray();
        var latestSequence = allMessages.Length == 0 ? 0 : allMessages[^1].Sequence;
        var visibleMessages = allMessages
            .Where(message => settings.ChatShowSystemMessages || !message.IsSystem)
            .Where(message => !settings.ChatHideSelfMessages || !message.IsSelf)
            .ToArray();

        if (resetBaseline)
        {
            ChatMessages.Clear();
            _pendingChatMessages.Clear();
            _chatChannelId = channelId;
            _chatSettingsSignature = nextSignature;
            _chatLastSequence = latestSequence;
            _chatInitialized = true;
            if (_chatDisplayMode == OverlayChatDisplayMode.MessageList)
            {
                PopulateChatHistory(visibleMessages, settings, zh);
            }

            OnChanged(nameof(ChatVisibility));
            RefreshEventNotificationTimer();
            return;
        }

        if (_chatDisplayMode == OverlayChatDisplayMode.MessageList)
        {
            _chatLastSequence = Math.Max(_chatLastSequence, latestSequence);
            PopulateChatHistory(visibleMessages, settings, zh);
            RefreshEventNotificationTimer();
            return;
        }

        foreach (var message in visibleMessages.Where(message => message.Sequence > _chatLastSequence))
        {
            QueueOrShowChatMessage(message, settings, zh);
        }

        _chatLastSequence = Math.Max(_chatLastSequence, latestSequence);
        RefreshEventNotificationTimer();
    }

    private void PopulateChatHistory(
        IReadOnlyList<OverlayChatMessage> messages,
        OverlayDisplaySettings settings,
        bool zh)
    {
        ChatMessages.Clear();
        foreach (var message in messages.TakeLast(ChatMessageListHistoryCapacity))
        {
            ChatMessages.Add(CreateChatRow(message, settings, zh, DateTimeOffset.MaxValue));
        }

        ChatPulse++;
        OnChanged(nameof(ChatVisibility));
    }

    private void QueueOrShowChatMessage(OverlayChatMessage message, OverlayDisplaySettings settings, bool zh)
    {
        if (ChatMessages.Count >= _chatMaxVisibleCount)
        {
            _pendingChatMessages.Enqueue(message);
            return;
        }

        ShowChatMessage(message, settings, zh, DateTimeOffset.Now);
    }

    private void ShowChatMessage(
        OverlayChatMessage message,
        OverlayDisplaySettings settings,
        bool zh,
        DateTimeOffset now)
    {
        var row = CreateChatRow(message, settings, zh, now.AddSeconds(_chatDurationSeconds));
        if (_chatDisplayMode == OverlayChatDisplayMode.FullScreenBarrage)
        {
            var lane = ResolveAvailableChatBarrageLane();
            if (_animationFrameRate == OverlayAnimationFrameRate.Off)
            {
                row.SetBarrageLane(lane);
            }
            else
            {
                row.BeginBarrage(now, ResolveChatBarrageDuration(row, settings), lane);
            }
        }
        else if (_animationFrameRate != OverlayAnimationFrameRate.Off)
        {
            row.BeginEnter(now, ResolveChatSlideOffset());
        }

        ChatMessages.Add(row);
        ChatPulse++;
        OnChanged(nameof(ChatVisibility));
    }

    public void ApplyChatBarrageViewportWidth(double viewportWidth)
    {
        if (double.IsFinite(viewportWidth) && viewportWidth > 0)
        {
            _chatBarrageViewportWidth = viewportWidth;
        }
    }

    private double ResolveChatBarrageDuration(
        OverlayEventNotificationRow row,
        OverlayDisplaySettings settings)
    {
        var fontSize = OverlayDisplaySettings.NormalizeChatBarrageFontSize(settings.ChatBarrageFontSize);
        var contentWidth =
            OverlayDisplaySettings.EstimateChatBarrageTextWidth(row.Title, fontSize) +
            OverlayDisplaySettings.EstimateChatBarrageTextWidth(row.Detail, fontSize) +
            (string.IsNullOrWhiteSpace(row.Timestamp) ? 0 : 52 * fontSize / 16d) +
            72;
        var travelDistance = Math.Max(1, _chatBarrageViewportWidth) + contentWidth + 120;
        return Math.Clamp(
            travelDistance / OverlayDisplaySettings.ResolveChatBarragePixelsPerSecond(settings.ChatDurationSeconds),
            4,
            30);
    }

    private int ResolveAvailableChatBarrageLane()
    {
        var occupied = ChatMessages
            .Where(message => message.BarrageLane >= 0)
            .Select(message => message.BarrageLane)
            .ToHashSet();
        var start = Random.Shared.Next(ChatBarrageLaneCount);
        for (var offset = 0; offset < ChatBarrageLaneCount; offset++)
        {
            var lane = (start + offset) % ChatBarrageLaneCount;
            if (!occupied.Contains(lane))
            {
                return lane;
            }
        }

        return start;
    }

    private OverlayEventNotificationRow CreateChatRow(
        OverlayChatMessage message,
        OverlayDisplaySettings settings,
        bool zh,
        DateTimeOffset expiresAt)
    {
        var sender = message.IsSystem
            ? zh ? "系统" : "SYSTEM"
            : FormatChatSender(message);
        if (!string.IsNullOrWhiteSpace(message.SourceLabel))
        {
            sender = $"{message.SourceLabel} · {sender}";
        }
        var title = settings.ChatShowSender
            ? sender
            : zh ? "通讯消息" : "COMMS MESSAGE";
        var timestamp = settings.ChatShowTimestamp
            ? CommunicationTimeFormatter.Format(message.CreatedAt)
            : "";
        return new OverlayEventNotificationRow(
            title,
            message.Text,
            timestamp,
            ParseChatAccentBrush(message.SenderColor),
            expiresAt,
            OverlayEventNotificationTypes.None);
    }

    private static string FormatChatSender(OverlayChatMessage message)
    {
        if (string.IsNullOrWhiteSpace(message.SenderCallsign))
        {
            return string.IsNullOrWhiteSpace(message.SenderGameId) ? "未知成员" : message.SenderGameId;
        }

        return string.IsNullOrWhiteSpace(message.SenderGameId) ||
               message.SenderCallsign.Equals(message.SenderGameId, StringComparison.OrdinalIgnoreCase)
            ? message.SenderCallsign
            : $"{message.SenderCallsign} ({message.SenderGameId})";
    }

    private static Brush ParseChatAccentBrush(string value)
    {
        try
        {
            return new SolidColorBrush((Color)System.Windows.Media.ColorConverter.ConvertFromString(value)!);
        }
        catch
        {
            return new SolidColorBrush(Color.FromRgb(105, 204, 255));
        }
    }

    private void ResetChatState()
    {
        var changed = ChatMessages.Count > 0 || _pendingChatMessages.Count > 0 || _chatInitialized;
        ChatMessages.Clear();
        _pendingChatMessages.Clear();
        _chatChannelId = "";
        _chatSettingsSignature = "";
        _chatLastSequence = 0;
        _chatInitialized = false;
        if (changed)
        {
            OnChanged(nameof(ChatVisibility));
        }

        RefreshEventNotificationTimer();
    }

    public void ApplyOverviewPanelLayout(
        OverlaySquadStatusDisplayMode _,
        double panelWidth,
        double panelHeight)
    {
        _overviewPanelWidth = double.IsFinite(panelWidth) ? Math.Max(0, panelWidth) : 0;
        _overviewPanelHeight = double.IsFinite(panelHeight) ? Math.Max(0, panelHeight) : 0;

        // Fleet and room scenes share one dimension-driven information skeleton.
        // The serialized legacy mode remains readable for compatibility but can no
        // longer make the room scene regress to a second overview layout.
        SquadStatusCompactVisibility = Visibility.Collapsed;
        SquadStatusDetailVisibility = Visibility.Collapsed;
        var layout = OverlayOverviewLocationLayout.Resolve(
            _overviewPanelWidth,
            _overviewPanelHeight,
            OverviewTopLocations);
        OverviewVisibleLocations = layout.VisibleItems;
        var hasLocations = layout.VisibleItems.Count > 0;
        OverviewLocationsHorizontalVisibility = hasLocations &&
                                                layout.Orientation == OverlayOverviewLocationOrientation.Horizontal
            ? Visibility.Visible
            : Visibility.Collapsed;
        OverviewLocationsVerticalVisibility = hasLocations &&
                                              layout.Orientation == OverlayOverviewLocationOrientation.Vertical
            ? Visibility.Visible
            : Visibility.Collapsed;
    }

    private void RefreshGameEventNotifications(
        IReadOnlyCollection<PlayerRow> players,
        OverlayDisplaySettings settings,
        bool zh,
        bool hasFleet,
        string localShard,
        OverlaySceneContext sceneContext)
    {
        _eventNotificationDurationSeconds = Math.Clamp(settings.EventNotificationDurationSeconds, 1, 12);
        _eventNotificationMaxVisibleCount = OverlayDisplaySettings.NormalizeEventNotificationMaxVisibleCount(settings.EventNotificationMaxVisibleCount);
        _eventNotificationPinImportant = settings.EventNotificationPinImportant;
        _eventNotificationSide = settings.EventNotificationSide;
        _eventNotificationAnimationScale = OverlayDisplaySettings.ResolveEventNotificationAnimationScale(settings.EventNotificationAnimationSpeed);
        _eventNotificationDurations = settings.EventNotificationDurations;
        _animationFrameRate = settings.AnimationFrameRate;
        RefreshEventNotificationRetentionSettings();
        CompleteEventNotificationMotionWhenDisabled(DateTimeOffset.Now);
        PromotePendingEventNotifications(DateTimeOffset.Now);
        var nextPlayerStates = BuildGameEventPlayerStates(players, settings.MemberNameMode, localShard);
        var nextFleetState = BuildGameEventFleetState(players, localShard);
        var sceneKind = sceneContext.Kind;
        var sceneChanged = _gameEventSnapshotSceneKind.HasValue &&
                           _gameEventSnapshotSceneKind.Value != sceneKind;
        _gameEventSnapshotSceneKind = sceneKind;

        if (sceneChanged)
        {
            ReplaceGameEventSnapshot(nextPlayerStates, nextFleetState, localShard);
            _gameEventSnapshotInitialized = true;
            if (!settings.ShowEventNotifications)
            {
                ClearEventNotifications();
            }
            return;
        }

        if (!settings.ShowEventNotifications)
        {
            ReplaceGameEventSnapshot(nextPlayerStates, nextFleetState, localShard);
            _gameEventSnapshotInitialized = true;
            ClearEventNotifications();
            return;
        }

        if (!sceneContext.IsLocalOnly)
        {
            QueueEventReceiverConnectionIfNeeded(zh);
        }

        if (!_gameEventSnapshotInitialized)
        {
            ReplaceGameEventSnapshot(nextPlayerStates, nextFleetState, localShard);
            _gameEventSnapshotInitialized = true;
            return;
        }

        var eventTypes = OverlayDisplaySettings.NormalizeEventNotificationTypes(settings.EventNotificationTypes);
        if (eventTypes == OverlayEventNotificationTypes.None ||
            !hasFleet && !sceneContext.IsLocalOnly)
        {
            ReplaceGameEventSnapshot(nextPlayerStates, nextFleetState, localShard);
            return;
        }

        if (sceneContext.IsLocalOnly)
        {
            foreach (var player in players.Where(player => player.IsSelf))
            {
                var key = ResolvePlayerEventKey(player);
                if (nextPlayerStates.TryGetValue(key, out var nextState) &&
                    _gameEventPlayerStates.TryGetValue(key, out var previousState))
                {
                    QueuePlayerGameEvents(previousState, nextState, eventTypes, zh);
                }
            }

            ReplaceGameEventSnapshot(nextPlayerStates, nextFleetState, localShard);
            return;
        }

        QueueLocalServerSummaryIfNeeded(players, localShard, eventTypes, zh);
        QueueFleetSummaryEvents(_gameEventFleetState, nextFleetState, eventTypes, zh);
        foreach (var player in players)
        {
            var key = ResolvePlayerEventKey(player);
            if (!nextPlayerStates.TryGetValue(key, out var nextState) ||
                !_gameEventPlayerStates.TryGetValue(key, out var previousState))
            {
                continue;
            }

            QueuePlayerGameEvents(previousState, nextState, eventTypes, zh);
        }

        ReplaceGameEventSnapshot(nextPlayerStates, nextFleetState, localShard);
    }

    private Dictionary<string, OverlayGameEventPlayerState> BuildGameEventPlayerStates(
        IReadOnlyCollection<PlayerRow> players,
        OverlayMemberNameMode memberNameMode,
        string localShard)
    {
        var hasLocalShard = !string.IsNullOrWhiteSpace(localShard);
        var states = new Dictionary<string, OverlayGameEventPlayerState>(StringComparer.OrdinalIgnoreCase);
        foreach (var player in players)
        {
            var key = ResolvePlayerEventKey(player);
            states[key] = new OverlayGameEventPlayerState(
                key,
                FormatMemberName(player, memberNameMode),
                IsGamePresence(player),
                TryGetOverlayPlayerServerRegion(player, localShard),
                hasLocalShard && IsPlayerOnLocalServer(player, localShard),
                player.IsSelf,
                IsSyncPausedLiveStatus(player.LiveStatus),
                NormalizeGameEventShip(player),
                NormalizeGameEventLocation(player),
                IsUnconfirmedLocation(player.LocationConfidence),
                player.SharedEventTypes);
        }

        return states;
    }

    private static OverlayGameEventFleetState BuildGameEventFleetState(
        IReadOnlyCollection<PlayerRow> players,
        string? localShard)
    {
        return new OverlayGameEventFleetState(
            players.Count(IsGamePresence),
            players.Count,
            ResolveDominantServerRegion(players, localShard));
    }

    private void ReplaceGameEventSnapshot(
        Dictionary<string, OverlayGameEventPlayerState> playerStates,
        OverlayGameEventFleetState fleetState,
        string localShard)
    {
        _gameEventPlayerStates.Clear();
        foreach (var (key, state) in playerStates)
        {
            _gameEventPlayerStates[key] = state;
        }

        _gameEventFleetState = fleetState;
        _lastGameEventLocalShard = localShard ?? "";
    }

    private void QueueLocalServerSummaryIfNeeded(
        IReadOnlyCollection<PlayerRow> players,
        string localShard,
        OverlayEventNotificationTypes eventTypes,
        bool zh)
    {
        if (!ShouldNotifyEvent(eventTypes, OverlayEventNotificationTypes.SameServer) ||
            !string.IsNullOrWhiteSpace(_lastGameEventLocalShard) ||
            string.IsNullOrWhiteSpace(localShard))
        {
            return;
        }

        if (string.IsNullOrWhiteSpace(localShard))
        {
            return;
        }

        var sameServerCount = players.Count(player =>
            !player.IsSelf &&
            IsGamePresence(player) &&
            IsPlayerOnLocalServer(player, localShard));
        QueueEventNotification(
            OverlayEventNotificationTypes.SameServer,
            zh ? "同服概况" : "Same server",
            zh
                ? $"当前有 {sameServerCount.ToString(CultureInfo.InvariantCulture)} 名组织成员与你在同服务器"
                : $"{sameServerCount.ToString(CultureInfo.InvariantCulture)} fleet members share your server",
            AlertBrush,
            important: true);
    }

    private void QueuePlayerGameEvents(
        OverlayGameEventPlayerState previous,
        OverlayGameEventPlayerState next,
        OverlayEventNotificationTypes eventTypes,
        bool zh)
    {
        if (previous.SyncPaused != next.SyncPaused &&
            AllowsSharedEvent(next, PlayerSharedEventTypes.Presence) &&
            ShouldNotifyEvent(eventTypes, OverlayEventNotificationTypes.MemberPresence))
        {
            var notice = FormatMemberPresenceNotification(next.DisplayName, next.Online, next.SyncPaused, zh);
            QueueEventNotification(
                OverlayEventNotificationTypes.MemberPresence,
                notice.Title,
                notice.Detail,
                next.SyncPaused ? MutedBrush : OnlineBrush);
            return;
        }

        if (previous.Online != next.Online &&
            !previous.SyncPaused &&
            !next.SyncPaused &&
            AllowsSharedEvent(next, PlayerSharedEventTypes.Presence) &&
            ShouldNotifyEvent(eventTypes, OverlayEventNotificationTypes.MemberPresence))
        {
            var notice = FormatMemberPresenceNotification(next.DisplayName, next.Online, next.SyncPaused, zh);
            QueueEventNotification(
                OverlayEventNotificationTypes.MemberPresence,
                notice.Title,
                notice.Detail,
                next.Online ? OnlineBrush : MutedBrush);
        }

        if (next.SyncPaused)
        {
            return;
        }

        if (previous.Online &&
            next.Online &&
            string.IsNullOrWhiteSpace(previous.ServerRegion) &&
            !string.IsNullOrWhiteSpace(next.ServerRegion) &&
            AllowsSharedEvent(next, PlayerSharedEventTypes.Server) &&
            ShouldNotifyEvent(eventTypes, OverlayEventNotificationTypes.MemberServer))
        {
            QueueEventNotification(
                OverlayEventNotificationTypes.MemberServer,
                zh ? "成员进入服务器" : "Member entered server",
                zh ? $"{next.DisplayName} 进入 {next.ServerRegion}" : $"{next.DisplayName} entered {next.ServerRegion}",
                TitleBrush);
        }

        if (previous.Online &&
            !string.IsNullOrWhiteSpace(previous.ServerRegion) &&
            (string.IsNullOrWhiteSpace(next.ServerRegion) || !next.Online) &&
            AllowsSharedEvent(next, PlayerSharedEventTypes.Server) &&
            ShouldNotifyEvent(eventTypes, OverlayEventNotificationTypes.MemberServer))
        {
            QueueEventNotification(
                OverlayEventNotificationTypes.MemberServer,
                zh ? "成员离开服务器" : "Member left server",
                zh ? $"{next.DisplayName} 已离开服务器" : $"{next.DisplayName} left server",
                MutedBrush);
        }

        if (!previous.SameServer &&
            next.SameServer &&
            next.Online &&
            !next.IsSelf &&
            AllowsSharedEvent(next, PlayerSharedEventTypes.Server) &&
            ShouldNotifyEvent(eventTypes, OverlayEventNotificationTypes.SameServer))
        {
            QueueEventNotification(
                OverlayEventNotificationTypes.SameServer,
                zh ? "同服成员" : "Same server member",
                zh ? $"{next.DisplayName} 进入与你相同服务器" : $"{next.DisplayName} joined your server",
                AlertBrush,
                important: true);
        }
        else if (previous.SameServer &&
                 !next.SameServer &&
                 !next.IsSelf &&
                 AllowsSharedEvent(next, PlayerSharedEventTypes.Server) &&
                 ShouldNotifyEvent(eventTypes, OverlayEventNotificationTypes.SameServer))
        {
            QueueEventNotification(
                OverlayEventNotificationTypes.SameServer,
                zh ? "同服成员离开" : "Same server left",
                zh ? $"{next.DisplayName} 已离开你的服务器" : $"{next.DisplayName} left your server",
                MutedBrush);
        }

        if (previous.Online &&
            next.Online &&
            !string.IsNullOrWhiteSpace(previous.Ship) &&
            !string.IsNullOrWhiteSpace(next.Ship) &&
            !previous.Ship.Equals(next.Ship, StringComparison.OrdinalIgnoreCase) &&
            AllowsSharedEvent(next, PlayerSharedEventTypes.Ship) &&
            ShouldNotifyEvent(eventTypes, OverlayEventNotificationTypes.ShipChange))
        {
            QueueEventNotification(
                OverlayEventNotificationTypes.ShipChange,
                zh ? "飞船变化" : "Ship changed",
                OverlayEventShipPresentation.FormatShipChange(next.DisplayName, next.Ship, zh),
                TitleBrush);
        }

        if (previous.Online &&
            next.Online &&
            !string.IsNullOrWhiteSpace(previous.Location) &&
            !string.IsNullOrWhiteSpace(next.Location) &&
            !previous.Location.Equals(next.Location, StringComparison.OrdinalIgnoreCase) &&
            AllowsSharedEvent(next, PlayerSharedEventTypes.Location) &&
            ShouldNotifyEvent(eventTypes, OverlayEventNotificationTypes.LocationChange))
        {
            var displayLocation = FormatGameEventLocation(next.Location, zh);
            if (next.LocationUnconfirmed)
            {
                QueueMergeableLocationEventNotification(
                    next.Key,
                    OverlayLocationMergePhase.Provisional,
                    zh ? "量子抵达" : "Quantum arrival",
                    zh
                        ? $"{next.DisplayName} 可能抵达：{displayLocation}"
                        : $"{next.DisplayName} may have arrived at {displayLocation}",
                    MutedBrush);
            }
            else if (previous.LocationUnconfirmed)
            {
                QueueMergeableLocationEventNotification(
                    next.Key,
                    OverlayLocationMergePhase.Confirmed,
                    zh ? "地点已确认" : "Location confirmed",
                    zh
                        ? $"{next.DisplayName} 已抵达：{displayLocation}"
                        : $"{next.DisplayName} arrived at {displayLocation}",
                    TitleBrush);
            }
            else
            {
                QueueEventNotification(
                    OverlayEventNotificationTypes.LocationChange,
                    zh ? "地点变化" : "Location changed",
                    zh ? $"{next.DisplayName} 位置：{displayLocation}" : $"{next.DisplayName} location: {displayLocation}",
                    TitleBrush);
            }
        }

    }

    private static (string Title, string Detail) FormatMemberPresenceNotification(
        string displayName,
        bool nextOnline,
        bool nextSyncPaused,
        bool zh)
    {
        return nextOnline
            ? zh
                ? ("成员上线", $"{displayName} 已上线")
                : ("Member online", $"{displayName} is online")
            : zh
                ? ("成员离线", $"{displayName} 已下线")
                : ("Member offline", $"{displayName} is offline");
    }

    private void QueueFleetSummaryEvents(
        OverlayGameEventFleetState previous,
        OverlayGameEventFleetState next,
        OverlayEventNotificationTypes eventTypes,
        bool zh)
    {
        if (previous.MemberCount > 0 &&
            previous.OnlineCount != next.OnlineCount &&
            ShouldNotifyEvent(eventTypes, OverlayEventNotificationTypes.OnlineSummary))
        {
            QueueEventNotification(
                OverlayEventNotificationTypes.OnlineSummary,
                zh ? "舰队在线" : "Fleet online",
                zh
                    ? $"舰队在线 {next.OnlineCount.ToString(CultureInfo.InvariantCulture)} / {next.MemberCount.ToString(CultureInfo.InvariantCulture)}"
                    : $"Fleet online {next.OnlineCount.ToString(CultureInfo.InvariantCulture)} / {next.MemberCount.ToString(CultureInfo.InvariantCulture)}",
                next.OnlineCount >= previous.OnlineCount ? OnlineBrush : MutedBrush,
                important: true);
        }

        if (!string.IsNullOrWhiteSpace(next.DominantServerRegion) &&
            !string.Equals(previous.DominantServerRegion, next.DominantServerRegion, StringComparison.OrdinalIgnoreCase) &&
            ShouldNotifyEvent(eventTypes, OverlayEventNotificationTypes.PrimaryServer))
        {
            QueueEventNotification(
                OverlayEventNotificationTypes.PrimaryServer,
                zh ? "主服务器" : "Primary server",
                zh ? $"当前主服务器：{next.DominantServerRegion}" : $"Primary server: {next.DominantServerRegion}",
                AlertBrush,
                important: true);
        }
    }

    private static string? NormalizeGameEventShip(PlayerRow player)
    {
        return NormalizeGameEventValue(player.RawShip) ??
               NormalizeGameEventValue(player.ShipInfo) ??
               NormalizeGameEventValue(player.Ship);
    }

    private static string? NormalizeGameEventLocation(PlayerRow player)
    {
        return NormalizeGameEventValue(player.RawLocation) ??
               NormalizeGameEventValue(player.Location);
    }

    private static string FormatGameEventLocation(string? location, bool zh)
    {
        return LocationNameLocalizer.DisplayName(location, zh ? "zh" : "en");
    }

    private static string? NormalizeGameEventValue(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        var text = value.Trim();
        const string shipPrefix = "飞船：";
        const string locationPrefix = "地点：";
        if (text.StartsWith(shipPrefix, StringComparison.OrdinalIgnoreCase))
        {
            text = text[shipPrefix.Length..].Trim();
        }
        else if (text.StartsWith(locationPrefix, StringComparison.OrdinalIgnoreCase))
        {
            text = text[locationPrefix.Length..].Trim();
        }

        return IsUnknownGameEventValue(text) ||
               PlayerSessionStatePresentation.IsSessionStateText(text)
            ? null
            : text;
    }

    private static bool IsUnknownGameEventValue(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return true;
        }

        var text = value.Trim();
        return text.Equals("Unknown", StringComparison.OrdinalIgnoreCase) ||
               text.Equals("None", StringComparison.OrdinalIgnoreCase) ||
               text.Equals("N/A", StringComparison.OrdinalIgnoreCase) ||
               text.Equals("未知", StringComparison.OrdinalIgnoreCase) ||
               text.Equals("无", StringComparison.OrdinalIgnoreCase) ||
               text.Equals("未连接", StringComparison.OrdinalIgnoreCase) ||
               text.Equals("等待确认", StringComparison.OrdinalIgnoreCase) ||
               text.Equals("仅游戏中显示", StringComparison.OrdinalIgnoreCase) ||
               text.Contains("未知", StringComparison.OrdinalIgnoreCase);
    }

    private static bool IsUnconfirmedLocation(string? confidence)
    {
        return confidence is not null &&
               (confidence.Equals("Medium", StringComparison.OrdinalIgnoreCase) ||
                confidence.Equals("中", StringComparison.OrdinalIgnoreCase) ||
                confidence.Equals("Low", StringComparison.OrdinalIgnoreCase) ||
                confidence.Equals("低", StringComparison.OrdinalIgnoreCase));
    }

    private static bool ShouldNotifyEvent(
        OverlayEventNotificationTypes enabledTypes,
        OverlayEventNotificationTypes eventType)
    {
        return (enabledTypes & eventType) == eventType;
    }

    private static bool AllowsSharedEvent(
        OverlayGameEventPlayerState player,
        PlayerSharedEventTypes eventType) =>
        PlayerEventSharingSettings.FromWireValue(player.SharedEventTypes).HasFlag(eventType);

    private static string ResolvePlayerEventKey(PlayerRow player)
    {
        return string.IsNullOrWhiteSpace(player.Callsign)
            ? player.Name
            : player.Callsign!;
    }

    private void QueueEventReceiverConnectionIfNeeded(bool zh)
    {
        if (_eventNotificationConnectionQueued)
        {
            return;
        }

        _eventNotificationConnectionQueued = true;
        QueueSystemEventNotification(
            zh ? "事件接收系统" : "Event receiver",
            zh ? "已连接事件接收系统" : "Event receiver connected",
            TitleBrush);
    }

    private void QueueSystemEventNotification(
        string title,
        string detail,
        Brush accent)
    {
        QueueOrShowEventNotification(new PendingOverlayEventNotification(
            title,
            detail,
            DateTime.Now.ToString("HH:mm", CultureInfo.InvariantCulture),
            accent,
            OverlayEventNotificationTypes.None,
            Important: false,
            MergeKey: null,
            OverlayLocationMergePhase.None,
            DateTimeOffset.Now));
    }

    private void QueueEventNotification(
        OverlayEventNotificationTypes eventType,
        string title,
        string detail,
        Brush accent,
        bool important = false)
    {
        QueueOrShowEventNotification(new PendingOverlayEventNotification(
            title,
            detail,
            DateTime.Now.ToString("HH:mm", CultureInfo.InvariantCulture),
            accent,
            eventType,
            important,
            MergeKey: null,
            OverlayLocationMergePhase.None,
            DateTimeOffset.Now));
    }

    private void QueueMergeableLocationEventNotification(
        string playerKey,
        OverlayLocationMergePhase mergePhase,
        string title,
        string detail,
        Brush accent)
    {
        QueueOrShowEventNotification(new PendingOverlayEventNotification(
            title,
            detail,
            DateTime.Now.ToString("HH:mm", CultureInfo.InvariantCulture),
            accent,
            OverlayEventNotificationTypes.LocationChange,
            Important: false,
            MergeKey: $"location:{playerKey}",
            mergePhase,
            DateTimeOffset.Now));
    }

    public void QueueGameEventNotification(
        OverlayEventNotificationTypes eventType,
        string title,
        string detail,
        bool important,
        bool positive)
    {
        QueueEventNotification(
            eventType,
            title,
            detail,
            positive ? OnlineBrush : AlertBrush,
            important);
    }

    private void QueueOrShowEventNotification(PendingOverlayEventNotification notification)
    {
        if (TryMergeEventNotification(notification))
        {
            return;
        }

        if (EventNotifications.Count >= _eventNotificationMaxVisibleCount)
        {
            _pendingEventNotifications.Enqueue(notification);
            OnChanged(nameof(PendingEventNotificationCount));
            return;
        }

        ShowEventNotification(notification, DateTimeOffset.Now);
    }

    private void ShowEventNotification(PendingOverlayEventNotification notification, DateTimeOffset now)
    {
        var durationSeconds = ResolveEventNotificationDuration(notification.EventType);
        var expiresAt = notification.Important && _eventNotificationPinImportant
            ? DateTimeOffset.MaxValue
            : now.AddSeconds(durationSeconds);
        var row = new OverlayEventNotificationRow(
            notification.Title,
            notification.Detail,
            notification.Timestamp,
            notification.Accent,
            expiresAt,
            notification.EventType);
        row.ConfigureMerge(notification.MergeKey, notification.MergePhase, notification.CreatedAt);
        if (_animationFrameRate != OverlayAnimationFrameRate.Off)
        {
            row.BeginEnter(now, ResolveEventNotificationSlideOffset());
        }

        EventNotifications.Add(row);
        EventNotificationPulse++;
        OnChanged(nameof(EventNotificationVisibility));
        RefreshEventNotificationTimer();
    }

    private bool TryMergeEventNotification(PendingOverlayEventNotification notification)
    {
        if (notification.MergePhase != OverlayLocationMergePhase.Confirmed ||
            string.IsNullOrWhiteSpace(notification.MergeKey))
        {
            return false;
        }

        var now = DateTimeOffset.Now;
        var visible = EventNotifications.LastOrDefault(row =>
            !row.IsExiting &&
            row.MergePhase == OverlayLocationMergePhase.Provisional &&
            notification.MergeKey.Equals(row.MergeKey, StringComparison.OrdinalIgnoreCase) &&
            now - row.MergeUpdatedAt <= LocationEventMergeWindow);
        if (visible is not null)
        {
            visible.MergeContent(
                notification.Title,
                notification.Detail,
                notification.Timestamp,
                notification.Accent,
                notification.MergePhase,
                now,
                now.AddSeconds(ResolveEventNotificationDuration(notification.EventType)));
            EventNotificationPulse++;
            OnChanged(nameof(EventNotificationVisibility));
            RefreshEventNotificationTimer();
            return true;
        }

        var pending = _pendingEventNotifications.ToArray();
        var pendingIndex = Array.FindLastIndex(pending, row =>
            row.MergePhase == OverlayLocationMergePhase.Provisional &&
            notification.MergeKey.Equals(row.MergeKey, StringComparison.OrdinalIgnoreCase) &&
            now - row.CreatedAt <= LocationEventMergeWindow);
        if (pendingIndex < 0)
        {
            return false;
        }

        pending[pendingIndex] = notification with { CreatedAt = now };
        _pendingEventNotifications.Clear();
        foreach (var row in pending)
        {
            _pendingEventNotifications.Enqueue(row);
        }

        return true;
    }

    private double ResolveEventNotificationDuration(OverlayEventNotificationTypes eventType)
    {
        return eventType == OverlayEventNotificationTypes.None
            ? _eventNotificationDurationSeconds
            : _eventNotificationDurations.Resolve(eventType, _eventNotificationDurationSeconds);
    }

    private bool PromotePendingEventNotifications(DateTimeOffset now)
    {
        var promoted = false;
        while (EventNotifications.Count < _eventNotificationMaxVisibleCount &&
               _pendingEventNotifications.TryDequeue(out var pending))
        {
            ShowEventNotification(pending, now);
            promoted = true;
        }

        if (promoted)
        {
            OnChanged(nameof(PendingEventNotificationCount));
        }

        return promoted;
    }

    private void RefreshEventNotificationRetentionSettings()
    {
        var changed = false;
        var now = DateTimeOffset.Now;
        if (!_eventNotificationPinImportant)
        {
            var fallbackExpiresAt = now.AddSeconds(_eventNotificationDurationSeconds);
            foreach (var notification in EventNotifications)
            {
                if (notification.ExpiresAt == DateTimeOffset.MaxValue)
                {
                    notification.ExpiresAt = fallbackExpiresAt;
                    changed = true;
                }
            }
        }

        if (changed)
        {
            OnChanged(nameof(EventNotificationVisibility));
        }

        RefreshEventNotificationTimer();
    }

    private sealed record OverlayGameEventPlayerState(
        string Key,
        string DisplayName,
        bool Online,
        string? ServerRegion,
        bool SameServer,
        bool IsSelf,
        bool SyncPaused,
        string? Ship,
        string? Location,
        bool LocationUnconfirmed,
        int SharedEventTypes);

    private sealed record OverlayGameEventFleetState(
        int OnlineCount,
        int MemberCount,
        string? DominantServerRegion)
    {
        public static OverlayGameEventFleetState Empty { get; } = new(0, 0, null);
    }

    private void TickEventNotifications(DateTimeOffset now)
    {
        var changed = false;
        var slideOffset = ResolveEventNotificationSlideOffset();
        foreach (var notification in EventNotifications)
        {
            if (!notification.IsExiting && notification.ExpiresAt <= now)
            {
                if (_animationFrameRate == OverlayAnimationFrameRate.Off)
                {
                    notification.MarkForImmediateRemoval();
                }
                else
                {
                    notification.BeginExit(now, slideOffset);
                }
                changed = true;
            }
        }

        var removed = false;
        for (var index = EventNotifications.Count - 1; index >= 0; index--)
        {
            if (EventNotifications[index].AdvanceAnimation(now, _eventNotificationAnimationScale))
            {
                EventNotifications.RemoveAt(index);
                removed = true;
            }
        }

        var promoted = removed && PromotePendingEventNotifications(now);

        if (changed || removed || promoted || EventNotifications.Any(notification => notification.IsAnimating))
        {
            EventNotificationAnimationFrame++;
        }

        if (changed || removed || promoted)
        {
            OnChanged(nameof(EventNotificationVisibility));
        }

        RefreshEventNotificationTimer();
    }

    private void TickChatMessages(DateTimeOffset now)
    {
        if (_chatDisplayMode != OverlayChatDisplayMode.FullScreenBarrage)
        {
            return;
        }

        var removed = false;
        for (var index = ChatMessages.Count - 1; index >= 0; index--)
        {
            var message = ChatMessages[index];
            var completed = _animationFrameRate == OverlayAnimationFrameRate.Off
                ? message.ExpiresAt <= now
                : message.AdvanceBarrage(now);
            if (completed)
            {
                ChatMessages.RemoveAt(index);
                removed = true;
            }
        }

        var promoted = false;
        while (removed &&
               ChatMessages.Count < _chatMaxVisibleCount &&
               _pendingChatMessages.TryDequeue(out var pending))
        {
            ShowChatMessage(pending, _chatSettings, _chatZh, now);
            promoted = true;
        }

        if (removed || promoted)
        {
            ChatAnimationFrame++;
        }

        if (removed || promoted)
        {
            OnChanged(nameof(ChatVisibility));
        }

        RefreshEventNotificationTimer();
    }

    private double ResolveChatSlideOffset()
    {
        return _chatSide == OverlayChatSide.Left
            ? -EventNotificationSlideDistance
            : EventNotificationSlideDistance;
    }

    private double ResolveEventNotificationSlideOffset()
    {
        return _eventNotificationSide == OverlayEventNotificationSide.Left
            ? -EventNotificationSlideDistance
            : EventNotificationSlideDistance;
    }

    private void RefreshEventNotificationTimer()
    {
        var hasAnimatingNotification = EventNotifications.Any(notification => notification.IsAnimating) ||
                                       ChatMessages.Any(message => message.IsEntering || message.IsExiting);
        if (hasAnimatingNotification)
        {
            _eventNotificationTimer.Interval = ResolveEventNotificationAnimationInterval();
            _eventNotificationTimer.Start();
            return;
        }

        if (EventNotifications.Any(notification => !notification.IsExiting && notification.ExpiresAt < DateTimeOffset.MaxValue) ||
            ChatMessages.Any(message => !message.IsExiting && message.ExpiresAt < DateTimeOffset.MaxValue))
        {
            _eventNotificationTimer.Interval = EventNotificationIdleInterval;
            _eventNotificationTimer.Start();
            return;
        }

        _eventNotificationTimer.Stop();
    }

    private void ClearEventNotifications()
    {
        if (EventNotifications.Count == 0 && _pendingEventNotifications.Count == 0)
        {
            return;
        }

        EventNotifications.Clear();
        _pendingEventNotifications.Clear();
        OnChanged(nameof(EventNotificationVisibility));
        OnChanged(nameof(PendingEventNotificationCount));
        RefreshEventNotificationTimer();
    }

    private TimeSpan ResolveEventNotificationAnimationInterval()
    {
        var fps = (int)_animationFrameRate;
        return fps > 0
            ? TimeSpan.FromMilliseconds(1000.0 / fps)
            : EventNotificationIdleInterval;
    }

    private void CompleteEventNotificationMotionWhenDisabled(DateTimeOffset now)
    {
        if (_animationFrameRate != OverlayAnimationFrameRate.Off)
        {
            return;
        }

        var removed = false;
        for (var index = EventNotifications.Count - 1; index >= 0; index--)
        {
            if (EventNotifications[index].CompleteMotionImmediately())
            {
                EventNotifications.RemoveAt(index);
                removed = true;
            }
        }

        if (removed)
        {
            PromotePendingEventNotifications(now);
            OnChanged(nameof(EventNotificationVisibility));
        }
    }

    private sealed record PendingOverlayEventNotification(
        string Title,
        string Detail,
        string Timestamp,
        Brush Accent,
        OverlayEventNotificationTypes EventType,
        bool Important,
        string? MergeKey,
        OverlayLocationMergePhase MergePhase,
        DateTimeOffset CreatedAt);

    private sealed record PendingCommunicationEvent(string Title, string Detail);

    private static bool IsGamePresence(PlayerRow player) =>
        player.Presence == PlayerPresenceKind.InGame;

    private static bool IsSyncPausedLiveStatus(string? liveStatus)
    {
        if (string.IsNullOrWhiteSpace(liveStatus))
        {
            return false;
        }

        var normalized = liveStatus.Trim()
            .Replace(" ", "", StringComparison.Ordinal)
            .Replace("-", "", StringComparison.Ordinal)
            .Replace("_", "", StringComparison.Ordinal)
            .ToUpperInvariant();
        return normalized is "PAUSED" or "STOPPED" or "SUSPENDED" or "SYNCSTOPPED" or "SYNCPAUSED";
    }

    private void ApplyCrosshairSettings(OverlayDisplaySettings settings)
    {
        var size = OverlayDisplaySettings.NormalizeCrosshairSize(settings.CrosshairSize);
        var thickness = Math.Clamp(settings.CrosshairThickness, 1, 8);
        var gap = OverlayDisplaySettings.NormalizeCrosshairGap(settings.CrosshairGap);
        var centerMarkSize = OverlayDisplaySettings.NormalizeCrosshairCenterMarkSize(settings.CrosshairCenterMarkSize);
        var showCenterMark = settings.CrosshairShowCenterMark && centerMarkSize > 0.5;
        CrosshairSize = size;
        CrosshairOpacity = Math.Clamp(settings.CrosshairOpacity, 0.2, 1.0);
        CrosshairOutlineOpacity = OverlayDisplaySettings.NormalizeCrosshairOutlineOpacity(settings.CrosshairOutlineOpacity);
        CrosshairCenterMarkVisibility = showCenterMark ? Visibility.Visible : Visibility.Collapsed;

        var simpleCompensation = 96.0 / size;
        SimpleCrosshairStrokeThickness = thickness * simpleCompensation;
        SimpleCrosshairDotSize = Math.Max(1, centerMarkSize) * simpleCompensation;
        var simpleArm = Math.Clamp(38 - gap, 12, 30);
        SimpleCrosshairNegativeFar = 48 - gap - simpleArm;
        SimpleCrosshairNegativeNear = 48 - gap;
        SimpleCrosshairPositiveNear = 48 + gap;
        SimpleCrosshairPositiveFar = 48 + gap + simpleArm;

        var techCompensation = 142.0 / size;
        TechCrosshairStrokeThickness = thickness * techCompensation;
        TechCrosshairThinStrokeThickness = Math.Max(1, thickness * 0.72) * techCompensation;
        TechCrosshairCornerStrokeThickness = Math.Max(0.8, thickness * 0.6) * techCompensation;
        var techGap = gap * (23.0 / 14.0);
        var techArm = Math.Clamp(53 - techGap, 20, 38);
        TechCrosshairMainNegativeFar = 71 - techGap - techArm;
        TechCrosshairMainNegativeNear = 71 - techGap;
        TechCrosshairMainPositiveNear = 71 + techGap;
        TechCrosshairMainPositiveFar = 71 + techGap + techArm;
        TechCrosshairCenterMarkSize = Math.Max(4, centerMarkSize * 3.0);
        TechCrosshairCenterMarkData = BuildTechCrosshairCenterMarkData(centerMarkSize);

        if (!settings.CrosshairUseThemeColor &&
            TryParseHexColor(settings.CrosshairColor, out var customColor))
        {
            CrosshairBrush = BrushFromArgb(215, customColor.R, customColor.G, customColor.B);
        }
    }

    private static string BuildTechCrosshairCenterMarkData(double centerMarkSize)
    {
        var center = 71.0;
        var inner = Math.Max(4, centerMarkSize * 1.2);
        var outer = Math.Min(22, inner + 12);
        return string.Format(
            CultureInfo.InvariantCulture,
            "M{0:0.##},{1:0.##} L{2:0.##},{1:0.##} M{3:0.##},{1:0.##} L{4:0.##},{1:0.##} M{1:0.##},{0:0.##} L{1:0.##},{2:0.##} M{1:0.##},{3:0.##} L{1:0.##},{4:0.##}",
            center - outer,
            center,
            center - inner,
            center + inner,
            center + outer);
    }

    private void ApplyTheme(OverlayVisualTheme theme)
    {
        if (theme == OverlayVisualTheme.Verdict)
        {
            PanelBackgroundBrush = BrushFromArgb(224, 8, 10, 13);
            PanelBorderBrush = BrushFromRgb(200, 206, 212);
            TitleBrush = BrushFromRgb(247, 245, 240);
            TextBrush = BrushFromRgb(247, 245, 240);
            MutedBrush = BrushFromRgb(174, 181, 189);
            AlertBrush = BrushFromRgb(255, 25, 23);
            IconBackgroundBrush = BrushFromArgb(148, 24, 4, 9);
            OnlineBrush = BrushFromRgb(247, 245, 240);
            OfflineBrush = BrushFromArgb(107, 174, 181, 189);
            SetCrosshairBrushes(235, 247, 255, 255, 240, 0);
            return;
        }

        if (theme == OverlayVisualTheme.LagrangeWeave)
        {
            PanelBackgroundBrush = BrushFromArgb(218, 8, 11, 19);
            PanelBorderBrush = BrushFromRgb(86, 101, 121);
            TitleBrush = BrushFromRgb(174, 186, 201);
            TextBrush = BrushFromRgb(229, 235, 241);
            MutedBrush = BrushFromRgb(135, 147, 163);
            AlertBrush = BrushFromRgb(240, 167, 107);
            IconBackgroundBrush = BrushFromArgb(148, 28, 23, 22);
            OnlineBrush = BrushFromRgb(130, 197, 162);
            OfflineBrush = BrushFromRgb(135, 147, 163);
            SetCrosshairBrushes(240, 167, 107, 255, 240, 207);
            return;
        }

        if (theme == OverlayVisualTheme.NightShadow)
        {
            PanelBackgroundBrush = BrushFromArgb(204, 7, 8, 10);
            PanelBorderBrush = BrushFromRgb(62, 66, 72);
            TitleBrush = BrushFromRgb(232, 237, 242);
            TextBrush = BrushFromRgb(232, 237, 242);
            MutedBrush = BrushFromRgb(135, 145, 156);
            AlertBrush = BrushFromRgb(255, 54, 74);
            IconBackgroundBrush = BrushFromArgb(132, 28, 4, 10);
            OnlineBrush = BrushFromRgb(255, 54, 74);
            OfflineBrush = BrushFromRgb(118, 124, 134);
            SetCrosshairBrushes(214, 31, 53, 255, 54, 74);
            return;
        }

        if (theme == OverlayVisualTheme.Anvil)
        {
            PanelBackgroundBrush = BrushFromArgb(190, 0, 18, 14);
            PanelBorderBrush = BrushFromRgb(0, 255, 141);
            TitleBrush = BrushFromRgb(78, 255, 171);
            TextBrush = BrushFromRgb(229, 255, 242);
            MutedBrush = BrushFromRgb(120, 221, 173);
            AlertBrush = BrushFromRgb(208, 255, 0);
            IconBackgroundBrush = BrushFromArgb(120, 0, 42, 28);
            OnlineBrush = BrushFromRgb(121, 255, 92);
            OfflineBrush = BrushFromRgb(255, 92, 76);
            SetCrosshairBrushes(78, 255, 171, 208, 255, 0);
            return;
        }

        if (theme == OverlayVisualTheme.Drake)
        {
            PanelBackgroundBrush = BrushFromArgb(188, 22, 10, 0);
            PanelBorderBrush = BrushFromRgb(255, 138, 18);
            TitleBrush = BrushFromRgb(255, 178, 48);
            TextBrush = BrushFromRgb(255, 236, 196);
            MutedBrush = BrushFromRgb(230, 151, 62);
            AlertBrush = BrushFromRgb(255, 222, 89);
            IconBackgroundBrush = BrushFromArgb(132, 52, 22, 0);
            OnlineBrush = BrushFromRgb(255, 190, 52);
            OfflineBrush = BrushFromRgb(196, 72, 48);
            SetCrosshairBrushes(255, 178, 48, 255, 222, 89);
            return;
        }

        if (theme == OverlayVisualTheme.Argo)
        {
            PanelBackgroundBrush = BrushFromArgb(184, 23, 12, 3);
            PanelBorderBrush = BrushFromRgb(255, 111, 55);
            TitleBrush = BrushFromRgb(255, 132, 73);
            TextBrush = BrushFromRgb(255, 235, 211);
            MutedBrush = BrushFromRgb(255, 167, 113);
            AlertBrush = BrushFromRgb(142, 255, 116);
            IconBackgroundBrush = BrushFromArgb(118, 64, 22, 8);
            OnlineBrush = BrushFromRgb(125, 255, 126);
            OfflineBrush = BrushFromRgb(255, 78, 61);
            SetCrosshairBrushes(255, 132, 73, 142, 255, 116);
            return;
        }

        if (theme == OverlayVisualTheme.Musashi)
        {
            PanelBackgroundBrush = BrushFromArgb(188, 20, 17, 5);
            PanelBorderBrush = BrushFromRgb(255, 212, 98);
            TitleBrush = BrushFromRgb(255, 228, 128);
            TextBrush = BrushFromRgb(255, 246, 214);
            MutedBrush = BrushFromRgb(131, 242, 221);
            AlertBrush = BrushFromRgb(91, 255, 230);
            IconBackgroundBrush = BrushFromArgb(124, 48, 40, 12);
            OnlineBrush = BrushFromRgb(94, 255, 225);
            OfflineBrush = BrushFromRgb(255, 111, 95);
            SetCrosshairBrushes(255, 228, 128, 91, 255, 230);
            return;
        }

        if (theme == OverlayVisualTheme.Mirai)
        {
            PanelBackgroundBrush = BrushFromArgb(184, 5, 20, 30);
            PanelBorderBrush = BrushFromRgb(83, 196, 255);
            TitleBrush = BrushFromRgb(134, 225, 255);
            TextBrush = BrushFromRgb(235, 250, 255);
            MutedBrush = BrushFromRgb(122, 191, 220);
            AlertBrush = BrushFromRgb(255, 92, 72);
            IconBackgroundBrush = BrushFromArgb(120, 8, 44, 64);
            OnlineBrush = BrushFromRgb(105, 255, 218);
            OfflineBrush = BrushFromRgb(255, 91, 74);
            SetCrosshairBrushes(134, 225, 255, 255, 92, 72);
            return;
        }

        if (theme == OverlayVisualTheme.Crusader)
        {
            PanelBackgroundBrush = BrushFromArgb(178, 4, 16, 34);
            PanelBorderBrush = BrushFromRgb(20, 145, 255);
            TitleBrush = BrushFromRgb(110, 205, 255);
            TextBrush = BrushFromRgb(240, 250, 255);
            MutedBrush = BrushFromRgb(146, 202, 255);
            AlertBrush = BrushFromRgb(84, 255, 107);
            IconBackgroundBrush = BrushFromArgb(110, 3, 32, 68);
            OnlineBrush = BrushFromRgb(97, 255, 126);
            OfflineBrush = BrushFromRgb(255, 104, 122);
            SetCrosshairBrushes(110, 205, 255, 84, 255, 107);
            return;
        }

        if (theme == OverlayVisualTheme.Aegis)
        {
            PanelBackgroundBrush = BrushFromArgb(186, 0, 18, 16);
            PanelBorderBrush = BrushFromRgb(55, 224, 214);
            TitleBrush = BrushFromRgb(84, 245, 232);
            TextBrush = BrushFromRgb(224, 255, 250);
            MutedBrush = BrushFromRgb(112, 201, 193);
            AlertBrush = BrushFromRgb(255, 51, 41);
            IconBackgroundBrush = BrushFromArgb(118, 0, 44, 42);
            OnlineBrush = BrushFromRgb(92, 255, 185);
            OfflineBrush = BrushFromRgb(255, 63, 55);
            SetCrosshairBrushes(84, 245, 232, 255, 51, 41);
            return;
        }

        if (theme == OverlayVisualTheme.Rsi)
        {
            PanelBackgroundBrush = BrushFromArgb(184, 20, 12, 34);
            PanelBorderBrush = BrushFromRgb(150, 143, 255);
            TitleBrush = BrushFromRgb(214, 201, 255);
            TextBrush = BrushFromRgb(250, 246, 255);
            MutedBrush = BrushFromRgb(187, 166, 220);
            AlertBrush = BrushFromRgb(255, 151, 58);
            IconBackgroundBrush = BrushFromArgb(124, 35, 22, 64);
            OnlineBrush = BrushFromRgb(116, 238, 210);
            OfflineBrush = BrushFromRgb(255, 112, 86);
            SetCrosshairBrushes(214, 201, 255, 255, 151, 58);
            return;
        }

        if (theme == OverlayVisualTheme.Origin)
        {
            PanelBackgroundBrush = BrushFromArgb(178, 7, 17, 28);
            PanelBorderBrush = BrushFromRgb(88, 170, 255);
            TitleBrush = BrushFromRgb(176, 219, 255);
            TextBrush = BrushFromRgb(245, 250, 255);
            MutedBrush = BrushFromRgb(132, 185, 232);
            AlertBrush = BrushFromRgb(255, 96, 83);
            IconBackgroundBrush = BrushFromArgb(116, 16, 36, 58);
            OnlineBrush = BrushFromRgb(135, 255, 180);
            OfflineBrush = BrushFromRgb(255, 104, 94);
            SetCrosshairBrushes(176, 219, 255, 255, 96, 83);
            return;
        }

        if (theme == OverlayVisualTheme.Aopoa)
        {
            PanelBackgroundBrush = BrushFromArgb(182, 4, 28, 30);
            PanelBorderBrush = BrushFromRgb(77, 255, 225);
            TitleBrush = BrushFromRgb(126, 255, 237);
            TextBrush = BrushFromRgb(230, 255, 250);
            MutedBrush = BrushFromRgb(116, 211, 198);
            AlertBrush = BrushFromRgb(171, 255, 67);
            IconBackgroundBrush = BrushFromArgb(122, 0, 58, 62);
            OnlineBrush = BrushFromRgb(156, 255, 77);
            OfflineBrush = BrushFromRgb(255, 72, 64);
            SetCrosshairBrushes(126, 255, 237, 171, 255, 67);
            return;
        }

        if (theme == OverlayVisualTheme.Esperia)
        {
            PanelBackgroundBrush = BrushFromArgb(184, 30, 6, 20);
            PanelBorderBrush = BrushFromRgb(255, 60, 78);
            TitleBrush = BrushFromRgb(255, 92, 112);
            TextBrush = BrushFromRgb(255, 228, 236);
            MutedBrush = BrushFromRgb(211, 125, 162);
            AlertBrush = BrushFromRgb(168, 77, 255);
            IconBackgroundBrush = BrushFromArgb(126, 70, 8, 34);
            OnlineBrush = BrushFromRgb(255, 108, 128);
            OfflineBrush = BrushFromRgb(152, 74, 255);
            SetCrosshairBrushes(255, 92, 112, 168, 77, 255);
            return;
        }

        if (theme == OverlayVisualTheme.Gatac)
        {
            PanelBackgroundBrush = BrushFromArgb(184, 24, 10, 32);
            PanelBorderBrush = BrushFromRgb(255, 176, 210);
            TitleBrush = BrushFromRgb(255, 205, 230);
            TextBrush = BrushFromRgb(255, 238, 246);
            MutedBrush = BrushFromRgb(203, 147, 221);
            AlertBrush = BrushFromRgb(255, 122, 76);
            IconBackgroundBrush = BrushFromArgb(124, 54, 18, 64);
            OnlineBrush = BrushFromRgb(255, 190, 230);
            OfflineBrush = BrushFromRgb(255, 117, 76);
            SetCrosshairBrushes(255, 205, 230, 255, 122, 76);
            return;
        }

        PanelBackgroundBrush = BrushFromArgb(176, 5, 10, 17);
        PanelBorderBrush = BrushFromRgb(69, 174, 255);
        TitleBrush = BrushFromRgb(83, 190, 255);
        TextBrush = BrushFromRgb(235, 247, 255);
        MutedBrush = BrushFromRgb(142, 187, 220);
        AlertBrush = BrushFromRgb(255, 240, 0);
        IconBackgroundBrush = BrushFromRgb(4, 16, 28);
        OnlineBrush = BrushFromRgb(121, 255, 158);
        OfflineBrush = BrushFromRgb(255, 105, 105);
        SetCrosshairBrushes(235, 247, 255, 255, 240, 0);
    }

    private void SetCrosshairBrushes(byte red, byte green, byte blue, byte alertRed, byte alertGreen, byte alertBlue)
    {
        CrosshairBrush = BrushFromArgb(215, red, green, blue);
        CrosshairAlertBrush = BrushFromArgb(225, alertRed, alertGreen, alertBlue);
    }

    private static SolidColorBrush BrushFromRgb(byte red, byte green, byte blue)
    {
        var brush = new SolidColorBrush(Color.FromRgb(red, green, blue));
        brush.Freeze();
        return brush;
    }

    private static SolidColorBrush BrushFromArgb(byte alpha, byte red, byte green, byte blue)
    {
        var brush = new SolidColorBrush(Color.FromArgb(alpha, red, green, blue));
        brush.Freeze();
        return brush;
    }

    private static bool TryParseHexColor(string? value, out Color color)
    {
        color = default;
        var text = value?.Trim();
        if (string.IsNullOrWhiteSpace(text))
        {
            return false;
        }

        if (text.StartsWith('#'))
        {
            text = text[1..];
        }

        if (text.Length == 3)
        {
            text = string.Concat(text.Select(ch => $"{ch}{ch}"));
        }

        if (text.Length == 6 &&
            byte.TryParse(text[..2], NumberStyles.HexNumber, CultureInfo.InvariantCulture, out var red) &&
            byte.TryParse(text.Substring(2, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture, out var green) &&
            byte.TryParse(text.Substring(4, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture, out var blue))
        {
            color = Color.FromRgb(red, green, blue);
            return true;
        }

        return false;
    }

    private void RefreshSquads(
        IEnumerable<PlayerRow> players,
        OverlayDisplaySettings settings,
        bool zh,
        bool hasFleet,
        PlayerPresenceKind localPresence,
        string localShard,
        OverlaySceneContext sceneContext)
    {
        Squads.Clear();
        CompactSquads.Clear();
        var playerRows = players.ToArray();
        var overview = OverlayOverviewProjection.Project(
            playerRows,
            sceneContext,
            hasFleet,
            localPresence,
            localShard,
            zh ? "zh" : "en");
        SquadsTitle = overview.Title;
        SquadStatusPrimaryName = overview.Primary;
        SquadStatusSummary = overview.Summary;
        SquadStatusServerSummary = overview.ServerSummary;
        SquadStatusFocusLine = overview.Focus;
        SquadStatusSecondaryLine = overview.Secondary;
        OverviewLocationPlaceholder = overview.LocationPlaceholder;
        OverviewLocationPlaceholderMetric = overview.LocationPlaceholderMetric;
        SquadStatusBrush = overview.StatusBrush;
        FleetOverviewVisibility = Visibility.Visible;
        FleetOverviewFocusVisibility = !string.IsNullOrWhiteSpace(overview.Focus)
            ? Visibility.Visible
            : Visibility.Collapsed;
        OverviewLocationPlaceholderVisibility = overview.TopLocations.Count == 0 &&
                                                !string.IsNullOrWhiteSpace(overview.LocationPlaceholder)
            ? Visibility.Visible
            : Visibility.Collapsed;
        PartyOverviewVisibility = Visibility.Collapsed;
        OverviewTopLocations = overview.TopLocations;
        ApplyOverviewPanelLayout(
            settings.SquadStatusDisplayMode,
            _overviewPanelWidth,
            _overviewPanelHeight);
    }

    private static string FormatFleetOnlineSummary(IReadOnlyCollection<PlayerRow> players, bool zh)
    {
        var online = players.Count(IsGamePresence);
        return zh
            ? $"游戏中 {online.ToString(CultureInfo.InvariantCulture)} / {players.Count.ToString(CultureInfo.InvariantCulture)}"
            : $"In game {online.ToString(CultureInfo.InvariantCulture)} / {players.Count.ToString(CultureInfo.InvariantCulture)}";
    }

    private static string ResolveDominantServerSummary(IReadOnlyCollection<PlayerRow> players, string? localShard, bool zh)
    {
        var onlinePlayers = players
            .Where(IsGamePresence)
            .ToArray();
        if (onlinePlayers.Length == 0)
        {
            return zh ? "无人处于游戏中" : "No one in game";
        }

        var primary = ResolveDominantServerGroup(players, localShard);
        if (primary is null)
        {
            return zh ? "服务器待确认" : "Server pending";
        }

        return zh
            ? $"{primary.Value.Region} · {primary.Value.Count.ToString(CultureInfo.InvariantCulture)}人"
            : $"{primary.Value.Region} · {primary.Value.Count.ToString(CultureInfo.InvariantCulture)}";
    }

    private static string? ResolveDominantServerRegion(IReadOnlyCollection<PlayerRow> players, string? localShard)
    {
        return ResolveDominantServerGroup(players, localShard)?.Region;
    }

    private static (string Region, int Count)? ResolveDominantServerGroup(IReadOnlyCollection<PlayerRow> players, string? localShard)
    {
        var onlinePlayers = players
            .Where(IsGamePresence)
            .ToArray();
        var groups = onlinePlayers
            .Select(player => TryGetOverlayPlayerServerRegion(player, localShard))
            .Where(region => !string.IsNullOrWhiteSpace(region))
            .GroupBy(region => region!, StringComparer.OrdinalIgnoreCase)
            .Select(group => new
            {
                Region = group.First()!,
                Count = group.Count()
            })
            .OrderByDescending(group => group.Count)
            .ThenBy(group => group.Region, StringComparer.CurrentCulture)
            .ToArray();

        if (groups.Length == 0)
        {
            return null;
        }

        var primary = groups[0];
        return (primary.Region, primary.Count);
    }

    private static string FormatSameServerLine(IReadOnlyCollection<PlayerRow> players, string? localShard, bool zh)
    {
        if (string.IsNullOrWhiteSpace(localShard))
        {
            return zh ? "与你同服务器 未进入服务器" : "Same server unavailable";
        }

        var sameServerCount = players.Count(player =>
            !player.IsSelf &&
            IsGamePresence(player) &&
            IsPlayerOnLocalServer(player, localShard));
        return zh
            ? $"与你同服务器 {sameServerCount.ToString(CultureInfo.InvariantCulture)} 人"
            : $"Same server {sameServerCount.ToString(CultureInfo.InvariantCulture)}";
    }

    private static bool IsPlayerOnLocalServer(PlayerRow player, string? localShard)
    {
        if (player.IsSelf)
        {
            return true;
        }

        return IsSameOverlayShard(player.ServerShard, localShard) ||
               ContainsOverlayShard(player.RawLocation, localShard) ||
               ContainsOverlayShard(player.Location, localShard);
    }

    private static bool IsSameOverlayShard(string? playerShard, string? localShard)
    {
        return !string.IsNullOrWhiteSpace(playerShard) &&
               !string.IsNullOrWhiteSpace(localShard) &&
               playerShard.Equals(localShard, StringComparison.OrdinalIgnoreCase);
    }

    private static string? TryGetOverlayPlayerServerRegion(PlayerRow player, string? localShard)
    {
        var localRegion = NormalizeOverlayServerRegion(MapOverlayGameServerRegion(localShard));
        if (player.IsSelf && !string.IsNullOrWhiteSpace(localRegion))
        {
            return localRegion;
        }

        if ((IsSameOverlayShard(player.ServerShard, localShard) ||
             ContainsOverlayShard(player.RawLocation, localShard) ||
             ContainsOverlayShard(player.Location, localShard)) &&
            !string.IsNullOrWhiteSpace(localRegion))
        {
            return localRegion;
        }

        var syncedRegion = NormalizeOverlayServerRegion(player.ServerRegion);
        if (!string.IsNullOrWhiteSpace(syncedRegion))
        {
            return syncedRegion;
        }

        if (!string.IsNullOrWhiteSpace(player.ServerShard))
        {
            return NormalizeOverlayServerRegion(MapOverlayGameServerRegion(player.ServerShard));
        }

        return TryExtractOverlayServerRegion(player.RawLocation) ??
               TryExtractOverlayServerRegion(player.Location);
    }

    private static bool ContainsOverlayShard(string? value, string? localShard)
    {
        return !string.IsNullOrWhiteSpace(value) &&
               !string.IsNullOrWhiteSpace(localShard) &&
               value.Contains(localShard, StringComparison.OrdinalIgnoreCase);
    }

    private static string? TryExtractOverlayServerRegion(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        var text = value.Trim();
        if (text.Equals("Unknown", StringComparison.OrdinalIgnoreCase) ||
            text.Equals("未知", StringComparison.OrdinalIgnoreCase) ||
            text.Equals("等待确认", StringComparison.OrdinalIgnoreCase) ||
            text.Equals("仅游戏中显示", StringComparison.OrdinalIgnoreCase) ||
            text.Equals("未连接", StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        var normalized = text.ToLowerInvariant();
        if (text.Contains("美服", StringComparison.OrdinalIgnoreCase) ||
            normalized.Contains("us east") ||
            normalized.Contains("us west") ||
            normalized.Contains("usa"))
        {
            return "美服";
        }

        if (text.Contains("欧服", StringComparison.OrdinalIgnoreCase) ||
            normalized.Contains("europe") ||
            normalized.Contains(" eu "))
        {
            return "欧服";
        }

        if (text.Contains("澳服", StringComparison.OrdinalIgnoreCase) ||
            normalized.Contains("australia") ||
            normalized.Contains("oceania"))
        {
            return "澳服";
        }

        if (text.Contains("亚服", StringComparison.OrdinalIgnoreCase) ||
            normalized.Contains("asia") ||
            normalized.Contains("singapore") ||
            normalized.Contains("hong kong") ||
            normalized.Contains("japan"))
        {
            return "亚服";
        }

        return normalized.Contains("pub_") ||
               normalized.Contains("shard") ||
               normalized.Contains("server")
            ? NormalizeOverlayServerRegion(MapOverlayGameServerRegion(normalized))
            : null;
    }

    private static string? NormalizeOverlayServerRegion(string? region)
    {
        return string.IsNullOrWhiteSpace(region) ||
               region.Equals("未知", StringComparison.OrdinalIgnoreCase)
            ? null
            : region.Trim();
    }

    private static string MapOverlayGameServerRegion(string? shard)
    {
        if (string.IsNullOrWhiteSpace(shard))
        {
            return "未知";
        }

        var normalized = shard.ToLowerInvariant();
        if (normalized.Contains("use") ||
            normalized.Contains("usw") ||
            normalized.Contains("_us") ||
            normalized.Contains("pub_us"))
        {
            return "美服";
        }

        if (normalized.Contains("eu"))
        {
            return "欧服";
        }

        if (normalized.Contains("aus") ||
            normalized.Contains("_au") ||
            normalized.Contains("oce"))
        {
            return "澳服";
        }

        if (normalized.Contains("asia") ||
            normalized.Contains("apse") ||
            normalized.Contains("_ap") ||
            normalized.Contains("sg") ||
            normalized.Contains("jp") ||
            normalized.Contains("hk"))
        {
            return "亚服";
        }

        return "未知";
    }

    private void OnChanged(string propertyName)
    {
        PropertyChanged?.Invoke(this, new System.ComponentModel.PropertyChangedEventArgs(propertyName));
    }

    private void SetProperty<T>(ref T field, T value, [CallerMemberName] string propertyName = "")
    {
        if (EqualityComparer<T>.Default.Equals(field, value))
        {
            return;
        }

        field = value;
        OnChanged(propertyName);
    }

    private static string FormatMemberName(PlayerRow player, OverlayMemberNameMode mode)
    {
        var callsign = string.IsNullOrWhiteSpace(player.Callsign) ? player.Name : player.Callsign;
        return mode switch
        {
            OverlayMemberNameMode.CallsignOnly => callsign,
            OverlayMemberNameMode.GameNameOnly => player.Name,
            _ => callsign.Equals(player.Name, StringComparison.OrdinalIgnoreCase)
                ? player.Name
                : $"{callsign} ({player.Name})"
        };
    }

}

public sealed record OverlaySquadRow(
    string Name,
    string Icon,
    string DetailLine,
    string SummaryLine,
    System.Windows.Media.Brush StatusBrush,
    string? EmblemPath,
    Visibility IconVisibility,
    Visibility IconTextVisibility,
    bool IsPartyRoomIcon = false)
{
    public Visibility StandardIconVisibility =>
        IconVisibility == Visibility.Visible && !IsPartyRoomIcon
            ? Visibility.Visible
            : Visibility.Collapsed;

    public Visibility PartyRoomIconVisibility =>
        IconVisibility == Visibility.Visible && IsPartyRoomIcon
            ? Visibility.Visible
            : Visibility.Collapsed;

    public Visibility EmblemVisibility =>
        StandardIconVisibility == Visibility.Visible && !string.IsNullOrWhiteSpace(EmblemPath)
            ? Visibility.Visible
            : Visibility.Collapsed;
}

public sealed record OverlayMemberRow(
    string DisplayName,
    string Status,
    string Ship,
    string Location,
    System.Windows.Media.Brush StatusBrush);

internal enum OverlayLocationMergePhase
{
    None,
    Provisional,
    Confirmed
}

public sealed class OverlayEventNotificationRow : System.ComponentModel.INotifyPropertyChanged
{
    private const double EnterDurationMs = 430;
    private const double ExitDurationMs = 320;

    private OverlayEventNotificationMotion _motion = OverlayEventNotificationMotion.None;
    private DateTimeOffset _motionStartedAt = DateTimeOffset.MinValue;
    private double _motionStartOffsetX;
    private double _motionEndOffsetX;
    private double _motionStartOpacity = 1;
    private double _motionEndOpacity = 1;
    private double _slideOffsetX;
    private double _rowOpacity = 1;
    private double _motionProgress = 1;
    private DateTimeOffset _barrageStartedAt = DateTimeOffset.MinValue;
    private TimeSpan _barrageDuration = TimeSpan.Zero;
    private int _barrageLane = -1;
    private bool _barrageActive;
    private bool _removeImmediately;
    private string _title;
    private string _detail;
    private string _timestamp;
    private System.Windows.Media.Brush _accentBrush;

    public OverlayEventNotificationRow(
        string title,
        string detail,
        string timestamp,
        System.Windows.Media.Brush accentBrush,
        DateTimeOffset expiresAt,
        OverlayEventNotificationTypes eventType)
    {
        _title = title;
        _detail = detail;
        _timestamp = timestamp;
        _accentBrush = accentBrush;
        ExpiresAt = expiresAt;
        EventType = eventType;
    }

    public event System.ComponentModel.PropertyChangedEventHandler? PropertyChanged;

    public string Title => _title;

    public string Detail => _detail;

    public string Timestamp => _timestamp;

    public System.Windows.Media.Brush AccentBrush => _accentBrush;

    public OverlayEventNotificationTypes EventType { get; }

    public DateTimeOffset ExpiresAt { get; set; }

    internal string? MergeKey { get; private set; }

    internal OverlayLocationMergePhase MergePhase { get; private set; }

    internal DateTimeOffset MergeUpdatedAt { get; private set; }

    internal void ConfigureMerge(
        string? mergeKey,
        OverlayLocationMergePhase mergePhase,
        DateTimeOffset updatedAt)
    {
        MergeKey = mergeKey;
        MergePhase = mergePhase;
        MergeUpdatedAt = updatedAt;
    }

    internal void MergeContent(
        string title,
        string detail,
        string timestamp,
        System.Windows.Media.Brush accentBrush,
        OverlayLocationMergePhase mergePhase,
        DateTimeOffset updatedAt,
        DateTimeOffset expiresAt)
    {
        _title = title;
        _detail = detail;
        _timestamp = timestamp;
        _accentBrush = accentBrush;
        MergePhase = mergePhase;
        MergeUpdatedAt = updatedAt;
        ExpiresAt = expiresAt;
        OnChanged(nameof(Title));
        OnChanged(nameof(Detail));
        OnChanged(nameof(Timestamp));
        OnChanged(nameof(AccentBrush));
    }

    public bool IsExiting => _motion == OverlayEventNotificationMotion.Exiting;

    public bool IsEntering => _motion == OverlayEventNotificationMotion.Entering;

    public bool IsAnimating => _motion != OverlayEventNotificationMotion.None || _barrageActive;

    public bool IsBarrageActive => _barrageActive;

    public DateTimeOffset BarrageStartedAtUtc => _barrageStartedAt;

    public double BarrageDurationSeconds => _barrageDuration.TotalSeconds;

    public int BarrageLane
    {
        get => _barrageLane;
        private set
        {
            if (_barrageLane == value)
            {
                return;
            }

            _barrageLane = value;
            OnChanged(nameof(BarrageLane));
        }
    }

    public double MotionProgress
    {
        get => _motionProgress;
        private set => SetProperty(ref _motionProgress, value);
    }

    public double SlideOffsetX
    {
        get => _slideOffsetX;
        private set => SetProperty(ref _slideOffsetX, value);
    }

    public double RowOpacity
    {
        get => _rowOpacity;
        private set => SetProperty(ref _rowOpacity, value);
    }

    public void BeginEnter(DateTimeOffset now, double offsetX)
    {
        StartMotion(OverlayEventNotificationMotion.Entering, now, offsetX, 0, 0, 1);
    }

    public void BeginExit(DateTimeOffset now, double offsetX)
    {
        if (_motion == OverlayEventNotificationMotion.Exiting)
        {
            return;
        }

        StartMotion(OverlayEventNotificationMotion.Exiting, now, SlideOffsetX, offsetX, RowOpacity, 0);
    }

    public void SetBarrageLane(int lane)
    {
        BarrageLane = Math.Max(0, lane);
        _barrageActive = false;
        OnChanged(nameof(IsBarrageActive));
        OnChanged(nameof(IsAnimating));
    }

    public void BeginBarrage(DateTimeOffset now, double durationSeconds, int lane)
    {
        _motion = OverlayEventNotificationMotion.None;
        _removeImmediately = false;
        _barrageStartedAt = now;
        _barrageDuration = TimeSpan.FromSeconds(Math.Clamp(durationSeconds, 2, 30));
        _barrageActive = true;
        BarrageLane = Math.Max(0, lane);
        SlideOffsetX = 0;
        RowOpacity = 1;
        OnChanged(nameof(IsBarrageActive));
        OnChanged(nameof(IsAnimating));
    }

    public bool AdvanceBarrage(DateTimeOffset now)
    {
        if (!_barrageActive)
        {
            return false;
        }

        if (now - _barrageStartedAt < _barrageDuration)
        {
            return false;
        }

        _barrageActive = false;
        OnChanged(nameof(IsBarrageActive));
        OnChanged(nameof(IsAnimating));
        return true;
    }

    public bool AdvanceAnimation(DateTimeOffset now, double scale)
    {
        if (_removeImmediately)
        {
            return true;
        }

        if (_motion == OverlayEventNotificationMotion.None)
        {
            return false;
        }

        var durationMs = (_motion == OverlayEventNotificationMotion.Exiting ? ExitDurationMs : EnterDurationMs) *
                         Math.Clamp(scale, 0.35, 2.0);
        var progress = durationMs <= 1
            ? 1
            : Math.Clamp((now - _motionStartedAt).TotalMilliseconds / durationMs, 0, 1);
        var eased = EaseOutCubic(progress);
        MotionProgress = progress;
        SlideOffsetX = Lerp(_motionStartOffsetX, _motionEndOffsetX, eased);
        RowOpacity = Lerp(_motionStartOpacity, _motionEndOpacity, eased);

        if (progress < 1)
        {
            return false;
        }

        if (_motion == OverlayEventNotificationMotion.Exiting)
        {
            return true;
        }

        _motion = OverlayEventNotificationMotion.None;
        SlideOffsetX = 0;
        RowOpacity = 1;
        MotionProgress = 1;
        OnChanged(nameof(IsEntering));
        OnChanged(nameof(IsAnimating));
        return false;
    }

    public void MarkForImmediateRemoval()
    {
        _motion = OverlayEventNotificationMotion.Exiting;
        _barrageActive = false;
        _removeImmediately = true;
        MotionProgress = 1;
        OnChanged(nameof(IsExiting));
        OnChanged(nameof(IsEntering));
        OnChanged(nameof(IsAnimating));
    }

    public bool CompleteMotionImmediately()
    {
        if (_barrageActive)
        {
            _barrageActive = false;
            OnChanged(nameof(IsBarrageActive));
            OnChanged(nameof(IsAnimating));
            return false;
        }

        if (_motion == OverlayEventNotificationMotion.Exiting || _removeImmediately)
        {
            return true;
        }

        _motion = OverlayEventNotificationMotion.None;
        SlideOffsetX = 0;
        RowOpacity = 1;
        MotionProgress = 1;
        OnChanged(nameof(IsExiting));
        OnChanged(nameof(IsEntering));
        OnChanged(nameof(IsAnimating));
        return false;
    }

    private void StartMotion(
        OverlayEventNotificationMotion motion,
        DateTimeOffset now,
        double startOffsetX,
        double endOffsetX,
        double startOpacity,
        double endOpacity)
    {
        _motion = motion;
        _removeImmediately = false;
        _motionStartedAt = now;
        _motionStartOffsetX = startOffsetX;
        _motionEndOffsetX = endOffsetX;
        _motionStartOpacity = startOpacity;
        _motionEndOpacity = endOpacity;
        SlideOffsetX = startOffsetX;
        RowOpacity = startOpacity;
        MotionProgress = 0;
        OnChanged(nameof(IsExiting));
        OnChanged(nameof(IsEntering));
        OnChanged(nameof(IsAnimating));
    }

    private static double EaseOutCubic(double value)
    {
        var inverse = 1 - Math.Clamp(value, 0, 1);
        return 1 - inverse * inverse * inverse;
    }

    private static double Lerp(double from, double to, double progress)
    {
        return from + (to - from) * progress;
    }

    private void SetProperty(ref double field, double value, [CallerMemberName] string? propertyName = null)
    {
        if (Math.Abs(field - value) < 0.01)
        {
            return;
        }

        field = value;
        OnChanged(propertyName);
    }

    private void OnChanged([CallerMemberName] string? propertyName = null)
    {
        PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
    }

    private enum OverlayEventNotificationMotion
    {
        None,
        Entering,
        Exiting
    }
}
