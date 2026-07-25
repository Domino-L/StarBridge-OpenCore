using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using Button = System.Windows.Controls.Button;
using Point = System.Windows.Point;

namespace StarBridge.Desktop;

public enum UiMotionRevealDirection
{
    FromBelow,
    FromLeft,
    FromRight
}

public static class UiMotion
{
    private static readonly Duration FastDuration = UiMotionProfile.FastDuration;
    private static readonly Duration NavigationDuration = UiMotionProfile.NavigationDuration;
    private static readonly Duration ContentDuration = UiMotionProfile.ContentDuration;
    private static readonly Duration ModalDuration = UiMotionProfile.ModalDuration;
    private static readonly Duration SignalDuration = UiMotionProfile.SignalDuration;
    private static readonly KeySpline EnterSpline = new(0.16, 1, 0.3, 1);
    private static readonly KeySpline ExitSpline = new(0.4, 0, 1, 1);
    private static readonly KeySpline RouteSpline = new(0.22, 1, 0.36, 1);

    private static readonly DependencyProperty MotionTransformGroupProperty = DependencyProperty.RegisterAttached(
        "MotionTransformGroup",
        typeof(TransformGroup),
        typeof(UiMotion),
        new PropertyMetadata(null));

    private static readonly DependencyProperty MotionTranslateProperty = DependencyProperty.RegisterAttached(
        "MotionTranslate",
        typeof(TranslateTransform),
        typeof(UiMotion),
        new PropertyMetadata(null));

    private static readonly DependencyProperty RouteTargetXProperty = DependencyProperty.RegisterAttached(
        "RouteTargetX",
        typeof(double),
        typeof(UiMotion),
        new PropertyMetadata(double.NaN));

    public static bool IsEnabled =>
        SystemParameters.ClientAreaAnimation && (RenderCapability.Tier >> 16) > 0;

    public static void InitializeGlobalInteractions()
    {
        // Button chrome already provides immediate hover/pressed feedback.
        // A global scale animation made dense toolbars and small controls feel
        // unstable, so high-frequency interactions intentionally stay fixed.
    }

    public static void ShowModal(Border? overlay, FrameworkElement? card)
    {
        if (overlay is null)
        {
            return;
        }

        overlay.Visibility = Visibility.Visible;
        if (card is not null)
        {
            card.Visibility = Visibility.Visible;
        }

        overlay.BeginAnimation(UIElement.OpacityProperty, null);
        overlay.Opacity = 1;
        if (!IsEnabled)
        {
            if (card is not null) card.Opacity = 1;
            return;
        }

        if (card is null)
        {
            return;
        }

        overlay.BeginAnimation(
            UIElement.OpacityProperty,
            CreateSplineAnimation(0.82, 1, FastDuration, EnterSpline));
        card.RenderTransformOrigin = new Point(0.5, 0.5);
        var translate = EnsureTranslate(card);
        card.BeginAnimation(UIElement.OpacityProperty, null);
        translate.BeginAnimation(TranslateTransform.YProperty, null);
        card.Opacity = 1;
        translate.Y = 0;
        card.BeginAnimation(
            UIElement.OpacityProperty,
            CreateSplineAnimation(UiMotionProfile.ModalStartOpacity, 1, ModalDuration, EnterSpline));
        translate.BeginAnimation(
            TranslateTransform.YProperty,
            CreateSplineAnimation(UiMotionProfile.ModalStartOffset, 0, ModalDuration, EnterSpline));
    }

    public static void HideModal(Border? overlay, FrameworkElement? card = null)
    {
        if (overlay is null || overlay.Visibility != Visibility.Visible)
        {
            return;
        }

        if (!IsEnabled)
        {
            overlay.Visibility = Visibility.Collapsed;
            if (card is not null) card.Visibility = Visibility.Collapsed;
            return;
        }

        if (card is null)
        {
            overlay.Visibility = Visibility.Collapsed;
            return;
        }

        var translate = EnsureTranslate(card);
        var animation = CreateSplineAnimation(1, 0, FastDuration, ExitSpline);
        animation.Completed += (_, _) =>
        {
            overlay.Visibility = Visibility.Collapsed;
            card.Visibility = Visibility.Collapsed;
            card.BeginAnimation(UIElement.OpacityProperty, null);
            translate.BeginAnimation(TranslateTransform.YProperty, null);
            card.Opacity = 1;
            translate.Y = 0;
        };
        card.BeginAnimation(UIElement.OpacityProperty, animation);
        translate.BeginAnimation(
            TranslateTransform.YProperty,
            CreateSplineAnimation(0, UiMotionProfile.ModalExitOffset, FastDuration, ExitSpline));
    }

