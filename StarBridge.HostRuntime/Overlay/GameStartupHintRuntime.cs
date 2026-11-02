namespace StarBridge.HostRuntime.Overlay;

using StarBridge.HostRuntime.Notifications;

public sealed record MenuShortcutHintGrant(string Binding, Func<bool> IsCurrent);
public sealed record GameStartupSession(string State, int ProcessId = 0);

/// <summary>One silent shortcut hint per observed game launch. Not a gameplay/identity reader.</summary>
public sealed class GameStartupHintRuntime : IDisposable
{
    private readonly Func<GameStartupSession> _game;
    private readonly Func<MenuShortcutHintGrant?> _shortcut;
    private readonly IDesktopNotificationSink _sink;
    private readonly Func<(string Locale, string Appearance, bool ReduceMotion)> _presentation;
    private readonly Func<DateTimeOffset> _now;
    private readonly HashSet<int> _shown = [];
    private int _pending;
    private DateTimeOffset _detected;
    private volatile bool _disposed;
    public GameStartupHintRuntime(Func<GameStartupSession> game, Func<MenuShortcutHintGrant?> shortcut,
        IDesktopNotificationSink sink, Func<(string Locale, string Appearance, bool ReduceMotion)> presentation,
        Func<DateTimeOffset>? now = null)
    { _game = game; _shortcut = shortcut; _sink = sink; _presentation = presentation; _now = now ?? (() => DateTimeOffset.UtcNow); }
    public async Task TickAsync(CancellationToken token = default)
    {
        if (_disposed) return;
        var session = _game();
        if (session.State == "notRunning") { _pending = 0; _shown.Clear(); return; }
        if (session.State != "running" || session.ProcessId <= 0) return;
        if (_shown.Contains(session.ProcessId)) return;
        if (_pending != session.ProcessId) { _pending = session.ProcessId; _detected = _now(); }
        if (_now() < _detected || _now() - _detected > TimeSpan.FromMinutes(5)) return;
        var grant = _shortcut();
        if (grant is null || !grant.IsCurrent()) return;
        var pid = session.ProcessId;
        bool Current() => !_disposed && grant.IsCurrent() && _game() is { State: "running" } current && current.ProcessId == pid;
        var view = _presentation();
        var notice = new DesktopNotification(Guid.NewGuid(), false, 0, 0, "fullContent", "topRight",
            view.Locale, view.Appearance, Current, view.ReduceMotion, BackgroundOnly: false,
            GameStartupHint: new(grant.Binding, pid)) { PresentUntil = _now().AddSeconds(8) };
        if (await _sink.TryPresentAsync(notice, token) && Current()) _shown.Add(pid);
        // Bound this observer even if transient unknown states hide many successive launches.
        if (_shown.Count > 16) { _shown.Clear(); _shown.Add(pid); }
    }
    public void Dispose() => _disposed = true;
}

public sealed class GameStartupHintDriver : IDisposable
{
    private readonly CancellationTokenSource _stop = new();
    private readonly Task _work;
    public GameStartupHintDriver(GameStartupHintRuntime runtime) => _work = Run(runtime);
    private async Task Run(GameStartupHintRuntime runtime)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromSeconds(1));
        try { while (await timer.WaitForNextTickAsync(_stop.Token)) { try { await runtime.TickAsync(_stop.Token); } catch (Exception) when (!_stop.IsCancellationRequested) { } } }
        catch (OperationCanceledException) when (_stop.IsCancellationRequested) { }
    }
    public void Dispose() { _stop.Cancel(); _ = _work.ContinueWith(_ => _stop.Dispose(), TaskScheduler.Default); }
}
