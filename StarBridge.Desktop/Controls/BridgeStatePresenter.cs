using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using Button = System.Windows.Controls.Button;
using Control = System.Windows.Controls.Control;

namespace StarBridge.Desktop.Controls;

public enum BridgeStateKind
{
    Loading,
    Empty,
    Error,
    AccessDenied,
    OfflineCache
}

internal sealed record BridgeStateDescriptor(
    string Icon,
    string Title,
    string Description,
    string ActionText);

internal static class BridgeStateCatalog
{
    internal static BridgeStateDescriptor Resolve(BridgeStateKind state) => state switch
    {
        BridgeStateKind.Loading => new(
            Icon: string.Empty,
            Title: "正在读取机库",
            Description: "通常需要几秒",
            ActionText: string.Empty),
        BridgeStateKind.Empty => new(
            Icon: "◇",
            Title: "还没有可加入的房间",
            Description: "创建一个，等待队友加入",
            ActionText: "创建房间"),
        BridgeStateKind.Error => new(
            Icon: "!",
            Title: "无法连接到服务器",
            Description: "检查网络后重试",
            ActionText: "重试"),
        BridgeStateKind.AccessDenied => new(
            Icon: "⌧",
            Title: "只有指挥官可以查看审核队列",
            Description: "如需权限，请联系舰队指挥官",
            ActionText: string.Empty),
        BridgeStateKind.OfflineCache => new(
            Icon: "◐",
            Title: "当前离线，显示的是本地缓存",
            Description: "恢复连接后会自动同步",
            ActionText: string.Empty),
        _ => throw new ArgumentOutOfRangeException(nameof(state), state, null)
    };
}

[TemplatePart(Name = ActionButtonPartName, Type = typeof(Button))]
public sealed class BridgeStatePresenter : Control
{
    private const string ActionButtonPartName = "PART_ActionButton";

    private static readonly DependencyPropertyKey DisplayIconPropertyKey =
        DependencyProperty.RegisterReadOnly(
            nameof(DisplayIcon),
            typeof(string),
            typeof(BridgeStatePresenter),
            new PropertyMetadata(string.Empty));

    private static readonly DependencyPropertyKey DisplayTitlePropertyKey =
        DependencyProperty.RegisterReadOnly(
            nameof(DisplayTitle),
            typeof(string),
            typeof(BridgeStatePresenter),
            new PropertyMetadata(string.Empty));

    private static readonly DependencyPropertyKey DisplayDescriptionPropertyKey =
        DependencyProperty.RegisterReadOnly(
            nameof(DisplayDescription),
            typeof(string),
            typeof(BridgeStatePresenter),
            new PropertyMetadata(string.Empty));

    private static readonly DependencyPropertyKey DisplayActionTextPropertyKey =
        DependencyProperty.RegisterReadOnly(
            nameof(DisplayActionText),
            typeof(string),
            typeof(BridgeStatePresenter),
            new PropertyMetadata(string.Empty));

    private static readonly DependencyPropertyKey HasActionPropertyKey =
        DependencyProperty.RegisterReadOnly(
            nameof(HasAction),
            typeof(bool),
            typeof(BridgeStatePresenter),
            new PropertyMetadata(false));

    public static readonly DependencyProperty StateProperty = DependencyProperty.Register(
        nameof(State),
        typeof(BridgeStateKind),
        typeof(BridgeStatePresenter),
        new PropertyMetadata(BridgeStateKind.Loading, OnPresentationPropertyChanged));

    public static readonly DependencyProperty TitleOverrideProperty = DependencyProperty.Register(
        nameof(TitleOverride),
        typeof(string),
        typeof(BridgeStatePresenter),
        new PropertyMetadata(null, OnPresentationPropertyChanged));

    public static readonly DependencyProperty DescriptionOverrideProperty = DependencyProperty.Register(
        nameof(DescriptionOverride),
        typeof(string),
        typeof(BridgeStatePresenter),
        new PropertyMetadata(null, OnPresentationPropertyChanged));

    public static readonly DependencyProperty ActionTextOverrideProperty = DependencyProperty.Register(
        nameof(ActionTextOverride),
        typeof(string),
        typeof(BridgeStatePresenter),
        new PropertyMetadata(null, OnPresentationPropertyChanged));

    public static readonly DependencyProperty ActionCommandProperty = DependencyProperty.Register(
        nameof(ActionCommand),
        typeof(ICommand),
        typeof(BridgeStatePresenter),
        new PropertyMetadata(null));

