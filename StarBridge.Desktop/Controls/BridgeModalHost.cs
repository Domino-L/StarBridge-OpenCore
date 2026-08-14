using System.Runtime.CompilerServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;

namespace StarBridge.Desktop.Controls;

public enum BridgeModalSize
{
    Confirm,
    Form,
    Detail
}

public sealed class BridgeModalHost : ContentControl
{
    private const double HorizontalSafeArea = 64;
    private const double VerticalSafeArea = 48;
    private static readonly ConditionalWeakTable<Window, ActiveModalSlot> ActiveModals = new();

    private FrameworkElement? _card;
    private System.Windows.Controls.Button? _closeButton;
    private IInputElement? _focusBeforeOpen;
    private bool _isClosing;

    public static readonly DependencyProperty TitleProperty = DependencyProperty.Register(
        nameof(Title),
        typeof(string),
        typeof(BridgeModalHost),
        new PropertyMetadata(string.Empty));

    public static readonly DependencyProperty DescriptionProperty = DependencyProperty.Register(
        nameof(Description),
        typeof(string),
        typeof(BridgeModalHost),
        new PropertyMetadata(string.Empty));

    public static readonly DependencyProperty FooterProperty = DependencyProperty.Register(
        nameof(Footer),
        typeof(object),
        typeof(BridgeModalHost),
        new PropertyMetadata(null));

    public static readonly DependencyProperty SizeProperty = DependencyProperty.Register(
        nameof(Size),
        typeof(BridgeModalSize),
        typeof(BridgeModalHost),
        new FrameworkPropertyMetadata(
            BridgeModalSize.Form,
            FrameworkPropertyMetadataOptions.AffectsMeasure,
            OnSizeChanged));

    private static readonly DependencyPropertyKey CardWidthPropertyKey = DependencyProperty.RegisterReadOnly(
        nameof(CardWidth),
        typeof(double),
        typeof(BridgeModalHost),
        new PropertyMetadata(660d));

    public static readonly DependencyProperty CardWidthProperty = CardWidthPropertyKey.DependencyProperty;

    private static readonly DependencyPropertyKey CardMaxHeightPropertyKey = DependencyProperty.RegisterReadOnly(
        nameof(CardMaxHeight),
        typeof(double),
        typeof(BridgeModalHost),
        new PropertyMetadata(720d));

    public static readonly DependencyProperty CardMaxHeightProperty = CardMaxHeightPropertyKey.DependencyProperty;

    public static readonly RoutedEvent DismissRequestedEvent = EventManager.RegisterRoutedEvent(
        nameof(DismissRequested),
        RoutingStrategy.Bubble,
        typeof(RoutedEventHandler),
        typeof(BridgeModalHost));

    static BridgeModalHost()
    {
        DefaultStyleKeyProperty.OverrideMetadata(
            typeof(BridgeModalHost),
            new FrameworkPropertyMetadata(typeof(BridgeModalHost)));
    }

    public BridgeModalHost()
    {
        Focusable = true;
        Visibility = Visibility.Collapsed;
        IsVisibleChanged += BridgeModalHost_IsVisibleChanged;
        SizeChanged += BridgeModalHost_SizeChanged;
        PreviewKeyDown += BridgeModalHost_PreviewKeyDown;
        PreviewMouseLeftButtonDown += BridgeModalHost_PreviewMouseLeftButtonDown;
        UpdateCardMetrics();
    }

    public string Title
    {
        get => (string)GetValue(TitleProperty);
        set => SetValue(TitleProperty, value);
    }

    public string Description
    {
        get => (string)GetValue(DescriptionProperty);
        set => SetValue(DescriptionProperty, value);
    }

    public object? Footer
    {
        get => GetValue(FooterProperty);
        set => SetValue(FooterProperty, value);
    }

    public BridgeModalSize Size
    {
        get => (BridgeModalSize)GetValue(SizeProperty);
        set => SetValue(SizeProperty, value);
    }

    public double CardWidth => (double)GetValue(CardWidthProperty);

    public double CardMaxHeight => (double)GetValue(CardMaxHeightProperty);

    public event RoutedEventHandler DismissRequested
    {
        add => AddHandler(DismissRequestedEvent, value);
        remove => RemoveHandler(DismissRequestedEvent, value);
    }

    public override void OnApplyTemplate()
    {
        if (_closeButton is not null)
        {
            _closeButton.Click -= CloseButton_Click;
        }

        base.OnApplyTemplate();
        _card = GetTemplateChild("PART_Card") as FrameworkElement;
        _closeButton = GetTemplateChild("PART_CloseButton") as System.Windows.Controls.Button;
        if (_closeButton is not null)
        {
            _closeButton.Click += CloseButton_Click;
        }
    }

