namespace StarBridge.OverlayRuntime.Windows;

using StarBridge.HostRuntime.Achievements;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;

// One passive card, one serial sound, owned by the Native Host lifetime.
public sealed class NativeAchievementCelebrationRuntime : IAchievementCelebrationSink, IDisposable
{
    private readonly Thread _thread;
    private readonly ManualResetEventSlim _started = new();
    private readonly object _postGate = new();
    private readonly Queue<Action> _startupActions = new();
    private readonly AchievementCelebrationPlayback _playback;
    private readonly Func<string?> _locale;
    private readonly Func<bool> _light, _reduce;
    private readonly Func<Func<bool>, bool> _play;
    private readonly Action _stop;
    private Dispatcher? _dispatcher;
    private DispatcherTimer? _timer;
    private long _lastTick;
    private long _desktopProbe;
    private bool _desktopAllowed;
    private volatile bool _disposed;

    public NativeAchievementCelebrationRuntime(Func<string?> locale, Func<bool> light, Func<bool> reduce,
        Func<Func<bool>, bool> play, Action stop)
    {
        _locale = locale; _light = light; _reduce = reduce; _play = play; _stop = stop;
        _playback = new(CreateSurface, () => _desktopAllowed,
            current => _play(() => !_disposed && current() &&
                StarBridge.Desktop.DesktopNotificationEnvironment.CanPresentAchievement()), _stop, AchievementCelebrationActivity.Shared);
        _thread = new Thread(Run) { IsBackground = true, Name = "StarBridge.AchievementCelebration" };
        _thread.SetApartmentState(ApartmentState.STA); _thread.Start();
        _started.Wait(TimeSpan.FromSeconds(3));
    }
    public void Submit(AchievementCelebration notice)
    {
        if (_disposed)
        {
            if (notice.Receipt is not null && notice.IsCurrent()) throw new InvalidOperationException("Celebration sink has retired.");
            return;
        }
        if (!notice.CanPresent || !notice.IsCurrent()) return;
        // Accept under the account-local durable receipt writer before handing
        // the card to the STA. Producer acknowledgement may fail independently.
        if (!notice.TryAcceptReceipt()) return;
        Post(() => { if (!_disposed && notice.IsCurrent()) _playback.SubmitAccepted(notice); });
    }
    private void Post(Action action)
    {
        lock (_postGate)
        {
            var dispatcher = _dispatcher;
            if (dispatcher is null) { _startupActions.Enqueue(action); return; }
            if (dispatcher.HasShutdownStarted) return;
            try { dispatcher.BeginInvoke(action, DispatcherPriority.Send); }
            catch (InvalidOperationException) { }
        }
    }
    public void Clear() => Post(_playback.Clear);
    private void Run()
    {
        var previousDpi = SetThreadDpiAwarenessContext(new IntPtr(-4)); // This STA only; do not change the shared Host context.
        try
        {
            lock (_postGate)
            {
                _dispatcher = Dispatcher.CurrentDispatcher;
                while (_startupActions.TryDequeue(out var action)) _dispatcher.BeginInvoke(action, DispatcherPriority.Send);
            }
            if (_disposed) return;
            _lastTick = Stopwatch.GetTimestamp();
            _timer = new DispatcherTimer(TimeSpan.FromMilliseconds(250), DispatcherPriority.Background,
                (_, _) => Tick(), _dispatcher);
            _started.Set(); Dispatcher.Run();
        }
        finally
        {
            _timer?.Stop(); _playback.Dispose(); lock (_postGate) _startupActions.Clear(); _started.Set();
            if (previousDpi != IntPtr.Zero) SetThreadDpiAwarenessContext(previousDpi);
        }
    }
    private void Tick()
    {
        var now = Stopwatch.GetTimestamp();
        var delta = Stopwatch.GetElapsedTime(_lastTick, now).TotalMilliseconds;
        _lastTick = now;
        // Do not query Windows at animation frequency. An inactive/locked
        // desktop hides and pauses rather than silently dropping the grant.
        if (_desktopProbe == 0 || Stopwatch.GetElapsedTime(_desktopProbe, now).TotalMilliseconds >= 250)
        {
            _desktopAllowed = StarBridge.Desktop.DesktopNotificationEnvironment.CanPresentAchievement();
            _desktopProbe = now;
        }
        _playback.Advance(delta);
        if (_timer is not null) _timer.Interval = TimeSpan.FromMilliseconds(_playback.HasActive ? 16 : 250);
    }
    private IAchievementCelebrationSurface? CreateSurface(AchievementCelebration notice)
    {
        if (!notice.IsCurrent()) return null;
        var card = new AchievementCelebrationCard(_locale(), _light(), _reduce() || !SystemParameters.ClientAreaAnimation,
            notice.AchievementId, notice.Rank, notice.DisplayName, notice.LocalImagePath);
        try
        {
            var surface = CreateHiddenSurface(card);
            _desktopAllowed = StarBridge.Desktop.DesktopNotificationEnvironment.CanPresentAchievement();
            _lastTick = Stopwatch.GetTimestamp();
            return surface;
        }
        catch { return null; }
    }
    internal static Surface CreateHiddenSurface(AchievementCelebrationCard card, string? targetScreen = null)
    {
        var window = new Window { Width = card.Width, Height = card.Height,
            Content = new System.Windows.Controls.Viewbox { Child = card, Stretch = Stretch.Uniform }, WindowStyle = WindowStyle.None,
            ResizeMode = ResizeMode.NoResize, ShowInTaskbar = false, ShowActivated = false, Topmost = true,
            AllowsTransparency = true, Background = Brushes.Transparent, Left = -32000, Top = -32000,
            Title = "StarBridge achievement", IsHitTestVisible = false };
        window.SourceInitialized += (_, _) =>
        {
            var hwnd = new WindowInteropHelper(window).Handle;
            SetWindowLongPtr(hwnd, -20, new IntPtr(GetWindowLongPtr(hwnd, -20).ToInt64() | 0x08000000L | 0x80L | 0x20L));
        };
        try
        {
            var surface = new Surface(window, card, targetScreen);
            surface.UpdatePosition();
            return surface;
        }
        catch { window.Close(); throw; }
    }
    internal sealed class Surface : IAchievementCelebrationSurface
    {
        private readonly Window window;
        private readonly AchievementCelebrationCard card;
        private readonly IntPtr _hwnd;
        private string _screen;
        private System.Drawing.Rectangle _lastArea;
        private uint _lastDpi;
        private long _positionProbe;
        private System.Drawing.Rectangle _bounds;
        internal IntPtr Handle => _hwnd;
        internal double PointerOpacity => window.Opacity;
        internal Surface(Window window, AchievementCelebrationCard card, string? targetScreen)
        {
            this.window = window; this.card = card;
            _hwnd = new WindowInteropHelper(window).EnsureHandle();
            var screen = System.Windows.Forms.Screen.AllScreens.FirstOrDefault(s => s.DeviceName == targetScreen)
                ?? System.Windows.Forms.Screen.FromHandle(GetForegroundWindow());
            _screen = screen.DeviceName;
            // First enter the target monitor while hidden. GetDpiForWindow then
            // describes that monitor rather than the off-screen creation site.
            if (!SetWindowPos(_hwnd, IntPtr.Zero, screen.WorkingArea.Left, screen.WorkingArea.Top, 1, 1, 0x14))
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
        }
        public double LifetimeMilliseconds => card.LifetimeMilliseconds;
        public bool IsVisible => window.IsVisible;
        public void Show()
        {
            _positionProbe = 0; UpdatePosition();
            if (!StarBridge.Desktop.DesktopNotificationEnvironment.CanPresentAchievement())
                throw new InvalidOperationException("Achievement desktop changed before show.");
            window.Show();
            UpdatePointerOpacity();
        }
        public void Hide() => window.Hide();
        public void Advance(double elapsed, int remaining)
        {
            card.Advance(elapsed, remaining);
            UpdatePointerOpacity();
        }
        private void UpdatePointerOpacity()
        {
            // The passive HWND never receives mouse-enter events. Poll screen
            // coordinates without capturing input or changing click-through.
            ApplyPointerPosition(GetCursorPos(out var point) ? new System.Drawing.Point(point.X, point.Y) : null);
        }
        internal void ApplyPointerPosition(System.Drawing.Point? point)
        {
            var opacity = point.HasValue && _bounds.Contains(point.Value) ? .5 : 1;
            if (window.Opacity != opacity) window.Opacity = opacity;
        }
        public void UpdatePosition()
        {
            var now = Stopwatch.GetTimestamp();
            if (_positionProbe != 0 && Stopwatch.GetElapsedTime(_positionProbe, now).TotalMilliseconds < 250) return;
            _positionProbe = now;
            var screen = System.Windows.Forms.Screen.AllScreens.FirstOrDefault(s => s.DeviceName == _screen)
                ?? System.Windows.Forms.Screen.FromHandle(GetForegroundWindow());
            _screen = screen.DeviceName;
            var area = screen.WorkingArea;
            var dpi = GetDpiForWindow(_hwnd);
            if (area == _lastArea && dpi == _lastDpi) return;
            var placement = AchievementCelebrationPlacement.ForWorkArea(area, dpi);
            var bounds = placement.Bounds;
            if (!SetWindowPos(_hwnd, new IntPtr(-1), bounds.X, bounds.Y, bounds.Width, bounds.Height, 0x10))
                throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            _bounds = bounds; _lastArea = area; _lastDpi = dpi;
        }
        public void Dispose() => window.Close();
    }
    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        Post(() => { _playback.Dispose(); _dispatcher?.BeginInvokeShutdown(DispatcherPriority.Send); });
        if (Thread.CurrentThread != _thread) _thread.Join(TimeSpan.FromSeconds(2));
    }
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [StructLayout(LayoutKind.Sequential)] private struct NativePoint { internal int X, Y; }
    [DllImport("user32.dll")] private static extern bool GetCursorPos(out NativePoint point);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] private static extern IntPtr GetWindowLongPtr(IntPtr hwnd, int index);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")] private static extern IntPtr SetWindowLongPtr(IntPtr hwnd, int index, IntPtr value);
    [DllImport("user32.dll")] private static extern uint GetDpiForWindow(IntPtr hwnd);
    [DllImport("user32.dll", SetLastError = true)] private static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int width, int height, uint flags);
    [DllImport("user32.dll")] private static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
}