    public static void ShowStatus(FrameworkElement? element)
    {
        if (element is null)
        {
            return;
        }

        var wasVisible = element.Visibility == Visibility.Visible;
        element.Visibility = Visibility.Visible;
        if (wasVisible)
        {
            return;
        }
        if (!IsEnabled)
        {
            element.Opacity = 1;
            return;
        }

        element.Opacity = 1;
        element.BeginAnimation(
            UIElement.OpacityProperty,
            CreateFocusLockAnimation());
    }

    public static void HideStatus(FrameworkElement? element)
    {
        if (element is null || element.Visibility != Visibility.Visible)
        {
            return;
        }

        if (!IsEnabled)
        {
            element.Visibility = Visibility.Collapsed;
            element.Opacity = 1;
            return;
        }

        var animation = CreateSplineAnimation(1, 0, FastDuration, ExitSpline);
        animation.Completed += (_, _) =>
        {
            element.Visibility = Visibility.Collapsed;
            element.BeginAnimation(UIElement.OpacityProperty, null);
            element.Opacity = 1;
        };
        element.BeginAnimation(UIElement.OpacityProperty, animation);
    }

    public static void RevealContent(
        FrameworkElement? element,
        UiMotionRevealDirection direction = UiMotionRevealDirection.FromBelow)
    {
        if (element is null || element.Visibility != Visibility.Visible)
        {
            return;
        }

        element.BeginAnimation(UIElement.OpacityProperty, null);
        element.Opacity = 1;
        if (!IsEnabled)
        {
            return;
        }

        element.BeginAnimation(
            UIElement.OpacityProperty,
            CreateSplineAnimation(
                UiMotionProfile.ContentStartOpacity,
                1,
                ContentDuration,
                EnterSpline),
            HandoffBehavior.SnapshotAndReplace);
    }

    public static void ApplyNavigationSelection(
        IEnumerable<Button?> buttons,
        Button? activeButton)
    {
        var availableButtons = buttons.Where(button => button is not null).Cast<Button>().ToArray();
        var previousButton = availableButtons.FirstOrDefault(button =>
            string.Equals(button.Tag as string, "Active", StringComparison.Ordinal));
        var selectionChanged = activeButton is not null &&
                               !ReferenceEquals(previousButton, activeButton);
        var previousIndex = Array.IndexOf(availableButtons, previousButton);
        var activeIndex = Array.IndexOf(availableButtons, activeButton);
        var movesForward = previousIndex < 0 || activeIndex >= previousIndex;

        foreach (var button in availableButtons)
        {
            button.Tag = ReferenceEquals(button, activeButton) ? "Active" : null;
        }

        if (!selectionChanged || activeButton is null || !IsEnabled)
        {
            return;
        }

        activeButton.Dispatcher.BeginInvoke(DispatcherPriority.Loaded, new Action(() =>
        {
            if (!activeButton.IsVisible)
            {
                return;
            }

            activeButton.ApplyTemplate();
            if (FindNavigationMarker(activeButton) is { } marker)
            {
                AnimateNavigationMarker(marker, movesForward);
            }
        }));
    }