    public void Show()
    {
        _isClosing = false;
        Visibility = Visibility.Visible;
    }

    public void Hide()
    {
        if (Visibility != Visibility.Visible || _isClosing)
        {
            return;
        }

        _isClosing = true;
        ApplyTemplate();
        UiMotion.HideModal(this, _card);
    }

    public void RequestDismiss()
    {
        var args = new RoutedEventArgs(DismissRequestedEvent, this);
        RaiseEvent(args);
        if (!args.Handled && Visibility == Visibility.Visible)
        {
            Hide();
        }
    }

    private static void OnSizeChanged(DependencyObject d, DependencyPropertyChangedEventArgs e) =>
        ((BridgeModalHost)d).UpdateCardMetrics();

    private void BridgeModalHost_SizeChanged(object sender, SizeChangedEventArgs e) => UpdateCardMetrics();

    private void UpdateCardMetrics()
    {
        var tierWidth = Size switch
        {
            BridgeModalSize.Confirm => 520d,
            BridgeModalSize.Detail => 960d,
            _ => 660d
        };
        var availableWidth = ActualWidth > 0 ? Math.Max(320, ActualWidth - HorizontalSafeArea) : tierWidth;
        var availableHeight = ActualHeight > 0 ? Math.Max(280, ActualHeight - VerticalSafeArea) : 720d;
        SetValue(CardWidthPropertyKey, Math.Min(tierWidth, availableWidth));
        SetValue(CardMaxHeightPropertyKey, Math.Min(720d, availableHeight));
    }

    private void BridgeModalHost_IsVisibleChanged(object sender, DependencyPropertyChangedEventArgs e)
    {
        if (Visibility == Visibility.Visible)
        {
            RegisterAsActiveModal();
            _focusBeforeOpen ??= Keyboard.FocusedElement;
            ApplyTemplate();
            UiMotion.ShowModal(this, _card);
            Dispatcher.BeginInvoke(
                DispatcherPriority.Input,
                new Action(MoveFocusIntoCard));
            return;
        }

        _isClosing = false;
        UnregisterActiveModal();
        RestoreFocus();
    }

    private void RegisterAsActiveModal()
    {
        var window = Window.GetWindow(this);
        if (window is null)
        {
            return;
        }

        var slot = ActiveModals.GetOrCreateValue(window);
        if (slot.Current is { } current &&
            !ReferenceEquals(current, this) &&
            current.Visibility == Visibility.Visible)
        {
            current.RequestDismiss();
            if (current.Visibility == Visibility.Visible)
            {
                current.Visibility = Visibility.Collapsed;
            }
        }

        slot.Current = this;
    }

    private void UnregisterActiveModal()
    {
        var window = Window.GetWindow(this);
        if (window is null || !ActiveModals.TryGetValue(window, out var slot))
        {
            return;
        }

        if (ReferenceEquals(slot.Current, this))
        {
            slot.Current = null;
        }
    }

    private void MoveFocusIntoCard()
    {
        if (Visibility != Visibility.Visible)
        {
            return;
        }

        FlattenInternalCorners(_card);
        Focus();
        MoveFocus(new TraversalRequest(FocusNavigationDirection.First));
    }

    private static void FlattenInternalCorners(DependencyObject? root)
    {
        if (root is null)
        {
            return;
        }

        var childCount = VisualTreeHelper.GetChildrenCount(root);
        for (var index = 0; index < childCount; index++)
        {
            var child = VisualTreeHelper.GetChild(root, index);
            if (child is System.Windows.Controls.Border border && child is not ChamferBorder)
            {
                border.CornerRadius = default;
            }

            FlattenInternalCorners(child);
        }
    }

    private void RestoreFocus()
    {
        var focus = _focusBeforeOpen;
        _focusBeforeOpen = null;
        if (focus is null)
        {
            return;
        }

        Dispatcher.BeginInvoke(
            DispatcherPriority.Input,
            new Action(() => Keyboard.Focus(focus)));
    }

    private void BridgeModalHost_PreviewKeyDown(object sender, System.Windows.Input.KeyEventArgs e)
    {
        if (e.Key != Key.Escape)
        {
            return;
        }

        e.Handled = true;
        RequestDismiss();
    }

    private void CloseButton_Click(object sender, RoutedEventArgs e)
    {
        e.Handled = true;
        RequestDismiss();
    }

    private void BridgeModalHost_PreviewMouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (_card is null || _card.IsMouseOver)
        {
            return;
        }

        e.Handled = true;
        RequestDismiss();
    }

    private sealed class ActiveModalSlot
    {
        public BridgeModalHost? Current { get; set; }
    }
}
