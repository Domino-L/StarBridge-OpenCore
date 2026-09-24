namespace StarBridge.Desktop;

using StarBridge.HostRuntime.Notifications;
using StarBridge.HostRuntime.Presence;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Threading;

/// <summary>One Native Host-owned STA; no App/MainWindow, tray, polling of business data or second client.</summary>
public sealed class NativeDesktopNotificationRuntime : IDesktopNotificationSink
{
    private readonly int _parentId;
    private readonly Thread _thread;
    private readonly ManualResetEventSlim _started = new();
    private readonly LocalGamePresenceReader _game = new();
    private readonly List<Entry> _visible = [];
    private readonly Queue<DesktopNotification> _pending = new();
    private Dispatcher? _dispatcher;
    private DispatcherTimer? _timer;
    private volatile bool _disposed;
    private long _tick = Stopwatch.GetTimestamp();
    private string? _lastSuppression;
    private sealed class Entry(DesktopNotification notice, Window window) {
        internal readonly DesktopNotification Notice = notice;
        internal readonly Window Window = window;
        internal TimeSpan Remaining = TimeSpan.FromSeconds(notice.Activity is null ? 8 : 4.5);
        internal System.Drawing.Rectangle Area;
        internal bool Exiting;
    }

    public NativeDesktopNotificationRuntime(int parentId)
    {
        _parentId = parentId;
        _thread = new Thread(Run) { IsBackground = true, Name = "StarBridge.DesktopReminders" };
        _thread.SetApartmentState(ApartmentState.STA); _thread.Start();
        _started.Wait(TimeSpan.FromSeconds(3));
    }

    public async ValueTask<bool> TryPresentAsync(DesktopNotification notice, CancellationToken token) =>
        (await TryPresentDetailedAsync(notice, token)).Submitted;

    public async ValueTask<DesktopNotificationResult> TryPresentDetailedAsync(DesktopNotification notice, CancellationToken token)
    {
        var dispatcher = _dispatcher;
        if (_disposed || dispatcher == null || dispatcher.HasShutdownStarted) return new(false, "unavailable");
        return await dispatcher.InvokeAsync(() => {
            token.ThrowIfCancellationRequested();
            if (_disposed || !notice.IsCurrent()) return new DesktopNotificationResult(false, "expired");
            if (!Allowed(notice)) return new DesktopNotificationResult(false, DesktopNotificationEnvironment.UserReason(_lastSuppression));
            if (_visible.Any(e => e.Notice.Id == notice.Id) || _pending.Any(e => e.Id == notice.Id)) return new(true, "submitted");
            if (notice.Activity is {} activity) {
                foreach (var previous in _visible.Where(e => e.Notice.Activity is {} old &&
                    activity.MemberKey != null && old.MemberKey == activity.MemberKey).ToArray()) Remove(previous);
                var activities = _visible.Where(e => e.Notice.Activity != null).ToArray();
                if (activities.Length >= 2) Remove(activities[0]);
                // Activity is ephemeral; never queue it behind business reminders.
                if (_visible.Count >= 3) return new(false, "queueFull");
                var shown = Show(notice);
                return new(shown, shown ? "submitted" : "unavailable");
            }
            if (_visible.Count < 3) {
                var shown = Show(notice);
                return new(shown, shown ? "submitted" : DesktopNotificationEnvironment.UserReason(_lastSuppression));
            }
            if (_pending.Count >= 12) return new(false, "queueFull");
            _pending.Enqueue(notice); return new(true, "submitted");
        }, DispatcherPriority.Send, token).Task.WaitAsync(token).ConfigureAwait(false);
    }

    private bool Allowed(DesktopNotification notice)
    {
        var reason = DesktopNotificationEnvironment.SuppressionReason();
        if (reason.Length == 0) {
            var foreground = GetForegroundWindow();
            bool? appForeground = foreground == IntPtr.Zero || GetWindowThreadProcessId(foreground, out var id) == 0
                ? null : id == _parentId;
            reason = DesktopNotificationVisibility.SuppressionReason(notice,
                notice.Activity is null ? _game.Read().State : "unknown", appForeground);
        }
        if (reason != _lastSuppression) {
            _lastSuppression = reason;
            Trace.WriteLine("desktop-notification-state: " + (reason.Length == 0 ? "allowed" : reason));
        }
        return reason.Length == 0;
    }

