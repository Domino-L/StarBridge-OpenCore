using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using Control = System.Windows.Controls.Control;

namespace StarBridge.Desktop.Controls;

internal static class BridgeLoadingMotionPolicy
{
    internal static TimeSpan ResolveCycleDuration(bool isActive, bool motionEnabled)
    {
        return isActive && motionEnabled
            ? global::StarBridge.Desktop.UiMotionProfile.StateLoadingCycleDuration
            : TimeSpan.Zero;
    }
}

[TemplatePart(Name = RotatingVisualPartName, Type = typeof(FrameworkElement))]
public sealed class BridgeLoadingIndicator : Control
{
    private const string RotatingVisualPartName = "PART_RotatingVisual";

    public static readonly DependencyProperty IsActiveProperty = DependencyProperty.Register(
        nameof(IsActive),
        typeof(bool),
        typeof(BridgeLoadingIndicator),
        new PropertyMetadata(false, OnIsActiveChanged));

    private FrameworkElement? _rotatingVisual;
    private RotateTransform? _ownedRotation;
#if DEBUG
    private bool? _acceptanceMotionEnabledOverride;
#endif

    static BridgeLoadingIndicator()
    {
        DefaultStyleKeyProperty.OverrideMetadata(
            typeof(BridgeLoadingIndicator),
            new FrameworkPropertyMetadata(typeof(BridgeLoadingIndicator)));
    }

    public BridgeLoadingIndicator()
    {
        Loaded += OnLoaded;
        Unloaded += OnUnloaded;
        IsVisibleChanged += OnIsVisibleChanged;
    }

    public bool IsActive
    {
        get => (bool)GetValue(IsActiveProperty);
        set => SetValue(IsActiveProperty, value);
    }

    public override void OnApplyTemplate()
    {
        StopMotion();
        base.OnApplyTemplate();
        _rotatingVisual = GetTemplateChild(RotatingVisualPartName) as FrameworkElement;
        RefreshMotion();
    }

    private static void OnIsActiveChanged(DependencyObject dependencyObject, DependencyPropertyChangedEventArgs args)
    {
        ((BridgeLoadingIndicator)dependencyObject).RefreshMotion();
    }

    private void RefreshMotion()
    {
        var rotation = EnsureOwnedRotation();
        if (rotation is null)
        {
            return;
        }

        rotation.BeginAnimation(RotateTransform.AngleProperty, null);
        rotation.Angle = 0;
        var cycle = BridgeLoadingMotionPolicy.ResolveCycleDuration(
            IsActive,
            IsLoaded && IsVisible && ResolveMotionEnabled());
        if (cycle == TimeSpan.Zero)
        {
            return;
        }

        var animation = new DoubleAnimation(0, 360, new Duration(cycle))
        {
            RepeatBehavior = RepeatBehavior.Forever
        };
        rotation.BeginAnimation(
            RotateTransform.AngleProperty,
            animation,
            HandoffBehavior.SnapshotAndReplace);
    }

    private void StopMotion()
    {
        var rotation = EnsureOwnedRotation();
        if (rotation is not null)
        {
            rotation.BeginAnimation(RotateTransform.AngleProperty, null);
            rotation.Angle = 0;
        }
    }

    private RotateTransform? EnsureOwnedRotation()
    {
        if (_rotatingVisual?.RenderTransform is not RotateTransform templateRotation)
        {
            _ownedRotation = null;
            return null;
        }

        if (_ownedRotation is not null && ReferenceEquals(templateRotation, _ownedRotation))
        {
            return _ownedRotation;
        }

        _ownedRotation = templateRotation.CloneCurrentValue();
        _rotatingVisual.RenderTransform = _ownedRotation;
        return _ownedRotation;
    }

    private bool ResolveMotionEnabled()
    {
#if DEBUG
        return _acceptanceMotionEnabledOverride ?? global::StarBridge.Desktop.UiMotion.IsEnabled;
#else
        return global::StarBridge.Desktop.UiMotion.IsEnabled;
#endif
    }

#if DEBUG
    internal void SetAcceptanceMotionEnabledOverride(bool? value)
    {
        _acceptanceMotionEnabledOverride = value;
        RefreshMotion();
    }
#endif

    private void OnLoaded(object sender, RoutedEventArgs args) => RefreshMotion();
    private void OnUnloaded(object sender, RoutedEventArgs args) => StopMotion();
    private void OnIsVisibleChanged(object sender, DependencyPropertyChangedEventArgs args) => RefreshMotion();
}
