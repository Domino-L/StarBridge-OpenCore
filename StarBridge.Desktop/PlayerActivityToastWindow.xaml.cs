using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace StarBridge.Desktop;

internal partial class PlayerActivityToastWindow : Window
{
    private const int ExtendedStyleIndex = -20;
    private const int ToolWindowStyle = 0x00000080;
    private const int NoActivateStyle = 0x08000000;
    private static readonly TimeSpan DisplayDuration = TimeSpan.FromSeconds(4.5);
    private readonly DispatcherTimer _dismissTimer = new() { Interval = TimeSpan.FromMilliseconds(100) };
    private readonly Stopwatch _visibleTime = new();
    private readonly TranslateTransform _translate = new();
    private bool _isPointerOver;
    private bool _isDismissing;

    public PlayerActivityToastWindow(PlayerActivityDesktopNotification notification)
    {
        InitializeComponent();
        Notification = notification;
        RenderTransform = _translate;
        RenderTransformOrigin = new System.Windows.Point(0.5, 0.5);
        InitialsText.Content = notification.Initials;
        DisplayNameText.Text = notification.DisplayName;
        EventText.Text = notification.EventText;
        var accent = ResolveBrush(notification.AccentColor);
        AccentLine.Background = accent;
        StatusDot.Fill = accent;
        AvatarImage.Source = TryResolveAvatar(notification.AvatarSource);
        AvatarImage.Visibility = AvatarImage.Source is null ? Visibility.Collapsed : Visibility.Visible;
        InitialsText.Visibility = AvatarImage.Source is null ? Visibility.Visible : Visibility.Collapsed;
        _dismissTimer.Tick += DismissTimer_Tick;
        SourceInitialized += PlayerActivityToastWindow_SourceInitialized;
    }

    public PlayerActivityDesktopNotification Notification { get; }

    public event EventHandler<PlayerActivityDesktopNotification>? ProfileRequested;

    public void BeginEnter(bool fromRight)
    {
        _visibleTime.Restart();
        _dismissTimer.Start();
        if (!UiMotion.IsEnabled)
        {
            Opacity = 1;
            _translate.X = 0;
            return;
        }

        Opacity = 0;
        _translate.X = fromRight ? 18 : -18;
        BeginAnimation(OpacityProperty, CreateSplineAnimation(0, 1, 210, 0.16, 1, 0.3, 1));
        _translate.BeginAnimation(
            TranslateTransform.XProperty,
            CreateSplineAnimation(_translate.X, 0, 210, 0.16, 1, 0.3, 1));
    }

    public void Dismiss(bool immediate = false)
    {
        if (_isDismissing)
        {
            return;
        }

        _isDismissing = true;
        _dismissTimer.Stop();
        if (immediate || !UiMotion.IsEnabled)
        {
            Close();
            return;
        }

        var exit = CreateSplineAnimation(Opacity, 0, 150, 0.4, 0, 1, 1);
        exit.Completed += (_, _) => Close();
        BeginAnimation(OpacityProperty, exit);
    }

    private void PlayerActivityToastWindow_SourceInitialized(object? sender, EventArgs e)
    {
        var handle = new WindowInteropHelper(this).Handle;
        var style = GetWindowLongPtr(handle, ExtendedStyleIndex).ToInt64();
        SetWindowLongPtr(handle, ExtendedStyleIndex, new IntPtr(style | ToolWindowStyle | NoActivateStyle));
    }

    private void DismissTimer_Tick(object? sender, EventArgs e)
    {
        if (!_isPointerOver && _visibleTime.Elapsed >= DisplayDuration)
        {
            Dismiss();
        }
    }

    private void ToastCard_MouseEnter(object sender, System.Windows.Input.MouseEventArgs e)
    {
        _isPointerOver = true;
        _visibleTime.Stop();
    }

    private void ToastCard_MouseLeave(object sender, System.Windows.Input.MouseEventArgs e)
    {
        _isPointerOver = false;
        _visibleTime.Start();
    }

    private void ToastCard_MouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        ProfileRequested?.Invoke(this, Notification);
        Dismiss(immediate: true);
        e.Handled = true;
    }

    private static DoubleAnimationUsingKeyFrames CreateSplineAnimation(
        double from,
        double to,
        int milliseconds,
        double x1,
        double y1,
        double x2,
        double y2)
    {
        var animation = new DoubleAnimationUsingKeyFrames();
        animation.KeyFrames.Add(new DiscreteDoubleKeyFrame(from, KeyTime.FromTimeSpan(TimeSpan.Zero)));
        animation.KeyFrames.Add(new SplineDoubleKeyFrame(
            to,
            KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(milliseconds)),
            new KeySpline(x1, y1, x2, y2)));
        return animation;
    }

    private static System.Windows.Media.Brush ResolveBrush(string color)
    {
        try
        {
            var brush = new SolidColorBrush(
                (System.Windows.Media.Color)System.Windows.Media.ColorConverter.ConvertFromString(color));
            brush.Freeze();
            return brush;
        }
        catch
        {
            return System.Windows.Media.Brushes.DeepSkyBlue;
        }
    }

    private static ImageSource? TryResolveAvatar(string? source)
    {
        if (string.IsNullOrWhiteSpace(source))
        {
            return null;
        }

        try
        {
            byte[] bytes;
            if (File.Exists(source))
            {
                bytes = File.ReadAllBytes(source);
            }
            else
            {
                var payload = source;
                var separator = payload.IndexOf(',');
                if (payload.StartsWith("data:", StringComparison.OrdinalIgnoreCase) && separator >= 0)
                {
                    payload = payload[(separator + 1)..];
                }

                bytes = Convert.FromBase64String(payload);
            }

            using var stream = new MemoryStream(bytes);
            var bitmap = new BitmapImage();
            bitmap.BeginInit();
            bitmap.CacheOption = BitmapCacheOption.OnLoad;
            bitmap.DecodePixelWidth = 84;
            bitmap.StreamSource = stream;
            bitmap.EndInit();
            bitmap.Freeze();
            return bitmap;
        }
        catch
        {
            return null;
        }
    }

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
    private static extern IntPtr GetWindowLongPtr(IntPtr handle, int index);

    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")]
    private static extern IntPtr SetWindowLongPtr(IntPtr handle, int index, IntPtr newStyle);
}