    private bool Show(DesktopNotification notice)
    {
        if (!notice.IsCurrent()) return false;
        var passive = notice.Activity != null;
        var window = new Window { Width = passive ? 368 : 380, Height = passive ? 88 : 170, WindowStyle = WindowStyle.None,
            ResizeMode = ResizeMode.NoResize, ShowInTaskbar = false, ShowActivated = false,
            AllowsTransparency = true, Background = System.Windows.Media.Brushes.Transparent,
            Topmost = true, Left = -32000, Top = -32000, Title = "StarBridge notification" };
        var entry = new Entry(notice, window);
        window.Content = passive ? new PlayerActivityNotificationCard(notice) : new DesktopNotificationCard(notice, () => Open(entry), () => Dismiss(entry));
        var animate = DesktopNotificationMotion.Enabled(notice.ReduceMotion);
        window.Opacity = !passive && animate ? 0 : 1;
        if (passive && window.Content is PlayerActivityNotificationCard card) {
            card.Margin = new(12, 0, 12, 0);
            card.Opacity = animate ? 0 : 1;
            card.Loaded += (_, _) => DesktopNotificationMotion.EnterActivity(card, notice.Position.EndsWith("Right"), animate);
        }
        window.SourceInitialized += (_, _) => {
            var handle = new WindowInteropHelper(window).Handle;
            var style = GetWindowLongPtr(handle, -20).ToInt64();
            SetWindowLongPtr(handle, -20, new IntPtr(style | 0x08000000L | 0x80L | (passive ? 0x20L : 0))); // passive: WS_EX_TRANSPARENT
            HwndSource.FromHwnd(handle)?.AddHook((IntPtr hwnd, int msg, IntPtr wp, IntPtr lp, ref bool handled) => {
                if (msg == 0x21) { handled = true; return new IntPtr(3); } // MA_NOACTIVATE, still accept the click
                return IntPtr.Zero;
            });
        };
        try {
            _visible.Add(entry);
            var foreground = GetForegroundWindow();
            var screen = System.Windows.Forms.Screen.FromHandle(foreground);
            entry.Area = screen.WorkingArea;
            new WindowInteropHelper(window).EnsureHandle();
            Place(entry, screen.WorkingArea, _visible.Count - 1);
            if (!notice.IsCurrent() || !Allowed(notice)) { Remove(entry); return false; }
            window.Show();
            Place(entry, screen.WorkingArea, _visible.Count - 1);
            if (!passive) DesktopNotificationMotion.Fade(window, 1, 180, animate);
            return true;
        } catch { Remove(entry); return false; }
    }

    private void Place(Entry entry, System.Drawing.Rectangle area, int index)
    {
        var handle = new WindowInteropHelper(entry.Window).Handle;
        var scale = Math.Max(96, GetDpiForWindow(handle)) / 96d;
        var width = (int)Math.Ceiling(entry.Window.Width * scale); var height = (int)Math.Ceiling(entry.Window.Height * scale);
        var gap = (int)Math.Ceiling(12 * scale);
        var offset = _visible.Take(index).Where(other => other.Area == area && other.Notice.Position == entry.Notice.Position)
            .Sum(other => (int)Math.Ceiling(other.Window.Height * scale) + gap);
        var x = entry.Notice.Position.EndsWith("Left") ? area.Left + gap : area.Right - width - gap;
        var y = entry.Notice.Position.StartsWith("top") ? area.Top + gap + offset : area.Bottom - height - gap - offset;
        SetWindowPos(handle, new IntPtr(-1), x, y, width, height, 0x10); // NOACTIVATE
    }

    private void Open(Entry entry)
    {
        if (entry.Notice.Activity != null) return;
        if (!entry.Notice.IsCurrent() || !Allowed(entry.Notice)) { Remove(entry); return; }
        try {
            using var parent = Process.GetProcessById(_parentId);
            var handle = parent.MainWindowHandle;
            if (handle == IntPtr.Zero) {
                EnumWindows((candidate, _) => {
                    GetWindowThreadProcessId(candidate, out var processId);
                    var name = new System.Text.StringBuilder(128);
                    if (processId == _parentId && GetClassName(candidate, name, name.Capacity) > 0 && name.ToString() == "FLUTTER_RUNNER_WIN32_WINDOW") {
                        handle = candidate; return false;
                    }
                    return true;
                }, IntPtr.Zero);
            }
            if (handle == IntPtr.Zero) return; // Keep the card if activation cannot be attempted.
            ShowWindowAsync(handle, IsIconic(handle) ? 9 : 5); // Preserve an already maximized main window.
            if (SetForegroundWindow(handle)) { entry.Notice.Activated?.Invoke(); Remove(entry); }
        } catch { /* Preserve the card and unread; never start another process. */ }
    }