    public static readonly DependencyProperty ActionCommandParameterProperty = DependencyProperty.Register(
        nameof(ActionCommandParameter),
        typeof(object),
        typeof(BridgeStatePresenter),
        new PropertyMetadata(null));

    public static readonly DependencyProperty DisplayIconProperty = DisplayIconPropertyKey.DependencyProperty;
    public static readonly DependencyProperty DisplayTitleProperty = DisplayTitlePropertyKey.DependencyProperty;
    public static readonly DependencyProperty DisplayDescriptionProperty = DisplayDescriptionPropertyKey.DependencyProperty;
    public static readonly DependencyProperty DisplayActionTextProperty = DisplayActionTextPropertyKey.DependencyProperty;
    public static readonly DependencyProperty HasActionProperty = HasActionPropertyKey.DependencyProperty;

    public static readonly RoutedEvent ActionInvokedEvent = EventManager.RegisterRoutedEvent(
        nameof(ActionInvoked),
        RoutingStrategy.Bubble,
        typeof(RoutedEventHandler),
        typeof(BridgeStatePresenter));

    private Button? _actionButton;

    static BridgeStatePresenter()
    {
        DefaultStyleKeyProperty.OverrideMetadata(
            typeof(BridgeStatePresenter),
            new FrameworkPropertyMetadata(typeof(BridgeStatePresenter)));
    }

    public BridgeStatePresenter()
    {
        UpdatePresentation();
    }

    public BridgeStateKind State
    {
        get => (BridgeStateKind)GetValue(StateProperty);
        set => SetValue(StateProperty, value);
    }

    public string? TitleOverride
    {
        get => (string?)GetValue(TitleOverrideProperty);
        set => SetValue(TitleOverrideProperty, value);
    }

    public string? DescriptionOverride
    {
        get => (string?)GetValue(DescriptionOverrideProperty);
        set => SetValue(DescriptionOverrideProperty, value);
    }

    public string? ActionTextOverride
    {
        get => (string?)GetValue(ActionTextOverrideProperty);
        set => SetValue(ActionTextOverrideProperty, value);
    }

    public ICommand? ActionCommand
    {
        get => (ICommand?)GetValue(ActionCommandProperty);
        set => SetValue(ActionCommandProperty, value);
    }

    public object? ActionCommandParameter
    {
        get => GetValue(ActionCommandParameterProperty);
        set => SetValue(ActionCommandParameterProperty, value);
    }

    public string DisplayIcon => (string)GetValue(DisplayIconProperty);
    public string DisplayTitle => (string)GetValue(DisplayTitleProperty);
    public string DisplayDescription => (string)GetValue(DisplayDescriptionProperty);
    public string DisplayActionText => (string)GetValue(DisplayActionTextProperty);
    public bool HasAction => (bool)GetValue(HasActionProperty);

    public event RoutedEventHandler ActionInvoked
    {
        add => AddHandler(ActionInvokedEvent, value);
        remove => RemoveHandler(ActionInvokedEvent, value);
    }

    public override void OnApplyTemplate()
    {
        if (_actionButton is not null)
        {
            _actionButton.Click -= OnActionButtonClick;
        }

        base.OnApplyTemplate();

        _actionButton = GetTemplateChild(ActionButtonPartName) as Button;
        if (_actionButton is not null)
        {
            _actionButton.Click += OnActionButtonClick;
        }
    }

    private static void OnPresentationPropertyChanged(DependencyObject dependencyObject, DependencyPropertyChangedEventArgs args)
    {
        var presenter = (BridgeStatePresenter)dependencyObject;
        presenter.UpdatePresentation();
    }

    private void UpdatePresentation()
    {
        var descriptor = BridgeStateCatalog.Resolve(State);
        var actionText = ActionTextOverride ?? descriptor.ActionText;
        SetValue(DisplayIconPropertyKey, descriptor.Icon);
        SetValue(DisplayTitlePropertyKey, TitleOverride ?? descriptor.Title);
        SetValue(DisplayDescriptionPropertyKey, DescriptionOverride ?? descriptor.Description);
        SetValue(DisplayActionTextPropertyKey, actionText);
        SetValue(HasActionPropertyKey, !string.IsNullOrWhiteSpace(actionText));
    }

    private void OnActionButtonClick(object sender, RoutedEventArgs args)
    {
        RaiseEvent(new RoutedEventArgs(ActionInvokedEvent, this));
    }
}