    public static void MoveRouteSignal(
        FrameworkElement? host,
        FrameworkElement? signal,
        FrameworkElement? target)
    {
        if (host is null || signal is null)
        {
            return;
        }

        if (target is null)
        {
            signal.SetValue(RouteTargetXProperty, double.NaN);
            if (!IsEnabled || signal.Visibility != Visibility.Visible)
            {
                signal.Visibility = Visibility.Collapsed;
                signal.Opacity = 1;
                return;
            }

            var hide = CreateSplineAnimation(signal.Opacity, 0, FastDuration, ExitSpline);
            hide.Completed += (_, _) =>
            {
                signal.Visibility = Visibility.Collapsed;
                signal.BeginAnimation(UIElement.OpacityProperty, null);
                signal.Opacity = 1;
            };
            signal.BeginAnimation(UIElement.OpacityProperty, hide, HandoffBehavior.SnapshotAndReplace);
            return;
        }

        host.Dispatcher.BeginInvoke(DispatcherPriority.Loaded, new Action(() =>
        {
            if (!host.IsVisible || !target.IsVisible || target.ActualWidth <= 0)
            {
                return;
            }

            var targetOrigin = target.TransformToAncestor(host).Transform(new Point(0, 0));
            var targetWidth = Math.Max(24, target.ActualWidth - 28);
            var targetX = targetOrigin.X + ((target.ActualWidth - targetWidth) / 2);
            var previousTargetX = (double)signal.GetValue(RouteTargetXProperty);
            var translate = EnsureTranslate(signal);
            var currentX = double.IsNaN(previousTargetX) ? targetX : translate.X;

            signal.Width = targetWidth;
            signal.Visibility = Visibility.Visible;
            signal.Opacity = 1;
            signal.RenderTransformOrigin = new Point(0.5, 0.5);
            translate.BeginAnimation(TranslateTransform.XProperty, null);
            translate.X = targetX;
            signal.SetValue(RouteTargetXProperty, targetX);

            if (!IsEnabled)
            {
                return;
            }

            if (double.IsNaN(previousTargetX))
            {
                signal.BeginAnimation(
                    UIElement.OpacityProperty,
                    CreateSplineAnimation(0.45, 1, NavigationDuration, EnterSpline),
                    HandoffBehavior.SnapshotAndReplace);
                return;
            }

            translate.BeginAnimation(
                TranslateTransform.XProperty,
                CreateSplineAnimation(currentX, targetX, NavigationDuration, RouteSpline),
                HandoffBehavior.SnapshotAndReplace);
            signal.BeginAnimation(
                UIElement.OpacityProperty,
                CreateSignalLockAnimation(),
                HandoffBehavior.SnapshotAndReplace);
        }));
    }

    public static void SweepSignal(FrameworkElement? host, FrameworkElement? signal)
    {
        if (host is null || signal is null)
        {
            return;
        }

        if (!IsEnabled)
        {
            signal.Visibility = Visibility.Collapsed;
            return;
        }

        host.Dispatcher.BeginInvoke(DispatcherPriority.Loaded, new Action(() =>
        {
            if (!host.IsVisible || host.ActualWidth <= 0)
            {
                return;
            }

            var translate = EnsureTranslate(signal);
            var signalWidth = signal.ActualWidth > 0 ? signal.ActualWidth : Math.Max(signal.Width, 32);
            var startX = -signalWidth;
            signal.Visibility = Visibility.Visible;
            signal.Opacity = 0;
            translate.X = startX;
            signal.BeginAnimation(UIElement.OpacityProperty, null);
            translate.BeginAnimation(TranslateTransform.XProperty, null);

            var opacity = new DoubleAnimationUsingKeyFrames
            {
                Duration = SignalDuration,
                FillBehavior = FillBehavior.Stop
            };
            opacity.KeyFrames.Add(new DiscreteDoubleKeyFrame(0, KeyTime.FromPercent(0)));
            opacity.KeyFrames.Add(new SplineDoubleKeyFrame(0.9, KeyTime.FromPercent(0.14), EnterSpline));
            opacity.KeyFrames.Add(new LinearDoubleKeyFrame(0.72, KeyTime.FromPercent(0.72)));
            opacity.KeyFrames.Add(new SplineDoubleKeyFrame(0, KeyTime.FromPercent(1), ExitSpline));
            opacity.Completed += (_, _) =>
            {
                signal.Visibility = Visibility.Collapsed;
                signal.BeginAnimation(UIElement.OpacityProperty, null);
                translate.BeginAnimation(TranslateTransform.XProperty, null);
                signal.Opacity = 0;
                translate.X = startX;
            };

            signal.BeginAnimation(
                UIElement.OpacityProperty,
                opacity,
                HandoffBehavior.SnapshotAndReplace);
            translate.BeginAnimation(
                TranslateTransform.XProperty,
                CreateSplineAnimation(startX, host.ActualWidth + signalWidth, SignalDuration, RouteSpline),
                HandoffBehavior.SnapshotAndReplace);
        }));
    }

