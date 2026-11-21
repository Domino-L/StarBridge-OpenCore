namespace StarBridge.HostRuntime.HealthReading;

// Reads the player's own health from the screen, but only while all three hold:
// the "读取自己的血量" setting is on (default off), the game is running, and the game
// window is in front (gameForeground; with "游戏在后台时也读取" on, the product passes
// "shown and not minimized" instead). The moment any of them stops holding, capture stops and every
// capture object is released; the visor then gets "no reading" and draws no ring.
//
// The screen only provides the percentage. lifeState is an optional seam for a local game-log
// life state; the product does not pass one today (the visor draws downed/dead from its own
// game-log events), so product readings are only "alive with a percentage" or "no reading".
//
// At full health the game folds the health tile away; SelfHealthFullHold decides when "no tile" still means full
// (Life: facts from the local game log, optional). Diagnostics (optional) counts what happens, without values.
internal sealed class SelfHealthReadingService : IDisposable
{
    public const double DefaultReadsPerSecond = 8;

    readonly Func<bool> _enabled, _gameRunning, _gameForeground;
    readonly Func<HudHealthModel?> _loadModel;
    readonly IHudFrameSourceFactory _sources;
    readonly Action<SelfHealthReading> _publish;
    readonly Func<SelfHealthState>? _lifeState;
    readonly TimeProvider _time;
    readonly double _readsPerSecond;
    // The reader's clock at the latest step, for diagnostics written outside a step's own arguments.
    double _now;
    readonly CancellationTokenSource _stop = new();
    readonly object _gate = new();
    // Serializes "is it stopped?" with the publish itself: once Dispose has requested the stop (under this
    // lock), no valid reading can start going out, and one already going out has finished.
    readonly object _publishGate = new();
    Thread? _thread;
    // Who frees the cancellation source: 0 = undecided, 1 = the reader finished first (Dispose frees it),
    // 2 = Dispose gave up waiting (the reader frees it when it finishes). Exactly one side frees it.
    int _cancelOwner;
    int _disposed;
    internal bool CancellationReleased { get; private set; }

    HudHealthModel? _model; bool _modelTried;
    HudHealthRecognizer? _recognizer;
    IHudFrameSource? _source;
    HudPanelFrame? _frame;
    SelfHealthReading _last = SelfHealthReading.None;
    long _nextSourceAttempt;
    double _lastFrameAt = double.NegativeInfinity;
    // No new frame (capture refused or nothing read) for this long: the visor goes back to "no reading" (no ring).
    const double StaleAfterSeconds = 2.0;

    // Idle polling interval while not capturing, and the wait after a failed start.
    internal TimeSpan IdlePoll { get; init; } = TimeSpan.FromMilliseconds(500);
    internal TimeSpan RetryAfterFailure { get; init; } = TimeSpan.FromSeconds(5);

    // Counters for tests and the delivery note.
    internal int SourcesCreated { get; private set; }
    internal int SourcesDisposed { get; private set; }
    internal bool Capturing { get { lock (_gate) return _source != null; } }
    internal bool ModelAvailable => _model != null;
    internal SelfHealthReading LastReading => _last;
    // For tests: whether the stop has been requested (Dispose requests it only between publishes).
    internal bool StopRequested => _stop.IsCancellationRequested;
    // For tests: runs when Dispose starts, before it takes the publish lock; and the recognizer in use.
    internal Action? OnDisposeEntering { get; init; }
    internal HudHealthRecognizer? Recognizer => _recognizer;

