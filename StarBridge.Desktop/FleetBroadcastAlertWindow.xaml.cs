using StarBridge.Core.FleetBroadcasts;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using WpfBrush = System.Windows.Media.Brush;
using WpfBrushes = System.Windows.Media.Brushes;
using WpfColor = System.Windows.Media.Color;
using WpfColorConverter = System.Windows.Media.ColorConverter;

namespace StarBridge.Desktop;

public partial class FleetBroadcastAlertWindow : Window
{
    private const int GwlExStyle = -20;
    private const int WsExTransparent = 0x00000020;
    private const int WsExToolWindow = 0x00000080;
    private const int WsExNoActivate = 0x08000000;
    private readonly Queue<FleetBroadcastContract> _queue = [];
    private bool _isPresenting;

    public FleetBroadcastAlertWindow()
    {
        InitializeComponent();
        SourceInitialized += (_, _) => ConfigureNoActivateWindow();
    }

    public void Enqueue(FleetBroadcastContract broadcast)
    {
        _queue.Enqueue(broadcast);
        if (!_isPresenting)
        {
            PresentNext();
        }
    }

    private void PresentNext()
    {
        if (!_queue.TryDequeue(out var broadcast))
        {
            _isPresenting = false;
            Hide();
            return;
        }

        _isPresenting = true;
        ApplyAppearance(broadcast);
        PositionOnPrimaryGameDisplay();
        Show();
        BroadcastCard.UpdateLayout();

        var transform = new TranslateTransform();
        BroadcastCard.RenderTransform = transform;
        var from = Math.Max(ActualWidth, SystemParameters.PrimaryScreenWidth) + 40;
        var to = -Math.Max(240, BroadcastCard.ActualWidth) - 40;
        var motion = new DoubleAnimation(from, to, TimeSpan.FromSeconds(broadcast.Appearance.DurationSeconds))
        {
            RepeatBehavior = new RepeatBehavior(broadcast.Appearance.RepeatCount)
        };
        motion.Completed += (_, _) =>
        {
            BroadcastCard.Opacity = 0;
            Dispatcher.BeginInvoke(PresentNext);
        };
        BroadcastCard.Opacity = 1;
        transform.BeginAnimation(TranslateTransform.XProperty, motion);
    }

    private void ApplyAppearance(FleetBroadcastContract broadcast)
    {
        BroadcastMessageText.Text = broadcast.Message;
        BroadcastAuthorText.Text = $"{broadcast.Author.Callsign} · {broadcast.Author.RoleTitle}";
        BroadcastMessageText.FontSize = 24 * broadcast.Appearance.FontScale;
        BroadcastCard.BorderBrush = ParseBrush(broadcast.Appearance.AccentColor, WpfBrushes.OrangeRed);
        BroadcastCard.Background = ParseBrush(broadcast.Appearance.BackgroundColor, new SolidColorBrush(WpfColor.FromArgb(230, 16, 24, 34)));
        BroadcastMessageText.Foreground = ParseBrush(broadcast.Appearance.TextColor, WpfBrushes.White);
    }

    private void PositionOnPrimaryGameDisplay()
    {
        var gameHandle = Process.GetProcessesByName("StarCitizen")
            .Select(process => process.MainWindowHandle)
            .FirstOrDefault(handle => handle != IntPtr.Zero);
        var area = gameHandle == IntPtr.Zero
            ? System.Windows.Forms.Screen.PrimaryScreen?.Bounds
            : System.Windows.Forms.Screen.FromHandle(gameHandle).Bounds;
        if (area is null)
        {
            Left = SystemParameters.VirtualScreenLeft;
            Top = SystemParameters.VirtualScreenTop + Math.Max(36, SystemParameters.PrimaryScreenHeight * 0.1);
            Width = SystemParameters.PrimaryScreenWidth;
            Height = 160;
            return;
        }

        var dpi = VisualTreeHelper.GetDpi(this);
        Left = area.Value.Left / dpi.DpiScaleX;
        Top = (area.Value.Top + Math.Max(36, area.Value.Height * 0.1)) / dpi.DpiScaleY;
        Width = area.Value.Width / dpi.DpiScaleX;
        Height = 160;
    }

    private void ConfigureNoActivateWindow()
    {
        var handle = new WindowInteropHelper(this).Handle;
        var style = GetWindowLongPtr(handle, GwlExStyle).ToInt64();
        SetWindowLongPtr(
            handle,
            GwlExStyle,
            new IntPtr(style | WsExTransparent | WsExToolWindow | WsExNoActivate));
    }

    private static WpfBrush ParseBrush(string value, WpfBrush fallback)
    {
        try
        {
            var color = (WpfColor)WpfColorConverter.ConvertFromString(value);
            var brush = new SolidColorBrush(color);
            brush.Freeze();
            return brush;
        }
        catch
        {
            return fallback;
        }
    }

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
    private static extern IntPtr GetWindowLongPtr(IntPtr hWnd, int nIndex);

    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")]
    private static extern IntPtr SetWindowLongPtr(IntPtr hWnd, int nIndex, IntPtr dwNewLong);
}
