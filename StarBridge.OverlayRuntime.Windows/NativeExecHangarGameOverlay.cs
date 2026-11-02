namespace StarBridge.OverlayRuntime.Windows;

using System.Runtime.InteropServices;
using System.Text;
using System.Diagnostics;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
using StarBridge.HostRuntime.Tools;

/// <summary>Host-owned passive HWND; never injects into the game or consumes keyboard/mouse input.</summary>
public sealed class NativeExecHangarGameOverlay : IExecHangarGameOverlaySink
{
    private readonly object _gate = new();
    private readonly Thread _thread;
    private readonly ManualResetEventSlim _started = new();
    private readonly Func<bool> _menuVisible;
    private readonly Func<string?> _locale;
    private Dispatcher? _dispatcher;
    private Window? _window;
    private ExecHangarGameOverlayCard? _card;
    private DispatcherTimer? _timer;
    private ExecHangarGameOverlayFrame? _frame;
    private Func<bool>? _current;
    private long _epoch;
    private long _received;
    private volatile bool _disposed, _ready;
    public bool Available => _ready && !_disposed;
    public NativeExecHangarGameOverlay(Func<bool> menuVisible, Func<string?> locale)
    {
        _menuVisible = menuVisible; _locale = locale;
        _thread = new Thread(Run) { IsBackground = true, Name = "StarBridge.ExecHangarGameOverlay" };
        _thread.SetApartmentState(ApartmentState.STA); _thread.Start();
        _started.Wait(TimeSpan.FromSeconds(3));
    }
    public void Present(ExecHangarGameOverlayFrame frame, Func<bool> isCurrent)
    {
        lock (_gate)
        {
            if (!Available || !isCurrent()) return;
            var epoch = Interlocked.Increment(ref _epoch);
            Post(() => { if (_disposed || epoch != Volatile.Read(ref _epoch) || !isCurrent()) return; _frame = frame; _current = isCurrent; _received = Stopwatch.GetTimestamp(); Sync(); });
        }
    }
    public void Clear()
    {
        lock (_gate)
        {
            var epoch = Interlocked.Increment(ref _epoch);
            Post(() => { if (epoch != Volatile.Read(ref _epoch)) return; _frame = null; _current = null; _window?.Hide(); });
        }
    }
    private void Post(Action action)
    {
        var dispatcher = _dispatcher;
        if (dispatcher is null || dispatcher.HasShutdownStarted) return;
        try { dispatcher.BeginInvoke(action, DispatcherPriority.Send); } catch (InvalidOperationException) { }
    }
    private void Run()
    {
        var previous = SetThreadDpiAwarenessContext(new IntPtr(-4));
        try
        {
            _dispatcher = Dispatcher.CurrentDispatcher;
            _card = new();
            _window = new Window { Width = ExecHangarGameOverlayCard.CardWidth, Height = ExecHangarGameOverlayCard.CardHeight,
                Content = new System.Windows.Controls.Viewbox { Child = _card, Stretch = Stretch.Fill },
                WindowStyle = WindowStyle.None, ResizeMode = ResizeMode.NoResize, ShowInTaskbar = false,
                ShowActivated = false, AllowsTransparency = true, Background = Brushes.Transparent,
                Topmost = true, IsHitTestVisible = false, Left = -32000, Top = -32000, Title = "StarBridge Executive Hangar" };
            _window.SourceInitialized += (_, _) =>
            {
                var handle = new WindowInteropHelper(_window).Handle;
                SetWindowLongPtr(handle, -20, new IntPtr(GetWindowLongPtr(handle, -20).ToInt64() | 0x08000000L | 0x80L | 0x20L));
                HwndSource.FromHwnd(handle)?.AddHook((IntPtr hwnd, int msg, IntPtr w, IntPtr l, ref bool handled) =>
                {
                    if (msg == 0x84) { handled = true; return new(-1); } // HTTRANSPARENT
                    if (msg == 0x21) { handled = true; return new(3); } // MA_NOACTIVATE
                    return IntPtr.Zero;
                });
            };
            new WindowInteropHelper(_window).EnsureHandle();
            _timer = new DispatcherTimer(TimeSpan.FromMilliseconds(250), DispatcherPriority.Background, (_, _) => Sync(), _dispatcher);
            _ready = true; _started.Set();
            if (!_disposed) Dispatcher.Run();
        }
        catch { _ready = false; }
        finally { _ready = false; _timer?.Stop(); _window?.Close(); _started.Set(); if (previous != IntPtr.Zero) SetThreadDpiAwarenessContext(previous); }
    }
    private void Sync()
    {
        try
        {
            if (_disposed || _frame is not {} frame || _current?.Invoke() != true || _menuVisible() ||
                !StarBridge.Desktop.DesktopNotificationEnvironment.CanPresentAchievement() ||
                !TryGame(out var game, out var client)) { _window?.Hide(); return; }
            var elapsed = Stopwatch.GetElapsedTime(_received);
            var display = frame with { Now = frame.Now + elapsed };
            if (elapsed > TimeSpan.FromSeconds(6) || display.Now >= frame.Boundary) { _window!.Hide(); return; }
            _card!.Update(display, _locale());
            var bounds = ExecHangarGameOverlayPlacement.ForGame(client, GetDpiForWindow(game), frame.Position, _card.Width);
            var hwnd = new WindowInteropHelper(_window!).Handle;
            if (!SetWindowPos(hwnd, new IntPtr(-1), bounds.X, bounds.Y, bounds.Width, bounds.Height, 0x10)) { _window!.Hide(); return; }
            if (!_window!.IsVisible) _window.Show();
        }
        catch { _window?.Hide(); }
    }
    private static bool TryGame(out IntPtr game, out System.Drawing.Rectangle client)
    {
        game = GetForegroundWindow(); client = default;
        if (game == IntPtr.Zero || IsIconic(game)) return false;
        GetWindowThreadProcessId(game, out var pid);
        if (!string.Equals(StarBridge.HostRuntime.Presence.ProcessSnapshotNames.FindForeground(pid), "StarCitizen.exe", StringComparison.OrdinalIgnoreCase)) return false;
        if (GetForegroundWindow() != game || !GetClientRect(game, out var rect)) return false;
        var top = new PointI(); if (!ClientToScreen(game, ref top)) return false;
        client = new(top.X, top.Y, rect.Right - rect.Left, rect.Bottom - rect.Top);
        return client.Width > 0 && client.Height > 0 && GetForegroundWindow() == game;
    }
    public void Dispose()
    {
        lock (_gate) { if (_disposed) return; _disposed = true; Interlocked.Increment(ref _epoch); }
        Post(() => { _frame = null; _window?.Hide(); _dispatcher?.BeginInvokeShutdown(DispatcherPriority.Send); });
        if (Thread.CurrentThread != _thread) _thread.Join(TimeSpan.FromSeconds(2));
    }
    [StructLayout(LayoutKind.Sequential)] private struct RectI { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] private struct PointI { public int X, Y; }
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern bool IsIconic(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("user32.dll")] private static extern bool GetClientRect(IntPtr hwnd, out RectI rect);
    [DllImport("user32.dll")] private static extern bool ClientToScreen(IntPtr hwnd, ref PointI point);
    [DllImport("user32.dll")] private static extern uint GetDpiForWindow(IntPtr hwnd);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] private static extern IntPtr GetWindowLongPtr(IntPtr hwnd, int index);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")] private static extern IntPtr SetWindowLongPtr(IntPtr hwnd, int index, IntPtr value);
    [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int width, int height, uint flags);
    [DllImport("user32.dll")] private static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
}