    // Where the player is and whether they are alive, from the local game log (SelfHealthLifeContext); null: unknown.
    internal Func<SelfHealthLife>? Life { get; init; }
    internal SelfHealthDiagnostics? Diagnostics { get; init; }
    // Capture sizes where clear digits were read (11-17: the new life's full shows only at such a size; null: never).
    internal SelfHealthReadableSizes? ReadableSizes { get; init; }
    // Whether the game log says the player is in a server now (review R5/R6 P1; null: not wired, taken as yes). Asked at
    // most every LogCheckSeconds, also while the game is behind; while it has said no for LogNotLiveSeconds, each check
    // ends a new life's full (the log page stopped, the log unreadable, back at the main menu: a leave line it cannot see
    // would leave the 100 there). A moment of no (the session published just after the spawn line) changes nothing, and
    // the last answer never stops a new life from beginning (review R7 P2: a join and spawn after a long main-menu wait,
    // read before the next check); if the log still says no, the next check ends it.
    internal Func<bool>? LogLive { get; init; }
    internal const double LogCheckSeconds = 0.5, LogNotLiveSeconds = 2.0;
    double _logCheckedAt = double.NegativeInfinity, _logNotLiveSince = double.NaN;
    bool _logNotLive;
    readonly SelfHealthFullHold _hold = new();
    long _lifeReset;
    // 11-17 user ("一进服就把识别器整个重置"): the "joined a server" count and life start last taken in, and whether the
    // first spawn after a join is still to come (the tile search starts afresh at both: loading screens come between).
    bool _factsSynced, _resyncOnCapture, _spawnResetPending;
    long _joinsSeen, _lifeStartSeen;
    // 11-17 (review R1 P1): clear-digit images in a row at the current capture size; two record the size as read.
    int _clearRun;
    (int Width, int Height) _lastSize;
    internal const int ClearImagesToRecordSize = 2;
    internal const float ClearUnitsDigitAt = 0.8f;
    // Whether the latest step read an image, and when (reader clock): the next read is "continuous" only right after
    // one (no gap: idle, failure, exception, stand-ins only, a stall).
    bool _readLast;
    double _readLastAt = double.NegativeInfinity;
    const double ContinuousWithinSeconds = 0.5;

    // 11-15 user (甲): a short unreadable gap keeps the last value (SelfHealthShortGap).
    readonly SelfHealthShortGap _gap = new();
    // A shown value change counts as "near full" in the diagnostics when either side is at least this (percent).
    internal const int NearFullAt = 98;

    internal SelfHealthFullHold Hold => _hold;

    public SelfHealthReadingService(Func<bool> enabled, Func<bool> gameRunning, Func<bool> gameForeground,
        Func<HudHealthModel?> loadModel, IHudFrameSourceFactory sources, Action<SelfHealthReading> publish,
        Func<SelfHealthState>? lifeState = null, TimeProvider? time = null, double readsPerSecond = DefaultReadsPerSecond)
    {
        _enabled = enabled; _gameRunning = gameRunning; _gameForeground = gameForeground;
        _loadModel = loadModel; _sources = sources; _publish = publish; _lifeState = lifeState;
        _time = time ?? TimeProvider.System;
        _readsPerSecond = Math.Clamp(readsPerSecond, 1, 30);
    }

    public void Start()
    {
        if (_thread != null) return;
        _thread = new Thread(Run) { IsBackground = true, Name = "self-health-reader", Priority = ThreadPriority.BelowNormal };
        _thread.Start();
    }

    // Only this thread touches the capture source once it runs; it releases everything on its way out.
    void Run()
    {
        var token = _stop.Token;
        var wake = token.WaitHandle;
        double interval = 1.0 / _readsPerSecond;
        var start = _time.GetTimestamp();
        try
        {
            while (!token.IsCancellationRequested)
            {
                TimeSpan wait;
                try { wait = Step(_time.GetElapsedTime(start).TotalSeconds) ? TimeSpan.FromSeconds(interval) : IdlePoll; }
                catch (Exception) { StopCapture("failed"); Publish(SelfHealthReading.None); wait = RetryAfterFailure; }
                if (wake.WaitOne(wait)) break;
            }
        }
        finally
        {
            StopCapture("stopping");
            PublishFinal(SelfHealthReading.None);
            if (Interlocked.CompareExchange(ref _cancelOwner, 1, 0) == 2) ReleaseCancellation();
        }
    }

