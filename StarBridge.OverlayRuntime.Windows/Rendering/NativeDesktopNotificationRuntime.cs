namespace StarBridge.Desktop;

using StarBridge.HostRuntime.Notifications;
using StarBridge.HostRuntime.Presence;
using StarBridge.HostRuntime.Achievements;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Threading;

/// <summary>One Native Host-owned STA; no App/MainWindow, tray, polling of business data or second client.</summary>
public sealed class NativeDesktopNotificationRuntime : IDesktopNotificationSink
{
    public string DiagnosticTransport => "wpfCard";
    private readonly int _parentId;
    private readonly Thread _thread;
    private readonly ManualResetEventSlim _started = new();
    private readonly LocalGamePresenceReader _game = new();
    private readonly List<Entry> _visible = [];
    private readonly Queue<DesktopNotification> _pending = new();
    private Dispatcher? _dispatcher;
    private DispatcherTimer? _timer;
    private volatile bool _disposed;
    private string? _lastSuppression;
    private readonly AchievementCelebrationActivity _celebration = AchievementCelebrationActivity.Shared;
    private bool _celebrationPaused, _serialAfterCelebration;
    private sealed class Entry(DesktopNotification notice, Window window) {
        internal readonly DesktopNotification Notice = notice;
        internal readonly Window Window = window;
        internal TimeSpan Remaining = TimeSpan.FromSeconds(notice.GameStartupHint != null ? 9 : IsPassive(notice) ? 4.5 : 8);
        internal long LastTick = Stopwatch.GetTimestamp();
        internal System.Drawing.Rectangle Area;
        internal bool Exiting;
    }

