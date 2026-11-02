using StarBridge.Core.Tools;
using System.Text.Json;
using StarBridge.HostRuntime.Presence;

namespace StarBridge.HostRuntime.Tools;

public sealed record ExecHangarSnapshot(int SchemaVersion, int Revision, ExecHangarReminders Reminders,
    ExecHangarConfig? Config, DateTimeOffset? FetchedAt, DateTimeOffset Now, bool Reliable, bool RefreshFailed,
    string DeliveryState, IReadOnlyList<ExecHangarPhase> Phases, IReadOnlyList<ExecHangarWindow> Windows,
    ExecHangarMonitoring? Monitoring = null, ExecHangarPlan? Plan = null,
    string MonitoringSource = "none", string GameMonitoringState = "disabled");
public sealed class ExecHangarConflictException : Exception;
public sealed record ExecHangarDelivery(IReadOnlyList<ExecHangarNotice> Notices, Func<bool> IsCurrent,
    ExecHangarConfig? Config = null, DateTimeOffset? MonitoringEndsAt = null, Action? Mute = null, bool Test = false);

/// <summary>Host-owned schedule, cache and durable deduplication. Page lifetimes cannot stop it.</summary>
public sealed class ExecHangarRuntime : IDisposable
{
    public static readonly TimeSpan MaxConfigAge = TimeSpan.FromHours(6);
    private readonly ExecHangarStore _store;
    private readonly IExecHangarConfigClient _client;
    private readonly Func<ExecHangarDelivery, CancellationToken, ValueTask<string>> _deliver;
    private readonly TimeProvider _time;
    private readonly Func<GameProcessSession> _game;
    private readonly Lifecycle.DeviceNetworkAdmission? _network;
    private readonly SemaphoreSlim _gate = new(1);
    private readonly CancellationTokenSource _stop = new();
    private ExecHangarDocument? _document;
    private DateTimeOffset? _previous, _lastAttempt;
    private long? _previousTick;
    private long _epoch;
    private bool _refreshFailed;
    private string _deliveryState = "idle";
    private string _gameState = "unknown";
    private bool _autoActive;
    private ExecHangarNotice? _gamePendingStart;
    public ExecHangarRuntime(string dataRoot, IExecHangarConfigClient client,
        Func<ExecHangarDelivery, CancellationToken, ValueTask<string>> deliver, TimeProvider? time = null,
        Func<GameProcessSession>? game = null, Lifecycle.DeviceNetworkAdmission? network = null)
    { _store = new(dataRoot); _client = client; _deliver = deliver; _time = time ?? TimeProvider.System; _game = game ?? (() => new("unknown")); _network = network; }
    private ExecHangarDocument Document => _document ??= _store.Read();
    private bool Reliable(DateTimeOffset now) => Document.Config is { Stale: false } && Document.FetchedAt is {} fetched &&
        now >= fetched && now - fetched <= MaxConfigAge;
    private bool ManualActive(DateTimeOffset now) => Document.Reminders!.Enabled && (Document.Monitoring?.Active(now) ?? true);
    private bool GameActive(DateTimeOffset now) => Document.Reminders!.AutoDuringGame && Document.Reminders.HasRules &&
        !ManualActive(now) && _gameState == "running" && Document.GameMonitoring is { Paused: false };
    private void ObserveGame(ExecHangarDocument? update = null)
    {
        var now = _time.GetUtcNow(); var before = _gameState;
        var document = update ?? Document;
        GameProcessSession observed;
        try { observed = document.Reminders!.AutoDuringGame ? _game() : new("notRunning"); }
        catch { observed = new("unknown"); }
        _gameState = observed.State == "running" && !string.IsNullOrWhiteSpace(observed.SessionId) && observed.SessionId.Length <= 100 &&
            !observed.SessionId.Any(char.IsControl) ? "running" : observed.State == "notRunning" ? "notRunning" : "unknown";
        var watch = document.Reminders!.AutoDuringGame
            ? ExecHangarGameMonitoring.Observe(document.GameMonitoring, _gameState, observed.SessionId, now) : null;
        if (update is not null || (!ManualActive(now) || _autoActive) &&
            (watch != Document.GameMonitoring || before != _gameState)) {
            Interlocked.Increment(ref _epoch); _previous = null;
        }
        if (update is not null || watch != Document.GameMonitoring) {
            var next = document with { GameMonitoring = watch }; _store.Write(next); _document = next;
        }
        var active = GameActive(now);
        if (active && !_autoActive && Reliable(now)) {
            var schedule = new ExecHangarSchedule(Document.Config!);
            var interval = new ExecHangarMonitoring(watch!.Id, now, now.AddDays(2), false, MutedBoundary: watch.MutedBoundary);
            _gamePendingStart = ExecHangarMonitor.Immediate(schedule, now, Document.Reminders! with { Enabled = true }, interval);
        }
        if (active != _autoActive) { Interlocked.Increment(ref _epoch); _previous = null; }
        _autoActive = active;
        if (!active) _gamePendingStart = null;
    }
    private string Receipt(ExecHangarNotice notice, bool game) => game
        ? $"{Document.GameMonitoring!.Id:N}:game:{notice.Key}" : ExecHangarMonitor.Receipt(notice, Document.Monitoring);
    private async Task RefreshAsync(bool force, CancellationToken token)
    {
        var now = _time.GetUtcNow();
        if (!force && Document.FetchedAt is {} fetched && now >= fetched && now - fetched < TimeSpan.FromHours(1)) return;
        if (!force && _lastAttempt is {} attempt && now >= attempt && now - attempt < TimeSpan.FromMinutes(5)) return;
        using var networkWork = _network?.Enter(token);
        if (_network is not null && networkWork is null) return; // Retain the saved schedule and reminders offline.
        _lastAttempt = now;
        try {
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token, _stop.Token, networkWork?.Token ?? CancellationToken.None);
            deadline.CancelAfter(TimeSpan.FromSeconds(8));
            var config = await _client.FetchAsync(deadline.Token);
            networkWork?.RequireCurrent();
            config.Validate(); token.ThrowIfCancellationRequested(); _stop.Token.ThrowIfCancellationRequested();
            var changed = config != Document.Config;
            var watch = Document.Monitoring;
            if (changed && watch is { OnlyNext: true } && watch.Active(now))
                watch = watch with { Target = new ExecHangarSchedule(config).Notices(now, watch.StartedAt.AddDays(2), Document.Reminders!)
                    .Where(n => n.Boundary != watch.MutedBoundary).OrderBy(n => n.Boundary).FirstOrDefault()?.Boundary };
            var next = Document with { Config = config, FetchedAt = _time.GetUtcNow(), Monitoring = watch,
                PendingStart = changed ? null : Document.PendingStart };
            networkWork?.RequireCurrent();
            _store.Write(next); _document = next; _refreshFailed = false;
            if (changed) { Interlocked.Increment(ref _epoch); _previous = null; _autoActive = false; _gamePendingStart = null; }
        } catch (Exception e) when (e is HttpRequestException or JsonException or InvalidDataException or ArgumentException or
            InvalidOperationException or KeyNotFoundException or FormatException or OverflowException or OperationCanceledException) {
            token.ThrowIfCancellationRequested(); _stop.Token.ThrowIfCancellationRequested(); _refreshFailed = true;
        }
    }
    private ExecHangarSnapshot Snapshot()
    {
        var now = _time.GetUtcNow(); var schedule = Document.Config is {} config ? new ExecHangarSchedule(config) : null;
        var game = GameActive(now);
        var gameReceiptPrefix = game ? $"{Document.GameMonitoring!.Id:N}:game:" : "";
        var rules = game ? Document.Reminders! with { Enabled = true } : Document.Reminders!;
        var plan = schedule is null ? null : ExecHangarMonitor.Plan(schedule, now, rules, game ? null : Document.Monitoring,
            game ? Document.Receipts!.Where(key => key.StartsWith(gameReceiptPrefix, StringComparison.Ordinal))
                .Select(key => key[gameReceiptPrefix.Length..]).ToArray() : Document.Receipts!, game ? Document.GameMonitoring!.MutedBoundary : Document.LegacyMutedBoundary);
        if (game && plan is not null) plan = plan with { StartedAt = Document.GameMonitoring!.StartedAt };
        var gameStatus = !Document.Reminders!.AutoDuringGame ? "disabled" : _gameState == "unknown" ? "unknown" :
            Document.GameMonitoring is { Paused: true } ? "paused" : !Document.Reminders.HasRules ? "noRules" :
            _gameState == "running" ? "watching" : "waiting";
        return new(1, Document.Revision, Document.Reminders!, Document.Config, Document.FetchedAt, now,
            Reliable(now), _refreshFailed, _deliveryState, schedule?.Phases(now) ?? [], schedule?.Windows(now) ?? [],
            Document.Monitoring, plan, game ? "game" : ManualActive(now) ? "manual" : "none", gameStatus);
    }
    public async Task<ExecHangarSnapshot> ReadAsync(bool refresh = false, CancellationToken token = default)
    {
        await _gate.WaitAsync(token);
        try { _stop.Token.ThrowIfCancellationRequested(); await RefreshAsync(refresh, token); ObserveGame(); return Snapshot(); }
        finally { _gate.Release(); }
    }
    public async Task<ExecHangarSnapshot> SaveAsync(ExecHangarReminders reminders, int expectedRevision,
        Func<bool> canCommit, CancellationToken token = default)
    {
        reminders.Validate(); await _gate.WaitAsync(token);
        try {
            token.ThrowIfCancellationRequested(); _stop.Token.ThrowIfCancellationRequested();
            if (!canCommit()) throw new OperationCanceledException();
            if (expectedRevision != Document.Revision) throw new ExecHangarConflictException();
            var now = _time.GetUtcNow();
            var manual = ManualActive(now); var game = GameActive(now);
            var gameId = Document.GameMonitoring?.Id;
            var previous = _previous; var previousTick = _previousTick;
            var watch = Document.Monitoring;
            if (watch is { OnlyNext: true } && watch.Active(_time.GetUtcNow()) && Document.Config is {} calibration)
                watch = watch with { Target = new ExecHangarSchedule(calibration).Notices(_time.GetUtcNow(), watch.StartedAt.AddDays(2), reminders)
                    .Where(n => n.Boundary != watch.MutedBoundary).OrderBy(n => n.Boundary).FirstOrDefault()?.Boundary };
            var pending = Reliable(now) && reminders.Enabled && (watch?.Active(now) ?? true)
                ? ExecHangarMonitor.Immediate(new ExecHangarSchedule(Document.Config!), now, reminders, watch,
                    Document.Receipts!, Document.LegacyMutedBoundary) : null;
            var next = Document with { Revision = checked(Document.Revision + 1), Reminders = reminders, PendingStart = pending, Monitoring = watch };
            ObserveGame(next); Interlocked.Increment(ref _epoch);
            // A settings edit is not a new monitoring session. Keep the clock
            // crossing when the same owner remains active, including at-time alerts.
            if ((manual && ManualActive(now)) || (game && GameActive(now) && gameId == Document.GameMonitoring?.Id)) {
                _previous = previous; _previousTick = previousTick;
            }
            if (Reliable(now) && GameActive(now)) {
                var schedule = new ExecHangarSchedule(Document.Config!);
                var prefix = $"{Document.GameMonitoring!.Id:N}:game:";
                _gamePendingStart = ExecHangarMonitor.Immediate(schedule, now, reminders with { Enabled = true }, null,
                    Document.Receipts!.Where(key => key.StartsWith(prefix, StringComparison.Ordinal))
                        .Select(key => key[prefix.Length..]).ToArray(), Document.GameMonitoring.MutedBoundary);
            }
            _deliveryState = "idle"; return Snapshot();
        } finally { _gate.Release(); }
    }
    public async Task<ExecHangarSnapshot> MonitorAsync(string action, int expectedRevision,
        int durationMinutes, bool onlyNext, Func<bool> canCommit, CancellationToken token = default)
    {
        if (action is not ("start" or "continuous" or "stop" or "extend" or "addHour" or "restore") || action == "start" && durationMinutes is < 1 or > 1440)
            throw new ArgumentException("Invalid monitoring command.");
        await _gate.WaitAsync(token);
        try {
            token.ThrowIfCancellationRequested(); _stop.Token.ThrowIfCancellationRequested();
            if (!canCommit()) throw new OperationCanceledException();
            if (expectedRevision != Document.Revision) throw new ExecHangarConflictException();
            var now = _time.GetUtcNow(); var rules = Document.Reminders!;
            ObserveGame();
            var game = GameActive(now);
            if (game && action is "extend" or "addHour") throw new InvalidOperationException("Game monitoring follows the game lifetime.");
            ExecHangarMonitoring? watch = Document.Monitoring;
            ExecHangarNotice? immediate = null;
            if (action != "stop") {
                if (!Reliable(now) || !rules.HasRules) throw new InvalidOperationException("No current reminder target.");
                var schedule = new ExecHangarSchedule(Document.Config!);
                if (action == "continuous") {
                    watch = null;
                    immediate = ExecHangarMonitor.Immediate(schedule, now, rules,
                        new(Guid.NewGuid(), now, now.AddDays(2), false));
                } else if (action == "start") {
                    var target = schedule.Notices(now, now.AddDays(2), rules).OrderBy(n => n.Boundary).FirstOrDefault()?.Boundary;
                    watch = new(Guid.NewGuid(), now, now.AddMinutes(durationMinutes), onlyNext, target);
                    immediate = ExecHangarMonitor.Immediate(schedule, now, rules, watch);
                } else if (action == "restore") {
                    var muted = game ? Document.GameMonitoring!.MutedBoundary : watch?.MutedBoundary ?? Document.LegacyMutedBoundary;
                    if (!game && watch is not null && !watch.Active(now) || muted is null || muted <= now)
                        throw new InvalidOperationException("No current suppressed event.");
                    // Restore future notices only. Existing durable receipts remain intact.
                    if (!game && watch is not null) watch = watch with { MutedBoundary = null, Target = watch.OnlyNext ? schedule.Notices(now, now.AddDays(2), rules)
                        .OrderBy(n => n.Boundary).FirstOrDefault()?.Boundary : watch.Target };
                } else if (action == "addHour") {
                    if (watch is null || !watch.Active(now) || watch.OnlyNext || watch.EndsAt.AddHours(1) - watch.StartedAt > TimeSpan.FromHours(24))
                        throw new InvalidOperationException("Monitoring cannot be extended.");
                    watch = watch with { EndsAt = watch.EndsAt.AddHours(1) };
                } else {
                    var outside = ExecHangarMonitor.Plan(schedule, now, rules with { Enabled = true }, watch, Document.Receipts!).Outside;
                    if (watch is null || outside is null || outside.Boundary <= watch.EndsAt || outside.Boundary <= now)
                        throw new InvalidOperationException("No event outside this monitoring window.");
                    watch = watch with { EndsAt = outside.Boundary, Target = watch.OnlyNext ? outside.Boundary : watch.Target };
                    watch.Validate();
                    immediate = ExecHangarMonitor.Immediate(schedule, now, rules, watch);
                }
            }
            var next = Document with { Revision = checked(Document.Revision + 1), Reminders = rules with { Enabled = action != "stop" },
                Monitoring = watch, PendingStart = immediate, LegacyMutedBoundary = action is "start" or "continuous" or "restore" ? null : Document.LegacyMutedBoundary,
                GameMonitoring = Document.GameMonitoring is {} session ? session with {
                    Paused = action == "stop" || session.Paused,
                    MutedBoundary = action == "restore" && game ? null : session.MutedBoundary } : null };
            if (game && action == "restore") next = next with { Reminders = rules };
            ObserveGame(next); Interlocked.Increment(ref _epoch);
            _previous = null; _deliveryState = "idle"; return Snapshot();
        } finally { _gate.Release(); }
    }
    public async Task<ExecHangarSnapshot> PreviewAsync(ExecHangarReminders reminders, int durationMinutes,
        bool onlyNext, CancellationToken token = default)
    {
        reminders.Validate();
        if (durationMinutes != -1 && durationMinutes is < 1 or > 1440 || durationMinutes == -1 && onlyNext)
            throw new ArgumentException("Invalid preview duration.");
        await _gate.WaitAsync(token);
        try {
            _stop.Token.ThrowIfCancellationRequested();
            var snapshot = Snapshot();
            if (!snapshot.Reliable || snapshot.Config is null || !reminders.HasRules)
                throw new InvalidOperationException("No current preview target.");
            var rules = reminders with { Enabled = true };
            var schedule = new ExecHangarSchedule(snapshot.Config);
            var target = schedule.Notices(snapshot.Now, snapshot.Now.AddDays(2), rules).OrderBy(n => n.Boundary).FirstOrDefault()?.Boundary;
            var watch = durationMinutes == -1 ? null : new ExecHangarMonitoring(Guid.NewGuid(), snapshot.Now, snapshot.Now.AddMinutes(durationMinutes), onlyNext, target);
            var plan = ExecHangarMonitor.Plan(schedule, snapshot.Now, rules, watch, []);
            var immediate = ExecHangarMonitor.Immediate(schedule, snapshot.Now, rules,
                watch ?? new(Guid.NewGuid(), snapshot.Now, snapshot.Now.AddDays(2), false));
            return snapshot with { Reminders = rules, Monitoring = watch, Plan = immediate is null ? plan : plan with { Next = immediate } };
        } finally { _gate.Release(); }
    }
    public async Task<ExecHangarSnapshot> TestAsync(Func<bool> canDeliver, CancellationToken token = default)
    {
        ExecHangarSnapshot snapshot; long epoch;
        await _gate.WaitAsync(token);
        try { _stop.Token.ThrowIfCancellationRequested(); snapshot = Snapshot(); epoch = Interlocked.Read(ref _epoch); }
        finally { _gate.Release(); }
        bool Current() => !_stop.IsCancellationRequested && epoch == Interlocked.Read(ref _epoch) && canDeliver();
        if (!Current()) throw new OperationCanceledException();
        if (!snapshot.Reliable || snapshot.Config is null) return snapshot with { DeliveryState = "paused" };
        // Use the real selected event and current calibrated phase. Testing is
        // an explicit delivery preview, never a new watch or a claimed receipt.
        var schedule = new ExecHangarSchedule(snapshot.Config);
        var phase = snapshot.Phases.First(p => p.Start <= snapshot.Now && snapshot.Now < p.End);
        var selected = snapshot.Plan is { Active: true } plan ? plan.Next ?? plan.Waiting : null;
        selected ??= schedule.Notices(snapshot.Now, snapshot.Now.AddDays(2), snapshot.Reminders)
            .OrderBy(n => n.Boundary).ThenBy(n => n.Due).FirstOrDefault();
        var opening = selected?.Opening ?? !phase.Open;
        var boundary = selected?.Boundary ?? (phase.Open ? snapshot.Windows[0].Close : snapshot.Windows[1].Open);
        var kind = opening ? "beforeOpen" : phase is { Open: true, GreenLights: 0, RedLights: 0 } && boundary == snapshot.Windows[0].Close
            ? "leave" : "beforeClose";
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token, _stop.Token);
        deadline.CancelAfter(TimeSpan.FromSeconds(1));
        var state = await _deliver(new([new(snapshot.Now, boundary, kind, opening)], Current,
            snapshot.Config, snapshot.Plan is { Active: true } active ? active.EndsAt : null, Test: true), deadline.Token);
        if (!Current()) throw new OperationCanceledException();
        return snapshot with { DeliveryState = state };
    }
    private async Task MuteAsync(long epoch, DateTimeOffset boundary, bool game)
    {
        try {
            await _gate.WaitAsync(_stop.Token);
            try {
                if (epoch != Interlocked.Read(ref _epoch)) return;
                var next = Document with { Revision = checked(Document.Revision + 1),
                    Monitoring = !game && Document.Monitoring is {} watch ? watch with { MutedBoundary = boundary } : Document.Monitoring,
                    GameMonitoring = game && Document.GameMonitoring is {} session ? session with { MutedBoundary = boundary } : Document.GameMonitoring,
                    LegacyMutedBoundary = !game && Document.Monitoring is null ? boundary : Document.LegacyMutedBoundary, PendingStart = null };
                _store.Write(next); _document = next; Interlocked.Increment(ref _epoch);
            } finally { _gate.Release(); }
        } catch (Exception e) when (e is OperationCanceledException or IOException or UnauthorizedAccessException) { }
    }
    public async Task TickAsync(CancellationToken token = default)
    {
        if (!await _gate.WaitAsync(0, token)) return;
        try {
            _stop.Token.ThrowIfCancellationRequested();
            if (Document.Reminders!.Enabled || Document.Reminders.AutoDuringGame) await RefreshAsync(false, token);
            ObserveGame();
            var now = _time.GetUtcNow(); var stamp = _time.GetTimestamp();
            var game = GameActive(now);
            var rules = game ? Document.Reminders! with { Enabled = true } : Document.Reminders!;
            var previous = _previous; var previousTick = _previousTick;
            _previous = now; _previousTick = stamp;
            if (!Reliable(now) || !rules.Enabled) { _deliveryState = rules.Enabled ? "paused" : "idle"; return; }
            if (!game && Document.Monitoring is {} watch && !watch.Active(now) &&
                !(previous is {} p && watch.Active(p) && now - p <= TimeSpan.FromSeconds(90))) return;
            var schedule = new ExecHangarSchedule(Document.Config!);
            var immediate = game ? _gamePendingStart : Document.PendingStart;
            _gamePendingStart = null;
            if (immediate is not null) {
                if (!game) { var consumed = Document with { PendingStart = null }; _store.Write(consumed); _document = consumed; }
            }
            var ordinary = previous is null || previousTick is null ||
                Math.Abs(((now - previous.Value) - _time.GetElapsedTime(previousTick.Value, stamp)).TotalSeconds) > 2
                ? [] : schedule.Due(previous.Value, now, rules);
            var notices = ordinary.Concat(immediate is not null && now >= immediate.Due && now - immediate.Due < TimeSpan.FromSeconds(30)
                    ? [immediate] : Array.Empty<ExecHangarNotice>())
                .Where(n => ExecHangarMonitor.Includes(n, game ? null : Document.Monitoring,
                        game ? Document.GameMonitoring!.MutedBoundary : Document.LegacyMutedBoundary) &&
                    !Document.Receipts!.Contains(Receipt(n, game)))
                .DistinctBy(n => n.Key).ToArray();
            // Timer crossings can include slightly different rounded due times.
            // One event crossed in one tick produces one card and one sound.
            foreach (var group in notices.GroupBy(n => n.Boundary)) {
                var batch = group.ToArray(); var epoch = Interlocked.Read(ref _epoch);
                // Claim before native output. Uncertain delivery is never replayed after a restart.
                var claimed = Document with { Receipts = Document.Receipts!.Concat(batch.Select(n => Receipt(n, game))).TakeLast(256).ToArray() };
                _store.Write(claimed); _document = claimed;
                bool Current() => !_stop.IsCancellationRequested && epoch == Interlocked.Read(ref _epoch) &&
                    (game ? GameActive(_time.GetUtcNow()) : Document.Reminders!.Enabled) && Reliable(_time.GetUtcNow()) &&
                    _time.GetUtcNow() >= now && _time.GetUtcNow() - now < TimeSpan.FromMinutes(10);
                using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token, _stop.Token);
                deadline.CancelAfter(TimeSpan.FromSeconds(1));
                var end = game ? null : Document.Monitoring is { OnlyNext: true, Target: {} target } monitor && target < monitor.EndsAt ? target : Document.Monitoring?.EndsAt;
                _deliveryState = Current() ? await _deliver(new(batch, Current, Document.Config, end,
                    () => _ = MuteAsync(epoch, batch[0].Boundary, game)), deadline.Token) : "suppressed";
            }
        } catch (OperationCanceledException) { if (!_stop.IsCancellationRequested) _deliveryState = "failed"; }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException or JsonException or ArgumentException or InvalidOperationException) {
            _deliveryState = "failed";
        } finally { _gate.Release(); }
    }
    public void Dispose() { Interlocked.Increment(ref _epoch); _stop.Cancel(); }
}

public sealed class ExecHangarDriver : IDisposable
{
    private readonly ITimer _timer;
    private readonly CancellationTokenSource _stop = new();
    public ExecHangarDriver(ExecHangarRuntime runtime, TimeProvider? time = null) =>
        _timer = (time ?? TimeProvider.System).CreateTimer(_ => _ = Tick(runtime), null,
            TimeSpan.Zero, TimeSpan.FromSeconds(1));
    private async Task Tick(ExecHangarRuntime runtime) { try { await runtime.TickAsync(_stop.Token); } catch (OperationCanceledException) { } }
    public void Dispose() { _timer.Dispose(); _stop.Cancel(); }
}