    // One tick. True when a frame was read (keep the fast cadence), false when idle.
    internal bool Step(double nowSeconds)
    {
        _now = nowSeconds;
        var continuous = _readLast && nowSeconds - _readLastAt <= ContinuousWithinSeconds;
        _readLast = false;
        SafeDiagnostics(d => d.Tick(nowSeconds));
        // 11-17 (review R1 P2): the log facts are taken as seen when the reader starts, and again when it reads after the
        // switch was off or the game not running (a life that began meanwhile was not watched begin). Switching away
        // (not readable) keeps watching: a join and spawn while the game is behind other windows still count.
        if (!_factsSynced) SyncFacts(SafeLife());
        NoteLogLive(nowSeconds);
        var idle = !SafeBool(_enabled) ? "off" : !SafeBool(_gameRunning) ? "not-running" : !SafeBool(_gameForeground) ? "not-readable" : null;
        // At the first step with the switch on and the game running, also while it is behind other windows (review R2
        // P2: a join and spawn after the switch came on with the game behind still count).
        if (_resyncOnCapture && idle is null or "not-readable") { _resyncOnCapture = false; SyncFacts(SafeLife()); }
        if (idle != null)
        {
            // Switching away keeps the "last reading was full" memory (health events in the gap still end it, see
            // the hold); the switch going off or the game closing ends it.
            if (idle != "not-readable") { _hold.Forget(SafeLife()); _resyncOnCapture = true; }
            StopCapture(idle); Publish(SelfHealthReading.None); return false;
        }
        if (!_modelTried) { _modelTried = true; try { _model = _loadModel(); } catch (Exception) { _model = null; } }
        if (_stop.IsCancellationRequested) return false;
        if (_model == null) { SafeDiagnostics(d => d.Idle(nowSeconds, "no-model")); Publish(SelfHealthReading.None); return false; }
        IHudFrameSource? source;
        lock (_gate)
        {
            if (_source == null)
            {
                if (Environment.TickCount64 < _nextSourceAttempt) { source = null; }
                else
                {
                    _source = _sources.TryCreate();
                    if (_source == null) _nextSourceAttempt = Environment.TickCount64 + (long)RetryAfterFailure.TotalMilliseconds;
                    else
                    {
                        SourcesCreated++; _recognizer ??= new HudHealthRecognizer(_model); _frame ??= new HudPanelFrame();
                        SafeDiagnostics(d => d.CaptureStarted(nowSeconds));
                    }
                }
            }
            source = _source;
        }
        if (_stop.IsCancellationRequested) { StopCapture("stopping"); return false; }
        if (source == null) { SafeDiagnostics(d => d.Idle(nowSeconds, "no-source")); Publish(SelfHealthReading.None); return false; }
        var started = System.Diagnostics.Stopwatch.GetTimestamp();
        bool captured = source.TryCapture(_frame!);
        // A capture can block; if the reader was stopped meanwhile, nothing it read may be published.
        if (_stop.IsCancellationRequested) return false;
        // No ring now, even without a new image, once the log says the player left or died (review round 6 P2), or
        // once any health event has come that is not taken in yet (it may end "full"; review round 9 P2). The events
        // themselves are taken in with the next new image.
        var lifeEarly = SafeLife();
        var goneNow = lifeEarly.Presence == SelfHealthPresence.Away || lifeEarly.Dead || lifeEarly.Revision != _hold.Revision;
        if (!captured)
        {
            // The captured window is no longer the one to read: release it; the next tick captures the current one.
            if (SafeLost(source)) { StopCapture("lost"); Publish(SelfHealthReading.None); return false; }
            // The picture changed size (the capture rebuilds and skips images): no ring until a new image is read
            // (review R4 P1: not 2 s of the old ring over a black screen).
            var resized = SelfHealthReadableSizes.Valid(_lastSize) && SafeSize(source) != _lastSize;
            if (goneNow || resized || nowSeconds - _lastFrameAt > StaleAfterSeconds) Publish(SelfHealthReading.None);
            return true;
        }
        // A stand-in copy of an earlier image is not read at all: it could be from before a death or respawn, and it
        // must not feed the recognizer's smoothing (review round 4 P1). The ring keeps its value; with no new image
        // for over 2 seconds it goes.
        var fresh = SafeNew(source);
        if (!fresh)
        {
            if (goneNow || nowSeconds - _lastFrameAt > StaleAfterSeconds) Publish(SelfHealthReading.None);
            return true;
        }
        _lastFrameAt = nowSeconds;
        // 11-17: the picture size first (review R2 P2: a new size restarts the tile search before this image is read).
        var size = SafeSize(source);
        NoteSize(size);
        var lifeFacts = SafeLife();
        // 11-17 user: joining a server starts the tile search afresh (tile position, confirmed position, digit scale),
        // as the switch going off and on does; the first spawn after it does again, as loading screens come in between
        // (b100: a tile found but never read after loading until the switch went off and on). A respawn alone keeps
        // them (below).
        if (lifeFacts.Joins != _joinsSeen)
        {
            // A spawn taken in with the join (one batch) is covered by this one restart (review R1 P2): only when the
            // player is in the universe now (also if downed or dead since; review R3 P2); a life start from the previous
            // server (a respawn there, then leaving and joining) leaves the spawn still to come (review R2 P2).
            _joinsSeen = lifeFacts.Joins;
            _spawnResetPending = !(lifeFacts.LifeStart != _lifeStartSeen && lifeFacts.Presence == SelfHealthPresence.InUniverse);
            RestartTileSearch();
        }
        else if (_spawnResetPending && lifeFacts.LifeStart != _lifeStartSeen)
        {
            _spawnResetPending = false;
            RestartTileSearch();
        }
        _lifeStartSeen = lifeFacts.LifeStart;
        // A log event that ends a full reading (spawn, death, downed, revived, server change) also drops the recognizer's
        // own estimate, so nothing from before it carries over (review P1). The tile position and the digit scale stay:
        // the HUD layout does not change with a new life (11-14: the confirmed tile position guards against reading a
        // neighbouring tile right after a death).
        if (lifeFacts.Revision != _lifeReset)
        {
            _lifeReset = lifeFacts.Revision;
            _gap.Clear();
            var pending = _recognizer!.Filter.BigDropPending;
            _recognizer.ResetEstimate();
            if (pending) SafeDiagnostics(d => d.Guards(false, false, false, true));
        }
        var sample = _recognizer!.Process(_frame!, nowSeconds, _readsPerSecond);
        var tileFound = sample.State is not ("black" or "not_found");
        // 11-17: where clear digits have been read, by picture size (the new life's full needs one at this size).
        NoteDigits(sample, size);
        var readableHere = SafeReadableAt(size);
        var shown = _hold.Next(sample.FoldedFull ? null : sample.Display, sample.Evidence, tileFound, sample.State == "black", fresh,
            sample.FrameDigits, lifeFacts, nowSeconds, continuous, sample.FrameRing, readableHere);
        (shown, var kept) = _gap.Next(shown, _hold.Last, _hold.Injured, nowSeconds, _hold.DropKept);
        _readLast = true; _readLastAt = nowSeconds;
        var milliseconds = System.Diagnostics.Stopwatch.GetElapsedTime(started).TotalMilliseconds;
        var waitingForSize = _hold.NewLifeWaitingForSize;
        SafeDiagnostics(d => d.Read(nowSeconds, fresh, sample.State, sample.Evidence && sample.Display.HasValue, _hold.Last, milliseconds, kept,
            waitingForSize));
        SafeDiagnostics(d => d.Guards(sample.OffHomeRejected, sample.BigDropStarted, sample.BigDropShown, sample.BigDropAbandoned));
        var life = _lifeState?.Invoke() ?? SelfHealthState.Unknown;
        var state = life is SelfHealthState.Downed or SelfHealthState.Dead ? life
            : shown.HasValue ? SelfHealthState.Normal : SelfHealthState.Unknown;
        int? percent = life == SelfHealthState.Dead ? 0 : shown;
        Publish(new SelfHealthReading(percent, state, _time.GetUtcNow()));
        return true;
    }

