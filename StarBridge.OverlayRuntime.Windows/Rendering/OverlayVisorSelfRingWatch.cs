using System.Globalization;
using System.Text;

namespace StarBridge.Desktop;

/// <summary>
/// Running totals from the visor renderer and the window, read once per drawn frame (11-15 diagnostics, counts only).
/// RingMissing is the latest frame's own: it composed no live layer holding a ring that has a state.
/// </summary>
internal readonly record struct OverlayVisorRenderCounts(
    int Flashes = 0, int IntroFrames = 0, int LiveClears = 0, int TopmostChecks = 0, int TopmostRaised = 0, bool RingMissing = false,
    OverlayVisorRefreshTotals Refresh = default);

/// <summary>Members-scene rebuilds (NativeInformationOverlayRuntime.RefreshWindow calls) by what asked for them.</summary>
internal readonly record struct OverlayVisorRefreshTotals(int Timer = 0, int Push = 0, int Modules = 0, int Menu = 0, int Forced = 0, int Sync = 0);

/// <summary>
/// 11-15 diagnostics (counts only): running totals of the overlay runtime's RefreshWindow calls by source: the
/// game-window timer (every 750 ms while the HUD is up), a content push, a module expiry, the in-game menu, forced
/// refreshes (settings, opening), and a sync that runs the game-window rules outside the timer. One overlay runtime per process, so the totals are process-wide.
/// </summary>
internal static class OverlayVisorRefreshCounts
{
    private static int _timer, _push, _modules, _menu, _forced, _sync;
    public static void Timer() => Interlocked.Increment(ref _timer);
    public static void Push() => Interlocked.Increment(ref _push);
    public static void Modules() => Interlocked.Increment(ref _modules);
    public static void Menu() => Interlocked.Increment(ref _menu);
    public static void Forced() => Interlocked.Increment(ref _forced);
    public static void Sync() => Interlocked.Increment(ref _sync);
    public static OverlayVisorRefreshTotals Read() => new(Volatile.Read(ref _timer), Volatile.Read(ref _push), Volatile.Read(ref _modules),
        Volatile.Read(ref _menu), Volatile.Read(ref _forced), Volatile.Read(ref _sync));
}

/// <summary>
/// 11-15 user ("满血，只有圆环在闪", about twice a second while the game is in front): counts, per drawn visor frame,
/// whether the player's own health ring is drawn, how often it goes away and why, and how often it comes back within
/// a second. Counts only: no name, no health value, no image. One summary line a minute in
/// desktop-overlay-diagnostics.log, only for a minute in which the ring was drawn, went away or flashed.
/// Why it goes away (the scene):
///  - reading: the health reader sent "no reading";
///  - panel: the members group is not shown;
///  - noSelfRow: no member row is marked as the player's own;
///  - nameShared: the own row is there, but the visor looks rings up by name and another row with the same name comes
///    first, so that row's (empty) ring is drawn instead.
/// Also (11-15 overlay line and scheduler, so one test by the user tells where it comes from):
///  - flashes: the ring's loss flashes (the visor lights the whole ring once for every loss of 0.4% or more), so a
///    reading wobbling 100/99 shows up as flashes rather than as the ring going away;
///  - notComposed: frames whose scene has the ring but whose picture did not compose it (a cause in the renderer);
///  - introFrames, liveClears: frames on the opening/closing beat (no live layer then) and live layers emptied;
///  - topmostChecks, topmostRaised: the window's topmost checks (every 750 ms) and the times it really was raised;
///  - refresh.*: members-scene rebuilds by what asked for them (timer = the 750 ms game-window check);
///  - gap.*: for each time the ring went away after an earlier time, how long after it (ms buckets): the members
///    scene is rebuilt every 750 ms while the game is in front, so a 600-900 bucket points there.
/// </summary>
internal sealed class OverlayVisorSelfRingWatch
{
    public const double SummaryEverySeconds = 60;
    public const double BackWithinSeconds = 1.0;

    private readonly Action<string> _write;
    private double _windowStart = double.NaN;
    private bool? _drawn;
    private double _hiddenAt = double.NegativeInfinity;
    private int _frames, _drawnFrames, _hidden, _back, _manySelfRows, _notComposed;
    private int _gapShort, _gapMid, _gapLong;
    private int _flashes, _intro, _clears, _topChecks, _topRaised;
    private int _refTimer, _refPush, _refModules, _refMenu, _refForced, _refSync;
    private OverlayVisorRenderCounts? _lastTotals;
    private readonly Dictionary<string, int> _hiddenBy = new(StringComparer.Ordinal);

    public OverlayVisorSelfRingWatch(Action<string> write) { _write = write; }

