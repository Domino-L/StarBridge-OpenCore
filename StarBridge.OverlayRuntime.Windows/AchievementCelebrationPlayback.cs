namespace StarBridge.OverlayRuntime.Windows;

using StarBridge.HostRuntime.Achievements;

// The schedule is independent of HWNDs so desktop transitions can be replayed
// without opening a window, producing sound or manufacturing cloud awards.
internal interface IAchievementCelebrationSurface : IDisposable
{
    double LifetimeMilliseconds { get; }
    bool IsVisible { get; }
    void Show();
    void Hide();
    void Advance(double elapsed, int remaining);
    void UpdatePosition();
}

internal sealed class AchievementCelebrationPlayback(
    Func<AchievementCelebration, IAchievementCelebrationSurface?> create,
    Func<bool> allowed, Func<Func<bool>, bool> play, Action stop,
    AchievementCelebrationActivity? activity = null) : IDisposable
{
    private readonly LinkedList<AchievementCelebration> _pending = new();
    private IAchievementCelebrationSurface? _surface;
    private AchievementCelebration? _notice;
    private double _elapsed, _gap;
    private bool _disposed;
    private bool _protectedGap;
    private readonly HashSet<string> _receipts = new(StringComparer.Ordinal);
    internal bool HasActive => _surface is not null;
    internal void Submit(AchievementCelebration notice) => SubmitCore(notice, accepted: false);
    // Native's synchronous boundary has already durably accepted this single
    // admission before posting it to the STA. Never cache acceptance on a notice.
    internal void SubmitAccepted(AchievementCelebration notice) => SubmitCore(notice, accepted: true);
    private void SubmitCore(AchievementCelebration notice, bool accepted)
    {
        if (_disposed || !notice.CanPresent || !notice.IsCurrent()) return;
        if (!accepted && !notice.TryAcceptReceipt()) return;
        if (notice.Receipt is { } receipt && !_receipts.Add(receipt)) return;
        _pending.AddLast(notice);
    }
    internal void Advance(double delta)
    {
        if (_disposed) return;
        try { AdvanceCore(double.IsFinite(delta) ? Math.Max(0, delta) : 0); }
        catch
        {
            // A transient HWND failure does not consume a trusted earned receipt.
            var interrupted = _notice;
            try { Remove(); }
            finally
            {
                if (interrupted is not null && interrupted.IsCurrent() && _pending.First?.Value != interrupted)
                    _pending.AddFirst(interrupted);
                _protectedGap = false; _gap = 250;
            }
        }
        finally { activity?.Report(_surface is not null || _protectedGap && _pending.Any(p => p.IsCurrent())); }
    }
    private void AdvanceCore(double delta)
    {
        if (_notice is not null && !_notice.IsCurrent()) Remove();
        while (_pending.First is { } retired && !retired.Value.IsCurrent()) _pending.RemoveFirst();
        if (delta > 1000)
        {
            // The dispatcher may have slept without observing the lock transition.
            // Do not charge time nobody could read against the remaining display.
            Pause(); return;
        }
        if (_surface is not null)
        {
            if (!allowed()) { Pause(); return; }
            if (!_surface.IsVisible)
            {
                var restartEntrance = _elapsed < 1650;
                if (restartEntrance) _elapsed = 0;
                _surface.UpdatePosition();
                _surface.Advance(_elapsed, _pending.Count);
                _surface.Show();
                if (restartEntrance) Play();
                return; // Do not count the unlocking interval as visible dwell.
            }
            _elapsed += delta;
            _surface.Advance(_elapsed, _pending.Count);
            _surface.UpdatePosition();
            if (_elapsed >= _surface.LifetimeMilliseconds) { Remove(); _gap = 220; _protectedGap = true; }
            return;
        }
        if (!allowed() || (_gap = Math.Max(0, _gap - delta)) > 0) return;
        while (_pending.First is { } first)
        {
            var next = first.Value;
            if (!next.IsCurrent()) { _pending.RemoveFirst(); continue; }
            var surface = create(next);
            if (surface is null) { _protectedGap = false; _gap = 250; return; }
            if (!next.IsCurrent() || !allowed()) { _protectedGap = false; surface.Dispose(); return; }
            _surface = surface; _notice = next; _elapsed = 0;
            _protectedGap = false; activity?.Report(true);
            surface.Advance(0, _pending.Count - 1); surface.Show();
            _pending.RemoveFirst(); // Commit only after presentation actually started.
            Play();
            break;
        }
    }
    private void Play()
    {
        var notice = _notice;
        play(() => !_disposed && notice is not null && notice.IsCurrent() && allowed());
    }
    private void Pause()
    {
        if (_surface?.IsVisible != true) return;
        _surface.Hide(); stop();
    }
    private void Remove()
    {
        var surface = _surface;
        _surface = null; _notice = null;
        if (surface is not null)
        {
            try { surface.Dispose(); } catch { /* Cleanup cannot consume the trusted receipt. */ }
            finally { try { stop(); } catch { /* Release visual ownership even if the output failed. */ } }
        }
    }
    internal void Clear()
    {
        try { _pending.Clear(); _receipts.Clear(); Remove(); }
        finally { _gap = 0; _protectedGap = false; activity?.Report(false); }
    }
    public void Dispose() { if (_disposed) return; _disposed = true; try { Clear(); } finally { activity?.Report(false); } }
}