    void Publish(SelfHealthReading reading)
    {
        // Once stopped, only the final "no reading" goes out (PublishFinal).
        lock (_publishGate)
        {
            if (_stop.IsCancellationRequested) return;
            PublishLocked(reading);
        }
    }

    void PublishFinal(SelfHealthReading reading)
    {
        lock (_publishGate) PublishLocked(reading);
    }

    void PublishLocked(SelfHealthReading reading)
    {
        // Only changes go out; the visor keeps the last value until told otherwise.
        if (reading.SameValueAs(_last)) return;
        var before = _last.ToVisor();
        var after = reading.ToVisor();
        var wasShown = before.Kind != SelfHealthVisorKind.Unknown;
        var nowShown = after.Kind != SelfHealthVisorKind.Unknown;
        _last = reading;
        // how often the ring the visor is sent goes away and comes back, and how often a shown value goes down (the
        // visor flashes the ring once for every loss of 0.4% or more, so a reading wobbling 100 -> 99 -> 100 would
        // flash it each time; 11-15 overlay line). Counts only.
        var now = _now;
        if (wasShown != nowShown) SafeDiagnostics(d => d.Ring(now, nowShown));
        else if (before.Kind == SelfHealthVisorKind.Alive && after.Kind == SelfHealthVisorKind.Alive && after.Health != before.Health)
        {
            // 11-15 scheduler: changes near full (either value 98 or more), e.g. a 100/99 wobble
            var nearFull = Math.Max(before.Health, after.Health) >= NearFullAt / 100f - 1e-6f;
            var drop = after.Health < before.Health;
            SafeDiagnostics(d => d.RingChange(drop, nearFull));
        }
        try { _publish(reading); } catch (Exception) { }
    }