    /// <summary>Whether the visor draws a ring for the player's own row in this scene, and if not, why.</summary>
    internal static (bool Drawn, string? Why) SelfRing(bool showTeam, IReadOnlyList<OverlayVisorMember> members, int selfRows,
        OverlayVisorVitals local)
    {
        if (local == OverlayVisorVitals.Unknown) return (false, "reading");
        if (!showTeam) return (false, "panel");
        if (selfRows < 1) return (false, "noSelfRow");
        // the renderer looks each ring up by name and takes the first member with it (OverlayVisorRenderer)
        var drawn = members.GroupBy(m => m.Name).Select(g => g.First()).Any(m => m.Vitals != OverlayVisorVitals.Unknown);
        return drawn ? (true, null) : (false, "nameShared");
    }

    /// <param name="totals">The renderer's and window's running totals (a new renderer starts again from 0).</param>
    public void Observe(double now, bool showTeam, IReadOnlyList<OverlayVisorMember> members, int selfRows, OverlayVisorVitals local,
        OverlayVisorRenderCounts totals = default)
    {
        if (!double.IsFinite(now)) return;
        if (double.IsNaN(_windowStart)) _windowStart = now;
        else if (now - _windowStart >= SummaryEverySeconds) { Flush(); Reset(now); }
        if (_lastTotals is { } last)
        {
            static int Up(int current, int before) => current >= before ? current - before : 0;
            _flashes += Up(totals.Flashes, last.Flashes);
            _intro += Up(totals.IntroFrames, last.IntroFrames);
            _clears += Up(totals.LiveClears, last.LiveClears);
            _topChecks += Up(totals.TopmostChecks, last.TopmostChecks);
            _topRaised += Up(totals.TopmostRaised, last.TopmostRaised);
            _refTimer += Up(totals.Refresh.Timer, last.Refresh.Timer);
            _refPush += Up(totals.Refresh.Push, last.Refresh.Push);
            _refModules += Up(totals.Refresh.Modules, last.Refresh.Modules);
            _refMenu += Up(totals.Refresh.Menu, last.Refresh.Menu);
            _refForced += Up(totals.Refresh.Forced, last.Refresh.Forced);
            _refSync += Up(totals.Refresh.Sync, last.Refresh.Sync);
        }
        _lastTotals = totals;
        var (drawn, why) = SelfRing(showTeam, members, selfRows, local);
        _frames++;
        if (selfRows > 1) _manySelfRows++;
        if (drawn)
        {
            _drawnFrames++;
            if (totals.RingMissing) _notComposed++;
            if (_drawn == false && now - _hiddenAt <= BackWithinSeconds + 1e-9) _back++;
        }
        else if (_drawn == true)
        {
            if (double.IsFinite(_hiddenAt))
            {
                var ms = (now - _hiddenAt) * 1000;
                if (ms < 600) _gapShort++; else if (ms <= 900) _gapMid++; else _gapLong++;
            }
            _hidden++; _hiddenAt = now;
            _hiddenBy[why!] = _hiddenBy.GetValueOrDefault(why!) + 1;
        }
        _drawn = drawn;
    }

    private void Flush()
    {
        if (_drawnFrames == 0 && _hidden == 0 && _flashes == 0) return;
        var line = new StringBuilder("visor-self-ring summary");
        line.Append(" frames=").Append(_frames).Append(" drawnFrames=").Append(_drawnFrames).Append(" notComposed=").Append(_notComposed);
        line.Append(" hidden=").Append(_hidden).Append(" backIn1s=").Append(_back);
        foreach (var why in new[] { "reading", "panel", "noSelfRow", "nameShared" })
            line.Append(" hiddenBy.").Append(why).Append('=').Append(_hiddenBy.GetValueOrDefault(why).ToString(CultureInfo.InvariantCulture));
        line.Append(" gap.under600=").Append(_gapShort).Append(" gap.600to900=").Append(_gapMid).Append(" gap.over900=").Append(_gapLong);
        line.Append(" flashes=").Append(_flashes).Append(" introFrames=").Append(_intro).Append(" liveClears=").Append(_clears);
        line.Append(" topmostChecks=").Append(_topChecks).Append(" topmostRaised=").Append(_topRaised);
        line.Append(" refresh.timer=").Append(_refTimer).Append(" refresh.push=").Append(_refPush).Append(" refresh.modules=").Append(_refModules)
            .Append(" refresh.menu=").Append(_refMenu).Append(" refresh.forced=").Append(_refForced).Append(" refresh.sync=").Append(_refSync);
        line.Append(" manySelfRows=").Append(_manySelfRows);
        try { _write(line.ToString()); } catch (Exception) { }
    }

    private void Reset(double now)
    {
        _windowStart = now;
        _frames = _drawnFrames = _hidden = _back = _manySelfRows = _notComposed = 0;
        _gapShort = _gapMid = _gapLong = 0;
        _flashes = _intro = _clears = _topChecks = _topRaised = 0;
        _refTimer = _refPush = _refModules = _refMenu = _refForced = _refSync = 0;
        _hiddenBy.Clear();
    }
}