    private static void AnimateNavigationMarker(FrameworkElement marker, bool movesForward)
    {
        marker.RenderTransformOrigin = new Point(0.5, 0.5);
        var horizontal = marker.ActualWidth >= marker.ActualHeight;
        var direction = movesForward ? 1d : -1d;
        var translate = EnsureTranslate(marker);
        var travel = UiMotionProfile.NavigationMarkerTravel * direction;

        marker.BeginAnimation(UIElement.OpacityProperty, null);
        translate.BeginAnimation(TranslateTransform.XProperty, null);
        translate.BeginAnimation(TranslateTransform.YProperty, null);
        translate.X = 0;
        translate.Y = 0;
        marker.BeginAnimation(
            UIElement.OpacityProperty,
            CreateSplineAnimation(0.45, 1, NavigationDuration, EnterSpline),
            HandoffBehavior.SnapshotAndReplace);
        if (horizontal)
        {
            translate.BeginAnimation(
                TranslateTransform.XProperty,
                CreateSplineAnimation(-travel, 0, NavigationDuration, RouteSpline),
                HandoffBehavior.SnapshotAndReplace);
        }
        else
        {
            translate.BeginAnimation(
                TranslateTransform.YProperty,
                CreateSplineAnimation(-travel, 0, NavigationDuration, RouteSpline),
                HandoffBehavior.SnapshotAndReplace);
        }
    }

    private static DoubleAnimationUsingKeyFrames CreateSignalLockAnimation()
    {
        var animation = new DoubleAnimationUsingKeyFrames
        {
            Duration = NavigationDuration,
            FillBehavior = FillBehavior.Stop
        };
        animation.KeyFrames.Add(new DiscreteDoubleKeyFrame(0.78, KeyTime.FromPercent(0)));
        animation.KeyFrames.Add(new SplineDoubleKeyFrame(1, KeyTime.FromPercent(1), EnterSpline));
        return animation;
    }

    private static DoubleAnimationUsingKeyFrames CreateFocusLockAnimation()
    {
        var animation = new DoubleAnimationUsingKeyFrames
        {
            Duration = FastDuration,
            FillBehavior = FillBehavior.Stop
        };
        animation.KeyFrames.Add(new DiscreteDoubleKeyFrame(0.68, KeyTime.FromPercent(0)));
        animation.KeyFrames.Add(new SplineDoubleKeyFrame(1, KeyTime.FromPercent(1), EnterSpline));
        return animation;
    }

    private static DoubleAnimationUsingKeyFrames CreateSplineAnimation(
        double from,
        double to,
        Duration duration,
        KeySpline spline,
        FillBehavior fillBehavior = FillBehavior.Stop)
    {
        var animation = new DoubleAnimationUsingKeyFrames
        {
            Duration = duration,
            FillBehavior = fillBehavior
        };
        animation.KeyFrames.Add(new DiscreteDoubleKeyFrame(from, KeyTime.FromPercent(0)));
        animation.KeyFrames.Add(new SplineDoubleKeyFrame(to, KeyTime.FromPercent(1), spline));
        return animation;
    }

    private static TranslateTransform EnsureTranslate(UIElement element)
    {
        if (element.GetValue(MotionTranslateProperty) is TranslateTransform existing)
        {
            return existing;
        }

        var translate = new TranslateTransform();
        var group = EnsureMotionTransformGroup(element);
        group.Children.Add(translate);
        element.SetValue(MotionTranslateProperty, translate);
        return translate;
    }

    private static TransformGroup EnsureMotionTransformGroup(UIElement element)
    {
        if (element.GetValue(MotionTransformGroupProperty) is TransformGroup existing)
        {
            return existing;
        }

        var group = new TransformGroup();
        if (element.RenderTransform is { } original && original != Transform.Identity)
        {
            group.Children.Add(original);
        }

        element.RenderTransform = group;
        element.SetValue(MotionTransformGroupProperty, group);
        return group;
    }

    private static FrameworkElement? FindNavigationMarker(Button button)
    {
        foreach (var markerName in new[] { "ActiveLine", "Rail", "RouteLight", "TabEnergy" })
        {
            if (button.Template.FindName(markerName, button) is FrameworkElement marker)
            {
                return marker;
            }
        }

        return null;
    }

}