    // reason: for the diagnostics line (off, not-running, not-readable, lost, failed, stopping).
    void StopCapture(string reason)
    {
        IHudFrameSource? source;
        lock (_gate) { source = _source; _source = null; }
        var now = _now;
        if (source == null) { SafeDiagnostics(d => d.Idle(now, reason)); return; }
        try { source.Dispose(); } catch (Exception) { }
        SourcesDisposed++;
        SafeDiagnostics(d => d.CaptureStopped(now, reason));
        // Next start begins afresh: estimate, icon position and the digit-scale average (the HUD scale may have changed).
        // A big drop still being confirmed is counted as dropped (review P3).
        if (_recognizer?.Filter.BigDropPending == true) SafeDiagnostics(d => d.Guards(false, false, false, true));
        _recognizer?.Reset();
        _lastFrameAt = double.NegativeInfinity;
        _gap.Clear();
        // clear images must come in a row within one capture (review R2 P3)
        _clearRun = 0;
    }

    // The log facts as they are now are taken as seen (11-17; review R1 P2): a life that began before was not watched;
    // a reader that starts while the player is loading after a join still restarts the tile search at the spawn.
    void SyncFacts(SelfHealthLife life)
    {
        _factsSynced = true;
        _hold.Forget(life);
        _joinsSeen = life.Joins; _lifeStartSeen = life.LifeStart;
        _spawnResetPending = life.Presence == SelfHealthPresence.Away;
    }

    // "Read clearly" (11-17; review R1 P1, R2 P1): a value of 1 to 100 whose three digit places were all cut from the
    // image (none off the edge) and read with confidence (a leading blank too), and the network's own digits agree with
    // the value the filter took for the image. A percent sign with no digit, or only the units place, is not.
    internal static bool ClearDigitImage(HudHealthSample s) =>
        s.State != "black" && s.FrameDigits is int digits and >= 1 and <= 100 && s.CnnRaw == digits
        && s.Probs is { Length: 3 } probs && probs.All(place => place is { Length: > 0 } && place.Max() >= ClearUnitsDigitAt);

    // A new picture size (11-17; review R1/R2 P2): the tile search starts afresh (the tile position and digit scale
    // follow the size), the clear-image run starts again and nothing is kept over a short gap from the old size. The
    // first size a reader sees is no change. Called on the reader thread before the image is read.
    internal void NoteSize((int Width, int Height) size)
    {
        if (size == _lastSize) return;
        var resized = SelfHealthReadableSizes.Valid(_lastSize);
        _lastSize = size; _clearRun = 0; _gap.Clear();
        if (resized) RestartTileSearch();
    }

    // Two images in a row read clearly at this size record it (review R1 P1). Called on the reader thread.
    internal void NoteDigits(HudHealthSample sample, (int Width, int Height) size)
    {
        _clearRun = ClearDigitImage(sample) ? _clearRun + 1 : 0;
        if (_clearRun >= ClearImagesToRecordSize) SafeReadable(r => r.Add(size));
    }

    // The tile search starts afresh (11-17: a server join and the first spawn after it). Called on the reader thread.
    void RestartTileSearch()
    {
        if (_recognizer?.Filter.BigDropPending == true) SafeDiagnostics(d => d.Guards(false, false, false, true));
        _recognizer?.Reset();
        _gap.Clear();
        SafeDiagnostics(d => d.TileSearchRestarted());
    }