    public NativeDesktopNotificationRuntime(int parentId)
    {
        _parentId = parentId;
        _celebration.Changed += CelebrationChanged;
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
            notice = PrepareTrade(PrepareHangar(notice));
            if (!Allowed(notice)) return new DesktopNotificationResult(false, DesktopNotificationEnvironment.UserReason(_lastSuppression));
            if (_visible.Any(e => e.Notice.Id == notice.Id) || _pending.Any(e => e.Id == notice.Id)) return new(true, "submitted");
            if (_celebration.IsActive || _serialAfterCelebration) return QueueDuringCelebration(notice);
            if (notice.GameStartupHint != null) {
                if (_visible.Count >= 3) return new(false, "queueFull");
                var shown = Show(notice);
                return new(shown, shown ? "submitted" : "unavailable");
            }
            if (notice.ExecHangar is { Compact: true }) {
                // Only one ephemeral hangar card; do not accumulate stale timers
                // or queue a compact card behind unrelated business reminders.
                foreach (var previous in _visible.Where(e => e.Notice.ExecHangar != null).ToArray()) Remove(previous);
                var kept = _pending.Where(n => n.ExecHangar == null).ToArray();
                foreach (var previous in _pending.Where(n => n.ExecHangar != null)) previous.ReportDiagnostic("superseded");
                _pending.Clear(); foreach (var other in kept) _pending.Enqueue(other);
                if (_visible.Count >= 3) return new(false, "queueFull");
                var shown = Show(notice);
                return new(shown, shown ? "submitted" : DesktopNotificationEnvironment.UserReason(_lastSuppression)) {
                    DiagnosticOutcome = shown ? "windowShown" : null
                };
            }
            if (notice.Activity is {} activity) {
                foreach (var previous in _visible.Where(e => e.Notice.Activity is {} old &&
                    activity.MemberKey != null && old.MemberKey == activity.MemberKey).ToArray()) Remove(previous);
                var activities = _visible.Where(e => e.Notice.Activity != null).ToArray();
                if (activities.Length >= 2) Remove(activities[0]);
                // Activity is ephemeral; never queue it behind business reminders.
                if (_visible.Count >= 3) return new(false, "queueFull");
                var shown = Show(notice);
                return new(shown, shown ? "submitted" : "unavailable") { DiagnosticOutcome = shown ? "windowShown" : "unavailable" };
            }
            if (_visible.Count < 3) {
                var shown = Show(notice);
                return new(shown, shown ? "submitted" : DesktopNotificationEnvironment.UserReason(_lastSuppression)) {
                    DiagnosticOutcome = shown ? "windowShown" : null
                };
            }
            if (_pending.Count >= 12) return new(false, "queueFull");
            _pending.Enqueue(notice); notice.ReportDiagnostic("queued");
            return new(true, "submitted") { DiagnosticOutcome = "queued" };
        }, DispatcherPriority.Send, token).Task.WaitAsync(token).ConfigureAwait(false);
    }

    private DesktopNotificationResult QueueDuringCelebration(DesktopNotification notice)
    {
        if (!DesktopCelebrationDeferral.Enqueue(_pending, notice, DateTimeOffset.UtcNow)) return new(false, "queueFull");
        _serialAfterCelebration = true;
        return new(true, "submitted") { DiagnosticOutcome = "queued" };
    }
    private void CelebrationChanged(bool active)
    {
        var dispatcher = _dispatcher;
        if (_disposed || dispatcher is null || dispatcher.HasShutdownStarted) return;
        // Complete hiding before Playback can show its first frame.
        if (active) dispatcher.Invoke(PauseForCelebration, DispatcherPriority.Send);
    }
    private void PauseForCelebration()
    {
        if (_celebrationPaused) return;
        _celebrationPaused = _serialAfterCelebration = true;
        foreach (var entry in _visible) entry.Window.Hide();
    }

    private bool Allowed(DesktopNotification notice)
    {
        if (notice.GameStartupHint is {} hint) {
            var game = GetForegroundWindow();
            return notice.IsCurrent() && DesktopNotificationEnvironment.CanPresentAchievement() && game != IntPtr.Zero &&
                GetWindowThreadProcessId(game, out var pid) != 0 && pid == hint.ProcessId;
        }
        var reason = notice.ExecHangar is not null
            ? DesktopNotificationEnvironment.ExecHangarSuppressionReason(_game.ReadCurrentState())
            : notice.Trade is { Compact: true }
            ? DesktopNotificationEnvironment.CompactTradeSuppressionReason(_game.ReadCurrentState())
            : notice.Trade is not null
            ? DesktopNotificationEnvironment.TradeSuppressionReason()
            : notice.Activity is not null
            ? DesktopNotificationEnvironment.PlayerActivitySuppressionReason()
            : DesktopNotificationEnvironment.SuppressionReason();
        if (reason.Length == 0) {
            var foreground = GetForegroundWindow();
            bool? appForeground = foreground == IntPtr.Zero || GetWindowThreadProcessId(foreground, out var id) == 0
                ? null : id == _parentId;
            reason = DesktopNotificationVisibility.SuppressionReason(notice,
                notice.Activity is null ? _game.ReadCurrentState() : "unknown", appForeground);
        }
        if (reason != _lastSuppression) {
            _lastSuppression = reason;
            Trace.WriteLine("desktop-notification-state: " + (reason.Length == 0 ? "allowed" : reason));
        }
        return reason.Length == 0;
    }

    private static bool IsPassive(DesktopNotification notice) =>
        notice.Activity != null || notice.ExecHangar is { Compact: true } || notice.Trade is { Compact: true } ||
        notice.GameStartupHint != null;
    private DesktopNotification PrepareTrade(DesktopNotification notice) => notice.Trade is null ? notice
        : WithTradePresentation(notice, DesktopNotificationEnvironment.CompactTradeSuppressionReason(_game.ReadCurrentState()).Length == 0);
    internal static DesktopNotification WithTradePresentation(DesktopNotification notice, bool compact) =>
        notice.Trade is {} trade ? notice with { Trade = trade with { Compact = compact } } : notice;
    private DesktopNotification PrepareHangar(DesktopNotification notice) => notice.ExecHangar is {} hangar
        ? notice with { ExecHangar = hangar with { Compact = DesktopNotificationEnvironment.CompactExecHangar(
            _game.ReadCurrentState(), DesktopNotificationEnvironment.ReadNotificationModeReason()) } }
        : notice;

    private bool Show(DesktopNotification notice)
    {
        if (_celebration.IsActive) { QueueDuringCelebration(notice); return false; }
        if (notice.PresentUntil is {} until && DateTimeOffset.UtcNow > until) { notice.ReportDiagnostic("expired"); return false; }
        if (!notice.IsCurrent()) { notice.ReportDiagnostic("expired"); return false; }
        notice = PrepareTrade(PrepareHangar(notice));
        var passive = IsPassive(notice);
        var window = new Window { Width = passive ? 368 : 380, Height = passive ? 88 : DesktopNotificationCard.PresentationHeight(notice), WindowStyle = WindowStyle.None,
            ResizeMode = ResizeMode.NoResize, ShowInTaskbar = false, ShowActivated = false,
            AllowsTransparency = true, Background = System.Windows.Media.Brushes.Transparent,
            Topmost = true, Left = -32000, Top = -32000, Title = "StarBridge notification" };
        var entry = new Entry(notice, window);
        window.ContentRendered += (_, _) => notice.ReportDiagnostic("contentRendered");
        window.Content = notice.GameStartupHint != null ? new GameStartupHintCard(notice)
            : notice.ExecHangar is { Compact: true } ? new CompactExecHangarNotificationCard(notice)
            : notice.Activity != null ? new PlayerActivityNotificationCard(notice)
            : notice.Trade is { Compact: true } ? new CompactTradeNotificationCard(notice)
            : notice.Trade is not null ? new TradeNotificationCard(notice, () => Open(entry), () => Dismiss(entry))
            : new DesktopNotificationCard(notice, () => Open(entry), () => Dismiss(entry));
        var animate = DesktopNotificationMotion.Enabled(notice.ReduceMotion);
        window.Opacity = !passive && animate ? 0 : 1;
        if (window.Content is GameStartupHintCard startup) {
            window.Width = startup.Width; window.Height = startup.Height;
            startup.Loaded += (_, _) => {
                if (_visible.Contains(entry) && notice.IsCurrent())
                    startup.BeginPresentation(animate, () => Remove(entry));
            };
        }
        else if (passive && window.Content is FrameworkElement card) {
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
            entry.Area = notice.GameStartupHint != null ? GameArea(foreground, screen.Bounds) : screen.WorkingArea;
            new WindowInteropHelper(window).EnsureHandle();
            Place(entry, entry.Area, _visible.Count - 1);
            if (!notice.IsCurrent()) { notice.ReportDiagnostic("expired"); Remove(entry); return false; }
            if (!Allowed(notice)) { notice.ReportDiagnostic(DesktopNotificationEnvironment.UserReason(_lastSuppression)); Remove(entry); return false; }
            window.Show();
            entry.LastTick = Stopwatch.GetTimestamp();
            notice.ReportDiagnostic("windowShown");
            Place(entry, entry.Area, _visible.Count - 1);
            if (!passive) DesktopNotificationMotion.Fade(window, 1, 180, animate);
            return true;
        } catch { notice.ReportDiagnostic("showFailed"); Remove(entry); return false; }
    }

    private void Place(Entry entry, System.Drawing.Rectangle area, int index)
    {
        var handle = new WindowInteropHelper(entry.Window).Handle;
        var scale = Math.Max(96, GetDpiForWindow(handle)) / 96d;
        if (entry.Window.Content is GameStartupHintCard startup) {
            var placement = GameStartupHintCard.Placement(area, GetDpiForWindow(handle), startup.VisibleWidth);
            if (!SetWindowPos(handle, new IntPtr(-1), placement.X, placement.Y, placement.Width, placement.Height, 0x10))
                entry.Notice.ReportDiagnostic("placementFailed");
            return;
        }
        var width = (int)Math.Ceiling(entry.Window.Width * scale); var height = (int)Math.Ceiling(entry.Window.Height * scale);
        var gap = (int)Math.Ceiling(12 * scale);
        var offset = _visible.Take(index).Where(other => other.Area == area && other.Notice.Position == entry.Notice.Position)
            .Sum(other => (int)Math.Ceiling(other.Window.Height * scale) + gap);
        var x = entry.Notice.Position.EndsWith("Left") ? area.Left + gap : area.Right - width - gap;
        var y = entry.Notice.Position.StartsWith("top") ? area.Top + gap + offset : area.Bottom - height - gap - offset;
        if (!SetWindowPos(handle, new IntPtr(-1), x, y, width, height, 0x10))
            entry.Notice.ReportDiagnostic("placementFailed"); // NOACTIVATE
    }

    private void Open(Entry entry)
    {
        if (IsPassive(entry.Notice)) return;
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
        if (entry.Window.Content is GameStartupHintCard) Remove(entry);
        else if (IsPassive(entry.Notice) && entry.Window.Content is UIElement card)
            DesktopNotificationMotion.ExitActivity(card, entry.Notice.Position.EndsWith("Right"), animate, () => Remove(entry));
        else
            DesktopNotificationMotion.Fade(entry.Window, 0, 120, animate, () => Remove(entry));
    }

    private void Remove(Entry entry) {
        if (!_visible.Contains(entry)) return;
        entry.Notice.ReportDiagnostic("removed");
        DesktopNotificationMotion.Cancel(entry.Window);
        if (entry.Window.Content is GameStartupHintCard startup) startup.Stop();
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
    private void ClearOnThread() {
        foreach (var notice in _pending) notice.ReportDiagnostic("cleared");
        _pending.Clear();
        foreach (var e in _visible.ToArray()) { e.Notice.ReportDiagnostic("cleared"); Remove(e); }
    }
    public void ClearMessages()
    {
        var dispatcher = _dispatcher;
        if (dispatcher == null || dispatcher.HasShutdownStarted || dispatcher.HasShutdownFinished) return;
        dispatcher.BeginInvoke(() => {
            var activities = _pending.Where(n => n.Activity != null).ToArray();
            foreach (var notice in _pending.Where(n => n.Activity == null)) notice.ReportDiagnostic("cleared");
            _pending.Clear();
            foreach (var activity in activities) _pending.Enqueue(activity);
            foreach (var entry in _visible.Where(e => e.Notice.Activity == null).ToArray()) { entry.Notice.ReportDiagnostic("cleared"); Remove(entry); }
        }, DispatcherPriority.Send);
    }
    private void Tick()
    {
        var now = Stopwatch.GetTimestamp();
        if (_celebration.IsActive) PauseForCelebration();
        if (_celebrationPaused)
        {
            foreach (var entry in _visible.ToArray())
            {
                entry.LastTick = now;
                if (!DesktopCelebrationDeferral.Current(entry.Notice, DateTimeOffset.UtcNow) || !Allowed(entry.Notice)) Remove(entry);
            }
            DesktopCelebrationDeferral.Prune(_pending, DateTimeOffset.UtcNow);
            if (_celebration.IsActive) return;
            _celebrationPaused = false;
        }
        foreach (var e in _visible.ToArray()) {
            // Restore one retained card at a time, preserving its remaining visible dwell.
            if (!e.Window.IsVisible) {
                e.LastTick = now;
                if (_visible.Any(other => other != e && other.Window.IsVisible)) continue;
                if (DesktopCelebrationDeferral.Current(e.Notice, DateTimeOffset.UtcNow) && Allowed(e.Notice)) e.Window.Show();
                else Remove(e);
                continue;
            }
            // Each card owns its display interval. Dispatcher time spent before
            // a new card was shown must not consume its visible lifetime.
            var elapsed = Stopwatch.GetElapsedTime(e.LastTick, now);
            e.LastTick = now;
            if (IsPassive(e.Notice) || !e.Window.IsMouseOver) e.Remaining -= elapsed;
            // Privacy revocation and system suppression bypass animation: never retain stale text for a fade.
            if (!e.Notice.IsCurrent()) { e.Notice.ReportDiagnostic("expired"); Remove(e); }
            else if (!Allowed(e.Notice)) { e.Notice.ReportDiagnostic(DesktopNotificationEnvironment.UserReason(_lastSuppression)); Remove(e); }
            else if (e.Remaining <= TimeSpan.Zero) { e.Notice.ReportDiagnostic("elapsed"); Dismiss(e); }
            else if (e.Notice.GameStartupHint != null) {
                var foreground = GetForegroundWindow();
                e.Area = GameArea(foreground, System.Windows.Forms.Screen.FromHandle(foreground).Bounds);
                Place(e, e.Area, 0);
            }
            else if (!e.Exiting && (e.Notice.ExecHangar is { Compact: false } && PrepareHangar(e.Notice).ExecHangar is { Compact: true } ||
                e.Notice.Trade is { Compact: false } && PrepareTrade(e.Notice).Trade is { Compact: true })) {
                // Entering a game/DND while the full card is visible also shrinks
                // it, without replaying sound or restarting its display lifetime.
                var remaining = e.Remaining; var trade = e.Notice.Trade is not null; Remove(e);
                // A trade alert keeps its own remaining lifetime; the hangar card keeps the shorter one.
                if (Show(e.Notice) && _visible.LastOrDefault() is {} replacement)
                    replacement.Remaining = trade || remaining < replacement.Remaining ? remaining : replacement.Remaining;
            }
        }
        while (DesktopCelebrationDeferral.CanDrain(_celebration, _visible.Count, _serialAfterCelebration) && _pending.TryDequeue(out var queued)) {
            var next = PrepareTrade(queued);
            if (!next.IsCurrent()) next.ReportDiagnostic("expired");
            else if (!Allowed(next)) next.ReportDiagnostic(DesktopNotificationEnvironment.UserReason(_lastSuppression));
            else Show(next);
        }
        if (_visible.Count == 0 && _pending.Count == 0) _serialAfterCelebration = false;
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
        _celebration.Changed -= CelebrationChanged;
        var dispatcher = _dispatcher;
        if (dispatcher != null && !dispatcher.HasShutdownStarted)
            dispatcher.BeginInvoke(() => { ClearOnThread(); dispatcher.BeginInvokeShutdown(DispatcherPriority.Send); }, DispatcherPriority.Send);
        if (Thread.CurrentThread != _thread) _thread.Join(TimeSpan.FromSeconds(2));
    }

    private static System.Drawing.Rectangle GameArea(IntPtr game, System.Drawing.Rectangle fallback) {
        var origin = new PointI();
        return game != IntPtr.Zero && GetClientRect(game, out var rect) && rect.Right > rect.Left && rect.Bottom > rect.Top && ClientToScreen(game, ref origin)
            ? new(origin.X, origin.Y, rect.Right - rect.Left, rect.Bottom - rect.Top) : fallback;
    }
    [StructLayout(LayoutKind.Sequential)] private struct RectI { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] private struct PointI { public int X, Y; }
    [DllImport("user32.dll")] private static extern bool GetClientRect(IntPtr hwnd, out RectI rect);
    [DllImport("user32.dll")] private static extern bool ClientToScreen(IntPtr hwnd, ref PointI point);
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

// Shared by native admission/drain and the headless notification regression.
internal static class DesktopCelebrationDeferral
{
    internal const int MaximumPending = 12;
    internal static bool CanDrain(AchievementCelebrationActivity activity, int visible, bool serial) =>
        !activity.IsActive && visible < (serial ? 1 : 3);
    internal static bool Current(DesktopNotification notice, DateTimeOffset now) =>
        notice.IsCurrent() && (notice.PresentUntil is null || now <= notice.PresentUntil);
    internal static void Prune(Queue<DesktopNotification> pending, DateTimeOffset now)
    {
        var count = pending.Count;
        for (var i = 0; i < count; i++)
        {
            var notice = pending.Dequeue();
            if (Current(notice, now)) pending.Enqueue(notice); else notice.ReportDiagnostic("expired");
        }
    }
    internal static bool Enqueue(Queue<DesktopNotification> pending, DesktopNotification notice, DateTimeOffset now)
    {
        Prune(pending, now);
        if (!Current(notice, now)) { notice.ReportDiagnostic("expired"); return false; }
        if (pending.Count >= MaximumPending) return false;
        pending.Enqueue(notice); notice.ReportDiagnostic("queued"); return true;
    }
}
