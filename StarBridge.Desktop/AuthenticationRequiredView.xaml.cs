using System.Windows;

namespace StarBridge.Desktop;

public partial class AuthenticationRequiredView : System.Windows.Controls.UserControl
{
    public static readonly DependencyProperty HeadingProperty = DependencyProperty.Register(
        nameof(Heading),
        typeof(string),
        typeof(AuthenticationRequiredView),
        new PropertyMetadata("登录后继续"));

    public static readonly DependencyProperty DescriptionProperty = DependencyProperty.Register(
        nameof(Description),
        typeof(string),
        typeof(AuthenticationRequiredView),
        new PropertyMetadata(string.Empty));

    public static readonly DependencyProperty FirstCapabilityProperty = DependencyProperty.Register(
        nameof(FirstCapability),
        typeof(string),
        typeof(AuthenticationRequiredView),
        new PropertyMetadata(string.Empty));

    public static readonly DependencyProperty SecondCapabilityProperty = DependencyProperty.Register(
        nameof(SecondCapability),
        typeof(string),
        typeof(AuthenticationRequiredView),
        new PropertyMetadata(string.Empty));

    public static readonly DependencyProperty ThirdCapabilityProperty = DependencyProperty.Register(
        nameof(ThirdCapability),
        typeof(string),
        typeof(AuthenticationRequiredView),
        new PropertyMetadata(string.Empty));

    public static readonly RoutedEvent LoginRequestedEvent = EventManager.RegisterRoutedEvent(
        nameof(LoginRequested),
        RoutingStrategy.Bubble,
        typeof(RoutedEventHandler),
        typeof(AuthenticationRequiredView));

    public AuthenticationRequiredView()
    {
        InitializeComponent();
    }

    public string Heading
    {
        get => (string)GetValue(HeadingProperty);
        set => SetValue(HeadingProperty, value);
    }

    public string Description
    {
        get => (string)GetValue(DescriptionProperty);
        set => SetValue(DescriptionProperty, value);
    }

    public string FirstCapability
    {
        get => (string)GetValue(FirstCapabilityProperty);
        set => SetValue(FirstCapabilityProperty, value);
    }

    public string SecondCapability
    {
        get => (string)GetValue(SecondCapabilityProperty);
        set => SetValue(SecondCapabilityProperty, value);
    }

    public string ThirdCapability
    {
        get => (string)GetValue(ThirdCapabilityProperty);
        set => SetValue(ThirdCapabilityProperty, value);
    }

    public event RoutedEventHandler LoginRequested
    {
        add => AddHandler(LoginRequestedEvent, value);
        remove => RemoveHandler(LoginRequestedEvent, value);
    }

    private void LoginButton_Click(object sender, RoutedEventArgs e)
    {
        RaiseEvent(new RoutedEventArgs(LoginRequestedEvent, this));
    }
}