    static bool SafeBool(Func<bool> f) { try { return f(); } catch (Exception) { return false; } }
    // Every step, also idle ones (review R6 P1: the log stopped and resumed while the game was behind).
    void NoteLogLive(double now)
    {
        if (LogLive is not { } live || now - _logCheckedAt < LogCheckSeconds) return;
        _logCheckedAt = now;
        if (SafeBool(live)) { _logNotLiveSince = double.NaN; _logNotLive = false; return; }
        if (double.IsNaN(_logNotLiveSince)) _logNotLiveSince = now;
        if (now - _logNotLiveSince < LogNotLiveSeconds - 1e-9) return;
        _logNotLive = true;
        if (_hold.NewLife) { _hold.EndNewLife(); _gap.Clear(); }
    }
    static (int Width, int Height) SafeSize(IHudFrameSource s) { try { return s.CaptureSize; } catch (Exception) { return (0, 0); } }
    void SafeReadable(Action<SelfHealthReadableSizes> use) { if (ReadableSizes is { } r) try { use(r); } catch (Exception) { } }
    bool SafeReadableAt((int Width, int Height) size)
    {
        try { return ReadableSizes?.Contains(size) == true; } catch (Exception) { return false; }
    }
    SelfHealthLife SafeLife() { try { return Life?.Invoke() ?? SelfHealthLife.Unknown; } catch (Exception) { return SelfHealthLife.Unknown; } }
    void SafeDiagnostics(Action<SelfHealthDiagnostics> use) { if (Diagnostics is { } d) try { use(d); } catch (Exception) { } }
    // A source that cannot say counts as lost (start afresh) and its image as not new (the 2-second rule holds).
    static bool SafeLost(IHudFrameSource s) { try { return s.TargetLost; } catch (Exception) { return true; } }
    static bool SafeNew(IHudFrameSource s) { try { return s.LastFrameWasNew; } catch (Exception) { return false; } }

    // Stops the reader. With a running thread, only that thread releases the capture source (in its
    // finally); if it does not finish within the wait (a driver call blocking), it still releases
    // everything when that call returns, and the cancellation source is left for it rather than freed here.
    public void Dispose()
    {
        if (Interlocked.Exchange(ref _disposed, 1) != 0) return;
        OnDisposeEntering?.Invoke();
        // Under the publish lock: after this no valid reading is published. The thread is joined outside it.
        lock (_publishGate) _stop.Cancel();
        if (_thread == null) { StopCapture("stopping"); PublishFinal(SelfHealthReading.None); ReleaseCancellation(); return; }
        if (_thread != Thread.CurrentThread && _thread.Join(TimeSpan.FromSeconds(3)))
        {
            // The reader finished (its finally ran); it set the owner to 1 and left the source to us.
            ReleaseCancellation();
            return;
        }
        // Still running (blocked call, or Dispose called from the reader itself): hand the source over.
        if (Interlocked.CompareExchange(ref _cancelOwner, 2, 0) == 1) ReleaseCancellation();
    }

    void ReleaseCancellation()
    {
        _stop.Dispose();
        CancellationReleased = true;
    }

    // For tests: the reader thread has finished (and so has released everything).
    internal bool Stopped => _thread == null || !_thread.IsAlive;
}

// 11-15 user (甲, "满血，只有圆环在闪"): one image whose tile is unreadable, or with no tile and no full memory, must not
// take the ring away for a single frame. The last value shown stays up to KeepSeconds after it was last really shown
// (kept images never extend it); longer than that, the ring goes. A black screen, leaving or dying, a health event in
// the log, switching away or off, and a stop clear it at once (the hold's outcome is not TileUnread/NoTile then, or the
// reader calls Clear). A full value is never kept over an image under the injured lock: the hold refuses full there
// with TileUnread too, and keeping 100 would bring back the full ring it refused (review CX-HUD-RINGFLICKER-073-R1 P1).
// Time running backwards keeps nothing. Accepted cost (user): right after a hit at full health, while the tile is
// still unread, the ring may read 100 for up to KeepSeconds.
internal sealed class SelfHealthShortGap
{
    public const double KeepSeconds = 0.6;
    int? _value;
    double _at = double.NegativeInfinity;

    public void Clear() => _value = null;

    // shown: what the hold returned for this image; outcome: why; injured: the hold's injured lock after this image;
    // drop: the hold dropped a value on purpose (review R5 P1): nothing is kept, and the last value is forgotten.
    public (int? Shown, bool Kept) Next(int? shown, SelfHealthHoldOutcome outcome, bool injured, double now, bool drop = false)
    {
        if (shown is int value) { _value = value; _at = now; return (value, false); }
        if (drop) { _value = null; return (null, false); }
        var since = now - _at;
        if (_value is int last && outcome is SelfHealthHoldOutcome.TileUnread or SelfHealthHoldOutcome.NoTile
            && since >= 0 && since <= KeepSeconds + 1e-9 && !(injured && last >= SelfHealthFullHold.FullAt))
            return (last, true);
        _value = null;
        return (null, false);
    }
}