    private void Dismiss(Entry entry) {
        if (entry.Exiting || !_visible.Contains(entry)) return;
        entry.Exiting = true;
        entry.Window.IsHitTestVisible = false;
        var animate = DesktopNotificationMotion.Enabled(entry.Notice.ReduceMotion);
        if (entry.Notice.Activity != null && entry.Window.Content is UIElement card)
            DesktopNotificationMotion.ExitActivity(card, entry.Notice.Position.EndsWith("Right"), animate, () => Remove(entry));
        else
            DesktopNotificationMotion.Fade(entry.Window, 0, 120, animate, () => Remove(entry));
    }

    private void Remove(Entry entry) {
        if (!_visible.Contains(entry)) return;
        DesktopNotificationMotion.Cancel(entry.Window);
        if (entry.Window.Content is UIElement card) {
            DesktopNotificationMotion.Cancel(card);
            if (card.RenderTransform is System.Windows.Media.TranslateTransform translation)
                translation.BeginAnimation(System.Windows.Media.TranslateTransform.XProperty, null);
        }
        _visible.Remove(entry); entry.Window.Close();
        for (var i = 0; i < _visible.Count; i++) Place(_visible[i], _visible[i].Area, i);
    }
    public void Clear()
    {
        var dispatcher = _dispatcher;
        if (dispatcher == null || dispatcher.HasShutdownStarted || dispatcher.HasShutdownFinished) return;
        dispatcher.BeginInvoke(ClearOnThread, DispatcherPriority.Send);
    }
    private void ClearOnThread() { _pending.Clear(); foreach (var e in _visible.ToArray()) Remove(e); }
    public void ClearMessages()
    {
        var dispatcher = _dispatcher;
        if (dispatcher == null || dispatcher.HasShutdownStarted || dispatcher.HasShutdownFinished) return;
        dispatcher.BeginInvoke(() => {
            var activities = _pending.Where(n => n.Activity != null).ToArray();
            _pending.Clear();
            foreach (var activity in activities) _pending.Enqueue(activity);
            foreach (var entry in _visible.Where(e => e.Notice.Activity == null).ToArray()) Remove(entry);
        }, DispatcherPriority.Send);
    }
    private void Tick()
    {
        var now = Stopwatch.GetTimestamp(); var elapsed = Stopwatch.GetElapsedTime(_tick, now); _tick = now;
        foreach (var e in _visible.ToArray()) {
            if (e.Notice.Activity != null || !e.Window.IsMouseOver) e.Remaining -= elapsed;
            // Privacy revocation and system suppression bypass animation: never retain stale text for a fade.
            if (!e.Notice.IsCurrent() || !Allowed(e.Notice)) Remove(e);
            else if (e.Remaining <= TimeSpan.Zero) Dismiss(e);
        }
        while (_visible.Count < 3 && _pending.TryDequeue(out var next))
            if (next.IsCurrent() && Allowed(next)) Show(next);
    }
    private void Run()
    {
        try {
            _dispatcher = Dispatcher.CurrentDispatcher;
            if (_disposed) return;
            _timer = new DispatcherTimer(TimeSpan.FromMilliseconds(250), DispatcherPriority.Background,
                (_, _) => { try { Tick(); } catch { ClearOnThread(); } }, _dispatcher);
            _started.Set(); Dispatcher.Run();
        } catch (Exception e) { Trace.WriteLine("desktop-notification-runtime: " + e.GetType().Name); }
        finally { _timer?.Stop(); ClearOnThread(); _started.Set(); }
    }
    public void Dispose()
    {
        if (_disposed) return; _disposed = true;
        var dispatcher = _dispatcher;
        if (dispatcher != null && !dispatcher.HasShutdownStarted)
            dispatcher.BeginInvoke(() => { ClearOnThread(); dispatcher.BeginInvokeShutdown(DispatcherPriority.Send); }, DispatcherPriority.Send);
        if (Thread.CurrentThread != _thread) _thread.Join(TimeSpan.FromSeconds(2));
    }

    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out uint id);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] private static extern IntPtr GetWindowLongPtr(IntPtr hwnd, int index);
    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")] private static extern IntPtr SetWindowLongPtr(IntPtr hwnd, int index, IntPtr value);
    [DllImport("user32.dll")] private static extern bool SetWindowPos(IntPtr hwnd, IntPtr after, int x, int y, int width, int height, uint flags);
    [DllImport("user32.dll")] private static extern uint GetDpiForWindow(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern bool ShowWindowAsync(IntPtr hwnd, int command);
    [DllImport("user32.dll")] private static extern bool IsIconic(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern bool SetForegroundWindow(IntPtr hwnd);
    private delegate bool EnumWindowCallback(IntPtr hwnd, IntPtr parameter);
    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumWindowCallback callback, IntPtr parameter);
    [DllImport("user32.dll", EntryPoint = "GetClassNameW", CharSet = CharSet.Unicode)]
    private static extern int GetClassName(IntPtr hwnd, System.Text.StringBuilder name, int size);
}
